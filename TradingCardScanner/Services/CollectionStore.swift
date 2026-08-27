import Foundation
import SwiftData

/// A single recorded change, kept only so it can be taken back.
struct CollectionMutation: Equatable, Sendable {
    let collectionKey: String
    let activityID: UUID?
    /// Whether the change created the row or incremented an existing one, which
    /// is the difference between deleting it and counting back down.
    let didInsert: Bool
    /// The ledger operation this mutation wrote. Undo inverts the whole
    /// operation through this, so a correction can never be half-taken-back.
    var operationID: UUID?
}

/// Every write to the collection goes through here.
///
/// Auto-add means mutations now happen without a confirmation step, so the
/// upsert, the undo, and the after-the-fact variant correction have to be one
/// mechanism rather than three lookalike blocks scattered through views.
@MainActor
struct CollectionStore {
    let context: ModelContext

    private var ledger: InventoryLedger { InventoryLedger(context: context) }

    /// Which flow a source represents.
    ///
    /// The app cannot tell a card bought this morning from one that has been in
    /// a shoebox for ten years, and does not pretend to: both are "added to the
    /// tracked collection" and both belong in the day's reconciliation. Only a
    /// CSV, which explicitly describes a collection that already existed, is
    /// recorded as such. `initialBalance` is reserved for the migration epoch
    /// and is never written here.
    private func inventoryKind(for source: CollectionActivitySource) -> InventoryEventKind {
        source == .csvImport ? .recordExisting : .acquire
    }

    func card(forKey key: String) -> CollectedCard? {
        var descriptor = FetchDescriptor<CollectedCard>(
            predicate: #Predicate { $0.collectionKey == key }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Changes a position's quantity while recording the matching ownership
    /// event in the same persistence transaction.
    func setQuantity(_ newQuantity: Int, for card: CollectedCard) throws {
        guard newQuantity >= 1 else { return }

        let delta = newQuantity - card.quantity
        guard delta != 0 else { return }

        ledger.record(
            card,
            kind: .quantityAdjust,
            source: .correction,
            deltaQuantity: delta
        )
        card.quantity = newQuantity
        try commit()
    }

#if DEBUG
    /// One-time development repair for the seven quantity edits made before
    /// the detail view routed ownership changes through this store.
    static func repairKnownQuantityMismatches(in context: ModelContext) throws {
        let repairs: [(String, Int, UUID)] = [
            ("me02.5-216#normal", -1, UUID(uuidString: "00000000-0000-0000-0000-000000000216")!),
            ("me04-049#normal", -2, UUID(uuidString: "00000000-0000-0000-0000-000000000417")!),
            ("sv07-072#normal", -1, UUID(uuidString: "00000000-0000-0000-0000-000000000072")!),
            ("sv08.5-077#normal", -1, UUID(uuidString: "00000000-0000-0000-0000-000000000077")!),
            ("sv08.5-086#normal", -1, UUID(uuidString: "00000000-0000-0000-0000-000000000086")!),
            ("sv09-026#normal", -1, UUID(uuidString: "00000000-0000-0000-0000-000000000026")!),
            ("sv09-086#normal", -1, UUID(uuidString: "00000000-0000-0000-0000-000000000986")!)
        ]
        let store = CollectionStore(context: context)
        for (key, delta, operationID) in repairs {
            guard let card = store.card(forKey: key) else { continue }
            InventoryLedger(context: context).record(
                card,
                kind: .quantityAdjust,
                source: .correction,
                deltaQuantity: delta,
                operationID: operationID
            )
        }
        try context.save()
    }
#endif

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
    ) throws -> CollectionMutation {
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
            let activity = record(existing, source: .gradedCatalog)
            let operationID = UUID()
            ledger.record(
                existing,
                kind: inventoryKind(for: .gradedCatalog),
                source: .gradedCatalog,
                deltaQuantity: 1,
                operationID: operationID
            )
            try commit()
            return CollectionMutation(
                collectionKey: key,
                activityID: activity.id,
                didInsert: false,
                operationID: operationID
            )
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
        let operationID = UUID()
        ledger.record(
            row,
            kind: inventoryKind(for: .gradedCatalog),
            source: .gradedCatalog,
            deltaQuantity: 1,
            operationID: operationID
        )
        try commit()
        return CollectionMutation(
            collectionKey: key,
            activityID: activity.id,
            didInsert: true,
            operationID: operationID
        )
    }

    /// Add one sealed product. These aggregate normally — three identical
    /// booster boxes are a quantity of three.
    @discardableResult
    func addSealed(
        _ product: SealedProductSummary,
        game: CardGame
    ) throws -> CollectionMutation {
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
            let operationID = UUID()
            ledger.record(
                existing,
                kind: inventoryKind(for: .sealedCatalog),
                source: .sealedCatalog,
                deltaQuantity: 1,
                operationID: operationID
            )
            try commit()
            return CollectionMutation(
                collectionKey: key,
                activityID: activity.id,
                didInsert: false,
                operationID: operationID
            )
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
        row.tcgplayerProductID = product.tcgplayerProductID
        row.justTCGAPIVersion = JustTCGV1Client.apiVersion
        context.insert(row)
        storeMarketPrice(
            product.marketPriceUSD,
            updatedAt: product.updatedAt,
            marketVariantID: product.variantID,
            for: row
        )
        let activity = record(row, source: .sealedCatalog)
        let operationID = UUID()
        ledger.record(
            row,
            kind: inventoryKind(for: .sealedCatalog),
            source: .sealedCatalog,
            deltaQuantity: 1,
            operationID: operationID
        )
        try commit()
        return CollectionMutation(
            collectionKey: key,
            activityID: activity.id,
            didInsert: true,
            operationID: operationID
        )
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
            variantID: card.variantID,
            marketVariantID: marketVariantID
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
        matchCatalogAliases: Bool = false,
        /// Off only for `recordVariantCorrection`, which writes a two-leg
        /// correction group of its own. A correction is a copy moving between
        /// identities, not an acquisition, and recording it as one would put a
        /// card the user already owned into "Added to collection".
        writesInventoryEvent: Bool = true,
        /// False only while a larger ledger-bearing mutation is being staged.
        /// The caller then writes every event and performs the single save.
        savesChanges: Bool = true
    ) throws -> CollectionMutation {
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
        let operationID = writesInventoryEvent ? UUID() : nil
        if let operationID {
            ledger.record(
                stored,
                kind: inventoryKind(for: source),
                source: source,
                deltaQuantity: 1,
                operationID: operationID
            )
        }
        if savesChanges { try commit() }
        return CollectionMutation(
            collectionKey: mutation.collectionKey,
            activityID: activity.id,
            didInsert: mutation.didInsert,
            operationID: operationID
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

    func undo(_ mutation: CollectionMutation) throws {
        guard let row = card(forKey: mutation.collectionKey) else { return }

        // The ledger is taken back by inverting every leg of the operation,
        // never by deleting rows. A history that can be edited away is not a
        // record, and inverting the whole operation is what keeps a two-leg
        // correction from being half-undone.
        if let operationID = mutation.operationID {
            ledger.reverseOperation(operationID)
        }

        if mutation.didInsert || row.quantity <= 1 {
            context.delete(row)
        } else {
            row.quantity -= 1
        }

        // `CollectionActivity` keeps its existing delete-on-undo behaviour. It
        // is a presentation log with its own UI and backfill path, and becomes
        // a projection over `InventoryEvent` in a later phase rather than being
        // rewritten underneath a shipping feature.
        if let activityID = mutation.activityID {
            let descriptor = FetchDescriptor<CollectionActivity>(
                predicate: #Predicate { $0.id == activityID }
            )
            if let activity = try? context.fetch(descriptor).first {
                context.delete(activity)
            }
        }

        try commit()
    }

    /// Removes every owned card while leaving catalog and price data alone.
    /// This is intentionally explicit and throwing because the settings screen
    /// confirms the destructive action and reports a persistence failure.
    func deleteAll() throws {
        let cards = try context.fetch(FetchDescriptor<CollectedCard>())
        let occurredAt = Date.now
        for card in cards {
            // Every copy leaving is a disposal, valued at the price in force
            // now. Without these the whole collection's value would vanish into
            // Unexplained rather than into "Removed".
            ledger.record(
                card,
                kind: .dispose,
                source: .correction,
                deltaQuantity: -card.quantity,
                occurredAt: occurredAt
            )
            context.delete(card)
        }
        try commit()
    }

    // MARK: - Removal
    //
    // Removal lives here rather than in the detail view. A view writing
    // straight to the context is how removals became invisible to history in
    // the first place; there is no second place that knows how to take a copy
    // out of the collection.

    /// Removes every copy of one position, returning what is needed to put it
    /// back.
    func remove(_ card: CollectedCard) throws -> RemovedCardSnapshot {
        let snapshot = RemovedCardSnapshot(card: card)
        let operationID = UUID()
        ledger.record(
            card,
            kind: .dispose,
            source: .correction,
            deltaQuantity: -card.quantity,
            operationID: operationID
        )
        context.delete(card)
        try commit()
        var stamped = snapshot
        stamped.operationID = operationID
        return stamped
    }

    /// Puts a removed position back, as the inverse of the disposal rather than
    /// as a new acquisition — undoing a removal is not buying the card again.
    func restore(_ snapshot: RemovedCardSnapshot) throws {
        snapshot.reinsert(in: context)
        if let operationID = snapshot.operationID {
            ledger.reverseOperation(operationID)
        } else if let restored = card(forKey: snapshot.collectionKey) {
            // A snapshot taken before the ledger existed. Recording the copies
            // as arriving now is the only honest option: there is no operation
            // to invert.
            ledger.record(
                restored,
                kind: .recordExisting,
                source: .correction,
                deltaQuantity: snapshot.quantity
            )
        }
        try commit()
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

    /// SwiftData commits the ownership mutation, ledger rows, activity, and
    /// price metadata in one store transaction. On any persistence failure the
    /// in-memory context is rolled back before the error reaches the caller, so
    /// a later unrelated save cannot accidentally commit a half-failed action.
    private func commit() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
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
    ) throws -> CollectionMutation? {
        guard current != corrected.variant else { return nil }

        let previousBaseKey = card.collectionKey(variant: current)
        let previousKey = previousCollectionKey
            ?? pokemonPrintRun.map { "\(previousBaseKey)@\($0.rawValue)" }
            ?? previousBaseKey
        // A stale scanner entry can outlive the collection row it was created
        // from (for example, the row may have been removed on another screen or
        // device). Do not manufacture the destination row and then record a
        // `-1` correction for a source that is no longer present: that leaves
        // the ledger permanently ahead of the collection and triggers the
        // reconciliation warning on the next portfolio pass.
        guard let previous = self.card(forKey: previousKey) else { return nil }

        let activityDescriptor = FetchDescriptor<CollectionActivity>(
            predicate: #Predicate { $0.collectionKey == previousKey }
        )
        // The scan being corrected is the newest acquisition for this row. Its
        // event moves with the copy; a correction is not a second acquisition.
        let activityToRetarget = try? context.fetch(activityDescriptor)
            .max(by: { $0.occurredAt < $1.occurredAt })

        // Read the outgoing side's price key before the row is decremented or
        // deleted — afterwards there is nothing left to ask.
        let previousPriceStorageKey = ledger.priceStorageKey(for: previous)
        if previous.quantity <= 1 {
            context.delete(previous)
        } else {
            previous.quantity -= 1
        }

        let mutation = try add(
            card,
            resolved: corrected,
            source: .correction,
            pokemonPrintRun: pokemonPrintRun,
            writesInventoryEvent: false,
            savesChanges: false
        )

        // Two legs, one operation: −1 of the wrong identity and +1 of the right
        // one. Later price movement then follows the corrected identity by
        // itself, and the pair is what makes undo a group inversion.
        let correctionOperationID = UUID()
        if let correctedRow = self.card(forKey: mutation.collectionKey) {
            ledger.recordCorrection(
                fromCollectionKey: previousKey,
                fromPriceStorageKey: previousPriceStorageKey
                    ?? ledger.priceStorageKey(for: correctedRow),
                toCard: correctedRow,
                operationID: correctionOperationID
            )
        }

        guard let activityToRetarget,
              let correctedCard = self.card(forKey: mutation.collectionKey) else {
            try commit()
            return CollectionMutation(
                collectionKey: mutation.collectionKey,
                activityID: mutation.activityID,
                didInsert: mutation.didInsert,
                operationID: correctionOperationID
            )
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
        try commit()

        return CollectionMutation(
            collectionKey: mutation.collectionKey,
            activityID: activityToRetarget.id,
            didInsert: mutation.didInsert,
            operationID: correctionOperationID
        )
    }
}

/// Everything needed to put a removed position back exactly as it was.
///
/// Lives beside `CollectionStore` because restoring is an ownership change, not
/// a view concern: it has to invert a ledger event, and only the store knows
/// how.
struct RemovedCardSnapshot: Identifiable {
    let id = UUID()
    /// The ledger operation that recorded the disposal, so restoring can invert
    /// exactly that rather than recording a fresh acquisition. `nil` only for a
    /// snapshot taken before the ledger existed.
    var operationID: UUID?
    let collectionKey: String
    let game: CardGame
    let providerID: String
    let catalogProviderID: String?
    let name: String
    let setName: String
    let setCode: String
    let cardNumber: String
    let rarity: String?
    let imageURL: String?
    let thumbnailURL: String?
    let userArtworkFilename: String?
    let pokemonPrintRunRaw: String?
    let tcgplayerURL: String?
    let catalogMetadataCheckedAt: Date?
    let catalogMetadataVersion: Int
    let quantity: Int
    let dateAdded: Date
    let variant: PhysicalVariant?
    let variantResolution: VariantResolution
    let identityResolution: IdentityResolution
    let setReleaseOrder: Int

    init(card: CollectedCard) {
        collectionKey = card.collectionKey
        game = card.cardGame
        providerID = card.providerID
        catalogProviderID = card.catalogProviderID
        name = card.name
        setName = card.setName
        setCode = card.setCode
        cardNumber = card.cardNumber
        rarity = card.rarity
        imageURL = card.imageURL
        thumbnailURL = card.thumbnailURL
        userArtworkFilename = card.userArtworkFilename
        pokemonPrintRunRaw = card.pokemonPrintRunRaw
        tcgplayerURL = card.tcgplayerURL
        catalogMetadataCheckedAt = card.catalogMetadataCheckedAt
        catalogMetadataVersion = card.catalogMetadataVersion
        quantity = card.quantity
        dateAdded = card.dateAdded
        variant = card.variant
        variantResolution = card.variantResolution ?? .catalogSilent
        identityResolution = card.identityResolution ?? .printedIdentifier
        setReleaseOrder = card.setReleaseOrder
    }

    /// Re-materialises the collection row. Ownership accounting is
    /// `CollectionStore.restore(_:)`'s job, not this type's.
    @MainActor
    func reinsert(in context: ModelContext) {
        let key = collectionKey
        var descriptor = FetchDescriptor<CollectedCard>(
            predicate: #Predicate { $0.collectionKey == key }
        )
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            existing.quantity += quantity
            existing.dateAdded = max(existing.dateAdded, dateAdded)
        } else {
            let restored = CollectedCard(
                collectionKey: collectionKey,
                game: game,
                providerID: providerID,
                name: name,
                setName: setName,
                setCode: setCode,
                cardNumber: cardNumber,
                rarity: rarity,
                imageURL: imageURL,
                thumbnailURL: thumbnailURL,
                variant: variant,
                variantResolution: variantResolution,
                identityResolution: identityResolution,
                setReleaseOrder: setReleaseOrder,
                quantity: quantity,
                dateAdded: dateAdded
            )
            restored.tcgplayerURL = tcgplayerURL
            restored.userArtworkFilename = userArtworkFilename
            restored.pokemonPrintRunRaw = pokemonPrintRunRaw
            restored.catalogProviderID = catalogProviderID
            restored.catalogMetadataCheckedAt = catalogMetadataCheckedAt
            restored.catalogMetadataVersion = catalogMetadataVersion
            context.insert(restored)
        }

    }
}
