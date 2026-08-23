import Foundation

/// Why a lookup failed, in the only terms the scanner cares about.
enum CatalogFailure: Equatable {
    /// The identifier was read correctly but no such record exists, or the record
    /// contradicts what was printed on the card. Re-reading the same card will
    /// fail the same way, so the scanner keeps its latch and asks the user to set
    /// the card aside instead of retrying in a loop.
    case notInCatalog
    /// Network or server trouble. Nothing was written and nothing is known to be
    /// wrong with the card, so the very next reading should be allowed through.
    case transient
}

/// Turns identifiers into catalog records, overlapping the network with OCR
/// instead of waiting for one to finish before starting the other.
///
/// The old shape was strictly serial:
///
///     OCR -> confirm -> request -> wait -> result
///
/// The moment a *plausible* identifier appears the request can already be in
/// flight while Vision keeps looking for its second matching observation. The
/// cost becomes `max(confirmation, network)` rather than their sum, and accuracy
/// is untouched because a speculative result is only ever consumed by the exact
/// identifier that was confirmed. A speculation that turns out to be a misread is
/// inert: it is filed under the identifier nobody will ask for.
///
/// The session cache is the other half. A second copy of a printing already
/// resolved this session needs no round trip at all.
actor CardCatalog {
    private let tcgdex = TCGdexService()
    private let scryfall = ScryfallService()

    private var resolved: [ScanIdentifier: IdentifiedCard] = [:]
    private var inFlight: [ScanIdentifier: Task<IdentifiedCard, Error>] = [:]

    /// Start resolving an identifier that looks plausible but is not yet
    /// confirmed. Deliberately returns nothing: speculation must never be able to
    /// affect anything on its own.
    func prefetch(_ identifier: ScanIdentifier) {
        guard resolved[identifier] == nil, inFlight[identifier] == nil else { return }
        let task = start(identifier)
        Task { _ = await self.complete(identifier, task: task) }
    }

    func card(for identifier: ScanIdentifier) async throws -> IdentifiedCard {
        if let card = resolved[identifier] { return card }
        let task = inFlight[identifier] ?? start(identifier)
        return try await complete(identifier, task: task).get()
    }

    func cachedCard(for identifier: ScanIdentifier) -> IdentifiedCard? {
        resolved[identifier]
    }

    static func classify(_ error: Error) -> CatalogFailure {
        switch error {
        case TCGdexError.cardNotFound, TCGdexError.identityMismatch, TCGdexError.invalidURL,
             ScryfallError.cardNotFound, ScryfallError.identityMismatch,
             ScryfallError.unsupportedPrinting, ScryfallError.invalidURL:
            return .notInCatalog
        default:
            return .transient
        }
    }

    private func start(_ identifier: ScanIdentifier) -> Task<IdentifiedCard, Error> {
        let tcgdex = tcgdex
        let scryfall = scryfall
        let task = Task<IdentifiedCard, Error> {
            switch identifier {
            case let .pokemon(setCode, cardNumber, printedTotal, setDefinition):
                let card = try await tcgdex.fetchCard(
                    setID: setDefinition.tcgdexSetID,
                    localID: cardNumber
                )
                // A network response answers the question the card asked; it does
                // not get to change the question. If the record disagrees with the
                // printed denominator or number, the identification failed.
                guard card.set.cardCount.official == printedTotal,
                      Int(card.localId) == Int(cardNumber) else {
                    throw TCGdexError.identityMismatch
                }
                return .pokemon(card, setCode: setCode)

            case let .magic(setCode, collectorNumber, language):
                let card = try await scryfall.fetchCard(
                    setCode: setCode,
                    collectorNumber: collectorNumber,
                    language: language
                )
                return .magic(card)
            }
        }
        inFlight[identifier] = task
        return task
    }

    private func complete(
        _ identifier: ScanIdentifier,
        task: Task<IdentifiedCard, Error>
    ) async -> Result<IdentifiedCard, Error> {
        let result = await task.result
        if case let .success(card) = result {
            resolved[identifier] = card
        }
        // Only successes are remembered. A failed lookup leaves no trace, so the
        // next attempt is a real attempt rather than a replayed failure.
        inFlight[identifier] = nil
        return result
    }
}
