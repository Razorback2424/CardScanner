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

    private actor MembershipSource: PokemonHistoricalCatalogSource {
        static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
            try JSONDecoder().decode(type, from: Data(json.utf8))
        }

        func historicalSetDirectory() async throws -> [CatalogSetReference] {
            [
                CatalogSetReference(
                    id: "pl1",
                    name: "Platinum",
                    cardCount: TCGdexCardCount(total: 127, official: 127)
                )
            ]
        }

        func historicalSet(id: String) async throws -> TCGdexSetCatalog {
            try Self.decode(
                TCGdexSetCatalog.self,
                from: #"""
                { "id": "pl1", "name": "Platinum", "releaseDate": "2009-02-11",
                  "cardCount": { "total": 127, "official": 127 },
                  "cards": [ { "id": "pl1-47", "localId": "47", "name": "Crobat G" } ] }
                """#
            )
        }

        func historicalCard(id: String) async throws -> TCGdexCard {
            let isClassic = id.caseInsensitiveCompare("30th-c-011") == .orderedSame
            let isClassicPikachu = id.caseInsensitiveCompare("30th-c-014") == .orderedSame
            let setID = isClassic || isClassicPikachu ? "30th-c" : "pl1"
            let setName = isClassic || isClassicPikachu
                ? "30th Celebration Classic Collection" : "Platinum"
            let localID = isClassicPikachu ? "014" : (isClassic ? "011" : "47")
            return TCGdexCard(
                id: id,
                localId: localID,
                name: isClassicPikachu ? "Pikachu" : "Crobat G",
                image: nil,
                rarity: nil,
                set: TCGdexSetBrief(
                    id: setID,
                    name: setName,
                    cardCount: TCGdexCardCount(total: 127, official: 127)
                ),
                variants: nil,
                pricing: nil,
                variantsDetailed: nil
            )
        }
    }

    private actor CelebrationsUmbreonSource: PokemonHistoricalCatalogSource {
        let directoryHasOriginalSet: Bool
        let originalName: String?
        private(set) var cardRequests = 0

        init(directoryHasOriginalSet: Bool = true, originalName: String? = "Umbreon ★") {
            self.directoryHasOriginalSet = directoryHasOriginalSet
            self.originalName = originalName
        }

        func historicalSetDirectory() async throws -> [CatalogSetReference] {
            directoryHasOriginalSet ? [CatalogSetReference(id: "pop5", name: "POP Series 5",
                cardCount: TCGdexCardCount(total: 17, official: 17))] : []
        }

        func historicalSet(id: String) async throws -> TCGdexSetCatalog {
            // Relevant identity projected from the retained live POP Series 5
            // inventory. The original is not present in the bundled snapshot.
            let cards = originalName.map { [["id": "pop5-17", "localId": "17", "name": $0]] } ?? []
            let object: [String: Any] = ["id": "pop5", "name": "POP Series 5",
                "cardCount": ["total": 17, "official": 17], "cards": cards]
            return try JSONDecoder().decode(TCGdexSetCatalog.self, from: JSONSerialization.data(withJSONObject: object))
        }

        func historicalCard(id: String) async throws -> TCGdexCard {
            cardRequests += 1
            guard id == "cel25cc-CC015" else { throw URLError(.badServerResponse) }
            return try JSONDecoder().decode(TCGdexCard.self, from: Data(#"{"id":"cel25cc-CC015","localId":"CC015","name":"Umbreon ☆","set":{"id":"cel25cc","name":"Celebrations Classic Collection","cardCount":{"total":25,"official":25}},"variants":{"firstEdition":false,"holo":true,"normal":false,"reverse":false}}"#.utf8))
        }
    }

    private func evidence(title: String) throws -> PokemonHistoricalScanEvidence {
        let identifier = try XCTUnwrap(
            PokemonHistoricalScanParser.parse(numberLines: ["19/102"], titleLines: [title])
        )
        guard case let .pokemonHistorical(value) = identifier.legacyIdentity else {
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

    func testSelectedMembershipIdentityFetchesProviderCardButKeepsPrintedNumber() async throws {
        let membership = PokemonCatalogMembershipRecognition(members: [
            .init(
                providerCardID: "30th-c-011",
                canonicalName: "crobat g",
                printedLocalID: "47",
                printedDenominator: 127
            )
        ])
        let registry = PokemonCatalogRegistry(
            release: PokemonCatalogRelease(
                revision: 1,
                generatedAt: .now,
                sets: [
                    PokemonCatalogSetDescriptor(
                        providerSetID: "30th-c",
                        displayName: "30th Celebration Classic Collection",
                        releaseDate: "2026-09-16",
                        releaseOrder: 23,
                        recognitionKind: .notScannable,
                        printedCode: nil,
                        officialCount: nil,
                        printedPrefix: nil,
                        catalogLocalIDPrefix: nil,
                        localIDPadWidth: nil,
                        scanEnabled: false,
                        logoURL: nil,
                        symbolURL: nil,
                        membershipRecognition: membership
                    )
                ]
            )
        )
        let identifier = try XCTUnwrap(
            PokemonHistoricalScanParser.parse(numberLines: ["47/127"], titleLines: ["Crobat G"])
        )
        guard case let .pokemonHistorical(evidence) = identifier.legacyIdentity else {
            return XCTFail("Expected historical evidence")
        }
        let identity = PokemonCatalogCardIdentity(
            providerID: "30th-c-011",
            setID: "30th-c",
            setName: "30th Celebration Classic Collection",
            localID: "47",
            name: "Crobat G",
            releaseYear: 2026
        )
        let catalog = PokemonHistoricalCatalog(service: MembershipSource())

        let identified = try await catalog.card(
            for: identity,
            matching: evidence,
            registry: registry
        )
        guard case let .pokemon(card, setCode) = identified.legacyIdentity else {
            return XCTFail("Expected a Pokémon card")
        }
        XCTAssertEqual(card.id, "30th-c-011")
        XCTAssertEqual(card.set.id, "30th-c")
        XCTAssertEqual(card.localId, "47")
        XCTAssertEqual(card.set.cardCount.official, 127)
        XCTAssertEqual(setCode, "30TH-C")

        let platinumIdentity = PokemonCatalogCardIdentity(
            providerID: "pl1-47",
            setID: "pl1",
            setName: "Platinum",
            localID: "47",
            name: "Crobat G",
            releaseYear: 2009
        )
        let platinum = try await catalog.card(
            for: platinumIdentity,
            matching: evidence,
            registry: registry
        )
        guard case let .pokemon(platinumCard, _) = platinum.legacyIdentity else {
            return XCTFail("Expected the historical Platinum card")
        }
        XCTAssertEqual(platinumCard.id, "pl1-47")
        XCTAssertEqual(platinumCard.localId, "47")
        XCTAssertEqual(platinumCard.set.id, "pl1")
    }

    func testLiveOriginalUmbreonAndCelebrationsRemakeRemainSeparateChoices() async throws {
        let catalog = PokemonHistoricalCatalog(service: CelebrationsUmbreonSource())
        let evidence = PokemonHistoricalScanEvidence(number: .init(localID: "17", denominator: 17,
            scheme: .officialSet), titleCandidates: ["Umbreon ☆"])
        do {
            _ = try await catalog.card(for: evidence, registry: .bundledSeed)
            XCTFail("The live original must prevent a unique Celebrations result")
        } catch PokemonHistoricalCatalogError.ambiguous(let candidates) {
            XCTAssertEqual(Set(candidates.map(\.providerID)), ["pop5-17", "cel25cc-CC015"])
        }
    }

    func testIncompleteOrContradictoryLiveOriginalCannotAutoSelectCelebrations() async throws {
        let evidence = PokemonHistoricalScanEvidence(number: .init(localID: "17", denominator: 17,
            scheme: .officialSet), titleCandidates: ["Umbreon ☆"])
        let registry = PokemonCatalogRegistry.bundledSeed
        let selected = try XCTUnwrap(PokemonHistoricalIdentityResolver.membershipIdentities(for: evidence, in: registry)
            .first { $0.providerID == "cel25cc-CC015" })
        for source in [CelebrationsUmbreonSource(directoryHasOriginalSet: false),
                       CelebrationsUmbreonSource(originalName: nil),
                       CelebrationsUmbreonSource(originalName: "Espeon")] {
            let catalog = PokemonHistoricalCatalog(service: source)
            do {
                _ = try await catalog.card(for: evidence, registry: registry)
                XCTFail("A partial original family cannot establish a unique reprint")
            } catch PokemonHistoricalCatalogError.unsupported {
                // No invented original metadata and no automatic reprint choice.
            }
            let automaticRequests = await source.cardRequests
            XCTAssertEqual(automaticRequests, 0)
            let explicit = try await catalog.card(for: selected, matching: evidence, registry: registry)
            XCTAssertEqual(explicit.providerID, "cel25cc-CC015")
            XCTAssertEqual(explicit.setCode, "CEL")
            guard case let .pokemon(card, _) = explicit.legacyIdentity else { return XCTFail("Expected Pokémon") }
            XCTAssertEqual(card.localId, "CC015")
            XCTAssertEqual(card.set.cardCount.official, 25)
            let selectedRequests = await source.cardRequests
            XCTAssertEqual(selectedRequests, 1)
        }
    }

    func testSelectedClassicPikachuFetchesProviderCardAndKeepsPrintedNumber() async throws {
        let registry = PokemonCatalogRegistry.bundledSeed
        let number = PokemonPrintedNumberEvidence(
            localID: "58",
            denominator: 102,
            scheme: .officialSet
        )
        let identity = try XCTUnwrap(PokemonHistoricalIdentityResolver.membershipIdentities(
            for: number,
            in: registry
        ).first { $0.providerID == "30th-c-014" })
        let evidence = PokemonHistoricalScanEvidence(number: number, titleCandidates: ["Pikachu"])
        let catalog = PokemonHistoricalCatalog(service: MembershipSource())

        guard case let .pokemon(card, setCode) = try await catalog.card(
            for: identity,
            matching: evidence,
            registry: registry
        ).legacyIdentity else {
            return XCTFail("Selected Classic Pikachu should resolve online")
        }
        XCTAssertEqual(card.id, "30th-c-014")
        XCTAssertEqual(card.set.id, "30th-c")
        XCTAssertEqual(card.localId, "58")
        XCTAssertEqual(card.set.cardCount.official, 102)
        XCTAssertEqual(setCode, "30C")
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

    /// TCGdex's records for originals that the bundled checklist may lack and
    /// for their Celebrations Classic reprints, which use `CC` local IDs.
    private actor CelebrationsSource: PokemonHistoricalCatalogSource {
        private static let cards: [String: (localID: String, name: String, set: String, count: Int)] = [
            "pop5-17": ("17", "Umbreon ★", "pop5", 17),
            "dp4-15": ("15", "Claydol", "dp4", 106),
            "cel25cc-CC015": ("CC015", "Umbreon ☆", "cel25cc", 25),
            "cel25cc-CC016": ("CC016", "Claydol", "cel25cc", 25)
        ]

        private let directoryHasOriginalSet: Bool
        private let originalName: String?

        init(directoryHasOriginalSet: Bool = true, originalName: String? = "Umbreon ★") {
            self.directoryHasOriginalSet = directoryHasOriginalSet
            self.originalName = originalName
        }

        func historicalSetDirectory() async throws -> [CatalogSetReference] {
            var directory = [
                CatalogSetReference(id: "dp4", name: "Great Encounters", cardCount: TCGdexCardCount(total: 106, official: 106))
            ]
            if directoryHasOriginalSet {
                directory.append(CatalogSetReference(
                    id: "pop5", name: "POP Series 5", cardCount: TCGdexCardCount(total: 17, official: 17)
                ))
            }
            return directory
        }

        func historicalSet(id: String) async throws -> TCGdexSetCatalog {
            var entries = Self.cards.filter { $0.value.set == id }
            if id == "pop5" {
                entries.removeAll()
                if let originalName {
                    entries["pop5-17"] = ("17", originalName, "pop5", 17)
                }
            }
            let cards = entries.map { #"{ "id": "\#($0.key)", "localId": "\#($0.value.localID)", "name": "\#($0.value.name)" }"# }
            let count = Self.cards.values.first { $0.set == id }?.count ?? 0
            return try JSONDecoder().decode(TCGdexSetCatalog.self, from: Data(#"""
                { "id": "\#(id)", "name": "\#(id)", "cardCount": { "total": \#(count), "official": \#(count) },
                  "cards": [\#(cards.joined(separator: ","))] }
                """#.utf8))
        }

        func historicalCard(id: String) async throws -> TCGdexCard {
            let value = try XCTUnwrap(Self.cards[id])
            return TCGdexCard(
                id: id, localId: value.localID, name: value.name, image: nil, rarity: nil,
                set: TCGdexSetBrief(id: value.set, name: value.set,
                                    cardCount: TCGdexCardCount(total: value.count, official: value.count)),
                variants: nil, pricing: nil, variantsDetailed: nil
            )
        }
    }

    private func celebrationsEvidence(_ number: String, _ title: String) throws -> PokemonHistoricalScanEvidence {
        let identifier = try XCTUnwrap(
            PokemonHistoricalScanParser.parse(numberLines: [number], titleLines: [title])
        )
        guard case let .pokemonHistorical(value) = identifier.legacyIdentity else {
            throw NSError(domain: "HistoricalCatalogRequestTests", code: 2)
        }
        return value
    }

    func testCelebrationsUmbreonIsAChoiceWhenOnlyTheLiveDirectoryHasTheOriginal() async throws {
        let catalog = PokemonHistoricalCatalog(service: CelebrationsSource())
        do {
            _ = try await catalog.card(for: try celebrationsEvidence("17/17", "Umbreon ☆"), registry: .bundledSeed)
            XCTFail("POP Series 5 Umbreon and its Celebrations reprint share 17/17")
        } catch PokemonHistoricalCatalogError.ambiguous(let matches) {
            XCTAssertEqual(matches.map(\.providerID), ["cel25cc-CC015", "pop5-17"])
            let original = try XCTUnwrap(matches.first { $0.providerID == "pop5-17" })
            let selected = try await catalog.card(
                for: original,
                matching: try celebrationsEvidence("17/17", "Umbreon ☆"),
                registry: .bundledSeed
            )
            XCTAssertEqual(selected.providerID, "pop5-17")
            XCTAssertEqual(selected.cardNumber, "17")
        }
    }

    func testSelectedCelebrationsReprintKeepsProviderNumberingForPriceAndArtwork() async throws {
        let source = CelebrationsSource()
        let catalog = PokemonHistoricalCatalog(service: source)
        let evidence = try celebrationsEvidence("15/106", "Claydol")
        let reprint = try XCTUnwrap(
            PokemonHistoricalIdentityResolver.membershipIdentities(for: evidence, in: .bundledSeed).first
        )
        XCTAssertEqual(reprint.localID, "15", "the choice still shows the printed number")

        let selected = try await catalog.card(for: reprint, matching: evidence, registry: .bundledSeed)
        XCTAssertEqual(selected.providerID, "cel25cc-CC016")
        XCTAssertEqual(selected.cardNumber, "CC016")
        XCTAssertEqual(selected.setCode, "CEL")
        guard case let .pokemon(card, _) = selected.legacyIdentity else {
            return XCTFail("Expected a Pokémon record")
        }
        XCTAssertEqual(card.set.id, "cel25cc")
        XCTAssertEqual(card.set.cardCount.official, 25)

        // Price refresh refetches the provider card and requires the same number.
        let response = try await source.historicalCard(id: "cel25cc-CC016")
        let stored = GamePriceIdentity.legacy(selected)
        XCTAssertTrue(stored.matches(.legacy(.pokemon(response, setCode: stored.displaySetCode))))

        // Artwork derives the reprint's own Limitless key, not main-set CEL 015.
        let artwork = CatalogCardArtworkSource(
            game: .pokemon, setCode: selected.setCode, collectorNumber: selected.cardNumber,
            thumbnailURL: nil, imageURL: nil, prefersFullSize: false,
            providerID: selected.providerID, providerSetID: "cel25cc"
        )
        let names = ([artwork.primaryURL].compactMap { $0 } + artwork.fallbacks).map(\.lastPathComponent)
        XCTAssertTrue(names.contains("CEL_CC16_R_EN_XS.png"), "\(names)")
        XCTAssertFalse(names.contains { $0.hasPrefix("CEL_015") }, "\(names)")
    }
}
