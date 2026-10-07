import Foundation

struct CanonicalCardSummary: Hashable, Sendable {
    let id: String
    let game: CardGame
    let name: String
    let printedIdentifier: String
    let language: String?
}

struct PhysicalPrintingCandidate: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let game: CardGame
    let canonicalCardID: String
    let language: String
    let catalogGeneration: String
    let name: String
    let printedIdentifier: String
    let releaseLabel: String?
    let treatmentLabel: String?
    let distributionLabel: String?
    let releaseDate: Date?
    let thumbnailURL: URL?
    /// Optional presentation evidence keeps older recovery records decodable.
    /// Artwork identity is used for comparison, never shown as a collector label.
    let artworkID: String?
    let distinctionLabels: [String]?
    let recognitionGeneration: String?

    init(id: String, game: CardGame, canonicalCardID: String, language: String,
         catalogGeneration: String, name: String, printedIdentifier: String,
         releaseLabel: String? = nil, treatmentLabel: String? = nil,
         distributionLabel: String? = nil, releaseDate: Date? = nil,
         thumbnailURL: URL? = nil, artworkID: String? = nil,
         distinctionLabels: [String]? = nil, recognitionGeneration: String? = nil) {
        self.id = id; self.game = game; self.canonicalCardID = canonicalCardID
        self.language = language; self.catalogGeneration = catalogGeneration
        self.name = name; self.printedIdentifier = printedIdentifier
        self.releaseLabel = releaseLabel; self.treatmentLabel = treatmentLabel
        self.distributionLabel = distributionLabel; self.releaseDate = releaseDate
        self.thumbnailURL = thumbnailURL; self.artworkID = artworkID
        self.distinctionLabels = distinctionLabels
        self.recognitionGeneration = recognitionGeneration
    }

    var choiceTitle: String {
        let labels = [releaseLabel, treatmentLabel, distributionLabel].compactMap { value -> String? in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        return labels.isEmpty ? name : labels.joined(separator: " · ")
    }

    var identificationDetails: [String] {
        (distinctionLabels ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var choiceLabel: String { ([choiceTitle] + identificationDetails).joined(separator: " · ") }

    /// Older persisted choices predate the optional artwork/footer fields.
    /// All original identity and presentation fields must still agree; supplied
    /// newer evidence must match in full rather than being silently discarded.
    func matchesPersistedChoice(_ candidate: Self) -> Bool {
        guard recognitionGeneration == candidate.recognitionGeneration else { return false }
        guard candidate.artworkID == nil, candidate.distinctionLabels == nil else { return self == candidate }
        return candidate == Self(id: id, game: game, canonicalCardID: canonicalCardID,
            language: language, catalogGeneration: catalogGeneration, name: name,
            printedIdentifier: printedIdentifier, releaseLabel: releaseLabel, treatmentLabel: treatmentLabel,
            distributionLabel: distributionLabel, releaseDate: releaseDate, thumbnailURL: thumbnailURL,
            recognitionGeneration: recognitionGeneration)
    }

    /// Prefer the shortest published distinction, retaining longer evidence
    /// when otherwise identical labels would collapse two physical choices.
    func compactChoiceLabel(among candidates: [Self]) -> String {
        func parts(_ candidate: Self) -> [String] {
            let release = candidate.releaseLabel?.components(separatedBy: " · ")
                .filter { $0 != "English" }.joined(separator: " · ")
            return [candidate.treatmentLabel ?? "", candidate.distributionLabel ?? "", release ?? ""]
                + candidate.identificationDetails + [candidate.releaseDateLabel ?? ""]
        }
        func shortLabel(_ candidate: Self) -> String {
            let own = parts(candidate)
            var remaining = candidates.filter { $0.id != candidate.id }.map(parts)
            var labels: [String] = []
            // A release or stamp that alone distinguishes the candidate beats
            // combining several individually repeated pieces of metadata.
            if let unique = own.enumerated().first(where: { index, value in
                !value.isEmpty && !remaining.isEmpty
                    && remaining.allSatisfy({ !$0.indices.contains(index) || $0[index] != value })
            }) { return unique.element }
            for (index, value) in own.enumerated() where !value.isEmpty {
                guard remaining.contains(where: { !$0.indices.contains(index) || $0[index] != value }) else { continue }
                labels.append(value)
                remaining = remaining.filter { $0.indices.contains(index) && $0[index] == value }
                if remaining.isEmpty { break }
            }
            return labels.isEmpty ? (own.first(where: { !$0.isEmpty }) ?? candidate.name)
                : labels.joined(separator: " · ")
        }
        let short = shortLabel(self)
        if candidates.contains(where: { $0.id != id && shortLabel($0) == short
            && ($0.choiceLabel != choiceLabel || $0.releaseDate != releaseDate) }) {
            return ([choiceLabel, releaseDateLabel].compactMap { $0 }).joined(separator: " · ")
        }
        return short
    }

    var releaseDateLabel: String? {
        guard let releaseDate else { return nil }
        // Product release dates are UTC calendar dates, not local instants.
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: releaseDate)
    }

    enum SelectionEvidence: Equatable {
        case labels
        case artwork
        case insufficient
    }

    /// Identical visible text cannot prove which printing a person chose.
    /// Distinct reviewed artwork can supply that distinction once it loads.
    func selectionEvidence(among candidates: [Self]) -> SelectionEvidence {
        let sameLabels = candidates.filter { $0.choiceLabel == choiceLabel && $0.releaseDate == releaseDate }
        guard sameLabels.count > 1 else { return .labels }
        guard let artworkID, thumbnailURL != nil,
              sameLabels.allSatisfy({ $0.id == id || ($0.artworkID != nil && $0.artworkID != artworkID) }) else {
            return .insufficient
        }
        return .artwork
    }
}

enum CatalogLookupOutcome: Sendable {
    /// Includes the original payload timestamp, provenance and cache eligibility.
    case resolved(CardCatalog.CatalogResolution)
    case needsPrintingChoice(canonical: CanonicalCardSummary, candidates: [PhysicalPrintingCandidate])
    case catalogIncomplete(CanonicalCardSummary?)
}

enum CatalogLookupError: Error {
    case staleCatalog
    case invalidAdapterOutcome
    case invalidPrintingChoice
    case printingChoiceRequired(CanonicalCardSummary, [PhysicalPrintingCandidate])
    case catalogIncomplete(CanonicalCardSummary?)
}

/// One immutable catalog generation. Activation installs a new adapter;
/// existing requests/choices must retain or explicitly revalidate their snapshot.
protocol GameCatalogAdapter: Sendable {
    var game: CardGame { get }
    var generation: String { get }
    func prepareLookupIdentifier(_ identifier: ScanIdentifier) throws -> ScanIdentifier
    func acceptsCompletion(for identifier: ScanIdentifier, fromGeneration: String) -> Bool
    func prewarm() async
    /// Explicit retry may rebase printed evidence, never a saved printing choice.
    func identifierForRetry(_ identifier: ScanIdentifier) throws -> ScanIdentifier
    func lookup(_ identifier: ScanIdentifier) async throws -> CatalogLookupOutcome
    /// Optional fresh membership lookup for explicit choices. It must not
    /// turn a user's answer into automatic resolution after language confirmation.
    func lookupPrintingChoices(_ identifier: ScanIdentifier) async throws -> CatalogLookupOutcome?
    func resolve(_ candidate: PhysicalPrintingCandidate, for identifier: ScanIdentifier) async throws -> CardCatalog.CatalogResolution
    /// Recheck semantic context even when a session outcome was cached.
    func validateLookupContext(_ identifier: ScanIdentifier) async throws
    /// Runs immediately before persistence; automatic resolution requires a
    /// current complete universe while an explicit reviewed choice is distinct.
    func validateAcquisition(_ identifier: ScanIdentifier, printingID: String, automatic: Bool) async throws
    /// Revalidates a user-requested finish change against the currently
    /// installed physical printing before collection rows or ledger history move.
    func validateVariantCorrection(printingID: String, variantID: String?) throws
}

extension GameCatalogAdapter {
    func lookupPrintingChoices(_ identifier: ScanIdentifier) async throws -> CatalogLookupOutcome? { nil }
    func validateLookupContext(_ identifier: ScanIdentifier) async throws {}
    func validateAcquisition(_ identifier: ScanIdentifier, printingID: String, automatic: Bool) async throws {}
    func acceptsCompletion(for identifier: ScanIdentifier, fromGeneration: String) -> Bool {
        identifier.game == game && generation == fromGeneration
    }

    func prewarm() async {}

    func prepareLookupIdentifier(_ identifier: ScanIdentifier) throws -> ScanIdentifier {
        guard identifier.game == game, identifier.catalogGeneration == generation else {
            throw CatalogLookupError.staleCatalog
        }
        return identifier
    }

    func identifierForRetry(_ identifier: ScanIdentifier) throws -> ScanIdentifier {
        guard identifier.game == game, identifier.catalogGeneration == generation else {
            throw CatalogLookupError.staleCatalog
        }
        return identifier
    }

    func validateVariantCorrection(printingID: String, variantID: String?) throws {
        throw CatalogLookupError.invalidPrintingChoice
    }
}

struct GameCatalogSnapshot: Sendable {
    let revision: Int
    let catalog: any GameCatalogAdapter
    let recognizer: any GameRecognitionAdapter
    let variantPolicy: any GameVariantPolicy
    var browse: (any GameBrowseAdapter)? = nil
    var importer: (any GameImportAdapter)? = nil
    var priceAuthority: GameCatalogPriceAuthority? = nil
}

protocol GameCatalogActivationSource: Sendable {
    var game: CardGame { get }
    func currentSnapshot() async -> GameCatalogSnapshot?
    func activationSnapshots() async -> AsyncStream<GameCatalogSnapshot>
    func refreshAtLaunch() async
}

extension GameCatalogActivationSource {
    func refreshAtLaunch() async {}
}

struct GameCatalogAdapterRegistry: Sendable {
    enum RegistrationError: Error, Equatable { case duplicateGame(CardGame) }
    private let adapters: [CardGame: any GameCatalogAdapter]

    init(adapters: [any GameCatalogAdapter]) throws {
        var values: [CardGame: any GameCatalogAdapter] = [:]
        for adapter in adapters {
            guard values[adapter.game] == nil else { throw RegistrationError.duplicateGame(adapter.game) }
            values[adapter.game] = adapter
        }
        self.adapters = values
    }

    func adapter(for game: CardGame) -> (any GameCatalogAdapter)? { adapters[game] }
    var games: [CardGame] { adapters.keys.sorted { $0.rawValue < $1.rawValue } }
    func replacing(_ adapter: any GameCatalogAdapter) -> Self {
        try! Self(adapters: adapters.values.filter { $0.game != adapter.game } + [adapter])
    }
}
