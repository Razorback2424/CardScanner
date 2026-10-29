import Foundation
import Combine
import OSLog

/// Value-only inputs: no SwiftData model leaves its executor. The content
/// generation also invalidates work when a reload begins before cards arrive.
struct CatalogSetPresentationInputs: Equatable, Sendable {
    let setID: CatalogSetID
    let contentGeneration: UUID
    let cards: [CatalogCardSummary]
    let search: String
    let sort: CatalogSetSort
    let ownership: CatalogOwnershipFilter
    let ownershipRevision: UInt
    let tier: PokemonMasterSetTier
    let prices: [String: Double]

    init(setID: CatalogSetID, contentGeneration: UUID, cards: [CatalogCardSummary],
         search: String, sort: CatalogSetSort, ownership: CatalogOwnershipFilter,
         ownershipRevision: UInt, tier: PokemonMasterSetTier, prices: [String: Double]) {
        self.setID = setID
        self.contentGeneration = contentGeneration
        self.cards = cards
        self.search = CardNameSearch.normalize(search)
        self.sort = sort
        self.ownership = ownership
        self.ownershipRevision = ownershipRevision
        self.tier = tier
        self.prices = sort.needsPrices ? prices : [:]
    }
}

private struct CatalogSetPreparedPresentation: Sendable {
    struct Row: Sendable {
        let summary: CatalogCardSummary
        let id: String
        let name: String
        let number: String
        let numberKey: CollectorNumber.SortKey
        let identity: CatalogCardDisplayIdentity
    }

    let setID: CatalogSetID
    let cards: [CatalogCardSummary]
    let rows: [Row]
    let numberOrder: [Int]

    init(setID: CatalogSetID, cards: [CatalogCardSummary]) {
        self.setID = setID
        self.cards = cards
        let interval = PerformanceSignpost.signposter.beginInterval("Browse.prepare")
        defer { PerformanceSignpost.signposter.endInterval("Browse.prepare", interval) }
        let rows = cards.map { card in
            Row(summary: card, id: card.id,
                name: CardNameSearch.normalize(card.name),
                number: CardNameSearch.normalize(card.collectorNumber),
                numberKey: CollectorNumber.key(for: card.collectorNumber),
                identity: CatalogCardDisplayIdentity(
                    game: card.game, setID: card.setID, providerID: card.providerID,
                    collectorNumber: SetCompletionCalculator.canonicalNumber(card.collectorNumber)
                        ?? card.collectorNumber.lowercased()
                ))
        }
        self.rows = rows
        numberOrder = rows.indices.sorted {
            let comparison = CollectorNumber.compare(rows[$0].numberKey, rows[$1].numberKey)
            return comparison == .orderedSame
                ? rows[$0].id.compare(rows[$1].id) == .orderedAscending : comparison == .orderedAscending
        }
    }
}

protocol CatalogSetPresentationBuilding: Sendable {
    func groups(for inputs: CatalogSetPresentationInputs,
                owned: CatalogOwnershipIndex) async throws -> [CatalogCardDisplayGroup]
}

/// One actor per set route retains immutable preparation across typing, tier
/// changes and temporary disappearance. A fresh navigation route prepares once.
/// Filtering preserves the established card order.
actor CatalogSetPresentationBuilder: CatalogSetPresentationBuilding {
    struct Diagnostics: Equatable, Sendable {
        var preparations = 0
        var priceSorts = 0
        var projections = 0
    }
    private(set) var diagnostics = Diagnostics()
    private var prepared: CatalogSetPreparedPresentation?
    private var descendingOrder: [Int]?
    private var priceOrder: (sort: CatalogSetSort, prices: [String: Double], indices: [Int])?
    private var ownedFlags: (revision: UInt, flags: [Bool])?
    private var lastPresentation: (inputs: CatalogSetPresentationInputs, groups: [CatalogCardDisplayGroup])?

    func groups(for inputs: CatalogSetPresentationInputs,
                owned: CatalogOwnershipIndex) throws -> [CatalogCardDisplayGroup] {
        try Task.checkCancellation()
        if let lastPresentation, lastPresentation.inputs == inputs { return lastPresentation.groups }
        let interval = PerformanceSignpost.signposter.beginInterval("Browse.project")
        defer { PerformanceSignpost.signposter.endInterval("Browse.project", interval) }
        if prepared?.setID != inputs.setID || prepared?.cards != inputs.cards {
            prepared = CatalogSetPreparedPresentation(setID: inputs.setID, cards: inputs.cards)
            priceOrder = nil
            descendingOrder = nil
            ownedFlags = nil
            diagnostics.preparations += 1
        }
        guard let prepared else { return [] }
        let order: [Int]
        switch inputs.sort {
        case .numberLowToHigh:
            order = prepared.numberOrder
        case .numberHighToLow:
            if descendingOrder == nil {
                descendingOrder = prepared.numberOrder.sorted {
                    let left = prepared.rows[$0], right = prepared.rows[$1]
                    let comparison = CollectorNumber.compare(left.numberKey, right.numberKey)
                    return comparison == .orderedSame
                        ? left.id.compare(right.id) == .orderedDescending : comparison == .orderedDescending
                }
            }
            order = descendingOrder ?? prepared.numberOrder
        case .priceHighToLow, .priceLowToHigh:
            if priceOrder?.sort != inputs.sort || priceOrder?.prices != inputs.prices {
                // Sorting the stable number order also retains number/ID ties
                // and keeps unknown prices last in either price direction.
                let indices = prepared.numberOrder.sorted {
                    let left = inputs.prices[prepared.rows[$0].id]
                    let right = inputs.prices[prepared.rows[$1].id]
                    switch (left, right) {
                    case let (left?, right?) where left != right:
                        return inputs.sort == .priceHighToLow ? left > right : left < right
                    case (_?, nil): return true
                    case (nil, _?): return false
                    default: return false
                    }
                }
                priceOrder = (inputs.sort, inputs.prices, indices)
                diagnostics.priceSorts += 1
            }
            order = priceOrder?.indices ?? prepared.numberOrder
        }
        if inputs.ownership != .all, ownedFlags?.revision != inputs.ownershipRevision {
            ownedFlags = (inputs.ownershipRevision, prepared.rows.map { owned.owns($0.summary) })
        }
        var summaries: [CatalogCardSummary] = []
        var identities: [CatalogCardDisplayIdentity] = []
        for (offset, index) in order.enumerated() {
            if offset.isMultiple(of: 64) { try Task.checkCancellation() }
            let row = prepared.rows[index]
            if row.summary.game == .pokemon, inputs.tier == .standard,
               row.summary.isExpandedMasterSetVariant { continue }
            if !inputs.search.isEmpty,
               !row.name.contains(inputs.search), !row.number.contains(inputs.search) { continue }
            if inputs.ownership != .all {
                let isOwned = ownedFlags?.flags[index] ?? false
                if (inputs.ownership == .owned) != isOwned { continue }
            }
            summaries.append(row.summary)
            identities.append(row.identity)
        }
        let groups = CatalogCardDisplayGrouping.groups(for: summaries, preparedIdentities: identities)
        try Task.checkCancellation()
        lastPresentation = (inputs, groups)
        diagnostics.projections += 1
        return groups
    }
}

/// A new request cancels the previous task immediately. The request identity
/// guards publication too, including builders that finish despite cancellation.
@MainActor
final class CatalogSetPresentationStore: ObservableObject {
    @Published private(set) var groups: [CatalogCardDisplayGroup] = []
    @Published private(set) var isProjecting = false
    private let builder: any CatalogSetPresentationBuilding
    private var requestedInputs: CatalogSetPresentationInputs?
    private var generation: UInt = 0
    private var task: Task<Void, Never>?

    init(builder: any CatalogSetPresentationBuilding = CatalogSetPresentationBuilder()) {
        self.builder = builder
    }

    @discardableResult
    func update(_ inputs: CatalogSetPresentationInputs, owned: CatalogOwnershipIndex) -> Task<Void, Never>? {
        guard requestedInputs != inputs else { return task }
        cancel()
        requestedInputs = inputs
        isProjecting = true
        let generation = generation
        let builder = builder
        task = Task { @MainActor [weak self] in
            do {
                let candidate = try await builder.groups(for: inputs, owned: owned)
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                if self.groups != candidate { self.groups = candidate }
                self.isProjecting = false
                PerformanceSignpost.emitEvent("Browse.presentationPublished",
                    "groups=\(candidate.count) queryLength=\(inputs.search.count)")
            } catch {
                guard let self, self.generation == generation else { return }
                self.isProjecting = false
            }
        }
        return task
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        requestedInputs = nil
        if isProjecting { isProjecting = false }
    }
}
