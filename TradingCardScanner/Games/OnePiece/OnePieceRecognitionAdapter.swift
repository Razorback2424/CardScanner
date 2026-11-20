import Foundation

struct OnePieceRecognitionAdapter: GameRecognitionAdapter {
    let profile: OnePieceScanProfile
    var game: CardGame { .onePiece }
    var customWords: [String] { profile.customWords }
    func identify(_ lines: [RecognizedLine]) -> GameRecognitionOutcome { profile.identify(lines) }
    /// One Piece search accepts the printed number across every set.
    func catalogSearchText(for identifier: ScanIdentifier) -> String? {
        Self.catalogSearchText(for: identifier)
    }

    static func catalogSearchText(for identifier: ScanIdentifier) -> String? {
        identifier.game == .onePiece ? identifier.fieldValue("number") : nil
    }
}
