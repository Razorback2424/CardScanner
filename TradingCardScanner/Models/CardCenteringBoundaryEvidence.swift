import Foundation

/// Source bytes are the identity; oriented native pixels are the evidence space.
/// Import history before these bytes reached the app is deliberately unknown.
struct CardCenteringInputRecord: Codable, Equatable {
    let sha256: String
    let byteCount: Int
    let rawRasterSize: CardCenteringSize
    let exifOrientation: Int
    let sourceColorSpace: String?
    let detectorMapping: CardCenteringCoordinateMapping
    let presentationMapping: CardCenteringCoordinateMapping
    let priorProcessingHistory: String
}

enum CardCenteringBoundaryRole: String, Codable, CaseIterable {
    case physicalCut, sleeveOrSlab, shadow, printedBorder, artwork, designReference, unknown

    var label: String {
        switch self {
        case .physicalCut: "Card edge"
        case .sleeveOrSlab: "Sleeve or slab"
        case .shadow: "Shadow"
        case .printedBorder: "Printed border"
        case .artwork: "Artwork frame"
        case .designReference: "Design reference"
        case .unknown: "Unidentified edge"
        }
    }
}

/// A definition identifies what is being compared, never a grading guarantee.
enum CardCenteringReferenceDefinition: String, Codable, CaseIterable {
    case unavailable, unverified
    case pokemonClassicBack, magicClassicBack
#if DEBUG
    case matchedArtwork
#endif
    case userPrintedBorder, userArtwork, userOther

    static let userChoices: [Self] = [.userPrintedBorder, .userArtwork, .userOther]
    var isUserSelected: Bool { Self.userChoices.contains(self) }
    var isAvailable: Bool { self != .unavailable && self != .unverified }
    var label: String {
        switch self {
        case .unavailable: "No reference"
        case .unverified: "Choose reference"
        case .pokemonClassicBack: "Pokémon classic back border"
        case .magicClassicBack: "Magic classic back border"
#if DEBUG
        case .matchedArtwork: "Published artwork frame"
#endif
        case .userPrintedBorder: "Printed border"
        case .userArtwork: "Artwork frame"
        case .userOther: "Other reference"
        }
    }
    var role: CardCenteringBoundaryRole {
        switch self {
        case .pokemonClassicBack, .magicClassicBack: .designReference
        case .userPrintedBorder: .printedBorder
        case .userArtwork: .artwork
#if DEBUG
        case .matchedArtwork: .artwork
#endif
        default: .unknown
        }
    }
    var reportNote: String {
        isUserSelected
            ? "Geometric estimate · \(label.lowercased()) chosen by you. Design asymmetry may be intentional; this is not a grading assessment."
            : "Reference: \(label). Guided estimate, not a grading assessment."
    }
}

struct CardCenteringNativeLine: Codable, Equatable {
    let start: CardCenteringPoint
    let end: CardCenteringPoint

    var isValid: Bool {
        [start.x, start.y, end.x, end.y].allSatisfy(\.isFinite)
            && hypot(end.x - start.x, end.y - start.y) > 1e-8
    }

    /// Supporting-line equality ignores which sample band supplied endpoints.
    func coincides(with other: Self, tolerance: Double = 1e-5) -> Bool {
        guard isValid, other.isValid else { return false }
        let dx = end.x - start.x, dy = end.y - start.y
        let length = hypot(dx, dy)
        return [other.start, other.end].allSatisfy {
            abs(dx * ($0.y - start.y) - dy * ($0.x - start.x)) / length <= tolerance
        }
    }
}

struct CardCenteringSampleBand: Codable, Equatable {
    let start: CardCenteringPoint
    let end: CardCenteringPoint
    /// Nil means the proposing stage did not retain the observation count.
    let sampleCount: Int?
}

struct CardCenteringBoundaryExclusion: Codable, Equatable {
    /// A stage's rejected interpretation, not proof of physical identity.
    let role: CardCenteringBoundaryRole
    let reason: String
    /// Only present when the stage recorded an actual excluded image region.
    /// A rejected interpretation alone must never be drawn as a spatial mask.
    var nativeBand: CardCenteringSampleBand? = nil
}

enum CardCenteringBoundarySelectionReason: String, Codable {
    case detectorProposal, competingCandidate, userSelected, manualAdjustment
}

struct CardCenteringBoundaryCandidate: Codable, Equatable, Identifiable {
    let id: String
    let frame: CardCenteringPrecisionFrame
    let side: CardCenteringPrecisionSide
    let nativeLine: CardCenteringNativeLine
    let source: String
    let proposedRole: CardCenteringBoundaryRole
    let competingRoles: [CardCenteringBoundaryRole]
    let signal: String
    let strength: Double?
    let polarity: Double?
    let coverage: Double?
    let fitResidualNativePixels: Double?
    let sampleBands: [CardCenteringSampleBand]
    let exclusions: [CardCenteringBoundaryExclusion]
    let selectionReason: CardCenteringBoundarySelectionReason
    let reason: String
    var observedPoints: [CardCenteringPoint]? = nil
}

struct CardCenteringSelectedLine: Codable, Equatable {
    let frame: CardCenteringPrecisionFrame
    let side: CardCenteringPrecisionSide
    let nativeLine: CardCenteringNativeLine
    let role: CardCenteringBoundaryRole
    let candidateID: String?
    let reason: CardCenteringBoundarySelectionReason
}

extension CardCenteringMeasurement {
    /// Review nearest the current guide first, never nearest a preferred ratio.
    /// All retained alternatives remain available; coincident stage proposals
    /// do not need duplicate controls in the editing interface.
    func reviewCandidates(frame: CardCenteringPrecisionFrame, side: CardCenteringPrecisionSide) -> [CardCenteringBoundaryCandidate] {
        guard let selected = selectedLines.first(where: { $0.frame == frame && $0.side == side }) else { return [] }
        let midpoint = CardCenteringPoint(x: (selected.nativeLine.start.x + selected.nativeLine.end.x) / 2,
                                         y: (selected.nativeLine.start.y + selected.nativeLine.end.y) / 2)
        func distance(_ candidate: CardCenteringBoundaryCandidate) -> Double {
            let a = candidate.nativeLine.start, b = candidate.nativeLine.end
            return abs((b.x - a.x) * (midpoint.y - a.y) - (b.y - a.y) * (midpoint.x - a.x)) / hypot(b.x - a.x, b.y - a.y)
        }
        let ordered = boundaryCandidates.filter { $0.frame == frame && $0.side == side && $0.nativeLine.isValid }.sorted {
            let lhs = distance($0), rhs = distance($1)
            return abs(lhs - rhs) > 1e-8 ? lhs < rhs : $0.id < $1.id
        }
        return ordered.reduce(into: []) { result, candidate in
            if !result.contains(where: { $0.nativeLine.coincides(with: candidate.nativeLine) }) { result.append(candidate) }
        }
    }

    var selectedLines: [CardCenteringSelectedLine] {
        CardCenteringPrecisionFrame.allCases.flatMap { frame in
            guard let quad = frame == .outer ? geometryOuterQuad : geometryInnerQuad else { return [CardCenteringSelectedLine]() }
            let native = coordinateMapping?.nativeQuad(fromWorking: quad) ?? quad
            return CardCenteringPrecisionSide.allCases.map { side in
                let line = CardCenteringNativeLine(start: native.points[side.index], end: native.points[(side.index + 1) % 4])
                let choice = boundaryChoices.first { $0.frame == frame && $0.side == side && $0.nativeLine.coincides(with: line) }
                let proposal = boundaryCandidates.first {
                    $0.frame == frame && $0.side == side && $0.source.hasPrefix("selected.") && $0.nativeLine.coincides(with: line)
                }
                return CardCenteringSelectedLine(frame: frame, side: side, nativeLine: line,
                    role: choice?.role ?? (frame == .outer ? .physicalCut : referenceDefinition.role),
                    candidateID: choice?.candidateID ?? proposal?.id,
                    reason: choice?.reason ?? (proposal == nil ? .manualAdjustment : .detectorProposal))
            }
        }
    }

    /// A deliberate choice replaces only one supporting line. Intersections
    /// move its endpoints; the other seven supporting lines remain unchanged.
    @discardableResult
    mutating func selectBoundaryCandidate(id: String, as role: CardCenteringBoundaryRole) -> Bool {
        guard let evidence = boundaryCandidates.first(where: { $0.id == id }),
              evidence.nativeLine.isValid,
              evidence.frame == .outer ? role == .physicalCut : [.printedBorder, .artwork, .designReference, .unknown].contains(role),
              let current = evidence.frame == .outer ? geometryOuterQuad : geometryInnerQuad else { return false }
        let native = coordinateMapping?.nativeQuad(fromWorking: current) ?? current
        let side = evidence.side
        let midpoint = CardCenteringPoint(x: (native.points[side.index].x + native.points[(side.index + 1) % 4].x) / 2,
                                         y: (native.points[side.index].y + native.points[(side.index + 1) % 4].y) / 2)
        let a = evidence.nativeLine.start, b = evidence.nativeLine.end
        let dx = b.x - a.x, dy = b.y - a.y
        // setPrecisionSide pivots at the current side midpoint. Intersect the
        // candidate there, instead of using a sample band's arbitrary midpoint.
        let position: Double
        if side.isVertical {
            guard abs(dy) > 1e-10 else { return false }
            position = a.x + (midpoint.y - a.y) * dx / dy
        } else {
            guard abs(dx) > 1e-10 else { return false }
            position = a.y + (midpoint.x - a.x) * dy / dx
        }
        guard setPrecisionSide(side, frame: evidence.frame, positionNativePixels: position,
                               angleDegrees: atan2(dy, dx) * 180 / .pi) else { return false }
        boundaryChoices.removeAll { $0.frame == evidence.frame && $0.side == side }
        boundaryChoices.append(CardCenteringSelectedLine(frame: evidence.frame, side: side,
            nativeLine: evidence.nativeLine, role: role, candidateID: id, reason: .userSelected))
        return true
    }
}
