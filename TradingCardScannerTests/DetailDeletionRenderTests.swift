import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import TradingCardScanner

@MainActor
final class DetailDeletionRenderTests: XCTestCase {
    func testDestinationSurvivesPriceFilterChangeAndDisappearsOnlyAfterRemoval() throws {
        var row = CollectionRow(id: "stable", game: .pokemon, name: "Test Card", setCode: "TST",
                                setName: "Test Set", setReleaseOrder: 0, cardNumber: "1",
                                variantID: nil, variantLabel: nil, quantity: 1, dateAdded: .now,
                                price: .unknown)
        let diagnostics = CollectionRowDiagnostics(unpricedReason: .notChecked, artworkReason: .lookupPending)
        func snapshot(all: [CollectionRow], entries: [CollectionView.Snapshot.Entry]) -> CollectionView.Snapshot {
            CollectionView.Snapshot(all: all, entries: entries, collectionValue: .zero,
                                    footer: .make(visibleRows: entries.map(\.row), collectionRows: all, isNarrowed: true))
        }
        let visible = CollectionView.Snapshot.Entry(row: row, unpricedReason: .notChecked,
                                                    artworkReason: .lookupPending, isLogicalConflict: true)
        XCTAssertNotNil(CollectionView.entry(for: row.id, in: snapshot(all: [row], entries: [visible])))
        row.price = PriceDisplay(amount: 10, currencyCode: "USD")
        let hiddenByUnpricedFilter = snapshot(all: [row], entries: [])
        let entry = try XCTUnwrap(CollectionView.entry(for: row.id, in: hiddenByUnpricedFilter,
                                                      projectedDiagnostics: [row.id: diagnostics],
                                                      physicalRowCounts: [row.id: 2]))
        XCTAssertEqual(entry.row.price.amount, 10)
        XCTAssertNil(entry.unpricedReason)
        XCTAssertEqual(entry.artworkReason, .lookupPending)
        XCTAssertTrue(entry.isLogicalConflict)
        XCTAssertNil(CollectionView.entry(for: row.id, in: snapshot(all: [], entries: [])))
    }

    func testHostedCollectionDetailShowsRemovedPlaceholderAfterSiblingDelete() async throws {
        let container = try ModelContainer(
            for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let collectionKey = "detail-deletion-render"
        let card = CollectedCard(
            collectionKey: collectionKey,
            game: .pokemon,
            providerID: "test-set-001",
            name: "Test Card",
            setName: "Test Set",
            setCode: "TST",
            cardNumber: "001",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .normal,
            variantResolution: .userConfirmed
        )
        container.mainContext.insert(card)
        try container.mainContext.save()

        let row = CollectionRow(
            id: collectionKey,
            game: .pokemon,
            name: "Test Card",
            setCode: "TST",
            setName: "Test Set",
            setReleaseOrder: 0,
            cardNumber: "001",
            variantID: PhysicalVariant.normal.id,
            variantLabel: PhysicalVariant.normal.label,
            quantity: 1,
            dateAdded: .now,
            price: .unknown
        )
        var placeholderAppeared = false
        let hosted = CollectionCardDestination(
            row: row,
            unpricedReason: nil,
            artworkReason: nil,
            isLogicalConflict: false,
            history: PortfolioHistoryStore(),
            onRemoved: { _ in },
            onMissingPlaceholderAppeared: { placeholderAppeared = true }
        )
        let controller = UIHostingController(rootView: hosted.modelContainer(container))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await pumpMainRunLoop()

        let siblingContext = ModelContext(container)
        let siblingRow = try XCTUnwrap(try siblingContext.fetch(FetchDescriptor<CollectedCard>()).first)
        siblingContext.delete(siblingRow)
        try siblingContext.save()

        for _ in 0..<20 {
            if placeholderAppeared { break }
            await Task.yield()
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertTrue(placeholderAppeared, "The removed-card placeholder should render after the sibling delete.")
    }

    private func pumpMainRunLoop() async throws {
        for _ in 0..<4 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}
