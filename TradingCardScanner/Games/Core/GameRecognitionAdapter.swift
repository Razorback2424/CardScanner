import Foundation

protocol GameRecognitionAdapter: Sendable {
    var game: CardGame { get }
    var customWords: [String] { get }
    func identify(_ lines: [RecognizedLine]) -> GameRecognitionOutcome
}

struct RecognitionRejection: Sendable, Equatable {
    let reason: String
    /// Soft rejection blocks secondary fallback only when no primary adapter
    /// independently identifies a card.
    let blocksFallbackRecognition: Bool
}

enum GameRecognitionOutcome: Sendable, Equatable {
    case nothing
    case identified(ScanSubject)
    case ambiguous
    case rejected(RecognitionRejection)

    static func identities(_ identifiers: [ScanIdentifier]) -> Self {
        let unique = Set(identifiers)
        guard unique.count <= 1 else { return .ambiguous }
        guard let identifier = unique.first else { return .nothing }
        return .identified(ScanSubject(identifier: identifier))
    }
}

struct GameRecognitionRegistry: Sendable {
    enum RegistrationError: Error, Equatable {
        case duplicateGame(CardGame)
    }
    let recognizers: [any GameRecognitionAdapter]

    init(recognizers: [any GameRecognitionAdapter]) throws {
        var seen: Set<CardGame> = []
        for recognizer in recognizers {
            guard seen.insert(recognizer.game).inserted else {
                throw RegistrationError.duplicateGame(recognizer.game)
            }
        }
        self.recognizers = recognizers.sorted { $0.game.rawValue < $1.game.rawValue }
    }

    var customWords: [String] {
        Array(Set(recognizers.flatMap(\.customWords))).sorted()
    }

    func identify(_ lines: [RecognizedLine]) -> RecognitionOutcome {
        // Evaluate every adapter before deciding; registration order cannot win.
        let outcomes = recognizers.map { ($0.game, $0.identify(lines)) }
        var subjects: [ScanSubject] = []
        var ambiguous = false
        var blocksFallback = false
        for (game, outcome) in outcomes {
            switch outcome {
            case .nothing: break
            case let .identified(subject):
                if subject.game == game { subjects.append(subject) }
                else { ambiguous = true }
            case .ambiguous: ambiguous = true
            case let .rejected(rejection):
                blocksFallback = blocksFallback || rejection.blocksFallbackRecognition
            }
        }
        if ambiguous || subjects.count > 1 { return .ambiguous }
        if let subject = subjects.first { return .identified(subject) }
        return blocksFallback ? .fallbackBlocked : .nothing
    }
}
