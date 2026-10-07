import XCTest
import Foundation
@testable import TradingCardScanner

/// The token/art identity fix.
///
/// The bug these protect against is silent: scanning a Clue token added
/// Invisible Woman, with no error and a plausible-looking result.
final class MagicContentKindTests: XCTestCase {
    func testModernMagicRejectsFutureOversizedAndIncompletePrintingMetadata() async throws {
        let recorder = MagicAdapterTestRecorder()
        MagicAdapterTestProtocol.recorder = recorder
        defer { MagicAdapterTestProtocol.recorder = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MagicAdapterTestProtocol.self]
        let adapter = MagicCatalogAdapter(source: ScryfallService(breaker: TCGdexCircuitBreaker(), session: URLSession(configuration: config)))
        let identity = ScanIdentifier.magic(setCode: "TRK", collectorNumber: "20", language: "en")
        let changes: [[String: Any]] = [["released_at": "2999-01-01"], ["released_at": "2014-07-17"],
            ["released_at": "invalid"], ["released_at": NSNull()], ["oversized": true], ["layout": NSNull()], ["layout": "token"]]
        for change in changes {
            recorder.setCardChanges(change)
            do { _ = try await adapter.lookup(identity); XCTFail("unsupported printing: \(change)") }
            catch ScryfallError.unsupportedPrinting {}
        }
        for layout in ["normal", "split", "transform", "modal_dfc", "adventure", "saga", "meld", "leveler"] {
            recorder.setCardChanges(["layout": layout, "frame": "1993", "oversized": false])
            guard case .resolved = try await adapter.lookup(identity) else { return XCTFail("Modern footer layout \(layout)") }
        }
    }

    func testAdapterPinsLegacyIdentityAndRejectsStaleOrForeignPayloads() throws {
        let adapter = MagicCatalogAdapter()
        let original = ScanIdentifier.magic(setCode: "TRK", collectorNumber: "0017", language: "en", contentKind: .token)
        let prepared = try adapter.prepareLookupIdentifier(original)
        XCTAssertEqual(prepared.fields, original.fields)
        XCTAssertEqual(prepared.displayIdentifier, original.displayIdentifier)
        XCTAssertEqual(prepared.suppressionIdentity, original.suppressionIdentity)
        XCTAssertEqual(prepared.catalogGeneration, adapter.generation)
        let stale = try ScanIdentifier(game: .magic, namespace: original.namespace, fields: original.fields,
            displayIdentifier: original.displayIdentifier, suppressionIdentity: original.suppressionIdentity,
            catalogGeneration: "other-generation")
        XCTAssertThrowsError(try adapter.prepareLookupIdentifier(stale))
        let malformed = try ScanIdentifier(game: .magic, namespace: "card", fields: [],
            displayIdentifier: "TRK 17", suppressionIdentity: "invalid")
        XCTAssertThrowsError(try adapter.prepareLookupIdentifier(malformed))
        XCTAssertThrowsError(try adapter.prepareLookupIdentifier(.pokemonHistorical(.init(
            number: .init(localID: "17", denominator: 100, scheme: .officialSet), titleCandidates: []))))
    }

    func testAdapterSignedChildRoutingCoalescesAndRejectsWrongLayoutWithoutFallback() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MagicAdapter-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root); MagicAdapterTestProtocol.recorder = nil }
        let recorder = MagicAdapterTestRecorder()
        MagicAdapterTestProtocol.recorder = recorder
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MagicAdapterTestProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let coordinator = MagicCatalogCoordinator(store: MagicCatalogReleaseStore(root: root), rolloutMode: .remoteAuthority)
        let adapter = MagicCatalogAdapter(source: ScryfallService(breaker: TCGdexCircuitBreaker(), session: session), coordinator: coordinator)
        let catalog = CardCatalog(gameCatalogAdapters: try .init(adapters: [adapter]))
        let token = ScanIdentifier.magic(setCode: "TRK", collectorNumber: "17", language: "en", contentKind: .token)
        async let first = catalog.resolution(for: token)
        async let second = catalog.resolution(for: token)
        let results = try await [first, second]
        XCTAssertEqual(results[0].card.providerID, results[1].card.providerID)
        XCTAssertEqual(results[0].retrievedAt, results[1].retrievedAt)
        let cached = try await catalog.resolution(for: token)
        XCTAssertEqual(cached.retrievedAt, results[0].retrievedAt)
        XCTAssertEqual(recorder.paths, ["/cards/ttrk/17/en"])
        let art = try await catalog.resolution(for: .magic(setCode: "MSH", collectorNumber: "18", language: "en", contentKind: .artCard))
        XCTAssertEqual(art.card.setCode.lowercased(), "amsh")
        recorder.setWrongLayout(true)
        let rejected = ScanIdentifier.magic(setCode: "TRK", collectorNumber: "19", language: "en", contentKind: .token)
        do { _ = try await catalog.resolution(for: rejected); XCTFail("Token must reject an ordinary layout") }
        catch ScryfallError.identityMismatch {}
        recorder.setWrongLayout(false)
        _ = try await catalog.resolution(for: rejected)
        let regular = try await catalog.resolution(for: .magic(setCode: "TRK", collectorNumber: "20", language: "en"))
        XCTAssertEqual(regular.card.setCode.lowercased(), "trk")
        do {
            _ = try await catalog.resolution(for: .magic(setCode: "ZZZ", collectorNumber: "1", language: "en", contentKind: .token))
            XCTFail("Missing signed child must not use a live directory or ordinary card")
        } catch ScryfallError.identityMismatch {}
        XCTAssertEqual(recorder.paths, ["/cards/ttrk/17/en", "/cards/amsh/18/en", "/cards/ttrk/19/en", "/cards/ttrk/19/en", "/cards/trk/20/en"])
    }

    // MARK: - The marker is identity

    /// `MSH 17` is Invisible Woman and `TMSH 17` is a Clue token. If the two
    /// identifiers compare equal, rolling confirmation will let frames of one
    /// confirm the other, and the session cache will serve whichever arrived
    /// first.
    func testTokenAndRegularWithTheSameNumberAreDifferentIdentifiers() {
        let regular = ScanIdentifier.magic(
            setCode: "MSH", collectorNumber: "17", language: "en", contentKind: .regular
        )
        let token = ScanIdentifier.magic(
            setCode: "MSH", collectorNumber: "17", language: "en", contentKind: .token
        )

        XCTAssertNotEqual(regular, token)
        XCTAssertNotEqual(regular.hashValue, token.hashValue)
        XCTAssertEqual(Set([regular, token]).count, 2)
    }

    /// The printed identity is shown to the user, so a wrong resolution is
    /// visible rather than plausible.
    func testDisplayIdentifierKeepsThePrintedMarker() {
        XCTAssertEqual(
            ScanIdentifier.magic(
                setCode: "MSH", collectorNumber: "17", language: "en", contentKind: .token
            ).displayIdentifier,
            "T 17 MSH EN"
        )
        XCTAssertEqual(
            ScanIdentifier.magic(
                setCode: "MSH", collectorNumber: "17", language: "en"
            ).displayIdentifier,
            "MSH 17 EN",
            "an ordinary card reads exactly as it did before"
        )
    }

    /// The default keeps every existing construction site meaning what it meant.
    func testMagicIdentifiersDefaultToRegular() {
        let identifier = ScanIdentifier.magic(
            setCode: "MSH", collectorNumber: "17", language: "en"
        )

        XCTAssertEqual(identifier.magicContentKind, .regular)
    }

    // MARK: - Marker recognition

    /// Magic prints a rarity letter in the same position as the token marker.
    /// Only `T` may be read as a content marker; the rest must keep being
    /// ignored, or ordinary cards start resolving as tokens.
    func testOnlyTIsAContentMarker() {
        XCTAssertEqual(MagicPrintedMarker.marker(for: "T")?.contentKind, .token)
        XCTAssertEqual(MagicPrintedMarker.marker(for: "t")?.contentKind, .token)

        for rarity in ["C", "U", "R", "M", "S", "L", "P"] {
            XCTAssertNil(
                MagicPrintedMarker.marker(for: rarity),
                "\(rarity) is a rarity letter, not a content marker"
            )
        }

        // Deliberately not enabled: the printed syntax for art cards has not
        // been confirmed from a physical card, and guessing would misread
        // ordinary footers.
        XCTAssertNil(MagicPrintedMarker.marker(for: "A"))
    }

    // MARK: - Layout validation

    /// Validation runs both ways. Without the reverse check, dropping the old
    /// blanket layout filter would let a token arrive through an ordinary
    /// lookup — the same bug pointing the other way.
    func testEachKindAcceptsOnlyItsOwnLayouts() {
        XCTAssertTrue(MagicContentKind.token.acceptedLayouts.contains("token"))
        XCTAssertTrue(MagicContentKind.token.acceptedLayouts.contains("double_faced_token"))
        XCTAssertFalse(MagicContentKind.token.acceptedLayouts.contains("normal"))
        XCTAssertFalse(MagicContentKind.token.acceptedLayouts.contains("art_series"))

        XCTAssertEqual(MagicContentKind.artCard.acceptedLayouts, ["art_series"])
        XCTAssertFalse(MagicContentKind.artCard.acceptedLayouts.contains("token"))
    }

    /// `art_series` is a card layout, not a set type. Art series sets are
    /// `memorabilia`, which is why the old exclusion list's `"art_series"` entry
    /// has never matched a single set.
    func testArtSeriesSetsAreMemorabiliaNotArtSeries() {
        XCTAssertEqual(MagicContentKind.artCard.childSetType, "memorabilia")
        XCTAssertEqual(MagicContentKind.token.childSetType, "token")
        XCTAssertNil(MagicContentKind.regular.childSetType)
    }

    // MARK: - Child-set resolution

    private func directory() -> [String: [MagicChildSet]] {
        [
            "MSH": [
                MagicChildSet(code: "TMSH", name: "Marvel Super Heroes Tokens",
                              parentCode: "MSH", setType: "token", contentKind: .token),
                MagicChildSet(code: "AMSH", name: "Marvel Super Heroes Art Series",
                              parentCode: "MSH", setType: "memorabilia", contentKind: .artCard)
            ],
            // A real multi-child case: the main token set plus a 3-card Asia
            // WPN promo set.
            "FIN": [
                MagicChildSet(code: "TFIN", name: "Final Fantasy Tokens",
                              parentCode: "FIN", setType: "token", contentKind: .token),
                MagicChildSet(code: "WFIN", name: "FIN Asia WPN Promo Tokens",
                              parentCode: "FIN", setType: "token", contentKind: .token)
            ],
            "ZZZ": [
                MagicChildSet(code: "WZZZ", name: "ZZZ Japanese Promo Tokens",
                              parentCode: "ZZZ", setType: "token", contentKind: .token),
                MagicChildSet(code: "SZZZ", name: "ZZZ Substitute Cards",
                              parentCode: "ZZZ", setType: "token", contentKind: .token)
            ]
        ]
    }

    func testUniqueChildSetResolves() {
        XCTAssertEqual(
            ScryfallService.childSet(for: .token, parentCode: "MSH", in: directory())?.code,
            "TMSH"
        )
        XCTAssertEqual(
            ScryfallService.childSet(for: .artCard, parentCode: "MSH", in: directory())?.code,
            "AMSH"
        )
    }

    /// Where a parent has several token children, the main set wins. The
    /// alternatives are regional promos and substitute cards — different
    /// products a booster-pack scan is not.
    func testMainTokenSetIsPreferredOverPromoSiblings() {
        XCTAssertEqual(
            ScryfallService.childSet(for: .token, parentCode: "FIN", in: directory())?.code,
            "TFIN"
        )
    }

    /// When no candidate is the main set, nothing is returned. Guessing between
    /// a Japanese promo and a substitute-card set would add the wrong object.
    func testAmbiguityWithNoMainSetRefusesToGuess() {
        XCTAssertNil(
            ScryfallService.childSet(for: .token, parentCode: "ZZZ", in: directory())
        )
    }

    /// The mapping comes from the directory, never from a naming rule. `"T" +
    /// parent` is wrong for 18 of 206 token sets, and every one of those is a
    /// substitute or promo set a prefix rule would return instead.
    func testUnknownParentResolvesToNothingRatherThanAGuessedCode() {
        XCTAssertNil(
            ScryfallService.childSet(for: .token, parentCode: "QQQ", in: directory())
        )
        XCTAssertNil(
            ScryfallService.childSet(for: .artCard, parentCode: "FIN", in: directory()),
            "FIN has no art-series child in this directory, so nothing is returned"
        )
    }

    // MARK: - Parser end to end

    private var profile: MagicScanProfile {
        MagicScanProfile(definitions: [
            .init(code: "MSH", printedSize: nil),
            .init(code: "ECL", printedSize: 269)
        ])
    }

    /// The bug, from the footer as the camera actually sees it. Two lines: the
    /// marker and number on one, the set code and language on the next.
    func testTokenFooterParsesAsAToken() {
        let identifier = profile.parse(["T 0017", "MSH • EN", "© 2026 WIZARDS"])

        XCTAssertEqual(identifier?.magicContentKind, .token)
        XCTAssertEqual(identifier?.displayIdentifier, "T 17 MSH EN")
    }

    /// The same footer on a single OCR line, which is how it often comes back.
    func testTokenFooterOnOneLineParsesAsAToken() {
        XCTAssertEqual(
            profile.parse(["T 0017 MSH • EN"])?.magicContentKind,
            .token
        )
    }

    /// The other half of the collision: an ordinary MSH 17 must keep resolving
    /// as an ordinary card, and must not become a token.
    func testOrdinaryFooterIsUnaffected() {
        let identifier = profile.parse(["MSH • 0017 • EN"])

        XCTAssertEqual(identifier?.magicContentKind, .regular)
        XCTAssertEqual(identifier?.displayIdentifier, "MSH 17 EN")
    }

    /// The rarity letter sits where the marker sits. It must stay ignored.
    func testRarityLetterIsStillNotAMarker() {
        let identifier = profile.parse(["R 0218", "ECL • EN"])

        XCTAssertEqual(identifier?.magicContentKind, .regular)
        XCTAssertEqual(identifier?.displayIdentifier, "ECL 218 EN")
    }

    /// The two readings of the same number must not confirm each other across
    /// frames, which is what `Hashable` identity on the enum guarantees.
    func testTokenAndOrdinaryReadingsDoNotConfirmEachOther() {
        var window = CandidateConfirmationWindow(matchesRequired: 2, windowSize: 4)
        let token = profile.parse(["T 0017", "MSH • EN"])
        let regular = profile.parse(["MSH • 0017 • EN"])
        XCTAssertNotNil(token)
        XCTAssertNotNil(regular)
        let tokenSubject = token.map { ScanSubject(identifier: $0) }
        let regularSubject = regular.map { ScanSubject(identifier: $0) }

        XCTAssertNil(window.observeSubject(tokenSubject))
        XCTAssertNil(window.observeSubject(regularSubject), "a card must not confirm a token")
        XCTAssertEqual(window.observeSubject(tokenSubject), tokenSubject, "two token frames do confirm")
    }

    // MARK: - Item kind stays a separate axis

    /// A graded token is both graded and a token. Collapsing the two axes would
    /// make one of them unrepresentable.
    func testContentKindIsIndependentOfOwnershipKind() {
        XCTAssertEqual(MagicContentKind.allCases.count, 3)
        XCTAssertEqual(CollectionItemKind.allCases.count, 3)
        // Different types entirely — this is a compile-time guarantee, asserted
        // here so the intent survives a future refactor.
        XCTAssertEqual(MagicContentKind.token.label, "Token")
        XCTAssertEqual(CollectionItemKind.gradedCard.label, "Graded Cards")
    }
}

private final class MagicAdapterTestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [String] = []
    private var wrongLayout = false
    private var cardChanges: [String: Any] = [:]
    var paths: [String] { lock.lock(); defer { lock.unlock() }; return captured }
    func setWrongLayout(_ value: Bool) { lock.lock(); defer { lock.unlock() }; wrongLayout = value }
    func setCardChanges(_ value: [String: Any]) { lock.lock(); defer { lock.unlock() }; cardChanges = value }
    func data(for request: URLRequest) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        let path = request.url!.path
        captured.append(path)
        let parts = path.split(separator: "/")
        guard parts.count == 4, parts[0] == "cards" else { throw ScryfallError.identityMismatch }
        let code = String(parts[1]), number = String(parts[2])
        let layout = wrongLayout ? "normal" : (code == "ttrk" ? "token" : (code == "amsh" ? "art_series" : "normal"))
        let card: [String: Any] = ["id": "fixture-\(code)-\(number)", "name": "Fixture card",
            "set": code, "set_name": "Fixture set", "collector_number": number, "lang": "en",
            "digital": false, "layout": layout, "released_at": "2025-01-01", "finishes": ["nonfoil"]]
        return try JSONSerialization.data(withJSONObject: card.merging(cardChanges) { _, new in new })
    }
}

private final class MagicAdapterTestProtocol: URLProtocol {
    nonisolated(unsafe) static var recorder: MagicAdapterTestRecorder?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let recorder = Self.recorder else { throw ScryfallError.providerUnavailable }
            let data = try recorder.data(for: request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
