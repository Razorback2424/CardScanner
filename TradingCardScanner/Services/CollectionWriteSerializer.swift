import Foundation
import SwiftData

/// Serializes ownership mutations across every context in the process.
///
/// Lock order for nested work is fixed: `CollectionWriteSerializer` is
/// outermost, then `PriceObservationLog.backfillLock`, the `CollectionStore`
/// alias-cache lock, and the artwork cleanup-queue lock. Alias-cache
/// invalidation may take its leaf lock by itself, but code must never hold a
/// subordinate lock while acquiring this serializer. The write body is
/// synchronous and never crosses an `await`, so the lock protects a complete
/// fresh-context read/validate/save.
enum CollectionWriteSerializer {
    enum Timeout: Equatable {
        /// Main-thread callers wait at most 1.5 seconds before reporting busy.
        case mainThread
        /// Background callers wait for the current ownership write to finish.
        case wait
    }

    private static let ownershipLock = NSRecursiveLock()
    private static let settingsLock = NSLock()
    private static let threadDepthKey = "TradingCardScanner.CollectionWriteSerializer.depth"
    private static var activeExclusiveToken: UUID?
    private static var ownershipRuleEnabled = false

    static var enforcesOwnershipRule: Bool {
        get {
            settingsLock.lock()
            defer { settingsLock.unlock() }
            return ownershipRuleEnabled
        }
        set {
            settingsLock.lock()
            ownershipRuleEnabled = newValue
            settingsLock.unlock()
        }
    }

    static var isHeldByCurrentThread: Bool {
        (Thread.current.threadDictionary[threadDepthKey] as? Int ?? 0) > 0
    }

    static func perform<T>(
        container: ModelContainer,
        timeout: Timeout,
        exclusiveToken: UUID? = nil,
        callerLabel: String = #function,
        _ body: (ModelContext) throws -> T
    ) throws -> T {
        guard !isHeldByCurrentThread else {
            assertionFailure("CollectionWriteSerializer.perform must not be nested")
            throw CollectionStoreError.collectionBusy
        }

        let waitID = PerformanceSignpost.makeID()
        let waitState = PerformanceSignpost.beginInterval(
            "collectionWriteLockWait",
            id: waitID,
            "caller=\(callerLabel) timeout=\(timeout)"
        )
        let acquired: Bool
        switch timeout {
        case .mainThread:
            acquired = ownershipLock.lock(before: Date.now.addingTimeInterval(1.5))
        case .wait:
            ownershipLock.lock()
            acquired = true
        }
        PerformanceSignpost.endInterval(
            "collectionWriteLockWait",
            waitState,
            "caller=\(callerLabel) outcome=\(acquired ? "acquired" : "timeout")"
        )
        guard acquired else {
            throw CollectionStoreError.collectionBusy
        }

        defer {
            Thread.current.threadDictionary.removeObject(forKey: threadDepthKey)
            ownershipLock.unlock()
        }

        guard activeExclusiveToken == exclusiveToken else {
            throw CollectionStoreError.collectionBusy
        }

        Thread.current.threadDictionary[threadDepthKey] = 1
        let context = ModelContext(container)
        context.autosaveEnabled = false

        do {
            let result = try body(context)
            if context.hasChanges {
                context.rollback()
                LocalArtworkOverrideRekeyer.discardPendingFilesAfterRollback(in: context)
                assertionFailure(
                    "CollectionWriteSerializer body returned with unsaved ownership changes"
                )
            }
            return result
        } catch {
            context.rollback()
            LocalArtworkOverrideRekeyer.discardPendingFilesAfterRollback(in: context)
            throw error
        }
    }

    /// Blocks un-tokened writes until `endExclusive` is called. Individual
    /// writes still acquire the lock and must pass this token explicitly.
    static func beginExclusive(timeout: Timeout = .wait) throws -> UUID {
        guard !isHeldByCurrentThread else {
            assertionFailure("Cannot begin an exclusive session inside a write")
            throw CollectionStoreError.collectionBusy
        }
        switch timeout {
        case .mainThread:
            guard ownershipLock.lock(before: Date.now.addingTimeInterval(1.5)) else {
                throw CollectionStoreError.collectionBusy
            }
        case .wait:
            ownershipLock.lock()
        }
        defer { ownershipLock.unlock() }
        guard activeExclusiveToken == nil else {
            throw CollectionStoreError.collectionBusy
        }
        let token = UUID()
        activeExclusiveToken = token
        return token
    }

    static func endExclusive(_ token: UUID) {
        ownershipLock.lock()
        defer { ownershipLock.unlock() }
        precondition(activeExclusiveToken == token, "Exclusive collection write token mismatch")
        activeExclusiveToken = nil
    }
}

/// Unforgeable authorization passed only by the migration and identity gates.
/// It is deliberately not a task-local value: Swift copies task-local values
/// into unstructured child tasks, which could otherwise outlive the gate.
struct PriceIdentityRewritePermit: Sendable {
    fileprivate let id: UUID
}

private final class PriceIdentityRewritePermitRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var activePermitIDs: Set<UUID> = []
    private var permitsByTask: [UnsafeCurrentTask: Set<UUID>] = [:]

    func activate(_ permit: PriceIdentityRewritePermit) {
        lock.lock()
        activePermitIDs.insert(permit.id)
        lock.unlock()
    }

    func deactivate(_ permit: PriceIdentityRewritePermit) {
        lock.lock()
        activePermitIDs.remove(permit.id)
        for task in Array(permitsByTask.keys) {
            permitsByTask[task]?.remove(permit.id)
            if permitsByTask[task]?.isEmpty == true {
                permitsByTask.removeValue(forKey: task)
            }
        }
        lock.unlock()
    }

    func add(_ permit: PriceIdentityRewritePermit, to task: UnsafeCurrentTask) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard activePermitIDs.contains(permit.id) else { return false }
        permitsByTask[task, default: []].insert(permit.id)
        return true
    }

    func remove(_ permit: PriceIdentityRewritePermit, from task: UnsafeCurrentTask) {
        lock.lock()
        defer { lock.unlock() }
        permitsByTask[task]?.remove(permit.id)
        if permitsByTask[task]?.isEmpty == true {
            permitsByTask.removeValue(forKey: task)
        }
    }

    func authorizesCurrentTask() -> Bool {
        guard let task = withUnsafeCurrentTask(body: { $0 }) else { return false }
        lock.lock()
        defer { lock.unlock() }
        return permitsByTask[task]?.contains(where: activePermitIDs.contains) == true
    }
}

enum PriceIdentityRewriteAuthorization {
    private static let registry = PriceIdentityRewritePermitRegistry()

    /// Starts an authorized gate scope and makes its capability available to
    /// the operation. Child tasks must explicitly bind that capability with
    /// `withAuthorizedTask`; inheriting the parent task context is not enough.
    @MainActor
    static func withAuthorization<T>(
        _ operation: @MainActor (PriceIdentityRewritePermit) async throws -> T
    ) async rethrows -> T {
        let permit = PriceIdentityRewritePermit(id: UUID())
        registry.activate(permit)
        defer { registry.deactivate(permit) }
        return try await withAuthorizedTask(permit, operation: {
            try await operation(permit)
        })
    }

    /// Explicitly authorizes one child task while its parent gate remains
    /// active. A copied permit becomes invalid as soon as that gate exits.
    @MainActor
    static func withAuthorizedTask<T>(
        _ permit: PriceIdentityRewritePermit,
        operation: @MainActor () async throws -> T
    ) async rethrows -> T {
        guard let task = withUnsafeCurrentTask(body: { $0 }), registry.add(permit, to: task) else {
            return try await operation()
        }
        defer { registry.remove(permit, from: task) }
        return try await operation()
    }

    static func requireForSerializedOwnershipWrite() throws {
        guard CollectionWriteSerializer.enforcesOwnershipRule,
              CollectionWriteSerializer.isHeldByCurrentThread else { return }
        guard registry.authorizesCurrentTask() else {
            throw CollectionStoreError.priceIdentityExclusivityRequired
        }
    }
}

extension PriceIdentityRewritePermit {
    static func requireForSerializedOwnershipWrite() throws {
        try PriceIdentityRewriteAuthorization.requireForSerializedOwnershipWrite()
    }
}

/// Coordinates structural price-identity rewrites with the refresh queue and
/// the existing migration/refresh gate. Callers must hold this boundary before
/// entering a serialized write that can rekey price records or their lineage.
@MainActor
enum CollectionExclusiveWrites {
    static func withPriceIdentityExclusivity<T>(
        waitForActivePassToFinish: Bool = false,
        _ operation: @MainActor () async throws -> T
    ) async rethrows -> T {
        let suspension = await PriceRefreshController.shared.suspendPasses(
            cancelActivePass: !waitForActivePassToFinish
        )
        let migrationGate = await MagicTreatmentMigrationCoordinator.shared.acquireExclusive()
        defer {
            MagicTreatmentMigrationCoordinator.shared.releaseExclusive(migrationGate)
            PriceRefreshController.shared.resume(suspension)
        }
        return try await PriceIdentityRewriteAuthorization.withAuthorization { _ in
            try await operation()
        }
    }

    /// Runs a write once, then retries under the identity gate if its in-write
    /// preflight found that a price key became structural after the caller's
    /// optimistic preflight.
    static func retryingIfRequired<T>(
        waitForActivePassToFinish: Bool = false,
        _ operation: @MainActor () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch CollectionStoreError.priceIdentityExclusivityRequired {
            return try await withPriceIdentityExclusivity(
                waitForActivePassToFinish: waitForActivePassToFinish
            ) {
                try await operation()
            }
        }
    }
}
