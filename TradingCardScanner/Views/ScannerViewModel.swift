import Combine
import Foundation
import UIKit

@MainActor
final class ScannerViewModel: ObservableObject {
    enum Phase: Equatable {
        case scanning
        case identifying
    }

    @Published var phase: Phase = .scanning
    @Published var resultCard: TCGdexCard?
    @Published var resultSetCode: String = ""
    @Published var lookupMessage: String?

    let scanner = CardScanner()
    private let tcgdex = TCGdexService()
    private var lookupMessageTask: Task<Void, Never>?

    init() {
        scanner.onConfirmedCandidate = { [weak self] candidate in
            guard let self else { return }
            Task { @MainActor in
                await self.identify(candidate)
            }
        }
    }

    func start() {
        scanner.start()
        scanner.resumeRecognition()
    }

    /// `fullScreenCover` fires the scanner's `onDisappear` when the result sheet
    /// covers it. Tearing the capture session down there and rebuilding it on
    /// dismiss costs a second of black preview on every single scan, and each
    /// rebuild is another round of capture-source XPC setup in the console. Hold
    /// the session and just stop recognizing while the result is up.
    func viewDisappeared() {
        guard resultCard == nil else {
            scanner.pauseRecognition()
            return
        }
        stop()
    }

    func stop() {
        scanner.stop()
    }

    func resetForNextScan() {
        resultCard = nil
        resultSetCode = ""
        phase = .scanning
        scanner.start()
        scanner.resumeRecognition()
    }

    private func identify(_ candidate: ScanCandidate) async {
        guard phase == .scanning else { return }

        phase = .identifying
        scanner.pauseRecognition()

        do {
            let card = try await tcgdex.fetchCard(
                setID: candidate.setDefinition.tcgdexSetID,
                localID: candidate.cardNumber
            )

            // TCGdex is our final sanity check before showing a result.
            guard card.set.cardCount.official == candidate.printedSetTotal else {
                showLookupFailure("\(candidate.displayIdentifier): set count did not match TCGdex")
                phase = .scanning
                scanner.resumeRecognition()
                return
            }

            lookupMessage = nil
            resultSetCode = candidate.setCode
            resultCard = card
        } catch {
            showLookupFailure("\(candidate.displayIdentifier): \(error.localizedDescription)")
            phase = .scanning
            scanner.resumeRecognition()
        }
    }

    private func showLookupFailure(_ message: String) {
        lookupMessageTask?.cancel()
        lookupMessage = message
        UINotificationFeedbackGenerator().notificationOccurred(.warning)

        lookupMessageTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            if self?.lookupMessage == message {
                self?.lookupMessage = nil
            }
        }
    }
}
