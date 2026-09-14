import CloudKit
import CoreData
import Foundation
import SwiftData

/// The only CloudKit event data retained by the readiness probe. In
/// particular, this value contains no record IDs, account IDs, model data, or
/// full error payloads.
struct RedactedCloudKitEvent: Equatable, Sendable {
    enum EventType: String, Equatable, Sendable {
        case setup
        case `import`
        case export
    }

    let identifier: UUID
    let type: EventType
    let storeIdentifier: String
    let startDate: Date
    let endDate: Date?
    let succeeded: Bool
    let errorCategory: String
}

/// A post-import snapshot read from the newly constructed container. A count
/// is intentionally the only visibility fact needed by the reducer.
struct CloudRestorationVisibilitySnapshot: Equatable, Sendable {
    let visibleRowCount: Int

    init(visibleRowCount: Int) {
        self.visibleRowCount = max(0, visibleRowCount)
    }
}

enum CloudKitEventReadinessCorrelation: Equatable, Sendable {
    case singleton
    case explicit(String)
    case failed(String)
}

@MainActor
final class CloudKitEventReadinessSource: @unchecked Sendable, CloudRestorationReadinessSource {
    typealias VisibilityProvider = @MainActor (ModelContainer) throws -> CloudRestorationVisibilitySnapshot
    typealias CorrelationTargetResolver = @MainActor (ModelContainer) -> String?

    private let notificationCenter: NotificationCenter
    private let visibilityProvider: VisibilityProvider
    private let correlationTargetResolver: CorrelationTargetResolver
    private let allowReadyEmpty: Bool
    private var activeGeneration: UInt?
    private var activeProbe: CloudKitEventReadinessProbe?

    /// Test-only visibility into the lifecycle object so throwing container
    /// construction can assert that arming did not leak observers.
    var activeProbeForTesting: CloudKitEventReadinessProbe? { activeProbe }

    init(
        notificationCenter: NotificationCenter = .default,
        visibilityProvider: @escaping VisibilityProvider = { container in
            CloudRestorationVisibilitySnapshot(
                visibleRowCount: try container.mainContext.fetchCount(
                    FetchDescriptor<CollectedCard>()
                )
            )
        },
        correlationTargetResolver: @escaping CorrelationTargetResolver = { _ in nil },
        allowReadyEmpty: Bool = false
    ) {
        self.notificationCenter = notificationCenter
        self.visibilityProvider = visibilityProvider
        self.correlationTargetResolver = correlationTargetResolver
        self.allowReadyEmpty = allowReadyEmpty
    }

    @MainActor
    func arm(_ request: CloudRestorationRequest) -> any CloudRestorationProbe {
        activeProbe?.cancel()
        activeGeneration = request.bootstrapGeneration
        let probe = CloudKitEventReadinessProbe(
            request: request,
            notificationCenter: notificationCenter,
            visibilityProvider: visibilityProvider,
            correlationTargetResolver: correlationTargetResolver,
            allowReadyEmpty: allowReadyEmpty,
            isCurrent: { [weak self] in
                guard let self else { return false }
                return self.activeGeneration == request.bootstrapGeneration
            }
        )
        activeProbe = probe
        return probe
    }
}

@MainActor
final class CloudKitEventReadinessProbe: CloudRestorationProbe {
    private static let maximumBufferedEvents = 64

    private let request: CloudRestorationRequest
    private let notificationCenter: NotificationCenter
    private let visibilityProvider: CloudKitEventReadinessSource.VisibilityProvider
    private let correlationTargetResolver: CloudKitEventReadinessSource.CorrelationTargetResolver
    private let allowReadyEmpty: Bool
    private let isCurrent: @MainActor () -> Bool

    private var observerTokens: [NSObjectProtocol] = []
    private var events: [RedactedCloudKitEvent] = []
    private var eventCursor = 0
    private var eventContinuation: AsyncStream<RedactedCloudKitEvent>.Continuation?
    private var correlationResolution: CloudKitEventReadinessCorrelation?
    private var terminalResult: CloudRestorationReadiness?

    private lazy var eventStream: AsyncStream<RedactedCloudKitEvent> = {
        AsyncStream(bufferingPolicy: .bufferingNewest(Self.maximumBufferedEvents)) { [weak self] continuation in
            self?.eventContinuation = continuation
        }
    }()

    /// Exposed for deterministic lifecycle tests. Production callers only use
    /// the protocol surface.
    var registeredObserverCount: Int { observerTokens.count }

    init(
        request: CloudRestorationRequest,
        notificationCenter: NotificationCenter,
        visibilityProvider: @escaping CloudKitEventReadinessSource.VisibilityProvider,
        correlationTargetResolver: @escaping CloudKitEventReadinessSource.CorrelationTargetResolver,
        allowReadyEmpty: Bool,
        isCurrent: @escaping @MainActor () -> Bool,
        preResolvedCorrelation: CloudKitEventReadinessCorrelation? = nil
    ) {
        self.request = request
        self.notificationCenter = notificationCenter
        self.visibilityProvider = visibilityProvider
        self.correlationTargetResolver = correlationTargetResolver
        self.allowReadyEmpty = allowReadyEmpty
        self.isCurrent = isCurrent
        self.correlationResolution = preResolvedCorrelation
        registerObservers()
    }

    deinit {
        for token in observerTokens {
            notificationCenter.removeObserver(token)
        }
    }

    func awaitReadiness(container: ModelContainer) async -> CloudRestorationReadiness {
        if let terminalResult { return terminalResult }
        guard isCurrent() else {
            return finish(.failed(category: "restoration-readiness-stale-generation"))
        }
        guard !request.expectedAnchorGeneration.isEmpty else {
            return finish(.failed(category: "restoration-readiness-missing-anchor-generation"))
        }
        if correlationResolution == nil {
            correlationResolution = resolveCorrelation(container: container)
        }
        if case let .failed(category) = correlationResolution {
            return finish(.failed(category: category))
        }

        // Events can arrive between arm() and container construction. Replay
        // them before waiting for a new notification.
        if eventCursor < events.count {
            eventCursor = events.count
            return evaluate(container: container)
        }

        while terminalResult == nil {
            guard let _ = await waitForNextEvent() else {
                return terminalResult ?? finish(.failed(category: "restoration-readiness-cancelled"))
            }
            guard isCurrent() else {
                return finish(.failed(category: "restoration-readiness-stale-generation"))
            }
            eventCursor = events.count
            let result = evaluate(container: container)
            switch result {
            case .checkingRemoteCollection, .importingRemoteCollection,
                 .readyEmpty, .readyPopulated, .failed, .notApplicable:
                return result
            }
        }
        return terminalResult ?? .failed(category: "restoration-readiness-cancelled")
    }

    func cancel() {
        guard terminalResult == nil else { return }
        terminalResult = .failed(category: "restoration-readiness-cancelled")
        tearDownObservers()
    }

    /// Deterministic test seam for the reducer. Production events enter via
    /// the NotificationCenter observer and are redacted before storage.
    func ingest(_ event: RedactedCloudKitEvent) {
        receive(event)
    }

    private func registerObservers() {
        let eventToken = notificationCenter.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event,
                let redacted = Self.redact(event) else {
                return
            }
            Task { @MainActor [weak self] in
                self?.receive(redacted)
            }
        }
        observerTokens.append(eventToken)

        let accountToken = notificationCenter.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.accountDidChange()
            }
        }
        observerTokens.append(accountToken)
    }

    private func receive(_ event: RedactedCloudKitEvent) {
        guard terminalResult == nil else { return }
        events.append(event)
        if events.count > Self.maximumBufferedEvents {
            let overflow = events.count - Self.maximumBufferedEvents
            events.removeFirst(overflow)
            eventCursor = max(0, eventCursor - overflow)
        }
        eventContinuation?.yield(event)
    }

    private func accountDidChange() {
        _ = finish(.failed(category: "restoration-readiness-account-changed"))
    }

    private func tearDownObservers() {
        for token in observerTokens {
            notificationCenter.removeObserver(token)
        }
        observerTokens.removeAll()
        eventContinuation?.finish()
        eventContinuation = nil
    }

    private func finish(_ result: CloudRestorationReadiness) -> CloudRestorationReadiness {
        terminalResult = result
        tearDownObservers()
        return result
    }

    private func waitForNextEvent() async -> RedactedCloudKitEvent? {
        return await withTaskCancellationHandler(operation: {
            // Install the stream continuation before checking the retained
            // buffer. This closes the arm/replay/wait race in which a
            // notification could arrive after the caller's replay check but
            // before the lazy stream was initialized.
            _ = eventStream
            if eventCursor < events.count {
                let event = events[eventCursor]
                eventCursor += 1
                return event
            }
            var iterator = eventStream.makeAsyncIterator()
            return await iterator.next()
        }, onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        })
    }

    private func resolveCorrelation(container: ModelContainer) -> CloudKitEventReadinessCorrelation {
        if let explicit = correlationTargetResolver(container) {
            guard !explicit.isEmpty else {
                return .failed("restoration-readiness-invalid-store-correlation")
            }
            return .explicit(explicit)
        }

        // SwiftData does not expose the underlying NSPersistentStore
        // identifier. §0 proves the safe fallback for this process shape:
        // there must be exactly one CloudKit-backed configuration, and the
        // first distinct event storeIdentifier becomes the singleton target.
        let cloudKitConfigurationCount = container.configurations.filter {
            $0.cloudKitContainerIdentifier != nil
        }.count
        guard cloudKitConfigurationCount == 1 else {
            return .failed("restoration-readiness-cloud-configuration-not-singleton")
        }
        return .singleton
    }

    private func evaluate(container: ModelContainer) -> CloudRestorationReadiness {
        guard let correlationResolution else {
            return .failed(category: "restoration-readiness-correlation-unresolved")
        }

        let matchingEvents: [RedactedCloudKitEvent]
        switch correlationResolution {
        case .singleton:
            let identifiers = Set(events.map(\.storeIdentifier))
            guard !identifiers.contains(where: { $0.isEmpty }) else {
                return .failed(category: "restoration-readiness-missing-store-identifier")
            }
            guard identifiers.count <= 1 else {
                return .failed(category: "restoration-readiness-multiple-store-identifiers")
            }
            guard let storeIdentifier = identifiers.first else {
                return .checkingRemoteCollection
            }
            matchingEvents = events.filter { $0.storeIdentifier == storeIdentifier }
        case let .explicit(storeIdentifier):
            matchingEvents = events.filter { $0.storeIdentifier == storeIdentifier }
        case let .failed(category):
            return .failed(category: category)
        }

        let imports = matchingEvents.filter { $0.type == .import }
        guard !imports.isEmpty else {
            return .checkingRemoteCollection
        }

        let successfulImports = imports.filter {
            $0.succeeded && $0.endDate != nil
        }
        guard let successfulImport = successfulImports.max(by: { lhs, rhs in
            Self.isLater(lhs, rhs)
        }) else {
            if imports.contains(where: { $0.endDate == nil }) {
                return .importingRemoteCollection
            }
            if let failedImport = imports.filter({ !$0.succeeded }).max(by: { lhs, rhs in
                Self.isLater(lhs, rhs)
            }) {
                return .failed(category: Self.failureCategory(for: failedImport))
            }
            return .checkingRemoteCollection
        }

        let newerImports = imports.filter {
            Self.isLater($0, than: successfulImport)
        }
        if newerImports.contains(where: { $0.endDate == nil }) {
            return .importingRemoteCollection
        }
        if let failedImport = newerImports.filter({ !$0.succeeded }).max(by: { lhs, rhs in
            Self.isLater(lhs, rhs)
        }) {
            return .failed(category: Self.failureCategory(for: failedImport))
        }

        do {
            // This is deliberately the first and only place the visibility
            // provider is called: after a completed successful import boundary
            // and after newer failure/in-progress checks.
            let snapshot = try visibilityProvider(container)
            if snapshot.visibleRowCount > 0 {
                return .readyPopulated
            }
            return allowReadyEmpty ? .readyEmpty : .importingRemoteCollection
        } catch {
            return .failed(category: "restoration-readiness-visibility-snapshot")
        }
    }

    private static func isLater(
        _ lhs: RedactedCloudKitEvent,
        _ rhs: RedactedCloudKitEvent
    ) -> Bool {
        eventDate(lhs) > eventDate(rhs)
    }

    private static func isLater(
        _ event: RedactedCloudKitEvent,
        than other: RedactedCloudKitEvent
    ) -> Bool {
        eventDate(event) > eventDate(other)
    }

    private static func eventDate(_ event: RedactedCloudKitEvent) -> Date {
        event.endDate ?? event.startDate
    }

    private static func failureCategory(for event: RedactedCloudKitEvent) -> String {
        event.errorCategory == "none" ? "restoration-readiness-import-failed" : event.errorCategory
    }

    private nonisolated static func redact(
        _ event: NSPersistentCloudKitContainer.Event
    ) -> RedactedCloudKitEvent? {
        let type: RedactedCloudKitEvent.EventType
        switch event.type {
        case .setup:
            type = .setup
        case .import:
            type = .import
        case .export:
            type = .export
        @unknown default:
            return nil
        }
        return RedactedCloudKitEvent(
            identifier: event.identifier,
            type: type,
            storeIdentifier: event.storeIdentifier,
            startDate: event.startDate,
            endDate: event.endDate,
            succeeded: event.succeeded,
            errorCategory: errorCategory(for: event.error)
        )
    }

    private nonisolated static func errorCategory(for error: Error?) -> String {
        guard let error else { return "none" }
        guard let cloudKitError = error as? CKError else { return "unknown" }
        switch cloudKitError.code {
        case .notAuthenticated, .accountTemporarilyUnavailable:
            return "account"
        case .networkFailure, .networkUnavailable:
            return "network"
        case .serviceUnavailable, .requestRateLimited, .zoneBusy, .limitExceeded:
            return "service"
        case .quotaExceeded:
            return "quota"
        case .partialFailure:
            return "partial-failure"
        case .operationCancelled:
            return "cancelled"
        case .unknownItem:
            return "missing-item"
        default:
            return "other"
        }
    }
}
