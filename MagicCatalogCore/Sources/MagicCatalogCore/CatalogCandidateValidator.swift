import Foundation

public enum MagicCatalogCandidateValidator {
    public enum ValidationError: Error, CustomStringConvertible, Equatable, Sendable {
        case activeRevisionNotLowerThanCandidate(active: Int, candidate: Int)
        case reportRevisionMismatch
        case reportDescriptorCountMismatch

        public var description: String {
            switch self {
            case let .activeRevisionNotLowerThanCandidate(active, candidate):
                return "Candidate revision \(candidate) must be greater than active revision \(active)"
            case .reportRevisionMismatch:
                return "Magic candidate review report revision does not match payload"
            case .reportDescriptorCountMismatch:
                return "Magic candidate review report descriptor count does not match payload"
            }
        }
    }

    public static func validate(
        _ result: MagicCatalogBuildResult,
        activeRevision: Int? = nil
    ) throws {
        try MagicCatalogReleaseValidator.validate(result.release)
        if let activeRevision, result.release.revision <= activeRevision {
            throw ValidationError.activeRevisionNotLowerThanCandidate(
                active: activeRevision,
                candidate: result.release.revision
            )
        }
        guard result.report.revision == result.release.revision else {
            throw ValidationError.reportRevisionMismatch
        }
        guard result.report.descriptorCount == result.release.sets.count else {
            throw ValidationError.reportDescriptorCountMismatch
        }
    }
}
