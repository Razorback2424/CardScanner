import XCTest
import MagicCatalogCore
import Foundation
import SwiftData
import Vision
import ImageIO
import CryptoKit
@testable import TradingCardScanner

final class MagicHistoricalIndexTests: XCTestCase {
    private let sourceContext = String(repeating: "a", count: 64)
    private let observed = MagicCatalogDate.parseDay("2026-10-06")!

    private func bundledData() throws -> Data {
        let index = try MagicHistoricalIndexSnapshot.loadBundled()
        return try MagicCatalogJSON.encode(index.artifact)
    }

    private func fixture(_ change: (inout [String: Any]) -> Void = { _ in }) throws -> MagicHistoricalIndexSnapshot {
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: bundledData()) as? [String: Any])
        change(&value)
        return try MagicHistoricalIndexSnapshot(data: JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
    }

    private func profiles(_ index: MagicHistoricalIndexSnapshot,
                          overrides: [MagicRecognitionPrintingOverride] = []) throws -> MagicRecognitionProfileSnapshot {
        try MagicRecognitionProfileSnapshot(descriptors: index.artifact.catalog.sets, overrides: overrides,
            indexGeneration: index.generation, catalogRevision: index.catalogRevision)
    }

    private func markAllayReviewed(_ value: inout [String: Any]) {
        var rows = value["records"] as! [[String: Any]]
        let position = rows.firstIndex { $0["name"] as? String == "Allay" && $0["setCode"] as? String == "exo" }!
        rows[position]["visibleCollectorNumber"] = true
        rows[position]["unresolvedDistinctions"] = [String]()
        value["records"] = rows
        var sources = value["sources"] as! [[String: Any]]
        sources.removeAll { $0["kind"] as? String == "scryfallCrossEra" }
        sources.append(["kind": "scryfallCrossEra", "url": "https://api.scryfall.com/cards/search?q=Allay&unique=prints",
                        "sha256": String(repeating: "c", count: 64), "dataDate": "2026-10-06"])
        value["sources"] = sources
        value["coverage"] = ["completeKeys": [["title": "allay", "collectorNumber": "1"]],
            "keyReceipts": [["key": ["title": "allay", "collectorNumber": "1"],
                "sourceSHA256": String(repeating: "c", count: 64),
                "printingIDs": [rows[position]["printingID"] as! String], "pageCount": 1,
                "resultCount": 1, "reconciliationVersion": 1]],
            "unresolvedKeys": [], "validUntil": "2026-10-06T12:00:00.000Z",
            "sourceContext": sourceContext, "missingSources": []] as [String: Any]
    }

    func testBundledPilotContainsExactIdentitiesAndCrossEraCollisionBlockers() throws {
        let index = try MagicHistoricalIndexSnapshot.loadBundled()
        let profile = try profiles(index)
        XCTAssertEqual(index.artifact.records.count, 150)
        XCTAssertEqual(index.artifact.records.filter(\.reconciled).count, 150)
        XCTAssertEqual(Set(index.artifact.records.map(\.printingID)).count, 150)
        let query = try index.query(title: "  ALLAY\n", collectorNumber: "1", profiles: profile,
                                    currentSourceContext: nil, now: observed)
        XCTAssertEqual(query.matchingRecords.map(\.printingID), ["f20a1c6d-ec6a-4bd6-b3b2-b997f71d41fc"])
        XCTAssertFalse(query.universeIsCurrent)
        XCTAssertEqual(query.eligiblePhaseOneRecords.count, 1, "reviewed provider front; device acceptance remains separate")
        XCTAssertFalse(profile.profile(setCode: "exo").acquisitionEnabled)
        let collision = try index.query(title: "Cataclysm", collectorNumber: "3", profiles: profile,
                                        currentSourceContext: nil, now: observed)
        XCTAssertEqual(Set(collision.matchingRecords.map(\.setCode)), ["exo", "v14"])
        XCTAssertFalse(collision.universeIsCurrent)
        let photographed = try index.query(title: "Survival of the Fittest", collectorNumber: "129",
            profiles: profile, currentSourceContext: index.artifact.coverage.sourceContext, now: observed)
        XCTAssertTrue(photographed.universeIsCurrent)
        XCTAssertEqual(photographed.eligiblePhaseOneRecords.map(\.printingID), ["c060c178-3c0e-493f-b6f0-ead5b1d6f191"])
    }

    func testEvidenceKeyPreservesNumberSuffixPunctuationAndLeadingZeroes() {
        XCTAssertNotEqual(MagicHistoricalEvidenceKey(title: "Allay", collectorNumber: "1"),
                          MagicHistoricalEvidenceKey(title: "Allay", collectorNumber: "01"))
        XCTAssertNotEqual(MagicHistoricalEvidenceKey(title: "Allay", collectorNumber: "1a"),
                          MagicHistoricalEvidenceKey(title: "Allay", collectorNumber: "1★"))
        XCTAssertEqual(MagicHistoricalEvidenceKey(title: "  Allay\n", collectorNumber: "1A"),
                       MagicHistoricalEvidenceKey(title: "allay", collectorNumber: "1a"))
    }

    func testExpiryOfflineAndCardLevelDriftInvalidatePreviouslyCurrentKey() throws {
        let index = try fixture(markAllayReviewed)
        let profile = try profiles(index)
        func query(_ time: Date, _ source: String?) throws -> MagicHistoricalIndexSnapshot.Query {
            try index.query(title: "Allay", collectorNumber: "1", profiles: profile,
                            currentSourceContext: source, now: time)
        }
        let current = try query(observed.addingTimeInterval(1), sourceContext)
        XCTAssertTrue(current.universeIsCurrent)
        XCTAssertEqual(current.eligiblePhaseOneRecords.count, 1)
        XCTAssertFalse(try query(observed.addingTimeInterval(12 * 60 * 60), sourceContext).universeIsCurrent)
        XCTAssertFalse(try query(observed, nil).universeIsCurrent)
        XCTAssertFalse(try query(observed, String(repeating: "b", count: 64)).universeIsCurrent)
        XCTAssertFalse(try query(observed.addingTimeInterval(-1), sourceContext).universeIsCurrent)
    }

    func testNewCollidingPrintingInsideExistingSetAndNewSetDoesNotBecomeUnique() throws {
        for setCode in ["exo", "m15"] {
            let index = try fixture { value in
                markAllayReviewed(&value)
                var records = value["records"] as! [[String: Any]]
                var added = records.first { $0["name"] as? String == "Allay" && $0["setCode"] as? String == "exo" }!
                added["printingID"] = "00000000-0000-4000-8000-000000000010"
                added["sourceIDs"] = ["00000000-0000-4000-8000-000000000011"]
                added["sourceFinishReferences"] = [String: [String]]()
                added["setCode"] = setCode
                added["reconciled"] = false
                added["unresolvedDistinctions"] = ["new_printing_unreconciled"]
                records.append(added)
                value["records"] = records
                var coverage = value["coverage"] as! [String: Any]
                var receipts = coverage["keyReceipts"] as! [[String: Any]]
                receipts[0]["printingIDs"] = ["f20a1c6d-ec6a-4bd6-b3b2-b997f71d41fc", added["printingID"] as! String]
                receipts[0]["resultCount"] = 2
                coverage["keyReceipts"] = receipts
                value["coverage"] = coverage
            }
            let result = try index.query(title: "Allay", collectorNumber: "1", profiles: profiles(index),
                                         currentSourceContext: sourceContext, now: observed)
            XCTAssertEqual(result.matchingRecords.count, 2)
            XCTAssertFalse(result.universeIsCurrent)
        }
    }

    func testLayoutLanguageNumberAndPhysicalDistinctionsGateAdmission() throws {
        let variants: [(String, Any)] = [("layout", "split"), ("layout", "unknown"), ("language", "fr"),
            ("paper", false), ("visibleCollectorNumber", NSNull()),
            ("unresolvedDistinctions", ["event_stamp_unknown"])]
        for (field, replacement) in variants {
            let index = try fixture { value in
                markAllayReviewed(&value)
                var records = value["records"] as! [[String: Any]]
                let i = records.firstIndex { $0["name"] as? String == "Allay" }!
                records[i][field] = replacement
                value["records"] = records
            }
            let result = try index.query(title: "Allay", collectorNumber: "1", profiles: profiles(index),
                                         currentSourceContext: sourceContext, now: observed)
            XCTAssertTrue(result.eligiblePhaseOneRecords.isEmpty, field)
            XCTAssertEqual(result.matchingRecords.count, 1, "unsupported matches must remain collision evidence")
        }
    }

    func testUnknownVersionsMissingSourcesDuplicateIDsAndOverlongFreshnessFailClosed() throws {
        for field in ["schemaVersion", "processingVersion", "profileVersion"] {
            XCTAssertThrowsError(try fixture { $0[field] = 99 })
        }
        XCTAssertThrowsError(try fixture { $0["sources"] = [] })
        XCTAssertThrowsError(try fixture { value in
            var records = value["records"] as! [[String: Any]]
            records.append(records[0]); value["records"] = records
        })
        XCTAssertThrowsError(try fixture { value in
            markAllayReviewed(&value)
            var coverage = value["coverage"] as! [String: Any]
            coverage["validUntil"] = "2026-10-08T00:00:00.000Z"
            value["coverage"] = coverage
        })
        XCTAssertThrowsError(try fixture { value in
            markAllayReviewed(&value)
            var sources = value["sources"] as! [[String: Any]]
            sources.removeAll { $0["kind"] as? String == "scryfallCrossEra" }
            value["sources"] = sources
        }, "a recent set-only capture cannot certify all-era uniqueness")
        XCTAssertThrowsError(try fixture { value in
            markAllayReviewed(&value)
            var coverage = value["coverage"] as! [String: Any]
            coverage["keyReceipts"] = []
            value["coverage"] = coverage
        })
        XCTAssertThrowsError(try fixture { value in
            markAllayReviewed(&value)
            var coverage = value["coverage"] as! [String: Any]
            coverage["missingSources"] = ["missing_shard"]
            value["coverage"] = coverage
        })
    }

    func testFinishReferencesRemainUnderOnePhysicalPrinting() throws {
        let index = try fixture { value in
            var records = value["records"] as! [[String: Any]]
            let i = records.firstIndex { $0["name"] as? String == "Allay" }!
            records[i]["finishes"] = ["nonfoil", "foil"]
            var refs = records[i]["sourceFinishReferences"] as! [String: [String]]
            refs["foil"] = ["00000000-0000-4000-8000-000000000013"]
            records[i]["sourceFinishReferences"] = refs
            value["records"] = records
        }
        let result = try index.query(title: "Allay", collectorNumber: "1", profiles: profiles(index),
                                     currentSourceContext: nil, now: observed)
        XCTAssertEqual(result.matchingRecords.count, 1)
        XCTAssertEqual(result.matchingRecords.first?.finishes, ["nonfoil", "foil"])
    }

    func testAtomicPairRejectsIndexProfileMismatchAndInvalidatesStaleChoices() async throws {
        let first = try fixture()
        let firstProfile = try profiles(first)
        let original = try MagicHistoricalLocalSnapshot(profiles: firstProfile, index: first)
        let store = MagicHistoricalLocalStore(snapshot: original)
        let changed = try fixture(markAllayReviewed)
        XCTAssertThrowsError(try MagicHistoricalLocalSnapshot(profiles: firstProfile, index: changed))
        let next = try MagicHistoricalLocalSnapshot(profiles: profiles(changed), index: changed)
        let activated = try await store.activate(next, expectedGeneration: original.generation)
        XCTAssertTrue(activated)
        let current = await store.isCurrent(original.generation)
        XCTAssertFalse(current)
        do {
            _ = try await store.activate(original, expectedGeneration: original.generation)
            XCTFail("stale pending choice must not publish")
        } catch {}
        let staleProfiles = try MagicRecognitionProfileSnapshot(descriptors: first.artifact.catalog.sets,
            indexGeneration: first.generation, catalogRevision: first.catalogRevision + 1)
        XCTAssertThrowsError(try first.query(title: "Allay", collectorNumber: "1", profiles: staleProfiles,
                                             currentSourceContext: nil, now: observed))
        let override = MagicRecognitionPrintingOverride(printingID: "f20a1c6d-ec6a-4bd6-b3b2-b997f71d41fc",
            setCode: "exo", route: .legacyNoCollectorNumber, reviewReference: "test-review")
        let overridden = try profiles(changed, overrides: [override])
        XCTAssertNotEqual(overridden.generation, next.generation)
        let query = try changed.query(title: "Allay", collectorNumber: "1", profiles: overridden,
                                      currentSourceContext: sourceContext, now: observed)
        XCTAssertTrue(query.eligiblePhaseOneRecords.isEmpty)
    }

    func testPilotLoadAndWarmQueryMeasurements() throws {
        var loads: [Double] = []
        for _ in 0..<10 {
            let start = Date()
            let index = try MagicHistoricalIndexSnapshot.loadBundled()
            loads.append(Date().timeIntervalSince(start) * 1000)
            XCTAssertEqual(index.artifact.records.count, 150)
        }
        let index = try MagicHistoricalIndexSnapshot.loadBundled()
        let profile = try profiles(index)
        var queries: [Double] = []
        for _ in 0..<1000 {
            let start = Date()
            let result = try index.query(title: "Allay", collectorNumber: "1", profiles: profile,
                                         currentSourceContext: nil, now: observed)
            queries.append(Date().timeIntervalSince(start) * 1000)
            XCTAssertEqual(result.matchingRecords.count, 1)
        }
        func percentile(_ samples: [Double], _ fraction: Double) -> Double {
            samples.sorted()[min(samples.count - 1, Int(Double(samples.count) * fraction))]
        }
        print("Magic historical simulator index load milliseconds p50=\(percentile(loads, 0.5)) p95=\(percentile(loads, 0.95)); warm query milliseconds p50=\(percentile(queries, 0.5)) p95=\(percentile(queries, 0.95))")
    }
}

final class MagicHistoricalRecognitionTests: XCTestCase {
    private func liveEvidence(_ title: String = "Counterspell", number: String? = "42") -> MagicHistoricalLiveEvidence {
        .init(title: title, collectorNumber: number, denominator: number == nil ? nil : 350,
            titleBounds: CGRect(x: 0.1, y: 0.9, width: 0.6, height: 0.03),
            numberBounds: number == nil ? nil : CGRect(x: 0.1, y: 0.03, width: 0.4, height: 0.03),
            encounterID: UUID(), recognitionVersion: MagicHistoricalLiveEvidence.version)
    }
    private func liveCard(_ title: String = "Counterspell", number: String = "42", layout: String = "normal") -> [String: Any] {
        ["object": "card", "id": "00000000-0000-4000-8000-000000000001",
         "oracle_id": "00000000-0000-4000-8000-000000000002", "set_id": "00000000-0000-4000-8000-000000000003",
         "name": title, "set": "7ed", "set_name": "Seventh Edition", "collector_number": number,
         "lang": "en", "games": ["paper"], "digital": false, "oversized": false, "layout": layout,
         "released_at": "2001-04-11", "finishes": ["nonfoil"]]
    }
    private func liveAdapter() -> MagicCatalogAdapter {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MagicHistoricalTestProtocol.self]
        return .init(source: ScryfallService(breaker: TCGdexCircuitBreaker(), session: URLSession(configuration: configuration)))
    }
    private func page(_ cards: [[String: Any]], total: Int? = nil, next: String? = nil) throws -> Data {
        var value: [String: Any] = ["object": "list", "has_more": next != nil, "total_cards": total ?? cards.count, "data": cards]
        if let next { value["next_page"] = next }
        return try JSONSerialization.data(withJSONObject: value)
    }

    func testGeneralHistoricalVocabularyAndFrameParserAreIndependentOfPilotCards() throws {
        XCTAssertGreaterThan(MagicHistoricalTitleVocabulary.names.count, 10000)
        XCTAssertEqual(MagicHistoricalTitleVocabulary.match("Birds of Daradise"), "Birds of Paradise")
        XCTAssertEqual(MagicHistoricalTitleVocabulary.match("Erhnam Dinn"), "Erhnam Djinn")
        XCTAssertNil(MagicHistoricalTitleVocabulary.match("Charizard"))
        for (title, number) in [("Counterspell", "42/350"), ("Tarmogoyf", "153/180"), ("Island", "237/249"), ("Dismember", "57/175")] {
            let result = MagicHistoricalLiveOCR.parse(lines: [
                .init(text: title, boundingBox: CGRect(x: 0.1, y: 0.9, width: 0.5, height: 0.03)),
                .init(text: number, boundingBox: CGRect(x: 0.1, y: 0.03, width: 0.3, height: 0.02))], encounterID: UUID())
            XCTAssertEqual(result?.title, title)
            XCTAssertNotNil(result?.collectorNumber)
        }
        let titleOnly = MagicHistoricalLiveOCR.parse(lines: [.init(text: "Black Lotus",
            boundingBox: CGRect(x: 0.1, y: 0.9, width: 0.5, height: 0.03))], encounterID: UUID())
        XCTAssertNotNil(titleOnly); XCTAssertNil(titleOnly?.collectorNumber)
        XCTAssertNil(MagicHistoricalLiveOCR.parse(lines: [.init(text: "Counterspell",
            boundingBox: CGRect(x: 0.1, y: 0.3, width: 0.5, height: 0.03))], encounterID: UUID()))
    }

    func testGeneralHistoricalWindowBoundsAbsenceAndNewEncounterLanguage() throws {
        var window = MagicHistoricalLiveWindow()
        let evidence = liveEvidence()
        XCTAssertTrue(window.begin(at: 0)); XCTAssertNil(window.observe(evidence))
        XCTAssertTrue(window.begin(at: 0.1))
        let first = try XCTUnwrap(window.observe(evidence))
        XCTAssertTrue(first.needsMagicEnglishConfirmation)
        XCTAssertFalse(try first.confirmingMagicEnglish().needsMagicEnglishConfirmation)
        XCTAssertNil(window.observe(nil))
        XCTAssertNil(window.observe(evidence))
        let second = try XCTUnwrap(window.observe(evidence))
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.needsMagicEnglishConfirmation)
        for i in 2..<6 { XCTAssertTrue(window.begin(at: Double(i) / 10)); XCTAssertNil(window.observe(nil)) }
        XCTAssertFalse(window.begin(at: 0.8), "missing text must not reset the retry budget")
        XCTAssertTrue(window.begin(at: 2))
        var stale = liveEvidence()
        stale = .init(title: stale.title, collectorNumber: stale.collectorNumber, denominator: stale.denominator,
            titleBounds: stale.titleBounds, numberBounds: stale.numberBounds, encounterID: stale.encounterID,
            recognitionVersion: "unknown")
        XCTAssertFalse(stale.valid)
    }

    func testHistoricalEraTypographyLevelersAndNumberSuffixes() throws {
        for (printed, canonical) in [("Æther Vial", "Aether Vial"), ("Lim-Dûl’s Vault", "Lim-Dûl's Vault"),
                                     ("Kongming, “Sleeping Dragon”", "Kongming, \"Sleeping Dragon\""),
                                     ("Student of Warfare", "Student of Warfare")] {
            let result = MagicHistoricalLiveOCR.parse(lines: [
                .init(text: printed, boundingBox: CGRect(x: 0.1, y: 0.9, width: 0.7, height: 0.04))], encounterID: UUID())
            XCTAssertEqual(result?.title, canonical)
            XCTAssertNotNil(try result?.identifier())
        }
        for number in ["001", "51a", "12★"] {
            let result = MagicHistoricalLiveOCR.parse(lines: [
                .init(text: "Counterspell", boundingBox: CGRect(x: 0.1, y: 0.9, width: 0.6, height: 0.03)),
                .init(text: number + "/350", boundingBox: CGRect(x: 0.1, y: 0.03, width: 0.4, height: 0.03))], encounterID: UUID())
            XCTAssertEqual(result?.collectorNumber, number)
        }
    }

    func testHistoricalOCRRejectsUnrelatedTitlesAndPreservesKnownSplitIdentity() throws {
        func line(_ text: String, x: CGFloat, y: CGFloat) -> RecognizedLine {
            .init(text: text, boundingBox: CGRect(x: x, y: y, width: 0.3, height: 0.03))
        }
        XCTAssertNil(MagicHistoricalLiveOCR.parse(lines: [line("Counterspell", x: 0.1, y: 0.9),
            line("Black Lotus", x: 0.1, y: 0.7)], encounterID: UUID()))
        XCTAssertNil(MagicHistoricalLiveOCR.parse(lines: [line("Counterspell", x: 0.1, y: 0.9),
            line("Black Lotus", x: 0.55, y: 0.9)], encounterID: UUID()))
        let split = MagicHistoricalLiveOCR.parse(lines: [line("Fire", x: 0.1, y: 0.9),
            line("Ice", x: 0.55, y: 0.9)], encounterID: UUID())
        XCTAssertEqual(split?.title, "Fire // Ice")
        let power = MagicHistoricalLiveOCR.parse(lines: [line("Counterspell", x: 0.1, y: 0.9),
            line("2/2", x: 0.1, y: 0.03)], encounterID: UUID())
        XCTAssertEqual(power?.title, "Counterspell"); XCTAssertNil(power?.collectorNumber)
        XCTAssertNil(MagicHistoricalLiveOCR.parse(lines: [.init(text: "Counterspell",
            boundingBox: CGRect(x: 0.1, y: 0.9, width: 0.6, height: 0.03), confidence: 0.1)], encounterID: UUID()))
    }

    func testHistoricalQuotedSearchIsLiteralAndOldLigatureProviderNamesAgree() async throws {
        for (title, providerName) in [("Kongming, \"Sleeping Dragon\"", "Kongming, \"Sleeping Dragon\""),
                                       ("Æther Vial", "Aether Vial")] {
            let card = liveCard(providerName)
            MagicHistoricalTestProtocol.handler = { request in
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value
                let searchTitle = title.replacingOccurrences(of: "\"", with: "")
                XCTAssertEqual(query, "!\"\(searchTitle)\" lang:en game:paper date<2014-07-18")
                return try self.page([card])
            }
            guard case let .needsPrintingChoice(_, choices) = try await liveAdapter().lookup(liveEvidence(title).identifier()) else {
                return XCTFail("literal quoted/ligature title")
            }
            XCTAssertEqual(choices.count, 1)
        }
        MagicHistoricalTestProtocol.handler = { _ in XCTFail("control characters must never reach transport"); return Data() }
        do { _ = try await liveAdapter().source.historicalPrintings(title: "Counterspell\rOR game:arena"); XCTFail("control characters") } catch {}
    }

    func testHistoricalBackFaceAndSplitAliasesHydrateRootPrinting() async throws {
        for (face, root, layout) in [("Insectile Aberration", "Delver of Secrets // Insectile Aberration", "transform"),
                                     ("Erayo's Essence", "Erayo, Soratami Ascendant // Erayo's Essence", "flip"),
                                     ("Ice", "Fire // Ice", "split")] {
            let card = liveCard(root, layout: layout).merging(["card_faces": [["name": face]]]) { _, new in new }
            MagicHistoricalTestProtocol.handler = { request in
                request.url?.path == "/cards/search" ? try self.page([card]) : try JSONSerialization.data(withJSONObject: card)
            }
            let adapter = liveAdapter(), identifier = try liveEvidence(face, number: nil).identifier().confirmingMagicEnglish()
            guard case let .needsPrintingChoice(_, choices) = try await adapter.lookup(identifier) else { return XCTFail("face alias") }
            let resolution = try await adapter.resolve(choices[0], for: identifier)
            XCTAssertEqual(resolution.card.name, root)
            XCTAssertEqual(resolution.card.physicalPrintingID, card["id"] as? String)
        }
    }

    func testHistoricalSameTitleDifferentOraclesRequireExactChoiceThroughSharedCatalog() async throws {
        let a = liveCard("B.F.M. (Big Furry Monster)", number: "28")
        let b = liveCard("B.F.M. (Big Furry Monster)", number: "29").merging([
            "id": "00000000-0000-4000-8000-000000000004",
            "oracle_id": "00000000-0000-4000-8000-000000000005"]) { _, new in new }
        MagicHistoricalTestProtocol.handler = { request in
            if request.url?.path == "/cards/search" { return try self.page([a, b]) }
            return try JSONSerialization.data(withJSONObject: request.url?.lastPathComponent == a["id"] as? String ? a : b)
        }
        let adapter = liveAdapter(), catalog = CardCatalog(gameCatalogAdapters: try GameCatalogAdapterRegistry(adapters: [adapter]))
        let identifier = try liveEvidence("B.F.M. (Big Furry Monster)", number: nil).identifier().confirmingMagicEnglish()
        guard case let .needsPrintingChoice(summary, choices) = try await catalog.lookupOutcome(for: identifier) else { return XCTFail("explicit choice") }
        XCTAssertTrue(summary.id.hasPrefix("magic-historical-title:"))
        XCTAssertEqual(Set(choices.map(\.canonicalCardID)).count, 2)
        for choice in choices {
            XCTAssertEqual(choice.selectionEvidence(among: choices), .labels)
            let resolved = try await catalog.resolvePrintingChoice(choice, for: identifier)
            XCTAssertEqual(resolved.card.canonicalCardID, choice.canonicalCardID)
            XCTAssertEqual(resolved.card.physicalPrintingID, choice.id)
        }
        do { try await adapter.validateAcquisition(identifier, printingID: choices[0].id, automatic: true); XCTFail("no automatic choice") } catch {}
    }

    func testHistoricalIncompleteDuplicateAndLoopingPagesFailClosed() async throws {
        let a = liveCard(), b = liveCard().merging(["id": "00000000-0000-4000-8000-000000000004"]) { _, new in new }
        let payloads = [try page([a], total: 2), try page([a, a]), try page([], total: 1),
                        try page([a], total: 2, next: "https://api.scryfall.com/cards/search?page=2")]
        for payload in payloads {
            MagicHistoricalTestProtocol.handler = { _ in payload }
            do { _ = try await liveAdapter().lookup(liveEvidence().identifier()); XCTFail("incomplete/duplicate/loop") } catch {}
        }
        MagicHistoricalTestProtocol.handler = { request in
            if request.url?.query?.contains("page=2") == true { return try self.page([b], total: 3) }
            return try self.page([a], total: 2, next: "https://api.scryfall.com/cards/search?page=2")
        }
        do { _ = try await liveAdapter().lookup(liveEvidence().identifier()); XCTFail("changed total") } catch {}
    }

    func testHistoricalExactHydrationRejectsChangedIdentityAndFinish() async throws {
        let a = liveCard()
        let changes: [[String: Any]] = [["oracle_id": "00000000-0000-4000-8000-000000000005"],
                                     ["set": "6ed"], ["collector_number": "43"], ["layout": "token"],
                                     ["finishes": ["foil"]], ["released_at": "2014-07-18"], ["oversized": true]]
        for change in changes {
            MagicHistoricalTestProtocol.handler = { request in
                if request.url?.path == "/cards/search" { return try self.page([a]) }
                return try JSONSerialization.data(withJSONObject: a.merging(change) { _, new in new })
            }
            let adapter = liveAdapter(), identifier = try liveEvidence().identifier().confirmingMagicEnglish()
            guard case let .needsPrintingChoice(_, choices) = try await adapter.lookup(identifier) else { return XCTFail("initial choice") }
            do { _ = try await adapter.resolve(choices[0], for: identifier); XCTFail("changed exact payload: \(change)") } catch {}
        }
    }

    func testHistoricalMalformedOrdinaryPrintingCannotDisappearFromChoices() async throws {
        let good = liveCard()
        for change: [String: Any] in [["oracle_id": NSNull()], ["finishes": ["foil", "unknown"]], ["released_at": "invalid"]] {
            let malformed = good.merging(change.merging(["id": "00000000-0000-4000-8000-000000000004"]) { _, new in new }) { _, new in new }
            MagicHistoricalTestProtocol.handler = { _ in try self.page([good, malformed]) }
            do { _ = try await liveAdapter().lookup(liveEvidence().identifier()); XCTFail("malformed printing was hidden") } catch {}
        }
        let token = good.merging(["layout": "token", "oracle_id": NSNull(), "id": "00000000-0000-4000-8000-000000000004"]) { _, new in new }
        MagicHistoricalTestProtocol.handler = { _ in try self.page([good, token]) }
        guard case let .needsPrintingChoice(_, choices) = try await liveAdapter().lookup(liveEvidence().identifier()) else { return XCTFail("explicitly unsupported token") }
        XCTAssertEqual(choices.count, 1)
    }

    func testHistoricalLiveProviderEdgeCaptures() async throws {
        guard let root = Bundle(for: Self.self).url(forResource: "01", withExtension: "json", subdirectory: "MagicHistoricalEdges")?.deletingLastPathComponent() else {
            throw XCTSkip("Stage retained public provider edge captures")
        }
        for i in 1...11 {
            let capture = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(String(format: "%02d.json", i)))) as! [String: Any]
            let title = capture["title"] as! String, providerPage = capture["page"] as! [String: Any]
            print("MAGIC_EDGE_CASE \(i): \(title)")
            let cards = providerPage["data"] as! [[String: Any]]
            MagicHistoricalTestProtocol.handler = { request in
                if request.url?.path == "/cards/search" { return try JSONSerialization.data(withJSONObject: providerPage) }
                return try JSONSerialization.data(withJSONObject: cards.first(where: { $0["id"] as? String == request.url?.lastPathComponent })!)
            }
            let catalog = CardCatalog(gameCatalogAdapters: try GameCatalogAdapterRegistry(adapters: [liveAdapter()]))
            let identifier = try liveEvidence(title, number: nil).identifier().confirmingMagicEnglish()
            guard case let .needsPrintingChoice(_, choices) = try await catalog.lookupOutcome(for: identifier) else { return XCTFail("\(title)") }
            XCTAssertFalse(choices.isEmpty)
            for choice in choices {
                let resolved = try await catalog.resolvePrintingChoice(choice, for: identifier)
                XCTAssertEqual(resolved.card.physicalPrintingID, choice.id)
                XCTAssertEqual(resolved.card.canonicalCardID, choice.canonicalCardID)
            }
        }
    }

    @MainActor
    func testGeneralHistoricalChoiceWorksForUnlistedPrintingAndNeverAutomaticallyWrites() async throws {
        let card = liveCard()
        MagicHistoricalTestProtocol.handler = { request in
            if request.url?.path == "/cards/search" { return try self.page([card]) }
            return try JSONSerialization.data(withJSONObject: card)
        }
        let source = liveAdapter(), identifier = try liveEvidence().identifier()
        guard case let .needsPrintingChoice(_, choices) = try await source.lookup(identifier) else { return XCTFail("choice required") }
        XCTAssertEqual(choices.count, 1)
        do { _ = try await source.resolve(choices[0], for: identifier); XCTFail("English confirmation required") } catch {}
        let confirmed = try identifier.confirmingMagicEnglish()
        let resolved = try await source.resolve(choices[0], for: confirmed)
        XCTAssertEqual(resolved.card.physicalPrintingID, card["id"] as? String)
        do { try await source.validateAcquisition(confirmed, printingID: choices[0].id, automatic: true); XCTFail("no title-based auto write") } catch {}
        let schema = Schema([CollectedCard.self, PriceRecord.self, CollectionActivity.self, InventoryEvent.self,
                             ReferenceQuote.self, PriceObservation.self, PriceCheckDay.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let recovery = FileManager.default.temporaryDirectory.appendingPathComponent("General-Magic-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: recovery) }
        let adapters = try GameCatalogAdapterRegistry(adapters: [source])
        let model = ScannerViewModel(scanner: CardScanner(), catalog: CardCatalog(gameCatalogAdapters: adapters),
            unresolvedScanStore: UnresolvedScanStore(fileURL: recovery))
        model.start(context: container.mainContext, isSceneActive: true, startCamera: false, shouldRefreshMagicDirectory: false)
        defer { model.viewDisappeared() }
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), ScanSubject(identifier: identifier), nil)
        for _ in 0..<600 where model.pendingIdentityChoice == nil { try await Task.sleep(for: .milliseconds(5)) }
        let pending = try XCTUnwrap(model.pendingIdentityChoice)
        XCTAssertTrue(pending.identifier.needsMagicEnglishConfirmation)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        model.chooseWithEnglishConfirmation(try XCTUnwrap(pending.displayCandidates.first))
        for _ in 0..<600 where model.recent.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        let saved = try container.mainContext.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.providerID, card["id"] as? String)
        XCTAssertEqual(saved.first?.quantity, 1)
    }

    func testGeneralHistoricalTitleOnlyOldFramesLayoutsAndOCRNumberCorrection() async throws {
        for layout in ["normal", "split", "flip", "transform"] {
            let card = liveCard("Black Lotus", number: "999", layout: layout).merging(["released_at": "1993-08-05"]) { _, new in new }
            MagicHistoricalTestProtocol.handler = { _ in try self.page([card]) }
            guard case .needsPrintingChoice = try await liveAdapter().lookup(liveEvidence("Black Lotus", number: nil).identifier()) else {
                return XCTFail("pre-Exodus title-only choice must work")
            }
            guard case .needsPrintingChoice = try await liveAdapter().lookup(liveEvidence("Black Lotus", number: "123").identifier()) else {
                return XCTFail("weak OCR number must not hide the exact printing choice")
            }
        }
        for change in [["layout": "token"], ["lang": "fr"], ["released_at": "2014-07-18"]] {
            let card = liveCard().merging(change) { _, new in new }
            MagicHistoricalTestProtocol.handler = { _ in try self.page([card]) }
            do { _ = try await liveAdapter().lookup(liveEvidence().identifier()); XCTFail("unsupported printing") } catch {}
        }
    }

    func testGeneralHistoricalPaginationAndChangedMembershipRevalidateBeforeSave() async throws {
        let a = liveCard(), b = liveCard().merging(["id": "00000000-0000-4000-8000-000000000004"]) { _, new in new }
        MagicHistoricalTestProtocol.handler = { request in
            if request.url?.query?.contains("page=2") == true { return try self.page([b], total: 2) }
            return try self.page([a], total: 2, next: "https://api.scryfall.com/cards/search?page=2")
        }
        let source = liveAdapter(), identifier = try liveEvidence().identifier().confirmingMagicEnglish()
        guard case let .needsPrintingChoice(_, choices) = try await source.lookup(identifier) else { return XCTFail("complete pages") }
        XCTAssertEqual(choices.count, 2)
        MagicHistoricalTestProtocol.handler = { _ in try self.page([b]) }
        do { try await source.validateAcquisition(identifier, printingID: a["id"] as! String, automatic: false); XCTFail("removed printing") } catch {}
        MagicHistoricalTestProtocol.handler = { _ in try self.page([a], total: 2, next: "https://example.org/cards/search?page=2") }
        do { _ = try await source.lookup(identifier); XCTFail("untrusted page") } catch {}
        let catalog = CardCatalog(gameCatalogAdapters: try GameCatalogAdapterRegistry(adapters: [source]))
        MagicHistoricalTestProtocol.handler = { _ in try self.page([a]) }
        guard case let .needsPrintingChoice(_, before) = try await catalog.lookupOutcome(for: identifier) else { return XCTFail("initial family") }
        XCTAssertEqual(before.count, 1)
        MagicHistoricalTestProtocol.handler = { _ in try self.page([a, b]) }
        guard case let .needsPrintingChoice(_, after) = try await catalog.lookupOutcome(for: identifier) else { return XCTFail("refreshed family") }
        XCTAssertEqual(after.count, 2, "retry must not reuse a frozen choice list")
    }

    @MainActor
    func testGeneralHistoricalCorpusAcrossAllFrameGenerations() async throws {
        guard let manifestURL = Bundle(for: Self.self).url(forResource: "evaluation", withExtension: "json", subdirectory: "MagicHistoricalCorpus") else {
            throw XCTSkip("Stage private corpus")
        }
        let root = manifestURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("general-provider-captures.json").path) else {
            throw XCTSkip("Stage general provider captures")
        }
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
        let rows = manifest["records"] as! [[String: Any]]
        let captures = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("general-provider-captures.json"))) as! [String: [[String: Any]]]
        let pages = captures.values.flatMap { $0 }
        MagicHistoricalTestProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            func query(_ value: String) -> [String: String] {
                let components = URLComponents(string: value.replacingOccurrences(of: "+", with: "%20"))!
                return Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
            }
            guard let captured = pages.first(where: { query($0["url"] as! String) == query(url.absoluteString) }) else { throw URLError(.badURL) }
            return try JSONSerialization.data(withJSONObject: captured["page"]!)
        }
        var results: [[String: Any]] = []
        for row in rows {
            let filename = row["filename"] as! String
            let bytes = try Data(contentsOf: root.appendingPathComponent(filename))
            XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), row["sha256"] as? String)
            let handler = VNImageRequestHandler(data: bytes)
            let evidence = try MagicHistoricalLiveOCR.readPhotograph(handler: handler, encounterID: UUID())
            var choices = 0
            if let evidence {
                do {
                    guard case let .needsPrintingChoice(_, candidates) = try await liveAdapter().lookup(evidence.identifier()) else {
                        XCTFail("printing choices for \(filename)"); continue
                    }
                    choices = candidates.count
                } catch {
                    XCTFail("\(filename): \(evidence.title): \(error)")
                }
                XCTAssertTrue(try evidence.identifier().needsMagicEnglishConfirmation)
                XCTAssertEqual(MagicHistoricalEvidenceKey.canonicalTitle(evidence.title),
                    MagicHistoricalEvidenceKey.canonicalTitle(row["referenceTitle"] as! String), filename)
            }
            results.append(["index": row["index"]!, "recognizedTitle": evidence?.title ?? "",
                "collector": evidence?.collectorNumber ?? "", "printingChoices": choices])
        }
        print("MAGIC_GENERAL_CORPUS_RESULT " + String(decoding: try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]), as: UTF8.self))
        XCTAssertEqual(results.filter { ($0["printingChoices"] as! Int) > 0 }.count, 27,
            "Every reference case must reach the appropriate printing choices")
    }

    /// Private images are staged into the external build, never checked in.
    /// A repeated still verifies the window plumbing, not independent video frames.
    @MainActor
    func testPhotographicCorpusOCRChoiceAndExactCollectionSave() async throws {
        guard let manifestURL = Bundle(for: Self.self).url(forResource: "evaluation", withExtension: "json",
            subdirectory: "MagicHistoricalCorpus") else {
            throw XCTSkip("Stage the hash-pinned corpus with scripts/stage_magic_historical_corpus.py")
        }
        let root = manifestURL.deletingLastPathComponent()
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        let rows = try XCTUnwrap(manifest["records"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 27)
        let snap = try snapshot()
        var positive: MagicHistoricalScanEvidence?
        var metrics: [[String: Any]] = []
        for row in rows {
            let filename = try XCTUnwrap(row["filename"] as? String)
            let bytes = try Data(contentsOf: root.appendingPathComponent(filename))
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(hash, row["sha256"] as? String)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let orientation = CGImagePropertyOrientation(rawValue: (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1) ?? .up
            let quarterTurn = [.left, .leftMirrored, .right, .rightMirrored].contains(orientation)
            let size = CGSize(width: quarterTurn ? image.height : image.width, height: quarterTurn ? image.width : image.height)
            let rect = try XCTUnwrap(row["cardRect"] as? [Double])
            let evidence = try MagicHistoricalOCR.read(handler: VNImageRequestHandler(cgImage: image, orientation: orientation),
                sourceSize: size, cardRect: CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3]),
                encounterID: UUID(), snapshot: snap)
            if let title = row["expectedTitle"] as? String {
                let found = try XCTUnwrap(evidence, filename)
                XCTAssertEqual(MagicHistoricalEvidenceKey.canonicalTitle(found.title), MagicHistoricalEvidenceKey.canonicalTitle(title))
                XCTAssertEqual(found.collectorNumber, row["expectedCollectorNumber"] as? String)
                XCTAssertFalse(found.permitsEnglishAcquisition)
                let query = try snap.index.query(title: found.title, collectorNumber: found.collectorNumber,
                    profiles: snap.profiles, currentSourceContext: snap.index.artifact.coverage.sourceContext,
                    now: MagicCatalogDate.parseDay("2026-10-06")!)
                XCTAssertEqual(query.eligiblePhaseOneRecords.map(\.printingID), [row["expectedPrintingID"] as! String])
                positive = found
            } else {
                XCTAssertNil(evidence, "Unsupported corpus entry must abstain: \(filename)")
            }
            metrics.append(["index": row["index"]!, "recognized": evidence != nil,
                "partition": row["partition"]!])
        }
        let found = try XCTUnwrap(positive)
        var window = MagicHistoricalCaptureWindow()
        XCTAssertTrue(window.begin(at: 0)); XCTAssertNil(window.observe(found))
        XCTAssertTrue(window.begin(at: 0.1))
        let identifier = try XCTUnwrap(window.observe(found))
        XCTAssertTrue(identifier.needsMagicEnglishConfirmation)
        let page = try Data(contentsOf: root.appendingPathComponent("Survival-search.json"))
        let provider = try XCTUnwrap(JSONSerialization.jsonObject(with: page) as? [String: Any])
        let cards = try XCTUnwrap(provider["data"] as? [[String: Any]])
        let card = try XCTUnwrap(cards.first { $0["id"] as? String == "c060c178-3c0e-493f-b6f0-ead5b1d6f191" })
        MagicHistoricalTestProtocol.handler = { request in
            if request.url?.path == "/cards/search" { return page }
            guard request.url?.path == "/cards/c060c178-3c0e-493f-b6f0-ead5b1d6f191" else { throw URLError(.badURL) }
            return try JSONSerialization.data(withJSONObject: card)
        }
        let schema = Schema([CollectedCard.self, PriceRecord.self, CollectionActivity.self, InventoryEvent.self,
                             ReferenceQuote.self, PriceObservation.self, PriceCheckDay.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let recoveryURL = FileManager.default.temporaryDirectory.appendingPathComponent("Corpus-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: recoveryURL) }
        let adapters = try GameCatalogAdapterRegistry(adapters: [adapter(snap)])
        let model = ScannerViewModel(scanner: CardScanner(), catalog: CardCatalog(gameCatalogAdapters: adapters),
            unresolvedScanStore: UnresolvedScanStore(fileURL: recoveryURL))
        model.start(context: container.mainContext, isSceneActive: true, startCamera: false, shouldRefreshMagicDirectory: false)
        defer { model.viewDisappeared() }
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), ScanSubject(identifier: identifier), nil)
        for _ in 0..<600 where model.pendingIdentityChoice == nil { try await Task.sleep(for: .milliseconds(5)) }
        let choice = try XCTUnwrap(model.pendingIdentityChoice)
        XCTAssertTrue(choice.identifier.needsMagicEnglishConfirmation)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        model.chooseWithEnglishConfirmation(try XCTUnwrap(choice.displayCandidates.first))
        for _ in 0..<600 where model.recent.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        let saved = try container.mainContext.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.providerID, "c060c178-3c0e-493f-b6f0-ead5b1d6f191")
        XCTAssertEqual(saved.first?.quantity, 1)
        let result: [String: Any] = ["images": metrics, "expectedRecognitions": 1, "expectedAbstentions": 26,
            "collectionRows": saved.count, "transport": "retained provider capture", "deviceAcceptance": "pending"]
        print("MAGIC_CORPUS_RESULT " + String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }

    func testHistoricalOCRRejectsInvalidFramingBeforeImageAccess() throws {
        let handler = VNImageRequestHandler(url: URL(fileURLWithPath: "/nonexistent-corpus-image.jpg"))
        let snap = try snapshot()
        for rect in [CGRect.zero, CGRect(x: -0.1, y: 0, width: 1, height: 1), CGRect(x: 0, y: 0, width: 2, height: 1)] {
            XCTAssertNil(try MagicHistoricalOCR.read(handler: handler, sourceSize: CGSize(width: 100, height: 100),
                cardRect: rect, encounterID: UUID(), snapshot: snap))
        }
    }

    @MainActor
    func testScannerChoiceConfirmationSaveAndRecoveryPreserveExactPrinting() async throws {
        let snap = try snapshot(), card = providerCard(snap)
        MagicHistoricalTestProtocol.handler = { _ in try JSONSerialization.data(withJSONObject: card) }
        let schema = Schema([CollectedCard.self, PriceRecord.self, CollectionActivity.self, InventoryEvent.self,
                             ReferenceQuote.self, PriceObservation.self, PriceCheckDay.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagicRecovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UnresolvedScanStore(fileURL: root.appendingPathComponent("unresolved.json"))
        let adapters = try GameCatalogAdapterRegistry(adapters: [adapter(snap)])
        let model = ScannerViewModel(scanner: CardScanner(), catalog: CardCatalog(gameCatalogAdapters: adapters),
            unresolvedScanStore: store)
        model.start(context: container.mainContext, isSceneActive: true, startCamera: false, shouldRefreshMagicDirectory: false)
        defer { model.viewDisappeared() }
        func wait(_ condition: () -> Bool) async -> Bool {
            for _ in 0..<600 {
                if condition() { return true }
                try? await Task.sleep(for: .milliseconds(5))
            }
            return condition()
        }
        let first = try evidence(snap).identifier()
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), ScanSubject(identifier: first), nil)
        let appeared = await wait { model.pendingIdentityChoice != nil }
        XCTAssertTrue(appeared)
        let choice = try XCTUnwrap(model.pendingIdentityChoice)
        XCTAssertTrue(choice.identifier.needsMagicEnglishConfirmation)
        model.chooseWithEnglishConfirmation(choice.displayCandidates[0])
        let saved = await wait { model.recent.count == 1 }
        XCTAssertTrue(saved, "\(String(describing: model.note)); unresolved: \(model.unresolvedScans.count); finish choice: \(model.pendingChoice != nil)")
        guard saved else { return }
        let rows = try container.mainContext.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.providerID, card["id"] as? String)
        // A different encounter must ask again. Dismiss to recovery, then answer
        // through the same persisted-identity route used after app relaunch.
        let next = try evidence(snap).identifier()
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), ScanSubject(identifier: next), nil)
        let nextAppeared = await wait { model.pendingIdentityChoice != nil }
        XCTAssertTrue(nextAppeared)
        XCTAssertTrue(model.pendingIdentityChoice?.identifier.needsMagicEnglishConfirmation == true)
        model.dismissIdentityChoice()
        let recovered = await wait { !model.unresolvedScans.isEmpty }
        XCTAssertTrue(recovered)
        let unresolved = try XCTUnwrap(model.unresolvedScans.first)
        let record = UnresolvedScanRecord(scan: unresolved)
        let bytes = try JSONEncoder().encode(record)
        let reloaded = try JSONDecoder().decode(UnresolvedScanRecord.self, from: bytes)
        XCTAssertEqual(reloaded.identifierSnapshot?.fields, record.identifierSnapshot?.fields)
        await model.waitForUnresolvedPersistenceForTesting()
        model.viewDisappeared()
        let recovery = ScannerViewModel(scanner: CardScanner(), catalog: CardCatalog(gameCatalogAdapters: adapters),
            unresolvedScanStore: UnresolvedScanStore(fileURL: root.appendingPathComponent("unresolved.json")))
        recovery.start(context: container.mainContext, isSceneActive: true, startCamera: false, shouldRefreshMagicDirectory: false)
        defer { recovery.viewDisappeared() }
        await recovery.waitForUnresolvedPersistenceForTesting()
        let recoveredRow = try XCTUnwrap(recovery.unresolvedScans.first)
        XCTAssertFalse(recoveredRow.isReadOnly)
        XCTAssertTrue(recoveredRow.identifier.needsMagicEnglishConfirmation)
        let recoveryCandidate = try XCTUnwrap(recoveredRow.printingCandidates.first)
        recovery.resolveUnresolved(id: recoveredRow.id, choice: .englishPrinting(recoveryCandidate))
        let secondSaved = await wait { recovery.recent.count == 1 }
        XCTAssertTrue(secondSaved, "\(String(describing: recovery.note)); unresolved: \(recovery.unresolvedScans.count)")
        XCTAssertTrue(recovery.unresolvedScans.isEmpty)
        let finalRows = try container.mainContext.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(finalRows.count, 1)
        XCTAssertEqual(finalRows.first?.quantity, 2)
    }
    private func snapshot() throws -> MagicHistoricalLocalSnapshot {
        let index = try MagicHistoricalIndexSnapshot.loadBundled()
        let profiles = try MagicRecognitionProfileSnapshot(descriptors: index.artifact.catalog.sets,
            indexGeneration: index.generation, catalogRevision: index.catalogRevision)
        return try .init(profiles: profiles, index: index)
    }
    private func evidence(_ snapshot: MagicHistoricalLocalSnapshot, title: String = "Allay", number: String = "1") -> MagicHistoricalScanEvidence {
        .init(title: title, collectorNumber: number, denominator: 143, encounterID: UUID(),
            profileGeneration: snapshot.generation, indexGeneration: snapshot.index.generation,
            titleBounds: CGRect(x: 0.1, y: 0.9, width: 0.5, height: 0.04),
            numberBounds: CGRect(x: 0.1, y: 0.03, width: 0.3, height: 0.03))
    }
    private func adapter(_ snapshot: MagicHistoricalLocalSnapshot, enabled: Bool = true, current: Bool = true) -> MagicCatalogAdapter {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MagicHistoricalTestProtocol.self]
        return .init(source: ScryfallService(breaker: TCGdexCircuitBreaker(), session: URLSession(configuration: configuration)),
            historicalSnapshot: snapshot, historicalSourceContext: current ? snapshot.index.artifact.coverage.sourceContext : nil,
            historicalEnabled: enabled, historicalNow: { MagicCatalogDate.parseDay("2026-10-06")!.addingTimeInterval(1) })
    }
    override func tearDown() { MagicHistoricalTestProtocol.handler = nil; super.tearDown() }

    func testParserRequiresSameSourceGeometryAndRejectsBodyYearPowerAndCrossGameNumbers() throws {
        let snap = try snapshot()
        func line(_ text: String, _ x: CGFloat = 100, _ y: CGFloat = 30) -> RecognizedLine {
            .init(text: text, sourcePixelRect: CGRect(x: x, y: y, width: 300, height: 30))
        }
        let title = line("Allay", 100, 900)
        func parse(_ footer: RecognizedLine, titles: [RecognizedLine]? = nil) -> MagicHistoricalScanEvidence? {
            MagicHistoricalScanParser.parse(titleLines: titles ?? [title], footerLines: [footer],
                sourceSize: CGSize(width: 1000, height: 1000), cardRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                encounterID: UUID(), snapshot: snap)
        }
        XCTAssertNotNil(parse(line("© 1998 Wizards 1/143")))
        for text in ["1998", "4/4", "HP 1/143", "T 1/143", "1/144", "1/143 2/143", "01/143"] {
            XCTAssertNil(parse(line(text)), text)
        }
        XCTAssertNil(parse(line("1/143", 700)))
        XCTAssertNil(parse(line("1/143", 100, 500)))
        XCTAssertNil(parse(.init(text: "1/143")))
        XCTAssertNil(parse(line("1/143"), titles: [line("Allay", 100, 500)]))
        XCTAssertNil(parse(line("1/143"), titles: [title, title]))
        XCTAssertNil(parse(line("1/143"), titles: [line("Charizard", 100, 900)]))
    }

    func testWindowBoundsAttemptsFreezesGeometryAndSeparatesAbsentCard() throws {
        let snap = try snapshot()
        var window = MagicHistoricalCaptureWindow()
        let e = evidence(snap)
        XCTAssertTrue(window.begin(at: 0))
        XCTAssertNil(window.observe(e))
        XCTAssertTrue(window.begin(at: 0.1))
        let identifier = try XCTUnwrap(window.observe(e))
        XCTAssertTrue(window.hasPlausibleEvidence)
        for i in 2..<6 { XCTAssertTrue(window.begin(at: Double(i) / 10)) }
        XCTAssertFalse(window.begin(at: 0.7))
        XCTAssertNil(window.observe(nil))
        XCTAssertFalse(window.hasPlausibleEvidence)
        XCTAssertTrue(window.begin(at: 2))
        XCTAssertNil(window.observe(e))
        let next = try XCTUnwrap(window.observe(e))
        XCTAssertNotEqual(identifier, next)
        XCTAssertEqual(identifier.suppressionIdentity, next.suppressionIdentity)
        XCTAssertNotEqual(try MagicHistoricalScanEvidence.decode(identifier).encounterID,
                          try MagicHistoricalScanEvidence.decode(next).encounterID)
    }

    func testLanguageProofPersistsOnlyInItsEncounterAndUnknownFieldsReject() throws {
        let snap = try snapshot()
        let e = evidence(snap)
        let original = try e.identifier()
        XCTAssertTrue(original.needsMagicEnglishConfirmation)
        let confirmed = try original.confirmingMagicEnglish()
        XCTAssertFalse(confirmed.needsMagicEnglishConfirmation)
        let serialized = try JSONEncoder().encode(ScanIdentifierSnapshot(identifier: confirmed))
        XCTAssertFalse(try JSONDecoder().decode(ScanIdentifierSnapshot.self, from: serialized).identifier().needsMagicEnglishConfirmation)
        var reused = try MagicHistoricalScanEvidence.decode(confirmed)
        reused.encounterID = UUID()
        XCTAssertFalse(reused.permitsEnglishAcquisition)
        reused.language = .conflictingOrNonEnglish
        XCTAssertThrowsError(try reused.confirmedEnglish())
        var json = try JSONSerialization.jsonObject(with: Data(original.fields[0].value.utf8)) as! [String: Any]
        json["guessedSet"] = "exo"
        let malformed = try ScanIdentifier(game: .magic, namespace: "historical",
            fields: [.init(key: "evidence", value: String(decoding: JSONSerialization.data(withJSONObject: json), as: UTF8.self))],
            displayIdentifier: "bad", suppressionIdentity: "bad")
        XCTAssertThrowsError(try adapter(snap).prepareLookupIdentifier(malformed))
        let namespace = try ScanIdentifier(game: .magic, namespace: "unknown", fields: original.fields,
            displayIdentifier: "bad", suppressionIdentity: "bad")
        XCTAssertThrowsError(try adapter(snap).prepareLookupIdentifier(namespace))
    }

    func testUnknownEnglishRequiresChoiceThenExactIDHydrationAndCanonicalIdentity() async throws {
        let snap = try snapshot(), e = evidence(snap)
        let card = providerCard(snap)
        var paths: [String] = []
        MagicHistoricalTestProtocol.handler = { request in paths.append(request.url!.path); return try JSONSerialization.data(withJSONObject: card) }
        let catalog = CardCatalog(gameCatalogAdapters: try .init(adapters: [adapter(snap)]))
        let identifier = try adapter(snap).prepareLookupIdentifier(e.identifier())
        guard case let .needsPrintingChoice(canonical, candidates) = try await catalog.lookupOutcome(for: identifier) else {
            return XCTFail("provider/title English must never auto-add")
        }
        XCTAssertEqual(candidates.count, 1)
        XCTAssertTrue(paths.isEmpty)
        do { _ = try await catalog.resolvePrintingChoice(candidates[0], for: identifier); XCTFail("language missing") } catch {}
        let confirmed = try identifier.confirmingMagicEnglish()
        let resolved = try await catalog.resolvePrintingChoice(candidates[0], for: confirmed)
        XCTAssertEqual(resolved.card.physicalPrintingID, candidates[0].id)
        XCTAssertEqual(resolved.card.canonicalCardID, canonical.id)
        XCTAssertEqual(paths, ["/cards/\(candidates[0].id)"])
        try await catalog.validateAcquisition(confirmed, printingID: candidates[0].id, automatic: false)
    }

    func testUnsupportedCrossEraCollisionsOfflineExpiryAndDisabledPilotAbstain() async throws {
        let snap = try snapshot()
        for (title, number) in [("Cataclysm", "3"), ("Monstrous Hound", "89")] {
            guard case .catalogIncomplete = try await adapter(snap).lookup(evidence(snap, title: title, number: number).identifier()) else {
                return XCTFail("outside-era/promotional printing must remain a blocker")
            }
        }
        guard case .catalogIncomplete = try await adapter(snap, current: false).lookup(evidence(snap).identifier()) else {
            return XCTFail("missing current context")
        }
        do { _ = try await adapter(snap, enabled: false).lookup(evidence(snap).identifier()); XCTFail("disabled") } catch {}
        var expired = adapter(snap)
        expired.historicalNow = { MagicCatalogDate.parseDay("2026-10-07")! }
        guard case .catalogIncomplete = try await expired.lookup(evidence(snap).identifier()) else { return XCTFail("expired") }
    }

    func testLiveCurrentUniverseRejectsNewPrintingPartialWarningsAndMalformedCards() async throws {
        let snap = try snapshot(), card = providerCard(snap)
        let source = adapter(snap).source
        let id = card["id"] as! String
        let page: [String: Any] = ["object": "list", "has_more": false, "total_cards": 1, "data": [card]]
        for mutation in 0..<6 {
            var response = page
            switch mutation {
            case 1: var duplicate = card; duplicate["id"] = UUID().uuidString; response["data"] = [card, duplicate]; response["total_cards"] = 2
            case 2: response["has_more"] = true; response["next_page"] = "https://api.scryfall.com/next"
            case 3: response["warnings"] = ["partial"]
            case 4: response["total_cards"] = 2
            case 5: var wrong = card; wrong["object"] = "error"; response["data"] = [wrong]
            default: break
            }
            MagicHistoricalTestProtocol.handler = { _ in try JSONSerialization.data(withJSONObject: response) }
            let current = try await source.hasCurrentHistoricalUniverse(title: "Allay", collectorNumber: "1", expectedIDs: [id])
            XCTAssertEqual(current, mutation == 0)
        }
        MagicHistoricalTestProtocol.handler = { _ in throw URLError(.timedOut) }
        do { _ = try await source.hasCurrentHistoricalUniverse(title: "Allay", collectorNumber: "1", expectedIDs: [id]); XCTFail("timeout") } catch {}
    }

    func testHydrationRejectsExactIdentityLanguageLayoutDateAndFinishDrift() async throws {
        let snap = try snapshot(), e = try evidence(snap).confirmedEnglish()
        let source = adapter(snap)
        guard case let .needsPrintingChoice(_, candidates) = try await source.lookup(evidence(snap).identifier()) else { return XCTFail() }
        for (key, value) in [("id", UUID().uuidString), ("lang", "fr"), ("layout", "split"),
                             ("released_at", "1998-06-16"), ("collector_number", "2"), ("oracle_id", UUID().uuidString)] {
            var card = providerCard(snap); card[key] = value
            MagicHistoricalTestProtocol.handler = { _ in try JSONSerialization.data(withJSONObject: card) }
            do { _ = try await source.resolve(candidates[0], for: e.identifier()); XCTFail(key) } catch {}
        }
        var card = providerCard(snap); card["finishes"] = ["foil"]
        MagicHistoricalTestProtocol.handler = { _ in try JSONSerialization.data(withJSONObject: card) }
        do { _ = try await source.resolve(candidates[0], for: e.identifier()); XCTFail("finish") } catch {}
    }

    func testAutomaticResolutionRechecksUniverseAndSaveRejectsNewCollision() async throws {
        let snap = try snapshot(), e = try evidence(snap).confirmedEnglish(), card = providerCard(snap)
        let source = adapter(snap)
        MagicHistoricalTestProtocol.handler = { request in
            try JSONSerialization.data(withJSONObject: request.url!.path == "/cards/search"
                ? ["object": "list", "has_more": false, "total_cards": 1, "data": [card]] : card)
        }
        guard case .resolved = try await source.lookup(e.identifier()) else { return XCTFail() }
        var collision = card; collision["id"] = UUID().uuidString
        MagicHistoricalTestProtocol.handler = { _ in try JSONSerialization.data(withJSONObject:
            ["object": "list", "has_more": false, "total_cards": 2, "data": [card, collision]]) }
        do { try await source.validateAcquisition(e.identifier(), printingID: card["id"] as! String, automatic: true); XCTFail("new printing") } catch {}
    }

    func testActivationDuringHydrationRejectsStaleCandidate() async throws {
        let snap = try snapshot(), store = MagicHistoricalLocalStore(snapshot: try snapshot())
        var source = adapter(snap); source.historicalStore = store
        guard case let .needsPrintingChoice(_, candidates) = try await source.lookup(evidence(snap).identifier()) else { return XCTFail() }
        let card = providerCard(snap)
        let override = MagicRecognitionPrintingOverride(printingID: card["id"] as! String, setCode: "exo",
            route: .legacyNoCollectorNumber, reviewReference: "activation-test")
        let profiles = try MagicRecognitionProfileSnapshot(descriptors: snap.index.artifact.catalog.sets,
            overrides: [override], indexGeneration: snap.index.generation, catalogRevision: snap.index.catalogRevision)
        let next = try MagicHistoricalLocalSnapshot(profiles: profiles, index: snap.index)
        MagicHistoricalTestProtocol.handler = { _ in
            let semaphore = DispatchSemaphore(value: 0)
            Task { _ = try await store.activate(next, expectedGeneration: snap.generation); semaphore.signal() }
            semaphore.wait()
            return try JSONSerialization.data(withJSONObject: card)
        }
        do { _ = try await source.resolve(candidates[0], for: evidence(snap).confirmedEnglish().identifier()); XCTFail("stale hydration") } catch {}
    }

    private func providerCard(_ snapshot: MagicHistoricalLocalSnapshot) -> [String: Any] {
        let record = snapshot.index.artifact.records.first { $0.name == "Allay" }!
        return ["object": "card", "id": record.printingID, "oracle_id": record.oracleID!, "set_id": record.setID!,
            "name": record.name, "set": record.setCode, "set_name": record.setName, "collector_number": record.collectorNumber,
            "lang": record.language, "digital": false, "oversized": false, "games": ["paper"],
            "layout": record.layout, "released_at": record.releaseDate!, "finishes": record.finishes]
    }
}

private final class MagicHistoricalTestProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.notConnectedToInternet) }
            let data = try handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
