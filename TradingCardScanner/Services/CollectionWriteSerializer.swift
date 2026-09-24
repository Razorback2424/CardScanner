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
        _ body: (ModelContext) throws -> T
    ) throws -> T {
        guard !isHeldByCurrentThread else {
            assertionFailure("CollectionWriteSerializer.perform must not be nested")
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

/// Task-scoped proof that the caller is inside the refresh/migration gate.
/// Rewrites check this again from inside their serialized transaction, closing
/// the gap between a read-only preflight and the write that uses its result.
enum PriceIdentityRewritePermit {
    @TaskLocal static var isAuthorized = false

    static func requireForSerializedOwnershipWrite() throws {
        guard CollectionWriteSerializer.enforcesOwnershipRule,
              CollectionWriteSerializer.isHeldByCurrentThread,
              !isAuthorized else { return }
        throw CollectionStoreError.priceIdentityExclusivityRequired
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
        return try await PriceIdentityRewritePermit.$isAuthorized.withValue(true) {
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
