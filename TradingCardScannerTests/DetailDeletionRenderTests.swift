import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import TradingCardScanner

@MainActor
final class DetailDeletionRenderTests: XCTestCase {
    func testHistoryLoadingAndFailuresKeepSavedDataAndDistinguishEmptyPeriods() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let points = [JustTCGHistoryPoint(p: 20, t: now.addingTimeInterval(-30 * 86_400).timeIntervalSince1970)]
        let all = PriceHistoryChartModel.market(points: points, range: .all, now: now)
        let week = PriceHistoryChartModel.market(points: points, range: .oneWeek, now: now)
        let empty = PriceHistoryChartModel.market(points: [], range: .oneWeek, now: now)

        XCTAssertEqual(MarketHistoryPresentation(model: empty, hasHistory: false, isLoading: true, error: nil), .loading)
        XCTAssertEqual(MarketHistoryPresentation(model: empty, hasHistory: false, isLoading: false, error: nil), .unavailable)
        XCTAssertEqual(MarketHistoryPresentation(model: empty, hasHistory: false, isLoading: false, error: "offline"), .failed)
        XCTAssertEqual(MarketHistoryPresentation(model: all, hasHistory: true, isLoading: true, error: nil), .chart)
        XCTAssertEqual(MarketHistoryPresentation(model: all, hasHistory: true, isLoading: false, error: "offline"), .chart)
        XCTAssertEqual(MarketHistoryPresentation(model: week, hasHistory: true, isLoading: true, error: nil), .outsideRange)
        XCTAssertEqual(MarketHistoryPresentation(model: week, hasHistory: true, isLoading: false, error: "offline"), .outsideRange)
        XCTAssertFalse(all.samples.isEmpty, "Switching to all history must recover the saved samples")

        var range = PortfolioHistoryRange.oneWeek
        var selection: Date? = now
        let content = MarketHistoryChartContent(model: week, hasHistory: true, isLoading: false,
            error: nil, direction: .flat,
            range: Binding(get: { range }, set: { range = $0 }),
            selection: Binding(get: { selection }, set: { selection = $0 }), retry: {})
        content.showAllHistory()
        XCTAssertEqual(range, .all, "The recovery action must select all history")
        XCTAssertNil(selection, "The current quote must not retain an out-of-range scrub selection")
        XCTAssertEqual(PriceHistoryChartModel.market(points: points, range: range, now: now).samples.count, 1)
    }

    func testLoadingHistoryUsesCompactLayoutAtStandardAndAccessibleTextSizes() {
        let model = PriceHistoryChartModel.market(points: [], range: .oneWeek)
        for size in [DynamicTypeSize.large, .accessibility3] {
            let content = MarketHistoryChartContent(model: model, hasHistory: false, isLoading: true,
                error: nil, direction: .flat, range: .constant(.oneWeek), selection: .constant(nil), retry: {})
                .environment(\.dynamicTypeSize, size)
            let controller = UIHostingController(rootView: content)
            let measured = controller.sizeThatFits(in: CGSize(width: 350, height: 1000))
            XCTAssertGreaterThanOrEqual(measured.height, 44)
            XCTAssertLessThan(measured.height, 160, "Loading should stay compact and leave ownership controls reachable")
        }
    }

    func testHostedDenseChartLayoutAndSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let points = (0..<1000).map { index in
            JustTCGHistoryPoint(p: Double(index % 100 + 1) / 100,
                t: now.addingTimeInterval(Double(index - 1000) * 60).timeIntervalSince1970)
        }
        let model = PriceHistoryChartModel.market(points: points, range: .all, now: now)
        var times: [Double] = []
        for _ in 0..<3 {
            let start = CACurrentMediaTime()
            let chart = PriceHistoryChartView(model: model, currencyCode: "USD", direction: .flat,
                selectedDate: .constant(nil)).frame(width: 360, height: 240)
            let controller = UIHostingController(rootView: chart)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.frame = window.bounds
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            let snapshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                controller.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            times.append((CACurrentMediaTime() - start) * 1000)
            XCTAssertNotNil(snapshot.cgImage)
            window.isHidden = true
            window.rootViewController = nil
        }
        print("Dense chart hosted layout/snapshot milliseconds (1000 points): \(times)")
        XCTAssertEqual(model.samples.count, 1000)
    }

    func testArtworkOverrideValueRules() {
        typealias Source = CollectionDetailArtworkSource<Text>
        XCTAssertEqual(Source.effectiveFilename(override: "new.png", legacy: "legacy.png"), "new.png")
        XCTAssertNil(Source.effectiveFilename(override: "", legacy: "legacy.png"))
        XCTAssertEqual(Source.effectiveFilename(override: nil, legacy: "legacy.png"), "legacy.png")
        XCTAssertNil(Source.effectiveFilename(override: nil, legacy: ""))
        XCTAssertNil(Source.effectiveFilename(override: nil, legacy: nil))
    }

    func testHostedArtworkQueryTracksSiblingReplacementRemovalAndKeyChanges() async throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        context.insert(LocalArtworkOverride(collectionKey: "a", filename: "older.png", updatedAt: Date(timeIntervalSince1970: 1)))
        context.insert(LocalArtworkOverride(collectionKey: "a", filename: "newest.png", updatedAt: Date(timeIntervalSince1970: 2)))
        context.insert(LocalArtworkOverride(collectionKey: "b", filename: "b.png"))
        try context.save()
        let state = ArtworkQueryHostState()
        var seen: String?
        let controller = UIHostingController(rootView: ArtworkQueryHost(state: state) { seen = $0 }.modelContainer(container))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitForArtwork { seen == "newest.png" }

        let sibling = ModelContext(container)
        let rows = try sibling.fetch(FetchDescriptor<LocalArtworkOverride>())
        let newest = try XCTUnwrap(rows.first { $0.filename == "newest.png" })
        newest.filename = "replacement.png"
        try sibling.save()
        try await waitForArtwork { seen == "replacement.png" }

        newest.filename = ""
        try sibling.save()
        try await waitForArtwork { seen == nil }
        for row in rows where row.collectionKey == "a" { sibling.delete(row) }
        try sibling.save()
        try await waitForArtwork { seen == "legacy.png" }
        state.legacy = "changed-legacy.png"
        try await waitForArtwork { seen == "changed-legacy.png" }
        state.key = "b"
        try await waitForArtwork { seen == "b.png" }
        state.key = "missing"
        try await waitForArtwork { seen == "changed-legacy.png" }
    }

    private func waitForArtwork(_ condition: () -> Bool) async throws {
        for _ in 0..<40 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertTrue(condition(), "The hosted query should publish the current key's newest override")
    }

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

@MainActor
private final class ArtworkQueryHostState: ObservableObject {
    @Published var key = "a"
    @Published var legacy: String? = "legacy.png"
}

private struct ArtworkQueryHost: View {
    @ObservedObject var state: ArtworkQueryHostState
    let rendered: (String?) -> Void

    var body: some View {
        CollectionDetailArtworkSource(collectionKey: state.key, legacyFilename: state.legacy) { filename in
            Text(filename ?? "none")
                .onChange(of: filename, initial: true) { _, value in rendered(value) }
        }
    }
}
