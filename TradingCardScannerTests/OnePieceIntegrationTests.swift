import CryptoKit
import OnePieceCatalogCore
import SwiftData
import SwiftUI
import Foundation
import XCTest
@testable import TradingCardScanner

private actor OnePieceTestPriceSource: OnePieceMarketPriceSource {
    var calls = 0
    var lastMinimumFetchedAt: Date?
    func quote(mapping: OnePieceMarketMapping, number: String, generation: String?, minimumFetchedAt: Date?) async throws -> PriceLookup {
        calls += 1
        lastMinimumFetchedAt = minimumFetchedAt
        return .price(.init(unitMarketPriceUSD: 8.16, currencyCode: "USD", source: .tcgCSV,
            sourceVariantID: "tcgplayer:\(mapping.productID):\(mapping.providerVariantID!)",
            sourceUpdatedAt: nil, fetchedAt: .now))
    }
}

private actor OnePieceSnapshotTestSource: GameCatalogActivationSource {
    nonisolated let game = CardGame.onePiece
    private var snapshot: GameCatalogSnapshot?
    private var continuations: [AsyncStream<GameCatalogSnapshot>.Continuation] = []
    private(set) var snapshotReads = 0
    init(_ snapshot: GameCatalogSnapshot?) { self.snapshot = snapshot }
    func update(_ snapshot: GameCatalogSnapshot) {
        self.snapshot = snapshot
        for continuation in continuations { continuation.yield(snapshot) }
    }
    func currentSnapshot() async -> GameCatalogSnapshot? { snapshotReads += 1; return snapshot }
    func activationSnapshots() async -> AsyncStream<GameCatalogSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(of: GameCatalogSnapshot.self)
        continuations.append(continuation)
        return stream
    }
}

@MainActor
private final class OnePieceTestSessionState { var isCurrent = true }

private struct OnePieceInjectedSaveFailure: Error {}

private final class OnePiecePriceTestProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Data)?
    nonisolated(unsafe) static var asyncHandler: (@Sendable (URLRequest) async -> Data)?
    private var responseTask: Task<Void, Never>?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let handler = Self.asyncHandler {
            responseTask = Task {
                let data = await handler(request)
                guard !Task.isCancelled else { return }
                send(data)
            }
            return
        }
        guard let data = Self.handler?(request) else { return }
        send(data)
    }
    private func send(_ data: Data) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { responseTask?.cancel() }
}

private actor OnePiecePriceRequestGate {
    let firstRequest = OnePieceLookupGate()
    private(set) var productCalls = 0
    private(set) var priceCalls = 0
    func response(_ request: URLRequest) async -> Data {
        if request.url!.lastPathComponent == "products" {
            productCalls += 1
            if productCalls == 1 { await firstRequest.pause() }
            return Data(#"{"success":true,"errors":[],"results":[{"productId":454664,"categoryId":68,"groupId":3188,"name":"Shanks","extendedData":[{"name":"Number","value":"OP01-120"}]}]}"#.utf8)
        }
        priceCalls += 1
        return Data(#"{"success":true,"errors":[],"results":[{"productId":454664,"subTypeName":"Foil","marketPrice":8.16}]}"#.utf8)
    }
}

private final class OnePieceRecoveryReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private let release = DispatchSemaphore(value: 0)
    private let blockedRead: Int
    private var readCount = 0
    private var started = false
    init(blockedRead: Int = 1) { self.blockedRead = blockedRead }
    var hasStarted: Bool { lock.withLock { started } }
    func read(_ url: URL) throws -> Data {
        let blocked = lock.withLock {
            readCount += 1
            guard readCount == blockedRead else { return false }
            started = true
            return true
        }
        if blocked { _ = release.wait(timeout: .now() + 10) }
        return try Data(contentsOf: url)
    }
    func resume() { release.signal() }
}

@MainActor
final class OnePieceIntegrationTests: XCTestCase {
    func testOnePieceSealedAddUndoAndExactVendorRepricingRespectRuntimeGates() async throws {
        let registry = try registry()
        let (_, container) = try model(registry: registry)
        let browseOnly = try CardGameRuntimeContainer(runtimes: [OnePieceGameRuntime(registry: registry).runtime])
        browseOnly.configureCollectionAuthority(for: container)
        let product = SealedProductSummary(id: "vendor-box", name: "One Piece Booster Box", setName: "Vendor OP Set",
            variantID: "vendor-exact", marketPriceUSD: 80, updatedAt: nil, imageURL: nil)
        XCTAssertThrowsError(try CollectionStore(context: container.mainContext).addSealed(product, game: .onePiece))
        XCTAssertTrue(browseOnly.registry.supports(.onePiece, .sealed))
        let writable = try CardGameRuntimeContainer(runtimes: [OnePieceGameRuntime(registry: registry,
            capabilities: [.browse, .sealed, .pricing, .collectionWrite]).runtime])
        writable.configureCollectionAuthority(for: container)
        XCTAssertTrue(writable.makePriceQuoteService().supportsSealedPricing(for: .onePiece))
        let store = CollectionStore(context: container.mainContext)
        let mutation = try store.addSealed(product, game: .onePiece)
        let row = try XCTUnwrap(store.card(forKey: mutation.collectionKey))
        XCTAssertEqual(row.itemKind, .sealedProduct)
        XCTAssertEqual(row.justTCGVariantID, "vendor-exact")
        XCTAssertEqual(row.cardNumber, "")
        let suite = "OnePieceSealedRefresh-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); OnePiecePriceTestProtocol.handler = nil }
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [OnePiecePriceTestProtocol.self]
        var settings = JustTCGTransport.Configuration()
        settings.baseURL = URL(string: "https://sealed.test")!
        settings.minimumRequestInterval = 0
        OnePiecePriceTestProtocol.handler = { request in
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            let items = (try? JSONSerialization.jsonObject(with: body)) as? [[String: String]]
            XCTAssertEqual(items, [["variantId": "vendor-exact"]])
            return Data(#"{"data":[{"uuid":"vendor-box","variants":[{"uuid":"wrong","condition":"Sealed","price":9000},{"uuid":"vendor-exact","condition":"Sealed","price":99.25}]}]}"#.utf8)
        }
        let transport = JustTCGTransport(configuration: settings, session: URLSession(configuration: session),
            ledger: .init(defaults: defaults), pacer: .init(), apiKeyOverride: "fixture-key")
        let coordinator = JustTCGRefreshCoordinator(client: JustTCGV1Client(transport: transport), syncLedger: .init(defaults: defaults))
        let target = MarketPriceTarget(priceKey: row.priceKey, game: .onePiece, printingID: row.priceStorageID,
            variantID: nil, itemKind: .sealedProduct, marketVariantID: row.justTCGVariantID,
            lookupCandidates: [.variantID("vendor-exact")], currentAmount: 80, lastCheckedAt: nil)
        let prices = PriceStore(context: container.mainContext)
        let storageID = row.priceStorageID
        let report = await coordinator.refresh([target], game: .onePiece, lane: .interactive,
            apply: { _, variant, _ in
                await MainActor.run {
                prices.store(.price(.init(unitMarketPriceUSD: variant.marketPriceUSD!, currencyCode: "USD", source: .justTCG,
                    sourceVariantID: variant.variantId!, sourceUpdatedAt: variant.updatedAt, fetchedAt: .now)),
                    game: .onePiece, printingID: storageID, variantID: nil)
                return true
                }
            }, checkpoint: { await MainActor.run { prices.save() } })
        XCTAssertEqual(report.pricesWritten, 1)
        XCTAssertEqual(prices.record(forKey: row.priceKey)?.effectiveUnitMarketPriceUSD, 99.25)
        try store.undo(mutation)
        XCTAssertEqual(store.card(forKey: mutation.collectionKey)?.quantity ?? 0, 0)
        browseOnly.configureCollectionAuthority(for: container)
        XCTAssertFalse(browseOnly.registry.supports(.onePiece, .collectionWrite))
    }

    private let date = "2026-10-03T00:00:00Z"

#if DEBUG && LOCAL_ONLY_SIGNING
    func testAcceptanceLaunchSeparatesCollectionAndRecoveryFromOwnerAndReviewStorage() throws {
        XCTAssertNil(OnePieceCatalogBootstrap.developerStorageDirectory(arguments: ["app"]))
        XCTAssertNil(OnePieceCatalogBootstrap.developerStorageDirectory(arguments: ["app", "-ui_debug_route"]))
        XCTAssertNil(OnePieceCatalogBootstrap.developerStorageDirectory(arguments: ["app", "-ui_debug_route", "PrintingChoice"]))
        XCTAssertEqual(OnePieceCatalogBootstrap.developerStorageDirectory(arguments: ["app", "-one_piece_local_review"]),
                       "OnePieceLocalReview")
        let args = ["app", "-ui_debug_route", "OnePieceAcceptance"]
        XCTAssertEqual(OnePieceCatalogBootstrap.developerStorageDirectory(arguments: args), "OnePieceAcceptance")
        XCTAssertEqual(OnePieceCatalogBootstrap.acceptanceNumber(arguments: args), "ST11-003")
        XCTAssertEqual(OnePieceCatalogBootstrap.acceptanceNumber(arguments: args + ["-ui_debug_state", "unknown"]), "OP01-999")
        let registry = try reviewedAwardRegistry()
        let profile = OnePieceScanProfile(registry: registry)
        for state in ["same-number", "starter", "booster", "unmapped", "unknown"] {
            let number = OnePieceCatalogBootstrap.acceptanceNumber(arguments: args + ["-ui_debug_state", state])
            guard case .identified = profile.identify([.init(text: number)]) else {
                return XCTFail("Acceptance sample \(state) must enter the real catalog lookup")
            }
        }
        XCTAssertNil(registry.printingsByCanonicalID["one-piece:en:OP01-999"])
        let ordinary = CollectionStoragePaths.production()
        let acceptance = CollectionStoragePaths.production(resolvedApplicationSupportURL:
            ordinary.applicationSupportURL.appendingPathComponent("OnePieceAcceptance"))
        XCTAssertNotEqual(acceptance.structuredStoreURL, ordinary.structuredStoreURL)
        XCTAssertNotEqual(acceptance.collectionStorageDirectoryURL, ordinary.collectionStorageDirectoryURL)
    }

    func testShikiScanSavesWithoutPrintingOrFinishPicker() async throws {
        let suite = "OnePieceShikiTests-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let runtime = try XCTUnwrap(OnePieceCatalogBootstrap.ownerRuntime(preferences: preferences))
        let registry = try XCTUnwrap((runtime.catalog as? OnePieceCatalogAdapter)?.registry)
        let (model, container) = try model(registry: registry, fixtureWritesEnabled: true)
        defer { model.viewDisappeared() }
        guard case let .identified(subject) = OnePieceScanProfile(registry: registry).identify([.init(text: "OP17-047")]) else {
            return XCTFail("Shiki's printed number should be recognized")
        }
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), subject, nil)
        let saved = await waitUntil { model.successCount == 1 }
        XCTAssertTrue(saved)
        XCTAssertNil(model.pendingIdentityChoice)
        XCTAssertNil(model.pendingChoice)
        let owned = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(owned.name, "Shiki")
        XCTAssertEqual(owned.cardNumber, "OP17-047")
        XCTAssertEqual(owned.quantity, 1)
        XCTAssertEqual(owned.variantResolution, .uniqueInCatalog)
    }

    func testOrdinaryAppBundleEnablesOnePieceWithoutSavedOwnerSettings() throws {
        let suite = "OnePieceFreshInstallTests-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let runtime = try XCTUnwrap(OnePieceCatalogBootstrap.ownerRuntime(preferences: preferences))
        XCTAssertTrue(runtime.descriptor.capabilities.contains(.scan))
        XCTAssertTrue(runtime.descriptor.capabilities.contains(.collectionWrite))
        XCTAssertNotNil(runtime.recognizer)
        XCTAssertFalse(runtime.variantPolicy.lockOptions.isEmpty)
        XCTAssertFalse(preferences.bool(forKey: "onePieceOwnerCatalogEnabled"))
        XCTAssertFalse(OnePieceCatalogBootstrap.isLocalReviewLaunch)
        let defaults = CardGameRuntimeContainer.appDefaults()
        XCTAssertTrue(defaults.registry.supports(.onePiece, .scan))
        XCTAssertTrue(defaults.registry.supports(.onePiece, .collectionWrite))
        XCTAssertTrue(defaults.registry.variantLockMenu.contains { $0.game == .onePiece && !$0.options.isEmpty })
    }

    func testBundledOwnerCatalogRepairsIdentifierTitlesAcrossReleaseFamilies() throws {
        let runtime = try XCTUnwrap(OnePieceCatalogBootstrap.ownerRuntime())
        let adapter = try XCTUnwrap(runtime.catalog as? OnePieceCatalogAdapter)
        for number in ["OP17-020", "OP16-052", "OP15-001", "OP14-034", "ST01-012", "EB03-010"] {
            let printing = try XCTUnwrap(adapter.registry.printingsByCanonicalID["one-piece:en:" + number]?
                .first(where: { $0.status == .verified && $0.treatment == "Standard artwork" }))
            XCTAssertFalse(printing.marketMappings.isEmpty, number)
        }
        let disputed = try XCTUnwrap(adapter.registry.printingsByCanonicalID["one-piece:en:OP16-030"]?
            .first(where: { $0.status == .verified && $0.treatment == "Standard artwork" }))
        XCTAssertTrue(disputed.marketMappings.isEmpty)
        XCTAssertEqual(disputed.supportedVariantIDs, ["normal"])
    }

    func testLocalOwnerReviewRotationRequiresAnExplicitMatchingPublicPin() throws {
        let registry = try registry(), old = Curve25519.Signing.PrivateKey(), rotated = Curve25519.Signing.PrivateKey()
        let keyID = "one-piece-owner-review-r2"
        let envelope = try OnePieceCatalogSignature.sign(registry.verifiedRelease.release, keyID: keyID, privateKey: rotated)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let seed = root.appendingPathComponent("seed.json")
        try JSONEncoder().encode(envelope).write(to: seed)
        let oldPin = old.publicKey.rawRepresentation.base64EncodedString()
        let args = ["-one_piece_local_review", "-one_piece_review_seed", seed.path,
                    "-one_piece_review_public_key", oldPin]
        XCTAssertThrowsError(try OnePieceCatalogBootstrap.localReviewRuntime(arguments: args, now: now))
        XCTAssertThrowsError(try OnePieceCatalogBootstrap.localReviewRuntime(arguments: args, now: now,
            pinnedReviewKeys: ["one-piece-local-review": oldPin, keyID: oldPin]))
        let runtime = try XCTUnwrap(OnePieceCatalogBootstrap.localReviewRuntime(arguments: args, now: now,
            pinnedReviewKeys: ["one-piece-local-review": oldPin,
                               keyID: rotated.publicKey.rawRepresentation.base64EncodedString()]))
        XCTAssertEqual(runtime.catalog?.generation, registry.generation)
        XCTAssertTrue(runtime.descriptor.capabilities.contains(.collectionWrite))
    }

    func testOwnerCatalogUsesNormalStorageAndRetainsVerifiedAuthorityForOrdinaryBuilds() throws {
        let registry = try registry(), key = Curve25519.Signing.PrivateKey()
        let envelope = try OnePieceCatalogSignature.sign(registry.verifiedRelease.release,
            keyID: "one-piece-local-review", privateKey: key)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnePieceOwner-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func bundle(_ name: String, owner: Bool) throws -> Bundle {
            let path = root.appendingPathComponent(name + ".bundle")
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            var info: [String: Any] = ["CFBundleIdentifier": "com.seankeller.CardScanner", "CFBundleName": name]
            if owner {
                info["ONE_PIECE_OWNER_CATALOG_ENABLED"] = true
                info["ONE_PIECE_OWNER_CATALOG_PUBLIC_KEY"] = key.publicKey.rawRepresentation.base64EncodedString()
            }
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: path.appendingPathComponent("Info.plist"))
            return try XCTUnwrap(Bundle(url: path))
        }
        let suite = "OnePieceOwnerTests-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let seed = root.appendingPathComponent("seed.json")
        let owner = try bundle("Owner", owner: true), ordinary = try bundle("Ordinary", owner: false)
        XCTAssertNil(try OnePieceCatalogBootstrap.ownerRuntime(bundle: ordinary, seedURL: seed, preferences: preferences, now: now))
        try Data("invalid".utf8).write(to: seed)
        XCTAssertThrowsError(try OnePieceCatalogBootstrap.ownerRuntime(bundle: owner, seedURL: seed, preferences: preferences, now: now))
        XCTAssertFalse(preferences.bool(forKey: "onePieceOwnerCatalogEnabled"))
        try JSONEncoder().encode(envelope).write(to: seed)
        let runtime = try XCTUnwrap(OnePieceCatalogBootstrap.ownerRuntime(bundle: owner, seedURL: seed, preferences: preferences, now: now))
        XCTAssertTrue(runtime.descriptor.capabilities.contains(.collectionWrite))
        let retained = try XCTUnwrap(OnePieceCatalogBootstrap.ownerRuntime(bundle: ordinary, seedURL: seed, preferences: preferences, now: now))
        XCTAssertEqual(retained.catalog?.generation, runtime.catalog?.generation)
        XCTAssertFalse(OnePieceCatalogBootstrap.isLocalReviewLaunch)
    }

    func testHomeScreenReviewLaunchRequiresSeparateBundleAndExplicitPublicKey() {
        let original = ["app"]
        XCTAssertEqual(OnePieceCatalogBootstrap.localReviewLaunchArguments(arguments: original,
            bundleIdentifier: "com.seankeller.CardScanner", publicKey: "key"), original)
        XCTAssertEqual(OnePieceCatalogBootstrap.localReviewLaunchArguments(arguments: original,
            bundleIdentifier: "com.seankeller.CardScanner.OnePieceReview", publicKey: nil), original)
        let automatic = OnePieceCatalogBootstrap.localReviewLaunchArguments(arguments: original,
            bundleIdentifier: "com.seankeller.CardScanner.OnePieceReview", publicKey: "key")
        XCTAssertTrue(automatic.contains("Documents/one-piece-local-review.json"))
        XCTAssertEqual(automatic.last, "key")
        XCTAssertEqual(OnePieceCatalogBootstrap.localReviewLaunchArguments(arguments: automatic,
            bundleIdentifier: "com.seankeller.CardScanner.OnePieceReview", publicKey: "other"), automatic)
        XCTAssertEqual(OnePieceCatalogBootstrap.localReviewLaunchArguments(arguments: original,
            bundleIdentifier: "com.seankeller.CardScanner", publicKey: "key", reviewEnabled: true), automatic)
        XCTAssertEqual(OnePieceCatalogBootstrap.localReviewLaunchArguments(arguments: original,
            bundleIdentifier: "com.seankeller.CardScanner", publicKey: nil, reviewEnabled: true), original)
        XCTAssertEqual(OnePieceCatalogBootstrap.localReviewLaunchArguments(arguments: original,
            bundleIdentifier: "unrelated.app", publicKey: "key", reviewEnabled: true), original)
    }
#endif

    func testDisabledBootstrapDoesNotRequireSeedOrRegisterOnePiece() throws {
        let config = try OnePieceCatalogBootstrapConfiguration(mode: .disabled, pinnedKeys: nil, baseURL: nil)
        XCTAssertNil(try OnePieceCatalogBootstrap.runtime(configuration: config, seed: Data("invalid".utf8)))
    }

    func testBootstrapRequiresDedicatedKeysSafeOriginAndVerifiedSeed() throws {
        let registry = try registry(), key = Curve25519.Signing.PrivateKey(), keyID = "one-piece-bootstrap-fixture"
        let pin = "\(keyID):\(key.publicKey.rawRepresentation.base64EncodedString())"
        let origin = "https://scanstash-catalog-prod.web.app"
        XCTAssertThrowsError(try OnePieceCatalogBootstrapConfiguration(mode: .remoteAuthority, pinnedKeys: pin,
            baseURL: origin, forbiddenPublicKeys: [key.publicKey.rawRepresentation]))
        for keys in ["pokemon-key:\(key.publicKey.rawRepresentation.base64EncodedString())", pin + "," , pin + "," + pin] {
            XCTAssertThrowsError(try OnePieceCatalogBootstrapConfiguration(mode: .remoteAuthority, pinnedKeys: keys, baseURL: origin))
        }
        for url in ["http://scanstash-catalog-prod.web.app", origin + "/other", origin + "?query=1", "https://elsewhere.invalid"] {
            XCTAssertThrowsError(try OnePieceCatalogBootstrapConfiguration(mode: .remoteAuthority, pinnedKeys: pin, baseURL: url))
        }
        let config = try OnePieceCatalogBootstrapConfiguration(mode: .remoteAuthority, pinnedKeys: pin, baseURL: origin)
        XCTAssertEqual(config.endpoint?.path, "/one-piece/v1/current.json")
        XCTAssertThrowsError(try OnePieceCatalogBootstrap.runtime(configuration: config, seed: nil))
        let wrong = try OnePieceCatalogSignature.sign(registry.verifiedRelease.release, keyID: keyID,
            privateKey: Curve25519.Signing.PrivateKey())
        XCTAssertThrowsError(try OnePieceCatalogBootstrap.runtime(configuration: config, seed: JSONEncoder().encode(wrong), now: now))
        let envelope = try OnePieceCatalogSignature.sign(registry.verifiedRelease.release, keyID: keyID, privateKey: key)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnePieceBootstrap-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = try XCTUnwrap(OnePieceCatalogBootstrap.runtime(configuration: config,
            seed: JSONEncoder().encode(envelope), root: root, now: now))
        XCTAssertEqual(runtime.catalog?.generation, registry.generation)
        XCTAssertTrue(runtime.descriptor.capabilities.contains(.scan))
        XCTAssertTrue(runtime.descriptor.capabilities.contains(.browse))
        XCTAssertFalse(runtime.descriptor.capabilities.contains(.collectionWrite))
        XCTAssertNotNil(runtime.pricing)
        let writable = try OnePieceCatalogBootstrapConfiguration(mode: .remoteAuthority, pinnedKeys: pin,
            baseURL: origin, collectionWrites: true)
        let writableRuntime = try XCTUnwrap(OnePieceCatalogBootstrap.runtime(configuration: writable,
            seed: JSONEncoder().encode(envelope), root: root, now: now))
        XCTAssertTrue(writableRuntime.descriptor.capabilities.contains(.collectionWrite))
    }

    func testValidationOnlyBootstrapKeepsGameHiddenAndWritesDisabled() throws {
        let registry = try registry(), key = Curve25519.Signing.PrivateKey(), keyID = "one-piece-bootstrap-fixture"
        let config = try OnePieceCatalogBootstrapConfiguration(mode: .remoteValidationOnly,
            pinnedKeys: "\(keyID):\(key.publicKey.rawRepresentation.base64EncodedString())",
            baseURL: "https://catalog.scan-stash.com", collectionWrites: true)
        let envelope = try OnePieceCatalogSignature.sign(registry.verifiedRelease.release, keyID: keyID, privateKey: key)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnePieceValidationBootstrap-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = try XCTUnwrap(OnePieceCatalogBootstrap.runtime(configuration: config,
            seed: JSONEncoder().encode(envelope), root: root, now: now))
        let container = try CardGameRuntimeContainer(runtimes: [runtime])
        XCTAssertTrue(container.registry.enabledGames.isEmpty)
        XCTAssertTrue(container.registry.games(supporting: .browse).isEmpty)
        XCTAssertFalse(container.registry.supports(.onePiece, .collectionWrite))
        XCTAssertNotNil(runtime.activationSource)
    }
    private var now: Date { ISO8601DateFormatter().date(from: date)! }

    func testNoChangeRecoveryRetainsExistingActivationSource() async throws {
        let registry = try registry()
        let (_, storage) = try model(registry: registry)
        let base = OnePieceGameRuntime(registry: registry).runtime
        let source = OnePieceSnapshotTestSource(.init(revision: 1, catalog: base.catalog!,
            recognizer: base.recognizer!, variantPolicy: base.variantPolicy, priceAuthority: base.priceAuthority))
        let runtime = CardGameRuntime(descriptor: base.descriptor, variantPolicy: base.variantPolicy,
            catalog: base.catalog, activationSource: source, requiresLaunchActivation: false)
        let raw = try CardGameRuntimeContainer(runtimes: [runtime])
        let bound = try await raw.bound(to: storage)
        let initialReads = await source.snapshotReads
        let rebound = try await raw.bound(to: storage, recovering: bound)
        let finalReads = await source.snapshotReads
        XCTAssertEqual(initialReads, finalReads, "No-op retry must not rebind existing authorities")
        XCTAssertEqual(bound.runtime(for: .onePiece)?.catalog?.generation, rebound.runtime(for: .onePiece)?.catalog?.generation)
        XCTAssertEqual(bound.registry.games(supporting: .collectionWrite), rebound.registry.games(supporting: .collectionWrite))
        let scanner = rebound.makeScannerModel()
        XCTAssertTrue(scanner.canReloadCatalogs)
        scanner.setIdentificationInFlightForTesting(true)
        XCTAssertFalse(scanner.canReloadCatalogs)
        scanner.setIdentificationInFlightForTesting(false)
        XCTAssertTrue(scanner.canReloadCatalogs)
    }

    func testOptionalCatalogFailureLeavesExistingGamesAvailable() async throws {
        let registry = try registry()
        let (_, storage) = try model(registry: registry)
        let optional = CardGameRuntime(descriptor: OnePieceGameRuntime(registry: registry).runtime.descriptor,
            variantPolicy: OnePieceVariantPolicy(registry: registry),
            activationSource: OnePieceSnapshotTestSource(nil), requiresLaunchActivation: false)
        let raw = try CardGameRuntimeContainer(runtimes: [PokemonGameRuntime().runtime,
            MagicGameRuntime().runtime, optional])
        let bound = try await raw.bound(to: storage)
        XCTAssertNil(bound.runtime(for: .onePiece))
        XCTAssertEqual(bound.unavailableGames.map(\.game), [.onePiece])
        XCTAssertEqual(bound.registry.enabledGames, [.pokemon, .magic])
        XCTAssertNotNil(bound.runtime(for: .pokemon)?.catalog)
        XCTAssertNotNil(bound.runtime(for: .magic)?.catalog)
        XCTAssertNotNil(bound.runtime(for: .pokemon)?.pricing)
        XCTAssertNotNil(bound.runtime(for: .magic)?.pricing)

        let required = CardGameRuntime(descriptor: optional.descriptor, variantPolicy: optional.variantPolicy,
            activationSource: OnePieceSnapshotTestSource(nil))
        do {
            _ = try await CardGameRuntimeContainer(runtimes: [required]).bound(to: storage)
            XCTFail("Required catalog failure must still reject launch preparation")
        } catch { XCTAssertEqual(error as? PriceQuoteError, .providerUnavailable) }
    }

    func testOmittedCatalogCanRecoverAfterVerifiedActivationWithoutRelaunch() async throws {
        let registry = try registry()
        let (_, storage) = try model(registry: registry)
        let source = OnePieceSnapshotTestSource(nil)
        let base = OnePieceGameRuntime(registry: registry).runtime
        let optional = CardGameRuntime(descriptor: base.descriptor, variantPolicy: base.variantPolicy,
            pricing: base.pricing, recognizer: base.recognizer, catalog: base.catalog,
            browse: base.browse, importer: base.importer, activationSource: source,
            requiresLaunchActivation: false)
        let raw = try CardGameRuntimeContainer(runtimes: [PokemonGameRuntime().runtime, optional])
        let omitted = try await raw.bound(to: storage)
        XCTAssertEqual(omitted.unavailableGames.map(\.game), [.onePiece])
        let recovery = raw.optionalCatalogRecoveryEvents(for: [.onePiece])
        let recovered = expectation(description: "Verified activation recovers omitted runtime")
        let listener = Task {
            for await _ in recovery {
                do {
                    let rebound = try await raw.bound(to: storage, recovering: omitted)
                    XCTAssertTrue(rebound.unavailableGames.isEmpty)
                    XCTAssertNotNil(rebound.runtime(for: .onePiece)?.pricing)
                    XCTAssertTrue(rebound.registry.supports(.onePiece, .scan))
                    XCTAssertFalse(rebound.registry.supports(.onePiece, .collectionWrite))
                } catch { XCTFail("Recovery binding failed: \(error)") }
                recovered.fulfill()
                break
            }
        }
        defer { listener.cancel() }
        await source.update(.init(revision: 1, catalog: OnePieceCatalogAdapter(registry: registry),
            recognizer: OnePieceRecognitionAdapter(profile: .init(registry: registry)),
            variantPolicy: base.variantPolicy, priceAuthority: base.priceAuthority))
        await fulfillment(of: [recovered], timeout: 5)
    }

    func testConfigurationFailureIsVisibleWithoutEnablingUnsupportedGame() throws {
        let descriptor = try XCTUnwrap(CardGameRegistry.standard.descriptor(for: .onePiece))
        let raw = try CardGameRuntimeContainer(runtimes: [PokemonGameRuntime().runtime], unavailableGames: [descriptor])
        XCTAssertEqual(raw.unavailableGames.map(\.displayName), ["One Piece"])
        XCTAssertNil(raw.runtime(for: .onePiece))
        XCTAssertFalse(raw.registry.supports(.onePiece, .scan))
    }

    func testOnePieceCleanupFailureLeavesExistingGamesAvailable() async throws {
        let registry = try registry()
        let (_, storage) = try model(registry: registry)
        let raw = try CardGameRuntimeContainer(runtimes: [PokemonGameRuntime().runtime,
            MagicGameRuntime().runtime, OnePieceGameRuntime(registry: registry).runtime])
        let token = try CollectionWriteSerializer.beginExclusive(timeout: .mainThread)
        defer { CollectionWriteSerializer.endExclusive(token) }
        let bound = try await raw.bound(to: storage)
        XCTAssertNil(bound.runtime(for: .onePiece))
        XCTAssertEqual(bound.registry.enabledGames, [.pokemon, .magic])
        let snapshot = GameCatalogSnapshot(revision: 1, catalog: OnePieceCatalogAdapter(registry: registry),
            recognizer: OnePieceRecognitionAdapter(profile: .init(registry: registry)),
            variantPolicy: OnePieceVariantPolicy(registry: registry),
            priceAuthority: OnePiecePriceAdapter.priceAuthority(registry))
        let sourced = CardGameRuntime(descriptor: OnePieceGameRuntime(registry: registry).runtime.descriptor,
            variantPolicy: snapshot.variantPolicy, activationSource: OnePieceSnapshotTestSource(snapshot),
            requiresLaunchActivation: false)
        let withSource = try CardGameRuntimeContainer(runtimes: [PokemonGameRuntime().runtime,
            MagicGameRuntime().runtime, sourced])
        let sourceBound = try await withSource.bound(to: storage)
        XCTAssertNil(sourceBound.runtime(for: .onePiece))
        XCTAssertEqual(sourceBound.registry.enabledGames, [.pokemon, .magic])
        do {
            _ = try await raw.bound(to: storage, isCurrent: { false })
            XCTFail("An expired storage session must not produce a runtime")
        } catch { XCTAssertEqual(error as? PriceQuoteError, .providerUnavailable) }
    }

    func testCoordinatorSnapshotsFollowVerifiedGeneration() async throws {
        let first = try registry(complete: false)
        let second = try registry(complete: false, revision: 2, firstStatus: .quarantined)
        let key = Curve25519.Signing.PrivateKey(), keyID = "one-piece-snapshot-fixture"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnePieceSnapshot-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        func envelope(_ registry: OnePieceCatalogRegistry) throws -> OnePieceCatalogReleaseEnvelope {
            try OnePieceCatalogSignature.sign(registry.verifiedRelease.release, keyID: keyID, privateKey: key)
        }
        let store = try OnePieceCatalogReleaseStore(root: root, keys: [keyID: key.publicKey],
            bundledEnvelope: envelope(first), now: now)
        let coordinator = OnePieceCatalogCoordinator(store: store)
        let initial = await coordinator.currentSnapshot()
        for _ in 0..<10 {
            let repeated = await coordinator.currentSnapshot()
            XCTAssertEqual(repeated?.catalog.generation, first.generation)
            XCTAssertEqual(repeated?.priceAuthority?.identityByPriceKey, initial?.priceAuthority?.identityByPriceKey)
        }
        guard case .activated = await coordinator.activateEnvelope(try envelope(second), now: now) else {
            return XCTFail("New verified revision must activate")
        }
        let updated = await coordinator.currentSnapshot()
        XCTAssertEqual(updated?.revision, 2)
        XCTAssertEqual(updated?.browse?.generation, second.generation)
        XCTAssertEqual(initial?.catalog.generation, first.generation)
    }

    private func reviewedAwardRegistry() throws -> OnePieceCatalogRegistry {
        // Review data stays outside the app bundle and is never a production seed.
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("OnePieceCatalogCore/ReviewCorpus/english-stress")
        let decoder = JSONDecoder()
        let document = try decoder.decode(OnePieceRegistryDocument.self,
            from: Data(contentsOf: directory.appendingPathComponent("registry.json")))
        let observations = try ["observations.json", "tcgcsv-observations.json", "event-observations.json", "retail-observations.json", "starter-booster-observations.json", "base-market-observations.json"].flatMap {
            try decoder.decode([OnePieceSourceObservation].self, from: Data(contentsOf: directory.appendingPathComponent($0)))
        }
        let inventories = try ["inventories.json", "tcgcsv-inventories.json", "event-inventories.json", "retail-inventories.json", "starter-booster-inventories.json", "base-market-inventories.json"].flatMap {
            try decoder.decode([OnePieceSourceInventory].self, from: Data(contentsOf: directory.appendingPathComponent($0)))
        }
        let timestamp = "2026-10-04T17:00:00Z"
        let release = try OnePieceCatalogBuilder.build(registry: document, observations: observations,
            inventories: inventories, revision: 1, generatedAt: timestamp)
        let key = Curve25519.Signing.PrivateKey(), keyID = "one-piece-review-test"
        let envelope = try OnePieceCatalogSignature.sign(release, keyID: keyID, privateKey: key)
        return OnePieceCatalogRegistry(verifiedRelease: try OnePieceCatalogSignature.verify(envelope,
            trustedKeys: [keyID: key.publicKey], now: ISO8601DateFormatter().date(from: timestamp)!))
    }

    func testReviewedAwardCorpusResolvesSoleVerifiedPrintingAndKeepsUnverifiedParticipationUnowned() async throws {
        let registry = try reviewedAwardRegistry()
        let adapter = OnePieceCatalogAdapter(registry: registry)
        let profile = OnePieceScanProfile(registry: registry, languageConfirmation: .userConfirmedEnglish)
        guard case let .identified(subject) = profile.identify([.init(text: "P-001")]),
              case let .resolved(selected) = try await adapter.lookup(subject.identifier) else {
            return XCTFail("A sole verified printing should not require a picker")
        }
        XCTAssertEqual(selected.card.providerID, "348ad90a-43d8-49b5-a384-4d9cc2a1fe27")
        XCTAssertEqual(selected.card.variantEvidence.catalogVariants.map(\.id), ["foil"])
        XCTAssertThrowsError(try adapter.resolution(forPrintingID:
            UUID(uuidString: "603d83b0-146a-4229-8eaf-b2f884087312")!))
        let browse = OnePieceBrowseAdapter(registry: registry)
        let sets = try await browse.sets()
        XCTAssertEqual(sets.count, 52, "Entirely held products cannot expose Browse ownership targets")
        let page = try await browse.cards(in: try XCTUnwrap(sets.first {
            $0.catalogID.providerID == "event:2022-super-pre-release"
        }), cursor: nil)
        XCTAssertEqual(page.items.count, 1, "Unverified participation cannot become a Browse ownership target")
        XCTAssertNil(selected.card.thumbnailImageURL, "Review asset rights do not authorize app image distribution")
        XCTAssertTrue(registry.verifiedRelease.release.indexes.automaticCandidateIDsByCanonicalID.isEmpty)
        XCTAssertFalse(OnePieceGameRuntime(registry: registry).runtime.descriptor.capabilities.contains(.collectionWrite))
    }

    func testST10ReprintReviewUsesManufacturerEvidenceWithoutRetailerClaims() throws {
        let registry = try reviewedAwardRegistry()
        for (number, id) in [
            ("OP01-016", UUID(uuidString: "0ee1d219-5d9d-4a87-a159-acd9d1e19eb6")!),
            ("OP01-025", UUID(uuidString: "f7158b48-0c99-446a-ad49-477194cfaab9")!)
        ] {
            let printing = try XCTUnwrap(registry.printingByID[id])
            XCTAssertEqual(printing.canonicalCardID, "one-piece:en:\(number)")
            XCTAssertEqual(printing.status, .verified)
            XCTAssertEqual(printing.supportedVariantIDs, ["foil"])
            let evidence = try XCTUnwrap(printing.review?.evidence)
            let language = try XCTUnwrap(evidence.first { $0.kind == .language })
            let release = try XCTUnwrap(evidence.first { $0.kind == .release })
            XCTAssertTrue(language.detail.contains("no matching retailer card listing"))
            XCTAssertTrue(release.detail.contains("no matching retailer card listing"))
            XCTAssertFalse(language.detail.contains("retailer independently"))
            XCTAssertFalse(release.detail.contains("corroborated by the retailer"))

            let finish = try XCTUnwrap(evidence.first { $0.kind == .finish })
            let observation = try XCTUnwrap(registry.verifiedRelease.release.observations.first {
                $0.id == finish.observationID
            })
            XCTAssertEqual(observation.alias.provider, "bandai")
            XCTAssertEqual(observation.printedEvidence["sourceRole"], "manufacturer-product-finish-specification")
            XCTAssertEqual(observation.printedEvidence["finishVariantID"], "foil")
        }
    }

    func testOnePieceVariantCorrectionRejectsUnsupportedFinishBeforeMutatingCollection() throws {
        let verifiedRegistry = try registry()
        let adapter = OnePieceCatalogAdapter(registry: verifiedRegistry)
        let printingID = uuid(1).uuidString.lowercased()
        XCTAssertNoThrow(try adapter.validateVariantCorrection(printingID: printingID, variantID: "foil"))
        for invalidVariant in ["manga", nil] as [String?] {
            XCTAssertThrowsError(try adapter.validateVariantCorrection(
                printingID: printingID, variantID: invalidVariant
            ))
        }
        XCTAssertThrowsError(try adapter.validateVariantCorrection(
            printingID: "A0000000-0000-4000-8000-000000000001", variantID: "foil"
        ))
        let provisional = try self.registry(secondStatus: .provisional)
        XCTAssertThrowsError(try OnePieceCatalogAdapter(registry: provisional).validateVariantCorrection(
            printingID: uuid(2).uuidString.lowercased(), variantID: "foil"
        ))

        let (model, container) = try model(registry: verifiedRegistry)
        defer { model.viewDisappeared() }
        let policy = CardGameRegistry(descriptors: [
            .init(game: .onePiece, displayName: "Writable fixture", sortOrder: 0, capabilities: [.collectionWrite])
        ])
        CollectionStore.configureGames(policy, for: container)
        CollectionStore.configureCatalogAdapters(
            try .init(adapters: [adapter]), legacyCorrectionGames: [], for: container
        )
        let store = CollectionStore(context: container.mainContext)
        let card = try adapter.resolution(forPrintingID: uuid(1)).card
        let acquisition = try store.add(
            card, resolved: .init(variant: .normal, resolution: .userConfirmed)
        )
        let row = try XCTUnwrap(store.card(forKey: acquisition.collectionKey))
        let activityID = try XCTUnwrap(acquisition.activityID)
        let beforeActivities = try container.mainContext.fetch(FetchDescriptor<CollectionActivity>())
        let beforeEvents = try container.mainContext.fetch(FetchDescriptor<InventoryEvent>())
        let beforePriceKeys = try container.mainContext.fetch(FetchDescriptor<PriceRecord>()).map(\.key)
        CollectionStore.configureCatalogAdapters(
            try .init(adapters: []), legacyCorrectionGames: [], for: container
        )
        let supported = ResolvedVariant(variant: .foil, resolution: .userConfirmed)
        XCTAssertThrowsError(try store.recordVariantCorrection(
            for: row, to: supported, activityID: activityID, quantity: 1
        ))
        CollectionStore.configureCatalogAdapters(
            try .init(adapters: [adapter]), legacyCorrectionGames: [], for: container
        )
        let unsupported = ResolvedVariant(
            variant: .init(id: "manga", label: "Manga"), resolution: .userConfirmed
        )
        XCTAssertThrowsError(try store.recordVariantCorrection(
            for: row, to: unsupported, activityID: activityID, quantity: 1
        ))
        XCTAssertThrowsError(try store.recordVariantCorrection(
            for: row, to: unsupported,
            claims: [.init(activityID: activityID, quantity: 1)],
            source: .correction, mode: .visibleCorrection
        ))
        let unchanged = try XCTUnwrap(store.card(forKey: acquisition.collectionKey))
        XCTAssertEqual(unchanged.quantity, 1)
        XCTAssertEqual(unchanged.variantID, "normal")
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<CollectionActivity>()).map(\.id),
                       beforeActivities.map(\.id))
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<InventoryEvent>()).map(\.id),
                       beforeEvents.map(\.id))
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PriceRecord>()).map(\.key), beforePriceKeys)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PriceObservation>()).isEmpty)
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "10000000-0000-4000-8000-%012x", value))!
    }

#if DEBUG && LOCAL_ONLY_SIGNING
    func testRealLocalReviewScanChoiceCollectionRelaunchAndCSVBaseCase() async throws {
        let reviewed = try reviewedAwardRegistry()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnePieceBaseCase-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = Curve25519.Signing.PrivateKey()
        let envelope = try OnePieceCatalogSignature.sign(reviewed.verifiedRelease.release,
            keyID: "one-piece-local-review", privateKey: key)
        let seed = root.appendingPathComponent("review-seed.json")
        try JSONEncoder().encode(envelope).write(to: seed)
        let runtime = try XCTUnwrap(OnePieceCatalogBootstrap.localReviewRuntime(arguments: [
            "app", "-one_piece_local_review", "-one_piece_review_seed", seed.path,
            "-one_piece_review_public_key", key.publicKey.rawRepresentation.base64EncodedString()
        ], now: reviewed.retrievedAt))
        XCTAssertNil(runtime.activationSource, "Local review performs no remote catalog update")
        let runtimes = try CardGameRuntimeContainer(runtimes: [runtime])
        let support = root.appendingPathComponent("OnePieceLocalReview", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let paths = CollectionStoragePaths.production(resolvedApplicationSupportURL: support)
        let container = try CollectionStorageBootstrapDependencies.makeContainer(paths: paths, mode: .onDevice)
        let recovery = UnresolvedScanStore(fileURL: support.appendingPathComponent("Scanner/unresolved-scans.json"))
        let model = ScannerViewModel(gameRegistry: runtimes.registry, priceQuoteService: runtimes.makePriceQuoteService(),
            catalog: runtimes.makeCardCatalog(), unresolvedScanStore: recovery)
        model.start(context: container.mainContext, startCamera: false, shouldRefreshMagicDirectory: false)
        defer { model.viewDisappeared() }
        guard case .identified(let subject) = OnePieceScanProfile(registry: reviewed).identify([.init(text: "P-001")]) else {
            return XCTFail("Real reviewed printed number should be recognized")
        }
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), subject, nil)
        let saved = await waitUntil { model.successCount == 1 }
        XCTAssertTrue(saved, "The sole verified printing and sole finish should save automatically")
        XCTAssertNil(model.pendingIdentityChoice)
        XCTAssertNil(model.pendingChoice)
        model.viewDisappeared()

        // Reopen the same disk stores through the app's on-device factory.
        let reopened = try CollectionStorageBootstrapDependencies.makeContainer(paths: paths, mode: .onDevice)
        let rows = try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>())
        let owned = try XCTUnwrap(rows.first)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(owned.providerID, "348ad90a-43d8-49b5-a384-4d9cc2a1fe27")
        XCTAssertEqual(owned.cardGame, .onePiece)
        XCTAssertEqual(owned.variant?.id, "foil")
        XCTAssertEqual(owned.quantity, 1)
        XCTAssertEqual(owned.cardNumber, "P-001")
        XCTAssertTrue(try reopened.mainContext.fetch(FetchDescriptor<PriceObservation>()).isEmpty)
        let plan = try CollectionCSV.parse(Data(CollectionCSV.export(rows).text.utf8))
        let entry = try XCTUnwrap(plan.entries.first)
        try runtimes.makeImportAdapters().validate(entry)
        XCTAssertEqual(entry.collectionKey, owned.collectionKey)
        XCTAssertEqual(entry.variant?.id, "foil")
        let browse = runtimes.makeBrowseCatalog()
        let sets = try await browse.sets(for: .onePiece)
        let set = try XCTUnwrap(sets.first { $0.catalogID.providerID == "event:2022-super-pre-release" })
        let page = try await browse.cards(in: set, cursor: nil)
        XCTAssertEqual(page.items.map(\.providerID), [owned.providerID])
    }
#endif

    func testFullCatalogSameNumberSameFinishPersistsSeparateOwnershipPricesAndCSV() async throws {
        let registry = try reviewedAwardRegistry()
        let number = "ST11-003"
        let originals = try XCTUnwrap(registry.printingsByCanonicalID["one-piece:en:" + number])
            .filter { $0.status == .verified }
        let mapped = try XCTUnwrap(originals.first { !$0.marketMappings.isEmpty })
        let unmapped = try XCTUnwrap(originals.first { $0.marketMappings.isEmpty })
        XCTAssertEqual(mapped.supportedVariantIDs, ["normal"])
        XCTAssertEqual(unmapped.supportedVariantIDs, ["normal"], "The finish must not hide a borrowed-printing quote")
        let source = OnePieceTestPriceSource()
        let runtimes = try acceptanceRuntimes(registry: registry, source: source)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnePieceRoundTrip-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = CollectionStoragePaths.production(resolvedApplicationSupportURL: root)
        let container = try CollectionStorageBootstrapDependencies.makeContainer(paths: paths, mode: .onDevice)
        runtimes.configureCollectionAuthority(for: container)
        let model = ScannerViewModel(gameRegistry: runtimes.registry, priceQuoteService: runtimes.makePriceQuoteService(),
            catalog: runtimes.makeCardCatalog(), unresolvedScanStore: UnresolvedScanStore(fileURL: root.appendingPathComponent("recovery.json")))
        model.start(context: container.mainContext, startCamera: false, shouldRefreshMagicDirectory: false)
        defer { model.viewDisappeared() }
        guard case let .identified(subject) = OnePieceScanProfile(registry: registry).identify([.init(text: number)]) else {
            return XCTFail("Retained Uta number must be recognized")
        }
        for (index, printing) in [mapped, unmapped].enumerated() {
            model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), subject, nil)
            let presented = await waitUntil { model.pendingIdentityChoice != nil }
            XCTAssertTrue(presented)
            let choices = try XCTUnwrap(model.pendingIdentityChoice).displayCandidates
            XCTAssertEqual(Set(choices.map(\.id)), Set(originals.map { $0.id.uuidString.lowercased() }))
            model.choose(try XCTUnwrap(choices.first { $0.id == printing.id.uuidString.lowercased() }))
            let saved = await waitUntil { model.successCount == index + 1 && !model.isIdentificationProcessingForTesting }
            XCTAssertTrue(saved)
            XCTAssertNil(model.pendingChoice, "Both exact printings have one supported finish")
        }
        let mappedKey = PriceRecord.key(game: .onePiece, printingID: mapped.id.uuidString.lowercased(), variantID: "normal")
        let unmappedKey = PriceRecord.key(game: .onePiece, printingID: unmapped.id.uuidString.lowercased(), variantID: "normal")
        let priced = await waitUntil {
            PriceStore(context: ModelContext(container)).record(forKey: mappedKey)?.effectiveUnitMarketPriceUSD == 8.16
        }
        XCTAssertTrue(priced)
        model.viewDisappeared()

        // Reopen the production on-device factory's disk stores, then run the
        // same stored-printing refresh lane used by Collection.
        let reopened = try CollectionStorageBootstrapDependencies.makeContainer(paths: paths, mode: .onDevice)
        runtimes.configureCollectionAuthority(for: reopened)
        let rows = try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.map(\.providerID)), Set([mapped, unmapped].map { $0.id.uuidString.lowercased() }))
        XCTAssertEqual(Set(rows.map(\.collectionKey)).count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.quantity == 1 && $0.variantID == "normal" && $0.cardNumber == number })
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<InventoryEvent>()).map(\.deltaQuantity).sorted(), [1, 1])
        let retainedQuote = try XCTUnwrap(PriceStore(context: reopened.mainContext).record(forKey: mappedKey))
        XCTAssertEqual(retainedQuote.effectiveUnitMarketPriceUSD, 8.16)
        // A freshly checked mapped quote is deliberately skipped by refresh.
        // Age only its check timestamp to exercise the actual overdue lane.
        retainedQuote.lastCheckedAt = Date.now.addingTimeInterval(-PriceRefreshController.automaticRefreshInterval - 1)
        try reopened.mainContext.save()
        let refresh = PriceRefreshModelActor(modelContainer: reopened)
        await refresh.configureGamePricing(.init(registry: runtimes.registry,
            adapters: try .init(adapters: [OnePiecePriceAdapter(registry: registry, source: source)])))
        _ = await refresh.run(.init(usesPriceFallback: false, includeImported: true, forceUnsupportedRetry: true,
            sortOldestFirst: false, maximumTargetCount: nil, markRecentlyCheckedIfEmpty: false),
            progress: { _ in }, shouldContinue: nil)
        let prices = PriceStore(context: ModelContext(reopened))
        XCTAssertEqual(prices.record(forKey: mappedKey)?.effectiveUnitMarketPriceUSD, 8.16)
        XCTAssertNil(prices.record(forKey: unmappedKey)?.effectiveUnitMarketPriceUSD)
        let calls = await source.calls
        XCTAssertEqual(calls, 2, "Only the mapped printing may fetch, once on scan and once on refresh")

        let browse = runtimes.makeBrowseCatalog()
        let sets = try await browse.sets(for: .onePiece)
        var browseAddCard: IdentifiedCard?
        for printing in [mapped, unmapped] {
            let set = try XCTUnwrap(sets.first { $0.catalogID.providerID == printing.releaseID })
            let page = try await browse.cards(in: set, cursor: nil)
            let summary = try XCTUnwrap(page.items.first { $0.providerID == printing.id.uuidString.lowercased() })
            let details = try await browse.details(for: summary)
            XCTAssertEqual(details.card.providerID, printing.id.uuidString.lowercased())
            XCTAssertEqual(details.card.cardNumber, number)
            if printing.id == unmapped.id { browseAddCard = details.card }
        }
        let plan = try CollectionCSV.parse(Data(CollectionCSV.export(rows).text.utf8))
        XCTAssertEqual(plan.entries.count, 2)
        let importRoot = root.appendingPathComponent("CSV", isDirectory: true)
        try FileManager.default.createDirectory(at: importRoot, withIntermediateDirectories: true)
        let imported = try CollectionStorageBootstrapDependencies.makeContainer(
            paths: .production(resolvedApplicationSupportURL: importRoot), mode: .onDevice)
        runtimes.configureCollectionAuthority(for: imported)
        let result = try CollectionCSV.apply(plan, to: imported.mainContext, gameRegistry: runtimes.registry,
                                            gameImportAdapters: runtimes.makeImportAdapters())
        XCTAssertEqual(result.importedQuantity, 2)
        XCTAssertTrue(result.failedRows.isEmpty)
        let restored = try imported.mainContext.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(Set(restored.map(\.collectionKey)), Set(rows.map(\.collectionKey)))
        XCTAssertEqual(Set(restored.map(\.priceKey)), Set(rows.map(\.priceKey)))
        XCTAssertTrue(restored.allSatisfy { $0.quantity == 1 && $0.variantID == "normal" })
        XCTAssertNil(PriceStore(context: imported.mainContext).record(forKey: unmappedKey)?.effectiveUnitMarketPriceUSD)
        // Add the later printing through the same exact detail card and store
        // API used by Browse. It must merge only that UUID's owned position.
        _ = try CollectionStore(context: imported.mainContext).add(try XCTUnwrap(browseAddCard),
            resolved: .init(variant: .normal, resolution: .uniqueInCatalog))
        let afterBrowse = try imported.mainContext.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(afterBrowse.count, 2)
        XCTAssertEqual(afterBrowse.first { $0.providerID == unmapped.id.uuidString.lowercased() }?.quantity, 2)
        XCTAssertEqual(afterBrowse.first { $0.providerID == mapped.id.uuidString.lowercased() }?.quantity, 1)
        XCTAssertNil(PriceStore(context: imported.mainContext).record(forKey: unmappedKey)?.effectiveUnitMarketPriceUSD)
    }

    func testFullCatalogEligibilityAndFinishesAgreeAcrossScanBrowseAndCSV() async throws {
        let registry = try reviewedAwardRegistry()
        let adapter = OnePieceCatalogAdapter(registry: registry)
        let browse = OnePieceBrowseAdapter(registry: registry)
        let profile = OnePieceScanProfile(registry: registry)
        let eligible = registry.printingByID.values.filter { $0.status == .verified && $0.language == "en" }
        let expectedIDs = Set(eligible.map { $0.id.uuidString.lowercased() })
        var cardsByID: [String: ResolvedCatalogCard] = [:]
        for set in try await browse.sets() {
            var cursor: String?
            repeat {
                let page = try await browse.cards(in: set, cursor: cursor)
                for summary in page.items {
                    XCTAssertTrue(expectedIDs.contains(summary.providerID), "Browse must not admit held printings")
                    let details = try await browse.details(for: summary)
                    XCTAssertEqual(details.card.physicalPrintingID, summary.providerID)
                    let printing = try XCTUnwrap(UUID(uuidString: summary.providerID).flatMap { registry.printingByID[$0] })
                    XCTAssertEqual(Set(details.card.variantEvidence.catalogVariants.map(\.id)), Set(printing.supportedVariantIDs))
                    cardsByID[summary.providerID] = details.card
                }
                cursor = page.nextCursor
            } while cursor != nil
        }
        XCTAssertEqual(Set(cardsByID.keys), expectedIDs, "Every eligible printing must remain reachable in Browse")
        for canonical in registry.canonicalByPrintedNumber.values {
            let printings = (registry.printingsByCanonicalID[canonical.id] ?? []).filter { $0.status == .verified }
            guard case let .identified(subject) = profile.identify([.init(text: canonical.printedNumber)]) else {
                return XCTFail("Catalog number \(canonical.printedNumber) must remain recognizable")
            }
            switch try await adapter.lookup(subject.identifier) {
            case let .resolved(resolution):
                XCTAssertEqual(printings.count, 1)
                XCTAssertEqual(resolution.card.physicalPrintingID, printings.first?.id.uuidString.lowercased())
                XCTAssertFalse(resolution.card.variantEvidence.catalogVariants.isEmpty)
            case let .needsPrintingChoice(_, candidates):
                XCTAssertGreaterThan(printings.count, 1)
                XCTAssertEqual(Set(candidates.map(\.id)), Set(printings.map { $0.id.uuidString.lowercased() }))
                XCTAssertTrue(candidates.allSatisfy { $0.selectionEvidence(among: candidates) != .insufficient },
                              "Verified choices must carry a usable collector distinction")
            case .catalogIncomplete:
                XCTAssertTrue(printings.isEmpty, "Held-only numbers must remain retryable and unowned")
            }
        }
        for printing in registry.printingByID.values where printing.status != .verified || printing.language != "en" {
            XCTAssertThrowsError(try adapter.resolution(forPrintingID: printing.id))
        }
        let rows = cardsByID.values.flatMap { card in
            card.variantEvidence.catalogVariants.map { finish in
                CollectedCard(card: card, resolved: .init(variant: finish, resolution: .userConfirmed))
            }
        }
        let plan = try CollectionCSV.parse(Data(CollectionCSV.export(rows).text.utf8))
        XCTAssertEqual(plan.entries.count, rows.count)
        XCTAssertEqual(plan.skippedRows, 0)
        let importer = OnePieceImportAdapter(registry: registry)
        for entry in plan.entries { XCTAssertNoThrow(try importer.validate(entry)) }
    }

    func testFullCatalogPrintingSkipSurvivesRecoveryRelaunchAndRetriesExactChoice() async throws {
        let registry = try reviewedAwardRegistry()
        let runtimes = try acceptanceRuntimes(registry: registry, source: OnePieceTestPriceSource())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnePieceSkippedChoice-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("recovery.json")
        let recovery = UnresolvedScanStore(fileURL: file)
        let (first, container) = try model(registry: registry, fixtureWritesEnabled: true, unresolvedScanStore: recovery)
        defer { first.viewDisappeared() }
        guard case let .identified(subject) = OnePieceScanProfile(registry: registry).identify([.init(text: "ST11-003")]) else {
            return XCTFail()
        }
        first.scanner.onConfirmedSubjectCandidate?(nil, UUID(), subject, nil)
        let presented = await waitUntil { first.pendingIdentityChoice != nil }
        XCTAssertTrue(presented)
        first.dismissIdentityChoice()
        let skipped = try XCTUnwrap(first.unresolvedScans.first)
        XCTAssertEqual(first.successCount, 0)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
        // Explicitly flush the same store used by scanner persistence before
        // constructing a new model, without relying on a filesystem delay.
        let flushed = await recovery.save(first.unresolvedScans)
        XCTAssertTrue(flushed)
        first.viewDisappeared()
        let (second, secondContainer) = try model(registry: registry, fixtureWritesEnabled: true,
            unresolvedScanStore: UnresolvedScanStore(fileURL: file))
        defer { second.viewDisappeared() }
        let loaded = await waitUntil { second.unresolvedScans.contains { $0.id == skipped.id && !$0.isReadOnly } }
        XCTAssertTrue(loaded)
        second.resolveUnresolved(id: skipped.id, choice: .retryLookup)
        let retryPresented = await waitUntil { second.pendingIdentityChoice != nil }
        XCTAssertTrue(retryPresented)
        let printing = try XCTUnwrap(registry.printingsByCanonicalID["one-piece:en:ST11-003"]?.first {
            $0.status == .verified && $0.marketMappings.isEmpty
        })
        second.choose(try XCTUnwrap(second.pendingIdentityChoice?.displayCandidates.first {
            $0.id == printing.id.uuidString.lowercased()
        }))
        let saved = await waitUntil { second.successCount == 1 && second.unresolvedScans.isEmpty }
        XCTAssertTrue(saved)
        let owned = try XCTUnwrap(secondContainer.mainContext.fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(owned.providerID, printing.id.uuidString.lowercased())
        XCTAssertEqual(owned.quantity, 1)
        XCTAssertNil(PriceStore(context: secondContainer.mainContext).record(forKey: owned.priceKey)?.effectiveUnitMarketPriceUSD)
        try runtimes.makeImportAdapters().validate(try XCTUnwrap(
            CollectionCSV.parse(Data(CollectionCSV.export([owned]).text.utf8)).entries.first))
    }

    func testEncounterDuringRecoveryLoadingMergesEarlierWorkWithoutFalseSaveFailure() async throws {
        let registry = try registry()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnePieceRecoveryStartup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("recovery.json")
        let profile = OnePieceScanProfile(registry: registry)
        guard case let .identified(earlierSubject) = profile.identify([.init(text: "OP99-998")]),
              case let .identified(newSubject) = profile.identify([.init(text: "OP99-999")]) else { return XCTFail() }
        let earlier = UnresolvedScan(subject: earlierSubject, reason: .noCatalogEntry)
        let seed = UnresolvedScanStore(fileURL: file)
        let seeded = await seed.save([earlier])
        XCTAssertTrue(seeded)
        let gate = OnePieceRecoveryReadGate()
        defer { gate.resume() }
        let store = UnresolvedScanStore(fileURL: file, readData: { try gate.read($0) })
        let (model, container) = try model(registry: registry, fixtureWritesEnabled: true, unresolvedScanStore: store)
        defer { model.viewDisappeared() }
        let loading = await waitUntil { gate.hasStarted }
        XCTAssertTrue(loading)
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), newSubject, nil)
        let encountered = await waitUntil { model.unresolvedScans.contains { $0.displayIdentifier == "OP99-999" } }
        XCTAssertTrue(encountered)
        // A second catalog-driven reload must not invalidate the first load's
        // merge token or let an early save overwrite the retained backlog.
        let secondReload = Task { await model.reloadUnresolvedScansForTesting() }
        await Task.yield()
        gate.resume()
        await secondReload.value
        await model.waitForUnresolvedPersistenceForTesting()
        XCTAssertEqual(Set(model.unresolvedScans.map(\.displayIdentifier)), ["OP99-998", "OP99-999"])
        XCTAssertFalse(model.note?.text.contains("could not be saved") ?? false)
        let reopened = await UnresolvedScanStore(fileURL: file).load(
            gameCatalogAdapters: try .init(adapters: [OnePieceCatalogAdapter(registry: registry)]))
        XCTAssertEqual(Set(reopened.map(\.displayIdentifier)), ["OP99-998", "OP99-999"])
        XCTAssertTrue(reopened.contains { $0.id == earlier.id })
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
    }

    func testDismissalDuringRecoveryReloadCannotResurrectPersistedEncounter() async throws {
        let registry = try registry()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnePieceRecoveryDismissal-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("recovery.json")
        let profile = OnePieceScanProfile(registry: registry)
        guard case let .identified(subject) = profile.identify([.init(text: "OP99-999")]) else { return XCTFail() }
        let earlier = UnresolvedScan(subject: subject, reason: .noCatalogEntry)
        let seeded = await UnresolvedScanStore(fileURL: file).save([earlier])
        XCTAssertTrue(seeded)
        let gate = OnePieceRecoveryReadGate(blockedRead: 2)
        defer { gate.resume() }
        let store = UnresolvedScanStore(fileURL: file, readData: { try gate.read($0) })
        let (model, _) = try model(registry: registry, fixtureWritesEnabled: true, unresolvedScanStore: store)
        defer { model.viewDisappeared() }
        let loaded = await waitUntil { model.unresolvedScans.contains { $0.id == earlier.id } }
        XCTAssertTrue(loaded)
        await model.waitForUnresolvedPersistenceForTesting()
        let reload = Task { await model.reloadUnresolvedScansForTesting() }
        let blocked = await waitUntil { gate.hasStarted }
        XCTAssertTrue(blocked)
        model.dismissUnresolved(id: earlier.id)
        gate.resume()
        await reload.value
        await model.waitForUnresolvedPersistenceForTesting()
        XCTAssertTrue(model.unresolvedScans.isEmpty)
        let reopened = await UnresolvedScanStore(fileURL: file).load()
        XCTAssertTrue(reopened.isEmpty)
        XCTAssertFalse(model.note?.text.contains("could not be saved") ?? false)
    }

    private func acceptanceRuntimes(registry: OnePieceCatalogRegistry, source: any OnePieceMarketPriceSource) throws -> CardGameRuntimeContainer {
        try CardGameRuntimeContainer(runtimes: [.init(
            descriptor: .init(game: .onePiece, displayName: "One Piece", sortOrder: 0,
                              capabilities: [.scan, .browse, .pricing, .collectionWrite]),
            variantPolicy: OnePieceVariantPolicy(registry: registry),
            pricing: OnePiecePriceAdapter(registry: registry, source: source),
            recognizer: OnePieceRecognitionAdapter(profile: .init(registry: registry)),
            catalog: OnePieceCatalogAdapter(registry: registry), browse: OnePieceBrowseAdapter(registry: registry),
            importer: OnePieceImportAdapter(registry: registry), priceAuthority: OnePiecePriceAdapter.priceAuthority(registry))])
    }

    func testRealRetailNamiBaseCaseUsesProductPrintingAndManufacturerFoil() async throws {
        let reviewed = try reviewedAwardRegistry()
        let product = "product:premium-card-collection-film-red-2023"
        let retail = reviewed.printingByID.values.filter { $0.releaseID == product }
        XCTAssertEqual(retail.count, 12)
        XCTAssertTrue(retail.allSatisfy { $0.status == .verified && $0.supportedVariantIDs == ["foil"] })
        let nami = try XCTUnwrap(retail.first { $0.canonicalCardID == "one-piece:en:ST01-007" })
        let browse = OnePieceBrowseAdapter(registry: reviewed)
        let sets = try await browse.sets()
        let retailSet = try XCTUnwrap(sets.first { $0.catalogID.providerID == product })
        XCTAssertEqual(retailSet.code, "Premium Card Collection · FILM RED")
        let page = try await browse.cards(in: retailSet, cursor: nil)
        let summary = try XCTUnwrap(page.items.first { $0.providerID == nami.id.uuidString.lowercased() })
        XCTAssertEqual(summary.setCode, "ST01")
        XCTAssertEqual(summary.collectorNumber, "ST01-007")
        let details = try await browse.details(for: summary)
        XCTAssertEqual(details.card.providerID, summary.providerID)
        let (model, container) = try model(registry: reviewed, fixtureWritesEnabled: true)
        defer { model.viewDisappeared() }
        guard case .identified(let subject) = OnePieceScanProfile(registry: reviewed).identify([.init(text: "ST01-007")]) else {
            return XCTFail("Retail Nami number must be recognized")
        }
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), subject, nil)
        let saved = await waitUntil { model.successCount == 1 }
        XCTAssertTrue(saved)
        XCTAssertNil(model.pendingIdentityChoice)
        XCTAssertNil(model.pendingChoice)
        let owned = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(owned.providerID, nami.id.uuidString.lowercased())
        XCTAssertEqual(owned.variant?.id, "foil")
        XCTAssertEqual(owned.cardNumber, "ST01-007")
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PriceObservation>()).isEmpty)
    }

    func testRealStandardStarterAndBoosterScanChoiceFinishAndCollectionBaseCases() async throws {
        let reviewed = try reviewedAwardRegistry()
        let rows: [(String, String, String)] = [
            ("ST01-003", "product:st01-straw-hat-crew-2022", "normal"),
            ("ST01-012", "product:st01-straw-hat-crew-2022", "foil"),
            ("OP01-120", "product:op01-romance-dawn-2022", "foil"),
            ("ST02-001", "product:st02-worst-generation-2022", "foil"),
            ("ST03-008", "product:st03-seven-warlords-2022", "normal"),
            ("ST04-005", "product:st04-animal-kingdom-pirates-2022", "normal"),
            ("OP02-004", "product:op02-paramount-war-2023", "foil"),
            ("ST05-002", "product:st05-film-edition-2023", "normal"),
            ("ST06-001", "product:st06-absolute-justice-2023", "foil"),
            ("ST07-002", "product:st07-big-mom-pirates-2023", "normal"),
            ("ST08-001", "product:st08-monkey-d-luffy-2023", "foil"),
            ("ST09-002", "product:st09-yamato-2023", "normal"),
            ("OP03-003", "product:op03-pillars-of-strength-2023", "foil"),
            ("ST10-005", "product:st10-three-captains-2023", "foil"),
            ("OP01-016", "product:st10-three-captains-2023", "foil"),
            ("OP04-083", "product:op04-kingdoms-of-intrigue-2023", "foil"),
            ("OP05-119", "product:op05-awakening-of-the-new-era-2023", "foil"),
            ("ST11-001", "product:st11-uta-2024", "foil"),
            ("ST12-003", "product:st12-zoro-and-sanji-2024", "foil"),
            ("ST13-001", "product:st13-st-13-ultra-deck-the-three-brothers-2024", "foil"),
            ("OP17-001", "product:op17-the-world-s-strongest-warriors-2026", "normal"),
            ("EB03-001", "product:eb03-extra-booster-one-piece-heroines-edition-2026", "foil"),
            ("EB04-002", "product:op15-adventure-on-kami-s-island-2026", "foil"),
            ("PRB01-001", "product:prb01-one-piece-card-the-best-2024", "normal"),
            ("PRB02-001", "product:prb02-premium-booster-the-best-vol-2-2025", "foil")
        ]
        for (number, product, finish) in rows {
            let (model, container) = try model(registry: reviewed, fixtureWritesEnabled: true)
            defer { model.viewDisappeared() }
            let printing = try XCTUnwrap(reviewed.printingByID.values.first {
                $0.canonicalCardID == "one-piece:en:" + number && $0.releaseID == product
            })
            guard case let .identified(subject) = OnePieceScanProfile(registry: reviewed).identify([.init(text: number)]) else {
                return XCTFail("Standard card number must be recognized")
            }
            model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), subject, nil)
            let resolvedOrChoice = await waitUntil { model.successCount == 1 || model.pendingIdentityChoice != nil }
            XCTAssertTrue(resolvedOrChoice)
            let verified = reviewed.printingsByCanonicalID[printing.canonicalCardID]?.filter { $0.status == .verified } ?? []
            if verified.count > 1 {
                let candidate = try XCTUnwrap(model.pendingIdentityChoice?.displayCandidates.first {
                    $0.id == printing.id.uuidString.lowercased()
                })
                XCTAssertEqual(candidate.treatmentLabel, "Standard artwork")
                model.choose(candidate)
            } else {
                XCTAssertNil(model.pendingIdentityChoice)
            }
            let saved = await waitUntil { model.successCount == 1 }
            XCTAssertTrue(saved)
            let owned = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<CollectedCard>()).first)
            XCTAssertEqual(owned.providerID, printing.id.uuidString.lowercased())
            XCTAssertEqual(owned.variant?.id, finish)
            XCTAssertEqual(owned.cardNumber, number)
            XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PriceObservation>()).isEmpty)
        }
        let browse = OnePieceBrowseAdapter(registry: reviewed)
        let sets = try await browse.sets()
        for (product, count) in [("product:st01-straw-hat-crew-2022", 10), ("product:op01-romance-dawn-2022", 59),
                                ("product:st02-worst-generation-2022", 9), ("product:st03-seven-warlords-2022", 8),
                                ("product:st04-animal-kingdom-pirates-2022", 7),
                                ("product:op02-paramount-war-2023", 119), ("product:st05-film-edition-2023", 17),
                                ("product:st06-absolute-justice-2023", 17), ("product:st07-big-mom-pirates-2023", 17),
                                ("product:st08-monkey-d-luffy-2023", 15), ("product:st09-yamato-2023", 15),
                                ("product:op03-pillars-of-strength-2023", 121), ("product:st10-three-captains-2023", 19),
                                ("product:op04-kingdoms-of-intrigue-2023", 119),
                                ("product:op05-awakening-of-the-new-era-2023", 118),
                                ("product:st11-uta-2024", 5), ("product:st12-zoro-and-sanji-2024", 4)] {
            let set = try XCTUnwrap(sets.first { $0.catalogID.providerID == product })
            XCTAssertEqual(set.cardCount, count)
        }
        let leader = try XCTUnwrap(reviewed.printingByID.values.first {
            $0.canonicalCardID == "one-piece:en:ST01-001"
        })
        XCTAssertThrowsError(try OnePieceCatalogAdapter(registry: reviewed).resolution(forPrintingID: leader.id))
    }

    func testMissingStarterFinishEvidenceCannotBecomeAnOwnedPrinting() async throws {
        let reviewed = try reviewedAwardRegistry()
        let adapter = OnePieceCatalogAdapter(registry: reviewed)
        let browse = OnePieceBrowseAdapter(registry: reviewed)
        let sets = try await browse.sets()
        for (number, product, hasVerifiedSiblings) in [("ST12-002", "product:st12-zoro-and-sanji-2024", true),
                                  ("OP02-028", "product:st11-uta-2024", true),
                                  ("ST31-001", "product:st31-st-31-starter-deck-31-red-monkey-d-luffy-2026", false),
                                  ("ST30-001", "product:st30-st-30-starter-deck-30-ex-luffy-ace-2026", false)] {
            let printing = try XCTUnwrap(reviewed.printingByID.values.first {
                $0.canonicalCardID == "one-piece:en:" + number && $0.releaseID == product
            })
            XCTAssertEqual(printing.status, .provisional)
            XCTAssertTrue(printing.supportedVariantIDs.isEmpty)
            XCTAssertThrowsError(try adapter.resolution(forPrintingID: printing.id))
            let set = sets.first { $0.catalogID.providerID == product }
            XCTAssertEqual(set != nil, hasVerifiedSiblings)
            if let set {
                let page = try await browse.cards(in: set, cursor: nil)
                XCTAssertFalse(page.items.contains { $0.providerID == printing.id.uuidString.lowercased() })
            }
        }
    }

    func testExactOnePiecePricingDoesNotBorrowAnotherPrintingOrFinish() async throws {
        let registry = try registry(withMarketMapping: true)
        let source = OnePieceTestPriceSource()
        let adapter = OnePiecePriceAdapter(registry: registry, source: source)
        let card = try OnePieceCatalogAdapter(registry: registry).resolution(forPrintingID: uuid(1)).card
        let quote = try await adapter.refresh(.init(identity: .legacy(card), variant: .foil,
            pokemonPrintRun: nil, catalogRefreshOverride: nil))
        guard case let .price(price) = quote else { return XCTFail("Mapped foil must receive its exact quote") }
        XCTAssertEqual(price.unitMarketPriceUSD, 8.16)
        let normal = try await adapter.refreshStoredPrinting(card.providerID, variant: .normal)
        XCTAssertEqual(normal, .unavailable(nil))
        let other = try await adapter.refreshStoredPrinting(uuid(2).uuidString.lowercased(), variant: .foil)
        XCTAssertEqual(other, .unavailable(nil))
        let calls = await source.calls
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(adapter.allowsProviderFallback)
        do {
            _ = try await adapter.refresh(.init(identity: .init(game: .onePiece, printingID: card.providerID,
                setID: card.setID, displaySetCode: card.setCode, cardNumber: "OP01-001", language: "en"),
                variant: .foil, pokemonPrintRun: nil, catalogRefreshOverride: nil))
            XCTFail("Wrong printed identity must fail")
        } catch PriceQuoteError.identityMismatch {}
    }

    func testBrowseGridUsesExactOnePiecePriceAdapter() async throws {
        let registry = try registry(withMarketMapping: true)
        let gameRegistry = try CardGameRuntimeContainer(runtimes: [OnePieceGameRuntime(registry: registry).runtime]).registry
        let source = OnePieceTestPriceSource()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = CatalogCacheStore(root: root)
        let catalog = BrowseCatalog(cache: cache,
            gameRegistry: gameRegistry,
            gameBrowseAdapters: try .init(adapters: [OnePieceBrowseAdapter(registry: registry)]),
            priceQuoteService: PriceQuoteService(registry: gameRegistry,
                adapters: try .init(adapters: [OnePiecePriceAdapter(registry: registry, source: source)])))
        let sets = try await catalog.sets(for: .onePiece)
        let set = try XCTUnwrap(sets.first { $0.catalogID.providerID == "fixture-release-0" })
        let page = try await catalog.cards(in: set, cursor: nil)
        let summary = try XCTUnwrap(page.items.first)
        await cache.storeSortPrices([summary.id: 999], for: set.id)
        var prices: [String: Double] = [:]
        for await update in catalog.sortPriceUpdates(for: [summary]) { prices = update.prices }
        XCTAssertEqual(prices[summary.id], 8.16)
        let normal = try await catalog.price(for: summary, variant: .normal)
        XCTAssertEqual(normal, .unavailable(nil))
        let quote = try await catalog.price(for: summary, variant: .foil)
        guard case let .price(price) = quote else { return XCTFail("Details must use the same mapped foil") }
        XCTAssertEqual(price.unitMarketPriceUSD, prices[summary.id])
    }

    func testOnePieceCollectionRefreshPersistsExactMappedQuoteWithoutVendorFallback() async throws {
        let registry = try registry(withMarketMapping: true)
        let source = OnePieceTestPriceSource()
        let runtime = OnePieceGameRuntime(registry: registry, capabilities: [.scan, .browse, .pricing, .collectionWrite]).runtime
        let runtimes = try CardGameRuntimeContainer(runtimes: [runtime])
        let (_, container) = try model(registry: registry)
        runtimes.configureCollectionAuthority(for: container)
        let card = try OnePieceCatalogAdapter(registry: registry).resolution(forPrintingID: uuid(1)).card
        _ = try CollectionStore(context: container.mainContext).add(card, resolved: .init(variant: .foil, resolution: .userConfirmed))
        let worker = PriceRefreshModelActor(modelContainer: container)
        await worker.configureGamePricing(.init(registry: runtimes.registry,
            adapters: try .init(adapters: [OnePiecePriceAdapter(registry: registry, source: source)])))
        _ = await worker.run(.init(usesPriceFallback: false, includeImported: true, forceUnsupportedRetry: true,
            sortOldestFirst: false, maximumTargetCount: nil, markRecentlyCheckedIfEmpty: false),
            progress: { _ in }, shouldContinue: nil)
        let context = ModelContext(container)
        let record = try XCTUnwrap(PriceStore(context: context).record(forKey:
            PriceRecord.key(game: .onePiece, printingID: card.providerID, variantID: "foil")))
        XCTAssertEqual(record.effectiveUnitMarketPriceUSD, 8.16)
        XCTAssertEqual(record.sourceRaw, PriceSource.tcgCSV.rawValue)
        XCTAssertEqual(record.sourceVariantID, "tcgplayer:454664:Foil")
    }

    func testOnePieceTCGCSVExactLaneAndDailyCache() async throws {
        let registry = try registry(withMarketMapping: true)
        let mapping = try XCTUnwrap(registry.printingByID[uuid(1)]?.marketMappings.first)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OnePiecePriceTestProtocol.self]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OnePiecePrice-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory); OnePiecePriceTestProtocol.handler = nil }
        OnePiecePriceTestProtocol.handler = { request in
            let json = request.url!.lastPathComponent == "products"
                ? #"{"success":true,"errors":[],"results":[{"productId":454664,"categoryId":68,"groupId":3188,"name":"Shanks","extendedData":[{"name":"Number","value":"OP01-120"}]}]}"#
                : #"{"success":true,"errors":[],"results":[{"productId":454664,"subTypeName":"Normal","marketPrice":9000},{"productId":454664,"subTypeName":"Foil","marketPrice":8.16}]}"#
            return Data(json.utf8)
        }
        let source = OnePieceTCGCSVPriceSource(session: URLSession(configuration: config), cacheDirectory: directory)
        guard case let .price(price) = try await source.quote(mapping: mapping, number: "OP01-120") else { return XCTFail() }
        XCTAssertEqual(price.unitMarketPriceUSD, 8.16)
        let validResponse = OnePiecePriceTestProtocol.handler
        OnePiecePriceTestProtocol.handler = { _ in Data("invalid network response".utf8) }
        let relaunched = OnePieceTCGCSVPriceSource(session: URLSession(configuration: config), cacheDirectory: directory)
        guard case let .price(cached) = try await relaunched.quote(mapping: mapping, number: "OP01-120") else { return XCTFail() }
        XCTAssertEqual(cached, price)
        do { _ = try await source.quote(mapping: mapping, number: "OP01-001"); XCTFail() }
        catch PriceQuoteError.identityMismatch {}
        OnePiecePriceTestProtocol.handler = validResponse
        guard case let .price(refreshed) = try await relaunched.quote(mapping: mapping, number: "OP01-120", generation: "corrected-catalog") else { return XCTFail() }
        XCTAssertGreaterThan(refreshed.fetchedAt, cached.fetchedAt)
        OnePiecePriceTestProtocol.handler = { _ in Data("invalid network response".utf8) }
        guard case let .price(sameGeneration) = try await relaunched.quote(mapping: mapping, number: "OP01-120", generation: "corrected-catalog") else { return XCTFail() }
        XCTAssertEqual(sameGeneration, refreshed)
        OnePiecePriceTestProtocol.handler = validResponse
        guard case let .price(afterWithdrawal) = try await relaunched.quote(mapping: mapping, number: "OP01-120",
            generation: "corrected-catalog", minimumFetchedAt: sameGeneration.fetchedAt) else { return XCTFail() }
        XCTAssertGreaterThan(afterWithdrawal.fetchedAt, sameGeneration.fetchedAt)
        async let oldGeneration = source.quote(mapping: mapping, number: "OP01-120", generation: "old-generation")
        async let newGeneration = source.quote(mapping: mapping, number: "OP01-120", generation: "new-generation")
        guard case let .price(oldPrice) = try await oldGeneration,
              case let .price(newPrice) = try await newGeneration else { return XCTFail() }
        XCTAssertNotEqual(oldPrice.fetchedAt, newPrice.fetchedAt,
            "Requests from different catalog generations must not share an in-flight snapshot")
    }

    func testBoundOnePiecePricingPassesWithdrawalWatermarkToSource() async throws {
        let registry = try registry(withMarketMapping: true)
        let (_, container) = try model(registry: registry)
        let watermark = Date.now
        let card = try OnePieceCatalogAdapter(registry: registry).resolution(forPrintingID: uuid(1)).card
        let record = PriceRecord(key: PriceRecord.key(game: .onePiece, printingID: card.providerID, variantID: "foil"),
            game: .onePiece, printingID: card.providerID, variantID: "foil")
        record.invalidatedAt = watermark
        container.mainContext.insert(record)
        try container.mainContext.save()
        let source = OnePieceTestPriceSource()
        let base = OnePieceGameRuntime(registry: registry).runtime
        let runtime = CardGameRuntime(descriptor: base.descriptor, variantPolicy: base.variantPolicy,
            pricing: OnePiecePriceAdapter(registry: registry, source: source), priceAuthority: base.priceAuthority)
        let raw = try CardGameRuntimeContainer(runtimes: [runtime])
        let bound = try await raw.bound(to: container)
        _ = try await bound.makePriceQuoteService().refreshStoredPrinting(game: .onePiece,
            printingID: card.providerID, variant: .foil)
        let minimum = await source.lastMinimumFetchedAt
        XCTAssertEqual(minimum, watermark)
        let nextWatermark = watermark.addingTimeInterval(10)
        record.invalidatedAt = nextWatermark
        try container.mainContext.save()
        _ = try await bound.makePriceQuoteService().refreshStoredPrinting(game: .onePiece,
            printingID: card.providerID, variant: .foil)
        let laterMinimum = await source.lastMinimumFetchedAt
        XCTAssertEqual(laterMinimum, nextWatermark, "Background reads must observe withdrawals after runtime binding")
    }

    func testWithdrawalStartsFreshFetchWhileOlderRequestIsPending() async throws {
        let registry = try registry(withMarketMapping: true)
        let mapping = try XCTUnwrap(registry.printingByID[uuid(1)]?.marketMappings.first)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OnePiecePriceTestProtocol.self]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OnePieceConcurrentPrice-\(UUID())")
        let gate = OnePiecePriceRequestGate()
        OnePiecePriceTestProtocol.asyncHandler = { await gate.response($0) }
        defer {
            OnePiecePriceTestProtocol.asyncHandler = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let source = OnePieceTCGCSVPriceSource(session: URLSession(configuration: config), cacheDirectory: directory)
        let old = Task { try await source.quote(mapping: mapping, number: "OP01-120", generation: "same-generation") }
        defer { old.cancel(); Task { await gate.firstRequest.resume() } }
        await gate.firstRequest.waitForStart()
        let watermark = Date.now
        let completed = expectation(description: "Fresh cohort finishes before the old request")
        let freshRequests = Task {
            async let first = source.quote(mapping: mapping, number: "OP01-120", generation: "same-generation", minimumFetchedAt: watermark)
            async let second = source.quote(mapping: mapping, number: "OP01-120", generation: "same-generation", minimumFetchedAt: watermark)
            let quotes = try await (first, second)
            completed.fulfill()
            return quotes
        }
        await fulfillment(of: [completed], timeout: 5)
        await gate.firstRequest.resume()
        let quotes = try await freshRequests.value
        guard case let .price(fresh) = quotes.0, case let .price(coalesced) = quotes.1 else { return XCTFail() }
        XCTAssertGreaterThan(fresh.fetchedAt, watermark)
        XCTAssertEqual(fresh, coalesced)
        guard case let .price(older) = try await old.value else { return XCTFail() }
        XCTAssertLessThan(older.fetchedAt, watermark)
        guard case let .price(cached) = try await source.quote(mapping: mapping, number: "OP01-120", generation: "same-generation") else { return XCTFail() }
        XCTAssertEqual(cached, fresh, "The older completion must not overwrite the newer cache")
        let products = await gate.productCalls, prices = await gate.priceCalls
        XCTAssertEqual(products, 2)
        XCTAssertEqual(prices, 2)
    }

    func testOnePieceMetadataRefreshPreservesPurchaseLink() async throws {
        let registry = try registry()
        let card = try OnePieceCatalogAdapter(registry: registry).resolution(forPrintingID: uuid(1)).card
        let row = CollectedCard(card: card, resolved: .init(variant: .foil, resolution: .userConfirmed))
        row.tcgplayerURL = "https://www.tcgplayer.com/product/454664"
        row.applyCatalogMetadata(from: card)
        XCTAssertEqual(row.tcgplayerURL, "https://www.tcgplayer.com/product/454664")
        let request = GameImportRequest(sourceProviderID: card.providerID, catalogProviderID: card.providerID,
            game: .onePiece, name: card.name, setName: card.setName, cardNumber: card.cardNumber, itemKind: .rawCard)
        let matches = await OnePieceImportAdapter(registry: registry).metadata(for: [request])
        row.applyCatalogMetadata(try XCTUnwrap(matches[request.identityKey]))
        XCTAssertEqual(row.tcgplayerURL, "https://www.tcgplayer.com/product/454664")
    }

    func testOnePieceScannerSaveQueuesExactBasePricingWithoutPaidCredentials() async throws {
        let registry = try registry(withMarketMapping: true), source = OnePieceTestPriceSource()
        let (model, container) = try model(registry: registry, fixtureWritesEnabled: true, priceSource: source)
        defer { model.viewDisappeared() }
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), .init(identifier: try identifier(registry)), nil)
        let presented = await waitUntil { model.pendingIdentityChoice != nil }
        XCTAssertTrue(presented)
        let selected = try XCTUnwrap(model.pendingIdentityChoice?.displayCandidates.first { $0.id == uuid(1).uuidString.lowercased() })
        model.choose(selected)
        let finish = await waitUntil { model.pendingChoice != nil }
        XCTAssertTrue(finish)
        model.choose(.foil)
        let key = PriceRecord.key(game: .onePiece, printingID: uuid(1).uuidString.lowercased(), variantID: "foil")
        let priced = await waitUntil {
            PriceStore(context: ModelContext(container)).record(forKey: key)?.effectiveUnitMarketPriceUSD == 8.16
        }
        XCTAssertTrue(priced)
        XCTAssertEqual(model.successCount, 1)
        let calls = await source.calls
        XCTAssertEqual(calls, 1)
    }

    func testPriceAuthorityWithdrawalPreservesManualValuesAndRejectsOldReceipts() async throws {
        let registry = try registry(withMarketMapping: true), source = OnePieceTestPriceSource()
        let (_, container) = try model(registry: registry)
        let id = uuid(1).uuidString.lowercased()
        let quote = try await OnePiecePriceAdapter(registry: registry, source: source).refreshStoredPrinting(id, variant: .foil)
        let context = container.mainContext, prices = PriceStore(context: context)
        XCTAssertTrue(prices.store(quote, game: .onePiece, printingID: id, variantID: "foil"))
        XCTAssertTrue(prices.save())
        _ = QuoteCache(context: context).store(quote, game: .onePiece, printingID: id, variantID: "foil")
        let manual = PriceLookup.price(.init(unitMarketPriceUSD: 22, currencyCode: "USD", source: .importedCSV,
            sourceVariantID: "owner-entered", sourceUpdatedAt: nil, fetchedAt: .now))
        XCTAssertTrue(prices.store(manual, game: .onePiece, printingID: id, variantID: "normal"))
        XCTAssertTrue(prices.save())
        try OnePiecePriceAdapter.priceAuthority(registry).install(in: container)
        let key = PriceRecord.key(game: .onePiece, printingID: id, variantID: "foil")
        XCTAssertEqual(PriceStore(context: ModelContext(container)).record(forKey: key)?.effectiveUnitMarketPriceUSD, 8.16)
        let withdrawn = GameCatalogPriceAuthority(game: .onePiece, managedSources: [.tcgCSV], identityByPriceKey: [:])
        try withdrawn.install(in: container)
        let fresh = ModelContext(container)
        let record = try XCTUnwrap(PriceStore(context: fresh).record(forKey: key))
        XCTAssertNil(record.effectiveUnitMarketPriceUSD)
        XCTAssertNotNil(record.invalidatedAt)
        let reference = try XCTUnwrap(QuoteCache(context: fresh).quote(game: .onePiece, printingID: id, variantID: "foil"))
        XCTAssertNil(reference.effectiveAmount)
        reference.apply(quote, at: .now)
        XCTAssertNil(reference.effectiveAmount)
        XCTAssertEqual(PriceStore(context: fresh).record(forKey: PriceRecord.key(game: .onePiece,
            printingID: id, variantID: "normal"))?.effectiveUnitMarketPriceUSD, 22)
        let receipt = PriceStore(context: fresh, checkpointsInFreshContext: true)
        _ = receipt.store(quote, game: .onePiece, printingID: id, variantID: "foil")
        _ = receipt.save()
        XCTAssertNil(PriceStore(context: ModelContext(container)).record(forKey: key)?.effectiveUnitMarketPriceUSD)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<PriceObservation>())
            .filter { $0.kind == .explicitInvalidation }.count, 1)
    }

    func testBoundActivationPublishesWithdrawalBeforeBrowseOrCorrection() async throws {
        let first = try registry(complete: false, withMarketMapping: true)
        let second = try registry(complete: false, revision: 2, firstStatus: .quarantined)
        let (_, container) = try model(registry: first)
        let key = Curve25519.Signing.PrivateKey(), keyID = "one-piece-authority-fixture"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnePieceAuthority-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let seed = try OnePieceCatalogSignature.sign(first.verifiedRelease.release, keyID: keyID, privateKey: key)
        let store = try OnePieceCatalogReleaseStore(root: root, keys: [keyID: key.publicKey], bundledEnvelope: seed, now: now)
        let coordinator = OnePieceCatalogCoordinator(store: store)
        let raw = try CardGameRuntimeContainer(runtimes: [OnePieceGameRuntime(registry: first,
            coordinator: coordinator, capabilities: [.scan, .browse, .pricing, .collectionWrite]).runtime])
        let bound = try await raw.bound(to: container)
        let publication = try XCTUnwrap(bound.runtime(for: .onePiece)?.activationSource)
        let initial = await publication.currentSnapshot()
        XCTAssertEqual(initial?.revision, 1)
        let ownership = CollectionStore(context: container.mainContext)
        let card = try OnePieceCatalogAdapter(registry: first).resolution(forPrintingID: uuid(1)).card
        let acquisition = try ownership.add(card, resolved: .init(variant: .normal, resolution: .userConfirmed))
        let owned = try XCTUnwrap(ownership.card(forKey: acquisition.collectionKey))
        let activityID = try XCTUnwrap(acquisition.activityID)
        let quote = try await OnePiecePriceAdapter(registry: first, source: OnePieceTestPriceSource())
            .refreshStoredPrinting(uuid(1).uuidString.lowercased(), variant: .foil)
        let prices = PriceStore(context: container.mainContext)
        XCTAssertTrue(prices.store(quote, game: .onePiece, printingID: uuid(1).uuidString.lowercased(), variantID: "foil"))
        XCTAssertTrue(prices.save())
        let stream = await publication.activationSnapshots()
        var iterator = stream.makeAsyncIterator()
        let envelope = try OnePieceCatalogSignature.sign(second.verifiedRelease.release, keyID: keyID, privateKey: key)
        guard case .activated = await coordinator.activateEnvelope(envelope, now: now) else { return XCTFail() }
        let next = await iterator.next()
        let published = try XCTUnwrap(next)
        XCTAssertEqual(published.revision, 2)
        let priceKey = PriceRecord.key(game: .onePiece, printingID: uuid(1).uuidString.lowercased(), variantID: "foil")
        XCTAssertNil(PriceStore(context: ModelContext(container)).record(forKey: priceKey)?.effectiveUnitMarketPriceUSD)
        XCTAssertThrowsError(try published.catalog.validateVariantCorrection(printingID: uuid(1).uuidString.lowercased(), variantID: "foil"))
        // Snapshot after the intentional quote withdrawal. The rejected
        // correction must not move ownership or add further price history.
        func lineage() throws -> [String] {
            let context = ModelContext(container)
            let rows = try context.fetch(FetchDescriptor<CollectedCard>()).map {
                "row:\($0.collectionKey):\($0.quantity):\($0.variantID ?? "-"):\($0.providerID)"
            }
            let activities = try context.fetch(FetchDescriptor<CollectionActivity>()).map {
                "activity:\($0.id):\($0.collectionKey):\($0.variantID ?? "-"):\($0.deltaQuantity):\($0.resolvedQuantity):\($0.ledgerOperationIDs)"
            }
            let events = try context.fetch(FetchDescriptor<InventoryEvent>()).map {
                "event:\($0.id):\($0.operationID):\($0.collectionKey):\($0.priceStorageKey):\($0.deltaQuantity)"
            }
            let prices = try context.fetch(FetchDescriptor<PriceRecord>()).map {
                "price:\($0.key):\(String(describing: $0.invalidatedAt)):\(String(describing: $0.catalogPriceIdentity))"
            }
            let observations = try context.fetch(FetchDescriptor<PriceObservation>()).map { "observation:\($0.id)" }
            return (rows + activities + events + prices + observations).sorted()
        }
        let before = try lineage()
        let corrected = ResolvedVariant(variant: .foil, resolution: .userConfirmed)
        XCTAssertThrowsError(try ownership.recordVariantCorrection(for: owned, to: corrected,
            activityID: activityID, quantity: 1))
        XCTAssertEqual(try lineage(), before)
        XCTAssertThrowsError(try ownership.recordVariantCorrection(for: owned, to: corrected,
            claims: [.init(activityID: activityID, quantity: 1)], source: .correction, mode: .visibleCorrection))
        XCTAssertEqual(try lineage(), before)
        let browse = bound.makeBrowseCatalog()
        let page = try await browse.searchCards(named: "Fixture Shanks", game: .onePiece, setIDs: [], cursor: nil)
        XCTAssertFalse(page.items.contains { $0.providerID == uuid(1).uuidString.lowercased() })
        let later = await publication.currentSnapshot()
        XCTAssertEqual(later?.catalog.generation, second.generation)
        let rebound = try await raw.bound(to: container)
        let reboundSource = try XCTUnwrap(rebound.runtime(for: .onePiece)?.activationSource)
        let reboundSnapshot = await reboundSource.currentSnapshot()
        XCTAssertEqual(reboundSnapshot?.catalog.generation, second.generation)
        XCTAssertFalse(CollectionStore.canInstallCatalogAdapter(OnePieceCatalogAdapter(registry: first), revision: 1, for: container))
        XCTAssertFalse(CollectionStore.canInstallCatalogAdapter(OnePieceCatalogAdapter(registry: first), revision: 2, for: container))
    }

    func testPublicationRejectsConflictsAndRetiredStorageSession() async throws {
        let first = try registry(complete: false)
        let second = try registry(complete: false, revision: 2, firstStatus: .quarantined)
        func snapshot(_ registry: OnePieceCatalogRegistry) -> GameCatalogSnapshot {
            .init(revision: registry.verifiedRelease.release.revision,
                catalog: OnePieceCatalogAdapter(registry: registry),
                recognizer: OnePieceRecognitionAdapter(profile: .init(registry: registry)),
                variantPolicy: OnePieceVariantPolicy(registry: registry),
                priceAuthority: OnePiecePriceAdapter.priceAuthority(registry))
        }
        let (_, original) = try model(registry: first)
        let (_, replacement) = try model(registry: first)
        let source = OnePieceSnapshotTestSource(snapshot(first))
        let session = OnePieceTestSessionState()
        let publication = CollectionAuthorizedActivationSource(source: source, container: original,
            isCurrent: { session.isCurrent })
        let initial = await publication.currentSnapshot()
        XCTAssertEqual(initial?.revision, 1)
        // A different catalog identity at the same revision is rejected.
        var conflict = snapshot(second)
        conflict = .init(revision: 1, catalog: conflict.catalog, recognizer: conflict.recognizer,
            variantPolicy: conflict.variantPolicy, priceAuthority: conflict.priceAuthority)
        await source.update(conflict)
        let rejected = await publication.currentSnapshot()
        XCTAssertNil(rejected)
        XCTAssertTrue(CollectionStore.canInstallCatalogAdapter(OnePieceCatalogAdapter(registry: first), revision: 1, for: original))
        await source.update(snapshot(second))
        session.isCurrent = false
        let retired = await publication.currentSnapshot()
        XCTAssertNil(retired)
        // The old container still has N, while a fresh subscriber installs N+1
        // only in the replacement container.
        let fresh = CollectionAuthorizedActivationSource(source: source, container: replacement)
        let installed = await fresh.currentSnapshot()
        XCTAssertEqual(installed?.revision, 2)
        XCTAssertTrue(CollectionStore.canInstallCatalogAdapter(OnePieceCatalogAdapter(registry: first), revision: 1, for: original))
        XCTAssertFalse(CollectionStore.canInstallCatalogAdapter(OnePieceCatalogAdapter(registry: first), revision: 1, for: replacement))
        await source.update(snapshot(first))
        let stale = await fresh.currentSnapshot()
        XCTAssertEqual(stale?.revision, 2)
        XCTAssertEqual(stale?.catalog.generation, second.generation)
    }

    private func registry(count: Int = 2, complete: Bool = true,
                          secondStatus: OnePieceReconciliationStatus = .verified,
                          revision: Int = 1, multiProduct: Bool = false,
                          includeFooterEvidence: Bool = false, sharedReleaseLabels: Bool = false,
                          withMarketMapping: Bool = false,
                          firstStatus: OnePieceReconciliationStatus = .verified,
                          language: String = "en", releaseDate: String? = nil) throws -> OnePieceCatalogRegistry {
        let number = "OP01-120"
        let card = OnePieceCanonicalCard(printedNumber: number, language: language, name: "Fixture Shanks",
            printingCoverageComplete: complete && !withMarketMapping,
            coverageReviewReference: complete && !withMarketMapping ? "fixture-coverage" : nil)
        let artworkID = uuid(900)
        let imageHash = OnePieceSourceObservation.sha256(Data("fixture art".utf8))
        var observations: [OnePieceSourceObservation] = []
        var printings: [OnePiecePhysicalPrinting] = []
        var products: [OnePieceProduct] = []
        for index in 0..<count {
            let product = OnePieceProduct(id: "fixture-release-\(index)",
                label: sharedReleaseLabels ? "Fixture release" : "Fixture release \(index)", releaseDate: releaseDate)
            products.append(product)
            let observation = OnePieceProviderNormalizer.observation(provider: .bandai, capture: .init(
                observationID: "fixture-observation-\(index)", sourceID: "fixture-row-\(index)",
                sourceURL: URL(string: "https://fixture.invalid/\(index)")!, observedAt: date, language: language,
                payloadBytes: Data("fixture source \(index)".utf8), imageBytes: Data("fixture art".utf8),
                productEvidence: [product.id] + (multiProduct && index == 0 ? ["fixture-bundle"] : []),
                printedEvidence: includeFooterEvidence
                    ? ["number": number, "blockText": "\(index)", "copyrightText": "Fixture footer \(index)", "finishVariantIDs": "[\"normal\",\"foil\"]"]
                    : ["number": number, "finishVariantIDs": "[\"normal\",\"foil\"]"]))
            observations.append(observation)
            var mappings: [OnePieceMarketMapping] = []
            if withMarketMapping && index == 0 {
                let market = OnePieceSourceObservation(id: "fixture-market", kind: .market,
                    alias: .init(provider: "tcgplayer", sourceID: "454664"),
                    sourceURL: URL(string: "https://tcgcsv.com/tcgplayer/68/3188/products")!,
                    observedAt: date, language: language, payloadSHA256: imageHash,
                    productEvidence: [product.id], printedEvidence: ["number": number,
                        "marketProductID": "454664", "marketVariantID": "Foil", "finishVariantID": "foil",
                        "market": "us", "currency": "USD", "condition": "aggregate",
                        "qualifier:groupID": "3188", "qualifier:productName": "Shanks", "qualifier:finish": "Foil"])
                observations.append(market)
                mappings = [.init(printingID: uuid(1), provider: "tcgplayer", productID: "454664",
                    providerVariantID: "Foil", variantID: "foil", market: "us", currency: "USD",
                    condition: "aggregate", qualifiers: ["groupID": "3188", "productName": "Shanks", "finish": "Foil"],
                    status: .exact, review: .init(reference: "fixture-market-review", evidence:
                        [OnePieceEvidenceKind.printedIdentity, .marketIdentity].map {
                            .init(kind: $0, observationID: market.id, detail: "Synthetic exact market evidence")
                        }))]
            }
            let review = OnePieceReview(reference: "fixture-printing-review-\(index)", evidence:
                ([OnePieceEvidenceKind.printedIdentity, .language, .artwork, .release, .finish]
                    + (includeFooterEvidence ? [.footer] : [])).map {
                    .init(kind: $0, observationID: observation.id, detail: "Synthetic fixture evidence")
                })
            printings.append(.init(id: uuid(index + 1), canonicalCardID: card.id, artworkID: artworkID,
                language: language, region: includeFooterEvidence ? "North America" : nil,
                releaseID: product.id, blockText: includeFooterEvidence ? "\(index)" : nil,
                copyrightText: includeFooterEvidence ? "Fixture footer \(index)" : nil,
                supportedVariantIDs: ["normal", "foil"],
                status: index == 1 ? secondStatus : firstStatus, review: review, sourceAliases: [observation.alias],
                marketMappings: mappings))
        }
        if multiProduct { products.append(.init(id: "fixture-bundle", label: "Fixture bundle")) }
        // Future prefix support is derived from registry cards. No permanent set horizon.
        let futureCards = ["ST01-007", "P-001", "OP99-001", "EB99-001", "PRB99-001", "ST99-001"].map {
            OnePieceCanonicalCard(printedNumber: $0, language: "en", name: "Fixture \($0)")
        }
        let release = try OnePieceCatalogBuilder.build(registry: .init(canonicalCards: [card] + futureCards,
            artworks: [.init(id: artworkID, referenceImageURL: URL(string: "https://fixture.invalid/art.png"),
                            imageSHA256: imageHash, observationIDs: observations.map(\.id))],
            printings: printings, variants: [.init(id: "normal", label: "Normal"), .init(id: "foil", label: "Foil")],
            products: products, appearances: multiProduct ? [.init(printingID: uuid(1),
                productID: "fixture-bundle", observationIDs: ["fixture-observation-0"])] : []), observations: observations,
            inventories: [.init(provider: "bandai", snapshotID: "fixture-snapshot", paginationComplete: true,
                                observationIDs: observations.filter { $0.alias.provider == "bandai" }.map(\.id))]
                + (withMarketMapping ? [.init(provider: "tcgplayer", snapshotID: "fixture-market", paginationComplete: false,
                    observationIDs: ["fixture-market"])] : []), revision: revision, generatedAt: date)
        let key = Curve25519.Signing.PrivateKey()
        let envelope = try OnePieceCatalogSignature.sign(release, keyID: "one-piece-test", privateKey: key)
        return .init(verifiedRelease: try OnePieceCatalogSignature.verify(envelope,
            trustedKeys: ["one-piece-test": key.publicKey], now: now))
    }

    private func identifier(_ registry: OnePieceCatalogRegistry, confirmedEnglish: Bool = false) throws -> ScanIdentifier {
        let profile = OnePieceScanProfile(registry: registry,
            languageConfirmation: confirmedEnglish ? .userConfirmedEnglish : .unconfirmed)
        guard case let .identified(subject) = profile.identify([.init(text: "OP01-120")]) else {
            throw CatalogLookupError.invalidAdapterOutcome
        }
        return subject.identifier
    }

    func testRegistryDerivedRecognitionKeepsNumericRepairAndLanguageConservative() throws {
        let registry = try registry()
        let profile = OnePieceScanProfile(registry: registry)
        for text in ["OP01-12O", "op01-120", "OP01 – 120"] {
            guard case let .identified(subject) = profile.identify([.init(text: text)]) else { return XCTFail(text) }
            XCTAssertEqual(subject.identifier.fields.first(where: { $0.key == "number" })?.value, "OP01-120")
            XCTAssertEqual(subject.identifier.fields.first(where: { $0.key == "language" })?.value, "unknown")
            XCTAssertEqual(subject.identifier.catalogGeneration, registry.generation)
        }
        XCTAssertEqual(profile.identify([.init(text: "OP0I-120")]), .nothing)
        XCTAssertEqual(profile.identify([.init(text: "DON-001")]), .nothing)
        guard case let .identified(unknown) = profile.identify([.init(text: "OP01-999")]) else {
            return XCTFail("A supported series must preserve an uncataloged printed number")
        }
        XCTAssertEqual(unknown.identifier.displayIdentifier, "OP01-999")
        XCTAssertEqual(profile.identify([.init(text: "XOP01-120Y")]), .nothing)
        XCTAssertEqual(profile.identify([.init(text: "OP01-120", boundingBox: CGRect(x: 0, y: 1.2, width: 0.2, height: 0.05))]), .nothing)
        XCTAssertTrue(profile.customWords.contains("PRB99"))
        XCTAssertFalse(profile.customWords.contains("OP01-120"))
        for number in ["ST01-007", "P-001", "OP99-001", "EB99-001", "PRB99-001", "ST99-001"] {
            guard case .identified = profile.identify([.init(text: number)]) else { return XCTFail(number) }
        }
    }

    func testMultipleNumbersAreHardAmbiguityAndRepeatedReadingsDeduplicate() throws {
        let profile = OnePieceScanProfile(registry: try registry())
        XCTAssertEqual(profile.identify([.init(text: "OP01-120 P-001")]), .ambiguous)
        guard case .identified = profile.identify([.init(text: "OP01-120"), .init(text: "OP01-12O")]) else {
            return XCTFail("Same normalized number should remain one identity")
        }
        let onePiece = OnePieceRecognitionAdapter(profile: profile)
        let sameGame = try GameRecognitionRegistry(recognizers: [onePiece])
        XCTAssertEqual(sameGame.identify([.init(text: "OP01-120 P-001")]), .ambiguous)
    }

    func testOnePieceFooterMustBeContainedInItsOCRRegion() throws {
        let profile = OnePieceScanProfile(registry: try registry())
        for rect in [CGRect(x: -0.05, y: 0.1, width: 0.2, height: 0.05),
                     CGRect(x: 0.9, y: 0.1, width: 0.2, height: 0.05),
                     CGRect(x: 0.1, y: 0.9, width: 0.2, height: 0.2),
                     CGRect(x: 0.1, y: 0.1, width: 2, height: 0.05)] {
            XCTAssertEqual(profile.identify([.init(text: "OP01-120", boundingBox: rect)]), .nothing)
        }
        guard case .identified = profile.identify([.init(text: "OP01-120",
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.7, height: 0.1))]) else {
            return XCTFail("Valid in-region footer")
        }
    }

    func testSoleVerifiedPrintingResolvesWithoutLanguageConfirmationPicker() async throws {
        let registry = try registry(count: 1)
        let catalog = CardCatalog(gameCatalogAdapters: try .init(adapters: [OnePieceCatalogAdapter(registry: registry)]))
        guard case let .resolved(selected) = try await catalog.lookupOutcome(for: identifier(registry)) else {
            return XCTFail("A sole verified printing should resolve without an extra tap")
        }
        XCTAssertEqual(selected.card.language, "en")
        XCTAssertEqual(selected.card.providerID, uuid(1).uuidString.lowercased())
        XCTAssertEqual(selected.retrievedAt, now)
        guard case .resolved = try await catalog.lookupOutcome(for: identifier(registry, confirmedEnglish: true)) else {
            return XCTFail("Confirmed English plus complete unique verified scope may resolve")
        }
    }

    func testSoleVerifiedPrintingResolvesInIncompleteScopeWithoutSelectingConflictedRecords() async throws {
        for registry in [try registry(count: 1, complete: false), try registry(secondStatus: .conflicted)] {
            let adapter = OnePieceCatalogAdapter(registry: registry)
            guard case let .resolved(selected) = try await adapter.lookup(identifier(registry, confirmedEnglish: true)) else {
                return XCTFail("Only available verified printings participate in the choice")
            }
            XCTAssertEqual(selected.card.providerID, uuid(1).uuidString.lowercased())
        }
        let registry = try registry()
        let unknownPrintingNumber = try ScanIdentifier(game: .onePiece, namespace: "numbered-card",
            fields: [.init(key: "number", value: "P-001")], displayIdentifier: "P-001", suppressionIdentity: "number:P-001",
            catalogGeneration: registry.generation)
        guard case let .catalogIncomplete(canonical) = try await OnePieceCatalogAdapter(registry: registry).lookup(unknownPrintingNumber) else {
            return XCTFail("Known canonical without physical records remains incomplete")
        }
        XCTAssertEqual(canonical?.printedIdentifier, "P-001")
    }

    func testPersistedSingletonChoiceStillRevalidatesAgainstCurrentResolvedPrinting() async throws {
        let registry = try registry(count: 1)
        let adapter = OnePieceCatalogAdapter(registry: registry)
        let catalog = CardCatalog(gameCatalogAdapters: try .init(adapters: [adapter]))
        let scan = try identifier(registry)
        let candidate = PhysicalPrintingCandidate(id: uuid(1).uuidString.lowercased(), game: .onePiece,
            canonicalCardID: "one-piece:en:OP01-120", language: "en", catalogGeneration: registry.generation,
            name: "Fixture Shanks", printedIdentifier: "OP01-120",
            releaseLabel: "English · Fixture release 0", distributionLabel: "",
            thumbnailURL: URL(string: "https://fixture.invalid/art.png"),
            artworkID: uuid(900).uuidString.lowercased(), distinctionLabels: [])
        let selected = try await catalog.resolvePrintingChoice(candidate, for: scan)
        XCTAssertEqual(selected.card.providerID, candidate.id)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(candidate)) as? [String: Any])
        payload["artworkID"] = uuid(901).uuidString.lowercased()
        let tampered = try JSONDecoder().decode(PhysicalPrintingCandidate.self,
            from: JSONSerialization.data(withJSONObject: payload))
        do { _ = try await catalog.resolvePrintingChoice(tampered, for: scan); XCTFail("Stored choices must retain validated evidence") }
        catch CatalogLookupError.invalidPrintingChoice {}
    }

    func testPrintingChoiceExposesReviewedFooterAndRegionWithoutOpaqueLabels() async throws {
        let registry = try registry(includeFooterEvidence: true, sharedReleaseLabels: true)
        guard case let .needsPrintingChoice(_, candidates) = try await OnePieceCatalogAdapter(registry: registry)
            .lookup(identifier(registry)) else { return XCTFail() }
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(Set(candidates.map(\.choiceTitle)).count, 1)
        XCTAssertEqual(Set(candidates.map(\.choiceLabel)).count, 2)
        for candidate in candidates {
            XCTAssertEqual(candidate.artworkID, uuid(900).uuidString.lowercased())
            XCTAssertTrue(candidate.identificationDetails.contains("Region: North America"))
            XCTAssertTrue(candidate.identificationDetails.contains { $0.hasPrefix("Block:") })
            XCTAssertTrue(candidate.identificationDetails.contains { $0.hasPrefix("Copyright:") })
            XCTAssertEqual(candidate.selectionEvidence(among: candidates), .labels)
            XCTAssertFalse(candidate.choiceLabel.contains(candidate.id))
        }
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("PrintingDetails-\(UUID()).json")
        let store = UnresolvedScanStore(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let saved = await store.save([.init(subject: .init(identifier: try identifier(registry)),
            reason: .noConfirmedMatch, printingCandidates: candidates)])
        XCTAssertTrue(saved)
        let restored = await store.load(gameCatalogAdapters: try .init(adapters: [OnePieceCatalogAdapter(registry: registry)]))
        XCTAssertEqual(restored.first?.printingCandidates, candidates)
    }

    func testOlderPrintingCandidatesStillDecodeAndResolveWithoutNewDetails() async throws {
        let registry = try registry(), adapter = OnePieceCatalogAdapter(registry: registry)
        let scan = try identifier(registry)
        guard case let .needsPrintingChoice(_, candidates) = try await adapter.lookup(scan) else { return XCTFail() }
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(candidates[0])) as? [String: Any])
        json.removeValue(forKey: "artworkID")
        json.removeValue(forKey: "distinctionLabels")
        let legacy = try JSONDecoder().decode(PhysicalPrintingCandidate.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.artworkID)
        XCTAssertTrue(legacy.identificationDetails.isEmpty)
        let selected = try await adapter.resolve(legacy, for: scan)
        XCTAssertEqual(selected.card.physicalPrintingID, legacy.id)
        let catalog = CardCatalog(gameCatalogAdapters: try .init(adapters: [adapter]))
        let recovered = try await catalog.resolvePrintingChoice(legacy, for: scan)
        XCTAssertEqual(recovered.card.physicalPrintingID, legacy.id,
                       "A valid older multi-printing recovery choice must pass the shared catalog boundary")
        json["artworkID"] = "another-artwork"
        let tampered = try JSONDecoder().decode(PhysicalPrintingCandidate.self, from: JSONSerialization.data(withJSONObject: json))
        do { _ = try await adapter.resolve(tampered, for: scan); XCTFail("Published artwork evidence must agree") }
        catch CatalogLookupError.invalidPrintingChoice {}
        do { _ = try await catalog.resolvePrintingChoice(tampered, for: scan); XCTFail("New presentation evidence cannot be ignored") }
        catch CatalogLookupError.invalidPrintingChoice {}
        json.removeValue(forKey: "artworkID")
        json["releaseLabel"] = "A different release"
        let wrongRelease = try JSONDecoder().decode(PhysicalPrintingCandidate.self, from: JSONSerialization.data(withJSONObject: json))
        do { _ = try await catalog.resolvePrintingChoice(wrongRelease, for: scan); XCTFail("Legacy release evidence must still agree") }
        catch CatalogLookupError.invalidPrintingChoice {}
    }

    func testIndistinguishableLabelsRequireDistinctAvailableArtworkOrMoreCatalogDetail() {
        func candidate(_ id: String, artwork: String? = nil, details: [String]? = nil, image: Bool = true) -> PhysicalPrintingCandidate {
            .init(id: id, game: .onePiece, canonicalCardID: "one-piece:en:OP01-120", language: "en",
                catalogGeneration: "fixture", name: "Shanks", printedIdentifier: "OP01-120",
                releaseLabel: "English · Same release",
                thumbnailURL: image ? URL(string: "https://fixture.invalid/\(id).png") : nil,
                artworkID: artwork, distinctionLabels: details)
        }
        let first = candidate("first", artwork: "art-a"), second = candidate("second", artwork: "art-b")
        XCTAssertEqual(first.selectionEvidence(among: [first, second]), .artwork)
        let identicalArt = candidate("third", artwork: "art-a")
        XCTAssertEqual(first.selectionEvidence(among: [first, identicalArt]), .insufficient)
        let noImage = candidate("missing", artwork: "art-c", image: false)
        XCTAssertEqual(noImage.selectionEvidence(among: [first, noImage]), .insufficient)
        let footer = candidate("footer", artwork: "art-a", details: ["Block: 2"])
        XCTAssertEqual(footer.selectionEvidence(among: [first, footer]), .labels)
        XCTAssertEqual(first.selectionEvidence(among: [first]), .labels)
    }

    func testCompactPrintingLabelsKeepEssentialDistinctionsAndOmitSharedMetadata() {
        func candidate(_ id: String, treatment: String? = nil, distribution: String? = nil,
                       release: String = "English · Romance Dawn", block: String = "Block: 1") -> PhysicalPrintingCandidate {
            .init(id: id, game: .onePiece, canonicalCardID: "one-piece:en:OP01-120", language: "en",
                  catalogGeneration: "fixture", name: "Shanks", printedIdentifier: "OP01-120",
                  releaseLabel: release, treatmentLabel: treatment, distributionLabel: distribution,
                  distinctionLabels: ["Region: North America", block, "Copyright: Shared footer"])
        }
        let original = candidate("original", treatment: "Original art")
        let parallel = candidate("parallel", treatment: "Alternate art")
        XCTAssertEqual(original.compactChoiceLabel(among: [original, parallel]), "Original art")
        XCTAssertEqual(parallel.compactChoiceLabel(among: [original, parallel]), "Alternate art")
        let reprint = candidate("reprint", treatment: "Original art", block: "Block: 2")
        XCTAssertEqual(original.compactChoiceLabel(among: [original, reprint]), "Block: 1")
        XCTAssertEqual(reprint.compactChoiceLabel(among: [original, reprint]), "Block: 2")
        let eventA = candidate("event-a", treatment: "Original art", distribution: "Participation", release: "English · Event A")
        let eventB = candidate("event-b", treatment: "Original art", distribution: "Winner", release: "English · Event B")
        let eventC = candidate("event-c", treatment: "Alternate art", distribution: "Participation", release: "English · Event C")
        XCTAssertEqual(eventA.compactChoiceLabel(among: [eventA, eventB, eventC]), "Event A")
        // Different fields can produce the same shortened string. Preserve
        // the published release distinctions rather than two 'Special' buttons.
        let first = candidate("first", treatment: "Special", release: "English · Release A")
        let second = candidate("second", distribution: "Special", release: "English · Release B")
        XCTAssertNotEqual(first.compactChoiceLabel(among: [first, second]), second.compactChoiceLabel(among: [first, second]))
        let identical = candidate("same", treatment: "Original art")
        XCTAssertEqual(original.selectionEvidence(among: [original, identical]), .insufficient)
    }

    func testPrintingReleaseDateKeepsItsUTCCalendarDay() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z"))
        let candidate = PhysicalPrintingCandidate(id: "fixture", game: .onePiece,
            canonicalCardID: "fixture", language: "en", catalogGeneration: "fixture",
            name: "Fixture", printedIdentifier: "P-001", releaseDate: date)
        let local = DateFormatter()
        local.dateStyle = .medium
        local.timeZone = TimeZone(secondsFromGMT: -12 * 3_600)
        XCTAssertNotEqual(candidate.releaseDateLabel, local.string(from: date))
    }

    func testUncatalogedNumbersParticipateInAmbiguityAndRemainIncomplete() async throws {
        let registry = try registry(), profile = OnePieceScanProfile(registry: registry)
        for text in ["OP01-120 OP01-999", "OP01-998 OP01-999"] {
            XCTAssertEqual(profile.identify([.init(text: text)]), .ambiguous)
        }
        XCTAssertEqual(profile.identify([.init(text: "OP98-001")]), .nothing, "Unregistered series remain outside recognition")
        guard case let .identified(subject) = profile.identify([.init(text: "OP01-999"), .init(text: "OP01-999")]) else {
            return XCTFail("Repeated evidence for one uncataloged number remains one identity")
        }
        XCTAssertEqual(subject.identifier.suppressionIdentity, "number:OP01-999")
        guard case .catalogIncomplete(nil) = try await OnePieceCatalogAdapter(registry: registry).lookup(subject.identifier) else {
            return XCTFail("Uncataloged number cannot manufacture a canonical card or printing")
        }
    }

    func testUncatalogedNumberIsRetainedForRecoveryWithoutOwnership() async throws {
        let registry = try registry()
        let profile = OnePieceScanProfile(registry: registry)
        guard case let .identified(subject) = profile.identify([.init(text: "OP01-999")]) else { return XCTFail() }
        let (model, container) = try model(registry: registry, fixtureWritesEnabled: true)
        defer { model.viewDisappeared() }
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), subject, nil)
        let filed = await waitUntil { !model.unresolvedScans.isEmpty }
        XCTAssertTrue(filed)
        let unresolved = try XCTUnwrap(model.unresolvedScans.first)
        XCTAssertEqual(unresolved.subject.identifier, subject.identifier)
        XCTAssertEqual(unresolved.reason, .noCatalogEntry, "Incomplete local catalogs must offer retry lookup")
        XCTAssertEqual(model.successCount, 0)
        XCTAssertNil(model.pendingIdentityChoice)
        XCTAssertNil(model.pendingChoice)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
    }

    func testCatalogGenerationChangesRejectStaleChoiceAndDoNotChangeSuppression() async throws {
        XCTAssertEqual(CardCatalog.classify(CatalogLookupError.staleCatalog), .notInCatalog)
        let first = try registry(revision: 1), second = try registry(revision: 2)
        let firstID = try identifier(first), secondID = try identifier(second)
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(firstID.suppressionKey, secondID.suppressionKey)
        let adapter = OnePieceCatalogAdapter(registry: first)
        guard case let .needsPrintingChoice(_, candidates) = try await adapter.lookup(firstID) else { return XCTFail() }
        let nextCatalog = CardCatalog(gameCatalogAdapters: try .init(adapters: [OnePieceCatalogAdapter(registry: second)]))
        do { _ = try await nextCatalog.resolvePrintingChoice(candidates[0], for: firstID); XCTFail("Stale choice must fail") }
        catch CatalogLookupError.staleCatalog {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testBrowseProductAppearancesKeepOnePhysicalIdentityAndExactDetails() async throws {
        let registry = try registry(multiProduct: true)
        let runtimes = try CardGameRuntimeContainer(runtimes: [OnePieceGameRuntime(registry: registry).runtime])
        let browse = runtimes.makeBrowseCatalog()
        let sets = try await browse.sets(for: .onePiece)
        XCTAssertEqual(sets.count, 3)
        let bundle = try XCTUnwrap(sets.first { $0.providerID == "fixture-bundle" })
        let page = try await browse.cards(in: bundle, cursor: nil)
        let summary = try XCTUnwrap(page.items.first)
        XCTAssertEqual(summary.providerID, uuid(1).uuidString.lowercased())
        let search = try await browse.searchCards(named: "OP01-120", game: .onePiece, setIDs: [], cursor: nil)
        XCTAssertEqual(search.items.count, 2, "Multiple product appearances must not duplicate physical search results")
        let filtered = try await browse.searchCards(named: "Shanks", game: .onePiece, setIDs: [bundle.catalogID], cursor: nil)
        XCTAssertEqual(filtered.items.map(\.providerID), [summary.providerID])
        let details = try await browse.details(for: summary)
        XCTAssertEqual(details.card.physicalPrintingID, summary.providerID)
        XCTAssertEqual(details.card.canonicalCardID, "one-piece:en:OP01-120")
        XCTAssertEqual(details.set.catalogID, bundle.catalogID)
        XCTAssertEqual(details.retrievedAt, now)
        XCTAssertTrue(browse.gameRegistry.supports(.onePiece, .browse))
        XCTAssertFalse(browse.gameRegistry.supports(.onePiece, .collectionWrite))
        XCTAssertTrue(browse.gameRegistry.supports(.onePiece, .pricing))
        let model = BrowseViewModel(catalog: browse, sealedModel: SealedBrowseModel(transport: .shared,
            gameRegistry: browse.gameRegistry, isConfigured: { false }))
        XCTAssertEqual(model.searchGames, [.onePiece])
        await model.loadSets()
        XCTAssertEqual(model.sets[.onePiece]?.count, 3)
        model.searchText = "not-a-real-fixture"
        let empty = await waitUntil { model.searchState == .empty(needsSealedSetup: true) }
        XCTAssertTrue(empty, "Enabled sealed browsing should offer setup when credentials are absent")
    }

    func testCSVExportRoundTripKeepsExactPrintingFinishAndRefusesProductionWrites() throws {
        let registry = try registry()
        let card = try OnePieceCatalogAdapter(registry: registry).resolution(forPrintingID: uuid(1)).card
        let row = CollectedCard(card: card, resolved: .init(variant: .normal, resolution: .userConfirmed))
        let document = CollectionCSV.export([row])
        let plan = try CollectionCSV.parse(Data(document.text.utf8))
        let entry = try XCTUnwrap(plan.entries.first)
        XCTAssertEqual(entry.game, .onePiece)
        XCTAssertEqual(entry.providerID, uuid(1).uuidString.lowercased())
        XCTAssertEqual(entry.collectionKey, row.collectionKey)
        XCTAssertEqual(entry.variant?.id, PhysicalVariant.normal.id)
        XCTAssertEqual(entry.cardNumber, "OP01-120")
        let adapter = OnePieceImportAdapter(registry: registry)
        XCTAssertNoThrow(try adapter.validate(entry))
        let (_, container) = try model(registry: registry)
        let result = try CollectionCSV.apply(plan, to: container.mainContext,
            gameImportAdapters: try .init(adapters: [adapter]))
        XCTAssertEqual(result.importedQuantity, 0)
        XCTAssertEqual(result.failedRows.count, 1)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
    }

    func testWritableNewGameCannotImportWithoutPrintingValidationAdapter() throws {
        let registry = try registry()
        let (model, container) = try model(registry: registry)
        defer { model.viewDisappeared() }
        let future = CardGame(rawValue: "future-game")
        let policy = CardGameRegistry(descriptors: [.onePiece, future].map {
            .init(game: $0, displayName: $0.rawValue, sortOrder: 0, capabilities: [.collectionWrite])
        })
        CollectionStore.configureGames(policy, for: container)
        let text = "game,provider_id,card_name,card_number,finish,quantity\n"
            + "one-piece,OP01-120,Shanks,OP01-120,normal,1\n"
            + "one-piece,\(uuid(1).uuidString.lowercased()),Shanks,OP01-120,normal,1\n"
            + "future-game,provider-123,Future card,001,normal,1\n"
        let plan = try CollectionCSV.parse(Data(text.utf8))
        XCTAssertEqual(plan.entries.count, 3)
        let result = try CollectionCSV.apply(plan, to: container.mainContext, gameRegistry: policy)
        XCTAssertEqual(result.importedQuantity, 0)
        XCTAssertEqual(result.failedRows.count, 3)
        XCTAssertTrue(result.failedRows.allSatisfy {
            $0.detail == GameImportValidationError.missingAdapter.localizedDescription
        })
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CollectionActivity>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PriceObservation>()).isEmpty)
    }

    func testEnabledFixtureImportRequiresExactUUIDKeyAndSupportedFinish() throws {
        let registry = try registry()
        let adapter = OnePieceImportAdapter(registry: registry)
        let policy = CardGameRegistry(descriptors: [.init(game: .onePiece, displayName: "Fixture", sortOrder: 0,
            capabilities: [.collectionWrite])])
        let (_, container) = try model(registry: registry)
        // Explicitly enable the isolated store; an importer argument must not
        // override a configured production container's write restrictions.
        CollectionStore.configureGames(policy, for: container)
        let card = try OnePieceCatalogAdapter(registry: registry).resolution(forPrintingID: uuid(1)).card
        let row = CollectedCard(card: card, resolved: .init(variant: .normal, resolution: .userConfirmed))
        let plan = try CollectionCSV.parse(Data(CollectionCSV.export([row]).text.utf8))
        let result = try CollectionCSV.apply(plan, to: container.mainContext, gameRegistry: policy,
                                            gameImportAdapters: try .init(adapters: [adapter]))
        XCTAssertEqual(result.importedQuantity, 1)
        let restored = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(restored.collectionKey, row.collectionKey)
        XCTAssertEqual(restored.providerID, row.providerID)
        XCTAssertEqual(restored.priceKey, row.priceKey)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PriceObservation>()).isEmpty)
        let headers = "game,provider_id,card_name,card_number,finish,quantity"
        let eventsBefore = try container.mainContext.fetch(FetchDescriptor<InventoryEvent>()).count
        let activitiesBefore = try container.mainContext.fetch(FetchDescriptor<CollectionActivity>()).count
        for values in [
            "one-piece,OP01-120,Shanks,OP01-120,normal,1",
            "one-piece,\(uuid(1).uuidString.lowercased()),Shanks,OP01-120,,1",
            "one-piece,\(uuid(1).uuidString.lowercased()),Shanks,OP01-121,normal,1",
            "one-piece,\(uuid(1).uuidString.lowercased()),Shanks,OP01-120,manga,1"
        ] {
            let invalid = try CollectionCSV.parse(Data((headers + "\n" + values + "\n").utf8))
            XCTAssertThrowsError(try adapter.validate(try XCTUnwrap(invalid.entries.first)))
            let denied = try CollectionCSV.apply(invalid, to: container.mainContext, gameRegistry: policy,
                                                gameImportAdapters: try .init(adapters: [adapter]))
            XCTAssertEqual(denied.importedQuantity, 0)
            XCTAssertEqual(denied.failedRows.count, 1)
            let rows = try container.mainContext.fetch(FetchDescriptor<CollectedCard>())
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows.first?.quantity, 1)
            XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<InventoryEvent>()).count, eventsBefore)
            XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<CollectionActivity>()).count, activitiesBefore)
        }
    }

    func testEnglishScopeExcludesForeignPrintingsFromAllAcquisitionAndPricingSurfaces() async throws {
        let registry = try registry(withMarketMapping: true, language: "ja")
        let adapter = OnePieceCatalogAdapter(registry: registry)
        XCTAssertThrowsError(try adapter.resolution(forPrintingID: uuid(1)))
        guard case .nothing = OnePieceScanProfile(registry: registry).identify([.init(text: "OP01-120")]) else {
            return XCTFail("An English scanner must not recognize a foreign-only series")
        }
        let plan = try CollectionCSV.parse(Data(("game,provider_id,card_name,card_number,finish,quantity\n"
            + "one-piece,\(uuid(1).uuidString.lowercased()),Shanks,OP01-120,foil,1\n").utf8))
        XCTAssertThrowsError(try OnePieceImportAdapter(registry: registry).validate(XCTUnwrap(plan.entries.first)))
        let browse = OnePieceBrowseAdapter(registry: registry)
        let sets = try await browse.sets()
        XCTAssertTrue(sets.isEmpty)
        let results = try await browse.search(query: "Shanks", setIDs: [], cursor: nil)
        XCTAssertTrue(results.items.isEmpty)
        XCTAssertTrue(OnePiecePriceAdapter.priceAuthority(registry).identityByPriceKey.isEmpty)
    }

    func testPrintingReleaseOrderUsesPrimaryReleaseRatherThanProductAppearance() async throws {
        let registry = try registry(multiProduct: true, releaseDate: "2024-02-02")
        let adapter = OnePieceCatalogAdapter(registry: registry)
        let card = try adapter.resolution(forPrintingID: uuid(1)).card
        let browse = OnePieceBrowseAdapter(registry: registry)
        let sets = try await browse.sets()
        let primary = try XCTUnwrap(sets.first { $0.providerID == "fixture-release-0" })
        XCTAssertGreaterThan(card.setReleaseOrder, 0)
        XCTAssertEqual(card.setReleaseOrder, primary.releaseOrder)
        let bundle = try XCTUnwrap(sets.first { $0.providerID == "fixture-bundle" })
        let page = try await browse.cards(in: bundle, cursor: nil)
        let details = try await browse.details(for: XCTUnwrap(page.items.first))
        XCTAssertEqual(details.card.setReleaseOrder, primary.releaseOrder)
        let metadata = await OnePieceImportAdapter(registry: registry).metadata(for: [.init(
            sourceProviderID: card.providerID, catalogProviderID: nil, game: .onePiece,
            name: card.name, setName: bundle.name, cardNumber: card.cardNumber, itemKind: .rawCard)])
        XCTAssertEqual(metadata.values.first?.setReleaseOrder, primary.releaseOrder)
    }

    func testNormalizationUsesExactAdapterAndPreservesUnknownAndProductionGatedRows() async throws {
        let registry = try registry()
        let (_, container) = try model(registry: registry)
        let context = container.mainContext
        let id = uuid(1).uuidString.lowercased()
        func row(game: CardGame) -> CollectedCard {
            .init(collectionKey: "\(game.rawValue):\(id)#normal", game: game, providerID: id,
                name: "Fixture Shanks", setName: "Imported set", setCode: "", cardNumber: "OP01-120",
                rarity: nil, imageURL: nil, thumbnailURL: nil, variant: .normal, variantResolution: .imported)
        }
        let known = row(game: .onePiece), future = row(game: .init(rawValue: "future-game"))
        context.insert(known); context.insert(future); try context.save()
        let production = try CardGameRuntimeContainer(runtimes: [OnePieceGameRuntime(registry: registry).runtime])
        await production.makeCollectionNormalizer().normalizeImportedCards(in: container)
        context.rollback()
        let unchanged = try context.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertTrue(unchanged.allSatisfy { $0.catalogMetadataCheckedAt == nil && $0.catalogProviderID == nil })
        let policy = CardGameRegistry(descriptors: [.init(game: .onePiece, displayName: "Fixture", sortOrder: 0,
            capabilities: [.collectionWrite])])
        CollectionStore.configureGames(policy, for: container)
        let normalizer = CollectionCatalogNormalizer(gameRegistry: policy,
            gameImportAdapters: try .init(adapters: [OnePieceImportAdapter(registry: registry)]))
        await normalizer.normalizeImportedCards(in: container)
        context.rollback()
        let rows = try context.fetch(FetchDescriptor<CollectedCard>())
        let enriched = try XCTUnwrap(rows.first { $0.cardGame == .onePiece })
        let retained = try XCTUnwrap(rows.first { $0.cardGame.rawValue == "future-game" })
        XCTAssertEqual(enriched.catalogProviderID, id)
        XCTAssertEqual(enriched.imageURL, "https://fixture.invalid/art.png")
        XCTAssertEqual(enriched.collectionKey, known.collectionKey)
        XCTAssertEqual(enriched.providerID, id)
        XCTAssertNil(retained.catalogMetadataCheckedAt)
        XCTAssertNil(retained.catalogProviderID)
        XCTAssertNil(retained.imageURL)
        XCTAssertNil(enriched.justTCGCardID)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PriceObservation>()).isEmpty)
    }

    func testNormalizationDiscardsMetadataAfterCollectionPolicyWithdrawal() async throws {
        let registry = try registry()
        let (model, container) = try model(registry: registry, fixtureWritesEnabled: true)
        defer { model.viewDisappeared() }
        let context = container.mainContext
        let id = uuid(1).uuidString.lowercased()
        let row = CollectedCard(collectionKey: "one-piece:\(id)#normal", game: .onePiece, providerID: id,
            name: "Fixture Shanks", setName: "Imported set", setCode: "", cardNumber: "OP01-120",
            rarity: nil, imageURL: nil, thumbnailURL: nil, variant: .normal, variantResolution: .imported)
        context.insert(row)
        try context.save()
        let gate = OnePieceLookupGate()
        let writable = CardGameRegistry(descriptors: [.init(game: .onePiece, displayName: "Fixture", sortOrder: 0,
            capabilities: [.collectionWrite])])
        let normalizer = CollectionCatalogNormalizer(gameRegistry: writable,
            gameImportAdapters: try .init(adapters: [DelayedOnePieceImportAdapter(
                base: OnePieceImportAdapter(registry: registry), gate: gate)]))
        let task = Task { await normalizer.normalizeImportedCards(in: container) }
        await gate.waitForStart()
        CollectionStore.configureGames(.standard, for: container)
        await gate.resume()
        await task.value
        let fresh = ModelContext(container)
        let retained = try XCTUnwrap(fresh.fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(retained.collectionKey, "one-piece:\(id)#normal")
        XCTAssertEqual(retained.providerID, id)
        XCTAssertEqual(retained.setName, "Imported set")
        XCTAssertNil(retained.catalogProviderID)
        XCTAssertNil(retained.catalogMetadataCheckedAt)
        XCTAssertNil(retained.imageURL)
        XCTAssertNil(retained.thumbnailURL)
        XCTAssertTrue(try fresh.fetch(FetchDescriptor<CollectionActivity>()).isEmpty)
        XCTAssertTrue(try fresh.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
        XCTAssertTrue(try fresh.fetch(FetchDescriptor<PriceObservation>()).isEmpty)
        XCTAssertFalse(fresh.hasChanges)
    }

    func testSharedRuntimeImportAndNormalizerUseActivatedPrintingGeneration() async throws {
        let first = try registry(revision: 1), second = try registry(count: 3, revision: 2)
        let key = Curve25519.Signing.PrivateKey()
        let keyID = "one-piece-shared-import-fixture"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnePieceImport-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let seed = try OnePieceCatalogSignature.sign(first.verifiedRelease.release, keyID: keyID, privateKey: key)
        let store = try OnePieceCatalogReleaseStore(root: root, keys: [keyID: key.publicKey], bundledEnvelope: seed, now: now)
        let coordinator = OnePieceCatalogCoordinator(store: store)
        let runtime = CardGameRuntime(descriptor: .init(game: .onePiece, displayName: "Writable fixture", sortOrder: 0,
            capabilities: [.collectionWrite]), variantPolicy: OnePieceVariantPolicy(registry: first),
            importer: OnePieceImportAdapter(registry: first), activationSource: coordinator)
        let runtimes = try CardGameRuntimeContainer(runtimes: [runtime])
        var environment = EnvironmentValues()
        XCTAssertNil(environment.cardGameRuntimes)
        environment.cardGameRuntimes = runtimes
        let shared = try XCTUnwrap(environment.cardGameRuntimes)
        let normalizer = shared.makeCollectionNormalizer() // Created before activation, like a view-owned service.
        let envelope = try OnePieceCatalogSignature.sign(second.verifiedRelease.release, keyID: keyID, privateKey: key)
        guard case .activated = await coordinator.activateEnvelope(envelope, now: now) else { return XCTFail() }
        let adapters = await shared.currentImportAdapters()
        XCTAssertEqual(adapters.adapter(for: .onePiece)?.generation, OnePieceImportAdapter(registry: second).generation)
        let (_, container) = try model(registry: first)
        CollectionStore.configureGames(shared.registry, for: container)
        let id = uuid(3).uuidString.lowercased()
        let plan = try CollectionCSV.parse(Data("game,provider_id,card_name,card_number,finish,quantity\none-piece,\(id),Shanks,OP01-120,normal,1\n".utf8))
        let token = try CollectionWriteSerializer.beginExclusive(timeout: .mainThread)
        let result: CollectionCSVImportResult
        do {
            result = try await CollectionCSV.applyIsolated(plan, to: container, exclusiveToken: token,
                gameRegistry: shared.registry, gameImportAdapters: adapters)
            CollectionWriteSerializer.endExclusive(token)
        } catch {
            CollectionWriteSerializer.endExclusive(token)
            throw error
        }
        XCTAssertEqual(result.importedQuantity, 1)
        XCTAssertTrue(result.failedRows.isEmpty)
        await normalizer.normalizeImportedCards(in: container)
        let row = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(row.providerID, id)
        XCTAssertEqual(row.catalogProviderID, id)
        XCTAssertEqual(row.imageURL, "https://fixture.invalid/art.png")
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PriceObservation>()).isEmpty)
    }

    func testUnknownGameFinishDoesNotBecomePokemonPrintRunDuringCSVPreview() throws {
        let csv = "game,provider_id,card_name,finish,quantity\nfuture-game,physical-id,Card,first-edition,1\n"
        let plan = try CollectionCSV.parse(Data(csv.utf8))
        let entry = try XCTUnwrap(plan.entries.first)
        XCTAssertEqual(entry.game.rawValue, "future-game")
        XCTAssertEqual(entry.variant?.id, "first-edition")
        XCTAssertNil(entry.pokemonPrintRun)
        XCTAssertEqual(entry.collectionKey, "future-game:physical-id#first-edition")
    }

    func testConflictingImportUUIDsNeverBorrowAnotherPrintingsMetadata() async throws {
        let adapter = OnePieceImportAdapter(registry: try registry())
        let wrong = GameImportRequest(sourceProviderID: uuid(1).uuidString.lowercased(),
            catalogProviderID: uuid(2).uuidString.lowercased(), game: .onePiece,
            name: "Shanks", setName: "Fixture", cardNumber: "OP01-120", itemKind: .rawCard)
        let correct = GameImportRequest(sourceProviderID: wrong.sourceProviderID,
            catalogProviderID: wrong.sourceProviderID, game: .onePiece,
            name: wrong.name, setName: wrong.setName, cardNumber: wrong.cardNumber, itemKind: .rawCard)
        XCTAssertNotEqual(wrong.identityKey, correct.identityKey)
        let matches = await adapter.metadata(for: [wrong, correct])
        XCTAssertNil(matches[wrong.identityKey])
        XCTAssertEqual(matches[correct.identityKey]?.providerID, correct.sourceProviderID)
        let graded = GameImportRequest(sourceProviderID: correct.sourceProviderID, catalogProviderID: correct.catalogProviderID,
            game: correct.game, name: correct.name, setName: correct.setName, cardNumber: correct.cardNumber, itemKind: .gradedCard)
        XCTAssertNotEqual(graded.identityKey, correct.identityKey)
    }

    func testBrowsePaginationPreservesAllPrintingsAndRejectsOtherQueryOrGeneration() async throws {
        let registry = try registry(count: 61)
        let adapter = OnePieceBrowseAdapter(registry: registry)
        let first = try await adapter.search(query: "Shanks", setIDs: [], cursor: nil)
        XCTAssertEqual(first.items.count, 60)
        let cursor = try XCTUnwrap(first.nextCursor)
        let last = try await adapter.search(query: "Shanks", setIDs: [], cursor: cursor)
        XCTAssertEqual(last.items.count, 1)
        XCTAssertNil(last.nextCursor)
        XCTAssertEqual(Set((first.items + last.items).map(\.providerID)).count, 61)
        do { _ = try await adapter.search(query: "OP01", setIDs: [], cursor: cursor); XCTFail("Cursor must bind query") }
        catch CatalogLookupError.staleCatalog {}
        let next = OnePieceBrowseAdapter(registry: try self.registry(count: 61, revision: 2))
        do { _ = try await next.search(query: "Shanks", setIDs: [], cursor: cursor); XCTFail("Cursor must bind generation") }
        catch CatalogLookupError.staleCatalog {}
    }

    func testBrowseSetsExposeOnlyVerifiedMemberArtworkForEmptyCollection() async throws {
        let adapter = OnePieceBrowseAdapter(registry: try registry(multiProduct: true))
        let sets = try await adapter.sets()
        XCTAssertFalse(sets.isEmpty)
        for set in sets {
            let page = try await adapter.cards(in: set, cursor: nil)
            let members = Set(page.items.compactMap(\.thumbnailURL))
            let hints = try XCTUnwrap(set.artworkFallbackURLs)
            XCTAssertFalse(hints.isEmpty)
            XCTAssertLessThanOrEqual(hints.count, 3)
            XCTAssertEqual(Set(hints).count, hints.count)
            XCTAssertTrue(Set(hints).isSubset(of: members))
            XCTAssertEqual(PokemonArtworkFallbacks.setSource(for: set, kind: .logo).candidates,
                           hints.map { .remote($0) })
        }
        let rebuilt = try await OnePieceBrowseAdapter(registry: registry(multiProduct: true)).sets()
        XCTAssertEqual(sets, rebuilt)
    }

    func testReviewEvidenceDoesNotBecomeDisplayArtworkHints() async throws {
        let registry = try reviewedAwardRegistry()
        let sets = try await OnePieceBrowseAdapter(registry: registry).sets()
        XCTAssertFalse(sets.isEmpty)
        XCTAssertTrue(sets.allSatisfy { $0.artworkFallbackURLs?.isEmpty == true })
    }

    func testOwnerArtworkOptInUsesExactRecordedImagesAcrossRetainedCorpus() async throws {
        let reviewed = try reviewedAwardRegistry()
        let owner = OnePieceCatalogRegistry(verifiedRelease: reviewed.verifiedRelease, includeRecordedArtwork: true)
        XCTAssertEqual(owner.artworkURLByID.count, reviewed.verifiedRelease.release.registry.artworks.count)
        XCTAssertEqual(owner.generation, reviewed.generation)
        let adapter = OnePieceBrowseAdapter(registry: owner)
        for set in try await adapter.sets() {
            XCTAssertFalse(set.artworkFallbackURLs?.isEmpty ?? true, set.name)
            let page = try await adapter.cards(in: set, cursor: nil)
            for card in page.items {
                let printing = try XCTUnwrap(owner.printingByID[UUID(uuidString: card.providerID)!])
                XCTAssertEqual(card.imageURL, owner.artworkURLByID[printing.artworkID])
            }
        }
        XCTAssertTrue(reviewed.verifiedRelease.release.registry.artworks.allSatisfy { $0.referenceImageURL == nil })
    }

    func testRecordedArtworkRequiresExactReferenceHashAndManufacturerImage() {
        let hash = String(repeating: "a", count: 64)
        let art = OnePieceArtwork(id: uuid(900), imageSHA256: hash, observationIDs: ["render"])
        let url = URL(string: "https://en.onepiece-cardgame.com/images/cardlist/card/OP01-120_p1.png?review")!
        func observation(imageHash: String, source: URL) -> OnePieceSourceObservation {
            .init(id: "render", alias: .init(provider: "bandai", sourceID: "exact-art"),
                  sourceURL: source, observedAt: "2026-10-07T00:00:00Z", language: "en",
                  payloadSHA256: hash, imageSHA256: imageHash)
        }
        XCTAssertEqual(OnePieceCatalogRegistry.recordedArtworkURL(for: art,
            observations: ["render": observation(imageHash: hash, source: url)]), url)
        XCTAssertNil(OnePieceCatalogRegistry.recordedArtworkURL(for: art,
            observations: ["render": observation(imageHash: String(repeating: "b", count: 64), source: url)]))
        XCTAssertNil(OnePieceCatalogRegistry.recordedArtworkURL(for: art,
            observations: ["unrelated": observation(imageHash: hash, source: url)]))
        XCTAssertNil(OnePieceCatalogRegistry.recordedArtworkURL(for: art,
            observations: ["render": observation(imageHash: hash, source: URL(string: "https://example.com/art.png")!)]))
        XCTAssertNil(OnePieceCatalogRegistry.recordedArtworkURL(for: art,
            observations: ["render": observation(imageHash: hash, source: URL(string: "https://en.onepiece-cardgame.com/cardlist/")!)]))
    }

    func testBrowseOwnershipAndCompletionRequireExactPrintingRatherThanSharedNumber() async throws {
        let adapter = OnePieceBrowseAdapter(registry: try registry(multiProduct: true))
        let sets = try await adapter.sets()
        let primary = try XCTUnwrap(sets.first { $0.providerID == "fixture-release-0" })
        let primaryPage = try await adapter.cards(in: primary, cursor: nil)
        let summary = try XCTUnwrap(primaryPage.items.first)
        func row(_ id: String) -> CollectedCard {
            CollectedCard(collectionKey: "one-piece:" + id, game: .onePiece, providerID: id,
                name: summary.name, setName: summary.setName, setCode: summary.setCode,
                cardNumber: summary.collectorNumber, rarity: nil, imageURL: nil, thumbnailURL: nil,
                variant: .normal, variantResolution: .userConfirmed)
        }
        let other = row(uuid(2).uuidString.lowercased())
        XCTAssertFalse(CatalogOwnershipIndex([other]).owns(summary))
        XCTAssertEqual(CatalogOwnershipIndex([other]).quantity(of: summary), 0)
        XCTAssertEqual(CatalogOwnershipIndex([other]).progress(for: primary).owned, 0)
        let exact = row(summary.providerID)
        let index = CatalogOwnershipIndex([exact])
        XCTAssertTrue(index.owns(summary))
        XCTAssertEqual(index.progress(for: primary).owned, 1)
        let bundle = try XCTUnwrap(sets.first { $0.providerID == "fixture-bundle" })
        XCTAssertEqual(index.progress(for: bundle).owned, 1, "One physical copy participates in both product checklists")
        XCTAssertEqual(index.progress(for: bundle).unit, "printings")
        let encoded = try JSONEncoder().encode(summary)
        XCTAssertEqual(try JSONDecoder().decode(CatalogCardSummary.self, from: encoded), summary)
        XCTAssertEqual(try JSONDecoder().decode(CatalogSet.self, from: JSONEncoder().encode(bundle)), bundle)
    }

    func testBrowseActivationInvalidatesDetailsAndRejectsOldSummary() async throws {
        let first = try registry(revision: 1), second = try registry(count: 3, revision: 2, sharedReleaseLabels: true)
        let key = Curve25519.Signing.PrivateKey()
        let keyID = "one-piece-browse-fixture"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnePieceBrowse-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let seed = try OnePieceCatalogSignature.sign(first.verifiedRelease.release, keyID: keyID, privateKey: key)
        let store = try OnePieceCatalogReleaseStore(root: root, keys: [keyID: key.publicKey], bundledEnvelope: seed, now: now)
        let coordinator = OnePieceCatalogCoordinator(store: store)
        let runtimes = try CardGameRuntimeContainer(runtimes: [
            OnePieceGameRuntime(registry: first, coordinator: coordinator).runtime
        ])
        let browse = runtimes.makeBrowseCatalog()
        let initialSets = try await browse.sets(for: .onePiece)
        let set = try XCTUnwrap(initialSets.first)
        let initialPage = try await browse.cards(in: set, cursor: nil)
        let old = try XCTUnwrap(initialPage.items.first)
        _ = try await browse.details(for: old)
        let updates = await browse.catalogUpdates()
        var receivedUpdates: [BrowseCatalogUpdate] = []
        let eventTask = Task { for await update in updates { receivedUpdates.append(update) } }
        let model = BrowseViewModel(catalog: browse, includesSealedProducts: false)
        await model.loadSets()
        let modelTask = Task { await model.observeCatalogUpdates() }
        defer { eventTask.cancel(); modelTask.cancel() }
        model.searchText = "Fixture Shanks"
        let searched = await waitUntil { model.lanes[.onePiece]?.cards.count == 2 }
        XCTAssertTrue(searched)
        let envelope = try OnePieceCatalogSignature.sign(second.verifiedRelease.release, keyID: keyID, privateKey: key)
        guard case .activated = await coordinator.activateEnvelope(envelope, now: now) else { return XCTFail() }
        let sets = try await browse.sets(for: .onePiece)
        XCTAssertEqual(sets.count, 3)
        do { _ = try await browse.details(for: old); XCTFail("Cached detail must not bypass generation validation") }
        catch CatalogLookupError.staleCatalog {}
        let nextSet = try XCTUnwrap(sets.first { $0.catalogID == set.catalogID })
        do { _ = try await browse.cards(in: set, cursor: nil); XCTFail("Old set definition must remain stale") }
        catch CatalogLookupError.staleCatalog {}
        let rebasedSet = try await browse.currentSet(for: set)
        XCTAssertEqual(rebasedSet, nextSet)
        let nextPage = try await browse.cards(in: nextSet, cursor: nil)
        let fresh = try XCTUnwrap(nextPage.items.first)
        let detail = try await browse.details(for: fresh)
        XCTAssertEqual(fresh.catalogGeneration, second.generation)
        XCTAssertEqual(detail.card.physicalPrintingID, old.providerID)
        let liveUpdated = await waitUntil {
            model.sets[.onePiece]?.count == 3 && model.lanes[.onePiece]?.cards.count == 3 &&
                model.lanes[.onePiece]?.cards.allSatisfy { $0.catalogGeneration == second.generation } == true
        }
        XCTAssertTrue(liveUpdated, "An unchanged search must discard old-generation rows and cursors")
        XCTAssertTrue(receivedUpdates.contains { $0.game == .onePiece && $0.revision == 2 })
    }

    func testActivationReachesScannerAndExplicitRecoveryRetryUsesNewGeneration() async throws {
        let first = try registry(revision: 1), second = try registry(count: 3, revision: 2)
        let key = Curve25519.Signing.PrivateKey()
        let keyID = "one-piece-activation-fixture"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnePieceLive-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let seed = try OnePieceCatalogSignature.sign(first.verifiedRelease.release, keyID: keyID, privateKey: key)
        let store = try OnePieceCatalogReleaseStore(root: root, keys: [keyID: key.publicKey],
                                                  bundledEnvelope: seed, now: now)
        let coordinator = OnePieceCatalogCoordinator(store: store)
        let (model, _) = try model(registry: first)
        defer { model.viewDisappeared() }
        model.observeCatalogActivations([coordinator])
        func scannerGeneration() -> String? {
            guard case let .identified(subject) = model.scanner.recognitionOutcomeForTesting(["OP01-120"]) else { return nil }
            return subject.identifier.catalogGeneration
        }
        let initialInstalled = await waitUntil { scannerGeneration() == first.generation }
        XCTAssertTrue(initialInstalled)
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), .init(identifier: try identifier(first)), nil)
        let initialChoice = await waitUntil { model.pendingIdentityChoice != nil }
        XCTAssertTrue(initialChoice)
        model.dismissIdentityChoice()
        let filed = await waitUntil { !model.unresolvedScans.isEmpty }
        XCTAssertTrue(filed)
        let rowID = try XCTUnwrap(model.unresolvedScans.first?.id)
        let envelope = try OnePieceCatalogSignature.sign(second.verifiedRelease.release, keyID: keyID, privateKey: key)
        guard case .activated = await coordinator.activateEnvelope(envelope, now: now) else {
            return XCTFail("Expected durable activation")
        }
        let updated = await waitUntil { scannerGeneration() == second.generation }
        XCTAssertTrue(updated)
        let recoveryLoaded = await waitUntil { model.unresolvedScans.contains { $0.id == rowID && !$0.isReadOnly } }
        XCTAssertTrue(recoveryLoaded)
        XCTAssertEqual(model.unresolvedScans.first { $0.id == rowID }?.subject.identifier.catalogGeneration, first.generation)
        model.resolveUnresolved(id: rowID, choice: .retryLookup)
        let newChoice = await waitUntil { model.pendingIdentityChoice?.displayCandidates.count == 3 }
        XCTAssertTrue(newChoice)
        XCTAssertEqual(model.pendingIdentityChoice?.identifier.catalogGeneration, second.generation)
        XCTAssertTrue(model.pendingIdentityChoice?.displayCandidates.allSatisfy {
            $0.catalogGeneration == second.generation
        } == true)
    }

    func testRetryPreservesEvidenceAndRejectsUnrecognizedIdentifierSemantics() throws {
        let first = try registry(revision: 1), second = try registry(revision: 2)
        let old = try identifier(first, confirmedEnglish: true)
        let adapter = OnePieceCatalogAdapter(registry: second)
        let retry = try adapter.identifierForRetry(old)
        XCTAssertEqual(retry.fields, old.fields)
        XCTAssertEqual(retry.suppressionIdentity, old.suppressionIdentity)
        XCTAssertEqual(retry.catalogGeneration, second.generation)
        let future = try ScanIdentifier(game: .onePiece, namespace: old.namespace,
            fields: old.fields + [.init(key: "futureIdentityRule", value: "new")],
            displayIdentifier: old.displayIdentifier, suppressionIdentity: old.suppressionIdentity,
            catalogGeneration: first.generation)
        XCTAssertThrowsError(try adapter.identifierForRetry(future))
    }

    func testActivationRejectsLookupCompletingFromPreviousGeneration() async throws {
        let first = try registry(revision: 1), second = try registry(revision: 2)
        let gate = OnePieceLookupGate()
        let catalog = CardCatalog(gameCatalogAdapters: try .init(adapters: [
            DelayedOnePieceCatalogAdapter(base: .init(registry: first), gate: gate)
        ]))
        let scan = try identifier(first)
        let lookup = Task { try await catalog.lookupOutcome(for: scan) }
        await gate.waitForStart()
        await catalog.install(OnePieceCatalogAdapter(registry: second))
        await gate.resume()
        do { _ = try await lookup.value; XCTFail("Old completion must not publish choices") }
        catch CatalogLookupError.staleCatalog {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testLookupChoiceAndRetryRejectTheSameMalformedIdentitySemantics() async throws {
        let registry = try registry(), adapter = OnePieceCatalogAdapter(registry: registry)
        let valid = try identifier(registry)
        guard case let .needsPrintingChoice(_, candidates) = try await adapter.lookup(valid) else { return XCTFail() }
        let payloads: [[ScanIdentityField]] = [
            valid.fields + [.init(key: "futureIdentityRule", value: "new")],
            [.init(key: "number", value: "OP01-120"), .init(key: "language", value: "jp")],
            [.init(key: "number", value: "OP01-120"), .init(key: "languageConfirmation", value: "inferred")],
            [.init(key: "number", value: "OP01-120"), .init(key: "language", value: "unknown"),
             .init(key: "languageConfirmation", value: "user-confirmed")],
            [.init(key: "number", value: "op01-120")]
        ]
        var malformed = try payloads.map { fields in
            try ScanIdentifier(game: .onePiece, namespace: valid.namespace, fields: fields,
                displayIdentifier: valid.displayIdentifier, suppressionIdentity: valid.suppressionIdentity,
                catalogGeneration: registry.generation)
        }
        malformed.append(try ScanIdentifier(game: .onePiece, namespace: valid.namespace, fields: valid.fields,
            displayIdentifier: valid.displayIdentifier, suppressionIdentity: "number:P-001",
            catalogGeneration: registry.generation))
        for identity in malformed {
            XCTAssertThrowsError(try adapter.identifierForRetry(identity))
            do { _ = try await adapter.lookup(identity); XCTFail("Live lookup accepted invalid semantics") }
            catch CatalogLookupError.invalidAdapterOutcome {}
            do { _ = try await adapter.resolve(candidates[0], for: identity); XCTFail("Choice accepted invalid semantics") }
            catch CatalogLookupError.invalidAdapterOutcome {}
        }
    }

    func testMalformedRecoveryEvidenceRemainsReadOnlyWithAnInstalledAdapter() async throws {
        let registry = try registry(), valid = try identifier(registry)
        let identity = try ScanIdentifier(game: .onePiece, namespace: valid.namespace,
            fields: valid.fields + [.init(key: "futureIdentityRule", value: "new")],
            displayIdentifier: valid.displayIdentifier, suppressionIdentity: valid.suppressionIdentity,
            catalogGeneration: registry.generation)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnePieceInvalidRecovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UnresolvedScanStore(fileURL: root.appendingPathComponent("recovery.json"))
        let row = UnresolvedScan(subject: .init(identifier: identity), reason: .noConfirmedMatch)
        let saved = await store.save([row])
        XCTAssertTrue(saved)
        let restored = await store.load(gameCatalogAdapters: try .init(adapters: [OnePieceCatalogAdapter(registry: registry)]))
        let preserved = try XCTUnwrap(restored.first)
        XCTAssertTrue(preserved.isReadOnly)
        XCTAssertEqual(preserved.identifier.fields, identity.fields)
        XCTAssertEqual(preserved.id, row.id)
    }

    func testRetrySaveAfterRelaunchRebasesEvidenceAndAsksForPrintingAgain() async throws {
        let first = try registry(revision: 1), second = try registry(count: 3, revision: 2)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnePieceSaveRetry-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UnresolvedScanStore(fileURL: root.appendingPathComponent("recovery.json"))
        let row = UnresolvedScan(subject: .init(identifier: try identifier(first)),
            reason: .saveFailed(inMemoryCandidateID: UUID()), resolvedProviderID: uuid(1).uuidString.lowercased())
        let saved = await store.save([row])
        XCTAssertTrue(saved)
        let (model, container) = try model(registry: second, fixtureWritesEnabled: true, unresolvedScanStore: store)
        defer { model.viewDisappeared() }
        let loaded = await waitUntil { model.unresolvedScans.contains { $0.id == row.id && !$0.isReadOnly } }
        XCTAssertTrue(loaded)
        let restored = try XCTUnwrap(model.unresolvedScans.first { $0.id == row.id })
        XCTAssertNil(restored.pendingCommit)
        XCTAssertEqual(restored.identifier.catalogGeneration, first.generation)
        model.resolveUnresolved(id: row.id, choice: .retrySave)
        let presented = await waitUntil { model.pendingIdentityChoice != nil }
        XCTAssertTrue(presented)
        let choice = try XCTUnwrap(model.pendingIdentityChoice)
        XCTAssertEqual(choice.identifier.catalogGeneration, second.generation)
        XCTAssertEqual(choice.displayCandidates.count, 3)
        XCTAssertTrue(choice.displayCandidates.allSatisfy { $0.catalogGeneration == second.generation })
        XCTAssertNil(model.pendingChoice, "A saved printing hint must not bypass a new physical choice")
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        let selected = try XCTUnwrap(choice.displayCandidates.first { $0.id == uuid(3).uuidString.lowercased() })
        model.choose(selected)
        let finish = await waitUntil { model.pendingChoice != nil }
        XCTAssertTrue(finish)
        model.choose(.normal)
        let committed = await waitUntil { model.successCount == 1 && model.unresolvedScans.isEmpty }
        XCTAssertTrue(committed)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).first?.catalogProviderID, selected.id)
    }

    func testIncompleteNumberRecoversAfterRelaunchWithALaterVerifiedCatalog() async throws {
        let first = try registry(), previous = first.verifiedRelease.release, state = previous.registry
        let number = "OP01-999"
        let canonical = OnePieceCanonicalCard(printedNumber: number, language: "en", name: "Later fixture card")
        let productID = "fixture-release-0"
        let observation = OnePieceProviderNormalizer.observation(provider: .bandai, capture: .init(
            observationID: "later-number-observation", sourceID: "later-number-row",
            sourceURL: URL(string: "https://fixture.invalid/later")!, observedAt: date, language: "en",
            payloadBytes: Data("later synthetic card".utf8), imageBytes: Data("fixture art".utf8),
            productEvidence: [productID], printedEvidence: ["number": number, "finishVariantID": "normal"]))
        let review = OnePieceReview(reference: "later-number-review", evidence:
            [OnePieceEvidenceKind.printedIdentity, .language, .artwork, .release, .finish].map {
                .init(kind: $0, observationID: observation.id, detail: "Synthetic fixture evidence")
            })
        let printing = OnePiecePhysicalPrinting(id: uuid(99), canonicalCardID: canonical.id, artworkID: uuid(900),
            language: "en", releaseID: productID, supportedVariantIDs: ["normal"],
            status: .verified, review: review, sourceAliases: [observation.alias])
        let release = try OnePieceCatalogBuilder.build(registry: .init(canonicalCards: state.canonicalCards + [canonical],
            artworks: state.artworks, printings: state.printings + [printing], variants: state.variants,
            products: state.products, appearances: state.appearances, corrections: state.corrections),
            observations: previous.observations + [observation], inventories: previous.inventories + [
                .init(provider: "bandai", snapshotID: "later-fixture-snapshot", paginationComplete: true,
                      observationIDs: [observation.id])
            ],
            revision: 2, generatedAt: date, previous: previous)
        let key = Curve25519.Signing.PrivateKey()
        let envelope = try OnePieceCatalogSignature.sign(release, keyID: "one-piece-later-fixture", privateKey: key)
        let second = OnePieceCatalogRegistry(verifiedRelease: try OnePieceCatalogSignature.verify(envelope,
            trustedKeys: ["one-piece-later-fixture": key.publicKey], now: now))
        guard case let .identified(subject) = OnePieceScanProfile(registry: first).identify([.init(text: number)]) else {
            return XCTFail()
        }
        guard case .catalogIncomplete(nil) = try await OnePieceCatalogAdapter(registry: first).lookup(subject.identifier) else {
            return XCTFail()
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnePieceLaterRecovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UnresolvedScanStore(fileURL: root.appendingPathComponent("recovery.json"))
        let row = UnresolvedScan(subject: subject, reason: .noCatalogEntry)
        let saved = await store.save([row])
        XCTAssertTrue(saved)
        let (model, container) = try model(registry: second, fixtureWritesEnabled: true, unresolvedScanStore: store)
        defer { model.viewDisappeared() }
        let loaded = await waitUntil { model.unresolvedScans.contains { $0.id == row.id && !$0.isReadOnly } }
        XCTAssertTrue(loaded)
        model.resolveUnresolved(id: row.id, choice: .retryLookup)
        let committed = await waitUntil { model.successCount == 1 && model.unresolvedScans.isEmpty }
        XCTAssertTrue(committed)
        XCTAssertNil(model.pendingIdentityChoice)
        XCTAssertNil(model.pendingChoice)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).first?.providerID,
                       uuid(99).uuidString.lowercased())
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).first?.cardNumber, number)
    }

    #if DEBUG
    func testDiskBackedOnePieceScannerSaveFailureRetriesOnceInSameSession() async throws {
        try await assertScannerFailureRecovery(relaunch: false)
    }

    func testDiskBackedOnePieceScannerSaveFailureRevalidatesAfterRelaunch() async throws {
        try await assertScannerFailureRecovery(relaunch: true)
    }

    private func assertScannerFailureRecovery(relaunch: Bool) async throws {
        let registry = try registry()
        let root = failureRoot("Scanner")
        let container = try failureContainer(at: root)
        let runtimes = try failureRuntimes(registry)
        runtimes.configureCollectionAuthority(for: container, configurePricing: false)
        let adapter = OnePieceCatalogAdapter(registry: registry)
        let recoveryAdapters = try GameCatalogAdapterRegistry(adapters: [adapter])
        let unrelated = try adapter.resolution(forPrintingID: uuid(2)).card
        try CollectionWriteSerializer.perform(container: container, timeout: .wait) { context in
            _ = try CollectionStore(context: context).add(unrelated,
                resolved: .init(variant: .normal, resolution: .userConfirmed))
        }
        let before = try failureSnapshot(container)
        let recoveryURL = root.appendingPathComponent("recovery.json")
        let recovery = UnresolvedScanStore(fileURL: recoveryURL)
        let writer = ScannerCollectionWriter(modelContainer: container)
        await writer.setSaveOverrideForTesting { throw OnePieceInjectedSaveFailure() }
        let first = ScannerViewModel(gameRegistry: runtimes.registry, catalog: runtimes.makeCardCatalog(),
            unresolvedScanStore: recovery, collectionAddOverride: { try await writer.add($0) })
        first.start(context: container.mainContext, startCamera: false, shouldRefreshMagicDirectory: false)
        defer { first.viewDisappeared() }
        first.scanner.onConfirmedSubjectCandidate?(nil, UUID(), .init(identifier: try identifier(registry)), nil)
        let choosingPrinting = await waitUntil { first.pendingIdentityChoice != nil }
        XCTAssertTrue(choosingPrinting)
        first.choose(try XCTUnwrap(first.pendingIdentityChoice?.displayCandidates.first { $0.id == uuid(1).uuidString.lowercased() }))
        let choosingFinish = await waitUntil { first.pendingChoice != nil }
        XCTAssertTrue(choosingFinish)
        first.choose(.foil)
        let failed = await waitUntil {
            first.scanAcknowledgement?.phase == .failed && !first.isIdentificationProcessingForTesting
                && first.unresolvedScans.count == 1
        }
        XCTAssertTrue(failed)
        XCTAssertEqual(first.successCount, 0)
        let unresolved = try XCTUnwrap(first.unresolvedScans.first)
        guard case .saveFailed = unresolved.reason else { return XCTFail("Actual save failure must retain recovery") }
        XCTAssertNotNil(unresolved.pendingCommit)
        XCTAssertEqual(try failureSnapshot(container), before)
        XCTAssertEqual(try failureSnapshot(failureContainer(at: root)), before)
        let flushed = await recovery.save(first.unresolvedScans)
        XCTAssertTrue(flushed)
        let diskRecovery = await UnresolvedScanStore(fileURL: recoveryURL).load(gameCatalogAdapters: recoveryAdapters)
        XCTAssertEqual(diskRecovery.map(\.id), [unresolved.id])
        XCTAssertNil(diskRecovery.first?.pendingCommit, "A disk record cannot retain the memory-only commit")

        // Use the same writer after the failure. Its next successful save must
        // not carry the failed transaction into another printing's acquisition.
        let unrelatedScan = ResolvedScan(request: .init(subject: .init(identifier: try identifier(registry)),
            purpose: .collection, generation: 1, encounterID: UUID()), card: unrelated,
            resolved: .init(variant: .normal, resolution: .userConfirmed), pokemonPrintRun: nil, options: [.normal])
        _ = try await writer.add(.init(resolvedScan: unrelatedScan))
        let afterOtherSave = ModelContext(container)
        let unrelatedRows = try afterOtherSave.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(unrelatedRows.count, 1)
        XCTAssertEqual(unrelatedRows.first?.providerID, unrelated.providerID)
        XCTAssertEqual(unrelatedRows.first?.quantity, 2)
        XCTAssertEqual(try afterOtherSave.fetch(FetchDescriptor<InventoryEvent>()).count, 2)

        let active: ScannerViewModel
        let activeContainer: ModelContainer
        let activeRecovery: UnresolvedScanStore
        if relaunch {
            first.viewDisappeared()
            activeContainer = try failureContainer(at: root)
            runtimes.configureCollectionAuthority(for: activeContainer, configurePricing: false)
            activeRecovery = UnresolvedScanStore(fileURL: recoveryURL)
            active = ScannerViewModel(gameRegistry: runtimes.registry, catalog: runtimes.makeCardCatalog(),
                unresolvedScanStore: activeRecovery)
            active.start(context: activeContainer.mainContext, startCamera: false, shouldRefreshMagicDirectory: false)
            let loaded = await waitUntil { active.unresolvedScans.contains { $0.id == unresolved.id && !$0.isReadOnly } }
            XCTAssertTrue(loaded)
            active.resolveUnresolved(id: unresolved.id, choice: .retrySave)
            let printings = await waitUntil { active.pendingIdentityChoice != nil }
            XCTAssertTrue(printings, "Relaunch must revalidate and ask for the printing")
            XCTAssertEqual(active.successCount, 0)
            active.choose(try XCTUnwrap(active.pendingIdentityChoice?.displayCandidates.first {
                $0.id == uuid(1).uuidString.lowercased()
            }))
            let finishes = await waitUntil { active.pendingChoice != nil }
            XCTAssertTrue(finishes)
            active.choose(.foil)
        } else {
            active = first
            activeContainer = container
            activeRecovery = recovery
            active.resolveUnresolved(id: unresolved.id, choice: .retrySave)
        }
        defer { active.viewDisappeared() }
        let saved = await waitUntil { active.successCount == 1 && active.unresolvedScans.isEmpty
            && !active.isIdentificationProcessingForTesting }
        XCTAssertTrue(saved)
        let reopened = try failureContainer(at: root)
        let rows = try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>())
        let target = try XCTUnwrap(rows.first { $0.providerID == uuid(1).uuidString.lowercased() })
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(target.quantity, 1)
        XCTAssertEqual(target.variantID, "foil")
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<InventoryEvent>()).count, 3)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<CollectionActivity>()).filter {
            $0.kind.hasQuantityClaim
        }.count, 3)
        active.resolveUnresolved(id: unresolved.id, choice: .retrySave)
        XCTAssertEqual(try failureSnapshot(activeContainer), try failureSnapshot(reopened))
        let finalFlush = await activeRecovery.save(active.unresolvedScans)
        XCTAssertTrue(finalFlush)
        let finalRecovery = await UnresolvedScanStore(fileURL: recoveryURL).load(gameCatalogAdapters: recoveryAdapters)
        XCTAssertTrue(finalRecovery.isEmpty)
    }

    func testDiskBackedOnePieceIncrementFailurePreservesQuantityAndClaims() async throws {
        let registry = try registry()
        let root = failureRoot("Increment")
        let container = try failureContainer(at: root)
        try failureRuntimes(registry).configureCollectionAuthority(for: container, configurePricing: false)
        let card = try OnePieceCatalogAdapter(registry: registry).resolution(forPrintingID: uuid(1)).card
        let scan = ResolvedScan(request: .init(subject: .init(identifier: try identifier(registry)),
            purpose: .collection, generation: 1, encounterID: UUID()), card: card,
            resolved: .init(variant: .foil, resolution: .userConfirmed), pokemonPrintRun: nil, options: [.foil])
        let candidate = CollectionCommitCandidate(resolvedScan: scan)
        let writer = ScannerCollectionWriter(modelContainer: container)
        _ = try await writer.add(candidate)
        let before = try failureSnapshot(container)
        await writer.setSaveOverrideForTesting { throw OnePieceInjectedSaveFailure() }
        do {
            _ = try await writer.add(candidate)
            XCTFail("Injected final save must fail")
        } catch is OnePieceInjectedSaveFailure {}
        XCTAssertEqual(try failureSnapshot(container), before)
        XCTAssertEqual(try failureSnapshot(failureContainer(at: root)), before)
        _ = try await writer.add(candidate)
        let reopened = try failureContainer(at: root)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 2)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<InventoryEvent>()).count, 2)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<CollectionActivity>()).count, 2)
    }

    func testDiskBackedOnePieceFinishCorrectionFailuresRollbackEveryEntryPoint() throws {
        let registry = try registry()
        let runtimes = try failureRuntimes(registry)
        let card = try OnePieceCatalogAdapter(registry: registry).resolution(forPrintingID: uuid(1)).card
        let unrelated = try OnePieceCatalogAdapter(registry: registry).resolution(forPrintingID: uuid(2)).card
        // Three entry points, each with an absent and an already-owned destination.
        for entryPoint in 0..<3 {
            for existingDestination in [false, true] {
                let root = failureRoot("Correction")
                let sourceFilename = root.lastPathComponent + "-source.jpg"
                let destinationFilename = root.lastPathComponent + "-destination.jpg"
                let container = try failureContainer(at: root)
                runtimes.configureCollectionAuthority(for: container, configurePricing: false)
                let acquisitions = try CollectionWriteSerializer.perform(container: container, timeout: .wait) { context in
                    let store = CollectionStore(context: context)
                    let first = try store.add(card, resolved: .init(variant: .normal, resolution: .userConfirmed))
                    var claims = [first]
                    if entryPoint == 2 {
                        claims.append(try store.add(card, resolved: .init(variant: .normal, resolution: .userConfirmed)))
                    }
                    if existingDestination {
                        _ = try store.add(card, resolved: .init(variant: .foil, resolution: .userConfirmed), quantity: 2)
                    }
                    _ = try store.add(unrelated, resolved: .init(variant: .normal, resolution: .userConfirmed))
                    context.insert(LocalArtworkOverride(collectionKey: first.collectionKey, filename: sourceFilename))
                    if existingDestination {
                        context.insert(LocalArtworkOverride(collectionKey: card.collectionKey(variant: .foil),
                            filename: destinationFilename))
                    }
                    try context.save()
                    return claims
                }
                let before = try failureSnapshot(container)
                let quantityBefore = try ModelContext(container).fetch(FetchDescriptor<CollectedCard>())
                    .reduce(0) { $0 + $1.quantity }
                func correct(_ context: ModelContext, fail: Bool) throws -> CollectionMutation? {
                    let store = fail ? CollectionStore(context: context, beforeSaveForTesting: { staged in
                        XCTAssertTrue(staged.hasChanges)
                        throw OnePieceInjectedSaveFailure()
                    }) : CollectionStore(context: context)
                    let first = acquisitions[0]
                    let resolved = ResolvedVariant(variant: .foil, resolution: .userConfirmed)
                    // This is the writer's existing price-staging order: an
                    // actual observation and the correction share one save.
                    _ = PriceStore(context: context).store(.price(.init(unitMarketPriceUSD: 8.16,
                        currencyCode: "USD", source: .tcgCSV, sourceVariantID: "fixture-foil",
                        sourceUpdatedAt: nil, fetchedAt: .now)), game: .onePiece,
                        printingID: card.providerID, variantID: "foil")
                    switch entryPoint {
                    case 0:
                        return try store.recordVariantCorrection(for: card, from: .normal, to: resolved,
                            previousCollectionKey: first.collectionKey, previousLedgerOperationIDs: first.ledgerOperationIDs,
                            activityID: first.activityID, quantity: 1)
                    case 1:
                        return try store.recordVariantCorrection(forCollectionKey: first.collectionKey,
                            to: resolved, activityID: try XCTUnwrap(first.activityID), quantity: 1)
                    default:
                        let row = try XCTUnwrap(store.card(forKey: first.collectionKey))
                        return try store.recordVariantCorrection(for: row, to: resolved,
                            claims: try acquisitions.map { .init(activityID: try XCTUnwrap($0.activityID), quantity: 1) },
                            source: .correction, mode: .visibleCorrection)
                    }
                }
                var failedContext: ModelContext?
                XCTAssertThrowsError(try CollectionWriteSerializer.perform(container: container, timeout: .wait) {
                    failedContext = $0
                    return try correct($0, fail: true)
                }) { XCTAssertTrue($0 is OnePieceInjectedSaveFailure) }
                XCTAssertFalse(try XCTUnwrap(failedContext).hasChanges)
                XCTAssertEqual(try failureSnapshot(container), before)
                XCTAssertEqual(try failureSnapshot(failureContainer(at: root)), before)
                // A subsequent successful transaction must not leak the failed move.
                try CollectionWriteSerializer.perform(container: container, timeout: .wait) { try $0.save() }
                XCTAssertEqual(try failureSnapshot(container), before)
                let mutation = try CollectionWriteSerializer.perform(container: container, timeout: .wait) {
                    try correct($0, fail: false)
                }
                XCTAssertNotNil(mutation)
                let reopened = try failureContainer(at: root), context = reopened.mainContext
                let rows = try context.fetch(FetchDescriptor<CollectedCard>())
                XCTAssertEqual(rows.reduce(0) { $0 + $1.quantity }, quantityBefore)
                XCTAssertFalse(rows.contains { $0.collectionKey == acquisitions[0].collectionKey })
                let destination = try XCTUnwrap(rows.first { $0.collectionKey == card.collectionKey(variant: .foil) })
                XCTAssertEqual(destination.quantity, acquisitions.count + (existingDestination ? 2 : 0))
                let events = try context.fetch(FetchDescriptor<InventoryEvent>())
                let legs = events.filter { $0.kindRaw == InventoryEventKind.correction.rawValue }
                XCTAssertEqual(legs.count, acquisitions.count * 2)
                XCTAssertEqual(legs.reduce(0) { $0 + $1.deltaQuantity }, 0)
                for pair in Dictionary(grouping: legs, by: \.operationID).values {
                    XCTAssertEqual(pair.count, 2)
                    XCTAssertEqual(Set(pair.compactMap(\.legRaw)), Set(["from", "to"]))
                }
                let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
                for acquisition in acquisitions {
                    let claim = try XCTUnwrap(activities.first { $0.id == acquisition.activityID })
                    XCTAssertEqual(claim.collectionKey, destination.collectionKey)
                    XCTAssertEqual(claim.remainingQuantity, 1)
                    XCTAssertEqual(claim.ledgerOperationIDs.count, acquisition.ledgerOperationIDs.count + 1)
                }
                let artwork = try context.fetch(FetchDescriptor<LocalArtworkOverride>())
                // Source artwork remains deliberately recoverable for undo.
                XCTAssertEqual(artwork.count, 2)
                XCTAssertEqual(artwork.first { $0.collectionKey == acquisitions[0].collectionKey }?.filename, sourceFilename)
                XCTAssertEqual(artwork.first { $0.collectionKey == destination.collectionKey }?.filename,
                    existingDestination ? destinationFilename : sourceFilename)
                XCTAssertEqual(try context.fetch(FetchDescriptor<PriceObservation>()).count, 1)
            }
        }
    }

    func testDiskBackedOnePieceWithdrawalFailureRetainsAuthorityUntilRetry() async throws {
        let first = try registry(complete: false, withMarketMapping: true)
        let second = try registry(complete: false, revision: 2, firstStatus: .quarantined)
        let root = failureRoot("Withdrawal")
        let container = try failureContainer(at: root)
        let key = Curve25519.Signing.PrivateKey(), keyID = "one-piece-save-failure-fixture"
        let seed = try OnePieceCatalogSignature.sign(first.verifiedRelease.release, keyID: keyID, privateKey: key)
        let releaseStore = try OnePieceCatalogReleaseStore(root: root.appendingPathComponent("catalog"),
            keys: [keyID: key.publicKey], bundledEnvelope: seed, now: now)
        let coordinator = OnePieceCatalogCoordinator(store: releaseStore)
        let raw = try CardGameRuntimeContainer(runtimes: [OnePieceGameRuntime(registry: first, coordinator: coordinator,
            capabilities: [.scan, .browse, .pricing, .collectionWrite]).runtime])
        let bound = try await raw.bound(to: container)
        let publication = try XCTUnwrap(bound.runtime(for: .onePiece)?.activationSource as? CollectionAuthorizedActivationSource)
        let initial = await publication.currentSnapshot()
        XCTAssertEqual(initial?.revision, 1)
        let card = try OnePieceCatalogAdapter(registry: first).resolution(forPrintingID: uuid(1)).card
        try CollectionWriteSerializer.perform(container: container, timeout: .wait) { context in
            _ = try CollectionStore(context: context).add(card, resolved: .init(variant: .normal, resolution: .userConfirmed))
        }
        let quote = try await OnePiecePriceAdapter(registry: first, source: OnePieceTestPriceSource())
            .refreshStoredPrinting(card.providerID, variant: .foil)
        let prices = PriceStore(context: container.mainContext)
        XCTAssertTrue(prices.store(quote, game: .onePiece, printingID: card.providerID, variantID: "foil"))
        XCTAssertTrue(prices.save())
        _ = QuoteCache(context: container.mainContext).store(quote, game: .onePiece,
            printingID: card.providerID, variantID: "foil")
        let manual = PriceLookup.price(.init(unitMarketPriceUSD: 22, currencyCode: "USD", source: .importedCSV,
            sourceVariantID: "owner-fixture", sourceUpdatedAt: nil, fetchedAt: .now))
        XCTAssertTrue(prices.store(manual, game: .onePiece, printingID: card.providerID, variantID: "normal"))
        XCTAssertTrue(prices.save())
        _ = QuoteCache(context: container.mainContext).store(manual, game: .onePiece,
            printingID: card.providerID, variantID: "normal")
        let before = try failureSnapshot(container)
        let failedSave = expectation(description: "Streamed activation attempts the withdrawal save")
        let rejectedPublication = expectation(description: "Failed revision must not be yielded")
        rejectedPublication.isInverted = true
        publication.setBeforeSaveForTesting { context in
            XCTAssertTrue(context.hasChanges)
            failedSave.fulfill()
            throw OnePieceInjectedSaveFailure()
        }
        let stream = await publication.activationSnapshots()
        var observed: [Int] = []
        let observation = Task { @MainActor in
            for await snapshot in stream {
                observed.append(snapshot.revision)
                if snapshot.revision == 2 { rejectedPublication.fulfill() }
            }
        }
        defer { observation.cancel() }
        let envelope = try OnePieceCatalogSignature.sign(second.verifiedRelease.release, keyID: keyID, privateKey: key)
        guard case .activated = await coordinator.activateEnvelope(envelope, now: now) else { return XCTFail() }
        await fulfillment(of: [failedSave], timeout: 5)
        await fulfillment(of: [rejectedPublication], timeout: 0.1)
        XCTAssertFalse(observed.contains(2))
        publication.setBeforeSaveForTesting { _ in throw OnePieceInjectedSaveFailure() }
        let rejected = await publication.currentSnapshot()
        XCTAssertNil(rejected)
        XCTAssertEqual(try failureSnapshot(container), before)
        XCTAssertEqual(try failureSnapshot(failureContainer(at: root)), before)
        XCTAssertFalse(CollectionStore.canInstallCatalogAdapter(OnePieceCatalogAdapter(registry: second), revision: 1, for: container))
        XCTAssertTrue(CollectionStore.canInstallCatalogAdapter(OnePieceCatalogAdapter(registry: first), revision: 1, for: container))
        // A supported correction still reaches the old authority's commit
        // boundary; roll it back deliberately so ownership stays unchanged.
        let claimID = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<CollectionActivity>()).first?.id)
        XCTAssertThrowsError(try CollectionWriteSerializer.perform(container: container, timeout: .wait) { context in
            try CollectionStore(context: context, beforeSaveForTesting: { _ in throw OnePieceInjectedSaveFailure() })
                .recordVariantCorrection(forCollectionKey: card.collectionKey(variant: .normal),
                    to: .init(variant: .foil, resolution: .userConfirmed), activityID: claimID, quantity: 1)
        }) { XCTAssertTrue($0 is OnePieceInjectedSaveFailure) }
        XCTAssertEqual(try failureSnapshot(container), before)
        publication.setBeforeSaveForTesting(nil)
        let retry = await publication.currentSnapshot()
        XCTAssertEqual(retry?.revision, 2)
        let context = ModelContext(container)
        XCTAssertNil(PriceStore(context: context).record(forKey: PriceRecord.key(game: .onePiece,
            printingID: card.providerID, variantID: "foil"))?.effectiveUnitMarketPriceUSD)
        XCTAssertNil(QuoteCache(context: context).quote(game: .onePiece, printingID: card.providerID, variantID: "foil")?.effectiveAmount)
        XCTAssertEqual(PriceStore(context: context).record(forKey: PriceRecord.key(game: .onePiece,
            printingID: card.providerID, variantID: "normal"))?.effectiveUnitMarketPriceUSD, 22)
        XCTAssertEqual(QuoteCache(context: context).quote(game: .onePiece, printingID: card.providerID, variantID: "normal")?.effectiveAmount, 22)
        XCTAssertThrowsError(try retry?.catalog.validateVariantCorrection(printingID: card.providerID, variantID: "foil"))
        let after = try failureSnapshot(container)
        let ownershipPrefixes = ["row:", "activity:", "event:", "artwork:"]
        XCTAssertEqual(after.filter { value in ownershipPrefixes.contains { value.hasPrefix($0) } },
                       before.filter { value in ownershipPrefixes.contains { value.hasPrefix($0) } })
        let repeated = await publication.currentSnapshot()
        XCTAssertEqual(repeated?.revision, 2)
        XCTAssertEqual(try failureSnapshot(container), after)
        XCTAssertEqual(try failureSnapshot(failureContainer(at: root)), after)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PriceObservation>()).filter { $0.kind == .explicitInvalidation }.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<InventoryEvent>()).count, 1)
    }

    private func failureRuntimes(_ registry: OnePieceCatalogRegistry) throws -> CardGameRuntimeContainer {
        try CardGameRuntimeContainer(runtimes: [OnePieceGameRuntime(registry: registry,
            capabilities: [.scan, .browse, .collectionWrite]).runtime])
    }

    private func failureRoot(_ label: String) -> URL {
        let configured = ProcessInfo.processInfo.environment["ONE_PIECE_SAVE_FAILURE_ROOT"]
        let base = configured.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        // Keep these small synthetic stores as evidence until the runner exits;
        // unlinking SQLite files while a container is alive invalidates its FDs.
        return base.appendingPathComponent("OnePieceSaveFailure-\(label)-\(UUID())", isDirectory: true)
    }

    private func failureContainer(at root: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try CollectionStorageBootstrapDependencies.makeContainer(
            paths: .production(resolvedApplicationSupportURL: root), mode: .onDevice)
    }

    /// Values read from a fresh context survive deletion/rollback of model objects.
    private func failureSnapshot(_ container: ModelContainer) throws -> [String] {
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<CollectedCard>()).map {
            "row:\($0.collectionKey):\($0.providerID):\($0.quantity):\($0.variantID ?? "-"):\($0.variantResolutionRaw ?? "-"):\($0.dateAdded):\($0.userArtworkFilename ?? "-")"
        }
        let activities = try context.fetch(FetchDescriptor<CollectionActivity>()).map {
            "activity:\($0.id):\($0.collectionKey):\($0.variantID ?? "-"):\($0.deltaQuantity):\($0.resolvedQuantity):\($0.ledgerOperationIDs):\(String(describing: $0.correctedAt))"
        }
        let events = try context.fetch(FetchDescriptor<InventoryEvent>()).map {
            "event:\($0.eventID):\($0.operationID):\($0.collectionKey):\($0.priceStorageKey):\($0.deltaQuantity):\($0.idempotencyKey):\(String(describing: $0.unitPriceUSDTenThousandths))"
        }
        let prices = try context.fetch(FetchDescriptor<PriceRecord>()).map {
            "price:\($0.key):\(String(describing: $0.unitMarketPriceUSD)):\($0.sourceRaw ?? "-"):\(String(describing: $0.fetchedAt)):\(String(describing: $0.lastCheckedAt)):\(String(describing: $0.invalidatedAt)):\($0.catalogPriceIdentity ?? "-")"
        }
        let quotes = try context.fetch(FetchDescriptor<ReferenceQuote>()).map {
            "quote:\($0.key):\(String(describing: $0.amount)):\($0.sourceRaw ?? "-"):\(String(describing: $0.retrievedAt)):\(String(describing: $0.invalidatedAt)):\($0.catalogPriceIdentity ?? "-")"
        }
        let observations = try context.fetch(FetchDescriptor<PriceObservation>()).map {
            "observation:\($0.id):\($0.instrumentKey):\($0.kindRaw):\(String(describing: $0.amountUSDTenThousandths)):\($0.sourceRaw):\($0.receivedAt)"
        }
        let artwork = try context.fetch(FetchDescriptor<LocalArtworkOverride>()).map {
            "artwork:\($0.collectionKey):\($0.filename):\($0.updatedAt)"
        }
        let checks = try context.fetch(FetchDescriptor<PriceCheckDay>()).map {
            "check:\($0.instrumentKey):\($0.portfolioDay):\($0.lastSuccessfulCheckAt):\($0.sourceRaw)"
        }
        return (rows + activities + events + prices + quotes + observations + artwork + checks).sorted()
    }
    #endif

    private func model(registry: OnePieceCatalogRegistry, fixtureWritesEnabled: Bool = false,
                       unresolvedScanStore: UnresolvedScanStore? = nil,
                       priceSource: (any OnePieceMarketPriceSource)? = nil)
        throws -> (ScannerViewModel, ModelContainer) {
        var capabilities: CardGameCapabilities = fixtureWritesEnabled ? [.scan, .collectionWrite] : [.scan]
        if priceSource != nil { capabilities.insert(.pricing) }
        let runtime = CardGameRuntime(descriptor: .init(game: .onePiece, displayName: "Fixture One Piece", sortOrder: 0,
            capabilities: capabilities),
            variantPolicy: OnePieceVariantPolicy(registry: registry),
            pricing: priceSource.map { OnePiecePriceAdapter(registry: registry, source: $0) },
            recognizer: OnePieceRecognitionAdapter(profile: .init(registry: registry)),
            catalog: OnePieceCatalogAdapter(registry: registry))
        let runtimes = try CardGameRuntimeContainer(runtimes: [runtime])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnePieceScanner-\(UUID())")
        let model = ScannerViewModel(gameRegistry: runtimes.registry, priceQuoteService: runtimes.makePriceQuoteService(),
            catalog: runtimes.makeCardCatalog(),
            unresolvedScanStore: unresolvedScanStore ?? UnresolvedScanStore(fileURL: root.appendingPathComponent("recovery.json")))
        let schema = Schema([CollectedCard.self, PriceRecord.self, CollectionActivity.self, InventoryEvent.self,
                             ReferenceQuote.self, PriceObservation.self, PriceCheckDay.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        model.start(context: container.mainContext, startCamera: false, shouldRefreshMagicDirectory: false)
        return (model, container)
    }

    private func waitUntil(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return predicate()
    }

    func testSolePrintingStillAsksForMultipleFinishes() async throws {
        let registry = try registry(count: 1)
        let (model, container) = try model(registry: registry, fixtureWritesEnabled: true)
        defer { model.viewDisappeared() }
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), .init(identifier: try identifier(registry)), nil)
        let appeared = await waitUntil { model.pendingChoice != nil }
        XCTAssertTrue(appeared)
        XCTAssertNil(model.pendingIdentityChoice)
        XCTAssertEqual(model.pendingChoice?.options.map(\.id), ["normal", "foil"])
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        model.choose(.foil)
        let saved = await waitUntil { model.successCount == 1 }
        XCTAssertTrue(saved)
        let owned = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(owned.providerID, uuid(1).uuidString.lowercased())
        XCTAssertEqual(owned.variantID, "foil")
        XCTAssertEqual(owned.variantResolution, .userConfirmed)
    }

    func testFinishLockCannotSelectPrintingOrOverrideItsSoleSupportedFinish() async throws {
        let registry = try reviewedAwardRegistry()
        let original = try XCTUnwrap(registry.printingsByCanonicalID["one-piece:en:ST11-003"]?
            .first { $0.status == .verified && !$0.marketMappings.isEmpty })
        let (model, container) = try model(registry: registry, fixtureWritesEnabled: true)
        defer { model.viewDisappeared() }
        model.setFinishLock(VariantLock(finish: .foil), for: .onePiece)
        XCTAssertEqual(model.finishLocks[.onePiece]?.finish.id, "foil")
        guard case let .identified(subject) = OnePieceScanProfile(registry: registry)
            .identify([.init(text: "ST11-003")]) else { return XCTFail() }
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), subject, nil)
        let appeared = await waitUntil { model.pendingIdentityChoice != nil }
        XCTAssertTrue(appeared, "A finish lock cannot choose between physical releases")
        XCTAssertEqual(model.successCount, 0)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        let pending = try XCTUnwrap(model.pendingIdentityChoice)
        XCTAssertEqual(pending.displayCandidates.count, 2)
        model.choose(try XCTUnwrap(pending.displayCandidates.first { $0.id == original.id.uuidString.lowercased() }))
        let saved = await waitUntil { model.successCount == 1 }
        XCTAssertTrue(saved)
        XCTAssertNil(model.pendingChoice)
        let owned = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(owned.providerID, original.id.uuidString.lowercased())
        XCTAssertEqual(owned.variantID, "normal", "The selected printing's sole finish wins over an inapplicable lock")
        XCTAssertEqual(owned.variantResolution, .uniqueInCatalog)
    }

    func testOnePieceScanningChoiceFinishAndDifferentPhysicalCopiesStayIndependent() async throws {
        let registry = try registry()
        let (model, container) = try model(registry: registry, fixtureWritesEnabled: true)
        defer { model.viewDisappeared() }
        let scanID = try identifier(registry)
        for index in 0..<2 {
            model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), .init(identifier: scanID), nil)
            let appeared = await waitUntil { model.pendingIdentityChoice != nil }
            XCTAssertTrue(appeared)
            let pending = try XCTUnwrap(model.pendingIdentityChoice)
            XCTAssertEqual(pending.displayCandidates.count, 2)
            model.choose(pending.displayCandidates[index])
            let finish = await waitUntil { model.pendingChoice != nil }
            XCTAssertTrue(finish)
            XCTAssertEqual(model.pendingChoice?.card.physicalPrintingID, uuid(index + 1).uuidString.lowercased())
            model.choose(.normal)
            let committed = await waitUntil { model.successCount == index + 1 }
            XCTAssertTrue(committed)
        }
        let rows = try container.mainContext.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.game == "one-piece" })
        XCTAssertEqual(Set(rows.map(\.catalogProviderID)), Set([uuid(1).uuidString.lowercased(), uuid(2).uuidString.lowercased()]))
        XCTAssertTrue(rows.allSatisfy { $0.collectionKey.hasPrefix("one-piece:") })
        let observations = try container.mainContext.fetch(FetchDescriptor<PriceObservation>())
        XCTAssertTrue(observations.isEmpty, "No pricing adapter must not manufacture market observations")
    }

    func testProductionOnePieceRuntimeCannotWriteToSharedCollection() async throws {
        let registry = try registry()
        let runtime = OnePieceGameRuntime(registry: registry).runtime
        XCTAssertFalse(runtime.descriptor.capabilities.contains(.collectionWrite))
        XCTAssertNotNil(runtime.pricing)
        let (model, container) = try model(registry: registry)
        defer { model.viewDisappeared() }
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), .init(identifier: try identifier(registry)), nil)
        let appeared = await waitUntil { model.pendingIdentityChoice != nil }
        XCTAssertTrue(appeared)
        model.choose(try XCTUnwrap(model.pendingIdentityChoice).displayCandidates[0])
        let finish = await waitUntil { model.pendingChoice != nil }
        XCTAssertTrue(finish)
        model.choose(.normal)
        let filed = await waitUntil { !model.unresolvedScans.isEmpty }
        XCTAssertTrue(filed)
        XCTAssertEqual(model.successCount, 0)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
    }
}

private actor OnePieceLookupGate {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var paused: CheckedContinuation<Void, Never>?
    func pause() async {
        await withCheckedContinuation { continuation in
            paused = continuation
            started = true
            startWaiter?.resume(); startWaiter = nil
        }
    }
    func waitForStart() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func resume() { paused?.resume(); paused = nil }
}

private struct DelayedOnePieceImportAdapter: GameImportAdapter {
    let base: OnePieceImportAdapter
    let gate: OnePieceLookupGate
    var game: CardGame { base.game }
    var generation: String? { base.generation }
    func validate(_ entry: CollectionCSVEntry) throws { try base.validate(entry) }
    func metadata(for requests: [GameImportRequest]) async -> [String: ImportedCatalogMetadata] {
        await gate.pause()
        return await base.metadata(for: requests)
    }
}

private struct DelayedOnePieceCatalogAdapter: GameCatalogAdapter {
    let base: OnePieceCatalogAdapter
    let gate: OnePieceLookupGate
    var game: CardGame { base.game }
    var generation: String { base.generation }
    func lookup(_ identifier: ScanIdentifier) async throws -> CatalogLookupOutcome {
        await gate.pause()
        return try await base.lookup(identifier)
    }
    func resolve(_ candidate: PhysicalPrintingCandidate, for identifier: ScanIdentifier) async throws -> CardCatalog.CatalogResolution {
        try await base.resolve(candidate, for: identifier)
    }
}
