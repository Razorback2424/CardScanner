import Foundation

/// The last authoritative headline Portfolio published for one store.
///
/// Launch shows this immediately instead of a blank "Calculating portfolio…"
/// screen while the replay rebuilds today's value. It is presentation only:
/// it never seeds the ledger, history, closes or live price deltas, and the
/// engine marks the summary built from it as provisional until a replay of the
/// current store replaces it.
struct PortfolioLaunchSnapshot: Codable, Equatable, Sendable {
    var storeID: UUID
    var valueTenThousandths: Int64
    var copyCount: Int?
    var unpricedCount: Int
    var otherCurrencyCount: Int
    var savedAt: Date

    /// A provisional summary: never authoritative, so nothing that depends on
    /// replayed history renders or publishes from it.
    var provisionalSummary: PortfolioSummary {
        var summary = PortfolioSummary(
            currentValue: Money(tenThousandths: valueTenThousandths),
            copyCount: copyCount,
            unpricedCount: unpricedCount,
            otherCurrencyCount: otherCurrencyCount
        )
        summary.isAuthoritative = false
        summary.isProvisional = true
        return summary
    }
}

/// Persists one launch snapshot, scoped to the store that produced it so a
/// different storage session (iCloud vs. on-device, another account, a reset
/// collection) never opens on someone else's number.
@MainActor
final class PortfolioLaunchSnapshotStore {
    static let shared = PortfolioLaunchSnapshotStore(defaults: .standard)

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults, key: String = "portfolioLaunchSnapshot.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load(storeID: UUID?, now: Date = .now) -> PortfolioLaunchSnapshot? {
        guard let storeID,
              let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(PortfolioLaunchSnapshot.self, from: data),
              snapshot.storeID == storeID,
              snapshot.savedAt <= now else { return nil }
        return snapshot
    }

    /// Records an authoritative, defect-free summary. An empty collection
    /// clears the snapshot: its own empty state is fast and must stay honest.
    func record(_ summary: PortfolioSummary, storeID: UUID?, now: Date = .now) {
        guard let storeID else { return }
        guard summary.isAuthoritative, !summary.isProvisional, summary.defects.isEmpty,
              summary.currentValue.isValid else { return }
        guard let copies = summary.copyCount, copies > 0 else {
            clear()
            return
        }
        let snapshot = PortfolioLaunchSnapshot(
            storeID: storeID,
            valueTenThousandths: summary.currentValue.tenThousandths,
            copyCount: copies,
            unpricedCount: summary.unpricedCount,
            otherCurrencyCount: summary.otherCurrencyCount,
            savedAt: now
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

/// The rest of the last authoritative Portfolio screen: the Showcase holdings
/// and the chart/movers result for the period that was on screen.
///
/// Launch renders the whole dashboard from this, beside the provisional value,
/// instead of a bare number that later grows a chart, Showcase and movers.
/// Like `PortfolioLaunchSnapshot` it is presentation only: it never seeds the
/// ledger, closes or the history engine, and the first replay of this launch
/// replaces every part of it.
struct PortfolioLaunchPresentation: Codable, Equatable, Sendable {
    var storeID: UUID
    var savedAt: Date
    var holdings: [Holding]
    var history: History?

    /// Enough holdings for the Showcase rail plus the named movers.
    static let showcaseLimit = 5
    static let moverLimit = 25

    init(
        storeID: UUID,
        savedAt: Date,
        holdings: [PortfolioHoldingSnapshot],
        history: PortfolioHistoryResult?
    ) {
        let movers = history.map(Self.moverKeys(in:)) ?? []
        let showcase = holdings
            .prefix(while: { $0.holdingValue != nil })
            .prefix(Self.showcaseLimit)
        let showcaseKeys = Set(showcase.map(\.collectionKey))
        let retainedKeys = showcaseKeys.union(movers)
        self.storeID = storeID
        self.savedAt = savedAt
        // Keep the published order so the rail ranks exactly as it did.
        self.holdings = holdings
            .filter { retainedKeys.contains($0.collectionKey) }
            .map(Holding.init)
        self.history = history.map { History($0, keeping: retainedKeys) }
    }

    var holdingSnapshots: [PortfolioHoldingSnapshot] { holdings.map(\.snapshot) }

    private static func moverKeys(in result: PortfolioHistoryResult) -> Set<String> {
        let ranked = result.contributions
            .filter { !$0.value.isZero }
            .sorted {
                $0.value.magnitude != $1.value.magnitude
                    ? $0.value.magnitude > $1.value.magnitude
                    : $0.key < $1.key
            }
            .prefix(moverLimit)
        return Set(ranked.map(\.key))
    }

    struct Holding: Codable, Equatable, Sendable {
        var collectionKey: String
        var name: String
        var detail: String
        var userArtworkFilename: String?
        var artworkURL: URL?
        var artworkFallbackURL: URL?
        var quantity: Int
        var unitPrice: Int64?
        var holdingValue: Int64?
        var priceStorageKey: String
        var artworkGame: CardGame?
        var artworkSetCode: String?
        var artworkCollectorNumber: String?
        var artworkProviderID: String?

        init(_ holding: PortfolioHoldingSnapshot) {
            collectionKey = holding.collectionKey
            name = holding.name
            detail = holding.detail
            userArtworkFilename = holding.userArtworkFilename
            artworkURL = holding.artworkURL
            artworkFallbackURL = holding.artworkFallbackURL
            quantity = holding.quantity
            unitPrice = holding.unitPrice?.tenThousandths
            holdingValue = holding.holdingValue?.tenThousandths
            priceStorageKey = holding.priceStorageKey
            artworkGame = holding.artworkGame
            artworkSetCode = holding.artworkSetCode
            artworkCollectorNumber = holding.artworkCollectorNumber
            artworkProviderID = holding.artworkProviderID
        }

        var snapshot: PortfolioHoldingSnapshot {
            PortfolioHoldingSnapshot(
                collectionKey: collectionKey,
                name: name,
                detail: detail,
                userArtworkFilename: userArtworkFilename,
                artworkURL: artworkURL,
                artworkFallbackURL: artworkFallbackURL,
                quantity: quantity,
                unitPrice: unitPrice.map { Money(tenThousandths: $0) },
                holdingValue: holdingValue.map { Money(tenThousandths: $0) },
                priceStorageKey: priceStorageKey,
                artworkGame: artworkGame,
                artworkSetCode: artworkSetCode,
                artworkCollectorNumber: artworkCollectorNumber,
                artworkProviderID: artworkProviderID
            )
        }
    }

    /// A `PortfolioHistoryResult` without its close revisions, with movement
    /// trimmed to the holdings the dashboard can name.
    struct History: Codable, Equatable, Sendable {
        struct Point: Codable, Equatable, Sendable {
            var displayDay: Date
            var instant: Date
            var value: Int64
            var cumulativeMarketMovement: Int64
            var performanceFactor: Decimal?
            var isLive: Bool
        }

        struct Accounting: Codable, Equatable, Sendable {
            var anchorValue, endValue, market, added, removed: Int64
            var corrections, newlyAddedValue, pricingAdjustments, unexplained: Int64
        }

        struct Coverage: Codable, Equatable, Sendable {
            var completeDays, partialDays, unknownDays: Int
            var liveRefreshed: Int?
            var liveCarriedForward: Int?
            var liveState: PortfolioCoverageState?
        }

        struct Interval: Codable, Equatable, Sendable {
            var anchorDate: Date
            var includedClosedDays: [Date]
            var includesLiveDay: Bool
            var liveDay: Date?
        }

        struct Movement: Codable, Equatable, Sendable {
            var totalImpact: Int64
            var cumulativeUnitMovement: Int64
            var affectedQuantities: [Int]
        }

        var range: PortfolioHistoryRange
        var points: [Point]
        var accounting: Accounting?
        var performanceFactor: Decimal?
        var performanceAvailable: Bool
        var coverage: Coverage
        var trackingBeganDate: Date?
        var hasTwoPublishedPoints: Bool
        var accountingInterval: Interval?
        var contributions: [String: Int64]
        var movementDetails: [String: Movement]
        var additions: [String: Int64]
        var addedQuantities: [String: Int]
        var hasEligibleMarketMovement: Bool

        init(_ result: PortfolioHistoryResult, keeping keys: Set<String>) {
            range = result.range
            points = result.points.map {
                Point(
                    displayDay: $0.displayDay,
                    instant: $0.instant,
                    value: $0.value.tenThousandths,
                    cumulativeMarketMovement: $0.cumulativeMarketMovement.tenThousandths,
                    performanceFactor: $0.performanceFactor,
                    isLive: $0.isLive
                )
            }
            accounting = result.accounting.map {
                Accounting(
                    anchorValue: $0.anchorValue.tenThousandths,
                    endValue: $0.endValue.tenThousandths,
                    market: $0.market.tenThousandths,
                    added: $0.added.tenThousandths,
                    removed: $0.removed.tenThousandths,
                    corrections: $0.corrections.tenThousandths,
                    newlyAddedValue: $0.newlyAddedValue.tenThousandths,
                    pricingAdjustments: $0.pricingAdjustments.tenThousandths,
                    unexplained: $0.unexplained.tenThousandths
                )
            }
            performanceFactor = result.performanceFactor
            performanceAvailable = result.performanceAvailable
            coverage = Coverage(
                completeDays: result.coverage.completeDays,
                partialDays: result.coverage.partialDays,
                unknownDays: result.coverage.unknownDays,
                liveRefreshed: result.coverage.live?.refreshed,
                liveCarriedForward: result.coverage.live?.carriedForward,
                liveState: result.coverage.live?.state
            )
            trackingBeganDate = result.trackingBeganDate
            hasTwoPublishedPoints = result.hasTwoPublishedPoints
            accountingInterval = result.accountingInterval.map {
                Interval(
                    anchorDate: $0.anchorDate,
                    includedClosedDays: $0.includedClosedDays,
                    includesLiveDay: $0.includesLiveDay,
                    liveDay: $0.liveDay
                )
            }
            contributions = result.contributions
                .filter { keys.contains($0.key) }
                .mapValues(\.tenThousandths)
            movementDetails = result.movementDetails
                .filter { keys.contains($0.key) }
                .mapValues {
                    Movement(
                        totalImpact: $0.totalImpact.tenThousandths,
                        cumulativeUnitMovement: $0.cumulativeUnitMovement.tenThousandths,
                        affectedQuantities: $0.affectedQuantities
                    )
                }
            additions = result.additions
                .filter { keys.contains($0.key) }
                .mapValues(\.tenThousandths)
            addedQuantities = result.addedQuantities.filter { keys.contains($0.key) }
            hasEligibleMarketMovement = result.hasEligibleMarketMovement
        }

        var result: PortfolioHistoryResult {
            func money(_ value: Int64) -> Money { Money(tenThousandths: value) }
            return PortfolioHistoryResult(
                range: range,
                points: points.map {
                    PortfolioHistoryPoint(
                        displayDay: $0.displayDay,
                        instant: $0.instant,
                        value: money($0.value),
                        cumulativeMarketMovement: money($0.cumulativeMarketMovement),
                        performanceFactor: $0.performanceFactor,
                        isLive: $0.isLive
                    )
                },
                accounting: accounting.map {
                    PortfolioHistoryAccounting(
                        anchorValue: money($0.anchorValue),
                        endValue: money($0.endValue),
                        market: money($0.market),
                        added: money($0.added),
                        removed: money($0.removed),
                        corrections: money($0.corrections),
                        newlyAddedValue: money($0.newlyAddedValue),
                        pricingAdjustments: money($0.pricingAdjustments),
                        unexplained: money($0.unexplained)
                    )
                },
                performanceFactor: performanceFactor,
                performanceAvailable: performanceAvailable,
                coverage: PortfolioHistoryCoverage(
                    completeDays: coverage.completeDays,
                    partialDays: coverage.partialDays,
                    unknownDays: coverage.unknownDays,
                    live: coverage.liveState.map {
                        PortfolioCoverage(
                            refreshed: coverage.liveRefreshed ?? 0,
                            carriedForward: coverage.liveCarriedForward ?? 0,
                            state: $0
                        )
                    }
                ),
                revisions: [],
                trackingBeganDate: trackingBeganDate,
                hasTwoPublishedPoints: hasTwoPublishedPoints,
                accountingInterval: accountingInterval.map {
                    PortfolioAccountingInterval(
                        anchorDate: $0.anchorDate,
                        includedClosedDays: $0.includedClosedDays,
                        includesLiveDay: $0.includesLiveDay,
                        liveDay: $0.liveDay
                    )
                },
                contributions: contributions.mapValues(money),
                movementDetails: movementDetails.mapValues {
                    PortfolioContributionDetail(
                        totalImpact: money($0.totalImpact),
                        cumulativeUnitMovement: money($0.cumulativeUnitMovement),
                        affectedQuantities: $0.affectedQuantities
                    )
                },
                additions: additions.mapValues(money),
                addedQuantities: addedQuantities,
                hasEligibleMarketMovement: hasEligibleMarketMovement
            )
        }
    }
}

/// Keeps one `PortfolioLaunchPresentation` as a small file in Caches: it can
/// outgrow what belongs in `UserDefaults`, and losing it only costs one launch
/// the plain provisional value.
@MainActor
final class PortfolioLaunchPresentationStore {
    static let shared = PortfolioLaunchPresentationStore(
        fileURL: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PortfolioLaunchPresentation.v1.json")
    )

    private let fileURL: URL
    private var lastWritten: PortfolioLaunchPresentation?
    private var writeTask: Task<Void, Never>?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load(storeID: UUID?, now: Date = .now) -> PortfolioLaunchPresentation? {
        guard let storeID,
              let data = try? Data(contentsOf: fileURL),
              let presentation = try? JSONDecoder().decode(PortfolioLaunchPresentation.self, from: data),
              presentation.storeID == storeID,
              presentation.savedAt <= now,
              presentation.history?.points.allSatisfy({ $0.instant <= now }) ?? true else { return nil }
        return presentation
    }

    func record(_ presentation: PortfolioLaunchPresentation) {
        var comparable = presentation
        comparable.savedAt = lastWritten?.savedAt ?? presentation.savedAt
        guard comparable != lastWritten else { return }
        lastWritten = presentation
        let fileURL = fileURL
        let previous = writeTask
        writeTask = Task.detached(priority: .utility) {
            await previous?.value
            guard let data = try? JSONEncoder().encode(presentation) else { return }
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    func clear() {
        lastWritten = nil
        let fileURL = fileURL
        let previous = writeTask
        writeTask = Task.detached(priority: .utility) {
            await previous?.value
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Tests read back what a launch would.
    func waitForPendingWrites() async {
        await writeTask?.value
    }
}
