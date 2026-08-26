import Foundation
import SwiftData

/// Persistence boundary for non-collection price knowledge.
///
/// There is deliberately no path from this service to `PriceObservationLog`,
/// `PriceCheckDay`, or `PriceRecord`.
struct QuoteCache {
    let context: ModelContext

    func quote(
        game: CardGame,
        printingID: String,
        variantID: String?
    ) -> ReferenceQuote? {
        let key = ReferenceQuote.key(game: game, printingID: printingID, variantID: variantID)
        var descriptor = FetchDescriptor<ReferenceQuote>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @discardableResult
    func store(
        _ lookup: PriceLookup,
        game: CardGame,
        printingID: String,
        variantID: String?,
        at date: Date = .now
    ) -> ReferenceQuote {
        let record = quote(game: game, printingID: printingID, variantID: variantID) ?? {
            let created = ReferenceQuote(
                key: ReferenceQuote.key(game: game, printingID: printingID, variantID: variantID),
                game: game,
                printingID: printingID,
                variantID: variantID
            )
            context.insert(created)
            return created
        }()
        record.apply(lookup, at: date)
        try? context.save()
        return record
    }

    @discardableResult
    func recordFailure(
        game: CardGame,
        printingID: String,
        variantID: String?,
        at date: Date = .now
    ) -> ReferenceQuote {
        let record = quote(game: game, printingID: printingID, variantID: variantID) ?? {
            let created = ReferenceQuote(
                key: ReferenceQuote.key(game: game, printingID: printingID, variantID: variantID),
                game: game,
                printingID: printingID,
                variantID: variantID
            )
            context.insert(created)
            return created
        }()
        record.recordFailure(at: date)
        try? context.save()
        return record
    }
}
