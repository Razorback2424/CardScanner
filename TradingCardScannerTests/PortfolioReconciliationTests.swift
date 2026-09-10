import XCTest
import SwiftData
@testable import TradingCardScanner

private final class CSVProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(Int, Int)] = []

    func append(_ completed: Int, _ total: Int) {
        lock.lock()
        recorded.append((completed, total))
        lock.unlock()
    }

    func values() -> [(Int, Int)] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

private actor PortfolioComputationGate {
    private var permits = 0
    private var waiting = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if permits > 0 {
            permits -= 1
            return
        }
        waiting += 1
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiting -= 1
            waiter.resume()
        } else {
            permits += 1
        }
    }

    func waitingCount() -> Int {
        waiting
    }
}

/// Container-backed reconciliation cases: local knowledge time, missed close
/// publication, CloudKit-style duplicate rows, invalidation, and explicit undo
/// semantics. These are the contracts most likely to pass pure accounting tests
/// while failing in a real store.
@MainActor
final class PortfolioReconciliationTests: XCTestCase {
    private var container: ModelContainer?

    /// Epoch establishment resolves each position's price key through the bulk
    /// valuation index rather than `InventoryLedger`, which costs two predicate
    /// fetches per candidate key per card. The point of that change was speed,
    /// but the thing that could silently break is *correctness*: the two
    /// resolvers must choose the same instrument, or the baseline opens valuing
    /// positions through a different price than the collection grid shows.
    ///
    /// A timing assertion was tried here and deliberately rejected — against an
    /// in-memory store the two implementations measure 2.6s and 3.0s for 1,500
    /// positions, so any bound that is not flaky also does not detect the
    /// regression. This pins the equivalence instead, which is deterministic
    /// and is the property that actually matters.
    func testEpochResolvesTheSamePriceKeyAsTheLedgerResolver() throws {
        let context = try makeContext()

        // A first-edition raw card reads through a legacy price key, so the two
        // resolvers have a real choice to disagree about rather than a single
        // candidate. One position holds its value on the legacy key only, one
        // on the canonical key, and one has no price at all.
        let legacyOnly = card(key: "legacy-only")
        legacyOnly.variantID = PhysicalVariant.firstEdition.id
        legacyOnly.variantLabel = PhysicalVariant.firstEdition.label
        let canonical = card(key: "canonical")
        let unpriced = card(key: "unpriced")
        unpriced.variantID = PhysicalVariant.firstEdition.id
        unpriced.variantLabel = PhysicalVariant.firstEdition.label
        for row in [legacyOnly, canonical, unpriced] { context.insert(row) }

        for (row, key) in [
            (legacyOnly, legacyOnly.legacyPriceKeys.first),
            (canonical, canonical.priceKey)
        ] {
            guard let key else { continue }
            let record = PriceRecord(
                key: key,
                game: row.cardGame,
                printingID: row.priceStorageID,
                variantID: row.variantID
            )
            _ = record.apply(
                NormalizedPrice(
                    unitMarketPriceUSD: 4.25,
                    currencyCode: "USD",
                    source: .tcgplayer,
                    sourceVariantID: key,
                    sourceUpdatedAt: nil,
                    fetchedAt: Date(timeIntervalSince1970: 100)
                )
            )
            context.insert(record)
        }
        try context.save()

        let ledger = InventoryLedger(context: context)
        let cards = try context.fetch(FetchDescriptor<CollectedCard>())
        let valuations = PortfolioReplaySnapshotBuilder.valuationIndex(
            observations: try context.fetch(FetchDescriptor<PriceObservation>()),
            records: try context.fetch(FetchDescriptor<PriceRecord>())
        )

        // The equivalence the refactor rests on, asserted directly.
        for row in cards {
            XCTAssertEqual(
                valuations.priceStorageKey(for: row),
                ledger.priceStorageKey(for: row),
                "Bulk and scalar resolvers disagree for \(row.collectionKey)"
            )
        }
        // Not vacuous: the legacy read-through really is in play here.
        XCTAssertEqual(
            valuations.priceStorageKey(for: legacyOnly),
            legacyOnly.legacyPriceKeys.first
        )
        XCTAssertNotEqual(
            valuations.priceStorageKey(for: legacyOnly),
            legacyOnly.priceKey
        )

        let defaults = UserDefaults(suiteName: "PortfolioEpochTests.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        try PortfolioEpoch.establishIfNeeded(
            context: context,
            defaults: defaults,
            isCloudSyncing: false
        )

        // And the baseline events carry that same instrument, so the books open
        // valuing each position through the price the collection displays.
        let events = ledger.allEvents()
        XCTAssertEqual(events.count, cards.count)
        for event in events {
            guard let row = cards.first(where: { $0.collectionKey == event.collectionKey }) else {
                XCTFail("Baseline event for an unknown position \(event.collectionKey)")
                continue
            }
            XCTAssertEqual(event.kind, .initialBalance)
            XCTAssertEqual(event.priceStorageKey, ledger.priceStorageKey(for: row))
        }
        XCTAssertEqual(
            events.first { $0.collectionKey == "unpriced" }?.unitPrice,
            nil
        )
    }

    /// Holding detail resolves a position's instrument the way the grid does,
    /// not the way the ledger does.
    ///
    /// `PortfolioOwnedCardDestination` used to project through
    /// `InventoryLedger.priceStorageKey(for:)`, which costs two to four
    /// predicate fetches per candidate key per position from inside `body`.
    /// Moving it to `PriceStore.priceStorageKey(for:in:)` was a performance
    /// change, but it is not a semantically neutral one: the ledger's rule can
    /// see an invalidation that exists only in the observation log, and the
    /// record-only rule cannot. This pins the choice that was made — detail and
    /// grid agree, and the price shown is the price of the instrument the
    /// position is attributed to — and pins it on the one input where the two
    /// rules genuinely disagree, so it cannot pass vacuously.
    func testHoldingDetailResolvesTheSameInstrumentAsTheGrid() throws {
        let context = try makeContext()

        // A first-edition raw card reads through a legacy price key, so there
        // is a real choice between two candidates.
        let row = card(key: "observation-invalidated")
        row.variantID = PhysicalVariant.firstEdition.id
        row.variantLabel = PhysicalVariant.firstEdition.label
        context.insert(row)

        let canonicalKey = row.priceKey
        guard let legacyKey = row.legacyPriceKeys.first else {
            return XCTFail("fixture needs a legacy read-through key")
        }

        // The canonical key holds a placeholder with no value; the legacy key
        // holds the only real price. Neither record is invalidated — the
        // withdrawal exists solely as an observation, which is the one shape
        // the two resolvers answer differently.
        for (key, priced) in [(canonicalKey, false), (legacyKey, true)] {
            let record = PriceRecord(
                key: key,
                game: row.cardGame,
                printingID: row.priceStorageID,
                variantID: row.variantID
            )
            if priced {
                _ = record.apply(
                    NormalizedPrice(
                        unitMarketPriceUSD: 4.25,
                        currencyCode: "USD",
                        source: .tcgplayer,
                        sourceVariantID: key,
                        sourceUpdatedAt: nil,
                        fetchedAt: Date(timeIntervalSince1970: 100)
                    )
                )
            }
            context.insert(record)
        }
        context.insert(
            PriceObservation(
                instrumentKey: canonicalKey,
                kind: .explicitInvalidation,
                amount: nil,
                source: .tcgplayer,
                sourceVariantID: nil,
                marketVariantID: nil,
                effectiveAt: Date(timeIntervalSince1970: 200),
                receivedAt: Date(timeIntervalSince1970: 200),
                isSourceStamped: false
            )
        )
        try context.save()

        let recordsByKey = Dictionary(
            try context.fetch(FetchDescriptor<PriceRecord>()).map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Not vacuous: the ledger really does answer differently here.
        XCTAssertEqual(
            InventoryLedger(context: context).priceStorageKey(for: row),
            canonicalKey,
            "the ledger honours an observation-only invalidation"
        )
        XCTAssertEqual(
            PriceStore.priceStorageKey(for: row, in: recordsByKey),
            legacyKey,
            "the record-only rule cannot see it, and falls through to the priced key"
        )

        let valuations = PortfolioReplaySnapshotBuilder.valuationIndex(
            observations: try context.fetch(FetchDescriptor<PriceObservation>()),
            records: try context.fetch(FetchDescriptor<PriceRecord>())
        )
        XCTAssertEqual(
            valuations.priceStorageKey(for: row),
            legacyKey,
            "portfolio attribution must use the same record-backed instrument as the grid"
        )

        // The property the change rests on: the instrument holding detail
        // attributes the position to is the instrument whose price it shows,
        // and both match what the grid computes from the same records.
        let detailInstrument = LogicalCollection
            .project(cards: [row]) { PriceStore.priceStorageKey(for: $0, in: recordsByKey) }
            .byKey[row.collectionKey]?
            .priceStorageKey
        XCTAssertEqual(detailInstrument, legacyKey)
        XCTAssertEqual(PriceStore.record(for: row, in: recordsByKey)?.key, detailInstrument)
    }

    // MARK: - Coverage retention (R1)

    private func replayDay(
        _ day: Date,
        closeValue: Double,
        coverage: PortfolioCoverage,
        carriedForwardValue: Money = .zero
    ) -> PortfolioReplayDay {
        PortfolioReplayDay(
            displayDay: day,
            boundary: day.addingTimeInterval(86_400),
            closeValue: money(closeValue),
            market: .zero,
            added: .zero,
            removed: .zero,
            corrections: .zero,
            newlyAddedValue: .zero,
            pricingAdjustment: .zero,
            performanceFactor: nil,
            pricedPositionCount: 1,
            excludedQuantity: 0,
            coverage: coverage,
            carriedForwardValue: carriedForwardValue,
            contributions: [:],
            movementDetails: [:],
            hasEligibleMarketMovement: false
        )
    }

    /// Coverage for a day whose `PriceCheckDay` rows have been pruned comes
    /// from the close already published, not from a recompute that would see
    /// no checks and report the whole holding as carried forward.
    ///
    /// The contract this pins is the one the retention window trades away, so
    /// it is asserted in the two halves that matter separately: a pruned day
    /// must not be revised at all merely because its evidence is gone, and a
    /// pruned day that a late event genuinely does revise must keep its
    /// original coverage counts while its value changes.
    func testPrunedDaysKeepPublishedCoverage() throws {
        let context = try makeContext()
        let zone = TimeZone(identifier: "America/Chicago") ?? .current
        let old = PortfolioCalendar.day(
            containing: Date(timeIntervalSince1970: 1_700_000_000),
            in: zone
        )
        let recent = PortfolioCalendar.day(
            containing: old.addingTimeInterval(500 * 86_400),
            in: zone
        )
        let windowStart = PortfolioCalendar.day(
            containing: old.addingTimeInterval(400 * 86_400),
            in: zone
        )
        let measured = PortfolioCoverage(refreshed: 3, carriedForward: 1, state: .partial)
        // What a recompute produces once the rows behind it are gone.
        let pruned = PortfolioCoverage(refreshed: 0, carriedForward: 4, state: .unknown)

        // Published while the evidence still existed.
        _ = PortfolioEngine.publish(
            [
                replayDay(
                    old,
                    closeValue: 10,
                    coverage: measured,
                    carriedForwardValue: money(2)
                ),
                replayDay(recent, closeValue: 20, coverage: measured)
            ],
            timeZone: zone,
            context: context
        )
        try context.save()

        // The rows are pruned; the replay now derives nothing for the old day.
        _ = PortfolioEngine.publish(
            [
                replayDay(
                    old,
                    closeValue: 10,
                    coverage: pruned,
                    carriedForwardValue: money(9)
                ),
                replayDay(recent, closeValue: 20, coverage: measured)
            ],
            timeZone: zone,
            coverageWindowStart: windowStart,
            context: context
        )
        try context.save()

        let afterPrune = try PortfolioEngine.allCloses(in: context)
        XCTAssertEqual(afterPrune.count, 2, "a pruned day must not be revised for lost evidence")
        let oldClose = try XCTUnwrap(afterPrune.first { $0.date == old })
        XCTAssertEqual(oldClose.revision, 1)
        XCTAssertEqual(oldClose.refreshedInstrumentCount, 3)
        XCTAssertEqual(oldClose.carriedForwardInstrumentCount, 1)
        XCTAssertEqual(oldClose.coverageState, .partial)
        XCTAssertEqual(oldClose.carriedForwardValue, money(2))

        // A late inventory event genuinely revises the same pruned day.
        _ = PortfolioEngine.publish(
            [
                replayDay(
                    old,
                    closeValue: 12,
                    coverage: pruned,
                    carriedForwardValue: money(9)
                ),
                replayDay(recent, closeValue: 20, coverage: measured)
            ],
            timeZone: zone,
            coverageWindowStart: windowStart,
            context: context
        )
        try context.save()

        let revised = try XCTUnwrap(
            try PortfolioEngine.allCloses(in: context)
                .filter { $0.date == old }
                .max { $0.revision < $1.revision }
        )
        XCTAssertEqual(revised.revision, 2)
        XCTAssertEqual(revised.closeValue, money(12), "value still replays from events")
        XCTAssertEqual(revised.refreshedInstrumentCount, 3, "coverage is carried, not recomputed")
        XCTAssertEqual(revised.carriedForwardInstrumentCount, 1)
        XCTAssertEqual(revised.carriedForwardValue, money(2))

        // Inside the window nothing is carried: a real coverage change is a
        // real revision.
        _ = PortfolioEngine.publish(
            [
                replayDay(old, closeValue: 12, coverage: pruned),
                replayDay(
                    recent,
                    closeValue: 20,
                    coverage: PortfolioCoverage(refreshed: 4, carriedForward: 0, state: .complete)
                )
            ],
            timeZone: zone,
            coverageWindowStart: windowStart,
            context: context
        )
        try context.save()

        let recentClose = try XCTUnwrap(
            try PortfolioEngine.allCloses(in: context)
                .filter { $0.date == recent }
                .max { $0.revision < $1.revision }
        )
        XCTAssertEqual(recentClose.revision, 2)
        XCTAssertEqual(recentClose.refreshedInstrumentCount, 4)
        XCTAssertEqual(recentClose.coverageState, .complete)
    }

    /// The window bounds the read without changing what an unaged store sees.
    func testCoverageWindowOnlyConstrainsHistoryOlderThanTheWindow() throws {
        let context = try makeContext()
        let zone = TimeZone(identifier: "America/Chicago") ?? .current
        let today = PortfolioCalendar.day(containing: .now, in: zone)
        let youngEpoch = PortfolioCalendar.day(
            containing: today.addingTimeInterval(-30 * 86_400),
            in: zone
        )
        context.insert(
            PriceCheckDay(
                instrumentKey: "instrument",
                portfolioDay: youngEpoch,
                lastSuccessfulCheckAt: youngEpoch,
                source: .tcgplayer
            )
        )
        try context.save()

        let index = PortfolioReplaySnapshotBuilder.coverageIndex(
            context: context,
            from: youngEpoch,
            through: today,
            timeZone: zone
        )
        XCTAssertNil(
            index.windowStart,
            "a store younger than the window is answered in full, so nothing is carried"
        )
        XCTAssertTrue(index.covers(youngEpoch))
        XCTAssertEqual(index.checkedInstruments(on: youngEpoch), ["instrument"])
    }

    // MARK: - Slice 1 baseline

    /// Measures the two whole-table reads the remediation plan's gated slices
    /// depend on, against a store aged the way a real one ages.
    ///
    /// Opt-in. Seeding a year of check days takes longer than the entire rest
    /// of the suite, and a slow test in the default run is a test people learn
    /// to skip. Run it deliberately:
    ///
    ///     PERF_BASELINE=1 xcodebuild test \
    ///       -only-testing:TradingCardScannerTests/PortfolioReconciliationTests/testAgedStoreBaseline
    ///
    /// `PERF_INSTRUMENTS` and `PERF_DAYS` override the shape. This asserts
    /// almost nothing on purpose — a wall-clock bound that is not flaky is also
    /// not sensitive enough to catch the regression, which is the same
    /// conclusion `testEpochResolvesTheSamePriceKeyAsTheLedgerResolver` reached.
    /// It exists to produce numbers, and it fails only if a read that is
    /// supposed to be bounded turns out not to be.
    func testAgedStoreBaseline() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            environment["PERF_BASELINE"] != nil,
            "Opt-in baseline; set PERF_BASELINE=1 to run."
        )
        let instrumentCount = environment["PERF_INSTRUMENTS"].flatMap(Int.init) ?? 300
        let dayCount = environment["PERF_DAYS"].flatMap(Int.init) ?? 365

        let context = try makeContext()
        let timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        let today = PortfolioCalendar.day(containing: .now, in: timeZone)
        let epochDay = PortfolioCalendar.day(
            containing: today.addingTimeInterval(-Double(dayCount) * 86_400),
            in: timeZone
        )

        let clock = ContinuousClock()
        let instrumentKeys = (0..<instrumentCount).map { "instrument-\($0)" }

        // One price record per instrument, as a live collection has.
        for key in instrumentKeys {
            let record = PriceRecord(key: key, game: .pokemon, printingID: key, variantID: nil)
            _ = record.apply(
                NormalizedPrice(
                    unitMarketPriceUSD: 4.25,
                    currencyCode: "USD",
                    source: .tcgplayer,
                    sourceVariantID: key,
                    sourceUpdatedAt: nil,
                    fetchedAt: .now
                )
            )
            context.insert(record)
        }

        // One check day per instrument per day: the growth `recordSuccessfulCheck`
        // actually produces, and the table nothing prunes.
        //
        // Observations are seeded on a fraction of days instead, because
        // `PriceObservationRules.decide` returns `.unchanged` for a same-value
        // re-check, so the log grows only when a price moves.
        var checkDays = 0
        var observations = 0
        for dayIndex in 0..<dayCount {
            let day = PortfolioCalendar.day(
                containing: epochDay.addingTimeInterval(Double(dayIndex) * 86_400 + 43_200),
                in: timeZone
            )
            for key in instrumentKeys {
                context.insert(
                    PriceCheckDay(
                        instrumentKey: key,
                        portfolioDay: day,
                        lastSuccessfulCheckAt: day.addingTimeInterval(3_600),
                        source: .tcgplayer
                    )
                )
                checkDays += 1
                if dayIndex % 20 == 0 {
                    context.insert(
                        PriceObservation(
                            instrumentKey: key,
                            kind: .marketUpdate,
                            amount: money(4.25 + Double(dayIndex) / 100),
                            source: .tcgplayer,
                            sourceVariantID: key,
                            marketVariantID: nil,
                            effectiveAt: day,
                            receivedAt: day,
                            isSourceStamped: false
                        )
                    )
                    observations += 1
                }
            }
            if dayIndex % 30 == 0 { try context.save() }
        }
        try context.save()

        let coverageDuration = clock.measure {
            _ = PortfolioReplaySnapshotBuilder.coverageIndex(
                context: context,
                from: epochDay,
                through: today,
                timeZone: timeZone
            )
        }
        let indexDuration = clock.measure {
            _ = PriceRefreshDataIndex(context: context)
        }

        print("""

        ── slice 1 baseline (simulator; device numbers will differ) ──
        shape              \(instrumentCount) instruments × \(dayCount) days
        PriceCheckDay      \(checkDays) rows
        PriceObservation   \(observations) rows
        coverageIndex      \(coverageDuration)
        PriceRefreshDataIndex.init  \(indexDuration)
        ─────────────────────────────────────────────────────────────

        """)

        // The one thing worth asserting: the coverage read really is bounded by
        // the window it is given, so a narrower window in R1 can bound its cost.
        let narrow = PortfolioReplaySnapshotBuilder.coverageIndex(
            context: context,
            from: PortfolioCalendar.day(
                containing: today.addingTimeInterval(-7 * 86_400),
                in: timeZone
            ),
            through: today,
            timeZone: timeZone
        )
        let recentDay = PortfolioCalendar.day(
            containing: today.addingTimeInterval(-2 * 86_400),
            in: timeZone
        )
        XCTAssertFalse(
            narrow.checkedInstruments(on: recentDay).isEmpty,
            "a windowed read must still answer for days inside the window"
        )
        XCTAssertTrue(
            narrow.checkedInstruments(on: epochDay).isEmpty,
            "a windowed coverage read must not materialise the whole history"
        )
    }

    private func makeContext() throws -> ModelContext {
        let syncedSchema = Schema([
            CollectedCard.self,
            PriceRecord.self,
            ProductIdentity.self,
            CollectionActivity.self,
            InventoryEvent.self
        ])
        let localSchema = Schema([
            PriceObservation.self,
            PriceCheckDay.self,
            PortfolioDailyClose.self
        ])
        let fullSchema = Schema([
            CollectedCard.self,
            PriceRecord.self,
            ProductIdentity.self,
            CollectionActivity.self,
            InventoryEvent.self,
            PriceObservation.self,
            PriceCheckDay.self,
            PortfolioDailyClose.self
        ])
        let container = try ModelContainer(
            for: fullSchema,
            configurations: [
                ModelConfiguration(
                    "TestSynced",
                    schema: syncedSchema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                ),
                ModelConfiguration(
                    "TestPortfolioLocal",
                    schema: localSchema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
            ]
        )
        self.container = container
        return container.mainContext
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func money(_ dollars: Double) -> Money { Money(rounding: dollars)! }

    private func entry(
        id: UUID = UUID(),
        operationID: UUID = UUID(),
        kind: InventoryEventKind,
        delta: Int,
        at date: Date,
        reversesEventID: UUID? = nil,
        priceReceivedAt: Date? = nil,
        position: String = "position",
        instrument: String = "instrument"
    ) -> LedgerEntry {
        LedgerEntry(
            eventID: id,
            operationID: operationID,
            leg: nil,
            kind: kind,
            occurredAt: date,
            recordedAt: date,
            reversesEventID: reversesEventID,
            collectionKey: position,
            priceStorageKey: instrument,
            deltaQuantity: delta,
            unitPrice: nil,
            priceReceivedAtEvent: priceReceivedAt
        )
    }

    private func observation(
        _ dollars: Double,
        at date: Date,
        instrument: String = "instrument"
    ) -> ObservationEntry {
        ObservationEntry(
            id: UUID(),
            instrumentKey: instrument,
            kind: .marketUpdate,
            amount: money(dollars),
            receivedAt: date
        )
    }

    private func card(
        key: String = "position",
        quantity: Int = 1,
        dateAdded: Date = .now
    ) -> CollectedCard {
        CollectedCard(
            collectionKey: key,
            game: .pokemon,
            providerID: key,
            name: "Portfolio Test Card",
            setName: "Test Set",
            setCode: "TST",
            cardNumber: "1",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: nil,
            variantResolution: .imported,
            quantity: quantity,
            dateAdded: dateAdded
        )
    }

    private func csvEntry(key: String, quantity: Int) -> CollectionCSVEntry {
        CollectionCSVEntry(
            collectionKey: key,
            game: .pokemon,
            providerID: key,
            name: "Portfolio Test Card",
            setName: "Test Set",
            setCode: "TST",
            cardNumber: "1",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: nil,
            importedMarketPriceUSD: nil,
            importedPriceAsOf: nil,
            quantity: quantity,
            dateAdded: Date(timeIntervalSince1970: 500)
        )
    }

    /// CSV import writes through `CollectionStore`, so it inherits every rule
    /// the scanner path enforces rather than carrying its own transcription of
    /// them. The graded guard is the one the second copy had already lost: a
    /// treatment-qualified graded key can describe a *different* slab, so a
    /// legacy/canonical pair must stay ambiguous instead of being merged.
    func testCSVImportInheritsTheStoresGradedMergeRefusal() throws {
        let context = try makeContext()
        let canonicalKey = "graded:magic:slab:variant#treatment=surgefoil"
        let legacyKey = "graded:magic:slab:variant"

        for key in [legacyKey, canonicalKey] {
            let slab = CollectedCard(
                collectionKey: key,
                game: .magic,
                providerID: key,
                name: "Slab",
                setName: "Fixture Set",
                setCode: "FIC",
                cardNumber: "10",
                rarity: nil,
                imageURL: nil,
                thumbnailURL: nil,
                variant: nil,
                variantResolution: .userConfirmed,
                quantity: 1
            )
            slab.itemKindRaw = CollectionItemKind.gradedCard.rawValue
            context.insert(slab)
        }
        try context.save()

        var entry = csvEntry(key: canonicalKey, quantity: 1)
        entry.itemKind = .gradedCard
        entry.magicTreatmentIDsRaw = ["surgefoil"]
        let result = try CollectionCSV.apply(
            CollectionCSVImportPlan(entries: [entry], skippedRows: 0, skippedCSVText: nil),
            to: context
        )

        // Refused, reported, and non-destructive: both slabs still exist and
        // neither absorbed the other's quantity.
        XCTAssertEqual(result.failedRows.map(\.collectionKey), [canonicalKey])
        XCTAssertEqual(result.failedEntries.map(\.collectionKey), [canonicalKey])
        // csvEntry uses its collection key as providerID, so the normalized
        // failed export must carry the canonical key that was refused.
        XCTAssertTrue(
            CollectionCSV.exportFailedEntries(result.failedEntries).text.contains(canonicalKey)
        )
        XCTAssertEqual(result.importedQuantity, 0)
        let rows = try context.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(Set(rows.map(\.collectionKey)), [legacyKey, canonicalKey])
        XCTAssertTrue(rows.allSatisfy { $0.quantity == 1 })
    }

    func testCSVImportMergesLegacyAndCanonicalRowsInsteadOfInsertingAThirdRow() throws {
        let context = try makeContext()
        let legacyKey = "magic:csv-ambiguous#foil"
        let canonicalKey = legacyKey + "#treatment=surgefoil"

        let legacy = CollectedCard(
            collectionKey: legacyKey,
            game: .magic,
            providerID: "csv-ambiguous",
            name: "CSV Magic Card",
            setName: "Fixture Set",
            setCode: "FIC",
            cardNumber: "1",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .foil,
            variantResolution: .userConfirmed,
            quantity: 1
        )
        let canonical = CollectedCard(
            collectionKey: canonicalKey,
            game: .magic,
            providerID: "csv-ambiguous",
            name: "CSV Magic Card",
            setName: "Fixture Set",
            setCode: "FIC",
            cardNumber: "1",
            rarity: nil,
            imageURL: "https://example.com/card.png",
            thumbnailURL: "https://example.com/card-thumb.png",
            variant: .foil,
            variantResolution: .userConfirmed,
            quantity: 1,
            magicTreatments: [.surgeFoil]
        )
        context.insert(legacy)
        context.insert(canonical)
        try context.save()

        let entry = CollectionCSVEntry(
            collectionKey: legacyKey,
            game: .magic,
            providerID: "csv-ambiguous",
            name: "CSV Magic Card",
            setName: "Fixture Set",
            setCode: "FIC",
            cardNumber: "1",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .foil,
            importedMarketPriceUSD: nil,
            importedPriceAsOf: nil,
            quantity: 1,
            dateAdded: Date(timeIntervalSince1970: 500)
        )
        let result = try CollectionCSV.apply(
            CollectionCSVImportPlan(entries: [entry], skippedRows: 0, skippedCSVText: nil),
            to: context
        )

        XCTAssertEqual(result.insertedEntries, 0)
        XCTAssertEqual(result.mergedEntries, 1)
        XCTAssertEqual(result.failedRows.count, 0)
        let rows = try context.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.map(\.collectionKey), [canonicalKey])
        XCTAssertEqual(rows.first?.quantity, 3)
        XCTAssertEqual(rows.first?.imageURL, "https://example.com/card.png")
    }

    func testCSVImportCommitsAndReportsDurableBatches() throws {
        let context = try makeContext()
        let plan = CollectionCSVImportPlan(
            entries: [
                csvEntry(key: "batch-1", quantity: 1),
                csvEntry(key: "batch-2", quantity: 1),
                csvEntry(key: "batch-3", quantity: 1)
            ],
            skippedRows: 0,
            skippedCSVText: nil
        )
        let recorder = CSVProgressRecorder()

        let result = try CollectionCSV.apply(
            plan,
            to: context,
            batchSize: 2,
            progress: { completed, total in
                recorder.append(completed, total)
            }
        )

        XCTAssertEqual(result.insertedEntries, 3)
        XCTAssertEqual(recorder.values().map(\.0), [0, 2, 3])
        XCTAssertEqual(recorder.values().map(\.1), [3, 3, 3])
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectedCard>()).count, 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<InventoryEvent>()).count, 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectionActivity>()).count, 3)
    }

    func testReimportingACertifiedSlabDoesNotChangeQuantityOrWriteAnEvent() throws {
        let context = try makeContext()
        let entry = CollectionCSVEntry(
            collectionKey: "graded:pokemon:printing:PSA|10:cert:ABC123",
            game: .pokemon,
            providerID: "printing",
            name: "Certified Test Card",
            setName: "Test Set",
            setCode: "TST",
            cardNumber: "1",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: nil,
            importedMarketPriceUSD: nil,
            importedPriceAsOf: nil,
            quantity: 1,
            dateAdded: Date(timeIntervalSince1970: 500),
            itemKind: .gradedCard,
            gradingCompany: .psa,
            grade: CardGrade(value: "10"),
            certificationNumber: "ABC123"
        )
        let plan = CollectionCSVImportPlan(
            entries: [entry],
            skippedRows: 0,
            skippedCSVText: nil
        )

        let first = try CollectionCSV.apply(plan, to: context)
        let second = try CollectionCSV.apply(plan, to: context)

        XCTAssertEqual(first.insertedEntries, 1)
        XCTAssertEqual(second.mergedEntries, 1)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CollectedCard>()).first?.quantity,
            1
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<InventoryEvent>()).count,
            1,
            "a repeated certified import is metadata refresh, not ownership"
        )
    }

    func testImportLeavesAPreexistingOverQuantityCertifiedRowAlone() throws {
        let context = try makeContext()
        let key = "graded:pokemon:printing:PSA|10:cert:ABC123"
        let existing = card(key: key, quantity: 3)
        existing.itemKindRaw = CollectionItemKind.gradedCard.rawValue
        existing.gradingCompanyRaw = GradingCompany.psa.rawValue
        existing.gradeRaw = "10"
        existing.certificationNumber = "ABC123"
        context.insert(existing)
        try context.save()

        let entry = CollectionCSVEntry(
            collectionKey: key,
            game: .pokemon,
            providerID: "printing",
            name: "Certified Test Card",
            setName: "Test Set",
            setCode: "TST",
            cardNumber: "1",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: nil,
            importedMarketPriceUSD: nil,
            importedPriceAsOf: nil,
            quantity: 1,
            dateAdded: Date(timeIntervalSince1970: 500),
            itemKind: .gradedCard,
            gradingCompany: .psa,
            grade: CardGrade(value: "10"),
            certificationNumber: "ABC123"
        )
        let plan = CollectionCSVImportPlan(
            entries: [entry],
            skippedRows: 0,
            skippedCSVText: nil
        )

        let beforeEvents = try context.fetch(FetchDescriptor<InventoryEvent>()).count
        _ = try CollectionCSV.apply(plan, to: context)

        XCTAssertEqual(existing.quantity, 3)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<InventoryEvent>()).count,
            beforeEvents,
            "a pre-existing quantity defect is diagnostic, not silently repaired"
        )
    }

    func testImportDoesNotRewriteQuantityForARowWithAnEmptyCertificateString() throws {
        let context = try makeContext()
        let key = "graded:pokemon:printing:PSA|10"
        let existing = card(key: key, quantity: 3)
        existing.itemKindRaw = CollectionItemKind.gradedCard.rawValue
        existing.gradingCompanyRaw = GradingCompany.psa.rawValue
        existing.gradeRaw = "10"
        existing.certificationNumber = ""
        context.insert(existing)
        try context.save()

        let entry = CollectionCSVEntry(
            collectionKey: key,
            game: .pokemon,
            providerID: "printing",
            name: "Unnumbered Slab",
            setName: "Test Set",
            setCode: "TST",
            cardNumber: "1",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: nil,
            importedMarketPriceUSD: nil,
            importedPriceAsOf: nil,
            quantity: 1,
            dateAdded: Date(timeIntervalSince1970: 500),
            itemKind: .gradedCard,
            gradingCompany: .psa,
            grade: CardGrade(value: "10"),
            certificationNumber: ""
        )

        _ = try CollectionCSV.apply(
            CollectionCSVImportPlan(entries: [entry], skippedRows: 0, skippedCSVText: nil),
            to: context
        )

        XCTAssertEqual(existing.quantity, 3)
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<InventoryEvent>()).isEmpty,
            "an empty certificate is still a non-aggregating row and cannot create an un-evented quantity change"
        )
    }

    func testCSVRoundTripKeepsDistinctCertificatesApart() throws {
        func slab(certificationNumber: String) -> CollectedCard {
            let card = CollectedCard(
                collectionKey: "source-(certificationNumber)",
                game: .pokemon,
                providerID: "printing",
                name: "Certified Test Card",
                setName: "Test Set",
                setCode: "TST",
                cardNumber: "1",
                rarity: nil,
                imageURL: nil,
                thumbnailURL: nil,
                variant: nil,
                variantResolution: .imported
            )
            card.itemKindRaw = CollectionItemKind.gradedCard.rawValue
            card.gradingCompanyRaw = GradingCompany.psa.rawValue
            card.gradeRaw = "10"
            card.certificationNumber = certificationNumber
            return card
        }

        let exported = CollectionCSV.export([
            slab(certificationNumber: "ABC123"),
            slab(certificationNumber: "XYZ789")
        ])
        let plan = try CollectionCSV.parse(Data(exported.text.utf8))
        let context = try makeContext()

        let result = try CollectionCSV.apply(plan, to: context)
        let rows = try context.fetch(FetchDescriptor<CollectedCard>())

        XCTAssertEqual(result.insertedEntries, 2)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.compactMap(\.certificationNumber)), Set(["ABC123", "XYZ789"]))
        XCTAssertEqual(rows.map(\.quantity), [1, 1])
        XCTAssertEqual(Set(rows.map(\.collectionKey)).count, 2)
    }

    func testCSVExportAppendsCatalogProviderWithoutReorderingOriginalColumns() throws {
        let exportedCard = card(key: "stable-provider")
        exportedCard.catalogProviderID = "catalog-provider"
        let lines = CollectionCSV.export([exportedCard]).text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        let headers = lines[0].split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        let values = lines[1].split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)

        XCTAssertEqual(Array(headers.prefix(3)), ["game", "provider_id", "card_name"])
        XCTAssertEqual(headers.last, "catalog_provider_id")
        XCTAssertEqual(Array(values.prefix(3)), ["pokemon", "stable-provider", "Portfolio Test Card"])
        XCTAssertEqual(values.last, "catalog-provider")

        let plan = try CollectionCSV.parse(Data(CollectionCSV.export([exportedCard]).text.utf8))
        XCTAssertEqual(plan.entries.first?.providerID, "stable-provider")
        XCTAssertEqual(plan.entries.first?.catalogProviderID, "catalog-provider")
    }

    func testDuplicateGradedRowsMergeWhenOneHasTheBoundMarketVariant() throws {
        let context = try makeContext()
        let key = CollectedCard.gradedCollectionKey(
            game: .pokemon,
            underlyingPrintingID: "sv08.5-074",
            variantUUID: "slab"
        )
        let unbound = card(key: key, dateAdded: Date(timeIntervalSince1970: 100))
        unbound.providerID = "sv08.5-074"
        unbound.itemKindRaw = CollectionItemKind.gradedCard.rawValue
        unbound.gradingCompanyRaw = GradingCompany.psa.rawValue
        unbound.gradeRaw = "10"
        unbound.gradeLabel = "Gem Mint"

        let bound = card(key: key, dateAdded: Date(timeIntervalSince1970: 200))
        bound.providerID = unbound.providerID
        bound.itemKindRaw = CollectionItemKind.gradedCard.rawValue
        bound.gradingCompanyRaw = unbound.gradingCompanyRaw
        bound.gradeRaw = unbound.gradeRaw
        bound.gradeLabel = unbound.gradeLabel
        bound.justTCGCardID = "vendor-card"
        bound.justTCGVariantID = "vendor-variant"
        bound.justTCGAPIVersion = "v2"
        let unboundPriceKey = unbound.priceKey
        let boundPriceKey = bound.priceKey
        context.insert(unbound)
        context.insert(bound)
        try context.save()

        let merged = try XCTUnwrap(
            try CollectionStore(context: context).card(
                forAnyKey: key,
                resolveLegacyIdentity: false
            )
        )
        try context.save()

        XCTAssertEqual(merged.quantity, 2)
        XCTAssertEqual(merged.priceKey, boundPriceKey)
        XCTAssertTrue(merged.legacyPriceKeys.contains(unboundPriceKey))
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectedCard>()).count, 1)
    }

    func testUnboundPriceIdentityPromotionMovesCompleteLineage() throws {
        let context = try makeContext()
        let epoch = Date(timeIntervalSince1970: 1_800_000_000)
        let card = CollectedCard(
            collectionKey: CollectedCard.scannedGradedCollectionKey(
                game: .pokemon,
                underlyingPrintingID: "sv08.5-074",
                company: .psa,
                grade: CardGrade(value: "10", label: "Gem Mint", qualifier: nil),
                certificationNumber: "CERT-1"
            ),
            game: .pokemon,
            providerID: "sv08.5-074",
            name: "Lineage Fixture",
            setName: "Fixture Set",
            setCode: "FIC",
            cardNumber: "074",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: nil,
            variantResolution: .imported
        )
        card.itemKindRaw = CollectionItemKind.gradedCard.rawValue
        card.gradingCompanyRaw = GradingCompany.psa.rawValue
        card.gradeRaw = "10"
        card.gradeLabel = "Gem Mint"
        card.certificationNumber = "CERT-1"
        context.insert(card)

        let oldKey = card.priceKey
        let oldRecord = PriceRecord(
            key: oldKey,
            game: .pokemon,
            printingID: card.priceStorageID,
            variantID: card.variantID
        )
        _ = oldRecord.applyImported(
            amount: 12,
            sourceUpdatedAt: epoch,
            importedAt: epoch.addingTimeInterval(60)
        )
        context.insert(oldRecord)
        context.insert(
            PriceObservation(
                instrumentKey: oldKey,
                kind: .marketUpdate,
                amount: money(12),
                currencyCode: "USD",
                source: .importedCSV,
                sourceVariantID: oldKey,
                marketVariantID: nil,
                effectiveAt: epoch,
                receivedAt: epoch.addingTimeInterval(60),
                isSourceStamped: true
            )
        )
        context.insert(
            PriceCheckDay(
                instrumentKey: oldKey,
                portfolioDay: epoch,
                lastSuccessfulCheckAt: epoch.addingTimeInterval(60),
                source: .importedCSV
            )
        )
        let operationID = UUID()
        context.insert(
            InventoryEvent(
                operationID: operationID,
                leg: nil,
                kind: .recordExisting,
                source: .csvImport,
                collectionKey: card.collectionKey,
                priceStorageKey: oldKey,
                deltaQuantity: 1,
                occurredAt: epoch,
                valuation: .unpriced
            )
        )
        try context.save()

        try PriceIdentityLineageMigration.promoteUnboundPriceIdentity(
            for: card,
            toMarketVariantID: "graded-market-1",
            apiVersion: "v2",
            in: context
        )
        card.justTCGCardID = "graded-card-1"
        card.justTCGVariantID = "graded-market-1"
        card.justTCGAPIVersion = "v2"
        try context.save()

        let newKey = card.priceKey
        XCTAssertNotEqual(oldKey, newKey)
        XCTAssertNil(
            try context.fetch(
                FetchDescriptor<PriceRecord>(predicate: #Predicate { $0.key == oldKey })
            ).first
        )
        XCTAssertEqual(
            try context.fetch(
                FetchDescriptor<PriceRecord>(predicate: #Predicate { $0.key == newKey })
            ).count,
            1
        )
        XCTAssertFalse(
            try context.fetch(FetchDescriptor<PriceObservation>())
                .contains { $0.instrumentKey == oldKey }
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<PriceObservation>())
                .contains { $0.instrumentKey == newKey }
        )
        XCTAssertFalse(
            try context.fetch(FetchDescriptor<PriceCheckDay>())
                .contains { $0.instrumentKey == oldKey }
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<PriceCheckDay>())
                .contains { $0.instrumentKey == newKey }
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<InventoryEvent>())
                .allSatisfy { $0.priceStorageKey == newKey }
        )
    }

    func testDuplicateSealedRowsMergeWhenOneHasTheBoundMarketVariant() throws {
        let context = try makeContext()
        let key = CollectedCard.sealedCollectionKey(
            game: .pokemon,
            productUUID: "product-1",
            variantUUID: "variant-1"
        )
        let unbound = card(key: key, dateAdded: Date(timeIntervalSince1970: 100))
        unbound.providerID = "sealed-source"
        unbound.itemKindRaw = CollectionItemKind.sealedProduct.rawValue

        let bound = card(key: key, dateAdded: Date(timeIntervalSince1970: 200))
        bound.providerID = unbound.providerID
        bound.itemKindRaw = unbound.itemKindRaw
        bound.justTCGCardID = "vendor-product"
        bound.justTCGVariantID = "vendor-variant"
        bound.justTCGAPIVersion = "v1"
        let boundPriceKey = bound.priceKey
        context.insert(unbound)
        context.insert(bound)
        try context.save()

        let merged = try XCTUnwrap(
            try CollectionStore(context: context).card(
                forAnyKey: key,
                resolveLegacyIdentity: false
            )
        )
        try context.save()

        XCTAssertEqual(merged.quantity, 2)
        XCTAssertEqual(merged.priceKey, boundPriceKey)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectedCard>()).count, 1)
    }

    private func waitForRecomputeToFinish(
        _ engine: PortfolioEngine,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<10_000 {
            guard engine.isRecomputing else { return }
            await Task.yield()
        }
        XCTFail("Portfolio recompute did not finish", file: file, line: line)
    }

    private func waitForComputationGate(
        _ gate: PortfolioComputationGate,
        count: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<10_000 {
            if await gate.waitingCount() == count { return }
            await Task.yield()
        }
        XCTFail("Expected (count) computation(s) waiting at the gate", file: file, line: line)
    }

    // MARK: - Recompute presentation and coalescing

    func testRecomputeRetainsTheLastUsableSummaryWhileUpdating() async throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        context.insert(card(dateAdded: date))
        try context.save()

        let engine = PortfolioEngine()
        await engine.recomputeAndWait(context: context, now: date)
        let retainedSummary = try XCTUnwrap(engine.summary)

        engine.recompute(context: context, now: date.addingTimeInterval(60))

        XCTAssertEqual(engine.summary, retainedSummary)
        XCTAssertTrue(engine.isRecomputing)
        await waitForRecomputeToFinish(engine)
        XCTAssertFalse(engine.isRecomputing)
    }

    func testColdStartStillLeavesSummaryUnavailableUntilItsFirstReplayFinishes() async throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        context.insert(card(dateAdded: date))
        try context.save()

        let engine = PortfolioEngine()
        engine.recompute(context: context, now: date)

        XCTAssertNil(engine.summary)
        XCTAssertTrue(engine.isRecomputing)
        await waitForRecomputeToFinish(engine)
        XCTAssertNotNil(engine.summary)
        XCTAssertFalse(engine.isRecomputing)
    }

    func testRapidRecomputesCoalesceToOneTrailingReplay() async throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        context.insert(card(dateAdded: date))
        try context.save()

        let engine = PortfolioEngine()
        await engine.recomputeAndWait(context: context, now: date)

        engine.recompute(context: context, now: date.addingTimeInterval(60))
        engine.recompute(context: context, now: date.addingTimeInterval(120))
        engine.recompute(context: context, now: date.addingTimeInterval(180))

        await waitForRecomputeToFinish(engine)

        // One initial replay established the retained value; the three rapid
        // requests above become the active pass plus one trailing pass.
        XCTAssertEqual(engine.inputRevision, 3)
    }

    func testCancelledComputationRunsTheNewestPendingReplay() async throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        context.insert(card(dateAdded: date))
        try context.save()

        let gate = PortfolioComputationGate()
        let engine = PortfolioEngine(
            computationProvider: { container, epoch, through, timeZoneIdentifier in
                await gate.wait()
                let actor = PortfolioComputationActor(modelContainer: container)
                return await actor.compute(
                    epoch: epoch,
                    through: through,
                    timeZoneIdentifier: timeZoneIdentifier
                )
            }
        )

        engine.recompute(context: context, now: date)
        await waitForComputationGate(gate, count: 1)

        engine.recompute(context: context, now: date.addingTimeInterval(60))
        engine.cancelRecompute()
        await gate.release()
        await waitForComputationGate(gate, count: 1)
        await gate.release()

        await waitForRecomputeToFinish(engine)
        XCTAssertFalse(engine.isRecomputing)
        XCTAssertNotNil(engine.summary)
        XCTAssertEqual(engine.inputRevision, 1)
    }

    func testRecomputeAndWaitIncludesTheTrailingReplayItQueues() async throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        context.insert(card(dateAdded: date))
        try context.save()

        let engine = PortfolioEngine()
        await engine.recomputeAndWait(context: context, now: date)

        engine.recompute(context: context, now: date.addingTimeInterval(60))
        await engine.recomputeAndWait(context: context, now: date.addingTimeInterval(120))

        XCTAssertFalse(engine.isRecomputing)
        // The initial result establishes the retained value. The direct call
        // starts pass two; recomputeAndWait queues and waits for pass three.
        XCTAssertEqual(engine.inputRevision, 3)
    }

    func testHoldingSnapshotPreservesLocalArtworkAndCatalogFallback() throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let ownedCard = card(dateAdded: date)
        ownedCard.userArtworkFilename = "custom-artwork.image"
        ownedCard.imageURL = "https://images.example.test/cards/portfolio-card"
        ownedCard.thumbnailURL = "https://images.example.test/cards/portfolio-card/low.png"
        context.insert(ownedCard)
        try context.save()

        let computation = PortfolioReplaySnapshotBuilder.compute(
            context: context,
            epoch: date,
            through: date,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let holding = try XCTUnwrap(computation.holdings.first)

        XCTAssertEqual(holding.userArtworkFilename, "custom-artwork.image")
        XCTAssertEqual(holding.artworkURL, URL(string: "https://images.example.test/cards/portfolio-card/high.png"))
        XCTAssertEqual(holding.artworkFallbackURL, URL(string: "https://images.example.test/cards/portfolio-card/low.png"))
    }

    func testHoldingSnapshotDoesNotRetryAnIdenticalDirectArtworkURL() throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let ownedCard = card(dateAdded: date)
        let directArtworkURL = "https://images.example.test/cards/portfolio-card.jpg"
        ownedCard.imageURL = directArtworkURL
        ownedCard.thumbnailURL = directArtworkURL
        context.insert(ownedCard)
        try context.save()

        let computation = PortfolioReplaySnapshotBuilder.compute(
            context: context,
            epoch: date,
            through: date,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let holding = try XCTUnwrap(computation.holdings.first)

        XCTAssertEqual(holding.artworkURL, URL(string: directArtworkURL))
        XCTAssertNil(holding.artworkFallbackURL)
    }

    // MARK: - Duplicate physical rows for one logical position
    //
    // Two devices adding the same card offline each pass their own local
    // uniqueness check, so one `collectionKey` legitimately arrives as two
    // stored rows. Every part of the app that answers "how many do I own" has
    // to answer from the sum.

    func testDuplicatePhysicalRowsProjectToOneSummedPosition() throws {
        let context = try makeContext()
        context.insert(card(key: "dupe", quantity: 1, dateAdded: Date(timeIntervalSince1970: 100)))
        context.insert(card(key: "dupe", quantity: 2, dateAdded: Date(timeIntervalSince1970: 900)))
        try context.save()

        let ledger = InventoryLedger(context: context)
        let cards = try context.fetch(FetchDescriptor<CollectedCard>())
        let projection = LogicalCollection.project(cards: cards, ledger: ledger)

        XCTAssertEqual(projection.positions.count, 1)
        XCTAssertEqual(projection.byKey["dupe"]?.quantity, 3)
        XCTAssertEqual(projection.byKey["dupe"]?.physicalRowCount, 2)
        // The oldest acquisition represents the position; the newest is what
        // "recently added" should mean for it.
        XCTAssertEqual(
            projection.byKey["dupe"]?.representative.dateAdded,
            Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(projection.byKey["dupe"]?.dateAdded, Date(timeIntervalSince1970: 900))
    }

    func testDuplicateRowsDoNotMoveTheValuedPortfolio() {
        let first = card(key: "dupe", quantity: 1)
        let second = card(key: "dupe", quantity: 2)
        let merged = LogicalCollection.project(cards: [first, second]) { _ in "instrument" }
        let single = LogicalCollection.project(cards: [card(key: "dupe", quantity: 3)]) { _ in "instrument" }
        let valuations = InstrumentValuationIndex(
            byInstrument: ["instrument": InventoryValuation(
                unitPrice: money(10), source: .justTCG, effectiveAt: nil,
                receivedAt: nil, observationID: nil
            )]
        )

        let mergedValue = PortfolioEngine.currentValuation(
            projection: merged,
            valuations: valuations,
            otherCurrencyInstruments: []
        )
        let singleValue = PortfolioEngine.currentValuation(
            projection: single,
            valuations: valuations,
            otherCurrencyInstruments: []
        )

        XCTAssertEqual(mergedValue.value, singleValue.value)
        XCTAssertEqual(mergedValue.value, money(30))
        XCTAssertEqual(mergedValue.unpricedCount, singleValue.unpricedCount)
        XCTAssertEqual(mergedValue.otherCurrencyCount, singleValue.otherCurrencyCount)
    }

    func testMigrationBaselinesDuplicateRowsAsOneEventWithTheSummedQuantity() throws {
        // The bug this exists to stop: iterating physical rows gave both rows
        // the same deterministic baseline id, so one was deduplicated away and
        // the ledger opened at 1 instead of 3 — or, with differing quantities,
        // collided as an idempotency conflict and opened at neither.
        let context = try makeContext()
        context.insert(card(key: "dupe", quantity: 1, dateAdded: Date(timeIntervalSince1970: 100)))
        context.insert(card(key: "dupe", quantity: 2, dateAdded: Date(timeIntervalSince1970: 900)))
        try context.save()

        let defaults = UserDefaults(suiteName: "PortfolioEpochTests.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        try PortfolioEpoch.establishIfNeeded(
            context: context,
            defaults: defaults,
            isCloudSyncing: false
        )

        let ledger = InventoryLedger(context: context)
        let events = ledger.allEvents()

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .initialBalance)
        XCTAssertEqual(events.first?.deltaQuantity, 3)

        // And the ledger now agrees with the collection, which is the whole
        // point of the assertion this feature ships.
        let cards = try context.fetch(FetchDescriptor<CollectedCard>())
        let projection = LogicalCollection.project(cards: cards, ledger: ledger)
        let defects = PortfolioEngine.reconcile(
            projection: projection,
            events: events.map(PortfolioEngine.entry(from:))
        )
        XCTAssertEqual(defects, [])
    }

    func testCSVImportAgainstDuplicateRowsMergesOnceInsteadOfTrapping() throws {
        // `Dictionary(uniqueKeysWithValues:)` traps on a duplicate key, so this
        // previously crashed rather than importing.
        let context = try makeContext()
        context.insert(card(key: "dupe", quantity: 1, dateAdded: Date(timeIntervalSince1970: 100)))
        context.insert(card(key: "dupe", quantity: 2, dateAdded: Date(timeIntervalSince1970: 900)))
        try context.save()

        let plan = CollectionCSVImportPlan(
            entries: [csvEntry(key: "dupe", quantity: 4)],
            skippedRows: 0,
            skippedCSVText: nil
        )
        let result = try CollectionCSV.apply(plan, to: context)

        XCTAssertEqual(result.mergedEntries, 1)
        XCTAssertEqual(result.insertedEntries, 0)

        let cards = try context.fetch(FetchDescriptor<CollectedCard>())
        let projection = LogicalCollection.project(
            cards: cards,
            ledger: InventoryLedger(context: context)
        )
        // Three owned plus four imported, counted exactly once.
        XCTAssertEqual(projection.byKey["dupe"]?.quantity, 7)
        XCTAssertEqual(projection.positions.count, 1)
    }

    // MARK: - Undo semantics

    func testSamePeriodAddAndUndoCollapseForAttribution() {
        let boundary = Date(timeIntervalSince1970: 2_000_000_000)
        let originalID = UUID()
        let events = [
            entry(id: originalID, kind: .acquire, delta: 1, at: boundary.addingTimeInterval(60)),
            entry(kind: .acquire, delta: -1, at: boundary.addingTimeInterval(180), reversesEventID: originalID)
        ]
        let observations = [
            observation(100, at: boundary.addingTimeInterval(-60)),
            observation(120, at: boundary.addingTimeInterval(120))
        ]

        let result = PortfolioClose.attribute(
            events: events,
            observations: observations,
            boundary: boundary,
            now: boundary.addingTimeInterval(300),
            currentValue: .zero
        )

        XCTAssertEqual(result.added, .zero)
        XCTAssertEqual(result.market, .zero)
        XCTAssertEqual(result.corrections, .zero)
        XCTAssertEqual(result.unexplained, .zero)
    }

    func testSamePeriodRemoveAndUndoBehaveAsThoughTemporaryRemovalNeverHappened() {
        let boundary = Date(timeIntervalSince1970: 2_000_000_000)
        let removalID = UUID()
        let events = [
            entry(kind: .initialBalance, delta: 1, at: boundary.addingTimeInterval(-120)),
            entry(id: removalID, kind: .dispose, delta: -1, at: boundary.addingTimeInterval(60)),
            entry(kind: .dispose, delta: 1, at: boundary.addingTimeInterval(180), reversesEventID: removalID)
        ]
        let observations = [
            observation(100, at: boundary.addingTimeInterval(-60)),
            observation(120, at: boundary.addingTimeInterval(120))
        ]

        let result = PortfolioClose.attribute(
            events: events,
            observations: observations,
            boundary: boundary,
            now: boundary.addingTimeInterval(300),
            currentValue: money(120)
        )

        XCTAssertEqual(result.removed, .zero)
        XCTAssertEqual(result.corrections, .zero)
        XCTAssertEqual(result.market, money(20))
        XCTAssertEqual(result.unexplained, .zero)
    }

    func testReversingPublishedOperationIsCurrentPeriodCorrection() {
        let boundary = Date(timeIntervalSince1970: 2_000_000_000)
        let originalID = UUID()
        let events = [
            entry(id: originalID, kind: .acquire, delta: 1, at: boundary.addingTimeInterval(-120)),
            entry(kind: .acquire, delta: -1, at: boundary.addingTimeInterval(120), reversesEventID: originalID)
        ]
        let observations = [
            observation(100, at: boundary.addingTimeInterval(-60)),
            observation(120, at: boundary.addingTimeInterval(60))
        ]

        let result = PortfolioClose.attribute(
            events: events,
            observations: observations,
            boundary: boundary,
            now: boundary.addingTimeInterval(300),
            currentValue: .zero
        )

        XCTAssertEqual(result.added, .zero)
        XCTAssertEqual(result.market, money(20))
        XCTAssertEqual(result.corrections, money(-120))
        XCTAssertEqual(result.unexplained, .zero)
    }

    // MARK: - Ordering

    func testMixedSameTimestampUsesOldBasisThenObservationThenNewBasis() {
        let boundary = Date(timeIntervalSince1970: 2_000_000_000)
        let instant = boundary.addingTimeInterval(60)
        let old = entry(
            kind: .acquire, delta: 1, at: instant,
            priceReceivedAt: boundary.addingTimeInterval(-60),
            position: "old"
        )
        let new = entry(
            kind: .acquire, delta: 1, at: instant,
            priceReceivedAt: instant,
            position: "new"
        )
        let observations = [
            observation(10, at: boundary.addingTimeInterval(-60)),
            observation(20, at: instant)
        ]

        let result = PortfolioClose.attribute(
            events: [new, old],
            observations: observations,
            boundary: boundary,
            now: instant.addingTimeInterval(60),
            currentValue: money(40)
        )

        XCTAssertEqual(result.added, money(30))
        XCTAssertEqual(result.market, money(10))
        XCTAssertEqual(result.unexplained, .zero)
    }

    func testQuantityAdjustIsCorrectionNotAdded() {
        let boundary = Date(timeIntervalSince1970: 2_000_000_000)
        let result = PortfolioClose.attribute(
            events: [entry(kind: .quantityAdjust, delta: 2, at: boundary.addingTimeInterval(60))],
            observations: [observation(15, at: boundary.addingTimeInterval(-60))],
            boundary: boundary,
            now: boundary.addingTimeInterval(120),
            currentValue: money(30)
        )
        XCTAssertEqual(result.added, .zero)
        XCTAssertEqual(result.corrections, money(30))
        XCTAssertEqual(result.unexplained, .zero)
    }

    // MARK: - Local knowledge and publication

    func testFailedEpochSaveDoesNotMarkTrackingEstablishedAndRetries() throws {
        enum ExpectedFailure: Error { case save }

        let context = try makeContext()
        let defaultsName = #function
        let defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        context.insert(card(dateAdded: now.addingTimeInterval(-86_400)))
        try context.save()

        XCTAssertThrowsError(
            try PortfolioEpoch.establishIfNeeded(
                context: context,
                defaults: defaults,
                at: now,
                isCloudSyncing: false,
                save: { _ in throw ExpectedFailure.save }
            )
        )
        XCTAssertNil(PortfolioEpoch.startedAt(defaults: defaults))
        XCTAssertTrue(InventoryLedger(context: context).allEvents().isEmpty)

        XCTAssertEqual(
            try PortfolioEpoch.establishIfNeeded(
                context: context,
                defaults: defaults,
                at: now,
                isCloudSyncing: false
            ),
            now
        )
        XCTAssertEqual(InventoryLedger(context: context).allEvents().count, 1)
    }

    func testBackfillUsesWhenThisDeviceLearnedSyncedPrice() throws {
        let context = try makeContext()
        let remoteFetch = Date(timeIntervalSince1970: 1_900_000_000)
        let localLearned = remoteFetch.addingTimeInterval(7 * 86_400)
        let record = PriceRecord(key: "instrument", game: .pokemon, printingID: "p", variantID: nil)
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 42,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "v",
                sourceUpdatedAt: remoteFetch,
                fetchedAt: remoteFetch
            )
        )
        context.insert(record)
        try context.save()

        XCTAssertEqual(
            PriceObservationLog(context: context).backfillFromRecords(receivedAt: localLearned),
            1
        )
        XCTAssertEqual(
            PriceObservationLog(context: context).newestObservation(instrumentKey: "instrument")?.receivedAt,
            localLearned
        )
    }

    func testBackfillReusesSuppliedObservationsWithoutInsertingADuplicate() throws {
        let context = try makeContext()
        let record = PriceRecord(key: "instrument", game: .pokemon, printingID: "p", variantID: nil)
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 42,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "v",
                sourceUpdatedAt: nil,
                fetchedAt: Date(timeIntervalSince1970: 100)
            )
        )
        context.insert(record)

        let supplied = PriceObservation(
            instrumentKey: "instrument",
            kind: .marketUpdate,
            amount: money(42),
            currencyCode: "USD",
            source: .justTCG,
            sourceVariantID: "v",
            marketVariantID: nil,
            effectiveAt: Date(timeIntervalSince1970: 100),
            receivedAt: Date(timeIntervalSince1970: 200),
            isSourceStamped: false
        )

        XCTAssertEqual(
            PriceObservationLog(context: context).backfillFromRecords(
                existingObservations: [supplied]
            ),
            0
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<PriceObservation>()).isEmpty,
            "the supplied snapshot is authoritative for this pass"
        )
    }

    func testBackfillDoesNotSeedWhenTheObservationLogCannotBeRead() throws {
        let context = try makeContext()
        let record = PriceRecord(key: "instrument", game: .pokemon, printingID: "p", variantID: nil)
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 42,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "v",
                sourceUpdatedAt: nil,
                fetchedAt: Date(timeIntervalSince1970: 100)
            )
        )
        context.insert(record)

        enum ObservationReadError: Error { case unavailable }
        XCTAssertEqual(
            PriceObservationLog(context: context).backfillFromRecordsForTesting {
                throw ObservationReadError.unavailable
            },
            0
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<PriceObservation>()).isEmpty,
            "an unreadable observation table is not an empty baseline"
        )
    }

    func testSyncedPriceRecordChangeBecomesLocalKnowledgeAtReconciliationTime() throws {
        let context = try makeContext()
        let remoteFetch = Date(timeIntervalSince1970: 1_900_000_000)
        let localLearned = remoteFetch.addingTimeInterval(7 * 86_400)
        let record = PriceRecord(key: "instrument", game: .pokemon, printingID: "p", variantID: nil)
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 20,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "remote-v2",
                sourceUpdatedAt: remoteFetch,
                fetchedAt: remoteFetch
            )
        )
        context.insert(record)
        context.insert(
            PriceObservation(
                instrumentKey: "instrument",
                kind: .marketUpdate,
                amount: money(10),
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "remote-v1",
                marketVariantID: nil,
                effectiveAt: remoteFetch.addingTimeInterval(-120),
                receivedAt: remoteFetch.addingTimeInterval(-60),
                isSourceStamped: true
            )
        )
        try context.save()

        let rows = PriceObservationLog(context: context)
            .reconcileSyncedRecordsAndReturnObservations(learnedAt: localLearned)
        let newest = try XCTUnwrap(
            rows.filter { $0.instrumentKey == "instrument" }
                .max(by: { $0.receivedAt < $1.receivedAt })
        )
        XCTAssertEqual(newest.amount, money(20))
        XCTAssertEqual(newest.receivedAt, localLearned)
        XCTAssertEqual(newest.effectiveAt, remoteFetch)
    }

    func testOutOfOrderSyncedPriceDoesNotOverwriteNewerLocalKnowledge() throws {
        let context = try makeContext()
        let newerKnowledge = Date(timeIntervalSince1970: 2_000)
        let staleRemoteFetch = Date(timeIntervalSince1970: 1_000)
        let record = PriceRecord(key: "instrument", game: .pokemon, printingID: "p", variantID: nil)
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 10,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "stale",
                sourceUpdatedAt: staleRemoteFetch,
                fetchedAt: staleRemoteFetch
            )
        )
        context.insert(record)
        let existing = PriceObservation(
            instrumentKey: "instrument",
            kind: .marketUpdate,
            amount: money(20),
            currencyCode: "USD",
            source: .justTCG,
            sourceVariantID: "newer",
            marketVariantID: nil,
            effectiveAt: newerKnowledge,
            receivedAt: newerKnowledge,
            isSourceStamped: true
        )
        context.insert(existing)
        try context.save()

        let rows = PriceObservationLog(context: context)
            .reconcileSyncedRecordsAndReturnObservations(
                learnedAt: newerKnowledge.addingTimeInterval(60)
            )
        XCTAssertEqual(rows.filter { $0.instrumentKey == "instrument" }.count, 1)
        XCTAssertEqual(rows.first?.amount, money(20))
    }

    func testNewerSourceClockIsAcceptedEvenWhenItsReceiptIsOlderThanLocalKnowledge() throws {
        let context = try makeContext()
        let previousSourceClock = Date(timeIntervalSince1970: 1_000)
        let localReceipt = Date(timeIntervalSince1970: 2_000)
        let newerSourceClock = Date(timeIntervalSince1970: 1_500)
        let record = PriceRecord(key: "instrument", game: .pokemon, printingID: "p", variantID: nil)
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 30,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "newer",
                sourceUpdatedAt: newerSourceClock,
                fetchedAt: newerSourceClock
            )
        )
        context.insert(record)
        context.insert(
            PriceObservation(
                instrumentKey: "instrument",
                kind: .marketUpdate,
                amount: money(20),
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "older",
                marketVariantID: nil,
                effectiveAt: previousSourceClock,
                receivedAt: localReceipt,
                isSourceStamped: true
            )
        )
        try context.save()

        let rows = PriceObservationLog(context: context)
            .reconcileSyncedRecordsAndReturnObservations(
                learnedAt: localReceipt.addingTimeInterval(60)
            )
        let instrumentRows = rows.filter { $0.instrumentKey == "instrument" }
        XCTAssertEqual(instrumentRows.count, 2)
        XCTAssertEqual(instrumentRows.max(by: { $0.receivedAt < $1.receivedAt })?.amount, money(30))
    }

    func testEqualSourceClockAcceptsAChangedValueForDecisionRules() throws {
        let context = try makeContext()
        let sourceClock = Date(timeIntervalSince1970: 3_000)
        let learnedAt = Date(timeIntervalSince1970: 4_000)
        let record = PriceRecord(key: "equal-stamp", game: .pokemon, printingID: "p", variantID: nil)
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 30,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "new",
                sourceUpdatedAt: sourceClock,
                fetchedAt: sourceClock
            )
        )
        context.insert(record)
        context.insert(
            PriceObservation(
                instrumentKey: "equal-stamp",
                kind: .marketUpdate,
                amount: money(20),
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "old",
                marketVariantID: nil,
                effectiveAt: sourceClock,
                receivedAt: sourceClock,
                isSourceStamped: true
            )
        )
        try context.save()

        let rows = PriceObservationLog(context: context)
            .reconcileSyncedRecordsAndReturnObservations(learnedAt: learnedAt)

        let instrumentRows = rows.filter { $0.instrumentKey == "equal-stamp" }
        XCTAssertEqual(instrumentRows.count, 2)
        XCTAssertEqual(
            instrumentRows.max(by: { $0.receivedAt < $1.receivedAt })?.amount,
            money(30)
        )
    }

    func testSyncedInvalidationCreatesLocalKnowledgeEvenWithoutPriorObservation() throws {
        let context = try makeContext()
        let remoteFetch = Date(timeIntervalSince1970: 1_900_000_000)
        let localLearned = remoteFetch.addingTimeInterval(7 * 86_400)
        let record = PriceRecord(key: "instrument", game: .pokemon, printingID: "p", variantID: nil)
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 20,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "remote-v2",
                sourceUpdatedAt: remoteFetch,
                fetchedAt: remoteFetch
            )
        )
        _ = record.invalidate(at: remoteFetch.addingTimeInterval(60))
        context.insert(record)
        try context.save()

        let rows = PriceObservationLog(context: context)
            .reconcileSyncedRecordsAndReturnObservations(learnedAt: localLearned)
        let invalidation = try XCTUnwrap(rows.first)
        XCTAssertEqual(invalidation.kind, .explicitInvalidation)
        XCTAssertNil(invalidation.amount)
        XCTAssertEqual(invalidation.receivedAt, localLearned)
    }

    func testDuplicatePriceRecordsResolveByEvidenceAndConvergeOnWrite() throws {
        let context = try makeContext()
        let key = PriceRecord.key(game: .pokemon, printingID: "p", variantID: nil)
        let older = PriceRecord(key: key, game: .pokemon, printingID: "p", variantID: nil)
        older.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 10,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "older",
                sourceUpdatedAt: nil,
                fetchedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let newer = PriceRecord(key: key, game: .pokemon, printingID: "p", variantID: nil)
        newer.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 20,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "newer",
                sourceUpdatedAt: nil,
                fetchedAt: Date(timeIntervalSince1970: 200)
            )
        )
        context.insert(older)
        context.insert(newer)
        try context.save()

        XCTAssertEqual(PriceStore(context: context).record(forKey: key)?.unitMarketPriceUSD, 20)
        XCTAssertTrue(
            PriceStore(context: context).store(
                .price(
                    NormalizedPrice(
                        unitMarketPriceUSD: 30,
                        currencyCode: "USD",
                        source: .justTCG,
                        sourceVariantID: "repaired",
                        sourceUpdatedAt: nil,
                        fetchedAt: Date(timeIntervalSince1970: 300)
                    )
                ),
                game: .pokemon,
                printingID: "p",
                variantID: nil,
                at: Date(timeIntervalSince1970: 300)
            )
        )
        XCTAssertTrue(PriceStore(context: context).save())
        let records = try context.fetch(
            FetchDescriptor<PriceRecord>(predicate: #Predicate { $0.key == key })
        )
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.unitMarketPriceUSD, 30)
    }

    func testDuplicateInvalidationWinsOverAnOlderUsableRecord() throws {
        let context = try makeContext()
        let usable = PriceRecord(key: "instrument", game: .pokemon, printingID: "p", variantID: nil)
        usable.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 10,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "usable",
                sourceUpdatedAt: nil,
                fetchedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let invalidated = PriceRecord(key: "instrument", game: .pokemon, printingID: "p", variantID: nil)
        invalidated.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 99,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "withdrawn",
                sourceUpdatedAt: nil,
                fetchedAt: Date(timeIntervalSince1970: 100)
            )
        )
        _ = invalidated.invalidate(at: Date(timeIntervalSince1970: 200))
        context.insert(usable)
        context.insert(invalidated)
        try context.save()

        let selected = try XCTUnwrap(PriceStore(context: context).record(forKey: "instrument"))
        XCTAssertTrue(selected.isInvalidated)
        XCTAssertNil(selected.effectiveUnitMarketPriceUSD)
    }

    func testSyncedOwnershipEpochDoesNotBackdateLocalKnowledgeEpoch() throws {
        let context = try makeContext()
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }
        let old = Date(timeIntervalSince1970: 1_900_000_000)
        let now = old.addingTimeInterval(20 * 86_400)
        context.insert(
            InventoryEvent(
                operationID: UUID(), leg: nil, kind: .initialBalance, source: .catalog,
                collectionKey: "position", priceStorageKey: "instrument", deltaQuantity: 1,
                occurredAt: old, valuation: .unpriced
            )
        )
        try context.save()

        XCTAssertNil(PortfolioEpoch.startedAt(defaults: defaults))
        XCTAssertEqual(
            try PortfolioEpoch.establishIfNeeded(
                context: context,
                defaults: defaults,
                at: now,
                isCloudSyncing: false
            ),
            now
        )
    }

    func testPublisherMaterializesEveryMissedDayWithHistoricalCoverage() throws {
        let context = try makeContext()
        let zone = TimeZone(secondsFromGMT: 0)!
        let calendar = PortfolioCalendar.calendar(in: zone)
        let epochDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        let lastDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 26))!
        let event = entry(kind: .initialBalance, delta: 1, at: epochDay.addingTimeInterval(60))
        let price = observation(100, at: epochDay.addingTimeInterval(120))
        context.insert(
            PriceCheckDay(
                instrumentKey: "instrument",
                portfolioDay: epochDay,
                lastSuccessfulCheckAt: epochDay.addingTimeInterval(180),
                source: .justTCG
            )
        )

        try context.save()

        // Through the replay and the real storage adapter, so the bulk coverage
        // fetch is exercised rather than a hand-built index.
        let through = PortfolioCalendar.boundary(afterDay: lastDay, in: zone)
        let replay = PortfolioReplayEngine.replay(
            PortfolioReplayInput(
                events: [event],
                observations: [price],
                coverage: PortfolioReplaySnapshotBuilder.coverageIndex(
                    context: context, from: epochDay, through: through, timeZone: zone
                ),
                epoch: epochDay.addingTimeInterval(30),
                through: through,
                timeZoneIdentifier: zone.identifier
            )
        )
        _ = PortfolioEngine.publish(replay.days, timeZone: zone, context: context)

        let closes = try PortfolioEngine.allCloses(in: context)
        XCTAssertEqual(closes.count, 7)
        XCTAssertEqual(closes.first?.coverageState, .complete)
        XCTAssertEqual(closes.first?.carriedForwardValue, .zero)
        XCTAssertEqual(closes.last?.coverageState, .partial)
        XCTAssertEqual(closes.last?.carriedForwardValue, money(100))
    }

    // MARK: - Read-side idempotency and invalidation

    func testReadSideCanonicalizesCloudKitDuplicatesAndSurfacesConflicts() throws {
        let context = try makeContext()
        let operationID = UUID()
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let first = InventoryEvent(
            operationID: operationID, leg: nil, kind: .acquire, source: .catalog,
            collectionKey: "position", priceStorageKey: "instrument", deltaQuantity: 1,
            occurredAt: date, valuation: .unpriced
        )
        first.eventID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let identical = InventoryEvent(
            operationID: operationID, leg: nil, kind: .acquire, source: .catalog,
            collectionKey: "position", priceStorageKey: "instrument", deltaQuantity: 1,
            occurredAt: date, valuation: .unpriced
        )
        identical.eventID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let conflict = InventoryEvent(
            operationID: operationID, leg: nil, kind: .acquire, source: .catalog,
            collectionKey: "position", priceStorageKey: "instrument", deltaQuantity: 2,
            occurredAt: date, valuation: .unpriced
        )
        conflict.eventID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        context.insert(first)
        context.insert(identical)
        context.insert(conflict)
        try context.save()

        let reading = InventoryLedger(context: context).read()

        // Two of the three rows are equivalent retries and collapse. The third
        // describes a different change under the same leg identity, so no row
        // from that group is counted — counting the lowest UUID would decide
        // the portfolio total by sort order.
        XCTAssertEqual(reading.events.count, 0)
        XCTAssertFalse(reading.isAuthoritative)
        XCTAssertEqual(reading.defects.map(\.reason), [.conflictingPayloadForIdempotencyKey])
    }

    func testConflictingLedgerRowsPauseHistoryWithoutHidingCurrentValue() async throws {
        let context = try makeContext()
        let operationID = UUID()
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        for (index, delta) in [1, 2].enumerated() {
            let event = InventoryEvent(
                operationID: operationID, leg: nil, kind: .acquire, source: .catalog,
                collectionKey: "position", priceStorageKey: "instrument", deltaQuantity: delta,
                occurredAt: date, valuation: .unpriced
            )
            event.eventID = UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index + 1)")!
            context.insert(event)
        }
        context.insert(card(key: "position", quantity: 1))
        try context.save()

        let engine = PortfolioEngine()
        await engine.recomputeAndWait(context: context, now: date.addingTimeInterval(86_400 * 2))

        guard let summary = engine.summary else { return XCTFail("no summary") }
        XCTAssertFalse(summary.isAuthoritative)
        XCTAssertTrue(summary.defects.contains { $0.reason == .conflictingPayloadForIdempotencyKey })
        // Paused, not published: no close may be written from a reading the
        // app already knows is untrustworthy.
        XCTAssertNil(summary.attribution)
        XCTAssertEqual(try PortfolioEngine.allCloses(in: context).count, 0)
    }

    func testLedgerProjectionMismatchAlsoPausesPublication() async throws {
        // The ledger says one copy, the collection holds three. Today already
        // surfaced this; now it also stops the app publishing a close it has
        // just proved it cannot support.
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        context.insert(
            InventoryEvent(
                operationID: UUID(), leg: nil, kind: .acquire, source: .catalog,
                collectionKey: "position", priceStorageKey: "instrument", deltaQuantity: 1,
                occurredAt: date, valuation: .unpriced
            )
        )
        context.insert(card(key: "position", quantity: 3))
        try context.save()

        let engine = PortfolioEngine()
        await engine.recomputeAndWait(context: context, now: date.addingTimeInterval(86_400 * 2))

        guard let summary = engine.summary else { return XCTFail("no summary") }
        XCTAssertFalse(summary.isAuthoritative)
        XCTAssertTrue(
            summary.defects.contains {
                $0.reason == .quantityMismatch && $0.detail == "ledger 1, collection 3"
            }
        )
        XCTAssertNil(summary.attribution)
        XCTAssertEqual(try PortfolioEngine.allCloses(in: context).count, 0)
    }

    func testQuantityRepairAppendsOneAdjustmentPerMismatchedPosition() throws {
        let context = try makeContext()
        let first = card(key: "repair-one", quantity: 3)
        let second = card(key: "repair-two", quantity: 2)
        context.insert(first)
        context.insert(second)
        let ledger = InventoryLedger(context: context)
        let firstOperationID = UUID()
        _ = ledger.record(
            first,
            kind: .acquire,
            source: .scan,
            deltaQuantity: 1,
            operationID: firstOperationID
        )
        let secondOperationID = UUID()
        _ = ledger.record(
            second,
            kind: .acquire,
            source: .scan,
            deltaQuantity: 1,
            operationID: secondOperationID
        )
        context.insert(
            CollectionActivity(
                card: first,
                source: .scan,
                quantity: 1,
                ledgerOperationIDs: [firstOperationID]
            )
        )
        context.insert(
            CollectionActivity(
                card: second,
                source: .scan,
                quantity: 1,
                ledgerOperationIDs: [secondOperationID]
            )
        )
        try context.save()

        let defects = [first, second].map {
            LedgerIntegrityDefect(
                reason: .quantityMismatch,
                collectionKey: $0.collectionKey,
                detail: "ledger 1, collection \($0.quantity)"
            )
        }
        try CollectionStore.repairQuantityMismatches(defects, in: context)

        let events = try ledger.allEventsThrowing()
        let adjustments = events.filter { $0.kind == .quantityAdjust }
        XCTAssertEqual(adjustments.count, 2)
        XCTAssertEqual(Set(adjustments.map(\.operationID)).count, 2)
        XCTAssertEqual(InventoryLedger.quantities(from: events)[first.collectionKey], 3)
        XCTAssertEqual(InventoryLedger.quantities(from: events)[second.collectionKey], 2)
        XCTAssertEqual(first.quantity, 3)
        XCTAssertEqual(second.quantity, 2)
    }

    func testQuantityRepairRejectsMixedDefectsWithoutMutation() throws {
        let context = try makeContext()
        let owned = card(key: "repair-mixed", quantity: 2)
        context.insert(owned)
        let ledger = InventoryLedger(context: context)
        _ = ledger.record(
            owned,
            kind: .acquire,
            source: .scan,
            deltaQuantity: 1,
            operationID: UUID()
        )
        try context.save()
        let defects = [
            LedgerIntegrityDefect(
                reason: .quantityMismatch,
                collectionKey: owned.collectionKey,
                detail: "ledger 1, collection 2"
            ),
            LedgerIntegrityDefect(
                reason: .orphanedCorrectionLeg,
                collectionKey: owned.collectionKey,
                detail: "missing correction leg"
            )
        ]

        XCTAssertThrowsError(
            try CollectionStore.repairQuantityMismatches(defects, in: context)
        )
        XCTAssertEqual(try ledger.allEventsThrowing().count, 1)
        XCTAssertEqual(owned.quantity, 2)
    }

    func testEquivalentBaselineDuplicatesCanonicalizeToEarliestOwnershipTime() throws {
        let context = try makeContext()
        let operationID = PortfolioEpoch.baselineOperationID(collectionKey: "position")
        let earlier = Date(timeIntervalSince1970: 2_000_000_000)
        let later = earlier.addingTimeInterval(86_400)

        let firstKnown = InventoryEvent(
            operationID: operationID, leg: nil, kind: .initialBalance, source: .catalog,
            collectionKey: "position", priceStorageKey: "instrument", deltaQuantity: 1,
            occurredAt: earlier, valuation: .unpriced
        )
        firstKnown.eventID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!

        let laterRandomWinner = InventoryEvent(
            operationID: operationID, leg: nil, kind: .initialBalance, source: .catalog,
            collectionKey: "position", priceStorageKey: "instrument", deltaQuantity: 1,
            occurredAt: later, valuation: .unpriced
        )
        laterRandomWinner.eventID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        context.insert(firstKnown)
        context.insert(laterRandomWinner)
        try context.save()

        let events = InventoryLedger(context: context).allEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.eventID, firstKnown.eventID)
        XCTAssertEqual(events.first?.occurredAt, earlier)
    }

    // MARK: - CSV integration

    func testCSVImportedPriceAttributesValueToAddedNotPricingAdjustment() throws {
        let context = try makeContext()
        let plan = CollectionCSVImportPlan(
            entries: [
                CollectionCSVEntry(
                    collectionKey: "csv-position",
                    game: .pokemon,
                    providerID: "csv-printing",
                    name: "Imported Collection",
                    setName: "Imported Set",
                    setCode: "CSV",
                    cardNumber: "7",
                    rarity: nil,
                    imageURL: nil,
                    thumbnailURL: nil,
                    variant: nil,
                    importedMarketPriceUSD: 7_000,
                    importedPriceAsOf: Date(timeIntervalSince1970: 1_900_000_000),
                    quantity: 1,
                    dateAdded: Date(timeIntervalSince1970: 1_800_000_000)
                )
            ],
            skippedRows: 0,
            skippedCSVText: nil
        )

        _ = try CollectionCSV.apply(plan, to: context)

        let events = InventoryLedger(context: context).allEvents().map(PortfolioEngine.entry(from:))
        let observations = try PortfolioEngine.observations(in: context)
        let eventTime = try XCTUnwrap(events.first?.occurredAt)
        XCTAssertEqual(observations.first?.receivedAt, eventTime)
        XCTAssertEqual(events.first?.priceReceivedAtEvent, eventTime)

        let attribution = PortfolioClose.attribute(
            events: events,
            observations: observations,
            boundary: eventTime.addingTimeInterval(-1),
            now: eventTime.addingTimeInterval(1),
            currentValue: money(7_000)
        )

        XCTAssertEqual(attribution.added, money(7_000))
        XCTAssertEqual(attribution.newlyAddedValue, .zero)
        XCTAssertEqual(attribution.pricingAdjustment, .zero)
        XCTAssertEqual(attribution.market, .zero)
        XCTAssertEqual(attribution.unexplained, .zero)
    }

    func testCSVImportedWithoutPriceThenRefreshedShowsNewPortfolioAddition() throws {
        let context = try makeContext()
        let plan = CollectionCSVImportPlan(
            entries: [
                CollectionCSVEntry(
                    collectionKey: "csv-unpriced-position",
                    game: .pokemon,
                    providerID: "csv-printing",
                    name: "Imported Without Price",
                    setName: "Imported Set",
                    setCode: "CSV",
                    cardNumber: "8",
                    rarity: nil,
                    imageURL: nil,
                    thumbnailURL: nil,
                    variant: nil,
                    importedMarketPriceUSD: nil,
                    importedPriceAsOf: nil,
                    quantity: 1,
                    dateAdded: Date(timeIntervalSince1970: 1_800_000_000)
                )
            ],
            skippedRows: 0,
            skippedCSVText: nil
        )

        _ = try CollectionCSV.apply(plan, to: context)
        let events = InventoryLedger(context: context).allEvents().map(PortfolioEngine.entry(from:))
        let eventTime = try XCTUnwrap(events.first?.occurredAt)
        let card = try XCTUnwrap(try context.fetch(FetchDescriptor<CollectedCard>()).first)
        let refreshedAt = eventTime.addingTimeInterval(60)

        PriceStore(context: context).store(
            .price(
                NormalizedPrice(
                    unitMarketPriceUSD: 7_000,
                    currencyCode: "USD",
                    source: .justTCG,
                    sourceVariantID: "refreshed-variant",
                    sourceUpdatedAt: nil,
                    fetchedAt: refreshedAt
                )
            ),
            game: CardGame(rawValue: card.game) ?? .pokemon,
            printingID: card.priceStorageID,
            variantID: card.variantID,
            at: refreshedAt
        )

        let attribution = PortfolioClose.attribute(
            events: events,
            observations: try PortfolioEngine.observations(in: context),
            boundary: eventTime.addingTimeInterval(-1),
            now: refreshedAt.addingTimeInterval(1),
            currentValue: money(7_000)
        )

        XCTAssertEqual(events.first?.kind, .recordExisting)
        XCTAssertEqual(attribution.added, .zero)
        XCTAssertEqual(attribution.newlyAddedValue, money(7_000))
        XCTAssertEqual(attribution.pricingAdjustment, .zero)
        XCTAssertEqual(attribution.unexplained, .zero)
    }

    func testExplicitInvalidationCannotFallBackToMutablePriceRecord() throws {
        let context = try makeContext()
        let record = PriceRecord(key: "instrument", game: .pokemon, printingID: "p", variantID: nil)
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 42,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "v",
                sourceUpdatedAt: nil,
                fetchedAt: Date(timeIntervalSince1970: 1_000)
            )
        )
        context.insert(record)
        let invalidatedAt = Date(timeIntervalSince1970: 2_000)
        _ = try XCTUnwrap(
            PriceObservationLog(context: context).recordInvalidation(
                instrumentKey: "instrument",
                source: .justTCG,
                at: invalidatedAt
            )
        )
        try context.save()

        XCTAssertNil(InventoryLedger(context: context).valuation(forPriceKey: "instrument").unitPrice)
        XCTAssertNil(record.unitMarketPriceUSD)
        XCTAssertEqual(record.invalidatedAt, invalidatedAt)
    }

    func testInvalidationMirrorsIntoCollectionReadPathAndBlocksLegacyFallback() throws {
        let context = try makeContext()
        let card = CollectedCard(
            collectionKey: "collection",
            game: .pokemon,
            providerID: "printing",
            name: "Test Card",
            setName: "Test Set",
            setCode: "TST",
            cardNumber: "1",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .normal,
            variantResolution: .imported
        )
        card.itemKindRaw = CollectionItemKind.sealedProduct.rawValue
        card.justTCGVariantID = "market-variant"
        card.justTCGAPIVersion = "v1"
        let canonical = PriceRecord(
            key: card.priceKey,
            game: .pokemon,
            printingID: card.priceStorageID,
            variantID: card.variantID
        )
        canonical.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 42,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "wrong-listing",
                sourceUpdatedAt: nil,
                fetchedAt: Date(timeIntervalSince1970: 100)
            )
        )
        context.insert(card)
        context.insert(canonical)
        let legacyKey = try XCTUnwrap(card.legacyPriceKeys.first)
        let legacy = PriceRecord(
            key: legacyKey,
            game: .pokemon,
            printingID: card.providerID,
            variantID: card.variantID
        )
        legacy.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 99,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "legacy-listing",
                sourceUpdatedAt: nil,
                fetchedAt: Date(timeIntervalSince1970: 100)
            )
        )
        context.insert(legacy)
        try context.save()

        let invalidatedAt = Date(timeIntervalSince1970: 200)
        let invalidation = try XCTUnwrap(
            PriceObservationLog(context: context).recordInvalidation(
                instrumentKey: canonical.key,
                source: .justTCG,
                at: invalidatedAt
            )
        )
        try context.save()

        let visible = PriceStore.record(
            for: card,
            in: [canonical.key: canonical, legacy.key: legacy]
        )
        XCTAssertEqual(invalidation.kind, .explicitInvalidation)
        XCTAssertTrue(canonical.isInvalidated)
        XCTAssertTrue(legacy.effectiveUnitMarketPriceUSD != nil)
        XCTAssertTrue(visible === canonical)
        XCTAssertNil(visible?.unitMarketPriceUSD)
        XCTAssertNil(visible?.display.amount)
        XCTAssertEqual(canonical.invalidatedAt, invalidatedAt)

        XCTAssertEqual(
            InventoryLedger(context: context).priceStorageKey(for: card),
            canonical.key,
            "Scalar ledger attribution must retain the invalidated canonical key."
        )
        let bulk = PortfolioReplaySnapshotBuilder.valuationIndex(
            observations: try context.fetch(FetchDescriptor<PriceObservation>()),
            records: try context.fetch(FetchDescriptor<PriceRecord>())
        )
        XCTAssertEqual(
            bulk.priceStorageKey(for: card),
            canonical.key,
            "Bulk attribution must retain the invalidated canonical key."
        )
    }

    func testInvalidationStillWinsOverNewerUnusableObservationInScalarAndBulkReads() throws {
        let context = try makeContext()
        let recordDate = Date(timeIntervalSince1970: 100)
        let invalidatedAt = Date(timeIntervalSince1970: 200)
        let laterObservationAt = Date(timeIntervalSince1970: 300)
        let record = PriceRecord(key: "instrument", game: .pokemon, printingID: "p", variantID: nil)
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 42,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "wrong-listing",
                sourceUpdatedAt: nil,
                fetchedAt: recordDate
            )
        )
        context.insert(record)
        context.insert(
            PriceObservation(
                instrumentKey: "instrument",
                kind: .marketUpdate,
                amount: money(42),
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "wrong-listing",
                marketVariantID: nil,
                effectiveAt: recordDate,
                receivedAt: recordDate,
                isSourceStamped: false
            )
        )
        try context.save()

        _ = try XCTUnwrap(
            PriceObservationLog(context: context).recordInvalidation(
                instrumentKey: "instrument",
                source: .justTCG,
                at: invalidatedAt
            )
        )
        context.insert(
            PriceObservation(
                instrumentKey: "instrument",
                kind: .marketUpdate,
                amount: money(99),
                currencyCode: "EUR",
                source: .cardmarket,
                sourceVariantID: "foreign-listing",
                marketVariantID: nil,
                effectiveAt: laterObservationAt,
                receivedAt: laterObservationAt,
                isSourceStamped: true
            )
        )
        try context.save()

        let scalar = InventoryLedger(context: context).valuation(forPriceKey: "instrument")
        let bulk = PortfolioReplaySnapshotBuilder.valuationIndex(
            observations: try context.fetch(FetchDescriptor<PriceObservation>()),
            records: try context.fetch(FetchDescriptor<PriceRecord>())
        )

        XCTAssertNil(scalar.unitPrice)
        XCTAssertNil(bulk.valuation(for: "instrument").unitPrice)
    }

    func testNewerUSDObservationCanArriveAfterInvalidationWatermark() throws {
        let context = try makeContext()
        let record = PriceRecord(key: "instrument", game: .pokemon, printingID: "p", variantID: nil)
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 42,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "old-listing",
                sourceUpdatedAt: nil,
                fetchedAt: Date(timeIntervalSince1970: 100)
            )
        )
        _ = record.invalidate(at: Date(timeIntervalSince1970: 200))
        context.insert(record)
        context.insert(
            PriceObservation(
                instrumentKey: "instrument",
                kind: .marketUpdate,
                amount: money(99),
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "new-listing",
                marketVariantID: nil,
                effectiveAt: Date(timeIntervalSince1970: 300),
                receivedAt: Date(timeIntervalSince1970: 300),
                isSourceStamped: true
            )
        )
        try context.save()

        let scalar = InventoryLedger(context: context).valuation(forPriceKey: "instrument")
        let bulk = PortfolioReplaySnapshotBuilder.valuationIndex(
            observations: try context.fetch(FetchDescriptor<PriceObservation>()),
            records: try context.fetch(FetchDescriptor<PriceRecord>())
        )

        XCTAssertEqual(scalar.unitPrice, money(99))
        XCTAssertEqual(bulk.valuation(for: "instrument").unitPrice, money(99))
    }

    func testFreshPriceReplacesAnInvalidationButStalePriceCannot() throws {
        let context = try makeContext()
        let key = PriceRecord.key(game: .pokemon, printingID: "p", variantID: "normal")
        let initial = Date(timeIntervalSince1970: 100)
        let invalidatedAt = Date(timeIntervalSince1970: 200)
        let store = PriceStore(context: context)

        store.store(
            .price(
                NormalizedPrice(
                    unitMarketPriceUSD: 42,
                    currencyCode: "USD",
                    source: .justTCG,
                    sourceVariantID: "old-listing",
                    sourceUpdatedAt: nil,
                    fetchedAt: initial
                )
            ),
            game: .pokemon,
            printingID: "p",
            variantID: "normal",
            at: initial
        )
        let record = try XCTUnwrap(store.record(forKey: key))
        _ = try XCTUnwrap(
            PriceObservationLog(context: context).recordInvalidation(
                instrumentKey: key,
                source: .justTCG,
                at: invalidatedAt
            )
        )

        store.store(
            .price(
                NormalizedPrice(
                    unitMarketPriceUSD: 7,
                    currencyCode: "USD",
                    source: .justTCG,
                    sourceVariantID: "stale-listing",
                    sourceUpdatedAt: nil,
                    fetchedAt: initial
                )
            ),
            game: .pokemon,
            printingID: "p",
            variantID: "normal",
            at: initial
        )
        XCTAssertTrue(record.isInvalidated)
        XCTAssertNil(record.unitMarketPriceUSD)
        XCTAssertNil(InventoryLedger(context: context).valuation(forPriceKey: key).unitPrice)
        XCTAssertEqual(
            PriceObservationLog(context: context).observations(instrumentKey: key).count,
            2,
            "a response received before invalidation must not append stale value evidence"
        )

        let fresh = invalidatedAt.addingTimeInterval(1)
        store.store(
            .price(
                NormalizedPrice(
                    unitMarketPriceUSD: 9,
                    currencyCode: "USD",
                    source: .justTCG,
                    sourceVariantID: "new-listing",
                    sourceUpdatedAt: nil,
                    fetchedAt: fresh
                )
            ),
            game: .pokemon,
            printingID: "p",
            variantID: "normal",
            at: fresh
        )

        XCTAssertFalse(record.isInvalidated)
        XCTAssertEqual(record.unitMarketPriceUSD, 9)
        XCTAssertEqual(PriceObservationLog(context: context).observations(instrumentKey: key).count, 3)
        XCTAssertEqual(InventoryLedger(context: context).valuation(forPriceKey: key).unitPrice, money(9))
    }

    func testOlderInvalidationCannotWithdrawAFreshPrice() throws {
        let record = PriceRecord(key: "instrument", game: .pokemon, printingID: "p", variantID: nil)
        let fresh = Date(timeIntervalSince1970: 300)
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 9,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "new-listing",
                sourceUpdatedAt: nil,
                fetchedAt: fresh
            )
        )

        XCTAssertFalse(record.invalidate(at: Date(timeIntervalSince1970: 200)))
        XCTAssertFalse(record.isInvalidated)
        XCTAssertEqual(record.unitMarketPriceUSD, 9)
    }

    func testScalarAndBulkValuationFallBackFromNewerNonUSDObservationToUSDRecord() throws {
        let context = try makeContext()
        let recordDate = Date(timeIntervalSince1970: 1_700_000_000)
        let observationDate = recordDate.addingTimeInterval(60)
        let record = PriceRecord(key: "instrument", game: .pokemon, printingID: "p", variantID: nil)
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 42,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "usd-listing",
                sourceUpdatedAt: recordDate,
                fetchedAt: recordDate
            )
        )
        context.insert(record)
        context.insert(
            PriceObservation(
                instrumentKey: "instrument",
                kind: .marketUpdate,
                amount: money(99),
                currencyCode: "EUR",
                source: .cardmarket,
                sourceVariantID: "eur-listing",
                marketVariantID: nil,
                effectiveAt: observationDate,
                receivedAt: observationDate,
                isSourceStamped: true
            )
        )
        try context.save()

        let scalar = InventoryLedger(context: context).valuation(forPriceKey: "instrument")
        let observations = try context.fetch(FetchDescriptor<PriceObservation>())
        let records = try context.fetch(FetchDescriptor<PriceRecord>())
        let bulk = PortfolioReplaySnapshotBuilder.valuationIndex(
            observations: observations,
            records: records
        )

        XCTAssertEqual(scalar.unitPrice, money(42))
        XCTAssertEqual(scalar.source, .justTCG)
        XCTAssertEqual(bulk.valuation(for: "instrument"), scalar)
    }

    func testAsOfBulkValuationMatchesReplayWhenRefreshEvidenceArrivesAfterCutoff() throws {
        let context = try makeContext()
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        let before = cutoff.addingTimeInterval(-60)
        let after = cutoff.addingTimeInterval(60)

        let record = PriceRecord(
            key: "instrument",
            game: .pokemon,
            printingID: "p",
            variantID: nil
        )
        _ = record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 1.21,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "new-listing",
                sourceUpdatedAt: nil,
                fetchedAt: after
            )
        )
        context.insert(record)
        context.insert(
            PriceObservation(
                instrumentKey: "instrument",
                kind: .marketUpdate,
                amount: money(0.99),
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "old-listing",
                marketVariantID: nil,
                effectiveAt: before,
                receivedAt: before,
                isSourceStamped: false
            )
        )
        context.insert(
            PriceObservation(
                instrumentKey: "instrument",
                kind: .marketUpdate,
                amount: money(1.21),
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "new-listing",
                marketVariantID: nil,
                effectiveAt: after,
                receivedAt: after,
                isSourceStamped: false
            )
        )
        try context.save()

        let rows = try context.fetch(FetchDescriptor<PriceObservation>())
        let records = try context.fetch(FetchDescriptor<PriceRecord>())
        let asOf = PortfolioReplaySnapshotBuilder.valuationIndex(
            observations: rows,
            records: records,
            asOf: cutoff
        )
        XCTAssertEqual(asOf.valuation(for: "instrument").unitPrice, money(0.99))

        let replay = PortfolioReplayEngine.replay(
            PortfolioReplayInput(
                events: [entry(
                    kind: .initialBalance,
                    delta: 1,
                    at: before.addingTimeInterval(1),
                    instrument: "instrument"
                )],
                observations: rows.map(PortfolioEngine.observationEntry(from:)),
                epoch: before.addingTimeInterval(-1),
                through: cutoff,
                timeZoneIdentifier: "UTC"
            )
        )
        var attribution = try XCTUnwrap(replay.live?.attribution)
        attribution.currentValue = try XCTUnwrap(asOf.valuation(for: "instrument").unitPrice)
        XCTAssertEqual(attribution.unexplained, .zero)
    }

    func testSourceLessUSDRecordIsBackfilledWithoutInventingProviderProvenance() throws {
        let context = try makeContext()
        let learnedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let record = PriceRecord(
            key: "legacy-instrument",
            game: .pokemon,
            printingID: "legacy-printing",
            variantID: nil
        )
        record.unitMarketPriceUSD = 1.21
        record.currencyCode = "USD"
        record.sourceRaw = nil
        record.fetchedAt = learnedAt.addingTimeInterval(-60)
        context.insert(record)
        try context.save()

        let observations = PriceObservationLog(context: context)
            .reconcileSyncedRecordsAndReturnObservations(learnedAt: learnedAt)
        let observation = try XCTUnwrap(
            observations.first { $0.instrumentKey == record.key }
        )

        // With no prior local row there is no provider transition to name. The
        // important contract is that the value is retained as evidence without
        // fabricating a provider identity; the replay still treats this first
        // value as pricing adjustment rather than market movement.
        XCTAssertEqual(observation.kind, .marketUpdate)
        XCTAssertEqual(observation.amount, money(1.21))
        XCTAssertNil(observation.source)
        XCTAssertEqual(observation.receivedAt, learnedAt)
    }

    func testSourceLessUSDRecordDoesNotLeaveAnUnattributedPortfolioResidual() throws {
        let context = try makeContext()
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        let now = epoch.addingTimeInterval(3_600)
        let owned = card(key: "legacy-position")
        context.insert(owned)
        let instrument = owned.priceKey
        let record = PriceRecord(
            key: instrument,
            game: .pokemon,
            printingID: "legacy-printing",
            variantID: nil
        )
        record.unitMarketPriceUSD = 1.21
        record.currencyCode = "USD"
        record.sourceRaw = nil
        record.fetchedAt = epoch.addingTimeInterval(600)
        context.insert(record)
        context.insert(
            InventoryEvent(
                operationID: UUID(),
                leg: nil,
                kind: .initialBalance,
                source: .catalog,
                collectionKey: owned.collectionKey,
                priceStorageKey: instrument,
                deltaQuantity: 1,
                occurredAt: epoch.addingTimeInterval(60),
                valuation: .unpriced
            )
        )
        try context.save()

        let observations = PriceObservationLog(context: context)
            .reconcileSyncedRecordsAndReturnObservations(learnedAt: epoch.addingTimeInterval(900))
        let computation = PortfolioReplaySnapshotBuilder.compute(
            context: context,
            epoch: epoch,
            through: now,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            existingObservations: observations
        )

        XCTAssertFalse(
            computation.defects.contains { $0.reason == .unattributedValueChange },
            "a current value inherited without provider provenance must still be explained by the backfilled transition"
        )
        XCTAssertEqual(computation.replay.live?.attribution.unexplained, .zero)
    }

    func testMigratedPriceAliasKeepsCanonicalRefreshInPortfolioReplay() throws {
        let context = try makeContext()
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        let now = epoch.addingTimeInterval(3_600)
        let card = CollectedCard(
            collectionKey: "magic:alias-card#foil#treatment=surgefoil",
            game: .magic,
            providerID: "alias-card",
            name: "Alias Card",
            setName: "Fixture Set",
            setCode: "FIC",
            cardNumber: "1",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .foil,
            variantResolution: .userConfirmed,
            magicTreatments: [.surgeFoil]
        )
        context.insert(card)

        let canonicalKey = card.priceKey
        let legacyKey = try XCTUnwrap(card.legacyPriceKeys.first)
        let record = PriceRecord(
            key: canonicalKey,
            game: .magic,
            printingID: card.priceStorageID,
            variantID: card.variantID,
            magicTreatmentIDs: card.priceTreatmentIDs
        )
        _ = record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 1.21,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "exact-treatment",
                sourceUpdatedAt: nil,
                fetchedAt: epoch.addingTimeInterval(300)
            )
        )
        context.insert(record)
        context.insert(
            PriceObservation(
                instrumentKey: canonicalKey,
                kind: .sourceTransition,
                amount: money(1.21),
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "exact-treatment",
                marketVariantID: nil,
                effectiveAt: epoch.addingTimeInterval(300),
                receivedAt: epoch.addingTimeInterval(300),
                isSourceStamped: false
            )
        )
        let operationID = UUID()
        context.insert(
            InventoryEvent(
                operationID: operationID,
                leg: nil,
                kind: .initialBalance,
                source: .catalog,
                collectionKey: card.collectionKey,
                priceStorageKey: legacyKey,
                deltaQuantity: 1,
                occurredAt: epoch.addingTimeInterval(60),
                valuation: .unpriced
            )
        )
        context.insert(
            CollectionActivity(
                card: card,
                source: .catalog,
                quantity: 1,
                occurredAt: epoch.addingTimeInterval(60),
                ledgerOperationIDs: [operationID]
            )
        )
        try context.save()

        let rows = try context.fetch(FetchDescriptor<PriceObservation>())
        let computation = PortfolioReplaySnapshotBuilder.compute(
            context: context,
            epoch: epoch,
            through: now,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            existingObservations: rows
        )
        let attribution = try XCTUnwrap(computation.replay.live?.attribution)

        XCTAssertEqual(computation.valuation.value, money(1.21))
        XCTAssertEqual(attribution.currentValue, money(1.21))
        XCTAssertEqual(
            attribution.unexplained,
            .zero,
            "a canonical treatment refresh must reconcile with an older event that still names the legacy price key"
        )
        XCTAssertFalse(
            computation.defects.contains { $0.reason == .quantityMismatch },
            "unexpected quantity defect: \(computation.defects)"
        )
    }

    // MARK: - Initial-sync deferral

    private func epochDefaults(_ name: String) -> UserDefaults {
        let suite = "PortfolioEpochSync.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testReadabilityRuleMigrationAttributesAnExistingTreatmentPrice() throws {
        let context = try makeContext()
        let defaults = epochDefaults(#function)
        let epoch = Date(timeIntervalSince1970: 2_000_000_000)
        let learnedAt = epoch.addingTimeInterval(3_600)
        let key = PriceRecord.key(
            game: .magic,
            printingID: "neo-429",
            variantID: "foil",
            treatmentIDs: ["surgefoil"]
        )
        let record = PriceRecord(
            key: key,
            game: .magic,
            printingID: "neo-429",
            variantID: "foil",
            magicTreatmentIDs: ["surgefoil"]
        )
        _ = record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 605.66,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "surge-foil-listing",
                sourceUpdatedAt: nil,
                fetchedAt: learnedAt
            )
        )
        context.insert(record)
        try context.save()

        let log = PriceObservationLog(context: context)
        let learned = log.reconcileSyncedRecordsAndReturnObservations(
            learnedAt: learnedAt,
            defaults: defaults
        )
        let transition = try XCTUnwrap(learned.first { $0.instrumentKey == key })
        XCTAssertEqual(transition.kind, .sourceTransition)
        XCTAssertEqual(transition.amount, money(605.66))
        XCTAssertEqual(
            defaults.integer(forKey: PriceReadabilityRules.defaultsKey),
            PriceReadabilityRules.currentVersion
        )

        let replay = PortfolioReplayEngine.replay(
            PortfolioReplayInput(
                events: [entry(
                    kind: .initialBalance,
                    delta: 1,
                    at: epoch.addingTimeInterval(60),
                    instrument: key
                )],
                observations: learned.map(PortfolioEngine.observationEntry(from:)),
                epoch: epoch,
                through: learnedAt,
                timeZoneIdentifier: "UTC"
            )
        )

        XCTAssertEqual(replay.live?.attribution.pricingAdjustment, money(605.66))
        XCTAssertEqual(replay.live?.attribution.unexplained, .zero)
        XCTAssertEqual(
            log.reconcileSyncedRecordsAndReturnObservations(
                learnedAt: learnedAt.addingTimeInterval(1),
                defaults: defaults
            ).filter { $0.instrumentKey == key }.count,
            1,
            "the process-wide version gate must be idempotent"
        )
    }

    func testReadabilityRuleMigrationAttributesAReadThroughTreatmentPrice() throws {
        let context = try makeContext()
        let defaults = epochDefaults(#function)
        let epoch = Date(timeIntervalSince1970: 2_000_000_000)
        let learnedAt = epoch.addingTimeInterval(3_600)
        let card = CollectedCard(
            collectionKey: "magic:neo-429#foil#treatment=surgefoil",
            game: .magic,
            providerID: "neo-429",
            name: "Surge Foil Fixture",
            setName: "Kamigawa: Neon Dynasty",
            setCode: "NEO",
            cardNumber: "429",
            rarity: "Rare",
            imageURL: nil,
            thumbnailURL: nil,
            variant: .foil,
            variantResolution: .imported,
            magicTreatments: [.surgeFoil]
        )
        context.insert(card)

        let legacyKey = try XCTUnwrap(card.legacyPriceKeys.first)
        let record = PriceRecord(
            key: legacyKey,
            game: .magic,
            printingID: card.priceStorageID,
            variantID: card.variantID
        )
        _ = record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 12,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "generic-foil-listing",
                sourceUpdatedAt: nil,
                fetchedAt: learnedAt
            )
        )
        context.insert(record)
        try context.save()

        let learned = PriceObservationLog(context: context)
            .reconcileSyncedRecordsAndReturnObservations(
                learnedAt: learnedAt,
                defaults: defaults
            )
        let transition = try XCTUnwrap(learned.first { $0.instrumentKey == legacyKey })
        XCTAssertEqual(transition.kind, .sourceTransition)
        XCTAssertEqual(transition.amount, money(12))

        let replay = PortfolioReplayEngine.replay(
            PortfolioReplayInput(
                events: [entry(
                    kind: .initialBalance,
                    delta: 1,
                    at: epoch.addingTimeInterval(60),
                    position: card.collectionKey,
                    instrument: legacyKey
                )],
                observations: learned.map(PortfolioEngine.observationEntry(from:)),
                epoch: epoch,
                through: learnedAt,
                timeZoneIdentifier: "UTC"
            )
        )

        XCTAssertEqual(replay.live?.attribution.pricingAdjustment, money(12))
        XCTAssertEqual(replay.live?.attribution.unexplained, .zero)
    }

    func testPortfolioHistoryExportPreservesAddedAndRemovedContributions() {
        let close = PortfolioDailyClose(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            revision: 1,
            timeZoneIdentifier: "UTC",
            closeValue: money(202),
            market: money(0),
            flow: money(2),
            corrections: .zero,
            pricingAdjustment: .zero,
            carriedForwardValue: .zero,
            coverage: .complete,
            refreshedInstrumentCount: 1,
            carriedForwardInstrumentCount: 0,
            pricedPositionCount: 1,
            excludedCount: 0,
            inputsFingerprint: "fixture",
            revisionReason: nil,
            added: money(5),
            removed: money(3)
        )

        let csv = CollectionCSV.exportPortfolioHistory([close]).text

        XCTAssertTrue(csv.contains("added_contribution_usd"))
        XCTAssertTrue(csv.contains("removed_contribution_usd"))
        XCTAssertTrue(csv.contains("5.0000"))
        XCTAssertTrue(csv.contains("3.0000"))
    }

    func testUnexplainedValueChangeBecomesAnIntegrityDefect() async throws {
        let context = try makeContext()
        let epoch = Date(timeIntervalSince1970: 2_000_000_000)
        let now = epoch.addingTimeInterval(2 * 86_400 + 3_600)
        let value = money(42)
        let defaults = UserDefaults.standard
        let previousEpoch = defaults.object(forKey: PortfolioEpoch.defaultsKey)
        defaults.set(epoch.timeIntervalSince1970, forKey: PortfolioEpoch.defaultsKey)
        defer {
            if let previousEpoch {
                defaults.set(previousEpoch, forKey: PortfolioEpoch.defaultsKey)
            } else {
                defaults.removeObject(forKey: PortfolioEpoch.defaultsKey)
            }
        }

        let provider: PortfolioComputationProvider = { _, _, _, _ in
            let replay = PortfolioReplayEngine.replay(
                PortfolioReplayInput(
                    events: [], observations: [], epoch: epoch, through: now,
                    timeZoneIdentifier: "UTC"
                )
            )
            return PortfolioReplaySnapshotBuilder.Computation(
                valuation: PortfolioEngine.CurrentValuation(value: value),
                defects: [],
                isAuthoritative: true,
                replay: replay,
                coverage: PortfolioCoverageIndex(),
                holdings: []
            )
        }
        let engine = PortfolioEngine(computationProvider: provider)

        await engine.recomputeAndWait(context: context, now: now)

        let summary = try XCTUnwrap(engine.summary)
        let defect = try XCTUnwrap(summary.defects.first)
        XCTAssertEqual(defect.reason, .unattributedValueChange)
        XCTAssertEqual(defect.amount, value)
        XCTAssertEqual(defect.periodEnd, now)
        XCTAssertTrue(summary.isAuthoritative)
        XCTAssertFalse(
            try context.fetch(FetchDescriptor<PortfolioDailyClose>()).isEmpty,
            "an attribution defect must not discard the independently measured close"
        )
        XCTAssertEqual(engine.integrityDefects, summary.defects)
    }

    /// A local-only device cannot be waiting on anything, so a collection with
    /// no ledger is genuine pre-ledger history and must be baselined at once.
    /// This is the upgrade path for everyone who used the app before the ledger
    /// existed, and it must not be delayed.
    func testLocalOnlyCollectionIsBaselinedImmediately() throws {
        let context = try makeContext()
        let defaults = epochDefaults(#function)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        context.insert(card(key: "local", quantity: 2, dateAdded: now))
        try context.save()

        try PortfolioEpoch.establishIfNeeded(
            context: context,
            defaults: defaults,
            at: now,
            isCloudSyncing: false
        )

        let events = InventoryLedger(context: context).allEvents()
        XCTAssertEqual(events.map(\.kind), [.initialBalance])
        XCTAssertEqual(events.first?.deltaQuantity, 2)
        XCTAssertNotNil(PortfolioEpoch.startedAt(defaults: defaults))
    }

    /// The race this exists to close: `CollectedCard` rows have arrived from
    /// another device but their `InventoryEvent`s have not. Baselining here
    /// would write an `initialBalance` beside an `acquire` that is still in
    /// flight — and the deterministic baseline id only dedupes against another
    /// baseline, never against a real acquisition, so the collection would be
    /// counted twice.
    func testSyncingDeviceDefersBaselineWhileTheLedgerIsStillEmpty() throws {
        let context = try makeContext()
        let defaults = epochDefaults(#function)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        context.insert(card(key: "remote", quantity: 3, dateAdded: now))
        try context.save()

        XCTAssertThrowsError(
            try PortfolioEpoch.establishIfNeeded(
                context: context,
                defaults: defaults,
                at: now,
                isCloudSyncing: true
            )
        ) { error in
            guard case .awaitingInitialSync? = error as? PortfolioEpoch.EstablishmentError else {
                XCTFail("expected awaitingInitialSync, got \(error)")
                return
            }
        }

        XCTAssertTrue(
            InventoryLedger(context: context).allEvents().isEmpty,
            "nothing may be written while the ledger is still arriving"
        )
        XCTAssertNil(
            PortfolioEpoch.startedAt(defaults: defaults),
            "the epoch is the public claim that the books are open"
        )
    }

    /// The wait is bounded. A collection whose events are never coming — a
    /// pre-ledger install on a signed-in device — still opens its books.
    func testDeferralExpiresSoAPreLedgerCollectionStillOpens() throws {
        let context = try makeContext()
        let defaults = epochDefaults(#function)
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        context.insert(card(key: "legacy", quantity: 1, dateAdded: start))
        try context.save()

        XCTAssertThrowsError(
            try PortfolioEpoch.establishIfNeeded(
                context: context,
                defaults: defaults,
                at: start,
                isCloudSyncing: true
            )
        )

        let afterGrace = start.addingTimeInterval(PortfolioEpoch.initialSyncGrace + 1)
        try PortfolioEpoch.establishIfNeeded(
            context: context,
            defaults: defaults,
            at: afterGrace,
            isCloudSyncing: true
        )

        XCTAssertEqual(
            InventoryLedger(context: context).allEvents().map(\.kind),
            [.initialBalance]
        )
        XCTAssertEqual(PortfolioEpoch.startedAt(defaults: defaults), afterGrace)
    }

    /// If the bounded sync wait expires before an older ownership event arrives,
    /// the visible collection has already included that event's quantity. Replay
    /// must rebase the provisional initial balance instead of counting both.
    func testDelayedPreBaselineOwnershipEventIsRebasedDuringReplay() throws {
        let baselineDate = Date(timeIntervalSince1970: 2_000_000_000)
        let acquisitionDate = baselineDate.addingTimeInterval(-60)
        let baseline = entry(
            kind: .initialBalance,
            delta: 3,
            at: baselineDate
        )
        let delayedAcquisition = entry(
            kind: .acquire,
            delta: 3,
            at: acquisitionDate
        )

        let events = PortfolioReplaySnapshotBuilder.rebaseDelayedInitialBalances([
            baseline,
            delayedAcquisition
        ])
        XCTAssertEqual(events.first(where: { $0.kind == .initialBalance })?.deltaQuantity, 0)

        let replay = PortfolioReplayEngine.replay(
            PortfolioReplayInput(
                events: events,
                observations: [observation(10, at: acquisitionDate.addingTimeInterval(-1))],
                epoch: acquisitionDate.addingTimeInterval(-3_600),
                through: baselineDate.addingTimeInterval(1),
                timeZoneIdentifier: "UTC"
            )
        )

        let live = try XCTUnwrap(replay.live)
        XCTAssertEqual(live.attribution.added, money(30))
        XCTAssertEqual(live.attribution.currentValue, money(30))
    }

    /// The ordinary resolution, and the one that happens in practice: the
    /// events arrive, which is itself proof that no baseline is needed. It must
    /// not wait out the grace period to notice.
    func testArrivingLedgerEndsTheDeferralWithoutWriting() throws {
        let context = try makeContext()
        let defaults = epochDefaults(#function)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let row = card(key: "remote", quantity: 1, dateAdded: now)
        context.insert(row)
        try context.save()

        XCTAssertThrowsError(
            try PortfolioEpoch.establishIfNeeded(
                context: context,
                defaults: defaults,
                at: now,
                isCloudSyncing: true
            )
        )

        // CloudKit delivers the acquisition that explains the row.
        _ = InventoryLedger(context: context).record(
            row,
            kind: .acquire,
            source: .scan,
            deltaQuantity: 1,
            occurredAt: now
        )
        try context.save()

        let opened = now.addingTimeInterval(1)
        try PortfolioEpoch.establishIfNeeded(
            context: context,
            defaults: defaults,
            at: opened,
            isCloudSyncing: true
        )

        let kinds = InventoryLedger(context: context).allEvents().map(\.kind)
        XCTAssertEqual(kinds, [.acquire], "no baseline may be added beside it")
        XCTAssertEqual(PortfolioEpoch.startedAt(defaults: defaults), opened)
    }

    /// A fresh install has nothing to protect and must not be delayed.
    func testEmptyCollectionOnASyncingDeviceOpensImmediately() throws {
        let context = try makeContext()
        let defaults = epochDefaults(#function)
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        try PortfolioEpoch.establishIfNeeded(
            context: context,
            defaults: defaults,
            at: now,
            isCloudSyncing: true
        )

        XCTAssertEqual(PortfolioEpoch.startedAt(defaults: defaults), now)
    }
}
