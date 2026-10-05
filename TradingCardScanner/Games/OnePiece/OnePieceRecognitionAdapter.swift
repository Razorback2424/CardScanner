import Foundation

struct OnePieceRecognitionAdapter: GameRecognitionAdapter {
    let profile: OnePieceScanProfile
    var game: CardGame { .onePiece }
    var customWords: [String] { profile.customWords }
    func identify(_ lines: [RecognizedLine]) -> GameRecognitionOutcome { profile.identify(lines) }
}
