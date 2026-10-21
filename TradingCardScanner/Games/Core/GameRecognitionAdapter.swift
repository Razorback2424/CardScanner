import Foundation

struct SupplementalTextRegion: Equatable, Sendable {
    let id: String
    let cardRelativeRect: CGRect
}

protocol GameRecognitionAdapter: Sendable {
    var game: CardGame { get }
    var customWords: [String] { get }
    var supplementalRegion: SupplementalTextRegion? { get }
    func needsSupplementalText(afterFooterLines lines: [RecognizedLine]) -> Bool
    func identify(footerLines: [RecognizedLine], supplementalLines: [RecognizedLine]) -> GameRecognitionOutcome
    func identify(_ lines: [RecognizedLine]) -> GameRecognitionOutcome
    /// An unnumbered footer can require a title outside the normal OCR band.
    /// Request it only for supported evidence, from the same camera frame.
    func needsFullCardText(afterFooterLines lines: [RecognizedLine]) -> Bool
}

extension GameRecognitionAdapter {
    var supplementalRegion: SupplementalTextRegion? { nil }
    func needsSupplementalText(afterFooterLines lines: [RecognizedLine]) -> Bool { false }
    func identify(footerLines: [RecognizedLine], supplementalLines: [RecognizedLine]) -> GameRecognitionOutcome {
        identify(footerLines)
    }
    func needsFullCardText(afterFooterLines lines: [RecognizedLine]) -> Bool { false }
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

    func supplementalRegions(afterFooterLines lines: [RecognizedLine]) -> [SupplementalTextRegion] {
        var seen: Set<String> = []
        return recognizers.compactMap { adapter in
            guard let region = adapter.supplementalRegion,
                  adapter.needsSupplementalText(afterFooterLines: lines), seen.insert(region.id).inserted else { return nil }
            return region
        }
    }

    func identify(footerLines: [RecognizedLine], supplementalLines: [String: [RecognizedLine]]) -> RecognitionOutcome {
        aggregate(recognizers.map { adapter in
            guard let region = adapter.supplementalRegion, let lines = supplementalLines[region.id] else {
                return (adapter.game, adapter.identify(footerLines))
            }
            return (adapter.game, adapter.identify(footerLines: footerLines, supplementalLines: lines))
        })
    }

    func identify(_ lines: [RecognizedLine]) -> RecognitionOutcome {
        // Evaluate every adapter before deciding; registration order cannot win.
        let outcomes = recognizers.map { ($0.game, $0.identify(lines)) }
        return aggregate(outcomes)
    }

    func identify(footerLines: [RecognizedLine], fullCardLines: [RecognizedLine]) -> RecognitionOutcome {
        let outcomes = recognizers.map { adapter -> (CardGame, GameRecognitionOutcome) in
            guard adapter.needsFullCardText(afterFooterLines: footerLines) else {
                return (adapter.game, adapter.identify(footerLines))
            }
            let result = adapter.identify(footerLines + fullCardLines)
            if result == .nothing {
                // A known footer with an unreadable title must not borrow an
                // unrelated historical identity from card rules or artwork text.
                return (adapter.game, .rejected(.init(reason: "Supported footer requires matching card text",
                    blocksFallbackRecognition: true)))
            }
            return (adapter.game, result)
        }
        return aggregate(outcomes)
    }

    private func aggregate(_ outcomes: [(CardGame, GameRecognitionOutcome)]) -> RecognitionOutcome {
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

    func needsFullCardText(afterFooterLines lines: [RecognizedLine]) -> Bool {
        recognizers.contains { $0.needsFullCardText(afterFooterLines: lines) }
    }
}
