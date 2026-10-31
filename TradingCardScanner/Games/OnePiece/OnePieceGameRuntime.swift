import Foundation

struct OnePieceVariantPolicy: GameVariantPolicy {
    let selectableVariants: [PhysicalVariant]
    init(registry: OnePieceCatalogRegistry) {
        selectableVariants = registry.variantsByID.values.sorted { $0.id < $1.id }.map {
            .init(id: $0.id, label: $0.label)
        }
    }
}

struct OnePieceGameRuntime: Sendable {
    let registry: OnePieceCatalogRegistry
    var coordinator: OnePieceCatalogCoordinator? = nil
    var capabilities: CardGameCapabilities = [.scan, .browse, .pricing]
    var runtime: CardGameRuntime {
        .init(descriptor: .init(game: .onePiece, displayName: "One Piece", sortOrder: 2, capabilities: capabilities),
              variantPolicy: OnePieceVariantPolicy(registry: registry),
              pricing: capabilities.contains(.pricing) ? OnePiecePriceAdapter(registry: registry, coordinator: coordinator) : nil,
              recognizer: OnePieceRecognitionAdapter(profile: .init(registry: registry)),
              catalog: OnePieceCatalogAdapter(registry: registry), browse: OnePieceBrowseAdapter(registry: registry),
              importer: OnePieceImportAdapter(registry: registry),
              priceAuthority: OnePiecePriceAdapter.priceAuthority(registry),
              activationSource: coordinator)
    }
}

extension OnePieceCatalogCoordinator: GameCatalogActivationSource {
    nonisolated var game: CardGame { .onePiece }

    func currentSnapshot() async -> GameCatalogSnapshot? {
        await loadPersistedOrBundled()
        return registry.map(Self.snapshot)
    }

    func activationSnapshots() -> AsyncStream<GameCatalogSnapshot> {
        let events = activationEvents()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                for await event in events {
                    guard !Task.isCancelled else { break }
                    continuation.yield(Self.snapshot(event.registry))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private nonisolated static func snapshot(_ registry: OnePieceCatalogRegistry) -> GameCatalogSnapshot {
        .init(revision: registry.verifiedRelease.release.revision,
              catalog: OnePieceCatalogAdapter(registry: registry),
              recognizer: OnePieceRecognitionAdapter(profile: .init(registry: registry)),
              variantPolicy: OnePieceVariantPolicy(registry: registry), browse: OnePieceBrowseAdapter(registry: registry),
              importer: OnePieceImportAdapter(registry: registry),
              priceAuthority: OnePiecePriceAdapter.priceAuthority(registry))
    }
}
