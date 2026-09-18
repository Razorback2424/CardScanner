import Foundation
import os

struct PokemonCatalogRegistry: Sendable {
    let revision: Int
    let descriptors: [PokemonCatalogSetDescriptor]

    private let byPrintedCode: [String: PokemonCatalogSetDescriptor]
    private let byPromoPrefix: [String: PokemonCatalogSetDescriptor]
    private let byProviderSetID: [String: PokemonCatalogSetDescriptor]

    /// A descriptor this binary can interpret. Kept in one place so `init` and
    /// `validate` cannot drift apart about which descriptors are in scope.
    static func isSupported(_ descriptor: PokemonCatalogSetDescriptor) -> Bool {
        descriptor.rulesVersion <= PokemonChecklistSnapshotVersion.masterSetRules
    }

    init(release: PokemonCatalogRelease) {
        self.revision = release.revision
        let supported = release.sets.filter(Self.isSupported)
        self.descriptors = supported
        var codes: [String: PokemonCatalogSetDescriptor] = [:]
        var promos: [String: PokemonCatalogSetDescriptor] = [:]
        var providers: [String: PokemonCatalogSetDescriptor] = [:]

        for descriptor in supported {
            providers[descriptor.providerSetID.lowercased()] = descriptor

            switch descriptor.recognitionKind {
            case .expansion:
                if let code = descriptor.printedCode {
                    codes[code.uppercased()] = descriptor
                }
            case .promo:
                if let prefix = descriptor.printedPrefix {
                    promos[prefix.uppercased()] = descriptor
                }
            case .notScannable:
                break
            }
        }

        self.byPrintedCode = codes
        self.byPromoPrefix = promos
        self.byProviderSetID = providers
    }

    // MARK: - Lookups

    func expansion(forPrintedCode code: String) -> PokemonCatalogSetDescriptor? {
        byPrintedCode[code.uppercased()]
    }

    func promo(forPrefix prefix: String) -> PokemonCatalogSetDescriptor? {
        byPromoPrefix[prefix.uppercased()]
    }

    func descriptor(forProviderSetID id: String) -> PokemonCatalogSetDescriptor? {
        byProviderSetID[id.lowercased()]
    }

    var expansionCodes: [String] {
        byPrintedCode.keys.sorted()
    }

    var promoPrefixes: [String] {
        byPromoPrefix.keys.sorted()
    }

    // MARK: - Bridge to existing definition types

    func pokemonSetDefinition(forPrintedCode code: String) -> PokemonSetDefinition? {
        guard let d = expansion(forPrintedCode: code),
              let printed = d.printedCode,
              let count = d.officialCount,
              let order = d.releaseOrder else { return nil }
        return PokemonSetDefinition(
            printedCode: printed,
            tcgdexSetID: d.providerSetID,
            officialCount: count,
            releaseIndex: order
        )
    }

    func pokemonPromoSetDefinition(forPrefix prefix: String) -> PokemonPromoSetDefinition? {
        guard let d = promo(forPrefix: prefix),
              let printedPfx = d.printedPrefix,
              let catalogPfx = d.catalogLocalIDPrefix,
              let padWidth = d.localIDPadWidth else { return nil }
        return PokemonPromoSetDefinition(
            printedPrefix: printedPfx,
            tcgdexSetID: d.providerSetID,
            catalogLocalIDPrefix: catalogPfx,
            localIDPadWidth: padWidth
        )
    }

    func printedCode(forProviderSetID id: String) -> String? {
        guard let d = descriptor(forProviderSetID: id) else { return nil }
        switch d.recognitionKind {
        case .expansion: return d.printedCode
        case .promo: return d.printedPrefix
        case .notScannable: return d.printedCode ?? d.printedPrefix
        }
    }

    func releaseOrder(forProviderSetID id: String) -> Int? {
        descriptor(forProviderSetID: id).flatMap(\.releaseOrder)
    }

    func officialCount(forProviderSetID id: String) -> Int? {
        descriptor(forProviderSetID: id)?.officialCount
    }

    func isScanEnabled(forProviderSetID id: String) -> Bool {
        guard let d = descriptor(forProviderSetID: id) else { return false }
        return d.recognitionKind != .notScannable && d.scanEnabled
    }

    /// Returns true only for a set the active release explicitly withdrew from
    /// scanning. Historical Pokémon resolution predates the registry and still
    /// knows about older sets that are not represented by the modern printed-code
    /// seed, so an absent descriptor must not accidentally disable that path.
    func isScanDisabled(forProviderSetID id: String) -> Bool {
        guard let d = descriptor(forProviderSetID: id) else { return false }
        return d.recognitionKind == .notScannable || !d.scanEnabled
    }

    // MARK: - Validation

    struct CollisionError: Error, CustomStringConvertible {
        let field: String
        let value: String
        let first: String
        let second: String
        var description: String {
            "\(field) collision: '\(value)' claimed by '\(first)' and '\(second)'"
        }
    }

    /// Collisions are evaluated only among descriptors this binary will
    /// activate. A descriptor requiring a newer rules version is skipped by
    /// `init`, so letting it reject the release would strand every client on
    /// its old revision over a set it was never going to use — losing all the
    /// other new sets in the same release.
    static func validate(_ release: PokemonCatalogRelease) throws {
        var seenCodes: [String: String] = [:]
        var seenPrefixes: [String: String] = [:]
        var seenProviders: [String: String] = [:]

        for d in release.sets where isSupported(d) {
            let providerKey = d.providerSetID.lowercased()
            if let existing = seenProviders[providerKey] {
                throw CollisionError(field: "providerSetID", value: d.providerSetID,
                                     first: existing, second: d.providerSetID)
            }
            seenProviders[providerKey] = d.providerSetID

            switch d.recognitionKind {
            case .expansion:
                if let code = d.printedCode {
                    let key = code.uppercased()
                    if let existing = seenCodes[key] {
                        throw CollisionError(field: "printedCode", value: code,
                                             first: existing, second: d.providerSetID)
                    }
                    seenCodes[key] = d.providerSetID
                }
            case .promo:
                if let prefix = d.printedPrefix {
                    let key = prefix.uppercased()
                    if let existing = seenPrefixes[key] {
                        throw CollisionError(field: "printedPrefix", value: prefix,
                                             first: existing, second: d.providerSetID)
                    }
                    seenPrefixes[key] = d.providerSetID
                }
            case .notScannable:
                break
            }
        }

        for (code, codeProvider) in seenCodes {
            if let prefixProvider = seenPrefixes[code] {
                throw CollisionError(field: "cross-namespace", value: code,
                                     first: codeProvider, second: prefixProvider)
            }
        }
    }

    // MARK: - Bundled seed

    static let bundledSeed: PokemonCatalogRegistry = {
        let expansions: [PokemonCatalogSetDescriptor] = SetCodeMap.definitions.values
            .sorted { $0.releaseIndex < $1.releaseIndex }
            .map { def in
                PokemonCatalogSetDescriptor(
                    providerSetID: def.tcgdexSetID,
                    displayName: nil,
                    releaseDate: nil,
                    releaseOrder: def.releaseIndex,
                    recognitionKind: .expansion,
                    printedCode: def.printedCode,
                    officialCount: def.officialCount,
                    printedPrefix: nil,
                    catalogLocalIDPrefix: nil,
                    localIDPadWidth: nil,
                    scanEnabled: true,
                    logoURL: nil,
                    symbolURL: nil,
                    rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules
                )
            }

        let promos: [PokemonCatalogSetDescriptor] = PokemonPromoCodeMap.definitions.values
            .sorted { $0.printedPrefix < $1.printedPrefix }
            .map { def in
                PokemonCatalogSetDescriptor(
                    providerSetID: def.tcgdexSetID,
                    displayName: nil,
                    releaseDate: nil,
                    releaseOrder: nil,
                    recognitionKind: .promo,
                    printedCode: nil,
                    officialCount: nil,
                    printedPrefix: def.printedPrefix,
                    catalogLocalIDPrefix: def.catalogLocalIDPrefix,
                    localIDPadWidth: def.localIDPadWidth,
                    scanEnabled: true,
                    logoURL: nil,
                    symbolURL: nil,
                    rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules
                )
            }

        let release = PokemonCatalogRelease(
            schemaVersion: PokemonCatalogRelease.currentSchemaVersion,
            revision: 0,
            generatedAt: Date(timeIntervalSince1970: 0),
            sets: expansions + promos
        )
        return PokemonCatalogRegistry(release: release)
    }()
}

// MARK: - Diagnostic counters

enum PokemonCatalogDiagnostics {
    private static let logger = Logger(
        subsystem: "com.scan-stash.TradingCardScanner",
        category: "pokemonCatalog"
    )
    private static let lock = NSLock()
    private static var _displayCodeFallbackCounts: [String: Int] = [:]
    private static var _persistedPlaceholderCodeCounts: [String: Int] = [:]

    static var displayCodeFallbackCounts: [String: Int] {
        lock.withLock { _displayCodeFallbackCounts }
    }

    static var persistedPlaceholderCodeCounts: [String: Int] {
        lock.withLock { _persistedPlaceholderCodeCounts }
    }

    static func recordDisplayCodeFallback(providerSetID: String) {
        logger.info("Display code unavailable; using placeholder for provider set: \(providerSetID, privacy: .public)")
        lock.withLock { _displayCodeFallbackCounts[providerSetID, default: 0] += 1 }
    }

    static func recordPersistedPlaceholderCode(providerSetID: String) {
        logger.info("Persisted placeholder code for set: \(providerSetID, privacy: .public)")
        lock.withLock { _persistedPlaceholderCodeCounts[providerSetID, default: 0] += 1 }
    }

    #if DEBUG
    static func resetCounters() {
        lock.withLock {
            _displayCodeFallbackCounts.removeAll()
            _persistedPlaceholderCodeCounts.removeAll()
        }
    }
    #endif
}
