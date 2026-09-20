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

    struct StoredRelease: Sendable {
        let envelope: MagicCatalogReleaseEnvelope
        let release: MagicCatalogRelease
        let registry: MagicCatalogRegistry
    }

    enum ActivationResult: Equatable {
        case activated(revision: Int, previousRevision: Int?)
        case alreadyCurrent
    }

    private let root: URL
    private var current: StoredRelease?
    private var previous: StoredRelease?
    private var didLoad = false

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("BrowseCatalogCache/MagicCatalogReleases", isDirectory: true)
    }

    var activeRelease: StoredRelease? { current ?? previous }
    var activeRevision: Int? { activeRelease?.release.revision }
    var activeRegistry: MagicCatalogRegistry? { activeRelease?.registry }

    func load(keys: [MagicCatalogSignatureVerifier.PinnedKey]) {
        guard !didLoad else { return }
        didLoad = true
        current = loadSlot(.current, keys: keys)
        if current == nil { previous = loadSlot(.previous, keys: keys) }
    }

    func activate(
        envelope: MagicCatalogReleaseEnvelope,
        release: MagicCatalogRelease,
        registry: MagicCatalogRegistry
    ) throws -> ActivationResult {
        let previousRevision = activeRelease?.release.revision
        if let previousRevision, release.revision <= previousRevision {
            return .alreadyCurrent
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let currentURL = root.appendingPathComponent(Slot.current.rawValue)
        let previousURL = root.appendingPathComponent(Slot.previous.rawValue)
        if current != nil, FileManager.default.fileExists(atPath: currentURL.path) {
            try? FileManager.default.removeItem(at: previousURL)
            try FileManager.default.moveItem(at: currentURL, to: previousURL)
            previous = current
        }
        let data = try MagicCatalogJSON.encode(envelope)
        try data.write(to: currentURL, options: .atomic)
        current = StoredRelease(envelope: envelope, release: release, registry: registry)
        return .activated(revision: release.revision, previousRevision: previousRevision)
    }

    nonisolated func recoverFromBundledSeed() -> MagicCatalogRegistry {
        MagicCatalogRegistry.bundledSeed
    }

    #if DEBUG
    var currentSlotRelease: StoredRelease? { current }

    func reset() {
        current = nil
        previous = nil
        didLoad = false
        for slot in Slot.allCases {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(slot.rawValue))
        }
    }
    #endif

    private func loadSlot(
        _ slot: Slot,
        keys: [MagicCatalogSignatureVerifier.PinnedKey]
    ) -> StoredRelease? {
        let url = root.appendingPathComponent(slot.rawValue)
        guard let data = try? Data(contentsOf: url),
              let envelope = try? MagicCatalogJSON.decode(
                MagicCatalogReleaseEnvelope.self,
                from: data
              ),
              let release = try? MagicCatalogSignatureVerifier.verify(
                envelope: envelope,
                currentRevision: nil,
                keys: keys
              ) else {
            if FileManager.default.fileExists(atPath: url.path) {
                Self.logger.warning("Failed to load or verify \(slot.rawValue)")
            }
            return nil
        }
        return StoredRelease(
            envelope: envelope,
            release: release,
            registry: MagicCatalogRegistry(release: release)
        )
    }
}
