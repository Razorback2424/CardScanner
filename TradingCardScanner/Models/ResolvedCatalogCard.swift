import Foundation

/// Exact physical printing, constructed by a catalog adapter after resolution.
/// Canonical-card summaries and unresolved candidates never use this type.
struct ResolvedCatalogCard: Identifiable, Sendable {
    enum ValidationError: Error, Equatable {
        case invalidIdentity
        case mismatchedVariantEvidence
        case invalidVariants
    }

    let game: CardGame
    let providerID: String
    let canonicalCardID: String?
    let language: String
    let name: String
    let setName: String
    let setCode: String
    let cardNumber: String
    let displayCardNumber: String
    let identifier: String
    let rarity: String?
    let displayImageURL: URL?
    let thumbnailImageURL: URL?
    let storedImageURL: String?
    let setReleaseOrder: Int
    let variantEvidence: VariantEvidence
    private let collectionBaseKey: String
    let legacyIdentity: LegacyResolvedCard?

    var id: String { "\(game.rawValue):\(providerID)" }
    var physicalPrintingID: String { providerID }
    var setID: String { variantEvidence.setID }

    init(game: CardGame, physicalPrintingID: String, canonicalCardID: String,
         language: String, name: String, setName: String, setCode: String,
         cardNumber: String, printedIdentifier: String, rarity: String? = nil,
         displayImageURL: URL? = nil, thumbnailImageURL: URL? = nil,
         setReleaseOrder: Int = 0, variantEvidence: VariantEvidence) throws {
        guard !game.rawValue.isEmpty, !game.rawValue.contains(":"),
              !physicalPrintingID.isEmpty, !physicalPrintingID.contains("#"),
              !canonicalCardID.isEmpty, !language.isEmpty else {
            throw ValidationError.invalidIdentity
        }
        guard variantEvidence.game == game,
              variantEvidence.cardNumber == cardNumber else {
            throw ValidationError.mismatchedVariantEvidence
        }
        let variants = variantEvidence.catalogVariants
        guard Set(variants.map(\.id)).count == variants.count,
              variants.allSatisfy({ !$0.id.isEmpty && !$0.id.contains("#") }) else {
            throw ValidationError.invalidVariants
        }
        self.game = game
        self.providerID = physicalPrintingID
        self.canonicalCardID = canonicalCardID
        self.language = language
        self.name = name
        self.setName = setName
        self.setCode = setCode
        self.cardNumber = cardNumber
        self.displayCardNumber = cardNumber
        self.identifier = printedIdentifier
        self.rarity = rarity
        self.displayImageURL = displayImageURL
        self.thumbnailImageURL = thumbnailImageURL
        self.storedImageURL = displayImageURL?.absoluteString
        self.setReleaseOrder = setReleaseOrder
        self.variantEvidence = variantEvidence
        self.collectionBaseKey = "\(game.rawValue):\(physicalPrintingID)"
        self.legacyIdentity = nil
    }

    /// Retains the exact historical key/display/variant semantics during extraction.
    init(legacy: LegacyResolvedCard) {
        game = legacy.game
        providerID = legacy.providerID
        canonicalCardID = nil
        language = legacy.language
        name = legacy.name
        setName = legacy.setName
        setCode = legacy.setCode
        cardNumber = legacy.cardNumber
        displayCardNumber = legacy.displayCardNumber
        identifier = legacy.identifier
        rarity = legacy.rarity
        displayImageURL = legacy.displayImageURL
        thumbnailImageURL = legacy.thumbnailImageURL
        storedImageURL = legacy.storedImageURL
        setReleaseOrder = legacy.setReleaseOrder
        variantEvidence = legacy.variantEvidence
        collectionBaseKey = legacy.collectionKey(variant: nil)
        legacyIdentity = legacy
    }

    /// Finish qualification is stable regardless of how many variants a later
    /// catalog release discovers. Existing provider families retain their keys.
    func collectionKey(variant: PhysicalVariant?) -> String {
        MagicTreatmentKeyCodec.finishQualifiedCollectionKey(
            base: collectionBaseKey, game: game, finish: variant,
            treatments: magicTreatments(for: variant)
        )
    }

    var marketPrices: [CardMarketPrice] { CardPricing.publishedPrices(for: self) }
    var providerPurchaseURL: String? { legacyIdentity?.providerPurchaseURL }
    var updatesProviderPurchaseURL: Bool { legacyIdentity?.updatesProviderPurchaseURL ?? true }
    var catalogMetadataThumbnailURL: String? {
        legacyIdentity?.catalogMetadataThumbnailURL ?? thumbnailImageURL?.absoluteString
    }
    var magicTreatmentEvidence: MagicTreatmentEvidence {
        legacyIdentity?.magicTreatmentEvidence ?? MagicTreatmentEvidence(treatments: [])
    }
    var magicContentKind: MagicContentKind { legacyIdentity?.magicContentKind ?? .regular }
    var magicTreatmentDisplayLabel: String? { legacyIdentity?.magicTreatmentDisplayLabel }
    var magicTreatmentDiagnostics: [MagicTreatmentDiagnostic] { legacyIdentity?.magicTreatmentDiagnostics ?? [] }
    var unambiguousMagicTreatments: [MagicTreatment] { legacyIdentity?.unambiguousMagicTreatments ?? [] }
    func magicTreatments(for finish: PhysicalVariant?) -> [MagicTreatment] {
        magicTreatmentEvidence.applicableTreatments(for: finish)
    }
    func magicTreatmentQualifiers(for finish: PhysicalVariant?) -> [String: String] {
        legacyIdentity?.magicTreatmentQualifiers(for: finish) ?? [:]
    }
    func finishAndTreatmentDisplayLabel(for finish: PhysicalVariant?) -> String {
        legacyIdentity?.finishAndTreatmentDisplayLabel(for: finish) ?? finish?.label ?? "Unknown finish"
    }
}

/// Source compatibility while consumers migrate to the neutral model name.
typealias IdentifiedCard = ResolvedCatalogCard
