import XCTest
@testable import TradingCardScanner

final class UnresolvedScanStoreTests: XCTestCase {
    func testRoundTripRehydratesIdentifierAndNameEvidence() async throws {
        let (directory, store) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let identity = PokemonCatalogCardIdentity(
            providerID: "me02.5-015",
            setID: "me02.5",
            setName: "Ascended Heroes",
            localID: "015",
            name: "Dustox",
            releaseYear: 2026,
            thumbnailURL: URL(string: "https://example.invalid/dustox.png")
        )
        let subject = ScanSubject(
            identifier: .pokemon(
                setCode: "ASC",
                cardNumber: "015",
                printedTotal: 217,
                setDefinition: SetCodeMap.definitions["ASC"]!
            ),
            inferredNameReadings: ["dustox"]
        )
        let row = UnresolvedScan(
            id: UUID(uuidString: "BCB9AB91-4135-4F84-8C8C-7FE2273CB66C")!,
            subject: subject,
            reason: .noConfirmedMatch,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            candidates: [identity],
            requestEvidence: UnresolvedScanRequestEvidence(
                catalogIdentifier: "ASC 015/217",
                titleReadings: ["dustox"]
            )
        )

        await store.save([row])
        let restored = await store.load(registry: .bundledSeed)

        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].id, row.id)
        XCTAssertEqual(restored[0].displayIdentifier, "ASC 15/217")
        XCTAssertEqual(restored[0].requestEvidence.catalogIdentifier, "ASC 015/217")
        XCTAssertEqual(restored[0].requestEvidence.titleReadings, ["dustox"])
        XCTAssertEqual(restored[0].subject.inferredNameReadings, ["dustox"])
        XCTAssertEqual(restored[0].candidateHints, [
            UnresolvedCandidateHint(providerID: "me02.5-015", name: "Dustox")
        ])
        XCTAssertFalse(restored[0].isReadOnly)
    }

    func testRoundTripPreservesSlabIdentityEvidence() async {
        let (directory, store) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let slab = GradedSlabEvidence(
            company: .psa,
            grade: CardGrade(value: "10"),
            certificationNumber: "12345678",
            labelCardText: ["Dustox"],
            printedFinish: .holo,
            printedPrintRun: .firstEdition
        )
        let row = UnresolvedScan(
            subject: ScanSubject(
                identifier: .pokemon(
                    setCode: "ASC",
                    cardNumber: "015",
                    printedTotal: 217,
                    setDefinition: SetCodeMap.definitions["ASC"]!
                ),
                slab: slab
            ),
            reason: .providerUnavailable
        )

        await store.save([row])
        let restored = await store.load(registry: .bundledSeed)

        XCTAssertEqual(restored.first?.subject.slab, slab)
    }

    func testStoreKeepsOnlyNewestFiftyRows() async {
        let (directory, store) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rows = (0..<55).map { index in
            UnresolvedScan(
                id: UUID(),
                subject: historicalSubject(localID: String(index + 1)),
                reason: .lookupFailed,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        await store.save(rows)
        let restored = await store.load(registry: .bundledSeed)

        XCTAssertEqual(restored.count, 50)
        XCTAssertEqual(restored.first?.createdAt, Date(timeIntervalSince1970: 5))
        XCTAssertEqual(restored.last?.createdAt, Date(timeIntervalSince1970: 54))
    }

    func testCorruptFileLoadsAsEmpty() async throws {
        let (directory, store) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: directory.appendingPathComponent("unresolved-scans.json"))

        let restored = await store.load(registry: .bundledSeed)
        XCTAssertTrue(restored.isEmpty)
    }

    func testUnsupportedSavedSetIsReadOnlyAndCanBeDismissed() async {
        let (directory, store) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let unknown = PokemonSetDefinition(
            printedCode: "ZZZ",
            tcgdexSetID: "unknown-set",
            officialCount: 123,
            releaseIndex: 900
        )
        let row = UnresolvedScan(
            subject: ScanSubject(identifier: .pokemon(
                setCode: "ZZZ",
                cardNumber: "007",
                printedTotal: 123,
                setDefinition: unknown
            )),
            reason: .noCatalogEntry
        )

        await store.save([row])
        let restored = await store.load(registry: .bundledSeed)

        XCTAssertEqual(restored.count, 1)
        XCTAssertTrue(restored[0].isReadOnly)
        XCTAssertEqual(restored[0].displayIdentifier, "ZZZ 7/123")
    }

    func testReadOnlySavedSetKeepsItsOriginalRecordUntilRegistryCanRehydrateIt() async {
        let (directory, store) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let unknown = PokemonSetDefinition(
            printedCode: "ZZZ",
            tcgdexSetID: "unknown-set",
            officialCount: 123,
            releaseIndex: 900
        )
        let original = UnresolvedScan(
            subject: ScanSubject(identifier: .pokemon(
                setCode: "ZZZ",
                cardNumber: "007",
                printedTotal: 123,
                setDefinition: unknown
            )),
            reason: .noCatalogEntry
        )
        await store.save([original])
        let readOnly = await store.load(registry: .bundledSeed)
        XCTAssertTrue(readOnly.first?.isReadOnly == true)

        await store.save(readOnly)
        let descriptor = PokemonCatalogSetDescriptor(
            providerSetID: "unknown-set",
            displayName: "New Set",
            releaseDate: "2026-01-01",
            releaseOrder: 900,
            recognitionKind: .expansion,
            printedCode: "ZZZ",
            officialCount: 123,
            printedPrefix: nil,
            catalogLocalIDPrefix: nil,
            localIDPadWidth: nil,
            scanEnabled: true,
            logoURL: nil,
            symbolURL: nil,
            rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules
        )
        let registry = PokemonCatalogRegistry(
            release: PokemonCatalogRelease(
                schemaVersion: PokemonCatalogRelease.currentSchemaVersion,
                revision: 1,
                generatedAt: .now,
                sets: [descriptor]
            )
        )

        let restored = await store.load(registry: registry)
        XCTAssertEqual(restored.count, 1)
        XCTAssertFalse(restored[0].isReadOnly)
        guard case let .pokemon(code, localID, denominator, _) = restored[0].identifier else {
            return XCTFail("the saved printed set code was lost before the registry loaded")
        }
        XCTAssertEqual(code, "ZZZ")
        XCTAssertEqual(localID, "007")
        XCTAssertEqual(denominator, 123)
    }

    func testMagicLanguageSurvivesAStoreRoundTrip() async {
        let (directory, store) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let row = UnresolvedScan(
            subject: ScanSubject(identifier: .magic(
                setCode: "TST",
                collectorNumber: "12",
                language: "ja",
                contentKind: .regular
            )),
            reason: .lookupFailed
        )
        await store.save([row])

        let restored = await store.load(registry: .bundledSeed)
        guard case let .magic(_, _, language, _) = restored.first?.identifier else {
            return XCTFail("expected a Magic unresolved row")
        }
        XCTAssertEqual(language, "ja")
    }

    func testDuplicateRecordIDsLoadOnlyOnceUsingTheLatestRecord() async throws {
        let (directory, store) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let first = UnresolvedScan(
            id: id,
            subject: ScanSubject(identifier: .pokemon(
                setCode: "TST",
                cardNumber: "001",
                printedTotal: 10,
                setDefinition: PokemonSetDefinition(
                    printedCode: "TST",
                    tcgdexSetID: "test-set",
                    officialCount: 10,
                    releaseIndex: 1
                )
            )),
            reason: .noCatalogEntry
        )
        let second = UnresolvedScan(
            id: id,
            subject: first.subject,
            reason: .lookupFailed
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let records = [UnresolvedScanRecord(scan: first), UnresolvedScanRecord(scan: second)]
        try JSONEncoder().encode(records).write(
            to: directory.appendingPathComponent("unresolved-scans.json")
        )

        let restored = await store.load(registry: .bundledSeed)
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.id, id)
        XCTAssertEqual(restored.first?.reason, .lookupFailed)
    }

    private func makeStore() -> (URL, UnresolvedScanStore) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UnresolvedScanStoreTests-\(UUID().uuidString)", isDirectory: true)
        return (directory, UnresolvedScanStore(
            fileURL: directory.appendingPathComponent("unresolved-scans.json")
        ))
    }

    private func historicalSubject(localID: String) -> ScanSubject {
        ScanSubject(identifier: .pokemonHistorical(
            PokemonHistoricalScanEvidence(
                number: PokemonPrintedNumberEvidence(
                    localID: localID,
                    denominator: 109,
                    scheme: .officialSet
                ),
                titleCandidates: ["dustox"]
            )
        ))
    }
}
