import Foundation

/// A price this app is willing to claim, together with everything needed to say
/// how much it should be trusted.
struct NormalizedPrice: Equatable, Sendable {
    let unitMarketPriceUSD: Double
    let currencyCode: String
    let source: PriceSource
    /// The provider-side listing the number was read from.
    let sourceVariantID: String
    /// When the provider says its market data is current through. `nil` for
    /// providers that publish no such timestamp, which is itself a fact the UI
    /// has to respect rather than paper over.
    let sourceUpdatedAt: Date?
    let fetchedAt: Date
    /// Catalog-owned mapping evidence; nil for providers without this contract.
    var catalogIdentity: String? = nil

    var effectiveAsOf: Date { sourceUpdatedAt ?? fetchedAt }

    func isStale(now: Date = .now) -> Bool {
        now.timeIntervalSince(effectiveAsOf) > PriceDisplay.staleAfter
    }

    var isUsableUSD: Bool {
        PortfolioPriceEligibility.eligibleUnitPrice(
            amount: unitMarketPriceUSD, currencyCode: currencyCode
        ) != nil
    }
}

enum PriceLookup: Equatable, Sendable {
    case price(NormalizedPrice)
    /// A non-nil source means that provider was consulted and had no quote for
    /// this exact physical variant. `nil` means no pricing source was queried.
    case unavailable(PriceSource?)

    /// Whether this lookup contains an observation worth persisting.
    var hasObservation: Bool {
        switch self {
        case .price:
            return true
        case let .unavailable(source):
            return source != nil
        }
    }
}

/// The result a set sorter can safely publish for an exact printing.
/// Missing source evidence stays unresolved so the UI can offer a retry instead
/// of claiming that no USD quote exists.
enum CatalogSortPriceResolution: Equatable, Sendable {
    case priced(Double, asOf: Date)
    case noUSDQuote
    case unresolved
    case mappingMissing

    static func cachedPrice(_ value: Double?, asOf: Date) -> Self? {
        guard let value, PortfolioPriceEligibility.eligibleUnitPrice(amount: value, currencyCode: "USD") != nil else { return nil }
        return .priced(value, asOf: asOf)
    }

    static func exactLookup(_ lookup: PriceLookup) -> Self {
        switch lookup {
        case let .price(price):
            guard price.isUsableUSD else {
                return .noUSDQuote
            }
            return .priced(price.unitMarketPriceUSD, asOf: price.fetchedAt)
        case let .unavailable(source):
            return source == nil ? .unresolved : .noUSDQuote
        }
    }

    /// A summary without a selected finish sorts by its highest available USD
    /// finish. If no finish has a price, every finish must have been checked
    /// before the summary can be classified as unpriced.
    static func aggregate(_ lookups: [PriceLookup]) -> Self {
        guard !lookups.isEmpty else { return .unresolved }
        let results = lookups.map(exactLookup)
        let prices = results.compactMap { result -> (Double, Date)? in
            guard case let .priced(value, date) = result else { return nil }
            return (value, date)
        }
        if let highest = prices.max(by: { $0.0 < $1.0 }) { return .priced(highest.0, asOf: highest.1) }
        if results.contains(.unresolved) { return .unresolved }
        if results.contains(.mappingMissing) { return .mappingMissing }
        return .noUSDQuote
    }
}

/// The rule that keeps the collection's totals honest.
///
/// A price belongs to `printing + physical variant`, never to a printing alone.
/// Magic treatments remain part of the exact printing identity when the source
/// provides that printing's vendor handle or published price fields.
/// If the provider exposes no listing for the variant the user actually owns —
/// a Master Ball parallel, say, where TCGdex's current pricing object only
/// carries normal, holofoil and reverse-holofoil — the answer is "unavailable".
/// Borrowing a different finish's number would make the collection look complete
/// while quietly contaminating it, which is the pricing equivalent of the
/// scanner guessing to appear fast.
enum CardPricing {
    // MARK: - Variant to marketplace listing

    /// TCGdex's current TCGplayer pricing object exposes these listings and no
    /// others. Anything absent from this table has no price mapping, on purpose.
    static func tcgplayerListing(for variant: PhysicalVariant?) -> String? {
        switch variant?.id {
        case PhysicalVariant.normal.id: return "normal"
        case PhysicalVariant.holo.id: return "holofoil"
        case PhysicalVariant.reverse.id: return "reverse-holofoil"
        default: return nil
        }
    }

    /// Scryfall's price keys map one-to-one onto its finish vocabulary, which is
    /// the same vocabulary `PhysicalVariant` uses for Magic.
    static func scryfallListing(for variant: PhysicalVariant?) -> String? {
        switch variant?.id {
        case PhysicalVariant.nonfoil.id: return "usd"
        case PhysicalVariant.foil.id: return "usd_foil"
        case PhysicalVariant.etched.id: return "usd_etched"
        default: return nil
        }
    }

    /// Exact provider product handles can recover a USD quote without a name
    /// search. Unreviewed edition handles cannot be borrowed from Unlimited.
    static func tcgplayerProductID(
        for card: IdentifiedCard, variant: PhysicalVariant?, printRun: PokemonPrintRun?
    ) -> Int? {
        if case let .magic(magic) = card.legacyIdentity {
            guard printRun == nil else { return nil }
            return magic.tcgplayerProductID(for: variant)
        }
        guard case let .pokemon(pokemon, _) = card.legacyIdentity, let variant,
              printRun != .shadowless else { return nil }
        guard !signedPriceIsBlocked(on: pokemon, variant: variant) else { return nil }
        if let deck = PokemonBattleDeckFinishCatalog.entry(cardID: pokemon.id, variantID: variant.id) {
            return printRun == nil && PokemonBattleDeckFinishCatalog.entry(for: pokemon) != nil ? deck.productID : nil
        }
        if variant == .jumbo || hasSignedProduct(on: pokemon, variant: variant) {
            guard printRun == nil || printRun == .unlimited else { return nil }
            return reviewedAdditionalProductID(on: pokemon, variant: variant)
        }
        guard !PokemonVariantRules.requiresPhysicalReview(cardID: pokemon.id, variant: variant) else { return nil }
        if let printing = PokemonReviewedEnergyCatalog.unnumberedPrinting(for: pokemon) {
            return printRun == nil ? printing.finishProducts[variant.id] : nil
        }
        if let printing = PokemonReviewedArtworkCatalog.printing(for: pokemon) {
            return printRun == nil && printing.marketFinishes.contains(variant.id) ? printing.artworkProductID : nil
        }
        if pokemon.set.id == "xya", ReviewedPokemonProductIdentity.catalogIDs.contains(pokemon.id) {
            return ReviewedPokemonProductIdentity.productID(for: pokemon, variant: variant, printRun: printRun)
        }
        let detailed = exactDetailedVariants(on: pokemon, variant: variant, printRun: printRun)
        let products = detailed.reduce(into: Set<Int>()) { $0.formUnion(productIDs(in: $1)) }
        if variant == PokemonReviewedParallelCatalog.variant,
           let reviewed = PokemonReviewedParallelCatalog.entry(cardID: pokemon.id) {
            guard printRun == nil || printRun == .unlimited, reviewed.matches(pokemon) else { return nil }
            // A later conflicting provider handle is new evidence to review,
            // not permission to choose between products. Missing handles are
            // exactly the gap this reviewed binding fills.
            guard products.isEmpty || (products == [reviewed.productID]
                && detailed.allSatisfy({ productIDs(in: $0) == products })) else { return nil }
            return reviewed.productID
        }
        if variant == .holo, let reviewed = PokemonTCGCSVMapping.byCardID[pokemon.id] {
            guard printRun == nil || printRun == .unlimited, reviewed.matches(pokemon) else { return nil }
            // Reuse the existing reviewed identity when the daily feed is
            // unconfigured/unavailable. The paid fallback can ask for this
            // exact product instead of searching a differently grouped set.
            guard products.isEmpty || (products == [reviewed.productID]
                && detailed.allSatisfy({ productIDs(in: $0) == products })) else { return nil }
            return reviewed.productID
        }
        if products.count == 1, detailed.allSatisfy({ productIDs(in: $0) == products }) {
            return products.first
        }
        guard detailed.isEmpty, printRun != .firstEdition,
              let listing = tcgplayerListing(for: variant) else { return nil }
        let pricing = pokemon.pricing?.tcgplayer
        let point: TCGPlayerPricePoint?
        switch listing {
        case "normal": point = pricing?.normal
        case "holofoil": point = pricing?.holofoil ?? pricing?.holo
        case "reverse-holofoil": point = pricing?.reverseHolofoil ?? pricing?.reverse
        default: point = nil
        }
        return point?.productID.flatMap { $0 > 0 ? $0 : nil }
    }

    /// Shared by quote and product extraction. Provider variantId is scoped to
    /// the card and is never a product binding.
    private static func exactDetailedVariants(
        on card: TCGdexCard, variant: PhysicalVariant, printRun: PokemonPrintRun?
    ) -> [TCGdexDetailedVariant] {
        if variant == .jumbo || hasSignedProduct(on: card, variant: variant) {
            guard printRun == nil || printRun == .unlimited,
                  let productID = reviewedAdditionalProductID(on: card, variant: variant) else { return [] }
            return card.additionalDetailedVariants(for: variant.id).filter {
                // A reviewed ID correction authorizes a direct lookup of the
                // right product, never the wrong product's embedded quote.
                productIDs(in: $0).isEmpty || productIDs(in: $0) == [productID]
            }
        }
        return (card.variantsDetailed ?? []).filter {
            guard $0.isStandardEnglish else { return false }
            if let object = PokemonReviewedPhysicalObjects.variant(for: $0, on: card) {
                return variant == object && printRun != .firstEdition && printRun != .shadowless
            }
            if printRun == .firstEdition {
                return $0.isFirstEdition && $0.genericStamps.isEmpty
                    && (variant == .firstEdition || $0.physicalVariant == variant)
            }
            guard printRun != .shadowless, !$0.isFirstEdition,
                  $0.subtype == nil || $0.subtype?.lowercased() == "unlimited" else { return false }
            if PokemonCatalogStampVariant.decode(variant.id) != nil {
                return $0.stampedPhysicalVariant?.id == variant.id
            }
            let reviewedAnniversary = $0.genericStamps.map { $0.lowercased() } == ["30th-anniversary"]
                && PokemonTCGCSVMapping.byCardID[card.id]?.setID == card.set.id
            // A modern catalog may represent its sole stamped object as Holo.
            // Only that existing representation, with exact quote/product proof,
            // can be recovered. Explicit edition requests retain their strict gate.
            let soleCatalogObject = printRun == nil
                && variant == .holo
                && PokemonMasterSetDefinition.printRuns(forSetProviderID: card.set.id).isEmpty
                && card.variantsDetailed?.count == 1
                && card.catalogVariants == [variant]
                && $0.subtype == nil
                && productIDs(in: $0).count == 1
                && $0.pricing?.tcgplayer.flatMap { marketPrice(from: $0, listing: "holofoil") } != nil
            return $0.physicalVariant == variant && ($0.genericStamps.isEmpty || reviewedAnniversary || soleCatalogObject)
        }
    }

    private static func unambiguousPrice(
        from details: [TCGdexDetailedVariant], at date: Date
    ) -> NormalizedPrice? {
        let products = details.reduce(into: Set<Int>()) { $0.formUnion(productIDs(in: $1)) }
        guard products.count <= 1 else { return nil }
        let quotes = details.compactMap { price(from: $0, at: date) }
        guard quotes.count == details.count, let quote = quotes.first,
              quotes.allSatisfy({ $0.unitMarketPriceUSD == quote.unitMarketPriceUSD
                  && $0.currencyCode == quote.currencyCode }) else { return nil }
        // Equivalent duplicate quotes have deterministic provenance. Distinct
        // products, amounts or missing quotes above remain unresolved.
        return quotes.sorted { $0.sourceVariantID < $1.sourceVariantID }.first
    }

    private static func productIDs(in detail: TCGdexDetailedVariant) -> Set<Int> {
        let pricing = detail.pricing?.tcgplayer
        return Set([detail.thirdParty?.tcgplayer, pricing?.normal?.productID,
            pricing?.holofoil?.productID, pricing?.holo?.productID,
            pricing?.reverseHolofoil?.productID, pricing?.reverse?.productID]
            .compactMap { $0 }.filter { $0 > 0 })
    }

    private static func hasSignedProduct(on card: TCGdexCard, variant: PhysicalVariant) -> Bool {
        card.authorizedAdditionalVariants.contains { $0.variantID == variant.id && $0.tcgplayerProductID != nil }
    }

    private static func reviewedAdditionalProductID(on card: TCGdexCard, variant: PhysicalVariant) -> Int? {
        guard let reviewed = card.authorizedAdditionalVariants.first(where: { $0.variantID == variant.id }),
              let productID = reviewed.tcgplayerProductID else { return nil }
        let objects = (card.variantsDetailed ?? []).filter {
            if variant == .jumbo { return $0.size?.lowercased() == "jumbo" }
            if ["normal", "holo", "reverse"].contains(variant.id) {
                return $0.size?.lowercased() != "jumbo" && $0.type == variant.id
                    && ($0.foil ?? "").isEmpty && $0.genericStamps.isEmpty
            }
            return $0.size?.lowercased() != "jumbo" && $0.foil?.lowercased() == variant.id
        }
        // A missing row may use the signed binding. A contradictory or newly
        // ambiguous row needs review; it cannot silently replace that binding.
        let allowed = Set([productID] + (reviewed.replacesProviderProductIDs ?? []))
        guard objects.isEmpty || (objects.count == 1 && card.additionalDetailedVariants(for: variant.id).count == 1
            && productIDs(in: objects[0]).count <= 1 && productIDs(in: objects[0]).isSubset(of: allowed)) else { return nil }
        let standardProducts = (card.variantsDetailed ?? []).filter {
            $0.isStandardEnglish && $0.physicalVariant?.id != variant.id
        }
            .reduce(into: Set<Int>()) { $0.formUnion(productIDs(in: $1)) }
        guard !standardProducts.contains(productID) else { return nil }
        return productID
    }

    private static func signedPriceIsBlocked(on card: TCGdexCard, variant: PhysicalVariant?) -> Bool {
        if variant == .normal && card.signedNormalNeedsReview { return true }
        return card.authorizedAdditionalVariants.contains { correction in
            guard !correction.addsMembership, variant == nil || correction.variantID == variant?.id else { return false }
            let excluded = Set(correction.excludedTCGplayerProductIDs ?? [])
            return (card.variantsDetailed ?? []).contains { detail in
                correction.matchesProviderDetail(type: detail.type, size: detail.size, foil: detail.foil,
                    stamp: detail.stamp, subtype: detail.subtype, languages: detail.languages)
                    && !productIDs(in: detail).isDisjoint(with: excluded)
            }
        }
    }

    /// A missing detailed quote may use the flat listing only when both its
    /// product and its finish agree. Product equality alone does not prove foil.
    private static func verifiedFlatPrice(
        for details: [TCGdexDetailedVariant], on card: TCGdexCard, at date: Date
    ) -> NormalizedPrice? {
        guard details.count == 1, let detail = details.first,
              productIDs(in: detail).count == 1, let product = productIDs(in: detail).first,
              let listing = detail.preferredListing, let pricing = card.pricing?.tcgplayer else { return nil }
        let point: TCGPlayerPricePoint?
        switch listing {
        case "normal": point = pricing.normal
        case "holofoil": point = pricing.holofoil ?? pricing.holo
        case "reverse-holofoil": point = pricing.reverseHolofoil ?? pricing.reverse
        default: point = nil
        }
        guard point?.productID == product, let amount = marketPrice(from: pricing, listing: listing) else { return nil }
        return .init(unitMarketPriceUSD: amount, currencyCode: "USD", source: .tcgplayer,
            sourceVariantID: listing, sourceUpdatedAt: pricing.updatedAt, fetchedAt: date)
    }

    // MARK: - Lookups

    static func price(
        for card: IdentifiedCard,
        variant: PhysicalVariant?,
        magicTreatments: [MagicTreatment],
        pokemonPrintRun: PokemonPrintRun? = nil,
        at fetchedAt: Date = .now
    ) -> PriceLookup {
        if case let .pokemon(pokemon, _) = card.legacyIdentity,
           signedPriceIsBlocked(on: pokemon, variant: variant) { return .unavailable(.tcgplayer) }
        let catalog = catalogPrice(
            for: card, variant: variant, magicTreatments: magicTreatments,
            pokemonPrintRun: pokemonPrintRun, at: fetchedAt
        )
        if case let .price(price) = catalog, price.isUsableUSD { return catalog }
        if case let .pokemon(pokemon, _) = card.legacyIdentity,
           let supplemental = pokemon.supplementalTCGCSV?.quote(
               cardID: pokemon.id, variant: variant, printRun: pokemonPrintRun
           ) { return supplemental }
        if case let .price(price) = catalog, !price.isUsableUSD { return .unavailable(price.source) }
        return catalog
    }

    private static func catalogPrice(
        for card: IdentifiedCard,
        variant: PhysicalVariant?,
        magicTreatments: [MagicTreatment],
        pokemonPrintRun: PokemonPrintRun? = nil,
        at fetchedAt: Date = .now
    ) -> PriceLookup {
        switch card.legacyIdentity {
        case .none:
            return .unavailable(nil)
        case let .pokemon(pokemon, _):
            if PokemonBattleDeckFinishCatalog.entry(cardID: pokemon.id, variantID: variant?.id) != nil {
                // The reviewed listing is served by the exact-product feed.
                // Expansion prices describe the ordinary printing.
                return .unavailable(nil)
            }
            let artworkPrinting = PokemonReviewedArtworkCatalog.printing(for: pokemon)
            let energyPrinting = PokemonReviewedEnergyCatalog.unnumberedPrinting(for: pokemon)
            let exactProductID: Int?
            if artworkPrinting != nil || energyPrinting != nil {
                guard pokemonPrintRun == nil, let variant,
                      let product = energyPrinting?.finishProducts[variant.id] ?? artworkPrinting.flatMap({
                          $0.marketFinishes.contains(variant.id) ? $0.artworkProductID : nil
                      }) else {
                    return .unavailable(nil)
                }
                exactProductID = product
            } else {
                exactProductID = nil
            }
            if let variant, variant == .jumbo || hasSignedProduct(on: pokemon, variant: variant) {
                guard pokemonPrintRun == nil || pokemonPrintRun == .unlimited,
                      reviewedAdditionalProductID(on: pokemon, variant: variant) != nil,
                      let quote = unambiguousPrice(from: exactDetailedVariants(on: pokemon,
                        variant: variant, printRun: pokemonPrintRun), at: fetchedAt) else {
                    return .unavailable(.tcgplayer)
                }
                return .price(quote)
            }
            if let variant, PokemonVariantRules.requiresPhysicalReview(cardID: pokemon.id, variant: variant) {
                return .unavailable(.tcgplayer)
            }
            if pokemonPrintRun == .firstEdition {
                guard let variant,
                      let resolved = unambiguousPrice(from: exactDetailedVariants(
                        on: pokemon, variant: variant, printRun: pokemonPrintRun), at: fetchedAt) else {
                    return .unavailable(hasProviderPricingEvidence(on: pokemon) ? .tcgplayer : nil)
                }
                return .price(resolved)
            }
            if pokemonPrintRun == .shadowless {
                // TCGdex's flat normal/holo listings represent Unlimited. It
                // exposes no verified Shadowless listing key, so borrowing that
                // number would erase the very split Browse now preserves.
                return .unavailable(hasProviderPricingEvidence(on: pokemon) ? .tcgplayer : nil)
            }
            // Per-object pricing first. It is the only representation that can
            // tell a Poké Ball copy from a Master Ball one, so when TCGdex
            // publishes it, it is strictly better evidence than the flat object.
            let detailed = exactProductID == nil ? variant.map {
                exactDetailedVariants(on: pokemon, variant: $0, printRun: pokemonPrintRun)
            } ?? [] : []
            if !detailed.isEmpty {
                guard let resolved = unambiguousPrice(from: detailed, at: fetchedAt)
                    ?? verifiedFlatPrice(for: detailed, on: pokemon, at: fetchedAt) else {
                    return .unavailable(.tcgplayer)
                }
                return .price(resolved)
            }

            guard let tcg = pokemon.pricing?.tcgplayer else {
                return .unavailable(pokemon.pricing == nil ? nil : .tcgplayer)
            }
            guard let listing = tcgplayerListing(for: variant),
                  let amount = marketPrice(from: tcg, listing: listing, requiredProductID: exactProductID) else {
                return .unavailable(.tcgplayer)
            }
            return .price(
                NormalizedPrice(
                    unitMarketPriceUSD: amount,
                    currencyCode: "USD",
                    source: .tcgplayer,
                    sourceVariantID: listing,
                    sourceUpdatedAt: tcg.updatedAt,
                    fetchedAt: fetchedAt
                )
            )

        case let .magic(magic):
            // Scryfall's price fields live on the exact printing object. Its
            // `tcgplayer_id` and `usd_foil` therefore already describe a Surge
            // Foil, Neon Ink, or future treated printing when that printing is
            // the card being priced. Treatment remains a separate app identity
            // axis, but it is not a reason to discard exact provider evidence.
            guard let prices = magic.prices else { return .unavailable(nil) }
            guard let listing = scryfallListing(for: variant),
                  let amount = prices.value(forKey: listing) else {
                return .unavailable(.scryfall)
            }
            return .price(
                NormalizedPrice(
                    unitMarketPriceUSD: amount,
                    currencyCode: "USD",
                    source: .scryfall,
                    sourceVariantID: listing,
                    // Scryfall stamps no "current through" time on prices, so the
                    // app may only ever report when it checked.
                    sourceUpdatedAt: nil,
                    fetchedAt: fetchedAt
                )
            )
        }
    }

    /// Every USD price the catalog publishes for this printing, tagged with the
    /// variant it belongs to, plus a stated row for every finish it does not
    /// price. For display beside a resolved price, never as a pool to pick from.
    ///
    /// Restricted to the variants the catalog says the printing actually exists
    /// in, so a stray marketplace listing can never advertise a finish that was
    /// never printed. A finish with no dollar figure is kept and marked rather
    /// than dropped: the whole point of this panel is telling the user what a
    /// printing costs, and "we do not know yet" is an answer they can act on
    /// while a missing row just looks like the finish does not exist.
    static func publishedPrices(
        for card: IdentifiedCard,
        pokemonPrintRun: PokemonPrintRun? = nil,
        at fetchedAt: Date = .now
    ) -> [CardMarketPrice] {
        let variants: [PhysicalVariant]
        if pokemonPrintRun == .firstEdition {
            // The provider's explicit edition listing is one quote, not a
            // verified price for every Normal/Holo finish in that edition.
            variants = [.firstEdition]
        } else if pokemonPrintRun != nil {
            variants = card.variantEvidence.excludingFirstEditionPseudoFinish().catalogVariants
        } else {
            variants = card.variantEvidence.catalogVariants
        }
        return variants.map { variant in
            let availability: CardMarketPrice.Availability
            switch self.price(
                for: card,
                variant: variant,
                magicTreatments: card.magicTreatments(for: variant),
                pokemonPrintRun: pokemonPrintRun,
                at: fetchedAt
            ) {
            case let .price(price):
                availability = .published(price.unitMarketPriceUSD)
            case let .unavailable(source):
                availability = .noUSDQuote(source)
                PriceCoverageGapLog.shared.record(
                    game: card.game,
                    providerID: card.providerID,
                    setCode: card.setCode,
                    cardNumber: card.cardNumber,
                    variantID: variant.id,
                    consultedSource: source
                )
            }
            return CardMarketPrice(
                variantID: variant.id,
                label: displayLabel(for: variant),
                availability: availability
            )
        }
    }

    /// A provider-neutral browse sort key. Only USD observations are comparable;
    /// Cardmarket-only euro values remain unknown instead of being ranked as if
    /// they were dollars. The highest published finish is used because an
    /// unowned catalog printing has no user-selected physical variant yet.
    static func highestPublishedUSDPrice(for card: IdentifiedCard) -> Double? {
        card.variantEvidence.catalogVariants.compactMap { variant -> Double? in
            guard case let .price(price) = self.price(
                for: card,
                variant: variant,
                magicTreatments: card.magicTreatments(for: variant)
            ),
                  price.currencyCode == "USD" else { return nil }
            return price.unitMarketPriceUSD
        }
        .max()
    }

    private static func displayLabel(for variant: PhysicalVariant) -> String {
        switch variant.id {
        case PhysicalVariant.holo.id: return "Holofoil"
        case PhysicalVariant.reverse.id: return "Reverse Holofoil"
        default: return variant.label
        }
    }

    /// A catalog identity can come from an offline checklist or resolved-card
    /// cache, neither of which proves that a pricing provider was consulted.
    /// Only mark an unsupported print run as checked when the card payload
    /// actually contains provider pricing data.
    private static func hasProviderPricingEvidence(on card: TCGdexCard) -> Bool {
        card.pricing != nil || card.variantsDetailed?.contains { $0.pricing != nil } == true
    }

    private static func marketPrice(from pricing: TCGPlayerPricing, listing: String, requiredProductID: Int? = nil) -> Double? {
        guard pricing.unit == nil || pricing.unit?.caseInsensitiveCompare("USD") == .orderedSame else { return nil }
        func eligibleAmount(for point: TCGPlayerPricePoint?) -> Double? {
            guard let point, requiredProductID == nil || requiredProductID == point.productID else { return nil }
            return point.marketPrice
        }
        let amount: Double?
        switch listing {
        case "normal": amount = eligibleAmount(for: pricing.normal)
        // TCGdex has published both spellings over time; either is the same
        // listing, so accept whichever is present rather than losing the price.
        case "holofoil": amount = eligibleAmount(for: pricing.holofoil) ?? eligibleAmount(for: pricing.holo)
        case "reverse-holofoil": amount = eligibleAmount(for: pricing.reverseHolofoil) ?? eligibleAmount(for: pricing.reverse)
        default: amount = nil
        }
        guard let amount, amount >= 0, Money(rounding: amount) != nil else { return nil }
        return amount
    }

    // MARK: - Per-object pricing

    /// Read a price out of one `variants_detailed` entry.
    ///
    /// The listing key inside such an entry is *not* reliably the one its `type`
    /// implies: TCGdex files parallel patterns under `type: "reverse"` but often
    /// prices them under `holofoil`. That is safe to accommodate here in a way it
    /// would never be in the flat object, because this entry is already scoped to
    /// a single physical object with its own marketplace product id — so when it
    /// carries exactly one priced listing, that listing is unambiguously this
    /// object's price and cannot be another finish's. Where the entry carries
    /// several, the one matching `type` still wins.
    private static func price(
        from detailed: TCGdexDetailedVariant,
        at fetchedAt: Date
    ) -> NormalizedPrice? {
        if let tcg = detailed.pricing?.tcgplayer {
            let candidates = pricedListings(in: tcg)
            var chosen: (listing: String, amount: Double)?
            if let preferred = detailed.preferredListing,
               let amount = marketPrice(from: tcg, listing: preferred) {
                chosen = (preferred, amount)
            } else if candidates.count == 1 {
                chosen = candidates[0]
            }
            if let chosen {
                return NormalizedPrice(
                    unitMarketPriceUSD: chosen.amount,
                    currencyCode: "USD",
                    source: .tcgplayer,
                    sourceVariantID: detailed.variantId.map { "\(chosen.listing)#\($0)" }
                        ?? chosen.listing,
                    sourceUpdatedAt: tcg.updatedAt,
                    fetchedAt: fetchedAt
                )
            }
        }
        // Cardmarket is deliberately not consulted here. Its figure is a euro
        // price from a different marketplace, and this app has no exchange-rate
        // policy that would let it become a dollar amount. A euro number that
        // cannot be used is not a fallback — it is a wrong price wearing the
        // right shape, so the answer is that this object has no USD quote yet.
        return nil
    }

    /// Every listing in a TCGplayer pricing object that actually carries a
    /// number, paired with its key.
    private static func pricedListings(in pricing: TCGPlayerPricing) -> [(listing: String, amount: Double)] {
        var result: [(listing: String, amount: Double)] = []
        for listing in ["normal", "holofoil", "reverse-holofoil"] {
            if let value = marketPrice(from: pricing, listing: listing) {
                result.append((listing, value))
            }
        }
        return result
    }

}
