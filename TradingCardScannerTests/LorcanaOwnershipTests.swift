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
                          finishes: [LorcanaPhysicalFinish] = [.normal, .foil],
                          supersedingFirst: Bool = false) throws -> LorcanaPhysicalCatalogManifest {
        let footer = try LorcanaPrintedIdentity(collectorNumber: "207", denominator: "204", language: "en", printedSetMarker: "1")
        let alias = LorcanaSourceAlias(provider: "fixture", id: "shared-family")
        let prints = (1...count).map { index in
            LorcanaPhysicalPrinting(id: id(index), identity: .init(canonicalCardID: canonicalID, footer: footer,
                artworkID: artworkID, distributionID: "booster", stamp: count > 1 ? "Fixture Stamp \(index)" : nil,
                size: .standard, layout: "normal"), providerSetCode: "TFC", setName: "Fixture First Chapter",
                artworkLabel: "Original artwork", distributionLabel: "Fixture Booster", imageURL: nil,
                status: supersedingFirst && index == 1 ? .superseded : .verified,
                identityEvidence: LorcanaPhysicalEvidenceKind.allCases.map { .init(kind: $0, reference: "fixture:\($0.rawValue)") },
                finishes: finishes.map { .init(finish: $0, evidenceReferences: ["fixture:\($0.rawValue)"]) },
                finishUniverseEvidenceReference: "fixture:finishes", sourceAliases: [alias])
        }
        return .init(schemaVersion: 2, reviewedAt: now, printFamilies: [.init(footer: footer, providerSetCode: "TFC",
            name: name, version: nil, rarity: "Fixture", layout: "normal", sourceAliases: [alias], footerEvidenceReference: "fixture:footer")],
            canonicalCards: [.init(id: canonicalID, name: name, version: nil, relationshipEvidenceReferences: ["fixture:canonical"])],
            physicalPrintings: prints, universes: [.init(footer: footer,
                printingIDs: prints.filter { $0.status != .superseded }.map(\.id), isComplete: complete,
                evidenceReference: complete ? "fixture:universe" : nil)],
            corrections: supersedingFirst ? [.init(id: UUID(uuidString: "B1000000-0000-0000-0000-000000000001")!,
                fromPrintingIDs: [id()], toPrintingIDs: [id(2)], evidenceReferences: ["fixture:correction"])] : [])
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
        XCTAssertEqual(Set(page.items.map(\.name)), ["Fixture Elsa · Stamp: Fixture Stamp 1", "Fixture Elsa · Stamp: Fixture Stamp 2"])
        for summary in page.items {
            let exact = try await adapter.details(for: summary)
            XCTAssertEqual(summary.name, exact.card.name)
        }
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

    func testBrowseConstructionPerformanceForLargeReviewedFamily() throws {
        let registry = try registry(count: 62)
        measure(metrics: [XCTClockMetric()]) {
            let adapter = LorcanaBrowseAdapter(registry: registry)
            XCTAssertEqual(adapter.generation, registry.generation)
        }
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
    private func manifestAddingOversized(name: String = "Fixture Elsa") throws -> LorcanaPhysicalCatalogManifest {
        let original = try manifest(name: name), first = try XCTUnwrap(original.physicalPrintings.first)
        let second = LorcanaPhysicalPrinting(id: id(2), identity: .init(canonicalCardID: canonicalID,
            footer: first.identity.footer, artworkID: artworkID, distributionID: "booster", stamp: nil,
            size: .oversized, layout: "normal"), providerSetCode: first.providerSetCode, setName: first.setName,
            artworkLabel: first.artworkLabel, distributionLabel: first.distributionLabel, imageURL: nil,
            status: .verified, identityEvidence: first.identityEvidence, finishes: first.finishes,
            finishUniverseEvidenceReference: first.finishUniverseEvidenceReference, sourceAliases: first.sourceAliases)
        return .init(schemaVersion: 2, reviewedAt: now, printFamilies: original.printFamilies,
            canonicalCards: original.canonicalCards, physicalPrintings: [first, second],
            universes: [.init(footer: first.identity.footer, printingIDs: [first.id, second.id],
                isComplete: true, evidenceReference: "fixture:expanded-universe")], corrections: [])
    }

    private func signed(_ manifest: LorcanaPhysicalCatalogManifest, revision: Int,
                        key: Curve25519.Signing.PrivateKey) throws -> LorcanaCatalogReleaseEnvelope {
        try LorcanaCatalogSignature.sign(.init(schemaVersion: 1, gameID: "lorcana", revision: revision,
            generatedAt: now, catalog: manifest), keyID: "lorcana-ownership-activation", privateKey: key)
    }

    private func activationFixture(root: URL, initial: LorcanaPhysicalCatalogManifest) async throws
        -> (model: ScannerViewModel, container: ModelContainer, coordinator: LorcanaCatalogCoordinator,
            key: Curve25519.Signing.PrivateKey) {
        let key = Curve25519.Signing.PrivateKey(), registry = try LorcanaCatalogRegistry(manifest: initial)
        let store = try LorcanaCatalogReleaseStore(root: root.appendingPathComponent("releases"),
            keys: ["lorcana-ownership-activation": key.publicKey], bundledEnvelope: signed(initial, revision: 1, key: key), now: now)
        let coordinator = LorcanaCatalogCoordinator(store: store), container = try container()
        let runtime = LorcanaGameRuntime(reviewedRegistry: registry, coordinator: coordinator, collectionWrites: true).runtime
        let runtimes = try await CardGameRuntimeContainer(runtimes: [runtime]).bound(to: container)
        let model = ScannerViewModel(gameRegistry: runtimes.registry, catalog: runtimes.makeCardCatalog(),
            unresolvedScanStore: UnresolvedScanStore(fileURL: root.appendingPathComponent("recovery.json")))
        model.start(context: container.mainContext, startCamera: false, shouldRefreshMagicDirectory: false)
        model.observeCatalogActivations([try XCTUnwrap(runtimes.runtime(for: .lorcana)?.activationSource)])
        let ready = await waitUntil { self.scannerGeneration(model) == registry.generation }
        XCTAssertTrue(ready)
        return (model, container, coordinator, key)
    }

    private func scannerGeneration(_ model: ScannerViewModel) -> String? {
        guard case let .identified(subject) = model.scanner.recognitionOutcomeForTesting(["207/204 EN 1"]) else { return nil }
        return subject.identifier.catalogGeneration
    }

    private func acquisitionCandidate(_ registry: LorcanaCatalogRegistry) async throws -> CollectionCommitCandidate {
        let identifier = try LorcanaRecognitionAdapter.identifier(
            XCTUnwrap(registry.physicalCatalog?.manifest.physicalPrintings.first?.identity.footer), generation: registry.generation)
        guard case let .resolved(resolution) = try await LorcanaCatalogAdapter(registry: registry).lookup(identifier) else {
            throw CatalogLookupError.invalidAdapterOutcome
        }
        return CollectionCommitCandidate(resolvedScan: .init(request: .init(subject: .init(identifier: identifier),
            purpose: .collection, generation: 0), card: resolution.card,
            resolved: .init(variant: .foil, resolution: .userConfirmed), identityResolution: .printedIdentifier,
            pokemonPrintRun: nil, options: [.normal, .foil], catalogRetrievedAt: now))
    }

    func testActivationWhileFinishPendingRequiresNewPrintingEvidenceBeforeSaving() async throws {
        for explicitPrinting in [false, true] {
            let root = root(); defer { try? FileManager.default.removeItem(at: root) }
            let initial = try (explicitPrinting ? manifestAddingOversized() : manifest())
            let fixture = try await activationFixture(root: root, initial: initial), model = fixture.model
            defer { model.viewDisappeared() }
            guard case let .identified(subject) = model.scanner.recognitionOutcomeForTesting(["207/204 EN 1"]) else { return XCTFail() }
            model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), subject, nil)
            if explicitPrinting {
                let choice = await waitUntil { model.pendingIdentityChoice != nil && !model.isIdentificationProcessingForTesting }
                XCTAssertTrue(choice)
                model.choose(try XCTUnwrap(model.pendingIdentityChoice?.displayCandidates.first { $0.id == self.id().uuidString.lowercased() }))
            }
            let finish = await waitUntil { model.pendingChoice != nil && !model.isIdentificationProcessingForTesting }
            XCTAssertTrue(finish)
            let next = try manifestAddingOversized(name: "Updated fixture")
            guard case let .activated(snapshot) = await fixture.coordinator.activate(try signed(next, revision: 2, key: fixture.key), now: now) else {
                return XCTFail("Fixture must be a valid protected transition")
            }
            let installed = await waitUntil { self.scannerGeneration(model) == snapshot.catalog.generation }
            XCTAssertTrue(installed)
            model.choose(.foil)
            let rejected = await waitUntil { !model.unresolvedScans.isEmpty && !model.isIdentificationProcessingForTesting }
            XCTAssertTrue(rejected)
            XCTAssertEqual(model.successCount, 0)
            let context = ModelContext(fixture.container)
            XCTAssertTrue(try context.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
            XCTAssertTrue(try context.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
            XCTAssertTrue(try context.fetch(FetchDescriptor<CollectionActivity>()).isEmpty)
            let row = try XCTUnwrap(model.unresolvedScans.first)
            XCTAssertEqual(row.reason, .noCatalogEntry); XCTAssertNil(row.pendingCommit)
            model.resolveUnresolved(id: row.id, choice: .retryLookup)
            let retried = await waitUntil { model.pendingIdentityChoice?.identifier.catalogGeneration == snapshot.catalog.generation
                && !model.isIdentificationProcessingForTesting }
            XCTAssertTrue(retried)
            model.choose(try XCTUnwrap(model.pendingIdentityChoice?.displayCandidates.first { $0.id == self.id(2).uuidString.lowercased() }))
            let newFinish = await waitUntil { model.pendingChoice != nil && !model.isIdentificationProcessingForTesting }
            XCTAssertTrue(newFinish)
            model.choose(.foil)
            let saved = await waitUntil { model.successCount == 1 }; XCTAssertTrue(saved)
            let stored = try XCTUnwrap(ModelContext(fixture.container).fetch(FetchDescriptor<CollectedCard>()).first)
            XCTAssertEqual(stored.collectionKey, "lorcana:\(id(2).uuidString.lowercased())#foil")
            XCTAssertTrue(model.unresolvedScans.isEmpty)
        }
    }

    func testActivationWhileDuplicatePendingDoesNotRestoreStaleSavePrompt() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await activationFixture(root: root, initial: manifest()), model = fixture.model
        defer { model.viewDisappeared() }
        let candidate = try await acquisitionCandidate(registry())
        model.fileUnresolvedForTesting(candidate.subject, reason: .saveFailed(inMemoryCandidateID: candidate.requestID),
            isAdditionalCopy: true, pendingCommit: candidate)
        let rowID = try XCTUnwrap(model.unresolvedScans.first?.id)
        model.resolveUnresolved(id: rowID, choice: .retrySave)
        let duplicate = await waitUntil { model.pendingDuplicateConfirmation != nil && !model.isIdentificationProcessingForTesting }
        XCTAssertTrue(duplicate)
        guard case let .activated(snapshot) = await fixture.coordinator.activate(
            try signed(manifestAddingOversized(), revision: 2, key: fixture.key), now: now) else { return XCTFail() }
        let installed = await waitUntil { self.scannerGeneration(model) == snapshot.catalog.generation }; XCTAssertTrue(installed)
        model.addAnother()
        let rejected = await waitUntil { model.unresolvedScans.first?.reason == .noCatalogEntry && !model.isIdentificationProcessingForTesting }
        XCTAssertTrue(rejected)
        XCTAssertNil(model.pendingDuplicateConfirmation)
        XCTAssertNil(model.unresolvedScans.first?.pendingCommit)
        XCTAssertEqual(model.unresolvedScans.first?.id, rowID)
        XCTAssertEqual(model.unresolvedScans.first?.isAdditionalCopy, true)
        XCTAssertTrue(try ModelContext(fixture.container).fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        model.resolveUnresolved(id: rowID, choice: .retryLookup)
        let retried = await waitUntil { model.pendingIdentityChoice != nil && !model.isIdentificationProcessingForTesting }; XCTAssertTrue(retried)
        model.choose(try XCTUnwrap(model.pendingIdentityChoice?.displayCandidates.first))
        let finish = await waitUntil { model.pendingChoice != nil && !model.isIdentificationProcessingForTesting }; XCTAssertTrue(finish)
        model.choose(.foil)
        let newDuplicate = await waitUntil { model.pendingDuplicateConfirmation != nil && !model.isIdentificationProcessingForTesting }
        XCTAssertTrue(newDuplicate)
        model.addAnother()
        let saved = await waitUntil { model.successCount == 1 }; XCTAssertTrue(saved)
        XCTAssertTrue(model.unresolvedScans.isEmpty)
    }

    func testStaleRetrySaveRequiresLookupEvenWhenOldPrintingIsAlreadyOwned() async throws {
        for additionalCopy in [false, true] {
            let root = root(); defer { try? FileManager.default.removeItem(at: root) }
            let fixture = try await activationFixture(root: root, initial: manifest()), model = fixture.model
            defer { model.viewDisappeared() }
            let candidate = try await acquisitionCandidate(registry())
            _ = try CollectionStore(context: fixture.container.mainContext).add(candidate.card, resolved: candidate.resolved)
            model.fileUnresolvedForTesting(candidate.subject, reason: .saveFailed(inMemoryCandidateID: candidate.requestID),
                isAdditionalCopy: additionalCopy, pendingCommit: candidate)
            let rowID = try XCTUnwrap(model.unresolvedScans.first?.id)
            guard case let .activated(snapshot) = await fixture.coordinator.activate(
                try signed(manifestAddingOversized(), revision: 2, key: fixture.key), now: now) else { return XCTFail() }
            let installed = await waitUntil { self.scannerGeneration(model) == snapshot.catalog.generation }; XCTAssertTrue(installed)
            model.resolveUnresolved(id: rowID, choice: .retrySave)
            let rejected = await waitUntil { model.unresolvedScans.first?.reason == .noCatalogEntry && !model.isIdentificationProcessingForTesting }
            XCTAssertTrue(rejected)
            XCTAssertEqual(model.unresolvedScans.first?.id, rowID)
            XCTAssertNil(model.unresolvedScans.first?.pendingCommit)
            XCTAssertNil(model.pendingDuplicateConfirmation)
            XCTAssertEqual(model.successCount, 0)
            XCTAssertEqual(try ModelContext(fixture.container).fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 1)
            // Even an obsolete UI action falls back to a fresh lookup after the
            // old in-memory commit is discarded.
            model.resolveUnresolved(id: rowID, choice: .retrySave)
            let retried = await waitUntil { model.pendingIdentityChoice?.identifier.catalogGeneration == snapshot.catalog.generation }
            XCTAssertTrue(retried)
        }
    }

    func testWriterRejectsActivationAfterSuccessfulAcquisitionPreflightAndRollsBackAllStaging() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let kit = try LorcanaLocalReviewKit.make(manifest: manifest(), root: root, now: now, allowCollectionWrites: true)
        let container = try container(), runtimes = try await kit.bound(to: container)
        let candidate = try await acquisitionCandidate(registry())
        try await runtimes.makeCardCatalog().validateAcquisition(candidate.identifier,
            printingID: candidate.card.physicalPrintingID, automatic: true)
        let next = try LorcanaCatalogRegistry(manifest: manifestAddingOversized(), previous: registry())
        XCTAssertTrue(CollectionStore.installCatalogAdapter(LorcanaCatalogAdapter(registry: next), revision: 2, for: container))
        let writer = ScannerCollectionWriter(modelContainer: container)
        do { _ = try await writer.containsCollectionEntry(for: candidate); XCTFail("Stale evidence cannot dismiss recovery as already owned") }
        catch CatalogLookupError.staleCatalog {}
        do { _ = try await writer.add(candidate); XCTFail("A valid UUID cannot authorize an obsolete scan") }
        catch CatalogLookupError.staleCatalog {}
        let context = ModelContext(container)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CollectionActivity>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PriceRecord>()).isEmpty)
        let identifier = try LorcanaRecognitionAdapter.identifier(
            XCTUnwrap(next.physicalCatalog?.manifest.physicalPrintings.first?.identity.footer), generation: next.generation)
        guard case let .needsPrintingChoice(_, choices) = try await LorcanaCatalogAdapter(registry: next).lookup(identifier) else { return XCTFail() }
        let resolution = try await LorcanaCatalogAdapter(registry: next).resolve(XCTUnwrap(choices.first), for: identifier)
        let current = CollectionCommitCandidate(resolvedScan: .init(request: .init(subject: .init(identifier: identifier),
            purpose: .collection, generation: 0), card: resolution.card,
            resolved: .init(variant: .foil, resolution: .userConfirmed), identityResolution: .userSelectedPrinting,
            pokemonPrintRun: nil, options: [.normal, .foil], catalogRetrievedAt: now))
        _ = try await writer.add(current)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 1)
    }

    func testCatalogRecoveryCorrectsUnknownFooterAndRevalidatesPendingSelectionAcrossActivation() async throws {
        for activateWhilePending in [false, true] {
            let root = root(); defer { try? FileManager.default.removeItem(at: root) }
            let fixture = try await activationFixture(root: root, initial: manifest()), model = fixture.model
            defer { model.viewDisappeared() }
            let original = ScanSubject(identifier: try LorcanaRecognitionAdapter.identifier(
                .init(collectorNumber: "999", denominator: "204", language: "en", printedSetMarker: "1"),
                generation: registry().generation))
            model.fileUnresolvedForTesting(original, reason: .noCatalogEntry)
            let rowID = try XCTUnwrap(model.unresolvedScans.first?.id)
            guard case let .activated(snapshot) = await fixture.coordinator.activate(
                try signed(manifestAddingOversized(), revision: 2, key: fixture.key), now: now) else { return XCTFail() }
            let installed = await waitUntil { self.scannerGeneration(model) == snapshot.catalog.generation }; XCTAssertTrue(installed)
            let browse = try XCTUnwrap(snapshot.browse), sets = try await browse.sets()
            let page = try await browse.cards(in: XCTUnwrap(sets.first), cursor: nil)
            let summary = try XCTUnwrap(page.items.first { $0.providerID == self.id(2).uuidString.lowercased() })
            let details = try await browse.details(for: summary)
            model.resolveUnresolved(id: rowID, choice: .catalog(details, printRun: nil, variant: nil))
            let finish = await waitUntil { model.pendingChoice != nil && !model.isIdentificationProcessingForTesting }; XCTAssertTrue(finish)
            XCTAssertEqual(model.pendingChoice?.request.subject, original)
            XCTAssertEqual(model.pendingChoice?.request.acquisitionIdentifier.catalogGeneration, snapshot.catalog.generation)
            if activateWhilePending {
                guard case let .activated(next) = await fixture.coordinator.activate(
                    try signed(manifestAddingOversized(name: "Updated catalog selection"), revision: 3, key: fixture.key), now: now) else { return XCTFail() }
                let updated = await waitUntil { self.scannerGeneration(model) == next.catalog.generation }; XCTAssertTrue(updated)
            }
            model.choose(.foil)
            let settled = await waitUntil { !model.isIdentificationProcessingForTesting }; XCTAssertTrue(settled)
            if activateWhilePending {
                XCTAssertEqual(model.successCount, 0)
                XCTAssertEqual(model.unresolvedScans.first?.id, rowID)
                XCTAssertNil(model.unresolvedScans.first?.pendingCommit)
                XCTAssertEqual(model.unresolvedScans.first?.subject, original)
                XCTAssertTrue(try ModelContext(fixture.container).fetch(FetchDescriptor<CollectedCard>()).isEmpty)
            } else {
                XCTAssertEqual(model.successCount, 1)
                XCTAssertEqual(model.sessionScans.first?.subject, original)
                XCTAssertEqual(try ModelContext(fixture.container).fetch(FetchDescriptor<CollectedCard>()).first?.collectionKey,
                    "lorcana:\(id(2).uuidString.lowercased())#foil")
                XCTAssertTrue(model.unresolvedScans.isEmpty)
            }
        }
    }

    func testRetrySavePreservesExplicitCatalogAcquisitionAlongsideOriginalUnknownFooter() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await activationFixture(root: root, initial: manifest()), model = fixture.model
        defer { model.viewDisappeared() }
        let known = try await acquisitionCandidate(registry())
        let original = ScanSubject(identifier: try LorcanaRecognitionAdapter.identifier(
            .init(collectorNumber: "999", denominator: "204", language: "en", printedSetMarker: "1"),
            generation: registry().generation))
        let request = ScanRequest(subject: original, purpose: .collection, generation: 0).acquiring(known.identifier)
        let candidate = CollectionCommitCandidate(resolvedScan: .init(request: request, card: known.card,
            resolved: known.resolved, identityResolution: .userSelectedPrinting, pokemonPrintRun: nil,
            options: known.options, catalogRetrievedAt: now))
        model.fileUnresolvedForTesting(original, reason: .saveFailed(inMemoryCandidateID: candidate.requestID), pendingCommit: candidate)
        let rowID = try XCTUnwrap(model.unresolvedScans.first?.id)
        model.resolveUnresolved(id: rowID, choice: .retrySave)
        let saved = await waitUntil { model.successCount == 1 }; XCTAssertTrue(saved)
        XCTAssertEqual(model.sessionScans.first?.subject, original)
        XCTAssertEqual(try ModelContext(fixture.container).fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 1)
        XCTAssertTrue(model.unresolvedScans.isEmpty)
    }

    func testReviewLaunchRequiresExactOptInAndUsesStableSyntheticIdentities() throws {
        XCTAssertFalse(LorcanaReviewLaunch.isEnabled(arguments: []))
        XCTAssertFalse(LorcanaReviewLaunch.isEnabled(arguments: ["-ui_debug_route"]))
        XCTAssertFalse(LorcanaReviewLaunch.isEnabled(arguments: ["-ui_debug_route", "Browse"]))
        XCTAssertTrue(LorcanaReviewLaunch.isEnabled(arguments: ["-ui_debug_route", "LorcanaReview"]))
        let first = try LorcanaCatalogRegistry(manifest: LorcanaReviewLaunch.fixtureManifest())
        let second = try LorcanaCatalogRegistry(manifest: LorcanaReviewLaunch.fixtureManifest(), previous: first)
        XCTAssertEqual(first.generation, second.generation)
        XCTAssertTrue(try XCTUnwrap(first.physicalCatalog).manifest.physicalPrintings.allSatisfy {
            $0.identityEvidence.allSatisfy { $0.reference.hasPrefix("synthetic-ui:") }
        })
    }

    func testReviewLaunchSamplesReachRealLookupAndFailClosedWithoutArtworkOrReview() async throws {
        let registry = try LorcanaCatalogRegistry(manifest: LorcanaReviewLaunch.fixtureManifest())
        let adapter = LorcanaCatalogAdapter(registry: registry)
        for sample in LorcanaReviewLaunch.Sample.allCases {
            guard case let .identified(subject) = LorcanaRecognitionAdapter(registry: registry)
                .identify([.init(text: sample.footerText)]) else { XCTFail(sample.rawValue); continue }
            let outcome = try await adapter.lookup(subject.identifier)
            switch (sample, outcome) {
            case (.size, .needsPrintingChoice(_, let choices)), (.stamp, .needsPrintingChoice(_, let choices)):
                XCTAssertEqual(choices.count, 2)
            case (.oversized, .needsPrintingChoice(_, let choices)):
                XCTAssertEqual(choices.count, 1)
            case (.standard, .resolved), (.landscape, .resolved),
                 (.artworkUnavailable, .catalogIncomplete), (.held, .catalogIncomplete), (.unknown, .catalogIncomplete):
                break
            default: XCTFail("Unexpected review outcome for \(sample.rawValue)")
            }
        }
    }

    func testReviewLaunchKitReopensOnlyIsolatedDiskOwnershipWithStableKeys() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let kit = try LorcanaReviewLaunch.makeKit(root: root)
        let disk = try container(url: kit.collectionDirectory.appendingPathComponent("default.store"))
        let runtimes = try await kit.bound(to: disk)
        XCTAssertEqual(runtimes.registry.games(supporting: .scan), [.lorcana])
        XCTAssertTrue(runtimes.registry.supports(.lorcana, .collectionWrite))
        XCTAssertNotNil(runtimes.runtime(for: .lorcana)?.pricing)
        XCTAssertTrue(runtimes.runtime(for: .lorcana)?.priceAuthority?.identityByPriceKey.isEmpty == true)
        let registry = try LorcanaCatalogRegistry(manifest: LorcanaReviewLaunch.fixtureManifest())
        let footer = try LorcanaPrintedIdentity(collectorNumber: "23", denominator: "204", language: "en", printedSetMarker: "1")
        let identifier = try LorcanaRecognitionAdapter.identifier(footer, generation: registry.generation)
        guard case let .resolved(result) = try await LorcanaCatalogAdapter(registry: registry).lookup(identifier) else { return XCTFail() }
        let card = result.card
        _ = try CollectionStore(context: disk.mainContext).add(card, resolved: .init(variant: .foil, resolution: .userConfirmed))
        let next = try LorcanaReviewLaunch.makeKit(root: root)
        XCTAssertNotEqual(kit.publicKey, next.publicKey)
        _ = try await next.bound(to: disk)
        let retained = try XCTUnwrap(ModelContext(disk).fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(retained.collectionKey, card.collectionKey(variant: .foil))
        let unrelated = try container(url: root.appendingPathComponent("default.store"))
        do { _ = try await next.bound(to: unrelated); XCTFail("Ordinary storage must be rejected") }
        catch LorcanaLocalReviewKit.ValidationError.nonIsolatedCollection {}
    }

    func testDebugWritesRequireAnIsolatedContainerAndStayDisabledOnUnboundRuntime() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let kit = try LorcanaLocalReviewKit.make(manifest: manifest(), root: root, now: now, allowCollectionWrites: true)
        XCTAssertFalse(kit.runtime.descriptor.capabilities.contains(.collectionWrite))
        let memory = try container(), bound = try await kit.bound(to: memory)
        XCTAssertTrue(bound.registry.supports(.lorcana, .collectionWrite))
        let unrelated = try container(url: root.appendingPathComponent("unrelated.store"))
        do { _ = try await kit.bound(to: unrelated); XCTFail() }
        catch LorcanaLocalReviewKit.ValidationError.nonIsolatedCollection {}
        XCTAssertTrue(CardGameRuntimeContainer.appDefaults().runtime(for: .lorcana)!.descriptor.capabilities.contains(.collectionWrite))
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

    func testSupersededHoldingCanReduceDeleteAndRestoreAfterReopen() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let kit = try LorcanaLocalReviewKit.make(manifest: manifest(count: 2), root: root, now: now, allowCollectionWrites: true)
        let url = kit.collectionDirectory.appendingPathComponent("collection.store")
        let original = try container(url: url)
        _ = try await kit.bound(to: original)
        let card = try LorcanaCatalogAdapter(registry: registry(count: 2)).resolution(forPrintingID: id()).card
        let store = CollectionStore(context: original.mainContext)
        _ = try store.add(card, resolved: .init(variant: .foil, resolution: .userConfirmed), quantity: 3)
        let next = try LorcanaCatalogRegistry(manifest: manifest(count: 2, supersedingFirst: true), previous: registry(count: 2))
        XCTAssertTrue(CollectionStore.installCatalogAdapter(LorcanaCatalogAdapter(registry: next), revision: 2, for: original))
        XCTAssertThrowsError(try store.add(card, resolved: .init(variant: .foil, resolution: .userConfirmed)))
        XCTAssertThrowsError(try store.setQuantity(4, forCollectionKey: card.collectionKey(variant: .foil), expectedCurrent: 3))
        XCTAssertEqual(try store.setQuantity(2, forCollectionKey: card.collectionKey(variant: .foil), expectedCurrent: 3), 2)
        let removed = try store.remove(collectionKey: card.collectionKey(variant: .foil))
        XCTAssertTrue(try ModelContext(original).fetch(FetchDescriptor<CollectedCard>()).isEmpty)

        let reopened = try container(url: url)
        _ = try await kit.bound(to: reopened)
        XCTAssertTrue(CollectionStore.installCatalogAdapter(LorcanaCatalogAdapter(registry: next), revision: 2, for: reopened))
        let recovered = CollectionStore(context: reopened.mainContext)
        try recovered.restore(removed)
        XCTAssertThrowsError(try recovered.restore(removed), "A disposal may be reversed only once")
        let rows = try ModelContext(reopened).fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.map(\.collectionKey), [card.collectionKey(variant: .foil)])
        XCTAssertEqual(rows.map(\.quantity), [2])
        XCTAssertEqual(try ModelContext(reopened).fetch(FetchDescriptor<InventoryEvent>()).reduce(0) { $0 + $1.deltaQuantity }, 2)
    }

    func testSupersededHoldingRejectsInsertedLookalikesAndChangedIdentity() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let kit = try LorcanaLocalReviewKit.make(manifest: manifest(count: 2), root: root, now: now, allowCollectionWrites: true)
        let original = try container()
        _ = try await kit.bound(to: original)
        let card = try LorcanaCatalogAdapter(registry: registry(count: 2)).resolution(forPrintingID: id()).card
        let store = CollectionStore(context: original.mainContext)
        _ = try store.add(card, resolved: .init(variant: .foil, resolution: .userConfirmed), quantity: 2)
        let next = try LorcanaCatalogRegistry(manifest: manifest(count: 2, supersedingFirst: true), previous: registry(count: 2))
        XCTAssertTrue(CollectionStore.installCatalogAdapter(LorcanaCatalogAdapter(registry: next), revision: 2, for: original))
        for attack in 0..<4 {
            let row = try XCTUnwrap(original.mainContext.fetch(FetchDescriptor<CollectedCard>()).first)
            switch attack {
            case 0:
                let lookalike = CollectedCard(collectionKey: row.collectionKey, game: .lorcana,
                    providerID: row.providerID, name: row.name, setName: row.setName, setCode: row.setCode,
                    cardNumber: row.cardNumber, rarity: nil, imageURL: nil, thumbnailURL: nil,
                    variant: .foil, variantResolution: .userConfirmed, quantity: 1)
                lookalike.catalogProviderID = row.catalogProviderID
                original.mainContext.insert(lookalike)
            case 1: row.variantID = PhysicalVariant.normal.id
            case 2: row.providerID = id(2).uuidString.lowercased()
            default: row.pokemonPrintRunRaw = PokemonPrintRun.firstEdition.rawValue
            }
            XCTAssertThrowsError(try store.validatePendingGameWrites(), "Rejected changed/fabricated identity \(attack)")
            original.mainContext.rollback()
        }
        XCTAssertEqual(try ModelContext(original).fetch(FetchDescriptor<CollectedCard>()).map(\.quantity), [2])
        XCTAssertEqual(try ModelContext(original).fetch(FetchDescriptor<InventoryEvent>()).count, 1)
    }

    func testSupersededHoldingUndoRequiresCompleteDurableInverseLineage() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let kit = try LorcanaLocalReviewKit.make(manifest: manifest(count: 2), root: root, now: now, allowCollectionWrites: true)
        let original = try container()
        _ = try await kit.bound(to: original)
        let card = try LorcanaCatalogAdapter(registry: registry(count: 2)).resolution(forPrintingID: id()).card
        let store = CollectionStore(context: original.mainContext)
        var mutation = try store.add(card, resolved: .init(variant: .normal, resolution: .userConfirmed))
        for (from, to) in [(PhysicalVariant.normal, PhysicalVariant.foil), (.foil, .normal)] {
            mutation = try XCTUnwrap(store.recordVariantCorrection(for: card, from: from,
                to: .init(variant: to, resolution: .userConfirmed), previousCollectionKey: mutation.collectionKey,
                previousLedgerOperationIDs: mutation.ledgerOperationIDs, activityID: mutation.activityID))
        }
        let next = try LorcanaCatalogRegistry(manifest: manifest(count: 2, supersedingFirst: true), previous: registry(count: 2))
        XCTAssertTrue(CollectionStore.installCatalogAdapter(LorcanaCatalogAdapter(registry: next), revision: 2, for: original))
        try store.undo(mutation, savesChanges: false)
        let inverse = try XCTUnwrap(original.mainContext.insertedModelsArray.compactMap { $0 as? InventoryEvent }.first)
        inverse.reversesEventID = UUID()
        XCTAssertThrowsError(try store.validatePendingGameWrites())
        original.mainContext.rollback()
        try store.undo(mutation)
        XCTAssertThrowsError(try store.undo(mutation))
        XCTAssertTrue(try ModelContext(original).fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertEqual(try ModelContext(original).fetch(FetchDescriptor<InventoryEvent>()).reduce(0) { $0 + $1.deltaQuantity }, 0)
    }

    func testSupersededHoldingRestoreRejectsForgedInverseAndDuplicateRows() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let kit = try LorcanaLocalReviewKit.make(manifest: manifest(count: 2), root: root, now: now, allowCollectionWrites: true)
        let original = try container()
        _ = try await kit.bound(to: original)
        let card = try LorcanaCatalogAdapter(registry: registry(count: 2)).resolution(forPrintingID: id()).card
        let store = CollectionStore(context: original.mainContext)
        _ = try store.add(card, resolved: .init(variant: .foil, resolution: .userConfirmed), quantity: 2)
        let removed = try store.remove(collectionKey: card.collectionKey(variant: .foil))
        let next = try LorcanaCatalogRegistry(manifest: manifest(count: 2, supersedingFirst: true), previous: registry(count: 2))
        XCTAssertTrue(CollectionStore.installCatalogAdapter(LorcanaCatalogAdapter(registry: next), revision: 2, for: original))
        for duplicateRow in [false, true] {
            let forged = CollectionStore(context: original.mainContext, beforeSaveForTesting: { context in
                if duplicateRow {
                    let row = try XCTUnwrap(context.fetch(FetchDescriptor<CollectedCard>()).first)
                    let lookalike = CollectedCard(collectionKey: row.collectionKey, game: .lorcana,
                        providerID: row.providerID, name: row.name, setName: row.setName, setCode: row.setCode,
                        cardNumber: row.cardNumber, rarity: nil, imageURL: nil, thumbnailURL: nil,
                        variant: .foil, variantResolution: .userConfirmed, quantity: 2)
                    lookalike.catalogProviderID = row.catalogProviderID
                    context.insert(lookalike)
                } else {
                    let inverse = try XCTUnwrap(context.insertedModelsArray.compactMap { $0 as? InventoryEvent }.first)
                    inverse.reversesEventID = UUID()
                }
                XCTAssertThrowsError(try CollectionStore(context: context).validatePendingGameWrites())
                throw CocoaError(.fileWriteUnknown)
            })
            XCTAssertThrowsError(try forged.restore(removed))
            XCTAssertTrue(try ModelContext(original).fetch(FetchDescriptor<CollectedCard>()).isEmpty)
            XCTAssertEqual(try ModelContext(original).fetch(FetchDescriptor<InventoryEvent>()).count, 2)
        }
        try store.restore(removed)
        XCTAssertEqual(try ModelContext(original).fetch(FetchDescriptor<CollectedCard>()).map(\.quantity), [2])
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

    func testBundledNormalFoilQuantitiesUndoAndCSVReplaySurviveRelaunch() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("collection.store")
        let original = try container(url: url)
        _ = try await CardGameRuntimeContainer.appDefaults().bound(to: original)
        let catalog = try LorcanaDiscoveryCatalog.bundledMarket.get()
        let printing = try XCTUnwrap(catalog.registry.physicalCatalog?.manifest.physicalPrintings.first {
            $0.identity.footer.printedSetMarker == "1" && $0.identity.footer.collectorNumber == "1"
        })
        let card = try LorcanaCatalogAdapter(registry: catalog.registry).resolution(forPrintingID: printing.id).card
        let store = CollectionStore(context: original.mainContext)
        _ = try store.add(card, resolved: .init(variant: .normal, resolution: .userConfirmed), quantity: 2)
        _ = try store.add(card, resolved: .init(variant: .foil, resolution: .userConfirmed), quantity: 3)
        let duplicate = try store.add(card, resolved: .init(variant: .normal, resolution: .userConfirmed))
        try store.undo(duplicate)
        let foil = try XCTUnwrap(original.mainContext.fetch(FetchDescriptor<CollectedCard>()).first { $0.variantID == "foil" })
        XCTAssertEqual(try store.setQuantity(7, for: foil), 7)
        XCTAssertThrowsError(try store.setQuantity(9, forCollectionKey: foil.collectionKey, expectedCurrent: 3))
        XCTAssertEqual(foil.quantity, 7)
        XCTAssertThrowsError(try store.add(card, resolved: .init(variant: .reverse, resolution: .userConfirmed)))
        let prices = PriceStore(context: original.mainContext)
        let entered = PriceLookup.price(.init(unitMarketPriceUSD: 22, currencyCode: "USD", source: .importedCSV,
            sourceVariantID: "owner-entered", sourceUpdatedAt: nil, fetchedAt: .now))
        XCTAssertTrue(prices.store(entered, game: .lorcana, printingID: card.physicalPrintingID, variantID: "normal"))
        XCTAssertTrue(prices.save())

        let reopened = try container(url: url)
        let rows = try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: rows.map { ($0.variantID!, $0.quantity) }), ["normal": 2, "foil": 7])
        XCTAssertEqual(Set(rows.map(\.catalogProviderID)), [card.physicalPrintingID])
        XCTAssertEqual(PriceStore(context: reopened.mainContext).record(forKey:
            PriceRecord.key(game: .lorcana, printingID: card.physicalPrintingID, variantID: "normal"))?.effectiveUnitMarketPriceUSD, 22)

        let csv = try await CollectionCSV.exportIsolated(from: reopened)
        let plan = try CollectionCSV.parse(Data(csv.text.utf8))
        let target = try container()
        let bound = try await CardGameRuntimeContainer.appDefaults().bound(to: target)
        let result = try await apply(plan, to: target, runtimes: bound)
        XCTAssertTrue(result.failedRows.isEmpty)
        XCTAssertEqual(result.importedQuantity, 9)
        let repeated = try await apply(plan, to: target, runtimes: bound)
        XCTAssertEqual(repeated.importedQuantity, 0)
        let imported = try ModelContext(target).fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: imported.map { ($0.collectionKey, $0.quantity) }),
            Dictionary(uniqueKeysWithValues: rows.map { ($0.collectionKey, $0.quantity) }))
        // CSV is an inventory transfer, not a backup of separate price records.
        XCTAssertTrue(try ModelContext(target).fetch(FetchDescriptor<PriceRecord>()).isEmpty)
    }

    func testFailedCSVRowCanBeCorrectedAndRetriedWithoutDuplicatingCommittedCopies() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let kit = try LorcanaLocalReviewKit.make(manifest: manifest(count: 2), root: directory, now: now, allowCollectionWrites: true)
        let host = try container(), bound = try await kit.bound(to: host)
        let input = CollectionCSV.exportFailedEntries([try entry(1), try entry(99)])
        let first = try await apply(CollectionCSV.parse(Data(input.text.utf8)), to: host, runtimes: bound)
        XCTAssertEqual(first.importedQuantity, 1)
        XCTAssertEqual(first.failedRows.count, 1)
        XCTAssertEqual(try ModelContext(host).fetch(FetchDescriptor<CollectedCard>()).count, 1)
        let failed = CollectionCSV.exportFailedEntries(first.failedEntries)
        let corrected = failed.text.replacingOccurrences(of: id(99).uuidString.lowercased(), with: id(2).uuidString.lowercased())
        let plan = try CollectionCSV.parse(Data(corrected.utf8))
        let recovered = try await apply(plan, to: host, runtimes: bound)
        XCTAssertEqual(recovered.importedQuantity, 1)
        XCTAssertTrue(recovered.failedRows.isEmpty)
        let repeated = try await apply(plan, to: host, runtimes: bound)
        XCTAssertEqual(repeated.importedQuantity, 0)
        XCTAssertEqual(repeated.alreadyImportedEntries, 1)
        let rows = try ModelContext(host).fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.quantity }, 2)
        XCTAssertEqual(Set(rows.map(\.collectionKey)), Set([id(1), id(2)].map { "lorcana:\($0.uuidString.lowercased())#foil" }))
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
