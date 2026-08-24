import Foundation

/// What kind of physical thing a collection row stands for.
///
/// The collection began as raw singles and the SwiftData type is still called
/// `CollectedCard` so existing local stores keep working. This is the axis that
/// widens it: a sealed booster box and a PSA 10 slab are different objects from
/// the raw card, with different prices and different identity, but they belong
/// in the same collection and the same totals.
///
/// Every row that existed before this type did is a `.rawCard`, which is why the
/// stored default is deliberately that value rather than something "unknown".
enum CollectionItemKind: String, Codable, CaseIterable, Hashable, Sendable {
    case rawCard
    case gradedCard
    case sealedProduct

    var label: String {
        switch self {
        case .rawCard: return "Raw Cards"
        case .gradedCard: return "Graded Cards"
        case .sealedProduct: return "Sealed Products"
        }
    }

    /// The word used on a single row rather than in a filter menu.
    var singularLabel: String {
        switch self {
        case .rawCard: return "Raw"
        case .gradedCard: return "Graded"
        case .sealedProduct: return "Sealed"
        }
    }

    var symbolName: String {
        switch self {
        case .rawCard: return "rectangle.on.rectangle"
        case .gradedCard: return "seal"
        case .sealedProduct: return "shippingbox"
        }
    }

    /// Whether owning this row counts toward completing a card set.
    ///
    /// A sealed box is not a card and never completes a slot. A raw copy and a
    /// graded copy of the same collector number are the same slot, counted once
    /// — which is enforced where completion is computed, not here.
    var countsTowardSetCompletion: Bool {
        switch self {
        case .rawCard, .gradedCard: return true
        case .sealedProduct: return false
        }
    }
}

/// Who graded a slab.
///
/// Raw values are stable and persisted. The display name is presentation only.
enum GradingCompany: String, Codable, CaseIterable, Hashable, Sendable {
    case psa
    case bgs
    case cgc
    case sgc
    case bccg
    case bvg

    var label: String {
        switch self {
        case .psa: return "PSA"
        case .bgs: return "BGS"
        case .cgc: return "CGC"
        case .sgc: return "SGC"
        case .bccg: return "BCCG"
        case .bvg: return "BVG"
        }
    }

    /// The vendor spells these in its own way; matching is case-insensitive on
    /// the label rather than assuming the raw value round-trips.
    static func named(_ value: String) -> GradingCompany? {
        let normalized = value.trimmingCharacters(in: .whitespaces).lowercased()
        return allCases.first { $0.rawValue == normalized || $0.label.lowercased() == normalized }
    }
}

/// One slab's grade, kept as text rather than a number.
///
/// `9.5` is not an integer, `Authentic` is not a number at all, and graders keep
/// inventing labels. Storing the string the vendor published means a grade this
/// build has never heard of still round-trips instead of being rounded into a
/// different slab.
struct CardGrade: Codable, Hashable, Sendable {
    /// `"10"`, `"9.5"`, or nil for Authentic and similar non-numeric grades.
    let value: String?
    /// `"Black Label"`, `"Pristine"`, `"Authentic"` — the grader's own wording.
    let label: String?
    /// `"OC"`, `"ST"`, `"MK"` — a qualifier narrows a grade and must not be
    /// folded into it: a PSA 10 and a PSA 10 OC are different objects.
    let qualifier: String?

    init(value: String?, label: String? = nil, qualifier: String? = nil) {
        self.value = value?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        self.label = label?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        self.qualifier = qualifier?.trimmingCharacters(in: .whitespaces).nilIfEmpty
    }

    /// What the collection tile shows: `PSA 10`, `BGS 10 Black Label`,
    /// `PSA 10 OC`, `CGC Authentic`.
    func display(company: GradingCompany) -> String {
        var parts = [company.label]
        if let value { parts.append(value) }
        if let label, label.caseInsensitiveCompare(value ?? "") != .orderedSame {
            parts.append(label)
        }
        if let qualifier { parts.append(qualifier) }
        return parts.joined(separator: " ")
    }

    /// Two slabs are the same holding only when grader, grade, label and
    /// qualifier all agree.
    var identityFragment: String {
        [value, label, qualifier]
            .map { $0 ?? "" }
            .joined(separator: "|")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
