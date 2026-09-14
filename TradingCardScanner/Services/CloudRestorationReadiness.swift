import Foundation

/// Evidence-backed state for a CloudKit-backed local replica.
///
/// Container construction, account availability, setup completion, an empty
/// fetch, and elapsed time are intentionally absent from this enum: none of
/// them proves that the remote collection has finished importing.
enum CloudRestorationReadiness: Equatable, Sendable {
    case notApplicable
    case checkingRemoteCollection
    case importingRemoteCollection
    case readyEmpty(remoteGeneration: String)
    case readyPopulated(remoteGeneration: String)
    case failed(category: String)

    var isReady: Bool {
        switch self {
        case .readyEmpty, .readyPopulated:
            return true
        case .notApplicable, .checkingRemoteCollection, .importingRemoteCollection, .failed:
            return false
        }
    }

    var isRecoverableFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    var remoteGeneration: String? {
        switch self {
        case let .readyEmpty(remoteGeneration), let .readyPopulated(remoteGeneration):
            return remoteGeneration.isEmpty ? nil : remoteGeneration
        case .notApplicable, .checkingRemoteCollection, .importingRemoteCollection, .failed:
            return nil
        }
    }
}

enum CloudRestorationReadinessContract {
    /// Bump whenever the evidence mechanism or its ordering contract changes.
    /// A checkpoint written by an older mechanism can never authorize a new
    /// launch as authoritative.
    static let currentMechanismVersion = 2
}

/// The smallest typed boundary a production readiness implementation must
/// satisfy. The default implementation is deliberately conservative until the
/// exact SwiftData/Core Data event ordering is proven on supported devices.
protocol CloudRestorationReadinessSource: Sendable {
    func readiness(
        storeID: UUID,
        accountFingerprint: String,
        generation: UInt
    ) async -> CloudRestorationReadiness
}

struct UnprovenCloudRestorationReadinessSource: CloudRestorationReadinessSource {
    func readiness(
        storeID: UUID,
        accountFingerprint: String,
        generation: UInt
    ) async -> CloudRestorationReadiness {
        // A missing proof is not a completed empty database. This source is
        // useful for the pre-enrollment app shell and makes an unsafe fallback
        // impossible in tests and development builds.
        .failed(category: "restoration-readiness-not-proven")
    }
}

struct FixedCloudRestorationReadinessSource: CloudRestorationReadinessSource {
    let result: CloudRestorationReadiness

    func readiness(
        storeID: UUID,
        accountFingerprint: String,
        generation: UInt
    ) async -> CloudRestorationReadiness {
        result
    }
}
