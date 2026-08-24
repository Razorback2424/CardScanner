import Foundation

// MARK: - Tokens

/// One printed face of a token.
///
/// Identity is the collector number, never the name. Marvel Super Heroes prints
/// `Soldier` at both #3 and #4, and those two faces pair with different backs —
/// so a name-keyed model would conflate two different physical objects on its
/// first real set.
struct MagicTokenFace: Hashable, Sendable {
    /// The token set's code, e.g. `TMSH`.
    let setCode: String
    /// The printed collector number of this face, e.g. `6`.
    let number: String
    let name: String

    /// Leading zeros are presentation. `0006` and `6` are one face.
    var normalizedNumber: String {
        Int(number).map(String.init) ?? number.trimmingCharacters(in: .whitespaces)
    }
}

/// The physical cardboard object: two faces, printed back to back.
///
/// This exists because a face does not identify a product. `Clue #17` is the
/// front of more than one real token, and no amount of OCR on that side can
/// say which — the pairing is a packaging decision, not a property of the face.
///
/// The marketplace already models exactly this. JustTCG catalogues
/// `Merfolk // Doombot Double-Sided Token` at number `6 // 18`, keyed by the two
/// face numbers, so the index below is read from the provider rather than
/// hand-curated.
struct MagicPhysicalToken: Hashable, Sendable {
    /// The two face numbers as printed, in the provider's order.
    let frontNumber: String
    let backNumber: String
    /// `Merfolk // Doombot Double-Sided Token`.
    let name: String
    /// The provider's stable product id, which is what pricing uses.
    let marketProductID: String?
    let tcgplayerID: String?

    /// The provider's own key for this object, e.g. `6 // 18`.
    var pairedNumber: String { "\(frontNumber) // \(backNumber)" }

    /// Either face, normalized. Order is not identity: the user may present
    /// whichever side they like to the camera first.
    var faceNumbers: Set<String> {
        [Self.normalize(frontNumber), Self.normalize(backNumber)]
    }

    func contains(faceNumber: String) -> Bool {
        faceNumbers.contains(Self.normalize(faceNumber))
    }

    static func normalize(_ number: String) -> String {
        let trimmed = number.trimmingCharacters(in: .whitespaces)
        return Int(trimmed).map(String.init) ?? trimmed
    }
}

/// What one scanned face can be.
///
/// The whole point of this type is that `resolved` is not always reachable from
/// one side, and that this is a fact about the cards rather than a shortcoming
/// of the scanner. Asking for the reverse is gathering evidence, not asking the
/// user to know something.
enum TokenResolution: Equatable, Sendable {
    /// Exactly one physical product contains this face.
    case resolved(MagicPhysicalToken)
    /// Several products contain it. The reverse decides which.
    case needsReverse(candidates: [MagicPhysicalToken])
    /// No catalogued product contains this face. The face is still known — it
    /// is the physical object that is not.
    case unknownProduct
}

/// Face number to the physical products that contain it.
///
/// One-to-many by construction. A `[face: face]` dictionary would encode a
/// relationship that does not exist and would silently pick a back.
struct MagicTokenProductIndex: Sendable {
    private let productsByFace: [String: [MagicPhysicalToken]]

    init(products: [MagicPhysicalToken]) {
        var index: [String: [MagicPhysicalToken]] = [:]
        for product in products {
            for face in product.faceNumbers {
                index[face, default: []].append(product)
            }
        }
        self.productsByFace = index
    }

    func products(containing faceNumber: String) -> [MagicPhysicalToken] {
        productsByFace[MagicPhysicalToken.normalize(faceNumber)] ?? []
    }

    /// What one scanned face determines on its own.
    func resolve(faceNumber: String) -> TokenResolution {
        let candidates = products(containing: faceNumber)
        switch candidates.count {
        case 0: return .unknownProduct
        case 1: return .resolved(candidates[0])
        default: return .needsReverse(candidates: candidates)
        }
    }

    /// What two scanned faces determine together.
    ///
    /// The intersection of the two candidate sets. Order is irrelevant, which is
    /// what lets the user present either side first.
    func resolve(faceNumber: String, reverseNumber: String) -> TokenResolution {
        let first = Set(products(containing: faceNumber))
        let second = Set(products(containing: reverseNumber))
        let both = Array(first.intersection(second))
        switch both.count {
        case 0: return .unknownProduct
        case 1: return .resolved(both[0])
        // Two faces that still do not decide it means the same pair exists as
        // more than one product — a finish difference, typically. Refusing is
        // correct; the alternative is picking a foil at a nonfoil's price.
        default: return .needsReverse(candidates: both)
        }
    }
}

// MARK: - Art cards

/// Which printed numbering pool an art card belongs to.
///
/// Marvel Super Heroes prints three, and their fractions are the identity
/// signal on the reverse. Verified against the catalogue: 45 + 12 + 9 = 66,
/// which is exactly what Scryfall lists for the set.
///
///     02/45 -> collector number `2`     Collector Booster art cards
///     09/12 -> collector number `9b`    Scene Box art cards
///     01/09 -> collector number `1c`    Thanos mosaic art cards
///
/// The suffix is Scryfall's way of keeping three `#1`s apart. It is not a
/// variant marker, and it is not a stamp.
enum ArtCardPool: Int, CaseIterable, Hashable, Sendable {
    case collectorBooster = 45
    case sceneBox = 12
    case mosaic = 9

    /// The printed denominator, e.g. the `45` in `02/45`.
    var printedTotal: Int { rawValue }

    /// Scryfall's suffix for this pool.
    var collectorNumberSuffix: String {
        switch self {
        case .collectorBooster: return ""
        case .sceneBox: return "b"
        case .mosaic: return "c"
        }
    }

    /// Only the Collector Booster pool has gold-stamped counterparts. The nine
    /// mosaic cards are explicitly never stamped, so offering the choice there
    /// would invite the user to record something that does not exist.
    var supportsGoldStamp: Bool { self == .collectorBooster }

    static func pool(printedTotal: Int) -> ArtCardPool? {
        ArtCardPool(rawValue: printedTotal)
    }
}

/// How an art card is finished.
///
/// Not a `PhysicalVariant`. Scryfall's `finishes` describes foil versus nonfoil
/// and says nothing about stamping, so folding the stamp into that axis would
/// claim something the data does not support.
///
/// The two stamps are kept apart internally because they are different physical
/// things and the marketplace lists them as different products. The UI may still
/// present them as one "Gold stamped" choice until there is evidence collectors
/// distinguish them.
enum ArtCardTreatment: String, Codable, CaseIterable, Hashable, Sendable {
    case normal
    case goldSignature
    case goldPlaneswalker

    var label: String {
        switch self {
        case .normal: return "Regular"
        case .goldSignature: return "Gold-Stamped Signature"
        case .goldPlaneswalker: return "Gold-Stamped Planeswalker Symbol"
        }
    }

    /// What the picker shows. Both stamps read as one choice until the two are
    /// shown to matter separately.
    var pickerLabel: String {
        self == .normal ? "Regular" : "Gold stamped"
    }

    var isStamped: Bool { self != .normal }
}

/// One art card as the catalogue knows it.
///
/// The stamped identity is carried here rather than inferred. The camera's job
/// is only to confirm whether the card in hand has the stamp the catalogue says
/// exists — never to work out which kind of stamp a set might use.
struct MagicArtCard: Hashable, Sendable {
    let setCode: String
    /// Scryfall's collector number, e.g. `2`, `9b`, `1c`.
    let collectorNumber: String
    let name: String
    let pool: ArtCardPool
    /// Present only where the catalogue confirms a stamped counterpart, and
    /// carrying which stamp it is.
    let stampedTreatment: ArtCardTreatment?
    /// Separate market identities: the stamped card is its own product, not a
    /// printing of the regular one.
    let marketProductID: String?
    let stampedMarketProductID: String?

    var availableTreatments: [ArtCardTreatment] {
        guard let stampedTreatment, pool.supportsGoldStamp else { return [.normal] }
        return [.normal, stampedTreatment]
    }

    func marketProductID(for treatment: ArtCardTreatment) -> String? {
        treatment.isStamped ? stampedMarketProductID : marketProductID
    }
}

/// Reads the fraction printed on an art card's reverse.
///
/// The grammar is settled — the denominator names the pool — but *where* the
/// fraction sits on the card, how small it is and what surrounds it are not.
/// So this parses, and the camera does not yet call it.
enum ArtCardNumberParser {
    /// `02/45` -> (`2`, .collectorBooster) -> Scryfall `2`
    /// `09/12` -> (`9`, .sceneBox)         -> Scryfall `9b`
    /// `01/09` -> (`1`, .mosaic)           -> Scryfall `1c`
    static func parse(_ printed: String) -> (collectorNumber: String, pool: ArtCardPool)? {
        let parts = printed
            .trimmingCharacters(in: .whitespaces)
            .split(separator: "/", maxSplits: 1)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let index = Int(parts[0]),
              let total = Int(parts[1]),
              index >= 1,
              let pool = ArtCardPool.pool(printedTotal: total),
              index <= pool.printedTotal else {
            return nil
        }
        return ("\(index)\(pool.collectorNumberSuffix)", pool)
    }
}
