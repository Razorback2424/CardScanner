import Foundation

/// Which physical object the scanner should expect in its framing guide.
/// This choice belongs to the live scanning session and is never persisted.
enum ScanSubjectMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case raw
    case slab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .raw: "Raw cards"
        case .slab: "Graded slabs"
        }
    }

    var symbolName: String {
        switch self {
        case .raw: "rectangle.portrait"
        case .slab: "rectangle.stack"
        }
    }
}
