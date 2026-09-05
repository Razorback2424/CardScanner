import Foundation
import SwiftData

/// One owned physical variant of one printing.
///
/// The collection does not contain cards, it contains *entries*: a Master Ball
/// copy and a reverse holo copy of PRE 074/131 share a printing identity but are
/// not interchangeable. They have different prices, the user filters them
/// separately, and their quantities are independent, so they are separate rows.
///
/// Price is deliberately not stored here. It lives in `PriceRecord`, keyed by
/// printing plus variant, so eight owned copies are one price to refresh and a
/// price can go stale without the ownership record changing at all.
///
/// The persisted entity keeps its original name so existing local collections
/// migrate without a versioned-schema rewrite.
@Model
final class CollectedCard {
    /// One row per physical object. For a printing with more than one possible
    /// variant this is `providerID#variantID`; when no variant is known it stays
    /// the bare provider id, which is also the key Pokémon-only collections were
    /// built with, so existing rows keep incrementing rather than forking.
    // CloudKit does not support unique constraints, so uniqueness for this key
    // is enforced in code (CollectionStore fetches by `collectionKey` before
    // every insert) rather than by the store. See `CollectionStore.card(forKey:)`.
    @Attribute(originalName: "tcgdexID") var collectionKey: String = ""
    var game: String = "pokemon"
    var providerID: String = ""
    var name: String = ""
    var setName: String = ""
    var setCode: String = ""
    var cardNumber: String = ""
    var rarity: String?
    /// Pokémon stores its TCGdex image base URL; Magic stores its direct
    /// Scryfall normal-image URL. game selects the appropriate representation.
    @Attribute(originalName: "imageBaseURL") var imageURL: String?
    var thumbnailURL: String?
    /// Legacy bridge for stores written before user artwork became device-local.
    /// Launch migration copies it into `LocalArtworkOverride` and clears this
    /// synced field; new artwork writes never publish a local filename.
    var userArtworkFilename: String?
    var quantity: Int = 1
    var dateAdded: Date = Date.now

    /// Which physical variant this row holds. `nil` means the catalog published
    /// none — recorded as unknown rather than filled in with something plausible.
    var variantID: String?
    var variantLabel: String?
    /// Magic treatment ids are persisted as strings so a newer catalog can
    /// synchronize a real treatment through CloudKit without requiring an older
    /// build to know its enum case. `[]` is the lightweight-migration default.
    var magicTreatmentIDsRaw: [String] = []
    /// Qualifiers are stored as JSON because the CloudKit-backed model already
    /// treats strings as the forward-compatible wire format. The map is keyed
    /// by normalized treatment id and keeps values such as a Neon Ink color.
    var magicTreatmentQualifiersJSON: String?
    /// The last exact-printing treatment migration this row has passed. A
    /// per-row watermark lets new CSV/import rows be picked up after launch,
    /// while a failed provider lookup remains retryable without a global
    /// UserDefaults claim that could miss a row arriving from another device.
    var magicTreatmentMigrationVersion: Int = 0
    /// The printed face's semantic kind is independent from how it is owned.
    /// Existing rows were created before this axis was persisted and therefore
    /// default to ordinary cards.
    var magicContentKindRaw: String = MagicContentKind.regular.rawValue
    /// WotC print run is independent of finish: a card can be both 1st Edition
    /// and Holo. Kept separate so pricing and master-set routing never have to
    /// overload one mutually exclusive variant field with two physical facts.
    var pokemonPrintRunRaw: String?

    /// Provenance, stored as raw strings so a future build can add resolutions
    /// without a schema migration.
    ///
    /// Keeping *why* alongside *what* is what makes the accuracy policy hold up
    /// over time: if a set rule is later found to be incomplete, every row that
    /// leaned on that rule can be found and reassessed without disturbing the
    /// ones a person confirmed by hand.
    var variantResolutionRaw: String?
    var identityResolutionRaw: String = IdentityResolution.printedIdentifier.rawValue

    /// Position of this card's set in release order. Collectors group by set the
    /// way sets were released, not alphabetically. Compared only within a game.
    var setReleaseOrder: Int = 0

    /// Imported rows begin without provider artwork. Recording the last catalog
    /// metadata attempt prevents a failed match from being retried on every tap.
    var catalogMetadataCheckedAt: Date?
    /// Lets improved matching rules retry previously unresolved imports once,
    /// without turning every collection launch into another network pass.
    var catalogMetadataVersion: Int = 0
    /// The real remote identity resolved after a fast local CSV import. The
    /// synthetic provider ID remains the stable ownership/price storage key.
    var catalogProviderID: String?
    /// A provider-supplied destination for this exact printing. Never populated
    /// from a name-based search or a guessed marketplace slug.
    var tcgplayerURL: String?
    /// TCGplayer's stable product identifier for this printing, as published by
    /// a provider. Kept locally once resolved, like the rest of the catalog
    /// metadata, so opening the marketplace never depends on a live request.
    var tcgplayerProductID: String?
    /// TCGplayer's SKU — product *plus* language, printing and condition.
    ///
    /// Persisted because it is the exact object a listing hangs off, but
    /// deliberately not used to build the marketplace link: the collection does
    /// not record the condition of the copy owned, so linking to a
    /// condition-specific SKU would claim knowledge the app does not have.
    var tcgplayerSKUID: String?

    // MARK: - Collection item kind
    //
    // Everything below is defaulted or optional so that every row written before
    // these existed migrates as a raw card without a migration pass. The type is
    // still called `CollectedCard` for the same reason: renaming it would orphan
    // the existing local store.

    var itemKindRaw: String = CollectionItemKind.rawCard.rawValue

    /// The vendor's stable card UUID, resolved once and then reused forever.
    /// Holding it is what turns every later refresh into a keyed batch lookup
    /// instead of a search.
    var justTCGCardID: String?
    /// The vendor's stable *variant* UUID — the exact printing and finish. This
    /// is the identifier batches are built from.
    var justTCGVariantID: String?
    /// Which API version resolved the identity. Graded slabs come from v2 and
    /// raw/sealed from v1, and the two are not interchangeable until the
    /// contract slice proves otherwise.
    var justTCGAPIVersion: String?

    var gradingCompanyRaw: String?
    /// Kept as text: `9.5` is not an integer and `Authentic` is not a number.
    var gradeRaw: String?
    var gradeLabel: String?
    /// `OC`, `ST`, `MK`. A qualifier makes a different object, never a footnote.
    var gradingQualifier: String?
    /// When present the row is one specific slab, so its quantity is one.
    var certificationNumber: String?

    var marketRegionRaw: String?

    var itemKind: CollectionItemKind {
        CollectionItemKind(rawValue: itemKindRaw) ?? .rawCard
    }

    var gradingCompany: GradingCompany? {
        gradingCompanyRaw.flatMap(GradingCompany.init(rawValue:))
    }

    var cardGrade: CardGrade? {
        guard itemKind == .gradedCard else { return nil }
        return CardGrade(value: gradeRaw, label: gradeLabel, qualifier: gradingQualifier)
    }

    /// Decodes the forward-compatible treatment storage without making an
    /// unknown future id fatal to the collection row.
    var magicTreatments: [MagicTreatment] {
        magicTreatmentIDsRaw.compactMap { MagicTreatment(id: $0) }
    }

    var magicTreatmentQualifiers: [String: String] {
        get { MagicTreatmentKeyCodec.decodeQualifiers(magicTreatmentQualifiersJSON) }
        set { magicTreatmentQualifiersJSON = MagicTreatmentKeyCodec.encodeQualifiers(newValue) }
    }

    var magicTreatmentEvidence: MagicTreatmentEvidence {
        MagicTreatmentEvidence(
            treatments: magicTreatments,
            qualifiers: magicTreatmentQualifiers
        )
    }

    var magicContentKind: MagicContentKind {
        MagicContentKind(rawValue: magicContentKindRaw) ?? .regular
    }

    /// The treatment label shown for this owned object. Raw rows have a
    /// selected finish, so they use the same finish-aware relationship as
    /// collection key construction; graded and sealed rows use the persisted
    /// exact-printing treatment set because their vendor identity has no raw
    /// finish selector.
    var displayedMagicTreatments: [MagicTreatment] {
        switch itemKind {
        case .rawCard:
            return displayedMagicTreatmentEvidence.treatments
        case .gradedCard, .sealedProduct:
            return magicTreatmentEvidence.treatments
        }
    }

    var displayedMagicTreatmentEvidence: MagicTreatmentEvidence {
        let treatments: [MagicTreatment]
        switch itemKind {
        case .rawCard:
            treatments = magicTreatmentIDs(for: variant).compactMap(MagicTreatment.init(id:))
        case .gradedCard, .sealedProduct:
            treatments = magicTreatments
        }
        let qualifiers = Dictionary(uniqueKeysWithValues: treatments.compactMap { treatment in
            magicTreatmentEvidence.qualifier(for: treatment).map { (treatment.id, $0) }
        })
        return MagicTreatmentEvidence(treatments: treatments, qualifiers: qualifiers)
    }

    /// Re-applies the shared finish relationship when a history correction
    /// changes the selected finish but has no live provider response available.
    func magicTreatmentIDs(for finish: PhysicalVariant?) -> [String] {
        guard cardGame == .magic else { return [] }
        // A raw row with no selected finish must retain the legacy bare
        // identity. This also prevents an unclassified treatment from being
        // smuggled into a price key when the finish is still unknown.
        guard finish != nil || itemKind != .rawCard else { return [] }
        return MagicTreatmentKeyCodec.storedIDs(
            from: magicTreatmentEvidence.applicableTreatments(for: finish)
        )
    }

    /// Treatment ids that are safe to use for the price identity already
    /// stored on this row. Raw cards need a selected finish; graded and sealed
    /// rows have their own namespaces and may carry a reviewed treatment even
    /// though they do not expose a raw-finish selector.
    var priceTreatmentIDs: [String] {
        guard cardGame == .magic else { return [] }
        if itemKind == .rawCard {
            return magicTreatmentIDs(for: variant)
        }
        return MagicTreatmentKeyCodec.storedIDs(from: magicTreatments)
    }

    /// What a collection tile calls this row.
    var itemKindLabel: String {
        switch itemKind {
        case .rawCard:
            return variantLabel ?? PhysicalVariant.normal.label
        case .gradedCard:
            guard let gradingCompany, let cardGrade else { return "Graded" }
            return cardGrade.display(company: gradingCompany)
        case .sealedProduct:
            return "Sealed"
        }
    }

    /// A slab identified by certificate is a single object and cannot stack.
    var allowsQuantityAggregation: Bool {
        certificationNumber == nil
    }

    init(
        collectionKey: String,
        game: CardGame,
        providerID: String,
        name: String,
        setName: String,
        setCode: String,
        cardNumber: String,
        rarity: String?,
        imageURL: String?,
        thumbnailURL: String?,
        variant: PhysicalVariant?,
        variantResolution: VariantResolution,
        identityResolution: IdentityResolution = .printedIdentifier,
        setReleaseOrder: Int = 0,
        quantity: Int = 1,
        dateAdded: Date = .now,
        magicTreatments: [MagicTreatment] = [],
        magicTreatmentQualifiers: [String: String] = [:],
        magicContentKind: MagicContentKind = .regular
    ) {
        self.collectionKey = collectionKey
        self.game = game.rawValue
        self.providerID = providerID
        self.name = name
        self.setName = setName
        self.setCode = setCode
        self.cardNumber = cardNumber
        self.rarity = rarity
        self.imageURL = imageURL
        self.thumbnailURL = thumbnailURL
        self.variantID = variant?.id
        self.variantLabel = variant?.label
        self.magicTreatmentIDsRaw = MagicTreatmentKeyCodec.storedIDs(from: magicTreatments)
        self.magicTreatmentQualifiersJSON = MagicTreatmentKeyCodec.encodeQualifiers(
            magicTreatmentQualifiers
        )
        self.magicContentKindRaw = magicContentKind.rawValue
        self.variantResolutionRaw = variantResolution.rawValue
        self.identityResolutionRaw = identityResolution.rawValue
        self.setReleaseOrder = setReleaseOrder
        self.quantity = quantity
        self.dateAdded = dateAdded
    }

    /// Keeps the import identity and collection key stable while filling in
    /// provider metadata from either background normalization or price refresh.
    /// The catalog retry watermark is recorded by CollectionCatalogNormalizer,
    /// which is its single owner.
    func applyCatalogMetadata(from card: IdentifiedCard) {
        catalogProviderID = card.providerID
        setCode = card.setCode
        rarity = card.rarity
        setReleaseOrder = card.setReleaseOrder
        switch card {
        case let .pokemon(pokemon, _):
            imageURL = pokemon.image
            thumbnailURL = pokemon.image.map { $0 + "/low.png" }
        case let .magic(magic):
            imageURL = card.displayImageURL?.absoluteString
            thumbnailURL = card.thumbnailImageURL?.absoluteString
            tcgplayerURL = magic.purchaseURIs?.tcgplayer?.absoluteString
        }
    }

    func applyCatalogMetadata(_ metadata: ImportedCatalogMetadata) {
        catalogProviderID = metadata.providerID
        setCode = metadata.setCode
        rarity = metadata.rarity ?? rarity
        setReleaseOrder = metadata.setReleaseOrder
        imageURL = metadata.imageURL
        thumbnailURL = metadata.thumbnailURL
        tcgplayerURL = metadata.tcgplayerURL
        justTCGCardID = metadata.justTCGCardID ?? justTCGCardID
        justTCGVariantID = metadata.justTCGVariantID ?? justTCGVariantID
        justTCGAPIVersion = metadata.justTCGAPIVersion ?? justTCGAPIVersion
    }

    convenience init(
        card: IdentifiedCard,
        resolved: ResolvedVariant,
        identityResolution: IdentityResolution = .printedIdentifier,
        setReleaseOrder: Int? = nil
    ) {
        self.init(
            collectionKey: card.collectionKey(variant: resolved.variant),
            game: card.game,
            providerID: card.providerID,
            name: card.name,
            setName: card.setName,
            setCode: card.setCode,
            cardNumber: card.cardNumber,
            rarity: card.rarity,
            imageURL: {
                switch card {
                case let .pokemon(pokemon, _): return pokemon.image
                case .magic: return card.displayImageURL?.absoluteString
                }
            }(),
            thumbnailURL: card.thumbnailImageURL?.absoluteString,
            variant: resolved.variant,
            variantResolution: resolved.resolution,
            identityResolution: identityResolution,
            setReleaseOrder: setReleaseOrder ?? card.setReleaseOrder,
            quantity: 1
        )
        magicTreatmentIDsRaw = MagicTreatmentKeyCodec.storedIDs(
            from: card.magicTreatments(for: resolved.variant)
        )
        magicTreatmentQualifiers = card.magicTreatmentQualifiers(for: resolved.variant)
        magicContentKindRaw = card.magicContentKind.rawValue
        if case let .magic(magic) = card {
            tcgplayerURL = magic.purchaseURIs?.tcgplayer?.absoluteString
        }
    }

    var cardGame: CardGame {
        CardGame(rawValue: game) ?? .pokemon
    }

    // MARK: - Namespaced identities
    //
    // Raw rows keep the key they have always had — unprefixed — so no existing
    // ownership or price record moves. Graded and sealed rows get their own
    // namespace instead, which is what stops a PSA 10 from ever sharing a row,
    // a quantity or a price with the raw copy of the same printing.

    static func gradedCollectionKey(
        game: CardGame,
        underlyingPrintingID: String,
        variantUUID: String,
        magicTreatments: [MagicTreatment] = []
    ) -> String {
        let base = "graded:\(game.rawValue):\(underlyingPrintingID):\(variantUUID)"
        guard game == .magic else { return base }
        return MagicTreatmentKeyCodec.appendCollectionSuffix(
            to: base,
            treatments: magicTreatments
        )
    }

    static func sealedCollectionKey(
        game: CardGame,
        productUUID: String,
        variantUUID: String,
        magicTreatments: [MagicTreatment] = []
    ) -> String {
        let base = "sealed:\(game.rawValue):\(productUUID):\(variantUUID)"
        guard game == .magic else { return base }
        return MagicTreatmentKeyCodec.appendCollectionSuffix(
            to: base,
            treatments: magicTreatments
        )
    }

    /// A slab identified by certificate never merges with another slab, even an
    /// identical grade from the same grader — they are two physical objects.
    static func gradedCollectionKey(
        game: CardGame,
        underlyingPrintingID: String,
        variantUUID: String,
        certificationNumber: String?,
        magicTreatments: [MagicTreatment] = []
    ) -> String {
        var base = "graded:\(game.rawValue):\(underlyingPrintingID):\(variantUUID)"
        if let certificationNumber, !certificationNumber.isEmpty {
            base += ":cert:\(certificationNumber)"
        }
        guard game == .magic else { return base }
        return MagicTreatmentKeyCodec.appendCollectionSuffix(
            to: base,
            treatments: magicTreatments
        )
    }

    /// The `PriceRecord` this entry reads its price from. Every owned copy of the
    /// same printing and variant shares one.
    var priceStorageID: String {
        // Vendor-native products are already identified at the exact priceable
        // object level. In particular, a certificate distinguishes two owned
        // slabs but does not distinguish their market price, so it must never be
        // part of the price key or cause a second refresh request.
        if itemKind != .rawCard, let marketVariantID = justTCGVariantID {
            let version = justTCGAPIVersion ?? (itemKind == .gradedCard ? "v2" : "v1")
            return "justtcg:\(version):\(marketVariantID)"
        }
        return pokemonPrintRun.map { "\(providerID)@\($0.rawValue)" } ?? providerID
    }

    var priceKey: String {
        PriceRecord.key(
            game: cardGame,
            printingID: priceStorageID,
            variantID: variantID,
            treatmentIDs: priceTreatmentIDs
        )
    }

    /// Keys used by builds before print run and vendor-native price identities
    /// were separated from collection-row identity. Reading through these keeps
    /// already-working stored prices visible until a fresh observation is saved
    /// under the canonical key.
    var legacyPriceKeys: [String] {
        // A generic finish price is not evidence for a treatment-bearing
        // printing. Do not reuse the treatment-free key: the correct state is a
        // cold, first-party treatment price rather than a wrong inherited one.
        guard priceTreatmentIDs.isEmpty else { return [] }
        var keys: [String] = []
        if itemKind != .rawCard, justTCGVariantID != nil {
            keys.append(PriceRecord.key(game: cardGame, printingID: providerID, variantID: variantID))
        }
        if itemKind == .rawCard,
           pokemonPrintRunRaw == nil,
           variantID == PhysicalVariant.firstEdition.id {
            keys.append(
                PriceRecord.key(
                    game: cardGame,
                    printingID: providerID,
                    variantID: PhysicalVariant.firstEdition.id
                )
            )
        }
        return keys.filter { $0 != priceKey }
    }

    var priceLookupKeys: [String] { [priceKey] + legacyPriceKeys }

    var variant: PhysicalVariant? {
        guard let variantID else { return nil }
        return PhysicalVariant(id: variantID, label: variantLabel ?? variantID.capitalized)
    }

    var pokemonPrintRun: PokemonPrintRun? {
        if let pokemonPrintRunRaw, let run = PokemonPrintRun(rawValue: pokemonPrintRunRaw) {
            return run
        }
        // Existing stores represented this as a finish. Read it as provenance
        // during migration, while all new writes use the independent field.
        return variantID == PhysicalVariant.firstEdition.id ? .firstEdition : nil
    }

    var variantResolution: VariantResolution? {
        variantResolutionRaw.flatMap(VariantResolution.init(rawValue:))
    }

    var identityResolution: IdentityResolution? {
        IdentityResolution(rawValue: identityResolutionRaw)
    }

    var highImageURL: URL? {
        guard let imageURL else { return nil }
        if game == CardGame.pokemon.rawValue, !imageURLIsDirect {
            return URL(string: imageURL + "/high.png")
        }
        return URL(string: imageURL)
    }

    var lowImageURL: URL? {
        if let thumbnailURL {
            return URL(string: thumbnailURL)
        }
        guard let imageURL else { return nil }
        if game == CardGame.pokemon.rawValue, !imageURLIsDirect {
            return URL(string: imageURL + "/low.png")
        }
        return URL(string: imageURL)
    }

    private var imageURLIsDirect: Bool {
        guard let imageURL else { return false }
        let path = URL(string: imageURL)?.path.lowercased() ?? ""
        return path.hasSuffix(".jpg") || path.hasSuffix(".jpeg")
            || path.hasSuffix(".png") || path.hasSuffix(".webp")
    }
}

/// Device-local ownership for user-selected artwork.
///
/// The image bytes live in this device's Application Support directory, so the
/// filename that points at them must not be a CloudKit field on `CollectedCard`.
/// The collection key is shared only as a stable local lookup key; two devices
/// can therefore choose different photos for the same physical position.
@Model
final class LocalArtworkOverride {
    var collectionKey: String = ""
    var filename: String = ""
    var updatedAt: Date = Date.now

    init(collectionKey: String, filename: String, updatedAt: Date = Date.now) {
        self.collectionKey = collectionKey
        self.filename = filename
        self.updatedAt = updatedAt
    }
}
