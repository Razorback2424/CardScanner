#if DEBUG && LOCAL_ONLY_SIGNING
import CryptoKit
import Foundation
import SwiftData

/// Explicit development injection. Nothing is registered with production defaults,
/// fetched or signed by a committed private key. Writes require an explicit opt-in
/// and an isolated on-device/in-memory model container at the call site.
struct LorcanaLocalReviewKit: Sendable {
    let seed: LorcanaCatalogReleaseEnvelope
    let publicKey: Data
    let coordinator: LorcanaCatalogCoordinator
    let runtime: CardGameRuntime
    private let registry: LorcanaCatalogRegistry
    private let root: URL
    private let allowsCollectionWrites: Bool
    enum ValidationError: Error { case nonIsolatedCollection }

    var collectionDirectory: URL { root.appendingPathComponent("LorcanaLocalReview", isDirectory: true) }

    /// A writable module is returned only after checking the actual model
    /// container. The public unbound runtime remains read-only.
    @MainActor
    func bound(to container: ModelContainer,
               isCurrent: @escaping @MainActor @Sendable () -> Bool = { true }) async throws -> CardGameRuntimeContainer {
        if allowsCollectionWrites {
            let directory = root.resolvingSymlinksInPath().appendingPathComponent("LorcanaLocalReview").path + "/"
            guard !container.configurations.isEmpty, container.configurations.allSatisfy({ configuration in
                configuration.cloudKitContainerIdentifier == nil && configuration.allowsSave
                    && (configuration.isStoredInMemoryOnly || configuration.url.resolvingSymlinksInPath().path.hasPrefix(directory))
            }) else { throw ValidationError.nonIsolatedCollection }
        }
        let module = LorcanaGameRuntime(reviewedRegistry: registry, coordinator: coordinator,
            collectionWrites: allowsCollectionWrites).runtime
        return try await CardGameRuntimeContainer(runtimes: [module]).bound(to: container, isCurrent: isCurrent)
    }

    static func make(manifest: LorcanaPhysicalCatalogManifest, root: URL, now: Date = .now,
                     allowCollectionWrites: Bool = false) throws -> Self {
        let key = Curve25519.Signing.PrivateKey(), keyID = "lorcana-local-review"
        let seed = try LorcanaCatalogSignature.sign(.init(schemaVersion: 1, gameID: CardGame.lorcana.rawValue,
            revision: 1, generatedAt: now, catalog: manifest), keyID: keyID, privateKey: key)
        let keys = [keyID: key.publicKey]
        let verified = try LorcanaCatalogSignature.verify(seed, trustedKeys: keys, now: now)
        let store = try LorcanaCatalogReleaseStore(root: root, keys: keys, bundledEnvelope: seed, now: now)
        let coordinator = LorcanaCatalogCoordinator(store: store)
        return .init(seed: seed, publicKey: key.publicKey.rawRepresentation, coordinator: coordinator,
            runtime: LorcanaGameRuntime(registry: verified.registry, coordinator: coordinator).runtime,
            registry: verified.registry, root: root.standardizedFileURL, allowsCollectionWrites: allowCollectionWrites)
    }
}
#endif
