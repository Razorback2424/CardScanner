import Foundation
import XCTest
@testable import TradingCardScanner

final class LorcanaIntegrationTests: XCTestCase {
    private func family(_ number: String = "207", denominator: String = "204", marker: String = "1",
                        language: String = "en", providerSet: String = "TFC", name: String = "Fixture Elsa",
                        alias: String = "fixture-elsa", layout: String = "normal") throws -> LorcanaPrintFamily {
        .init(footer: try .init(collectorNumber: number, denominator: denominator, language: language,
                               printedSetMarker: marker), providerSetCode: providerSet, name: name,
              version: "Spirit of Winter", rarity: "future-premium-rarity", layout: layout,
              sourceAliases: [.init(provider: "fixture", id: alias)], footerEvidenceReference: "synthetic-test-footer")
    }

    private func registry(_ families: [LorcanaPrintFamily]? = nil) throws -> LorcanaCatalogRegistry {
        try .init(manifest: .init(schemaVersion: 1, printFamilies: families ?? [family()]))
    }

    private func identity(_ text: String, registry: LorcanaCatalogRegistry) throws -> ScanIdentifier {
        guard case let .identified(subject) = LorcanaRecognitionAdapter(registry: registry).identify([.init(text: text)]) else {
            XCTFail("Expected a complete footer: \(text)")
            throw LorcanaPrintedIdentity.ValidationError.invalidFooter
        }
        return subject.identifier
    }

    func testPremiumNumeratorAndProviderCodeRemainSeparateFromPrintedMarker() async throws {
        let registry = try registry()
        let identifier = try identity("207/204 EN 1", registry: registry)
        let footer = try family().footer
        XCTAssertEqual(registry.familiesByFooter[footer]?.providerSetCode, "TFC")
        XCTAssertEqual(registry.familiesByFooter[footer]?.rarity, "future-premium-rarity")
        let catalog = try CardGameRuntimeContainer(runtimes: [LorcanaGameRuntime(registry: registry).runtime]).makeCardCatalog()
        guard case let .catalogIncomplete(summary) = try await catalog.lookupOutcome(for: identifier) else {
            return XCTFail("A print family cannot become an owned printing")
        }
        XCTAssertEqual(summary?.id, "lorcana-family:en:1:207:204")
        XCTAssertEqual(summary?.printedIdentifier, "207/204 EN 1")
    }

    func testCatalogDrivenDenominatorsMarkersLanguagesAndLayouts() throws {
        let entries = try [family("158", denominator: "207", marker: "99", alias: "new-set"),
                           family("7", denominator: "P9", marker: "CC9", alias: "promo", layout: "landscape"),
                           family("207", language: "fr", alias: "french")]
        let registry = try registry(entries)
        for entry in entries {
            let identifier = try identity(entry.footer.displayIdentifier, registry: registry)
            XCTAssertEqual(identifier.game, .lorcana)
            XCTAssertEqual(identifier.displayIdentifier, entry.footer.displayIdentifier)
        }
        XCTAssertTrue(registry.customWords.contains("CC9"))
        XCTAssertTrue(registry.customWords.contains("P9"))
        XCTAssertFalse(registry.customWords.contains("207/204 EN 1"))
    }

    func testSameGameplayNameInDifferentSetsNeverSharesFamilyOrSuppression() throws {
        let registry = try registry([family("159", marker: "3", name: "Fixture Distract", alias: "first"),
                                     family("164", marker: "11", name: "Fixture Distract", alias: "reprint")])
        let first = try identity("159/204 EN 3", registry: registry)
        let second = try identity("164/204 EN 11", registry: registry)
        XCTAssertEqual(registry.familiesByFooter.count, 2)
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(ScanSubject(identifier: first).suppressionKey, ScanSubject(identifier: second).suppressionKey)
    }

    func testNumericConfusionsStayInsideKnownNumericPositions() throws {
        let registry = try registry()
        XCTAssertEqual(try identity("2O7/2O4 en 1", registry: registry).displayIdentifier, "207/204 EN 1")
        // Unknown tokens are kept literally and cannot borrow a known print.
        XCTAssertEqual(try identity("207/P1 EN 1", registry: registry).displayIdentifier, "207/P1 EN 1")
        XCTAssertEqual(try identity("207/204 EN I", registry: registry).displayIdentifier, "207/204 EN I")
        XCTAssertEqual(LorcanaRecognitionAdapter(registry: registry).identify([.init(text: "2O7/204 EN 99")]), .nothing)
        let tokenRegistry = try self.registry([family(denominator: "LIL")])
        XCTAssertEqual(try identity("207/LIL EN 1", registry: tokenRegistry).displayIdentifier, "207/LIL EN 1")
    }

    func testMissingComponentsAndInvalidGeometryCannotSupplyIdentity() throws {
        let recognizer = LorcanaRecognitionAdapter(registry: try registry())
        for text in ["207/204", "207/204 1", "EN 1", "207/204 EN", "0/204 EN 1", "207/0 EN 1",
                     "207/204 EN 1/42", "OP01-120", "207/204\nEN 1"] {
            XCTAssertEqual(recognizer.identify([.init(text: text)]), .nothing, text)
        }
        XCTAssertEqual(recognizer.identify([.init(text: "207/204"), .init(text: "EN 1")]), .nothing)
        for bounds in [CGRect(x: 2, y: 0, width: 0.2, height: 0.1),
                       CGRect(x: 0, y: 0, width: 0, height: 0.1),
                       CGRect(x: Double.nan, y: 0, width: 0.2, height: 0.1)] {
            XCTAssertEqual(recognizer.identify([.init(text: "207/204 EN 1", boundingBox: bounds)]), .nothing)
        }
    }

    func testEveryDistinctFooterIncludingUnknownNumberCountsTowardAmbiguity() throws {
        let recognizer = LorcanaRecognitionAdapter(registry: try registry())
        XCTAssertEqual(recognizer.identify([.init(text: "207/204 EN 1 and 208/204 EN 99")]), .ambiguous)
        XCTAssertEqual(recognizer.identify([.init(text: "207/204 EN 1"), .init(text: "207/204 FR 1")]), .ambiguous)
        guard case .identified = recognizer.identify([.init(text: "207/204 EN 1"), .init(text: "207/204 EN 1")]) else {
            return XCTFail("Repeated readings of one footer must deduplicate")
        }
    }

    func testUnknownFutureFooterRemainsIncompleteWithoutClosestMatch() async throws {
        let registry = try registry()
        let adapter = LorcanaCatalogAdapter(registry: registry)
        for text in ["208/204 EN 1", "207/207 EN 1", "207/204 EN 99", "207/204 JA 1"] {
            let identifier = try identity(text, registry: registry)
            guard case let .catalogIncomplete(summary) = try await adapter.lookup(identifier) else {
                return XCTFail("Unknown evidence must stay incomplete")
            }
            XCTAssertNil(summary)
            XCTAssertEqual(identifier.displayIdentifier, text)
        }
    }

    func testRegistryFailsClosedOnDuplicateMappingsAndFutureSchema() throws {
        let original = try family()
        XCTAssertThrowsError(try registry([original, original])) {
            XCTAssertEqual($0 as? LorcanaCatalogRegistry.ValidationError, .duplicateFooter)
        }
        XCTAssertThrowsError(try registry([original, family("208")])) {
            XCTAssertEqual($0 as? LorcanaCatalogRegistry.ValidationError, .duplicateSourceAlias)
        }
        XCTAssertThrowsError(try LorcanaCatalogRegistry(manifest: .init(schemaVersion: 2, printFamilies: [original])))
        let invalid = LorcanaPrintFamily(footer: original.footer, providerSetCode: " ", name: original.name,
            version: nil, rarity: "Promo", layout: "normal", sourceAliases: original.sourceAliases, footerEvidenceReference: "")
        XCTAssertThrowsError(try registry([invalid]))
        let invalidFooter = Data(#"{"collectorNumber":"0","denominator":"204","language":"en","printedSetMarker":"1"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(LorcanaPrintedIdentity.self, from: invalidFooter))
    }

    func testGenerationIsContentDerivedAndIndependentOfInputOrder() throws {
        let first = try family(), second = try family("208", alias: "second")
        let registry = try registry([first, second])
        XCTAssertEqual(registry.generation, try self.registry([second, first]).generation)
        let changed = try family(name: "Changed metadata")
        XCTAssertNotEqual(registry.generation, try self.registry([changed, second]).generation)
        let data = try JSONEncoder().encode(LorcanaCatalogManifest(schemaVersion: 1, printFamilies: [second, first]))
        XCTAssertEqual(registry.generation, try LorcanaCatalogRegistry(data: data).generation)
    }

    func testRetryRebasesGenerationButRejectsTamperedOrFuturePayload() async throws {
        let registry = try registry(), identifier = try identity("207/204 EN 1", registry: registry)
        let updated = LorcanaCatalogAdapter(registry: try self.registry([family(name: "Changed metadata")]))
        do { _ = try await updated.lookup(identifier); XCTFail("Old generation must be rejected") }
        catch CatalogLookupError.staleCatalog {}
        let rebased = try updated.identifierForRetry(identifier)
        XCTAssertEqual(rebased.fields, identifier.fields)
        XCTAssertEqual(rebased.suppressionIdentity, identifier.suppressionIdentity)
        XCTAssertEqual(rebased.catalogGeneration, updated.generation)
        for fields in [identifier.fields + [.init(key: "futureField", value: "unknown")],
                       identifier.fields.filter { $0.key != "language" }] {
            let changed = try ScanIdentifier(game: .lorcana, namespace: identifier.namespace, fields: fields,
                displayIdentifier: identifier.displayIdentifier, suppressionIdentity: identifier.suppressionIdentity)
            XCTAssertThrowsError(try updated.identifierForRetry(changed))
        }
        let tampered = try ScanIdentifier(game: .lorcana, namespace: identifier.namespace, fields: identifier.fields,
            displayIdentifier: "Ordinary Elsa", suppressionIdentity: identifier.suppressionIdentity)
        XCTAssertThrowsError(try updated.identifierForRetry(tampered))
    }

    func testRuntimeUsesSharedAdaptersAndKeepsProductionAndWritesDisabled() async throws {
        let runtime = LorcanaGameRuntime(registry: try registry()).runtime
        let container = try CardGameRuntimeContainer(runtimes: [runtime])
        XCTAssertEqual(container.registry.enabledGames, [.lorcana])
        for capability in [CardGameCapabilities.browse, .pricing, .sealed, .collectionWrite] {
            XCTAssertFalse(container.registry.supports(.lorcana, capability))
        }
        XCTAssertTrue(container.registry.variantLockMenu.isEmpty)
        XCTAssertNil(runtime.pricing); XCTAssertNil(runtime.importer); XCTAssertNil(runtime.browse)
        XCTAssertNil(CardGameRuntimeContainer.appDefaults().runtime(for: .lorcana))
        XCTAssertFalse(CardGameRegistry.standard.enabledGames.contains(.lorcana))
        XCTAssertEqual(CardGame.lorcana.label, "Disney Lorcana")
        XCTAssertEqual(try JSONDecoder().decode(CardGame.self, from: JSONEncoder().encode(CardGame.lorcana)), .lorcana)
    }

    func testCrossGameRecognitionCollisionCannotBeWonByRegistrationOrder() throws {
        struct OtherRecognizer: GameRecognitionAdapter {
            let game = CardGame.magic
            let customWords: [String] = []
            let identifier: ScanIdentifier
            func identify(_ lines: [RecognizedLine]) -> GameRecognitionOutcome {
                .identified(ScanSubject(identifier: identifier))
            }
        }
        let other = OtherRecognizer(identifier: try .init(game: .magic, namespace: "fixture",
            fields: [.init(key: "number", value: "1")], displayIdentifier: "1", suppressionIdentity: "1"))
        let lorcana = LorcanaRecognitionAdapter(registry: try registry())
        let registrations: [[any GameRecognitionAdapter]] = [[other, lorcana], [lorcana, other]]
        for adapters in registrations {
            XCTAssertEqual(try GameRecognitionRegistry(recognizers: adapters).identify([.init(text: "207/204 EN 1")]), .ambiguous)
        }
    }

    func testGenericRecoveryPreservesFooterWithAndWithoutInstalledModule() async throws {
        let registry = try registry(), identifier = try identity("207/204 EN 1", registry: registry)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LorcanaRecovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("unresolved.json")
        let store = UnresolvedScanStore(fileURL: url)
        let saved = await store.save([.init(subject: ScanSubject(identifier: identifier), reason: .lookupFailed)])
        XCTAssertTrue(saved)
        let unsupported = await UnresolvedScanStore(fileURL: url).load()
        XCTAssertEqual(unsupported.first?.identifier, identifier)
        XCTAssertTrue(unsupported.first?.isReadOnly == true)
        let adapters = try GameCatalogAdapterRegistry(adapters: [LorcanaCatalogAdapter(registry: registry)])
        let restored = await UnresolvedScanStore(fileURL: url).load(gameCatalogAdapters: adapters)
        XCTAssertEqual(restored.first?.identifier, identifier)
        XCTAssertEqual(restored.first?.game, .lorcana)
        XCTAssertFalse(restored.first?.isReadOnly ?? true)
    }
}
