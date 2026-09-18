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

    struct StoredRelease: Sendable {
        let envelope: PokemonCatalogReleaseEnvelope
        let release: PokemonCatalogRelease
        let registry: PokemonCatalogRegistry
    }

    private let root: URL
    private var current: StoredRelease?
    private var previous: StoredRelease?
    private var didLoad = false

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("BrowseCatalogCache/CatalogReleases", isDirectory: true)
    }

    var activeRelease: StoredRelease? { current ?? previous }

    var activeRevision: Int? { activeRelease?.release.revision }

    var activeRegistry: PokemonCatalogRegistry? { activeRelease?.registry }

    /// Bytes occupied by the two small release slots. This is intentionally a
    /// direct file measurement so rollout evidence does not confuse the
    /// catalog's footprint with the much larger checklist/card cache.
    func diskUsageBytes() -> Int {
        Slot.allCases.reduce(into: 0) { total, slot in
            let url = root.appendingPathComponent(slot.rawValue)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber else { return }
            total += size.intValue
        }
    }

    func load(keys: [PokemonCatalogSignatureVerifier.PinnedKey]) {
        guard !didLoad else { return }
        didLoad = true
        current = loadSlot(.current, keys: keys)
        if current == nil {
            previous = loadSlot(.previous, keys: keys)
        }
    }

    enum ActivationResult: Equatable {
        case activated(revision: Int, previousRevision: Int?)
        case alreadyCurrent
    }

    func activate(
        envelope: PokemonCatalogReleaseEnvelope,
        release: PokemonCatalogRelease,
        registry: PokemonCatalogRegistry
    ) throws -> ActivationResult {
        let previousRevision = current?.release.revision
        if let prev = previousRevision, release.revision <= prev {
            return .alreadyCurrent
        }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()

        if current != nil {
            let previousURL = root.appendingPathComponent(Slot.previous.rawValue)
            let currentURL = root.appendingPathComponent(Slot.current.rawValue)
            if FileManager.default.fileExists(atPath: currentURL.path) {
                try? FileManager.default.removeItem(at: previousURL)
                try FileManager.default.moveItem(at: currentURL, to: previousURL)
                previous = current
            }
        }

        let data = try encoder.encode(envelope)
        let currentURL = root.appendingPathComponent(Slot.current.rawValue)
        try data.write(to: currentURL, options: .atomic)

        current = StoredRelease(envelope: envelope, release: release, registry: registry)
        return .activated(revision: release.revision, previousRevision: previousRevision)
    }

    nonisolated func recoverFromBundledSeed() -> PokemonCatalogRegistry {
        PokemonCatalogRegistry.bundledSeed
    }

    private func loadSlot(
        _ slot: Slot,
        keys: [PokemonCatalogSignatureVerifier.PinnedKey]
    ) -> StoredRelease? {
        let url = root.appendingPathComponent(slot.rawValue)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(PokemonCatalogReleaseEnvelope.self, from: data) else {
            Self.logger.warning("Failed to decode \(slot.rawValue) envelope")
            return nil
        }
        guard let release = try? PokemonCatalogSignatureVerifier.verify(
            envelope: envelope,
            currentRevision: nil,
            keys: keys
        ) else {
            Self.logger.warning("Failed to verify \(slot.rawValue) signature")
            return nil
        }
        let registry = PokemonCatalogRegistry(release: release)
        return StoredRelease(envelope: envelope, release: release, registry: registry)
    }

    #if DEBUG
    var currentSlotRelease: StoredRelease? { current }
    var previousSlotRelease: StoredRelease? { previous }

    func slotFileExists(_ slot: Slot) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(slot.rawValue).path)
    }

    func reset() {
        current = nil
        previous = nil
        didLoad = false
        for slot in Slot.allCases {
            try? FileManager.default.removeItem(
                at: root.appendingPathComponent(slot.rawValue)
            )
        }
    }
    #endif
}
