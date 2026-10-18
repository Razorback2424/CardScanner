import Dispatch
import SwiftData

/// Launch workers use an explicitly owned serial executor. Off-main creation
/// alone did not keep DefaultSerialModelExecutor off the UI thread in a real
/// iOS 27 launch profile, despite passing the in-memory simulator probe.
protocol BackgroundModelActor: ModelActor {
    init(modelContainer: ModelContainer, modelExecutor: any ModelExecutor)
}

extension BackgroundModelActor {
    nonisolated static func makeBackground(modelContainer: ModelContainer) async -> Self {
        let queue = DispatchQueue(label: "TradingCardScanner.\(Self.self)", qos: .userInitiated)
        return await withCheckedContinuation { continuation in
            queue.async {
                let context = ModelContext(modelContainer)
                let executor = BackgroundSerialModelExecutor(modelContext: context, queue: queue)
                continuation.resume(returning: Self(modelContainer: modelContainer, modelExecutor: executor))
            }
        }
    }
}

/// Context creation and every actor job use the same private serial queue.
/// Only the actor and Sendable results cross back to the UI; no model context
/// or fetched model is handed to a different owner.
final class BackgroundSerialModelExecutor: SerialModelExecutor, @unchecked Sendable {
    let modelContext: ModelContext
    private let queue: DispatchQueue

    init(modelContext: ModelContext, queue: DispatchQueue) {
        self.modelContext = modelContext
        self.queue = queue
    }

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        queue.async {
            job.runSynchronously(on: self.asUnownedSerialExecutor())
        }
    }
}
