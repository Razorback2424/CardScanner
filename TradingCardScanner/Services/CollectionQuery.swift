import Foundation

/// A collection entry flattened for display, with its price already joined in.
///
/// Filtering and sorting operate on these, never on the network. Changing a chip
/// or a sort order is a local computation over values that are already loaded, so
/// it stays instant at thousands of cards.
struct CollectionRow: Identifiable, Equatable {
    let id: String
    let game: CardGame
    let name: String
    let setCode: String
    let setName: String
    let setReleaseOrder: Int
    let cardNumber: String
    let variantID: String?
    let variantLabel: String?
    let quantity: Int
    let dateAdded: Date
    let price: PriceDisplay
    /// Raw card, graded slab or sealed product. Defaulted so every construction
    /// site that predates the widening keeps compiling and keeps meaning what it
    /// meant.
    var itemKind: CollectionItemKind = .rawCard
    /// What the tile says under the name: `Reverse Holo`, `PSA 10`, `Sealed`.
    var itemKindLabel: String?

    var variant: PhysicalVariant? {
        guard let variantID else { return nil }
        return PhysicalVariant(id: variantID, label: variantLabel ?? variantID.capitalized)
    }

    /// Current market price of *one* copy. Filtering and sorting deliberately use
    /// the unit price: ten copies of a $2 card are not a $20 card, and "worth
    /// more than $10" should not return them.
    var unitPrice: Double? { price.amount }

    /// Set codes are only unique within a game. Magic and Pokémon can both use
    /// the same short printed code, so filter identity must include the game's
    /// namespace even though the UI continues to show the familiar code alone.
    var setFilterID: String { "\(game.rawValue):\(setCode.uppercased())" }

    /// The badge shown on the tile. Falls back to the raw finish label so a row
    /// written before item kinds existed still reads correctly.
    var displayKindLabel: String {
        itemKindLabel ?? variantLabel ?? PhysicalVariant.normal.label
    }

    /// Which slot this row occupies for set-completion purposes.
    ///
    /// A raw copy and a graded copy of the same collector number are the same
    /// slot and must count once. Sealed products occupy no slot at all — a
    /// booster box is not a card and cannot complete a set.
    var setCompletionSlot: String? {
        guard itemKind.countsTowardSetCompletion else { return nil }
        return "\(game.rawValue):\(setCode.uppercased()):\(cardNumber)"
    }
}

/// A price question asked the way collectors ask it. Deliberately bands rather
/// than a slider: card prices are distributed far too unevenly for a slider to
/// land where anyone wants it.
enum PriceBand: Hashable, Identifiable, CaseIterable {
    case underOne
    case oneToFive
    case fiveToTen
    case tenToTwentyFive
    case twentyFiveToFifty
    case fiftyToHundred
    case hundredPlus

    var id: String { label }

    var label: String {
        switch self {
        case .underOne: return "Under $1"
        case .oneToFive: return "$1–5"
        case .fiveToTen: return "$5–10"
        case .tenToTwentyFive: return "$10–25"
        case .twentyFiveToFifty: return "$25–50"
        case .fiftyToHundred: return "$50–100"
        case .hundredPlus: return "$100+"
        }
    }

    var bounds: (min: Double?, max: Double?) {
        switch self {
        case .underOne: return (nil, 1)
        case .oneToFive: return (1, 5)
        case .fiveToTen: return (5, 10)
        case .tenToTwentyFive: return (10, 25)
        case .twentyFiveToFifty: return (25, 50)
        case .fiftyToHundred: return (50, 100)
        case .hundredPlus: return (100, nil)
        }
    }
}

/// Either a band or a hand-entered range. One of the four chips.
enum PriceFilter: Hashable {
    case band(PriceBand)
    case custom(min: Double?, max: Double?)
    /// Rows the app has no price for. The only filter that asks about the
    /// *absence* of a price rather than its size, which is why it is the one
    /// case `matches` answers before looking at any range.
    case unpriced

    var label: String {
        switch self {
        case let .band(band): return band.label
        case .unpriced: return "Unpriced"
        case let .custom(min, max):
            let formatted: (Double) -> String = { $0.formatted(.currency(code: "USD").precision(.fractionLength(0...2))) }
            switch (min, max) {
            case let (min?, max?): return "\(formatted(min))–\(formatted(max))"
            case let (min?, nil): return "\(formatted(min))+"
            case let (nil, max?): return "Under \(formatted(max))"
            case (nil, nil): return "Any"
            }
        }
    }

    var bounds: (min: Double?, max: Double?) {
        switch self {
        case let .band(band): return band.bounds
        case let .custom(min, max): return (min, max)
        // Not a range question. `matches` answers `.unpriced` before it reaches
        // here, so these bounds are never consulted.
        case .unpriced: return (nil, nil)
        }
    }

    /// An unknown price is not a cheap price. A row with no price can never
    /// satisfy a question about how much a card costs, in either direction — it
    /// answers only the question of what is still missing a price.
    func matches(_ price: Double?) -> Bool {
        if case .unpriced = self { return price == nil }
        guard let price else { return false }
        let (lower, upper) = bounds
        if let lower, price < lower { return false }
        guard let upper else { return true }
        // Bands tile, so their upper bound is exclusive and $5.00 lands in $5–10
        // rather than in both bands. A hand-typed maximum is inclusive, because
        // someone who types 25 means to see the $25 card.
        return isBand ? price < upper : price <= upper
    }

    private var isBand: Bool {
        if case .band = self { return true }
        return false
    }
}

struct CollectionFilters: Equatable {
    var game: CardGame?
    var setCodes: Set<String> = []
    var variantIDs: Set<String> = []
    var price: PriceFilter?
    /// Empty means every kind, which is what "All Items" selects.
    var itemKinds: Set<CollectionItemKind> = []

    var isActive: Bool {
        game != nil || !setCodes.isEmpty || !variantIDs.isEmpty
            || price != nil || !itemKinds.isEmpty
    }

    static let none = CollectionFilters()
}

enum CollectionSort: String, CaseIterable, Identifiable {
    case cardNumber
    case setAndCardNumber
    case priceHighToLow
    case priceLowToHigh

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cardNumber: return "Card Number"
        case .setAndCardNumber: return "Set + Card Number"
        case .priceHighToLow: return "Price: High to Low"
        case .priceLowToHigh: return "Price: Low to High"
        }
    }
}

/// Name search, and nothing else.
///
/// The box answers one question — *what card name am I looking for?* — and the
/// chips answer the other — *which version of it do I care about?* Keeping those
/// separate is what makes both predictable, so this deliberately does not match
/// set names, set codes, collector numbers, rarity, finish or price. Typing
/// `OBF` finds nothing unless a card is literally named that.
///
/// Matching is case- and diacritic-insensitive, punctuation-insensitive and
/// substring-based. It is not fuzzy: `Charzard` returns nothing rather than
/// quietly deciding what was meant and mixing unexpected cards into the results.
enum CardNameSearch {
    /// Apostrophes close up (`Urza's` and `Urzas` are the same word); every other
    /// separator becomes a space, so `Ho-Oh` matches `ho oh` and runs of spaces
    /// never matter.
    private static let elidedCharacters: Set<Character> = ["\u{0027}", "\u{2019}", "\u{02BC}", "\u{0060}"]

    static func normalize(_ value: String) -> String {
        let folded = value.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )

        var result = ""
        var pendingSeparator = false
        for character in folded {
            if elidedCharacters.contains(character) { continue }
            if character.isLetter || character.isNumber {
                if pendingSeparator, !result.isEmpty { result.append(" ") }
                pendingSeparator = false
                result.append(character)
            } else {
                pendingSeparator = true
            }
        }
        return result
    }

    /// An empty query matches everything: the box narrows whatever view is
    /// already there rather than being a mode of its own.
    static func matches(name: String, normalizedQuery: String) -> Bool {
        guard !normalizedQuery.isEmpty else { return true }
        return normalize(name).contains(normalizedQuery)
    }
}

enum CollectionQuery {
    static func filter(
        _ rows: [CollectionRow],
        nameQuery: String = "",
        with filters: CollectionFilters
    ) -> [CollectionRow] {
        // Normalized once, not once per row.
        let normalizedQuery = CardNameSearch.normalize(nameQuery)

        return rows.filter { row in
            guard CardNameSearch.matches(name: row.name, normalizedQuery: normalizedQuery) else { return false }
            return matchesFilters(row, filters)
        }
    }

    private static func matchesFilters(_ row: CollectionRow, _ filters: CollectionFilters) -> Bool {
        if let game = filters.game, row.game != game { return false }
        if !filters.setCodes.isEmpty, !filters.setCodes.contains(row.setFilterID) { return false }
        if !filters.variantIDs.isEmpty {
            guard let variantID = row.variantID, filters.variantIDs.contains(variantID) else { return false }
        }
        if !filters.itemKinds.isEmpty, !filters.itemKinds.contains(row.itemKind) { return false }
        if let price = filters.price, !price.matches(row.unitPrice) { return false }
        return true
    }

    static func sort(_ rows: [CollectionRow], by sort: CollectionSort) -> [CollectionRow] {
        switch sort {
        case .cardNumber:
            return rows.sorted { left, right in
                let byNumber = CollectorNumber.compare(left.cardNumber, right.cardNumber)
                if byNumber != .orderedSame { return byNumber == .orderedAscending }
                return tieBreak(left, right)
            }

        case .setAndCardNumber:
            // Game first so a Pokémon release index is never weighed against a
            // Magic release date, then newest set first, then binder order.
            return rows.sorted { left, right in
                if left.game != right.game { return left.game.rawValue < right.game.rawValue }
                if left.setReleaseOrder != right.setReleaseOrder { return left.setReleaseOrder > right.setReleaseOrder }
                if left.setCode != right.setCode { return left.setCode < right.setCode }
                let byNumber = CollectorNumber.compare(left.cardNumber, right.cardNumber)
                if byNumber != .orderedSame { return byNumber == .orderedAscending }
                return tieBreak(left, right)
            }

        case .priceHighToLow:
            return rows.sorted { left, right in
                priceOrder(left, right) { $0 > $1 }
            }

        case .priceLowToHigh:
            return rows.sorted { left, right in
                priceOrder(left, right) { $0 < $1 }
            }
        }
    }

    /// Search, then filters, then sort — all local, against records already
    /// loaded. Changing any of them is arithmetic, never a network request.
    static func apply(
        nameQuery: String = "",
        filters: CollectionFilters,
        sort: CollectionSort,
        to rows: [CollectionRow]
    ) -> [CollectionRow] {
        self.sort(filter(rows, nameQuery: nameQuery, with: filters), by: sort)
    }

    /// Unknown is not worthless, so an unpriced card sinks to the bottom of *both*
    /// price sorts rather than sorting as zero.
    private static func priceOrder(
        _ left: CollectionRow,
        _ right: CollectionRow,
        _ compare: (Double, Double) -> Bool
    ) -> Bool {
        switch (left.unitPrice, right.unitPrice) {
        case let (l?, r?):
            return l == r ? tieBreak(left, right) : compare(l, r)
        case (nil, _?): return false
        case (_?, nil): return true
        case (nil, nil): return tieBreak(left, right)
        }
    }

    private static func tieBreak(_ left: CollectionRow, _ right: CollectionRow) -> Bool {
        if left.name != right.name { return left.name < right.name }
        return left.id < right.id
    }
}

/// Collector numbers are not integers. `223`, `0218`, `GG01` and `218a` all
/// appear, so comparison splits a leading number from whatever follows and
/// compares the number numerically — otherwise `100` sorts before `9`.
enum CollectorNumber {
    static func compare(_ left: String, _ right: String) -> ComparisonResult {
        let (leftPrefix, leftNumber, leftSuffix) = parts(of: left)
        let (rightPrefix, rightNumber, rightSuffix) = parts(of: right)

        if leftPrefix != rightPrefix {
            return leftPrefix < rightPrefix ? .orderedAscending : .orderedDescending
        }

        switch (leftNumber, rightNumber) {
        case let (l?, r?) where l != r:
            return l < r ? .orderedAscending : .orderedDescending
        case (nil, _?): return .orderedDescending
        case (_?, nil): return .orderedAscending
        default: break
        }

        if leftSuffix != rightSuffix {
            return leftSuffix < rightSuffix ? .orderedAscending : .orderedDescending
        }
        return .orderedSame
    }

    /// Splits `GG01a` into ("GG", 1, "a").
    private static func parts(of value: String) -> (prefix: String, number: Int?, suffix: String) {
        let scalars = Array(value.uppercased())
        var index = 0

        var prefix = ""
        while index < scalars.count, !scalars[index].isNumber {
            prefix.append(scalars[index])
            index += 1
        }

        var digits = ""
        while index < scalars.count, scalars[index].isNumber {
            digits.append(scalars[index])
            index += 1
        }

        let suffix = String(scalars[index...])
        return (prefix, Int(digits), suffix)
    }
}
