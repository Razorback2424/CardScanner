import CryptoKit
import XCTest
@testable import TradingCardScanner

// MARK: - Fixture builder

private enum CatalogFixture {
    static let keyID = "test-key-1"
    static let privateKey = Curve25519.Signing.PrivateKey()
    static var publicKey: Curve25519.Signing.PublicKey { privateKey.publicKey }
    static var pinnedKey: PokemonCatalogSignatureVerifier.PinnedKey {
        .init(id: keyID, publicKey: publicKey)
    }

    static func signedEnvelope(
        release: PokemonCatalogRelease,
        privateKey: Curve25519.Signing.PrivateKey = privateKey,
        keyID: String = keyID
    ) throws -> PokemonCatalogReleaseEnvelope {
        try PokemonCatalogSignatureVerifier.sign(
            release: release,
            privateKey: privateKey,
            keyID: keyID
        )
    }

    static func release(
        revision: Int = 1,
        generatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        sets: [PokemonCatalogSetDescriptor]? = nil
    ) -> PokemonCatalogRelease {
        PokemonCatalogRelease(
            schemaVersion: PokemonCatalogRelease.currentSchemaVersion,
            revision: revision,
            generatedAt: generatedAt,
            sets: sets ?? [expansion(), promo()]
        )
    }

    static func expansion(
        providerSetID: String = "sv99",
        printedCode: String = "TST",
        officialCount: Int = 100,
        releaseOrder: Int = 99,
        scanEnabled: Bool = true,
        rulesVersion: Int = PokemonChecklistSnapshotVersion.masterSetRules
    ) -> PokemonCatalogSetDescriptor {
        PokemonCatalogSetDescriptor(
            providerSetID: providerSetID,
            displayName: "Test Set",
            releaseDate: "2026-01-01",
            releaseOrder: releaseOrder,
            recognitionKind: .expansion,
            printedCode: printedCode,
            officialCount: officialCount,
            printedPrefix: nil,
            catalogLocalIDPrefix: nil,
            localIDPadWidth: nil,
            scanEnabled: scanEnabled,
            logoURL: nil,
            symbolURL: nil,
            rulesVersion: rulesVersion
        )
    }

    static func promo(
        providerSetID: String = "tstp",
        printedPrefix: String = "TSP",
        catalogLocalIDPrefix: String = "",
        localIDPadWidth: Int = 3,
        scanEnabled: Bool = true,
        rulesVersion: Int = PokemonChecklistSnapshotVersion.masterSetRules
    ) -> PokemonCatalogSetDescriptor {
        PokemonCatalogSetDescriptor(
            providerSetID: providerSetID,
            displayName: "Test Promo",
            releaseDate: nil,
            releaseOrder: nil,
            recognitionKind: .promo,
            printedCode: nil,
            officialCount: nil,
            printedPrefix: printedPrefix,
            catalogLocalIDPrefix: catalogLocalIDPrefix,
            localIDPadWidth: localIDPadWidth,
            scanEnabled: scanEnabled,
            logoURL: nil,
            symbolURL: nil,
            rulesVersion: rulesVersion
        )
    }

    static func notScannable(
        providerSetID: String = "sv99ns",
        printedCode: String? = "NSC"
    ) -> PokemonCatalogSetDescriptor {
        PokemonCatalogSetDescriptor(
            providerSetID: providerSetID,
            displayName: "Not Scannable",
            releaseDate: nil,
            releaseOrder: nil,
            recognitionKind: .notScannable,
            printedCode: printedCode,
            officialCount: nil,
            printedPrefix: nil,
            catalogLocalIDPrefix: nil,
            localIDPadWidth: nil,
            scanEnabled: false,
            logoURL: nil,
            symbolURL: nil,
            rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules
        )
    }
}

// MARK: - Envelope round-trip and malformed tests

final class PokemonCatalogEnvelopeTests: XCTestCase {
    func testRoundTrip() throws {
        let release = CatalogFixture.release()
        let envelope = try CatalogFixture.signedEnvelope(release: release)
        let decoded = try PokemonCatalogSignatureVerifier.verify(
            envelope: envelope,
            currentRevision: nil,
            now: Date(timeIntervalSince1970: 1_700_001_000),
            keys: [CatalogFixture.pinnedKey]
        )
        XCTAssertEqual(decoded, release)
    }

    func testMalformedPayloadRejected() {
        let envelope = PokemonCatalogReleaseEnvelope(
            keyID: CatalogFixture.keyID,
            payload: "not-valid-base64url-@@@",
            signature: "AAAA"
        )
        XCTAssertThrowsError(try PokemonCatalogSignatureVerifier.verify(
            envelope: envelope,
            currentRevision: nil,
            keys: [CatalogFixture.pinnedKey]
        ))
    }

    func testMalformedSignatureRejected() throws {
        let release = CatalogFixture.release()
        let envelope = try CatalogFixture.signedEnvelope(release: release)
        let bad = PokemonCatalogReleaseEnvelope(
            keyID: envelope.keyID,
            payload: envelope.payload,
            signature: "not-valid-base64url-@@@"
        )
        XCTAssertThrowsError(try PokemonCatalogSignatureVerifier.verify(
            envelope: bad,
            currentRevision: nil,
            keys: [CatalogFixture.pinnedKey]
        ))
    }

    func testTruncatedPayloadRejected() throws {
        let release = CatalogFixture.release()
        let envelope = try CatalogFixture.signedEnvelope(release: release)
        let truncated = PokemonCatalogReleaseEnvelope(
            keyID: envelope.keyID,
            payload: String(envelope.payload.prefix(10)),
            signature: envelope.signature
        )
        XCTAssertThrowsError(try PokemonCatalogSignatureVerifier.verify(
            envelope: truncated,
            currentRevision: nil,
            keys: [CatalogFixture.pinnedKey]
        ))
    }
}

// MARK: - Signature verification tests

final class PokemonCatalogSignatureTests: XCTestCase {
    func testSignatureSuccess() throws {
        let release = CatalogFixture.release()
        let envelope = try CatalogFixture.signedEnvelope(release: release)
        let decoded = try PokemonCatalogSignatureVerifier.verify(
            envelope: envelope,
            currentRevision: nil,
            now: Date(timeIntervalSince1970: 1_700_001_000),
            keys: [CatalogFixture.pinnedKey]
        )
        XCTAssertEqual(decoded.revision, 1)
    }

    func testWrongKeyRejected() throws {
        let release = CatalogFixture.release()
        let otherKey = Curve25519.Signing.PrivateKey()
        let otherPinned = PokemonCatalogSignatureVerifier.PinnedKey(
            id: "other-key",
            publicKey: otherKey.publicKey
        )
        let envelope = try CatalogFixture.signedEnvelope(release: release)
        XCTAssertThrowsError(try PokemonCatalogSignatureVerifier.verify(
            envelope: envelope,
            currentRevision: nil,
            keys: [otherPinned]
        )) { error in
            guard case PokemonCatalogSignatureVerifier.VerificationError.unknownKeyID = error else {
                return XCTFail("Expected unknownKeyID, got \(error)")
            }
        }
    }

    func testChangedByteRejected() throws {
        let release = CatalogFixture.release()
        let envelope = try CatalogFixture.signedEnvelope(release: release)
        guard var payloadData = Base64URL.decode(envelope.payload) else {
            return XCTFail("Could not decode payload")
        }
        payloadData[0] ^= 0xFF
        let tampered = PokemonCatalogReleaseEnvelope(
            keyID: envelope.keyID,
            payload: Base64URL.encode(payloadData),
            signature: envelope.signature
        )
        XCTAssertThrowsError(try PokemonCatalogSignatureVerifier.verify(
            envelope: tampered,
            currentRevision: nil,
            keys: [CatalogFixture.pinnedKey]
        )) { error in
            guard case PokemonCatalogSignatureVerifier.VerificationError.signatureVerificationFailed = error else {
                return XCTFail("Expected signatureVerificationFailed, got \(error)")
            }
        }
    }

    func testUnknownKeyIDRejected() throws {
        let release = CatalogFixture.release()
        let envelope = try PokemonCatalogSignatureVerifier.sign(
            release: release,
            privateKey: CatalogFixture.privateKey,
            keyID: "unknown-key"
        )
        XCTAssertThrowsError(try PokemonCatalogSignatureVerifier.verify(
            envelope: envelope,
            currentRevision: nil,
            keys: [CatalogFixture.pinnedKey]
        )) { error in
            guard case PokemonCatalogSignatureVerifier.VerificationError.unknownKeyID("unknown-key") = error else {
                return XCTFail("Expected unknownKeyID(unknown-key), got \(error)")
            }
        }
    }

    func testReplayRejected() throws {
        let release = CatalogFixture.release(revision: 5)
        let envelope = try CatalogFixture.signedEnvelope(release: release)
        XCTAssertThrowsError(try PokemonCatalogSignatureVerifier.verify(
            envelope: envelope,
            currentRevision: 5,
            now: Date(timeIntervalSince1970: 1_700_001_000),
            keys: [CatalogFixture.pinnedKey]
        )) { error in
            guard case PokemonCatalogSignatureVerifier.VerificationError.revisionNotMonotonic = error else {
                return XCTFail("Expected revisionNotMonotonic, got \(error)")
            }
        }
    }

    func testFutureSkewRejected() throws {
        let farFuture = Date().addingTimeInterval(7200)
        let release = CatalogFixture.release(generatedAt: farFuture)
        let envelope = try CatalogFixture.signedEnvelope(release: release)
        XCTAssertThrowsError(try PokemonCatalogSignatureVerifier.verify(
            envelope: envelope,
            currentRevision: nil,
            maxFutureSkew: 3600,
            keys: [CatalogFixture.pinnedKey]
        )) { error in
            guard case PokemonCatalogSignatureVerifier.VerificationError.futureTimestamp = error else {
                return XCTFail("Expected futureTimestamp, got \(error)")
            }
        }
    }
}

// MARK: - Registry collision and scanEnabled tests

final class PokemonCatalogRegistryTests: XCTestCase {
    func testExpansionCodeCollisionRejected() {
        let a = CatalogFixture.expansion(providerSetID: "sv01", printedCode: "DUP")
        let b = CatalogFixture.expansion(providerSetID: "sv02", printedCode: "DUP")
        let release = CatalogFixture.release(sets: [a, b])
        XCTAssertThrowsError(try PokemonCatalogRegistry.validate(release)) { error in
            guard let collision = error as? PokemonCatalogRegistry.CollisionError else {
                return XCTFail("Expected CollisionError, got \(error)")
            }
            XCTAssertEqual(collision.field, "printedCode")
        }
    }

    func testPromoPrefixCollisionRejected() {
        let a = CatalogFixture.promo(providerSetID: "p1", printedPrefix: "DUP")
        let b = CatalogFixture.promo(providerSetID: "p2", printedPrefix: "DUP")
        let release = CatalogFixture.release(sets: [a, b])
        XCTAssertThrowsError(try PokemonCatalogRegistry.validate(release)) { error in
            guard let collision = error as? PokemonCatalogRegistry.CollisionError else {
                return XCTFail("Expected CollisionError, got \(error)")
            }
            XCTAssertEqual(collision.field, "printedPrefix")
        }
    }

    func testProviderSetIDCollisionRejected() {
        let a = CatalogFixture.expansion(providerSetID: "sv01", printedCode: "AAA")
        let b = CatalogFixture.expansion(providerSetID: "SV01", printedCode: "BBB")
        let release = CatalogFixture.release(sets: [a, b])
        XCTAssertThrowsError(try PokemonCatalogRegistry.validate(release)) { error in
            guard let collision = error as? PokemonCatalogRegistry.CollisionError else {
                return XCTFail("Expected CollisionError, got \(error)")
            }
            XCTAssertEqual(collision.field, "providerSetID")
        }
    }

    func testCrossNamespaceCollisionRejected() {
        let exp = CatalogFixture.expansion(providerSetID: "sv01", printedCode: "SVP")
        let pro = CatalogFixture.promo(providerSetID: "svp", printedPrefix: "SVP")
        let release = CatalogFixture.release(sets: [exp, pro])
        XCTAssertThrowsError(try PokemonCatalogRegistry.validate(release)) { error in
            guard let collision = error as? PokemonCatalogRegistry.CollisionError else {
                return XCTFail("Expected CollisionError, got \(error)")
            }
            XCTAssertEqual(collision.field, "cross-namespace")
        }
    }

    func testScanEnabledExpansion() {
        let set = CatalogFixture.expansion(scanEnabled: true)
        let release = CatalogFixture.release(sets: [set])
        let registry = PokemonCatalogRegistry(release: release)
        XCTAssertTrue(registry.isScanEnabled(forProviderSetID: "sv99"))
    }

    func testScanDisabledExpansion() {
        let set = CatalogFixture.expansion(scanEnabled: false)
        let release = CatalogFixture.release(sets: [set])
        let registry = PokemonCatalogRegistry(release: release)
        XCTAssertFalse(registry.isScanEnabled(forProviderSetID: "sv99"))
    }

    func testNotScannableAlwaysDisabled() {
        let set = CatalogFixture.notScannable()
        let release = CatalogFixture.release(sets: [set])
        let registry = PokemonCatalogRegistry(release: release)
        XCTAssertFalse(registry.isScanEnabled(forProviderSetID: "sv99ns"))
    }

    func testUnsupportedRulesVersionSkipped() {
        let future = CatalogFixture.expansion(
            providerSetID: "future1",
            printedCode: "FUT",
            rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules + 1
        )
        let current = CatalogFixture.expansion(
            providerSetID: "current1",
            printedCode: "CUR"
        )
        let release = CatalogFixture.release(sets: [future, current])
        let registry = PokemonCatalogRegistry(release: release)
        XCTAssertNil(registry.expansion(forPrintedCode: "FUT"))
        XCTAssertNotNil(registry.expansion(forPrintedCode: "CUR"))
    }
}

// MARK: - Promo pad-width parity tests

final class PokemonCatalogPromoPadWidthTests: XCTestCase {
    func testBWPadWidth2() {
        let seed = PokemonCatalogRegistry.bundledSeed
        let def = seed.pokemonPromoSetDefinition(forPrefix: "BW")
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.localIDPadWidth, 2)
        XCTAssertEqual(def?.catalogLocalID(number: 1), "BW01")
        XCTAssertEqual(def?.catalogLocalID(number: 99), "BW99")
        let compiled = PokemonPromoCodeMap.definitions["BW"]!
        XCTAssertEqual(def?.catalogLocalID(number: 1), compiled.catalogLocalID(number: 1))
    }

    func testXYPadWidth2() {
        let seed = PokemonCatalogRegistry.bundledSeed
        let def = seed.pokemonPromoSetDefinition(forPrefix: "XY")
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.localIDPadWidth, 2)
        XCTAssertEqual(def?.catalogLocalID(number: 1), "XY01")
        let compiled = PokemonPromoCodeMap.definitions["XY"]!
        XCTAssertEqual(def?.catalogLocalID(number: 1), compiled.catalogLocalID(number: 1))
    }

    func testSMPadWidth2() {
        let seed = PokemonCatalogRegistry.bundledSeed
        let def = seed.pokemonPromoSetDefinition(forPrefix: "SM")
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.localIDPadWidth, 2)
        XCTAssertEqual(def?.catalogLocalID(number: 1), "SM01")
        let compiled = PokemonPromoCodeMap.definitions["SM"]!
        XCTAssertEqual(def?.catalogLocalID(number: 1), compiled.catalogLocalID(number: 1))
    }

    func testSWSHPadWidth3() {
        let seed = PokemonCatalogRegistry.bundledSeed
        let def = seed.pokemonPromoSetDefinition(forPrefix: "SWSH")
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.localIDPadWidth, 3)
        XCTAssertEqual(def?.catalogLocalID(number: 1), "SWSH001")
        let compiled = PokemonPromoCodeMap.definitions["SWSH"]!
        XCTAssertEqual(def?.catalogLocalID(number: 1), compiled.catalogLocalID(number: 1))
    }

    func testSVPPadWidth3() {
        let seed = PokemonCatalogRegistry.bundledSeed
        let def = seed.pokemonPromoSetDefinition(forPrefix: "SVP")
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.localIDPadWidth, 3)
        XCTAssertEqual(def?.catalogLocalID(number: 1), "001")
        let compiled = PokemonPromoCodeMap.definitions["SVP"]!
        XCTAssertEqual(def?.catalogLocalID(number: 1), compiled.catalogLocalID(number: 1))
    }

    func testMEPPadWidth3() {
        let seed = PokemonCatalogRegistry.bundledSeed
        let def = seed.pokemonPromoSetDefinition(forPrefix: "MEP")
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.localIDPadWidth, 3)
        XCTAssertEqual(def?.catalogLocalID(number: 83), "083")
        let compiled = PokemonPromoCodeMap.definitions["MEP"]!
        XCTAssertEqual(def?.catalogLocalID(number: 83), compiled.catalogLocalID(number: 83))
    }

    func testAllPromoSeriesMatchCompiled() {
        let seed = PokemonCatalogRegistry.bundledSeed
        for (prefix, compiled) in PokemonPromoCodeMap.definitions {
            let registry = seed.pokemonPromoSetDefinition(forPrefix: prefix)
            XCTAssertNotNil(registry, "Missing promo \(prefix) in registry")
            XCTAssertEqual(registry?.tcgdexSetID, compiled.tcgdexSetID, "Set ID mismatch for \(prefix)")
            XCTAssertEqual(registry?.localIDPadWidth, compiled.localIDPadWidth, "Pad width mismatch for \(prefix)")
            XCTAssertEqual(registry?.catalogLocalIDPrefix, compiled.catalogLocalIDPrefix, "Prefix mismatch for \(prefix)")
            for n in [1, 10, 99, 100] {
                XCTAssertEqual(
                    registry?.catalogLocalID(number: n),
                    compiled.catalogLocalID(number: n),
                    "Local ID mismatch for \(prefix) number \(n)"
                )
            }
        }
    }
}

// MARK: - Parity gate tests

final class PokemonCatalogParityTests: XCTestCase {

    func testParserExpansionParity() {
        for (code, compiled) in SetCodeMap.definitions {
            let registry = PokemonCatalogRegistry.bundledSeed.pokemonSetDefinition(forPrintedCode: code)
            XCTAssertNotNil(registry, "Missing expansion \(code) in registry")
            XCTAssertEqual(registry?.printedCode, compiled.printedCode, "Printed code mismatch for \(code)")
            XCTAssertEqual(registry?.tcgdexSetID, compiled.tcgdexSetID, "Set ID mismatch for \(code)")
            XCTAssertEqual(registry?.officialCount, compiled.officialCount, "Official count mismatch for \(code)")
            XCTAssertEqual(registry?.releaseIndex, compiled.releaseIndex, "Release index mismatch for \(code)")
        }
    }

    func testParserPromoParity() {
        for (prefix, compiled) in PokemonPromoCodeMap.definitions {
            let registry = PokemonCatalogRegistry.bundledSeed.pokemonPromoSetDefinition(forPrefix: prefix)
            XCTAssertNotNil(registry, "Missing promo \(prefix) in registry")
            XCTAssertEqual(registry?.printedPrefix, compiled.printedPrefix)
            XCTAssertEqual(registry?.tcgdexSetID, compiled.tcgdexSetID)
        }
    }

    func testCustomWordsParity() {
        let compiledWords = Set(ScanText.unique(
            SetCodeMap.codes + PokemonPromoCodeMap.codes
        ))
        let seed = PokemonCatalogRegistry.bundledSeed
        let registryWords = Set(ScanText.unique(
            seed.expansionCodes + seed.promoPrefixes
        ))
        XCTAssertEqual(compiledWords, registryWords)
    }

    func testCardCatalogOfficialCountParity() {
        let seed = PokemonCatalogRegistry.bundledSeed
        for compiled in SetCodeMap.definitions.values {
            let registryCount = seed.officialCount(forProviderSetID: compiled.tcgdexSetID)
            XCTAssertEqual(
                registryCount, compiled.officialCount,
                "Official count mismatch for \(compiled.tcgdexSetID)"
            )
        }
    }

    func testBrowseSortParity() {
        let seed = PokemonCatalogRegistry.bundledSeed
        for compiled in SetCodeMap.definitions.values {
            let registryOrder = seed.releaseOrder(forProviderSetID: compiled.tcgdexSetID)
            XCTAssertEqual(
                registryOrder, compiled.releaseIndex,
                "Release order mismatch for \(compiled.tcgdexSetID)"
            )
        }
    }

    func testPriceRefreshPrintedCodeParity() {
        let seed = PokemonCatalogRegistry.bundledSeed
        for compiled in SetCodeMap.definitions.values {
            let registryCode = seed.printedCode(forProviderSetID: compiled.tcgdexSetID)
            XCTAssertEqual(
                registryCode, compiled.printedCode,
                "Printed code mismatch for provider \(compiled.tcgdexSetID)"
            )
        }
    }

    func testCollectionNormalizerParity() {
        let seed = PokemonCatalogRegistry.bundledSeed
        for compiled in SetCodeMap.definitions.values {
            let registryCode = seed.printedCode(forProviderSetID: compiled.tcgdexSetID)
            let compiledCode = SetCodeMap.printedCode(forTCGdexSetID: compiled.tcgdexSetID)
            XCTAssertEqual(registryCode, compiledCode,
                          "Printed code mismatch for \(compiled.tcgdexSetID)")
            let registryOrder = seed.releaseOrder(forProviderSetID: compiled.tcgdexSetID)
            let compiledOrder = SetCodeMap.releaseIndex(forPrintedCode: compiled.printedCode)
            XCTAssertEqual(registryOrder, compiledOrder,
                          "Release order mismatch for \(compiled.tcgdexSetID)")
        }
    }

    func testDisplayCodeParity() {
        let seed = PokemonCatalogRegistry.bundledSeed
        for compiled in SetCodeMap.definitions.values {
            let registryCode = seed.printedCode(forProviderSetID: compiled.tcgdexSetID)
            let compiledCode = SetCodeMap.printedCode(forTCGdexSetID: compiled.tcgdexSetID)
            XCTAssertEqual(registryCode, compiledCode,
                          "Display code mismatch for \(compiled.tcgdexSetID)")
        }
    }

    func testExpansionCodesCoverAllCompiledSets() {
        let registryCodes = Set(PokemonCatalogRegistry.bundledSeed.expansionCodes)
        let compiledCodes = Set(SetCodeMap.codes)
        XCTAssertEqual(registryCodes, compiledCodes)
    }

    func testPromoPrefixesCoverAllCompiledSeries() {
        let registryPrefixes = Set(PokemonCatalogRegistry.bundledSeed.promoPrefixes)
        let compiledPrefixes = Set(PokemonPromoCodeMap.codes)
        XCTAssertEqual(registryPrefixes, compiledPrefixes)
    }

    func testScanParserStillParsesAllCompiledExpansions() {
        for (code, compiled) in SetCodeMap.definitions {
            let text = "\(code) 001/\(String(format: "%03d", compiled.officialCount))"
            let result = ScanParser.parsePokemon(text)
            XCTAssertNotNil(result, "Parser failed for \(text)")
            if case let .pokemon(setCode, _, printedTotal, definition)? = result {
                XCTAssertEqual(setCode, code)
                XCTAssertEqual(printedTotal, compiled.officialCount)
                XCTAssertEqual(definition.tcgdexSetID, compiled.tcgdexSetID)
            } else {
                XCTFail("Expected .pokemon case for \(text), got \(String(describing: result))")
            }
        }
    }

    func testScanParserStillParsesAllCompiledPromos() {
        for (prefix, compiled) in PokemonPromoCodeMap.definitions {
            let number = prefix.count <= 2 ? "01" : "001"
            let text = "\(prefix) \(number)"
            let result = ScanParser.parsePokemon(text)
            XCTAssertNotNil(result, "Parser failed for \(text)")
            if case let .pokemonPromo(resultPrefix, localID, definition)? = result {
                XCTAssertEqual(resultPrefix, prefix)
                XCTAssertEqual(definition.tcgdexSetID, compiled.tcgdexSetID)
                let expectedLocalID = compiled.catalogLocalID(number: 1)
                XCTAssertEqual(localID, expectedLocalID, "Local ID mismatch for \(prefix)")
            } else {
                XCTFail("Expected .pokemonPromo case for \(text), got \(String(describing: result))")
            }
        }
    }
}

// MARK: - Diagnostic counter tests

final class PokemonCatalogDiagnosticsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PokemonCatalogDiagnostics.resetCounters()
    }

    func testDisplayCodeFallbackCounter() {
        PokemonCatalogDiagnostics.recordDisplayCodeFallback(providerSetID: "sv99")
        PokemonCatalogDiagnostics.recordDisplayCodeFallback(providerSetID: "sv99")
        PokemonCatalogDiagnostics.recordDisplayCodeFallback(providerSetID: "me99")
        XCTAssertEqual(PokemonCatalogDiagnostics.displayCodeFallbackCounts["sv99"], 2)
        XCTAssertEqual(PokemonCatalogDiagnostics.displayCodeFallbackCounts["me99"], 1)
    }

    func testPersistedPlaceholderCodeCounter() {
        PokemonCatalogDiagnostics.recordPersistedPlaceholderCode(providerSetID: "sv11")
        XCTAssertEqual(PokemonCatalogDiagnostics.persistedPlaceholderCodeCounts["sv11"], 1)
    }

    func testResetClearsAllCounters() {
        PokemonCatalogDiagnostics.recordDisplayCodeFallback(providerSetID: "a")
        PokemonCatalogDiagnostics.recordPersistedPlaceholderCode(providerSetID: "b")
        PokemonCatalogDiagnostics.resetCounters()
        XCTAssertTrue(PokemonCatalogDiagnostics.displayCodeFallbackCounts.isEmpty)
        XCTAssertTrue(PokemonCatalogDiagnostics.persistedPlaceholderCodeCounts.isEmpty)
    }
}
