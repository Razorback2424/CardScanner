import Foundation
import XCTest
@testable import TradingCardScanner

final class BrowsePriceVariantDescriptorTests: XCTestCase {
    func testV1DescriptorsStayPinnedForSupportedVariants() {
        let expected: [(PhysicalVariant, String)] = [
            (.normal, "pokemon.normal"),
            (.holo, "pokemon.holo"),
            (.reverse, "pokemon.reverse"),
            (.firstEdition, "pokemon.first-edition"),
            (.pokeBall, "pokemon.poke-ball"),
            (.masterBall, "pokemon.master-ball"),
            (.duskBall, "pokemon.dusk-ball"),
            (.friendBall, "pokemon.friend-ball"),
            (.quickBall, "pokemon.quick-ball"),
            (.loveBall, "pokemon.love-ball"),
            (.nonfoil, "magic.nonfoil"),
            (.foil, "magic.foil"),
            (.etched, "magic.etched")
        ]

        for (variant, value) in expected {
            XCTAssertEqual(
                variant.browsePriceHistoryDescriptorV1,
                BrowsePriceVariantDescriptor(schemaVersion: 1, value: value),
                variant.id
            )
        }
    }

    func testDescriptorIgnoresPresentationLabel() {
        let first = PhysicalVariant(id: "foil", label: "Foil")
        let renamed = PhysicalVariant(id: "foil", label: "A different label")
        XCTAssertEqual(
            first.browsePriceHistoryDescriptorV1,
            renamed.browsePriceHistoryDescriptorV1
        )
    }

    func testUnsupportedVariantFailsClosed() {
        XCTAssertNil(
            PhysicalVariant(id: "future-finish", label: "Future finish")
                .browsePriceHistoryDescriptorV1
        )
        XCTAssertNil(
            BrowsePriceQuote(
                printingID: "printing",
                setID: "set",
                variant: PhysicalVariant(id: "future-finish", label: "Future finish"),
                amountUSD: 1,
                marketSource: .tcgplayer,
                transportProvider: .pokemonTCGIO,
                providerUpdatedAt: Date()
            )
        )
    }
}

final class BrowsePriceObservationDayResolverTests: XCTestCase {
    func testPokemonSlashDateUsesUTCProviderDay() {
        let resolved = BrowsePriceObservationDayResolver.pokemonTCGIO(
            updatedAt: "2025/02/03"
        )
        XCTAssertEqual(resolved?.day.rawValue, "2025-02-03")
        XCTAssertEqual(resolved?.providerUpdatedAt, BrowsePriceDay(rawValue: "2025-02-03")?.date)
    }

    func testInvalidTimestampDoesNotFallBackToFetchTime() {
        XCTAssertNil(BrowsePriceObservationDayResolver.pokemonTCGIO(updatedAt: "not-a-date"))
        XCTAssertNil(BrowsePriceObservationDayResolver.tcgdex(updatedAt: nil))
        XCTAssertNil(BrowsePriceObservationDayResolver.scryfallDataset(updatedAt: nil))
    }

    func testScryfallStampIsAProviderDay() {
        let date = BrowsePriceDay(rawValue: "2025-02-03")!.date.addingTimeInterval(23 * 60 * 60)
        let resolved = BrowsePriceObservationDayResolver.scryfallDataset(updatedAt: date)
        XCTAssertEqual(resolved?.day.rawValue, "2025-02-03")
    }
}

final class BrowsePriceHistoryStoreTests: XCTestCase {
    func testFirstObservationPersistsAndSameObservationDeduplicates() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BrowsePriceHistoryStore(root: root)
        let quote = try XCTUnwrap(makeQuote(day: "2025-02-03", amount: 4))

        try await store.record(quote, game: .pokemon)
        try await store.record(quote, game: .pokemon)

        let series = await store.series(game: .pokemon, setID: "pokemon:sv01", printingID: "p1")
        let diagnostics = await store.diagnostics()
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0].points.count, 1)
        XCTAssertEqual(diagnostics.deduplicatedObservationCount, 1)
    }

    func testNewerSameDayReplacesOlderAndOlderCannotOverwrite() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BrowsePriceHistoryStore(root: root)
        let day = BrowsePriceDay(rawValue: "2025-02-03")!.date
        let older = try XCTUnwrap(makeQuote(date: day.addingTimeInterval(60), amount: 4))
        let newer = try XCTUnwrap(makeQuote(date: day.addingTimeInterval(120), amount: 7))
        let latestAgain = try XCTUnwrap(makeQuote(date: day.addingTimeInterval(90), amount: 2))

        try await store.record(older, game: .pokemon)
        try await store.record(newer, game: .pokemon)
        try await store.record(latestAgain, game: .pokemon)

        let series = await store.series(game: .pokemon, setID: "pokemon:sv01", printingID: "p1")
        XCTAssertEqual(series.first?.points.first?.amountUSD, 7)
    }

    func testRetentionUsesNewestProviderDayAndKeepsFinishesAndSourcesSeparate() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BrowsePriceHistoryStore(root: root)

        let first = try XCTUnwrap(makeQuote(day: "2025-01-01", amount: 1))
        let day91 = try XCTUnwrap(makeQuote(day: "2025-04-01", amount: 2))
        let foil = try XCTUnwrap(
            BrowsePriceQuote(
                printingID: "p1",
                setID: "pokemon:sv01",
                variant: .holo,
                amountUSD: 3,
                marketSource: .tcgplayer,
                transportProvider: .pokemonTCGIO,
                providerUpdatedAt: day91.providerUpdatedAt
            )
        )
        let scryfall = try XCTUnwrap(
            BrowsePriceQuote(
                printingID: "p1",
                setID: "pokemon:sv01",
                variant: .normal,
                amountUSD: 4,
                marketSource: .scryfall,
                transportProvider: .scryfall,
                providerUpdatedAt: day91.providerUpdatedAt
            )
        )

        try await store.record(first, game: .pokemon)
        try await store.record([day91, foil], game: .pokemon)
        try await store.record(scryfall, game: .pokemon)

        let series = await store.series(game: .pokemon, setID: "pokemon:sv01", printingID: "p1")
        XCTAssertEqual(series.count, 3)
        XCTAssertFalse(series.contains { $0.points.contains { $0.day.rawValue == "2025-01-01" } })
        XCTAssertNotEqual(series[0].key, series[1].key)
    }

    func testSeparateSetsAndCorruptFileAreIsolated() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BrowsePriceHistoryStore(root: root)
        let quote = try XCTUnwrap(makeQuote(day: "2025-02-03", amount: 4))
        try await store.record(quote, game: .pokemon)

        let corruptURL = await store.storageURL(game: .magic, setID: "magic:neo")
        try Data("corrupt".utf8).write(to: corruptURL)
        let corruptSeries = await store.series(game: .magic, setID: "magic:neo")
        let diagnostics = await store.diagnostics()
        XCTAssertTrue(corruptSeries.isEmpty)
        XCTAssertEqual(diagnostics.corruptFileRecoveryCount, 1)
        XCTAssertEqual(diagnostics.setCount, 1)
    }

    func testUnsupportedPriceSourceCannotEnterHistory() {
        let normalized = NormalizedPrice(
            unitMarketPriceUSD: 4,
            currencyCode: "USD",
            source: .cardmarket,
            sourceVariantID: "normal",
            sourceUpdatedAt: Date(),
            fetchedAt: Date()
        )
        XCTAssertNil(
            BrowsePriceQuote.from(
                normalizedPrice: normalized,
                printingID: "p1",
                setID: "pokemon:sv01",
                variant: .normal,
                transportProvider: .pokemonTCGIO
            )
        )
    }

    func testLegacyBulkCacheIsIncompatibleWithStage4A() throws {
        let data = Data(#"{"valuesByCardID":{"sv01|1":{"normal":4.0}}}"#.utf8)
        let map = try JSONDecoder().decode(PokemonBulkPriceMap.self, from: data)
        XCTAssertFalse(map.isStage4Compatible)
        XCTAssertNil(map.providerUpdatedAt(for: "sv01-1"))
        XCTAssertEqual(map.price(for: "sv01-1", variant: .normal), 4)
    }

    private func makeQuote(day: String, amount: Double) -> BrowsePriceQuote? {
        guard let date = BrowsePriceDay(rawValue: day)?.date else { return nil }
        return makeQuote(date: date.addingTimeInterval(12 * 60 * 60), amount: amount)
    }

    private func makeQuote(date: Date, amount: Double) -> BrowsePriceQuote? {
        BrowsePriceQuote(
            printingID: "p1",
            setID: "pokemon:sv01",
            variant: .normal,
            amountUSD: amount,
            marketSource: .tcgplayer,
            transportProvider: .pokemonTCGIO,
            providerUpdatedAt: date
        )
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("browse-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

final class BrowsePriceHistoryChartModelTests: XCTestCase {
    func testOnePointIsInsufficientHistory() {
        let model = BrowsePriceHistoryChartModel(series: [series(points: ["2025-02-03"])])
        XCTAssertFalse(model.hasSufficientHistory)
    }

    func testConsecutivePointsProduceOneSegment() {
        let model = BrowsePriceHistoryChartModel(
            series: [series(points: ["2025-02-03", "2025-02-04"])]
        )
        XCTAssertTrue(model.hasSufficientHistory)
        XCTAssertEqual(model.segments.count, 1)
        XCTAssertEqual(model.segments[0].points.count, 2)
    }

    func testMissingDateBreaksTheLine() {
        let model = BrowsePriceHistoryChartModel(
            series: [series(points: ["2025-02-03", "2025-02-04", "2025-02-07", "2025-02-08"])]
        )
        XCTAssertEqual(model.segments.count, 2)
        XCTAssertEqual(model.segments.map { $0.points.count }, [2, 2])
    }

    private func series(points: [String]) -> BrowsePricePersistedSeries {
        BrowsePricePersistedSeries(
            key: BrowsePriceSeriesKey(
                printingID: "p1",
                variantDescriptor: PhysicalVariant.normal.browsePriceHistoryDescriptorV1!,
                marketSource: .tcgplayer
            ),
            points: points.enumerated().map { index, value in
                BrowsePriceHistoryPoint(
                    day: BrowsePriceDay(rawValue: value)!,
                    amountUSD: Double(index + 1),
                    providerUpdatedAt: BrowsePriceDay(rawValue: value)!.date,
                    transportProvider: .pokemonTCGIO
                )
            }
        )
    }
}
