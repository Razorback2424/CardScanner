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

    // MARK: - Graded and sealed
    //
    // Both go through their own namespaced key rather than the raw card's, so a
    // slab or a booster box can never share a row, a quantity or a price record
    // with the raw copy of the same printing.

    /// Add one graded slab.
    ///
    /// A slab with a certificate number is one specific physical object and
    /// never stacks — two PSA 10s of the same card are two rows. Without a
    /// certificate they are indistinguishable to the app, so identical grades
    /// aggregate the way raw copies do.
    @discardableResult
    func addGraded(
        underlying card: IdentifiedCard,
        variant: GradedVariant,
        certificationNumber: String?,
        setReleaseOrder: Int? = nil
    ) -> CollectionMutation {
        let key = CollectedCard.gradedCollectionKey(
            game: card.game,
            underlyingPrintingID: card.providerID,
            variantUUID: variant.id,
            certificationNumber: certificationNumber
        )

        if certificationNumber == nil, let existing = self.card(forKey: key) {
            existing.quantity += 1
            existing.dateAdded = .now
            try? context.save()
            return CollectionMutation(collectionKey: key, didInsert: false)
        }

        let row = CollectedCard(
            collectionKey: key,
            game: card.game,
            providerID: key,
            name: card.name,
            setName: card.setName,
            setCode: card.setCode,
            cardNumber: card.cardNumber,
            rarity: card.rarity,
            imageURL: imageURL(for: card),
            thumbnailURL: card.thumbnailImageURL?.absoluteString,
            // A slab has no raw finish. `PhysicalVariant` stays raw-only, and the
            // grade lives in its own fields.
            variant: nil,
            variantResolution: .userConfirmed,
            identityResolution: .catalogSelected,
            setReleaseOrder: setReleaseOrder ?? card.setReleaseOrder
        )
        row.itemKindRaw = CollectionItemKind.gradedCard.rawValue
        row.justTCGVariantID = variant.id
        row.justTCGAPIVersion = JustTCGV2GradedClient.apiVersion
        row.gradingCompanyRaw = variant.company.rawValue
        row.gradeRaw = variant.grade.value
        row.gradeLabel = variant.grade.label
        row.gradingQualifier = variant.grade.qualifier
        row.certificationNumber = certificationNumber
        row.catalogProviderID = card.providerID
        context.insert(row)
        try? context.save()
        return CollectionMutation(collectionKey: key, didInsert: true)
    }

    /// Add one sealed product. These aggregate normally — three identical
    /// booster boxes are a quantity of three.
    @discardableResult
    func addSealed(
        _ product: SealedProductSummary,
        game: CardGame
    ) -> CollectionMutation {
        let variantUUID = product.variantID ?? product.id
        let key = CollectedCard.sealedCollectionKey(
            game: game,
            productUUID: product.id,
            variantUUID: variantUUID
        )

        if let existing = self.card(forKey: key) {
            existing.quantity += 1
            existing.dateAdded = .now
            try? context.save()
            return CollectionMutation(collectionKey: key, didInsert: false)
        }

        let row = CollectedCard(
            collectionKey: key,
            game: game,
            providerID: key,
            name: product.name,
            setName: product.setName ?? "",
            // Sealed products are not part of a printed set's numbering, so they
            // carry no set code and no collector number rather than a fabricated
            // one that would collide with real cards.
            setCode: "",
            cardNumber: "",
            rarity: nil,
            imageURL: product.imageURL?.absoluteString,
            thumbnailURL: nil,
            variant: nil,
            variantResolution: .userConfirmed,
            identityResolution: .catalogSelected
        )
        row.itemKindRaw = CollectionItemKind.sealedProduct.rawValue
        row.justTCGCardID = product.id
        row.justTCGVariantID = product.variantID
        row.justTCGAPIVersion = JustTCGV1Client.apiVersion
        context.insert(row)
        try? context.save()
        return CollectionMutation(collectionKey: key, didInsert: true)
    }

    private func imageURL(for card: IdentifiedCard) -> String? {
        switch card {
        case let .pokemon(pokemon, _): return pokemon.image
        case .magic: return card.displayImageURL?.absoluteString
        }
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
