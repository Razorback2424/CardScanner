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
        switch card {
        case let .magic(magic):
            return productURL(
                productID: magic.tcgplayerID.map(String.init),
                variantID: variant?.id,
                game: .magic
            ) ?? providerURL(magic.purchaseURIs?.tcgplayer?.absoluteString)
        case let .pokemon(pokemon, _):
            // TCGdex's ordinary product identity must not be used for a
            // Shadowless virtual set, whose marketplace identity is distinct.
            guard pokemonPrintRun != .shadowless else { return nil }
            let selected = pokemonPrintRun == .firstEdition ? PhysicalVariant.firstEdition : variant
            let productID: String?
            if let selected {
                let detailed = pokemon.detailedVariant(for: selected)
                productID = detailed?.isStandardEnglish == true
                    ? detailed?.thirdParty?.tcgplayer.map(String.init) : nil
            } else {
                let ids = Set((pokemon.variantsDetailed ?? []).compactMap { detailed in
                    detailed.isStandardEnglish ? detailed.thirdParty?.tcgplayer : nil
                })
                productID = ids.count == 1 ? ids.first.map(String.init) : nil
            }
            return productURL(productID: productID, variantID: selected?.id, game: .pokemon)
        }
    }

    /// A product page, with the printing preselected where the owned variant
    /// maps onto a TCGplayer printing without guessing.
    static func productURL(productID: String?, variantID: String?, game: CardGame) -> URL? {
        guard let id = productID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty,
              id.allSatisfy(\.isNumber) else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/product/\(id)"

        // Only printings with an exact, known name. An unrecognised finish
        // drops the filter rather than inventing one — the product page is
        // still the right card, just unfiltered.
        if let printing = printingName(variantID: variantID, game: game) {
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
              let host = url.host?.lowercased(),
              host == "tcgplayer.com" || host.hasSuffix(".tcgplayer.com") else { return nil }
        return url
    }
}
