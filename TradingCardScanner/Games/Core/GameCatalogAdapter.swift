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
        Self.compactChoiceLabels(among: candidates.contains(where: { $0.id == id }) ? candidates : candidates + [self])[id] ?? choiceLabel
    }

    /// Whole-family consumers compute each short label once rather than
    /// repeating every sibling's disambiguation for every returned card.
    static func compactChoiceLabels(among candidates: [Self]) -> [String: String] {
        // Island can have hundreds of printings. Prepare each field and date
        // once, before comparing labels; formatting dates in the nested sibling
        // scans can block the main thread for seconds even for visible rows.
        let formatter = releaseDateFormatter()
        let dates = candidates.map { $0.releaseDate.map { formatter.string(from: $0) } }
        let parts = candidates.enumerated().map { index, candidate in
            let release = candidate.releaseLabel?.components(separatedBy: " · ")
                .filter { $0 != "English" }.joined(separator: " · ")
            return [candidate.treatmentLabel ?? "", candidate.distributionLabel ?? "", release ?? ""]
                + candidate.identificationDetails + [dates[index] ?? ""]
        }
        var indexesByPart: [[String: Set<Int>]] = []
        for (index, fields) in parts.enumerated() {
            for (column, value) in fields.enumerated() {
                if indexesByPart.count <= column { indexesByPart.append([:]) }
                indexesByPart[column][value, default: []].insert(index)
            }
        }
        let choices = candidates.enumerated().map { index, candidate in
            (candidate: candidate, short: candidate.shortChoiceLabel(parts: parts[index], indexesByPart: indexesByPart,
                candidateCount: candidates.count, excluding: index),
             full: candidate.choiceLabel, date: dates[index])
        }
        let groups = Dictionary(grouping: choices, by: \.short)
        var labels: [String: String] = [:]
        for choice in choices {
            let collides = groups[choice.short, default: []].contains {
                $0.candidate.id != choice.candidate.id
                    && ($0.full != choice.full || $0.candidate.releaseDate != choice.candidate.releaseDate)
            }
            labels[choice.candidate.id] = collides
                ? ([choice.full, choice.date].compactMap { $0 }).joined(separator: " · ") : choice.short
        }
        return labels
    }

    private func shortChoiceLabel(parts own: [String], indexesByPart: [[String: Set<Int>]],
                                  candidateCount: Int, excluding candidateIndex: Int) -> String {
        var remaining: Set<Int>?
        var labels: [String] = []
        // A release or stamp that alone distinguishes the candidate beats
        // combining several individually repeated pieces of metadata.
        if let unique = own.enumerated().first(where: { index, value in
            !value.isEmpty && candidateCount > 1 && indexesByPart[index][value]?.count == 1
        }) { return unique.element }
        for (index, value) in own.enumerated() where !value.isEmpty {
            let matching = indexesByPart[index][value, default: []]
            if let remaining {
                guard !remaining.isSubset(of: matching) else { continue }
            } else {
                guard matching.count < candidateCount else { continue }
            }
            labels.append(value)
            remaining = remaining.map { $0.intersection(matching) } ?? matching
            remaining?.remove(candidateIndex)
            if remaining?.isEmpty == true { break }
        }
        return labels.isEmpty ? (own.first(where: { !$0.isEmpty }) ?? name)
            : labels.joined(separator: " · ")
    }

    var releaseDateLabel: String? {
        guard let releaseDate else { return nil }
        return Self.releaseDateFormatter().string(from: releaseDate)
    }

    private static func releaseDateFormatter() -> DateFormatter {
        // Product release dates are UTC calendar dates, not local instants.
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    enum SelectionEvidence: Equatable {
        case labels
        case artwork
        case insufficient
    }

    private struct VisibleChoice: Hashable {
        let label: String
        let date: Date?
    }

    /// Compute the whole family's selection requirements once per presentation.
    /// Calling the per-row helper for every printing repeats all label building.
    static func selectionEvidenceByID(among candidates: [Self]) -> [String: SelectionEvidence] {
        let groups = Dictionary(grouping: candidates) { VisibleChoice(label: $0.choiceLabel, date: $0.releaseDate) }
        var result: [String: SelectionEvidence] = [:]
        for group in groups.values {
            let artworkCounts = Dictionary(grouping: group.compactMap(\.artworkID), by: { $0 }).mapValues(\.count)
            let allHaveArtwork = group.allSatisfy { $0.artworkID != nil }
            for candidate in group {
                if group.count == 1 { result[candidate.id] = .labels }
                else if allHaveArtwork, let artwork = candidate.artworkID,
                        candidate.thumbnailURL != nil, artworkCounts[artwork] == 1 {
                    result[candidate.id] = .artwork
                } else { result[candidate.id] = .insufficient }
            }
        }
        return result
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
    /// Explicit catalog recovery may correct OCR. Pin acquisition to the chosen
    /// printing while the scanner retains the original observation separately.
    func identifierForCatalogSelection(printingID: String, original: ScanIdentifier) throws -> ScanIdentifier
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
    /// Synchronous final guard under the container's ownership transaction. It
    /// also validates CSV/staged rows against authority installed after lookup.
    func validateCollectionMutation(printingID: String, catalogProviderID: String?, variantID: String?,
                                    itemKindRaw: String, collectionKey: String) throws
}

extension GameCatalogAdapter {
    func identifierForCatalogSelection(printingID: String, original: ScanIdentifier) throws -> ScanIdentifier { original }
    func validateCollectionMutation(printingID: String, catalogProviderID: String?, variantID: String?,
                                    itemKindRaw: String, collectionKey: String) throws {}
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
