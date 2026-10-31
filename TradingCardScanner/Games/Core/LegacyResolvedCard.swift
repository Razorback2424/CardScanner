import Foundation

/// Transitional provider-payload projection. New games construct ResolvedCatalogCard directly.
enum LegacyResolvedCard: Identifiable, Sendable {
    case pokemon(TCGdexCard, setCode: String)
    case magic(ScryfallCard)

    var language: String {
        switch self {
        case let .pokemon(card, _): return CatalogIdentityNormalization.locale(forCatalogCardID: card.id).rawValue
        case let .magic(card): return card.language
        }
    }

    var storedImageURL: String? {
        switch self {
        case let .pokemon(card, _): return card.image
        case .magic: return displayImageURL?.absoluteString
        }
    }

    var providerPurchaseURL: String? {
        guard case let .magic(card) = self else { return nil }
        return card.purchaseURIs?.tcgplayer?.absoluteString
    }

    var updatesProviderPurchaseURL: Bool {
        if case .magic = self { return true }
        return false
    }

    var catalogMetadataThumbnailURL: String? {
        switch self {
        case let .pokemon(card, _): return card.image.map { $0 + "/low.png" }
        case .magic: return thumbnailImageURL?.absoluteString
        }
    }

    var id: String {
        switch self {
        case let .pokemon(card, _): return "pokemon:\(card.id)"
        case let .magic(card): return "magic:\(card.id)"
        }
    }

    var game: CardGame {
        switch self {
        case .pokemon: return .pokemon
        case .magic: return .magic
        }
    }

    var providerID: String {
        switch self {
        case let .pokemon(card, _): return card.id
        case let .magic(card): return card.id
        }
    }

    /// The row a scan mutates.
    ///
    /// A Master Ball copy and a plain reverse copy of one printing are different
    /// physical objects and must not share a quantity. The legacy bare-provider
    /// key is preserved when no variant is known, so a collection built before
    /// finish resolution keeps incrementing the row it already has.
    func collectionKey(variant: PhysicalVariant?) -> String {
        switch self {
        case let .pokemon(card, _):
            return MagicTreatmentKeyCodec.finishQualifiedCollectionKey(
                base: card.id,
                game: .pokemon,
                finish: variant
            )
        case let .magic(card):
            let base = "magic:\(card.id)"
            return MagicTreatmentKeyCodec.finishQualifiedCollectionKey(
                base: base,
                game: .magic,
                finish: variant,
                treatments: card.magicTreatmentEvidence.applicableTreatments(for: variant)
            )
        }
    }

    var name: String {
        switch self {
        case let .pokemon(card, _): return card.name
        case let .magic(card): return card.name
        }
    }

    var setName: String {
        switch self {
        case let .pokemon(card, _): return card.set.name
        case let .magic(card): return card.setName
        }
    }

    var setCode: String {
        switch self {
        case let .pokemon(_, setCode): return setCode
        case let .magic(card): return card.setCode.uppercased()
        }
    }

    var cardNumber: String {
        switch self {
        case let .pokemon(card, _): return card.localId
        case let .magic(card): return card.collectorNumber
        }
    }

    var displayCardNumber: String {
        switch self {
        case let .pokemon(card, _):
            return "\(card.localId)/\(card.set.cardCount.official)"
        case let .magic(card):
            return card.collectorNumber
        }
    }

    var identifier: String {
        switch self {
        case let .pokemon(card, _):
            return "\(setCode) \(card.localId)/\(card.set.cardCount.official)"
        case let .magic(card):
            return "\(card.setCode.uppercased()) \(card.collectorNumber)"
        }
    }

    var rarity: String? {
        switch self {
        case let .pokemon(card, _): return card.rarity
        case let .magic(card): return card.rarity
        }
    }

    var displayImageURL: URL? {
        switch self {
        case let .pokemon(card, _): return card.highImageURL
        case let .magic(card): return card.displayImageURL
        }
    }

    var thumbnailImageURL: URL? {
        switch self {
        case let .pokemon(card, _):
            guard let image = card.image else { return nil }
            guard let url = URL(string: image) else { return nil }
            return url.pathExtension.isEmpty ? URL(string: image + "/low.png") : url
        case let .magic(card): return card.thumbnailImageURL
        }
    }

    var marketPrices: [CardMarketPrice] {
        CardPricing.publishedPrices(for: ResolvedCatalogCard(legacy: self))
    }

    /// Release ordering for "Set + Card Number". Pokémon uses the position in the
    /// local set table; Magic uses the printing's release date. Both grow with
    /// time, and sorting always groups by game first so the two scales are never
    /// compared against each other.
    var setReleaseOrder: Int {
        switch self {
        case let .pokemon(card, _):
            return PokemonCatalogRegistry.bundledSeed.releaseOrder(forProviderSetID: card.set.id)
                ?? 0
        case let .magic(card):
            guard let date = card.releaseDate else { return 0 }
            return Int(date.timeIntervalSince1970 / 86_400)
        }
    }

    /// The only thing the variant resolver is ever shown.
    var variantEvidence: VariantEvidence {
        switch self {
        case let .pokemon(card, _):
            return VariantEvidence(
                game: .pokemon,
                setID: card.set.id,
                cardNumber: card.localId,
                catalogVariants: card.catalogVariants
            )
        case let .magic(card):
            return VariantEvidence(
                game: .magic,
                setID: card.setCode.lowercased(),
                cardNumber: card.collectorNumber,
                catalogVariants: card.catalogVariants,
                magicTreatments: card.magicTreatmentEvidence.treatments
            )
        }
    }

    /// The treatment axis is intentionally absent for Pokémon. Returning an
    /// empty value keeps callers from accidentally treating a Pokémon finish as
    /// a Magic treatment while giving future identity surfaces one neutral API.
    var magicTreatmentEvidence: MagicTreatmentEvidence {
        switch self {
        case .pokemon: return MagicTreatmentEvidence(treatments: [])
        case let .magic(card): return card.magicTreatmentEvidence
        }
    }

    /// The treatment axis shared by display and identity. Known treatments are
    /// filtered against the selected finish; an unknown treatment remains
    /// unclassified evidence rather than being guessed into a finish.
    func magicTreatments(for finish: PhysicalVariant?) -> [MagicTreatment] {
        magicTreatmentEvidence.applicableTreatments(for: finish)
    }

    /// The semantic kind of the exact printed face. Tokens and art-series
    /// cards are separate from ordinary cards even when their visible number
    /// overlaps one in the parent set; the provider layout is the authoritative
    /// value after the content-aware lookup has resolved.
    var magicContentKind: MagicContentKind {
        guard case let .magic(card) = self else { return .regular }
        switch card.layout?.lowercased() {
        case "token", "double_faced_token", "emblem": return .token
        case "art_series": return .artCard
        default: return .regular
        }
    }

    /// Qualifiers follow the same finish-aware treatment relationship as the
    /// treatment ids. A dual-finish printing therefore carries its qualifier
    /// only on the foil row that actually has the treatment.
    func magicTreatmentQualifiers(for finish: PhysicalVariant?) -> [String: String] {
        let evidence = magicTreatmentEvidence
        let applicable = evidence.applicableTreatments(for: finish)
        return Dictionary(uniqueKeysWithValues: applicable.compactMap { treatment in
            evidence.qualifier(for: treatment).map { (treatment.id, $0) }
        })
    }

    /// A graded entry has no raw finish selector in the vendor's graded
    /// response. It may still carry a treatment when the exact printing has one
    /// and publishes exactly one finish; dual-finish printings remain
    /// intentionally unqualified until a finish-bearing identity exists.
    var unambiguousMagicTreatments: [MagicTreatment] {
        guard case let .magic(card) = self,
              card.catalogVariants.count == 1,
              let finish = card.catalogVariants.first else {
            return []
        }
        return card.magicTreatmentEvidence.applicableTreatments(for: finish)
    }

    func finishAndTreatmentDisplayLabel(for finish: PhysicalVariant?) -> String {
        let finishLabel = finish?.label ?? "Unknown finish"
        guard case let .magic(card) = self else {
            return finishLabel
        }
        if let finish {
            return card.magicTreatmentEvidence.displayLabel(with: finish) ?? finishLabel
        }
        guard let treatmentLabel = card.magicTreatmentEvidence.displayLabel else {
            return finishLabel
        }
        return "\(finishLabel) · \(treatmentLabel)"
    }

    var magicTreatmentDisplayLabel: String? {
        switch self {
        case .pokemon: return nil
        case let .magic(card): return card.magicTreatmentDisplayLabel
        }
    }

    var magicTreatmentDiagnostics: [MagicTreatmentDiagnostic] {
        switch self {
        case .pokemon: return []
        case let .magic(card): return card.magicTreatmentDiagnostics
        }
    }
}
