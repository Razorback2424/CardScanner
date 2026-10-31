import Foundation

struct PokemonRecognitionAdapter: GameRecognitionAdapter {
    let profile: PokemonScanProfile
    var game: CardGame { .pokemon }
    var customWords: [String] { profile.customWords }
    func identify(_ lines: [RecognizedLine]) -> GameRecognitionOutcome {
        profile.parseOutcome(lines.map(\.text))
    }
}
