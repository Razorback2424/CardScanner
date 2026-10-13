import CryptoKit
import Foundation
import SwiftData
import XCTest
@testable import TradingCardScanner

/// Cryptographic and runtime fixtures; the review references are synthetic.
@MainActor
final class LorcanaCatalogActivationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let keyID = "lorcana-activation-fixture"
    private let key = Curve25519.Signing.PrivateKey()
    private let canonicalID = UUID(uuidString: "80000000-0000-0000-0000-000000000001")!
    private let printingID = UUID(uuidString: "90000000-0000-0000-0000-000000000001")!
    private let secondID = UUID(uuidString: "90000000-0000-0000-0000-000000000002")!
    private var keys: [String: Curve25519.Signing.PublicKey] { [keyID: key.publicKey] }
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("LorcanaActivation-\(UUID())") }

    private func release(_ revision: Int = 1, name: String = "Fixture Elsa", two: Bool = false) throws -> LorcanaCatalogRelease {
        let footer = try LorcanaPrintedIdentity(collectorNumber: "207", denominator: "204", language: "en", printedSetMarker: "1")
        let alias = LorcanaSourceAlias(provider: "fixture", id: "family")
        let family = LorcanaPrintFamily(footer: footer, providerSetCode: "TFC", name: name, version: nil,
            rarity: "fixture", layout: "normal", sourceAliases: [alias], footerEvidenceReference: "fixture:footer")
        let records = [printingID] + (two ? [secondID] : [])
        let printings = records.map { id in
            LorcanaPhysicalPrinting(id: id, identity: .init(canonicalCardID: canonicalID, footer: footer,
                artworkID: UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!, distributionID: "booster",
                stamp: nil, size: id == printingID ? .standard : .oversized, layout: "normal"),
                providerSetCode: "TFC", setName: "Fixture First Chapter", artworkLabel: "Fixture artwork",
                distributionLabel: "Fixture Booster", imageURL: nil, status: .verified,
                identityEvidence: LorcanaPhysicalEvidenceKind.allCases.map { .init(kind: $0, reference: "fixture:\($0.rawValue)") },
                finishes: [.init(finish: .normal, evidenceReferences: ["fixture:normal"]),
                           .init(finish: .foil, evidenceReferences: ["fixture:foil"])],
                finishUniverseEvidenceReference: "fixture:finishes", sourceAliases: [alias])
        }
        let manifest = LorcanaPhysicalCatalogManifest(schemaVersion: 2, reviewedAt: now.addingTimeInterval(-1),
            printFamilies: [family], canonicalCards: [.init(id: canonicalID, name: name, version: nil,
                relationshipEvidenceReferences: ["fixture:canonical"])], physicalPrintings: printings,
            universes: [.init(footer: footer, printingIDs: records, isComplete: true, evidenceReference: "fixture:universe")], corrections: [])
        return .init(schemaVersion: 1, gameID: "lorcana", revision: revision, generatedAt: now, catalog: manifest)
    }
    private func sign(_ release: LorcanaCatalogRelease) throws -> LorcanaCatalogReleaseEnvelope {
        try LorcanaCatalogSignature.sign(release, keyID: keyID, privateKey: key)
    }
    private func rawEnvelope(_ bytes: Data) throws -> LorcanaCatalogReleaseEnvelope {
        func encode(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        return .init(keyID: keyID, payload: encode(bytes), signature: encode(try key.signature(for: bytes)))
    }
    private func mutate(_ release: LorcanaCatalogRelease, _ change: (inout [String: Any]) -> Void) throws -> LorcanaCatalogRelease {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(release)) as! [String: Any]
        change(&object)
        return try JSONDecoder().decode(LorcanaCatalogRelease.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func store(_ root: URL, seed: LorcanaCatalogReleaseEnvelope? = nil,
                       fault: LorcanaWriteFault? = nil) throws -> LorcanaCatalogReleaseStore {
        try .init(root: root, keys: keys, bundledEnvelope: seed, now: now, writeData: { bytes, url in
            if let fault { try fault.write(bytes, url) } else { try bytes.write(to: url, options: .atomic) }
        })
    }
    private func identifier(_ snapshot: GameCatalogSnapshot) throws -> ScanIdentifier {
        guard case let .identified(subject) = snapshot.recognizer.identify([.init(text: "207/204 EN 1")]) else {
            throw CatalogLookupError.invalidAdapterOutcome
        }
        return subject.identifier
    }
    private func snapshot(_ coordinator: LorcanaCatalogCoordinator) async throws -> GameCatalogSnapshot {
        let value = await coordinator.currentSnapshot()
        return try XCTUnwrap(value)
    }
    private func container() throws -> ModelContainer {
        let schema = Schema([CollectedCard.self, PriceRecord.self, CollectionActivity.self, InventoryEvent.self,
                             ReferenceQuote.self, PriceObservation.self, PriceCheckDay.self])
        return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    private func waitUntil(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return predicate()
    }

    func testSignatureRoundTripPinsPhysicalRegistryAndCanonicalBytes() throws {
        let release = try release(), envelope = try sign(release)
        let verified = try LorcanaCatalogSignature.verify(envelope, trustedKeys: keys, now: now)
        XCTAssertEqual(verified.release.revision, 1)
        XCTAssertEqual(verified.payloadFingerprint.count, 64)
        XCTAssertEqual(verified.registry.generation, try LorcanaCatalogRegistry(manifest: release.catalog).generation)
        let resigned = try sign(verified.release)
        XCTAssertEqual(envelope.keyID, resigned.keyID)
        XCTAssertEqual(envelope.payload, resigned.payload)
        XCTAssertEqual(verified.payloadFingerprint,
            try LorcanaCatalogSignature.verify(resigned, trustedKeys: keys, now: now).payloadFingerprint)
    }

    func testCanonicalBytesIgnoreOrderButRetainMetadata() throws {
        let original = try release(two: true)
        let reversed = try mutate(original) { object in
            var catalog = object["catalog"] as! [String: Any]
            catalog["physicalPrintings"] = Array((catalog["physicalPrintings"] as! [[String: Any]]).reversed())
            object["catalog"] = catalog
        }
        XCTAssertEqual(try original.canonicalData(), try reversed.canonicalData())
        XCTAssertNotEqual(try original.canonicalData(), try release(name: "Corrected fixture", two: true).canonicalData())
    }

    func testTrustRejectsForeignNamespacesDuplicateAndForbiddenKeyMaterial() throws {
        for pins in [["one-piece-fixture": key.publicKey], [keyID: key.publicKey, "lorcana-second": key.publicKey], [:]] {
            XCTAssertThrowsError(try LorcanaCatalogSignature.validateTrust(pins))
        }
        XCTAssertThrowsError(try LorcanaCatalogSignature.validateTrust(keys, forbiddenPublicKeys: [key.publicKey.rawRepresentation]))
        XCTAssertThrowsError(try LorcanaCatalogSignature.sign(release(), keyID: "lorcana-", privateKey: key))
    }

    func testUnknownKeyMalformedEncodingAndTamperedSignatureReject() throws {
        let envelope = try sign(release())
        let unknown = LorcanaCatalogReleaseEnvelope(keyID: "lorcana-unknown", payload: envelope.payload, signature: envelope.signature)
        XCTAssertThrowsError(try LorcanaCatalogSignature.verify(unknown, trustedKeys: keys, now: now))
        let padded = LorcanaCatalogReleaseEnvelope(keyID: keyID, payload: envelope.payload + "=", signature: envelope.signature)
        XCTAssertThrowsError(try LorcanaCatalogSignature.verify(padded, trustedKeys: keys, now: now))
        let forged = LorcanaCatalogReleaseEnvelope(keyID: keyID, payload: envelope.payload, signature: String(repeating: "A", count: 86))
        XCTAssertThrowsError(try LorcanaCatalogSignature.verify(forged, trustedKeys: keys, now: now)) { error in
            XCTAssertEqual(error as? LorcanaCatalogSignatureError, .invalidSignature)
        }
    }

    func testValidSignatureCannotAuthorizeWrongSchemaGameRevisionOrFutureDate() throws {
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["schemaVersion"] = 99 }, { $0["gameID"] = "one_piece" }, { $0["revision"] = 0 },
            { object in var catalog = object["catalog"] as! [String: Any]; catalog["schemaVersion"] = 1; object["catalog"] = catalog }
        ]
        for change in changes {
            let altered = try mutate(release(), change)
            let envelope = try rawEnvelope(JSONEncoder().encode(altered))
            XCTAssertThrowsError(try LorcanaCatalogSignature.verify(envelope, trustedKeys: keys, now: now))
        }
        let future = try mutate(release()) { $0["generatedAt"] = now.addingTimeInterval(301).timeIntervalSinceReferenceDate }
        XCTAssertThrowsError(try LorcanaCatalogSignature.verify(rawEnvelope(future.canonicalData()), trustedKeys: keys, now: now)) { error in
            XCTAssertEqual(error as? LorcanaCatalogSignatureError, .futureRelease)
        }
    }

    func testNoncanonicalAndUnknownFieldsRejectEvenWithValidSignature() throws {
        let canonical = try release().canonicalData()
        let whitespace = Data(" ".utf8) + canonical
        XCTAssertThrowsError(try LorcanaCatalogSignature.verify(rawEnvelope(whitespace), trustedKeys: keys, now: now))
        var object = try JSONSerialization.jsonObject(with: canonical) as! [String: Any]
        object["unreviewedFutureAuthority"] = true
        let unknown = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        XCTAssertThrowsError(try LorcanaCatalogSignature.verify(rawEnvelope(unknown), trustedKeys: keys, now: now))
    }

    func testEncodedPayloadBoundRejectsBeforeAllocationOrJSONDecode() throws {
        let envelope = LorcanaCatalogReleaseEnvelope(keyID: keyID,
            payload: String(repeating: "A", count: LorcanaCatalogSignature.maximumPayloadBytes * 4 / 3 + 4),
            signature: String(repeating: "A", count: 86))
        XCTAssertThrowsError(try LorcanaCatalogSignature.verify(envelope, trustedKeys: keys, now: now)) { error in
            XCTAssertEqual(error as? LorcanaCatalogSignatureError, .oversizedPayload)
        }
    }

    func testRollbackCollisionAndIdenticalRevisionPolicy() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let seed = try sign(release()), store = try store(root, seed: seed)
        let repeated = try await store.activate(seed, now: now)
        XCTAssertEqual(repeated, .alreadyCurrent)
        let resigned = try await store.activate(sign(release()), now: now)
        XCTAssertEqual(resigned, .alreadyCurrent)
        _ = try await store.activate(sign(release(2)), now: now)
        do { _ = try await store.activate(seed, now: now); XCTFail() } catch SignedCatalogStoreError.revisionRollback {}
        do { _ = try await store.activate(sign(release(2, name: "Changed")), now: now); XCTFail() }
        catch SignedCatalogStoreError.revisionCollision {}
        let revision = await store.activeRevision
        XCTAssertEqual(revision, 2)
    }

    func testSignedTransitionCannotReuseUUIDOrRemoveFinishEvidence() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try store(root, seed: sign(release()))
        let changes: [(inout [String: Any]) -> Void] = [
            { record in var identity = record["identity"] as! [String: Any]; identity["stamp"] = "New stamp"; record["identity"] = identity },
            { $0["finishes"] = [($0["finishes"] as! [[String: Any]])[0]] },
            { record in var finishes = record["finishes"] as! [[String: Any]]; finishes[0]["evidenceReferences"] = ["fixture:replacement-proof"]; record["finishes"] = finishes },
            { $0["identityEvidence"] = LorcanaPhysicalEvidenceKind.allCases.map { ["kind": $0.rawValue, "reference": "fixture:new-proof"] } }
        ]
        for change in changes {
            let altered = try mutate(release(2)) { object in
                var catalog = object["catalog"] as! [String: Any]
                var records = catalog["physicalPrintings"] as! [[String: Any]]
                change(&records[0]); catalog["physicalPrintings"] = records; object["catalog"] = catalog
            }
            do { _ = try await store.activate(sign(altered), now: now); XCTFail() }
            catch LorcanaPhysicalCatalog.ValidationError.invalidTransition {}
        }
        let revision = await store.activeRevision
        XCTAssertEqual(revision, 1)
    }

    func testExplicitSupersessionRetainsOldUUIDAndWithdrawsItsAuthority() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try store(root, seed: sign(release()))
        let corrected = try mutate(release(2)) { object in
            var catalog = object["catalog"] as! [String: Any]
            var old = (catalog["physicalPrintings"] as! [[String: Any]])[0], next = old
            old["status"] = "superseded"; next["id"] = secondID.uuidString
            var identity = next["identity"] as! [String: Any]; identity["stamp"] = "Corrected stamp"; next["identity"] = identity
            next["finishes"] = [(next["finishes"] as! [[String: Any]])[0]]
            catalog["physicalPrintings"] = [old, next]
            var universe = (catalog["universes"] as! [[String: Any]])[0]; universe["printingIDs"] = [secondID.uuidString]
            catalog["universes"] = [universe]
            catalog["corrections"] = [["id": UUID().uuidString, "fromPrintingIDs": [printingID.uuidString],
                "toPrintingIDs": [secondID.uuidString], "evidenceReferences": ["fixture:reviewed-correction"]]]
            object["catalog"] = catalog
        }
        _ = try await store.activate(sign(corrected), now: now)
        let active = await store.activeRelease
        let registry = try XCTUnwrap(active?.registry)
        XCTAssertNotNil(registry.physicalCatalog?.printingByID[printingID])
        XCTAssertThrowsError(try LorcanaCatalogAdapter(registry: registry).validateVariantCorrection(
            printingID: printingID.uuidString.lowercased(), variantID: "normal"))
        try LorcanaCatalogAdapter(registry: registry).validateVariantCorrection(printingID: secondID.uuidString.lowercased(), variantID: "normal")
    }

    func testDurableRotationReloadsExactVerifiedHead() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try store(root)
        let first = try sign(release()), second = try sign(release(2, name: "Corrected fixture"))
        _ = try await store.activate(first, now: now); _ = try await store.activate(second, now: now)
        let previous = try JSONDecoder().decode(LorcanaCatalogReleaseEnvelope.self,
            from: Data(contentsOf: root.appendingPathComponent(LorcanaCatalogReleaseStore.Slot.previous.rawValue)))
        XCTAssertEqual(previous, first)
        let fresh = try self.store(root); await fresh.load(now: now)
        let active = await fresh.activeRelease
        XCTAssertEqual(active?.envelope, second)
    }

    func testCorruptCurrentRecoversPreviousThenSeedOffline() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let seed = try sign(release()), store = try store(root, seed: seed)
        _ = try await store.activate(sign(release(2)), now: now); _ = try await store.activate(sign(release(3)), now: now)
        try Data("broken".utf8).write(to: root.appendingPathComponent(LorcanaCatalogReleaseStore.Slot.current.rawValue))
        let recovered = try self.store(root, seed: seed); await recovered.load(now: now)
        let previousRevision = await recovered.activeRevision
        XCTAssertEqual(previousRevision, 2)
        try Data("broken".utf8).write(to: root.appendingPathComponent(LorcanaCatalogReleaseStore.Slot.previous.rawValue))
        let fallback = try self.store(root, seed: seed); await fallback.load(now: now)
        let fallbackRevision = await fallback.activeRevision
        XCTAssertEqual(fallbackRevision, 1)
    }

    func testRecoveryRejectsSignedRollbackCollisionAndIdentityRewrite() async throws {
        let candidates = [try release(), try release(2, name: "Same revision collision"),
            try mutate(release(3)) { object in
                var catalog = object["catalog"] as! [String: Any], records = catalog["physicalPrintings"] as! [[String: Any]]
                var identity = records[0]["identity"] as! [String: Any]; identity["stamp"] = "UUID rewrite"
                records[0]["identity"] = identity; catalog["physicalPrintings"] = records; object["catalog"] = catalog
            }]
        for candidate in candidates {
            let root = root(); defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try JSONEncoder().encode(sign(release(2))).write(to: root.appendingPathComponent(LorcanaCatalogReleaseStore.Slot.previous.rawValue))
            try JSONEncoder().encode(sign(candidate)).write(to: root.appendingPathComponent(LorcanaCatalogReleaseStore.Slot.current.rawValue))
            let fresh = try store(root); await fresh.load(now: now)
            let revision = await fresh.activeRevision
            XCTAssertEqual(revision, 2)
        }
    }

    func testInterruptedCurrentAndBackupWritesRetainPublishedHead() async throws {
        for slot in [LorcanaCatalogReleaseStore.Slot.current, .previous] {
            let root = root(); defer { try? FileManager.default.removeItem(at: root) }
            let fault = LorcanaWriteFault(), store = try store(root, fault: fault)
            let coordinator = LorcanaCatalogCoordinator(store: store)
            guard case .activated = await coordinator.activate(try sign(release()), now: now) else { return XCTFail() }
            fault.fail(slot.rawValue)
            guard case .rejected = await coordinator.activate(try sign(release(2)), now: now) else { return XCTFail() }
            let current = try await snapshot(coordinator)
            XCTAssertEqual(current.revision, 1)
            let fresh = try self.store(root); await fresh.load(now: now)
            let revision = await fresh.activeRevision
            XCTAssertEqual(revision, 1)
        }
    }

    func testWriterErrorAfterCommitReconcilesExactBytes() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let fault = LorcanaWriteFault(), store = try store(root, fault: fault)
        fault.fail(LorcanaCatalogReleaseStore.Slot.current.rawValue, afterCommit: true)
        let result = try await store.activate(sign(release()), now: now)
        XCTAssertEqual(result, .activated(revision: 1, previousRevision: nil))
        let fresh = try self.store(root); await fresh.load(now: now)
        let revision = await fresh.activeRevision
        XCTAssertEqual(revision, 1)
    }

    func testConcurrentActivationsPublishOnlyMonotonicDurableHead() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = LorcanaCatalogCoordinator(store: try store(root, seed: sign(release())))
        let second = try sign(release(2)), third = try sign(release(3, name: "Newest fixture"))
        async let low = coordinator.activate(second, now: now)
        async let high = coordinator.activate(third, now: now)
        _ = await (low, high)
        let current = try await snapshot(coordinator)
        XCTAssertEqual(current.revision, 3)
        let fresh = try store(root); await fresh.load(now: now)
        let revision = await fresh.activeRevision
        XCTAssertEqual(revision, 3)
    }

    func testValidationOnlyDoesNotActivateAndRejectionsResetConditionals() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let client = LorcanaTestUpdateClient(envelope: try sign(release(2)))
        let coordinator = LorcanaCatalogCoordinator(store: try store(root, seed: sign(release())), client: client, mode: .validationOnly)
        guard case .validated(2) = await coordinator.refresh(now: now) else { return XCTFail() }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let original = try await snapshot(coordinator)
        XCTAssertEqual(original.revision, 1)
        let bad = LorcanaCatalogReleaseEnvelope(keyID: keyID, payload: "bad", signature: "bad")
        await client.update(bad)
        guard case .rejected = await coordinator.refresh(now: now) else { return XCTFail() }
        let resets = await client.resets
        XCTAssertEqual(resets, 1)
    }

    func testRemoteRefreshCoalescesAndLaunchRefreshRunsOnce() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let client = LorcanaTestUpdateClient(envelope: try sign(release(2)))
        let coordinator = LorcanaCatalogCoordinator(store: try store(root, seed: sign(release())), client: client, mode: .authority)
        async let first = coordinator.refresh(now: now)
        async let second = coordinator.refresh(now: now)
        _ = await (first, second)
        let count = await client.fetches
        XCTAssertEqual(count, 1)
        await coordinator.refreshAtLaunch(); await coordinator.refreshAtLaunch()
        let launchCount = await client.fetches
        XCTAssertEqual(launchCount, 2)
        let disabled = LorcanaCatalogCoordinator(store: try store(root), client: client)
        guard case .disabled = await disabled.refresh(now: now) else { return XCTFail() }
    }

    func testMetadataOnlyActivationPublishesCoherentImmutableSnapshotAndStalesChoices() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = LorcanaCatalogCoordinator(store: try store(root, seed: sign(release(two: true))))
        let initial = try await snapshot(coordinator), oldIdentifier = try identifier(initial)
        guard case let .needsPrintingChoice(_, choices) = try await initial.catalog.lookup(oldIdentifier) else { return XCTFail() }
        let stream = await coordinator.activationSnapshots(); var iterator = stream.makeAsyncIterator()
        guard case .activated = await coordinator.activate(try sign(release(2, name: "Corrected fixture", two: true)), now: now) else { return XCTFail() }
        let event = await iterator.next(), next = try XCTUnwrap(event), rebased = try next.catalog.identifierForRetry(oldIdentifier)
        XCTAssertNotEqual(next.catalog.generation, initial.catalog.generation)
        XCTAssertEqual(try identifier(next).catalogGeneration, next.catalog.generation)
        XCTAssertEqual(rebased.fields, oldIdentifier.fields)
        XCTAssertEqual(next.variantPolicy.selectableVariants, initial.variantPolicy.selectableVariants)
        XCTAssertEqual(choices[0].catalogGeneration, initial.catalog.generation)
        do { _ = try await next.catalog.resolve(choices[0], for: rebased); XCTFail() } catch CatalogLookupError.invalidPrintingChoice {}
        let oldResolution = try await initial.catalog.resolve(choices[0], for: oldIdentifier)
        XCTAssertTrue(oldResolution.card.name.hasPrefix("Fixture Elsa"))
        XCTAssertFalse(oldResolution.card.name.contains("Corrected fixture"))
    }

    func testContainerBindingRebindAndRetiredSessionProtectCollectionAuthority() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let registry = try LorcanaCatalogRegistry(manifest: release().catalog)
        let coordinator = LorcanaCatalogCoordinator(store: try store(root, seed: sign(release())))
        let raw = try CardGameRuntimeContainer(runtimes: [LorcanaGameRuntime(registry: registry, coordinator: coordinator).runtime])
        let container = try container(), session = LorcanaTestSession()
        let bound = try await raw.bound(to: container, isCurrent: { session.isCurrent })
        let source = try XCTUnwrap(bound.runtime(for: .lorcana)?.activationSource)
        let first = await source.currentSnapshot()
        XCTAssertEqual(first?.revision, 1)
        guard case .activated = await coordinator.activate(try sign(release(2, name: "Corrected fixture")), now: now) else { return XCTFail() }
        let updated = await source.currentSnapshot()
        XCTAssertEqual(updated?.revision, 2)
        let rebound = try await raw.bound(to: container), reboundSource = try XCTUnwrap(rebound.runtime(for: .lorcana)?.activationSource)
        let reboundSnapshot = await reboundSource.currentSnapshot()
        XCTAssertEqual(reboundSnapshot?.catalog.generation, updated?.catalog.generation)
        XCTAssertFalse(CollectionStore.canInstallCatalogAdapter(LorcanaCatalogAdapter(registry: registry), revision: 1, for: container))
        session.isCurrent = false
        guard case .activated = await coordinator.activate(try sign(release(3)), now: now) else { return XCTFail() }
        let retired = await source.currentSnapshot()
        XCTAssertNil(retired)
        // The retired container retains revision 2; a replacement installs 3.
        XCTAssertTrue(CollectionStore.canInstallCatalogAdapter(updated!.catalog, revision: 2, for: container))
        let replacement = try self.container(), fresh = try await raw.bound(to: replacement)
        let freshSource = try XCTUnwrap(fresh.runtime(for: .lorcana)?.activationSource), freshSnapshot = await freshSource.currentSnapshot()
        XCTAssertEqual(freshSnapshot?.revision, 3)
    }

    func testBoundBrowseAndImportFollowTheSameActivatedPhysicalGeneration() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let registry = try LorcanaCatalogRegistry(manifest: release(two: true).catalog)
        let coordinator = LorcanaCatalogCoordinator(store: try store(root, seed: sign(release(two: true))))
        let raw = try CardGameRuntimeContainer(runtimes: [LorcanaGameRuntime(registry: registry, coordinator: coordinator).runtime])
        let container = try container(), bound = try await raw.bound(to: container)
        let browse = bound.makeBrowseCatalog(), sets = try await browse.sets(for: .lorcana)
        let oldPage = try await browse.cards(in: XCTUnwrap(sets.first), cursor: nil)
        let old = try XCTUnwrap(oldPage.items.first)
        _ = try await browse.details(for: old)
        guard case let .activated(next) = await coordinator.activate(try sign(release(2, name: "Corrected fixture", two: true)), now: now) else { return XCTFail() }
        let nextSets = try await browse.sets(for: .lorcana)
        let page = try await browse.cards(in: XCTUnwrap(nextSets.first), cursor: nil)
        XCTAssertTrue(page.items.allSatisfy { $0.catalogGeneration == next.catalog.generation && $0.name.hasPrefix("Corrected fixture") })
        do { _ = try await browse.details(for: old); XCTFail() } catch CatalogLookupError.staleCatalog {}
        let imports = await bound.currentImportAdapters()
        XCTAssertEqual(imports.adapter(for: .lorcana)?.generation, next.catalog.generation)
        XCTAssertEqual(next.browse?.generation, next.catalog.generation)
        XCTAssertEqual(next.importer?.generation, next.catalog.generation)
        XCTAssertEqual(Set(page.items.map(\.providerID)), Set(oldPage.items.map(\.providerID)))
    }

    func testActivationRejectsInFlightOldGenerationCompletion() async throws {
        let first = try LorcanaCatalogRegistry(manifest: release().catalog)
        let next = try LorcanaCatalogRegistry(manifest: release(2, name: "Corrected fixture").catalog)
        let snapshot = GameCatalogSnapshot(revision: 1, catalog: LorcanaCatalogAdapter(registry: first),
            recognizer: LorcanaRecognitionAdapter(registry: first), variantPolicy: LorcanaVariantPolicy(registry: first))
        let gate = LorcanaLookupGate()
        let catalog = CardCatalog(gameCatalogAdapters: try .init(adapters: [LorcanaDelayedAdapter(base: .init(registry: first), gate: gate)]))
        let scan = try identifier(snapshot), lookup = Task { try await catalog.lookupOutcome(for: scan) }
        await gate.waitForStart()
        await catalog.install(LorcanaCatalogAdapter(registry: next)); await gate.resume()
        do { _ = try await lookup.value; XCTFail() } catch CatalogLookupError.staleCatalog {}
    }

    func testBoundActivationReachesScannerAndRecoveryRetryReopensPhysicalChoice() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let registry = try LorcanaCatalogRegistry(manifest: release(two: true).catalog)
        let coordinator = LorcanaCatalogCoordinator(store: try store(root, seed: sign(release(two: true))))
        let raw = try CardGameRuntimeContainer(runtimes: [LorcanaGameRuntime(registry: registry, coordinator: coordinator).runtime])
        let container = try container(), bound = try await raw.bound(to: container)
        let source = try XCTUnwrap(bound.runtime(for: .lorcana)?.activationSource)
        let model = ScannerViewModel(gameRegistry: bound.registry, catalog: bound.makeCardCatalog(),
            unresolvedScanStore: UnresolvedScanStore(fileURL: root.appendingPathComponent("recovery.json")))
        model.start(context: container.mainContext, startCamera: false, shouldRefreshMagicDirectory: false)
        defer { model.viewDisappeared() }
        model.observeCatalogActivations([source])
        func scannerGeneration() -> String? {
            guard case let .identified(subject) = model.scanner.recognitionOutcomeForTesting(["207/204 EN 1"]) else { return nil }
            return subject.identifier.catalogGeneration
        }
        let initiallyInstalled = await waitUntil { scannerGeneration() == registry.generation }
        XCTAssertTrue(initiallyInstalled)
        let initial = try await snapshot(coordinator)
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), .init(identifier: try identifier(initial)), nil)
        let appeared = await waitUntil { model.pendingIdentityChoice != nil }
        XCTAssertTrue(appeared)
        model.dismissIdentityChoice()
        let filed = await waitUntil { !model.unresolvedScans.isEmpty }
        XCTAssertTrue(filed)
        let rowID = try XCTUnwrap(model.unresolvedScans.first?.id)
        guard case let .activated(next) = await coordinator.activate(try sign(release(2, name: "Corrected fixture", two: true)), now: now) else { return XCTFail() }
        let installed = await waitUntil { scannerGeneration() == next.catalog.generation }
        XCTAssertTrue(installed)
        model.resolveUnresolved(id: rowID, choice: .retryLookup)
        let retried = await waitUntil { model.pendingIdentityChoice?.identifier.catalogGeneration == next.catalog.generation }
        XCTAssertTrue(retried)
        XCTAssertEqual(model.pendingIdentityChoice?.displayCandidates.count, 2)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
    }

    #if DEBUG && LOCAL_ONLY_SIGNING
    func testExplicitDebugKitUsesEphemeralKeysAndOfflineValidatedSeed() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try LorcanaLocalReviewKit.make(manifest: release().catalog, root: root, now: now)
        let second = try LorcanaLocalReviewKit.make(manifest: release().catalog, root: root.appendingPathComponent("other"), now: now)
        XCTAssertNotEqual(first.publicKey, second.publicKey)
        let snapshot = try await snapshot(first.coordinator)
        XCTAssertEqual(snapshot.revision, 1)
        XCTAssertEqual(first.runtime.descriptor.capabilities, [.scan, .browse])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertNil(CardGameRuntimeContainer.appDefaults().runtime(for: .lorcana)?.activationSource)
        XCTAssertNil(first.runtime.pricing); XCTAssertNotNil(first.runtime.browse); XCTAssertNotNil(first.runtime.importer)
    }
    #endif
}

private final class LorcanaWriteFault: @unchecked Sendable {
    enum Failure: Error { case injected }
    private let lock = NSLock()
    private var fileName: String?
    private var afterCommit = false
    func fail(_ name: String, afterCommit: Bool = false) {
        lock.lock(); fileName = name; self.afterCommit = afterCommit; lock.unlock()
    }
    func write(_ bytes: Data, _ url: URL) throws {
        lock.lock(); let fails = fileName == url.lastPathComponent, after = afterCommit; lock.unlock()
        if fails && !after { throw Failure.injected }
        try bytes.write(to: url, options: .atomic)
        if fails && after { throw Failure.injected }
    }
}

private actor LorcanaTestUpdateClient: LorcanaCatalogUpdateFetching {
    var envelope: LorcanaCatalogReleaseEnvelope
    var fetches = 0
    var resets = 0
    init(envelope: LorcanaCatalogReleaseEnvelope) { self.envelope = envelope }
    func update(_ envelope: LorcanaCatalogReleaseEnvelope) { self.envelope = envelope }
    func fetch() async throws -> SignedCatalogFetchResult<LorcanaCatalogReleaseEnvelope> {
        fetches += 1
        try await Task.sleep(for: .milliseconds(20))
        return .fetched(envelope)
    }
    func resetConditionalState() { resets += 1 }
}

@MainActor private final class LorcanaTestSession { var isCurrent = true }

private actor LorcanaLookupGate {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var paused: CheckedContinuation<Void, Never>?
    func pause() async {
        await withCheckedContinuation { continuation in
            paused = continuation; started = true; startWaiter?.resume(); startWaiter = nil
        }
    }
    func waitForStart() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func resume() { paused?.resume(); paused = nil }
}

private struct LorcanaDelayedAdapter: GameCatalogAdapter {
    let base: LorcanaCatalogAdapter
    let gate: LorcanaLookupGate
    var game: CardGame { base.game }
    var generation: String { base.generation }
    func lookup(_ identifier: ScanIdentifier) async throws -> CatalogLookupOutcome {
        await gate.pause()
        return try await base.lookup(identifier)
    }
    func resolve(_ candidate: PhysicalPrintingCandidate, for identifier: ScanIdentifier) async throws -> CardCatalog.CatalogResolution {
        try await base.resolve(candidate, for: identifier)
    }
}
