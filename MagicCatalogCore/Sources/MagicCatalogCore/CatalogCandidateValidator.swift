import Foundation

public enum MagicCatalogCandidateValidator {
    public enum ValidationError: Error, CustomStringConvertible, Equatable, Sendable {
        case activeRevisionNotLowerThanCandidate(active: Int, candidate: Int)
        case reportRevisionMismatch
        case reportDescriptorCountMismatch
        case reportSemanticDiffMismatch(String)

        public var description: String {
            switch self {
            case let .activeRevisionNotLowerThanCandidate(active, candidate):
                return "Candidate revision \(candidate) must be greater than active revision \(active)"
            case .reportRevisionMismatch:
                return "Magic candidate review report revision does not match payload"
            case .reportDescriptorCountMismatch:
                return "Magic candidate review report descriptor count does not match payload"
            case .reportSemanticDiffMismatch(let component):
                return "Magic candidate review report does not match recomputed \(component)"
            }
        }
    }

    public enum PublicationBindingError: Error, CustomStringConvertible, Equatable, Sendable {
        case missingRequestedChangeClass
        case requestedChangeClassMismatch(
            requested: MagicCatalogChangeClass,
            recomputed: MagicCatalogChangeClass
        )
        case reportChangeClassMismatch(
            reported: MagicCatalogChangeClass,
            recomputed: MagicCatalogChangeClass
        )

        public var description: String {
            switch self {
            case .missingRequestedChangeClass:
                return "--change-class is required for publish"
            case .requestedChangeClassMismatch:
                return "--change-class does not match the candidate classification"
            case let .reportChangeClassMismatch(reported, recomputed):
                return "candidate review report changeClass \(reported.rawValue) does not match recomputed classification \(recomputed.rawValue)"
            }
        }
    }

    public static func validate(
        _ result: MagicCatalogBuildResult,
        activeRelease: MagicCatalogRelease? = nil
    ) throws {
        try MagicCatalogReleaseValidator.validate(result.release)
        if let activeRelease, result.release.revision <= activeRelease.revision {
            throw ValidationError.activeRevisionNotLowerThanCandidate(
                active: activeRelease.revision,
                candidate: result.release.revision
            )
        }
        guard result.report.revision == result.release.revision else {
            throw ValidationError.reportRevisionMismatch
        }
        guard result.report.generatedAt == result.release.generatedAt else {
            throw ValidationError.reportSemanticDiffMismatch("generatedAt")
        }
        guard result.report.descriptorCount == result.release.sets.count else {
            throw ValidationError.reportDescriptorCountMismatch
        }

        let expectedSurfaceDiff = MagicCatalogChangeClassifier.surfaceDiff(
            previousRelease: activeRelease,
            currentRelease: result.release
        )
        let expectedClassification = MagicCatalogChangeClassifier.classify(
            previousRelease: activeRelease,
            currentRelease: result.release,
            surfaceDiff: expectedSurfaceDiff
        )

        try requireEqual(
            result.report.addedCodes,
            expectedSurfaceDiff.addedCodes,
            component: "addedCodes"
        )
        try requireEqual(
            result.report.changedCodes,
            expectedSurfaceDiff.changedCodes,
            component: "changedCodes"
        )
        try requireEqual(
            result.report.removedCodes,
            expectedSurfaceDiff.removedCodes,
            component: "removedCodes"
        )
        try requireEqual(
            result.report.scannerProjectionChangedCodes,
            expectedSurfaceDiff.scannerProjectionChangedCodes,
            component: "scannerProjectionChangedCodes"
        )
        try requireEqual(
            result.report.browseProjectionChangedCodes,
            expectedSurfaceDiff.browseProjectionChangedCodes,
            component: "browseProjectionChangedCodes"
        )
        try requireEqual(
            result.report.routingProjectionChangedCodes,
            expectedSurfaceDiff.routingProjectionChangedCodes,
            component: "routingProjectionChangedCodes"
        )
        try requireEqual(
            result.report.changeClass,
            expectedClassification.changeClass,
            component: "changeClass"
        )
        try requireEqual(
            result.report.contentChangedCodes,
            expectedClassification.contentChangedCodes,
            component: "contentChangedCodes"
        )
        try requireEqual(
            result.report.authorityChangedCodes,
            expectedClassification.authorityChangedCodes,
            component: "authorityChangedCodes"
        )
    }

    /// Binds the workflow-selected class to the same recomputed result used
    /// by candidate validation before any signing material is loaded.
    public static func bindPublicationClass(
        requestedChangeClass: MagicCatalogChangeClass?,
        report: MagicCatalogReviewReport,
        recomputedClassification: MagicCatalogChangeClassification
    ) throws -> MagicCatalogChangeClass {
        guard let requestedChangeClass else {
            throw PublicationBindingError.missingRequestedChangeClass
        }
        guard requestedChangeClass == recomputedClassification.changeClass else {
            throw PublicationBindingError.requestedChangeClassMismatch(
                requested: requestedChangeClass,
                recomputed: recomputedClassification.changeClass
            )
        }
        guard report.changeClass == recomputedClassification.changeClass else {
            throw PublicationBindingError.reportChangeClassMismatch(
                reported: report.changeClass,
                recomputed: recomputedClassification.changeClass
            )
        }
        return recomputedClassification.changeClass
    }

    private static func requireEqual<T: Equatable>(
        _ received: T,
        _ expected: T,
        component: String
    ) throws {
        guard received == expected else {
            throw ValidationError.reportSemanticDiffMismatch(component)
        }
    }
}
