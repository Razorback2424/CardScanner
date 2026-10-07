import XCTest
@testable import TradingCardScanner

final class MagicRecognitionProfileTests: XCTestCase {
    private func descriptor(code: String = "EXO", date: String? = "1998-06-15",
                            scan: Bool = false, browse: Bool = true) -> MagicCatalogSetDescriptor {
        .init(scryfallSetID: "00000000-0000-4000-8000-000000000001", code: code,
              displayName: "Example", releaseDate: date, setType: "expansion",
              printedSize: 143, cardCount: 143, iconSVGURL: nil, parentSetCode: nil,
              routingKind: nil, scanEnabled: scan, browseEnabled: browse)
    }

    func testDateDefaultsAreClassificationOnly() throws {
        for (date, route) in [("1998-06-14", MagicRecognitionRoute.legacyNoCollectorNumber),
                              ("1998-06-15", .legacyCollectorNumber),
                              ("2014-07-17", .legacyCollectorNumber),
                              ("2014-07-18", .modernFooter)] {
            let snapshot = try MagicRecognitionProfileSnapshot(descriptors: [descriptor(date: date)])
            let profile = snapshot.profile(setCode: " exo ")
            XCTAssertEqual(profile.route, route)
            XCTAssertFalse(profile.acquisitionEnabled)
        }
        for date in [nil, "1998-06-31", "unknown"] as [String?] {
            let snapshot = try MagicRecognitionProfileSnapshot(descriptors: [descriptor(date: date)])
            XCTAssertEqual(snapshot.profile(setCode: "EXO").route, .unknown)
        }
    }

    func testModernAuthorityAndBrowseStayIndependent() throws {
        let historical = descriptor(code: "PLG20", date: "2000-01-01")
        let snapshot = try MagicRecognitionProfileSnapshot(descriptors: [historical])
        XCTAssertEqual(snapshot.profile(setCode: "PLG20").route, .legacyCollectorNumber)
        XCTAssertFalse(snapshot.profile(setCode: "PLG20").acquisitionEnabled)
        XCTAssertTrue(historical.browseEnabled)
        let modern = try MagicRecognitionProfileSnapshot(descriptors: [descriptor(date: "2020-01-01", scan: true)])
        XCTAssertTrue(modern.profile(setCode: "EXO").acquisitionEnabled)
        let hidden = try MagicRecognitionProfileSnapshot(descriptors: [descriptor(browse: false)])
        XCTAssertEqual(hidden.profile(setCode: "EXO").route, .unknown)
        XCTAssertEqual(hidden.profile(setCode: "missing"), .disabled)
    }

    func testBundledProjectionDoesNotChangeModernVocabulary() {
        let registry = MagicCatalogRegistry.bundledSeed
        for descriptor in registry.descriptors {
            let profile = registry.recognitionProfiles.profile(setCode: descriptor.code)
            XCTAssertEqual(profile.acquisitionEnabled, descriptor.scanEnabled)
            if descriptor.scanEnabled { XCTAssertEqual(profile.route, .modernFooter) }
        }
        XCTAssertEqual(registry.scannerDefinitions.count, 353)
        XCTAssertFalse(registry.recognitionProfiles.profile(setCode: "EXO").acquisitionEnabled)
    }

    func testOverrideChangesGenerationWithoutChangingModernProjection() throws {
        let sets = [descriptor()]
        let original = try MagicRecognitionProfileSnapshot(descriptors: sets)
        let override = MagicRecognitionPrintingOverride(
            printingID: "00000000-0000-4000-8000-000000000002", setCode: "EXO",
            route: .legacyNoCollectorNumber, reviewReference: "fixture-review-1")
        let changed = try MagicRecognitionProfileSnapshot(descriptors: sets, overrides: [override])
        XCTAssertNotEqual(original.generation, changed.generation)
        XCTAssertEqual(changed.profile(setCode: "exo", printingID: override.printingID).route, .legacyNoCollectorNumber)
        XCTAssertFalse(changed.profile(setCode: "exo", printingID: override.printingID).acquisitionEnabled)
        XCTAssertEqual(changed.profile(setCode: "other", printingID: override.printingID), .disabled)
        XCTAssertNotEqual(original.generation,
                          try MagicRecognitionProfileSnapshot(descriptors: sets, indexGeneration: "reviewed-index-2").generation)
        XCTAssertNotEqual(original.generation,
                          try MagicRecognitionProfileSnapshot(descriptors: sets, catalogRevision: 2).generation)
    }

    func testCanonicalGenerationAndUnknownProfilesFailClosed() throws {
        let first = descriptor()
        let second = MagicCatalogSetDescriptor(scryfallSetID: "00000000-0000-4000-8000-000000000003",
            code: "M15", displayName: "Modern", releaseDate: "2014-07-18", setType: "core",
            printedSize: 269, cardCount: 269, iconSVGURL: nil, parentSetCode: nil, routingKind: nil,
            scanEnabled: true, browseEnabled: true)
        let a = try MagicRecognitionProfileSnapshot(descriptors: [first, second])
        let b = try MagicRecognitionProfileSnapshot(descriptors: [second, first])
        XCTAssertEqual(a.generation, b.generation)
        XCTAssertThrowsError(try JSONDecoder().decode(MagicRecognitionRoute.self, from: Data("\"futureRoute\"".utf8)))
        XCTAssertThrowsError(try MagicRecognitionProfileSnapshot(descriptors: [first], version: 2))
        XCTAssertThrowsError(try MagicRecognitionProfileSnapshot(descriptors: [first, first]))
        XCTAssertThrowsError(try MagicRecognitionProfileSnapshot(descriptors: [first], overrides: [
            .init(printingID: "not-an-id", setCode: "EXO", route: .legacyCollectorNumber, reviewReference: "review")
        ]))
        let override = MagicRecognitionPrintingOverride(
            printingID: "00000000-0000-4000-8000-000000000002", setCode: "exo",
            route: .modernFooter, reviewReference: "review")
        let changed = try MagicRecognitionProfileSnapshot(descriptors: [first], overrides: [override])
        XCTAssertFalse(changed.profile(setCode: "EXO", printingID: override.printingID).acquisitionEnabled,
                       "a reviewed route must not turn historical metadata into modern authority")
        XCTAssertThrowsError(try MagicRecognitionProfileSnapshot(descriptors: [first], overrides: [override, override]))
        XCTAssertThrowsError(try MagicRecognitionProfileSnapshot(descriptors: [first], overrides: [
            .init(printingID: override.printingID, setCode: "missing", route: .modernFooter, reviewReference: "review")
        ]))
        XCTAssertThrowsError(try MagicRecognitionProfileSnapshot(descriptors: [first], indexGeneration: " "))
    }

    func testAtomicActivationRejectsStaleContextAndInvalidatesCapturedGeneration() async throws {
        let original = try MagicRecognitionProfileSnapshot(descriptors: [descriptor()])
        let store = MagicRecognitionProfileStore(snapshot: original)
        let changed = try MagicRecognitionProfileSnapshot(descriptors: [descriptor()], indexGeneration: "index-2")
        let activated = try await store.activate(changed, expectedGeneration: original.generation)
        XCTAssertTrue(activated)
        let staleIsCurrent = await store.isCurrent(original.generation)
        XCTAssertFalse(staleIsCurrent)
        do {
            _ = try await store.activate(original, expectedGeneration: original.generation)
            XCTFail("stale activation must not overwrite the active snapshot")
        } catch {}
        let current = await store.snapshot
        XCTAssertEqual(current.generation, changed.generation)
        let repeated = try await store.activate(changed, expectedGeneration: changed.generation)
        XCTAssertFalse(repeated)
    }
}
