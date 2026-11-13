import Foundation
import SwiftData
import XCTest
@testable import TradingCardScanner

/// Foundation of unverified Pokémon reports: the report model, the fail-closed
/// key marker, price isolation, unverified acquisition, and the guards that keep
/// automatic processing away from report rows. Linking is a later stage.
@MainActor
final class UnverifiedReportTests: XCTestCase {

    // MARK: - Report model

    func testReportRoundTripsAndNormalizesStructuredFields() throws {
        let report = UnverifiedReport(
            kind: .knownCard,
            baseProviderID: "sv08.5-074",
            reportedFinishID: PhysicalVariant.holo.id,
            reportedStamps: ["Pre-Release", "pre-release"],
            note: "   ",
            catalogRevisionAtCreation: 7,
            knownVariantIDsAtCreation: ["reverse", "normal"]
        )
        XCTAssertEqual(report.reportedStamps, ["pre-release"])
        XCTAssertNil(report.note, "A blank note must not block automatic linking later")
        XCTAssertEqual(report.knownVariantIDsAtCreation, ["normal", "reverse"])

        let decoded = try XCTUnwrap(UnverifiedReport.decode(try report.encodedJSON()))
        XCTAssertEqual(decoded, report)
        XCTAssertTrue(decoded.isUnderstood)
        XCTAssertEqual(decoded.reviewState, .waiting)
        XCTAssertEqual(
            decoded.reportedVariant?.id,
            PokemonCatalogStampVariant.make(base: .holo, stamps: ["pre-release"])?.id
        )
    }

    func testNewerReportStaysReadableButIsNotActedOn() throws {
        let id = UUID()
        let json = """
        {"schemaVersion": 99, "reportID": "\(id.uuidString)", "kind": "knownCard",
         "baseProviderID": "sv08.5-074", "reportedFinishID": "holo",
         "createdAt": 784684800, "reviewStateRaw": "futureState",
         "someFutureField": {"x": 1}}
        """
        let report = try XCTUnwrap(UnverifiedReport.decode(json))
        XCTAssertFalse(report.isUnderstood)
        XCTAssertNil(report.reviewState)
        XCTAssertEqual(report.reportID, id)
    }

    // MARK: - Fail-closed marker and price isolation

    func testMarkerProtectsRowEvenWhenReportJSONIsMissingOrDamaged() {
        let reportID = UUID()
        let row = CollectedCard(
            collectionKey: CollectionStore.unverifiedCollectionKey(for: reportID),
            game: .pokemon,
            providerID: "sv08.5-074",
            name: "Eevee", setName: "Prismatic Evolutions", setCode: "PRE", cardNumber: "074",
            rarity: nil, imageURL: nil, thumbnailURL: nil,
            variant: nil, variantResolution: .userConfirmed
        )
        for json in [nil, "{not json", "{\"schemaVersion\": 1}"] as [String?] {
            row.unverifiedReportJSON = json
            XCTAssertNil(row.unverifiedReport)
            XCTAssertTrue(row.isUnverified)
            XCTAssertTrue(row.hasReport)
            // Even with the base card's provider id on the row, the price
            // identity is the report's own and no alias reaches the base card.
            XCTAssertTrue(row.priceStorageID.hasPrefix(UnverifiedReportKey.providerPrefix))
            XCTAssertNotEqual(
                row.priceKey,
                PriceRecord.key(game: .pokemon, printingID: "sv08.5-074", variantID: nil)
            )
            XCTAssertNil(row.resolvedCatalogPriceKey)
            XCTAssertEqual(row.legacyPriceKeys, [])
            XCTAssertFalse(CollectionCatalogNormalizer.needsNormalization(row))
        }

        let linked = UnverifiedReportKey.linkedKey(base: "sv08.5-074#holo", reportID: reportID)
        XCTAssertTrue(UnverifiedReportKey.hasReport(linked))
        XCTAssertFalse(UnverifiedReportKey.isUnverified(linked))
        XCTAssertEqual(UnverifiedReportKey.reportToken(in: linked), reportID.uuidString.lowercased())
    }

    func testUnverifiedCopiesStayUnpricedWhenTheBasePrintingHasAQuote() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let context = container.mainContext
        let store = CollectionStore(context: context)
        let card = try ProductionRowFixtures.pokemonCard()

        _ = try store.add(card, resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed))
        let verified = try XCTUnwrap(store.card(forKey: card.collectionKey(variant: .normal)))
        let record = PriceRecord(key: verified.priceKey, game: .pokemon,
                                 printingID: verified.priceStorageID, variantID: verified.variantID)
        record.unitMarketPriceUSD = 42
        context.insert(record)
        try context.save()

        // Sanity: with the quote in place, another verified copy is priced.
        let verifiedCopy = try store.add(card, resolved: ResolvedVariant(variant: .normal,
                                                                          resolution: .userConfirmed))
        let verifiedOperation = try XCTUnwrap(verifiedCopy.ledgerOperationIDs.first)
        let verifiedEvent = try XCTUnwrap(
            try context.fetch(FetchDescriptor<InventoryEvent>()).first { $0.operationID == verifiedOperation }
        )
        XCTAssertNotNil(verifiedEvent.unitPriceUSDTenThousandths)

        let report = knownReport(for: card)
        let mutation = try store.addUnverified(report: report, baseCard: card, quantity: 2)
        let row = try XCTUnwrap(store.card(forKey: mutation.collectionKey))

        XCTAssertTrue(row.isUnverified)
        XCTAssertEqual(row.providerID, UnverifiedReportKey.providerID(reportID: report.reportID))
        XCTAssertNil(row.catalogProviderID)
        XCTAssertNil(row.variantID)
        XCTAssertEqual(row.variantResolution, .userConfirmed)
        XCTAssertFalse(row.priceLookupKeys.contains(verified.priceKey))
        XCTAssertNil(PriceStore.record(for: row, in: [record.key: record]))

        let events = try context.fetch(FetchDescriptor<InventoryEvent>())
        let reportEvent = try XCTUnwrap(events.first { $0.collectionKey == row.collectionKey })
        XCTAssertEqual(reportEvent.deltaQuantity, 2)
        XCTAssertEqual(reportEvent.priceStorageKey, row.priceKey)
        XCTAssertNil(reportEvent.unitPriceUSDTenThousandths, "Acquired unpriced, not at the base card's quote")

        let targets = try PriceRefreshTargets.make(context: context, usesPriceFallback: false,
                                                   includeImported: true)
        XCTAssertFalse(targets.contains { $0.id == row.priceKey })
        XCTAssertTrue(targets.contains { $0.id == verified.priceKey })
    }

    // MARK: - Unverified acquisition

    func testEachReportIsItsOwnRowAndAnotherCopyIncrementsIt() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let context = container.mainContext
        let store = CollectionStore(context: context)
        let card = try ProductionRowFixtures.pokemonCard()

        let first = knownReport(for: card, stamps: ["pre-release"])
        let second = knownReport(for: card, stamps: ["pokemon-center"])
        let a = try store.addUnverified(report: first, baseCard: card)
        let b = try store.addUnverified(report: second, baseCard: card)
        XCTAssertNotEqual(a.collectionKey, b.collectionKey)
        XCTAssertTrue(a.didInsert && b.didInsert)

        let again = try store.addUnverified(report: first, baseCard: card, quantity: 2)
        XCTAssertFalse(again.didInsert)
        XCTAssertEqual(try store.card(forKey: a.collectionKey)?.quantity, 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectedCard>()), 2)

        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
            .filter { $0.collectionKey == a.collectionKey }
        XCTAssertEqual(activities.map(\.quantity).sorted(), [1, 2])
        XCTAssertTrue(activities.allSatisfy { $0.kind == .added && $0.ledgerOperationIDs.count == 1 })
    }

    func testUnknownSetReportKeepsTheObservedIdentityVerbatim() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let store = CollectionStore(context: container.mainContext)
        let report = UnverifiedReport(
            kind: .unknownSet,
            observed: .init(setCode: "MEG", setName: nil, number: "214", name: "Mega Lucario ex")
        )
        let mutation = try store.addUnverified(report: report, baseCard: nil)
        let row = try XCTUnwrap(store.card(forKey: mutation.collectionKey))
        XCTAssertEqual(row.setCode, "MEG")
        XCTAssertEqual(row.cardNumber, "214")
        XCTAssertEqual(row.name, "Mega Lucario ex")
        XCTAssertEqual(row.cardGame, .pokemon)
        XCTAssertEqual(row.identityResolution, .userSelectedPrinting)
        XCTAssertEqual(row.unverifiedReport?.reportID, report.reportID)
    }

    func testMalformedReportsAreRejectedWithoutWriting() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let context = container.mainContext
        let store = CollectionStore(context: context)
        let card = try ProductionRowFixtures.pokemonCard()

        var linked = knownReport(for: card)
        linked.linkedAt = .now
        var future = knownReport(for: card)
        future.schemaVersion = UnverifiedReport.currentSchemaVersion + 1
        let cases: [(UnverifiedReport, IdentifiedCard?)] = [
            (knownReport(for: card), nil),
            (UnverifiedReport(kind: .knownCard, baseProviderID: "other-001", reportedFinishID: "holo"), card),
            (UnverifiedReport(kind: .knownCard, baseProviderID: card.providerID), card),
            (UnverifiedReport(kind: .unknownSet, observed: .init(setCode: " ", number: "1")), nil),
            (UnverifiedReport(kind: .unknownSet, observed: .init(setCode: "MEG", number: "1")), card),
            (linked, card),
            (future, card)
        ]
        for (report, base) in cases {
            XCTAssertThrowsError(try store.addUnverified(report: report, baseCard: base))
        }
        XCTAssertThrowsError(try store.addUnverified(report: knownReport(for: card), baseCard: card, quantity: 0))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectedCard>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<InventoryEvent>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectionActivity>()), 0)
    }

    func testScannerWriterAddsUnverifiedCopiesThroughTheSerializedWrite() async throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let card = try ProductionRowFixtures.pokemonCard()
        let writer = await ScannerCollectionWriter.makeBackground(modelContainer: container)
        let mutation = try await writer.addUnverified(report: knownReport(for: card), baseCard: card)
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectedCard>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<InventoryEvent>()), 1)
        XCTAssertTrue(UnverifiedReportKey.isUnverified(mutation.collectionKey))
    }

    // MARK: - Automatic processing never reaches report rows

    func testOrdinaryAddOfTheBasePrintingNeverJoinsTheReportRow() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let context = container.mainContext
        let store = CollectionStore(context: context)
        let card = try ProductionRowFixtures.pokemonCard()
        let report = try store.addUnverified(report: knownReport(for: card), baseCard: card)

        _ = try store.add(card, resolved: ResolvedVariant(variant: nil, resolution: .catalogSilent),
                          matchCatalogAliases: true)
        XCTAssertEqual(try store.card(forKey: report.collectionKey)?.quantity, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectedCard>()), 2)
    }

    func testReportRowsCannotBeRekeyedOrMergedAutomatically() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let store = CollectionStore(context: container.mainContext)
        let card = try ProductionRowFixtures.pokemonCard()
        let mutation = try store.addUnverified(report: knownReport(for: card), baseCard: card)
        let row = try XCTUnwrap(store.card(forKey: mutation.collectionKey))

        XCTAssertThrowsError(try store.rekey(row, to: card.collectionKey(variant: nil)))
        XCTAssertEqual(row.collectionKey, mutation.collectionKey)

        _ = try store.add(card, resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed))
        XCTAssertThrowsError(try store.rekey(row, to: card.collectionKey(variant: .normal)))
        XCTAssertEqual(try store.card(forKey: mutation.collectionKey)?.quantity, 1)
        XCTAssertEqual(try store.card(forKey: card.collectionKey(variant: .normal))?.quantity, 1)
    }

    func testFinishReconciliationNeverConsidersUnverifiedRows() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let store = CollectionStore(context: container.mainContext)
        let card = try ProductionRowFixtures.pokemonCard()
        let mutation = try store.addUnverified(report: knownReport(for: card), baseCard: card)
        let row = try XCTUnwrap(store.card(forKey: mutation.collectionKey))
        // A finish-less catalog row of the same printing is exactly what the
        // backfill exists for; the report row beside it must never be touched.
        _ = try store.add(card, resolved: ResolvedVariant(variant: nil, resolution: .catalogSilent))
        let base = try XCTUnwrap(store.card(forKey: card.collectionKey(variant: nil)))
        let targets = try PriceRefreshTargets.make(context: container.mainContext,
                                                   usesPriceFallback: false, includeImported: true)
        XCTAssertFalse(targets.isEmpty)
        let repairs = PokemonFinishReconciliation.candidates(targets: targets, card: card,
                                                             rows: [base, row])
        XCTAssertFalse(repairs.contains { $0.collectionKey == row.collectionKey })
        let assessment = PokemonFinishReconciliation.assess(targets: targets, card: card,
                                                          rows: [base, row], refreshID: UUID(), at: .now)
        XCTAssertFalse(assessment.repairs.contains { $0.collectionKey == row.collectionKey })
        XCTAssertFalse(assessment.pendingPatches.contains { $0.collectionKey == row.collectionKey })
    }

    // MARK: - Removal and restore

    func testRemovalSnapshotRestoresTheReportAndItsKey() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let context = container.mainContext
        let store = CollectionStore(context: context)
        let card = try ProductionRowFixtures.pokemonCard()
        let report = knownReport(for: card)
        let mutation = try store.addUnverified(report: report, baseCard: card)
        let row = try XCTUnwrap(store.card(forKey: mutation.collectionKey))

        let snapshot = try store.remove(row)
        XCTAssertNotNil(snapshot.unverifiedReportJSON)
        XCTAssertNil(try store.card(forKey: mutation.collectionKey))

        let roundTripped = try JSONDecoder().decode(RemovedCardSnapshot.self,
                                                    from: JSONEncoder().encode(snapshot))
        try store.restore(roundTripped)
        let restored = try XCTUnwrap(store.card(forKey: mutation.collectionKey))
        XCTAssertTrue(restored.isUnverified)
        XCTAssertEqual(restored.unverifiedReport?.reportID, report.reportID)
        XCTAssertTrue(restored.priceStorageID.hasPrefix(UnverifiedReportKey.providerPrefix))
    }

    // MARK: - Linking

    func testLinkMovesTheWholeRowThroughDatedCorrectionsAndUndoRestoresIt() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let context = container.mainContext
        let store = CollectionStore(context: context)
        let base = try ProductionRowFixtures.pokemonCard()
        let updated = try eeveeWithHolo()

        // An ordinary verified holding of the same variant must stay separate.
        _ = try store.add(updated, resolved: .init(variant: .holo, resolution: .userConfirmed), quantity: 3)
        let ordinary = try XCTUnwrap(store.card(forKey: updated.collectionKey(variant: .holo)))
        let record = PriceRecord(key: ordinary.priceKey, game: .pokemon,
                                 printingID: ordinary.priceStorageID, variantID: ordinary.variantID)
        record.unitMarketPriceUSD = 10
        context.insert(record)
        try context.save()

        let report = knownReport(for: base, stamps: [])
        let unverifiedKey = try store.addUnverified(report: report, baseCard: base, quantity: 2).collectionKey
        _ = try store.addUnverified(report: report, baseCard: base, quantity: 1)
        let unverifiedPriceKey = try XCTUnwrap(store.card(forKey: unverifiedKey)?.priceKey)
        let json = try XCTUnwrap(store.card(forKey: unverifiedKey)?.unverifiedReportJSON)
        let acquisitions = try context.fetch(FetchDescriptor<InventoryEvent>())
            .filter { $0.collectionKey == unverifiedKey }
        XCTAssertEqual(acquisitions.count, 2)

        let linkedAt = Date.now.addingTimeInterval(60)
        let link = try store.linkUnverified(reportID: report.reportID, expectedReportJSON: json, to: updated,
            variant: .holo, resolution: .linkedFromReport, setReleaseOrder: 7, linkedAt: linkedAt)
        let linkedKey = UnverifiedReportKey.linkedKey(base: updated.collectionKey(variant: .holo),
                                                      reportID: report.reportID)
        XCTAssertEqual(link.collectionKey, linkedKey)
        XCTAssertEqual(link.ledgerOperationIDs.count, 2, "One dated correction per acquisition")

        let linked = try XCTUnwrap(store.card(forKey: linkedKey))
        XCTAssertNil(try store.card(forKey: unverifiedKey))
        XCTAssertFalse(linked.isUnverified)
        XCTAssertTrue(linked.hasReport)
        XCTAssertEqual(linked.quantity, 3)
        XCTAssertEqual(linked.providerID, updated.providerID)
        XCTAssertEqual(linked.variantID, PhysicalVariant.holo.id)
        XCTAssertEqual(linked.variantResolution, .linkedFromReport)
        XCTAssertEqual(linked.priceKey, ordinary.priceKey, "Prices like the verified card")
        XCTAssertEqual(linked.unverifiedReport?.linkedAt, linkedAt)
        XCTAssertEqual(linked.unverifiedReport?.preLinkIdentity?.collectionKey, unverifiedKey)
        XCTAssertEqual(try store.card(forKey: ordinary.collectionKey)?.quantity, 3, "Never merged")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectedCard>()), 2)

        var events = try context.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(net(events, unverifiedKey), 0)
        XCTAssertEqual(net(events, linkedKey), 3)
        XCTAssertTrue(acquisitions.allSatisfy { $0.collectionKey == unverifiedKey && $0.priceStorageKey == unverifiedPriceKey },
                      "History is appended to, never rewritten")
        let corrections = events.filter { $0.kind == .correction }
        XCTAssertEqual(corrections.count, 4)
        XCTAssertTrue(corrections.allSatisfy { $0.occurredAt == linkedAt })
        XCTAssertEqual(held(events, asOf: linkedAt.addingTimeInterval(-1), keys: [unverifiedKey, linkedKey]), [unverifiedPriceKey: 3])
        XCTAssertEqual(held(events, asOf: linkedAt, keys: [unverifiedKey, linkedKey]), [ordinary.priceKey: 3])
        let history = try context.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertFalse(history.contains { $0.collectionKey == unverifiedKey })

        // The same link again changes nothing.
        _ = try store.linkUnverified(reportID: report.reportID, expectedReportJSON: json, to: updated,
            variant: .holo, resolution: .linkedFromReport, setReleaseOrder: 7, linkedAt: linkedAt)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<InventoryEvent>()), events.count)

        let unlinkedAt = linkedAt.addingTimeInterval(60)
        try store.unlinkReport(reportID: report.reportID, unlinkedAt: unlinkedAt)
        let restored = try XCTUnwrap(store.card(forKey: unverifiedKey))
        XCTAssertNil(try store.card(forKey: linkedKey))
        XCTAssertTrue(restored.isUnverified)
        XCTAssertEqual(restored.quantity, 3)
        XCTAssertEqual(restored.providerID, UnverifiedReportKey.providerID(reportID: report.reportID))
        XCTAssertNil(restored.variantID)
        XCTAssertEqual(restored.variantResolution, .userConfirmed)
        XCTAssertEqual(restored.name, base.name)
        XCTAssertEqual(restored.priceKey, unverifiedPriceKey)
        let reverted = try XCTUnwrap(restored.unverifiedReport)
        XCTAssertNil(reverted.linkedAt)
        XCTAssertNil(reverted.preLinkIdentity)
        XCTAssertEqual(reverted.unlinkedAt, unlinkedAt)
        XCTAssertEqual(reverted.reviewState, .needsReview)

        events = try context.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(net(events, unverifiedKey), 3)
        XCTAssertEqual(net(events, linkedKey), 0)
        XCTAssertEqual(held(events, asOf: linkedAt.addingTimeInterval(1), keys: [unverifiedKey, linkedKey]), [ordinary.priceKey: 3])
        XCTAssertEqual(held(events, asOf: unlinkedAt, keys: [unverifiedKey, linkedKey]), [unverifiedPriceKey: 3])
        XCTAssertEqual(try store.card(forKey: ordinary.collectionKey)?.quantity, 3)
    }

    func testLinkedCopiesRemoveThroughNormalLineageAndThenUndoIsUnavailable() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let context = container.mainContext
        let store = CollectionStore(context: context)
        let base = try ProductionRowFixtures.pokemonCard()
        let report = knownReport(for: base, stamps: [])
        let key = try store.addUnverified(report: report, baseCard: base).collectionKey
        _ = try store.addUnverified(report: report, baseCard: base)
        let json = try XCTUnwrap(store.card(forKey: key)?.unverifiedReportJSON)
        let link = try store.linkUnverified(reportID: report.reportID, expectedReportJSON: json, to: try eeveeWithHolo(),
            variant: .holo, resolution: .linkedFromReport, setReleaseOrder: 0)

        let claim = try XCTUnwrap(context.fetch(FetchDescriptor<CollectionActivity>())
            .first { $0.collectionKey == link.collectionKey && $0.kind == .added })
        _ = try store.remove(claim)
        XCTAssertEqual(try store.card(forKey: link.collectionKey)?.quantity, 1)
        XCTAssertThrowsError(try store.unlinkReport(reportID: report.reportID)) { error in
            guard case .reportLinkUnavailable = error as? CollectionStoreError else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try store.card(forKey: link.collectionKey)?.isUnverified, false)
    }

    func testReportStaysUnverifiedWhenAnyAcquisitionIsNotIntact() throws {
        for change in ["removed", "stepper"] {
            let container = try ProductionRowFixtures.makeContainer()
            let context = container.mainContext
            let store = CollectionStore(context: context)
            let base = try ProductionRowFixtures.pokemonCard()
            let report = knownReport(for: base, stamps: [])
            let key = try store.addUnverified(report: report, baseCard: base).collectionKey
            _ = try store.addUnverified(report: report, baseCard: base)
            let row = try XCTUnwrap(store.card(forKey: key))
            if change == "removed" {
                let claim = try XCTUnwrap(context.fetch(FetchDescriptor<CollectionActivity>()).first)
                _ = try store.remove(claim)
            } else {
                _ = try store.setQuantity(3, for: row)
            }
            let json = try XCTUnwrap(store.card(forKey: key)?.unverifiedReportJSON)
            let eventsBefore = try context.fetchCount(FetchDescriptor<InventoryEvent>())
            XCTAssertThrowsError(try store.linkUnverified(reportID: report.reportID, expectedReportJSON: json,
                to: try eeveeWithHolo(), variant: .holo, resolution: .linkedFromReport, setReleaseOrder: 0)) { error in
                guard case .reportLinkUnavailable = error as? CollectionStoreError else { return XCTFail("\(change): \(error)") }
            }
            XCTAssertEqual(try store.card(forKey: key)?.isUnverified, true, change)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<InventoryEvent>()), eventsBefore, change)
        }
    }

    func testStaleReportOrInvalidProvenanceStopsTheLink() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let store = CollectionStore(context: container.mainContext)
        let base = try ProductionRowFixtures.pokemonCard()
        let report = knownReport(for: base, stamps: [])
        let key = try store.addUnverified(report: report, baseCard: base).collectionKey
        let json = try XCTUnwrap(store.card(forKey: key)?.unverifiedReportJSON)
        XCTAssertThrowsError(try store.linkUnverified(reportID: report.reportID, expectedReportJSON: json + " ",
            to: try eeveeWithHolo(), variant: .holo, resolution: .linkedFromReport, setReleaseOrder: 0)) {
            XCTAssertEqual($0 as? CollectionStoreError, .staleReport)
        }
        // An automatic link always names a finish.
        XCTAssertThrowsError(try store.linkUnverified(reportID: report.reportID, expectedReportJSON: json,
            to: try eeveeWithHolo(), variant: nil, resolution: .linkedFromReport, setReleaseOrder: 0))
        XCTAssertEqual(try store.card(forKey: key)?.isUnverified, true)
    }

    func testUnknownSetLinkWithoutAFinishIsUserConfirmedAndReplacesTheIdentity() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let store = CollectionStore(context: container.mainContext)
        let report = UnverifiedReport(kind: .unknownSet,
            observed: .init(setCode: "PRE", setName: nil, number: "074", name: "Eevee"))
        let key = try store.addUnverified(report: report, baseCard: nil).collectionKey
        let json = try XCTUnwrap(store.card(forKey: key)?.unverifiedReportJSON)
        let target = try ProductionRowFixtures.pokemonCard()
        let link = try store.linkUnverified(reportID: report.reportID, expectedReportJSON: json, to: target,
            variant: nil, resolution: .userConfirmed, setReleaseOrder: 0)
        let row = try XCTUnwrap(store.card(forKey: link.collectionKey))
        XCTAssertEqual(row.providerID, target.providerID)
        XCTAssertNil(row.variantID)
        XCTAssertEqual(row.variantResolution, .userConfirmed)
        XCTAssertFalse(row.priceStorageID.hasPrefix(UnverifiedReportKey.providerPrefix))
    }

    func testLinkedRowWithUnreadableReportStaysPricedAndOffersNoUndo() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let store = CollectionStore(context: container.mainContext)
        let base = try ProductionRowFixtures.pokemonCard()
        let report = knownReport(for: base, stamps: [])
        let key = try store.addUnverified(report: report, baseCard: base).collectionKey
        let json = try XCTUnwrap(store.card(forKey: key)?.unverifiedReportJSON)
        let link = try store.linkUnverified(reportID: report.reportID, expectedReportJSON: json, to: try eeveeWithHolo(),
            variant: .holo, resolution: .linkedFromReport, setReleaseOrder: 0)
        let row = try XCTUnwrap(store.card(forKey: link.collectionKey))
        row.unverifiedReportJSON = "{damaged"
        try container.mainContext.save()
        XCTAssertFalse(row.isUnverified)
        XCTAssertEqual(row.priceStorageID, row.providerID)
        XCTAssertThrowsError(try store.unlinkReport(reportID: report.reportID))
        XCTAssertEqual(try store.card(forKey: link.collectionKey)?.quantity, 1)
    }

    func testCSVKeepsTheReportOnExportAndNeverMergesItOnImport() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let context = container.mainContext
        let store = CollectionStore(context: context)
        let base = try ProductionRowFixtures.pokemonCard()
        let report = knownReport(for: base, stamps: [])
        let unverified = try store.addUnverified(report: report, baseCard: base).collectionKey
        let other = knownReport(for: base, stamps: [])
        let otherKey = try store.addUnverified(report: other, baseCard: base).collectionKey
        let otherJSON = try XCTUnwrap(store.card(forKey: otherKey)?.unverifiedReportJSON)
        let linkedKey = try store.linkUnverified(reportID: other.reportID, expectedReportJSON: otherJSON,
            to: try eeveeWithHolo(), variant: .holo, resolution: .linkedFromReport, setReleaseOrder: 0).collectionKey

        let rows = try context.fetch(FetchDescriptor<CollectedCard>())
        let document = CollectionCSV.export(rows)
        XCTAssertTrue(document.text.split(separator: "\n")[0].hasSuffix(",unverified_report"))
        XCTAssertTrue(document.text.contains(report.reportID.uuidString.lowercased()))

        let eventsBefore = try context.fetchCount(FetchDescriptor<InventoryEvent>())
        let plan = try CollectionCSV.parse(Data(document.text.utf8))
        let result = try CollectionCSV.apply(plan, to: context)
        XCTAssertEqual(result.importedQuantity, 0)
        XCTAssertEqual(result.failedRows.count, 2)
        XCTAssertEqual(try store.card(forKey: unverified)?.quantity, 1)
        XCTAssertEqual(try store.card(forKey: linkedKey)?.quantity, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectedCard>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<InventoryEvent>()), eventsBefore)
    }

    func testReportADifferentVariantMovesOneIntactAcquisition() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let context = container.mainContext
        let store = CollectionStore(context: context)
        let card = try ProductionRowFixtures.pokemonCard()
        let first = try store.add(card, resolved: .init(variant: .normal, resolution: .userConfirmed))
        _ = try store.add(card, resolved: .init(variant: .normal, resolution: .userConfirmed))
        let verifiedKey = first.collectionKey
        let firstActivity = try XCTUnwrap(first.activityID)

        let report = knownReport(for: card, stamps: [])
        let moved = try store.moveAcquisitionToReport(activityID: firstActivity, report: report, baseCard: card)
        XCTAssertTrue(UnverifiedReportKey.isUnverified(moved.collectionKey))
        XCTAssertEqual(try store.card(forKey: verifiedKey)?.quantity, 1)
        XCTAssertEqual(try store.card(forKey: moved.collectionKey)?.quantity, 1)
        let events = try context.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(net(events, verifiedKey), 1)
        XCTAssertEqual(net(events, moved.collectionKey), 1)
        let claim = try XCTUnwrap(context.fetch(FetchDescriptor<CollectionActivity>()).first { $0.id == firstActivity })
        XCTAssertEqual(claim.collectionKey, moved.collectionKey)

        // The moved copy is an intact claim, so the report can still link.
        let json = try XCTUnwrap(store.card(forKey: moved.collectionKey)?.unverifiedReportJSON)
        XCTAssertNoThrow(try store.linkUnverified(reportID: report.reportID, expectedReportJSON: json,
            to: try eeveeWithHolo(), variant: .holo, resolution: .linkedFromReport, setReleaseOrder: 0))
    }

    func testReportADifferentVariantIsBlockedForAPartlyConsumedAcquisition() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let context = container.mainContext
        let store = CollectionStore(context: context)
        let card = try ProductionRowFixtures.pokemonCard()
        let added = try store.add(card, resolved: .init(variant: .normal, resolution: .userConfirmed), quantity: 2)
        _ = try store.add(card, resolved: .init(variant: .normal, resolution: .userConfirmed), quantity: 2)
        _ = try store.remove(collectionKey: added.collectionKey, quantity: 1)
        let consumed = try XCTUnwrap(context.fetch(FetchDescriptor<CollectionActivity>())
            .first { $0.kind == .added && $0.resolvedQuantity > 0 && $0.remainingQuantity > 0 },
            "Removing one copy partly consumes one acquisition")
        let eventsBefore = try context.fetchCount(FetchDescriptor<InventoryEvent>())
        XCTAssertThrowsError(try store.moveAcquisitionToReport(activityID: consumed.id,
            report: knownReport(for: card, stamps: []), baseCard: card))
        XCTAssertEqual(try store.card(forKey: added.collectionKey)?.quantity, 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<InventoryEvent>()), eventsBefore)
        XCTAssertFalse(try context.fetch(FetchDescriptor<CollectedCard>()).contains(where: \.hasReport))
    }

    // MARK: - Evaluation

    func testEvaluatorLinksOnlyOnGenuinelyNewUnambiguousEvidence() throws {
        let base = try ProductionRowFixtures.pokemonCard()
        let updated = try eeveeWithHolo()
        let report = knownReport(for: base, stamps: [])
        typealias E = UnverifiedReportEvaluator
        XCTAssertEqual(E.evaluate(report, catalogRevision: 1, baseCard: updated), .waiting, "Same revision")
        XCTAssertEqual(E.evaluate(report, catalogRevision: 2, baseCard: updated), .autoLink(.holo))
        XCTAssertEqual(E.evaluate(report, catalogRevision: 2, baseCard: base), .needsReview(.noCatalogMatch))

        var known = report
        known.knownVariantIDsAtCreation.append(PhysicalVariant.holo.id)
        XCTAssertEqual(E.evaluate(known, catalogRevision: 2, baseCard: updated), .needsReview(.matchAlreadyKnown))

        let described = UnverifiedReport(kind: .knownCard, baseProviderID: base.providerID,
            reportedFinishID: PhysicalVariant.holo.id, note: "Gold border", catalogRevisionAtCreation: 1)
        XCTAssertEqual(E.evaluate(described, catalogRevision: 2, baseCard: updated), .needsReview(.describedByCollector))

        var unlinked = report
        unlinked.unlinkedAt = .now
        XCTAssertEqual(E.evaluate(unlinked, catalogRevision: 2, baseCard: updated), .needsReview(.previouslyUnlinked))

        let unknown = UnverifiedReport(kind: .unknownSet,
            observed: .init(setCode: "PRE", setName: nil, number: "074", name: nil), catalogRevisionAtCreation: 1)
        XCTAssertEqual(E.evaluate(unknown, catalogRevision: 2, baseCard: nil), .waiting)
        XCTAssertEqual(E.evaluate(unknown, catalogRevision: 2, baseCard: nil, unknownSetMatch: base),
                       .needsReview(.unknownSetResolved))
    }

    func testReconcilerAutoLinksOnceAndMarksUnlinkableReports() async throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let base = try ProductionRowFixtures.pokemonCard()
        let updated = try eeveeWithHolo()
        let writer = await ScannerCollectionWriter.makeBackground(modelContainer: container)
        let linkable = knownReport(for: base, stamps: [])
        _ = try await writer.addUnverified(report: linkable, baseCard: base)
        let blocked = knownReport(for: base, stamps: [])
        let blockedKey = try await writer.addUnverified(report: blocked, baseCard: base).collectionKey
        _ = try await writer.addUnverified(report: blocked, baseCard: base)
        do {
            let context = ModelContext(container)
            let claim = try XCTUnwrap(context.fetch(FetchDescriptor<CollectionActivity>())
                .first { $0.collectionKey == blockedKey })
            _ = try CollectionStore(context: context).remove(claim)
        }
        let stored = try XCTUnwrap(UnverifiedReport.decode(
            ModelContext(container).fetch(FetchDescriptor<CollectedCard>()).first { $0.collectionKey == blockedKey }?
                .unverifiedReportJSON))
        XCTAssertEqual(stored.knownVariantIDsAtCreation, UnverifiedReportEvaluator.knownVariantIDs(for: base).sorted(),
                       "Stamped by the write, not trusted from the caller")
        XCTAssertFalse(stored.knownVariantIDsAtCreation.contains(PhysicalVariant.holo.id))

        let reconciler = UnverifiedReportReconciler(writer: writer,
            baseCard: { $0 == updated.providerID ? updated : nil }, unknownSetMatch: { _ in nil })
        let first = try await reconciler.run(catalogRevision: 2)
        XCTAssertEqual(first.linked, [linkable.reportID])
        XCTAssertEqual(first.linkUnavailable, [blocked.reportID])
        let second = try await reconciler.run(catalogRevision: 2)
        XCTAssertEqual(second, .init(), "Already evaluated against this revision")

        let rows = try ModelContext(container).fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.filter(\.isUnverified).count, 1)
        XCTAssertEqual(rows.first { $0.isUnverified }?.unverifiedReport?.reviewState, .linkUnavailable)
        XCTAssertEqual(rows.first { !$0.isUnverified }?.variantResolution, .linkedFromReport)
    }

    // MARK: - Helpers

    private func eeveeWithHolo() throws -> IdentifiedCard {
        let json = """
        {"id":"sv08.5-074","localId":"074","name":"Eevee","image":"https://assets.tcgdex.net/en/sv/sv08.5/074",
         "set":{"id":"sv08.5","name":"Prismatic Evolutions","cardCount":{"total":180,"official":131}},
         "variants":{"firstEdition":false,"holo":true,"normal":true,"reverse":true}}
        """
        return .pokemon(try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8)), setCode: "PRE")
    }

    private func net(_ events: [InventoryEvent], _ key: String) -> Int {
        events.filter { $0.collectionKey == key }.reduce(0) { $0 + $1.deltaQuantity }
    }

    /// Copies held per price instrument as of a date: what replay values.
    private func held(_ events: [InventoryEvent], asOf date: Date, keys: Set<String>) -> [String: Int] {
        events.filter { $0.occurredAt <= date && keys.contains($0.collectionKey) }
            .reduce(into: [String: Int]()) { $0[$1.priceStorageKey, default: 0] += $1.deltaQuantity }
            .filter { $0.value != 0 }
    }

    private func knownReport(for card: IdentifiedCard, stamps: [String] = ["pre-release"]) -> UnverifiedReport {
        UnverifiedReport(
            kind: .knownCard,
            baseProviderID: card.providerID,
            reportedFinishID: PhysicalVariant.holo.id,
            reportedStamps: stamps,
            catalogRevisionAtCreation: 1,
            knownVariantIDsAtCreation: [PhysicalVariant.normal.id, PhysicalVariant.reverse.id]
        )
    }
}
