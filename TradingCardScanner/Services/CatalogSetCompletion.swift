import Foundation
import Combine

/// The completion builder only needs the manifest for every set and one
/// checklist for the owned candidates it actually resolves. Keeping this seam
/// small makes the I/O bound decision testable without materialising the whole
/// bundled snapshot.
protocol CatalogSetCompletionChecklistStore: Sendable {
    func mergedEntries() async -> [PokemonChecklistSnapshotEntry]
    func mergedChecklist(for setID: CatalogSetID) async -> [CatalogCardSummary]?
}

extension PokemonChecklistStore: CatalogSetCompletionChecklistStore {}

actor CatalogSetCompletionBuilder {
    private let checklistStore: any CatalogSetCompletionChecklistStore

    init(
        checklistStore: any CatalogSetCompletionChecklistStore = PokemonChecklistStore.shared
    ) {
        self.checklistStore = checklistStore
    }

    func build(
        sets: [CatalogSet],
        ownership: CatalogOwnershipIndex,
        tier: PokemonMasterSetTier
    ) async -> CatalogSetCompletionIndex {
        let entries = await checklistStore.mergedEntries()
        let entriesBySetID = entries.reduce(into: [String: PokemonChecklistSnapshotEntry]()) {
            result, entry in
            result[entry.set.id] = entry
        }
        let ownedKeys = ownership.ownedSetKeys()

        var candidateIDs: Set<String> = []
        let candidateSets = sets.filter { set in
            guard set.game == .pokemon else { return false }
            let codeMatches = ownedKeys.codes.contains(normalizedKey(set.code))
            let providerPrefix = normalizedKey(set.providerID) + "-"
            let providerMatches = ownedKeys.providerIDs.contains {
                $0.hasPrefix(providerPrefix)
            }
            guard codeMatches || providerMatches else { return false }
            return candidateIDs.insert(set.id).inserted
        }
        let ownedRowsBySetID = ownership.ownedRowCounts(for: candidateSets)
        let pokemonCandidates = candidateSets.sorted {
            let leftOwnedRows = ownedRowsBySetID[$0.id] ?? 0
            let rightOwnedRows = ownedRowsBySetID[$1.id] ?? 0
            if leftOwnedRows != rightOwnedRows {
                return leftOwnedRows > rightOwnedRows
            }
            return $0.id < $1.id
        }
        // A large owned collection can otherwise turn opening the directory
        // into a checklist crawl. The first forty candidates receive exact
        // variation progress. They are selected by owned-row count above so
        // the bounded exact work is stable and useful; overflow deliberately
        // uses collector-number progress with the same manifest denominator.
        let exactCandidateIDs = Set(
            pokemonCandidates.prefix(40).map(\.id)
        )
        let overflowCandidateIDs = Set(
            pokemonCandidates.dropFirst(40).map(\.id)
        )
        var exactChecklistsBySetID: [String: [CatalogCardSummary]] = [:]
        exactChecklistsBySetID.reserveCapacity(exactCandidateIDs.count)
        for candidate in pokemonCandidates.prefix(40) {
            exactChecklistsBySetID[candidate.id] =
                await checklistStore.mergedChecklist(for: candidate.catalogID) ?? []
        }

        var completions: [String: SetCompletion] = [:]
        completions.reserveCapacity(sets.count)
        for set in sets {
            guard set.game == .pokemon else {
                completions[set.id] = ownership.progress(for: set)
                continue
            }

            let entry = entriesBySetID[set.id]
            let total: Int? = {
                switch tier {
                case .standard:
                    return entry?.standardSlotCount
                        ?? entry?.officialCount
                        ?? set.cardCount
                case .expanded:
                    return entry?.expandedSlotCount
                        ?? entry?.officialCount
                        ?? set.cardCount
                }
            }()

            if exactCandidateIDs.contains(set.id) {
                let cards = exactChecklistsBySetID[set.id] ?? []
                let slots = tier == .standard
                    ? cards.filter { !$0.isExpandedMasterSetVariant }
                    : cards
                let progress = ownership.progress(for: slots)
                completions[set.id] = SetCompletion(
                    owned: progress.owned,
                    total: total,
                    unit: "variations"
                )
            } else if overflowCandidateIDs.contains(set.id) {
                let progress = ownership.progress(for: set)
                completions[set.id] = SetCompletion(
                    owned: progress.owned,
                    total: total,
                    unit: "cards"
                )
            } else {
                // Unowned sets do not need a checklist read. The directory
                // still shows the manifest denominator so it agrees with the
                // detail screen once the user opens the set.
                completions[set.id] = SetCompletion(
                    owned: 0,
                    total: total,
                    unit: "variations"
                )
            }
        }

        return CatalogSetCompletionIndex(completions: completions, tier: tier)
    }

    private func normalizedKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
    }
}

/// A coalescing main-actor store keeps completion calculation off the view
/// tree. Every caller can submit its newest set list/tier while one manifest
/// read is in flight; only the newest request is published.
@MainActor
final class CatalogSetCompletionStore: ObservableObject {
    @Published private(set) var index: CatalogSetCompletionIndex?

    private let builder: CatalogSetCompletionBuilder
    private var rebuildTask: Task<Void, Never>?
    private var rebuildRequested = false
    private var requestedSets: [CatalogSet] = []
    private var requestedOwnership = CatalogOwnershipIndex(rows: [])
    private var requestedTier: PokemonMasterSetTier = .standard

    init(builder: CatalogSetCompletionBuilder = CatalogSetCompletionBuilder()) {
        self.builder = builder
    }

    func rebuild(
        sets: [CatalogSet],
        ownership: CatalogOwnershipIndex,
        tier: PokemonMasterSetTier
    ) async {
        requestedSets = sets
        requestedOwnership = ownership
        requestedTier = tier
        rebuildRequested = true
        guard rebuildTask == nil else {
            await rebuildTask?.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.rebuildTask = nil }

            while self.rebuildRequested {
                self.rebuildRequested = false
                let sets = self.requestedSets
                let ownership = self.requestedOwnership
                let tier = self.requestedTier
                let candidate = await self.builder.build(
                    sets: sets,
                    ownership: ownership,
                    tier: tier
                )
                guard !Task.isCancelled else { return }
                guard !self.rebuildRequested else { continue }
                self.index = candidate
            }
        }
        rebuildTask = task
        await task.value
    }
}
