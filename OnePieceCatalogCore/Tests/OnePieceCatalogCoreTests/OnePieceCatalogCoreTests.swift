import CryptoKit
import Foundation
import XCTest
@testable import OnePieceCatalogCore

final class OnePieceCatalogCoreTests: XCTestCase {
    private let date = "2026-10-03T00:00:00Z"

    func testBundledOwnerCatalogVerification() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TradingCardScanner/OnePieceOwnerCatalog")
        let decoder = JSONDecoder()
        let pins = try decoder.decode([String: String].self,
            from: Data(contentsOf: directory.appendingPathComponent("public-keys.json")))
        let keys = try pins.mapValues { encoded in
            try Curve25519.Signing.PublicKey(rawRepresentation: XCTUnwrap(Data(base64Encoded: encoded)))
        }
        let start = Date()
        let envelope = try decoder.decode(OnePieceCatalogReleaseEnvelope.self,
            from: Data(contentsOf: directory.appendingPathComponent("one-piece-owner-catalog.json")))
        let verified = try OnePieceCatalogSignature.verify(envelope, trustedKeys: keys)
        print("Bundled catalog decode + verification: \(Date().timeIntervalSince(start)) seconds")
        XCTAssertGreaterThan(verified.release.registry.printings.count, 2_000)
        XCTAssertEqual(verified.release.indexes, OnePieceCatalogIndexes(registry: verified.release.registry))
    }

    func testRetainedTCGCSVStressProductsRemainMarketEvidenceWithoutPhysicalAuthority() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ReviewCorpus/english-stress")
        let decoder = JSONDecoder()
        let registry = try decoder.decode(OnePieceRegistryDocument.self,
            from: Data(contentsOf: directory.appendingPathComponent("registry.json")))
        let official = try decoder.decode([OnePieceSourceObservation].self,
            from: Data(contentsOf: directory.appendingPathComponent("observations.json")))
        let market = try decoder.decode([OnePieceSourceObservation].self,
            from: Data(contentsOf: directory.appendingPathComponent("tcgcsv-observations.json")))
        let originalInventories = try decoder.decode([OnePieceSourceInventory].self,
            from: Data(contentsOf: directory.appendingPathComponent("inventories.json")))
        let eventObservations = try decoder.decode([OnePieceSourceObservation].self,
            from: Data(contentsOf: directory.appendingPathComponent("event-observations.json")))
        let eventInventories = try decoder.decode([OnePieceSourceInventory].self,
            from: Data(contentsOf: directory.appendingPathComponent("event-inventories.json")))
        let retailObservations = try ["retail-observations.json", "starter-booster-observations.json", "base-market-observations.json"].flatMap {
            try decoder.decode([OnePieceSourceObservation].self, from: Data(contentsOf: directory.appendingPathComponent($0)))
        }
        let retailInventories = try ["retail-inventories.json", "starter-booster-inventories.json", "base-market-inventories.json"].flatMap {
            try decoder.decode([OnePieceSourceInventory].self, from: Data(contentsOf: directory.appendingPathComponent($0)))
        }
        let marketInventories = try decoder.decode([OnePieceSourceInventory].self,
            from: Data(contentsOf: directory.appendingPathComponent("tcgcsv-inventories.json")))
        XCTAssertEqual(market.count, 31)
        XCTAssertTrue(market.allSatisfy { $0.kind == .market && $0.alias.provider == "tcgplayer"
            && $0.language == "unknown" && $0.imageSHA256 == nil })
        let counts = Dictionary(grouping: market, by: { $0.printedEvidence["number"] ?? "" }).mapValues(\.count)
        XCTAssertEqual(counts, ["OP01-120": 7, "ST01-007": 10, "P-001": 14])
        XCTAssertEqual(Set(market.map(\.alias)).count, market.count)
        XCTAssertTrue(marketInventories.allSatisfy { !$0.paginationComplete })
        let release = try OnePieceCatalogBuilder.build(registry: registry, observations: official + market + eventObservations + retailObservations,
            inventories: originalInventories + marketInventories + eventInventories + retailInventories, revision: 1, generatedAt: "2026-10-04T23:00:00Z")
        let withoutMarket = try OnePieceCatalogBuilder.build(registry: registry, observations: official + eventObservations + retailObservations,
            inventories: originalInventories + eventInventories + retailInventories, revision: 1, generatedAt: "2026-10-04T23:00:00Z")
        XCTAssertEqual(release.registry, withoutMarket.registry,
                       "Market product observations cannot allocate extra printing IDs")
        XCTAssertEqual(release.registry.printings.flatMap(\.marketMappings).count, 2367)
        XCTAssertTrue(release.registry.printings.filter { $0.treatment != "Standard artwork" }
            .allSatisfy { $0.marketMappings.isEmpty })
        XCTAssertTrue(release.indexes.automaticCandidateIDsByCanonicalID.isEmpty)
        let next = try OnePieceCatalogBuilder.build(registry: registry, observations: Array((official + market + eventObservations + retailObservations).reversed()),
            inventories: Array((originalInventories + marketInventories + eventInventories + retailInventories).reversed()),
            revision: 2, generatedAt: "2026-10-04T23:00:00Z", previous: release)
        XCTAssertEqual(next.registry, release.registry)
        XCTAssertEqual(next.observations, release.observations)
    }

    func testRetainedRealSourceReviewKeepsReviewedAwardAndUnresolvedParticipationSeparate() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ReviewCorpus/english-stress")
        let decoder = JSONDecoder()
        let registry = try decoder.decode(OnePieceRegistryDocument.self,
            from: Data(contentsOf: directory.appendingPathComponent("registry.json")))
        let observations = try decoder.decode([OnePieceSourceObservation].self,
            from: Data(contentsOf: directory.appendingPathComponent("observations.json")))
        let inventories = try decoder.decode([OnePieceSourceInventory].self,
            from: Data(contentsOf: directory.appendingPathComponent("inventories.json")))
        let eventObservations = try decoder.decode([OnePieceSourceObservation].self,
            from: Data(contentsOf: directory.appendingPathComponent("event-observations.json")))
        let eventInventories = try decoder.decode([OnePieceSourceInventory].self,
            from: Data(contentsOf: directory.appendingPathComponent("event-inventories.json")))
        let retailObservations = try ["retail-observations.json", "starter-booster-observations.json", "base-market-observations.json"].flatMap {
            try decoder.decode([OnePieceSourceObservation].self, from: Data(contentsOf: directory.appendingPathComponent($0)))
        }
        let retailInventories = try ["retail-inventories.json", "starter-booster-inventories.json", "base-market-inventories.json"].flatMap {
            try decoder.decode([OnePieceSourceInventory].self, from: Data(contentsOf: directory.appendingPathComponent($0)))
        }
        let release = try OnePieceCatalogBuilder.build(registry: registry, observations: observations + eventObservations + retailObservations,
            inventories: inventories + eventInventories + retailInventories, revision: 1, generatedAt: "2026-10-04T23:00:00Z")
        XCTAssertTrue(Set(registry.canonicalCards.map(\.printedNumber)).isSuperset(of: ["OP01-120", "ST01-007", "P-001"]))
        XCTAssertEqual(registry.canonicalCards.count, 2692)
        XCTAssertTrue(registry.canonicalCards.allSatisfy { !$0.printingCoverageComplete })
        XCTAssertEqual(registry.printings.count, 2745)
        let winner = try XCTUnwrap(registry.printings.first { $0.id.uuidString.lowercased() == "348ad90a-43d8-49b5-a384-4d9cc2a1fe27" })
        XCTAssertEqual(winner.status, .verified)
        XCTAssertEqual(winner.supportedVariantIDs, ["foil"])
        XCTAssertEqual(winner.stamp, "Super Pre-Release WINNER")
        let retail = registry.printings.filter { $0.releaseID == "product:premium-card-collection-film-red-2023" }
        XCTAssertEqual(retail.count, 12)
        XCTAssertTrue(retail.allSatisfy { $0.status == .verified && $0.supportedVariantIDs == ["foil"] })
        XCTAssertEqual(Set(retail.map(\.canonicalCardID)).count, 12)
        let participant = try XCTUnwrap(registry.printings.first { $0.id.uuidString.lowercased() == "603d83b0-146a-4229-8eaf-b2f884087312" })
        XCTAssertEqual(participant.status, .provisional)
        XCTAssertTrue(participant.supportedVariantIDs.isEmpty)
        XCTAssertNil(participant.stamp)
        XCTAssertTrue(registry.artworks.allSatisfy { $0.referenceImageURL == nil })
        XCTAssertTrue(release.indexes.automaticCandidateIDsByCanonicalID.isEmpty)
        XCTAssertTrue(inventories.allSatisfy { !$0.paginationComplete })
        XCTAssertEqual(Set(observations.map { $0.alias.provider }), ["bandai", "limitless"])
        XCTAssertTrue(observations.allSatisfy { $0.imageSHA256 == nil && $0.productEvidence.isEmpty })
        XCTAssertTrue(observations.contains { $0.alias.sourceID.contains("|appearance:") })
        // A second generation reuses observations, without allocating IDs from
        // provider ordering or promoting a source-table count to completeness.
        let next = try OnePieceCatalogBuilder.build(registry: registry,
            observations: Array((observations + eventObservations + retailObservations).reversed()), inventories: Array((inventories + eventInventories + retailInventories).reversed()),
            revision: 2, generatedAt: "2026-10-04T23:00:00Z", previous: release)
        XCTAssertEqual(next.registry, release.registry)
        XCTAssertEqual(next.observations, release.observations)
    }

    func testRealStarterBoosterReviewRetainsEveryStandardRowAndExcludesUnresolvedPhysicalDistinctions() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ReviewCorpus/english-stress")
        let decoder = JSONDecoder()
        let registry = try decoder.decode(OnePieceRegistryDocument.self,
            from: Data(contentsOf: directory.appendingPathComponent("registry.json")))
        let observations = try ["observations", "tcgcsv-observations", "event-observations", "retail-observations", "starter-booster-observations", "base-market-observations"].flatMap {
            try decoder.decode([OnePieceSourceObservation].self, from: Data(contentsOf: directory.appendingPathComponent($0 + ".json")))
        }
        let inventories = try ["inventories", "tcgcsv-inventories", "event-inventories", "retail-inventories", "starter-booster-inventories", "base-market-inventories"].flatMap {
            try decoder.decode([OnePieceSourceInventory].self, from: Data(contentsOf: directory.appendingPathComponent($0 + ".json")))
        }
        let release = try OnePieceCatalogBuilder.build(registry: registry, observations: observations,
            inventories: inventories, revision: 1, generatedAt: "2026-10-04T23:00:00Z")
        let standard = registry.printings.filter { $0.treatment == "Standard artwork" }
        XCTAssertEqual(standard.count, 2731)
        XCTAssertEqual(standard.filter { $0.status == .verified }.count, 2477)
        XCTAssertEqual(standard.filter { $0.status == .provisional }.count, 223)
        XCTAssertEqual(standard.filter { $0.status == .conflicted }.count, 31)
        let expectedFamilies = Set((1...17).map { "OP" + String(format: "%02d", $0) }
            + (1...36).map { "ST" + String(format: "%02d", $0) }
            + (1...4).map { "EB" + String(format: "%02d", $0) }
            + ["PRB01", "PRB02", "P"])
        XCTAssertEqual(Set(registry.canonicalCards.map { String($0.printedNumber.split(separator: "-")[0]) }), expectedFamilies)
        for (number, productPrefix) in [("EB04-011", "product:op14-"), ("EB04-001", "product:op15-"), ("EB04-061", "product:op15-"), ("OP17-001", "product:op17-")] {
            XCTAssertTrue(standard.contains { $0.canonicalCardID == "one-piece:en:" + number && ($0.releaseID?.hasPrefix(productPrefix) ?? false) })
        }
        let latestDeck = standard.filter { $0.releaseID?.hasPrefix("product:st31-") == true }
        XCTAssertEqual(latestDeck.count, 7)
        XCTAssertTrue(latestDeck.allSatisfy { $0.status == .provisional && $0.supportedVariantIDs.isEmpty },
                      "Missing standard finish evidence cannot be supplied by rarity or another release")
        let starter = standard.filter { $0.releaseID == "product:st01-straw-hat-crew-2022" }
        let booster = standard.filter { $0.releaseID == "product:op01-romance-dawn-2022" }
        XCTAssertEqual(starter.count, 17)
        XCTAssertEqual(booster.count, 121)
        for product in ["product:st02-worst-generation-2022", "product:st03-seven-warlords-2022", "product:st04-animal-kingdom-pirates-2022"] {
            XCTAssertEqual(standard.filter { $0.releaseID == product }.count, 17)
        }
        for (product, count, date) in [
            ("product:op02-paramount-war-2023", 121, "2023-03-10"),
            ("product:st05-film-edition-2023", 17, "2023-02-03"),
            ("product:st06-absolute-justice-2023", 17, "2023-03-10"),
            ("product:st07-big-mom-pirates-2023", 17, "2023-06-30"),
            ("product:st08-monkey-d-luffy-2023", 15, "2023-08-11"),
            ("product:st09-yamato-2023", 15, "2023-08-11"),
            ("product:op03-pillars-of-strength-2023", 123, "2023-06-30"),
            ("product:st10-three-captains-2023", 19, "2023-11-10"),
            ("product:op04-kingdoms-of-intrigue-2023", 119, "2023-09-22"),
            ("product:op05-awakening-of-the-new-era-2023", 119, "2023-12-08"),
            ("product:st11-uta-2024", 15, "2024-02-02"),
            ("product:st12-zoro-and-sanji-2024", 17, "2024-03-15")
        ] {
            XCTAssertEqual(standard.filter { $0.releaseID == product }.count, count)
            XCTAssertEqual(registry.products.first { $0.id == product }?.releaseDate, date)
        }
        let ultraDeck = standard.filter { $0.releaseID == "product:st10-three-captains-2023" }
        XCTAssertTrue(ultraDeck.allSatisfy { $0.status == .verified && $0.supportedVariantIDs == ["foil"] })
        for number in ["OP01-016", "OP01-025"] {
            let reprint = try XCTUnwrap(ultraDeck.first { $0.canonicalCardID == "one-piece:en:" + number })
            let original = try XCTUnwrap(booster.first { $0.canonicalCardID == reprint.canonicalCardID })
            XCTAssertNotEqual(reprint.id, original.id)
            XCTAssertNotEqual(reprint.artworkID, original.artworkID)
            XCTAssertTrue(reprint.review?.evidence.contains { evidence in
                evidence.kind == .finish && observations.contains {
                    $0.id == evidence.observationID && $0.printedEvidence["sourceRole"] == "manufacturer-product-finish-specification"
                }
            } == true)
        }
        let luffy = try XCTUnwrap(starter.first { $0.canonicalCardID == "one-piece:en:ST01-012" })
        XCTAssertEqual(luffy.status, .verified)
        XCTAssertEqual(luffy.supportedVariantIDs, ["foil"])
        let karoo = try XCTUnwrap(starter.first { $0.canonicalCardID == "one-piece:en:ST01-003" })
        XCTAssertEqual(karoo.status, .verified)
        XCTAssertEqual(karoo.supportedVariantIDs, ["normal"])
        let shanks = try XCTUnwrap(booster.first { $0.canonicalCardID == "one-piece:en:OP01-120" })
        XCTAssertEqual(shanks.status, .verified)
        XCTAssertEqual(shanks.supportedVariantIDs, ["foil"])
        let nami = try XCTUnwrap(starter.first { $0.canonicalCardID == "one-piece:en:ST01-007" })
        XCTAssertEqual(nami.status, .provisional, "Finish alone cannot settle original versus revision artwork/text")
        XCTAssertEqual(nami.supportedVariantIDs, ["normal"])
        XCTAssertNotEqual(nami.id.uuidString.lowercased(), "6a0527fd-1a7a-448c-a55b-53deba7bb428")
        let leader = try XCTUnwrap(starter.first { $0.canonicalCardID == "one-piece:en:ST01-001" })
        XCTAssertTrue(leader.supportedVariantIDs.isEmpty)
        XCTAssertTrue(release.indexes.printingIDsByCanonicalID[leader.canonicalCardID]?.contains(leader.id) == true,
                      "Conflicted review rows remain retained rather than disappearing")
        XCTAssertTrue(release.indexes.automaticCandidateIDsByCanonicalID.isEmpty)
    }

    func testTimestampValidationAcceptsFractionalSecondsAndStillRejectsInvalidValues() throws {
        let base = try fixture()
        func release(_ timestamp: String) -> OnePieceCatalogRelease {
            OnePieceCatalogRelease(revision: base.revision, generatedAt: timestamp,
                registry: base.registry, observations: base.observations, inventories: base.inventories)
        }
        XCTAssertNoThrow(try OnePieceCatalogCandidateValidator.validate(release("2026-10-04T23:27:16.093633Z")))
        XCTAssertTrue(OnePieceCatalogCandidateValidator.issues(in: release("not-a-date"))
            .contains { $0.code == "invalidTimestamp" })
    }

    func testPublicationRequiresReviewedCanonicalBytesAndPinnedSigningKey() throws {
        let candidate = try fixture().canonicalData()
        let key = Curve25519.Signing.PrivateKey(), keyID = "one-piece-publication-fixture"
        let keys = [keyID: key.publicKey]
        let hash = OnePieceSourceObservation.sha256(candidate)
        let result = try OnePieceCatalogPublication.prepare(candidate: candidate, reviewedSHA256: hash,
            keyID: keyID, privateKey: key, trustedKeys: keys, bootstrap: true)
        XCTAssertEqual(result.manifest.revision, 1)
        XCTAssertNil(result.manifest.previousRevision)
        XCTAssertEqual(result.manifest.payloadSHA256, hash)
        XCTAssertEqual(result.manifest.classification.changeClass, .protectedReview)
        XCTAssertEqual(result.manifest.envelopeSHA256,
            OnePieceSourceObservation.sha256(try OnePieceCatalogPublication.envelopeData(result.envelope)))
        XCTAssertEqual(try OnePieceCatalogPublication.verify(result.envelope, reviewedSHA256: hash,
            trustedKeys: keys, bootstrap: true), result.manifest)
        XCTAssertThrowsError(try OnePieceCatalogPublication.prepare(candidate: candidate, reviewedSHA256: "changed",
            keyID: keyID, privateKey: key, trustedKeys: keys, bootstrap: true))
        XCTAssertThrowsError(try OnePieceCatalogPublication.prepare(candidate: candidate, reviewedSHA256: hash,
            keyID: keyID, privateKey: Curve25519.Signing.PrivateKey(), trustedKeys: keys, bootstrap: true))
        let whitespace = candidate + Data("\n".utf8)
        XCTAssertThrowsError(try OnePieceCatalogPublication.prepare(candidate: whitespace,
            reviewedSHA256: OnePieceSourceObservation.sha256(whitespace), keyID: keyID,
            privateKey: key, trustedKeys: keys, bootstrap: true))
    }

    func testPublicationVerifiesBaselineRevisionAndRetainedRegistry() throws {
        let release = try fixture(), key = Curve25519.Signing.PrivateKey(), keyID = "one-piece-publication-fixture"
        let keys = [keyID: key.publicKey]
        let baseline = try OnePieceCatalogSignature.sign(release, keyID: keyID, privateKey: key)
        let next = try OnePieceCatalogBuilder.build(registry: release.registry, observations: release.observations,
            inventories: release.inventories, revision: 2, generatedAt: date, previous: release)
        let bytes = try next.canonicalData(), hash = OnePieceSourceObservation.sha256(bytes)
        let result = try OnePieceCatalogPublication.prepare(candidate: bytes, reviewedSHA256: hash,
            keyID: keyID, privateKey: key, trustedKeys: keys, previous: baseline)
        XCTAssertEqual(result.manifest.previousRevision, 1)
        XCTAssertEqual(result.manifest.classification.changeClass, .none)
        XCTAssertThrowsError(try OnePieceCatalogPublication.prepare(candidate: bytes, reviewedSHA256: hash,
            keyID: keyID, privateKey: key, trustedKeys: keys, bootstrap: true))
        XCTAssertThrowsError(try OnePieceCatalogPublication.verify(baseline,
            reviewedSHA256: OnePieceSourceObservation.sha256(try release.canonicalData()), trustedKeys: keys, previous: baseline))
        let bad = OnePieceCatalogReleaseEnvelope(keyID: keyID, payload: baseline.payload, signature: "invalid")
        XCTAssertThrowsError(try OnePieceCatalogPublication.prepare(candidate: bytes, reviewedSHA256: hash,
            keyID: keyID, privateKey: key, trustedKeys: keys, previous: bad))
    }

    func testPublisherCLISignsVerifiesAndRefusesDifferentExistingArtifacts() throws {
        var parent = Bundle(for: OnePieceCatalogCoreTests.self).bundleURL.deletingLastPathComponent()
        var executable: URL?
        for _ in 0..<6 {
            let candidate = parent.appendingPathComponent("one-piece-catalog-publisher")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { executable = candidate; break }
            parent.deleteLastPathComponent()
        }
        let cli = try XCTUnwrap(executable, "SwiftPM must build the publisher beside the test product")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnePiecePublisher-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try fixture().canonicalData(), hash = OnePieceSourceObservation.sha256(bytes)
        let key = Curve25519.Signing.PrivateKey(), keyID = "one-piece-cli-fixture"
        try bytes.write(to: root.appendingPathComponent("candidate.json"))
        try JSONEncoder().encode([keyID: key.publicKey.rawRepresentation.base64EncodedString()])
            .write(to: root.appendingPathComponent("keys.json"))
        func run(_ arguments: [String]) throws -> Int32 {
            let process = Process(); process.executableURL = cli; process.currentDirectoryURL = root
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment["ONE_PIECE_CATALOG_SIGNING_KEY"] = key.rawRepresentation.base64EncodedString()
            process.environment = environment
            let errors = Pipe()
            process.standardOutput = FileHandle.nullDevice; process.standardError = errors
            try process.run(); process.waitUntilExit()
            if process.terminationStatus != 0 {
                print(String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
            }
            return process.terminationStatus
        }
        let signing = ["sign", "--input", "candidate.json", "--trusted-keys", "keys.json", "--key-id", keyID,
            "--reviewed-payload-sha256", hash, "--bootstrap-registry", "yes", "--output", "signed.json", "--manifest", "manifest.json"]
        XCTAssertEqual(try run(signing), 0)
        XCTAssertEqual(try run(signing), 0, "Identical artifacts are idempotent")
        let hosted = ["verify-hosted-release", "--input", "signed.json", "--trusted-keys", "keys.json"]
        XCTAssertEqual(try run(hosted + ["--expected-revision", "1"]), 0)
        XCTAssertNotEqual(try run(hosted + ["--expected-revision", "2"]), 0)
        try JSONEncoder().encode([keyID: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()])
            .write(to: root.appendingPathComponent("wrong-keys.json"))
        XCTAssertNotEqual(try run(["verify-hosted-release", "--input", "signed.json", "--trusted-keys", "wrong-keys.json"]), 0)
        XCTAssertEqual(try run(["verify", "--input", "signed.json", "--trusted-keys", "keys.json",
            "--reviewed-payload-sha256", hash, "--bootstrap-registry", "yes", "--manifest", "verified.json"]), 0)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("manifest.json")),
                       try Data(contentsOf: root.appendingPathComponent("verified.json")))
        try Data("retain this artifact".utf8).write(to: root.appendingPathComponent("signed.json"))
        XCTAssertNotEqual(try run(hosted), 0)
        XCTAssertNotEqual(try run(signing), 0)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("signed.json")), Data("retain this artifact".utf8))
        var overwriting = signing
        overwriting[overwriting.firstIndex(of: "--output")! + 1] = "candidate.json"
        XCTAssertNotEqual(try run(overwriting), 0)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("candidate.json")), bytes)
    }
    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", value))!
    }

    private func fixture(numbers: [String] = ["OP01-120"], count: Int = 2,
                         complete: Bool = true) throws -> OnePieceCatalogRelease {
        let imageHash = OnePieceSourceObservation.sha256(Data("synthetic shared artwork".utf8))
        let products = (0..<count).map { OnePieceProduct(id: "fixture-release-\($0)", label: "Fixture release \($0)") }
        var cards: [OnePieceCanonicalCard] = []
        var artwork: [OnePieceArtwork] = []
        var printings: [OnePiecePhysicalPrinting] = []
        var observations: [OnePieceSourceObservation] = []
        var appearances: [OnePieceProductAppearance] = []
        for (numberIndex, number) in numbers.enumerated() {
            let card = OnePieceCanonicalCard(printedNumber: number, language: "en", name: "Fixture \(number)",
                printingCoverageComplete: complete, coverageReviewReference: complete ? "fixture-coverage-review" : nil)
            cards.append(card)
            let artworkID = uuid(100_000 + numberIndex)
            var artObservations: [String] = []
            for index in 0..<count {
                let printingID = uuid(1 + numberIndex * count + index)
                let sourceID = "\(number)-fixture-\(index)"
                var aliases: [OnePieceSourceAlias] = []
                var observationIDs: [String] = []
                for provider in [OnePieceObservationProvider.bandai, .limitless, .scrydex] {
                    let id = "\(provider.rawValue):\(sourceID)"
                    let observation = OnePieceProviderNormalizer.observation(provider: provider, capture: .init(
                        observationID: id, sourceID: sourceID,
                        sourceURL: URL(string: "https://fixture.invalid/\(provider.rawValue)/\(sourceID)")!,
                        observedAt: date, language: "en", payloadBytes: Data("fixture \(id)".utf8),
                        imageBytes: Data("synthetic shared artwork".utf8), productEvidence: [products[index].id],
                        printedEvidence: ["number": number, "finishVariantID": "normal"]))
                    observations.append(observation); aliases.append(observation.alias); observationIDs.append(id)
                    artObservations.append(id)
                }
                let review = OnePieceReview(reference: "fixture-distinction-review-\(printingID)", evidence: [
                    .init(kind: .printedIdentity, observationID: observationIDs[0], detail: "Fixture printed identity"),
                    .init(kind: .language, observationID: observationIDs[0], detail: "Fixture English language"),
                    .init(kind: .artwork, observationID: observationIDs[0], detail: "Fixture exact image bytes"),
                    .init(kind: .release, observationID: observationIDs[1], detail: "Fixture separate release"),
                    .init(kind: .finish, observationID: observationIDs[0], detail: "Synthetic fixture finish specification")
                ])
                printings.append(.init(id: printingID, canonicalCardID: card.id, artworkID: artworkID,
                    language: "en", releaseID: products[index].id, supportedVariantIDs: ["normal"],
                    status: .verified, review: review, sourceAliases: aliases))
                appearances.append(.init(printingID: printingID, productID: products[index].id,
                                         observationIDs: observationIDs))
            }
            artwork.append(.init(id: artworkID, referenceImageURL: URL(string: "https://fixture.invalid/image.png"),
                                 imageSHA256: imageHash, observationIDs: artObservations))
        }
        let inventories = [OnePieceObservationProvider.bandai, .limitless, .scrydex].map { provider in
            OnePieceSourceInventory(provider: provider.rawValue, snapshotID: "fixture-snapshot",
                paginationComplete: true, observationIDs: observations.filter { $0.alias.provider == provider.rawValue }.map(\.id))
        }
        return try OnePieceCatalogBuilder.build(registry: .init(canonicalCards: cards, artworks: artwork,
            printings: printings, variants: [.init(id: "normal", label: "Normal")], products: products,
            appearances: appearances), observations: observations, inventories: inventories,
            revision: 1, generatedAt: date)
    }

    private func alter(_ release: OnePieceCatalogRelease, reindex: Bool = true,
                       _ mutate: (inout [String: Any]) -> Void) throws -> OnePieceCatalogRelease {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: release.canonicalData()) as? [String: Any])
        mutate(&object)
        let decoded = try JSONDecoder().decode(OnePieceCatalogRelease.self, from: JSONSerialization.data(withJSONObject: object))
        guard reindex else { return decoded }
        return .init(schemaVersion: decoded.schemaVersion, rulesVersion: decoded.rulesVersion,
            catalogKind: decoded.catalogKind, revision: decoded.revision, generatedAt: decoded.generatedAt,
            registry: decoded.registry, observations: decoded.observations, inventories: decoded.inventories)
    }

    private func editPrintings(_ object: inout [String: Any], _ edit: (inout [[String: Any]]) -> Void) {
        var registry = object["registry"] as! [String: Any]
        var printings = registry["printings"] as! [[String: Any]]
        edit(&printings); registry["printings"] = printings; object["registry"] = registry
    }

    private func codes(_ release: OnePieceCatalogRelease, previous: OnePieceCatalogRelease? = nil) -> Set<String> {
        Set(OnePieceCatalogCandidateValidator.issues(in: release, previous: previous).map(\.code))
    }

    func testRegenerationRetainsUUIDsAndIsIndependentOfSourceRowOrder() throws {
        let first = try fixture()
        let reordered = try OnePieceCatalogBuilder.build(registry: .init(
            canonicalCards: first.registry.canonicalCards.reversed(), artworks: first.registry.artworks.reversed(),
            printings: first.registry.printings.reversed(), variants: first.registry.variants.reversed(),
            products: first.registry.products.reversed(), appearances: first.registry.appearances.reversed()),
            observations: first.observations.reversed(), inventories: first.inventories.reversed(),
            revision: first.revision, generatedAt: first.generatedAt)
        XCTAssertEqual(try first.canonicalData(), try reordered.canonicalData())
        XCTAssertEqual(Set(first.registry.printings.map(\.id)), Set(reordered.registry.printings.map(\.id)))
    }

    func testHistoricalStressNumbersAndFuturePrefixesKeepEverySuppliedCandidate() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "stress-identifiers", withExtension: "json"))
        let data = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let numbers = try XCTUnwrap(data["numbers"] as? [String])
        let distinctions = try XCTUnwrap(data["distinctions"] as? [String])
        let release = try fixture(numbers: numbers, count: distinctions.count)
        XCTAssertEqual(release.registry.canonicalCards.count, numbers.count)
        for number in numbers {
            XCTAssertEqual(release.indexes.printingIDsByCanonicalID["one-piece:en:\(number)"]?.count, distinctions.count)
        }
        XCTAssertTrue(release.indexes.supportedPrefixes.contains("PRB99"))
        let manyPromos = try fixture(numbers: ["P-106"], count: 137)
        XCTAssertEqual(manyPromos.indexes.printingIDsByCanonicalID["one-piece:en:P-106"]?.count, 137)
    }

    func testExactImageEqualityDoesNotJoinDifferentReleases() throws {
        let release = try fixture()
        XCTAssertEqual(Set(release.registry.printings.map(\.artworkID)).count, 1)
        XCTAssertEqual(Set(release.registry.printings.map(\.id)).count, 2)
        XCTAssertEqual(Set(release.registry.printings.compactMap(\.releaseID)).count, 2)
    }

    func testIncompleteCoverageDoesNotCreateAutomaticUniqueness() throws {
        let release = try fixture(count: 1, complete: false)
        XCTAssertEqual(release.indexes.printingIDsByCanonicalID.values.first?.count, 1)
        XCTAssertTrue(release.indexes.automaticCandidateIDsByCanonicalID.isEmpty)
    }

    func testProvisionalAndConflictedCandidatesCannotManufactureUniqueness() throws {
        for status in ["provisional", "conflicted", "quarantined"] {
            let release = try alter(fixture()) { object in
                editPrintings(&object) { $0[1]["status"] = status }
            }
            XCTAssertTrue(codes(release).isEmpty)
            XCTAssertEqual(release.indexes.printingIDsByCanonicalID.values.first?.count, 2)
            XCTAssertTrue(release.indexes.automaticCandidateIDsByCanonicalID.isEmpty)
        }
    }

    func testTamperedAutomaticIndexIsRejected() throws {
        let base = try fixture()
        let release = try alter(base, reindex: false) { object in
            editPrintings(&object) { $0[1]["status"] = "conflicted" }
        }
        XCTAssertTrue(codes(release).contains("invalidCandidateIndexes"))
    }

    func testUnverifiedUnknownFinishSurvivesRegenerationWithoutAutomaticAuthority() throws {
        for status in ["provisional", "conflicted", "quarantined"] {
            let review = try alter(fixture()) { object in
                editPrintings(&object) {
                    $0[1]["status"] = status
                    $0[1]["supportedVariantIDs"] = [] as [String]
                }
            }
            let built = try OnePieceCatalogBuilder.build(registry: review.registry,
                observations: review.observations, inventories: review.inventories,
                revision: 2, generatedAt: date, previous: review)
            let unknown = try XCTUnwrap(built.registry.printings.first { $0.id == uuid(2) })
            XCTAssertTrue(unknown.supportedVariantIDs.isEmpty)
            XCTAssertEqual(unknown.status.rawValue, status)
            XCTAssertEqual(built.indexes.printingIDsByCanonicalID.values.first?.count, 2)
            XCTAssertTrue(built.indexes.automaticCandidateIDsByCanonicalID.isEmpty,
                          "An unresolved candidate cannot manufacture a unique verified printing")
            let replay = try OnePieceCatalogBuilder.build(registry: built.registry,
                observations: Array(built.observations.reversed()),
                inventories: Array(built.inventories.reversed()), revision: 3,
                generatedAt: date, previous: built)
            XCTAssertEqual(replay.registry, built.registry)
        }
    }

    func testUnknownFinishCannotBeVerifiedOrReferenceUnregisteredVariants() throws {
        let base = try fixture()
        let emptyVerified = try alter(base) { object in
            editPrintings(&object) { $0[1]["supportedVariantIDs"] = [] as [String] }
        }
        XCTAssertTrue(codes(emptyVerified).contains("invalidPrintingVariants"))
        for status in ["provisional", "conflicted", "quarantined"] {
            let invalid = try alter(base) { object in
                editPrintings(&object) {
                    $0[1]["status"] = status
                    $0[1]["supportedVariantIDs"] = ["invented-finish"]
                }
            }
            XCTAssertTrue(codes(invalid).contains("invalidPrintingVariants"))
        }
        let review = try alter(base) { object in
            editPrintings(&object) {
                $0[1]["status"] = "provisional"
                $0[1]["supportedVariantIDs"] = [] as [String]
            }
        }
        let promoted = try OnePieceCatalogBuilder.build(registry: base.registry,
            observations: base.observations, inventories: base.inventories,
            revision: 2, generatedAt: date, previous: review)
        XCTAssertEqual(promoted.registry.printings.map(\.id), base.registry.printings.map(\.id))
        XCTAssertEqual(OnePieceCatalogChangeClassifier.classify(previous: review, current: promoted).changeClass,
                       .protectedReview)
    }

    func testDuplicateUUIDAliasAndMissingReferencesRejectWholeCandidate() throws {
        let base = try fixture()
        let duplicateID = try alter(base) { object in editPrintings(&object) { $0[1]["id"] = $0[0]["id"] } }
        XCTAssertTrue(codes(duplicateID).contains("duplicatePrintingID"))
        let duplicateAlias = try alter(base) { object in editPrintings(&object) { $0[1]["sourceAliases"] = $0[0]["sourceAliases"] } }
        XCTAssertTrue(codes(duplicateAlias).contains("duplicateSourceAlias"))
        let missingArt = try alter(base) { object in editPrintings(&object) { $0[0]["artworkID"] = uuid(999).uuidString } }
        XCTAssertTrue(codes(missingArt).contains("missingArtworkReference"))
        let missingCard = try alter(base) { object in editPrintings(&object) { $0[0]["canonicalCardID"] = "one-piece:en:OP99-099" } }
        XCTAssertTrue(codes(missingCard).contains("missingCanonicalReference"))
    }

    func testAliasEvidenceRequiresMatchingLanguageAndRetainsAllObservations() throws {
        let base = try fixture(count: 1)
        let wrongLanguage = try alter(base) { object in
            var observations = object["observations"] as! [[String: Any]]
            for index in observations.indices { observations[index]["language"] = "ja" }
            object["observations"] = observations
        }
        XCTAssertTrue(codes(wrongLanguage).contains("missingAliasObservation"))
        let missingAlias = try alter(base) { object in
            editPrintings(&object) {
                $0[0]["sourceAliases"] = [["provider": "bandai", "sourceID": "missing"]]
            }
        }
        XCTAssertTrue(codes(missingAlias).contains("missingAliasObservation"))
        let multipleLanguages = try alter(base) { object in
            var observations = object["observations"] as! [[String: Any]]
            var otherLanguage = observations[0]
            otherLanguage["id"] = "other-language-observation"
            otherLanguage["language"] = "ja"
            observations.insert(otherLanguage, at: 0)
            object["observations"] = observations
        }
        XCTAssertFalse(codes(multipleLanguages).contains("missingAliasObservation"),
                       "An earlier observation in another language must not hide matching evidence")
        let duplicateArtwork = try alter(base) { object in
            var registry = object["registry"] as! [String: Any]
            var artworks = registry["artworks"] as! [[String: Any]]
            var conflicting = artworks[0]
            conflicting["imageSHA256"] = String(repeating: "0", count: 64)
            artworks.append(conflicting)
            registry["artworks"] = artworks
            object["registry"] = registry
        }
        XCTAssertTrue(codes(duplicateArtwork).contains("duplicateArtworkID"))
        XCTAssertFalse(codes(duplicateArtwork).contains("contradictoryReviewedEvidence"),
                       "Duplicate input must reject safely while retaining first-row lookup semantics")
    }

    func testVerifiedStampRequiresSupportingObservation() throws {
        let base = try fixture(count: 1)
        let missing = try alter(base) { object in editPrintings(&object) { $0[0]["stamp"] = "Winner" } }
        XCTAssertTrue(codes(missing).contains("missingDistinctionEvidence"))
        let contradiction = try alter(missing) { object in
            editPrintings(&object) { rows in
                var review = rows[0]["review"] as! [String: Any]
                var evidence = review["evidence"] as! [[String: Any]]
                evidence.append(["kind": "stamp", "observationID": base.observations[0].id, "detail": "Unsupported stamp claim"])
                review["evidence"] = evidence; rows[0]["review"] = review
            }
        }
        XCTAssertTrue(codes(contradiction).contains("contradictoryReviewedEvidence"))
    }

    func testVerifiedFinishesRequireEvidenceForEveryDeclaredVariant() throws {
        let base = try fixture(count: 1)
        let missingReview = try alter(base) { object in
            editPrintings(&object) { rows in
                var review = rows[0]["review"] as! [String: Any]
                review["evidence"] = (review["evidence"] as! [[String: Any]]).filter { $0["kind"] as? String != "finish" }
                rows[0]["review"] = review
            }
        }
        XCTAssertTrue(codes(missingReview).contains("missingFinishEvidence"))
        let extraFinish = try alter(base) { object in
            var state = object["registry"] as! [String: Any]
            state["variants"] = [["id":"normal", "label":"Normal"], ["id":"foil", "label":"Foil"]]
            object["registry"] = state
            editPrintings(&object) { $0[0]["supportedVariantIDs"] = ["normal", "foil"] }
        }
        XCTAssertTrue(codes(extraFinish).contains("missingFinishEvidence"),
                      "A registered finish still requires evidence for this exact printing")
        let supported = try alter(extraFinish) { object in
            var rows = object["observations"] as! [[String: Any]]
            for index in rows.indices {
                var fields = rows[index]["printedEvidence"] as! [String: String]
                fields.removeValue(forKey: "finishVariantID")
                fields["finishVariantIDs"] = "[\"normal\",\"foil\"]"
                rows[index]["printedEvidence"] = fields
            }
            object["observations"] = rows
        }
        XCTAssertTrue(codes(supported).isEmpty)
    }

    func testMarketAndOpticalEvidenceCannotAuthorizePhysicalFinishes() throws {
        let base = try fixture(count: 1)
        for role in ["watermarked-digital-render", "photograph-of-physical-card"] {
            let optical = try alter(base) { object in
                var rows = object["observations"] as! [[String: Any]]
                for index in rows.indices {
                    var fields = rows[index]["printedEvidence"] as! [String: String]
                    fields["sourceRole"] = role; rows[index]["printedEvidence"] = fields
                }
                object["observations"] = rows
            }
            XCTAssertTrue(codes(optical).contains("missingFinishEvidence"), role)
        }
        let market = try alter(base) { object in
            var rows = object["observations"] as! [[String: Any]]
            for index in rows.indices { rows[index]["kind"] = "market" }
            object["observations"] = rows
        }
        XCTAssertTrue(codes(market).contains("missingFinishEvidence"))
    }

    func testMalformedAndContradictoryFinishClaimsAreRejected() throws {
        let base = try fixture(count: 1)
        for value in ["normal", "[]", "[\"normal\",\"normal\"]", "[1]", "[\"foil\"]"] {
            let malformed = try alter(base) { object in
                var rows = object["observations"] as! [[String: Any]]
                for index in rows.indices {
                    var fields = rows[index]["printedEvidence"] as! [String: String]
                    fields.removeValue(forKey: "finishVariantID"); fields["finishVariantIDs"] = value
                    rows[index]["printedEvidence"] = fields
                }
                object["observations"] = rows
            }
            XCTAssertTrue(codes(malformed).contains("missingFinishEvidence"), value)
        }
        let conflictingForms = try alter(base) { object in
            var rows = object["observations"] as! [[String: Any]]
            for index in rows.indices {
                var fields = rows[index]["printedEvidence"] as! [String: String]
                fields["finishVariantIDs"] = "[\"normal\"]"; rows[index]["printedEvidence"] = fields
            }
            object["observations"] = rows
        }
        XCTAssertTrue(codes(conflictingForms).contains("missingFinishEvidence"))
    }

    func testFinishRulesRejectEarlierContractWithoutEvidenceMigration() throws {
        let earlier = try alter(fixture()) { $0["rulesVersion"] = 1 }
        XCTAssertTrue(codes(earlier).contains("unsupportedContract"))
    }

    func testDONExclusionAndCanonicalLanguageValidation() throws {
        XCTAssertNil(OnePieceTextNormalization.printedNumber("DON-001"))
        XCTAssertNil(OnePieceTextNormalization.printedNumber("DON!!"))
        XCTAssertEqual(OnePieceTextNormalization.printedNumber(" op99-001 "), "OP99-001")
        XCTAssertThrowsError(try fixture(numbers: ["DON-001"]))
        let languageMismatch = try alter(fixture()) { object in editPrintings(&object) { $0[0]["language"] = "ja" } }
        XCTAssertTrue(codes(languageMismatch).contains("printingLanguageMismatch"))
    }

    func testPermanentPrintingDeletionAndIdentityMutationAreRejected() throws {
        let base = try fixture()
        let removed = try alter(base) { object in object["revision"] = 2; editPrintings(&object) { $0.removeLast() } }
        XCTAssertTrue(codes(removed, previous: base).contains("removedPermanentPrinting"))
        let mutated = try alter(base) { object in object["revision"] = 2; editPrintings(&object) { $0[0]["stamp"] = "Winner" } }
        XCTAssertTrue(codes(mutated, previous: base).contains("mutatedPermanentIdentity"))
    }

    private func correctionObject(_ base: OnePieceCatalogRelease, kind: String,
                                  from: [UUID], to: [UUID], aliases: [OnePieceSourceAlias] = []) throws -> [String: Any] {
        let correction = OnePieceRegistryCorrection(id: "fixture-reviewed-correction", kind: OnePieceCorrectionKind(rawValue: kind)!,
            fromPrintingIDs: from, toPrintingIDs: to, movedAliases: aliases,
            review: .init(reference: "fixture-correction-review", evidence: [
                .init(kind: .printedIdentity, observationID: base.observations[0].id, detail: "Fixture identity correction")
            ]))
        return try JSONSerialization.jsonObject(with: JSONEncoder().encode(correction)) as! [String: Any]
    }

    func testAliasReassignmentNeedsExplicitRetainedCorrection() throws {
        let base = try fixture()
        let old = base.registry.printings[0], new = base.registry.printings[1]
        let alias = old.sourceAliases[0]
        let moved = try alter(base) { object in
            object["revision"] = 2
            editPrintings(&object) { rows in
                var oldAliases = rows[0]["sourceAliases"] as! [[String: Any]]
                let movedAlias = oldAliases.removeFirst()
                rows[0]["sourceAliases"] = oldAliases
                var newAliases = rows[1]["sourceAliases"] as! [[String: Any]]
                newAliases.append(movedAlias); rows[1]["sourceAliases"] = newAliases
            }
        }
        XCTAssertTrue(codes(moved, previous: base).contains("unreviewedAliasChange"))
        let correction = try correctionObject(base, kind: "aliasReassignment", from: [old.id], to: [new.id], aliases: [alias])
        let reviewed = try alter(moved) { object in
            var registry = object["registry"] as! [String: Any]
            registry["corrections"] = [correction]; object["registry"] = registry
        }
        XCTAssertTrue(codes(reviewed, previous: base).isEmpty)
    }

    func testSupersessionRetainsOldOwnedUUIDAndRequiresReviewedGraph() throws {
        let base = try fixture()
        let old = base.registry.printings[0].id, new = base.registry.printings[1].id
        let correction = try correctionObject(base, kind: "supersession", from: [old], to: [new])
        let release = try alter(base) { object in
            object["revision"] = 2
            editPrintings(&object) { $0[0]["status"] = "superseded"; $0[1]["supersedes"] = [old.uuidString] }
            var registry = object["registry"] as! [String: Any]
            registry["corrections"] = [correction]; object["registry"] = registry
        }
        XCTAssertTrue(codes(release, previous: base).isEmpty)
        XCTAssertEqual(release.registry.printings.count, 2)
        XCTAssertEqual(release.indexes.printingIDsByCanonicalID.values.first, [new])
    }

    func testReviewedSplitAndMergeGraphs() throws {
        let base = try fixture(count: 3)
        let ids = base.registry.printings.map(\.id)
        for split in [true, false] {
            let from = split ? [ids[0]] : [ids[0], ids[1]]
            let to = split ? [ids[1], ids[2]] : [ids[2]]
            let correction = try correctionObject(base, kind: split ? "split" : "merge", from: from, to: to)
            let release = try alter(base) { object in
                object["revision"] = 2
                editPrintings(&object) { rows in
                    for index in rows.indices {
                        if from.contains(ids[index]) { rows[index]["status"] = "superseded" }
                        if to.contains(ids[index]) { rows[index]["supersedes"] = from.map(\.uuidString) }
                    }
                }
                var registry = object["registry"] as! [String: Any]
                registry["corrections"] = [correction]; object["registry"] = registry
            }
            XCTAssertTrue(codes(release, previous: base).isEmpty)
            XCTAssertEqual(release.registry.printings.count, ids.count)
        }
    }

    func testSupersessionCycleIsRejected() throws {
        let base = try fixture()
        let ids = base.registry.printings.map(\.id)
        let cyclic = try alter(base) { object in editPrintings(&object) { rows in
            rows[0]["status"] = "superseded"; rows[1]["status"] = "superseded"
            rows[0]["supersedes"] = [ids[1].uuidString]; rows[1]["supersedes"] = [ids[0].uuidString]
        } }
        XCTAssertTrue(codes(cyclic).contains("supersessionCycle"))
    }

    private func mapping(_ printing: OnePiecePhysicalPrinting, product: String, observationID: String) -> OnePieceMarketMapping {
        .init(printingID: printing.id, provider: "fixture-market", productID: product, variantID: "normal",
              market: "us", currency: "USD", condition: "near-mint", status: .exact,
              review: .init(reference: "fixture-market-review", evidence: [
                .init(kind: .printedIdentity, observationID: observationID, detail: "Fixture exact SKU"),
                .init(kind: .marketIdentity, observationID: observationID, detail: "Fixture SKU/finish/release qualifiers")
              ]))
    }

    private func withMappings(_ base: OnePieceCatalogRelease, assignments: [(Int, String)]) throws -> OnePieceCatalogRelease {
        var marketObservations: [OnePieceSourceObservation] = []
        var mappingObjects: [(Int, Any)] = []
        for (index, product) in assignments {
            let printing = base.registry.printings[index]
            let id = "fixture-market:\(index):\(product)"
            let observation = OnePieceProviderNormalizer.observation(provider: .scrydex, capture: .init(
                observationID: id, kind: .market, sourceID: product, sourceURL: URL(string: "https://fixture.invalid/market/\(product)")!,
                observedAt: date, language: "en", payloadBytes: Data("fixture SKU \(product)".utf8),
                productEvidence: printing.releaseID.map { [$0] } ?? [], printedEvidence: [
                    "number": "OP01-120", "marketProductID": product, "finishVariantID": "normal",
                    "market": "us", "currency": "USD", "condition": "near-mint"
                ]))
            // An explicit synthetic market provider remains separate from the
            // real Scrydex schema/access contract.
            marketObservations.append(.init(id: id, kind: .market, alias: .init(provider: "fixture-market", sourceID: product),
                sourceURL: observation.sourceURL, observedAt: observation.observedAt, language: observation.language,
                payloadSHA256: observation.payloadSHA256, productEvidence: observation.productEvidence,
                printedEvidence: observation.printedEvidence))
            mappingObjects.append((index, try JSONSerialization.jsonObject(with: JSONEncoder().encode(
                mapping(printing, product: product, observationID: id)))))
        }
        let inventory = OnePieceSourceInventory(provider: "fixture-market", snapshotID: "fixture-market-snapshot",
            paginationComplete: true, observationIDs: marketObservations.map(\.id))
        let observationObjects = try marketObservations.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) }
        let inventoryObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(inventory))
        return try alter(base) { object in
            object["revision"] = base.revision + 1
            editPrintings(&object) { rows in
                for (index, mapping) in mappingObjects { rows[index]["marketMappings"] = [mapping] }
            }
            object["observations"] = (object["observations"] as! [Any]) + observationObjects
            object["inventories"] = (object["inventories"] as! [Any]) + [inventoryObject]
        }
    }

    func testOneSKUCannotQuoteTwoDifferentPhysicalPrintings() throws {
        let base = try fixture()
        let release = try withMappings(base, assignments: [(0, "same-sku"), (1, "same-sku")])
        XCTAssertTrue(codes(release).contains("conflictingMarketMapping"))
    }

    func testDuplicateMarketMappingsCannotSilentlyDisableExactPricing() throws {
        let base = try withMappings(fixture(), assignments: [(0, "454664")])
        let release = try alter(base) { object in
            editPrintings(&object) { rows in
                let mappings = rows[0]["marketMappings"] as! [Any]
                rows[0]["marketMappings"] = mappings + mappings
            }
        }
        XCTAssertTrue(codes(release).contains("duplicateMarketMapping"))
    }

    func testTCGplayerSKUCollisionCannotBeHiddenByDescriptiveQualifiers() throws {
        let base = try withMappings(fixture(), assignments: [(0, "454664"), (1, "454664")])
        let release = try alter(base) { object in
            editPrintings(&object) { rows in
                for index in rows.indices {
                    var mappings = rows[index]["marketMappings"] as! [[String: Any]]
                    mappings[0]["provider"] = "tcgplayer"
                    mappings[0]["providerVariantID"] = "Normal"
                    mappings[0]["condition"] = "aggregate"
                    mappings[0]["qualifiers"] = ["productName": "Reviewed release \(index)"]
                    rows[index]["marketMappings"] = mappings
                }
            }
            var observations = object["observations"] as! [[String: Any]]
            for index in observations.indices where (observations[index]["kind"] as? String) == "market" {
                var alias = observations[index]["alias"] as! [String: Any]
                alias["provider"] = "tcgplayer"; observations[index]["alias"] = alias
                var fields = observations[index]["printedEvidence"] as! [String: String]
                fields["marketVariantID"] = "Normal"; fields["condition"] = "aggregate"
                let releaseIndex = (observations[index]["productEvidence"] as! [String])[0].suffix(1)
                fields["qualifier:productName"] = "Reviewed release \(releaseIndex)"
                observations[index]["printedEvidence"] = fields
            }
            object["observations"] = observations
            var inventories = object["inventories"] as! [[String: Any]]
            for index in inventories.indices where inventories[index]["provider"] as? String == "fixture-market" {
                inventories[index]["provider"] = "tcgplayer"
            }
            object["inventories"] = inventories
        }
        XCTAssertEqual(codes(release), ["conflictingMarketMapping"])
        let numericAlias = try alter(release) { object in
            editPrintings(&object) { rows in
                var mappings = rows[1]["marketMappings"] as! [[String: Any]]
                mappings[0]["productID"] = "0454664"; rows[1]["marketMappings"] = mappings
            }
            var observations = object["observations"] as! [[String: Any]]
            for index in observations.indices where (observations[index]["id"] as? String)?.hasPrefix("fixture-market:1:") == true {
                var fields = observations[index]["printedEvidence"] as! [String: String]
                fields["marketProductID"] = "0454664"; observations[index]["printedEvidence"] = fields
            }
            object["observations"] = observations
        }
        XCTAssertEqual(codes(numericAlias), ["conflictingMarketMapping"])
    }

    func testProductMetadataRejectsBlankLabelsAndInvalidCalendarDates() throws {
        let base = try fixture()
        for (key, value) in [("id", " "), ("id", " product "), ("label", "   "),
                             ("releaseDate", "2026-02-30"), ("releaseDate", "2026-2-03")] {
            let release = try alter(base) { object in
                var registry = object["registry"] as! [String: Any]
                var products = registry["products"] as! [[String: Any]]
                products[0][key] = value
                registry["products"] = products; object["registry"] = registry
            }
            XCTAssertTrue(codes(release).contains("invalidProduct"), "Invalid product \(key): \(value)")
        }
        let whitespaceVariant = try alter(base) { object in
            var registry = object["registry"] as! [String: Any]
            var variants = registry["variants"] as! [[String: Any]]
            variants.append(["id": " normal ", "label": "Normal"])
            registry["variants"] = variants; object["registry"] = registry
        }
        XCTAssertTrue(codes(whitespaceVariant).contains("invalidVariant"))
        XCTAssertNotNil(OnePieceTextNormalization.releaseDate("2024-02-29"))
        XCTAssertNil(OnePieceTextNormalization.releaseDate("2025-02-29"))
    }

    func testMappingCorrectionInvalidatesOnlyChangedPrintingAndRequiresProtectedReview() throws {
        let base = try fixture()
        let printing = base.registry.printings[0]
        let current = try withMappings(base, assignments: [(0, "reviewed-sku")])
        XCTAssertTrue(codes(current, previous: base).isEmpty)
        let classification = OnePieceCatalogChangeClassifier.classify(previous: base, current: current)
        XCTAssertEqual(classification.changeClass, .protectedReview)
        XCTAssertEqual(classification.marketMappingInvalidations, [printing.id])
    }

    func testCanonicalNumberAloneCannotVerifyMarketSKU() throws {
        let base = try fixture()
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            mapping(base.registry.printings[0], product: "unproven-sku", observationID: base.observations[0].id)))
        let release = try alter(base) { object in editPrintings(&object) { $0[0]["marketMappings"] = [encoded] } }
        XCTAssertTrue(codes(release).contains("marketIdentityMismatch"))
    }

    func testProductAppearancesAreManyToManyWithoutAdditionalOwnershipUUIDs() throws {
        let base = try fixture()
        let release = try alter(base) { object in
            var registry = object["registry"] as! [String: Any]
            var appearances = registry["appearances"] as! [[String: Any]]
            var extra = appearances[0]; extra["productID"] = base.registry.products[1].id
            appearances.append(extra); registry["appearances"] = appearances; object["registry"] = registry
            var observations = object["observations"] as! [[String: Any]]
            let evidenceID = (extra["observationIDs"] as! [String])[0]
            let index = observations.firstIndex { $0["id"] as? String == evidenceID }!
            var productEvidence = observations[index]["productEvidence"] as! [String]
            productEvidence.append(base.registry.products[1].id)
            observations[index]["productEvidence"] = productEvidence; object["observations"] = observations
        }
        XCTAssertTrue(codes(release).isEmpty)
        XCTAssertEqual(release.registry.printings.count, base.registry.printings.count)
        XCTAssertEqual(release.registry.appearances.count, base.registry.appearances.count + 1)
    }

    func testIncompletePaginationCannotAdvertiseAutomaticAuthority() throws {
        let release = try alter(fixture()) { object in
            var inventories = object["inventories"] as! [[String: Any]]
            inventories[0]["paginationComplete"] = false; object["inventories"] = inventories
        }
        XCTAssertTrue(codes(release).contains("incompleteSourceInventory"))
    }

    func testRetirementCannotSilentlyRemoveAPossiblePrinting() throws {
        let base = try fixture()
        let release = try alter(base) { object in
            object["revision"] = 2
            editPrintings(&object) { $0[0]["status"] = "superseded" }
        }
        XCTAssertTrue(codes(release, previous: base).contains("orphanSupersededPrinting"))
    }

    func testUnjoinedDiscoveryPreventsClaimingCompleteCandidateScope() throws {
        let base = try fixture()
        let unjoined = OnePieceProviderNormalizer.observation(provider: .bandai, capture: .init(
            observationID: "new-discovery", sourceID: "new-physical-release",
            sourceURL: URL(string: "https://fixture.invalid/new-release")!, observedAt: date, language: "en",
            payloadBytes: Data("new catalog discovery".utf8), printedEvidence: ["number": "OP01-120"]))
        let release = OnePieceCatalogRelease(revision: 2, generatedAt: date, registry: base.registry,
            observations: base.observations + [unjoined], inventories: base.inventories + [
                .init(provider: "bandai", snapshotID: "new-snapshot", paginationComplete: true, observationIDs: [unjoined.id])
            ])
        XCTAssertTrue(codes(release).contains("unreconciledCanonicalObservation"))
    }

    func testContentOnlyAllowListExcludesAuthorityAndSourceChanges() throws {
        let base = try fixture()
        XCTAssertEqual(OnePieceCatalogChangeClassifier.classify(previous: base, current: base).changeClass, .none)
        let rename = try alter(base) { object in
            var registry = object["registry"] as! [String: Any]
            var cards = registry["canonicalCards"] as! [[String: Any]]
            cards[0]["name"] = "Corrected display name"; registry["canonicalCards"] = cards; object["registry"] = registry
        }
        XCTAssertEqual(OnePieceCatalogChangeClassifier.classify(previous: base, current: rename).changeClass, .contentOnly)
        let authority = try alter(base) { object in editPrintings(&object) { $0[0]["status"] = "provisional" } }
        XCTAssertEqual(OnePieceCatalogChangeClassifier.classify(previous: base, current: authority).changeClass, .protectedReview)
    }

    func testProductAppearanceNeedsProductEvidenceRatherThanJustAnObservationID() throws {
        let base = try fixture()
        let release = try alter(base) { object in
            var registry = object["registry"] as! [String: Any]
            var appearances = registry["appearances"] as! [[String: Any]]
            appearances[0]["productID"] = base.registry.products[1].id
            registry["appearances"] = appearances; object["registry"] = registry
        }
        XCTAssertTrue(codes(release).contains("missingProductAppearanceEvidence"))
    }

    func testProductAppearanceRequiresEvidenceFromItsExactPrinting() throws {
        let base = try fixture(numbers: ["OP01-120", "ST01-001"])
        for wrongPrinting in [base.registry.printings[1], base.registry.printings[2]] {
            let release = try alter(base) { object in
                var registry = object["registry"] as! [String: Any]
                var appearances = registry["appearances"] as! [[String: Any]]
                appearances[0]["printingID"] = wrongPrinting.id.uuidString
                registry["appearances"] = appearances; object["registry"] = registry
            }
            XCTAssertTrue(codes(release).contains("missingProductAppearanceEvidence"),
                          "A product observation for another printing/card must not authorize membership")
        }
    }

    func testProviderByteHashesAndAliasesStaySeparate() throws {
        let bytes = Data([0, 1, 2, 255])
        let capture = OnePieceProviderCapture(observationID: "fixture", sourceID: "row-1",
            sourceURL: URL(string: "https://fixture.invalid/source")!, observedAt: date, language: "en",
            payloadBytes: bytes, imageBytes: bytes)
        let bandai = OnePieceProviderNormalizer.observation(provider: .bandai, capture: capture)
        let limitless = OnePieceProviderNormalizer.observation(provider: .limitless, capture: capture)
        XCTAssertEqual(bandai.payloadSHA256, OnePieceSourceObservation.sha256(bytes))
        XCTAssertNotEqual(bandai.alias, limitless.alias)
        XCTAssertEqual(bandai.imageSHA256, limitless.imageSHA256)
        XCTAssertNotEqual(bandai.payloadSHA256, OnePieceSourceObservation.sha256(Data([0, 1, 2])))
    }

    func testPublisherPreservesRegistryAndRequiresBaselineBeforeWriting() throws {
        let release = try fixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnePiecePublisher-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = root.appendingPathComponent("registry.json")
        let observations = root.appendingPathComponent("observations.json")
        let inventories = root.appendingPathComponent("inventories.json")
        let output = root.appendingPathComponent("candidate.json")
        let registryBytes = try JSONEncoder().encode(release.registry)
        try registryBytes.write(to: registry)
        try JSONEncoder().encode(release.observations).write(to: observations)
        try JSONEncoder().encode(release.inventories).write(to: inventories)
        let binary = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("one-piece-catalog-publisher")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: binary.path))
        func run(_ extra: [String], outputPath: String = output.path) throws -> Int32 {
            let process = Process(); process.executableURL = binary
            process.arguments = ["build", "--registry", registry.path, "--observations", observations.path,
                "--inventories", inventories.path, "--revision", "1", "--generated-at", date,
                "--output", outputPath] + extra
            process.standardOutput = Pipe(); process.standardError = Pipe()
            try process.run(); process.waitUntilExit()
            return process.terminationStatus
        }
        XCTAssertNotEqual(try run([]), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try run(["--bootstrap-registry", "yes"]), 0)
        let candidate = try JSONDecoder().decode(OnePieceCatalogRelease.self, from: Data(contentsOf: output))
        XCTAssertEqual(candidate, release)
        XCTAssertEqual(try Data(contentsOf: registry), registryBytes)
        XCTAssertNotEqual(try run(["--bootstrap-registry", "yes"], outputPath: registry.path), 0)
        let symlink = root.appendingPathComponent("registry-link.json")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: registry)
        XCTAssertNotEqual(try run(["--bootstrap-registry", "yes"], outputPath: symlink.path), 0)
        XCTAssertEqual(try Data(contentsOf: registry), registryBytes)
    }

    func testSignedReleaseBindsPayloadKeyContractAndRevision() throws {
        let release = try fixture()
        let key = Curve25519.Signing.PrivateKey()
        let envelope = try OnePieceCatalogSignature.sign(release, keyID: "one-piece-fixture", privateKey: key)
        let now = ISO8601DateFormatter().date(from: date)!
        let verified = try OnePieceCatalogSignature.verify(envelope, trustedKeys: [envelope.keyID: key.publicKey], now: now)
        XCTAssertEqual(verified.release, release)
        XCTAssertEqual(verified.payloadFingerprint, OnePieceSourceObservation.sha256(try release.canonicalData()))
        XCTAssertEqual(verified.verifiedAt, now)
        XCTAssertThrowsError(try OnePieceCatalogSignature.verify(envelope, trustedKeys: [:], now: now)) { error in
            XCTAssertEqual(error as? OnePieceCatalogSignatureError, .unknownKey)
        }
        let otherKey = Curve25519.Signing.PrivateKey()
        XCTAssertThrowsError(try OnePieceCatalogSignature.verify(envelope,
            trustedKeys: [envelope.keyID: otherKey.publicKey], now: now)) { error in
            XCTAssertEqual(error as? OnePieceCatalogSignatureError, .invalidSignature)
        }
        XCTAssertThrowsError(try OnePieceCatalogSignature.verify(envelope,
            trustedKeys: [envelope.keyID: key.publicKey], minimumRevision: release.revision, now: now)) { error in
            XCTAssertEqual(error as? OnePieceCatalogSignatureError, .nonMonotonicRevision)
        }
        XCTAssertThrowsError(try OnePieceCatalogSignature.sign(release, keyID: "magic-fixture", privateKey: key)) { error in
            XCTAssertEqual(error as? OnePieceCatalogSignatureError, .invalidKeyID)
        }
    }

    func testSignatureRejectsChangedBytesFutureTimeAndPayloadLimit() throws {
        let release = try fixture()
        let key = Curve25519.Signing.PrivateKey()
        let envelope = try OnePieceCatalogSignature.sign(release, keyID: "one-piece-fixture", privateKey: key)
        let keys = [envelope.keyID: key.publicKey]
        let now = ISO8601DateFormatter().date(from: date)!
        let tampered = OnePieceCatalogReleaseEnvelope(keyID: envelope.keyID,
            payload: envelope.payload + "AA", signature: envelope.signature)
        XCTAssertThrowsError(try OnePieceCatalogSignature.verify(tampered, trustedKeys: keys, now: now))
        let padded = OnePieceCatalogReleaseEnvelope(keyID: envelope.keyID,
            payload: envelope.payload + "=", signature: envelope.signature)
        XCTAssertThrowsError(try OnePieceCatalogSignature.verify(padded, trustedKeys: keys, now: now)) { error in
            XCTAssertEqual(error as? OnePieceCatalogSignatureError, .invalidEncoding)
        }
        XCTAssertThrowsError(try OnePieceCatalogSignature.verify(envelope, trustedKeys: keys,
            now: now.addingTimeInterval(-301))) { error in
            XCTAssertEqual(error as? OnePieceCatalogSignatureError, .futureRelease)
        }
        XCTAssertThrowsError(try OnePieceCatalogSignature.verify(envelope, trustedKeys: keys, now: now, maximumPayloadBytes: 1)) { error in
            XCTAssertEqual(error as? OnePieceCatalogSignatureError, .oversizedPayload)
        }
    }
}
