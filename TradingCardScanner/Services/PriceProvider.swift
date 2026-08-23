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
    /// The provider was consulted and has nothing it can attribute to this exact
    /// physical variant.
    case unavailable(PriceSource?)
}

/// The rule that keeps the collection's totals honest.
///
/// A price belongs to `printing + physical variant`, never to a printing alone.
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
        at fetchedAt: Date = .now
    ) -> PriceLookup {
        switch card {
        case let .pokemon(pokemon, _):
            guard let tcg = pokemon.pricing?.tcgplayer else { return .unavailable(nil) }
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

    /// Every price the catalog publishes for this printing, tagged with the
    /// variant it belongs to. For display beside a resolved price, never as a
    /// pool to pick from.
    ///
    /// Restricted to the variants the catalog says the printing actually exists
    /// in, so a stray marketplace listing can never advertise a finish that was
    /// never printed.
    static func publishedPrices(for card: IdentifiedCard) -> [CardMarketPrice] {
        card.variantEvidence.catalogVariants.compactMap { variant in
            guard case let .price(price) = self.price(for: card, variant: variant) else { return nil }
            return CardMarketPrice(
                variantID: variant.id,
                label: displayLabel(for: variant),
                value: price.unitMarketPriceUSD
            )
        }
    }

    private static func displayLabel(for variant: PhysicalVariant) -> String {
        switch variant.id {
        case PhysicalVariant.holo.id: return "Holofoil"
        case PhysicalVariant.reverse.id: return "Reverse Holofoil"
        default: return variant.label
        }
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
}
