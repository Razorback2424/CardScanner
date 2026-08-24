import Foundation
import SwiftData

/// Reads and writes `PriceRecord`s.
///
/// Prices are keyed by printing plus variant, never by collection row, so eight
/// owned copies of one printing are one record to fetch, one to refresh and one
/// to keep fresh.
@MainActor
struct PriceStore {
    let context: ModelContext

    func record(forKey key: String) -> PriceRecord? {
        var descriptor = FetchDescriptor<PriceRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func allRecords() -> [PriceRecord] {
        (try? context.fetch(FetchDescriptor<PriceRecord>())) ?? []
    }

    func importedCardsByProviderID() -> [String: [CollectedCard]] {
        let cards = (try? context.fetch(FetchDescriptor<CollectedCard>())) ?? []
        return Dictionary(grouping: cards.filter { $0.providerID.hasPrefix("csv:") }, by: \.providerID)
    }

    /// Records what a provider said about one variant, creating the record if
    /// this is the first time the app has asked.
    func store(
        _ lookup: PriceLookup,
        game: CardGame,
        printingID: String,
        variantID: String?,
        at date: Date = .now
    ) {
        let key = PriceRecord.key(game: game, printingID: printingID, variantID: variantID)
        let record = self.record(forKey: key) ?? {
            let created = PriceRecord(key: key, game: game, printingID: printingID, variantID: variantID)
            context.insert(created)
            return created
        }()

        switch lookup {
        case let .price(price):
            record.apply(price)
        case let .unavailable(source):
            record.applyUnavailable(source: source, at: date)
        }
    }

    func storeImported(
        amount: Double,
        sourceUpdatedAt: Date?,
        game: CardGame,
        printingID: String,
        variantID: String?
    ) {
        let key = PriceRecord.key(game: game, printingID: printingID, variantID: variantID)
        let record = self.record(forKey: key) ?? {
            let created = PriceRecord(key: key, game: game, printingID: printingID, variantID: variantID)
            context.insert(created)
            return created
        }()
        guard record.unitMarketPriceUSD == nil else { return }
        record.applyImported(amount: amount, sourceUpdatedAt: sourceUpdatedAt)
    }

    /// A refresh attempt that never reached an answer. The previous price stays
    /// exactly where it was — an offline phone should show yesterday's price
    /// labelled as yesterday's, not nothing at all.
    func recordFailure(
        game: CardGame,
        printingID: String,
        variantID: String?,
        at date: Date = .now
    ) {
        let key = PriceRecord.key(game: game, printingID: printingID, variantID: variantID)
        let record = self.record(forKey: key) ?? {
            let created = PriceRecord(key: key, game: game, printingID: printingID, variantID: variantID)
            context.insert(created)
            return created
        }()
        record.recordFailure(at: date)
    }

    func save() {
        try? context.save()
    }
}
