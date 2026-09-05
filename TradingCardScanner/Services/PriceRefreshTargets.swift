import Foundation
import SwiftData

/// Builds the distinct printings whose prices can be refreshed.
///
/// The foreground path receives the already-observed SwiftData rows. The
/// headless path fetches the exact same inputs in display order, so a
/// background refresh never needs a SwiftUI view or a ledger instance.
@MainActor
enum PriceRefreshTargets {
    private static func make(
        cards: [CollectedCard],
        priceRecords: [PriceRecord],
        usesPriceFallback: Bool,
        includeImported: Bool
    ) -> [PriceTarget] {
        let recordsByKey = Dictionary(
            priceRecords.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let projection = LogicalCollection.project(cards: cards) { card in
            PriceStore.priceStorageKey(for: card, in: recordsByKey)
        }
        var seen = Set<String>()
        var result: [PriceTarget] = []

        for position in projection.positions {
            let card = position.representative
            if card.providerID.hasPrefix("csv:"), !includeImported { continue }
            guard seen.insert(card.priceKey).inserted else { continue }
            let record = PriceStore.record(for: card, in: recordsByKey)
            var target = PriceTarget(
                game: card.cardGame,
                printingID: card.priceStorageID,
                catalogPrintingID: card.catalogProviderID ?? card.providerID,
                setCode: card.setCode,
                variantID: card.variantID,
                pokemonPrintRun: card.pokemonPrintRun,
                importedIdentity: card.providerID.hasPrefix("csv:") && card.catalogProviderID == nil
                    ? ImportedPriceIdentity(name: card.name, setName: card.setName, cardNumber: card.cardNumber)
                    : nil,
                catalogMetadataCheckedAt: card.catalogMetadataCheckedAt,
                lastFailureAt: record?.lastFailureAt,
                lastFailureReasonRaw: record?.lastFailureReasonRaw,
                hasPrice: PriceRefreshController.hasFinishedPrice(
                    amount: record?.effectiveUnitMarketPriceUSD,
                    currencyCode: record?.currencyCode,
                    usesFallback: usesPriceFallback
                ),
                lastCheckedAt: record?.lastCheckedAt,
                itemKind: card.itemKind,
                marketVariantID: card.justTCGVariantID ?? record?.marketVariantID,
                needsArtwork: ArtworkDiagnostics.shouldRetrySealedArtwork(for: card),
                gradedIdentity: card.itemKind == .gradedCard
                    ? GradedCardIdentity(name: card.name, setName: card.setName, collectorNumber: card.cardNumber)
                    : nil,
                gradingCompany: card.gradingCompany,
                grade: card.gradeRaw,
                magicTreatmentIDsRaw: card.priceTreatmentIDs
            )
            target.fallbackIdentity = ImportedPriceIdentity(
                name: card.name,
                setName: card.setName,
                cardNumber: card.cardNumber
            )
            target.justTCGCardID = card.justTCGCardID
            target.tcgplayerProductID = card.tcgplayerProductID
            result.append(target)
        }
        return result
    }

    static func make(
        context: ModelContext,
        usesPriceFallback: Bool,
        includeImported: Bool
    ) throws -> [PriceTarget] {
        let cards = try context.fetch(
            FetchDescriptor<CollectedCard>(
                sortBy: [SortDescriptor(\CollectedCard.dateAdded, order: .reverse)]
            )
        )
        let priceRecords = try context.fetch(FetchDescriptor<PriceRecord>())
        return make(
            cards: cards,
            priceRecords: priceRecords,
            usesPriceFallback: usesPriceFallback,
            includeImported: includeImported
        )
    }
}
