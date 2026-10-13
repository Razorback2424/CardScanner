import CryptoKit
import Foundation
import SwiftData
import XCTest
@testable import TradingCardScanner

/// Synthetic review records exercise local contracts, not physical-card coverage.
@MainActor
final class LorcanaOwnershipTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let canonicalID = UUID(uuidString: "81000000-0000-0000-0000-000000000001")!
    private let artworkID = UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!
    private func id(_ index: Int = 1) -> UUID {
        UUID(uuidString: String(format: "91000000-0000-0000-0000-%012d", index))!
    }
    private func manifest(count: Int = 1, complete: Bool = true, name: String = "Fixture Elsa",
                          finishes: [LorcanaPhysicalFinish] = [.normal, .foil]) throws -> LorcanaPhysicalCatalogManifest {
        let footer = try LorcanaPrintedIdentity(collectorNumber: "207", denominator: "204", language: "en", printedSetMarker: "1")
        let alias = LorcanaSourceAlias(provider: "fixture", id: "shared-family")
        let prints = (1...count).map { index in
            LorcanaPhysicalPrinting(id: id(index), identity: .init(canonicalCardID: canonicalID, footer: footer,
                artworkID: artworkID, distributionID: "booster", stamp: count > 1 ? "Fixture Stamp \(index)" : nil,
                size: .standard, layout: "normal"), providerSetCode: "TFC", setName: "Fixture First Chapter",
                artworkLabel: "Original artwork", distributionLabel: "Fixture Booster", imageURL: nil, status: .verified,
                identityEvidence: LorcanaPhysicalEvidenceKind.allCases.map { .init(kind: $0, reference: "fixture:\($0.rawValue)") },
                finishes: finishes.map { .init(finish: $0, evidenceReferences: ["fixture:\($0.rawValue)"]) },
                finishUniverseEvidenceReference: "fixture:finishes", sourceAliases: [alias])
        }
        return .init(schemaVersion: 2, reviewedAt: now, printFamilies: [.init(footer: footer, providerSetCode: "TFC",
            name: name, version: nil, rarity: "Fixture", layout: "normal", sourceAliases: [alias], footerEvidenceReference: "fixture:footer")],
            canonicalCards: [.init(id: canonicalID, name: name, version: nil, relationshipEvidenceReferences: ["fixture:canonical"])],
            physicalPrintings: prints, universes: [.init(footer: footer, printingIDs: prints.map(\.id), isComplete: complete,
                evidenceReference: complete ? "fixture:universe" : nil)], corrections: [])
    }
    private func registry(count: Int = 1, complete: Bool = true, name: String = "Fixture Elsa") throws -> LorcanaCatalogRegistry {
        try .init(manifest: manifest(count: count, complete: complete, name: name))
    }
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("LorcanaOwnership-\(UUID())") }
    private func container(url: URL? = nil) throws -> ModelContainer {
        if let url { try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true) }
        let schema = Schema([CollectedCard.self, CollectionActivity.self, InventoryEvent.self, PriceRecord.self,
                             ReferenceQuote.self, PriceObservation.self, PriceCheckDay.self])
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0, cloudKitDatabase: .none) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: configuration)
    }
    private func entry(_ index: Int = 1, finish: String = "foil", extraHeaders: String = "", extraValues: String = "") throws -> CollectionCSVEntry {
        let csv = "game,provider_id,card_name,card_number,finish,quantity\(extraHeaders)\nlorcana,\(id(index).uuidString.lowercased()),Fixture Elsa,207/204 EN 1,\(finish),1\(extraValues)\n"
        return try XCTUnwrap(CollectionCSV.parse(Data(csv.utf8)).entries.first)
    }
    private func apply(_ plan: CollectionCSVImportPlan, to container: ModelContainer,
                       runtimes: CardGameRuntimeContainer, adapters: GameImportAdapterRegistry? = nil) async throws -> CollectionCSVImportResult {
        let current = await runtimes.currentImportAdapters()
        let token = try CollectionWriteSerializer.beginExclusive(timeout: .mainThread)
        defer { CollectionWriteSerializer.endExclusive(token) }
        return try await CollectionCSV.applyIsolated(plan, to: container, exclusiveToken: token,
            gameRegistry: runtimes.registry, gameImportAdapters: adapters ?? current)
    }
    private func waitUntil(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<300 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return predicate()
    }

    func testBrowseListsReviewedPhysicalPrintingsAndCountsExactOwnership() async throws {
        let adapter = LorcanaBrowseAdapter(registry: try registry(count: 2))
        let sets = try await adapter.sets(), set = try XCTUnwrap(sets.first)
        XCTAssertEqual(sets.count, 1)
        XCTAssertTrue(set.name.contains("reviewed printings"))
        XCTAssertEqual(set.cardCount, 2)
        XCTAssertEqual(set.physicalPrintingIDs, Set([id().uuidString.lowercased(), id(2).uuidString.lowercased()]))
        let page = try await adapter.cards(in: set, cursor: nil)
        XCTAssertEqual(page.items.count, 2)
        XCTAssertNotEqual(page.items[0].name, page.items[1].name)
        let detail = try await adapter.details(for: page.items[0])
        let row = CollectedCard(collectionKey: detail.card.collectionKey(variant: .foil), game: .lorcana,
            providerID: detail.card.physicalPrintingID, name: detail.card.name, setName: detail.card.setName,
            setCode: detail.card.setCode, cardNumber: detail.card.cardNumber, rarity: nil, imageURL: nil, thumbnailURL: nil,
            variant: .foil, variantResolution: .userConfirmed)
        let index = CatalogOwnershipIndex([row])
        XCTAssertTrue(index.owns(page.items[0])); XCTAssertFalse(index.owns(page.items[1]))
        XCTAssertEqual(index.progress(for: set).owned, 1)
        XCTAssertEqual(index.progress(for: set).unit, "printings")
    }

    func testIncompleteUniverseCannotBeBrowsedOrImported() async throws {
        let registry = try registry(complete: false), adapter = LorcanaBrowseAdapter(registry: registry)
        let sets = try await adapter.sets()
        XCTAssertTrue(sets.isEmpty)
        XCTAssertThrowsError(try LorcanaImportAdapter(registry: registry).validate(entry()))
    }

    func testBrowsePaginationBindsCursorToQueryScopeAndGeneration() async throws {
        let first = LorcanaBrowseAdapter(registry: try registry(count: 62))
        let sets = try await first.sets(), set = try XCTUnwrap(sets.first)
        let page = try await first.cards(in: set, cursor: nil), cursor = try XCTUnwrap(page.nextCursor)
        let tail = try await first.cards(in: set, cursor: cursor)
        XCTAssertEqual(page.items.count, 60); XCTAssertEqual(tail.items.count, 2); XCTAssertNil(tail.nextCursor)
        XCTAssertEqual(Set((page.items + tail.items).map(\.id)).count, 62)
        let search = try await first.search(query: "Fixture Elsa", setIDs: [], cursor: nil)
        let searchCursor = try XCTUnwrap(search.nextCursor)
        do { _ = try await first.search(query: "Stamp", setIDs: [], cursor: searchCursor); XCTFail() }
        catch CatalogLookupError.staleCatalog {}
        do { _ = try await first.search(query: "Fixture Elsa", setIDs: [set.catalogID], cursor: searchCursor); XCTFail() }
        catch CatalogLookupError.staleCatalog {}
        let next = LorcanaBrowseAdapter(registry: try registry(count: 62, name: "Corrected fixture"))
        let nextSets = try await next.sets()
        do { _ = try await next.cards(in: XCTUnwrap(nextSets.first), cursor: cursor); XCTFail() }
        catch CatalogLookupError.staleCatalog {}
        do { _ = try await next.details(for: page.items[0]); XCTFail() }
        catch CatalogLookupError.staleCatalog {}
    }

    func testImportRequiresExactUUIDSupportedFinishAndOwnershipKey() throws {
        let adapter = LorcanaImportAdapter(registry: try registry())
        XCTAssertNoThrow(try adapter.validate(entry()))
        XCTAssertThrowsError(try adapter.validate(entry(2)))
        XCTAssertThrowsError(try adapter.validate(entry(finish: "future-finish")))
        XCTAssertThrowsError(try adapter.validate(entry(finish: "")))
        XCTAssertThrowsError(try adapter.validate(entry(extraHeaders: ",collection_key", extraValues: ",lorcana:wrong#foil")))
        XCTAssertThrowsError(try adapter.validate(entry(extraHeaders: ",catalog_provider_id", extraValues: ",\(id(2).uuidString.lowercased())")))
        XCTAssertThrowsError(try adapter.validate(entry(extraHeaders: ",item_kind", extraValues: ",future-kind")))
        var conflicting = try entry(); conflicting.sourceLanguage = "fr"
        XCTAssertThrowsError(try adapter.validate(conflicting))
        conflicting.sourceLanguage = "English"
        XCTAssertNoThrow(try adapter.validate(conflicting))
    }

    func testConflictingDuplicateRowsRetainEvidenceThroughFailedExport() throws {
        let key = "lorcana:\(id().uuidString.lowercased())#foil"
        let headers = "game,provider_id,collection_key,card_name,card_number,finish,quantity,item_kind,language\n"
        let valid = "lorcana,\(id().uuidString.lowercased()),\(key),Fixture Elsa,207,foil,1,rawCard,en\n"
        let conflict = "lorcana,\(id(2).uuidString.lowercased()),\(key),Fixture Elsa,207,foil,1,rawCard,en\n"
        let plan = try CollectionCSV.parse(Data((headers + valid + conflict).utf8))
        XCTAssertEqual(plan.entries.count, 1)
        let row = try XCTUnwrap(plan.entries.first)
        XCTAssertTrue(row.conflictingSourceIdentity)
        let exported = CollectionCSV.exportFailedEntries([row])
        let replay = try XCTUnwrap(CollectionCSV.parse(Data(exported.text.utf8)).entries.first)
        XCTAssertTrue(replay.conflictingSourceIdentity)
        XCTAssertThrowsError(try LorcanaImportAdapter(registry: registry(count: 2)).validate(replay))
        let harmless = try CollectionCSV.parse(Data((headers + valid + valid).utf8))
        XCTAssertEqual(harmless.entries.first?.quantity, 2)
        XCTAssertFalse(try XCTUnwrap(harmless.entries.first).conflictingSourceIdentity)
        for altered in [valid.replacingOccurrences(of: ",207,", with: ",208,"),
                        valid.replacingOccurrences(of: ",foil,", with: ",normal,"),
                        valid.replacingOccurrences(of: ",rawCard,", with: ",future-kind,")] {
            let duplicate = try CollectionCSV.parse(Data((headers + valid + altered).utf8))
            XCTAssertTrue(try XCTUnwrap(duplicate.entries.first).conflictingSourceIdentity)
        }
    }

    func testMetadataNeverUsesFamilyAliasToChooseAPhysicalUUID() async throws {
        let adapter = LorcanaImportAdapter(registry: try registry(count: 2))
        func request(_ source: String, _ catalog: String?) -> GameImportRequest {
            .init(sourceProviderID: source, catalogProviderID: catalog, game: .lorcana, name: "Fixture Elsa",
                setName: "Imported", cardNumber: "207", itemKind: .rawCard)
        }
        let ambiguous = request("fixture:shared-family", nil)
        let explicit = request("fixture:shared-family", id().uuidString.lowercased())
        let conflict = request(id(2).uuidString.lowercased(), id().uuidString.lowercased())
        let results = await adapter.metadata(for: [ambiguous, explicit, conflict])
        XCTAssertNil(results[ambiguous.identityKey]); XCTAssertNil(results[conflict.identityKey])
        XCTAssertEqual(results[explicit.identityKey]?.providerID, id().uuidString.lowercased())
    }

    #if DEBUG && LOCAL_ONLY_SIGNING
    func testDebugWritesRequireAnIsolatedContainerAndStayDisabledOnUnboundRuntime() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let kit = try LorcanaLocalReviewKit.make(manifest: manifest(), root: root, now: now, allowCollectionWrites: true)
        XCTAssertFalse(kit.runtime.descriptor.capabilities.contains(.collectionWrite))
        let memory = try container(), bound = try await kit.bound(to: memory)
        XCTAssertTrue(bound.registry.supports(.lorcana, .collectionWrite))
        let unrelated = try container(url: root.appendingPathComponent("unrelated.store"))
        do { _ = try await kit.bound(to: unrelated); XCTFail() }
        catch LorcanaLocalReviewKit.ValidationError.nonIsolatedCollection {}
        XCTAssertNil(CardGameRuntimeContainer.appDefaults().runtime(for: .lorcana))
    }

    func testBrowseAddUndoAndUnsupportedFinishLeaveNoOwnership() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let kit = try LorcanaLocalReviewKit.make(manifest: manifest(), root: root, now: now, allowCollectionWrites: true)
        let container = try container(), runtimes = try await kit.bound(to: container)
        let browse = runtimes.makeBrowseCatalog(), sets = try await browse.sets(for: .lorcana)
        let page = try await browse.cards(in: XCTUnwrap(sets.first), cursor: nil)
        let card = try await browse.details(for: XCTUnwrap(page.items.first)).card
        let store = CollectionStore(context: container.mainContext)
        let mutation = try store.add(card, resolved: .init(variant: .foil, resolution: .userConfirmed))
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).first?.collectionKey, card.collectionKey(variant: .foil))
        try store.undo(mutation)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertThrowsError(try store.add(card, resolved: .init(variant: .reverse, resolution: .userConfirmed)))
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PriceObservation>()).isEmpty)
    }

    func testCSVStorageRelaunchAndRoundTripPreservePhysicalFinishKeys() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let kit = try LorcanaLocalReviewKit.make(manifest: manifest(), root: root, now: now, allowCollectionWrites: true)
        try FileManager.default.createDirectory(at: kit.collectionDirectory, withIntermediateDirectories: true)
        let url = kit.collectionDirectory.appendingPathComponent("collection.store")
        let original = try container(url: url), runtimes = try await kit.bound(to: original)
        let input = CollectionCSV.exportFailedEntries([try entry()])
        let result = try await apply(CollectionCSV.parse(Data(input.text.utf8)), to: original, runtimes: runtimes)
        XCTAssertEqual(result.importedQuantity, 1); XCTAssertTrue(result.failedRows.isEmpty)
        await runtimes.makeCollectionNormalizer().normalizeImportedCards(in: original)
        let relaunched = try container(url: url)
        let rows = try relaunched.mainContext.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows.first?.variantID, "foil")
        XCTAssertEqual(rows.first?.catalogProviderID, id().uuidString.lowercased())
        XCTAssertEqual(rows.first?.setCode, "TFC")
        XCTAssertEqual(rows.first?.collectionKey, "lorcana:\(id().uuidString.lowercased())#foil")
        let exported = CollectionCSV.export(rows)
        let target = try container(), targetRuntimes = try await kit.bound(to: target)
        let replay = try await apply(CollectionCSV.parse(Data(exported.text.utf8)), to: target, runtimes: targetRuntimes)
        XCTAssertEqual(replay.importedQuantity, 1); XCTAssertTrue(replay.failedRows.isEmpty)
        XCTAssertEqual(try target.mainContext.fetch(FetchDescriptor<CollectedCard>()).first?.collectionKey, rows.first?.collectionKey)
    }

    func testStaleImportAdapterCannotWriteAfterCatalogAuthorityBecomesIncomplete() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let kit = try LorcanaLocalReviewKit.make(manifest: manifest(), root: root, now: now, allowCollectionWrites: true)
        let container = try container(), runtimes = try await kit.bound(to: container)
        let stale = await runtimes.currentImportAdapters()
        let incomplete = LorcanaCatalogAdapter(registry: try registry(complete: false))
        XCTAssertTrue(CollectionStore.installCatalogAdapter(incomplete, revision: 2, for: container))
        let csv = CollectionCSV.exportFailedEntries([try entry()])
        let result = try await apply(CollectionCSV.parse(Data(csv.text.utf8)), to: container, runtimes: runtimes, adapters: stale)
        XCTAssertEqual(result.importedQuantity, 0); XCTAssertEqual(result.failedRows.count, 1)
        let fresh = ModelContext(container)
        XCTAssertTrue(try fresh.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertTrue(try fresh.fetch(FetchDescriptor<CollectionActivity>()).isEmpty)
        XCTAssertTrue(try fresh.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
    }

    func testFinishCorrectionAndLaterCatalogWithdrawalProtectQuantityAndHistory() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let kit = try LorcanaLocalReviewKit.make(manifest: manifest(), root: root, now: now, allowCollectionWrites: true)
        let container = try container(), runtimes = try await kit.bound(to: container)
        let store = CollectionStore(context: container.mainContext)
        let card = try LorcanaCatalogAdapter(registry: registry()).resolution(forPrintingID: id()).card
        _ = try store.add(card, resolved: .init(variant: .normal, resolution: .userConfirmed))
        _ = try store.recordVariantCorrection(for: card, from: .normal, to: .init(variant: .foil, resolution: .userConfirmed))
        let row = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(row.collectionKey, card.collectionKey(variant: .foil))
        XCTAssertEqual(row.quantity, 1)
        let events = try container.mainContext.fetch(FetchDescriptor<InventoryEvent>()).count
        let activities = try container.mainContext.fetch(FetchDescriptor<CollectionActivity>()).count
        XCTAssertThrowsError(try store.recordVariantCorrection(for: card, from: .foil, to: .init(variant: .reverse, resolution: .userConfirmed)))
        XCTAssertTrue(CollectionStore.installCatalogAdapter(LorcanaCatalogAdapter(registry: try registry(complete: false)), revision: 2, for: container))
        XCTAssertThrowsError(try store.setQuantity(2, for: row))
        XCTAssertThrowsError(try store.recordVariantCorrection(for: card, from: .foil, to: .init(variant: .normal, resolution: .userConfirmed)))
        let fresh = ModelContext(container), retained = try XCTUnwrap(fresh.fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(retained.quantity, 1); XCTAssertEqual(retained.collectionKey, card.collectionKey(variant: .foil))
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<InventoryEvent>()).count, events)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<CollectionActivity>()).count, activities)
        XCTAssertTrue(runtimes.registry.supports(.lorcana, .collectionWrite))
        CollectionStore.configureCatalogAdapters(try .init(adapters: []), legacyCorrectionGames: [], for: container)
        XCTAssertThrowsError(try store.setQuantity(2, forCollectionKey: retained.collectionKey, expectedCurrent: 1))
        CollectionStore.configureGames(CardGameRegistry.standard, for: container)
        XCTAssertThrowsError(try store.add(card, resolved: .init(variant: .foil, resolution: .userConfirmed)))
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 1)
    }

    func testReadOnlyBindingRejectsScanAndCSVWithoutOwnershipOrHistory() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let kit = try LorcanaLocalReviewKit.make(manifest: manifest(), root: root, now: now)
        let container = try container(), runtimes = try await kit.bound(to: container)
        let card = try LorcanaCatalogAdapter(registry: registry()).resolution(forPrintingID: id()).card
        XCTAssertThrowsError(try CollectionStore(context: container.mainContext).add(card, resolved: .init(variant: .foil, resolution: .userConfirmed)))
        let csv = CollectionCSV.exportFailedEntries([try entry()])
        let result = try await apply(CollectionCSV.parse(Data(csv.text.utf8)), to: container, runtimes: runtimes)
        XCTAssertEqual(result.importedQuantity, 0)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
    }

    func testScannerPrintingThenFinishSavesDifferentCopiesWithIndependentRecovery() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let kit = try LorcanaLocalReviewKit.make(manifest: manifest(count: 2), root: root, now: now, allowCollectionWrites: true)
        let container = try container(), runtimes = try await kit.bound(to: container)
        let source = try XCTUnwrap(runtimes.runtime(for: .lorcana)?.activationSource)
        let recovery = UnresolvedScanStore(fileURL: root.appendingPathComponent("recovery.json"))
        let model = ScannerViewModel(gameRegistry: runtimes.registry, catalog: runtimes.makeCardCatalog(), unresolvedScanStore: recovery)
        model.start(context: container.mainContext, startCamera: false, shouldRefreshMagicDirectory: false)
        defer { model.viewDisappeared() }
        model.observeCatalogActivations([source])
        let currentSnapshot = await source.currentSnapshot()
        let snapshot = try XCTUnwrap(currentSnapshot)
        guard case let .identified(subject) = snapshot.recognizer.identify([.init(text: "207/204 EN 1")]) else { return XCTFail() }
        for _ in 0..<2 {
            model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), subject, nil)
            let appeared = await waitUntil { model.pendingIdentityChoice != nil }; XCTAssertTrue(appeared)
            model.dismissIdentityChoice()
            let filed = await waitUntil { model.pendingIdentityChoice == nil }; XCTAssertTrue(filed)
        }
        XCTAssertEqual(model.unresolvedScans.count, 2)
        let firstRecovery = try XCTUnwrap(model.unresolvedScans.first?.id)
        model.resolveUnresolved(id: firstRecovery, choice: .retryLookup)
        let choice = await waitUntil { model.pendingIdentityChoice != nil }; XCTAssertTrue(choice)
        model.choose(try XCTUnwrap(model.pendingIdentityChoice).displayCandidates[0])
        let finish = await waitUntil { model.pendingChoice != nil }; XCTAssertTrue(finish)
        model.choose(.foil)
        let saved = await waitUntil { model.successCount == 1 }; XCTAssertTrue(saved)
        XCTAssertEqual(model.unresolvedScans.count, 1)
        XCTAssertNotEqual(model.unresolvedScans.first?.id, firstRecovery)
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), subject, nil)
        let next = await waitUntil { model.pendingIdentityChoice != nil }; XCTAssertTrue(next)
        model.choose(try XCTUnwrap(model.pendingIdentityChoice).displayCandidates[1])
        let nextFinish = await waitUntil { model.pendingChoice != nil }; XCTAssertTrue(nextFinish)
        model.choose(.normal)
        let nextSave = await waitUntil { model.successCount == 2 }; XCTAssertTrue(nextSave)
        let rows = try container.mainContext.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(Set(rows.map(\.collectionKey)), Set(["lorcana:\(id().uuidString.lowercased())#foil", "lorcana:\(id(2).uuidString.lowercased())#normal"]))
        XCTAssertEqual(model.unresolvedScans.count, 1)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PriceObservation>()).isEmpty)
    }
    #endif
}
