import XCTest
@testable import TradingCardScanner

/// What one scanned card costs in HTTP requests.
///
/// The resolver tests all feed fixed evidence to a pure function, so none of
/// them can see the property that actually matters at the camera: scanning one
/// physical card must not scale network work with the number of frames Vision
/// happens to read it in.
final class HistoricalCatalogRequestTests: XCTestCase {
    /// Counts every outbound call, and can be told to fail the directory to
    /// reproduce a stalled network.
    private actor CountingSource: PokemonHistoricalCatalogSource {
        private(set) var directoryRequests = 0
        private(set) var setRequests = 0
        private(set) var cardRequests = 0
        private var directoryFailuresRemaining: Int

        init(directoryFailuresRemaining: Int = 0) {
            self.directoryFailuresRemaining = directoryFailuresRemaining
        }

        static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
            try JSONDecoder().decode(type, from: Data(json.utf8))
        }

        func historicalSetDirectory() async throws -> [CatalogSetReference] {
            directoryRequests += 1
            if directoryFailuresRemaining > 0 {
                directoryFailuresRemaining -= 1
                throw URLError(.timedOut)
            }
            return try Self.decode(
                [CatalogSetReference].self,
                from: #"[{"id":"base1","name":"Base Set","cardCount":{"total":102,"official":102}}]"#
            )
        }

        func historicalSet(id: String) async throws -> TCGdexSetCatalog {
            setRequests += 1
            return try Self.decode(
                TCGdexSetCatalog.self,
                from: #"""
                { "id": "base1", "name": "Base Set",
                  "cardCount": { "total": 102, "official": 102 },
                  "cards": [ { "id": "base1-19", "localId": "19", "name": "Dugtrio" } ] }
                """#
            )
        }

        func historicalCard(id: String) async throws -> TCGdexCard {
            cardRequests += 1
            let components = id.split(separator: "-", maxSplits: 1).map(String.init)
            let setID = components.first ?? "base1"
            let localID = setID == "ecard2"
                ? "1"
                : (components.count == 2 ? components[1] : "19")
            return try Self.decode(
                TCGdexCard.self,
                from: """
                { "id": "\(id)", "localId": "\(localID)", "name": "Dugtrio",
                  "set": { "id": "\(setID)", "name": "Base Set",
                           "cardCount": { "total": 102, "official": 102 } } }
                """
            )
        }
    }

    private func evidence(title: String) throws -> PokemonHistoricalScanEvidence {
        let identifier = try XCTUnwrap(
            PokemonHistoricalScanParser.parse(numberLines: ["19/102"], titleLines: [title])
        )
        guard case let .pokemonHistorical(value) = identifier else {
            throw NSError(domain: "HistoricalCatalogRequestTests", code: 1)
        }
        return value
    }

    /// The regression. Title OCR is not stable frame to frame — that is why the
    /// evidence keeps every observation — but the *network* work depends only on
    /// the printed number and the resolved provider id. Re-reading one card must
    /// therefore cost nothing after the first resolution.
    func testRepeatedFramesOfOneCardCostOneRequestEach() async throws {
        let source = CountingSource()
        let catalog = PokemonHistoricalCatalog(service: source)

        // The same physical card, read three times, with the title landing
        // slightly differently each time. This is ordinary OCR behaviour.
        for title in ["Dugtrio", "Dugtrio ", "DUGTRIO"] {
            _ = try await catalog.card(for: try evidence(title: title))
        }

        let directory = await source.directoryRequests
        let sets = await source.setRequests
        let cards = await source.cardRequests
        XCTAssertEqual(directory, 1, "the set directory is reference data")
        XCTAssertEqual(sets, 1, "one candidate set, fetched once")
        XCTAssertEqual(cards, 1, "one card, fetched once — not once per frame")
    }

    /// A stalled directory must not be re-requested by every following frame.
    /// Clearing the memo on failure with no cooldown turns one timeout into a
    /// request per frame, which is what buries the connection pool.
    func testStalledDirectoryIsNotRetriedEveryFrame() async throws {
        let source = CountingSource(directoryFailuresRemaining: 8)
        let catalog = PokemonHistoricalCatalog(service: source)

        for title in ["Dugtrio", "Dugtrio ", "DUGTRIO", "Dugtrlo", "Dugtrio."] {
            _ = try? await catalog.card(for: try evidence(title: title))
        }

        let directory = await source.directoryRequests
        XCTAssertLessThanOrEqual(
            directory, 2,
            "a stalled directory may be retried, but not once per frame (was \(directory))"
        )
    }

    func testCardRequestMemoEvictsLeastRecentlyUsedEntries() async throws {
        let source = CountingSource()
        let catalog = PokemonHistoricalCatalog(service: source, cardTaskCapacity: 2)
        let evidence = PokemonHistoricalScanEvidence(
            number: PokemonPrintedNumberEvidence(
                localID: "1",
                denominator: 32,
                scheme: .subset(prefix: "H")
            ),
            titleCandidates: [CatalogIdentityNormalization.canonicalText("Dugtrio")]
        )
        let identities = (1...3).map {
            PokemonCatalogCardIdentity(
                providerID: "ecard2-\($0)",
                setID: "ecard2",
                setName: "e-Card",
                localID: "1",
                name: "Dugtrio"
            )
        }

        for identity in identities {
            _ = try await catalog.card(for: identity, matching: evidence)
        }
        _ = try await catalog.card(for: identities[0], matching: evidence)

        let cards = await source.cardRequests
        XCTAssertEqual(
            cards,
            4,
            "the oldest resolved card should be refetched after the two-entry memo fills"
        )
    }
}
