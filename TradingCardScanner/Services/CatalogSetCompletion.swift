import Foundation
import Combine
import OSLog

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
    private struct BuildInputs: Equatable {
        let sets: [CatalogSet]
        let ownership: CatalogOwnershipIndex
        let tier: PokemonMasterSetTier
        let entries: [PokemonChecklistSnapshotEntry]
    }
    private var lastBuild: (inputs: BuildInputs, index: CatalogSetCompletionIndex)?

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
        // The manifest fingerprints also catch checklist changes while Browse
        // was closed, even when the directory and collection are unchanged.
        let inputs = BuildInputs(sets: sets, ownership: ownership, tier: tier, entries: entries)
        if let lastBuild, lastBuild.inputs == inputs { return lastBuild.index }
        let interval = PerformanceSignpost.signposter.beginInterval("CatalogSetCompletion.build")
        defer { PerformanceSignpost.signposter.endInterval("CatalogSetCompletion.build", interval) }
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
        // shows collector numbers without a variation denominator or percentage.
        let exactCandidateIDs = Set(
            pokemonCandidates.prefix(40).map(\.id)
        )
        let overflowCandidateIDs = Set(
            pokemonCandidates.dropFirst(40).map(\.id)
        )
        var exactChecklistsBySetID: [String: [CatalogCardSummary]] = [:]
        exactChecklistsBySetID.reserveCapacity(exactCandidateIDs.count)
        var allChecklistsLoaded = true
        for candidate in pokemonCandidates.prefix(40) {
            if let checklist = await checklistStore.mergedChecklist(for: candidate.catalogID) {
                exactChecklistsBySetID[candidate.id] = checklist
            } else {
                allChecklistsLoaded = false
            }
        }

        var completions: [String: SetCompletion] = [:]
        completions.reserveCapacity(sets.count)
        for set in sets {
            guard set.game == .pokemon else {
                if set.physicalPrintingIDs == nil,
                   !ownedKeys.codes.contains(normalizedKey(set.code)) {
                    completions[set.id] = SetCompletion(owned: 0, total: set.cardCount, unit: "cards")
                } else {
                    completions[set.id] = ownership.progress(for: set)
                }
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
                    total: nil,
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

        let index = CatalogSetCompletionIndex(completions: completions, tier: tier)
        // A transient unavailable checklist must be retried on the next request.
        lastBuild = allChecklistsLoaded ? (inputs, index) : nil
        return index
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
                if self.index != candidate { self.index = candidate }
            }
        }
        rebuildTask = task
        await task.value
    }
}
