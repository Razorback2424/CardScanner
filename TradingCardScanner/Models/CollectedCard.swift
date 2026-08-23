import Foundation
import SwiftData

/// One owned physical variant of one printing.
///
/// The collection does not contain cards, it contains *entries*: a Master Ball
/// copy and a reverse holo copy of PRE 074/131 share a printing identity but are
/// not interchangeable. They have different prices, the user filters them
/// separately, and their quantities are independent, so they are separate rows.
///
/// Price is deliberately not stored here. It lives in `PriceRecord`, keyed by
/// printing plus variant, so eight owned copies are one price to refresh and a
/// price can go stale without the ownership record changing at all.
///
/// The persisted entity keeps its original name so existing local collections
/// migrate without a versioned-schema rewrite.
@Model
final class CollectedCard {
    /// One row per physical object. For a printing with more than one possible
    /// variant this is `providerID#variantID`; when no variant is known it stays
    /// the bare provider id, which is also the key Pokémon-only collections were
    /// built with, so existing rows keep incrementing rather than forking.
    @Attribute(.unique, originalName: "tcgdexID") var collectionKey: String
    var game: String = "pokemon"
    var providerID: String = ""
    var name: String
    var setName: String
    var setCode: String
    var cardNumber: String
    var rarity: String?
    /// Pokémon stores its TCGdex image base URL; Magic stores its direct
    /// Scryfall normal-image URL. game selects the appropriate representation.
    @Attribute(originalName: "imageBaseURL") var imageURL: String?
    var thumbnailURL: String?
    var quantity: Int
    var dateAdded: Date

    /// Which physical variant this row holds. `nil` means the catalog published
    /// none — recorded as unknown rather than filled in with something plausible.
    var variantID: String?
    var variantLabel: String?

    /// Provenance, stored as raw strings so a future build can add resolutions
    /// without a schema migration.
    ///
    /// Keeping *why* alongside *what* is what makes the accuracy policy hold up
    /// over time: if a set rule is later found to be incomplete, every row that
    /// leaned on that rule can be found and reassessed without disturbing the
    /// ones a person confirmed by hand.
    var variantResolutionRaw: String?
    var identityResolutionRaw: String = IdentityResolution.printedIdentifier.rawValue

    /// Position of this card's set in release order. Collectors group by set the
    /// way sets were released, not alphabetically. Compared only within a game.
    var setReleaseOrder: Int = 0

    init(
        collectionKey: String,
        game: CardGame,
        providerID: String,
        name: String,
        setName: String,
        setCode: String,
        cardNumber: String,
        rarity: String?,
        imageURL: String?,
        thumbnailURL: String?,
        variant: PhysicalVariant?,
        variantResolution: VariantResolution,
        identityResolution: IdentityResolution = .printedIdentifier,
        setReleaseOrder: Int = 0,
        quantity: Int = 1,
        dateAdded: Date = .now
    ) {
        self.collectionKey = collectionKey
        self.game = game.rawValue
        self.providerID = providerID
        self.name = name
        self.setName = setName
        self.setCode = setCode
        self.cardNumber = cardNumber
        self.rarity = rarity
        self.imageURL = imageURL
        self.thumbnailURL = thumbnailURL
        self.variantID = variant?.id
        self.variantLabel = variant?.label
        self.variantResolutionRaw = variantResolution.rawValue
        self.identityResolutionRaw = identityResolution.rawValue
        self.setReleaseOrder = setReleaseOrder
        self.quantity = quantity
        self.dateAdded = dateAdded
    }

    convenience init(card: IdentifiedCard, resolved: ResolvedVariant) {
        self.init(
            collectionKey: card.collectionKey(variant: resolved.variant),
            game: card.game,
            providerID: card.providerID,
            name: card.name,
            setName: card.setName,
            setCode: card.setCode,
            cardNumber: card.cardNumber,
            rarity: card.rarity,
            imageURL: {
                switch card {
                case let .pokemon(pokemon, _): return pokemon.image
                case .magic: return card.displayImageURL?.absoluteString
                }
            }(),
            thumbnailURL: card.thumbnailImageURL?.absoluteString,
            variant: resolved.variant,
            variantResolution: resolved.resolution,
            setReleaseOrder: card.setReleaseOrder,
            quantity: 1
        )
    }

    var cardGame: CardGame {
        CardGame(rawValue: game) ?? .pokemon
    }

    /// The `PriceRecord` this entry reads its price from. Every owned copy of the
    /// same printing and variant shares one.
    var priceKey: String {
        PriceRecord.key(game: cardGame, printingID: providerID, variantID: variantID)
    }

    var variant: PhysicalVariant? {
        guard let variantID else { return nil }
        return PhysicalVariant(id: variantID, label: variantLabel ?? variantID.capitalized)
    }

    var variantResolution: VariantResolution? {
        variantResolutionRaw.flatMap(VariantResolution.init(rawValue:))
    }

    var identityResolution: IdentityResolution? {
        IdentityResolution(rawValue: identityResolutionRaw)
    }

    var highImageURL: URL? {
        guard let imageURL else { return nil }
        if game == CardGame.pokemon.rawValue {
            return URL(string: imageURL + "/high.png")
        }
        return URL(string: imageURL)
    }

    var lowImageURL: URL? {
        if let thumbnailURL {
            return URL(string: thumbnailURL)
        }
        guard let imageURL else { return nil }
        if game == CardGame.pokemon.rawValue {
            return URL(string: imageURL + "/low.png")
        }
        return URL(string: imageURL)
    }
}
