import Foundation
import SwiftData
import XCTest
@testable import TradingCardScanner

@MainActor
final class OwnershipConcurrencyStressTests: XCTestCase {
    func testSerializedAddsAndCompareAndSetRepairsKeepLedgerQuantityAligned() async throws {
        let container = try ModelContainer(
            for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let card = identifiedCard()
        let resolved = ResolvedVariant(variant: .normal, resolution: .userConfirmed)
        let initial = try CollectionWriteSerializer.perform(
            container: container,
            timeout: .mainThread
        ) { context in
            try CollectionStore(context: context).add(card, resolved: resolved)
        }

        for _ in 0..<200 {
            let observedQuantity = try currentQuantity(
                collectionKey: initial.collectionKey,
                in: container
            )
            let addTask = Task.detached {
                try CollectionWriteSerializer.perform(
                    container: container,
                    timeout: .wait
                ) { context in
                    _ = try CollectionStore(context: context).add(card, resolved: resolved)
                }
            }
            let compareAndSetTask = Task.detached {
                do {
                    _ = try CollectionWriteSerializer.perform(
                        container: container,
                        timeout: .wait
                    ) { context in
                        try CollectionStore(context: context).setQuantity(
                            observedQuantity + 1,
                            forCollectionKey: initial.collectionKey,
                            expectedCurrent: observedQuantity
                        )
                    }
                } catch CollectionStoreError.staleQuantity {
                    // The scan add won the race. The caller must review the
                    // new count before applying the quantity edit.
                }
            }

            try await addTask.value
            try await compareAndSetTask.value

            let context = ModelContext(container)
            let quantity = try currentQuantity(
                collectionKey: initial.collectionKey,
                in: container
            )
            let events = try InventoryLedger(context: context).events(
                collectionKey: initial.collectionKey
            )
            XCTAssertEqual(
                events.reduce(0) { $0 + $1.deltaQuantity },
                quantity,
                "The row and ledger must agree after each racing ownership pair."
            )
        }
    }

    private func currentQuantity(collectionKey: String, in container: ModelContainer) throws -> Int {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<CollectedCard>(
            predicate: #Predicate { $0.collectionKey == collectionKey }
        )
        descriptor.fetchLimit = 1
        return try XCTUnwrap(context.fetch(descriptor).first).quantity
    }

    private func identifiedCard() -> IdentifiedCard {
        .pokemon(
            TCGdexCard(
                id: "ownership-stress-001",
                localId: "001",
                name: "Ownership Stress Card",
                image: nil,
                rarity: "Common",
                set: TCGdexSetBrief(
                    id: "ownership-stress",
                    name: "Ownership Stress",
                    cardCount: TCGdexCardCount(total: 10, official: 10)
                ),
                variants: TCGdexVariants(
                    firstEdition: false,
                    holo: false,
                    normal: true,
                    reverse: false,
                    wPromo: nil
                ),
                pricing: nil,
                variantsDetailed: nil
            ),
            setCode: "OST"
        )
    }
}
