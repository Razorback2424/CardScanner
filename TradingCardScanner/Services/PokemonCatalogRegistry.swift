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
        descriptor.rulesVersion <= 2 && (descriptor.recognitionKind != .energy || descriptor.rulesVersion >= 2)
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
            case .promo, .energy:
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
        byPromoPrefix[prefix.uppercased()].flatMap { $0.recognitionKind == .promo ? $0 : nil }
    }

    func descriptor(forProviderSetID id: String) -> PokemonCatalogSetDescriptor? {
        byProviderSetID[id.lowercased()]
    }

    func membershipRecognition(forProviderSetID id: String) -> PokemonCatalogMembershipRecognition? {
        descriptor(forProviderSetID: id)?.membershipRecognition
    }

    var expansionCodes: [String] {
        byPrintedCode.keys.sorted()
    }

    var promoPrefixes: [String] {
        byPromoPrefix.filter { $0.value.recognitionKind == .promo }.keys.sorted()
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
              d.recognitionKind == .promo,
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
        case .promo, .energy: return d.printedPrefix
        case .notScannable:
            let parent = d.parentProviderSetID.flatMap { descriptor(forProviderSetID: $0) }
            return d.printedCode ?? d.printedPrefix ?? parent?.printedCode ?? parent?.printedPrefix
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
            case .promo, .energy:
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
                    providerFingerprint: nil,
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
                    providerFingerprint: nil,
                    rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules
                )
            }

        // The bundled registry is the scanner's first-launch and offline
        // authority. Classic Collection cards reuse older printed numbers, so
        // omitting their membership here silently turns them into old printings
        // until a signed release has downloaded. A parity test checks these
        // rows against publisher/catalog-input.json. Resolving a chosen card
        // still requires its downloaded checklist or a live provider response.
        let classicMembers: [(id: String, name: String, number: String, denominator: Int)] = [
            ("001", "charizard", "4", 102),
            ("002", "delcatty", "5", 109),
            ("003", "metagross", "11", 113),
            ("004", "genesect ex", "11", 101),
            ("005", "misty", "18", 132),
            ("006", "dark tyranitar", "19", 109),
            ("007", "sneasel", "25", 111),
            ("008", "pikachu and zekrom gx", "33", 181),
            ("009", "greninja break", "41", 122),
            ("010", "uxie", "43", 146),
            ("011", "crobat g", "47", 127),
            ("012", "raikou", "50", 185),
            ("013", "buzzwole gx", "57", 111),
            ("014", "pikachu", "58", 102),
            ("015", "erika s jigglypuff", "69", 132),
            ("016", "rayquaza ex", "85", 124),
            ("017", "solgaleo gx", "89", 149),
            ("018", "gengar", "94", 102),
            ("019", "darkrai and cresselia legend", "99", 102),
            ("020", "darkrai and cresselia legend", "100", 102),
            ("021", "n", "101", 101),
            ("022", "palkia", "106", 106),
            ("023", "m gardevoir ex", "106", 160),
            ("024", "shining celebi", "106", 105),
            ("025", "scizor ex", "108", 115),
            ("026", "mew vmax", "114", 264),
            ("027", "arceus vstar", "123", 172),
            ("028", "zacian v", "138", 202),
            ("029", "lugia", "149", 147),
            ("030", "magikarp", "203", 193)
        ]
        let classic = PokemonCatalogSetDescriptor(
            providerSetID: "30th-c",
            displayName: "30th Celebration Classic Collection",
            releaseDate: "2026-09-16",
            releaseOrder: 23,
            recognitionKind: .notScannable,
            printedCode: nil,
            officialCount: nil,
            printedPrefix: nil,
            catalogLocalIDPrefix: nil,
            localIDPadWidth: nil,
            scanEnabled: false,
            logoURL: nil,
            symbolURL: nil,
            parentProviderSetID: "30th",
            membershipRecognition: PokemonCatalogMembershipRecognition(
                members: classicMembers.map { member in
                    .init(
                        providerCardID: "30th-c-\(member.id)",
                        canonicalName: member.name,
                        printedLocalID: member.number,
                        printedDenominator: member.denominator
                    )
                }
            )
        )

        let release = PokemonCatalogRelease(
            schemaVersion: PokemonCatalogRelease.currentSchemaVersion,
            revision: 0,
            generatedAt: Date(timeIntervalSince1970: 0),
            sets: expansions + promos + [classic, Self.energyDescriptor]
        )
        return PokemonCatalogRegistry(release: release)
    }()
}

extension PokemonCatalogRegistry {
    /// Historical reprint products that print each card's original number.
    /// Historical sets are outside the signed catalog's discovery scope, so
    /// these are read only by the historical identity resolver and are never
    /// registry descriptors: Browse, import, pricing and artwork treat the set
    /// exactly as before. A signed descriptor for the same set takes precedence.
    static let historicalMembershipDescriptors = [celebrationsClassicDescriptor]

    /// Celebrations Classic Collection prints the original card's number
    /// (Charizard `4/102`), never a `/25` number, so without membership it
    /// resolves as the vintage original. Numbers are from TCGplayer (TCGCSV
    /// group 2931) and agree with pokemontcg.io `cel25c`, checked 2026-11-01.
    static let celebrationsClassicDescriptor: PokemonCatalogSetDescriptor = {
        let members: [(id: String, name: String, number: String, denominator: Int)] = [
            ("CC001", "Blastoise", "2", 102),
            ("CC002", "Charizard", "4", 102),
            ("CC003", "Venusaur", "15", 102),
            ("CC004", "Imposter Professor Oak", "73", 102),
            ("CC005", "Dark Gyarados", "8", 82),
            ("CC006", "Here Comes Team Rocket!", "15", 82),
            ("CC007", "Rocket's Zapdos", "15", 132),
            ("CC008", "_____'s Pikachu", "24", 53),
            ("CC009", "Cleffa", "20", 111),
            ("CC010", "Shining Magikarp", "66", 64),
            ("CC011", "Team Magma's Groudon", "9", 95),
            ("CC012", "Rocket's Admin.", "86", 109),
            ("CC013", "Mew ex", "88", 92),
            ("CC014", "Gardevoir ex", "93", 101),
            ("CC015", "Umbreon ☆", "17", 17),
            ("CC016", "Claydol", "15", 106),
            ("CC017", "Luxray GL LV.X", "109", 111),
            ("CC018", "Garchomp C LV.X", "145", 147),
            ("CC019", "Donphan", "107", 123),
            ("CC020", "Reshiram", "113", 114),
            ("CC021", "Zekrom", "114", 114),
            ("CC022", "Mewtwo EX", "54", 99),
            ("CC023", "Xerneas EX", "97", 146),
            ("CC024", "M Rayquaza EX", "76", 108),
            ("CC025", "Tapu Lele GX", "60", 145)
        ]
        return PokemonCatalogSetDescriptor(
            providerSetID: "cel25cc",
            displayName: "Celebrations Classic Collection",
            releaseDate: "2021-10-08",
            releaseOrder: nil,
            recognitionKind: .notScannable,
            printedCode: "CEL",
            officialCount: nil,
            printedPrefix: nil,
            catalogLocalIDPrefix: nil,
            localIDPadWidth: nil,
            scanEnabled: false,
            logoURL: nil,
            symbolURL: nil,
            parentProviderSetID: "cel25",
            membershipRecognition: PokemonCatalogMembershipRecognition(
                members: members.map { member in
                    .init(
                        providerCardID: "cel25cc-\(member.id)",
                        canonicalName: CatalogIdentityNormalization.canonicalText(member.name),
                        printedLocalID: member.number,
                        printedDenominator: member.denominator
                    )
                }
            )
        )
    }()

    /// Every descriptor whose membership the historical resolver consults.
    var membershipDescriptors: [PokemonCatalogSetDescriptor] {
        descriptors.filter { $0.membershipRecognition != nil }
            + Self.historicalMembershipDescriptors.filter {
                descriptor(forProviderSetID: $0.providerSetID) == nil
            }
    }

    /// The code shown for a membership card, including historical reprints.
    func membershipPrintedCode(forProviderSetID id: String) -> String? {
        printedCode(forProviderSetID: id)
            ?? Self.historicalMembershipDescriptors.first {
                $0.providerSetID.caseInsensitiveCompare(id) == .orderedSame
            }?.printedCode
    }
}

extension PokemonCatalogRegistry {
    static let energyDescriptor = PokemonCatalogSetDescriptor(
        providerSetID: "mee", displayName: "Mega Evolution Energy", releaseDate: "2025-09-25",
        releaseOrder: nil, recognitionKind: .energy, printedCode: nil, officialCount: nil,
        printedPrefix: "MEE", catalogLocalIDPrefix: "", localIDPadWidth: 3,
        scanEnabled: true, logoURL: nil, symbolURL: nil, rulesVersion: 2)

    func energyDefinition(forCode code: String) -> PokemonEnergySetDefinition? {
        guard let d = byPromoPrefix[code.uppercased()], d.recognitionKind == .energy,
              let code = d.printedPrefix, let width = d.localIDPadWidth else { return nil }
        return .init(printedCode: code, tcgdexSetID: d.providerSetID, localIDPadWidth: width)
    }
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
        lock.withLock { _displayCodeFallbackCounts[providerSetID, default: 0] += 1 }
        logger.info("Display code unavailable; using placeholder for provider set: \(providerSetID, privacy: .public)")
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
