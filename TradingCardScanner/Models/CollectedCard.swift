import Foundation
import SwiftData

@Model
final class CollectedCard {
    @Attribute(.unique) var tcgdexID: String
    var name: String
    var setName: String
    var setCode: String
    var cardNumber: String
    var rarity: String?
    var imageBaseURL: String?
    var quantity: Int
    var dateAdded: Date

    init(
        tcgdexID: String,
        name: String,
        setName: String,
        setCode: String,
        cardNumber: String,
        rarity: String?,
        imageBaseURL: String?,
        quantity: Int = 1,
        dateAdded: Date = .now
    ) {
        self.tcgdexID = tcgdexID
        self.name = name
        self.setName = setName
        self.setCode = setCode
        self.cardNumber = cardNumber
        self.rarity = rarity
        self.imageBaseURL = imageBaseURL
        self.quantity = quantity
        self.dateAdded = dateAdded
    }

    convenience init(card: TCGdexCard, setCode: String) {
        self.init(
            tcgdexID: card.id,
            name: card.name,
            setName: card.set.name,
            setCode: setCode,
            cardNumber: card.localId,
            rarity: card.rarity,
            imageBaseURL: card.image,
            quantity: 1
        )
    }

    var highImageURL: URL? {
        guard let imageBaseURL else { return nil }
        return URL(string: imageBaseURL + "/high.png")
    }

    var lowImageURL: URL? {
        guard let imageBaseURL else { return nil }
        return URL(string: imageBaseURL + "/low.png")
    }
}
