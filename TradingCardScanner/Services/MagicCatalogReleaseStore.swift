import Foundation
import os

actor MagicCatalogReleaseStore {
    private static let logger = Logger(
        subsystem: "com.scan-stash.TradingCardScanner",
        category: "magicCatalogStore"
    )
    enum Slot: String, CaseIterable {
        case current = "magic-catalog-release-current.json"
        case previous = "magic-catalog-release-previous.json"
    }
    typealias Core = SignedCatalogReleaseStore<MagicCatalogReleaseEnvelope, MagicCatalogRelease, MagicCatalogRegistry>
    typealias StoredRelease = Core.StoredRelease
    typealias ActivationResult = SignedCatalogActivationResult
    private let core: Core

    init(root: URL? = nil) {
        let root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("BrowseCatalogCache/MagicCatalogReleases", isDirectory: true)
        core = Core(root: root, currentName: Slot.current.rawValue, previousName: Slot.previous.rawValue,
                    revisionPolicy: .activeRelease, revision: { $0.revision },
                    encode: { try MagicCatalogJSON.encode($0) })
    }

    var activeRelease: StoredRelease? { get async { await core.activeRelease } }
    var activeRevision: Int? { get async { await core.activeRevision } }
    var activeRegistry: MagicCatalogRegistry? { get async { await core.activeRegistry } }

    func load(keys: [MagicCatalogSignatureVerifier.PinnedKey]) async {
        await core.load(decodeAndVerify: { bytes in
            let envelope = try MagicCatalogJSON.decode(MagicCatalogReleaseEnvelope.self, from: bytes)
            let release = try MagicCatalogSignatureVerifier.verify(envelope: envelope, currentRevision: nil, keys: keys)
            return .init(envelope: envelope, release: release, registry: MagicCatalogRegistry(release: release))
        }, rejectedSlot: { slot in
            Self.logger.warning("Failed to load or verify \(slot)")
        })
    }

    func activate(envelope: MagicCatalogReleaseEnvelope, release: MagicCatalogRelease,
                  registry: MagicCatalogRegistry) async throws -> ActivationResult {
        try await core.activate(.init(envelope: envelope, release: release, registry: registry))
    }

    nonisolated func recoverFromBundledSeed() -> MagicCatalogRegistry { .bundledSeed }

    #if DEBUG
    var currentSlotRelease: StoredRelease? { get async { await core.currentSlotRelease } }
    func reset() async { await core.reset() }
    #endif
}
