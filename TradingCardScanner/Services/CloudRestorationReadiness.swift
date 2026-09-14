import Foundation
import SwiftData

/// Evidence-backed state for a CloudKit-backed local replica.
///
/// Container construction, account availability, setup completion, an empty
/// fetch, and elapsed time are intentionally absent from this enum: none of
/// them proves that the remote collection has finished importing.
enum CloudRestorationReadiness: Equatable, Sendable {
    case notApplicable
    case checkingRemoteCollection
    case importingRemoteCollection
    case readyEmpty
    case readyPopulated
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
}

enum CloudRestorationReadinessContract {
    /// Bump whenever the evidence mechanism or its ordering contract changes.
    /// A checkpoint written by an older mechanism can never authorize a new
    /// launch as authoritative.
    static let currentMechanismVersion = 3
}

/// Values known before constructing the CloudKit-backed container.
struct CloudRestorationRequest: Equatable, Sendable {
    let bootstrapGeneration: UInt
    let storeID: UUID
    let expectedAnchorGeneration: String
    let accountFingerprint: String
    let anchorClaimedThisLaunch: Bool

    init(
        bootstrapGeneration: UInt,
        storeID: UUID,
        expectedAnchorGeneration: String,
        accountFingerprint: String,
        anchorClaimedThisLaunch: Bool
    ) {
        precondition(
            !expectedAnchorGeneration.isEmpty,
            "A restoration-readiness request requires an anchor generation."
        )
        self.bootstrapGeneration = bootstrapGeneration
        self.storeID = storeID
        self.expectedAnchorGeneration = expectedAnchorGeneration
        self.accountFingerprint = accountFingerprint
        self.anchorClaimedThisLaunch = anchorClaimedThisLaunch
    }
}

@MainActor
protocol CloudRestorationProbe: AnyObject {
    /// Called only after the container exists. The probe resolves the
    /// correlation target from that container, replays events buffered while
    /// it was being constructed, and awaits later events when needed.
    func awaitReadiness(container: ModelContainer) async -> CloudRestorationReadiness

    /// Idempotent. Implementations must tear down notification observers.
    func cancel()
}

/// The production readiness boundary. The default implementation is
/// deliberately conservative until entitled restoration is proven end to end.
protocol CloudRestorationReadinessSource: Sendable {
    @MainActor
    func arm(_ request: CloudRestorationRequest) -> any CloudRestorationProbe
}

@MainActor
private final class UnprovenCloudRestorationProbe: CloudRestorationProbe {
    private var isCancelled = false

    func awaitReadiness(container: ModelContainer) async -> CloudRestorationReadiness {
        guard !isCancelled else {
            return .failed(category: "restoration-readiness-cancelled")
        }
        // A missing proof is not a completed empty database. This probe is
        // useful for the pre-enrollment app shell and makes an unsafe fallback
        // impossible in tests and development builds.
        return .failed(category: "restoration-readiness-not-proven")
    }

    func cancel() {
        isCancelled = true
    }
}

struct UnprovenCloudRestorationReadinessSource: CloudRestorationReadinessSource {
    @MainActor
    func arm(_ request: CloudRestorationRequest) -> any CloudRestorationProbe {
        UnprovenCloudRestorationProbe()
    }
}

@MainActor
private final class FixedCloudRestorationProbe: CloudRestorationProbe {
    private let result: CloudRestorationReadiness
    private var isCancelled = false

    init(result: CloudRestorationReadiness) {
        self.result = result
    }

    func awaitReadiness(container: ModelContainer) async -> CloudRestorationReadiness {
        guard !isCancelled else {
            return .failed(category: "restoration-readiness-cancelled")
        }
        return result
    }

    func cancel() {
        isCancelled = true
    }
}

struct FixedCloudRestorationReadinessSource: CloudRestorationReadinessSource {
    let result: CloudRestorationReadiness

    @MainActor
    func arm(_ request: CloudRestorationRequest) -> any CloudRestorationProbe {
        FixedCloudRestorationProbe(result: result)
    }
}
