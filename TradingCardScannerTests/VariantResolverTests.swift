import XCTest
import SwiftData
import PokemonCatalogCore
@testable import TradingCardScanner

/// Expectations come from the original BOM CSV, independently of the runtime table.
final class PokemonFinishEvidenceTests: XCTestCase {
    private func ledger() throws -> [[String: String]] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("TestFixtures/TradingCards/PokemonFinishEvidence/confirmed_repairs_v2.csv"), encoding: .utf8)
            .replacingOccurrences(of: "\u{feff}", with: "")
        var table: [[String]] = [], row: [String] = [], cell = "", quoted = false
        var chars = Array(text).makeIterator()
        while let c = chars.next() {
            if c == "\"" { quoted.toggle() }
            else if c == "," && !quoted { row.append(cell); cell = "" }
            else if (c == "\n" || c == "\r\n") && !quoted {
                row.append(cell); table.append(row); row = []; cell = ""
            } else { cell.append(c) }
        }
        if !cell.isEmpty { row.append(cell); table.append(row) }
        let headers = try XCTUnwrap(table.first)
        return table.dropFirst().map { Dictionary(uniqueKeysWithValues: zip(headers, $0)) }
    }

    private func snapshot() async throws -> PokemonChecklistSnapshot {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let loaded = await PokemonChecklistStore(root: root, bundle: .main).bundledSnapshot()
        return try XCTUnwrap(loaded)
    }

    private func card(_ id: String, in snapshot: PokemonChecklistSnapshot) throws -> TCGdexCard {
        let parts = id.split(separator: "-", maxSplits: 1).map(String.init)
        return try XCTUnwrap(PokemonOfflineCardFactory.card(in: snapshot, providerSetID: parts[0],
            localID: parts[1], expectedOfficialCount: snapshot.entry(forProviderID: parts[0])?.officialCount))
    }

    func testEveryLedgerMembershipThroughBundledLoaderFactoryAndResolver() async throws {
        let snapshot = try await snapshot()
        try assertLedgerMinimums(in: snapshot)
    }

    private func assertLedgerMinimums(in snapshot: PokemonChecklistSnapshot) throws {
        let rows = try ledger()
        XCTAssertEqual(rows.count, 457)
        XCTAssertEqual(Set(rows.compactMap { $0["provider_id"] }).count, 457)
        var memberships = 0
        for row in rows {
            let id = try XCTUnwrap(row["provider_id"])
            let card = try card(id, in: snapshot)
            let entry = try XCTUnwrap(snapshot.entry(forProviderID: card.set.id))
            let slots = try XCTUnwrap(snapshot.checklist(for: entry.set.catalogID)).filter { $0.providerID == id }
            XCTAssertEqual(Set(slots.map(\.id)).count, slots.count, id)
            XCTAssertEqual(Set(slots.compactMap(\.masterSetVariant)).count, slots.count, id)
            let options = VariantResolver.options(for: IdentifiedCard.pokemon(card, setCode: entry.set.code).variantEvidence)
            for finish in try XCTUnwrap(row["required_minimum_finishes"]).components(separatedBy: "; ") {
                XCTAssertTrue(slots.contains { $0.masterSetVariant?.id == finish }, "\(id) missing retained \(finish)")
                XCTAssertTrue(options.contains { $0.id == finish }, "\(id) missing resolved \(finish)")
            }
            memberships += Int(row["missing_finish_count"]!)!
        }
        XCTAssertEqual(memberships, 510)
    }

    func testExactIdentitiesControlsAndExcludedPrintings() async throws {
        let snapshot = try await snapshot()
        for (id, expected) in [("xy12-80", ["normal", "reverse"]), ("xy12-108", ["normal", "holo"]),
                               ("xy12-11", ["normal", "holo", "reverse"]), ("sm6-1", ["normal", "reverse"]),
                               ("sm6-31", ["normal", "holo"]), ("dv1-21", ["normal", "holo"]),
                               ("det1-10", ["normal", "holo"])] {
            let value = try card(id, in: snapshot)
            XCTAssertEqual(value.id, id)
            XCTAssertEqual(Set(value.catalogVariants.map(\.id)), Set(expected), id)
            XCTAssertTrue(value.catalogVariants.allSatisfy { ["normal", "holo", "reverse"].contains($0.id) })
            XCTAssertNil(value.pricing)
        }
        for id in (109...113).map({ "xy12-\($0)" }) + (132...146).map({ "sm6-\($0)" })
            + (74...78).map({ "sm3.5-\($0)" }) + (71...78).map({ "sm7.5-\($0)" }) {
            XCTAssertEqual(try card(id, in: snapshot).catalogVariants, [.normal], id)
        }
        XCTAssertEqual(try card("dv1-20", in: snapshot).catalogVariants.count, 2, "No stamped/Cosmos/World Championship additions")
    }

    func testExpandedExactFinishAndControlMemberships() async throws {
        let snapshot = try await snapshot()
        for (id, minimum) in [("sm3.5-40", ["holo"]), ("sm3.5-32", ["holo", "reverse"]),
                              ("sm7.5-3", ["holo", "reverse"]), ("sm7.5-7", ["holo"])] {
            let value = try card(id, in: snapshot)
            XCTAssertTrue(Set(minimum).isSubset(of: Set(value.catalogVariants.map(\.id))), id)
        }
        let holoNumbers: Set<Int> = [2, 5, 6, 8, 11, 14, 15, 21]
        for number in 1...34 {
            let value = try card("dc1-\(number)", in: snapshot)
            let finishes = Set(value.catalogVariants.map(\.id))
            XCTAssertEqual(finishes.contains("reverse"), ![6, 15].contains(number), value.id)
            XCTAssertEqual(finishes.contains("holo"), holoNumbers.contains(number), value.id)
        }
        for number in 1...16 {
            let value = try card("ru1-\(number)", in: snapshot)
            XCTAssertEqual(Set(value.catalogVariants.map(\.id)), [1, 7, 9].contains(number) ? ["normal", "holo"] : ["normal"], value.id)
        }
        var celebrationIDs = Set<String>()
        for set in ["cel25", "cel25cc"] {
            if let entry = snapshot.entry(forProviderID: set), let slots = snapshot.checklist(for: entry.set.catalogID) {
                for slot in slots {
                    celebrationIDs.insert(slot.providerID)
                    XCTAssertTrue(try card(slot.providerID, in: snapshot).catalogVariants.contains(.holo), slot.providerID)
                }
            }
        }
        XCTAssertEqual(celebrationIDs.count, 50)
        let normalControl = IdentifiedCard.pokemon(try card("ru1-2", in: snapshot), setCode: "RUM").variantEvidence
        XCTAssertFalse(normalControl.physicalCoverageVerified)
        XCTAssertEqual(VariantResolver.resolve(normalControl), .resolved(.init(variant: .normal, resolution: .uniqueInCatalog)))
        XCTAssertEqual(VariantResolver.resolve(normalControl, finishLock: PhysicalVariant.normal),
            .resolved(.init(variant: .normal, resolution: .uniqueInCatalog)))
        for number in ["24a", "28a", "54a", "55a", "92a", "107a"] {
            let value = try card("xya-\(number)", in: snapshot)
            let expected: Set<PhysicalVariant> = ["92a", "107a"].contains(number) ? [.normal, .holo] : [.holo]
            XCTAssertEqual(Set(value.catalogVariants), expected)
        }
    }

    func testMissingEvidenceNeverBecomesNormalAndSupportedSingletonResolvesAutomatically() throws {
        let empty = TCGdexCard(id: "fixture-1", localId: "1", name: "Unknown", image: nil, rarity: nil,
            set: .init(id: "fixture", name: "Fixture", cardCount: .init(total: 1, official: 1)),
            variants: nil, pricing: nil, variantsDetailed: nil)
        XCTAssertTrue(PokemonMasterSetDefinition.requiredVariants(for: empty).isEmpty)
        XCTAssertTrue(empty.catalogVariants.isEmpty)
        let explicitNormal = TCGdexCard(id: "fixture-1", localId: "1", name: "Known Normal", image: nil, rarity: nil,
            set: empty.set, variants: .init(firstEdition: false, holo: false, normal: true, reverse: false, wPromo: nil),
            pricing: nil, variantsDetailed: nil)
        XCTAssertEqual(PokemonMasterSetDefinition.requiredVariants(for: explicitNormal).map(\.variant), [.normal])
        let partial = VariantEvidence(game: .pokemon, setID: "fixture", cardNumber: "1", catalogVariants: [.holo],
            physicalCoverageVerified: false, explicitMembershipSupported: true)
        XCTAssertEqual(VariantResolver.resolve(partial), .resolved(.init(variant: .holo, resolution: .uniqueInCatalog)))
        XCTAssertEqual(VariantResolver.resolve(partial, finishLock: PhysicalVariant.holo), .resolved(.init(variant: .holo, resolution: .uniqueInCatalog)))
        XCTAssertEqual(VariantResolver.resolveAcquisition(partial, printedEdition: .absent, finishLock: .init(finish: .holo)),
            .resolved(.init(variant: .holo, resolution: .uniqueInCatalog)))
        XCTAssertEqual(VariantResolver.resolve(partial, finishLock: PhysicalVariant.normal),
            .resolved(.init(variant: .holo, resolution: .uniqueInCatalog)))
        let verified = VariantEvidence(game: .pokemon, setID: "fixture", cardNumber: "1", catalogVariants: [.normal], physicalCoverageVerified: true)
        XCTAssertEqual(VariantResolver.resolve(verified), .resolved(.init(variant: .normal, resolution: .uniqueInCatalog)))
        let silent = IdentifiedCard.pokemon(empty, setCode: "FIX").variantEvidence
        XCTAssertTrue(VariantResolver.options(for: silent).isEmpty)
    }

    func testReviewedMinimumAutoResolvesSupportedHoloWithoutCertifyingRetainedNormal() async throws {
        let snapshot = try await snapshot()
        let value = try card("dv1-21", in: snapshot)
        let evidence = IdentifiedCard.pokemon(value, setCode: "DRV").variantEvidence
        XCTAssertFalse(evidence.physicalCoverageVerified)
        XCTAssertEqual(VariantResolver.options(for: evidence), [.holo])
        XCTAssertEqual(VariantResolver.resolve(evidence), .resolved(.init(variant: .holo, resolution: .uniqueInCatalog)))
        XCTAssertEqual(VariantResolver.resolve(evidence, finishLock: PhysicalVariant.holo), .resolved(.init(variant: .holo, resolution: .uniqueInCatalog)))
        XCTAssertTrue(PokemonVariantRules.requiresPhysicalReview(cardID: "dv1-21", variant: .normal))
        XCTAssertFalse(PokemonVariantRules.requiresPhysicalReview(cardID: "xy12-80", variant: .normal))
    }

    func testOldDownloadRefreshAndReopenPreserveMinimumAndUnrelatedData() async throws {
        let bundled = try await snapshot()
        let affected = Set(try ledger().compactMap { $0["provider_id"] })
        let setIDs = Set(try ledger().compactMap { $0["set_id"] })
        let entries = bundled.manifest.entries.filter { setIDs.contains($0.providerID) }
        let old = Dictionary(uniqueKeysWithValues: try entries.map { entry in
            (entry.set.id, try XCTUnwrap(bundled.checklist(for: entry.set.catalogID)).filter {
                !affected.contains($0.providerID) || $0.masterSetVariant == .normal
            })
        })
        let other = try XCTUnwrap(bundled.entry(forProviderID: "sv10"))
        let unrelated = try XCTUnwrap(bundled.checklist(for: other.set.catalogID))
        var staleCards = old
        staleCards[other.set.id] = unrelated
        let stale = PokemonChecklistSnapshot(manifest: .init(schemaVersion: 1, rulesVersion: 1, generatedAt: .now,
            directoryFingerprint: "legacy", entries: entries + [other]), checklists: staleCards)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PokemonChecklistStore(root: root, bundle: .main)
        for _ in 0..<2 {
            try await store.publish(stale)
            let loaded = await store.mergedSnapshot()
            let snapshot = try XCTUnwrap(loaded)
            try assertLedgerMinimums(in: snapshot)
            XCTAssertEqual(Set(try card("xy12-11", in: snapshot).catalogVariants), [.normal, .holo, .reverse])
            XCTAssertEqual(snapshot.checklist(for: other.set.catalogID), unrelated)
        }
        let reopened = PokemonChecklistStore(root: root, bundle: .main)
        let loaded = await reopened.mergedSnapshot()
        let fresh = try XCTUnwrap(loaded)
        try assertLedgerMinimums(in: fresh)
        XCTAssertEqual(Set(try card("xy12-80", in: fresh).catalogVariants), [.normal, .reverse])
    }

    func testStaleResolvedCacheAndProviderPayloadCannotEraseMinimum() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        // Current format with stale finish evidence: no coverage field,
        // Normal-only affected entry and an unrelated entry. No per-card purge.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let date = ISO8601DateFormatter().string(from: .now)
        let rows = try ledger()
        let entries = (rows.compactMap { $0["provider_id"] } + ["fixture-1"]).map { id -> [String: Any] in
            let parts = id.split(separator: "-").map(String.init)
            return ["key": id, "storedAt": date, "cardID": id, "localID": parts[1], "name": "Cached",
                    "setID": parts[0], "setName": "Cached Set", "officialCount": 20, "setCode": "FIX",
                    "variants": [["id": "normal", "label": "Normal"]]]
        }
        try JSONSerialization.data(withJSONObject: ["appVersion": "fixture", "schemaGeneration": 3, "entries": entries])
            .write(to: root.appendingPathComponent("ResolvedPokemonCards.json"))
        let oldCache = ResolvedPokemonCardCache(root: root, appVersion: "fixture")
        for row in rows {
            let cached = await oldCache.card(for: row["provider_id"]!)
            let value = try XCTUnwrap(cached)
            let finishes = Set(value.card.catalogVariants.map(\.id))
            XCTAssertTrue(Set(row["required_minimum_finishes"]!.components(separatedBy: "; ")).isSubset(of: finishes), value.card.id)
            XCTAssertFalse(IdentifiedCard.pokemon(value.card, setCode: "FIX").variantEvidence.physicalCoverageVerified)
        }
        let oldHit = await oldCache.card(for: "dv1-21")
        XCTAssertEqual(Set(try XCTUnwrap(oldHit).card.catalogVariants), [.normal, .holo])
        let other = await oldCache.card(for: "fixture-1")
        let unrelated = try XCTUnwrap(other)
        XCTAssertEqual(unrelated.card.catalogVariants, [.normal])
        XCTAssertFalse(IdentifiedCard.pokemon(unrelated.card, setCode: "FIX").variantEvidence.physicalCoverageVerified)
        let raw = #"{"id":"dv1-21","localId":"21","name":"Kyurem","set":{"id":"dv1","name":"Dragon Vault","cardCount":{"total":21,"official":20}},"variants":{"normal":true,"holo":false,"reverse":false,"firstEdition":false}}"#
        let value = try JSONDecoder().decode(TCGdexCard.self, from: Data(raw.utf8))
        await oldCache.store(card: value, setCode: "DRV", key: "dv1-21")
        let reopened = ResolvedPokemonCardCache(root: root, appVersion: "fixture")
        let loaded = await reopened.card(for: "dv1-21")
        let hit = try XCTUnwrap(loaded)
        XCTAssertEqual(Set(hit.card.catalogVariants), [.normal, .holo])
        XCTAssertEqual(VariantResolver.resolve(IdentifiedCard.pokemon(hit.card, setCode: hit.setCode).variantEvidence),
            .resolved(.init(variant: .holo, resolution: .uniqueInCatalog)))
        let preserved = await reopened.card(for: "fixture-1")
        XCTAssertEqual(preserved?.card.catalogVariants, [.normal])
    }

    func testRegenerationUsesNativeWriterAndPreservesProviderFingerprints() async throws {
        let source = try XCTUnwrap(Bundle.main.url(forResource: "PokemonChecklistSnapshot", withExtension: nil))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("Pokemon-Finish-Minimum-Generated")
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        try FileManager.default.copyItem(at: source, to: output)
        try await PokemonChecklistSnapshotGenerator.rebuildFinishMinimums(root: output)
        let generated = await PokemonChecklistStore(root: output, bundle: nil).downloadedSnapshot()
        let result = try XCTUnwrap(generated)
        let original = try await snapshot()
        for id in ["xy12", "sm6", "dv1", "det1", "sm3.5", "sm7.5", "dc1", "ru1"] {
            let entry = try XCTUnwrap(result.entry(forProviderID: id))
            let old = try XCTUnwrap(original.entry(forProviderID: id))
            XCTAssertEqual(entry.providerFingerprint, old.providerFingerprint)
            XCTAssertEqual(entry.providerProbeFingerprint, old.providerProbeFingerprint)
            XCTAssertEqual(entry.resource, old.resource)
            let cards = try XCTUnwrap(result.checklist(for: entry.set.catalogID))
            XCTAssertEqual(entry.standardSlotCount, cards.filter { !$0.isExpandedMasterSetVariant }.count)
            XCTAssertEqual(entry.expandedSlotCount, cards.count)
        }
        try await PokemonChecklistSnapshotGenerator.rebuildFinishMinimums(root: output)
        let repeated = await PokemonChecklistStore(root: output, bundle: nil).downloadedSnapshot()
        XCTAssertEqual(repeated, result, "Regeneration must be idempotent")
        print("POKEMON_FINISH_GENERATED=\(output.path)")
    }

    @MainActor
    func testSyntheticHoldingsKeepExplicitAndInferredDecisionsAfterReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = ModelConfiguration(url: root.appendingPathComponent("holdings.store"))
        let container = try ModelContainer(for: CollectionStorageModelSchema.full, configurations: [config])
        let store = CollectionStore(context: container.mainContext)
        let snapshot = try await snapshot()
        let value = IdentifiedCard.pokemon(try card("dv1-21", in: snapshot), setCode: "DRV")
        let decisions: [VariantResolution] = [.userConfirmed, .imported, .finishLock, .uniqueInCatalog]
        var cards: [String: IdentifiedCard] = [:]
        for (index, resolution) in decisions.enumerated() {
            let card = IdentifiedCard.pokemon(try card("dv1-\(index + 1)", in: snapshot), setCode: "DRV")
            cards[card.providerID] = card
            XCTAssertNil(PokemonFinishReconciliation.repair(storedVariantID: "normal", storedResolution: resolution,
                itemKind: .rawCard, printRun: nil, card: value))
            _ = try store.add(card, resolved: .init(variant: .normal, resolution: resolution),
                source: resolution == .imported ? .csvImport : .scan, quantity: index + 1)
        }
        let beforeRows = try container.mainContext.fetch(FetchDescriptor<CollectedCard>())
        let before = Dictionary(uniqueKeysWithValues: beforeRows.map { ($0.collectionKey, ($0.quantity, $0.variantResolutionRaw)) })
        let activities = try container.mainContext.fetchCount(FetchDescriptor<CollectionActivity>())
        let events = try container.mainContext.fetchCount(FetchDescriptor<InventoryEvent>())
        try container.mainContext.save()
        let worker = PriceRefreshModelActor(modelContainer: container)
        let resolvedCards = cards
        await worker.setPokemonFetchOverrideForTesting { printing in
            guard let card = resolvedCards[printing.printingID] else { throw URLError(.resourceUnavailable) }
            return card
        }
        for _ in 0..<2 {
            let outcome = await worker.run(.init(usesPriceFallback: false, includeImported: true,
                forceUnsupportedRetry: true, sortOldestFirst: false, maximumTargetCount: nil,
                markRecentlyCheckedIfEmpty: false), progress: { _ in }, shouldContinue: nil)
            guard case let .completed(result) = outcome else { return XCTFail("Synthetic refresh must complete") }
            XCTAssertEqual(result.repairedFinishes, 0)
        }
        let reopened = try ModelContainer(for: CollectionStorageModelSchema.full, configurations: [config])
        let rows = try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 4)
        for row in rows {
            XCTAssertEqual(row.variantID, "normal")
            XCTAssertEqual(row.quantity, before[row.collectionKey]?.0)
            XCTAssertEqual(row.variantResolutionRaw, before[row.collectionKey]?.1)
        }
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<CollectionActivity>()), activities)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<InventoryEvent>()), events)
    }
}

private struct RetailVariantSource: PokemonCardSource {
    let cards: [String: TCGdexCard]
    func fetchTCGdexCard(setID: String, localID: String) async throws -> TCGdexCard {
        try XCTUnwrap(cards[setID + "-" + localID])
    }
    func fetchPokemonTCGCard(setID: String, cardNumber: String) async throws -> PokemonTCGAPICard? { nil }
}

final class RetailVariantTests: XCTestCase {
    private func usd(_ lookup: PriceLookup) -> Double? {
        guard case let .price(price) = lookup else { return nil }
        return price.unitMarketPriceUSD
    }
    private func registry(includeSupplements: Bool = true) throws -> PokemonCatalogRegistry {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "catalog-input", withExtension: "json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let rows = try XCTUnwrap(object["sets"] as? [[String: Any]])
        let descriptors = try rows.filter { ["30th", "svp"].contains($0["providerSetID"] as? String ?? "") }.map { row in
            var row = row
            row["officialCount"] = row["claimedOfficialCount"]
            if !includeSupplements { row.removeValue(forKey: "additionalVariants") }
            return try JSONDecoder().decode(PokemonCatalogSetDescriptor.self, from: JSONSerialization.data(withJSONObject: row))
        }
        let release = PokemonCatalogRelease(revision: includeSupplements ? 2 : 1, generatedAt: .now, sets: descriptors)
        try PokemonCatalogRegistry.validate(release)
        return .init(release: release)
    }

    private func eevee() throws -> TCGdexCard {
        try JSONDecoder().decode(TCGdexCard.self, from: Data(#"""
        {"id":"30th-116","localId":"116","name":"Eevee","image":"https://assets.tcgdex.net/en/me/30th/116",
         "set":{"id":"30th","name":"30th Celebration","cardCount":{"total":158,"official":128}},
         "variants":{"firstEdition":false,"normal":true,"holo":false,"reverse":false},
         "pricing":{"tcgplayer":{"unit":"USD","holofoil":{"marketPrice":1.25,"productId":714357}}}}
        """#.utf8))
    }

    private func charizard(jumbo: String = #"{"type":"lenticular","size":"jumbo","languages":["en"],"thirdParty":{"tcgplayer":641615},"pricing":{"tcgplayer":{"unit":"USD","normal":{"marketPrice":7,"productId":641615}}}}"#) throws -> TCGdexCard {
        let json = #"{"id":"svp-196","localId":"196","name":"Charizard ex","set":{"id":"svp","name":"SV Promos","cardCount":{"total":226,"official":226}},"variants":{"firstEdition":false,"normal":false,"holo":true,"reverse":false},"variants_detailed":[{"type":"holo","size":"standard","thirdParty":{"tcgplayer":641610},"pricing":{"tcgplayer":{"unit":"USD","holofoil":{"marketPrice":2,"productId":641610}}}},"# + jumbo + "]}"
        return try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8))
    }

    func testSignedEeveeAddsCosmosWithoutBorrowingHoloPriceOrChangingControls() throws {
        let registry = try registry()
        let raw = try eevee()
        XCTAssertEqual(raw.catalogVariants, [.holo])
        let card = raw.applyingAdditionalVariants(from: registry)
        let cosmos = PhysicalVariant.pokemonFoilPattern("cosmos")
        XCTAssertEqual(Set(card.catalogVariants), [.holo, cosmos])
        let identified = IdentifiedCard.pokemon(card, setCode: "30C")
        XCTAssertEqual(Set(VariantResolver.options(for: identified.variantEvidence)), [.holo, cosmos])
        XCTAssertNil(usd(CardPricing.price(for: identified, variant: cosmos, magicTreatments: [])))
        XCTAssertEqual(CardPricing.tcgplayerProductID(for: identified, variant: cosmos, printRun: nil), 717879)
        XCTAssertTrue(TCGplayerLinkBuilder.destination(for: identified, variant: cosmos)?.isExactProduct == true)
        XCTAssertEqual(TCGplayerLinkBuilder.destination(for: identified, variant: cosmos)?.url.path, "/product/717879")
        XCTAssertEqual(usd(CardPricing.price(for: identified, variant: .holo, magicTreatments: [])), 1.25)
        let slots = PokemonMasterSetDefinition.requiredVariants(for: card)
        XCTAssertTrue(try XCTUnwrap(slots.first { $0.variant == cosmos }).isExpanded)
        XCTAssertFalse(try XCTUnwrap(slots.first { $0.variant == .holo }).isExpanded)
        XCTAssertNotEqual(identified.collectionKey(variant: cosmos), identified.collectionKey(variant: .holo))
        XCTAssertEqual(card.applyingAdditionalVariants(from: try self.registry(includeSupplements: false)).catalogVariants, [.holo])
    }

    func testJumboHasStableLabelDistinctKeysAndExactSizeScopedPrice() throws {
        let card = try charizard().applyingAdditionalVariants(from: registry())
        XCTAssertEqual(card.catalogVariants, [.holo, .jumbo])
        XCTAssertEqual(PhysicalVariant.resolving("jumbo").label, "Jumbo")
        XCTAssertEqual(try JSONDecoder().decode(PhysicalVariant.self, from: JSONEncoder().encode(PhysicalVariant.jumbo)), .jumbo)
        let identified = IdentifiedCard.pokemon(card, setCode: "SVP")
        XCTAssertNotEqual(identified.collectionKey(variant: .jumbo), identified.collectionKey(variant: .holo))
        XCTAssertEqual(CardPricing.tcgplayerProductID(for: identified, variant: .jumbo, printRun: nil), 641615)
        XCTAssertEqual(CardPricing.tcgplayerProductID(for: identified, variant: .holo, printRun: nil), 641610)
        XCTAssertEqual(usd(CardPricing.price(for: identified, variant: .jumbo, magicTreatments: [])), 7)
        XCTAssertEqual(usd(CardPricing.price(for: identified, variant: .holo, magicTreatments: [])), 2)
        XCTAssertEqual(PriceFallbackQuoteResolver.directLookups(card: identified, variant: .jumbo), [.tcgplayerID("641615")])
        XCTAssertEqual(TCGplayerLinkBuilder.destination(for: identified, variant: .jumbo)?.url.path, "/product/641615")
        XCTAssertNil(TCGplayerLinkBuilder.destination(for: identified, variant: nil))
        XCTAssertNil(CardPricing.tcgplayerProductID(for: identified, variant: .jumbo, printRun: .firstEdition))
        XCTAssertFalse(PokemonMasterSetDefinition.requiredVariants(for: card).contains { $0.variant == .jumbo })
    }

    func testJumboRejectsForeignConflictingAmbiguousAndStandardProductEvidence() throws {
        for jumbo in [
            #"{"type":"lenticular","size":"jumbo","languages":["ja"],"thirdParty":{"tcgplayer":641615}}"#,
            #"{"type":"lenticular","size":"jumbo","thirdParty":{"tcgplayer":999999}}"#,
            #"{"type":"lenticular","size":"jumbo","thirdParty":{"tcgplayer":641610}}"#,
            #"{"type":"lenticular","size":"jumbo","thirdParty":{"tcgplayer":641615}},{"type":"holo","size":"jumbo","thirdParty":{"tcgplayer":555}}"#
        ] {
            let card = try charizard(jumbo: jumbo).applyingAdditionalVariants(from: registry())
            let identified = IdentifiedCard.pokemon(card, setCode: "SVP")
            XCTAssertNil(CardPricing.tcgplayerProductID(for: identified, variant: .jumbo, printRun: nil), jumbo)
            XCTAssertNil(usd(CardPricing.price(for: identified, variant: .jumbo, magicTreatments: [])), jumbo)
        }
        XCTAssertEqual(try charizard().catalogVariants, [.holo], "Provider data alone cannot authorize the new object")
    }

    func testAdapterAppliesSignedMembershipToLiveAndCachedReadsAndCanWithdrawIt() async throws {
        let registry = try registry()
        let card = try eevee()
        let source = RetailVariantSource(cards: [card.id: card])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let adapter = PokemonCatalogAdapter(source: source, resolvedDiskCache: .init(root: root), registry: registry)
        let identifier = try XCTUnwrap(PokemonScanProfile(registry: registry).parse("30C EN 116/128"))
        for _ in 0..<2 {
            guard case let .resolved(result) = try await adapter.lookup(identifier) else { return XCTFail("Expected exact printing") }
            XCTAssertTrue(result.card.variantEvidence.catalogVariants.contains(.pokemonFoilPattern("cosmos")))
        }
        let removed = await adapter.updating(try self.registry(includeSupplements: false))
        guard case let .resolved(result) = try await removed.lookup(identifier) else { return XCTFail("Expected exact printing") }
        XCTAssertEqual(result.card.variantEvidence.catalogVariants, [.holo])
    }

    func testEeveeChecklistProjectionIsAdditiveIdempotentAndLimitedToGrandMaster() throws {
        var base = CatalogCardSummary(game: .pokemon, providerID: "30th-116",
            setID: .init(game: .pokemon, providerID: "30th"), setName: "30th Celebration", setCode: "30C",
            name: "Eevee", collectorNumber: "116", thumbnailURL: nil, imageURL: nil)
        base.masterSetVariant = .holo
        base.isSoleSlotForCard = true
        let registry = try registry()
        let projected = PokemonChecklistReviewedProjection.addingAdditionalVariants(to: [base], registry: registry)
        XCTAssertEqual(projected.count, 2)
        XCTAssertEqual(Set(projected.map(\.id)).count, 2)
        XCTAssertEqual(projected.filter(\.isExpandedMasterSetVariant).map { $0.masterSetVariant?.id }, ["cosmos"])
        XCTAssertTrue(projected.allSatisfy { !$0.isSoleSlotForCard })
        XCTAssertEqual(PokemonChecklistReviewedProjection.addingAdditionalVariants(to: projected, registry: registry), projected)
        XCTAssertEqual(PokemonChecklistReviewedProjection.addingAdditionalVariants(to: [base],
            registry: try self.registry(includeSupplements: false)), [base])
    }

    func testCollectionRefreshReappliesCurrentSignedSupplementAndWithdrawal() async throws {
        let coordinator = PokemonCatalogCoordinator()
        let registry = try registry()
        await coordinator.overrideRegistry(registry, revision: registry.revision)
        let service = PriceQuoteService(registry: .standard,
            adapters: try GamePriceAdapterRegistry(adapters: [PokemonPriceAdapter()]),
            pokemonCatalogCoordinator: coordinator)
        let raw = IdentifiedCard.pokemon(try charizard(), setCode: "SVP")
        let refreshed = await service.applyingCatalogSupplements(to: raw)
        XCTAssertEqual(CardPricing.tcgplayerProductID(for: refreshed, variant: .jumbo, printRun: nil), 641615)
        let removed = try self.registry(includeSupplements: false)
        await coordinator.overrideRegistry(removed, revision: 3)
        let withdrawn = await service.applyingCatalogSupplements(to: refreshed)
        XCTAssertFalse(withdrawn.variantEvidence.catalogVariants.contains(.jumbo))
        XCTAssertNil(CardPricing.tcgplayerProductID(for: withdrawn, variant: .jumbo, printRun: nil))
    }

    func testReviewedJumboBatchUsesNineteenSizeScopedProductsAndHoldsNumberlessCard() throws {
        let registry = try registryWithOBF()
        // Independently reviewed TCGplayer Jumbo product metadata, not IDs read
        // back from the authoring input being tested.
        let expected: [(String, String, Int)] = [
            ("sv03-125", "Charizard ex", 581987), ("svp-004", "Mimikyu ex", 487439),
            ("svp-018", "Cyclizar ex", 497721), ("svp-049", "Zapdos ex", 520722),
            ("svp-067", "Roaring Moon ex", 529857), ("svp-068", "Iron Valiant ex", 531864),
            ("svp-072", "Great Tusk ex", 666593), ("svp-078", "Meowscarada ex", 537979),
            ("svp-081", "Skeledirge ex", 537976), ("svp-084", "Quaquaval ex", 537977),
            ("svp-086", "Mabosstiff ex", 543638), ("svp-100", "Grafaiai ex", 548540),
            ("svp-126", "Palafin ex", 560085), ("svp-162", "Houndstone ex", 596423),
            ("svp-177", "Bloodmoon Ursaluna ex", 595474), ("svp-193", "Hop's Zacian ex", 625633),
            ("svp-196", "Charizard ex", 641615), ("svp-205", "Team Rocket's Mewtwo ex", 639951),
            ("svp-208", "Victini", 646170)
        ]
        XCTAssertEqual(registry.descriptors.flatMap { $0.additionalVariants ?? [] }.filter { $0.variantID == "jumbo" }.count, 19)
        for (id, name, product) in expected {
            let split = try XCTUnwrap(id.lastIndex(of: "-"))
            let set = String(id[..<split]), number = String(id[id.index(after: split)...])
            var detail: [String: Any] = ["type": id == "svp-196" ? "lenticular" : "holo", "size": "jumbo",
                "languages": ["en"], "thirdParty": ["tcgplayer": id == "svp-162" ? 791832 : product],
                "pricing": ["tcgplayer": ["unit": "USD", "normal": ["marketPrice": 999, "productId": id == "svp-162" ? 791832 : product]]]]
            if id == "svp-072" { detail["stamp"] = ["set-logo"] }
            let object: [String: Any] = ["id": id, "localId": number, "name": name,
                "set": ["id": set, "name": "Retail fixture", "cardCount": ["total": 226, "official": 197]],
                "variants": ["normal": false, "holo": true, "reverse": false, "firstEdition": false],
                "variants_detailed": [detail]]
            let raw = try JSONDecoder().decode(TCGdexCard.self, from: JSONSerialization.data(withJSONObject: object))
            let card = raw.applyingAdditionalVariants(from: registry)
            let identified = IdentifiedCard.pokemon(card, setCode: "SVP")
            XCTAssertTrue(card.catalogVariants.contains(.jumbo), id)
            XCTAssertEqual(CardPricing.tcgplayerProductID(for: identified, variant: .jumbo, printRun: nil), product, id)
            XCTAssertEqual(TCGplayerLinkBuilder.destination(for: identified, variant: .jumbo)?.url.path, "/product/\(product)", id)
            if id == "svp-162" {
                XCTAssertNil(usd(CardPricing.price(for: identified, variant: .jumbo, magicTreatments: [])), "Never relabel the replaced product's quote")
            }
            if id == "svp-072" {
                var wrong = detail; wrong["stamp"] = ["horizons"]
                var wrongCard = object; wrongCard["variants_detailed"] = [wrong]
                let decoded = try JSONDecoder().decode(TCGdexCard.self, from: JSONSerialization.data(withJSONObject: wrongCard))
                    .applyingAdditionalVariants(from: registry)
                XCTAssertNil(CardPricing.tcgplayerProductID(for: .pokemon(decoded, setCode: "SVP"), variant: .jumbo, printRun: nil))
            }
            XCTAssertFalse(PokemonMasterSetDefinition.requiredVariants(for: card).contains { $0.variant == .jumbo }, id)
        }
        XCTAssertFalse(registry.descriptors.flatMap { $0.additionalVariants ?? [] }.contains { $0.providerCardID == "svp-500" })
    }

    func testCosmosSignedProductNeverUsesOrdinaryHoloQuoteOrUnknownConflictingHandle() throws {
        let original = try eevee()
        let registry = try registry()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(#"""
        {"id":"30th-116","localId":"116","name":"Eevee",
         "set":{"id":"30th","name":"30th Celebration","cardCount":{"total":158,"official":128}},
         "variants":{"normal":true,"holo":false,"reverse":false,"firstEdition":false}}
        """#.utf8)) as? [String: Any])
        for product in [717879, 714357, 999999] {
            object["variants_detailed"] = [["type": "holo", "foil": "cosmos", "size": "standard", "languages": ["en"],
                "thirdParty": ["tcgplayer": product],
                "pricing": ["tcgplayer": ["unit": "USD", "holofoil": ["marketPrice": 3.75, "productId": product]]]]]
            let card = try JSONDecoder().decode(TCGdexCard.self, from: JSONSerialization.data(withJSONObject: object))
                .applyingAdditionalVariants(from: registry)
            let identified = IdentifiedCard.pokemon(card, setCode: "30C")
            let cosmos = PhysicalVariant.pokemonFoilPattern("cosmos")
            XCTAssertEqual(CardPricing.tcgplayerProductID(for: identified, variant: cosmos, printRun: nil), product == 717879 ? 717879 : nil)
            XCTAssertEqual(usd(CardPricing.price(for: identified, variant: cosmos, magicTreatments: [])), product == 717879 ? 3.75 : nil)
        }
        XCTAssertNil(usd(CardPricing.price(for: .pokemon(original.applyingAdditionalVariants(from: registry), setCode: "30C"),
            variant: .pokemonFoilPattern("cosmos"), magicTreatments: [])))
    }

    private func ordinaryCorrectionRegistry(includeCorrections: Bool = true) throws -> PokemonCatalogRegistry {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "catalog-input", withExtension: "json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let rows = try XCTUnwrap(object["sets"] as? [[String: Any]])
        let descriptors = try rows.filter { ["xyp", "sve"].contains($0["providerSetID"] as? String ?? "") }.map { row in
            var row = row
            if !includeCorrections { row.removeValue(forKey: "additionalVariants") }
            return try JSONDecoder().decode(PokemonCatalogSetDescriptor.self, from: JSONSerialization.data(withJSONObject: row))
        }
        let release = PokemonCatalogRelease(revision: includeCorrections ? 2 : 1, generatedAt: .now, sets: descriptors)
        try PokemonCatalogRegistry.validate(release)
        return .init(release: release)
    }

    private func ordinaryPromo(number: String = "XY111", name: String = "Celebi", product: Int = 114526,
                               detailedProduct: Int? = nil) throws -> TCGdexCard {
        var object: [String: Any] = ["id": "xyp-" + number, "localId": number, "name": name,
            "set": ["id": "xyp", "name": "XY Promos", "cardCount": ["total": 216, "official": 216]],
            "variants": ["normal": true, "holo": false, "reverse": false, "firstEdition": false],
            "pricing": ["tcgplayer": ["unit": "USD", "normal": ["marketPrice": 777, "productId": product]]]]
        if let detailedProduct {
            object["variants_detailed"] = [["type": "holo", "size": "standard", "thirdParty": ["tcgplayer": detailedProduct],
                "pricing": ["tcgplayer": ["unit": "USD", "holofoil": ["marketPrice": 3.75, "productId": detailedProduct]]]]]
        }
        return try JSONDecoder().decode(TCGdexCard.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testSevenOrdinaryHoloMinimumsAutoResolveRetainNormalAndUseExactProducts() throws {
        let registry = try ordinaryCorrectionRegistry()
        // Expectations from the separate official/marketplace review receipts.
        for (number, name, product) in [("XY111", "Celebi", 114526), ("XY112", "Jirachi", 117266),
            ("XY114", "Darkrai", 121946), ("XY116", "Arceus", 121364), ("XY118", "Keldeo", 126034),
            ("XY119", "Genesect", 125322), ("XY120", "Meloetta", 125898)] {
            let raw = try ordinaryPromo(number: number, name: name, product: product)
            let card = raw.applyingAdditionalVariants(from: registry)
            XCTAssertEqual(card.catalogVariants, [.normal, .holo], number)
            let identified = IdentifiedCard.pokemon(card, setCode: "XY")
            XCTAssertEqual(VariantResolver.options(for: identified.variantEvidence), [.holo])
            XCTAssertFalse(identified.variantEvidence.physicalCoverageVerified)
            XCTAssertEqual(VariantResolver.resolve(identified.variantEvidence), .resolved(.init(variant: .holo, resolution: .uniqueInCatalog)))
            XCTAssertNil(PokemonFinishReconciliation.repair(storedVariantID: "normal", storedResolution: .uniqueInCatalog,
                itemKind: .rawCard, printRun: nil, card: identified))
            XCTAssertNil(usd(CardPricing.price(for: identified, variant: .normal, magicTreatments: [])))
            XCTAssertNil(usd(CardPricing.price(for: identified, variant: .holo, magicTreatments: [])), "Never borrow the flat Normal quote")
            XCTAssertNil(CardPricing.tcgplayerProductID(for: identified, variant: .normal, printRun: nil))
            XCTAssertEqual(CardPricing.tcgplayerProductID(for: identified, variant: .holo, printRun: nil), product)
            XCTAssertEqual(TCGplayerLinkBuilder.destination(for: identified, variant: .holo)?.url.path, "/product/\(product)")
            XCTAssertEqual(card.applyingAdditionalVariants(from: try ordinaryCorrectionRegistry(includeCorrections: false)).catalogVariants, [.normal])
        }
        let matching = try ordinaryPromo(detailedProduct: 114526).applyingAdditionalVariants(from: registry)
        XCTAssertEqual(usd(CardPricing.price(for: .pokemon(matching, setCode: "XY"), variant: .holo, magicTreatments: [])), 3.75)
        let conflicting = try ordinaryPromo(detailedProduct: 999999).applyingAdditionalVariants(from: registry)
        XCTAssertNil(CardPricing.tcgplayerProductID(for: .pokemon(conflicting, setCode: "XY"), variant: .holo, printRun: nil))
        XCTAssertNil(usd(CardPricing.price(for: .pokemon(conflicting, setCode: "XY"), variant: .holo, magicTreatments: [])))
    }

    func testOrdinaryHoloProjectionIsStandardAndExclusionDoesNotInventAMembership() throws {
        var base = CatalogCardSummary(game: .pokemon, providerID: "xyp-XY111", setID: .init(game: .pokemon, providerID: "xyp"),
            setName: "XY Promos", setCode: "XY", name: "Celebi", collectorNumber: "XY111", thumbnailURL: nil, imageURL: nil)
        base.masterSetVariant = .normal; base.isSoleSlotForCard = true
        let registry = try ordinaryCorrectionRegistry()
        let projected = PokemonChecklistReviewedProjection.addingAdditionalVariants(to: [base], registry: registry)
        XCTAssertEqual(Set(projected.compactMap(\.masterSetVariant)), [.normal, .holo])
        XCTAssertTrue(projected.allSatisfy { !$0.isExpandedMasterSetVariant && !$0.isSoleSlotForCard })
        XCTAssertEqual(PokemonChecklistReviewedProjection.addingAdditionalVariants(to: projected, registry: registry), projected)
        let energy = CatalogCardSummary(game: .pokemon, providerID: "sve-002", setID: .init(game: .pokemon, providerID: "sve"),
            setName: "SV Energy", setCode: "SVE", name: "Fire Energy", collectorNumber: "002", thumbnailURL: nil, imageURL: nil)
        XCTAssertEqual(PokemonChecklistReviewedProjection.addingAdditionalVariants(to: [energy], registry: registry), [energy])
    }

    func testEnergyExclusionBlocksWrongHandleAndQuoteWithoutAffectingThe010Printing() throws {
        let registry = try ordinaryCorrectionRegistry()
        let stamp = try XCTUnwrap(PokemonCatalogStampVariant.make(base: .pokemonFoilPattern("cosmos"), stamps: ["player-rewards-program"]))
        func energy(_ number: String, product: Int = 651037) throws -> TCGdexCard {
            let object: [String: Any] = ["id": "sve-" + number, "localId": number, "name": "Fire Energy",
                "set": ["id": "sve", "name": "SV Energy", "cardCount": ["total": 24, "official": 24]],
                "variants": ["normal": true, "holo": false, "reverse": true, "firstEdition": false],
                "variants_detailed": [
                    ["type": "reverse", "foil": "cosmos", "size": "standard", "stamp": ["player-rewards-program"],
                     "thirdParty": ["tcgplayer": product], "pricing": ["tcgplayer": ["unit": "USD", "holofoil": ["marketPrice": 5, "productId": product]]]],
                    ["type": "reverse", "foil": "cosmos", "size": "standard", "thirdParty": ["tcgplayer": 517178],
                     "pricing": ["tcgplayer": ["unit": "USD", "holofoil": ["marketPrice": 2, "productId": 517178]]]]]]
            return try JSONDecoder().decode(TCGdexCard.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let raw = try energy("002")
        let corrected = raw.applyingAdditionalVariants(from: registry)
        XCTAssertEqual(corrected.catalogVariants, raw.catalogVariants, "An exclusion cannot authorize a physical object")
        let identified = IdentifiedCard.pokemon(corrected, setCode: "SVE")
        XCTAssertNil(CardPricing.tcgplayerProductID(for: identified, variant: stamp, printRun: nil))
        XCTAssertNil(usd(CardPricing.price(for: identified, variant: stamp, magicTreatments: [])))
        XCTAssertNil(TCGplayerLinkBuilder.destination(for: identified, variant: stamp))
        XCTAssertEqual(usd(CardPricing.price(for: identified, variant: .pokemonFoilPattern("cosmos"), magicTreatments: [])), 2)
        let sibling = IdentifiedCard.pokemon(try energy("010").applyingAdditionalVariants(from: registry), setCode: "SVE")
        XCTAssertEqual(CardPricing.tcgplayerProductID(for: sibling, variant: stamp, printRun: nil), 651037)
        XCTAssertEqual(usd(CardPricing.price(for: sibling, variant: stamp, magicTreatments: [])), 5)
        let changed = IdentifiedCard.pokemon(try energy("002", product: 123456).applyingAdditionalVariants(from: registry), setCode: "SVE")
        XCTAssertEqual(CardPricing.tcgplayerProductID(for: changed, variant: stamp, printRun: nil), 123456, "Only the reviewed bad handle is excluded")
        let withdrawn = IdentifiedCard.pokemon(corrected.applyingAdditionalVariants(from: try ordinaryCorrectionRegistry(includeCorrections: false)), setCode: "SVE")
        XCTAssertEqual(CardPricing.tcgplayerProductID(for: withdrawn, variant: stamp, printRun: nil), 651037)
    }

    func testOrdinaryCorrectionReappliesOnAdapterCacheReadsAndWithdraws() async throws {
        let source = RetailVariantSource(cards: ["xyp-XY111": try ordinaryPromo()])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let adapter = PokemonCatalogAdapter(source: source,
            offline: PokemonOfflineCatalog(store: .init(root: root.appendingPathComponent("offline"), bundle: nil)),
            resolvedDiskCache: .init(root: root), registry: try ordinaryCorrectionRegistry())
        let identifier = try XCTUnwrap(PokemonScanProfile(registry: try ordinaryCorrectionRegistry()).parse("XY111"))
        for _ in 0..<2 {
            guard case let .resolved(result) = try await adapter.lookup(identifier) else { return XCTFail("Expected promo printing") }
            XCTAssertEqual(VariantResolver.options(for: result.card.variantEvidence), [.holo])
            XCTAssertFalse(result.card.variantEvidence.physicalCoverageVerified)
        }
        let withdrawn = try ordinaryCorrectionRegistry(includeCorrections: false)
        let removed = await adapter.updating(withdrawn)
        guard case let .resolved(result) = try await removed.lookup(identifier) else { return XCTFail("Expected promo printing") }
        XCTAssertEqual(VariantResolver.options(for: result.card.variantEvidence), [.normal])
        let cold = PokemonCatalogAdapter(source: source,
            offline: PokemonOfflineCatalog(store: .init(root: root.appendingPathComponent("offline"), bundle: nil)),
            resolvedDiskCache: .init(root: root), registry: withdrawn)
        guard case let .resolved(reopened) = try await cold.lookup(identifier) else { return XCTFail("Expected cached printing") }
        XCTAssertEqual(reopened.path, .cacheHit)
        XCTAssertEqual(VariantResolver.options(for: reopened.card.variantEvidence), [.normal],
            "A withdrawn signed correction must not become durable provider evidence")
    }

    @MainActor
    func testSignedMinimumDoesNotRekeyStoredNormalHoldingsDuringRefreshOrReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = ModelConfiguration(url: root.appendingPathComponent("holdings.store"))
        let container = try ModelContainer(for: CollectionStorageModelSchema.full, configurations: [configuration])
        let store = CollectionStore(context: container.mainContext)
        let registry = try ordinaryCorrectionRegistry()
        var corrected: [String: IdentifiedCard] = [:]
        for (index, item) in [("XY111", "Celebi", 114526, VariantResolution.userConfirmed),
            ("XY112", "Jirachi", 117266, .imported), ("XY114", "Darkrai", 121946, .finishLock),
            ("XY116", "Arceus", 121364, .uniqueInCatalog)].enumerated() {
            let raw = try ordinaryPromo(number: item.0, name: item.1, product: item.2)
            let identified = IdentifiedCard.pokemon(raw, setCode: "XY")
            _ = try store.add(identified, resolved: .init(variant: .normal, resolution: item.3),
                source: item.3 == .imported ? .csvImport : .scan, quantity: index + 1)
            corrected[raw.id] = .pokemon(raw.applyingAdditionalVariants(from: registry), setCode: "XY")
        }
        let before = try container.mainContext.fetch(FetchDescriptor<CollectedCard>())
        let saved = Dictionary(uniqueKeysWithValues: before.map { ($0.collectionKey, ($0.quantity, $0.variantResolutionRaw)) })
        let activityCount = try container.mainContext.fetchCount(FetchDescriptor<CollectionActivity>())
        let eventCount = try container.mainContext.fetchCount(FetchDescriptor<InventoryEvent>())
        try container.mainContext.save()
        let worker = PriceRefreshModelActor(modelContainer: container)
        let refreshedCards = corrected
        await worker.setPokemonFetchOverrideForTesting { printing in
            guard let card = refreshedCards[printing.printingID] else { throw URLError(.resourceUnavailable) }
            return card
        }
        let outcome = await worker.run(.init(usesPriceFallback: false, includeImported: true,
            forceUnsupportedRetry: true, sortOldestFirst: false, maximumTargetCount: nil,
            markRecentlyCheckedIfEmpty: false), progress: { _ in }, shouldContinue: nil)
        guard case let .completed(result) = outcome else { return XCTFail("Synthetic refresh must complete") }
        XCTAssertEqual(result.repairedFinishes, 0)
        let reopened = try ModelContainer(for: CollectionStorageModelSchema.full, configurations: [configuration])
        let rows = try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 4)
        for row in rows {
            XCTAssertEqual(row.variantID, "normal")
            XCTAssertEqual(row.quantity, saved[row.collectionKey]?.0)
            XCTAssertEqual(row.variantResolutionRaw, saved[row.collectionKey]?.1)
        }
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<CollectionActivity>()), activityCount)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<InventoryEvent>()), eventCount)
    }

    private func registryWithOBF() throws -> PokemonCatalogRegistry {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "catalog-input", withExtension: "json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let rows = try XCTUnwrap(object["sets"] as? [[String: Any]])
        let descriptors = try rows.filter { ["30th", "svp", "sv03"].contains($0["providerSetID"] as? String ?? "") }.map { row in
            var row = row; row["officialCount"] = row["claimedOfficialCount"]
            return try JSONDecoder().decode(PokemonCatalogSetDescriptor.self, from: JSONSerialization.data(withJSONObject: row))
        }
        let release = PokemonCatalogRelease(revision: 3, generatedAt: .now, sets: descriptors)
        try PokemonCatalogRegistry.validate(release)
        return .init(release: release)
    }
}

final class VariantResolverTests: XCTestCase {
    private func pokemon(
        setID: String,
        variants: [PhysicalVariant],
        number: String = "074"
    ) -> VariantEvidence {
        VariantEvidence(game: .pokemon, setID: setID, cardNumber: number, catalogVariants: variants)
    }

    private func identifiedPokemon(_ variants: [PhysicalVariant]) -> IdentifiedCard {
        let card = TCGdexCard(
            id: "sv03-053",
            localId: "053",
            name: "Pikachu ex",
            image: nil,
            rarity: nil,
            set: TCGdexSetBrief(
                id: "sv03",
                name: "Obsidian Flames",
                cardCount: TCGdexCardCount(total: 152, official: 152)
            ),
            variants: TCGdexVariants(
                firstEdition: variants.contains(.firstEdition),
                holo: variants.contains(.holo),
                normal: variants.contains(.normal),
                reverse: variants.contains(.reverse),
                wPromo: nil
            ),
            pricing: nil,
            variantsDetailed: nil
        )
        return .pokemon(card, setCode: "OBF")
    }

    func testResolutionCertaintyDoesNotReuseAutomaticRevisitSemantics() {
        XCTAssertTrue(VariantResolution.uniqueInCatalog.isAutomatic)
        XCTAssertEqual(VariantResolution.uniqueInCatalog.certainty, .catalogCertain)
        XCTAssertTrue(VariantResolution.catalogSilent.isAutomatic)
        XCTAssertEqual(VariantResolution.catalogSilent.certainty, .unresolved)
        XCTAssertFalse(VariantResolution.userConfirmed.isAutomatic)
        XCTAssertEqual(VariantResolution.userConfirmed.certainty, .userConfirmed)
    }

    func testPokemonFinishReconciliationRepairsOnlyUnambiguousAutomaticOrUnknownRows() {
        let holoOnly = identifiedPokemon([.holo])
        XCTAssertEqual(
            PokemonFinishReconciliation.repair(
                storedVariantID: PhysicalVariant.normal.id,
                storedResolution: .uniqueInCatalog,
                itemKind: .rawCard,
                printRun: nil,
                card: holoOnly
            ),
            ResolvedVariant(variant: .holo, resolution: .uniqueInCatalog)
        )

        let normalOnly = identifiedPokemon([.normal])
        XCTAssertEqual(
            PokemonFinishReconciliation.repair(
                storedVariantID: nil,
                storedResolution: nil,
                itemKind: .rawCard,
                printRun: nil,
                card: normalOnly
            ),
            ResolvedVariant(variant: .normal, resolution: .uniqueInCatalog)
        )
        XCTAssertEqual(
            PokemonFinishReconciliation.repair(
                storedVariantID: nil,
                storedResolution: .catalogSilent,
                itemKind: .rawCard,
                printRun: nil,
                card: normalOnly
            ),
            ResolvedVariant(variant: .normal, resolution: .uniqueInCatalog)
        )

        XCTAssertNil(
            PokemonFinishReconciliation.repair(
                storedVariantID: PhysicalVariant.normal.id,
                storedResolution: nil,
                itemKind: .rawCard,
                printRun: nil,
                card: holoOnly
            ),
            "A legacy finish without provenance may have been selected by the user"
        )
        for resolution in [
            VariantResolution.userConfirmed,
            .finishLock,
            .printedLabel,
            .imported
        ] {
            XCTAssertNil(
                PokemonFinishReconciliation.repair(
                    storedVariantID: PhysicalVariant.normal.id,
                    storedResolution: resolution,
                    itemKind: .rawCard,
                    printRun: nil,
                    card: holoOnly
                )
            )
        }

        XCTAssertNil(
            PokemonFinishReconciliation.repair(
                storedVariantID: PhysicalVariant.normal.id,
                storedResolution: .uniqueInCatalog,
                itemKind: .rawCard,
                printRun: nil,
                card: identifiedPokemon([.normal, .reverse])
            ),
            "Multiple possible finishes must remain unresolved"
        )
        XCTAssertNil(
            PokemonFinishReconciliation.repair(
                storedVariantID: PhysicalVariant.normal.id,
                storedResolution: .uniqueInCatalog,
                itemKind: .rawCard,
                printRun: nil,
                card: identifiedPokemon([.normal])
            ),
            "A finish that remains valid is not a repair"
        )
        XCTAssertNil(
            PokemonFinishReconciliation.repair(
                storedVariantID: PhysicalVariant.normal.id,
                storedResolution: .uniqueInCatalog,
                itemKind: .gradedCard,
                printRun: nil,
                card: holoOnly
            )
        )
    }

    func testPokemonFinishReconciliationSkipsSpecialRunsAndNonPokemonCards() throws {
        let cardWithFirstEditionPseudoFinish = identifiedPokemon([.firstEdition, .holo])
        for printRun in [PokemonPrintRun.firstEdition, .shadowless] {
            XCTAssertNil(
                PokemonFinishReconciliation.repair(
                    storedVariantID: PhysicalVariant.normal.id,
                    storedResolution: .uniqueInCatalog,
                    itemKind: .rawCard,
                    printRun: printRun,
                    card: cardWithFirstEditionPseudoFinish
                )
            )
        }
        XCTAssertEqual(
            PokemonFinishReconciliation.repair(
                storedVariantID: PhysicalVariant.normal.id,
                storedResolution: .uniqueInCatalog,
                itemKind: .rawCard,
                printRun: .unlimited,
                card: cardWithFirstEditionPseudoFinish
            ),
            ResolvedVariant(variant: .holo, resolution: .uniqueInCatalog)
        )

        let json = #"{"id":"11111111-1111-4111-8111-111111111111","name":"Fixture","set":"abc","set_name":"Fixture Set","collector_number":"1","lang":"en","digital":false,"finishes":["nonfoil","foil"]}"#
        let magic = IdentifiedCard.magic(
            try JSONDecoder().decode(ScryfallCard.self, from: Data(json.utf8))
        )
        XCTAssertNil(
            PokemonFinishReconciliation.repair(
                storedVariantID: "nonfoil",
                storedResolution: .uniqueInCatalog,
                itemKind: .rawCard,
                printRun: nil,
                card: magic
            )
        )
    }

    func testReceiptProminenceKeepsRoutineCatalogAnswersQuiet() {
        XCTAssertEqual(VariantResolution.uniqueInCatalog.receiptProminence, .quiet)
        XCTAssertEqual(VariantResolution.deterministicSetRule.receiptProminence, .quiet)
        XCTAssertEqual(VariantResolution.finishLock.receiptProminence, .attention)
        XCTAssertEqual(VariantResolution.userConfirmed.receiptProminence, .attention)
        XCTAssertEqual(VariantResolution.catalogSilent.receiptProminence, .attention)
    }

    func testProvenancePresentationStatesFinishAndEvidence() {
        XCTAssertEqual(
            VariantProvenancePresentation.text(
                finish: "Reverse Holo",
                resolution: .uniqueInCatalog
            ),
            "Reverse Holo · Only variant printed"
        )
        XCTAssertEqual(
            VariantProvenancePresentation.text(
                finish: nil,
                resolution: .catalogSilent
            ),
            "Finish unconfirmed"
        )
        XCTAssertEqual(
            VariantProvenancePresentation.text(
                finish: "Holofoil",
                resolution: .userConfirmed
            ),
            "Holofoil · You confirmed"
        )
    }

    func testReceiptCallsOutOnlyFinishesThatNeedAPerson() {
        XCTAssertFalse(VariantProvenancePresentation.needsAttention(finish: "Holo", resolution: .uniqueInCatalog))
        XCTAssertFalse(VariantProvenancePresentation.needsAttention(finish: "Foil Etched", resolution: nil))
        XCTAssertTrue(VariantProvenancePresentation.needsAttention(finish: nil, resolution: nil))
        XCTAssertTrue(VariantProvenancePresentation.needsAttention(finish: nil, resolution: .catalogSilent))
        XCTAssertTrue(VariantProvenancePresentation.needsAttention(finish: "Holofoil", resolution: .userConfirmed))
        XCTAssertEqual(VariantProvenancePresentation.text(finish: "Foil Etched", resolution: nil), "Foil Etched")
    }

    func testUncertaintyNeverHardensWhenItCrossesIntoTheScanReceipt() throws {
        let outcome = VariantResolver.resolve(pokemon(setID: "sv03", variants: []))
        guard case let .resolved(resolved) = outcome else {
            return XCTFail("Catalog silence should still produce a receipt, not a guessed variant")
        }

        XCTAssertNil(resolved.variant)
        XCTAssertEqual(resolved.resolution, .catalogSilent)
        XCTAssertEqual(resolved.resolution.certainty, .unresolved)

        let receipt = ScanReceipt(
            scanID: UUID(),
            name: "Eevee",
            identifier: "PRE 074",
            variantLabel: "Finish unknown",
            treatmentDiagnostics: [],
            thumbnailURL: nil,
            resolution: resolved.resolution
        )
        XCTAssertNil(resolved.variant)
        XCTAssertEqual(receipt.resolution?.certainty, .unresolved)
        XCTAssertEqual(
            VariantProvenancePresentation.text(
                finish: receipt.variantLabel,
                resolution: receipt.resolution
            ),
            "Finish unconfirmed"
        )
    }

    // MARK: - Zero friction where the app can already know

    func testSingleCatalogVariantResolvesWithoutAsking() {
        let outcome = VariantResolver.resolve(pokemon(setID: "sv03", variants: [.holo]))

        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .holo, resolution: .uniqueInCatalog)))
    }

    func testUnverifiedPokemonSingletonAutoResolvesWithoutBypassingAcquisitionGates() {
        for variant in [PhysicalVariant.normal, .holo, .reverse] {
            let evidence = VariantEvidence(game: .pokemon, setID: "fixture", cardNumber: "1",
                catalogVariants: [variant], physicalCoverageVerified: false, explicitMembershipSupported: true)
            XCTAssertEqual(VariantResolver.resolveAcquisition(evidence, printedEdition: .absent),
                .resolved(.init(variant: variant, resolution: .uniqueInCatalog)), variant.id)
        }

        let ambiguous = VariantEvidence(game: .pokemon, setID: "fixture", cardNumber: "1",
            catalogVariants: [.normal, .reverse], physicalCoverageVerified: false, explicitMembershipSupported: true)
        XCTAssertEqual(VariantResolver.resolveAcquisition(ambiguous, printedEdition: .absent),
            .needsChoice(options: [.reverse, .normal], lockDidNotApply: nil))

        let unsupported = VariantEvidence(game: .pokemon, setID: "fixture", cardNumber: "1",
            catalogVariants: [.holo], physicalCoverageVerified: false)
        XCTAssertEqual(VariantResolver.resolveAcquisition(unsupported, printedEdition: .absent),
            .needsChoice(options: [], lockDidNotApply: nil))

        let supported = VariantEvidence(game: .pokemon, setID: "fixture", cardNumber: "1",
            catalogVariants: [.holo], physicalCoverageVerified: false, explicitMembershipSupported: true)
        XCTAssertEqual(VariantResolver.resolveAcquisition(supported, printedEdition: .observed(.normal)),
            .needsChoice(options: [], lockDidNotApply: nil))
        XCTAssertEqual(VariantResolver.resolveAcquisition(supported,
            printedEdition: .init(observed: [.normal, .holo], illegible: false)),
            .needsChoice(options: [], lockDidNotApply: nil))

        let otherGame = VariantEvidence(game: .magic, setID: "fixture", cardNumber: "1",
            catalogVariants: [.foil], physicalCoverageVerified: false, explicitMembershipSupported: true)
        XCTAssertEqual(VariantResolver.resolveAcquisition(otherGame, printedEdition: .absent),
            .needsChoice(options: [.foil], lockDidNotApply: nil))
    }

    func testCatalogWithNothingToSayRecordsUnknownRatherThanGuessing() {
        let outcome = VariantResolver.resolve(pokemon(setID: "sv03", variants: []))

        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: nil, resolution: .catalogSilent)))
    }

    func testSingleCatalogVariantWinsOverAConflictingPrintedLabel() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "sv03", variants: [.holo]),
            printedFinish: .reverse
        )

        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .holo, resolution: .uniqueInCatalog)))
    }

    func testPrintedLabelDisagreementFallsBackToCatalogOptions() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "sv03", variants: [.holo]),
            printedFinish: .reverse
        )

        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .holo, resolution: .uniqueInCatalog)))
    }

    func testPrintedLabelDisagreementLeavesMultipleCatalogOptionsForTheUser() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "sv03", variants: [.normal, .holo]),
            printedFinish: .reverse
        )

        XCTAssertEqual(outcome, .needsChoice(options: [.normal, .holo], lockDidNotApply: nil))
    }

    func testPrintedLabelCanResolveOnlyAfterTheCatalogLeavesMultipleUnstampedOptions() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "sv03", variants: [.normal, .holo]),
            printedFinish: .holo
        )

        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .holo, resolution: .printedLabel)))
    }

    func testFinishLockWinsOverAConflictingPrintedLabel() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "sv03", variants: [.normal, .holo]),
            finishLock: .normal,
            printedFinish: .holo
        )

        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .normal, resolution: .finishLock)))
    }

    func testPrintedLabelCannotSilentlyAnswerAStampedVariantQuestion() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "swsh11", variants: [.holo, .reverse], number: "066"),
            printedFinish: .holo
        )

        guard case let .needsChoice(options, lockDidNotApply) = outcome else {
            return XCTFail("A printed finish must not dismiss a catalog stamp choice")
        }
        XCTAssertNil(lockDidNotApply)
        XCTAssertTrue(options.contains { $0.id == "trickOrTrade2023Holofoil" })
    }

    // MARK: - One tap where the human holds the missing fact

    func testTwoPossibleVariantsAskWithTheLikelierOptionFirst() {
        let outcome = VariantResolver.resolve(pokemon(setID: "sv03", variants: [.normal, .reverse]))

        XCTAssertEqual(outcome, .needsChoice(options: [.reverse, .normal], lockDidNotApply: nil))
    }

    // MARK: - Finish Lock is evidence, not an override

    func testOnePieceFinishLockRequiresExactIDAndReturnsCatalogFinish() {
        let reviewedFoil = PhysicalVariant(id: "foil", label: "Reviewed Foil")
        let evidence = VariantEvidence(
            game: .onePiece, setID: "reviewed-release", cardNumber: "OP01-120",
            catalogVariants: [.normal, reviewedFoil]
        )
        let otherFinish = VariantLock(finish: PhysicalVariant(id: "Foil", label: "Other finish"))
        guard case .needsChoice(_, let rejectedLock) = VariantResolver.resolve(evidence, finishLock: otherFinish) else {
            return XCTFail("A different case-sensitive finish ID must not select this printing's foil")
        }
        XCTAssertEqual(rejectedLock, otherFinish)
        XCTAssertEqual(
            VariantResolver.resolve(evidence, finishLock: VariantLock(finish: .foil)),
            .resolved(ResolvedVariant(variant: reviewedFoil, resolution: .finishLock))
        )
    }

    func testFinishLockResolvesWhenTheCatalogAgreesItIsPossible() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "sv03", variants: [.normal, .reverse]),
            finishLock: .reverse
        )

        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .reverse, resolution: .finishLock)))
    }

    func testFinishLockNeverInventsAVariantThePrintingDoesNotHave() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "sv03", variants: [.normal, .reverse]),
            finishLock: .masterBall
        )

        XCTAssertEqual(
            outcome,
            .needsChoice(
                options: [.reverse, .normal],
                lockDidNotApply: MagicFinishLock(finish: .masterBall)
            )
        )
    }

    func testFinishLockDoesNotOverrideAPrintingThatOnlyExistsOneWay() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "sv03", variants: [.holo]),
            finishLock: .reverse
        )

        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .holo, resolution: .uniqueInCatalog)))
    }

    // MARK: - The supplemental rules layer

    func testBallPatternSetOffersThePatternsTheCatalogDoesNotModel() {
        let outcome = VariantResolver.resolve(pokemon(setID: "sv08.5", variants: [.normal, .reverse]))

        XCTAssertEqual(
            outcome,
            .needsChoice(options: [.reverse, .normal, .pokeBall, .masterBall], lockDidNotApply: nil)
        )
    }

    func testBallPatternRuleDoesNotFireWithoutAReverseHoloPrinting() {
        let outcome = VariantResolver.resolve(pokemon(setID: "sv08.5", variants: [.holo]))

        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .holo, resolution: .uniqueInCatalog)))
    }

    func testOrdinarySetsAreUntouchedByTheRulesLayer() {
        let outcome = VariantResolver.resolve(pokemon(setID: "sv03", variants: [.normal, .reverse]))

        guard case let .needsChoice(options, _) = outcome else {
            return XCTFail("Expected a choice")
        }
        XCTAssertFalse(options.contains(.masterBall))
        XCTAssertFalse(options.contains(.pokeBall))
    }

    func testMasterBallLockOnABallPatternSetRemovesTheTap() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "sv08.5", variants: [.normal, .reverse]),
            finishLock: .masterBall
        )

        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .masterBall, resolution: .finishLock)))
    }

    func testBallPatternsUseExactEligibilityRatherThanEveryReverseHolo() {
        for (set, number) in [("sv08.5", "093"), ("sv10.5b", "079"), ("sv10.5w", "086")] {
            let evidence = pokemon(setID: set, variants: [.normal, .reverse], number: number)
            let options = VariantResolver.options(for: evidence)
            XCTAssertTrue(options.contains(.pokeBall))
            XCTAssertFalse(options.contains(.masterBall))
            guard case .needsChoice(_, let rejected) = VariantResolver.resolve(evidence, finishLock: .masterBall) else {
                return XCTFail("An ineligible Master Ball lock cannot select a finish")
            }
            XCTAssertEqual(rejected?.finish, .masterBall)
        }
        for number in ["006", "119", "131", "001a", "999"] {
            XCTAssertEqual(Set(VariantResolver.options(for: pokemon(setID: "sv08.5",
                variants: [.normal, .reverse], number: number))), Set([.normal, .reverse]))
        }
        XCTAssertEqual(VariantResolver.options(for: pokemon(setID: "sv08.5", variants: [.reverse], number: "1")),
                       VariantResolver.options(for: pokemon(setID: "sv08.5", variants: [.reverse], number: "001")))
        // An additive fallback must not erase newer exact provider evidence.
        XCTAssertTrue(VariantResolver.options(for: pokemon(setID: "sv08.5",
            variants: [.reverse, .masterBall], number: "093")).contains(.masterBall))
    }

    func testExactBallPatternInventoriesHaveAll471Slots() {
        let expected = ["sv08.5": ["pokeBall": 100, "masterBall": 67],
                        "sv10.5b": ["pokeBall": 80, "masterBall": 72],
                        "sv10.5w": ["pokeBall": 80, "masterBall": 72]]
        for (set, counts) in expected {
            for (variant, count) in counts {
                XCTAssertEqual((1...180).filter { number in
                    VariantResolver.options(for: pokemon(setID: set, variants: [.reverse], number: String(number)))
                        .contains(where: { $0.id == variant })
                }.count, count, "\(set) \(variant)")
            }
        }
    }

    func testBrowseSlotsAndScannerShareExactParallelEligibility() throws {
        let card = try JSONDecoder().decode(TCGdexCard.self, from: Data(#"""
        {"id":"sv08.5-093","localId":"093","name":"Amarys",
         "set":{"id":"sv08.5","name":"Prismatic Evolutions","cardCount":{"total":180,"official":131}},
         "variants":{"firstEdition":false,"holo":false,"normal":true,"reverse":true},
         "variants_detailed":[{"type":"reverse","foil":"masterball","languages":["ja"],"size":"standard"},
                                {"type":"holo","foil":"cosmos","languages":["en"],"size":"jumbo"},
                                {"type":"reverse","foil":"pokeball","languages":["ja"],"size":"standard","thirdParty":{"tcgplayer":11}},
                                {"type":"reverse","foil":"pokeball","languages":["en"],"size":"standard","thirdParty":{"tcgplayer":99}}]}
        """#.utf8))
        XCTAssertEqual(Set(PokemonMasterSetDefinition.requiredVariants(for: card).map(\.variant)),
                       Set([.normal, .reverse, .pokeBall]))
        XCTAssertEqual(Set(VariantResolver.options(for: IdentifiedCard.pokemon(card, setCode: "PRE").variantEvidence)),
                       Set([.normal, .reverse, .pokeBall]))
        XCTAssertNil(card.detailedVariant(for: .masterBall))
        XCTAssertNil(card.detailedVariant(for: PhysicalVariant.pokemonFoilPattern("cosmos")))
        XCTAssertEqual(card.detailedVariant(for: .pokeBall)?.thirdParty?.tcgplayer, 99)
    }

    // MARK: - Stamped releases

    func testLostOriginGengarOffersItsExactStampedRelease() throws {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "swsh11", variants: [.holo, .reverse], number: "066")
        )
        guard case let .needsChoice(options, _) = outcome else {
            return XCTFail("Stamped eligibility must remain a user choice")
        }

        let stamped = try XCTUnwrap(options.first { $0.id == "trickOrTrade2023Holofoil" })
        XCTAssertEqual(stamped.label, "Stamped (2023)")
        XCTAssertEqual(
            PokemonStampedReleaseCatalog.entries(providerID: "swsh11-066").first?.tcgplayerProductID,
            "515661"
        )
        XCTAssertEqual(ProductFinish.printing(for: stamped), "Holofoil")
    }

    func testStampedPickerIsNotOfferedToSameNumberInAnotherSet() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "different", variants: [.holo], number: "066")
        )
        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .holo, resolution: .uniqueInCatalog)))
    }

    func testFinishLockSelectsExactUnstampedVariantAlongsideSupplementalStampedRelease() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "swsh11", variants: [.holo, .reverse], number: "066"),
            finishLock: .holo
        )
        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .holo, resolution: .finishLock)))
    }

    func testLilliesDeterminationNormalLockResolvesAlongsideCatalogStampsAndPatterns() throws {
        let prizePack = try XCTUnwrap(PokemonCatalogStampVariant.make(base: .normal, stamps: ["prize-pack"]))
        let regional = try XCTUnwrap(PokemonCatalogStampVariant.make(base: .normal, stamps: ["regional-championships"]))
        let staff = try XCTUnwrap(PokemonCatalogStampVariant.make(base: .normal, stamps: ["regional-championships", "staff"]))
        let evidence = pokemon(
            setID: "me01", variants: [.reverse, .normal, .holo, .pokemonFoilPattern("cosmos"), prizePack, regional, staff],
            number: "119"
        )

        XCTAssertEqual(
            VariantResolver.resolve(evidence, finishLock: .normal),
            .resolved(ResolvedVariant(variant: .normal, resolution: .finishLock))
        )
        guard case let .needsChoice(options, _) = VariantResolver.resolve(evidence) else {
            return XCTFail("Auto should retain all seven physical variants")
        }
        XCTAssertEqual(Set(options), Set(evidence.catalogVariants))
    }

    func testFinishLockDoesNotMatchStampedBaseWhenPlainFinishIsUnavailable() throws {
        let prizePack = try XCTUnwrap(PokemonCatalogStampVariant.make(base: .normal, stamps: ["prize-pack"]))
        let regional = try XCTUnwrap(PokemonCatalogStampVariant.make(base: .normal, stamps: ["regional-championships"]))
        let evidence = pokemon(setID: "me01", variants: [prizePack, regional], number: "119")
        guard case let .needsChoice(options, rejected) = VariantResolver.resolve(evidence, finishLock: .normal) else {
            return XCTFail("Normal must never substitute for a stamped Normal variant")
        }
        XCTAssertEqual(Set(options), [prizePack, regional])
        XCTAssertEqual(rejected, VariantLock(finish: .normal))
    }

    func testSerializedStampedVariantKeepsItsReadableLabel() throws {
        let detailed = try JSONDecoder().decode(
            TCGdexDetailedVariant.self,
            from: Data(#"{"type":"reverse","foil":"pokemonStamp|holo|set-logo|"}"#.utf8)
        )

        XCTAssertEqual(detailed.physicalVariant?.id, "pokemonStamp|holo|set-logo|")
        XCTAssertEqual(detailed.physicalVariant?.label, "Holo · Set Logo")
    }

    func testStampedCatalogHasOneExactMarketplaceProductPerDocumentedCard() {
        XCTAssertEqual(PokemonStampedReleaseCatalog.entries.count, 90)
        XCTAssertEqual(
            Set(PokemonStampedReleaseCatalog.entries.map(\.tcgplayerProductID)).count,
            PokemonStampedReleaseCatalog.entries.count
        )
        XCTAssertTrue(PokemonStampedReleaseCatalog.entries.allSatisfy {
            !$0.providerID.isEmpty
                && Int($0.tcgplayerProductID) != nil
                && ["Normal", "Holofoil"].contains($0.printing)
        })
    }

    // MARK: - Magic

    func testMagicFinishesComeStraightFromTheCatalog() {
        let evidence = VariantEvidence(
            game: .magic,
            setID: "ecl",
            cardNumber: "218",
            catalogVariants: [.nonfoil, .foil]
        )

        XCTAssertEqual(
            VariantResolver.resolve(evidence),
            .needsChoice(options: [.nonfoil, .foil], lockDidNotApply: nil)
        )
    }

    func testMagicFinishLockMenuIsNarrowAndTreatmentAware() {
        let magicLocks = MagicFinishLock.selectable(for: .magic)
        XCTAssertEqual(
            magicLocks.map(\.label),
            ["Nonfoil", "Foil", "Etched Foil", "Surge Foil", "Neon Ink"]
        )
        XCTAssertEqual(
            magicLocks.map(\.id),
            [
                "nonfoil",
                "foil",
                "etched",
                "foil#treatment=surgefoil",
                "foil#treatment=neonink"
            ]
        )

        XCTAssertEqual(
            MagicFinishLock.selectable(for: .pokemon).map(\.finish),
            PhysicalVariant.selectable(for: .pokemon)
        )
        XCTAssertTrue(
            magicLocks.contains {
                $0.finish == .foil && $0.treatment == .surgeFoil
            }
        )
        for lock in magicLocks.compactMap({ $0.treatment }) {
            XCTAssertEqual(
                magicLocks.first(where: { $0.treatment == lock })?.finish,
                lock.requiredFinishes.first,
                "Treatment locks should derive their physical finish from the treatment"
            )
        }
    }

    func testMagicTreatmentLockRequiresMatchingEvidenceAndPhysicalFinish() {
        let lock = MagicFinishLock(finish: .foil, treatment: .surgeFoil)
        let dualFinishEvidence = VariantEvidence(
            game: .magic,
            setID: "fic",
            cardNumber: "10",
            catalogVariants: [.nonfoil, .foil],
            magicTreatments: [.surgeFoil]
        )

        XCTAssertEqual(
            VariantResolver.resolve(dualFinishEvidence, finishLock: lock),
            .resolved(ResolvedVariant(variant: .foil, resolution: .finishLock))
        )

        let missingTreatment = VariantEvidence(
            game: .magic,
            setID: "fic",
            cardNumber: "10",
            catalogVariants: [.nonfoil, .foil]
        )
        XCTAssertEqual(
            VariantResolver.resolve(missingTreatment, finishLock: lock),
            .needsChoice(options: [.nonfoil, .foil], lockDidNotApply: lock)
        )

        let wrongFinish = VariantEvidence(
            game: .magic,
            setID: "fic",
            cardNumber: "10",
            catalogVariants: [.nonfoil],
            magicTreatments: [.surgeFoil]
        )
        XCTAssertEqual(
            VariantResolver.resolve(wrongFinish, finishLock: lock),
            .resolved(ResolvedVariant(variant: .nonfoil, resolution: .uniqueInCatalog))
        )

        let differentTreatment = VariantEvidence(
            game: .magic,
            setID: "fic",
            cardNumber: "10",
            catalogVariants: [.nonfoil, .foil],
            magicTreatments: [.neonInk]
        )
        XCTAssertEqual(
            VariantResolver.resolve(differentTreatment, finishLock: lock),
            .needsChoice(options: [.nonfoil, .foil], lockDidNotApply: lock)
        )
    }

    func testMagicTreatmentLockReportsNonApplicationWhenTheCatalogIsSilent() {
        let lock = MagicFinishLock(finish: .foil, treatment: .surgeFoil)
        let evidence = VariantEvidence(
            game: .magic,
            setID: "unknown",
            cardNumber: "1",
            catalogVariants: [],
            magicTreatments: [.surgeFoil]
        )

        XCTAssertEqual(
            VariantResolver.resolve(evidence, finishLock: lock),
            .resolved(ResolvedVariant(variant: nil, resolution: .catalogSilent))
        )
    }

    func testMagicTreatmentLockDoesNotApplyAcrossGameBoundaries() {
        let lock = MagicFinishLock(finish: .holo, treatment: .surgeFoil)
        let evidence = VariantEvidence(
            game: .pokemon,
            setID: "sv08.5",
            cardNumber: "1",
            catalogVariants: [.normal, .holo],
            magicTreatments: [.surgeFoil]
        )

        XCTAssertEqual(
            VariantResolver.resolve(evidence, finishLock: lock),
            .needsChoice(options: [.normal, .holo], lockDidNotApply: lock)
        )
    }

    func testPokemonRulesNeverApplyToMagic() {
        // A Magic set code could collide with a Pokémon set id in a naive table.
        let evidence = VariantEvidence(
            game: .magic,
            setID: "sv08.5",
            cardNumber: "218",
            catalogVariants: [.nonfoil, .foil]
        )

        guard case let .needsChoice(options, _) = VariantResolver.resolve(evidence) else {
            return XCTFail("Expected a choice")
        }
        XCTAssertEqual(options, [.nonfoil, .foil])
    }
}
