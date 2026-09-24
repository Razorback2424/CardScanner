import BackgroundTasks
import Foundation
import SwiftData
import UIKit

/// Schedules and runs the best-effort overnight price refresh.
///
/// Background Tasks decides when the work runs. The processing request asks for
/// a charging-and-network window; the app refresh request is intentionally a
/// small top-up for nights when the device is not charging.
enum BackgroundPriceRefresh {
    enum Kind {
        case processing
        case appRefresh
    }

    /// The one background-work setting a person can change. Scheduler errors
    /// are still best-effort, but this keeps the common system-wide block from
    /// looking like a price-refresh failure.
    enum Availability {
        case available
        case denied
        case restricted

        var label: String {
            switch self {
            case .available: return "On"
            case .denied: return "Off"
            case .restricted: return "Restricted"
            }
        }

        var detail: String? {
            switch self {
            case .available:
                return nil
            case .denied:
                return "Turn on Background App Refresh in Settings to allow overnight price updates."
            case .restricted:
                return "This device restricts Background App Refresh, so overnight price updates can’t run."
            }
        }
    }

    /// Derived from the bundle id, and the `Info.plist` entries are derived
    /// from the same build setting. `BGTaskScheduler.register` throws when an
    /// identifier is absent from `BGTaskSchedulerPermittedIdentifiers`, and a
    /// scheduled request for an unpermitted identifier simply never fires — so
    /// a bundle rename that updated three of the four hard-coded strings would
    /// have disabled overnight price refresh with no error anywhere. One
    /// source now, in the project settings.
    private static let identifierPrefix =
        Bundle.main.bundleIdentifier ?? "com.seankeller.CardScanner"
    static let processingIdentifier = "\(identifierPrefix).priceRefresh.processing"
    static let appRefreshIdentifier = "\(identifierPrefix).priceRefresh.appRefresh"

    /// Three vendor fall-throughs fit comfortably within an opportunistic
    /// app-refresh window even when each needs one paced identity request.
    private static let appRefreshTargetLimit = 3
    private static var hasRegistered = false
    @MainActor private static var activeRun: (id: UUID, task: Task<Bool, Never>)?

    /// Stops the headless phase as well as the price queue when foreground
    /// startup takes ownership. The local migration phase can otherwise hold
    /// the shared migration gate before the refresh controller knows about it.
    @MainActor
    static func preemptActiveRunForForeground() async -> Bool {
        guard let activeRun else { return false }
        await preemptBackgroundRunForForeground(
            task: activeRun.task,
            refreshController: PriceRefreshController.shared
        )
        if self.activeRun?.id == activeRun.id { self.activeRun = nil }
        return true
    }

    @MainActor
    static func preemptBackgroundRunForForeground(
        task: Task<Bool, Never>,
        refreshController: PriceRefreshController
    ) async {
        task.cancel()
        // The controller queue is an unstructured child. Cancelling only the
        // BG task does not cancel that queue, so stop it before awaiting the
        // enclosing run or foreground startup can still wait for the whole
        // provider pass.
        _ = await refreshController.preemptBackgroundPass()
        _ = await task.value
    }

    @MainActor
    static var availability: Availability {
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: return .available
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .restricted
        }
    }

    static func register() {
        guard !hasRegistered else { return }
        hasRegistered = true

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: processingIdentifier,
            using: nil
        ) { task in
            handle(task, kind: .processing)
        }
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: appRefreshIdentifier,
            using: nil
        ) { task in
            handle(task, kind: .appRefresh)
        }
    }

    /// A new request replaces an unexecuted request with the same identifier.
    static func schedule() {
        scheduleProcessing()
        scheduleAppRefresh()
    }

    private static func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: processingIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = true
        request.earliestBeginDate = nextProcessingWindow()
        submit(request)
    }

    private static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: appRefreshIdentifier)
        // An hour is a floor, not a promise. It gives iOS room to choose a
        // low-impact window without competing with the full charging task.
        request.earliestBeginDate = Date.now.addingTimeInterval(60 * 60)
        submit(request)
    }

    private static func submit(_ request: BGTaskRequest) {
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // A matching pending request is replaced rather than rejected.
            // Failures here are instead conditions such as `.notPermitted`,
            // `.unavailable`, or capacity. Settings exposes the common
            // Background App Refresh block; background scheduling remains
            // best-effort for the rest.
        }
    }

    private static func nextProcessingWindow(now: Date = .now) -> Date {
        // Scheduling must never establish portfolio tracking. AppDelegate runs
        // before the epoch owner and otherwise the first launch's current zone
        // would become the permanent portfolio timezone merely because a
        // background request was registered.
        let timeZone = PortfolioCalendar.pinnedTimeZone() ?? .current
        let calendar = PortfolioCalendar.calendar(in: timeZone)
        let time = DateComponents(hour: 2, minute: 30)
        return calendar.nextDate(
            after: now,
            matching: time,
            matchingPolicy: .nextTime,
            direction: .forward
        ) ?? now.addingTimeInterval(24 * 60 * 60)
    }

    private static func handle(_ task: BGTask, kind: Kind) {
        // A task request does not repeat itself. Re-arm before doing any work.
        schedule()

        let completion = TaskCompletion()
        let runID = UUID()
        let work = Task { @MainActor in await run(kind) }
        Task { @MainActor in
            activeRun = (runID, work)
            let success = await work.value
            if activeRun?.id == runID { activeRun = nil }
            completion.finish(task, success: success)
        }
        task.expirationHandler = {
            work.cancel()
            // Completion is time-sensitive. Finish synchronously before the
            // main-actor cancellation so an occupied refresh cannot make iOS
            // record this task as abandoned.
            completion.finish(task, success: false)
            Task { @MainActor in
                // The controller owns an unstructured refresh task, so
                // cancelling only the enclosing background task is insufficient.
                PriceRefreshController.shared.cancelRefresh(onlyIfOwnedBy: .background)
            }
        }
    }

    /// The single headless refresh path. `allowsForeground` exists only for the
    /// debug settings action that exercises the same work without a scheduler.
    @MainActor
    static func run(_ kind: Kind, allowsForeground: Bool = false) async -> Bool {
        guard allowsForeground || UIApplication.shared.applicationState == .background else {
            return true
        }
        guard let storage = await CollectionStorageHeadlessPreflight.prepare(
            dependencies: .production()
        ) else {
            // A fresh background process may not run the foreground bootstrap.
            // Without a previously proven manifest/checkpoint/store tuple, the
            // task must remain a no-op rather than minting or attaching data.
            return true
        }
        guard storage.isAuthoritative else {
            // A cached populated checkpoint is last-known state only. It must
            // not authorize price writes or portfolio-close publication until
            // a fresh foreground restoration proof establishes current state.
            return true
        }
        let shouldContinue = storage.continuation
        let container = storage.container
        let context = container.mainContext
        let migration = MagicTreatmentMigrationCoordinator.shared
        // Background Tasks has a small, non-renewable budget, and a scheduled
        // launch is normally a *fresh process* — so deferred Scryfall
        // enrichment has never run here and would consume the whole window
        // before any pricing happened. Skip that phase rather than skipping the
        // refresh: holding the gate is what makes the pass safe, and a row that
        // has not been enriched yet is priced under its current key, exactly as
        // it would be if no migration were pending at all.
        let refreshResult = await migration.withPriceRefresh(
            in: context,
            runsNetworkMigration: false,
            storageToken: storage.token,
            shouldContinue: shouldContinue,
            operation: {
                guard shouldContinue() else {
                    return PriceRefreshResult(
                        didRun: false,
                        targetBuildFailed: false,
                        wasPreempted: true
                    )
                }
                let usesPriceFallback = UserDefaults.standard.bool(forKey: "usesPriceFallback")
                let request = PriceRefreshRequest(
                    usesPriceFallback: usesPriceFallback,
                    includeImported: true,
                    forceUnsupportedRetry: false,
                    sortOldestFirst: true,
                    maximumTargetCount: kind == .appRefresh ? appRefreshTargetLimit : nil,
                    markRecentlyCheckedIfEmpty: false,
                    gradedOnly: false
                )
                return await PriceRefreshController.shared.refresh(
                    request,
                    container: context.container,
                    shouldContinue: shouldContinue,
                    owner: .background
                )
            }
        )
        guard let refreshResult else { return false }
        guard !refreshResult.wasPreempted,
              !Task.isCancelled,
              shouldContinue() else { return false }

        // Do not call `start`: a background launch must never establish a new
        // portfolio epoch. It may only publish a close from an epoch the person
        // has already opened in the app.
        await PortfolioEngine().recomputeAndWait(context: context)
        return !Task.isCancelled && shouldContinue()
    }
}

/// `BGTask` completion can race its expiration handler. Complete exactly once
/// so a late success cannot overwrite an expiration failure.
private final class TaskCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var hasCompleted = false

    func finish(_ task: BGTask, success: Bool) {
        lock.lock()
        guard !hasCompleted else {
            lock.unlock()
            return
        }
        hasCompleted = true
        lock.unlock()
        task.setTaskCompleted(success: success)
    }
}
