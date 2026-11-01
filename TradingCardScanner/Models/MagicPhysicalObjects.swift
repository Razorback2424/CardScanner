import Foundation

// MARK: - Tokens
//
// A token *face* is what one side of the cardboard says. A physical token is
// the cardboard: one face, or two printed back to back. The scanner reads a
// face; the collection owns cardboard. Everything below exists because those
// are not the same thing.
//
// The design and its evidence live in `docs/plans/magic-token-scanning.md`.

/// One printed token face, identified the way the card identifies itself: the
/// token set its footer routes to and the collector number printed on it.
///
/// The set is part of identity. TCGplayer's Ravnica Allegiance Guild Kit
/// listing prints `Ooze // Frog Lizard` at `9 // 6` and `Dragon // Goblin` at
/// `5 // 6`: two different faces carry `6`. A number-only key would say those
/// two cards share a side.
///
/// The name is not identity either. Marvel Super Heroes prints `Soldier` at
/// both #3 and #4, and those faces pair with different backs.
struct MagicTokenFaceID: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// The token set's code, uppercased, e.g. `TMSH`.
    let setCode: String
    /// The printed collector number, normalized so `0017` and `17` are one face.
    let number: String

    init(setCode: String, number: String) {
        self.setCode = setCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.number = Self.normalize(number)
    }

    var description: String { "\(setCode) \(number)" }

    /// Leading zeros are presentation and case is OCR noise. A letter prefix
    /// (`H13`, LTR's helper card) and a suffix are kept: they are identity.
    static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let letters = trimmed.prefix(while: { !$0.isNumber })
        let rest = trimmed.dropFirst(letters.count)
        let digits = rest.prefix(while: { $0.isASCII && $0.isNumber })
        guard !digits.isEmpty, let value = Int(digits) else { return trimmed }
        return String(letters) + String(value) + String(rest.dropFirst(digits.count))
    }

    private var numericStem: Int? {
        Int(number.drop(while: { !$0.isNumber }).prefix(while: { $0.isASCII && $0.isNumber }))
    }

    /// Set, then binder order. A tuple keeps this a strict total order even
    /// when a number has no numeric stem at all.
    private var sortKey: (String, Int, Int, String) {
        (setCode, numericStem == nil ? 1 : 0, numericStem ?? 0, number)
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.sortKey < rhs.sortKey }
}

/// One printed face: identity plus the name printed on it.
struct MagicTokenFace: Hashable, Sendable {
    let id: MagicTokenFaceID
    let name: String

    init(id: MagicTokenFaceID, name: String) {
        self.id = id
        self.name = name
    }

    init(setCode: String, number: String, name: String) {
        self.init(id: MagicTokenFaceID(setCode: setCode, number: number), name: name)
    }
}

/// The order-independent identity of one physical token card.
///
/// One face for a single-sided token, two for a double-sided one. Sorted, so
/// `Merfolk // Doombot` and `Doombot // Merfolk` are one object — the person
/// may show either side first. A double-sided card with the same face on both
/// sides (Amonkhet's `Punchcard // Punchcard`) keeps both entries, so it can
/// never collide with a single-sided printing of that face.
///
/// Provider product ids are deliberately not part of this. The same cardboard
/// can be listed more than once (foil and nonfoil listings, or one token sold
/// in two decks), and none of that changes which object is in the person's
/// hand.
struct MagicPhysicalTokenKey: Hashable, Comparable, Sendable, CustomStringConvertible {
    let faces: [MagicTokenFaceID]

    init?(faces: [MagicTokenFaceID]) {
        guard (1...2).contains(faces.count) else { return nil }
        self.faces = faces.sorted()
    }

    /// Round-trips `storageKey`. Returns nil for anything that is not one or
    /// two `SET:NUMBER` faces.
    init?(storageKey: String) {
        let parsed = storageKey.split(separator: "|", omittingEmptySubsequences: false).map { part -> MagicTokenFaceID? in
            let pieces = part.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2,
                  !pieces[0].trimmingCharacters(in: .whitespaces).isEmpty,
                  !pieces[1].trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return MagicTokenFaceID(setCode: String(pieces[0]), number: String(pieces[1]))
        }
        let faces = parsed.compactMap { $0 }
        guard faces.count == parsed.count else { return nil }
        self.init(faces: faces)
    }

    var isDoubleFaced: Bool { faces.count == 2 }

    func contains(_ face: MagicTokenFaceID) -> Bool { faces.contains(face) }

    /// Stable, provider-independent storage form: `TMSH:6|TMSH:18`.
    var storageKey: String {
        faces.map { "\($0.setCode):\($0.number)" }.joined(separator: "|")
    }

    var description: String { storageKey }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.faces.lexicographicallyPrecedes(rhs.faces)
    }
}

/// One physical token card as the catalog knows it.
struct MagicPhysicalToken: Hashable, Sendable {
    /// Faces in the provider's display order: `Merfolk // Doombot`.
    let faces: [MagicTokenFace]
    let key: MagicPhysicalTokenKey
    /// Every marketplace listing of this exact cardboard. More than one id is
    /// not more than one object; pricing decides what to do with them.
    let tcgplayerProductIDs: Set<String>

    init?(faces: [MagicTokenFace], tcgplayerProductIDs: Set<String> = []) {
        guard let key = MagicPhysicalTokenKey(faces: faces.map(\.id)) else { return nil }
        self.faces = faces
        self.key = key
        self.tcgplayerProductIDs = tcgplayerProductIDs
    }

    /// `Merfolk // Doombot`, or just `Clue` for a single-sided token.
    var name: String { faces.map(\.name).joined(separator: " // ") }

    var isDoubleFaced: Bool { key.isDoubleFaced }

    func contains(_ face: MagicTokenFaceID) -> Bool { key.contains(face) }

    /// The other side of `face`. Nil for a single-sided card or a face this
    /// card does not carry.
    func reverse(of face: MagicTokenFaceID) -> MagicTokenFace? {
        guard isDoubleFaced, let index = faces.firstIndex(where: { $0.id == face }) else { return nil }
        return faces[1 - index]
    }

    fileprivate func addingListings(_ ids: Set<String>) -> MagicPhysicalToken {
        MagicPhysicalToken(faces: faces, tcgplayerProductIDs: tcgplayerProductIDs.union(ids)) ?? self
    }
}

/// How much of one token set's physical pairing the catalog has verified.
///
/// This is what lets an *absence* mean something. When every card carrying a
/// face from a set is listed, a face that appears on exactly one listing is
/// that card, and a back that appears on none was never printed with it.
/// Without that claim, a listing is still evidence but an absence is not.
enum MagicTokenPairingCoverage: String, Codable, Hashable, Sendable {
    /// Every physical card carrying a face from this set is listed.
    case complete
    /// Some cards are listed. Treated exactly like a set with no entry.
    case partial
}

/// What one scanned face determines on its own.
enum MagicTokenFaceResolution: Equatable, Sendable {
    /// Coverage is complete and exactly one card carries this face.
    case resolved(MagicPhysicalToken)
    /// The face alone cannot say which cardboard it is on.
    ///
    /// - candidates: catalogued cards carrying the face, in key order.
    /// - catalogIsExhaustive: whether those candidates are every possibility.
    ///   When false the back may be something the catalog does not list, or
    ///   carry no token at all.
    case needsReverse(candidates: [MagicPhysicalToken], catalogIsExhaustive: Bool)
}

/// What two faces read from one presentation determine together.
enum MagicTokenPairResolution: Equatable, Sendable {
    /// Exactly one catalogued card carries both faces.
    case resolved(MagicPhysicalToken)
    /// No catalogued card carries both, and the catalog cannot rule it out.
    /// Only a person can say whether this is one card.
    case uncataloguedPair
    /// A coverage-complete set says these faces are never printed together:
    /// these are two different cards.
    case differentCards
    /// The same face read twice is not evidence about the other side, even on
    /// a card printed with that face on both sides.
    case sameFace
}

/// Face to the physical cards that carry it.
///
/// One-to-many by construction. A `[face: face]` dictionary would encode a
/// relationship that does not exist and would silently pick a back: in GRN's
/// Guild Kits one Saproling face is printed against Voja, Wurm and Elf Knight.
struct MagicTokenProductCatalog: Sendable {
    /// Which build of the catalog answered. Recorded with the pairing basis so
    /// a later correction can find every row that leaned on an older build.
    let generation: String
    private let productsByFace: [MagicTokenFaceID: [MagicPhysicalToken]]
    private let productsByKey: [MagicPhysicalTokenKey: MagicPhysicalToken]
    private let coverage: [String: MagicTokenPairingCoverage]

    /// Listings of the same cardboard are merged into one object here, not in
    /// resolution. Two listings of one pair are a finish or packaging
    /// difference, which the existing finish resolver owns — they must never
    /// turn into a request to flip a card that has already been flipped.
    init(
        generation: String = "",
        products: [MagicPhysicalToken],
        coverage: [String: MagicTokenPairingCoverage] = [:]
    ) {
        var byKey: [MagicPhysicalTokenKey: MagicPhysicalToken] = [:]
        for product in products {
            if let existing = byKey[product.key] {
                byKey[product.key] = existing.addingListings(product.tcgplayerProductIDs)
            } else {
                byKey[product.key] = product
            }
        }
        var byFace: [MagicTokenFaceID: [MagicPhysicalToken]] = [:]
        for product in byKey.values {
            for face in Set(product.key.faces) {
                byFace[face, default: []].append(product)
            }
        }
        self.generation = generation
        self.productsByKey = byKey
        self.productsByFace = byFace.mapValues { cards in cards.sorted { $0.key < $1.key } }
        // Two spellings of one code that disagree are not a completeness claim.
        self.coverage = Dictionary(
            coverage.map { ($0.key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), $0.value) },
            uniquingKeysWith: { $0 == $1 ? $0 : .partial }
        )
    }

    func product(for key: MagicPhysicalTokenKey) -> MagicPhysicalToken? {
        productsByKey[key]
    }

    func products(containing face: MagicTokenFaceID) -> [MagicPhysicalToken] {
        productsByFace[face] ?? []
    }

    /// Whether the cards listed for `face` are every card that carries it.
    ///
    /// A coverage claim that does not know the face at all has just been shown
    /// to be wrong, so it is not trusted for that face.
    func isExhaustive(for face: MagicTokenFaceID) -> Bool {
        coverage[face.setCode] == .complete && !products(containing: face).isEmpty
    }

    func resolve(face: MagicTokenFaceID) -> MagicTokenFaceResolution {
        let candidates = products(containing: face)
        let exhaustive = isExhaustive(for: face)
        if exhaustive, candidates.count == 1 {
            return .resolved(candidates[0])
        }
        return .needsReverse(candidates: candidates, catalogIsExhaustive: exhaustive)
    }

    /// Order is irrelevant, which is what lets the person present either side
    /// first.
    func resolve(face: MagicTokenFaceID, reverse: MagicTokenFaceID) -> MagicTokenPairResolution {
        guard face != reverse else { return .sameFace }
        if let key = MagicPhysicalTokenKey(faces: [face, reverse]), let product = productsByKey[key] {
            return .resolved(product)
        }
        // Either complete side is enough: it lists every card its face is on,
        // and none of them carries the other face.
        if isExhaustive(for: face) || isExhaustive(for: reverse) {
            return .differentCards
        }
        return .uncataloguedPair
    }
}

// MARK: Catalog wire format

/// The published form of the token catalog.
///
/// Built offline from marketplace listings (TCGplayer names double-sided
/// tokens `Merfolk // Doombot Double-Sided Token` at number `6 // 18`),
/// Scryfall's own `double_faced_token` records, and reviewed corrections.
/// Coverage is per set and is a reviewed claim, never a default.
struct MagicTokenProductCatalogFile: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    struct SetCoverage: Codable, Equatable, Sendable {
        let code: String
        let coverage: MagicTokenPairingCoverage
    }

    struct Face: Codable, Equatable, Sendable {
        let set: String
        let number: String
        let name: String
    }

    struct Product: Codable, Equatable, Sendable {
        let faces: [Face]
        let tcgplayerProductIDs: [String]?
    }

    let schemaVersion: Int
    let generation: String
    let sets: [SetCoverage]
    let products: [Product]
}

enum MagicTokenProductCatalogError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case missingGeneration
    case duplicateSetCoverage(String)
    case invalidProduct(index: Int)
    /// One face id carrying two different names means a face was assigned to
    /// the wrong set or number somewhere upstream. The whole file is refused:
    /// a catalog that cannot say what a face is cannot say what it pairs with.
    case conflictingFaceNames(MagicTokenFaceID)
}

extension MagicTokenProductCatalog {
    init(jsonData: Data) throws {
        try self.init(file: JSONDecoder().decode(MagicTokenProductCatalogFile.self, from: jsonData))
    }

    init(file: MagicTokenProductCatalogFile) throws {
        guard file.schemaVersion == MagicTokenProductCatalogFile.currentSchemaVersion else {
            throw MagicTokenProductCatalogError.unsupportedSchemaVersion(file.schemaVersion)
        }
        guard !file.generation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MagicTokenProductCatalogError.missingGeneration
        }

        var coverage: [String: MagicTokenPairingCoverage] = [:]
        for entry in file.sets {
            let code = entry.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !code.isEmpty, coverage[code] == nil else {
                throw MagicTokenProductCatalogError.duplicateSetCoverage(code)
            }
            coverage[code] = entry.coverage
        }

        func isBlank(_ value: String) -> Bool {
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        func comparableName(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        }

        var namesByFace: [MagicTokenFaceID: String] = [:]
        var products: [MagicPhysicalToken] = []
        for (index, wire) in file.products.enumerated() {
            let ids = wire.tcgplayerProductIDs ?? []
            guard wire.faces.allSatisfy({ !isBlank($0.set) && !isBlank($0.number) && !isBlank($0.name) }),
                  ids.allSatisfy({ !isBlank($0) }),
                  let product = MagicPhysicalToken(
                    faces: wire.faces.map {
                        MagicTokenFace(
                            setCode: $0.set,
                            number: $0.number,
                            name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    },
                    tcgplayerProductIDs: Set(ids)
                  ) else {
                throw MagicTokenProductCatalogError.invalidProduct(index: index)
            }
            for face in product.faces {
                let name = comparableName(face.name)
                if let known = namesByFace[face.id], known != name {
                    throw MagicTokenProductCatalogError.conflictingFaceNames(face.id)
                }
                namesByFace[face.id] = name
            }
            products.append(product)
        }

        self.init(generation: file.generation, products: products, coverage: coverage)
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
