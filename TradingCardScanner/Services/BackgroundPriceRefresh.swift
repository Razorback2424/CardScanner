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

    static let processingIdentifier = "com.example.TradingCardScanner.priceRefresh.processing"
    static let appRefreshIdentifier = "com.example.TradingCardScanner.priceRefresh.appRefresh"

    /// Three vendor fall-throughs fit comfortably within an opportunistic
    /// app-refresh window even when each needs one paced identity request.
    private static let appRefreshTargetLimit = 3
    private static var hasRegistered = false

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
        let work = Task { @MainActor in
            let success = await run(kind)
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
                PriceRefreshController.shared.cancelRefresh()
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
        guard UIApplication.shared.isProtectedDataAvailable,
              PortfolioEpoch.startedAt() != nil else {
            return true
        }

        let context = TradingCardScannerApp.container.mainContext
        let migration = MagicTreatmentMigrationCoordinator.shared
        // Background Tasks has a small, non-renewable budget, and a scheduled
        // launch is normally a *fresh process* — so deferred Scryfall
        // enrichment has never run here and would consume the whole window
        // before any pricing happened. Skip that phase rather than skipping the
        // refresh: holding the gate is what makes the pass safe, and a row that
        // has not been enriched yet is priced under its current key, exactly as
        // it would be if no migration were pending at all.
        await migration.withPriceRefresh(
            in: context,
            runsNetworkMigration: false
        ) {
            // Make the target snapshot inside the gate. A target built before
            // the gate was acquired could have been rekeyed underneath it and
            // would write its result under a superseded price key.
            let allTargets: [PriceTarget]
            do {
                allTargets = try PriceRefreshTargets.make(
                    context: context,
                    usesPriceFallback: UserDefaults.standard.bool(forKey: "usesPriceFallback"),
                    includeImported: true
                )
            } catch {
                return
            }

            let usesPriceFallback = UserDefaults.standard.bool(forKey: "usesPriceFallback")
            let staleTargets = PriceRefreshController.staleTargets(
                from: allTargets,
                usesPriceFallback: usesPriceFallback
            )
                .sorted {
                    ($0.lastCheckedAt ?? .distantPast) < ($1.lastCheckedAt ?? .distantPast)
                }
            let targets: [PriceTarget]
            switch kind {
            case .processing:
                targets = staleTargets
            case .appRefresh:
                targets = Array(staleTargets.prefix(appRefreshTargetLimit))
            }

            if !targets.isEmpty {
                await PriceRefreshController.shared.refresh(
                    targets,
                    store: PriceStore(context: context)
                )
            }
        }
        guard !Task.isCancelled else { return false }

        // Do not call `start`: a background launch must never establish a new
        // portfolio epoch. It may only publish a close from an epoch the person
        // has already opened in the app.
        await PortfolioEngine().recomputeAndWait(context: context)
        return !Task.isCancelled
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
