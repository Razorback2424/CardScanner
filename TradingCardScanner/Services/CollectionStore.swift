import Foundation
import SwiftData

/// A single recorded change, kept only so it can be taken back.
struct CollectionMutation: Equatable, Sendable {
    let collectionKey: String
    let activityID: UUID?
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
            storeMarketPrice(
                variant.marketPriceUSD,
                updatedAt: variant.updatedAt,
                marketVariantID: variant.id,
                for: existing
            )
            try? context.save()
            let activity = record(existing, source: .gradedCatalog)
            try? context.save()
            return CollectionMutation(collectionKey: key, activityID: activity.id, didInsert: false)
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
        // Both handles. Without the card handle a refresh has no way back to
        // this slab: graded variants live only in v2, and v2 finds a card by
        // set and name rather than by the catalog id the row already had.
        row.justTCGCardID = variant.cardID
        row.justTCGAPIVersion = JustTCGV2GradedClient.apiVersion
        row.gradingCompanyRaw = variant.company.rawValue
        row.gradeRaw = variant.grade.value
        row.gradeLabel = variant.grade.label
        row.gradingQualifier = variant.grade.qualifier
        row.certificationNumber = certificationNumber
        row.catalogProviderID = card.providerID
        context.insert(row)
        storeMarketPrice(
            variant.marketPriceUSD,
            updatedAt: variant.updatedAt,
            marketVariantID: variant.id,
            for: row
        )
        let activity = record(row, source: .gradedCatalog)
        try? context.save()
        return CollectionMutation(collectionKey: key, activityID: activity.id, didInsert: true)
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
            // Re-adding also heals rows saved before sealed artwork support.
            if existing.imageURL == nil {
                existing.imageURL = product.imageURL?.absoluteString
            }
            storeMarketPrice(
                product.marketPriceUSD,
                updatedAt: product.updatedAt,
                marketVariantID: product.variantID,
                for: existing
            )
            let activity = record(existing, source: .sealedCatalog)
            try? context.save()
            return CollectionMutation(collectionKey: key, activityID: activity.id, didInsert: false)
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
        storeMarketPrice(
            product.marketPriceUSD,
            updatedAt: product.updatedAt,
            marketVariantID: product.variantID,
            for: row
        )
        let activity = record(row, source: .sealedCatalog)
        try? context.save()
        return CollectionMutation(collectionKey: key, activityID: activity.id, didInsert: true)
    }

    private func imageURL(for card: IdentifiedCard) -> String? {
        switch card {
        case let .pokemon(pokemon, _): return pokemon.image
        case .magic: return card.displayImageURL?.absoluteString
        }
    }

    /// Sealed and graded browse responses already contain the exact variant's
    /// current market observation. Persist it at add time under the exact vendor
    /// variant identity; adding an item must not make the price that was just
    /// shown disappear until a later refresh.
    private func storeMarketPrice(
        _ amount: Double?,
        updatedAt: Date?,
        marketVariantID: String?,
        for card: CollectedCard
    ) {
        guard let amount else { return }
        PriceStore(context: context).store(
            .price(
                NormalizedPrice(
                    unitMarketPriceUSD: amount,
                    currencyCode: "USD",
                    source: .justTCG,
                    sourceVariantID: marketVariantID
                        ?? card.justTCGCardID
                        ?? card.priceStorageID,
                    sourceUpdatedAt: updatedAt,
                    fetchedAt: .now
                )
            ),
            game: card.cardGame,
            printingID: card.priceStorageID,
            variantID: card.variantID
        )
    }

    @discardableResult
    func add(
        _ card: IdentifiedCard,
        resolved: ResolvedVariant,
        source: CollectionActivitySource = .catalog,
        pokemonPrintRun: PokemonPrintRun? = nil,
        identityResolution: IdentityResolution = .printedIdentifier,
        setReleaseOrder: Int? = nil,
        matchCatalogAliases: Bool = false
    ) -> CollectionMutation {
        let baseKey = card.collectionKey(variant: resolved.variant)
        let key = pokemonPrintRun.map { "\(baseKey)@\($0.rawValue)" } ?? baseKey
        let mutation: CollectionMutation
        let stored: CollectedCard

        let existing = self.card(forKey: key) ?? (matchCatalogAliases
            ? catalogAliasCard(
                providerID: card.providerID,
                variantID: resolved.variant?.id,
                pokemonPrintRun: pokemonPrintRun
            )
            : nil)

        if let existing {
            existing.quantity += 1
            existing.dateAdded = .now
            mutation = CollectionMutation(
                collectionKey: existing.collectionKey,
                activityID: nil,
                didInsert: false
            )
            stored = existing
        } else {
            let inserted = CollectedCard(
                card: card,
                resolved: resolved,
                identityResolution: identityResolution,
                setReleaseOrder: setReleaseOrder
            )
            // `CollectedCard` can derive the finish-qualified base key, but the
            // independent Pokémon print run is known only at this layer.
            inserted.collectionKey = key
            inserted.pokemonPrintRunRaw = pokemonPrintRun?.rawValue
            context.insert(inserted)
            mutation = CollectionMutation(collectionKey: key, activityID: nil, didInsert: true)
            stored = inserted
        }

        if let stamped = PokemonStampedReleaseCatalog.entry(
            providerID: card.providerID,
            variantID: resolved.variant?.id
        ) {
            // The catalog identity still points at the source artwork/number,
            // while the owned object belongs to the separate stamped release.
            // Display and artwork must describe what is physically held.
            stored.setName = "Trick or Trade \(stamped.year)"
            stored.setCode = "TOT\(String(stamped.year).suffix(2))"
            let artwork = JustTCGV1Client.productImageURL(
                tcgplayerID: stamped.tcgplayerProductID
            )?.absoluteString
            stored.imageURL = artwork
            stored.thumbnailURL = artwork
        }

        let activity = record(stored, source: source)
        try? context.save()
        return CollectionMutation(
            collectionKey: mutation.collectionKey,
            activityID: activity.id,
            didInsert: mutation.didInsert
        )
    }

    /// Imported entries retain a synthetic storage key after catalog
    /// normalization. The real provider id is still authoritative for deciding
    /// whether a catalog selection is another copy of that same physical object.
    private func catalogAliasCard(
        providerID: String,
        variantID: String?,
        pokemonPrintRun: PokemonPrintRun?
    ) -> CollectedCard? {
        let rows = (try? context.fetch(FetchDescriptor<CollectedCard>())) ?? []
        return rows.first {
            ($0.providerID == providerID || $0.catalogProviderID == providerID)
                && $0.variantID == variantID
                && (pokemonPrintRun == .unlimited
                    ? ($0.pokemonPrintRun == .unlimited || $0.pokemonPrintRun == nil)
                    : $0.pokemonPrintRun == pokemonPrintRun)
        }
    }

    func undo(_ mutation: CollectionMutation) {
        guard let row = card(forKey: mutation.collectionKey) else { return }

        if mutation.didInsert || row.quantity <= 1 {
            context.delete(row)
        } else {
            row.quantity -= 1
        }

        if let activityID = mutation.activityID {
            let descriptor = FetchDescriptor<CollectionActivity>(
                predicate: #Predicate { $0.id == activityID }
            )
            if let activity = try? context.fetch(descriptor).first {
                context.delete(activity)
            }
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

    @discardableResult
    private func record(
        _ card: CollectedCard,
        source: CollectionActivitySource,
        quantity: Int = 1
    ) -> CollectionActivity {
        let activity = CollectionActivity(card: card, source: source, quantity: quantity)
        context.insert(activity)
        return activity
    }

    /// Moves one copy from the variant it was recorded as to the one it really
    /// is. A different variant is a different physical object, so this is a move
    /// between rows rather than an edit in place.
    @discardableResult
    func recordVariantCorrection(
        for card: IdentifiedCard,
        from current: PhysicalVariant?,
        to corrected: ResolvedVariant,
        pokemonPrintRun: PokemonPrintRun? = nil,
        previousCollectionKey: String? = nil
    ) -> CollectionMutation? {
        guard current != corrected.variant else { return nil }

        let previousBaseKey = card.collectionKey(variant: current)
        let previousKey = previousCollectionKey
            ?? pokemonPrintRun.map { "\(previousBaseKey)@\($0.rawValue)" }
            ?? previousBaseKey
        let activityDescriptor = FetchDescriptor<CollectionActivity>(
            predicate: #Predicate { $0.collectionKey == previousKey }
        )
        // The scan being corrected is the newest acquisition for this row. Its
        // event moves with the copy; a correction is not a second acquisition.
        let activityToRetarget = try? context.fetch(activityDescriptor)
            .max(by: { $0.occurredAt < $1.occurredAt })
        if let previous = self.card(forKey: previousKey) {
            if previous.quantity <= 1 {
                context.delete(previous)
            } else {
                previous.quantity -= 1
            }
        }

        let mutation = add(
            card,
            resolved: corrected,
            source: .correction,
            pokemonPrintRun: pokemonPrintRun
        )
        guard let activityToRetarget,
              let correctedCard = self.card(forKey: mutation.collectionKey) else {
            return mutation
        }

        // Remove the provisional correction event created by `add`, then move
        // the original acquisition event to the corrected row so history has
        // neither an orphan nor an extra card addition.
        if let provisionalID = mutation.activityID {
            let descriptor = FetchDescriptor<CollectionActivity>(
                predicate: #Predicate { $0.id == provisionalID }
            )
            if let provisional = try? context.fetch(descriptor).first {
                context.delete(provisional)
            }
        }
        activityToRetarget.collectionKey = correctedCard.collectionKey
        activityToRetarget.name = correctedCard.name
        activityToRetarget.setName = correctedCard.setName
        activityToRetarget.setCode = correctedCard.setCode
        activityToRetarget.cardNumber = correctedCard.cardNumber
        activityToRetarget.variantID = correctedCard.variantID
        activityToRetarget.variantLabel = correctedCard.variantLabel
        activityToRetarget.pokemonPrintRunRaw = correctedCard.pokemonPrintRunRaw
        activityToRetarget.correctedAt = .now
        try? context.save()

        return CollectionMutation(
            collectionKey: mutation.collectionKey,
            activityID: activityToRetarget.id,
            didInsert: mutation.didInsert
        )
    }
}
