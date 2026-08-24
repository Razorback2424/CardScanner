import Foundation
import SwiftData

/// A single recorded change, kept only so it can be taken back.
struct CollectionMutation: Equatable, Sendable {
    let collectionKey: String
    /// Whether the change created the row or incremented an existing one, which
    /// is the difference between deleting it and counting back down.
    let didInsert: Bool
}

/// Every write to the collection goes through here.
///
/// Auto-add means mutations now happen without a confirmation step, so the
/// upsert, the undo, and the after-the-fact variant correction have to be one
/// mechanism rather than three lookalike blocks scattered through views.
@MainActor
struct CollectionStore {
    let context: ModelContext

    func card(forKey key: String) -> CollectedCard? {
        var descriptor = FetchDescriptor<CollectedCard>(
            predicate: #Predicate { $0.collectionKey == key }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @discardableResult
    func add(
        _ card: IdentifiedCard,
        resolved: ResolvedVariant,
        identityResolution: IdentityResolution = .printedIdentifier,
        setReleaseOrder: Int? = nil,
        matchCatalogAliases: Bool = false
    ) -> CollectionMutation {
        let key = card.collectionKey(variant: resolved.variant)
        let mutation: CollectionMutation

        let existing = self.card(forKey: key) ?? (matchCatalogAliases
            ? catalogAliasCard(providerID: card.providerID, variantID: resolved.variant?.id)
            : nil)

        if let existing {
            existing.quantity += 1
            existing.dateAdded = .now
            mutation = CollectionMutation(collectionKey: existing.collectionKey, didInsert: false)
        } else {
            context.insert(
                CollectedCard(
                    card: card,
                    resolved: resolved,
                    identityResolution: identityResolution,
                    setReleaseOrder: setReleaseOrder
                )
            )
            mutation = CollectionMutation(collectionKey: key, didInsert: true)
        }

        try? context.save()
        return mutation
    }

    /// Imported entries retain a synthetic storage key after catalog
    /// normalization. The real provider id is still authoritative for deciding
    /// whether a catalog selection is another copy of that same physical object.
    private func catalogAliasCard(providerID: String, variantID: String?) -> CollectedCard? {
        let rows = (try? context.fetch(FetchDescriptor<CollectedCard>())) ?? []
        return rows.first {
            ($0.providerID == providerID || $0.catalogProviderID == providerID)
                && $0.variantID == variantID
        }
    }

    func undo(_ mutation: CollectionMutation) {
        guard let row = card(forKey: mutation.collectionKey) else { return }

        if mutation.didInsert || row.quantity <= 1 {
            context.delete(row)
        } else {
            row.quantity -= 1
        }

        try? context.save()
    }

    /// Removes every owned card while leaving catalog and price data alone.
    /// This is intentionally explicit and throwing because the settings screen
    /// confirms the destructive action and reports a persistence failure.
    func deleteAll() throws {
        let cards = try context.fetch(FetchDescriptor<CollectedCard>())
        for card in cards {
            context.delete(card)
        }
        try context.save()
    }

    /// Moves one copy from the variant it was recorded as to the one it really
    /// is. A different variant is a different physical object, so this is a move
    /// between rows rather than an edit in place.
    @discardableResult
    func recordVariantCorrection(
        for card: IdentifiedCard,
        from current: PhysicalVariant?,
        to corrected: ResolvedVariant
    ) -> CollectionMutation? {
        guard current != corrected.variant else { return nil }

        let previousKey = card.collectionKey(variant: current)
        if let previous = self.card(forKey: previousKey) {
            if previous.quantity <= 1 {
                context.delete(previous)
            } else {
                previous.quantity -= 1
            }
        }

        return add(card, resolved: corrected)
    }
}
