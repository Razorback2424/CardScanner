import Foundation

/// Stable persisted identity. Knowing a game ID does not imply that this build
/// has a recognizer, catalog, ownership writer, or provider for that game.
struct CardGame: RawRepresentable, Hashable, Sendable, Identifiable, Codable {
    let rawValue: String

    static let pokemon = CardGame(rawValue: "pokemon")
    static let magic = CardGame(rawValue: "magic")
    static let onePiece = CardGame(rawValue: "one-piece")
    static let lorcana = CardGame(rawValue: "lorcana")

    var id: String { rawValue }
    var label: String { CardGameRegistry.standard.descriptor(for: self)?.displayName ?? rawValue }

    init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum CardGameSupportError: LocalizedError, Equatable {
    case unsupportedGame(CardGame)

    var errorDescription: String? {
        switch self {
        case let .unsupportedGame(game):
            return "This build cannot modify or request provider data for \(game.label). The original identity is retained."
        }
    }
}
