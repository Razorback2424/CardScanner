import Foundation
import OSLog

#if canImport(Darwin)
import Darwin
#endif

/// Controls the only production cutover in the automatic-catalog rollout.
///
/// The validation-only default is deliberate: a build can exercise the real
/// signed origin without allowing a remote descriptor to change recognition or
/// Browse. Staging can opt into `remoteAuthority` through its xcconfig after a
/// no-op release has been reviewed.
enum PokemonCatalogRolloutMode: String, Equatable, Sendable {
    case bundledValidationOnly = "bundled-validation-only"
    case remoteAuthority = "remote-authority"

    static let infoPlistKey = "POKEMON_CATALOG_ROLLOUT_MODE"

    static var configured: Self {
        from(rawValue: Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String)
    }

    static func from(rawValue: String?) -> Self {
        guard let rawValue else { return .bundledValidationOnly }
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        return Self(rawValue: normalized) ?? .bundledValidationOnly
    }
}

struct PokemonCatalogRolloutValidation: Equatable, Sendable {
    let revision: Int
    let descriptorCount: Int
    let supportedDescriptorCount: Int
    let payloadBytes: Int?
}

struct PokemonCatalogRolloutDiagnosticsSnapshot: Equatable, Sendable {
    let mode: PokemonCatalogRolloutMode
    let launchLoadCount: Int
    let refreshCount: Int
    let networkRequestCount: Int
    let networkResponseCount: Int
    let networkResponseBytes: Int
    let networkNotModifiedCount: Int
    let validationCount: Int
    let activationCount: Int
    let rejectionCount: Int
    let cancellationCount: Int
    let lastRevision: Int?
    let lastPayloadBytes: Int?
    let lastDiskBytes: Int?
    let lastMemoryFootprintBytes: UInt64?
    let lastLaunchLoadDuration: TimeInterval?
    let lastValidationDuration: TimeInterval?
    let lastActivationDuration: TimeInterval?
    let lastOutcome: String?
    let lastError: String?
}

/// Lightweight, local-only rollout evidence. Nothing here is uploaded or
/// attached to a collection export. Instruments can use the matching
/// `PerformanceSignpost` intervals for frame-level measurements; this actor
/// keeps the release-path counts and footprint samples easy to assert in tests.
actor PokemonCatalogRolloutDiagnostics {
    static let shared = PokemonCatalogRolloutDiagnostics()

    private static let logger = Logger(
        subsystem: "com.scan-stash.TradingCardScanner",
        category: "pokemonCatalogRollout"
    )

    private var mode: PokemonCatalogRolloutMode = .bundledValidationOnly
    private var launchLoadCount = 0
    private var refreshCount = 0
    private var networkRequestCount = 0
    private var networkResponseCount = 0
    private var networkResponseBytes = 0
    private var networkNotModifiedCount = 0
    private var validationCount = 0
    private var activationCount = 0
    private var rejectionCount = 0
    private var cancellationCount = 0
    private var lastRevision: Int?
    private var lastPayloadBytes: Int?
    private var lastDiskBytes: Int?
    private var lastMemoryFootprintBytes: UInt64?
    private var lastLaunchLoadDuration: TimeInterval?
    private var lastValidationDuration: TimeInterval?
    private var lastActivationDuration: TimeInterval?
    private var lastOutcome: String?
    private var lastError: String?

    func setMode(_ mode: PokemonCatalogRolloutMode) {
        self.mode = mode
    }

    func recordLaunchLoad(
        mode: PokemonCatalogRolloutMode,
        duration: TimeInterval,
        usedPersistedRelease: Bool
    ) {
        self.mode = mode
        launchLoadCount += 1
        lastLaunchLoadDuration = duration
        lastOutcome = usedPersistedRelease ? "loaded-persisted" : "loaded-bundled"
        Self.logger.debug(
            "Catalog launch load mode=\(mode.rawValue, privacy: .public) duration=\(duration, privacy: .public) persisted=\(usedPersistedRelease, privacy: .public)"
        )
    }

    func recordRefreshStarted(mode: PokemonCatalogRolloutMode) {
        self.mode = mode
        refreshCount += 1
    }

    func recordNetworkRequest(attempt: Int) {
        networkRequestCount += 1
        Self.logger.debug("Catalog network request attempt=\(attempt, privacy: .public)")
    }

    func recordNetworkResponse(statusCode: Int, bytes: Int, attempt: Int) {
        networkResponseCount += 1
        networkResponseBytes += bytes
        Self.logger.debug(
            "Catalog network response status=\(statusCode, privacy: .public) bytes=\(bytes, privacy: .public) attempt=\(attempt, privacy: .public)"
        )
    }

    func recordNotModified() {
        networkNotModifiedCount += 1
        lastOutcome = "not-modified"
    }

    func recordValidation(
        _ validation: PokemonCatalogRolloutValidation,
        diskBytes: Int,
        memoryFootprintBytes: UInt64?,
        duration: TimeInterval
    ) {
        validationCount += 1
        lastRevision = validation.revision
        lastPayloadBytes = validation.payloadBytes
        lastDiskBytes = diskBytes
        lastMemoryFootprintBytes = memoryFootprintBytes
        lastValidationDuration = duration
        lastOutcome = "validated-and-discarded"
        Self.logger.info(
            "Catalog release validated and discarded revision=\(validation.revision, privacy: .public) descriptors=\(validation.descriptorCount, privacy: .public) supported=\(validation.supportedDescriptorCount, privacy: .public) diskBytes=\(diskBytes, privacy: .public) memoryBytes=\(memoryFootprintBytes ?? 0, privacy: .public)"
        )
    }

    func recordActivation(
        revision: Int,
        diskBytes: Int,
        memoryFootprintBytes: UInt64?,
        duration: TimeInterval
    ) {
        activationCount += 1
        lastRevision = revision
        lastDiskBytes = diskBytes
        lastMemoryFootprintBytes = memoryFootprintBytes
        lastActivationDuration = duration
        lastOutcome = "activated"
        Self.logger.info(
            "Catalog release activated revision=\(revision, privacy: .public) diskBytes=\(diskBytes, privacy: .public) memoryBytes=\(memoryFootprintBytes ?? 0, privacy: .public)"
        )
    }

    func recordRejection(_ error: Error) {
        rejectionCount += 1
        lastOutcome = "rejected"
        lastError = String(describing: error)
        Self.logger.warning("Catalog release rejected: \(self.lastError ?? "unknown", privacy: .public)")
    }

    func recordCancellation() {
        cancellationCount += 1
        lastOutcome = "cancelled"
    }

    func recordNetworkFailure(_ error: Error) {
        lastOutcome = "network-failed"
        lastError = String(describing: error)
        Self.logger.warning("Catalog network failed: \(self.lastError ?? "unknown", privacy: .public)")
    }

    func snapshot() -> PokemonCatalogRolloutDiagnosticsSnapshot {
        PokemonCatalogRolloutDiagnosticsSnapshot(
            mode: mode,
            launchLoadCount: launchLoadCount,
            refreshCount: refreshCount,
            networkRequestCount: networkRequestCount,
            networkResponseCount: networkResponseCount,
            networkResponseBytes: networkResponseBytes,
            networkNotModifiedCount: networkNotModifiedCount,
            validationCount: validationCount,
            activationCount: activationCount,
            rejectionCount: rejectionCount,
            cancellationCount: cancellationCount,
            lastRevision: lastRevision,
            lastPayloadBytes: lastPayloadBytes,
            lastDiskBytes: lastDiskBytes,
            lastMemoryFootprintBytes: lastMemoryFootprintBytes,
            lastLaunchLoadDuration: lastLaunchLoadDuration,
            lastValidationDuration: lastValidationDuration,
            lastActivationDuration: lastActivationDuration,
            lastOutcome: lastOutcome,
            lastError: lastError
        )
    }

    #if DEBUG
    func reset() {
        mode = .bundledValidationOnly
        launchLoadCount = 0
        refreshCount = 0
        networkRequestCount = 0
        networkResponseCount = 0
        networkResponseBytes = 0
        networkNotModifiedCount = 0
        validationCount = 0
        activationCount = 0
        rejectionCount = 0
        cancellationCount = 0
        lastRevision = nil
        lastPayloadBytes = nil
        lastDiskBytes = nil
        lastMemoryFootprintBytes = nil
        lastLaunchLoadDuration = nil
        lastValidationDuration = nil
        lastActivationDuration = nil
        lastOutcome = nil
        lastError = nil
    }
    #endif

    static func currentMemoryFootprintBytes() -> UInt64? {
#if canImport(Darwin)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.phys_footprint)
#else
        return nil
#endif
    }
}
