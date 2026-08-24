import Foundation

enum CardGame: String, CaseIterable, Identifiable, Hashable, Sendable {
    case pokemon
    case magic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pokemon: return "Pokémon"
        case .magic: return "Magic"
        }
    }
}

struct PokemonSetDefinition: Equatable, Hashable, Sendable {
    let printedCode: String
    let tcgdexSetID: String
    let officialCount: Int
    /// Position in release order, oldest first. Collectors think about sets in
    /// release order, not alphabetically, so this is what "Set + Card Number"
    /// sorting groups by. It is an ordering, not a date: the table below is
    /// already written in release order and this only makes that explicit.
    let releaseIndex: Int
}

/// A deliberately small, OCR-oriented subset of Scryfall's set directory. The
/// three-character printed code and (when present) printed size are the only
/// set facts the scanner needs; card metadata remains Scryfall's job.
struct MagicSetDefinition: Equatable, Sendable {
    let code: String
    let printedSize: Int?
}

enum SetCodeMap {
    // MVP scope: English cards that use modern printed expansion codes.
    // The printed three-letter code is what Vision reads from the physical card.
    static let definitions: [String: PokemonSetDefinition] = [
        "SVI": .init(printedCode: "SVI", tcgdexSetID: "sv01", officialCount: 198, releaseIndex: 0),
        "PAL": .init(printedCode: "PAL", tcgdexSetID: "sv02", officialCount: 193, releaseIndex: 1),
        "OBF": .init(printedCode: "OBF", tcgdexSetID: "sv03", officialCount: 197, releaseIndex: 2),
        "MEW": .init(printedCode: "MEW", tcgdexSetID: "sv03.5", officialCount: 165, releaseIndex: 3),
        "PAR": .init(printedCode: "PAR", tcgdexSetID: "sv04", officialCount: 182, releaseIndex: 4),
        "PAF": .init(printedCode: "PAF", tcgdexSetID: "sv04.5", officialCount: 91, releaseIndex: 5),
        "TEF": .init(printedCode: "TEF", tcgdexSetID: "sv05", officialCount: 162, releaseIndex: 6),
        "TWM": .init(printedCode: "TWM", tcgdexSetID: "sv06", officialCount: 167, releaseIndex: 7),
        "SFA": .init(printedCode: "SFA", tcgdexSetID: "sv06.5", officialCount: 64, releaseIndex: 8),
        "SCR": .init(printedCode: "SCR", tcgdexSetID: "sv07", officialCount: 142, releaseIndex: 9),
        "SSP": .init(printedCode: "SSP", tcgdexSetID: "sv08", officialCount: 191, releaseIndex: 10),
        "PRE": .init(printedCode: "PRE", tcgdexSetID: "sv08.5", officialCount: 131, releaseIndex: 11),
        "JTG": .init(printedCode: "JTG", tcgdexSetID: "sv09", officialCount: 159, releaseIndex: 12),
        "DRI": .init(printedCode: "DRI", tcgdexSetID: "sv10", officialCount: 182, releaseIndex: 13),
        "BLK": .init(printedCode: "BLK", tcgdexSetID: "sv10.5b", officialCount: 86, releaseIndex: 14),
        "WHT": .init(printedCode: "WHT", tcgdexSetID: "sv10.5w", officialCount: 86, releaseIndex: 15),
        "MEG": .init(printedCode: "MEG", tcgdexSetID: "me01", officialCount: 132, releaseIndex: 16),
        "PFL": .init(printedCode: "PFL", tcgdexSetID: "me02", officialCount: 94, releaseIndex: 17),
        "ASC": .init(printedCode: "ASC", tcgdexSetID: "me02.5", officialCount: 217, releaseIndex: 18),
        "POR": .init(printedCode: "POR", tcgdexSetID: "me03", officialCount: 88, releaseIndex: 19),
        "CRI": .init(printedCode: "CRI", tcgdexSetID: "me04", officialCount: 86, releaseIndex: 20),
        "PBL": .init(printedCode: "PBL", tcgdexSetID: "me05", officialCount: 84, releaseIndex: 21)
    ]

    static var codes: [String] {
        definitions.keys.sorted()
    }

    static func releaseIndex(forPrintedCode code: String) -> Int? {
        definitions[code.uppercased()]?.releaseIndex
    }

    static func printedCode(forTCGdexSetID id: String) -> String? {
        definitions.values.first { $0.tcgdexSetID.caseInsensitiveCompare(id) == .orderedSame }?.printedCode
    }
}

/// The full TCGdex directory supplies a stable all-set release rank that the
/// scanner's deliberately small OCR table cannot. Browse refreshes this cache;
/// scans can then use the same scale as manually selected historical cards.
enum PokemonCatalogReleaseOrder {
    private static let defaultsKey = "pokemonCatalogReleaseOrder.v1"

    static func install(_ values: [String: Int]) {
        UserDefaults.standard.set(values, forKey: defaultsKey)
    }

    static func order(forSetID setID: String) -> Int? {
        (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Int])?[setID.lowercased()]
    }
}
