import Foundation
import XCTest
@testable import TradingCardScanner

final class LorcanaDiscoveryCatalogTests: XCTestCase {
    func testLocalManifestByteBudgetIsBoundedWithoutChangingSignedTransport() throws {
        let maximum = LorcanaCatalogRegistry.maximumManifestBytes
        var boundary = Data(#"{"schemaVersion":1,"printFamilies":[]}"#.utf8)
        boundary.append(Data(repeating: 0x20, count: maximum - boundary.count))
        XCTAssertNoThrow(try LorcanaCatalogRegistry(data: boundary))
        boundary.append(0x20)
        XCTAssertThrowsError(try LorcanaCatalogRegistry(data: boundary)) {
            XCTAssertEqual($0 as? LorcanaCatalogRegistry.ValidationError, .oversizedManifest)
        }
        XCTAssertEqual(LorcanaCatalogSignature.maximumPayloadBytes, 8 * 1_024 * 1_024)
        XCTAssertEqual(LorcanaCatalogSignature.maximumEnvelopeBytes, 12 * 1_024 * 1_024)
    }

    func testPackagedMarketLoaderPreservesSourceBindingAndResourceBounds() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("LorcanaCatalogSeed")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        for name in ["discovery", "market"] {
            let original = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "LorcanaCatalogSeed"))
            try FileManager.default.copyItem(at: original, to: resources.appendingPathComponent(name + ".json"))
        }
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "fixture.lorcana.bounds", "CFBundlePackageType": "BNDL"],
            format: .xml, options: 0).write(to: root.appendingPathComponent("Info.plist"))
        let bundle = try XCTUnwrap(Bundle(url: root))
        XCTAssertNoThrow(try LorcanaDiscoveryCatalog.loadBundledMarket(from: bundle))
        let marketURL = resources.appendingPathComponent("market.json")
        let market = try Data(contentsOf: marketURL)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: market) as? [String: Any])
        object["discoverySHA256"] = String(repeating: "0", count: 64)
        try JSONSerialization.data(withJSONObject: object).write(to: marketURL)
        XCTAssertThrowsError(try LorcanaDiscoveryCatalog.loadBundledMarket(from: bundle)) {
            guard case BrowseCatalogError.badResponse = $0 else { return XCTFail("Source binding must reject before admission") }
        }
        try Data(repeating: 0x20, count: LorcanaCatalogRegistry.maximumManifestBytes + 1).write(to: marketURL)
        XCTAssertThrowsError(try LorcanaDiscoveryCatalog.loadBundledMarket(from: bundle)) {
            guard case BrowseCatalogError.badResponse = $0 else { return XCTFail("Oversize resource must reject before decoding") }
        }
        try market.write(to: marketURL)
        try Data(repeating: 0x20, count: 8 * 1_024 * 1_024 + 1).write(to: resources.appendingPathComponent("discovery.json"))
        XCTAssertThrowsError(try LorcanaDiscoveryCatalog.loadBundledMarket(from: bundle)) {
            guard case BrowseCatalogError.badResponse = $0 else { return XCTFail("Discovery budget must remain bounded") }
        }
    }

    func testEverySourceCardIsBrowsableWithArtworkAndFinishMetadata() async throws {
        let catalog = try LorcanaDiscoveryCatalog.bundled.get()
        XCTAssertEqual(catalog.cardsByID.values.filter { $0.id.hasPrefix("lorcanajson:") }.count, 3_556)
        XCTAssertEqual(catalog.cardsByID.count, 3_595)
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

    func testHeldFooterSiblingsPassSharedCatalogMembershipAndStayReadOnly() async throws {
        let discovery = try LorcanaDiscoveryCatalog.bundled.get()
        let catalog = try CardGameRuntimeContainer(runtimes: [discovery.runtime]).makeCardCatalog()
        let recognizer = LorcanaDiscoveryRecognizer(catalog: discovery)
        let families = discovery.cardsByFooter.values.filter { $0.count > 1 }
        XCTAssertGreaterThanOrEqual(families.count, 6)
        for rows in families {
            let first = try XCTUnwrap(rows.first)
            guard case let .identified(subject) = recognizer.identify([.init(text: first.printedIdentifier)]),
                  case let .needsPrintingChoice(family, candidates) = try await catalog.lookupOutcome(for: subject.identifier)
            else { return XCTFail(first.printedIdentifier) }
            XCTAssertEqual(Set(candidates.map(\.id)), Set(rows.map(\.id)))
            for candidate in candidates {
                XCTAssertEqual(candidate.canonicalCardID, family.id)
                XCTAssertNotNil(candidate.acquisitionUnavailableReason)
                let resolved = try await catalog.resolvePrintingChoice(candidate, for: subject.identifier)
                XCTAssertEqual(resolved.card.physicalPrintingID, candidate.id)
            }
        }
    }

    func testLocalSetSearchUsesFullChecklistAndExactPrintedNumbers() async throws {
        let catalog = try LorcanaDiscoveryCatalog.bundledMarket.get()
        let sets = try await catalog.sets()
        let first = try XCTUnwrap(sets.first { $0.code == "1" })
        let full = try await catalog.completeLocalCards(in: first)
        let rows = try XCTUnwrap(full)
        XCTAssertEqual(rows.count, first.cardCount)
        let result = try await catalog.search(query: "05 / 204 EN 1", setIDs: [first.catalogID], cursor: nil)
        XCTAssertEqual(result.items.map(\.collectorNumber), ["5", "5"])
        let combined = try await catalog.search(query: "Mulan 118", setIDs: [first.catalogID], cursor: nil)
        XCTAssertEqual(combined.items.map(\.collectorNumber), ["118", "118"])
        let builder = CatalogSetPresentationBuilder()
        let inputs = CatalogSetPresentationInputs(setID: first.catalogID, contentGeneration: UUID(),
            cards: rows, search: "Mulan 118/204", sort: .numberLowToHigh, ownership: .all,
            ownershipRevision: 0, tier: .standard, prices: [:])
        let groups = try await builder.groups(for: inputs, owned: CatalogOwnershipIndex(rows: []))
        XCTAssertEqual(groups.map(\.preferredSummary.collectorNumber), ["118", "118"])
        let fabled = try XCTUnwrap(sets.first { $0.code == "9" })
        let zero = try await catalog.search(query: "0/204", setIDs: [fabled.catalogID], cursor: nil)
        XCTAssertEqual(zero.items.map(\.collectorNumber), ["0"])
        let inklands = try XCTUnwrap(sets.first { $0.code == "3" })
        let suffix = try await catalog.search(query: "04B/204", setIDs: [inklands.catalogID], cursor: nil)
        XCTAssertEqual(suffix.items.map(\.collectorNumber), ["4B"])
    }

    func testNewSourceSiblingOrFinishWithdrawsAutomaticAcquisition() async throws {
        let bundled = try LorcanaDiscoveryCatalog.bundledMarket.get()
        let manifest = try XCTUnwrap(bundled.registry.normalizedPhysicalManifest)
        let url = try XCTUnwrap(Bundle.main.url(forResource: "discovery", withExtension: "json", subdirectory: "LorcanaCatalogSeed"))
        let data = try Data(contentsOf: url)
        for addsSibling in [true, false] {
            var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var rows = try XCTUnwrap(payload["cards"] as? [[String: Any]])
            let index = try XCTUnwrap(rows.firstIndex { $0["id"] as? String == "lorcanajson:en:6" })
            if addsSibling {
                var extra = rows[index]
                extra["id"] = "lorcanajson:en:99999"
                rows.append(extra)
                var coverage = try XCTUnwrap(payload["coverage"] as? [String: Any])
                coverage["sourceCardCount"] = try XCTUnwrap(coverage["sourceCardCount"] as? Int) + 1
                payload["coverage"] = coverage
            } else {
                rows[index]["foilTypes"] = ["None", "Silver", "RainbowPillars"]
            }
            payload["cards"] = rows
            let catalog = try LorcanaDiscoveryCatalog(data: JSONSerialization.data(withJSONObject: payload), reviewedManifest: manifest)
            guard case let .identified(subject) = LorcanaDiscoveryRecognizer(catalog: catalog).identify([.init(text: "6/204 EN 1")]),
                  case .catalogIncomplete = try await catalog.lookup(subject.identifier)
            else { return XCTFail("A changed source family must withhold acquisition") }
        }
    }

    func testSharedDiscoveryRowProjectsBothReviewedPhysicalSiblings() async throws {
        let discoveryURL = try XCTUnwrap(Bundle.main.url(forResource: "discovery", withExtension: "json", subdirectory: "LorcanaCatalogSeed"))
        let marketURL = try XCTUnwrap(Bundle.main.url(forResource: "market", withExtension: "json", subdirectory: "LorcanaCatalogSeed"))
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: discoveryURL)) as? [String: Any])
        let cards = try XCTUnwrap(payload["cards"] as? [[String: Any]])
        payload["cards"] = cards.filter { $0["id"] as? String != "tcgcsv:71:516775" }
        var coverage = try XCTUnwrap(payload["coverage"] as? [String: Any])
        coverage["supplementalCardCount"] = try XCTUnwrap(coverage["supplementalCardCount"] as? Int) - 1
        payload["coverage"] = coverage
        var market = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: marketURL)) as? [String: Any])
        var printings = try XCTUnwrap(market["physicalPrintings"] as? [[String: Any]])
        let oversized = try XCTUnwrap(printings.firstIndex {
            ($0["id"] as? String)?.lowercased() == "64cde47d-47b8-4d05-ac65-05975c59ead4"
        })
        printings[oversized]["sourceAliases"] = [["provider": "lorcanajson", "id": "lorcanajson:en:5"]]
        market["physicalPrintings"] = printings
        let reviewed = try JSONDecoder().decode(LorcanaPhysicalCatalogManifest.self,
            from: JSONSerialization.data(withJSONObject: market))
        let catalog = try LorcanaDiscoveryCatalog(data: JSONSerialization.data(withJSONObject: payload), reviewedManifest: reviewed)
        let sets = try await catalog.sets()
        let set = try XCTUnwrap(sets.first { $0.code == "1" })
        let choices = try await catalog.search(query: "5/204", setIDs: [set.catalogID], cursor: nil)
        XCTAssertEqual(choices.items.count, 2)
        XCTAssertEqual(Set(choices.items.map(\.providerID)).count, 2)
        XCTAssertTrue(choices.items.allSatisfy { $0.collectionAvailabilityNotice == nil })
        XCTAssertTrue(choices.items.contains { $0.name.contains("Oversized") })
    }

    func testBundledAcquirableBrowseIDsMatchEveryReviewedFooter() async throws {
        let bundled = try LorcanaDiscoveryCatalog.bundledMarket.get()
        let catalog = try CardGameRuntimeContainer(runtimes: [bundled.runtime]).makeCardCatalog()
        let physical = try XCTUnwrap(bundled.registry.physicalCatalog)
        let sets = try await bundled.sets()
        var fromBrowse: [String: CatalogCardSummary] = [:]
        for set in sets {
            for row in try await bundled.completeLocalCards(in: set) ?? [] where row.collectionAvailabilityNotice == nil {
                XCTAssertNil(fromBrowse.updateValue(row, forKey: row.providerID))
            }
        }
        XCTAssertEqual(fromBrowse.count, 3_426)
        for (footer, universe) in physical.universesByFooter where universe.isComplete {
            let identifier = try LorcanaRecognitionAdapter.identifier(footer, generation: bundled.generation)
            let outcome = try await catalog.lookupOutcome(for: identifier)
            let resolved: [IdentifiedCard]
            switch outcome {
            case let .resolved(result):
                resolved = [result.card]
            case let .needsPrintingChoice(_, choices):
                var selected: [IdentifiedCard] = []
                for choice in choices {
                    selected.append(try await catalog.resolvePrintingChoice(choice, for: identifier).card)
                }
                resolved = selected
            case .catalogIncomplete:
                return XCTFail(footer.displayIdentifier)
            }
            XCTAssertEqual(Set(resolved.map(\.physicalPrintingID)),
                           Set(universe.printingIDs.map { $0.uuidString.lowercased() }))
            for card in resolved {
                let row = try XCTUnwrap(fromBrowse.removeValue(forKey: card.physicalPrintingID))
                let details = try await bundled.details(for: row)
                XCTAssertEqual(details.card.variantEvidence.catalogVariants, card.variantEvidence.catalogVariants)
            }
        }
        XCTAssertTrue(fromBrowse.isEmpty)
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

    func testBundledLetteredDalmatiansResolveExactArtAndMarketLanes() async throws {
        let catalog = try LorcanaDiscoveryCatalog.bundledMarket.get()
        let recognizer = LorcanaDiscoveryRecognizer(catalog: catalog)
        var printingIDs: Set<String> = []
        var artworkURLs: Set<URL> = []
        for (index, suffix) in ["a", "b", "c", "d", "e"].enumerated() {
            let text = "4\(suffix)/204 EN 3"
            guard case let .identified(subject) = recognizer.identify([.init(text: text)]),
                  case let .resolved(resolution) = try await catalog.lookup(subject.identifier) else {
                return XCTFail(text)
            }
            let card = resolution.card
            let id = try XCTUnwrap(UUID(uuidString: card.physicalPrintingID))
            let printing = try XCTUnwrap(catalog.registry.physicalCatalog?.printingByID[id])
            XCTAssertEqual(printing.identity.footer.collectorNumber, "4\(suffix.uppercased())")
            XCTAssertTrue(printingIDs.insert(card.physicalPrintingID).inserted)
            XCTAssertTrue(artworkURLs.insert(try XCTUnwrap(printing.imageURL)).inserted)
            XCTAssertEqual(Set(printing.finishes.map(\.finish)), [.normal, .foil])
            XCTAssertEqual(Set(printing.marketMappings?.map(\.productID) ?? []), [532867 + index])
            XCTAssertEqual(Set(printing.marketMappings?.map(\.providerVariantID) ?? []), ["Normal", "Cold Foil"])
        }
    }

    func testBundledD23PrintedFootersFindTheCorrectMickeyAndFinish() async throws {
        let bundled = try LorcanaDiscoveryCatalog.bundledMarket.get()
        let recognizer = LorcanaDiscoveryRecognizer(catalog: bundled)
        let sets = try await bundled.sets()
        let catalog = try CardGameRuntimeContainer(runtimes: [bundled.runtime]).makeCardCatalog()
        let importer = LorcanaImportAdapter(registry: bundled.registry)
        var printingIDs: Set<String> = []
        for (input, printed, normalized, wrong, setCode, finish, product) in [
            ("1TFC - EN - 1/P1", "1TFC EN 1/P1", "1/P1 EN 1", "2/P1 EN 1", "P1", PhysicalVariant.normal, "454233"),
            ("01/D23 - EN - 1", "01/D23 EN 1", "1/D23 EN 1", "02/D23 EN 1", "D23", .foil, "559532")
        ] {
            guard case let .identified(subject) = recognizer.identify([.init(text: input)]),
                  case let .resolved(result) = try await catalog.lookupOutcome(for: subject.identifier) else {
                return XCTFail(input)
            }
            let card = result.card
            XCTAssertTrue(printingIDs.insert(card.physicalPrintingID).inserted)
            XCTAssertEqual(card.identifier, printed)
            XCTAssertEqual(card.variantEvidence.catalogVariants, [finish])
            XCTAssertEqual(TCGplayerLinkBuilder.destination(for: card, variant: finish)?.url.path, "/product/\(product)")
            let set = try XCTUnwrap(sets.first { $0.code == setCode })
            let hits = try await bundled.search(query: printed, setIDs: [set.catalogID], cursor: nil)
            XCTAssertEqual(hits.items.map(\.providerID), [card.physicalPrintingID])
            for (number, valid) in [(printed, true), (normalized, true), (wrong, false)] {
                let csv = "game,provider_id,card_name,card_number,finish,quantity\nlorcana,\(card.providerID),Mickey,\(number),\(finish.id),1\n"
                let entry = try XCTUnwrap(CollectionCSV.parse(Data(csv.utf8)).entries.first)
                if valid {
                    XCTAssertNoThrow(try importer.validate(entry), number)
                } else {
                    XCTAssertThrowsError(try importer.validate(entry), number)
                }
            }
        }
    }

    func testNumberedQuestCardKeepsItsPrintedNumberWithoutTheWrongPrice() async throws {
        let bundled = try LorcanaDiscoveryCatalog.bundledMarket.get()
        let recognizer = LorcanaDiscoveryRecognizer(catalog: bundled)
        guard case let .identified(subject) = recognizer.identify([.init(text: "20/35 EN Q2")]),
              case let .resolved(result) = try await bundled.lookup(subject.identifier) else {
            return XCTFail("The published 20/35 should resolve")
        }
        XCTAssertEqual(result.card.name, "Disastrous Sandstorm")
        XCTAssertEqual(result.card.variantEvidence.catalogVariants, [.normal])
        XCTAssertNil(TCGplayerLinkBuilder.destination(for: result.card, variant: .normal))
    }

    func testChampionshipFoilIsBrowsableWithoutBorrowingTheNonFoilMarketProduct() async throws {
        let bundled = try LorcanaDiscoveryCatalog.bundledMarket.get()
        let recognizer = LorcanaDiscoveryRecognizer(catalog: bundled)
        let sets = try await bundled.sets()
        let challenge = try XCTUnwrap(sets.first { $0.code == "C2" })
        let page = try await bundled.search(query: "Headless Horseman 13/C2", setIDs: [challenge.catalogID], cursor: nil)
        let summary = try XCTUnwrap(page.items.first)
        XCTAssertEqual(page.items.count, 1)
        let details = try await bundled.details(for: summary)
        XCTAssertNil(details.collectionWriteUnavailableReason)
        XCTAssertEqual(details.card.variantEvidence.catalogVariants, [.foil])
        XCTAssertNil(TCGplayerLinkBuilder.destination(for: details.card, variant: .foil))
        guard case let .identified(subject) = recognizer.identify([.init(text: "13/C2 EN 10")]),
              case let .resolved(result) = try await bundled.lookup(subject.identifier)
        else { return XCTFail("The published foil footer should resolve") }
        XCTAssertEqual(result.card.physicalPrintingID, details.card.physicalPrintingID)
    }

    func testChallengeYearOneKeepsBothFinishesAndQuotesOnlyExactLanes() async throws {
        let bundled = try LorcanaDiscoveryCatalog.bundledMarket.get()
        let sets = try await bundled.sets()
        let set = try XCTUnwrap(sets.first { $0.code == "C1" })
        let localCards = try await bundled.completeLocalCards(in: set)
        let rows = try XCTUnwrap(localCards)
        XCTAssertEqual(rows.count, 10)
        for row in rows {
            let details = try await bundled.details(for: row)
            let number = try XCTUnwrap(Int(row.collectorNumber))
            if number == 5 {
                XCTAssertNotNil(details.collectionWriteUnavailableReason)
                continue
            }
            XCTAssertNil(details.collectionWriteUnavailableReason)
            let expected: Set<PhysicalVariant> = [3, 4, 8, 9, 10].contains(number) ? [.normal, .foil] : [.foil]
            XCTAssertEqual(Set(details.card.variantEvidence.catalogVariants), expected)
            XCTAssertEqual(TCGplayerLinkBuilder.destination(for: details.card, variant: .foil) != nil, [1, 2, 3].contains(number))
            XCTAssertEqual(TCGplayerLinkBuilder.destination(for: details.card, variant: .normal) != nil, expected.contains(.normal))
        }
    }

    func testBundledFloodbornErrataRequireAVisiblePrintingChoice() async throws {
        let bundled = try LorcanaDiscoveryCatalog.bundledMarket.get()
        let recognizer = LorcanaDiscoveryRecognizer(catalog: bundled)
        let catalog = try CardGameRuntimeContainer(runtimes: [bundled.runtime]).makeCardCatalog()
        let cases: [(String, [String: (product: String, normal: Bool)])] = [
            ("39/204 EN 2", ["Separated branch": ("516333", true), "Continuous branch": ("618771", true)]),
            ("73/204 EN 2", ["Cost 2 · Ward": ("519506", true), "Cost 3 · no Ward": ("597095", false)])
        ]
        for (printed, expected) in cases {
            guard case let .identified(subject) = recognizer.identify([.init(text: printed)]),
                  case let .needsPrintingChoice(_, choices) = try await catalog.lookupOutcome(for: subject.identifier)
            else { return XCTFail(printed) }
            XCTAssertEqual(Set(choices.compactMap(\.treatmentLabel)), Set(expected.keys))
            XCTAssertEqual(Set(choices.compactMap(\.thumbnailURL)).count, 2)
            var ids: Set<String> = []
            for choice in choices {
                let label = try XCTUnwrap(choice.treatmentLabel)
                let match = try XCTUnwrap(expected[label])
                let card = try await catalog.resolvePrintingChoice(choice, for: subject.identifier).card
                XCTAssertTrue(ids.insert(card.physicalPrintingID).inserted)
                XCTAssertEqual(Set(card.variantEvidence.catalogVariants), match.normal ? [.normal, .foil] : [.foil])
                XCTAssertEqual(TCGplayerLinkBuilder.destination(for: card, variant: .foil)?.url.path,
                               "/product/\(match.product)")
            }
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
        XCTAssertEqual(catalog.products.count, 188)
        var seen: Set<String> = []
        let sets = try await catalog.sealedSets(game: .lorcana)
        XCTAssertEqual(sets.reduce(0) { $0 + $1.sealedCount }, 188)
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
        XCTAssertEqual(seen.count, 188)
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
        let catalog = try LorcanaDiscoveryCatalog.bundledMarket.get()
        let manifest = try XCTUnwrap(catalog.registry.physicalCatalog?.manifest)
        let expectedMappings = manifest.physicalPrintings.reduce(0) { $0 + ($1.marketMappings?.count ?? 0) }
        XCTAssertEqual(runtime.priceAuthority?.identityByPriceKey.count, expectedMappings)
        XCTAssertNotNil(runtime.pricing); XCTAssertNotNil(runtime.importer)
    }

    func testBrowseAvailabilityMatchesReviewedAcquisitionAuthority() async throws {
        let catalog = try LorcanaDiscoveryCatalog.bundledMarket.get()
        let sets = try await catalog.sets()
        let recent = try XCTUnwrap(sets.first { $0.code == "C3" })
        XCTAssertEqual(recent.collectionAvailabilityNotice, "Browse only")
        XCTAssertEqual(recent.withSortRank(99).collectionAvailabilityNotice, "Browse only")
        let recentCards = try await catalog.cards(in: recent, cursor: nil)
        let recentCard = try XCTUnwrap(recentCards.items.first)
        XCTAssertEqual(recentCard.collectionAvailabilityNotice, "Browse only")
        let recentDetail = try await catalog.details(for: recentCard)
        XCTAssertNotNil(recentDetail.collectionWriteUnavailableReason)

        let firstSet = try XCTUnwrap(sets.first { $0.code == "P1" })
        XCTAssertEqual(firstSet.collectionAvailabilityNotice, "Some cards are browse only")
        let firstCards = try await catalog.cards(in: firstSet, cursor: nil)
        let reviewedCard = try XCTUnwrap(firstCards.items.first { $0.collectionAvailabilityNotice == nil })
        let reviewedDetail = try await catalog.details(for: reviewedCard)
        XCTAssertNil(reviewedDetail.collectionWriteUnavailableReason)
        let owned = CatalogOwnershipIndex(rows: [])
        XCTAssertNil(owned.directoryProgress(for: recent).total)
        let partial = owned.directoryProgress(for: firstSet)
        XCTAssertEqual(partial.unit, "reviewed printings")
        XCTAssertEqual(partial.total, firstSet.physicalPrintingIDs?.count)
        XCTAssertLessThan(try XCTUnwrap(partial.total), try XCTUnwrap(firstSet.cardCount))
        let complete = try XCTUnwrap(sets.first { $0.code == "14" })
        XCTAssertEqual(owned.directoryProgress(for: complete).total, complete.cardCount)

        let search = try await catalog.search(query: recentCard.name, setIDs: [recent.catalogID], cursor: nil)
        XCTAssertTrue(search.items.contains { $0.id == recentCard.id && $0.collectionAvailabilityNotice == "Browse only" })
        let decorated = recentCard.withArtwork(thumbnailURL: nil, imageURL: nil)
        XCTAssertEqual(decorated.collectionAvailabilityNotice, "Browse only")
        let encoded = try JSONEncoder().encode(decorated)
        XCTAssertEqual(try JSONDecoder().decode(CatalogCardSummary.self, from: encoded).collectionAvailabilityNotice, "Browse only")
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "collectionAvailabilityNotice")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        XCTAssertNil(try JSONDecoder().decode(CatalogCardSummary.self, from: legacyData).collectionAvailabilityNotice)
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
        XCTAssertEqual(heldCount, 9)
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
