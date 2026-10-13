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
        let store = try LorcanaCatalogReleaseStore(root: root.appendingPathComponent("LorcanaLocalReview", isDirectory: true)
            .appendingPathComponent("CatalogReleases", isDirectory: true), keys: keys, bundledEnvelope: seed, now: now)
        let coordinator = LorcanaCatalogCoordinator(store: store)
        return .init(seed: seed, publicKey: key.publicKey.rawRepresentation, coordinator: coordinator,
            runtime: LorcanaGameRuntime(registry: verified.registry, coordinator: coordinator).runtime,
            registry: verified.registry, root: root.standardizedFileURL, allowsCollectionWrites: allowCollectionWrites)
    }
}

/// A deterministic UI workspace, never a source of real physical-card authority.
/// Keep the route, fixture identities and all storage out of production builds.
enum LorcanaReviewLaunch {
    static let storageDirectory = "LorcanaLocalReview"
    static func isEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        value("-ui_debug_route", arguments: arguments) == "LorcanaReview"
    }

    static func value(_ flag: String, arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    enum Sample: String, CaseIterable, Identifiable {
        case size, standard, oversized, stamp, artworkUnavailable, held, landscape, unknown
        var id: String { rawValue }
        var label: String {
            switch self {
            case .size: "Standard / oversized"
            case .standard: "Standard · choose finish"
            case .oversized: "Oversized only"
            case .stamp: "Two stamps"
            case .artworkUnavailable: "Artwork unavailable"
            case .held: "Unreviewed printing"
            case .landscape: "Landscape"
            case .unknown: "Unknown footer"
            }
        }
        var number: String {
            switch self {
            case .size: "5"
            case .standard: "23"
            case .oversized: "6"
            case .stamp: "7"
            case .artworkUnavailable: "8"
            case .held: "9"
            case .landscape: "170"
            case .unknown: "999"
            }
        }
        var footerText: String { "\(number)/204 EN 1" }
    }

    static var initialSample: Sample {
        value("-ui_debug_state").flatMap(Sample.init(rawValue:)) ?? .size
    }

    static func makeKit(root: URL? = nil) throws -> LorcanaLocalReviewKit {
        guard let root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { throw CollectionStorageBootstrapError.storageLocationUnavailable }
        // Stable fixture UUIDs survive review-app relaunch, but cannot be promoted
        // into the real catalog. All evidence references explicitly say synthetic.
        return try .make(manifest: fixtureManifest(), root: root, allowCollectionWrites: true)
    }

    static func fixtureManifest() throws -> LorcanaPhysicalCatalogManifest {
        func uuid(_ prefix: String, _ index: Int) -> UUID {
            UUID(uuidString: String(format: "\(prefix)000000-0000-0000-0000-%012d", index))!
        }
        var families: [LorcanaPrintFamily] = []
        var cards: [LorcanaCanonicalCard] = []
        var prints: [LorcanaPhysicalPrinting] = []
        var universes: [LorcanaPhysicalUniverse] = []
        for sample in Sample.allCases where sample != .unknown {
            // UUID allocation is independent of menu order and future samples.
            let index = Int(sample.number)!
            let footer = try LorcanaPrintedIdentity(collectorNumber: sample.number, denominator: "204",
                language: "en", printedSetMarker: "1")
            let canonical = uuid("D1", index)
            let alias = LorcanaSourceAlias(provider: "synthetic-ui", id: sample.rawValue)
            let reference = "synthetic-ui:\(sample.rawValue)"
            let layout = sample == .landscape ? "landscape" : "normal"
            let name = "UI Fixture — \(sample.label)"
            families.append(.init(footer: footer, providerSetCode: "UI", name: name, version: nil,
                rarity: "Synthetic", layout: layout, sourceAliases: [alias], footerEvidenceReference: reference))
            cards.append(.init(id: canonical, name: name, version: nil, relationshipEvidenceReferences: [reference]))
            let count = [.size, .stamp, .artworkUnavailable].contains(sample) ? 2 : 1
            var ids: [UUID] = []
            for offset in 0..<count {
                let id = uuid("D2", index * 10 + offset)
                ids.append(id)
                let size: LorcanaPhysicalSize = sample == .oversized || (sample == .size && offset == 1) ? .oversized : .standard
                let finishes: [LorcanaPhysicalFinish] = size == .oversized ? [.foil] : [.normal, .foil]
                prints.append(.init(id: id, identity: .init(canonicalCardID: canonical, footer: footer,
                    artworkID: uuid("D3", sample == .artworkUnavailable ? index * 10 + offset : index),
                    distributionID: "synthetic-ui", stamp: sample == .stamp ? "Review stamp \(offset + 1)" : nil,
                    size: size, layout: layout), providerSetCode: "UI", setName: "Synthetic UI Review",
                    artworkLabel: "Synthetic artwork", distributionLabel: "UI fixture", imageURL: nil,
                    status: sample == .held ? .provisional : .verified,
                    identityEvidence: LorcanaPhysicalEvidenceKind.allCases.map { .init(kind: $0, reference: reference) },
                    finishes: finishes.map { .init(finish: $0, evidenceReferences: [reference]) },
                    finishUniverseEvidenceReference: reference, sourceAliases: [alias]))
            }
            universes.append(.init(footer: footer, printingIDs: ids, isComplete: sample != .held,
                evidenceReference: sample == .held ? nil : reference))
        }
        return .init(schemaVersion: 2, reviewedAt: Date(timeIntervalSince1970: 1_790_000_000),
            printFamilies: families, canonicalCards: cards, physicalPrintings: prints,
            universes: universes, corrections: [])
    }
}
#endif
