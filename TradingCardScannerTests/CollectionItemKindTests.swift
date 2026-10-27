import XCTest
import SwiftData
@testable import TradingCardScanner

/// Graded slabs and sealed products entering a collection that was built for
/// raw singles. The rules that keep them from contaminating what was there.
@MainActor
final class CollectionItemKindTests: XCTestCase {
    func testSynchronousGradedPickerAcquisitionBlocksMainActorUnderContention() async throws {
        let container = try makePickerContainer()
        let card = try identifiedPokemonCard()
        let variant = pickerVariant()
        let locked = expectation(description: "Ownership lock ahead of graded picker")
        let beginWait = DispatchSemaphore(value: 0)
        let heartbeat = DispatchSemaphore(value: 0)
        let holder = Task.detached {
            try CollectionWriteSerializer.perform(container: container, timeout: .wait) { _ in
                locked.fulfill()
                guard beginWait.wait(timeout: .now() + 3) == .success else { return false }
                return heartbeat.wait(timeout: .now() + .milliseconds(500)) == .success
            }
        }
        await fulfillment(of: [locked], timeout: 3)
        DispatchQueue.main.async { heartbeat.signal() }
        beginWait.signal()
        let started = Date.now
        let wroteOnMain = try CollectionWriteSerializer.perform(container: container, timeout: .mainThread) { context in
            _ = try CollectionStore(context: context).addGraded(underlying: card,
                variant: variant, certificationNumber: "PICKER-BASELINE")
            return Thread.isMainThread
        }
        let heartbeatRanWhileLocked = try await holder.value
        XCTAssertTrue(wroteOnMain)
        XCTAssertFalse(heartbeatRanWhileLocked)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<CollectedCard>()).map(\.quantity), [1])
        print("M04 graded picker: mainThread=\(wroteOnMain), heartbeatDuringLock=\(heartbeatRanWhileLocked), elapsedMs=\(Date.now.timeIntervalSince(started) * 1000)")
    }

    func testBackgroundGradedPickerStaysResponsiveAndSavesSelectedIdentityAndPrice() async throws {
        for amount: Double? in [50, nil] {
            let container = try makePickerContainer()
            let card = try identifiedPokemonCard()
            _ = try CollectionStore(context: container.mainContext).add(card,
                resolved: .init(variant: .normal, resolution: .userConfirmed))
            let selected = pickerVariant(amount: amount, printing: "1st Edition Holofoil")
            let writer = await ScannerCollectionWriter.makeBackground(modelContainer: container)
            XCTAssertTrue(writer.modelExecutor is BackgroundSerialModelExecutor)
            let locked = expectation(description: "Ownership contention ahead of background graded add")
            let heartbeat = DispatchSemaphore(value: 0)
            let holder = Task.detached {
                try CollectionWriteSerializer.perform(container: container, timeout: .wait) { _ in
                    locked.fulfill()
                    return heartbeat.wait(timeout: .now() + 2) == .success
                }
            }
            await fulfillment(of: [locked], timeout: 3)
            DispatchQueue.main.async { heartbeat.signal() }
            let receipt = try await writer.addGradedSelection(underlying: card, variant: selected,
                certificationNumber: "PICKER-CERT", setReleaseOrder: 123, pokemonPrintRun: .firstEdition,
                shouldContinue: { true })
            let heartbeatRanWhileLocked = try await holder.value
            XCTAssertTrue(heartbeatRanWhileLocked)
            let fresh = ModelContext(container)
            let rows = try fresh.fetch(FetchDescriptor<CollectedCard>())
            let slab = try XCTUnwrap(rows.first { $0.itemKind == .gradedCard })
            XCTAssertEqual(rows.count, 2, "The raw copy stays separate")
            XCTAssertEqual(slab.collectionKey, receipt.collectionKey)
            XCTAssertEqual(slab.quantity, 1)
            XCTAssertEqual(slab.certificationNumber, "PICKER-CERT")
            XCTAssertEqual(slab.pokemonPrintRun, .firstEdition)
            XCTAssertEqual(slab.setReleaseOrder, 123)
            XCTAssertEqual(slab.justTCGVariantID, selected.id)
            XCTAssertEqual(slab.justTCGCardID, selected.cardID)
            XCTAssertEqual(slab.gradingCompany, .psa)
            XCTAssertEqual(slab.gradeRaw, "10")
            XCTAssertEqual(slab.identityResolution, .catalogSelected)
            // Explicit listing selection remains priced even when no physical
            // finish was separately recorded; automatic M02 binding is stricter.
            XCTAssertNil(slab.variant)
            XCTAssertEqual(PriceStore(context: fresh).record(forKey: slab.priceKey)?.effectiveUnitMarketPriceUSD, amount)
            XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<PriceObservation>()), amount == nil ? 0 : 1)
            let events = try fresh.fetch(FetchDescriptor<InventoryEvent>())
            let activities = try fresh.fetch(FetchDescriptor<CollectionActivity>())
            XCTAssertEqual(events.count, 2)
            XCTAssertEqual(activities.first { $0.id == receipt.activityID }?.source, .gradedCatalog)
            XCTAssertTrue(CollectionActivity.integrityDefects(activities: activities, events: events).isEmpty)
        }
    }

    func testGradedPickerPreservesDuplicateCertificateAndCertlessCopyRules() async throws {
        for certificate: String? in ["PICKER-CERT", nil] {
            let container = try makePickerContainer()
            let writer = await ScannerCollectionWriter.makeBackground(modelContainer: container)
            let card = try identifiedPokemonCard()
            let selected = pickerVariant()
            let first = try await writer.addGradedSelection(underlying: card, variant: selected,
                certificationNumber: certificate, setReleaseOrder: nil, pokemonPrintRun: nil, shouldContinue: { true })
            let second = try await writer.addGradedSelection(underlying: card, variant: selected,
                certificationNumber: certificate, setReleaseOrder: nil, pokemonPrintRun: nil, shouldContinue: { true })
            XCTAssertEqual(first.collectionKey, second.collectionKey)
            XCTAssertEqual(second.wasDuplicate, certificate != nil)
            if certificate != nil {
                do {
                    _ = try await writer.addGradedSelection(underlying: card, variant: pickerVariant(id: "conflicting-market", amount: 999),
                        certificationNumber: certificate, setReleaseOrder: nil, pokemonPrintRun: nil, shouldContinue: { true })
                    XCTFail("A certificate cannot change its bound listing")
                } catch { XCTAssertTrue(error is CollectionStoreError) }
            } else {
                XCTAssertNotEqual(first.activityID, second.activityID, "Two intentional certless acquisitions stay undoable separately")
            }
            let fresh = ModelContext(container)
            let slab = try XCTUnwrap(fresh.fetch(FetchDescriptor<CollectedCard>()).first)
            XCTAssertEqual(slab.quantity, certificate == nil ? 2 : 1)
            XCTAssertEqual(slab.justTCGVariantID, selected.id)
            XCTAssertEqual(PriceStore(context: fresh).record(forKey: slab.priceKey)?.effectiveUnitMarketPriceUSD, 50)
            let events = try fresh.fetch(FetchDescriptor<InventoryEvent>())
            let activities = try fresh.fetch(FetchDescriptor<CollectionActivity>())
            XCTAssertEqual(events.count, certificate == nil ? 2 : 1)
            XCTAssertEqual(activities.count, certificate == nil ? 2 : 1)
            XCTAssertTrue(CollectionActivity.integrityDefects(activities: activities, events: events).isEmpty)
        }
    }

    func testGradedPickerPromotionRetainsTaskAuthorizationAndExistingLineage() async throws {
        let container = try makePickerContainer()
        let card = try identifiedPokemonCard()
        let original = try CollectionStore(context: container.mainContext).addScannedGraded(underlying: card,
            company: .psa, grade: .init(value: "10"), certificationNumber: "PICKER-PROMOTION",
            resolved: .init(variant: .normal, resolution: .userConfirmed))
        let writer = await ScannerCollectionWriter.makeBackground(modelContainer: container)
        let enforced = CollectionWriteSerializer.enforcesOwnershipRule
        CollectionWriteSerializer.enforcesOwnershipRule = true
        defer { CollectionWriteSerializer.enforcesOwnershipRule = enforced }
        var attempts = 0
        let receipt = try await CollectionExclusiveWrites.retryingIfRequired {
            attempts += 1
            return try await writer.addGradedSelection(underlying: card, variant: pickerVariant(printing: "Normal"),
                certificationNumber: "PICKER-PROMOTION", setReleaseOrder: nil, pokemonPrintRun: nil, shouldContinue: { true })
        }
        XCTAssertEqual(attempts, 2)
        XCTAssertTrue(receipt.wasDuplicate)
        XCTAssertNotEqual(receipt.collectionKey, original.collectionKey)
        let fresh = ModelContext(container)
        let rows = try fresh.fetch(FetchDescriptor<CollectedCard>())
        let slab = try XCTUnwrap(rows.first)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(slab.quantity, 1)
        XCTAssertEqual(slab.variant, .normal)
        XCTAssertEqual(slab.justTCGVariantID, "picker-market")
        let events = try fresh.fetch(FetchDescriptor<InventoryEvent>())
        let activities = try fresh.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.collectionKey, slab.collectionKey)
        XCTAssertEqual(events.first?.priceStorageKey, slab.priceKey)
        XCTAssertTrue(CollectionActivity.integrityDefects(activities: activities, events: events).isEmpty)
    }

    func testQueuedGradedPickerAcquisitionRejectsCancellationAndRetiredStorage() async throws {
        for cancel in [false, true] {
            let container = try makePickerContainer()
            let writer = await ScannerCollectionWriter.makeBackground(modelContainer: container)
            let card = try identifiedPokemonCard()
            let variant = pickerVariant()
            let generation = CollectionStorageGeneration()
            generation.installReady(storeID: UUID())
            let shouldContinue = generation.continuation(for: try XCTUnwrap(generation.currentToken()))
            let locked = expectation(description: "Ownership lock ahead of invalidated graded acquisition")
            let release = DispatchSemaphore(value: 0)
            let holder = Task.detached {
                try CollectionWriteSerializer.perform(container: container, timeout: .wait) { _ in
                    locked.fulfill()
                    return release.wait(timeout: .now() + 3) == .success
                }
            }
            await fulfillment(of: [locked], timeout: 3)
            let write = Task {
                try await writer.addGradedSelection(underlying: card, variant: variant,
                    certificationNumber: "PICKER-CANCELED", setReleaseOrder: nil, pokemonPrintRun: nil,
                    shouldContinue: shouldContinue)
            }
            await Task.yield()
            if cancel { write.cancel() } else { generation.suspend() }
            release.signal()
            do { _ = try await write.value; XCTFail("Invalidated graded acquisition must not commit") }
            catch is CancellationError { }
            let released = try await holder.value
            XCTAssertTrue(released)
            let fresh = ModelContext(container)
            XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<CollectedCard>()), 0)
            XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<InventoryEvent>()), 0)
            XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<CollectionActivity>()), 0)
            XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<PriceRecord>()), 0)
            XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<PriceObservation>()), 0)
        }
    }

    private func makePickerContainer() throws -> ModelContainer {
        try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    private func pickerVariant(id: String = "picker-market", amount: Double? = 50,
                               printing: String? = "Holofoil") -> GradedVariant {
        GradedVariant(id: id, cardID: "picker-card", company: .psa, grade: .init(value: "10"),
            printing: printing, marketPriceUSD: amount, updatedAt: nil)
    }

    func testUnknownFinishCannotBindOrStoreGradedQuote() async throws {
        for (finish, printing): (PhysicalVariant?, String?) in [(nil, "Holofoil"), (nil, nil), (.normal, nil), (.normal, "Holofoil")] {
            let container = try ProductionRowFixtures.makeContainer()
            let mutation = try CollectionStore(context: container.mainContext).addScannedGraded(
                underlying: ProductionRowFixtures.pokemonCard(), company: .psa,
                grade: .init(value: "10"), certificationNumber: nil,
                resolved: .init(variant: finish, resolution: .userConfirmed))
            let receipt = try await ScannerCollectionWriter(modelContainer: container).bindScannedGraded(
                collectionKey: mutation.collectionKey,
                variant: GradedVariant(id: "sole-holo", company: .psa, grade: .init(value: "10"),
                    printing: printing, marketPriceUSD: 123, updatedAt: nil))
            XCTAssertNil(receipt)
            let fresh = ModelContext(container)
            let row = try XCTUnwrap(fresh.fetch(FetchDescriptor<CollectedCard>()).first)
            XCTAssertNil(row.justTCGVariantID)
            XCTAssertNil(PriceStore(context: fresh).record(forKey: row.priceKey)?.effectiveUnitMarketPriceUSD)
        }
    }

    func testCertlessScannedFinishesDoNotMerge() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let store = CollectionStore(context: container.mainContext)
        let card = try ProductionRowFixtures.pokemonCard()
        let normal = try store.addScannedGraded(underlying: card, company: .psa,
            grade: CardGrade(value: "10"), certificationNumber: nil,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed))
        let reverse = try store.addScannedGraded(underlying: card, company: .psa,
            grade: CardGrade(value: "10"), certificationNumber: nil,
            resolved: ResolvedVariant(variant: .reverse, resolution: .userConfirmed))
        let repeatedNormal = try store.addScannedGraded(underlying: card, company: .psa,
            grade: CardGrade(value: "10"), certificationNumber: nil,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed))

        XCTAssertNotEqual(normal.collectionKey, reverse.collectionKey)
        XCTAssertEqual(normal.collectionKey, repeatedNormal.collectionKey)
        let fresh = ModelContext(container)
        let rows = try fresh.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first { $0.variant == .normal }?.quantity, 2)
        XCTAssertEqual(rows.first { $0.variant == .reverse }?.quantity, 1)
        let events = try fresh.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(InventoryLedger.quantities(from: events)[normal.collectionKey], 2)
        XCTAssertEqual(InventoryLedger.quantities(from: events)[reverse.collectionKey], 1)
        XCTAssertTrue(CollectionActivity.integrityDefects(
            activities: try fresh.fetch(FetchDescriptor<CollectionActivity>()), events: events).isEmpty)
    }

    func testCertlessScansPreserveLegacyAndUnknownFinishes() throws {
        let card = try ProductionRowFixtures.pokemonCard()
        let pairs: [(PhysicalVariant?, PhysicalVariant?)] = [(nil, .normal), (.normal, nil), (.reverse, .normal)]
        for (storedFinish, incomingFinish) in pairs {
            let container = try ProductionRowFixtures.makeContainer()
            let store = CollectionStore(context: container.mainContext)
            let legacy = try store.addScannedGraded(underlying: card, company: .psa,
                grade: CardGrade(value: "10"), certificationNumber: nil,
                resolved: ResolvedVariant(variant: storedFinish, resolution: .userConfirmed))
            let legacyKey = CollectedCard.scannedGradedCollectionKey(game: .pokemon,
                underlyingPrintingID: card.providerID, company: .psa,
                grade: CardGrade(value: "10"), certificationNumber: nil)
            XCTAssertEqual(legacy.collectionKey, legacyKey)
            let incoming = try store.addScannedGraded(underlying: card, company: .psa,
                grade: CardGrade(value: "10"), certificationNumber: nil,
                resolved: ResolvedVariant(variant: incomingFinish, resolution: .userConfirmed))
            let repeated = try store.addScannedGraded(underlying: card, company: .psa,
                grade: CardGrade(value: "10"), certificationNumber: nil,
                resolved: ResolvedVariant(variant: incomingFinish, resolution: .userConfirmed))
            XCTAssertNotEqual(incoming.collectionKey, legacyKey)
            XCTAssertEqual(incoming.collectionKey, repeated.collectionKey)
            XCTAssertEqual(store.card(forKey: legacyKey)?.variant, storedFinish)
            XCTAssertEqual(store.card(forKey: legacyKey)?.quantity, 1)
            XCTAssertEqual(store.card(forKey: incoming.collectionKey)?.variant, incomingFinish)
            XCTAssertEqual(store.card(forKey: incoming.collectionKey)?.quantity, 2)
            XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<CollectedCard>()), 2)
        }
    }

    func testCorrectedCertlessScansMatchStoredFinishWithoutRekeying() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let store = CollectionStore(context: container.mainContext)
        let card = try ProductionRowFixtures.pokemonCard()
        let original = try store.addScannedGraded(underlying: card, company: .psa,
            grade: CardGrade(value: "10"), certificationNumber: nil,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed))
        let originalRow = try XCTUnwrap(store.card(forKey: original.collectionKey))
        _ = try store.recordVariantCorrection(for: originalRow,
            to: ResolvedVariant(variant: .holo, resolution: .userConfirmed),
            activityID: XCTUnwrap(original.activityID), quantity: 1)
        let normal = try store.addScannedGraded(underlying: card, company: .psa,
            grade: CardGrade(value: "10"), certificationNumber: nil,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed))
        let repeatedHolo = try store.addScannedGraded(underlying: card, company: .psa,
            grade: CardGrade(value: "10"), certificationNumber: nil,
            resolved: ResolvedVariant(variant: .holo, resolution: .userConfirmed))
        XCTAssertEqual(original.collectionKey, repeatedHolo.collectionKey)
        XCTAssertNotEqual(normal.collectionKey, original.collectionKey)
        let normalRow = try XCTUnwrap(store.card(forKey: normal.collectionKey))
        _ = try store.recordVariantCorrection(for: normalRow,
            to: ResolvedVariant(variant: .reverse, resolution: .userConfirmed),
            activityID: XCTUnwrap(normal.activityID), quantity: 1)
        let newNormal = try store.addScannedGraded(underlying: card, company: .psa,
            grade: CardGrade(value: "10"), certificationNumber: nil,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed))
        XCTAssertEqual(Set([original.collectionKey, normal.collectionKey, newNormal.collectionKey]).count, 3)
        XCTAssertEqual(originalRow.variant, .holo)
        XCTAssertEqual(normalRow.variant, .reverse)
        try store.undo(repeatedHolo)
        try store.undo(newNormal)
        let fresh = ModelContext(container)
        let rows = try fresh.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(Set(rows.compactMap(\.variant)), [.holo, .reverse])
        XCTAssertTrue(rows.allSatisfy { $0.quantity == 1 })
        XCTAssertTrue(CollectionActivity.integrityDefects(
            activities: try fresh.fetch(FetchDescriptor<CollectionActivity>()),
            events: try fresh.fetch(FetchDescriptor<InventoryEvent>())).isEmpty)
    }

    func testCertlessMagicNonfoilAndFoilScansStaySeparate() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let store = CollectionStore(context: container.mainContext)
        let data = Data("""
        {"id":"3f0a1f52-0000-4000-8000-000000000001","name":"Llanowar Elves",
         "set":"ecl","set_name":"Eclipse","collector_number":"218","lang":"en",
         "digital":false,"frame":"2015","rarity":"common","finishes":["nonfoil","foil"]}
        """.utf8)
        let card = IdentifiedCard.magic(try JSONDecoder().decode(ScryfallCard.self, from: data))
        var mutations: [CollectionMutation] = []
        for finish in [PhysicalVariant.nonfoil, .foil, .foil] {
            mutations.append(try store.addScannedGraded(underlying: card, company: .bgs,
                grade: CardGrade(value: "9.5"), certificationNumber: nil,
                resolved: ResolvedVariant(variant: finish, resolution: .userConfirmed)))
        }
        XCTAssertNotEqual(mutations[0].collectionKey, mutations[1].collectionKey)
        XCTAssertEqual(mutations[1].collectionKey, mutations[2].collectionKey)
        let rows = try ModelContext(container).fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first { $0.variant == .nonfoil }?.quantity, 1)
        XCTAssertEqual(rows.first { $0.variant == .foil }?.quantity, 2)
    }

    func testSeparatedScannedFinishesKeepBindingCertificationAndRestore() async throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let card = try ProductionRowFixtures.pokemonCard()
        let grade = CardGrade(value: "10")
        let store = CollectionStore(context: container.mainContext)
        let normal = try store.addScannedGraded(underlying: card, company: .psa,
            grade: grade, certificationNumber: nil,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed))
        let reverse = try store.addScannedGraded(underlying: card, company: .psa,
            grade: grade, certificationNumber: nil,
            resolved: ResolvedVariant(variant: .reverse, resolution: .userConfirmed))
        let writer = ScannerCollectionWriter(modelContainer: container)
        for (mutation, marketID, printing, amount) in [
            (normal, "normal-market", "Normal", 10.0),
            (reverse, "reverse-market", "Reverse Holofoil", 30.0)
        ] {
            let receipt = try await writer.bindScannedGraded(collectionKey: mutation.collectionKey,
                variant: GradedVariant(id: marketID, company: .psa, grade: grade,
                    printing: printing, marketPriceUSD: amount, updatedAt: nil))
            XCTAssertNotNil(receipt)
        }
        let fresh = ModelContext(container)
        let freshStore = CollectionStore(context: fresh)
        let repeated = try freshStore.addScannedGraded(underlying: card, company: .psa,
            grade: grade, certificationNumber: nil,
            resolved: ResolvedVariant(variant: .reverse, resolution: .userConfirmed))
        XCTAssertEqual(repeated.collectionKey, reverse.collectionKey)
        XCTAssertEqual(freshStore.card(forKey: reverse.collectionKey)?.justTCGVariantID, "reverse-market")
        try freshStore.undo(repeated)
        let certified = try XCTUnwrap(freshStore.recordGradedCertificationRefinement(
            underlying: card, previous: reverse, company: .psa, grade: grade,
            certificationNumber: "FINISH-REFINEMENT"))
        let certifiedRow = try XCTUnwrap(freshStore.card(forKey: certified.collectionKey))
        XCTAssertEqual(certifiedRow.variant, .reverse)
        XCTAssertEqual(certifiedRow.certificationNumber, "FINISH-REFINEMENT")
        let removed = try freshStore.remove(certifiedRow)
        try freshStore.restore(removed)
        let verify = ModelContext(container)
        let rows = try verify.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.compactMap(\.variant)), [.normal, .reverse])
        for row in rows {
            XCTAssertEqual(row.quantity, 1)
            XCTAssertEqual(PriceStore(context: verify).record(forKey: row.priceKey)?.effectiveUnitMarketPriceUSD,
                row.variant == .normal ? 10 : 30)
        }
        XCTAssertTrue(CollectionActivity.integrityDefects(
            activities: try verify.fetch(FetchDescriptor<CollectionActivity>()),
            events: try verify.fetch(FetchDescriptor<InventoryEvent>())).isEmpty)
    }

    func testSeparatedScannedFinishesSurviveStoreReopenAndCSVRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = ModelConfiguration(url: root.appendingPathComponent("holdings.store"), cloudKitDatabase: .none)
        let card = try ProductionRowFixtures.pokemonCard()
        let keys = try autoreleasepool {
            let container = try ModelContainer(for: CollectionStorageModelSchema.full, configurations: [configuration])
            let store = CollectionStore(context: container.mainContext)
            return try [PhysicalVariant.normal, .reverse].map { finish in
                try store.addScannedGraded(underlying: card, company: .psa,
                    grade: CardGrade(value: "10"), certificationNumber: nil,
                    resolved: ResolvedVariant(variant: finish, resolution: .userConfirmed)).collectionKey
            }
        }
        let reopened = try ModelContainer(for: CollectionStorageModelSchema.full, configurations: [configuration])
        let rows = try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(Set(rows.map(\.collectionKey)), Set(keys))
        XCTAssertEqual(Set(rows.compactMap(\.variant)), [.normal, .reverse])
        let plan = try CollectionCSV.parse(Data(CollectionCSV.export(rows).text.utf8))
        let target = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let imported = try CollectionCSV.apply(plan, to: target.mainContext)
        XCTAssertTrue(imported.failedRows.isEmpty)
        let store = CollectionStore(context: target.mainContext)
        let repeated = try store.addScannedGraded(underlying: card, company: .psa,
            grade: CardGrade(value: "10"), certificationNumber: nil,
            resolved: ResolvedVariant(variant: .reverse, resolution: .userConfirmed))
        XCTAssertEqual(repeated.collectionKey, keys[1])
        XCTAssertEqual(store.card(forKey: keys[0])?.quantity, 1)
        XCTAssertEqual(store.card(forKey: keys[1])?.quantity, 2)
        XCTAssertEqual(try target.mainContext.fetchCount(FetchDescriptor<CollectedCard>()), 2)
    }

    func testCertifiedRescanValidatesFinalFinishAndEditionBeforeReturningDuplicate() throws {
        for unknownFinish in [false, true] {
            for compatible in [false, true] {
                let container = try ProductionRowFixtures.makeContainer()
                let context = container.mainContext
                let store = CollectionStore(context: context)
                let card = try ProductionRowFixtures.pokemonCard()
                let initial = try store.addGraded(underlying: card,
                    variant: GradedVariant(id: "old-market", company: .psa,
                        grade: CardGrade(value: "10"), marketPriceUSD: 90, updatedAt: nil),
                    certificationNumber: "REFINE-CERT",
                    resolved: ResolvedVariant(variant: unknownFinish ? nil : .normal, resolution: .userConfirmed))
                let row = try XCTUnwrap(store.card(forKey: initial.collectionKey))
                let record = try XCTUnwrap(PriceStore(context: context).record(forKey: row.priceKey))
                record.gradedPrinting = compatible ? "1st Edition" : "Normal"
                try context.save()
                XCTAssertTrue(PriceIdentityWritePreflight.requiresScannedGradedVariantRepair(
                    container: container, game: card.game, providerID: card.providerID,
                    grade: CardGrade(value: "10"), company: .psa, certificationNumber: "REFINE-CERT",
                    pokemonPrintRun: .firstEdition, treatmentIDs: [], toVariantID: "normal"))
                let events = try context.fetchCount(FetchDescriptor<InventoryEvent>())
                let activities = try context.fetchCount(FetchDescriptor<CollectionActivity>())
                let duplicate = try store.addScannedGraded(underlying: card, company: .psa,
                    grade: CardGrade(value: "10"), certificationNumber: "REFINE-CERT",
                    pokemonPrintRun: .firstEdition,
                    resolved: ResolvedVariant(variant: .normal, resolution: .printedLabel))
                XCTAssertTrue(duplicate.wasDuplicate)
                XCTAssertNil(duplicate.activityID)
                XCTAssertEqual(row.quantity, 1)
                XCTAssertEqual(row.pokemonPrintRun, .firstEdition)
                XCTAssertEqual(row.variant, .normal)
                XCTAssertEqual(row.justTCGVariantID, compatible ? "old-market" : nil)
                XCTAssertEqual(duplicate.gradedIdentityToResolve == nil, compatible)
                XCTAssertEqual(PriceStore(context: context).record(forKey: row.priceKey)?.effectiveUnitMarketPriceUSD,
                    compatible ? 90 : nil)
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<InventoryEvent>()), events)
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectionActivity>()), activities)
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectedCard>()), 1)
            }
        }
    }

    func testDelayedGradedBindingRechecksDurableCorrectedFinish() async throws {
        let container = try ProductionRowFixtures.makeContainer()
        let context = container.mainContext
        let store = CollectionStore(context: context)
        let mutation = try store.addScannedGraded(underlying: ProductionRowFixtures.pokemonCard(),
            company: .psa, grade: CardGrade(value: "10"), certificationNumber: "DELAYED-CERT")
        let row = try XCTUnwrap(store.card(forKey: mutation.collectionKey))
        let originalIdentity = GradedBindingIdentity(finishID: row.variantID, printRun: row.pokemonPrintRun)
        _ = try store.recordVariantCorrection(for: row,
            to: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            activityID: XCTUnwrap(mutation.activityID), quantity: 1)
        let writer = ScannerCollectionWriter(modelContainer: container)
        let receipt = try await writer.bindScannedGraded(collectionKey: mutation.collectionKey,
            variant: GradedVariant(id: "stale-holo", company: .psa, grade: CardGrade(value: "10"),
                printing: "Holofoil", marketPriceUSD: 250, updatedAt: nil), expectedIdentity: originalIdentity)
        XCTAssertNil(receipt)
        let saved = try XCTUnwrap(CollectionStore(context: ModelContext(container)).card(forKey: mutation.collectionKey))
        XCTAssertNil(saved.justTCGVariantID)
        XCTAssertEqual(saved.certificationNumber, "DELAYED-CERT")
        XCTAssertEqual(saved.quantity, 1)
        XCTAssertEqual(saved.variant, .normal)
    }

    func testQuantityIncreaseCannotDuplicateCertifiedSlab() throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let store = CollectionStore(context: context)
        let mutation = try store.addGraded(
            underlying: identifiedPokemonCard(),
            variant: GradedVariant(id: "certified-market", company: .psa,
                grade: CardGrade(value: "10"), marketPriceUSD: 500, updatedAt: nil),
            certificationNumber: "11111111"
        )
        let eventCount = try context.fetchCount(FetchDescriptor<InventoryEvent>())
        let activityCount = try context.fetchCount(FetchDescriptor<CollectionActivity>())

        XCTAssertThrowsError(try store.setQuantity(2,
            forCollectionKey: mutation.collectionKey, expectedCurrent: 1)) { error in
            guard case CollectionStoreError.quantityOutOfRange = error else {
                return XCTFail("Expected a certified quantity rejection, got \(error)")
            }
        }

        let fresh = ModelContext(context.container)
        let row = try XCTUnwrap(CollectionStore(context: fresh).card(forKey: mutation.collectionKey))
        XCTAssertFalse(row.allowsQuantityAggregation)
        XCTAssertEqual(row.quantity, 1)
        XCTAssertEqual(InventoryLedger.quantities(from: try fresh.fetch(FetchDescriptor<InventoryEvent>()))[row.collectionKey], 1)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<InventoryEvent>()), eventCount)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<CollectionActivity>()), activityCount)
        XCTAssertEqual(PriceStore(context: fresh).record(forKey: row.priceKey)?.effectiveUnitMarketPriceUSD, 500)
        XCTAssertFalse(context.hasChanges)
    }

    func testCertifiedLegacyQuantityCanDecreaseAndUncertifiedQuantityCanIncrease() throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let store = CollectionStore(context: context)
        let variant = GradedVariant(id: "quantity-market", company: .psa,
            grade: CardGrade(value: "10"), marketPriceUSD: 500, updatedAt: nil)
        let certified = try store.addGraded(underlying: identifiedPokemonCard(),
            variant: variant, certificationNumber: "11111111")
        let row = try XCTUnwrap(store.card(forKey: certified.collectionKey))
        // Model a pre-existing legacy defect without silently repairing it.
        row.quantity = 3
        let operationID = UUID()
        _ = InventoryLedger(context: context).record(row, kind: .quantityAdjust,
            source: .correction, deltaQuantity: 2, operationID: operationID)
        _ = try store.appendActivity(row, source: .correction, kind: .quantityAdjusted,
            deltaQuantity: 2, ledgerOperationIDs: [operationID])
        try context.save()

        XCTAssertEqual(try store.setQuantity(2, forCollectionKey: certified.collectionKey, expectedCurrent: 3), 2)
        XCTAssertEqual(try store.setQuantity(1, forCollectionKey: certified.collectionKey, expectedCurrent: 2), 1)
        let uncertified = try store.addGraded(underlying: identifiedPokemonCard(),
            variant: variant, certificationNumber: nil)
        XCTAssertEqual(try store.setQuantity(2, forCollectionKey: uncertified.collectionKey, expectedCurrent: 1), 2)
        let quantities = InventoryLedger.quantities(from: try context.fetch(FetchDescriptor<InventoryEvent>()))
        XCTAssertEqual(quantities[certified.collectionKey], 1)
        XCTAssertEqual(quantities[uncertified.collectionKey], 2)
    }

    func testGradedFinishCorrectionFindsSurvivingAcquisitionAfterNewestUndo() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let context = container.mainContext
        let store = CollectionStore(context: context)
        let card = try ProductionRowFixtures.pokemonCard()
        let first = try store.addScannedGraded(underlying: card, company: .psa,
                                               grade: CardGrade(value: "10"), certificationNumber: nil)
        let second = try store.addScannedGraded(underlying: card, company: .psa,
                                                grade: CardGrade(value: "10"), certificationNumber: nil)
        XCTAssertEqual(first.collectionKey, second.collectionKey)
        let firstID = try XCTUnwrap(first.activityID)
        let secondID = try XCTUnwrap(second.activityID)
        for activity in try context.fetch(FetchDescriptor<CollectionActivity>()) {
            if activity.id == firstID { activity.occurredAt = .now.addingTimeInterval(-1) }
            if activity.id == secondID { activity.occurredAt = .now }
        }
        try context.save()
        try store.undo(second)
        let selected = try XCTUnwrap(context.fetch(
            CollectionCardDetailView.gradedAcquisitionDescriptor(for: first.collectionKey)
        ).first)
        XCTAssertEqual(selected.id, firstID)
        let row = try XCTUnwrap(store.card(forKey: first.collectionKey))
        _ = try store.recordVariantCorrection(for: row,
            to: ResolvedVariant(variant: .holo, resolution: .userConfirmed),
            activityID: selected.id, quantity: 1)
        XCTAssertEqual(row.quantity, 1)
        XCTAssertEqual(row.variant, .holo)
        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
        let events = try context.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertTrue(CollectionActivity.integrityDefects(activities: activities, events: events).isEmpty)
        XCTAssertEqual(InventoryLedger.quantities(from: events)[row.collectionKey], 1)
    }
    func testCertlessPrintRunsStayDistinctThroughBindingRefinementCorrectionAndRestore() async throws {
        let container = try ProductionRowFixtures.makeContainer()
        let context = container.mainContext
        let store = CollectionStore(context: context)
        let card = try ProductionRowFixtures.pokemonCard()
        let grade = CardGrade(value: "10")
        let first = try store.addScannedGraded(
            underlying: card, company: .psa, grade: grade, certificationNumber: nil,
            pokemonPrintRun: .firstEdition,
            resolved: .init(variant: .holo, resolution: .userConfirmed)
        )
        let unlimited = try store.addScannedGraded(
            underlying: card, company: .psa, grade: grade, certificationNumber: nil,
            pokemonPrintRun: .unlimited,
            resolved: .init(variant: .holo, resolution: .userConfirmed)
        )
        XCTAssertNotEqual(first.collectionKey, unlimited.collectionKey)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<CollectedCard>()).count, 2)
        let writer = ScannerCollectionWriter(modelContainer: container)
        for (mutation, variantID) in [(first, "first-market"), (unlimited, "unlimited-market")] {
            let receipt = try await writer.bindScannedGraded(
                collectionKey: mutation.collectionKey,
                variant: GradedVariant(id: variantID, cardID: "card", company: .psa,
                                       grade: grade, printing: variantID == "first-market" ? "1st Edition Holofoil" : "Unlimited Holofoil",
                                       marketPriceUSD: nil, updatedAt: nil)
            )
            XCTAssertNotNil(receipt)
        }
        let fresh = ModelContext(container)
        let freshStore = CollectionStore(context: fresh)
        let refined = try XCTUnwrap(freshStore.recordGradedCertificationRefinement(
            underlying: card, previous: first, company: .psa, grade: grade,
            certificationNumber: "FIRST-CERT"
        ))
        XCTAssertTrue(refined.collectionKey.contains(":run:firstEdition:cert:"))
        let firstRow = try XCTUnwrap(freshStore.card(forKey: refined.collectionKey))
        _ = try freshStore.recordVariantCorrection(
            for: firstRow, to: ResolvedVariant(variant: .holo, resolution: .userConfirmed),
            activityID: try XCTUnwrap(refined.activityID), quantity: 1
        )
        let removed = try freshStore.remove(firstRow)
        try freshStore.restore(removed)
        let verify = ModelContext(container)
        let rows = try verify.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.compactMap(\.pokemonPrintRun)), [.firstEdition, .unlimited])
        XCTAssertEqual(Set(rows.compactMap(\.justTCGVariantID)), ["first-market", "unlimited-market"])
        try freshStore.undo(unlimited)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<CollectedCard>()).count, 1)
    }

    func testSameRunScansMergeAndAmbiguousLegacyRowsDoNotAbsorbKnownRuns() throws {
        let card = try ProductionRowFixtures.pokemonCard()
        for storedRun: PokemonPrintRun? in [nil, .firstEdition, .unlimited] {
            let container = try ProductionRowFixtures.makeContainer()
            let context = container.mainContext
            let store = CollectionStore(context: context)
            let legacy = try store.addScannedGraded(
                underlying: card, company: .psa, grade: CardGrade(value: "10"), certificationNumber: nil
            )
            let row = try XCTUnwrap(store.card(forKey: legacy.collectionKey))
            row.pokemonPrintRunRaw = storedRun?.rawValue
            try context.save()
            let first = try store.addScannedGraded(
                underlying: card, company: .psa, grade: CardGrade(value: "10"), certificationNumber: nil,
                pokemonPrintRun: .firstEdition
            )
            let second = try store.addScannedGraded(
                underlying: card, company: .psa, grade: CardGrade(value: "10"), certificationNumber: nil,
                pokemonPrintRun: .firstEdition
            )
            XCTAssertEqual(first.collectionKey, second.collectionKey)
            XCTAssertEqual(first.collectionKey == legacy.collectionKey, storedRun == .firstEdition)
            XCTAssertEqual(try context.fetch(FetchDescriptor<CollectedCard>()).count, storedRun == .firstEdition ? 1 : 2)
            XCTAssertEqual(store.card(forKey: first.collectionKey)?.quantity, storedRun == .firstEdition ? 3 : 2)
            XCTAssertEqual(row.pokemonPrintRun, storedRun)
        }
    }

    func testBoundCertlessSlabsKeepRunsDistinct() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let store = CollectionStore(context: container.mainContext)
        let card = try ProductionRowFixtures.pokemonCard()
        let variant = GradedVariant(id: "variant", cardID: "card", company: .psa,
                                    grade: CardGrade(value: "10"), marketPriceUSD: nil, updatedAt: nil)
        let first = try store.addGraded(underlying: card, variant: variant, certificationNumber: nil, pokemonPrintRun: .firstEdition)
        let unlimited = try store.addGraded(underlying: card, variant: variant, certificationNumber: nil, pokemonPrintRun: .unlimited)
        XCTAssertNotEqual(first.collectionKey, unlimited.collectionKey)
        _ = try store.addGraded(underlying: card, variant: variant, certificationNumber: nil, pokemonPrintRun: .firstEdition)
        XCTAssertEqual(store.card(forKey: first.collectionKey)?.quantity, 2)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<CollectedCard>()).count, 2)
    }

    func testGradedPreflightDoesNotMatchDifferentPrintRun() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let card = try ProductionRowFixtures.pokemonCard()
        _ = try CollectionStore(context: container.mainContext).addScannedGraded(
            underlying: card, company: .psa, grade: CardGrade(value: "10"), certificationNumber: nil,
            pokemonPrintRun: .firstEdition
        )
        for (run, expected) in [(PokemonPrintRun.unlimited, false), (.firstEdition, true)] {
            XCTAssertEqual(PriceIdentityWritePreflight.requiresScannedGradedVariantRepair(
                container: container, game: .pokemon, providerID: card.providerID,
                grade: CardGrade(value: "10"), company: .psa, certificationNumber: nil,
                pokemonPrintRun: run, treatmentIDs: [], toVariantID: "holo"
            ), expected)
        }
    }

    func testCertlessPreflightIgnoresKnownDifferentFinishHolding() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let store = CollectionStore(context: container.mainContext)
        let card = try ProductionRowFixtures.pokemonCard()
        let normal = try store.addScannedGraded(underlying: card, company: .psa,
            grade: CardGrade(value: "10"), certificationNumber: nil,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed))
        // A known different finish becomes its own holding, so no identity
        // rewrite (and no refresh-cancelling gate) is needed.
        XCTAssertFalse(PriceIdentityWritePreflight.requiresScannedGradedVariantRepair(
            container: container, game: .pokemon, providerID: card.providerID,
            grade: CardGrade(value: "10"), company: .psa, certificationNumber: nil,
            treatmentIDs: [], toVariantID: PhysicalVariant.reverse.id))
        let reverse = try store.addScannedGraded(underlying: card, company: .psa,
            grade: CardGrade(value: "10"), certificationNumber: nil,
            resolved: ResolvedVariant(variant: .reverse, resolution: .userConfirmed))
        XCTAssertNotEqual(reverse.collectionKey, normal.collectionKey)
        XCTAssertEqual(store.card(forKey: normal.collectionKey)?.variant, .normal)
        XCTAssertEqual(store.card(forKey: normal.collectionKey)?.quantity, 1)
    }

    private var container: ModelContainer?

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CollectedCard.self, PriceRecord.self, ProductIdentity.self,
            CollectionActivity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container.mainContext
    }

    private func rawCard(number: String = "001", setCode: String = "PRE") -> CollectedCard {
        CollectedCard(
            collectionKey: "raw-\(setCode)-\(number)",
            game: .pokemon,
            providerID: "sv08.5-\(number)",
            name: "Eevee",
            setName: "Prismatic Evolutions",
            setCode: setCode,
            cardNumber: number,
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .holo,
            variantResolution: .userConfirmed
        )
    }

    // MARK: - Migration

    /// Every row written before item kinds existed is a raw card, and says so
    /// without a migration pass.
    func testExistingRowsMigrateAsRawCards() throws {
        let card = rawCard()

        XCTAssertEqual(card.itemKind, .rawCard)
        XCTAssertEqual(card.itemKindLabel, PhysicalVariant.holo.label)
        XCTAssertNil(card.cardGrade)
    }

    /// Raw keys keep their unprefixed form, so no existing ownership row or
    /// price record moves.
    func testRawKeysAreUnchangedByTheWidening() {
        let raw = PriceRecord.key(game: .pokemon, printingID: "sv08.5-001", variantID: "holo")

        XCTAssertFalse(raw.hasPrefix("graded:"))
        XCTAssertFalse(raw.hasPrefix("sealed:"))
        XCTAssertEqual(raw, PriceRecord.key(game: .pokemon, printingID: "sv08.5-001", variantID: "holo"))
    }

    // MARK: - Grades

    /// Grades are text, because `9.5` is not an integer and `Authentic` is not a
    /// number at all.
    func testGradeLabelsRenderTheWayCollectorsWriteThem() {
        XCTAssertEqual(CardGrade(value: "10").display(company: .psa), "PSA 10")
        XCTAssertEqual(CardGrade(value: "9.5").display(company: .bgs), "BGS 9.5")
        XCTAssertEqual(
            CardGrade(value: "10", label: "Black Label").display(company: .bgs),
            "BGS 10 Black Label"
        )
        XCTAssertEqual(
            CardGrade(value: "10", qualifier: "OC").display(company: .psa),
            "PSA 10 OC"
        )
        XCTAssertEqual(
            CardGrade(value: nil, label: "Authentic").display(company: .cgc),
            "CGC Authentic"
        )
        XCTAssertEqual(
            CardGrade(value: "10", label: "Pristine").display(company: .cgc),
            "CGC 10 Pristine"
        )
    }

    /// A qualifier makes a different object. A PSA 10 and a PSA 10 OC are not
    /// the same holding and must never merge.
    func testEveryGraderGradeLabelAndQualifierStaysDistinct() {
        let grades = [
            CardGrade(value: "10"),
            CardGrade(value: "10", qualifier: "OC"),
            CardGrade(value: "10", label: "Black Label"),
            CardGrade(value: "9.5"),
            CardGrade(value: nil, label: "Authentic")
        ]
        let fragments = Set(grades.map(\.identityFragment))

        XCTAssertEqual(fragments.count, grades.count, "each must be its own holding")
    }

    // MARK: - Namespaced keys

    func testGradedAndSealedRowsCannotCollideWithRaw() {
        let graded = CollectedCard.gradedCollectionKey(
            game: .pokemon, underlyingPrintingID: "sv08.5-001", variantUUID: "g-uuid"
        )
        let sealed = CollectedCard.sealedCollectionKey(
            game: .pokemon, productUUID: "p-uuid", variantUUID: "v-uuid"
        )

        XCTAssertNotEqual(graded, sealed)
        XCTAssertTrue(graded.contains("sv08.5-001"))
        XCTAssertTrue(sealed.hasPrefix("sealed:pokemon:"))
    }

    func testMagicTreatmentIsNamespacedInGradedAndSealedKeys() {
        let graded = CollectedCard.gradedCollectionKey(
            game: .magic,
            underlyingPrintingID: "neo-429",
            variantUUID: "graded-uuid",
            magicTreatments: [.neonInk]
        )
        let certified = CollectedCard.gradedCollectionKey(
            game: .magic,
            underlyingPrintingID: "neo-429",
            variantUUID: "graded-uuid",
            certificationNumber: "1234",
            magicTreatments: [.neonInk]
        )
        let sealed = CollectedCard.sealedCollectionKey(
            game: .magic,
            productUUID: "product-uuid",
            variantUUID: "variant-uuid",
            magicTreatments: [.surgeFoil]
        )

        XCTAssertEqual(
            graded,
            "graded:magic:neo-429:graded-uuid#treatment=neonink"
        )
        XCTAssertEqual(
            certified,
            "graded:magic:neo-429:graded-uuid:cert:1234#treatment=neonink"
        )
        XCTAssertEqual(
            sealed,
            "sealed:magic:product-uuid:variant-uuid#treatment=surgefoil"
        )
        XCTAssertNotEqual(graded, certified)
        XCTAssertNotEqual(graded, sealed)
    }

    func testMagicTreatmentPriceRowsReadThroughLegacyFoilPriceUntilRefresh() {
        let card = CollectedCard(
            collectionKey: "magic:printing#foil#treatment=surgefoil",
            game: .magic,
            providerID: "printing",
            name: "Fixture",
            setName: "Fixture Set",
            setCode: "FIC",
            cardNumber: "10",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .foil,
            variantResolution: .userConfirmed,
            magicTreatments: [.surgeFoil]
        )
        let genericKey = PriceRecord.key(
            game: .magic,
            printingID: "printing",
            variantID: PhysicalVariant.foil.id
        )
        let treatmentKey = PriceRecord.key(
            game: .magic,
            printingID: "printing",
            variantID: PhysicalVariant.foil.id,
            treatmentIDs: ["surgefoil"]
        )

        XCTAssertEqual(card.priceKey, treatmentKey)
        XCTAssertEqual(card.legacyPriceKeys, [genericKey])
        XCTAssertNotEqual(card.priceKey, genericKey)
        XCTAssertEqual(card.priceLookupKeys, [treatmentKey, genericKey])

        let genericRecord = PriceRecord(
            key: genericKey,
            game: .magic,
            printingID: "printing",
            variantID: PhysicalVariant.foil.id
        )
        genericRecord.unitMarketPriceUSD = 99
        XCTAssertEqual(
            PriceStore.record(
                for: card,
                in: [genericRecord.key: genericRecord]
            )?.effectiveUnitMarketPriceUSD,
            99
        )

        let nonfoil = CollectedCard(
            collectionKey: "magic:printing#nonfoil",
            game: .magic,
            providerID: "printing",
            name: "Fixture",
            setName: "Fixture Set",
            setCode: "FIC",
            cardNumber: "10",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .nonfoil,
            variantResolution: .userConfirmed,
            magicTreatments: [.surgeFoil]
        )
        XCTAssertEqual(
            nonfoil.priceKey,
            PriceRecord.key(
                game: .magic,
                printingID: "printing",
                variantID: PhysicalVariant.nonfoil.id
            )
        )
    }

    // REQ-004: identity tests must have fixtures that match production's
    // providerID/catalogProviderID split for graded and sealed rows.
    func testREQ004ProductionShapedGradedAndSealedFixturesExposeProductionIdentityFields() throws {
        let context = try makeContext()
        let graded = try ProductionRowFixtures.gradedRow(in: context)
        let scannedGraded = try ProductionRowFixtures.scannedGradedRow(in: context)
        let sealed = try ProductionRowFixtures.sealedRow(in: context)

        for row in [graded, scannedGraded, sealed] {
            XCTAssertEqual(row.providerID, row.collectionKey)
            XCTAssertNotNil(row.catalogProviderID)
            XCTAssertNotEqual(row.catalogProviderID, row.collectionKey)
        }
    }

    /// A certificate identifies one physical slab, so two of them never stack
    /// even at an identical grade from the same grader.
    func testCertifiedSlabsAreSeparateRows() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let card = try identifiedPokemonCard()
        let variant = GradedVariant(
            id: "g-uuid", company: .psa,
            grade: CardGrade(value: "10"),
            marketPriceUSD: 500, updatedAt: nil
        )

        let first = try! store.addGraded(
            underlying: card, variant: variant, certificationNumber: "11111111"
        )
        let second = try! store.addGraded(
            underlying: card, variant: variant, certificationNumber: "22222222"
        )

        XCTAssertTrue(first.didInsert)
        XCTAssertTrue(second.didInsert, "a second certificate is a second slab")
        XCTAssertNotEqual(first.collectionKey, second.collectionKey)

        let firstRow = try XCTUnwrap(store.card(forKey: first.collectionKey))
        let secondRow = try XCTUnwrap(store.card(forKey: second.collectionKey))
        XCTAssertEqual(firstRow.priceKey, secondRow.priceKey, "certificates do not split market identity")
        XCTAssertEqual(firstRow.priceStorageID, "justtcg:v2:g-uuid")
        let prices = try context.fetch(FetchDescriptor<PriceRecord>())
        XCTAssertEqual(prices.count, 1)
        XCTAssertEqual(prices.first?.unitMarketPriceUSD, 500)
        XCTAssertEqual(prices.first?.sourceVariantID, "g-uuid")
    }

    func testGradedPrintRunSurvivesThePickerPersistenceRoundTrip() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let card = try identifiedPokemonCard()
        let variant = GradedVariant(
            id: "first-edition-grade",
            company: .psa,
            grade: CardGrade(value: "10"),
            marketPriceUSD: 500,
            updatedAt: nil
        )

        let mutation = try store.addGraded(
            underlying: card,
            variant: variant,
            certificationNumber: nil,
            pokemonPrintRun: .firstEdition
        )
        let persisted = try XCTUnwrap(store.card(forKey: mutation.collectionKey))
        let refetched = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CollectedCard>()).first {
                $0.collectionKey == mutation.collectionKey
            }
        )

        XCTAssertEqual(persisted.pokemonPrintRun, .firstEdition)
        XCTAssertEqual(refetched.pokemonPrintRun, .firstEdition)
    }

    /// Without a certificate the app cannot tell two identical slabs apart, so
    /// they aggregate the way raw copies do.
    func testUncertifiedSlabsAggregate() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let card = try identifiedPokemonCard()
        let variant = GradedVariant(
            id: "g-uuid", company: .psa,
            grade: CardGrade(value: "10"),
            marketPriceUSD: 500, updatedAt: nil
        )

        let first = try! store.addGraded(underlying: card, variant: variant, certificationNumber: nil)
        let second = try! store.addGraded(underlying: card, variant: variant, certificationNumber: nil)

        XCTAssertTrue(first.didInsert)
        XCTAssertFalse(second.didInsert, "identical uncertified slabs stack")
        XCTAssertEqual(store.card(forKey: first.collectionKey)?.quantity, 2)
    }

    func testSealedProductsAggregate() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let artwork = try XCTUnwrap(URL(
            string: "https://tcgplayer-cdn.tcgplayer.com/product/98580_400w.jpg"
        ))
        let product = SealedProductSummary(
            id: "p-uuid", name: "Legendary Treasures Booster Box",
            setName: "Legendary Treasures", variantID: "v-uuid",
            marketPriceUSD: 18_750, updatedAt: nil, imageURL: artwork
        )

        let first = try! store.addSealed(product, game: .pokemon)
        let second = try! store.addSealed(product, game: .pokemon)

        XCTAssertTrue(first.didInsert)
        XCTAssertFalse(second.didInsert)
        let row = store.card(forKey: first.collectionKey)
        XCTAssertEqual(row?.quantity, 2)
        XCTAssertEqual(row?.itemKind, .sealedProduct)
        XCTAssertEqual(row?.itemKindLabel, "Sealed")
        XCTAssertEqual(row?.priceStorageID, "justtcg:v1:v-uuid")
        XCTAssertEqual(row?.imageURL, artwork.absoluteString)
        let price = try XCTUnwrap(
            PriceStore(context: context).record(forKey: try XCTUnwrap(row?.priceKey))
        )
        XCTAssertEqual(price.unitMarketPriceUSD, 18_750)
        XCTAssertEqual(price.sourceVariantID, "v-uuid")
    }

    func testReaddingSealedProductHealsLegacyMissingArtwork() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let withoutArtwork = SealedProductSummary(
            id: "p-uuid", name: "Legendary Treasures Booster Box",
            setName: "Legendary Treasures", variantID: "v-uuid",
            marketPriceUSD: 18_750, updatedAt: nil, imageURL: nil
        )
        let first = try! store.addSealed(withoutArtwork, game: .pokemon)
        let artwork = try XCTUnwrap(URL(
            string: "https://tcgplayer-cdn.tcgplayer.com/product/98580_400w.jpg"
        ))
        let withArtwork = SealedProductSummary(
            id: withoutArtwork.id, name: withoutArtwork.name,
            setName: withoutArtwork.setName, variantID: withoutArtwork.variantID,
            marketPriceUSD: withoutArtwork.marketPriceUSD,
            updatedAt: withoutArtwork.updatedAt, imageURL: artwork
        )

        _ = try! store.addSealed(withArtwork, game: .pokemon)

        XCTAssertEqual(store.card(forKey: first.collectionKey)?.imageURL, artwork.absoluteString)
    }

    func testNullPriceBatchStillBackfillsSealedArtworkAndIdentity() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let mutation = try! store.addSealed(
            SealedProductSummary(
                id: "p-uuid", name: "Legendary Treasures Booster Box",
                setName: "Legendary Treasures", variantID: "v-uuid",
                marketPriceUSD: nil, updatedAt: nil, imageURL: nil
            ),
            game: .pokemon
        )
        let row = try XCTUnwrap(store.card(forKey: mutation.collectionKey))
        let hit = try sealedBatchHit(tcgplayerID: "98580", price: nil)
        let owner = marketOwner(for: row)

        PriceRefreshController.applyVendorBatchHit(
            card: hit.card,
            variant: hit.variant,
            owners: [owner],
            store: PriceStore(context: context),
            identities: ProductIdentityStore(context: context),
            rowsByPriceKey: [row.priceKey: [row]],
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(
            row.imageURL,
            "https://tcgplayer-cdn.tcgplayer.com/product/98580_400w.jpg"
        )
        XCTAssertEqual(row.catalogMetadataVersion, CollectionCatalogNormalizer.metadataVersion)
        XCTAssertNil(ArtworkDiagnostics.reason(for: row))
        XCTAssertEqual(
            ProductIdentityStore(context: context).cachedVariantID(forKey: row.priceKey),
            "v-uuid"
        )
        XCTAssertNil(
            PriceStore(context: context).record(forKey: row.priceKey),
            "a null market price stays null while artwork and identity are retained"
        )
    }

    func testProviderWithoutArtworkBecomesTerminalInsteadOfRetryingForever() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let mutation = try! store.addSealed(
            SealedProductSummary(
                id: "p-uuid", name: "Artworkless Box", setName: "Set",
                variantID: "v-uuid", marketPriceUSD: 25,
                updatedAt: nil, imageURL: nil
            ),
            game: .pokemon
        )
        let row = try XCTUnwrap(store.card(forKey: mutation.collectionKey))
        let hit = try sealedBatchHit(tcgplayerID: nil, price: 25)

        PriceRefreshController.applyVendorBatchHit(
            card: hit.card,
            variant: hit.variant,
            owners: [marketOwner(for: row)],
            store: PriceStore(context: context),
            identities: ProductIdentityStore(context: context),
            rowsByPriceKey: [row.priceKey: [row]],
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertNil(row.imageURL)
        XCTAssertFalse(ArtworkDiagnostics.shouldRetrySealedArtwork(for: row))
        XCTAssertEqual(ArtworkDiagnostics.reason(for: row), .providerHasNoArtwork)
    }

    func testVendorBatchHitPersistsMarketplaceIdentityForIllustratedRows() throws {
        let context = try makeContext()
        let row = rawCard()
        row.imageURL = "https://example.com/already-illustrated.png"
        context.insert(row)
        try context.save()

        let hit = try sealedBatchHit(tcgplayerID: "98580", price: 25)
        let owner = MarketPriceTarget(
            priceKey: row.priceKey,
            game: row.cardGame,
            printingID: row.priceStorageID,
            variantID: row.variantID,
            itemKind: .rawCard,
            marketVariantID: nil,
            lookupCandidates: [],
            currentAmount: nil,
            lastCheckedAt: nil
        )

        PriceRefreshController.applyVendorBatchHit(
            card: hit.card,
            variant: hit.variant,
            owners: [owner],
            store: PriceStore(context: context),
            identities: ProductIdentityStore(context: context),
            rowsByPriceKey: [row.priceKey: [row]],
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(row.tcgplayerProductID, "98580")
        XCTAssertNotNil(
            TCGplayerLinkBuilder.url(for: row),
            "an illustrated row still needs the exact marketplace identity returned by the batch"
        )
    }

    func testExistingSealedRowFromOlderArtworkRulesGetsOneBackfill() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let mutation = try! store.addSealed(
            SealedProductSummary(
                id: "p-uuid", name: "Legacy Box", setName: "Set",
                variantID: "v-uuid", marketPriceUSD: 25,
                updatedAt: nil, imageURL: nil
            ),
            game: .pokemon
        )
        let row = try XCTUnwrap(store.card(forKey: mutation.collectionKey))
        row.catalogMetadataCheckedAt = .now
        row.catalogMetadataVersion = CollectionCatalogNormalizer.metadataVersion - 1

        XCTAssertTrue(ArtworkDiagnostics.shouldRetrySealedArtwork(for: row))
        XCTAssertEqual(ArtworkDiagnostics.reason(for: row), .lookupPending)
    }

    func testLegacySealedGatewayArtworkIsRepairedLocally() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let legacyURL = try XCTUnwrap(URL(
            string: "https://product-images.tcgplayer.com/fit-in/1000x1000/98580.jpg"
        ))
        let mutation = try! store.addSealed(
            SealedProductSummary(
                id: "p-uuid", name: "Legacy Box", setName: "Set",
                variantID: "v-uuid", marketPriceUSD: 25,
                updatedAt: nil, imageURL: legacyURL
            ),
            game: .pokemon
        )
        let row = try XCTUnwrap(store.card(forKey: mutation.collectionKey))

        XCTAssertEqual(
            CollectionCatalogNormalizer.migratedLegacySealedArtworkURL(from: row.imageURL),
            "https://tcgplayer-cdn.tcgplayer.com/product/98580_400w.jpg"
        )
    }

    // MARK: - Set completion

    func testSealedProductsNeverAffectSetCompletion() {
        XCTAssertFalse(CollectionItemKind.sealedProduct.countsTowardSetCompletion)
    }

    /// Owning a raw copy and three grades of one card is still one slot filled.
    func testRawAndGradedOwnershipOfOneCardCountsOnce() {
        let raw = CollectionRow(
            id: "raw", game: .pokemon, name: "Eevee", setCode: "PRE",
            setName: "Prismatic Evolutions", setReleaseOrder: 1, cardNumber: "001",
            variantID: "holo", variantLabel: "Holo", quantity: 1,
            dateAdded: .now, price: .unknown, itemKind: .rawCard, itemKindLabel: "Holo"
        )
        let graded = CollectionRow(
            id: "graded", game: .pokemon, name: "Eevee", setCode: "PRE",
            setName: "Prismatic Evolutions", setReleaseOrder: 1, cardNumber: "001",
            variantID: nil, variantLabel: nil, quantity: 1,
            dateAdded: .now, price: .unknown, itemKind: .gradedCard, itemKindLabel: "PSA 10"
        )
        let sealed = CollectionRow(
            id: "sealed", game: .pokemon, name: "Booster Box", setCode: "",
            setName: "Prismatic Evolutions", setReleaseOrder: 1, cardNumber: "",
            variantID: nil, variantLabel: nil, quantity: 1,
            dateAdded: .now, price: .unknown, itemKind: .sealedProduct, itemKindLabel: "Sealed"
        )

        let slots = Set([raw, graded, sealed].compactMap(\.setCompletionSlot))

        XCTAssertEqual(slots.count, 1, "one card, one slot, however many copies")
        XCTAssertNil(sealed.setCompletionSlot, "a box completes nothing")
    }

    // MARK: - Filtering

    func testItemKindFilterNarrowsToOneKind() {
        let rows = [
            CollectionRow(
                id: "a", game: .pokemon, name: "Eevee", setCode: "PRE", setName: "s",
                setReleaseOrder: 1, cardNumber: "1", variantID: nil, variantLabel: nil,
                quantity: 1, dateAdded: .now, price: .unknown, itemKind: .rawCard
            ),
            CollectionRow(
                id: "b", game: .pokemon, name: "Eevee", setCode: "PRE", setName: "s",
                setReleaseOrder: 1, cardNumber: "1", variantID: nil, variantLabel: nil,
                quantity: 1, dateAdded: .now, price: .unknown, itemKind: .gradedCard
            ),
            CollectionRow(
                id: "c", game: .pokemon, name: "Box", setCode: "", setName: "s",
                setReleaseOrder: 1, cardNumber: "", variantID: nil, variantLabel: nil,
                quantity: 1, dateAdded: .now, price: .unknown, itemKind: .sealedProduct
            )
        ]

        var filters = CollectionFilters.none
        filters.itemKinds = [.gradedCard]
        XCTAssertEqual(CollectionQuery.filter(rows, with: filters).map(\.id), ["b"])

        // Empty means every kind — that is what "All Items" selects.
        filters.itemKinds = []
        XCTAssertEqual(CollectionQuery.filter(rows, with: filters).count, 3)
    }

    // MARK: - Helpers

    private func identifiedPokemonCard() throws -> IdentifiedCard {
        let json = """
        {
          "id": "sv08.5-001", "localId": "001", "name": "Eevee",
          "set": { "id": "sv08.5", "name": "Prismatic Evolutions",
                   "cardCount": { "total": 180, "official": 131 } }
        }
        """
        return .pokemon(
            try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8)),
            setCode: "PRE"
        )
    }

    private func sealedBatchHit(
        tcgplayerID: String?,
        price: Double?
    ) throws -> (card: JustTCGCard, variant: JustTCGVariant) {
        let marketplace = tcgplayerID.map { "\"tcgplayerId\": \"\($0)\"," } ?? ""
        let amount = price.map { String($0) } ?? "null"
        let json = """
        {
          "data": [ {
            "id": "box", "uuid": "p-uuid", \(marketplace)
            "variants": [ {
              "uuid": "v-uuid", "condition": "Sealed", "price": \(amount)
            } ]
          } ]
        }
        """
        let response = try JSONDecoder().decode(
            JustTCGBatchResponse.self,
            from: Data(json.utf8)
        )
        let card = try XCTUnwrap(response.data.first)
        return (card, try XCTUnwrap(card.variants?.first))
    }

    private func marketOwner(for row: CollectedCard) -> MarketPriceTarget {
        MarketPriceTarget(
            priceKey: row.priceKey,
            game: row.cardGame,
            printingID: row.priceStorageID,
            variantID: row.variantID,
            itemKind: .sealedProduct,
            marketVariantID: row.justTCGVariantID,
            lookupCandidates: [],
            currentAmount: nil,
            lastCheckedAt: nil
        )
    }
}
