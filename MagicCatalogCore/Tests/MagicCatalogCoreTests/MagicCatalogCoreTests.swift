import CryptoKit
import Foundation
import XCTest
@testable import MagicCatalogCore

final class MagicCatalogCoreTests: XCTestCase {
    private func fixture() throws -> MagicCatalogProviderFixture {
        let url = Bundle.module.url(
            forResource: "recorded-provider",
            withExtension: "json"
        )!
        return try MagicCatalogJSON.decode(
            MagicCatalogProviderFixture.self,
            from: Data(contentsOf: url)
        )
    }

    private func build(
        fixture: MagicCatalogProviderFixture? = nil,
        active: MagicCatalogRelease? = nil,
        generatedAt: String = "2026-01-01T00:00:00.000Z",
        revision: Int = 1
    ) throws -> MagicCatalogBuildResult {
        try MagicCatalogBuilder().build(
            MagicCatalogBuildRequest(
                fixture: fixture ?? self.fixture(),
                activeRelease: active,
                revision: revision,
                generatedAt: generatedAt
            )
        )
    }

    private func baseDescriptor(
        scryfallSetID: String = "00000000-0000-4000-8000-000000000001",
        code: String = "ABC",
        displayName: String = "Recorded Expansion",
        releaseDate: String? = "2020-01-01",
        setType: String = "expansion",
        printedSize: Int? = 100,
        cardCount: Int? = 100,
        iconSVGURL: URL? = URL(string: "https://svgs.scryfall.io/sets/abc.svg"),
        parentSetCode: String? = nil,
        routingKind: MagicCatalogRoutingKind? = nil,
        scanEnabled: Bool = true,
        browseEnabled: Bool = true
    ) -> MagicCatalogSetDescriptor {
        MagicCatalogSetDescriptor(
            scryfallSetID: scryfallSetID,
            code: code,
            displayName: displayName,
            releaseDate: releaseDate,
            setType: setType,
            printedSize: printedSize,
            cardCount: cardCount,
            iconSVGURL: iconSVGURL,
            parentSetCode: parentSetCode,
            routingKind: routingKind,
            scanEnabled: scanEnabled,
            browseEnabled: browseEnabled
        )
    }

    private func release(
        descriptors: [MagicCatalogSetDescriptor],
        revision: Int = 1,
        generatedAt: String = "2026-01-01T00:00:00.000Z"
    ) -> MagicCatalogRelease {
        MagicCatalogRelease(
            revision: revision,
            generatedAt: generatedAt,
            sets: descriptors
        )
    }

    private func tamperedReport(
        _ report: MagicCatalogReviewReport,
        revision: Int? = nil,
        generatedAt: String? = nil,
        descriptorCount: Int? = nil,
        changeClass: MagicCatalogChangeClass? = nil,
        addedCodes: [String]? = nil,
        changedCodes: [String]? = nil,
        contentChangedCodes: [String]? = nil,
        authorityChangedCodes: [String]? = nil,
        removedCodes: [String]? = nil,
        scannerProjectionChangedCodes: [String]? = nil,
        browseProjectionChangedCodes: [String]? = nil,
        routingProjectionChangedCodes: [String]? = nil
    ) -> MagicCatalogReviewReport {
        MagicCatalogReviewReport(
            revision: revision ?? report.revision,
            generatedAt: generatedAt ?? report.generatedAt,
            descriptorCount: descriptorCount ?? report.descriptorCount,
            changeClass: changeClass ?? report.changeClass,
            addedCodes: addedCodes ?? report.addedCodes,
            changedCodes: changedCodes ?? report.changedCodes,
            contentChangedCodes: contentChangedCodes ?? report.contentChangedCodes,
            authorityChangedCodes: authorityChangedCodes ?? report.authorityChangedCodes,
            removedCodes: removedCodes ?? report.removedCodes,
            scannerProjectionChangedCodes: scannerProjectionChangedCodes
                ?? report.scannerProjectionChangedCodes,
            browseProjectionChangedCodes: browseProjectionChangedCodes
                ?? report.browseProjectionChangedCodes,
            routingProjectionChangedCodes: routingProjectionChangedCodes
                ?? report.routingProjectionChangedCodes,
            warnings: report.warnings
        )
    }

    func testThreePoliciesProduceIndependentProjections() throws {
        let result = try build()
        let byCode = Dictionary(result.release.sets.map { ($0.code, $0) }) { first, _ in first }

        XCTAssertEqual(byCode["ABC"]?.scanEnabled, true)
        XCTAssertEqual(byCode["ABC"]?.browseEnabled, true)
        XCTAssertEqual(byCode["OLD"]?.scanEnabled, false)
        XCTAssertEqual(byCode["OLD"]?.browseEnabled, true)
        XCTAssertEqual(byCode["TABC"]?.routingKind, .token)
        XCTAssertEqual(byCode["AABC"]?.routingKind, .artCard)
        XCTAssertEqual(byCode["TABC"]?.browseEnabled, false)
        XCTAssertEqual(byCode["TABC"]?.scanEnabled, false)
        XCTAssertNil(byCode["DGT"])
        XCTAssertEqual(result.report.scannerProjectionChangedCodes, ["ABC"])
        XCTAssertEqual(result.report.browseProjectionChangedCodes, ["ABC", "OLD"])
        XCTAssertEqual(result.report.routingProjectionChangedCodes, ["AABC", "TABC"])
    }

    func testIconSVGURLValidationRequiresApprovedHTTPSOrigin() throws {
        let validRelease = release(descriptors: [baseDescriptor()])
        XCTAssertNoThrow(try MagicCatalogReleaseValidator.validate(validRelease))

        // The shape the provider actually publishes. Every icon URL in the
        // bundled seed carries a cache-buster, so this is the common case, not
        // an edge case.
        let cacheBusted = release(descriptors: [
            baseDescriptor(
                iconSVGURL: try XCTUnwrap(URL(string: "https://svgs.scryfall.io/sets/abc.svg?1789358400"))
            )
        ])
        XCTAssertNoThrow(try MagicCatalogReleaseValidator.validate(cacheBusted))

        let invalidURLs = [
            "http://svgs.scryfall.io/sets/abc.svg",
            "https://assets.scryfall.io/sets/abc.svg",
            "https://evil-svgs.scryfall.io/sets/abc.svg",
            "https://user@svgs.scryfall.io/sets/abc.svg",
            "https://user:password@svgs.scryfall.io/sets/abc.svg",
            "https://svgs.scryfall.io:443/sets/abc.svg",
            "https://svgs.scryfall.io/sets/abc.svg#fragment"
        ]
        for rawURL in invalidURLs {
            let descriptor = baseDescriptor(iconSVGURL: try XCTUnwrap(URL(string: rawURL)))
            XCTAssertThrowsError(
                try MagicCatalogReleaseValidator.validate(
                    release(descriptors: [descriptor])
                ),
                "Expected icon URL to be rejected: \(rawURL)"
            ) { error in
                guard case .invalidIconSVGURL = error as? MagicCatalogReleaseValidator.ValidationError else {
                    return XCTFail("Unexpected error for \(rawURL): \(error)")
                }
            }
        }
    }

    func testMagicClassifierUsesExplicitAutomaticAllowList() {
        let previous = baseDescriptor()
        let contentChanges: [(String, MagicCatalogSetDescriptor)] = [
            ("displayName", baseDescriptor(displayName: "Renamed Expansion")),
            ("releaseDate", baseDescriptor(releaseDate: "2020-01-02")),
            ("cardCount", baseDescriptor(cardCount: 101)),
            (
                "iconSVGURL",
                baseDescriptor(
                    iconSVGURL: URL(string: "https://svgs.scryfall.io/sets/renamed.svg")
                )
            )
        ]
        for (field, current) in contentChanges {
            XCTAssertEqual(
                MagicCatalogChangeClassifier.classify(previous: previous, current: current),
                .contentOnly,
                "Expected \(field) to remain content-only"
            )
        }

        let authorityChanges: [(String, MagicCatalogSetDescriptor)] = [
            (
                "scryfallSetID",
                baseDescriptor(scryfallSetID: "00000000-0000-4000-8000-000000000099")
            ),
            ("code", baseDescriptor(code: "ABD")),
            ("setType", baseDescriptor(setType: "core")),
            ("printedSize", baseDescriptor(printedSize: 101)),
            ("parentSetCode", baseDescriptor(parentSetCode: "XYZ")),
            ("routingKind", baseDescriptor(routingKind: .token)),
            ("scanEnabled", baseDescriptor(scanEnabled: false)),
            ("browseEnabled", baseDescriptor(browseEnabled: false))
        ]
        for (field, current) in authorityChanges {
            XCTAssertEqual(
                MagicCatalogChangeClassifier.classify(previous: previous, current: current),
                .authority,
                "Expected \(field) to require protected authority"
            )
        }
    }

    func testMagicCardCountIsContentOnlyButPrintedSizeIsAuthority() {
        let previous = baseDescriptor()
        XCTAssertEqual(
            MagicCatalogChangeClassifier.classify(
                previous: previous,
                current: baseDescriptor(cardCount: 101)
            ),
            .contentOnly
        )
        XCTAssertEqual(
            MagicCatalogChangeClassifier.classify(
                previous: previous,
                current: baseDescriptor(printedSize: 101)
            ),
            .authority
        )
    }

    func testReleaseClassificationPrecedenceAndContentInvariant() throws {
        let first = try build().release
        let source = try fixture()

        let identical = MagicCatalogChangeClassifier.classify(
            previousRelease: first,
            currentRelease: first
        )
        XCTAssertEqual(identical.changeClass, .none)

        let renamedSource = MagicCatalogProviderFixture(sets: source.sets.map { row in
            guard row.code == "ABC" else { return row }
            return MagicCatalogProviderSet(
                id: row.id,
                code: row.code,
                name: "Renamed Expansion",
                releasedAt: "2020-01-02",
                setType: row.setType,
                cardCount: 101,
                printedSize: row.printedSize,
                iconSVGURL: URL(string: "https://svgs.scryfall.io/sets/renamed.svg"),
                parentSetCode: row.parentSetCode,
                digital: row.digital
            )
        })
        let contentResult = try build(
            fixture: renamedSource,
            active: first,
            revision: 2
        )
        XCTAssertEqual(contentResult.report.changeClass, .contentOnly)
        XCTAssertEqual(contentResult.report.contentChangedCodes, ["ABC"])

        let authoritySource = MagicCatalogProviderFixture(sets: source.sets.map { row in
            guard row.code == "ABC" else { return row }
            return MagicCatalogProviderSet(
                id: row.id,
                code: row.code,
                name: row.name,
                releasedAt: row.releasedAt,
                setType: "core",
                cardCount: row.cardCount,
                printedSize: row.printedSize,
                iconSVGURL: row.iconSVGURL,
                parentSetCode: row.parentSetCode,
                digital: row.digital
            )
        })
        let contentAndAuthority = try build(
            fixture: authoritySource,
            active: first,
            revision: 2
        )
        XCTAssertEqual(contentAndAuthority.report.changeClass, .authority)
        XCTAssertEqual(contentAndAuthority.report.authorityChangedCodes, ["ABC"])

        let added = MagicCatalogProviderSet(
            id: "00000000-0000-4000-8000-000000000099",
            code: "NEW",
            name: "New Expansion",
            releasedAt: "2026-01-01",
            setType: "expansion",
            cardCount: 10,
            printedSize: 10,
            iconSVGURL: URL(string: "https://svgs.scryfall.io/sets/new.svg")
        )
        let newSetResult = try build(
            fixture: MagicCatalogProviderFixture(sets: source.sets + [added]),
            active: first,
            revision: 2
        )
        XCTAssertEqual(newSetResult.report.changeClass, .newSet)
        XCTAssertEqual(newSetResult.report.addedCodes, ["NEW"])

        let newSetAndAuthority = try build(
            fixture: MagicCatalogProviderFixture(
                sets: authoritySource.sets + [added]
            ),
            active: first,
            revision: 2
        )
        XCTAssertEqual(newSetAndAuthority.report.changeClass, .newSet)

        let removalSource = MagicCatalogProviderFixture(
            sets: source.sets.filter { $0.code != "OLD" }
        )
        let authorizedRemoval = try MagicCatalogBuilder().build(
            MagicCatalogBuildRequest(
                fixture: removalSource,
                activeRelease: first,
                revision: 2,
                generatedAt: "2026-01-01T00:00:00.000Z",
                authorizedRemovalCodes: ["OLD"]
            )
        )
        XCTAssertEqual(authorizedRemoval.report.changeClass, .authority)
        XCTAssertEqual(authorizedRemoval.report.removedCodes, ["OLD"])

        let expectedContentDiff = MagicCatalogChangeClassifier.surfaceDiff(
            previousRelease: first,
            currentRelease: contentResult.release
        )
        let mismatchedSurface = MagicCatalogSurfaceDiff(
            addedCodes: expectedContentDiff.addedCodes,
            changedCodes: expectedContentDiff.changedCodes,
            removedCodes: expectedContentDiff.removedCodes,
            scannerProjectionChangedCodes: ["ABC"],
            browseProjectionChangedCodes: expectedContentDiff.browseProjectionChangedCodes,
            routingProjectionChangedCodes: expectedContentDiff.routingProjectionChangedCodes
        )
        let unknown = MagicCatalogChangeClassifier.classify(
            previousRelease: first,
            currentRelease: contentResult.release,
            surfaceDiff: mismatchedSurface
        )
        XCTAssertEqual(unknown.changeClass, .unknown)
        XCTAssertEqual(unknown.contentChangedCodes, [])
        XCTAssertTrue(unknown.authorityChangedCodes.contains("ABC"))
    }

    func testSurfaceInvariantRejectsScannerRoutingAndBrowseMismatches() throws {
        let first = try build().release
        let source = try fixture()
        let changed = try build(
            fixture: MagicCatalogProviderFixture(sets: source.sets.map { row in
                guard row.code == "ABC" else { return row }
                return MagicCatalogProviderSet(
                    id: row.id,
                    code: row.code,
                    name: "Renamed",
                    releasedAt: row.releasedAt,
                    setType: row.setType,
                    cardCount: row.cardCount,
                    printedSize: row.printedSize,
                    iconSVGURL: row.iconSVGURL,
                    parentSetCode: row.parentSetCode,
                    digital: row.digital
                )
            }),
            active: first,
            revision: 2
        ).release
        let expected = MagicCatalogChangeClassifier.surfaceDiff(
            previousRelease: first,
            currentRelease: changed
        )
        let variants = [
            MagicCatalogSurfaceDiff(
                addedCodes: expected.addedCodes,
                changedCodes: expected.changedCodes,
                removedCodes: expected.removedCodes,
                scannerProjectionChangedCodes: ["ABC"],
                browseProjectionChangedCodes: expected.browseProjectionChangedCodes,
                routingProjectionChangedCodes: expected.routingProjectionChangedCodes
            ),
            MagicCatalogSurfaceDiff(
                addedCodes: expected.addedCodes,
                changedCodes: expected.changedCodes,
                removedCodes: expected.removedCodes,
                scannerProjectionChangedCodes: expected.scannerProjectionChangedCodes,
                browseProjectionChangedCodes: expected.browseProjectionChangedCodes,
                routingProjectionChangedCodes: ["ABC"]
            ),
            MagicCatalogSurfaceDiff(
                addedCodes: expected.addedCodes,
                changedCodes: expected.changedCodes,
                removedCodes: expected.removedCodes,
                scannerProjectionChangedCodes: expected.scannerProjectionChangedCodes,
                browseProjectionChangedCodes: [],
                routingProjectionChangedCodes: expected.routingProjectionChangedCodes
            )
        ]
        for surfaceDiff in variants {
            let classification = MagicCatalogChangeClassifier.classify(
                previousRelease: first,
                currentRelease: changed,
                surfaceDiff: surfaceDiff
            )
            XCTAssertEqual(classification.changeClass, .unknown)
        }
    }

    func testProviderIdentityRejectsDuplicateCodeAndUUID() throws {
        let source = try fixture()
        let duplicateCode = MagicCatalogProviderSet(
            id: "00000000-0000-4000-8000-000000000099",
            code: "abc",
            name: "Collision",
            releasedAt: "2020-01-01",
            setType: "expansion"
        )
        XCTAssertThrowsError(try build(fixture: .init(sets: source.sets + [duplicateCode]))) { error in
            guard case .providerCodeMapsToMultipleUUIDs = error as? MagicCatalogBuilderError else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        let duplicateUUID = MagicCatalogProviderSet(
            id: source.sets[0].id,
            code: "ZZZ",
            name: "Collision",
            releasedAt: "2020-01-01",
            setType: "expansion"
        )
        XCTAssertThrowsError(try build(fixture: .init(sets: source.sets + [duplicateUUID]))) { error in
            guard case .providerUUIDMapsToMultipleCodes = error as? MagicCatalogBuilderError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testReleasedPrintedSizeDriftFailsClosedButFutureDriftIsAllowed() throws {
        let first = try build().release
        let source = try fixture()
        let changedRows = source.sets.map { row in
            row.code == "ABC"
                ? MagicCatalogProviderSet(
                    id: row.id,
                    code: row.code,
                    name: row.name,
                    releasedAt: row.releasedAt,
                    setType: row.setType,
                    cardCount: row.cardCount,
                    printedSize: 101,
                    iconSVGURL: row.iconSVGURL,
                    parentSetCode: row.parentSetCode,
                    digital: row.digital
                )
                : row
        }
        XCTAssertThrowsError(try build(fixture: .init(sets: changedRows), active: first, revision: 2)) { error in
            guard case .printedSizeDrift(let code, let activeSize, let candidateSize) = error as? MagicCatalogBuilderError else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(code, "ABC")
            XCTAssertEqual(activeSize, 100)
            XCTAssertEqual(candidateSize, 101)
        }

        let futureSource = MagicCatalogProviderFixture(sets: source.sets.map { row in
            row.code == "ABC"
                ? MagicCatalogProviderSet(
                    id: row.id,
                    code: row.code,
                    name: row.name,
                    releasedAt: "2030-01-01",
                    setType: row.setType,
                    cardCount: row.cardCount,
                    printedSize: 101,
                    iconSVGURL: row.iconSVGURL,
                    parentSetCode: row.parentSetCode,
                    digital: row.digital
                )
                : row
        })
        let futureActiveSource = MagicCatalogProviderFixture(sets: source.sets.map { row in
            row.code == "ABC"
                ? MagicCatalogProviderSet(
                    id: row.id,
                    code: row.code,
                    name: row.name,
                    releasedAt: "2030-01-01",
                    setType: row.setType,
                    cardCount: row.cardCount,
                    printedSize: row.printedSize,
                    iconSVGURL: row.iconSVGURL,
                    parentSetCode: row.parentSetCode,
                    digital: row.digital
                )
                : row
        })
        let futureActive = try build(fixture: futureActiveSource, generatedAt: "2026-01-01T00:00:00.000Z").release
        let futureResult = try build(
            fixture: futureSource,
            active: futureActive,
            generatedAt: "2026-01-02T00:00:00.000Z",
            revision: 2
        )
        XCTAssertTrue(
            futureResult.report.warnings.contains {
                $0.contains("Future Magic set ABC printedSize changed")
            }
        )
    }

    func testRoutingInvariantsAndParentIdentityAreValidated() throws {
        let source = try fixture()
        let badChild = MagicCatalogProviderFixture(sets: source.sets.map { row in
            row.code == "TABC"
                ? MagicCatalogProviderSet(
                    id: row.id,
                    code: row.code,
                    name: row.name,
                    releasedAt: row.releasedAt,
                    setType: row.setType,
                    cardCount: row.cardCount,
                    printedSize: row.printedSize,
                    iconSVGURL: row.iconSVGURL,
                    parentSetCode: "MISSING",
                    digital: row.digital
                )
                : row
        })
        XCTAssertThrowsError(try build(fixture: badChild)) { error in
            XCTAssertEqual(
                error as? MagicCatalogReleaseValidator.ValidationError,
                .routingChildMissingParent("TABC")
            )
        }
    }

    func testSignatureRequiresMagicCatalogKind() throws {
        let key = Curve25519.Signing.PrivateKey()
        let release = try build().release
        let envelope = try MagicCatalogSignatureVerifier.sign(
            release: release,
            privateKey: key,
            keyID: "test"
        )
        XCTAssertNoThrow(try MagicCatalogSignatureVerifier.verify(
            envelope: envelope,
            keys: [.init(id: "test", publicKey: key.publicKey)]
        ))

        let wrongKind = MagicCatalogRelease(
            schemaVersion: 1,
            catalogKind: "pokemon",
            revision: release.revision,
            generatedAt: release.generatedAt,
            sets: release.sets
        )
        let wrongEnvelope = try MagicCatalogSignatureVerifier.sign(
            release: wrongKind,
            privateKey: key,
            keyID: "test"
        )
        XCTAssertThrowsError(try MagicCatalogSignatureVerifier.verify(
            envelope: wrongEnvelope,
            keys: [.init(id: "test", publicKey: key.publicKey)]
        )) { error in
            XCTAssertEqual(error as? MagicCatalogSignatureError, .wrongCatalogKind("pokemon"))
        }
    }

    func testSigningKeyLoaderRequiresProtectedGitHubPublicationContext() throws {
        let key = Curve25519.Signing.PrivateKey()
        let valid: [String: String] = [
            "GITHUB_ACTIONS": "true",
            "GITHUB_EVENT_NAME": "workflow_dispatch",
            "GITHUB_REF": "refs/heads/main",
            "MAGIC_CATALOG_PUBLISH": "true",
            "GITHUB_ENVIRONMENT": "magic-catalog-production",
            "MAGIC_CATALOG_SIGNING_KEY": MagicCatalogBase64URL.encode(key.rawRepresentation),
            "MAGIC_CATALOG_KEY_ID": "test-key"
        ]

        let material = try MagicCatalogSigningKeyLoader.load(
            environment: .production,
            variables: valid,
            changeClass: .authority
        )
        XCTAssertEqual(material.keyID, "test-key")

        for (name, value) in [
            ("GITHUB_ACTIONS", "false"),
            ("GITHUB_EVENT_NAME", "pull_request"),
            ("GITHUB_REF", "refs/heads/feature"),
            ("MAGIC_CATALOG_PUBLISH", "false")
        ] {
            var blocked = valid
            blocked[name] = value
            XCTAssertThrowsError(
                try MagicCatalogSigningKeyLoader.load(
                    environment: .production,
                    variables: blocked,
                    changeClass: .authority
                ),
                "Expected signing to be blocked for invalid publication context"
            ) { error in
                guard case MagicCatalogSigningKeyLoader.Error.notProtectedEnvironment = error else {
                    return XCTFail("Unexpected error")
                }
            }
        }

        var wrongEnvironment = valid
        wrongEnvironment["GITHUB_ENVIRONMENT"] = "pokemon-catalog-production"
        XCTAssertThrowsError(
            try MagicCatalogSigningKeyLoader.load(
                environment: .production,
                variables: wrongEnvironment,
                changeClass: .authority
            )
        ) { error in
            guard case MagicCatalogSigningKeyLoader.Error.notProtectedEnvironment = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        var automatic = valid
        automatic["GITHUB_ENVIRONMENT"] = "magic-catalog-production-auto"
        XCTAssertNoThrow(
            try MagicCatalogSigningKeyLoader.load(
                environment: .production,
                variables: automatic,
                changeClass: .contentOnly
            )
        )
        for changeClass in [
            MagicCatalogChangeClass.none,
            .authority,
            .newSet,
            .unknown
        ] {
            XCTAssertThrowsError(
                try MagicCatalogSigningKeyLoader.load(
                    environment: .production,
                    variables: automatic,
                    changeClass: changeClass
                ),
                "Automatic environment must reject \(changeClass.rawValue)"
            )
        }

        var missingActions = valid
        missingActions.removeValue(forKey: "GITHUB_ACTIONS")
        XCTAssertThrowsError(
            try MagicCatalogSigningKeyLoader.load(
                environment: .production,
                variables: missingActions,
                changeClass: .authority
            )
        )

        var staging = valid
        staging["GITHUB_ENVIRONMENT"] = "magic-catalog-staging"
        XCTAssertThrowsError(
            try MagicCatalogSigningKeyLoader.load(
                environment: .staging,
                variables: staging,
                changeClass: .contentOnly
            )
        )
    }

    func testMetadataChangeDoesNotChangeScannerProjection() throws {
        let first = try build().release
        let source = try fixture()
        let renamed = MagicCatalogProviderFixture(sets: source.sets.map { row in
            guard row.code == "ABC" else { return row }
            return MagicCatalogProviderSet(
                id: row.id,
                code: row.code,
                name: "Recorded Expansion Renamed",
                releasedAt: row.releasedAt,
                setType: row.setType,
                cardCount: row.cardCount,
                printedSize: row.printedSize,
                iconSVGURL: row.iconSVGURL,
                parentSetCode: row.parentSetCode,
                digital: row.digital
            )
        })

        let next = try build(fixture: renamed, active: first, revision: 2)
        XCTAssertEqual(next.report.scannerProjectionChangedCodes, [])
        XCTAssertEqual(next.report.browseProjectionChangedCodes, ["ABC"])
        XCTAssertEqual(next.report.routingProjectionChangedCodes, [])
    }

    func testScannerAndRoutingProjectionChangesAreReportedOrRejected() throws {
        let first = try build().release
        let source = try fixture()
        let releasedHistorical = MagicCatalogProviderFixture(sets: source.sets.map { row in
            guard row.code == "OLD" else { return row }
            return MagicCatalogProviderSet(
                id: row.id,
                code: row.code,
                name: row.name,
                releasedAt: "2015-01-01",
                setType: row.setType,
                cardCount: row.cardCount,
                printedSize: row.printedSize,
                iconSVGURL: row.iconSVGURL,
                parentSetCode: row.parentSetCode,
                digital: row.digital
            )
        })
        let next = try build(fixture: releasedHistorical, active: first, revision: 2)
        XCTAssertEqual(next.report.scannerProjectionChangedCodes, ["OLD"])

        let movedChild = MagicCatalogProviderFixture(sets: source.sets.map { row in
            guard row.code == "TABC" else { return row }
            return MagicCatalogProviderSet(
                id: row.id,
                code: row.code,
                name: row.name,
                releasedAt: row.releasedAt,
                setType: row.setType,
                cardCount: row.cardCount,
                printedSize: row.printedSize,
                iconSVGURL: row.iconSVGURL,
                parentSetCode: "OLD",
                digital: row.digital
            )
        })
        XCTAssertThrowsError(try build(fixture: movedChild, active: first, revision: 2)) { error in
            XCTAssertEqual(
                error as? MagicCatalogBuilderError,
                .routingAuthorityDrift(code: "TABC")
            )
        }
    }

    func testRemovalAuthorizationIsExplicitAndComplete() throws {
        let active = try build().release
        let source = try fixture()
        let twoRemoved = MagicCatalogProviderFixture(
            sets: source.sets.filter { !["OLD", "TABC"].contains($0.code) }
        )

        XCTAssertThrowsError(
            try build(
                fixture: MagicCatalogProviderFixture(
                    sets: source.sets.filter { $0.code != "OLD" }
                ),
                active: active,
                revision: 2
            )
        ) { error in
            XCTAssertEqual(
                error as? MagicCatalogBuilderError,
                .unauthorizedRemoval("old")
            )
        }

        let authorized = try MagicCatalogBuilder().build(
            MagicCatalogBuildRequest(
                fixture: MagicCatalogProviderFixture(
                    sets: source.sets.filter { $0.code != "OLD" }
                ),
                activeRelease: active,
                revision: 2,
                generatedAt: "2026-01-01T00:00:00.000Z",
                authorizedRemovalCodes: [" OLD "]
            )
        )
        XCTAssertEqual(authorized.report.changeClass, .authority)

        XCTAssertThrowsError(
            try MagicCatalogBuilder().build(
                MagicCatalogBuildRequest(
                    fixture: source,
                    activeRelease: active,
                    revision: 2,
                    generatedAt: "2026-01-01T00:00:00.000Z",
                    authorizedRemovalCodes: ["NOT-ACTIVE"]
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? MagicCatalogBuilderError,
                .authorizedRemovalNotActive("not-active")
            )
        }

        XCTAssertThrowsError(
            try MagicCatalogBuilder().build(
                MagicCatalogBuildRequest(
                    fixture: twoRemoved,
                    activeRelease: active,
                    revision: 2,
                    generatedAt: "2026-01-01T00:00:00.000Z",
                    authorizedRemovalCodes: ["OLD"]
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? MagicCatalogBuilderError,
                .unauthorizedRemoval("tabc")
            )
        }

        let fullyAuthorized = try MagicCatalogBuilder().build(
            MagicCatalogBuildRequest(
                fixture: twoRemoved,
                activeRelease: active,
                revision: 2,
                generatedAt: "2026-01-01T00:00:00.000Z",
                authorizedRemovalCodes: ["old", "TABC"]
            )
        )
        XCTAssertEqual(fullyAuthorized.report.changeClass, .authority)
        XCTAssertEqual(fullyAuthorized.report.removedCodes, ["OLD", "TABC"])
    }

    func testCandidateValidatorRejectsReportTamperingAgainstRecomputedSemanticDiff() throws {
        let active = try build().release
        let source = try fixture()
        let renamed = MagicCatalogProviderFixture(sets: source.sets.map { row in
            guard row.code == "ABC" else { return row }
            return MagicCatalogProviderSet(
                id: row.id,
                code: row.code,
                name: "Renamed",
                releasedAt: row.releasedAt,
                setType: row.setType,
                cardCount: row.cardCount,
                printedSize: row.printedSize,
                iconSVGURL: row.iconSVGURL,
                parentSetCode: row.parentSetCode,
                digital: row.digital
            )
        })
        let candidate = try build(
            fixture: renamed,
            active: active,
            revision: 2
        )
        XCTAssertNoThrow(
            try MagicCatalogCandidateValidator.validate(
                candidate,
                activeRelease: active
            )
        )

        let tamperedReports: [(String, MagicCatalogReviewReport)] = [
            (
                "changeClass",
                tamperedReport(candidate.report, changeClass: .authority)
            ),
            (
                "contentChangedCodes",
                tamperedReport(candidate.report, contentChangedCodes: [])
            ),
            (
                "authorityChangedCodes",
                tamperedReport(candidate.report, authorityChangedCodes: ["ABC"])
            ),
            (
                "addedCodes",
                tamperedReport(candidate.report, addedCodes: ["NEW"])
            ),
            (
                "changedCodes",
                tamperedReport(candidate.report, changedCodes: [])
            ),
            (
                "removedCodes",
                tamperedReport(candidate.report, removedCodes: ["OLD"])
            ),
            (
                "scannerProjectionChangedCodes",
                tamperedReport(candidate.report, scannerProjectionChangedCodes: ["ABC"])
            ),
            (
                "browseProjectionChangedCodes",
                tamperedReport(candidate.report, browseProjectionChangedCodes: [])
            ),
            (
                "routingProjectionChangedCodes",
                tamperedReport(candidate.report, routingProjectionChangedCodes: ["ABC"])
            ),
            (
                "generatedAt",
                tamperedReport(
                    candidate.report,
                    generatedAt: "2026-01-02T00:00:00.000Z"
                )
            ),
            (
                "descriptorCount",
                tamperedReport(
                    candidate.report,
                    descriptorCount: candidate.report.descriptorCount + 1
                )
            ),
            (
                "revision",
                tamperedReport(candidate.report, revision: candidate.report.revision + 1)
            )
        ]

        for (component, report) in tamperedReports {
            let tampered = MagicCatalogBuildResult(
                release: candidate.release,
                report: report
            )
            XCTAssertThrowsError(
                try MagicCatalogCandidateValidator.validate(
                    tampered,
                    activeRelease: active
                ),
                "Expected report tampering to fail for \(component)"
            )
        }
    }

    func testPublicationClassBindingRequiresRequestedAndRecomputedAgreement() throws {
        let active = try build().release
        let source = try fixture()
        let renamed = MagicCatalogProviderFixture(sets: source.sets.map { row in
            guard row.code == "ABC" else { return row }
            return MagicCatalogProviderSet(
                id: row.id,
                code: row.code,
                name: "Renamed",
                releasedAt: row.releasedAt,
                setType: row.setType,
                cardCount: row.cardCount,
                printedSize: row.printedSize,
                iconSVGURL: row.iconSVGURL,
                parentSetCode: row.parentSetCode,
                digital: row.digital
            )
        })
        let candidate = try build(
            fixture: renamed,
            active: active,
            revision: 2
        )
        let surfaceDiff = MagicCatalogChangeClassifier.surfaceDiff(
            previousRelease: active,
            currentRelease: candidate.release
        )
        let classification = MagicCatalogChangeClassifier.classify(
            previousRelease: active,
            currentRelease: candidate.release,
            surfaceDiff: surfaceDiff
        )

        XCTAssertEqual(
            try MagicCatalogCandidateValidator.bindPublicationClass(
                requestedChangeClass: .contentOnly,
                report: candidate.report,
                recomputedClassification: classification
            ),
            .contentOnly
        )
        XCTAssertThrowsError(
            try MagicCatalogCandidateValidator.bindPublicationClass(
                requestedChangeClass: .authority,
                report: candidate.report,
                recomputedClassification: classification
            )
        ) { error in
            XCTAssertEqual(
                error as? MagicCatalogCandidateValidator.PublicationBindingError,
                .requestedChangeClassMismatch(
                    requested: .authority,
                    recomputed: .contentOnly
                )
            )
        }

        let tamperedReport = tamperedReport(candidate.report, changeClass: .authority)
        XCTAssertThrowsError(
            try MagicCatalogCandidateValidator.bindPublicationClass(
                requestedChangeClass: .contentOnly,
                report: tamperedReport,
                recomputedClassification: classification
            )
        ) { error in
            XCTAssertEqual(
                error as? MagicCatalogCandidateValidator.PublicationBindingError,
                .reportChangeClassMismatch(
                    reported: .authority,
                    recomputed: .contentOnly
                )
            )
        }
    }

    func testPublisherIsIdempotentAndRejectsDowngrade() throws {
        let first = try build().release
        let key = Curve25519.Signing.PrivateKey()
        let publisherRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("magic-catalog-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: publisherRoot) }

        let firstBuild = try build()
        let firstSigned = try MagicCatalogSigner.sign(
            firstBuild,
            privateKey: key,
            keyID: "test"
        )
        let publisher = MagicCatalogFilesystemPublisher(
            root: publisherRoot,
            environment: .production
        )
        _ = try publisher.publish(firstSigned)
        _ = try publisher.publish(firstSigned)

        let secondBuild = try build(active: first, revision: 2)
        let secondSigned = try MagicCatalogSigner.sign(
            secondBuild,
            privateKey: key,
            keyID: "test"
        )
        let secondReceipt = try publisher.publish(
            secondSigned,
            activeRelease: first
        )
        XCTAssertEqual(secondReceipt.revision, 2)
        XCTAssertThrowsError(try publisher.publish(firstSigned, activeRelease: secondBuild.release)) { error in
            XCTAssertEqual(
                error as? MagicCatalogPublisherError,
                .activeRevisionNotMonotonic(received: 1, current: 2)
            )
        }
    }

    func testSignatureCorruptionFailsClosed() throws {
        let key = Curve25519.Signing.PrivateKey()
        let envelope = try MagicCatalogSignatureVerifier.sign(
            release: try build().release,
            privateKey: key,
            keyID: "test"
        )
        let corrupted = MagicCatalogReleaseEnvelope(
            keyID: envelope.keyID,
            payload: envelope.payload,
            signature: envelope.signature + "A"
        )
        XCTAssertThrowsError(try MagicCatalogSignatureVerifier.verify(
            envelope: corrupted,
            keys: [.init(id: "test", publicKey: key.publicKey)]
        )) { error in
            XCTAssertEqual(error as? MagicCatalogSignatureError, .signatureVerificationFailed)
        }
    }
}
