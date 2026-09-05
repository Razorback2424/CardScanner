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
        variantID: String?,
        treatmentIDs: [String] = []
    ) -> ReferenceQuote? {
        let key = ReferenceQuote.key(
            game: game,
            printingID: printingID,
            variantID: variantID,
            treatmentIDs: treatmentIDs
        )
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
        at date: Date = .now,
        treatmentIDs: [String] = []
    ) -> ReferenceQuote {
        let record = quote(
            game: game,
            printingID: printingID,
            variantID: variantID,
            treatmentIDs: treatmentIDs
        ) ?? {
            let created = ReferenceQuote(
                key: ReferenceQuote.key(
                    game: game,
                    printingID: printingID,
                    variantID: variantID,
                    treatmentIDs: treatmentIDs
                ),
                game: game,
                printingID: printingID,
                variantID: variantID,
                magicTreatmentIDs: treatmentIDs
            )
            context.insert(created)
            return created
        }()
        if record.magicTreatmentIDsRaw.isEmpty, !treatmentIDs.isEmpty {
            record.magicTreatmentIDsRaw = MagicTreatmentKeyCodec.storedIDs(from: treatmentIDs)
        }
        record.apply(lookup, at: date)
        save()
        return record
    }

    @discardableResult
    func recordFailure(
        game: CardGame,
        printingID: String,
        variantID: String?,
        at date: Date = .now,
        treatmentIDs: [String] = []
    ) -> ReferenceQuote {
        let record = quote(
            game: game,
            printingID: printingID,
            variantID: variantID,
            treatmentIDs: treatmentIDs
        ) ?? {
            let created = ReferenceQuote(
                key: ReferenceQuote.key(
                    game: game,
                    printingID: printingID,
                    variantID: variantID,
                    treatmentIDs: treatmentIDs
                ),
                game: game,
                printingID: printingID,
                variantID: variantID,
                magicTreatmentIDs: treatmentIDs
            )
            context.insert(created)
            return created
        }()
        if record.magicTreatmentIDsRaw.isEmpty, !treatmentIDs.isEmpty {
            record.magicTreatmentIDsRaw = MagicTreatmentKeyCodec.storedIDs(from: treatmentIDs)
        }
        record.recordFailure(at: date)
        save()
        return record
    }

    /// Quote persistence is intentionally best effort, but a failed save must
    /// not leave this context dirty for the next Price Check or collection
    /// mutation. Production Price Check contexts are separate from collection
    /// ownership state as well.
    @discardableResult
    private func save() -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            return false
        }
    }
}
