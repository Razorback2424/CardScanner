import Foundation
import os

actor PokemonCatalogReleaseStore {
    private static let logger = Logger(
        subsystem: "com.scan-stash.TradingCardScanner",
        category: "pokemonCatalogStore"
    )
    enum Slot: String, CaseIterable {
        case current = "catalog-release-current.json"
        case previous = "catalog-release-previous.json"
    }
    typealias Core = SignedCatalogReleaseStore<PokemonCatalogReleaseEnvelope, PokemonCatalogRelease, PokemonCatalogRegistry>
    typealias StoredRelease = Core.StoredRelease
    typealias ActivationResult = SignedCatalogActivationResult
    private let core: Core

    init(root: URL? = nil) {
        let root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("BrowseCatalogCache/CatalogReleases", isDirectory: true)
        core = Core(root: root, currentName: Slot.current.rawValue, previousName: Slot.previous.rawValue,
                    revisionPolicy: .currentSlot, revision: { $0.revision },
                    encode: { try JSONEncoder().encode($0) })
    }

    var activeRelease: StoredRelease? { get async { await core.activeRelease } }
    var activeRevision: Int? { get async { await core.activeRevision } }
    var activeRegistry: PokemonCatalogRegistry? { get async { await core.activeRegistry } }

    func load(keys: [PokemonCatalogSignatureVerifier.PinnedKey]) async {
        await core.load(decodeAndVerify: { bytes in
            let envelope = try JSONDecoder().decode(PokemonCatalogReleaseEnvelope.self, from: bytes)
            let release = try PokemonCatalogSignatureVerifier.verify(envelope: envelope, currentRevision: nil, keys: keys)
            return .init(envelope: envelope, release: release, registry: PokemonCatalogRegistry(release: release))
        }, rejectedSlot: { slot in
            Self.logger.warning("Failed to load or verify \(slot)")
        })
    }

    func activate(envelope: PokemonCatalogReleaseEnvelope, release: PokemonCatalogRelease,
                  registry: PokemonCatalogRegistry) async throws -> ActivationResult {
        try await core.activate(.init(envelope: envelope, release: release, registry: registry))
    }

    nonisolated func recoverFromBundledSeed() -> PokemonCatalogRegistry { .bundledSeed }

    /// Direct two-slot measurement, separate from the much larger card cache.
    func diskUsageBytes() async -> Int { await core.diskUsageBytes() }

    #if DEBUG
    var currentSlotRelease: StoredRelease? { get async { await core.currentSlotRelease } }
    var previousSlotRelease: StoredRelease? { get async { await core.previousSlotRelease } }
    func slotFileExists(_ slot: Slot) async -> Bool {
        await core.slotFileExists(slot == .current ? .current : .previous)
    }
    func reset() async { await core.reset() }
    #endif
}
