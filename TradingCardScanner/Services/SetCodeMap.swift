import Foundation

struct PokemonSetDefinition: Equatable, Sendable {
    let printedCode: String
    let tcgdexSetID: String
    let officialCount: Int
}

enum SetCodeMap {
    // MVP scope: English cards that use modern printed expansion codes.
    // The printed three-letter code is what Vision reads from the physical card.
    static let definitions: [String: PokemonSetDefinition] = [
        "SVI": .init(printedCode: "SVI", tcgdexSetID: "sv01", officialCount: 198),
        "PAL": .init(printedCode: "PAL", tcgdexSetID: "sv02", officialCount: 193),
        "OBF": .init(printedCode: "OBF", tcgdexSetID: "sv03", officialCount: 197),
        "MEW": .init(printedCode: "MEW", tcgdexSetID: "sv03.5", officialCount: 165),
        "PAR": .init(printedCode: "PAR", tcgdexSetID: "sv04", officialCount: 182),
        "PAF": .init(printedCode: "PAF", tcgdexSetID: "sv04.5", officialCount: 91),
        "TEF": .init(printedCode: "TEF", tcgdexSetID: "sv05", officialCount: 162),
        "TWM": .init(printedCode: "TWM", tcgdexSetID: "sv06", officialCount: 167),
        "SFA": .init(printedCode: "SFA", tcgdexSetID: "sv06.5", officialCount: 64),
        "SCR": .init(printedCode: "SCR", tcgdexSetID: "sv07", officialCount: 142),
        "SSP": .init(printedCode: "SSP", tcgdexSetID: "sv08", officialCount: 191),
        "PRE": .init(printedCode: "PRE", tcgdexSetID: "sv08.5", officialCount: 131),
        "JTG": .init(printedCode: "JTG", tcgdexSetID: "sv09", officialCount: 159),
        "DRI": .init(printedCode: "DRI", tcgdexSetID: "sv10", officialCount: 182),
        "BLK": .init(printedCode: "BLK", tcgdexSetID: "sv10.5b", officialCount: 86),
        "WHT": .init(printedCode: "WHT", tcgdexSetID: "sv10.5w", officialCount: 86),
        "MEG": .init(printedCode: "MEG", tcgdexSetID: "me01", officialCount: 132),
        "PFL": .init(printedCode: "PFL", tcgdexSetID: "me02", officialCount: 94),
        "ASC": .init(printedCode: "ASC", tcgdexSetID: "me02.5", officialCount: 217),
        "POR": .init(printedCode: "POR", tcgdexSetID: "me03", officialCount: 88),
        "CRI": .init(printedCode: "CRI", tcgdexSetID: "me04", officialCount: 86),
        "PBL": .init(printedCode: "PBL", tcgdexSetID: "me05", officialCount: 84)
    ]

    static var codes: [String] {
        definitions.keys.sorted()
    }
}
