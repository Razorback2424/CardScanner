import Foundation
import XCTest
@testable import TradingCardScanner

final class LorcanaDiscoveryCatalogTests: XCTestCase {
    func testEverySourceCardIsBrowsableWithArtworkAndFinishMetadata() async throws {
        let catalog = try LorcanaDiscoveryCatalog.bundled.get()
        XCTAssertEqual(catalog.cardsByID.values.filter { $0.id.hasPrefix("lorcanajson:") }.count, 3_556)
        XCTAssertEqual(catalog.cardsByID.count, 3_582)
        var seen: Set<String> = []
        for set in try await catalog.sets() {
            var cursor: String?
            var count = 0
            repeat {
                let page = try await catalog.cards(in: set, cursor: cursor)
                for summary in page.items {
                    XCTAssertTrue(seen.insert(summary.providerID).inserted)
                    let detail = try await catalog.details(for: summary)
                    let source = try XCTUnwrap(catalog.cardsByID[summary.providerID])
                    XCTAssertEqual(detail.card.name, source.name)
                    XCTAssertEqual(detail.card.identifier, source.printedIdentifier)
                    XCTAssertEqual(detail.card.variantEvidence.catalogVariants, source.variants)
                    XCTAssertNotNil(summary.imageURL)
                    count += 1
                }
                cursor = page.nextCursor
            } while cursor != nil
            XCTAssertEqual(count, set.cardCount)
        }
        XCTAssertEqual(seen, Set(catalog.cardsByID.keys))
    }

    func testEveryNumberedEnglishCardRecognizesItsRealFooterAndIsFound() async throws {
        let catalog = try LorcanaDiscoveryCatalog.bundled.get()
        let recognizer = LorcanaDiscoveryRecognizer(catalog: catalog)
        for row in catalog.cardsByID.values where row.footer != nil {
            guard case let .identified(subject) = recognizer.identify([.init(text: row.printedIdentifier)]) else {
                XCTFail("Unrecognized \(row.id): \(row.printedIdentifier)"); continue
            }
            XCTAssertEqual(subject.identifier.catalogGeneration, catalog.generation)
            guard case let .needsPrintingChoice(_, choices) = try await catalog.lookup(subject.identifier),
                  let choice = choices.first(where: { $0.id == row.id }) else {
                XCTFail("Missing \(row.id): \(row.printedIdentifier)"); continue
            }
            let found = try await catalog.resolve(choice, for: subject.identifier)
            XCTAssertEqual(found.card.name, row.name)
            XCTAssertEqual(found.card.physicalPrintingID, row.id)
            do {
                try await catalog.validateAcquisition(subject.identifier, printingID: row.id, automatic: true)
                XCTFail("Discovery must not grant physical acquisition authority")
            } catch CatalogLookupError.catalogIncomplete {}
        }
    }

    func testDalmatiansAndPromoArtworkSuffixesRemainDistinct() async throws {
        let catalog = try LorcanaDiscoveryCatalog.bundled.get()
        let recognizer = LorcanaDiscoveryRecognizer(catalog: catalog)
        var identifiers: Set<ScanIdentifier> = []
        for number in ["4a", "4b", "4c", "4d", "4e"] {
            guard case let .identified(subject) = recognizer.identify([.init(text: "\(number)/204 • EN • 3")]) else { return XCTFail() }
            identifiers.insert(subject.identifier)
        }
        XCTAssertEqual(identifiers.count, 5)
        for text in ["24A/P2 • EN • 7", "24B/P2 • EN • 7", "1 TFC • EN • 2/P1"] {
            guard case let .identified(subject) = recognizer.identify([.init(text: text)]) else { return XCTFail(text) }
            guard case .needsPrintingChoice = try await catalog.lookup(subject.identifier) else { return XCTFail(text) }
        }
    }

    func testObservedNativeOCRHyphensAndNumericConfusionsStayBoundToCatalog() async throws {
        let catalog = try LorcanaDiscoveryCatalog.bundled.get()
        let recognizer = LorcanaDiscoveryRecognizer(catalog: catalog)
        // Three public-image macOS Vision CPU readings; raw OCR logs/artwork
        // remain temporary. Expected identities come from reviewed image joins.
        for (text, id) in [("S7/P3 - EN - 12", "lorcanajson:en:3250"),
                           ("58/P3 - EN - 13", "lorcanajson:en:3235"),
                           ("60/P3 - EN - 13", "lorcanajson:en:3236")] {
            guard case let .identified(subject) = recognizer.identify([.init(text: text)]) else { return XCTFail(text) }
            guard case let .needsPrintingChoice(_, choices) = try await catalog.lookup(subject.identifier) else { return XCTFail() }
            XCTAssertTrue(choices.contains { $0.id == id })
        }
        XCTAssertEqual(recognizer.identify([.init(text: "S7/P3 - EN - 99")]), .nothing)
        guard case let .identified(subject) = recognizer.identify([.init(text: "207I/204 - EN - 1")]) else { return XCTFail() }
        XCTAssertEqual(subject.identifier.displayIdentifier, "207I/204 EN 1")
        guard case .catalogIncomplete(nil) = try await catalog.lookup(subject.identifier) else { return XCTFail("A suffix must not become collector 2071") }
        XCTAssertTrue(recognizer.needsFullCardText(afterFooterLines: [.init(text: "EN - Q1")]))
    }

    func testAmbiguousNumericAndArtworkSuffixRepairsCannotPickAPrinting() throws {
        let families = try ["58", "5B"].map { number in
            LorcanaPrintFamily(footer: try .init(collectorNumber: number, denominator: "204", language: "en", printedSetMarker: "1"),
                providerSetCode: "1", name: "Fixture", version: nil, rarity: "Fixture", layout: "normal",
                sourceAliases: [.init(provider: "fixture", id: number)], footerEvidenceReference: "fixture:footer")
        }
        let registry = try LorcanaCatalogRegistry(manifest: .init(schemaVersion: 1, printFamilies: families))
        XCTAssertEqual(LorcanaRecognitionAdapter(registry: registry).identify([.init(text: "SB/204 - EN - 1")]), .ambiguous)
    }

    func testUnnumberedQuestTokenRequiresItsTitleAndFooter() async throws {
        let catalog = try LorcanaDiscoveryCatalog.bundled.get()
        let recognizer = LorcanaDiscoveryRecognizer(catalog: catalog)
        XCTAssertEqual(recognizer.identify([.init(text: "Vine Tendril")]), .nothing)
        XCTAssertEqual(recognizer.identify([.init(text: "EN • Q3")]), .nothing)
        guard case let .identified(subject) = recognizer.identify([.init(text: "Vine Tendril"), .init(text: "EN • Q3")]) else { return XCTFail() }
        guard case let .needsPrintingChoice(_, choices) = try await catalog.lookup(subject.identifier) else { return XCTFail() }
        XCTAssertEqual(choices.map(\.id), ["lorcanajson:en:3551"])
        XCTAssertEqual(recognizer.identify([.init(text: "Vine Tendril"), .init(text: "EN • Q3"),
            .init(text: "1/204 • EN • 1")]), .ambiguous)
    }

    func testSealedInventoryIsCompleteOfflineAndHasNoFabricatedPricesOrVendorVariants() async throws {
        let catalog = try LorcanaDiscoveryCatalog.bundled.get()
        XCTAssertEqual(catalog.products.count, 177)
        var seen: Set<String> = []
        let sets = try await catalog.sealedSets(game: .lorcana)
        XCTAssertEqual(sets.reduce(0) { $0 + $1.sealedCount }, 177)
        for set in sets {
            var offset = 0
            var hasMore = true
            while hasMore {
                let page = try await catalog.searchSealedProducts(game: .lorcana, setID: set.id, query: nil, offset: offset)
                for product in page.items {
                    XCTAssertTrue(seen.insert(product.id).inserted)
                    XCTAssertNil(product.marketPriceUSD); XCTAssertNil(product.variantID)
                    XCTAssertNotNil(product.tcgplayerProductID)
                    XCTAssertFalse(product.name.contains("Puzzle Insert"))
                    XCTAssertFalse(product.name.contains("Oversized"))
                }
                offset += page.items.count; hasMore = page.hasMore
            }
        }
        XCTAssertEqual(seen.count, 177)
        let search = try await catalog.searchSealedProducts(game: .lorcana, setID: nil, query: "first chapter booster", offset: 0)
        XCTAssertFalse(search.items.isEmpty)
        XCTAssertTrue(search.items.allSatisfy { $0.name.contains("Booster") })
    }

    func testPaginationAndSelectionRejectWrongScopeStaleGenerationAndUnknownFooters() async throws {
        let catalog = try LorcanaDiscoveryCatalog.bundled.get()
        let sets = try await catalog.sets()
        let first = try XCTUnwrap(sets.first { $0.code == "1" })
        let second = try XCTUnwrap(sets.first { $0.code == "2" })
        let firstPage = try await catalog.cards(in: first, cursor: nil)
        let cursor = try XCTUnwrap(firstPage.nextCursor)
        do { _ = try await catalog.cards(in: second, cursor: cursor); XCTFail() } catch CatalogLookupError.staleCatalog {}
        let unknown = try LorcanaRecognitionAdapter.identifier(.init(collectorNumber: "999", denominator: "204", language: "en", printedSetMarker: "1"), generation: catalog.generation)
        guard case .catalogIncomplete(nil) = try await catalog.lookup(unknown) else { return XCTFail() }
        let stale = try LorcanaRecognitionAdapter.identifier(.init(collectorNumber: "1", denominator: "204", language: "en", printedSetMarker: "1"), generation: "old")
        do { _ = try await catalog.lookup(stale); XCTFail() } catch CatalogLookupError.staleCatalog {}
        XCTAssertEqual(try catalog.identifierForRetry(stale).catalogGeneration, catalog.generation)
        XCTAssertThrowsError(try catalog.validateCollectionMutation(printingID: "lorcanajson:en:1", catalogProviderID: nil,
            variantID: "normal", itemKindRaw: "rawCard", collectionKey: "lorcana:lorcanajson:en:1#normal"))
    }

    func testDefaultRuntimeRegistersReviewedMarketAuthorityAlongsideDiscovery() throws {
        let runtime = try XCTUnwrap(CardGameRuntimeContainer.appDefaults().runtime(for: .lorcana))
        XCTAssertTrue(runtime.descriptor.capabilities.contains([.scan, .browse, .sealed]))
        XCTAssertTrue(runtime.descriptor.capabilities.contains([.collectionWrite, .pricing]))
        XCTAssertEqual(runtime.priceAuthority?.identityByPriceKey.count,3_232)
        XCTAssertNotNil(runtime.pricing); XCTAssertNotNil(runtime.importer)
    }

    func testAllReviewedUnnumberedCardsRequireExactTitlesAndQuestMarkers() async throws {
        let catalog = try LorcanaDiscoveryCatalog.bundled.get()
        let recognizer = LorcanaDiscoveryRecognizer(catalog: catalog)
        XCTAssertEqual(catalog.unnumberedCards.count, 5)
        for row in catalog.unnumberedCards {
            XCTAssertEqual(row.number, "Unnumbered", "Provider sequencing is not a printed collector number")
            let title = try XCTUnwrap(row.recognitionTitles?.first)
            let marker = try XCTUnwrap(row.unnumberedSetMarker)
            let components = title.components(separatedBy: " - ")
            let lines = components.map { RecognizedLine(text: $0) } + [.init(text: "EN • \(marker)")]
            guard case let .identified(subject) = recognizer.identify(lines) else { XCTFail(row.name); continue }
            guard case let .needsPrintingChoice(_, choices) = try await catalog.lookup(subject.identifier) else { return XCTFail() }
            XCTAssertEqual(choices.map(\.id), [row.id])
            XCTAssertEqual(recognizer.identify(components.map { .init(text: $0) }), .nothing)
            XCTAssertEqual(recognizer.identify(components.map { .init(text: $0) } + [.init(text: "EN • Q9")]), .nothing)
        }
        XCTAssertEqual(recognizer.identify([.init(text: "The Encounter"), .init(text: "The Lair"), .init(text: "EN • Q1")]), .ambiguous)
        XCTAssertEqual(recognizer.identify([.init(text: "Ursula"), .init(text: "EN • Q1")]), .nothing)
    }

    func testCameraFullCardTextReadOnlyRunsForUnidentifiedKnownQuestFooters() throws {
        let catalog = try LorcanaDiscoveryCatalog.bundled.get()
        let recognizer = LorcanaDiscoveryRecognizer(catalog: catalog)
        let profile = RecognitionProfile(additionalRecognizers: [recognizer])
        func requests(_ lines: [RecognizedLine]) -> Bool {
            profile.needsFullCardText(afterFooterLines: lines, outcome: profile.identify(lines))
        }
        XCTAssertTrue(requests([.init(text: "EN • Q1")]))
        XCTAssertTrue(requests([.init(text: "EN • Q2")]))
        XCTAssertTrue(requests([.init(text: "EN • Q3")]))
        XCTAssertFalse(requests([.init(text: "EN • Q9")]))
        XCTAssertFalse(requests([.init(text: "EN • Q1", boundingBox: .init(x: 2, y: 0, width: 1, height: 1))]))
        XCTAssertFalse(requests([.init(text: "1/204 • EN • 1")]))
        XCTAssertFalse(requests([.init(text: "EN • Q1"), .init(text: "1/204 • EN • 1"), .init(text: "2/204 • EN • 1")]))
        XCTAssertEqual(profile.identify([.init(text: "EN • Q1"), .init(text: "1/204 • EN • 1")]), .ambiguous)
        let oldProfile = RecognitionProfile.pokemonOnly
        let footer = [RecognizedLine(text: "EN • Q1")]
        XCTAssertFalse(oldProfile.needsFullCardText(afterFooterLines: footer, outcome: oldProfile.identify(footer)))
        guard case let .identified(subject) = profile.identify(footerLines: footer, fullCardLines: [.init(text: "Ursula"), .init(text: "Ruler of Lorcana")]) else {
            return XCTFail("Full-card text must reach the installed recognizer in the same batch")
        }
        XCTAssertEqual(subject.game, .lorcana)
    }

    func testFullCardTextCannotSupplyAnotherGamesIdentityOrUnrelatedHistoricalFallback() throws {
        struct Other: GameRecognitionAdapter {
            let game = CardGame.magic
            let customWords: [String] = []
            let identifier: ScanIdentifier
            func identify(_ lines: [RecognizedLine]) -> GameRecognitionOutcome {
                lines.contains { $0.text == "foreign-body-marker" } ? .identified(.init(identifier: identifier)) : .nothing
            }
        }
        let catalog = try LorcanaDiscoveryCatalog.bundled.get()
        let other = Other(identifier: try .init(game: .magic, namespace: "fixture",
            fields: [.init(key: "number", value: "1")], displayIdentifier: "1", suppressionIdentity: "fixture"))
        let profile = RecognitionProfile(additionalRecognizers: [LorcanaDiscoveryRecognizer(catalog: catalog), other])
        let footer = [RecognizedLine(text: "EN • Q1")]
        let body: [RecognizedLine] = [.init(text: "Ursula"), .init(text: "Ruler of Lorcana"), .init(text: "foreign-body-marker")]
        guard case let .identified(subject) = profile.identify(footerLines: footer, fullCardLines: body) else { return XCTFail() }
        XCTAssertEqual(subject.game, .lorcana)
        XCTAssertEqual(profile.identify(footerLines: footer, fullCardLines: [.init(text: "foreign-body-marker")]), .fallbackBlocked)
    }

    func testEveryRecordIncludingHeldComponentsSupportsExplicitScannerRecovery() async throws {
        let catalog = try LorcanaDiscoveryCatalog.bundled.get()
        let original = try LorcanaRecognitionAdapter.identifier(.init(collectorNumber: "999", denominator: "204", language: "en", printedSetMarker: "1"), generation: catalog.generation)
        var heldCount = 0
        for row in catalog.cardsByID.values {
            let identifier = try catalog.identifierForCatalogSelection(printingID: row.id, original: original)
            if identifier.namespace == "catalog-record" { heldCount += 1 }
            guard case let .needsPrintingChoice(_, choices) = try await catalog.lookup(identifier),
                  let choice = choices.first(where: { $0.id == row.id }) else { XCTFail(row.id); continue }
            let resolved = try await catalog.resolve(choice, for: identifier)
            XCTAssertEqual(resolved.card.name, row.name)
            XCTAssertEqual(try catalog.identifierForRetry(identifier), identifier)
        }
        XCTAssertEqual(heldCount, 3)
        XCTAssertThrowsError(try catalog.identifierForCatalogSelection(printingID: "tcgcsv:71:unknown", original: original))
    }

    func testMissingPromosAreInTheirActualPromoScopesAndNoMarketDuplicatesRemain() async throws {
        let catalog = try LorcanaDiscoveryCatalog.bundled.get()
        let sets = try await catalog.sets()
        let p2 = try XCTUnwrap(sets.first { $0.code == "P2" })
        let p2Page = try await catalog.cards(in: p2, cursor: nil)
        XCTAssertTrue(p2Page.items.contains { $0.providerID == "tcgcsv:71:616373" })
        let c3 = try XCTUnwrap(sets.first { $0.code == "C3" })
        XCTAssertTrue(c3.name.contains("Partial catalog"))
        XCTAssertEqual(c3.cardCount, 2)
        let first = try XCTUnwrap(sets.first { $0.code == "1" })
        let firstPage = try await catalog.cards(in: first, cursor: nil)
        XCTAssertTrue(firstPage.items.contains { $0.providerID == "tcgcsv:71:516775" }, "Oversized gift cards belong with their printed expansion")
        XCTAssertEqual(catalog.cardsByID["tcgcsv:71:597095"]?.setCode, "2", "Errata cards retain their printed expansion")
        for id in ["tcgcsv:71:722383", "tcgcsv:71:722555", "tcgcsv:71:722695", "tcgcsv:71:652646"] {
            XCTAssertNil(catalog.cardsByID[id], "Duplicate source aliases and card bundles must not become individual cards")
        }
    }

    func testUpcomingLabelsAdvanceAndInvalidateOldBrowseGeneration() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "discovery", withExtension: "json", subdirectory: "LorcanaCatalogSeed"))
        let data = try Data(contentsOf: url)
        let formatter = ISO8601DateFormatter()
        let before = try LorcanaDiscoveryCatalog(data: data, asOf: XCTUnwrap(formatter.date(from: "2026-10-15T00:00:00Z")))
        let after = try LorcanaDiscoveryCatalog(data: data, asOf: XCTUnwrap(formatter.date(from: "2026-10-16T00:00:00Z")))
        let beforeSets = try await before.sets(), afterSets = try await after.sets()
        let first = try XCTUnwrap(beforeSets.first { $0.code == "14" })
        let second = try XCTUnwrap(afterSets.first { $0.code == "14" })
        XCTAssertTrue(first.name.contains("Upcoming")); XCTAssertFalse(second.name.contains("Upcoming"))
        XCTAssertNotEqual(before.generation, after.generation)
        let page = try await before.cards(in: first, cursor: nil)
        do { _ = try await after.cards(in: second, cursor: page.nextCursor); XCTFail() } catch CatalogLookupError.staleCatalog {}
    }

    @MainActor
    func testSealedModelLoadsLorcanaWithoutCredentialsAndKeepsOtherGamesBlocked() async throws {
        let catalog = try LorcanaDiscoveryCatalog.bundled.get()
        let registry = CardGameRegistry(descriptors: [LorcanaDiscoveryCatalog.descriptor,
            .init(game: .pokemon, displayName: "Pokémon", sortOrder: 0, capabilities: [.browse, .sealed])])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LorcanaSealed-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = SealedBrowseModel(client: catalog, gameRegistry: registry,
                                     cache: CatalogCacheStore(root: root), isConfigured: { false })
        XCTAssertTrue(model.isConfigured(for: .lorcana))
        XCTAssertFalse(model.isConfigured(for: .pokemon))
        await model.loadSetsIfNeeded(game: .lorcana)
        XCTAssertFalse(model.sets.isEmpty)
        let set = try XCTUnwrap(model.sets.first)
        await model.loadProducts(game: .lorcana, setID: set.id)
        XCTAssertFalse(model.products.isEmpty)
        await model.search(query: "booster", games: [.lorcana, .pokemon])
        XCTAssertFalse(model.searchLanes[.lorcana]?.products.isEmpty ?? true)
        XCTAssertTrue(model.searchLanes[.pokemon]?.products.isEmpty ?? false)
        XCTAssertNil(model.searchLanes[.pokemon]?.error)
    }
}
