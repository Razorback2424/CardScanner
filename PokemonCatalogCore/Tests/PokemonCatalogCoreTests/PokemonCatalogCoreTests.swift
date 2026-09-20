import CryptoKit
import Foundation
import XCTest
@testable import PokemonCatalogCore

final class PokemonCatalogCoreTests: XCTestCase {
    private let generatedAt = Date(timeIntervalSince1970: 1_768_000_000)

    func testTCGdexPathComponentsEncodePercentExactlyOnce() throws {
        let base = try XCTUnwrap(URL(string: "https://api.tcgdex.net/v2/en"))

        let escapedQuestionMark = PokemonCatalogTCGdexProviderClient.makeURL(
            baseURL: base,
            pathComponents: ["cards", "exu-%3F"]
        )
        XCTAssertEqual(
            escapedQuestionMark.absoluteString,
            "https://api.tcgdex.net/v2/en/cards/exu-%253F"
        )

        let ordinaryID = PokemonCatalogTCGdexProviderClient.makeURL(
            baseURL: base,
            pathComponents: ["cards", "sv01-001"]
        )
        XCTAssertEqual(
            ordinaryID.absoluteString,
            "https://api.tcgdex.net/v2/en/cards/sv01-001"
        )
    }

    func testDetailedProviderSetDecodesSeriesAndOfficialAbbreviation() throws {
        let data = Data("""
        {
          "id": "30th",
          "name": "30th Celebration",
          "cards": [],
          "serie": {"id": "me", "name": "Mega Evolution"},
          "abbreviation": {"official": "30C"},
          "cardCount": {"total": 128, "official": 128}
        }
        """.utf8)

        let set = try PokemonCatalogJSON.decode(
            PokemonCatalogProviderSet.self,
            from: data
        )

        XCTAssertEqual(set.serie, .init(id: "me", name: "Mega Evolution"))
        XCTAssertEqual(set.abbreviation, .init(official: "30C"))
        XCTAssertEqual(set.cardCount?.official, 128)
    }

    func testRecordedProviderFixtureWithoutNewMetadataStillDecodes() throws {
        let fixture = try load(PokemonCatalogProviderFixture.self, named: "recorded-provider")
        XCTAssertNil(fixture.sets.first?.serie)
        XCTAssertNil(fixture.sets.first?.abbreviation)
    }

    func testOrdinaryExpansionDerivesProviderCodeCountAndArtworkFallbackHints() throws {
        let fixture = providerFixture(
            sets: [
                .init(
                    id: "sv99",
                    name: "Recorded Test Set",
                    code: "TST",
                    releaseDate: "2026-09-18",
                    imageURLs: [
                        "https://assets.tcgdex.net/en/sv/sv99/001",
                        "https://assets.tcgdex.net/en/sv/sv99/002",
                        "https://assets.tcgdex.net/en/sv/sv99/003",
                        "https://assets.tcgdex.net/en/sv/sv99/004"
                    ]
                )
            ]
        )

        let result = try PokemonCatalogBuilder().build(
            .init(
                fixture: fixture,
                humanInputs: [],
                revision: 1,
                generatedAt: generatedAt
            )
        )

        let descriptor = try XCTUnwrap(result.release.sets.first)
        XCTAssertEqual(descriptor.printedCode, "TST")
        XCTAssertEqual(descriptor.officialCount, 4)
        XCTAssertTrue(descriptor.scanEnabled)
        XCTAssertEqual(
            result.snapshot.entries.first?.artworkFallbackURLs,
            Array(fixture.cards.map(\.image).compactMap { $0 }.prefix(3))
        )
    }

    func testMissingProviderAbbreviationUsesValidOperatorFallback() throws {
        let fixture = providerFixture(
            sets: [
                .init(
                    id: "sv99",
                    name: "Recorded Test Set",
                    code: nil,
                    releaseDate: "2026-09-18",
                    imageURLs: ["https://assets.tcgdex.net/en/sv/sv99/001"]
                )
            ]
        )
        let input = PokemonCatalogHumanInput(
            providerSetID: "sv99",
            recognitionKind: .expansion,
            printedCode: " tst ",
            claimedOfficialCount: nil
        )

        let result = try PokemonCatalogBuilder().build(
            .init(
                fixture: fixture,
                humanInputs: [input],
                revision: 1,
                generatedAt: generatedAt
            )
        )

        XCTAssertEqual(result.release.sets.first?.printedCode, "TST")
        XCTAssertEqual(result.release.sets.first?.officialCount, 1)
    }

    func testMalformedProviderAbbreviationFailsClosedWithoutOverride() throws {
        let fixture = providerFixture(
            sets: [
                .init(
                    id: "sv99",
                    name: "Recorded Test Set",
                    code: "TOOLONG",
                    releaseDate: "2026-09-18",
                    imageURLs: ["https://assets.tcgdex.net/en/sv/sv99/001"]
                )
            ]
        )

        XCTAssertThrowsError(
            try PokemonCatalogBuilder().build(
                .init(
                    fixture: fixture,
                    humanInputs: [],
                    revision: 1,
                    generatedAt: generatedAt
                )
            )
        ) { error in
            guard case let PokemonCatalogBuildError.invalidProviderPrintedCode(id, value) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(id, "sv99")
            XCTAssertEqual(value, "TOOLONG")
        }
    }

    func testValidProviderCodeCannotBeSilentlyOverriddenByOperatorInput() throws {
        let fixture = providerFixture(
            sets: [
                .init(
                    id: "sv99",
                    name: "Recorded Test Set",
                    code: "TST",
                    releaseDate: "2026-09-18",
                    imageURLs: ["https://assets.tcgdex.net/en/sv/sv99/001"]
                )
            ]
        )
        let input = PokemonCatalogHumanInput(
            providerSetID: "sv99",
            recognitionKind: .expansion,
            printedCode: "OLD",
            claimedOfficialCount: 1
        )

        XCTAssertThrowsError(
            try PokemonCatalogBuilder().build(
                .init(fixture: fixture, humanInputs: [input], revision: 1, generatedAt: generatedAt)
            )
        ) { error in
            guard case let PokemonCatalogBuildError.providerPrintedCodeConflict(id, human, provider) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(id, "sv99")
            XCTAssertEqual(human, "OLD")
            XCTAssertEqual(provider, "TST")
        }
    }

    func testActiveProviderCodeDriftFailsEvenWhenLegacyInputAgreesWithActiveCode() throws {
        let initialFixture = providerFixture(
            sets: [
                .init(
                    id: "sv99",
                    name: "Recorded Test Set",
                    code: "TST",
                    releaseDate: "2026-09-18",
                    imageURLs: ["https://assets.tcgdex.net/en/sv/sv99/001"]
                )
            ]
        )
        let initial = try PokemonCatalogBuilder().build(
            .init(
                fixture: initialFixture,
                humanInputs: [],
                revision: 1,
                generatedAt: generatedAt
            )
        )
        let driftFixture = providerFixture(
            sets: [
                .init(
                    id: "sv99",
                    name: "Recorded Test Set",
                    code: "NEW",
                    releaseDate: "2026-09-18",
                    imageURLs: ["https://assets.tcgdex.net/en/sv/sv99/001"]
                )
            ]
        )
        let legacyInput = PokemonCatalogHumanInput(
            providerSetID: "sv99",
            recognitionKind: .expansion,
            printedCode: "TST",
            claimedOfficialCount: 1
        )

        XCTAssertThrowsError(
            try PokemonCatalogBuilder().build(
                .init(
                    fixture: driftFixture,
                    activeRelease: initial.release,
                    humanInputs: [legacyInput],
                    revision: 2,
                    generatedAt: generatedAt
                )
            )
        ) { error in
            guard case let PokemonCatalogBuildError.providerPrintedCodeDrift(id, active, provider) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(id, "sv99")
            XCTAssertEqual(active, "TST")
            XCTAssertEqual(provider, "NEW")
        }
    }

    func testActiveDescriptorPreservesScannerAuthorityWhileRefreshingPresentationMetadata() throws {
        let initialFixture = providerFixture(
            sets: [
                .init(
                    id: "sv99",
                    name: "Recorded Test Set",
                    code: "TST",
                    releaseDate: "2026-09-18",
                    imageURLs: ["https://assets.tcgdex.net/en/sv/sv99/001"]
                )
            ]
        )
        let initial = try PokemonCatalogBuilder().build(
            .init(fixture: initialFixture, humanInputs: [], revision: 1, generatedAt: generatedAt)
        )
        let enrichedFixture = providerFixture(
            sets: [
                .init(
                    id: "sv99",
                    name: "Renamed Recorded Test Set",
                    code: "TST",
                    releaseDate: "2026-09-19",
                    imageURLs: ["https://assets.tcgdex.net/en/sv/sv99/001"],
                    logo: "https://assets.tcgdex.net/en/sv/sv99/logo.png"
                )
            ]
        )

        let result = try PokemonCatalogBuilder().build(
            .init(
                fixture: enrichedFixture,
                activeRelease: initial.release,
                humanInputs: [],
                revision: 2,
                generatedAt: generatedAt
            )
        )
        let descriptor = try XCTUnwrap(result.release.sets.first)
        XCTAssertEqual(descriptor.printedCode, "TST")
        XCTAssertEqual(descriptor.officialCount, 1)
        XCTAssertTrue(descriptor.scanEnabled)
        XCTAssertEqual(descriptor.releaseOrder, initial.release.sets.first?.releaseOrder)
        XCTAssertEqual(descriptor.displayName, "Renamed Recorded Test Set")
        XCTAssertEqual(descriptor.releaseDate, "2026-09-19")
        XCTAssertEqual(descriptor.logoURL, "https://assets.tcgdex.net/en/sv/sv99/logo.png")
        XCTAssertEqual(result.report.changedProviderSetIDs, ["sv99"])
    }

    func testAutomaticReleaseOrdersUseDateThenProviderIDWithoutRenumberingActiveSets() throws {
        let fixture = providerFixture(
            sets: [
                .init(
                    id: "later",
                    name: "Later",
                    code: "LAT",
                    releaseDate: "2026-09-20",
                    imageURLs: ["https://assets.tcgdex.net/en/sv/later/001"]
                ),
                .init(
                    id: "earlier",
                    name: "Earlier",
                    code: "EAR",
                    releaseDate: "2026-09-19",
                    imageURLs: ["https://assets.tcgdex.net/en/sv/earlier/001"]
                )
            ]
        )
        let result = try PokemonCatalogBuilder().build(
            .init(
                fixture: fixture,
                humanInputs: [],
                revision: 1,
                generatedAt: generatedAt
            )
        )

        let orders = Dictionary(uniqueKeysWithValues: result.release.sets.map {
            ($0.providerSetID, $0.releaseOrder)
        })
        XCTAssertEqual(orders["earlier"], 0)
        XCTAssertEqual(orders["later"], 1)
    }

    func testWholeCandidateCollisionIsRejectedAfterAllDescriptorsAreBuilt() throws {
        let fixture = providerFixture(
            sets: [
                .init(
                    id: "first",
                    name: "First",
                    code: "SAM",
                    releaseDate: "2026-09-18",
                    imageURLs: ["https://assets.tcgdex.net/en/sv/first/001"]
                ),
                .init(
                    id: "second",
                    name: "Second",
                    code: "SAM",
                    releaseDate: "2026-09-19",
                    imageURLs: ["https://assets.tcgdex.net/en/sv/second/001"]
                )
            ]
        )

        XCTAssertThrowsError(
            try PokemonCatalogBuilder().build(
                .init(
                    fixture: fixture,
                    humanInputs: [],
                    revision: 1,
                    generatedAt: generatedAt
                )
            )
        ) { error in
            guard case PokemonCatalogReleaseValidator.ValidationError.duplicatePrintedCode = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testNotScannableSameCodeCoexistsWithExpansionWithoutEnteringExpansionNamespace() throws {
        let release = PokemonCatalogRelease(
            revision: 1,
            generatedAt: generatedAt,
            sets: [
                descriptor(providerID: "30th", code: "30C", count: 128),
                PokemonCatalogSetDescriptor(
                    providerSetID: "30th-c",
                    displayName: "30th Classic Collection",
                    releaseDate: "2026-09-16",
                    releaseOrder: 23,
                    recognitionKind: .notScannable,
                    printedCode: "30C",
                    officialCount: nil,
                    printedPrefix: nil,
                    catalogLocalIDPrefix: nil,
                    localIDPadWidth: nil,
                    scanEnabled: false,
                    logoURL: nil,
                    symbolURL: nil
                )
            ]
        )

        XCTAssertNoThrow(try PokemonCatalogReleaseValidator.validate(release))
    }

    func testArtworkResolverAcceptsOnlyImageMIMEAndTriesEnglishThenUniversal() async throws {
        let resolver = PokemonCatalogTCGdexArtworkResolver { request in
            let url = try XCTUnwrap(request.url)
            let isUniversal = url.path.hasPrefix("/univ/")
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: url,
                    statusCode: isUniversal ? 200 : 200,
                    httpVersion: nil,
                    headerFields: [
                        "Content-Type": isUniversal ? "image/png" : "text/html"
                    ]
                )
            )
            return (Data(), response)
        }

        let result = await resolver.resolve(
            seriesID: "me",
            setID: "30th",
            kind: .logo
        )

        XCTAssertEqual(result, "https://assets.tcgdex.net/univ/me/30th/logo.png")
    }

    func testSnapshotEntryWithoutOptionalArtworkFieldRemainsReadable() throws {
        let oldJSON = Data("""
        {
          "providerSetID": "sv99",
          "displayName": "Recorded Test Set",
          "printedCode": "TST",
          "officialCount": 1,
          "releaseOrder": 0,
          "providerFingerprint": "fixture",
          "cardCount": 1,
          "resource": "sets/sv99.json"
        }
        """.utf8)

        let entry = try PokemonCatalogJSON.decode(
            PokemonCatalogSnapshotEntry.self,
            from: oldJSON
        )
        XCTAssertNil(entry.artworkFallbackURLs)
    }

    func testRecordedProviderFixtureProducesDeterministicReleaseAndSnapshot() throws {
        let fixture = try load(PokemonCatalogProviderFixture.self, named: "recorded-provider")
        let input = try load(PokemonCatalogHumanInputFile.self, named: "catalog-input")
        let request = PokemonCatalogBuildRequest(
            fixture: fixture,
            humanInputs: input.sets,
            revision: 1,
            generatedAt: generatedAt
        )

        let first = try PokemonCatalogBuilder().build(request)
        let second = try PokemonCatalogBuilder().build(request)

        XCTAssertEqual(try PokemonCatalogJSON.encode(first.release), try PokemonCatalogJSON.encode(second.release))
        XCTAssertEqual(try PokemonCatalogJSON.encode(first.snapshot), try PokemonCatalogJSON.encode(second.snapshot))
        XCTAssertEqual(first.report, second.report)
        XCTAssertEqual(first.release.sets.map(\.providerSetID), ["sv99"])
        XCTAssertEqual(first.snapshot.checklists["sv99"]?.map(\.localID), ["001", "002"])
        XCTAssertEqual(first.report.excludedProviderSetIDs, ["tcgp01"])
    }

    func testNewSetWithoutProviderCodeOrOperatorFallbackIsRejected() throws {

        let fixture = try load(PokemonCatalogProviderFixture.self, named: "recorded-provider")
        let request = PokemonCatalogBuildRequest(
            fixture: fixture,
            humanInputs: [],
            revision: 1,
            generatedAt: generatedAt
        )

        XCTAssertThrowsError(try PokemonCatalogBuilder().build(request)) { error in
            guard case let PokemonCatalogBuildError.humanPrintedCodeRequired(id) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(id, "sv99")
        }
    }

    func testCandidateValidatorBindsReleaseSnapshotAndReportAndEnforcesActiveRevision() throws {
        let fixture = try load(PokemonCatalogProviderFixture.self, named: "recorded-provider")
        let input = try load(PokemonCatalogHumanInputFile.self, named: "catalog-input")
        let build = try PokemonCatalogBuilder().build(
            .init(fixture: fixture, humanInputs: input.sets, revision: 1, generatedAt: generatedAt)
        )

        XCTAssertNoThrow(try PokemonCatalogCandidateValidator.validate(build))
        XCTAssertThrowsError(
            try PokemonCatalogCandidateValidator.validate(build, activeRevision: 1)
        ) { error in
            guard case let PokemonCatalogCandidateValidationError.revisionNotMonotonic(
                received,
                current
            ) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(received, 1)
            XCTAssertEqual(current, 1)
        }

        let mismatchedReport = PokemonCatalogReviewReport(
            revision: 2,
            generatedAt: build.report.generatedAt,
            addedProviderSetIDs: build.report.addedProviderSetIDs,
            changedProviderSetIDs: build.report.changedProviderSetIDs,
            excludedProviderSetIDs: build.report.excludedProviderSetIDs,
            sets: build.report.sets
        )
        let tampered = PokemonCatalogBuildResult(
            release: build.release,
            snapshot: build.snapshot,
            report: mismatchedReport
        )
        XCTAssertThrowsError(try PokemonCatalogCandidateValidator.validate(tampered)) { error in
            guard case let PokemonCatalogCandidateValidationError.mismatchedRevision(
                component,
                expected,
                received
            ) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(component, "report")
            XCTAssertEqual(expected, 1)
            XCTAssertEqual(received, 2)
        }
    }

    func testNewSetCannotBePublishedWithoutHumanPrintedCodeInput() throws {
        let fixture = try load(PokemonCatalogProviderFixture.self, named: "recorded-provider")
        let request = PokemonCatalogBuildRequest(
            fixture: fixture,
            humanInputs: [],
            revision: 1,
            generatedAt: generatedAt
        )

        XCTAssertThrowsError(try PokemonCatalogBuilder().build(request)) { error in
            guard case let PokemonCatalogBuildError.humanPrintedCodeRequired(id) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(id, "sv99")
        }
    }

    func testHumanClaimedDenominatorMustMatchProvider() throws {
        let fixture = try load(PokemonCatalogProviderFixture.self, named: "recorded-provider")
        let input = try load(PokemonCatalogHumanInputFile.self, named: "catalog-input")
        let wrongInput = PokemonCatalogHumanInput(
            providerSetID: "sv99",
            recognitionKind: .expansion,
            printedCode: "TST",
            claimedOfficialCount: 3,
            displayName: "Recorded Test Set",
            releaseOrder: 100,
            logoURL: "https://assets.tcgdex.net/en/sv99/logo",
            symbolURL: "https://assets.tcgdex.net/en/sv99/symbol"
        )
        let request = PokemonCatalogBuildRequest(
            fixture: fixture,
            humanInputs: [wrongInput],
            revision: 1,
            generatedAt: generatedAt
        )

        XCTAssertThrowsError(try PokemonCatalogBuilder().build(request)) { error in
            guard case let PokemonCatalogBuildError.officialCountMismatch(id, expected, received) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(id, "sv99")
            XCTAssertEqual(expected, 3)
            XCTAssertEqual(received, 2)
        }
        XCTAssertEqual(input.sets.count, 1)
    }

    func testReleaseValidatorRejectsOCRConfusableSameDenominator() throws {
        let descriptors = [
            descriptor(providerID: "sv99", code: "AB0", count: 100),
            descriptor(providerID: "sv100", code: "ABO", count: 100)
        ]
        let release = PokemonCatalogRelease(
            revision: 1,
            generatedAt: generatedAt,
            sets: descriptors
        )

        XCTAssertThrowsError(try PokemonCatalogReleaseValidator.validate(release)) { error in
            guard case let PokemonCatalogReleaseValidator.ValidationError.OCRConfusableCodeCollision(
                first,
                second,
                denominator
            ) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(Set([first, second]), Set(["AB0", "ABO"]))
            XCTAssertEqual(denominator, 100)
        }
    }

    func testSignatureRoundTripUsesExactSortedPayloadBytes() throws {
        let release = PokemonCatalogRelease(
            revision: 1,
            generatedAt: generatedAt,
            sets: [descriptor(providerID: "sv99", code: "TST", count: 2)]
        )
        let privateKey = Curve25519.Signing.PrivateKey()
        let envelope = try PokemonCatalogSignatureVerifier.sign(
            release: release,
            privateKey: privateKey,
            keyID: "fixture"
        )
        let decoded = try PokemonCatalogSignatureVerifier.verify(
            envelope: envelope,
            now: generatedAt.addingTimeInterval(1),
            keys: [.init(id: "fixture", publicKey: privateKey.publicKey)]
        )

        XCTAssertEqual(decoded, release)
        XCTAssertEqual(envelope.payload, PokemonCatalogBase64URL.encode(try PokemonCatalogJSON.encode(release)))
    }

    func testFilesystemPublisherWritesImmutableObjectsBeforeCurrentPointerAndAllowsHigherRevisionRollback() throws {
        let fixture = try load(PokemonCatalogProviderFixture.self, named: "recorded-provider")
        let input = try load(PokemonCatalogHumanInputFile.self, named: "catalog-input")
        let builder = PokemonCatalogBuilder()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PokemonCatalogCoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = Curve25519.Signing.PrivateKey()
        let material = PokemonCatalogSigningMaterial(keyID: "fixture", privateKey: key)

        let build1 = try builder.build(
            .init(fixture: fixture, humanInputs: input.sets, revision: 1, generatedAt: generatedAt)
        )
        let observedBeforePointer = root.appendingPathComponent("observed-before-pointer.txt")
        let currentURL = root.appendingPathComponent("v1/current.json")
        let publisher1 = PokemonCatalogFilesystemPublisher(
            root: root,
            environment: .production,
            beforePointerUpdate: {
                let state = FileManager.default.fileExists(atPath: currentURL.path) ? "present" : "absent"
                try Data(state.utf8).write(to: observedBeforePointer, options: .atomic)
            }
        )
        let receipt1 = try publisher1.publish(
            PokemonCatalogSigner.sign(build1, material: material)
        )
        XCTAssertEqual(receipt1.revision, 1)
        XCTAssertEqual(try String(contentsOf: observedBeforePointer), "absent")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("v1/releases/1/.complete").path
            )
        )
        XCTAssertEqual(
            Set(try FileManager.default.contentsOfDirectory(
                at: root.appendingPathComponent("v1/releases/1"),
                includingPropertiesForKeys: nil
            ).map(\.lastPathComponent)),
            Set([
                "catalog-release.json",
                "catalog-payload.json",
                "pokemon-catalog-snapshot.json",
                "review-report.json",
                ".complete"
            ])
        )

        let build2 = try builder.build(
            .init(
                fixture: fixture,
                activeRelease: build1.release,
                humanInputs: input.sets,
                revision: 2,
                generatedAt: generatedAt
            )
        )
        let observedCurrentAtRevision2 = root.appendingPathComponent("observed-revision-2.json")
        let publisher2 = PokemonCatalogFilesystemPublisher(
            root: root,
            environment: .production,
            beforePointerUpdate: {
                try Data(contentsOf: currentURL).write(to: observedCurrentAtRevision2, options: .atomic)
            }
        )
        _ = try publisher2.publish(PokemonCatalogSigner.sign(build2, material: material))
        let observedEnvelope = try PokemonCatalogJSON.decode(
            PokemonCatalogReleaseEnvelope.self,
            from: Data(contentsOf: observedCurrentAtRevision2)
        )
        let observedPayload = try XCTUnwrap(PokemonCatalogBase64URL.decode(observedEnvelope.payload))
        let observedRelease = try PokemonCatalogJSON.decode(
            PokemonCatalogRelease.self,
            from: observedPayload
        )
        XCTAssertEqual(observedRelease.revision, 1)

        let conflictingBuild = try builder.build(
            .init(
                fixture: fixture,
                activeRelease: build1.release,
                humanInputs: input.sets,
                revision: 2,
                generatedAt: generatedAt.addingTimeInterval(1)
            )
        )
        XCTAssertThrowsError(
            try publisher2.publish(PokemonCatalogSigner.sign(conflictingBuild, material: material))
        ) { error in
            guard case let PokemonCatalogPublicationError.immutableRevisionConflict(revision) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(revision, 2)
        }
        let currentAfterConflict = try XCTUnwrap(try publisher2.currentEnvelope())
        let currentAfterConflictPayload = try XCTUnwrap(
            PokemonCatalogBase64URL.decode(currentAfterConflict.payload)
        )
        let currentAfterConflictRelease = try PokemonCatalogJSON.decode(
            PokemonCatalogRelease.self,
            from: currentAfterConflictPayload
        )
        XCTAssertEqual(currentAfterConflictRelease.revision, 2)

        let rollback = try builder.build(
            .init(
                fixture: fixture,
                activeRelease: build2.release,
                humanInputs: input.sets,
                revision: 3,
                generatedAt: generatedAt
            )
        )
        let publisher3 = PokemonCatalogFilesystemPublisher(root: root, environment: .production)
        _ = try publisher3.publish(PokemonCatalogSigner.sign(rollback, material: material))
        let currentAfterRollback = try XCTUnwrap(try publisher3.currentEnvelope())
        let rollbackPayload = try XCTUnwrap(
            PokemonCatalogBase64URL.decode(currentAfterRollback.payload)
        )
        let rollbackRelease = try PokemonCatalogJSON.decode(
            PokemonCatalogRelease.self,
            from: rollbackPayload
        )
        XCTAssertEqual(rollbackRelease.revision, 3)
        XCTAssertEqual(rollbackRelease.sets, build1.release.sets)
    }

    func testFilesystemPublisherRejectsUnreadableCurrentPointer() throws {
        let fixture = try load(PokemonCatalogProviderFixture.self, named: "recorded-provider")
        let input = try load(PokemonCatalogHumanInputFile.self, named: "catalog-input")
        let build = try PokemonCatalogBuilder().build(
            .init(fixture: fixture, humanInputs: input.sets, revision: 1, generatedAt: generatedAt)
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PokemonCatalogCoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let currentURL = root.appendingPathComponent("v1/current.json")
        try FileManager.default.createDirectory(
            at: currentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: currentURL)

        let key = Curve25519.Signing.PrivateKey()
        let signed = try PokemonCatalogSigner.sign(
            build,
            material: .init(keyID: "fixture", privateKey: key)
        )
        XCTAssertThrowsError(
            try PokemonCatalogFilesystemPublisher(
                root: root,
                environment: .production
            ).publish(signed)
        ) { error in
            guard case PokemonCatalogPublicationError.invalidCurrentPointer = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testSigningRequiresMatchingProtectedEnvironmentAndMainPublicationContext() throws {
        let key = Curve25519.Signing.PrivateKey()
        let validSecret = PokemonCatalogBase64URL.encode(key.rawRepresentation)
        let base: [String: String] = [
            "GITHUB_ACTIONS": "true",
            "GITHUB_EVENT_NAME": "workflow_dispatch",
            "GITHUB_REF": "refs/heads/main",
            "POKEMON_CATALOG_PUBLISH": "true",
            "POKEMON_CATALOG_SIGNING_KEY": validSecret,
            "POKEMON_CATALOG_KEY_ID": "fixture"
        ]

        for (label, encodedSecret) in [
            ("base64url", validSecret),
            ("base64", key.rawRepresentation.base64EncodedString()),
            ("hex", key.rawRepresentation.map { String(format: "%02x", $0) }.joined())
        ] {
            var staging = base
            staging["GITHUB_ENVIRONMENT"] = "pokemon-catalog-staging"
            staging["POKEMON_CATALOG_SIGNING_KEY"] = encodedSecret
            let stagingMaterial = try PokemonCatalogSigningKeyLoader.load(
                environment: .staging,
                variables: staging
            )
            XCTAssertEqual(stagingMaterial.keyID, "fixture", label)
            XCTAssertEqual(
                stagingMaterial.privateKey.publicKey.rawRepresentation,
                key.publicKey.rawRepresentation,
                label
            )
        }

        var pem = base
        pem["GITHUB_ENVIRONMENT"] = "pokemon-catalog-staging"
        pem["POKEMON_CATALOG_SIGNING_KEY"] = "-----BEGIN PRIVATE KEY-----\n\(validSecret)\n-----END PRIVATE KEY-----"
        XCTAssertThrowsError(
            try PokemonCatalogSigningKeyLoader.load(environment: .staging, variables: pem)
        )

        var production = base
        production["GITHUB_ENVIRONMENT"] = "pokemon-catalog-production"
        XCTAssertNoThrow(
            try PokemonCatalogSigningKeyLoader.load(
                environment: .production,
                variables: production
            )
        )

        for (environment, environmentName) in [
            (PokemonCatalogPublicationEnvironment.production, "pokemon-catalog-staging"),
            (.staging, "pokemon-catalog-production")
        ] {
            var wrongEnvironment = base
            wrongEnvironment["GITHUB_ENVIRONMENT"] = environmentName
            XCTAssertThrowsError(
                try PokemonCatalogSigningKeyLoader.load(
                    environment: environment,
                    variables: wrongEnvironment
                )
            ) { error in
                guard case PokemonCatalogPublicationError.invalidSigningEnvironment = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }

        var local = base
        local.removeValue(forKey: "GITHUB_ACTIONS")
        XCTAssertThrowsError(
            try PokemonCatalogSigningKeyLoader.load(environment: .production, variables: local)
        ) { error in
            guard case PokemonCatalogPublicationError.invalidSigningEnvironment = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        var pullRequest = base
        pullRequest["GITHUB_ACTIONS"] = "true"
        pullRequest["GITHUB_EVENT_NAME"] = "pull_request"
        pullRequest["GITHUB_ENVIRONMENT"] = "pokemon-catalog-production"
        XCTAssertThrowsError(
            try PokemonCatalogSigningKeyLoader.load(environment: .production, variables: pullRequest)
        ) { error in
            guard case PokemonCatalogPublicationError.invalidSigningEnvironment = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        var nonMain = production
        nonMain["GITHUB_REF"] = "refs/heads/feature/catalog"
        XCTAssertThrowsError(
            try PokemonCatalogSigningKeyLoader.load(environment: .production, variables: nonMain)
        ) { error in
            guard case PokemonCatalogPublicationError.invalidSigningEnvironment = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        var unpublished = production
        unpublished["POKEMON_CATALOG_PUBLISH"] = "false"
        XCTAssertThrowsError(
            try PokemonCatalogSigningKeyLoader.load(environment: .production, variables: unpublished)
        ) { error in
            guard case PokemonCatalogPublicationError.invalidSigningEnvironment = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testPublicationEnvironmentPathsAreTheSingleNamespaceSource() {
        XCTAssertEqual(PokemonCatalogPublicationEnvironment.production.path, "v1")
        XCTAssertEqual(PokemonCatalogPublicationEnvironment.staging.path, "staging/v1")
    }

    func testMembershipRowsBindByProviderCardIDAndNotProviderLocalID() throws {
        let directory = [
            PokemonCatalogProviderDirectoryRow(
                id: "future-c",
                name: "Future Classic Collection",
                cardCount: .init(total: 2, official: 2)
            )
        ]
        let briefs = [
            PokemonCatalogProviderCardBrief(
                id: "future-c-001",
                localID: "011",
                name: "Crobat G"
            ),
            PokemonCatalogProviderCardBrief(
                id: "future-c-002",
                localID: "012",
                name: "Charizard"
            )
        ]
        let providerSet = PokemonCatalogProviderSet(
            id: "future-c",
            name: "Future Classic Collection",
            cards: briefs,
            cardCount: .init(total: 2, official: 2)
        )
        let details = briefs.map {
            PokemonCatalogProviderCard(
                id: $0.id,
                localID: $0.localID,
                name: $0.name,
                setID: "future-c"
            )
        }
        let membership = PokemonCatalogMembershipRecognition(members: [
            .init(
                providerCardID: "future-c-001",
                canonicalName: "crobat g",
                printedLocalID: "47",
                printedDenominator: 127
            ),
            .init(
                providerCardID: "future-c-002",
                canonicalName: "charizard",
                printedLocalID: "4",
                printedDenominator: 102
            )
        ])
        let input = PokemonCatalogHumanInput(
            providerSetID: "future-c",
            recognitionKind: .expansion,
            printedCode: "FTR",
            claimedOfficialCount: 2,
            displayName: "Future Classic Collection",
            membershipRecognition: membership
        )
        let fixture = PokemonCatalogProviderFixture(
            directory: directory,
            sets: [providerSet],
            cards: details
        )

        let result = try PokemonCatalogBuilder().build(
            .init(fixture: fixture, humanInputs: [input], revision: 1, generatedAt: generatedAt)
        )
        let descriptor = try XCTUnwrap(result.release.sets.first)
        XCTAssertEqual(descriptor.membershipRecognition?.members.count, 2)
        XCTAssertEqual(
            descriptor.membershipRecognition?.members.first?.providerCardID,
            "future-c-001"
        )
        XCTAssertEqual(
            descriptor.membershipRecognition?.members.first?.printedLocalID,
            "47"
        )
    }

    func testMembershipRowsRequireCompleteProviderChecklistCoverage() throws {
        let providerCard = PokemonCatalogProviderCard(
            id: "future-c-001",
            localID: "011",
            name: "Crobat G",
            setID: "future-c"
        )
        let fixture = PokemonCatalogProviderFixture(
            directory: [
                .init(
                    id: "future-c",
                    name: "Future Classic Collection",
                    cardCount: .init(total: 1, official: 1)
                )
            ],
            sets: [
                .init(
                    id: "future-c",
                    name: "Future Classic Collection",
                    cards: [
                        .init(id: providerCard.id, localID: providerCard.localID, name: providerCard.name)
                    ],
                    cardCount: .init(total: 1, official: 1)
                )
            ],
            cards: [providerCard]
        )
        let input = PokemonCatalogHumanInput(
            providerSetID: "future-c",
            recognitionKind: .notScannable,
            scanEnabled: false,
            membershipRecognition: .init(members: [
                .init(
                    providerCardID: "missing-card",
                    canonicalName: "Crobat G",
                    printedLocalID: "47",
                    printedDenominator: 127
                )
            ])
        )

        XCTAssertThrowsError(
            try PokemonCatalogBuilder().build(
                .init(fixture: fixture, humanInputs: [input], revision: 1, generatedAt: generatedAt)
            )
        ) { error in
            guard case let PokemonCatalogBuildError.membershipProviderCardMissing(setID, cardID) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(setID, "future-c")
            XCTAssertEqual(cardID, "missing-card")
        }
    }

    func testMembershipPhysicalIdentityPairsMustBeUnique() throws {
        let descriptor = PokemonCatalogSetDescriptor(
            providerSetID: "future-c",
            displayName: "Future Classic Collection",
            releaseDate: nil,
            releaseOrder: nil,
            recognitionKind: .notScannable,
            printedCode: nil,
            officialCount: nil,
            printedPrefix: nil,
            catalogLocalIDPrefix: nil,
            localIDPadWidth: nil,
            scanEnabled: false,
            logoURL: nil,
            symbolURL: nil,
            membershipRecognition: .init(members: [
                .init(
                    providerCardID: "future-c-001",
                    canonicalName: "crobat g",
                    printedLocalID: "47",
                    printedDenominator: 127
                ),
                .init(
                    providerCardID: "future-c-002",
                    canonicalName: "Crobat G",
                    printedLocalID: "047",
                    printedDenominator: 127
                )
            ])
        )
        let release = PokemonCatalogRelease(
            revision: 1,
            generatedAt: generatedAt,
            sets: [descriptor]
        )

        XCTAssertThrowsError(try PokemonCatalogReleaseValidator.validate(release)) { error in
            guard case let PokemonCatalogReleaseValidator.ValidationError.invalidDescriptor(reason) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(reason.contains("unique canonical name"))
        }
    }

    func testOldDescriptorPayloadDecodesWithoutMembershipRecognition() throws {
        let data = Data(
            """
            {
              "providerSetID":"sv99",
              "displayName":"Recorded Test Set",
              "releaseDate":"2026-01-01",
              "releaseOrder":1,
              "recognitionKind":"expansion",
              "printedCode":"TST",
              "officialCount":2,
              "printedPrefix":null,
              "catalogLocalIDPrefix":null,
              "localIDPadWidth":null,
              "scanEnabled":true,
              "logoURL":null,
              "symbolURL":null,
              "rulesVersion":1
            }
            """.utf8
        )
        let descriptor = try PokemonCatalogJSON.decode(
            PokemonCatalogSetDescriptor.self,
            from: data
        )
        XCTAssertNil(descriptor.membershipRecognition)
    }

    private func load<T: Decodable>(_ type: T.Type, named name: String) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try PokemonCatalogJSON.decode(type, from: Data(contentsOf: url))
    }

    private struct ProviderSetSpec {
        let id: String
        let name: String
        let code: String?
        let releaseDate: String
        let imageURLs: [String]
        let logo: String?

        init(
            id: String,
            name: String,
            code: String?,
            releaseDate: String,
            imageURLs: [String],
            logo: String? = nil
        ) {
            self.id = id
            self.name = name
            self.code = code
            self.releaseDate = releaseDate
            self.imageURLs = imageURLs
            self.logo = logo
        }
    }

    private func providerFixture(
        sets specs: [ProviderSetSpec]
    ) -> PokemonCatalogProviderFixture {
        var rows: [PokemonCatalogProviderDirectoryRow] = []
        var providerSets: [PokemonCatalogProviderSet] = []
        var cards: [PokemonCatalogProviderCard] = []

        for spec in specs {
            let count = PokemonCatalogProviderCardCount(
                total: spec.imageURLs.count,
                official: spec.imageURLs.count,
                normal: spec.imageURLs.count,
                reverse: 0,
                holo: 0,
                firstEd: 0
            )
            let briefs = spec.imageURLs.enumerated().map { index, imageURL in
                let localID = String(format: "%03d", index + 1)
                let cardID = "\(spec.id)-\(localID)"
                return PokemonCatalogProviderCardBrief(
                    id: cardID,
                    localID: localID,
                    name: "Card \(localID)",
                    image: imageURL
                )
            }
            rows.append(
                PokemonCatalogProviderDirectoryRow(
                    id: spec.id,
                    name: spec.name,
                    cardCount: count,
                    releaseDate: spec.releaseDate
                )
            )
            providerSets.append(
                PokemonCatalogProviderSet(
                    id: spec.id,
                    name: spec.name,
                    cards: briefs,
                    logo: spec.logo,
                    releaseDate: spec.releaseDate,
                    cardCount: count,
                    serie: .init(id: "sv"),
                    abbreviation: spec.code.map { .init(official: $0) }
                )
            )
            cards += briefs.map { brief in
                PokemonCatalogProviderCard(
                    id: brief.id,
                    localID: brief.localID,
                    name: brief.name,
                    image: brief.image,
                    setID: spec.id
                )
            }
        }

        return PokemonCatalogProviderFixture(
            directory: rows,
            sets: providerSets,
            cards: cards
        )
    }

    private func descriptor(
        providerID: String,
        code: String,
        count: Int
    ) -> PokemonCatalogSetDescriptor {
        PokemonCatalogSetDescriptor(
            providerSetID: providerID,
            displayName: providerID,
            releaseDate: "2026-01-01",
            releaseOrder: 1,
            recognitionKind: .expansion,
            printedCode: code,
            officialCount: count,
            printedPrefix: nil,
            catalogLocalIDPrefix: nil,
            localIDPadWidth: nil,
            scanEnabled: true,
            logoURL: nil,
            symbolURL: nil
        )
    }
}
