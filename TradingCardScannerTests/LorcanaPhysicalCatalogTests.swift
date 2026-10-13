import Foundation
import XCTest
@testable import TradingCardScanner

/// All review references here are synthetic contracts, not physical-card proof.
final class LorcanaPhysicalCatalogTests: XCTestCase {
    private let canonicalID = UUID(uuidString: "80000000-0000-0000-0000-000000000001")!
    private let firstID = UUID(uuidString: "90000000-0000-0000-0000-00000000000A")!
    private let secondID = UUID(uuidString: "90000000-0000-0000-0000-00000000000B")!
    private let artworkID = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
    private let alias = LorcanaSourceAlias(provider: "fixture", id: "physical-family")

    private func footer(number: String = "207", marker: String = "1") throws -> LorcanaPrintedIdentity {
        try .init(collectorNumber: number, denominator: "204", language: "en", printedSetMarker: marker)
    }

    private func family(_ footer: LorcanaPrintedIdentity, aliases: [LorcanaSourceAlias]? = nil, layout: String = "normal") -> LorcanaPrintFamily {
        .init(footer: footer, providerSetCode: "TFC", name: "Fixture Elsa", version: "Spirit of Winter",
              rarity: "Fixture Rarity", layout: layout, sourceAliases: aliases ?? [alias], footerEvidenceReference: "fixture:footer")
    }

    private func printing(id: UUID? = nil, footer: LorcanaPrintedIdentity? = nil, canonical: UUID? = nil,
                          artwork: UUID? = nil, size: LorcanaPhysicalSize = .standard, stamp: String? = nil,
                          status: LorcanaPhysicalReviewStatus = .verified, finishes: [LorcanaPhysicalFinish] = [.normal, .foil],
                          aliases: [LorcanaSourceAlias]? = nil, artworkLabel: String = "Original artwork",
                          distribution: String = "booster", imageURL: URL? = nil,
                          identityEvidence: [LorcanaPhysicalEvidence]? = nil,
                          finishUniverse: String? = "fixture:finish-universe", layout: String = "normal") throws -> LorcanaPhysicalPrinting {
        .init(id: id ?? firstID,
              identity: .init(canonicalCardID: canonical ?? canonicalID, footer: try footer ?? self.footer(),
                              artworkID: artwork ?? artworkID, distributionID: distribution, stamp: stamp, size: size, layout: layout),
              providerSetCode: "TFC", setName: "Fixture First Chapter", artworkLabel: artworkLabel,
              distributionLabel: "Fixture Booster", imageURL: imageURL, status: status,
              identityEvidence: identityEvidence ?? LorcanaPhysicalEvidenceKind.allCases.map { .init(kind: $0, reference: "fixture:\($0.rawValue)") },
              finishes: finishes.map { .init(finish: $0, evidenceReferences: ["fixture:\($0.rawValue)"]) },
              finishUniverseEvidenceReference: finishUniverse, sourceAliases: aliases ?? [alias])
    }

    private func manifest(_ printings: [LorcanaPhysicalPrinting]? = nil, complete: Bool = true,
                          families: [LorcanaPrintFamily]? = nil, canonicalCards: [LorcanaCanonicalCard]? = nil,
                          universes: [LorcanaPhysicalUniverse]? = nil,
                          corrections: [LorcanaPhysicalCorrection] = []) throws -> LorcanaPhysicalCatalogManifest {
        let records = try printings ?? [printing()]
        let footers = Array(Set(records.map { $0.identity.footer }))
        let active = records.filter { $0.status != .superseded }
        return .init(schemaVersion: 2, reviewedAt: Date(timeIntervalSince1970: 1_700_000_000),
                     printFamilies: families ?? footers.map { family($0) },
                     canonicalCards: canonicalCards ?? [.init(id: canonicalID, name: "Fixture Elsa", version: "Spirit of Winter",
                         relationshipEvidenceReferences: ["fixture:canonical-relationship"])],
                     physicalPrintings: records, universes: universes ?? footers.map { footer in
                         .init(footer: footer, printingIDs: active.filter { $0.identity.footer == footer }.map(\.id),
                               isComplete: complete, evidenceReference: complete ? "fixture:all-physical-printings" : nil)
                     }, corrections: corrections)
    }

    private func registry(_ printings: [LorcanaPhysicalPrinting]? = nil, complete: Bool = true) throws -> LorcanaCatalogRegistry {
        try .init(manifest: manifest(printings, complete: complete))
    }

    private func identifier(_ registry: LorcanaCatalogRegistry, footer: LorcanaPrintedIdentity? = nil) throws -> ScanIdentifier {
        let printed = try footer ?? self.footer()
        guard case let .identified(subject) = LorcanaRecognitionAdapter(registry: registry).identify([.init(text: printed.displayIdentifier)]) else {
            throw CatalogLookupError.invalidAdapterOutcome
        }
        return subject.identifier
    }

    private func resolved(_ outcome: CatalogLookupOutcome) throws -> ResolvedCatalogCard {
        guard case let .resolved(resolution) = outcome else { throw CatalogLookupError.invalidAdapterOutcome }
        return resolution.card
    }

    func testReviewedSingletonResolvesExactUUIDThenAsksForSupportedFinish() async throws {
        let registry = try registry(), adapter = LorcanaCatalogAdapter(registry: registry)
        let card = try resolved(await adapter.lookup(identifier(registry)))
        XCTAssertEqual(card.physicalPrintingID, firstID.uuidString.lowercased())
        XCTAssertEqual(card.canonicalCardID, canonicalID.uuidString.lowercased())
        XCTAssertEqual(card.identifier, "207/204 EN 1")
        XCTAssertEqual(card.setCode, "TFC")
        XCTAssertEqual(card.variantEvidence.catalogVariants, [.normal, .foil])
        XCTAssertEqual(card.collectionKey(variant: .foil), "lorcana:\(firstID.uuidString.lowercased())#foil")
        guard case let .needsChoice(options, _) = VariantResolver.resolve(card.variantEvidence) else {
            return XCTFail("The reviewed normal/foil pair requires explicit finish evidence")
        }
        XCTAssertEqual(options, [.normal, .foil])
        try await adapter.validateAcquisition(identifier(registry), printingID: card.physicalPrintingID, automatic: true)
    }

    func testStandardAndOversizedRequireAnExplicitSizeChoice() async throws {
        let registry = try registry([printing(), printing(id: secondID, size: .oversized)])
        let container = try CardGameRuntimeContainer(runtimes: [LorcanaGameRuntime(registry: registry).runtime])
        let catalog = container.makeCardCatalog(), identifier = try identifier(registry)
        guard case let .needsPrintingChoice(summary, choices) = try await catalog.lookupOutcome(for: identifier) else {
            return XCTFail("Footer OCR cannot pick the physical size")
        }
        XCTAssertEqual(summary.id, canonicalID.uuidString.lowercased())
        XCTAssertEqual(choices.count, 2)
        XCTAssertTrue(choices[0].choiceLabel.contains("Size: Standard"))
        XCTAssertTrue(choices[1].choiceLabel.contains("Size: Oversized"))
        XCTAssertEqual(choices[0].selectionEvidence(among: choices), .labels)
        let oversized = try await catalog.resolvePrintingChoice(choices[1], for: identifier).card
        XCTAssertEqual(oversized.physicalPrintingID, secondID.uuidString.lowercased())
        XCTAssertNotEqual(oversized.collectionKey(variant: .foil), "lorcana:\(firstID.uuidString.lowercased())#foil")
        let adapter = LorcanaCatalogAdapter(registry: registry)
        do { try await adapter.validateAcquisition(identifier, printingID: oversized.physicalPrintingID, automatic: true); XCTFail() }
        catch CatalogLookupError.invalidPrintingChoice {}
        try await adapter.validateAcquisition(identifier, printingID: oversized.physicalPrintingID, automatic: false)
    }

    func testLoneOversizedStillRequiresUserSizeEvidence() async throws {
        let registry = try registry([printing(size: .oversized)])
        let adapter = LorcanaCatalogAdapter(registry: registry)
        guard case let .needsPrintingChoice(_, choices) = try await adapter.lookup(identifier(registry)) else { return XCTFail() }
        XCTAssertEqual(choices.count, 1)
        XCTAssertTrue(choices[0].choiceLabel.contains("Oversized"))
        let card = try await adapter.resolve(choices[0], for: identifier(registry)).card
        XCTAssertEqual(card.physicalPrintingID, firstID.uuidString.lowercased())
    }

    func testStampIsAPhysicalChoiceBeforeFinishAndSharesNoOwnershipKey() async throws {
        let registry = try registry([printing(), printing(id: secondID, stamp: "Fixture Event Stamp", finishes: [.foil])])
        let adapter = LorcanaCatalogAdapter(registry: registry), identifier = try identifier(registry)
        guard case let .needsPrintingChoice(_, choices) = try await adapter.lookup(identifier) else { return XCTFail() }
        XCTAssertEqual(choices.count, 2)
        XCTAssertTrue(choices[1].choiceLabel.contains("Fixture Event Stamp"))
        let stamped = try await adapter.resolve(choices[1], for: identifier).card
        XCTAssertEqual(stamped.variantEvidence.catalogVariants, [.foil])
        XCTAssertThrowsError(try adapter.validateVariantCorrection(printingID: stamped.physicalPrintingID, variantID: "normal"))
        XCTAssertNoThrow(try adapter.validateVariantCorrection(printingID: stamped.physicalPrintingID, variantID: "foil"))
    }

    func testIncompleteUniverseAndEveryUnreviewedCandidateBlockFalseUniqueness() async throws {
        let incomplete = try registry(complete: false)
        guard case .catalogIncomplete = try await LorcanaCatalogAdapter(registry: incomplete).lookup(identifier(incomplete)) else { return XCTFail() }
        for status in [LorcanaPhysicalReviewStatus.provisional, .conflicted] {
            let registry = try registry([printing(), printing(id: secondID, size: .oversized, status: status, finishes: [], identityEvidence: [], finishUniverse: nil)])
            let adapter = LorcanaCatalogAdapter(registry: registry)
            guard case .catalogIncomplete = try await adapter.lookup(identifier(registry)) else { return XCTFail("Filtering \(status) would falsely imply uniqueness") }
            XCTAssertEqual(LorcanaVariantPolicy(registry: registry).selectableVariants, [.normal, .foil])
            // Discovery cannot prove acquisition uniqueness, but an already
            // known exact verified UUID still has its own finish authority.
            XCTAssertNoThrow(try adapter.validateVariantCorrection(printingID: firstID.uuidString.lowercased(), variantID: "foil"))
            XCTAssertThrowsError(try adapter.validateVariantCorrection(printingID: secondID.uuidString.lowercased(), variantID: "foil"))
        }
    }

    func testCandidateUniverseCannotOmitAnUnreviewedOrOversizedRecord() throws {
        let prints = try [printing(), printing(id: secondID, size: .oversized, status: .provisional)]
        let universe = LorcanaPhysicalUniverse(footer: try footer(), printingIDs: [firstID], isComplete: true, evidenceReference: "fixture:incomplete-claim")
        XCTAssertThrowsError(try LorcanaCatalogRegistry(manifest: manifest(prints, universes: [universe]))) {
            XCTAssertEqual($0 as? LorcanaPhysicalCatalog.ValidationError, .invalidUniverse)
        }
        let noReview = LorcanaPhysicalUniverse(footer: try footer(), printingIDs: [firstID], isComplete: true, evidenceReference: nil)
        XCTAssertThrowsError(try LorcanaCatalogRegistry(manifest: manifest(universes: [noReview])))
        let missing = try LorcanaCatalogRegistry(manifest: manifest(universes: []))
        XCTAssertNil(missing.physicalCatalog?.reviewedPrintings(for: try footer()))
    }

    func testMissingIdentityOrFinishEvidenceAndContradictoryFinishesRejectManifest() throws {
        for printing in try [printing(finishes: []), printing(finishes: [.foil, .foil]),
                              printing(identityEvidence: []), printing(finishUniverse: nil)] {
            XCTAssertThrowsError(try registry([printing])) {
                XCTAssertEqual($0 as? LorcanaPhysicalCatalog.ValidationError, .invalidPrinting)
            }
        }
        let body = try JSONEncoder().encode(manifest())
        let unknownFinish = Data(String(decoding: body, as: UTF8.self).replacingOccurrences(of: "\"finish\":\"foil\"", with: "\"finish\":\"future-finish\"").utf8)
        XCTAssertThrowsError(try LorcanaCatalogRegistry(data: unknownFinish))
    }

    func testSamePhysicalIdentityCannotAllocateTwoUUIDs() throws {
        XCTAssertThrowsError(try registry([printing(), printing(id: secondID)])) {
            XCTAssertEqual($0 as? LorcanaPhysicalCatalog.ValidationError, .duplicateIdentity)
        }
    }

    func testIndistinguishableLabelsAndUnavailableArtworkStayIncomplete() async throws {
        let secondArtwork = UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!
        let registry = try registry([printing(), printing(id: secondID, artwork: secondArtwork)])
        let adapter = LorcanaCatalogAdapter(registry: registry)
        guard case .catalogIncomplete = try await adapter.lookup(identifier(registry)) else {
            return XCTFail("Hidden artwork IDs without visible distinctions must not enable selection")
        }
        do { try await adapter.validateAcquisition(identifier(registry), printingID: firstID.uuidString.lowercased(), automatic: false); XCTFail() }
        catch CatalogLookupError.invalidPrintingChoice {}
    }

    func testArtworkLabelsSupplyExplicitDistinctionWithoutImageAvailability() async throws {
        let secondArtwork = UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!
        let registry = try registry([printing(), printing(id: secondID, artwork: secondArtwork, artworkLabel: "Fixture Alternate Artwork")])
        let adapter = LorcanaCatalogAdapter(registry: registry)
        guard case let .needsPrintingChoice(_, choices) = try await adapter.lookup(identifier(registry)) else { return XCTFail() }
        XCTAssertTrue(choices.allSatisfy { $0.thumbnailURL == nil && $0.selectionEvidence(among: choices) == .labels })
        _ = try await adapter.resolve(choices[1], for: identifier(registry))
    }

    func testBatchResolutionPreservesSizeLabelsAndWithholdsUnreviewedOrIndistinguishableFamilies() throws {
        let complete = try registry([printing(), printing(id: secondID, size: .oversized)])
        let rows = LorcanaCatalogAdapter(registry: complete).resolutions(forFooter: try footer())
        XCTAssertEqual(Set(rows.map { $0.printing.id }), [firstID, secondID])
        XCTAssertEqual(Set(rows.map { $0.resolution.card.name }), [
            "Fixture Elsa — Spirit of Winter · Size: Standard", "Fixture Elsa — Spirit of Winter · Size: Oversized"
        ])
        let secondArtwork = UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!
        let held = try registry([printing(), printing(id: secondID, size: .oversized, status: .provisional)])
        let indistinguishable = try registry([printing(), printing(id: secondID, artwork: secondArtwork)])
        let incomplete = try registry([printing()], complete: false)
        for catalog in [held, indistinguishable, incomplete] {
            XCTAssertTrue(LorcanaCatalogAdapter(registry: catalog).resolutions(forFooter: try footer()).isEmpty)
        }
    }

    func testBatchedCompactLabelsKeepCollisionFallbackAndHandleEmptyOrSingletonChoices() {
        func candidate(_ id: String, treatment: String, distribution: String) -> PhysicalPrintingCandidate {
            .init(id: id, game: .lorcana, canonicalCardID: "fixture", language: "en", catalogGeneration: "fixture",
                name: "Fixture", printedIdentifier: "207/204 EN 1", treatmentLabel: treatment, distributionLabel: distribution)
        }
        let first = candidate("first", treatment: "Original", distribution: "Premium")
        let second = candidate("second", treatment: "Premium", distribution: "Original")
        let third = candidate("third", treatment: "Premium", distribution: "Premium")
        let choices = [first, second, third]
        let labels = PhysicalPrintingCandidate.compactChoiceLabels(among: choices)
        XCTAssertEqual(labels[first.id], "Original · Premium")
        XCTAssertEqual(labels[second.id], "Premium · Original")
        XCTAssertEqual(labels[third.id], "Premium · Premium")
        XCTAssertEqual(Set(labels.values).count, 3)
        XCTAssertTrue(PhysicalPrintingCandidate.compactChoiceLabels(among: []).isEmpty)
        XCTAssertEqual(PhysicalPrintingCandidate.compactChoiceLabels(among: [first])[first.id], "Original")
    }

    func testTamperedCrossGameAndStaleChoicesCannotResolve() async throws {
        let registry = try registry([printing(), printing(id: secondID, size: .oversized)])
        let adapter = LorcanaCatalogAdapter(registry: registry), identifier = try identifier(registry)
        guard case let .needsPrintingChoice(_, choices) = try await adapter.lookup(identifier) else { return XCTFail() }
        let body = try JSONEncoder().encode(choices[0])
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let edits: [(String, Any)] = [("distinctionLabels", ["Size: Oversized", "Stamp: Unstamped", "Layout: normal"]),
                                     ("game", "magic"), ("catalogGeneration", "stale-generation"),
                                     ("canonicalCardID", "fake-canonical"), ("printedIdentifier", "tampered-footer")]
        for (field, value) in edits {
            var edited = original
            edited[field] = value
            let tampered = try JSONDecoder().decode(PhysicalPrintingCandidate.self,
                from: JSONSerialization.data(withJSONObject: edited))
            XCTAssertNotEqual(tampered, choices[0], "The fixture must actually alter \(field)")
            do { _ = try await adapter.resolve(tampered, for: identifier); XCTFail("Accepted tampered \(field)") }
            catch CatalogLookupError.invalidPrintingChoice {}
        }
        let updated = try self.registry([printing(), printing(id: secondID, size: .oversized, artworkLabel: "Updated display")])
        do { _ = try await LorcanaCatalogAdapter(registry: updated).resolve(choices[0], for: identifier); XCTFail() }
        catch CatalogLookupError.staleCatalog {}
    }

    func testRetryPreservesFooterRecoveryAcrossSchemaPromotionAndChoiceNeverBecomesDefault() async throws {
        let original = try LorcanaCatalogRegistry(manifest: .init(schemaVersion: 1, printFamilies: [family(footer())]))
        let old = try identifier(original)
        let promoted = try LorcanaCatalogRegistry(manifest: manifest([printing(), printing(id: secondID, size: .oversized)]), previous: original)
        let adapter = LorcanaCatalogAdapter(registry: promoted), rebased = try adapter.identifierForRetry(old)
        XCTAssertEqual(old.fields, rebased.fields)
        XCTAssertEqual(old.suppressionIdentity, rebased.suppressionIdentity)
        let catalog = try CardGameRuntimeContainer(runtimes: [LorcanaGameRuntime(registry: promoted).runtime]).makeCardCatalog()
        guard case let .needsPrintingChoice(_, choices) = try await catalog.lookupOutcome(for: rebased) else { return XCTFail() }
        _ = try await catalog.resolvePrintingChoice(choices[1], for: rebased)
        guard case let .needsPrintingChoice(_, again) = try await catalog.lookupOutcome(for: rebased) else { return XCTFail() }
        XCTAssertEqual(choices, again)
        XCTAssertEqual(ScanSubject(identifier: old).suppressionKey, ScanSubject(identifier: rebased).suppressionKey)
    }

    func testVariantCorrectionUsesExactPrintingRatherThanGlobalFinishMenu() throws {
        let registry = try registry([printing(finishes: [.normal]), printing(id: secondID, size: .oversized, finishes: [.foil])])
        XCTAssertEqual(LorcanaVariantPolicy(registry: registry).selectableVariants, [.normal, .foil])
        let adapter = LorcanaCatalogAdapter(registry: registry)
        XCTAssertNoThrow(try adapter.validateVariantCorrection(printingID: firstID.uuidString.lowercased(), variantID: "normal"))
        for finish in ["foil", "Normal", "etched", nil] {
            XCTAssertThrowsError(try adapter.validateVariantCorrection(printingID: firstID.uuidString.lowercased(), variantID: finish))
        }
        XCTAssertThrowsError(try adapter.validateVariantCorrection(printingID: firstID.uuidString.uppercased(), variantID: "normal"))
        XCTAssertThrowsError(try adapter.validateVariantCorrection(printingID: UUID().uuidString.lowercased(), variantID: "normal"))
    }

    func testExactChoicesSurviveRecoveryRelaunchAndModuleAbsence() async throws {
        let registry = try registry([printing(), printing(id: secondID, size: .oversized)])
        let adapter = LorcanaCatalogAdapter(registry: registry), identifier = try identifier(registry)
        guard case let .needsPrintingChoice(_, choices) = try await adapter.lookup(identifier) else { return XCTFail() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LorcanaPhysicalRecovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("unresolved.json")
        let encounter = UnresolvedScan(subject: ScanSubject(identifier: identifier), reason: .interrupted, printingCandidates: choices)
        let saved = await UnresolvedScanStore(fileURL: url).save([encounter])
        XCTAssertTrue(saved)
        let withoutModule = await UnresolvedScanStore(fileURL: url).load()
        XCTAssertTrue(withoutModule.first?.isReadOnly == true)
        XCTAssertEqual(withoutModule.first?.printingCandidates, choices)
        let adapters = try GameCatalogAdapterRegistry(adapters: [adapter])
        let restored = await UnresolvedScanStore(fileURL: url).load(gameCatalogAdapters: adapters)
        XCTAssertFalse(restored.first?.isReadOnly ?? true)
        XCTAssertEqual(restored.first?.id, encounter.id)
        XCTAssertEqual(restored.first?.printingCandidates, choices)
        let catalog = try CardGameRuntimeContainer(runtimes: [LorcanaGameRuntime(registry: registry).runtime]).makeCardCatalog()
        let resolved = try await catalog.resolvePrintingChoice(try XCTUnwrap(restored.first?.printingCandidates.last), for: identifier)
        XCTAssertEqual(resolved.card.physicalPrintingID, secondID.uuidString.lowercased())
    }

    func testUUIDAndOwnershipKeysSurviveAliasMetadataAndFinishAdditions() async throws {
        let original = try registry([printing(finishes: [.normal])])
        let additional = LorcanaSourceAlias(provider: "fixture", id: "new-source-alias")
        let revised = try manifest([printing(finishes: [.normal, .foil], aliases: [additional, alias], artworkLabel: "Updated label")],
            families: [family(footer(), aliases: [alias, additional])])
        let updated = try LorcanaCatalogRegistry(manifest: revised, previous: original)
        let before = try resolved(await LorcanaCatalogAdapter(registry: original).lookup(identifier(original)))
        let after = try resolved(await LorcanaCatalogAdapter(registry: updated).lookup(identifier(updated)))
        XCTAssertEqual(before.physicalPrintingID, after.physicalPrintingID)
        XCTAssertEqual(before.collectionKey(variant: .normal), after.collectionKey(variant: .normal))
        XCTAssertNotEqual(original.generation, updated.generation)
    }

    func testTransitionRejectsIdentityReuseRemovedIDsAliasesFinishesAndSchemaDowngrade() throws {
        let original = try registry()
        for changed in try [manifest([printing(size: .oversized)]), manifest([printing(finishes: [.normal])]),
                            manifest([printing(id: secondID)]), manifest([], families: [family(footer())])] {
            XCTAssertThrowsError(try LorcanaCatalogRegistry(manifest: changed, previous: original)) {
                XCTAssertEqual($0 as? LorcanaPhysicalCatalog.ValidationError, .invalidTransition)
            }
        }
        let additional = LorcanaSourceAlias(provider: "fixture", id: "retained-alias")
        let withAlias = try LorcanaCatalogRegistry(manifest: manifest([printing(aliases: [alias, additional])],
            families: [family(footer(), aliases: [alias, additional])]))
        XCTAssertThrowsError(try LorcanaCatalogRegistry(manifest: manifest(), previous: withAlias))
        let schema1 = try JSONEncoder().encode(LorcanaCatalogManifest(schemaVersion: 1, printFamilies: [family(footer())]))
        XCTAssertThrowsError(try LorcanaCatalogRegistry(data: schema1, previous: original))
    }

    func testExplicitCorrectionRetainsOldUUIDAndRequiresNewChoiceEvidence() async throws {
        let original = try registry()
        let correction = LorcanaPhysicalCorrection(id: UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!,
            fromPrintingIDs: [firstID], toPrintingIDs: [secondID], evidenceReferences: ["fixture:size-correction"])
        let changed = try manifest([printing(status: .superseded), printing(id: secondID, size: .oversized)], corrections: [correction])
        let registry = try LorcanaCatalogRegistry(manifest: changed, previous: original)
        XCTAssertNotNil(registry.physicalCatalog?.printingByID[firstID])
        let adapter = LorcanaCatalogAdapter(registry: registry)
        XCTAssertThrowsError(try adapter.validateVariantCorrection(printingID: firstID.uuidString.lowercased(), variantID: "foil"))
        guard case let .needsPrintingChoice(_, choices) = try await adapter.lookup(identifier(registry)) else { return XCTFail() }
        XCTAssertEqual(choices.map(\.id), [secondID.uuidString.lowercased()])
        XCTAssertThrowsError(try LorcanaCatalogRegistry(manifest: manifest([printing(status: .superseded), printing(id: secondID, size: .oversized)]), previous: original))
    }

    func testCorrectionCyclesAndMissingHistoryFailClosed() throws {
        let corrections = [LorcanaPhysicalCorrection(id: UUID(), fromPrintingIDs: [firstID], toPrintingIDs: [secondID], evidenceReferences: ["fixture:one"]),
                           LorcanaPhysicalCorrection(id: UUID(), fromPrintingIDs: [secondID], toPrintingIDs: [firstID], evidenceReferences: ["fixture:two"])]
        XCTAssertThrowsError(try LorcanaCatalogRegistry(manifest: manifest([printing(status: .superseded), printing(id: secondID, size: .oversized, status: .superseded)], corrections: corrections))) {
            XCTAssertEqual($0 as? LorcanaPhysicalCatalog.ValidationError, .invalidCorrection)
        }
        let records = try [printing(status: .superseded), printing(id: secondID, size: .oversized)]
        let prior = try LorcanaCatalogRegistry(manifest: manifest(records, corrections: [corrections[0]]))
        let replaced = LorcanaPhysicalCorrection(id: UUID(), fromPrintingIDs: [firstID], toPrintingIDs: [secondID], evidenceReferences: ["fixture:replacement"])
        XCTAssertThrowsError(try LorcanaCatalogRegistry(manifest: manifest(records, corrections: [replaced]), previous: prior)) {
            XCTAssertEqual($0 as? LorcanaPhysicalCatalog.ValidationError, .invalidTransition)
        }
    }

    func testGenerationIgnoresInputOrderAndRoundTripsSchemaTwo() throws {
        let prints = try [printing(), printing(id: secondID, size: .oversized)]
        let first = try LorcanaCatalogRegistry(manifest: manifest(prints))
        let second = try LorcanaCatalogRegistry(manifest: manifest(Array(prints.reversed())), previous: first)
        XCTAssertEqual(first.generation, second.generation)
        XCTAssertEqual(try LorcanaCatalogRegistry(data: JSONEncoder().encode(manifest(prints))).generation, first.generation)
        XCTAssertTrue(first.generation.hasPrefix("lorcana:s2:"))
    }

    func testLandscapeAndCrossSetCanonicalRelationshipPreserveDistinctPrintings() async throws {
        let firstFooter = try footer(number: "159", marker: "3"), secondFooter = try footer(number: "164", marker: "11")
        let secondAlias = LorcanaSourceAlias(provider: "fixture", id: "reprint-source")
        let prints = try [printing(footer: firstFooter, layout: "landscape"),
                          printing(id: secondID, footer: secondFooter, aliases: [secondAlias], layout: "landscape")]
        let manifest = try manifest(prints, families: [family(firstFooter, layout: "landscape"), family(secondFooter, aliases: [secondAlias], layout: "landscape")])
        let registry = try LorcanaCatalogRegistry(manifest: manifest), adapter = LorcanaCatalogAdapter(registry: registry)
        let first = try resolved(await adapter.lookup(identifier(registry, footer: firstFooter)))
        let second = try resolved(await adapter.lookup(identifier(registry, footer: secondFooter)))
        XCTAssertEqual(first.canonicalCardID, second.canonicalCardID)
        XCTAssertNotEqual(first.setID, second.setID)
        XCTAssertNotEqual(first.physicalPrintingID, second.physicalPrintingID)
        XCTAssertNotEqual(first.collectionKey(variant: .foil), second.collectionKey(variant: .foil))
    }

    func testConflictingCanonicalMembershipStaysIncomplete() async throws {
        let other = UUID(uuidString: "80000000-0000-0000-0000-000000000002")!
        let printings = try [printing(), printing(id: secondID, canonical: other, size: .oversized)]
        let canonicals = [LorcanaCanonicalCard(id: canonicalID, name: "Fixture A", version: nil, relationshipEvidenceReferences: ["fixture:a"]),
                          LorcanaCanonicalCard(id: other, name: "Fixture B", version: nil, relationshipEvidenceReferences: ["fixture:b"])]
        let registry = try LorcanaCatalogRegistry(manifest: manifest(printings, canonicalCards: canonicals))
        guard case .catalogIncomplete = try await LorcanaCatalogAdapter(registry: registry).lookup(identifier(registry)) else { return XCTFail() }
    }

    func testPhysicalRuntimeKeepsIndependentProductionCapabilitiesDisabled() throws {
        let registry = try registry(), runtime = LorcanaGameRuntime(registry: registry).runtime
        XCTAssertEqual(runtime.variantPolicy.selectableVariants, [.normal, .foil])
        for capability in [CardGameCapabilities.collectionWrite, .pricing, .sealed] {
            XCTAssertFalse(runtime.descriptor.capabilities.contains(capability))
        }
        XCTAssertTrue(runtime.descriptor.capabilities.contains(.browse))
        XCTAssertNotNil(runtime.browse); XCTAssertNotNil(runtime.importer); XCTAssertNil(runtime.pricing)
        XCTAssertNil(runtime.activationSource)
        XCTAssertFalse(CardGameRuntimeContainer.appDefaults().runtime(for: .lorcana)!.descriptor.capabilities.contains(.collectionWrite))
    }
}
