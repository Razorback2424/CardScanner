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
    private let storageDirectory: String
    enum ValidationError: Error { case nonIsolatedCollection, invalidStorageDirectory }

    var collectionDirectory: URL { root.appendingPathComponent(storageDirectory, isDirectory: true) }

    /// A writable module is returned only after checking the actual model
    /// container. The public unbound runtime remains read-only.
    @MainActor
    func bound(to container: ModelContainer,
               isCurrent: @escaping @MainActor @Sendable () -> Bool = { true }) async throws -> CardGameRuntimeContainer {
        if allowsCollectionWrites {
            let directory = collectionDirectory.resolvingSymlinksInPath().path + "/"
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
                     allowCollectionWrites: Bool = false, storageDirectory: String = "LorcanaLocalReview") throws -> Self {
        guard ["LorcanaLocalReview", "LorcanaPricingReview"].contains(storageDirectory) else {
            throw ValidationError.invalidStorageDirectory
        }
        let key = Curve25519.Signing.PrivateKey(), keyID = "lorcana-local-review"
        let seed = try LorcanaCatalogSignature.sign(.init(schemaVersion: 1, gameID: CardGame.lorcana.rawValue,
            revision: 1, generatedAt: now, catalog: manifest), keyID: keyID, privateKey: key)
        let keys = [keyID: key.publicKey]
        let verified = try LorcanaCatalogSignature.verify(seed, trustedKeys: keys, now: now)
        let store = try LorcanaCatalogReleaseStore(root: root.appendingPathComponent(storageDirectory, isDirectory: true)
            .appendingPathComponent("CatalogReleases", isDirectory: true), keys: keys, bundledEnvelope: seed, now: now)
        let coordinator = LorcanaCatalogCoordinator(store: store)
        return .init(seed: seed, publicKey: key.publicKey.rawRepresentation, coordinator: coordinator,
            runtime: LorcanaGameRuntime(registry: verified.registry, coordinator: coordinator).runtime,
            registry: verified.registry, root: root.standardizedFileURL, allowsCollectionWrites: allowCollectionWrites,
            storageDirectory: storageDirectory)
    }
}

/// Explicit isolated development workspaces for synthetic UI and public-reference
/// pricing review. Neither route grants production physical-card authority.
enum LorcanaReviewLaunch {
    static var storageDirectory: String { isPricingReview ? "LorcanaPricingReview" : "LorcanaLocalReview" }
    static var isPricingReview: Bool { value("-ui_debug_route") == "LorcanaPricingReview" }
    static var banner: String {
        isPricingReview ? "Lorcana pricing review · Public references · Separate collection"
            : "Lorcana UI review · Synthetic cards · Separate collection"
    }
    static var samples: [Sample] { isPricingReview ? [.size, .unknown] : Sample.allCases }
    static func isEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        ["LorcanaReview", "LorcanaPricingReview"].contains(value("-ui_debug_route", arguments: arguments) ?? "")
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
        if isPricingReview { return value("-ui_debug_state") == "unknown" ? .unknown : .size }
        return value("-ui_debug_state").flatMap(Sample.init(rawValue:)) ?? .size
    }

    static func makeKit(root: URL? = nil) throws -> LorcanaLocalReviewKit {
        guard let root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { throw CollectionStorageBootstrapError.storageLocationUnavailable }
        // Synthetic and public-reference UUIDs/storage stay separate. Both
        // routes survive relaunch without changing ordinary runtime authority.
        return try .make(manifest: isPricingReview ? pricingManifest(withdrawn: value("-ui_debug_state") == "withdrawn")
            : fixtureManifest(), root: root, allowCollectionWrites: true, storageDirectory: storageDirectory)
    }

    /// Public-reference-reviewed acceptance seed. Never registered by appDefaults;
    /// stable IDs belong to these explicit records, not to the synthetic UI cards.
    static func pricingManifest(withdrawn: Bool = false) throws -> LorcanaPhysicalCatalogManifest {
        guard let url = Bundle.main.url(forResource: "pricing-review", withExtension: "json",
                                       subdirectory: "LorcanaCatalogSeed") else { throw BrowseCatalogError.badResponse }
        var manifest = try JSONDecoder().decode(LorcanaPhysicalCatalogManifest.self, from: Data(contentsOf: url))
        if withdrawn {
            var printings = manifest.physicalPrintings
            for index in printings.indices { printings[index].marketMappings = nil }
            manifest = .init(schemaVersion: manifest.schemaVersion, reviewedAt: manifest.reviewedAt,
                printFamilies: manifest.printFamilies, canonicalCards: manifest.canonicalCards,
                physicalPrintings: printings, universes: manifest.universes, corrections: manifest.corrections)
        }
        return manifest
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
