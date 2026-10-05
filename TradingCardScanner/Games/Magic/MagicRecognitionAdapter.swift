import Foundation

struct MagicRecognitionAdapter: GameRecognitionAdapter {
    let profile: MagicScanProfile
    var game: CardGame { .magic }
    var customWords: [String] { profile.customWords }
    func identify(_ lines: [RecognizedLine]) -> GameRecognitionOutcome {
        switch profile.parseOutcome(lines) {
        case .nothing: return .nothing
        case .ambiguous: return .ambiguous
        case let .identified(identifier): return .identified(ScanSubject(identifier: identifier))
        case .spatiallyRejectedCollector:
            return .rejected(.init(reason: "Collector reading is outside the footer identity region",
                                   blocksFallbackRecognition: true))
        }
    }
}
