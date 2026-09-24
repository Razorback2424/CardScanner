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
    case priced(Double)
    case noUSDQuote
    case unresolved

    static func cachedPrice(_ value: Double?) -> Self? {
        value.map(Self.priced)
    }

    static func exactLookup(_ lookup: PriceLookup) -> Self {
        switch lookup {
        case let .price(price):
            guard price.currencyCode.caseInsensitiveCompare("USD") == .orderedSame else {
                return .noUSDQuote
            }
            return .priced(price.unitMarketPriceUSD)
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
        let prices = results.compactMap { result -> Double? in
            guard case let .priced(value) = result else { return nil }
            return value
        }
        if let highest = prices.max() { return .priced(highest) }
        if results.contains(.unresolved) { return .unresolved }
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

    // MARK: - Lookups

    static func price(
        for card: IdentifiedCard,
        variant: PhysicalVariant?,
        magicTreatments: [MagicTreatment],
        pokemonPrintRun: PokemonPrintRun? = nil,
        at fetchedAt: Date = .now
    ) -> PriceLookup {
        switch card {
        case let .pokemon(pokemon, _):
            if pokemonPrintRun == .firstEdition {
                guard let detailed = pokemon.detailedVariant(for: .firstEdition),
                      let resolved = price(from: detailed, at: fetchedAt) else {
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
            if let variant,
               let detailed = pokemon.detailedVariant(for: variant),
               let resolved = price(from: detailed, at: fetchedAt) {
                return .price(resolved)
            }

            guard let tcg = pokemon.pricing?.tcgplayer else {
                return .unavailable(pokemon.pricing == nil ? nil : .tcgplayer)
            }
            guard let listing = tcgplayerListing(for: variant),
                  let amount = marketPrice(from: tcg, listing: listing) else {
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
    static func publishedPrices(for card: IdentifiedCard) -> [CardMarketPrice] {
        card.variantEvidence.catalogVariants.map { variant in
            let availability: CardMarketPrice.Availability
            switch self.price(
                for: card,
                variant: variant,
                magicTreatments: card.magicTreatments(for: variant)
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

    private static func marketPrice(from pricing: TCGPlayerPricing, listing: String) -> Double? {
        switch listing {
        case "normal": return pricing.normal?.marketPrice
        // TCGdex has published both spellings over time; either is the same
        // listing, so accept whichever is present rather than losing the price.
        case "holofoil": return pricing.holofoil?.marketPrice ?? pricing.holo?.marketPrice
        case "reverse-holofoil": return pricing.reverseHolofoil?.marketPrice ?? pricing.reverse?.marketPrice
        default: return nil
        }
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
        if let value = pricing.normal?.marketPrice { result.append(("normal", value)) }
        if let value = pricing.holofoil?.marketPrice ?? pricing.holo?.marketPrice {
            result.append(("holofoil", value))
        }
        if let value = pricing.reverseHolofoil?.marketPrice ?? pricing.reverse?.marketPrice {
            result.append(("reverse-holofoil", value))
        }
        return result
    }

}
