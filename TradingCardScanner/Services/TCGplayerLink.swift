import Foundation

/// Builds the marketplace destination for a card with a known product identity.
///
/// One place on purpose. TCGplayer's URL and query conventions are theirs to
/// change, and when they do this is the only function that needs to move.
///
/// The promise the button makes is deliberately narrow:
///
/// > Take me to this exact TCGplayer card and printing.
///
/// Not "take me to a listing matching the condition of my copy" — the
/// collection does not record condition, and a SKU is product plus language,
/// printing *and* condition. Claiming more than that would be the same class of
/// mistake as borrowing another finish's price.
enum TCGplayerLinkBuilder {
    private static let host = "www.tcgplayer.com"

    struct Destination: Equatable {
        let url: URL
        let isExactProduct: Bool
        var printingLabel: String? = nil
        var title: String { printingLabel.map { "View \($0) on TCGplayer" } ?? "View on TCGplayer" }
        var accessibilityLabel: String { printingLabel == nil ? "View this printing on TCGplayer" : title }
    }

    /// Only show a marketplace action when the exact product is known.
    static func destination(for card: CollectedCard) -> Destination? {
        guard let exact = url(for: card), isProductPage(exact) else { return nil }
        return .init(url: exact, isExactProduct: true)
    }

    static func destination(for card: IdentifiedCard, variant: PhysicalVariant?,
                            pokemonPrintRun: PokemonPrintRun? = nil) -> Destination? {
        if let exact = url(for: card, variant: variant, pokemonPrintRun: pokemonPrintRun), isProductPage(exact) {
            return .init(url: exact, isExactProduct: true)
        }
        return nil
    }

    static func destination(for card: IdentifiedCard, summary: CatalogCardSummary) -> Destination? {
        if let selected = destination(for: card, variant: summary.masterSetVariant, pokemonPrintRun: summary.pokemonPrintRun) {
            return selected
        }
        // Name search opens the card identity. Label the exact deck link with
        // its finish so it cannot be mistaken for the original printing.
        guard summary.masterSetVariant == nil, summary.pokemonPrintRun == nil,
              let deck = PokemonBattleDeckFinishCatalog.entry(for: summary),
              var selected = destination(for: card, variant: deck.variant) else { return nil }
        selected.printingLabel = deck.variant.label
        return selected
    }

    static func destinations(for card: IdentifiedCard, summary: CatalogCardSummary) -> [Destination] {
        if let exact = destination(for: card, summary: summary) { return [exact] }
        guard summary.masterSetVariant == nil, let reviewed = PokemonDeltaReignCatalog.card(for: summary) else { return [] }
        return reviewed.printings.compactMap { printing in
            guard var exact = destination(for: card, variant: printing.variant) else { return nil }
            exact.printingLabel = printing.variant.label
            return exact
        }
    }

    /// Persist the same exact product Browse can open, including its ambiguity
    /// and physical-review guards. A product handle never comes from a search.
    static func productID(for card: IdentifiedCard, variant: PhysicalVariant?,
                          pokemonPrintRun: PokemonPrintRun? = nil) -> String? {
        guard let url = url(for: card, variant: variant, pokemonPrintRun: pokemonPrintRun),
              isProductPage(url) else { return nil }
        return url.pathComponents[2]
    }

    private static func isProductPage(_ url: URL) -> Bool {
        let parts = url.pathComponents
        return parts.count > 2 && parts[1] == "product" && validProductID(parts[2])
    }

    private static func validProductID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.allSatisfy { (48...57).contains($0) } && id.contains { $0 != "0" }
    }

    /// The destination for a card, or `nil` when the app has no marketplace
    /// identity it can stand behind.
    ///
    /// Resolution order:
    /// 1. A known TCGplayer product id, plus the printing when it maps exactly.
    /// 2. A provider-supplied URL for this exact printing.
    /// 3. Nothing.
    ///
    /// There is deliberately no name, set or collector-number search fallback.
    /// A button that occasionally opens the wrong reprint is worse than no
    /// button: it looks authoritative and is silently wrong, and the whole
    /// point of this link is letting someone check the price we showed them.
    static func url(for card: CollectedCard) -> URL? {
        if card.cardGame == .pokemon, let cardID = card.underlyingPrintingID {
            if let reviewed = PokemonReviewedMarketProduct.entry(cardID: cardID, variantID: card.variantID) {
                guard card.pokemonPrintRun == nil, reviewed.matches(name: card.name, number: card.cardNumber) else { return nil }
                return productURL(productID: String(reviewed.productID), variantID: card.variantID, game: .pokemon)
            }
            if PokemonReviewedMarketProduct.usesReviewedVariantsOnly(cardID: cardID) { return nil }
        }
        if let product = productURL(
            productID: card.tcgplayerProductID,
            variantID: card.variantID,
            game: card.cardGame
        ) {
            return product
        }
        return providerURL(card.tcgplayerURL)
    }

    /// Browse may have an exact catalog printing without an owned row. A
    /// Pokémon card with several marketplace products needs a selected finish
    /// before one of those products can be chosen safely.
    static func url(
        for card: IdentifiedCard,
        variant: PhysicalVariant?,
        pokemonPrintRun: PokemonPrintRun? = nil
    ) -> URL? {
        switch card.legacyIdentity {
        case .none:
            guard pokemonPrintRun == nil else { return nil }
            let ids = card.marketProductIDsByVariant
            let productID: String?
            if let variant {
                guard card.variantEvidence.catalogVariants.contains(where: { $0.id == variant.id }) else { return nil }
                productID = ids[variant.id]
            } else {
                let distinct = Set(ids.values)
                let supported = Set(card.variantEvidence.catalogVariants.map(\.id))
                productID = !supported.isEmpty && Set(ids.keys) == supported && distinct.count == 1
                    ? distinct.first : nil
            }
            return productURL(productID: productID, variantID: variant?.id, game: card.game)
        case let .magic(magic):
            return productURL(
                productID: magic.tcgplayerProductID(for: variant).map(String.init),
                variantID: variant?.id,
                game: .magic
            ) ?? providerURL(magic.tcgplayerPurchaseURI(for: variant)?.absoluteString)
        case let .pokemon(pokemon, _):
            if let m26 = PokemonM26Catalog.entry(cardID: pokemon.id) {
                let selected = variant ?? m26.variant
                return CardPricing.tcgplayerProductID(for: card, variant: selected, printRun: pokemonPrintRun)
                    .flatMap { productURL(productID: String($0), variantID: selected.id, game: .pokemon) }
            }
            // TCGdex's ordinary product identity must not be used for a
            // Shadowless virtual set, whose marketplace identity is distinct.
            guard pokemonPrintRun != .shadowless else { return nil }
            if variant == .jumbo || (variant.map { selected in
                pokemon.authorizedAdditionalVariants.contains { $0.variantID == selected.id }
                    || (selected == .normal && pokemon.signedNormalNeedsReview)
            } ?? false) {
                return CardPricing.tcgplayerProductID(for: card, variant: variant, printRun: pokemonPrintRun)
                    .flatMap { productURL(productID: String($0), variantID: variant?.id, game: .pokemon) }
            }
            if variant == nil, pokemon.authorizedJumbo != nil
                || pokemon.authorizedAdditionalVariants.contains(where: { !$0.addsMembership }) { return nil }
            if pokemon.set.id == "xya", let variant,
               let id = CardPricing.tcgplayerProductID(for: card, variant: variant, printRun: pokemonPrintRun) {
                return productURL(productID: String(id), variantID: variant.id, game: .pokemon)
            }
            let selected = pokemonPrintRun == .firstEdition ? PhysicalVariant.firstEdition : variant
            let productID: String?
            if let selected {
                productID = CardPricing.tcgplayerProductID(for: card, variant: selected,
                    printRun: pokemonPrintRun ?? (selected == .firstEdition ? .firstEdition : nil)).map(String.init)
            } else {
                let variants = pokemon.catalogVariants
                let ids = variants.compactMap {
                    CardPricing.tcgplayerProductID(for: card, variant: $0, printRun: pokemonPrintRun)
                }
                productID = !variants.isEmpty && ids.count == variants.count && Set(ids).count == 1
                    ? ids.first.map(String.init) : nil
            }
            return productURL(productID: productID, variantID: selected?.id, game: .pokemon)
        }
    }

    /// A product page, with the printing preselected where the owned variant
    /// maps onto a TCGplayer printing without guessing.
    static func productURL(productID: String?, variantID: String?, game: CardGame) -> URL? {
        guard let id = productID?.trimmingCharacters(in: .whitespacesAndNewlines),
              validProductID(id) else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/product/\(id)"

        // Only printings with an exact, known name. An unrecognised finish
        // drops the filter rather than inventing one — the product page is
        // still the right card, just unfiltered.
        let reviewedPrinting = game == .pokemon ? Int(id).flatMap {
            PokemonReviewedMarketProduct.printing(productID: $0, variantID: variantID)
        } : nil
        if let printing = reviewedPrinting ?? printingName(variantID: variantID, game: game) {
            components.queryItems = [URLQueryItem(name: "Printing", value: printing)]
        }
        return components.url
    }

    /// TCGplayer's own printing vocabulary, for the finishes this app models.
    ///
    /// Mirrors `CardPricing.tcgplayerListing(for:)`, which maps the same
    /// variants onto the pricing object's keys. Anything absent has no mapping
    /// on purpose.
    static func printingName(variantID: String?, game: CardGame) -> String? {
        guard let variantID else { return nil }
        switch game {
        case .pokemon:
            switch variantID {
            case PhysicalVariant.normal.id: return "Normal"
            case PhysicalVariant.holo.id: return "Holofoil"
            case PhysicalVariant.reverse.id: return "Reverse Holofoil"
            default: return nil
            }
        case .magic:
            switch variantID {
            case PhysicalVariant.nonfoil.id: return "Normal"
            case PhysicalVariant.foil.id: return "Foil"
            default: return nil
            }
        default: return nil
        }
    }

    /// A provider-supplied URL, accepted only when it is actually a TCGplayer
    /// destination. A stored value that has drifted to something else is not
    /// something to open on the user's behalf.
    static func providerURL(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased(),
              host == "tcgplayer.com" || host == "www.tcgplayer.com",
              isProductPage(url) else { return nil }
        return url
    }
}
