import Foundation
import OSLog
import SwiftData

/// A single recorded change, kept only so it can be taken back.
struct CollectionMutation: Equatable, Sendable {
    let collectionKey: String
    let activityID: UUID?
    /// Whether the change created the row or incremented an existing one, which
    /// is the difference between deleting it and counting back down.
    let didInsert: Bool
    /// The ordered ledger lineage for this session-only mutation. A scan starts
    /// with its acquisition operation; each correction appends another
    /// operation without discarding what came before it.
    let ledgerOperationIDs: [UUID]
    /// A certified slab re-scan is a successful no-op: the certificate already
    /// identifies the physical object, so it must not create a second row or a
    /// second ledger acquisition.
    let wasDuplicate: Bool

    init(
        collectionKey: String,
        activityID: UUID?,
        didInsert: Bool,
        ledgerOperationIDs: [UUID] = [],
        wasDuplicate: Bool = false
    ) {
        self.collectionKey = collectionKey
        self.activityID = activityID
        self.didInsert = didInsert
        self.ledgerOperationIDs = ledgerOperationIDs
        self.wasDuplicate = wasDuplicate
    }
}

enum CollectionQuantityLimits {
    static let maximum = 1_000_000

    static func checkedAdd(_ lhs: Int, _ rhs: Int) throws -> Int {
        guard lhs >= 0, rhs >= 0 else {
            throw CollectionStoreError.quantityOutOfRange("negative quantity")
        }
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow, sum <= maximum else {
            throw CollectionStoreError.quantityOutOfRange("quantity exceeds \(maximum)")
        }
        return sum
    }

    static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { return rhs >= 0 ? Int.max : Int.min }
        return sum
    }
}

/// Keeps device-local artwork attached to a collection identity when that
/// identity is normalized or a physical copy is corrected to another key.
enum LocalArtworkOverrideRekeyer {
    private final class CleanupQueue: @unchecked Sendable {
        private final class ContextEntry {
            weak var context: ModelContext?
            var filenames = Set<String>()

            init(context: ModelContext) {
                self.context = context
            }
        }

        private let lock = NSLock()
        private var entriesByContext: [ObjectIdentifier: ContextEntry] = [:]

        func add(_ filename: String, context: ModelContext) {
            guard !filename.isEmpty else { return }
            lock.lock()
            let identifier = ObjectIdentifier(context)
            let entry: ContextEntry
            if let existing = entriesByContext[identifier], existing.context === context {
                entry = existing
            } else {
                entry = ContextEntry(context: context)
                entriesByContext[identifier] = entry
            }
            entry.filenames.insert(filename)
            lock.unlock()
        }

        func take(context: ModelContext) -> Set<String> {
            lock.lock()
            defer { lock.unlock() }
            let identifier = ObjectIdentifier(context)
            guard let entry = entriesByContext[identifier], entry.context === context else {
                entriesByContext[identifier] = nil
                return []
            }
            entriesByContext[identifier] = nil
            return entry.filenames
        }

        func restore(_ filenames: Set<String>, context: ModelContext) {
            guard !filenames.isEmpty else { return }
            lock.lock()
            let identifier = ObjectIdentifier(context)
            let entry: ContextEntry
            if let existing = entriesByContext[identifier], existing.context === context {
                entry = existing
            } else {
                entry = ContextEntry(context: context)
                entriesByContext[identifier] = entry
            }
            entry.filenames.formUnion(filenames)
            lock.unlock()
        }

        func discard(context: ModelContext) {
            lock.lock()
            let identifier = ObjectIdentifier(context)
            if entriesByContext[identifier]?.context === context {
                entriesByContext[identifier] = nil
            }
            lock.unlock()
        }
    }

    private static let cleanupQueue = CleanupQueue()

    enum DestinationPolicy {
        /// Combine overrides for two rows that represent the same identity.
        case newestWins
        /// Keep the destination's own artwork when moving a different identity
        /// onto it, using source artwork only when the destination has none.
        case preserveExisting
    }

    struct PreparedMove {
        fileprivate let destinationKey: String
        fileprivate let sourceRows: [LocalArtworkOverride]
        fileprivate let destinationRows: [LocalArtworkOverride]
        fileprivate let preferred: LocalArtworkOverride
        fileprivate let preservingSource: Bool
        fileprivate let destinationPolicy: DestinationPolicy
    }

    static func rekey(
        from sourceKey: String,
        to destinationKey: String,
        preservingSource: Bool = false,
        destinationPolicy: DestinationPolicy = .newestWins,
        in context: ModelContext
    ) throws {
        apply(
            try prepareMove(
                from: sourceKey,
                to: destinationKey,
                preservingSource: preservingSource,
                destinationPolicy: destinationPolicy,
                in: context
            ),
            in: context
        )
    }

    /// Fetches and resolves both sides before a caller begins a larger write.
    /// Applying the returned plan performs only in-memory model edits.
    static func prepareMove(
        from sourceKey: String,
        to destinationKey: String,
        preservingSource: Bool = false,
        destinationPolicy: DestinationPolicy = .newestWins,
        in context: ModelContext
    ) throws -> PreparedMove? {
        guard sourceKey != destinationKey else { return nil }
        let sourceRows = try context.fetch(
            FetchDescriptor<LocalArtworkOverride>(
                predicate: #Predicate { $0.collectionKey == sourceKey }
            )
        )
        guard !sourceRows.isEmpty else { return nil }
        let destinationRows = try context.fetch(
            FetchDescriptor<LocalArtworkOverride>(
                predicate: #Predicate { $0.collectionKey == destinationKey }
            )
        )
        let sourcePreferred = sourceRows.max(by: isOlder)
        let destinationPreferred = destinationRows.max(by: isOlder)
        let preferred: LocalArtworkOverride?
        switch destinationPolicy {
        case .newestWins:
            preferred = (sourceRows + destinationRows).max(by: isOlder)
        case .preserveExisting:
            preferred = destinationPreferred ?? sourcePreferred
        }
        guard let preferred else { return nil }

        return PreparedMove(
            destinationKey: destinationKey,
            sourceRows: sourceRows,
            destinationRows: destinationRows,
            preferred: preferred,
            preservingSource: preservingSource,
            destinationPolicy: destinationPolicy
        )
    }

    static func apply(_ move: PreparedMove?, in context: ModelContext) {
        guard let move else { return }

        let destinationPreferred = move.destinationRows.max(by: isOlder)
        if case .preserveExisting = move.destinationPolicy {
            let sourcePreferred = move.sourceRows.max(by: isOlder)
            if destinationPreferred == nil, let sourcePreferred {
                context.insert(
                    LocalArtworkOverride(
                        collectionKey: move.destinationKey,
                        filename: sourcePreferred.filename,
                        updatedAt: sourcePreferred.updatedAt
                    )
                )
            }
            for duplicate in move.sourceRows where duplicate !== sourcePreferred {
                delete(duplicate, in: context)
            }
            if let destinationPreferred {
                for duplicate in move.destinationRows where duplicate !== destinationPreferred {
                    delete(duplicate, in: context)
                }
            }
            // Keep one mapping on the source key even when the source row is
            // about to disappear. Undo and recent-removal restore can then
            // recover that card's own image.
            return
        }

        if move.preservingSource {
            if let destination = destinationPreferred {
                if destination.filename != move.preferred.filename {
                    cleanupQueue.add(destination.filename, context: context)
                }
                destination.filename = move.preferred.filename
                destination.updatedAt = move.preferred.updatedAt
                for duplicate in move.destinationRows where duplicate !== destination {
                    delete(duplicate, in: context)
                }
            } else {
                context.insert(
                    LocalArtworkOverride(
                        collectionKey: move.destinationKey,
                        filename: move.preferred.filename,
                        updatedAt: move.preferred.updatedAt
                    )
                )
            }
            return
        }

        move.preferred.collectionKey = move.destinationKey
        for duplicate in move.sourceRows + move.destinationRows where duplicate !== move.preferred {
            delete(duplicate, in: context)
        }
    }

    /// Files are removed only after the model save that deleted their mappings.
    /// If a reference lookup fails, retain the candidate for another save on
    /// this context; launch-time sweeping eventually handles a context that is
    /// no longer active.
    static func removePendingFilesAfterSave(in context: ModelContext) {
        let candidates = takePendingFilesAfterSave(in: context)
        let failedChecks = Set(candidates.filter {
            !CollectionArtworkStore.removeIfUnreferenced($0, in: context)
        })
        cleanupQueue.restore(failedChecks, context: context)
    }

    /// Returns durable cleanup candidates so a caller with expensive directory
    /// work can release the ownership serializer before touching the filesystem.
    static func takePendingFilesAfterSave(in context: ModelContext) -> Set<String> {
        cleanupQueue.take(context: context)
    }

    static func discardPendingFilesAfterRollback(in context: ModelContext) {
        cleanupQueue.discard(context: context)
    }

    private static func delete(_ override: LocalArtworkOverride, in context: ModelContext) {
        cleanupQueue.add(override.filename, context: context)
        context.delete(override)
    }

    static func enqueueFileRemoval(_ filename: String, in context: ModelContext) {
        cleanupQueue.add(filename, context: context)
    }

    private static func isOlder(_ lhs: LocalArtworkOverride, _ rhs: LocalArtworkOverride) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        return lhs.filename < rhs.filename
    }
}

/// Repairs the local half of artwork identity transitions and retires only
/// references that are outside the collection's restore window.
enum ArtworkOrphanSweep {
    struct OverrideSnapshot: Equatable, Sendable {
        let collectionKey: String
        let filename: String
        let updatedAt: Date
    }

    struct Snapshot: Sendable {
        let liveCardKeys: Set<String>
        let canonicalKeysByLegacyKey: [String: Set<String>]
        let overrides: [OverrideSnapshot]
        let recentActivityKeys: Set<String>
        let referencedFilenames: Set<String>
    }

    struct Report: Equatable, Sendable {
        let repairedLegacyAliases: Int
        let removedOverrides: Int
        let removedFiles: Int
    }

    struct CleanupPlan: Equatable, Sendable {
        let repairedLegacyAliases: Int
        let removedOverrides: Int
        let filesToRemove: Set<String>
    }

    /// Captures the full-table read-only inventory away from the ownership
    /// lock. `prepare` re-fetches every candidate it plans to mutate.
    static func snapshot(in container: ModelContainer, now: Date = .now) throws -> Snapshot {
        let context = ModelContext(container)
        let cards = try context.fetch(FetchDescriptor<CollectedCard>())
        let overrides = try context.fetch(FetchDescriptor<LocalArtworkOverride>())
        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
        let liveKeys = Set(cards.map(\.collectionKey))
        var canonicalKeysByLegacyKey: [String: Set<String>] = [:]
        for canonicalKey in liveKeys {
            for legacyKey in MagicTreatmentKeyCodec.legacyCollectionKeys(for: canonicalKey) {
                canonicalKeysByLegacyKey[legacyKey, default: []].insert(canonicalKey)
            }
        }
        let recentActivityKeys = Set(
            activities
                .filter { now.timeIntervalSince($0.occurredAt) <= CollectionActivity.restoreWindow }
                .map(\.collectionKey)
        )
        return Snapshot(
            liveCardKeys: liveKeys,
            canonicalKeysByLegacyKey: canonicalKeysByLegacyKey,
            overrides: overrides.map {
                OverrideSnapshot(
                    collectionKey: $0.collectionKey,
                    filename: $0.filename,
                    updatedAt: $0.updatedAt
                )
            },
            recentActivityKeys: recentActivityKeys,
            referencedFilenames: Set(overrides.map(\.filename))
                .union(cards.compactMap(\.userArtworkFilename))
        )
    }

    /// Compatibility entry point for isolated callers. Production runs
    /// `prepare` inside the writer and performs its returned file cleanup
    /// after releasing the serializer.
    static func run(in context: ModelContext, now: Date = .now) throws -> Report {
        let agedFiles = CollectionArtworkStore.agedFilenames(
            olderThan: now.addingTimeInterval(-24 * 60 * 60)
        )
        let plan = try prepare(
            in: context,
            snapshot: snapshot(in: context.container, now: now),
            agedFileCandidates: agedFiles,
            now: now
        )
        let removedFiles = CollectionArtworkStore.removeFiles(named: plan.filesToRemove)
        return Report(
            repairedLegacyAliases: plan.repairedLegacyAliases,
            removedOverrides: plan.removedOverrides,
            removedFiles: removedFiles
        )
    }

    static func prepare(
        in context: ModelContext,
        snapshot: Snapshot,
        agedFileCandidates: Set<String>,
        now: Date = .now
    ) throws -> CleanupPlan {
        var repairedAliases = 0
        var removedOverrides = 0
        let recentActivityCutoff = now.addingTimeInterval(-CollectionActivity.restoreWindow)
        do {
            let orphanKeys = Set(
                snapshot.overrides
                    .map(\.collectionKey)
                    .filter { !snapshot.liveCardKeys.contains($0) }
            )
            for legacyKey in orphanKeys {
                guard let canonicalKeys = snapshot.canonicalKeysByLegacyKey[legacyKey],
                      canonicalKeys.count == 1,
                      let canonicalKey = canonicalKeys.first,
                      try context.fetchCount(
                        FetchDescriptor<CollectedCard>(
                            predicate: #Predicate { $0.collectionKey == legacyKey }
                        )
                      ) == 0,
                      try context.fetchCount(
                        FetchDescriptor<CollectedCard>(
                            predicate: #Predicate { $0.collectionKey == canonicalKey }
                        )
                      ) > 0 else { continue }
                try LocalArtworkOverrideRekeyer.rekey(
                    from: legacyKey,
                    to: canonicalKey,
                    destinationPolicy: .newestWins,
                    in: context
                )
                repairedAliases += 1
            }

            for candidate in snapshot.overrides
            where !snapshot.liveCardKeys.contains(candidate.collectionKey)
                && !snapshot.recentActivityKeys.contains(candidate.collectionKey)
                && now.timeIntervalSince(candidate.updatedAt) > CollectionActivity.restoreWindow {
                let key = candidate.collectionKey
                let filename = candidate.filename
                let updatedAt = candidate.updatedAt
                guard try context.fetchCount(
                    FetchDescriptor<CollectedCard>(
                        predicate: #Predicate { $0.collectionKey == key }
                    )
                ) == 0,
                      try context.fetchCount(
                        FetchDescriptor<CollectionActivity>(
                            predicate: #Predicate {
                                $0.collectionKey == key
                                    && $0.occurredAt > recentActivityCutoff
                            }
                        )
                      ) == 0 else { continue }
                let currentOverrides = try context.fetch(
                    FetchDescriptor<LocalArtworkOverride>(
                        predicate: #Predicate { $0.collectionKey == key }
                    )
                )
                guard let current = currentOverrides.first(where: {
                    $0.filename == filename && $0.updatedAt == updatedAt
                }) else { continue }
                LocalArtworkOverrideRekeyer.enqueueFileRemoval(current.filename, in: context)
                context.delete(current)
                removedOverrides += 1
            }

            if context.hasChanges {
                try context.save()
            }
            let pendingCleanupFiles = LocalArtworkOverrideRekeyer.takePendingFilesAfterSave(
                in: context
            )

            let candidateFiles = agedFileCandidates
                .subtracting(snapshot.referencedFilenames)
                .union(pendingCleanupFiles)
            var filesToRemove = Set<String>()
            let candidateFilenameList = Array(candidateFiles)
            if !candidateFilenameList.isEmpty {
                let currentOverrideFilenames = Set(
                    try context.fetch(
                        FetchDescriptor<LocalArtworkOverride>(
                            predicate: #Predicate {
                                candidateFilenameList.contains($0.filename)
                            }
                        )
                    ).map(\.filename)
                )
                let currentLegacyFilenames = Set(
                    try context.fetch(
                        FetchDescriptor<CollectedCard>(
                            predicate: #Predicate {
                                $0.userArtworkFilename != nil
                            }
                        )
                    ).compactMap(\.userArtworkFilename)
                    .filter(candidateFiles.contains)
                )
                filesToRemove = candidateFiles.subtracting(currentOverrideFilenames)
                    .subtracting(currentLegacyFilenames)
            }
            return CleanupPlan(
                repairedLegacyAliases: repairedAliases,
                removedOverrides: removedOverrides,
                filesToRemove: filesToRemove
            )
        } catch {
            context.rollback()
            LocalArtworkOverrideRekeyer.discardPendingFilesAfterRollback(in: context)
            throw error
        }
    }
}

enum CollectionVariantCorrectionMode: Equatable, Sendable {
    case visibleCorrection
    case quietBackfill
}

struct CollectionVariantCorrectionClaim: Equatable, Sendable {
    let activityID: UUID
    let quantity: Int
}

/// Owns the scanner's durable writes on a SwiftData model actor.
///
/// The scanner view model is deliberately main-actor isolated because it owns
/// presentation and recognition state. This actor owns the context used for
/// collection identity lookup, price staging, inventory/activity writes, undo,
/// and variant correction. Only value snapshots and `CollectionMutation` cross
/// the boundary; no SwiftData model object is returned to the view model.
@ModelActor
actor ScannerCollectionWriter {
    #if DEBUG
    private var saveOverrideForTesting: (@Sendable () throws -> Void)?

    func setSaveOverrideForTesting(_ override: (@Sendable () throws -> Void)?) {
        saveOverrideForTesting = override
    }
    #endif

    private func performOwnershipWrite<T>(
        _ body: (ModelContext) throws -> T
    ) throws -> T {
        try CollectionWriteSerializer.perform(
            container: modelContext.container,
            timeout: .wait,
            body
        )
    }

    func add(_ candidate: CollectionCommitCandidate) throws -> CollectionMutation {
        let persistenceID = PerformanceSignpost.makeID()
        let signpostState = PerformanceSignpost.beginInterval(
            "scannerPersistence",
            id: persistenceID,
            "operation=add"
        )
        defer {
            PerformanceSignpost.endInterval("scannerPersistence", signpostState, "operation=add")
        }

        return try performOwnershipWrite { context in
          do {
            let store = CollectionStore(context: context)

            if let slab = candidate.subject.slab {
                switch candidate.gradedOutcome {
                case let .bound(variant):
                    return try store.addGraded(
                        underlying: candidate.card,
                        variant: variant,
                        certificationNumber: slab.certificationNumber,
                        setReleaseOrder: candidate.card.setReleaseOrder,
                        pokemonPrintRun: candidate.pokemonPrintRun,
                        identityResolution: candidate.identityResolution,
                        resolved: candidate.resolved
                    )
                case .cardNotTracked, .noGradedListings, .gradeNotTracked,
                     .unavailable, .none:
                    let mutation = try store.addScannedGraded(
                        underlying: candidate.card,
                        company: slab.company,
                        grade: slab.grade,
                        certificationNumber: slab.certificationNumber,
                        setReleaseOrder: candidate.card.setReleaseOrder,
                        pokemonPrintRun: candidate.pokemonPrintRun,
                        identityResolution: candidate.identityResolution,
                        resolved: candidate.resolved,
                        savesChanges: false
                    )
                    try saveModelContext(context)
                    store.invalidateIdentityAliasCache()
                    return mutation
                }
            }

            // Resolve/import aliases before deriving the price key. Imported rows
            // deliberately keep their local identity while catalog normalization
            // may have found a canonical provider id; staging first could write the
            // quote under the obsolete synthetic key and lose lineage on re-import.
            let mutation = try store.add(
                candidate.card,
                resolved: candidate.resolved,
                source: .scan,
                pokemonPrintRun: candidate.pokemonPrintRun,
                identityResolution: candidate.identityResolution,
                matchCatalogAliases: true,
                savesChanges: false,
                signpostID: persistenceID
            )
            guard let stored = try store.card(forAnyKey: mutation.collectionKey) else {
                throw CollectionStoreError.missingDestinationRow(mutation.collectionKey)
            }
            // Both add and correction use the same staging gate: a lookup with
            // no provider observation must leave the price ledger untouched.
            stagePrice(candidate.price, for: stored, in: context)
            try saveModelContext(context)
            return mutation
          } catch {
            // The staged add, ledger event, activity and price write are one
            // transaction from the writer's perspective. In particular, a
            // failed final save must not leave the context carrying the add
            // into the next successful scan.
            context.rollback()
            throw error
          }
        }
    }

    func containsCollectionEntry(for candidate: CollectionCommitCandidate) throws -> Bool {
        try performOwnershipWrite { context in
            let baseKey = candidate.card.collectionKey(variant: candidate.resolved.variant)
            let key = candidate.pokemonPrintRun.map {
                "\(baseKey)@\($0.rawValue)"
            } ?? baseKey
            return CollectionStore(context: context).card(forKey: key) != nil
        }
    }

    /// A newly scanned slab is a plain ownership insert. Only the uncommon
    /// case that merges into an existing unbound slab needs the price-identity
    /// migration gate before `addGraded` promotes its vendor identity.
    func requiresPriceIdentityExclusivity(
        for candidate: CollectionCommitCandidate
    ) -> Bool {
        guard let slab = candidate.subject.slab else { return false }
        let treatmentIDs = MagicTreatmentKeyCodec.storedIDs(
            from: candidate.card.unambiguousMagicTreatments
        )
        if PriceIdentityWritePreflight.requiresScannedGradedVariantRepair(
            container: modelContainer,
            game: candidate.card.game,
            providerID: candidate.card.providerID,
            grade: slab.grade,
            company: slab.company,
            certificationNumber: slab.certificationNumber,
            treatmentIDs: treatmentIDs,
            toVariantID: candidate.resolved.variant?.id
        ) { return true }
        guard let outcome = candidate.gradedOutcome,
              case .bound = outcome else { return false }
        return PriceIdentityWritePreflight.requiresGradedPromotion(
            container: modelContainer,
            game: candidate.card.game,
            providerID: candidate.card.providerID,
            grade: slab.grade,
            company: slab.company,
            certificationNumber: slab.certificationNumber,
            treatmentIDs: treatmentIDs
        )
    }

    func requiresPriceIdentityExclusivity(
        forRawConversion scan: RecentScan,
        evidence: GradedSlabEvidence
    ) -> Bool {
        PriceIdentityWritePreflight.requiresScannedGradedVariantRepair(
            container: modelContainer,
            game: scan.card.game,
            providerID: scan.card.providerID,
            grade: evidence.grade,
            company: evidence.company,
            certificationNumber: evidence.certificationNumber,
            treatmentIDs: MagicTreatmentKeyCodec.storedIDs(
                from: scan.card.unambiguousMagicTreatments
            ),
            toVariantID: scan.resolved.variant?.id
        )
    }

    func requiresGradedVariantIdentityRewrite(
        forCollectionKey collectionKey: String,
        toVariantID: String?
    ) -> Bool {
        PriceIdentityWritePreflight.requiresGradedVariantIdentityRewrite(
            container: modelContainer,
            collectionKey: collectionKey,
            toVariantID: toVariantID
        )
    }

    func requiresGradedBindingPromotion(for collectionKey: String) -> Bool {
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<CollectedCard>(
            predicate: #Predicate { $0.collectionKey == collectionKey }
        )
        descriptor.fetchLimit = 1
        guard let rows = try? context.fetch(descriptor),
              let row = rows.first else { return false }
        return row.itemKind == .gradedCard && row.justTCGVariantID == nil
    }


    func refineGradedCertification(
        for scan: RecentScan,
        to evidence: GradedSlabEvidence
    ) throws -> CollectionMutation? {
        guard let certificationNumber = evidence.certificationNumber else { return nil }
        return try performOwnershipWrite { context in
            try CollectionStore(context: context).recordGradedCertificationRefinement(
                underlying: scan.card,
                previous: scan.mutation,
                company: evidence.company,
                grade: evidence.grade,
                certificationNumber: certificationNumber
            )
        }
    }

    /// Replaces one raw scanner acquisition with its graded identity in one
    /// model-context save. Both inverses and the graded acquisition are staged
    /// together so a failure cannot leave the card missing or double counted.
    func convertRawScanToGraded(
        _ scan: RecentScan,
        evidence: GradedSlabEvidence
    ) throws -> CollectionMutation {
        guard scan.subject.slab == nil else {
            throw CollectionStoreError.ledgerConflict("scan is already graded")
        }
        return try performOwnershipWrite { context in
          do {
            let store = CollectionStore(context: context)
            try store.undo(scan.mutation, savesChanges: false)
            let mutation = try store.addScannedGraded(
                underlying: scan.card,
                company: evidence.company,
                grade: evidence.grade,
                certificationNumber: evidence.certificationNumber,
                setReleaseOrder: scan.card.setReleaseOrder,
                pokemonPrintRun: scan.pokemonPrintRun,
                identityResolution: .catalogSelected,
                resolved: scan.resolved,
                savesChanges: false
            )
            try saveModelContext(context)
            store.invalidateIdentityAliasCache()
            return mutation
        } catch {
            context.rollback()
            throw error
          }
        }
    }

    /// Resolves and binds a committed unbound slab after the acquisition has
    /// already been saved. The current collection key is supplied by the view
    /// model after any certificate refinement has completed.
    func bindScannedGraded(
        collectionKey: String,
        variant: GradedVariant
    ) throws -> GradedVariantBindingReceipt? {
        return try performOwnershipWrite { context in
          do {
            let collectionStore = CollectionStore(context: context)
            guard let row = try collectionStore.card(forAnyKey: collectionKey),
                  row.itemKind == .gradedCard else { return nil }
            let priceStore = PriceStore(context: context)
            let receipt = try GradedVariantBinding.apply(
                variant,
                to: row,
                store: priceStore,
                context: context,
                variantID: row.variantID,
                treatmentIDs: row.priceTreatmentIDs,
                at: .now
            )
            guard receipt.wasAccepted else {
                context.rollback()
                return nil
            }
            try saveModelContext(context)
            collectionStore.invalidateIdentityAliasCache()
            return receipt
          } catch {
            context.rollback()
            throw error
          }
        }
    }

    /// Persists the graded catalogue coverage returned for a committed slab
    /// when its exact market variant is absent.
    @discardableResult
    func recordGradedMarketCoverage(
        collectionKey: String,
        coverage: GradedMarketCoverage,
        at date: Date = .now
    ) throws -> Bool {
        return try performOwnershipWrite { context in
          do {
            let collectionStore = CollectionStore(context: context)
            guard let row = try collectionStore.card(forAnyKey: collectionKey),
                  row.itemKind == .gradedCard else { return false }
            let accepted = PriceStore(context: context).recordGradedMarketCoverage(
                coverage,
                game: row.cardGame,
                printingID: row.priceStorageID,
                variantID: row.variantID,
                at: date,
                treatmentIDs: row.priceTreatmentIDs
            )
            guard accepted else {
                context.rollback()
                return false
            }
            try saveModelContext(context)
            return true
          } catch {
            context.rollback()
            throw error
          }
        }
    }

    private func saveModelContext(_ context: ModelContext) throws {
        #if DEBUG
        if let saveOverrideForTesting {
            self.saveOverrideForTesting = nil
            try saveOverrideForTesting()
            return
        }
        #endif
        try context.save()
    }

    func undo(_ mutation: CollectionMutation) throws {
        let signpostID = PerformanceSignpost.makeID()
        let signpostState = PerformanceSignpost.beginInterval(
            "scannerPersistence",
            id: signpostID,
            "operation=undo"
        )
        defer {
            PerformanceSignpost.endInterval("scannerPersistence", signpostState, "operation=undo")
        }
        try performOwnershipWrite { context in
            try CollectionStore(context: context).undo(mutation)
        }
    }

    func correct(
        card: IdentifiedCard,
        from current: PhysicalVariant?,
        to corrected: ResolvedVariant,
        pokemonPrintRun: PokemonPrintRun?,
        previousCollectionKey: String,
        previousLedgerOperationIDs: [UUID],
        activityID: UUID?,
        quantity: Int,
        price: PriceLookup,
        isGraded: Bool = false
    ) throws -> CollectionMutation? {
        let signpostID = PerformanceSignpost.makeID()
        let signpostState = PerformanceSignpost.beginInterval(
            "scannerPersistence",
            id: signpostID,
            "operation=correct"
        )
        defer {
            PerformanceSignpost.endInterval("scannerPersistence", signpostState, "operation=correct")
        }

        return try performOwnershipWrite { context in
            if !isGraded {
                stagePrice(
                    price,
                    for: card,
                    variant: corrected.variant,
                    pokemonPrintRun: pokemonPrintRun,
                    in: context
                )
            }

            let mutation = try CollectionStore(context: context).recordVariantCorrection(
                for: card,
                from: current,
                to: corrected,
                pokemonPrintRun: pokemonPrintRun,
                previousCollectionKey: previousCollectionKey,
                previousLedgerOperationIDs: previousLedgerOperationIDs,
                activityID: activityID,
                quantity: quantity
            )
            guard mutation != nil else {
                // Price staging happens before correction so a successful correction
                // saves both facts atomically. A missing/stale source must not leave
                // an unsaved price mutation in this call's context for a later scan.
                context.rollback()
                return nil
            }
            return mutation
        }
    }

    private func stagePrice(
        _ lookup: PriceLookup,
        for card: CollectedCard,
        in context: ModelContext
    ) {
        guard lookup.hasObservation else { return }
        PriceStore(context: context).store(
            lookup,
            game: card.cardGame,
            printingID: card.priceStorageID,
            variantID: card.variantID,
            treatmentIDs: card.priceTreatmentIDs
        )
    }

    private func stagePrice(
        _ lookup: PriceLookup,
        for card: IdentifiedCard,
        variant: PhysicalVariant?,
        pokemonPrintRun: PokemonPrintRun?,
        in context: ModelContext
    ) {
        guard lookup.hasObservation else { return }
        let printingID = pokemonPrintRun.map { "\(card.providerID)@\($0.rawValue)" }
            ?? card.providerID
        PriceStore(context: context).store(
            lookup,
            game: card.game,
            printingID: printingID,
            variantID: variant?.id,
            treatmentIDs: MagicTreatmentKeyCodec.storedIDs(
                from: card.magicTreatments(for: variant)
            )
        )
    }
}

/// Read-only checks used to avoid pausing a refresh for ordinary ownership
/// writes. A pause is needed only when an existing unbound market identity is
/// about to move to a vendor-native price key.
enum PriceIdentityWritePreflight {
    static func requiresGradedPromotion(
        container: ModelContainer,
        game: CardGame,
        providerID: String,
        grade: CardGrade,
        company: GradingCompany,
        certificationNumber: String?,
        treatmentIDs: [String]
    ) -> Bool {
        guard let certificationNumber, !certificationNumber.isEmpty else { return false }
        let context = ModelContext(container)
        let certification = certificationNumber
        guard let rows = try? context.fetch(
            FetchDescriptor<CollectedCard>(
                predicate: #Predicate { $0.certificationNumber == certification }
            )
        ) else { return true }
        let expectedTreatments = Set(MagicTreatmentKeyCodec.storedIDs(from: treatmentIDs))
        return rows.contains { row in
            row.itemKind == .gradedCard
                && row.cardGame == game
                && (row.catalogProviderID == providerID || row.providerID == providerID)
                && row.gradingCompany == company
                && row.gradeRaw == grade.value
                && row.gradeLabel == grade.label
                && row.gradingQualifier == grade.qualifier
                && Set(MagicTreatmentKeyCodec.storedIDs(from: row.magicTreatmentIDsRaw))
                    == expectedTreatments
                && row.justTCGVariantID == nil
        }
    }

    static func requiresScannedGradedVariantRepair(
        container: ModelContainer,
        game: CardGame,
        providerID: String,
        grade: CardGrade,
        company: GradingCompany,
        certificationNumber: String?,
        treatmentIDs: [String],
        toVariantID: String?
    ) -> Bool {
        let context = ModelContext(container)
        let expectedTreatments = Set(MagicTreatmentKeyCodec.canonicalIDs(from: treatmentIDs))
        let matchesIdentity: (CollectedCard) -> Bool = { row in
            row.itemKind == .gradedCard
                && row.cardGame == game
                && (row.catalogProviderID == providerID || row.providerID == providerID)
                && row.gradingCompany == company
                && row.gradeRaw == grade.value
                && row.gradeLabel == grade.label
                && row.gradingQualifier == grade.qualifier
                && Set(MagicTreatmentKeyCodec.canonicalIDs(from: row.magicTreatmentIDsRaw))
                    == expectedTreatments
        }
        if let certificationNumber, !certificationNumber.isEmpty {
            let certification = certificationNumber
            guard let rows = try? context.fetch(
                FetchDescriptor<CollectedCard>(
                    predicate: #Predicate { $0.certificationNumber == certification }
                )
            ) else { return true }
            return rows.contains { matchesIdentity($0) && $0.variantID != toVariantID }
        }

        let gradedKind = CollectionItemKind.gradedCard.rawValue
        let companyRaw = company.rawValue
        let gradeValue = grade.value
        guard let rows = try? context.fetch(
            FetchDescriptor<CollectedCard>(
                predicate: #Predicate {
                    $0.itemKindRaw == gradedKind
                        && $0.certificationNumber == nil
                        && $0.gradingCompanyRaw == companyRaw
                        && $0.gradeRaw == gradeValue
                }
            )
        ) else { return true }
        return rows.contains { matchesIdentity($0) && $0.variantID != toVariantID }
    }

    static func requiresGradedVariantIdentityRewrite(
        container: ModelContainer,
        collectionKey: String,
        toVariantID: String?
    ) -> Bool {
        let context = ModelContext(container)
        let directKeys = Array(
            Set([collectionKey] + MagicTreatmentKeyCodec.legacyCollectionKeys(for: collectionKey))
        )
        let canonicalPrefix = collectionKey + "#treatment="
        guard let rows = try? context.fetch(
            FetchDescriptor<CollectedCard>(
                predicate: #Predicate {
                    directKeys.contains($0.collectionKey)
                        || $0.collectionKey.starts(with: canonicalPrefix)
                }
            )
        ) else { return true }
        return rows.contains {
            $0.itemKind == .gradedCard && $0.variantID != toVariantID
        }
    }

    static func requiresSealedPromotion(
        container: ModelContainer,
        game: CardGame,
        productUUID: String,
        variantUUID: String,
        marketVariantID: String?
    ) -> Bool {
        guard marketVariantID != nil else { return false }
        let context = ModelContext(container)
        let key = CollectedCard.sealedCollectionKey(
            game: game,
            productUUID: productUUID,
            variantUUID: variantUUID
        )
        let directKeys = Array(
            Set([key] + MagicTreatmentKeyCodec.legacyCollectionKeys(for: key))
        )
        let canonicalPrefix = key + "#treatment="
        guard let rows = try? context.fetch(
            FetchDescriptor<CollectedCard>(
                predicate: #Predicate {
                    directKeys.contains($0.collectionKey)
                        || $0.collectionKey.starts(with: canonicalPrefix)
                }
            )
        ) else { return true }
        return rows.contains {
            $0.itemKind == .sealedProduct && $0.justTCGVariantID == nil
        }
    }
}

enum CollectionStoreError: Error, Equatable {
    case collectionBusy
    case priceIdentityExclusivityRequired
    case staleQuantity
    case missingDestinationRow(String)
    case missingActivity(UUID)
    case invalidActivity(UUID)
    case activityAlreadyResolved(UUID)
    case missingRemovalSnapshot(UUID)
    case missingLedgerOperation(UUID)
    case invalidLedgerOperation(UUID)
    case ledgerConflict(String)
    case insufficientQuantity(String)
    case quantityOutOfRange(String)
    case restoreConflict(String)
    case staleQuantityDefect(String)
}

extension CollectionStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .collectionBusy:
            return "Your collection is being updated. Try again in a moment."
        case .priceIdentityExclusivityRequired:
            return "The price identity changed while this write was starting. Try again."
        case .staleQuantity:
            return "This quantity changed while you were editing it. Review the current quantity and try again."
        case let .missingDestinationRow(key):
            return "The collection position \(key) is no longer available."
        case let .missingActivity(id):
            return "That history entry \(id.uuidString) is no longer available."
        case let .invalidActivity(id):
            return "That history entry \(id.uuidString) cannot be changed."
        case .activityAlreadyResolved:
            return "That history entry has already been acted on."
        case let .missingRemovalSnapshot(id):
            return "The removal snapshot for history entry \(id.uuidString) is missing."
        case let .missingLedgerOperation(id):
            return "The ledger operation \(id.uuidString) is missing."
        case let .invalidLedgerOperation(id):
            return "The ledger operation \(id.uuidString) is incomplete."
        case let .ledgerConflict(detail):
            return "The ledger could not be changed: \(detail)"
        case let .insufficientQuantity(key):
            return "The current quantity for \(key) is too small for this action."
        case let .quantityOutOfRange(detail):
            return "The quantity is outside the supported range: \(detail)."
        case let .restoreConflict(detail):
            return "This removal cannot be restored: \(detail)."
        case let .staleQuantityDefect(key):
            return "The quantity mismatch for \(key) is no longer current."
        }
    }
}

/// Cache isolation follows the owner of the ModelContext: ProductIdentityIndex
/// is @MainActor because its context is main-actor-owned, PriceRefreshDataIndex
/// stays context-owned, and a cache shared beyond one store value must
/// synchronize itself. This session cache is the last case — its registry
/// shares it by container, so CollectionStore values created for one container
/// see the same aliases even though each value is only a wrapper around the
/// context.
private final class CollectionStoreSession: @unchecked Sendable {
    enum LegacyIdentityLookup: Equatable {
        case resolved(String)
        case noMatch
    }

    private static let capacity = 1_024
    private let lock = NSLock()
    private var lookups: [String: LegacyIdentityLookup] = [:]
    private var usage: [String] = []

    func lookup(for legacyKey: String) -> LegacyIdentityLookup? {
        lock.lock()
        defer { lock.unlock() }
        guard let result = lookups[legacyKey] else { return nil }
        touch(legacyKey)
        return result
    }

    func store(_ result: LegacyIdentityLookup, for legacyKey: String) {
        lock.lock()
        defer { lock.unlock() }
        lookups[legacyKey] = result
        touch(legacyKey)
        while lookups.count > Self.capacity, let oldest = usage.first {
            usage.removeFirst()
            lookups[oldest] = nil
        }
    }

    func invalidate() {
        lock.lock()
        lookups.removeAll(keepingCapacity: true)
        usage.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    private func touch(_ legacyKey: String) {
        usage.removeAll { $0 == legacyKey }
        usage.append(legacyKey)
    }
}

/// Keeps the alias cache session-scoped without making callers thread a
/// reference through every view and service that creates a `CollectionStore`.
/// Weak container entries keep test containers and discarded app sessions from
/// being retained by the registry.
private final class CollectionStoreSessionRegistry: @unchecked Sendable {
    static let shared = CollectionStoreSessionRegistry()

    private final class Entry {
        weak var container: ModelContainer?
        let session: CollectionStoreSession

        init(container: ModelContainer, session: CollectionStoreSession) {
            self.container = container
            self.session = session
        }
    }

    private let lock = NSLock()
    private var entries: [ObjectIdentifier: Entry] = [:]

    func session(for container: ModelContainer) -> CollectionStoreSession {
        lock.lock()
        defer { lock.unlock() }

        entries = entries.filter { $0.value.container != nil }
        let identifier = ObjectIdentifier(container)
        if let entry = entries[identifier], entry.container != nil {
            return entry.session
        }

        let session = CollectionStoreSession()
        entries[identifier] = Entry(container: container, session: session)
        return session
    }
}

/// Reads the detail screen's logical quantity without doing SwiftData fetches
/// on the main actor. Only the value crosses back to the view.
@ModelActor
actor CollectionDetailQuantityReader {
    func logicalQuantity(
        forAnyKey key: String,
        magicTreatmentIDsRaw: [String]
    ) throws -> Int? {
        try CollectionStore(context: modelContext).logicalQuantity(
            forAnyKey: key,
            magicTreatmentIDsRaw: magicTreatmentIDsRaw
        )
    }
}

/// Every write to the collection goes through here.
///
/// Auto-add means mutations now happen without a confirmation step, so the
/// upsert, the undo, and the after-the-fact variant correction have to be one
/// mechanism rather than three lookalike blocks scattered through views.
///
/// Deliberately not `@MainActor`, and for the same reason `InventoryLedger`,
/// `PriceStore`, `PriceObservationLog` and `QuoteCache` are not: the real
/// invariant is *a store may only be used on whatever owns its `ModelContext`*,
/// which main-actor isolation cannot express and only approximates. Annotating
/// it forced CSV import — which owns an isolated context precisely so a large
/// write stays off the main actor — to keep its own transcription of identity
/// merging, and the two copies had already drifted apart. One implementation of
/// the ownership invariant is worth more than an annotation that describes the
/// wrong half of it.
struct CollectionStore {
    let context: ModelContext
    private let session: CollectionStoreSession

    init(context: ModelContext) {
        self.context = context
        self.session = CollectionStoreSessionRegistry.shared.session(for: context.container)
    }

    private static let existingCollectionBackfillVersionKey =
        "collectionActivity.existingCollectionBackfillVersion"
    private static let existingCollectionBackfillVersion = 1

    static func existingCollectionBackfillVersionKey(
        for container: ModelContainer
    ) -> String {
        let identity = container.configurations
            .map { configuration -> String in
                if configuration.isStoredInMemoryOnly {
                    // In-memory stores have no cross-launch identity and must
                    // remain independent inside one test/process.
                    return "memory:\(ObjectIdentifier(container).hashValue)"
                }
                return [
                    configuration.name,
                    configuration.url.standardizedFileURL.path,
                    configuration.cloudKitContainerIdentifier ?? "",
                    String(describing: configuration.cloudKitDatabase)
                ].joined(separator: "|")
            }
            .sorted()
            .joined(separator: "||")
        let encodedIdentity = Data(identity.utf8).base64EncodedString()
        return "\(existingCollectionBackfillVersionKey).store.\(encodedIdentity)"
    }

    private var ledger: InventoryLedger { InventoryLedger(context: context) }

    /// Read-only lineage materialized by a history screen. The write path keeps
    /// its strict per-operation fetches, while presentation can validate every
    /// row against one snapshot of the events already observed by SwiftUI.
    struct LineageIndex {
        let eventsByOperationID: [UUID: [InventoryEvent]]
        let reversedEventIDs: Set<UUID>

        init(events: [InventoryEvent]) {
            self.eventsByOperationID = Dictionary(grouping: events, by: \.operationID)
            self.reversedEventIDs = Set(events.compactMap(\.reversesEventID))
        }
    }

    /// Which flow a source represents.
    ///
    /// The app cannot tell a card bought this morning from one that has been in
    /// a shoebox for ten years, and does not pretend to: both are "added to the
    /// tracked collection" and both belong in the day's reconciliation. Only a
    /// CSV, which explicitly describes a collection that already existed, is
    /// recorded as such. `initialBalance` is reserved for the migration epoch
    /// and is never written here.
    private func inventoryKind(for source: CollectionActivitySource) -> InventoryEventKind {
        source == .csvImport ? .recordExisting : .acquire
    }

    /// Appends history without saving. Callers can therefore stage the activity,
    /// ledger and collection row in one transaction. This is internal rather
    /// than private because CSV import is a service-level write that shares the
    /// store's context and must use the same history path.
    @discardableResult
    func appendActivity(
        _ card: CollectedCard,
        source: CollectionActivitySource,
        kind: CollectionActivityKind,
        deltaQuantity: Int,
        ledgerOperationIDs: [UUID] = [],
        occurredAt: Date = .now,
        removalSnapshot: RemovedCardSnapshot? = nil,
        resolvedQuantity: Int = 0
    ) throws -> CollectionActivity {
        let snapshotData = try removalSnapshot.map { try JSONEncoder().encode($0) }
        let activity = CollectionActivity(
            card: card,
            source: source,
            quantity: abs(deltaQuantity),
            occurredAt: occurredAt,
            kind: kind,
            deltaQuantity: deltaQuantity,
            ledgerOperationIDs: ledgerOperationIDs,
            removalSnapshotData: snapshotData,
            resolvedQuantity: resolvedQuantity
        )
        context.insert(activity)
        return activity
    }

    /// Brings acquisition-only activity rows and collections from older builds
    /// into the history vocabulary. This is intentionally idempotent and saves
    /// once, so opening the history screen cannot create one transaction per row.
    /// The watermark is scoped to this active container. A process-wide claim
    /// would let the first store opened on a device suppress the migration for
    /// a second store or a newly delivered CloudKit store.
    func backfillExistingCollectionIfNeeded(
        defaults: UserDefaults = .standard
    ) throws {
        do {
            let hasLegacyActivities = try context.fetchCount(
                FetchDescriptor<CollectionActivity>(
                    predicate: #Predicate { $0.kindRaw == "" }
                )
            ) > 0
            let watermarkKey = Self.existingCollectionBackfillVersionKey(
                for: context.container
            )
            let hasCompletedWatermark = defaults.integer(
                forKey: watermarkKey
            ) >= Self.existingCollectionBackfillVersion
            let backfillVersion = Self.existingCollectionBackfillVersion
            let cardCount = try context.fetchCount(
                FetchDescriptor<CollectedCard>()
            )
            let activityCount = try context.fetchCount(
                FetchDescriptor<CollectionActivity>()
            )
            let anchoredActivityCount = try context.fetchCount(
                FetchDescriptor<CollectionActivity>(
                    predicate: #Predicate { $0.backfillAnchorCard != nil }
                )
            )
            let hasUncoveredCards = try context.fetchCount(
                FetchDescriptor<CollectedCard>(
                    predicate: #Predicate {
                        $0.activityBackfillVersion < backfillVersion
                            || $0.activityBackfillAnchor == nil
                    }
                )
            ) > 0
            let hasMissingAnchor = anchoredActivityCount < cardCount
            let hasMissingActivity = activityCount < cardCount
            if !hasLegacyActivities,
               hasCompletedWatermark,
               !hasUncoveredCards,
               !hasMissingAnchor,
               !hasMissingActivity {
                return
            }

            let existingActivities = try context.fetch(FetchDescriptor<CollectionActivity>())
            let existingActivityIDs = Set(existingActivities.map(\.id))
            var didChange = false

            for activity in existingActivities {
                if activity.kindRaw.isEmpty {
                    activity.kindRaw = CollectionActivityKind.added.rawValue
                    didChange = true
                }
                if activity.kind == .added, activity.deltaQuantity == 0 {
                    activity.deltaQuantity = activity.quantity
                    didChange = true
                }
            }

            let activitiesByKey = Dictionary(grouping: existingActivities, by: \.collectionKey)
            let cards = try context.fetch(FetchDescriptor<CollectedCard>())
            for card in cards {
                let anchorIsPresent = card.activityBackfillAnchor.map {
                    existingActivityIDs.contains($0.id)
                } ?? false
                guard card.activityBackfillVersion < backfillVersion
                    || !anchorIsPresent else { continue }
                if let existing = activitiesByKey[card.collectionKey]?.first {
                    card.activityBackfillAnchor = existing
                } else {
                    let source: CollectionActivitySource
                    switch card.itemKind {
                    case .sealedProduct:
                        source = .sealedCatalog
                    case .gradedCard:
                        source = .gradedCatalog
                    case .rawCard:
                        switch card.identityResolution {
                        case .imported: source = .csvImport
                        case .printedIdentifier, .userSelectedPrinting: source = .scan
                        case .catalogSelected, .userCorrected, .none: source = .catalog
                        }
                    }
                    let activity = try appendActivity(
                        card,
                        source: source,
                        kind: .added,
                        deltaQuantity: card.quantity,
                        occurredAt: card.dateAdded
                    )
                    card.activityBackfillAnchor = activity
                }
                card.activityBackfillVersion = backfillVersion
                didChange = true
            }

            if didChange { try commit() }
            defaults.set(
                Self.existingCollectionBackfillVersion,
                forKey: watermarkKey
            )
        } catch {
            context.rollback()
            throw error
        }
    }

    func card(forKey key: String) -> CollectedCard? {
        let descriptor = FetchDescriptor<CollectedCard>(
            predicate: #Predicate { $0.collectionKey == key }
        )
        // The projection's rule, not a second one: a read must name the row a
        // write would keep, or the two disagree about which duplicate survives.
        return LogicalCollection.chooseRepresentative(
            from: (try? context.fetch(descriptor)) ?? []
        )
    }

    /// Returns the same merged position quantity that a mutating lookup will
    /// compare and update. This includes duplicate physical rows and supported
    /// legacy aliases, so detail-screen compare-and-set values match writes.
    func logicalQuantity(
        forAnyKey key: String,
        magicTreatmentIDsRaw: [String] = []
    ) throws -> Int? {
        try card(forAnyKey: key, magicTreatmentIDsRaw: magicTreatmentIDsRaw)?.quantity
    }

    private func cards(forKey key: String) throws -> [CollectedCard] {
        try context.fetch(
            FetchDescriptor<CollectedCard>(
                predicate: #Predicate { $0.collectionKey == key }
            )
        )
    }

    private func activities(forKey key: String) throws -> [CollectionActivity] {
        try context.fetch(
            FetchDescriptor<CollectionActivity>(
                predicate: #Predicate { $0.collectionKey == key }
            )
        )
    }

    /// Finds the one treatment-qualified identity that a newer device may have
    /// written into the synced ledger while this device still has the old row.
    /// A legacy finish can map to more than one treatment, so ambiguity is
    /// intentionally left unresolved rather than guessed into the wrong card.
    private func canonicalKeyForLegacyRow(_ legacyKey: String) throws -> String? {
        // Pokémon, sealed, and imported keys cannot have Magic treatment
        // aliases. Avoid fetching the entire ownership ledger for every
        // ordinary scan just to prove that fact.
        guard legacyKey.lowercased().hasPrefix("magic:") else { return nil }
        // Only the treatment-free shape has a canonical counterpart to look
        // for. A key that already carries its own `#treatment=` marker *is* the
        // canonical form, and `legacyCollectionKeys` is non-empty for exactly
        // that case — so this guard asks whether the argument is still legacy.
        guard MagicTreatmentKeyCodec.legacyCollectionKeys(for: legacyKey).isEmpty else {
            return nil
        }
        if let cached = session.lookup(for: legacyKey) {
            switch cached {
            case let .resolved(canonicalKey): return canonicalKey
            case .noMatch: return nil
            }
        }
        // A canonical key is this key with one or more `#treatment=` components
        // spliced in ahead of any legacy Pokémon print-run suffix, so every
        // candidate begins with this prefix. Narrowing on it keeps an ordinary
        // write from materialising three whole tables.
        let canonicalPrefix = String(legacyKey.prefix { $0 != "@" }) + "#treatment="
        let rowKeys = try context.fetch(
            FetchDescriptor<CollectedCard>(
                predicate: #Predicate { $0.collectionKey.starts(with: canonicalPrefix) }
            )
        ).map(\.collectionKey)
        let activityKeys = try context.fetch(
            FetchDescriptor<CollectionActivity>(
                predicate: #Predicate { $0.collectionKey.starts(with: canonicalPrefix) }
            )
        ).map(\.collectionKey)
        let eventKeys = try context.fetch(
            FetchDescriptor<InventoryEvent>(
                predicate: #Predicate { $0.collectionKey.starts(with: canonicalPrefix) }
            )
        ).map(\.collectionKey)
        // The prefix only narrows the search. The codec still decides identity,
        // so a key that merely looks similar can never be adopted.
        let candidates = Set(
            (rowKeys + activityKeys + eventKeys).filter { canonicalKey in
                MagicTreatmentKeyCodec.legacyCollectionKeys(for: canonicalKey)
                    .contains(legacyKey)
            }
        )
        guard candidates.count == 1, let canonicalKey = candidates.first else {
            session.store(.noMatch, for: legacyKey)
            return nil
        }
        session.store(.resolved(canonicalKey), for: legacyKey)
        return canonicalKey
    }

    /// Consolidates the physical rows that represent one logical position.
    ///
    /// CloudKit can legitimately deliver two rows for the same collection key:
    /// each device may have passed its local uniqueness check while offline.
    /// The projection sums those rows, so writes must use the same truth. This
    /// helper makes one deterministic representative, retargets all durable
    /// history and ledger rows, and deletes only the redundant collection rows.
    /// It deliberately does not save; callers can include the merge in the
    /// mutation transaction that caused the lookup.
    private func isBoundVendorPriceAlias(
        _ rows: [CollectedCard],
        priceKeys: Set<String>
    ) -> Bool {
        guard rows.count > 1,
              priceKeys.count == 2,
              let representative = rows.first,
              representative.itemKind != .rawCard,
              rows.allSatisfy({ row in
                  row.collectionKey == representative.collectionKey
                      && row.itemKind == representative.itemKind
                      && row.cardGame == representative.cardGame
                      && row.providerID == representative.providerID
                      && row.variantID == representative.variantID
                      && row.gradingCompanyRaw == representative.gradingCompanyRaw
                      && row.gradeRaw == representative.gradeRaw
                      && row.gradeLabel == representative.gradeLabel
                      && row.gradingQualifier == representative.gradingQualifier
                      && row.certificationNumber == representative.certificationNumber
                      && Set(MagicTreatmentKeyCodec.canonicalIDs(from: row.priceTreatmentIDs))
                          == Set(MagicTreatmentKeyCodec.canonicalIDs(from: representative.priceTreatmentIDs))
              }) else {
            return false
        }

        let boundRows = rows.filter { $0.justTCGVariantID != nil }
        let unboundRows = rows.filter { $0.justTCGVariantID == nil }
        guard !boundRows.isEmpty,
              !unboundRows.isEmpty,
              Set(boundRows.compactMap(\.justTCGVariantID)).count == 1,
              Set(boundRows.map { row in
                  row.justTCGAPIVersion ?? (row.itemKind == .gradedCard ? "v2" : "v1")
              }).count == 1,
              Set(boundRows.map(\.priceKey)).count == 1,
              Set(unboundRows.map(\.priceKey)).count == 1 else {
            return false
        }

        return priceKeys == Set(rows.map(\.priceKey))
    }

    private func mergeCollectionRows(
        _ rows: [CollectedCard],
        canonicalKey: String,
        suppliedTreatmentIDs: [String] = [],
        suppliedTreatmentQualifiers: [String: String] = [:]
    ) throws -> CollectedCard {
        guard let representative = LogicalCollection.chooseRepresentative(from: rows) else {
            throw CollectionStoreError.missingDestinationRow(canonicalKey)
        }

        let sourceKeys = Set(rows.map(\.collectionKey))
        let priceKeys = Set(rows.map(\.priceKey))
        if sourceKeys.count > 1, rows.contains(where: { $0.itemKind == .gradedCard }) {
            // A treatment-qualified graded key can describe a different slab
            // when the certificate/market handle is incomplete. Exact duplicate
            // rows are still safe to consolidate, but a legacy/canonical pair
            // must retain its explicit ambiguity until the slab is enriched.
            throw CollectionStoreError.ledgerConflict(
                "graded collection rows with different identities cannot be merged safely"
            )
        }
        let keyTreatmentIDs = MagicTreatmentKeyCodec.collectionTreatmentIDs(from: canonicalKey)
        let suppliedIDs = MagicTreatmentKeyCodec.storedIDs(from: suppliedTreatmentIDs)
        let representativeIDs = MagicTreatmentKeyCodec.storedIDs(
            from: representative.magicTreatmentIDsRaw
        )
        let finalTreatmentIDs = suppliedIDs.isEmpty
            ? (keyTreatmentIDs.isEmpty ? representativeIDs : keyTreatmentIDs)
            : suppliedIDs
        let finalTreatmentSet = Set(MagicTreatmentKeyCodec.canonicalIDs(from: finalTreatmentIDs))

        // A treatment-qualified Magic row and its treatment-free predecessor
        // intentionally have different price keys until the predecessor is
        // re-read through the canonical treatment. That is a known alias pair,
        // not a conflict. Keep the guard strict for every other combination so
        // two genuinely different price lineages can never be merged merely
        // because their collection keys look similar.
        let isKnownTreatmentAliasPair = sourceKeys.count > 1
            && !finalTreatmentIDs.isEmpty
            && rows.allSatisfy { row in
                row.cardGame == .magic
                    && row.itemKind == .rawCard
                    && row.providerID == representative.providerID
                    && row.variantID == representative.variantID
            }
        let isBoundVendorAlias = isBoundVendorPriceAlias(rows, priceKeys: priceKeys)
        if priceKeys.count > 1 {
            let allowedAliasKeys = isKnownTreatmentAliasPair
                ? Set(rows.flatMap { row in
                    [
                        PriceRecord.key(
                            game: row.cardGame,
                            printingID: row.priceStorageID,
                            variantID: row.variantID
                        ),
                        PriceRecord.key(
                            game: row.cardGame,
                            printingID: row.priceStorageID,
                            variantID: row.variantID,
                            treatmentIDs: finalTreatmentIDs
                        )
                    ]
                })
                : (isBoundVendorAlias ? priceKeys : [])
            guard !allowedAliasKeys.isEmpty, priceKeys.isSubset(of: allowedAliasKeys) else {
                throw CollectionStoreError.ledgerConflict(
                    "duplicate collection rows use different price identities"
                )
            }
        }

        for row in rows {
            let rowIDs = MagicTreatmentKeyCodec.storedIDs(from: row.magicTreatmentIDsRaw)
            let rowSet = Set(MagicTreatmentKeyCodec.canonicalIDs(from: rowIDs))
            guard rowSet.isEmpty || rowSet == finalTreatmentSet else {
                throw CollectionStoreError.ledgerConflict(
                    "stored treatment ids disagree with \(canonicalKey)"
                )
            }
        }

        var finalQualifiers = representative.magicTreatmentQualifiers
        for row in rows {
            for (key, value) in row.magicTreatmentQualifiers
                where finalTreatmentSet.contains(key) {
                if let existing = finalQualifiers[key], existing != value {
                    throw CollectionStoreError.ledgerConflict(
                        "stored treatment qualifier disagrees with \(canonicalKey)"
                    )
                }
                finalQualifiers[key] = value
            }
        }
        for (key, value) in MagicTreatmentKeyCodec.storedQualifiers(
            from: suppliedTreatmentQualifiers
        ) where finalTreatmentSet.contains(key) {
            if let existing = finalQualifiers[key], existing != value {
                throw CollectionStoreError.ledgerConflict(
                    "stored treatment qualifier disagrees with \(canonicalKey)"
                )
            }
            finalQualifiers[key] = value
        }

        // Preserve useful fields when the deterministic representative is the
        // older/less enriched row. The identity key and quantity remain owned by
        // this merge, while optional metadata is filled only when absent.
        for row in rows where row !== representative {
            if representative.providerID.isEmpty { representative.providerID = row.providerID }
            if representative.name.isEmpty { representative.name = row.name }
            if representative.setName.isEmpty { representative.setName = row.setName }
            if representative.setCode.isEmpty { representative.setCode = row.setCode }
            if representative.cardNumber.isEmpty { representative.cardNumber = row.cardNumber }
            if representative.rarity == nil { representative.rarity = row.rarity }
            if representative.imageURL == nil { representative.imageURL = row.imageURL }
            if representative.thumbnailURL == nil { representative.thumbnailURL = row.thumbnailURL }
            if representative.userArtworkFilename == nil {
                representative.userArtworkFilename = row.userArtworkFilename
            }
            if representative.variantID == nil { representative.variantID = row.variantID }
            if representative.variantLabel == nil { representative.variantLabel = row.variantLabel }
            if representative.catalogProviderID == nil {
                representative.catalogProviderID = row.catalogProviderID
            }
            if representative.tcgplayerURL == nil { representative.tcgplayerURL = row.tcgplayerURL }
            if representative.tcgplayerProductID == nil {
                representative.tcgplayerProductID = row.tcgplayerProductID
            }
            if representative.tcgplayerSKUID == nil { representative.tcgplayerSKUID = row.tcgplayerSKUID }
            if representative.justTCGCardID == nil { representative.justTCGCardID = row.justTCGCardID }
            if representative.justTCGVariantID == nil {
                representative.justTCGVariantID = row.justTCGVariantID
            }
            if representative.justTCGAPIVersion == nil {
                representative.justTCGAPIVersion = row.justTCGAPIVersion
            }
            if representative.gradingCompanyRaw == nil {
                representative.gradingCompanyRaw = row.gradingCompanyRaw
            }
            if representative.gradeRaw == nil { representative.gradeRaw = row.gradeRaw }
            if representative.gradeLabel == nil { representative.gradeLabel = row.gradeLabel }
            if representative.gradingQualifier == nil {
                representative.gradingQualifier = row.gradingQualifier
            }
            if representative.certificationNumber == nil {
                representative.certificationNumber = row.certificationNumber
            }
            if representative.marketRegionRaw == nil { representative.marketRegionRaw = row.marketRegionRaw }
            if representative.variantResolutionRaw == nil {
                representative.variantResolutionRaw = row.variantResolutionRaw
            }
            if representative.identityResolutionRaw.isEmpty {
                representative.identityResolutionRaw = row.identityResolutionRaw
            }
            if representative.setReleaseOrder == 0 {
                representative.setReleaseOrder = row.setReleaseOrder
            }
            if representative.itemKindRaw == CollectionItemKind.rawCard.rawValue,
               row.itemKindRaw != CollectionItemKind.rawCard.rawValue {
                representative.itemKindRaw = row.itemKindRaw
            }
            if representative.magicContentKindRaw == MagicContentKind.regular.rawValue,
               row.magicContentKindRaw != MagicContentKind.regular.rawValue {
                representative.magicContentKindRaw = row.magicContentKindRaw
            }
        }
        for sourceKey in sourceKeys {
            try LocalArtworkOverrideRekeyer.rekey(
                from: sourceKey,
                to: canonicalKey,
                in: context
            )
        }
        representative.collectionKey = canonicalKey
        representative.quantity = try rows.reduce(into: 0) { total, row in
            total = try CollectionQuantityLimits.checkedAdd(total, row.quantity)
        }
        representative.dateAdded = rows.map(\.dateAdded).max() ?? representative.dateAdded
        representative.magicTreatmentIDsRaw = finalTreatmentIDs
        representative.magicTreatmentQualifiers = finalQualifiers

        if representative.itemKind == .rawCard,
           representative.variantID == nil,
           let finishID = MagicTreatmentKeyCodec.collectionKeyParts(from: canonicalKey)?.finishID {
            representative.variantID = finishID
            representative.variantLabel = finishID.capitalized
        }

        let allActivities = try sourceKeys.sorted().flatMap { key in
            try activities(forKey: key)
        }
        var rewrittenSnapshots: [(CollectionActivity, Data?)] = []
        rewrittenSnapshots.reserveCapacity(allActivities.count)
        for activity in allActivities {
            let activityIDs = MagicTreatmentKeyCodec.storedIDs(
                from: activity.magicTreatmentIDsRaw
            )
            let activitySet = Set(MagicTreatmentKeyCodec.canonicalIDs(from: activityIDs))
            guard activitySet.isEmpty || activitySet == finalTreatmentSet else {
                throw CollectionStoreError.ledgerConflict(
                    "history treatment ids disagree with \(canonicalKey)"
                )
            }
            var snapshotData: Data?
            if let data = activity.removalSnapshotData {
                guard var snapshot = try? JSONDecoder().decode(
                    RemovedCardSnapshot.self,
                    from: data
                ), sourceKeys.contains(snapshot.collectionKey) || snapshot.collectionKey == canonicalKey else {
                    throw CollectionStoreError.ledgerConflict(
                        "removal snapshot for history entry \(activity.id.uuidString) could not be reconciled"
                    )
                }
                let snapshotIDs = MagicTreatmentKeyCodec.storedIDs(
                    from: snapshot.magicTreatmentIDsRaw ?? []
                )
                let snapshotSet = Set(MagicTreatmentKeyCodec.canonicalIDs(from: snapshotIDs))
                guard snapshotSet.isEmpty || snapshotSet == finalTreatmentSet else {
                    throw CollectionStoreError.ledgerConflict(
                        "removal snapshot treatment ids disagree with \(canonicalKey)"
                    )
                }
                snapshot.collectionKey = canonicalKey
                if snapshotIDs.isEmpty { snapshot.magicTreatmentIDsRaw = finalTreatmentIDs }
                if snapshot.variant == nil, representative.itemKind == .rawCard {
                    snapshot.variant = representative.variant
                }
                if snapshot.magicContentKindRaw == nil,
                   representative.magicContentKindRaw != MagicContentKind.regular.rawValue {
                    snapshot.magicContentKindRaw = representative.magicContentKindRaw
                }
                var snapshotQualifiers = MagicTreatmentKeyCodec.decodeQualifiers(
                    snapshot.magicTreatmentQualifiersJSON
                )
                for (key, value) in finalQualifiers where snapshotQualifiers[key] == nil {
                    snapshotQualifiers[key] = value
                }
                snapshot.magicTreatmentQualifiersJSON =
                    MagicTreatmentKeyCodec.encodeQualifiers(snapshotQualifiers)
                snapshotData = try JSONEncoder().encode(snapshot)
            }
            rewrittenSnapshots.append((activity, snapshotData))
        }

        let events = try sourceKeys.sorted().flatMap { key in
            try context.fetch(
                FetchDescriptor<InventoryEvent>(
                    predicate: #Predicate { $0.collectionKey == key }
                )
            )
        }
        for activity in allActivities {
            activity.collectionKey = canonicalKey
            activity.name = representative.name
            activity.setName = representative.setName
            activity.setCode = representative.setCode
            activity.cardNumber = representative.cardNumber
            activity.variantID = representative.variantID
            activity.variantLabel = representative.variantLabel
            if activity.magicTreatmentIDsRaw.isEmpty {
                activity.magicTreatmentIDsRaw = finalTreatmentIDs
            }
            var activityQualifiers = activity.magicTreatmentQualifiers
            for (key, value) in finalQualifiers where activityQualifiers[key] == nil {
                activityQualifiers[key] = value
            }
            activity.magicTreatmentQualifiersJSON =
                MagicTreatmentKeyCodec.encodeQualifiers(activityQualifiers)
            if activity.magicContentKindRaw == MagicContentKind.regular.rawValue,
               representative.magicContentKindRaw != MagicContentKind.regular.rawValue {
                activity.magicContentKindRaw = representative.magicContentKindRaw
            }
            activity.pokemonPrintRunRaw = representative.pokemonPrintRunRaw
        }
        for (activity, snapshotData) in rewrittenSnapshots where snapshotData != nil {
            activity.removalSnapshotData = snapshotData
        }
        for event in events { event.collectionKey = canonicalKey }

        if representative.itemKind != .rawCard {
            let canonicalPriceKey = representative.priceKey
            for legacyPriceKey in priceKeys where legacyPriceKey != canonicalPriceKey {
                try PriceIdentityLineageMigration.migrate(
                    from: legacyPriceKey,
                    to: canonicalPriceKey,
                    game: representative.cardGame,
                    printingID: representative.priceStorageID,
                    variantID: representative.variantID,
                    treatmentIDs: representative.priceTreatmentIDs,
                    in: context
                )
            }
        }
        for row in rows where row !== representative { context.delete(row) }
        return representative
    }

    /// Resolves a collection row against its canonical identity and every
    /// treatment-free identity that preceded it. A match on a legacy key is
    /// repaired in the same context transaction as the caller's mutation, so
    /// scanning a treated printing increments the old row instead of creating a
    /// second position.
    ///
    /// `magicTreatmentIDsRaw` is supplied by a live provider response when one
    /// exists. When a caller only has a persisted canonical key, the codec can
    /// recover the normalized ids from that key; live ids are preferred because
    /// they preserve the spelling of an unknown future treatment.
    func card(
        forAnyKey canonicalKey: String,
        magicTreatmentIDsRaw suppliedTreatmentIDs: [String] = [],
        resolveLegacyIdentity: Bool = true
    ) throws -> CollectedCard? {
        // Direct ownership lookup is still the common path, but a treatment-free
        // Magic key cannot use an empty result as proof that no position exists.
        // A newer device may already have synced only the treatment-qualified
        // row, leaving no local legacy row for the direct lookup to find. Probe
        // that shape even when `directRows` is empty, or the next scan creates a
        // second position under the old key. Bulk callers can pass
        // `resolveLegacyIdentity: false` after building one projection-wide
        // alias index; that keeps a large import or delete from repeating the
        // three unindexed prefix scans.
        let directKeys = Array(
            Set(
                [canonicalKey]
                    + MagicTreatmentKeyCodec.legacyCollectionKeys(for: canonicalKey)
            )
        )
        let directRows = try directKeys.flatMap(cards(forKey:))
        let shouldProbeLegacyIdentity = MagicTreatmentKeyCodec
            .collectionTreatmentIDs(from: canonicalKey)
            .isEmpty
        let resolvedCanonicalKey = resolveLegacyIdentity && shouldProbeLegacyIdentity
            ? (try canonicalKeyForLegacyRow(canonicalKey) ?? canonicalKey)
            : canonicalKey
        let rows: [CollectedCard]
        if resolvedCanonicalKey == canonicalKey, !directRows.isEmpty {
            rows = directRows
        } else {
            let keys = Array(
                Set(
                    [canonicalKey, resolvedCanonicalKey]
                        + MagicTreatmentKeyCodec.legacyCollectionKeys(for: resolvedCanonicalKey)
                )
            )
            rows = try keys.flatMap(cards(forKey:))
        }
        let requestedTreatmentIDs = try validatedTreatmentIDs(
            for: resolvedCanonicalKey,
            suppliedTreatmentIDs: suppliedTreatmentIDs
        )

        guard !rows.isEmpty else { return nil }
        if rows.count > 1 {
            return try mergeCollectionRows(
                rows,
                canonicalKey: resolvedCanonicalKey,
                suppliedTreatmentIDs: requestedTreatmentIDs
            )
        }
        guard let row = rows.first else { return nil }

        try repairCollectionIdentity(
            row,
            canonicalKey: resolvedCanonicalKey,
            treatmentIDs: requestedTreatmentIDs
        )
        return row
    }

    /// Migration-only rekeying for an exact source row whose old identity is
    /// not one of the safe runtime aliases. The bare `magic:<printingID>` form
    /// is intentionally not a general read-through alias for a selected finish:
    /// a dual-finish printing could represent either physical copy. Slice 8 may
    /// use this method only after exact enrichment has proved the source row's
    /// finish, and the method still performs the same destination, treatment,
    /// activity, snapshot, and ledger checks as ordinary read-through repair.
    func rekey(
        _ row: CollectedCard,
        to canonicalKey: String,
        magicTreatmentIDsRaw suppliedTreatmentIDs: [String] = [],
        magicTreatmentQualifiers suppliedTreatmentQualifiers: [String: String] = [:]
    ) throws -> CollectedCard {
        let sourceRows = try cards(forKey: row.collectionKey)
        guard sourceRows.contains(where: { $0 === row }) else {
            throw CollectionStoreError.ledgerConflict(
                "the migration source row is not uniquely identifiable"
            )
        }
        let destinationRows = try cards(forKey: canonicalKey)
        let requestedTreatmentIDs = try validatedTreatmentIDs(
            for: canonicalKey,
            suppliedTreatmentIDs: suppliedTreatmentIDs
        )

        if row.collectionKey == canonicalKey {
            if sourceRows.count > 1 {
                return try mergeCollectionRows(
                    sourceRows,
                    canonicalKey: canonicalKey,
                    suppliedTreatmentIDs: requestedTreatmentIDs,
                    suppliedTreatmentQualifiers: suppliedTreatmentQualifiers
                )
            } else {
                try repairCollectionIdentity(
                    row,
                    canonicalKey: canonicalKey,
                    treatmentIDs: requestedTreatmentIDs,
                    treatmentQualifiers: suppliedTreatmentQualifiers
                )
            }
            return row
        }

        if !destinationRows.isEmpty {
            return try mergeCollectionRows(
                sourceRows + destinationRows,
                canonicalKey: canonicalKey,
                suppliedTreatmentIDs: requestedTreatmentIDs,
                suppliedTreatmentQualifiers: suppliedTreatmentQualifiers
            )
        }

        guard sourceRows.count == 1 else {
            return try mergeCollectionRows(
                sourceRows,
                canonicalKey: canonicalKey,
                suppliedTreatmentIDs: requestedTreatmentIDs,
                suppliedTreatmentQualifiers: suppliedTreatmentQualifiers
            )
        }
        try repairCollectionIdentity(
            row,
            canonicalKey: canonicalKey,
            treatmentIDs: requestedTreatmentIDs,
            treatmentQualifiers: suppliedTreatmentQualifiers
        )
        return row
    }

    private func validatedTreatmentIDs(
        for canonicalKey: String,
        suppliedTreatmentIDs: [String]
    ) throws -> [String] {
        let keyTreatmentIDs = MagicTreatmentKeyCodec.collectionTreatmentIDs(
            from: canonicalKey
        )
        let requestedTreatmentIDs = suppliedTreatmentIDs.isEmpty
            ? keyTreatmentIDs
            : MagicTreatmentKeyCodec.storedIDs(from: suppliedTreatmentIDs)
        let keyTreatmentSet = Set(MagicTreatmentKeyCodec.canonicalIDs(from: keyTreatmentIDs))
        let requestedTreatmentSet = Set(
            MagicTreatmentKeyCodec.canonicalIDs(from: requestedTreatmentIDs)
        )
        guard keyTreatmentSet == requestedTreatmentSet else {
            throw CollectionStoreError.ledgerConflict(
                "treatment ids do not match canonical collection key \(canonicalKey)"
            )
        }
        return requestedTreatmentIDs
    }

    /// Repairs the row, its durable activity projections, removal snapshots,
    /// and ownership-ledger collection references as one staged identity
    /// operation. Existing price records stay under their original identity;
    /// treatment-bearing rows read through to the same finish's legacy price
    /// until an exact provider refresh writes the canonical treatment key.
    private func repairCollectionIdentity(
        _ row: CollectedCard,
        canonicalKey: String,
        treatmentIDs requestedTreatmentIDs: [String],
        treatmentQualifiers suppliedTreatmentQualifiers: [String: String] = [:]
    ) throws {
        let oldKey = row.collectionKey
        let existingTreatmentIDs = MagicTreatmentKeyCodec.storedIDs(
            from: row.magicTreatmentIDsRaw
        )
        let requestedTreatmentIDs = MagicTreatmentKeyCodec.storedIDs(
            from: requestedTreatmentIDs
        )
        let requestedTreatmentSet = Set(
            MagicTreatmentKeyCodec.canonicalIDs(from: requestedTreatmentIDs)
        )
        let existingTreatmentSet = Set(
            MagicTreatmentKeyCodec.canonicalIDs(from: existingTreatmentIDs)
        )
        guard existingTreatmentSet.isEmpty
                || existingTreatmentSet == requestedTreatmentSet else {
            throw CollectionStoreError.ledgerConflict(
                "stored treatment ids disagree with \(canonicalKey)"
            )
        }
        let finalTreatmentIDs = existingTreatmentIDs.isEmpty
            ? requestedTreatmentIDs
            : existingTreatmentIDs
        let requestedTreatmentQualifiers = MagicTreatmentKeyCodec.storedQualifiers(
            from: suppliedTreatmentQualifiers
        ).filter { requestedTreatmentSet.contains($0.key) }
        let existingTreatmentQualifiers = row.magicTreatmentQualifiers
        for (key, value) in existingTreatmentQualifiers where requestedTreatmentSet.contains(key) {
            if let requested = requestedTreatmentQualifiers[key], requested != value {
                throw CollectionStoreError.ledgerConflict(
                    "stored treatment qualifier disagrees with \(canonicalKey)"
                )
            }
        }
        var finalTreatmentQualifiers = existingTreatmentQualifiers
        for (key, value) in requestedTreatmentQualifiers {
            finalTreatmentQualifiers[key] = value
        }
        let inferredRawFinish: PhysicalVariant? = {
            guard row.itemKind == .rawCard,
                  row.variantID == nil,
                  let finishID = MagicTreatmentKeyCodec
                    .collectionKeyParts(from: canonicalKey)?.finishID else {
                return nil
            }
            return PhysicalVariant(id: finishID, label: finishID.capitalized)
        }()

        let relatedActivities = try activities(forKey: oldKey)
        let activityRewrites = try relatedActivities.map { activity -> (CollectionActivity, Data?) in
            let activityTreatmentIDs = MagicTreatmentKeyCodec.storedIDs(
                from: activity.magicTreatmentIDsRaw
            )
            let activityTreatmentSet = Set(
                MagicTreatmentKeyCodec.canonicalIDs(from: activityTreatmentIDs)
            )
            let finalTreatmentSet = Set(
                MagicTreatmentKeyCodec.canonicalIDs(from: finalTreatmentIDs)
            )
            guard activityTreatmentSet.isEmpty
                    || activityTreatmentSet == finalTreatmentSet else {
                throw CollectionStoreError.ledgerConflict(
                    "history treatment ids disagree with \(canonicalKey)"
                )
            }
            let activityQualifiers = activity.magicTreatmentQualifiers
            for (key, value) in activityQualifiers where finalTreatmentSet.contains(key) {
                if let requested = finalTreatmentQualifiers[key], requested != value {
                    throw CollectionStoreError.ledgerConflict(
                        "history treatment qualifier disagrees with \(canonicalKey)"
                    )
                }
            }

            guard let data = activity.removalSnapshotData else {
                return (activity, nil)
            }
            guard var snapshot = try? JSONDecoder().decode(
                RemovedCardSnapshot.self,
                from: data
            ) else {
                throw CollectionStoreError.ledgerConflict(
                    "removal snapshot for history entry \(activity.id.uuidString) could not be decoded"
                )
            }
            guard snapshot.collectionKey == oldKey || snapshot.collectionKey == canonicalKey else {
                throw CollectionStoreError.ledgerConflict(
                    "removal snapshot for history entry \(activity.id.uuidString) points at a different collection key"
                )
            }
            let snapshotTreatmentIDs = MagicTreatmentKeyCodec.storedIDs(
                from: snapshot.magicTreatmentIDsRaw ?? []
            )
            let snapshotTreatmentSet = Set(
                MagicTreatmentKeyCodec.canonicalIDs(from: snapshotTreatmentIDs)
            )
            guard snapshotTreatmentSet.isEmpty
                    || snapshotTreatmentSet == finalTreatmentSet else {
                throw CollectionStoreError.ledgerConflict(
                    "removal snapshot treatment ids disagree with \(canonicalKey)"
                )
            }
            let snapshotQualifiers = MagicTreatmentKeyCodec.decodeQualifiers(
                snapshot.magicTreatmentQualifiersJSON
            )
            for (key, value) in snapshotQualifiers where finalTreatmentSet.contains(key) {
                if let requested = finalTreatmentQualifiers[key], requested != value {
                    throw CollectionStoreError.ledgerConflict(
                        "removal snapshot treatment qualifier disagrees with \(canonicalKey)"
                    )
                }
            }
            snapshot.collectionKey = canonicalKey
            if snapshotTreatmentIDs.isEmpty {
                snapshot.magicTreatmentIDsRaw = finalTreatmentIDs
            }
            if snapshot.magicTreatmentQualifiersJSON == nil {
                snapshot.magicTreatmentQualifiersJSON =
                    MagicTreatmentKeyCodec.encodeQualifiers(finalTreatmentQualifiers)
            } else {
                var snapshotQualifiers = MagicTreatmentKeyCodec.decodeQualifiers(
                    snapshot.magicTreatmentQualifiersJSON
                )
                for (key, value) in finalTreatmentQualifiers where snapshotQualifiers[key] == nil {
                    snapshotQualifiers[key] = value
                }
                snapshot.magicTreatmentQualifiersJSON =
                    MagicTreatmentKeyCodec.encodeQualifiers(snapshotQualifiers)
            }
            if snapshot.variant == nil, row.itemKind == .rawCard {
                snapshot.variant = row.variant ?? inferredRawFinish
            }
            if snapshot.magicContentKindRaw == nil,
               row.magicContentKindRaw != MagicContentKind.regular.rawValue {
                snapshot.magicContentKindRaw = row.magicContentKindRaw
            }
            return (activity, try JSONEncoder().encode(snapshot))
        }

        let oldEvents = try ledger.events(collectionKey: oldKey)

        if row.itemKind == .gradedCard,
           row.justTCGVariantID == nil {
            let oldPriceKey = row.priceKey
            let newPriceKey = PriceRecord.key(
                game: row.cardGame,
                printingID: canonicalKey,
                variantID: row.variantID,
                treatmentIDs: finalTreatmentIDs
            )
            try PriceIdentityLineageMigration.migrate(
                from: oldPriceKey,
                to: newPriceKey,
                game: row.cardGame,
                printingID: canonicalKey,
                variantID: row.variantID,
                treatmentIDs: finalTreatmentIDs,
                in: context
            )
        }

        try LocalArtworkOverrideRekeyer.rekey(
            from: oldKey,
            to: canonicalKey,
            in: context
        )
        row.collectionKey = canonicalKey
        if let inferredRawFinish {
            row.variantID = inferredRawFinish.id
            row.variantLabel = inferredRawFinish.label
        }
        if row.magicTreatmentIDsRaw.isEmpty {
            row.magicTreatmentIDsRaw = finalTreatmentIDs
        }
        if !finalTreatmentQualifiers.isEmpty {
            row.magicTreatmentQualifiers = finalTreatmentQualifiers
        }
        for (activity, snapshotData) in activityRewrites {
            activity.collectionKey = canonicalKey
            activity.variantID = row.variantID
            activity.variantLabel = row.variantLabel
            if activity.magicTreatmentIDsRaw.isEmpty {
                activity.magicTreatmentIDsRaw = finalTreatmentIDs
            }
            var activityQualifiers = activity.magicTreatmentQualifiers
            for (key, value) in finalTreatmentQualifiers where activityQualifiers[key] == nil {
                activityQualifiers[key] = value
            }
            if activityQualifiers != activity.magicTreatmentQualifiers {
                activity.magicTreatmentQualifiersJSON =
                    MagicTreatmentKeyCodec.encodeQualifiers(activityQualifiers)
            }
            if activity.magicContentKindRaw == MagicContentKind.regular.rawValue,
               row.magicContentKindRaw != MagicContentKind.regular.rawValue {
                activity.magicContentKindRaw = row.magicContentKindRaw
            }
            if let snapshotData {
                activity.removalSnapshotData = snapshotData
            }
        }
        for event in oldEvents where oldKey != canonicalKey {
            // This is an ownership-identity repair only. Keeping the old
            // priceStorageKey preserves the historical observation; the
            // repaired card reads through it until an exact treatment refresh
            // writes the canonical price key.
            event.collectionKey = canonicalKey
        }
    }

    private func activity(id: UUID) throws -> CollectionActivity {
        let descriptor = FetchDescriptor<CollectionActivity>(
            predicate: #Predicate { $0.id == id }
        )
        let matches = try context.fetch(descriptor)
        guard matches.count == 1, let match = matches.first else {
            throw CollectionStoreError.missingActivity(id)
        }
        return match
    }

    /// Checks a complete lineage before any collection or activity mutation is
    /// staged. Corrections must have both legs and an operation may not already
    /// have an inverse.
    private func preflightLineage(
        _ operationIDs: [UUID],
        expectedCollectionKey: String? = nil,
        expectedQuantity: Int? = nil
    ) throws -> [(UUID, [InventoryEvent])] {
        var eventsByOperationID: [UUID: [InventoryEvent]] = [:]
        var reversedEventIDs: Set<UUID> = []
        for operationID in operationIDs {
            let events = try ledger.events(forOperationID: operationID)
            for event in events {
                let reversals = try ledger.reversalEvents(forEventID: event.eventID)
                if !reversals.isEmpty {
                    reversedEventIDs.insert(event.eventID)
                }
            }
            eventsByOperationID[operationID] = events
        }

        return try Self.validateLineage(
            operationIDs,
            eventsByOperationID: eventsByOperationID,
            reversedEventIDs: reversedEventIDs,
            expectedCollectionKey: expectedCollectionKey,
            expectedQuantity: expectedQuantity
        )
    }

    private static func validateLineage(
        _ operationIDs: [UUID],
        eventsByOperationID: [UUID: [InventoryEvent]],
        reversedEventIDs: Set<UUID>,
        expectedCollectionKey: String? = nil,
        expectedQuantity: Int? = nil
    ) throws -> [(UUID, [InventoryEvent])] {
        guard !operationIDs.isEmpty, Set(operationIDs).count == operationIDs.count else {
            throw CollectionStoreError.invalidLedgerOperation(UUID())
        }

        let lineage = try operationIDs.map { operationID in
            guard let events = eventsByOperationID[operationID], !events.isEmpty else {
                throw CollectionStoreError.missingLedgerOperation(operationID)
            }
            guard events.allSatisfy({ $0.kind != .initialBalance }) else {
                throw CollectionStoreError.invalidLedgerOperation(operationID)
            }

            let correctionLegs = Set(events.compactMap { $0.leg })
            if events.contains(where: { $0.kind == .correction }) {
                guard events.count == 2,
                      events.allSatisfy({ $0.kind == .correction }),
                      correctionLegs == Set([.from, .to]) else {
                    throw CollectionStoreError.invalidLedgerOperation(operationID)
                }
            } else {
                guard events.count == 1, correctionLegs.isEmpty else {
                    throw CollectionStoreError.invalidLedgerOperation(operationID)
                }
            }

            for event in events {
                guard !reversedEventIDs.contains(event.eventID) else {
                    throw CollectionStoreError.ledgerConflict(
                        "\(operationID.uuidString) was already reversed"
                    )
                }
            }
            return (operationID, events)
        }

        if let expectedCollectionKey, let expectedQuantity {
            guard expectedQuantity > 0 else {
                throw CollectionStoreError.invalidLedgerOperation(UUID())
            }
            let net = lineage.reduce(into: [String: Int]()) { result, item in
                for event in item.1 {
                    result[event.collectionKey, default: 0] += event.deltaQuantity
                }
            }
            guard net[expectedCollectionKey, default: 0] == expectedQuantity,
                  net.allSatisfy({ key, quantity in
                      key == expectedCollectionKey ? quantity == expectedQuantity : quantity == 0
                  }) else {
                throw CollectionStoreError.invalidLedgerOperation(UUID())
            }
        }

        return lineage
    }

    /// Read-only form of the mutation preflight for history controls. Views can
    /// use the exact same validation without reaching into the private write
    /// path or duplicating its reversal checks.
    func hasValidLineage(
        _ operationIDs: [UUID],
        for collectionKey: String,
        quantity: Int
    ) -> Bool {
        (try? preflightLineage(
            operationIDs,
            expectedCollectionKey: collectionKey,
            expectedQuantity: quantity
        )) != nil
    }

    /// Bulk, read-only equivalent used by history rows. It intentionally shares
    /// the same pure validator as the write preflight so disabled actions cannot
    /// drift from the checks a mutation will enforce.
    static func hasValidLineage(
        _ operationIDs: [UUID],
        for collectionKey: String,
        quantity: Int,
        using index: LineageIndex
    ) -> Bool {
        (try? validateLineage(
            operationIDs,
            eventsByOperationID: index.eventsByOperationID,
            reversedEventIDs: index.reversedEventIDs,
            expectedCollectionKey: collectionKey,
            expectedQuantity: quantity
        )) != nil
    }

    /// Removal activities point at their disposal operation, whose sign is the
    /// inverse of an acquisition lineage. Keep this check beside the store's
    /// restore preflight so the disabled reason in the history UI is truthful.
    func hasValidRemovalLineage(_ activity: CollectionActivity) -> Bool {
        guard activity.kind == .removed,
              let data = activity.removalSnapshotData,
              let snapshot = try? JSONDecoder().decode(RemovedCardSnapshot.self, from: data),
              snapshot.collectionKey == activity.collectionKey,
              snapshot.quantity > 0,
              let operationID = snapshot.operationID,
              activity.ledgerOperationIDs == [operationID] else {
            return false
        }

        guard let lineage = try? preflightLineage([operationID]),
              lineage.count == 1,
              lineage[0].1.count == 1 else {
            return false
        }
        let event = lineage[0].1[0]
        return event.kind == .dispose
            && event.collectionKey == activity.collectionKey
            && event.deltaQuantity == -snapshot.quantity
    }

    static func hasValidRemovalLineage(
        _ activity: CollectionActivity,
        using index: LineageIndex
    ) -> Bool {
        guard activity.kind == .removed,
              let data = activity.removalSnapshotData,
              let snapshot = try? JSONDecoder().decode(RemovedCardSnapshot.self, from: data),
              snapshot.collectionKey == activity.collectionKey,
              snapshot.quantity > 0,
              let operationID = snapshot.operationID,
              activity.ledgerOperationIDs == [operationID] else {
            return false
        }

        guard let lineage = try? validateLineage(
            [operationID],
            eventsByOperationID: index.eventsByOperationID,
            reversedEventIDs: index.reversedEventIDs
        ),
        lineage.count == 1,
        lineage[0].1.count == 1 else {
            return false
        }
        let event = lineage[0].1[0]
        return event.kind == .dispose
            && event.collectionKey == activity.collectionKey
            && event.deltaQuantity == -snapshot.quantity
    }

    private func reverseLineage(
        _ lineage: [(UUID, [InventoryEvent])],
        at date: Date = .now
    ) throws -> [UUID] {
        var inverseOperationIDs: [UUID] = []
        for (operationID, events) in lineage.reversed() {
            let inverseOperationID = UUID()
            let outcomes = try ledger.reverseOperation(
                operationID,
                at: date,
                inverseOperationID: inverseOperationID
            )
            guard outcomes.count == events.count else {
                throw CollectionStoreError.missingLedgerOperation(operationID)
            }
            for outcome in outcomes {
                switch outcome {
                case .appended:
                    break
                case .duplicate:
                    throw CollectionStoreError.ledgerConflict(
                        "\(operationID.uuidString) inverse already exists"
                    )
                case let .conflict(defect):
                    throw CollectionStoreError.ledgerConflict(defect.detail)
                case let .unreadableStore(defect):
                    throw CollectionStoreError.ledgerConflict(defect.detail)
                }
            }
            inverseOperationIDs.append(inverseOperationID)
        }
        return inverseOperationIDs
    }

    private func requireAppended(_ outcome: InventoryLedger.WriteOutcome) throws {
        switch outcome {
        case .appended:
            break
        case .duplicate:
            throw CollectionStoreError.ledgerConflict("ledger operation already exists")
        case let .conflict(defect):
            throw CollectionStoreError.ledgerConflict(defect.detail)
        case let .unreadableStore(defect):
            throw CollectionStoreError.ledgerConflict(defect.detail)
        }
    }

    /// Changes a position's quantity while recording the matching ownership
    /// event in the same persistence transaction.
    @discardableResult
    func setQuantity(_ newQuantity: Int, for card: CollectedCard) throws -> Int {
        guard let current = try self.card(
            forAnyKey: card.collectionKey,
            magicTreatmentIDsRaw: card.magicTreatmentIDsRaw
        ) else {
            throw CollectionStoreError.missingDestinationRow(card.collectionKey)
        }
        return try setQuantity(
            newQuantity,
            forCollectionKey: card.collectionKey,
            magicTreatmentIDsRaw: card.magicTreatmentIDsRaw,
            expectedCurrent: current.quantity
        )
    }

    /// Compare-and-set quantity update. The expected value is the quantity the
    /// user actually saw; a newer row is left untouched until they review it.
    @discardableResult
    func setQuantity(
        _ newQuantity: Int,
        forCollectionKey collectionKey: String,
        magicTreatmentIDsRaw: [String] = [],
        expectedCurrent: Int
    ) throws -> Int {
        guard newQuantity >= 1 else { return expectedCurrent }
        guard newQuantity <= CollectionQuantityLimits.maximum else {
            throw CollectionStoreError.quantityOutOfRange(
                "quantity exceeds \(CollectionQuantityLimits.maximum)"
            )
        }

        do {
            guard let target = try self.card(
                forAnyKey: collectionKey,
                magicTreatmentIDsRaw: magicTreatmentIDsRaw
            ) else {
                throw CollectionStoreError.missingDestinationRow(collectionKey)
            }
            guard target.quantity == expectedCurrent else {
                throw CollectionStoreError.staleQuantity
            }
            let delta = newQuantity - target.quantity
            guard delta != 0 else { return target.quantity }
            let operationID = UUID()
            try requireAppended(
                ledger.record(
                    target,
                    kind: .quantityAdjust,
                    source: .correction,
                    deltaQuantity: delta,
                    operationID: operationID
                )
            )
            _ = try appendActivity(
                target,
                source: .correction,
                kind: .quantityAdjusted,
                deltaQuantity: delta,
                ledgerOperationIDs: [operationID]
            )
            target.quantity = newQuantity
            try commit()
            return target.quantity
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Repairs only persisted quantity mismatches. The caller must have already
    /// established that the active defect set contains only collection/ledger
    /// quantity mismatches; activity-projection disagreements are diagnostic
    /// only because this repair cannot reconstruct their missing history.
    /// This method repeats that guard so it is safe to call outside the view as
    /// well.
    static func repairQuantityMismatches(
        _ defects: [LedgerIntegrityDefect],
        in context: ModelContext
    ) throws {
        guard !defects.isEmpty,
              defects.allSatisfy({ $0.reason == .quantityMismatch && $0.canRepairQuantity }) else {
            throw CollectionStoreError.ledgerConflict(
                "quantity repair is not valid for the active defect set"
            )
        }

        do {
            let collectionStore = CollectionStore(context: context)
            let ledger = InventoryLedger(context: context)
            let cards = try context.fetch(FetchDescriptor<CollectedCard>())
            let projection = LogicalCollection.project(cards: cards, ledger: ledger)
            let reading = ledger.read()
            let events = reading.events
            let collectionKeyAliases = LogicalCollection.readThroughAliases(
                projection: projection,
                eventKeys: Set(events.map(\.collectionKey))
            )
            let normalizedEvents = events.map { event -> LedgerEntry in
                var entry = PortfolioEngine.entry(from: event)
                entry.collectionKey = collectionKeyAliases[entry.collectionKey] ?? entry.collectionKey
                return entry
            }
            let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
            let activityDefects = CollectionActivity.integrityDefects(
                activities: activities,
                events: events,
                collectionKeyAliases: collectionKeyAliases
            )
            let activeDefects = reading.defects
                + projection.defects
                + PortfolioEngine.reconcile(
                    projection: projection,
                    events: normalizedEvents
                )
                + activityDefects
            let requestedKeys = Set(
                defects.map { collectionKeyAliases[$0.collectionKey] ?? $0.collectionKey }
            )
            guard !activeDefects.isEmpty,
                  activeDefects.allSatisfy({ $0.reason == .quantityMismatch && $0.canRepairQuantity }),
                  Set(activeDefects.map { $0.collectionKey }) == requestedKeys else {
                throw CollectionStoreError.ledgerConflict(
                    "active integrity defects changed; quantity repair was not applied"
                )
            }
            let ledgerQuantities = events.reduce(into: [String: Int]()) { quantities, event in
                let key = collectionKeyAliases[event.collectionKey] ?? event.collectionKey
                quantities[key, default: 0] += event.deltaQuantity
            }
            let eventPriceKeys = Dictionary(
                grouping: events,
                by: { collectionKeyAliases[$0.collectionKey] ?? $0.collectionKey }
            )
                .compactMapValues { events in
                    events.map { $0.priceStorageKey }.first(where: { !$0.isEmpty })
                }
            let keys = requestedKeys

            for key in keys {
                let collectionQuantity = projection.quantities[key] ?? 0
                let ledgerQuantity = ledgerQuantities[key] ?? 0
                let delta = collectionQuantity - ledgerQuantity
                guard delta != 0 else {
                    throw CollectionStoreError.staleQuantityDefect(key)
                }

                let priceKey = projection.byKey[key]?.priceStorageKey
                    ?? eventPriceKeys[key] ?? key
                guard let card = projection.byKey[key]?.representative else {
                    throw CollectionStoreError.missingDestinationRow(key)
                }
                let operationID = UUID()
                let outcome = ledger.record(
                    collectionKey: key,
                    priceStorageKey: priceKey,
                    valuation: ledger.valuation(forPriceKey: priceKey),
                    kind: .quantityAdjust,
                    source: .correction,
                    deltaQuantity: delta,
                    operationID: operationID
                )
                switch outcome {
                case .appended:
                    _ = try collectionStore.appendActivity(
                        card,
                        source: .correction,
                        kind: .quantityAdjusted,
                        deltaQuantity: delta,
                        ledgerOperationIDs: [operationID]
                    )
                case .duplicate:
                    throw CollectionStoreError.ledgerConflict(
                        "quantity repair operation unexpectedly duplicated"
                    )
                case let .conflict(defect):
                    throw CollectionStoreError.ledgerConflict(defect.detail)
                case let .unreadableStore(defect):
                    throw CollectionStoreError.ledgerConflict(defect.detail)
                }
            }
            try context.save()
            collectionStore.invalidateIdentityAliasCache()
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: - Graded and sealed
    //
    // Both go through their own namespaced key rather than the raw card's, so a
    // slab or a booster box can never share a row, a quantity or a price record
    // with the raw copy of the same printing.

    /// Add one graded slab.
    ///
    /// A slab with a certificate number is one specific physical object and
    /// never stacks — two PSA 10s of the same card are two rows. Without a
    /// certificate they are indistinguishable to the app, so identical grades
    /// aggregate the way raw copies do.
    @discardableResult
    func addGraded(
        underlying card: IdentifiedCard,
        variant: GradedVariant,
        certificationNumber: String?,
        setReleaseOrder: Int? = nil,
        pokemonPrintRun: PokemonPrintRun? = nil,
        identityResolution: IdentityResolution = .catalogSelected,
        resolved: ResolvedVariant = ResolvedVariant(
            variant: nil,
            resolution: .userConfirmed
        )
    ) throws -> CollectionMutation {
        do {
            let magicTreatments = card.unambiguousMagicTreatments
            let magicTreatmentQualifiers = card.variantEvidence.catalogVariants.count == 1
                ? card.magicTreatmentQualifiers(for: card.variantEvidence.catalogVariants[0])
                : [:]
            let key = CollectedCard.gradedCollectionKey(
                game: card.game,
                underlyingPrintingID: card.providerID,
                variantUUID: variant.id,
                certificationNumber: certificationNumber,
                magicTreatments: magicTreatments
            )
            let treatmentIDs = MagicTreatmentKeyCodec.storedIDs(from: magicTreatments)

            if let certificationNumber,
               let existing = try certifiedGradedCard(
                   underlyingProviderID: card.providerID,
                   company: variant.company,
                   grade: variant.grade,
                   certificationNumber: certificationNumber,
                   treatmentIDs: treatmentIDs
               ) {
                var owner = existing
                if let boundVariantID = owner.justTCGVariantID,
                   boundVariantID != variant.id {
                    throw CollectionStoreError.ledgerConflict(
                        "certificate \(certificationNumber) is bound to a different market variant"
                    )
                }
                if owner.justTCGVariantID == nil {
                    owner = try rekey(
                        owner,
                        to: key,
                        magicTreatmentIDsRaw: treatmentIDs,
                        magicTreatmentQualifiers: magicTreatmentQualifiers
                    )
                    try PriceIdentityLineageMigration.promoteUnboundPriceIdentity(
                        for: owner,
                        toMarketVariantID: variant.id,
                        apiVersion: JustTCGV2GradedClient.apiVersion,
                        in: context
                    )
                    owner.justTCGVariantID = variant.id
                    owner.justTCGCardID = variant.cardID
                    owner.justTCGAPIVersion = JustTCGV2GradedClient.apiVersion
                }
                if owner.variantID == nil, resolved.variant != nil {
                    try updateGradedVariantIdentity(
                        on: owner,
                        to: resolved.variant,
                        resolution: resolved.resolution
                    )
                }
                if owner.pokemonPrintRunRaw == nil {
                    owner.pokemonPrintRunRaw = pokemonPrintRun?.rawValue
                }
                markLiveMagicTreatmentMigrationComplete(for: card, on: owner)
                storeMarketPrice(
                    variant.marketPriceUSD,
                    updatedAt: variant.updatedAt,
                    marketVariantID: variant.id,
                    for: owner
                )
                try commit()
                return CollectionMutation(
                    collectionKey: owner.collectionKey,
                    activityID: nil,
                    didInsert: false,
                    wasDuplicate: true
                )
            }

            if certificationNumber == nil,
               let existing = try uniqueCard(
                   forAnyKey: key,
                   magicTreatmentIDsRaw: treatmentIDs
               ) {
            existing.quantity = try CollectionQuantityLimits.checkedAdd(existing.quantity, 1)
            existing.dateAdded = .now
            if existing.magicTreatmentQualifiersJSON == nil {
                existing.magicTreatmentQualifiers = magicTreatmentQualifiers
            }
            if existing.magicContentKind == .regular {
                existing.magicContentKindRaw = card.magicContentKind.rawValue
            }
            if existing.variantID == nil, resolved.variant != nil {
                try updateGradedVariantIdentity(
                    on: existing,
                    to: resolved.variant,
                    resolution: resolved.resolution
                )
            }
            if existing.pokemonPrintRunRaw == nil {
                existing.pokemonPrintRunRaw = pokemonPrintRun?.rawValue
            }
            markLiveMagicTreatmentMigrationComplete(for: card, on: existing)
            storeMarketPrice(
                variant.marketPriceUSD,
                updatedAt: variant.updatedAt,
                marketVariantID: variant.id,
                for: existing
            )
            let operationID = UUID()
            try requireAppended(
                ledger.record(
                    existing,
                    kind: inventoryKind(for: .gradedCatalog),
                    source: .gradedCatalog,
                    deltaQuantity: 1,
                    operationID: operationID
                )
            )
            let activity = try appendActivity(
                existing,
                source: .gradedCatalog,
                kind: .added,
                deltaQuantity: 1,
                ledgerOperationIDs: [operationID]
            )
            try commit()
            return CollectionMutation(
                collectionKey: key,
                activityID: activity.id,
                didInsert: false,
                ledgerOperationIDs: [operationID]
            )
        }

            let row = CollectedCard(
            collectionKey: key,
            game: card.game,
            providerID: key,
            name: card.name,
            setName: card.setName,
            setCode: card.setCode,
            cardNumber: card.cardNumber,
            rarity: card.rarity,
            imageURL: imageURL(for: card),
            thumbnailURL: card.thumbnailImageURL?.absoluteString,
            // A slab has no raw finish. `PhysicalVariant` stays raw-only, and the
            // grade lives in its own fields.
            variant: resolved.variant,
            variantResolution: resolved.resolution,
            identityResolution: identityResolution,
            setReleaseOrder: setReleaseOrder ?? card.setReleaseOrder,
            magicTreatments: magicTreatments,
            magicTreatmentQualifiers: magicTreatmentQualifiers,
            magicContentKind: card.magicContentKind
        )
        row.itemKindRaw = CollectionItemKind.gradedCard.rawValue
        row.justTCGVariantID = variant.id
        // Both handles. Without the card handle a refresh has no way back to
        // this slab: graded variants live only in v2, and v2 finds a card by
        // set and name rather than by the catalog id the row already had.
        row.justTCGCardID = variant.cardID
        row.justTCGAPIVersion = JustTCGV2GradedClient.apiVersion
        row.gradingCompanyRaw = variant.company.rawValue
        row.gradeRaw = variant.grade.value
        row.gradeLabel = variant.grade.label
        row.gradingQualifier = variant.grade.qualifier
        row.certificationNumber = certificationNumber
        row.pokemonPrintRunRaw = pokemonPrintRun?.rawValue
        row.catalogProviderID = card.providerID
        markLiveMagicTreatmentMigrationComplete(for: card, on: row)
        context.insert(row)
        storeMarketPrice(
            variant.marketPriceUSD,
            updatedAt: variant.updatedAt,
            marketVariantID: variant.id,
            for: row
        )
        let operationID = UUID()
        try requireAppended(
            ledger.record(
                row,
                kind: inventoryKind(for: .gradedCatalog),
                source: .gradedCatalog,
                deltaQuantity: 1,
                operationID: operationID
            )
        )
        let activity = try appendActivity(
            row,
            source: .gradedCatalog,
            kind: .added,
            deltaQuantity: 1,
            ledgerOperationIDs: [operationID]
        )
        try commit()
            return CollectionMutation(
                collectionKey: key,
                activityID: activity.id,
                didInsert: true,
                ledgerOperationIDs: [operationID]
            )
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Add a slab whose label is trusted but whose vendor variant has not yet
    /// been bound. The row is still a complete graded object; a later refresh
    /// may attach the vendor handles without changing its ownership identity.
    @discardableResult
    func addScannedGraded(
        underlying card: IdentifiedCard,
        company: GradingCompany,
        grade: CardGrade,
        certificationNumber: String?,
        setReleaseOrder: Int? = nil,
        pokemonPrintRun: PokemonPrintRun? = nil,
        identityResolution: IdentityResolution = .catalogSelected,
        resolved: ResolvedVariant = ResolvedVariant(
            variant: nil,
            resolution: .userConfirmed
        ),
        savesChanges: Bool = true
    ) throws -> CollectionMutation {
        do {
            let magicTreatments = card.unambiguousMagicTreatments
            let magicTreatmentQualifiers = card.variantEvidence.catalogVariants.count == 1
                ? card.magicTreatmentQualifiers(for: card.variantEvidence.catalogVariants[0])
                : [:]
            let key = CollectedCard.scannedGradedCollectionKey(
                game: card.game,
                underlyingPrintingID: card.providerID,
                company: company,
                grade: grade,
                certificationNumber: certificationNumber,
                magicTreatments: magicTreatments
            )
            let treatmentIDs = MagicTreatmentKeyCodec.storedIDs(from: magicTreatments)

            if let certificationNumber,
               let existing = try certifiedGradedCard(
                   underlyingProviderID: card.providerID,
                   company: company,
                   grade: grade,
                   certificationNumber: certificationNumber,
                   treatmentIDs: treatmentIDs
               ) {
                // A bound row is kept bound; an unbound row is already the same
                // physical slab and is deliberately not incremented.
                if existing.variantID == nil, resolved.variant != nil {
                    try updateGradedVariantIdentity(
                        on: existing,
                        to: resolved.variant,
                        resolution: resolved.resolution
                    )
                }
                if existing.pokemonPrintRunRaw == nil {
                    existing.pokemonPrintRunRaw = pokemonPrintRun?.rawValue
                }
                markLiveMagicTreatmentMigrationComplete(for: card, on: existing)
                try commit(savesChanges: savesChanges)
                return CollectionMutation(
                    collectionKey: existing.collectionKey,
                    activityID: nil,
                    didInsert: false,
                    wasDuplicate: true
                )
            }

            if certificationNumber == nil,
               let existing = try uniqueCard(
                   forAnyKey: key,
                   magicTreatmentIDsRaw: treatmentIDs
               ) {
                existing.quantity = try CollectionQuantityLimits.checkedAdd(existing.quantity, 1)
                existing.dateAdded = .now
                if existing.magicTreatmentQualifiersJSON == nil {
                    existing.magicTreatmentQualifiers = magicTreatmentQualifiers
                }
                if existing.variantID == nil, resolved.variant != nil {
                    try updateGradedVariantIdentity(
                        on: existing,
                        to: resolved.variant,
                        resolution: resolved.resolution
                    )
                }
                if existing.pokemonPrintRunRaw == nil {
                    existing.pokemonPrintRunRaw = pokemonPrintRun?.rawValue
                }
                markLiveMagicTreatmentMigrationComplete(for: card, on: existing)
                let operationID = UUID()
                try requireAppended(
                    ledger.record(
                        existing,
                        kind: inventoryKind(for: .gradedCatalog),
                        source: .gradedCatalog,
                        deltaQuantity: 1,
                        operationID: operationID
                    )
                )
                let activity = try appendActivity(
                    existing,
                    source: .gradedCatalog,
                    kind: .added,
                    deltaQuantity: 1,
                    ledgerOperationIDs: [operationID]
                )
                try commit(savesChanges: savesChanges)
                return CollectionMutation(
                    collectionKey: key,
                    activityID: activity.id,
                    didInsert: false,
                    ledgerOperationIDs: [operationID]
                )
            }

            let row = CollectedCard(
                collectionKey: key,
                game: card.game,
                providerID: key,
                name: card.name,
                setName: card.setName,
                setCode: card.setCode,
                cardNumber: card.cardNumber,
                rarity: card.rarity,
                imageURL: imageURL(for: card),
                thumbnailURL: card.thumbnailImageURL?.absoluteString,
                variant: resolved.variant,
                variantResolution: resolved.resolution,
                identityResolution: identityResolution,
                setReleaseOrder: setReleaseOrder ?? card.setReleaseOrder,
                magicTreatments: magicTreatments,
                magicTreatmentQualifiers: magicTreatmentQualifiers,
                magicContentKind: card.magicContentKind
            )
            row.itemKindRaw = CollectionItemKind.gradedCard.rawValue
            row.gradingCompanyRaw = company.rawValue
            row.gradeRaw = grade.value
            row.gradeLabel = grade.label
            row.gradingQualifier = grade.qualifier
            row.certificationNumber = certificationNumber
            row.pokemonPrintRunRaw = pokemonPrintRun?.rawValue
            row.catalogProviderID = card.providerID
            markLiveMagicTreatmentMigrationComplete(for: card, on: row)
            context.insert(row)

            let operationID = UUID()
            try requireAppended(
                ledger.record(
                    row,
                    kind: inventoryKind(for: .gradedCatalog),
                    source: .gradedCatalog,
                    deltaQuantity: 1,
                    operationID: operationID
                )
            )
            let activity = try appendActivity(
                row,
                source: .gradedCatalog,
                kind: .added,
                deltaQuantity: 1,
                ledgerOperationIDs: [operationID]
            )
            try commit(savesChanges: savesChanges)
            return CollectionMutation(
                collectionKey: key,
                activityID: activity.id,
                didInsert: true,
                ledgerOperationIDs: [operationID]
            )
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Refines the certificate on the exact scanner acquisition that produced
    /// a certless graded row. When that row also represents other certless
    /// copies, move only this encounter's ledger-backed unit to the certified
    /// key. This keeps certificate discovery from creating a second collection
    /// entry for the same continuously tracked slab.
    @discardableResult
    func recordGradedCertificationRefinement(
        underlying card: IdentifiedCard,
        previous mutation: CollectionMutation,
        company: GradingCompany,
        grade: CardGrade,
        certificationNumber: String
    ) throws -> CollectionMutation? {
        guard !certificationNumber.isEmpty,
              let activityID = mutation.activityID else { return nil }

        do {
            guard let previous = try self.card(forAnyKey: mutation.collectionKey) else {
                return nil
            }
            let previousKey = previous.collectionKey
            guard previous.itemKind == .gradedCard,
                  previous.certificationNumber == nil,
                  previous.gradingCompany == company,
                  previous.cardGrade == grade else { return nil }

            let activityToRetarget = try activity(id: activityID)
            guard activityToRetarget.collectionKey == previousKey,
                  activityToRetarget.kind.hasQuantityClaim,
                  activityToRetarget.signedQuantity > 0,
                  activityToRetarget.remainingQuantity == 1,
                  activityToRetarget.ledgerOperationIDs == mutation.ledgerOperationIDs,
                  previous.quantity >= 1 else {
                throw CollectionStoreError.invalidActivity(activityID)
            }
            let operationIDs = activityToRetarget.ledgerOperationIDs
            _ = try preflightLineage(
                operationIDs,
                expectedCollectionKey: previousKey,
                expectedQuantity: 1
            )

            let treatments = previous.magicTreatments
            let destinationKey: String
            if let marketVariantID = previous.justTCGVariantID {
                destinationKey = CollectedCard.gradedCollectionKey(
                    game: previous.cardGame,
                    underlyingPrintingID: card.providerID,
                    variantUUID: marketVariantID,
                    certificationNumber: certificationNumber,
                    magicTreatments: treatments
                )
            } else {
                destinationKey = CollectedCard.scannedGradedCollectionKey(
                    game: previous.cardGame,
                    underlyingPrintingID: card.providerID,
                    company: company,
                    grade: grade,
                    certificationNumber: certificationNumber,
                    magicTreatments: treatments
                )
            }

            let existingDestination = try certifiedGradedCard(
                underlyingProviderID: card.providerID,
                company: company,
                grade: grade,
                certificationNumber: certificationNumber,
                treatmentIDs: MagicTreatmentKeyCodec.storedIDs(from: treatments)
            )
            let rowsAtDestination = try cards(forKey: destinationKey)
            if existingDestination == nil, !rowsAtDestination.isEmpty {
                throw CollectionStoreError.ledgerConflict(
                    "graded certification destination is occupied by a different slab"
                )
            }
            guard existingDestination == nil else {
                // The certificate already names a stored physical slab. Undo
                // only this just-added certless acquisition instead of
                // inflating the certified slab's quantity.
                let lineage = try preflightLineage(
                    operationIDs,
                    expectedCollectionKey: previousKey,
                    expectedQuantity: 1
                )
                let inverseOperationIDs = try reverseLineage(lineage)
                try LocalArtworkOverrideRekeyer.rekey(
                    from: previousKey,
                    to: destinationKey,
                    preservingSource: previous.quantity > 1,
                    destinationPolicy: .preserveExisting,
                    in: context
                )
                activityToRetarget.resolvedQuantity += 1
                _ = try appendActivity(
                    previous,
                    source: activityToRetarget.source,
                    kind: .undone,
                    deltaQuantity: -1,
                    ledgerOperationIDs: inverseOperationIDs
                )
                if previous.quantity == 1 {
                    context.delete(previous)
                } else {
                    previous.quantity -= 1
                }
                try commit()
                return CollectionMutation(
                    collectionKey: destinationKey,
                    activityID: nil,
                    didInsert: false,
                    wasDuplicate: true
                )
            }

            let previousPriceStorageKey = ledger.priceStorageKey(for: previous)
            try LocalArtworkOverrideRekeyer.rekey(
                from: previousKey,
                to: destinationKey,
                preservingSource: previous.quantity > 1,
                destinationPolicy: .preserveExisting,
                in: context
            )
            if previous.quantity == 1 {
                context.delete(previous)
            } else {
                previous.quantity -= 1
            }

            let certified = CollectedCard(
                collectionKey: destinationKey,
                game: previous.cardGame,
                providerID: destinationKey,
                name: previous.name,
                setName: previous.setName,
                setCode: previous.setCode,
                cardNumber: previous.cardNumber,
                rarity: previous.rarity,
                imageURL: previous.imageURL,
                thumbnailURL: previous.thumbnailURL,
                variant: previous.variant,
                variantResolution: previous.variantResolution ?? .catalogSilent,
                identityResolution: previous.identityResolution ?? .printedIdentifier,
                setReleaseOrder: previous.setReleaseOrder,
                quantity: 1,
                magicTreatments: treatments,
                magicTreatmentQualifiers: previous.magicTreatmentQualifiers,
                magicContentKind: previous.magicContentKind
            )
            certified.catalogProviderID = previous.catalogProviderID ?? card.providerID
            certified.userArtworkFilename = previous.userArtworkFilename
            certified.pokemonPrintRunRaw = previous.pokemonPrintRunRaw
            certified.tcgplayerURL = previous.tcgplayerURL
            certified.tcgplayerProductID = previous.tcgplayerProductID
            certified.tcgplayerSKUID = previous.tcgplayerSKUID
            certified.catalogMetadataCheckedAt = previous.catalogMetadataCheckedAt
            certified.catalogMetadataVersion = previous.catalogMetadataVersion
            certified.justTCGCardID = previous.justTCGCardID
            certified.justTCGVariantID = previous.justTCGVariantID
            certified.justTCGAPIVersion = previous.justTCGAPIVersion
            certified.itemKindRaw = CollectionItemKind.gradedCard.rawValue
            certified.gradingCompanyRaw = company.rawValue
            certified.gradeRaw = grade.value
            certified.gradeLabel = grade.label
            certified.gradingQualifier = grade.qualifier
            certified.certificationNumber = certificationNumber
            certified.marketRegionRaw = previous.marketRegionRaw
            certified.dateAdded = previous.dateAdded
            certified.magicTreatmentIDsRaw = previous.magicTreatmentIDsRaw
            certified.magicTreatmentQualifiersJSON = previous.magicTreatmentQualifiersJSON
            context.insert(certified)

            let correctionOperationID = UUID()
            let correction = ledger.recordCorrection(
                fromCollectionKey: previousKey,
                fromPriceStorageKey: previousPriceStorageKey,
                toCard: certified,
                source: .correction,
                quantity: 1,
                operationID: correctionOperationID
            )
            try requireAppended(correction.from)
            try requireAppended(correction.to)

            activityToRetarget.collectionKey = destinationKey
            activityToRetarget.name = certified.name
            activityToRetarget.setName = certified.setName
            activityToRetarget.setCode = certified.setCode
            activityToRetarget.cardNumber = certified.cardNumber
            activityToRetarget.variantID = certified.variantID
            activityToRetarget.variantLabel = certified.variantLabel
            activityToRetarget.magicTreatmentIDsRaw = certified.magicTreatmentIDsRaw
            activityToRetarget.magicTreatmentQualifiersJSON = certified.magicTreatmentQualifiersJSON
            activityToRetarget.magicContentKindRaw = certified.magicContentKindRaw
            activityToRetarget.pokemonPrintRunRaw = certified.pokemonPrintRunRaw
            activityToRetarget.correctedAt = .now
            activityToRetarget.ledgerOperationIDs = operationIDs + [correctionOperationID]
            _ = try appendActivity(
                certified,
                source: .correction,
                kind: .corrected,
                deltaQuantity: 0,
                ledgerOperationIDs: [correctionOperationID]
            )
            try commit()

            return CollectionMutation(
                collectionKey: destinationKey,
                activityID: activityToRetarget.id,
                didInsert: mutation.didInsert,
                ledgerOperationIDs: operationIDs + [correctionOperationID]
            )
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Add one sealed product. These aggregate normally — three identical
    /// booster boxes are a quantity of three.
    @discardableResult
    func addSealed(
        _ product: SealedProductSummary,
        game: CardGame
    ) throws -> CollectionMutation {
        do {
            let variantUUID = product.variantID ?? product.id
            let key = CollectedCard.sealedCollectionKey(
                game: game,
                productUUID: product.id,
                variantUUID: variantUUID
            )

            if let existing = try uniqueCard(forAnyKey: key) {
            existing.quantity = try CollectionQuantityLimits.checkedAdd(existing.quantity, 1)
            existing.dateAdded = .now
            if game == .magic {
                existing.magicTreatmentMigrationVersion = MagicTreatmentMigration.currentVersion
            }
            // Re-adding also heals rows saved before sealed artwork support.
            if existing.imageURL == nil {
                existing.imageURL = product.imageURL?.absoluteString
            }
            if existing.justTCGVariantID == nil,
               let marketVariantID = product.variantID {
                try PriceIdentityLineageMigration.promoteUnboundPriceIdentity(
                    for: existing,
                    toMarketVariantID: marketVariantID,
                    apiVersion: JustTCGV1Client.apiVersion,
                    in: context
                )
                existing.justTCGCardID = product.id
                existing.justTCGVariantID = marketVariantID
                existing.justTCGAPIVersion = JustTCGV1Client.apiVersion
            }
            storeMarketPrice(
                product.marketPriceUSD,
                updatedAt: product.updatedAt,
                marketVariantID: product.variantID,
                for: existing
            )
            let operationID = UUID()
            try requireAppended(
                ledger.record(
                    existing,
                    kind: inventoryKind(for: .sealedCatalog),
                    source: .sealedCatalog,
                    deltaQuantity: 1,
                    operationID: operationID
                )
            )
            let activity = try appendActivity(
                existing,
                source: .sealedCatalog,
                kind: .added,
                deltaQuantity: 1,
                ledgerOperationIDs: [operationID]
            )
            try commit()
            return CollectionMutation(
                collectionKey: key,
                activityID: activity.id,
                didInsert: false,
                ledgerOperationIDs: [operationID]
            )
        }

            let row = CollectedCard(
            collectionKey: key,
            game: game,
            providerID: key,
            name: product.name,
            setName: product.setName ?? "",
            // Sealed products are not part of a printed set's numbering, so they
            // carry no set code and no collector number rather than a fabricated
            // one that would collide with real cards.
            setCode: "",
            cardNumber: "",
            rarity: nil,
            imageURL: product.imageURL?.absoluteString,
            thumbnailURL: nil,
            variant: nil,
            variantResolution: .userConfirmed,
            identityResolution: .catalogSelected
        )
        row.itemKindRaw = CollectionItemKind.sealedProduct.rawValue
        row.justTCGCardID = product.id
        row.justTCGVariantID = product.variantID
        row.tcgplayerProductID = product.tcgplayerProductID
        row.justTCGAPIVersion = JustTCGV1Client.apiVersion
        if game == .magic {
            row.magicTreatmentMigrationVersion = MagicTreatmentMigration.currentVersion
        }
        context.insert(row)
        storeMarketPrice(
            product.marketPriceUSD,
            updatedAt: product.updatedAt,
            marketVariantID: product.variantID,
            for: row
        )
        let operationID = UUID()
        try requireAppended(
            ledger.record(
                row,
                kind: inventoryKind(for: .sealedCatalog),
                source: .sealedCatalog,
                deltaQuantity: 1,
                operationID: operationID
            )
        )
        let activity = try appendActivity(
            row,
            source: .sealedCatalog,
            kind: .added,
            deltaQuantity: 1,
            ledgerOperationIDs: [operationID]
        )
        try commit()
            return CollectionMutation(
                collectionKey: key,
                activityID: activity.id,
                didInsert: true,
                ledgerOperationIDs: [operationID]
            )
        } catch {
            context.rollback()
            throw error
        }
    }

    private func imageURL(for card: IdentifiedCard) -> String? {
        switch card {
        case let .pokemon(pokemon, _): return pokemon.image
        case .magic: return card.displayImageURL?.absoluteString
        }
    }

    private func updateGradedVariantIdentity(
        on row: CollectedCard,
        to variant: PhysicalVariant?,
        resolution: VariantResolution
    ) throws {
        let oldPriceKey = row.priceKey
        let printingID = row.priceStorageID
        let treatmentIDs = row.priceTreatmentIDs
        let newPriceKey = PriceRecord.key(
            game: row.cardGame,
            printingID: printingID,
            variantID: variant?.id,
            treatmentIDs: treatmentIDs
        )
        if oldPriceKey != newPriceKey {
            try PriceIdentityRewritePermit.requireForSerializedOwnershipWrite()
            try PriceIdentityLineageMigration.migrate(
                from: oldPriceKey,
                to: newPriceKey,
                game: row.cardGame,
                printingID: printingID,
                variantID: variant?.id,
                treatmentIDs: treatmentIDs,
                in: context
            )
        }
        row.variantID = variant?.id
        row.variantLabel = variant?.label
        row.variantResolutionRaw = resolution.rawValue
    }

    /// Scanner and catalog paths already carry the exact live provider evidence
    /// needed by Magic treatment migration. Stamp those rows so migration stays
    /// reserved for historical and imported rows.
    private func markLiveMagicTreatmentMigrationComplete(
        for card: IdentifiedCard,
        on row: CollectedCard
    ) {
        guard card.game == .magic else { return }
        row.magicTreatmentMigrationVersion = MagicTreatmentMigration.currentVersion
    }

    /// Sealed and graded browse responses already contain the exact variant's
    /// current market observation. Persist it at add time under the exact vendor
    /// variant identity; adding an item must not make the price that was just
    /// shown disappear until a later refresh.
    private func storeMarketPrice(
        _ amount: Double?,
        updatedAt: Date?,
        marketVariantID: String?,
        for card: CollectedCard
    ) {
        guard let amount else { return }
        PriceStore(context: context).store(
            .price(
                NormalizedPrice(
                    unitMarketPriceUSD: amount,
                    currencyCode: "USD",
                    source: .justTCG,
                    sourceVariantID: marketVariantID
                        ?? card.justTCGCardID
                        ?? card.priceStorageID,
                    sourceUpdatedAt: updatedAt,
                    fetchedAt: .now
                )
            ),
            game: card.cardGame,
            printingID: card.priceStorageID,
            variantID: card.variantID,
            marketVariantID: marketVariantID,
            treatmentIDs: card.priceTreatmentIDs
        )
    }

    @discardableResult
    func add(
        _ card: IdentifiedCard,
        resolved: ResolvedVariant,
        source: CollectionActivitySource = .catalog,
        pokemonPrintRun: PokemonPrintRun? = nil,
        identityResolution: IdentityResolution = .printedIdentifier,
        setReleaseOrder: Int? = nil,
        matchCatalogAliases: Bool = false,
        quantity: Int = 1,
        /// Off only for `recordVariantCorrection`, which writes a two-leg
        /// correction group of its own. A correction is a copy moving between
        /// identities, not an acquisition, and recording it as one would put a
        /// card the user already owned into "Added to collection".
        writesInventoryEvent: Bool = true,
        /// False only while a larger ledger-bearing mutation is being staged.
        /// The caller then writes every event and performs the single save.
        savesChanges: Bool = true,
        signpostID: OSSignpostID? = nil
    ) throws -> CollectionMutation {
        // The scan commit's persistence half, which is what a hitch on the tap
        // that dismisses the choice bar would show up in.
        let addID = signpostID ?? PerformanceSignpost.makeID()
        let signpostState = PerformanceSignpost.beginInterval(
            "CollectionStore.add",
            id: addID,
            "source=\(source.rawValue)"
        )
        defer {
            PerformanceSignpost.endInterval(
                "CollectionStore.add",
                signpostState,
                "source=\(source.rawValue)"
            )
        }
        guard quantity > 0, quantity <= CollectionQuantityLimits.maximum else {
            throw CollectionStoreError.insufficientQuantity(card.providerID)
        }
        do {
            let baseKey = card.collectionKey(variant: resolved.variant)
            let key = pokemonPrintRun.map { "\(baseKey)@\($0.rawValue)" } ?? baseKey
            let mutation: CollectionMutation
            let stored: CollectedCard
            let treatmentIDs = MagicTreatmentKeyCodec.storedIDs(
                from: card.magicTreatments(for: resolved.variant)
            )
            let treatmentQualifiers = card.magicTreatmentQualifiers(for: resolved.variant)

            let existing = try uniqueCard(
                forAnyKey: key,
                magicTreatmentIDsRaw: treatmentIDs
            ) ?? (matchCatalogAliases
                ? try catalogAliasCard(
                    providerID: card.providerID,
                    variantID: resolved.variant?.id,
                    pokemonPrintRun: pokemonPrintRun
                )
                : nil)

            if let existing {
                existing.quantity = try CollectionQuantityLimits.checkedAdd(existing.quantity, quantity)
                existing.dateAdded = .now
                // Any row still missing its catalog identity can take the one
                // this scan just resolved. Requiring a synthetic `csv:`
                // provider id here excluded rows imported with a real
                // provider id, which are exactly the rows that never get a
                // catalog identity from normalization either.
                if existing.catalogProviderID == nil {
                    existing.catalogProviderID = card.providerID
                }
                if existing.imageURL == nil {
                    existing.imageURL = imageURL(for: card)
                }
                if existing.thumbnailURL == nil {
                    existing.thumbnailURL = card.thumbnailImageURL?.absoluteString
                }
                if existing.magicTreatmentIDsRaw.isEmpty {
                    existing.magicTreatmentIDsRaw = treatmentIDs
                }
                if existing.magicTreatmentQualifiersJSON == nil {
                    existing.magicTreatmentQualifiers = treatmentQualifiers
                }
                if existing.magicContentKind == .regular {
                    existing.magicContentKindRaw = card.magicContentKind.rawValue
                }
                mutation = CollectionMutation(
                    collectionKey: existing.collectionKey,
                    activityID: nil,
                    didInsert: false
                )
                stored = existing
            } else {
                let inserted = CollectedCard(
                    card: card,
                    resolved: resolved,
                    identityResolution: identityResolution,
                    setReleaseOrder: setReleaseOrder
                )
                // `CollectedCard` can derive the finish-qualified base key, but the
                // independent Pokémon print run is known only at this layer.
                inserted.collectionKey = key
                inserted.pokemonPrintRunRaw = pokemonPrintRun?.rawValue
                inserted.quantity = quantity
                context.insert(inserted)
                mutation = CollectionMutation(collectionKey: key, activityID: nil, didInsert: true)
                stored = inserted
            }

            markLiveMagicTreatmentMigrationComplete(for: card, on: stored)

            if let stamped = PokemonStampedReleaseCatalog.entry(
                providerID: card.providerID,
                variantID: resolved.variant?.id
            ) {
                // The catalog identity still points at the source artwork/number,
                // while the owned object belongs to the separate stamped release.
                // Display and artwork must describe what is physically held.
                stored.setName = "Trick or Trade \(stamped.year)"
                stored.setCode = "TOT\(String(stamped.year).suffix(2))"
                let artwork = JustTCGV1Client.productImageURL(
                    tcgplayerID: stamped.tcgplayerProductID
                )?.absoluteString
                stored.imageURL = artwork
                stored.thumbnailURL = artwork
            }

            let operationID = writesInventoryEvent ? UUID() : nil
            if let operationID {
                try requireAppended(
                    ledger.record(
                        stored,
                        kind: inventoryKind(for: source),
                        source: source,
                        deltaQuantity: quantity,
                        operationID: operationID
                    )
                )
            }
            let activity = try appendActivity(
                stored,
                source: source,
                kind: writesInventoryEvent ? .added : .corrected,
                deltaQuantity: writesInventoryEvent ? quantity : 0,
                ledgerOperationIDs: operationID.map { [$0] } ?? []
            )
            if savesChanges { try commit() }
            return CollectionMutation(
                collectionKey: mutation.collectionKey,
                activityID: activity.id,
                didInsert: mutation.didInsert,
                ledgerOperationIDs: operationID.map { [$0] } ?? []
            )
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Imported entries retain a synthetic storage key after catalog
    /// normalization. The real provider id is still authoritative for deciding
    /// whether a catalog selection is another copy of that same physical object.
    private func catalogAliasCard(
        providerID: String,
        variantID: String?,
        pokemonPrintRun: PokemonPrintRun?
    ) throws -> CollectedCard? {
        // Vendor identity is an indexed equality match, so it belongs in the
        // query rather than in a filter over every row the store has ever held.
        // The finish and print-run rules stay in Swift: `pokemonPrintRun` is a
        // computed view over the stored raw value, which the predicate grammar
        // cannot reach.
        let catalogID: String? = providerID
        let rawCardKind = CollectionItemKind.rawCard.rawValue
        let rows = try context.fetch(
            FetchDescriptor<CollectedCard>(
                predicate: #Predicate {
                    ($0.providerID == providerID || $0.catalogProviderID == catalogID)
                        && $0.itemKindRaw == rawCardKind
                }
            )
        ).filter {
            $0.variantID == variantID
                && (pokemonPrintRun == .unlimited
                    ? ($0.pokemonPrintRun == .unlimited || $0.pokemonPrintRun == nil)
                    : $0.pokemonPrintRun == pokemonPrintRun)
        }
        guard rows.count <= 1 else {
            let keys = Set(rows.map(\.collectionKey))
            guard keys.count == 1, let key = keys.first else {
                throw CollectionStoreError.ledgerConflict(
                    "more than one collection row matches catalog identity \(providerID)"
                )
            }
            return try mergeCollectionRows(rows, canonicalKey: key)
        }
        return rows.first
    }

    private func certifiedGradedCard(
        underlyingProviderID: String,
        company: GradingCompany,
        grade: CardGrade,
        certificationNumber: String,
        treatmentIDs: [String]
    ) throws -> CollectedCard? {
        let gradedRaw = CollectionItemKind.gradedCard.rawValue
        let rows = try context.fetch(
            FetchDescriptor<CollectedCard>(
                predicate: #Predicate {
                    $0.itemKindRaw == gradedRaw
                        && $0.certificationNumber == certificationNumber
                }
            )
        ).filter { row in
            let sharesUnderlyingID = row.catalogProviderID == underlyingProviderID
                || row.providerID == underlyingProviderID
            guard sharesUnderlyingID,
                  row.gradingCompany == company,
                  row.gradeRaw == grade.value,
                  row.gradeLabel == grade.label,
                  row.gradingQualifier == grade.qualifier else { return false }
            return Set(MagicTreatmentKeyCodec.canonicalIDs(from: row.magicTreatmentIDsRaw))
                == Set(MagicTreatmentKeyCodec.canonicalIDs(from: treatmentIDs))
        }
        guard rows.count <= 1 else {
            throw CollectionStoreError.ledgerConflict(
                "certificate \(certificationNumber) matches multiple graded rows"
            )
        }
        return rows.first
    }

    /// Reverses exactly one scan mutation. Every precondition is checked before
    /// the first inverse is staged, and one save commits the ledger, collection
    /// row, and activity together. This is intentionally strict: a stale UI
    /// value must fail and remain retryable, never become a partial undo.
    func undo(_ mutation: CollectionMutation, savesChanges: Bool = true) throws {
        do {
            guard let row = try card(forAnyKey: mutation.collectionKey) else {
                throw CollectionStoreError.missingDestinationRow(mutation.collectionKey)
            }
            // `card(forAnyKey:)` may have repaired a legacy row to the
            // treatment-qualified key inferred from synced ledger events. All
            // lineage checks and the appended inverse must use that repaired
            // key, not the stale in-memory mutation key.
            let collectionKey = row.collectionKey

            guard let activityID = mutation.activityID else {
                throw CollectionStoreError.invalidLedgerOperation(UUID())
            }
            let activity = try activity(id: activityID)
            guard activity.collectionKey == collectionKey else {
                throw CollectionStoreError.missingActivity(activityID)
            }
            guard activity.remainingQuantity >= 1 else {
                throw CollectionStoreError.activityAlreadyResolved(activityID)
            }
            guard row.quantity >= 1 else {
                throw CollectionStoreError.insufficientQuantity(collectionKey)
            }

            let operationIDs = mutation.ledgerOperationIDs
            guard activity.ledgerOperationIDs.isEmpty
                    || activity.ledgerOperationIDs == operationIDs else {
                throw CollectionStoreError.invalidLedgerOperation(UUID())
            }
            let lineage = try preflightLineage(
                operationIDs,
                expectedCollectionKey: collectionKey,
                expectedQuantity: 1
            )
            guard lineage.allSatisfy({ _, events in
                events.allSatisfy { abs($0.deltaQuantity) == 1 }
            }) else {
                throw CollectionStoreError.invalidLedgerOperation(UUID())
            }
            let inverseOperationIDs = try reverseLineage(lineage)

            activity.resolvedQuantity += 1
            _ = try appendActivity(
                row,
                source: activity.source,
                kind: .undone,
                deltaQuantity: -1,
                ledgerOperationIDs: inverseOperationIDs
            )

            if activity.ledgerOperationIDs.isEmpty {
                activity.ledgerOperationIDs = operationIDs
            }

            if row.quantity <= 1 {
                context.delete(row)
            } else {
                row.quantity -= 1
            }
            try commit(savesChanges: savesChanges)
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Removes only the copies represented by one history entry. It is separate
    /// from removing a collection position, which intentionally removes all of
    /// that position.
    @discardableResult
    func remove(
        _ activity: CollectionActivity,
        quantity requestedQuantity: Int? = nil
    ) throws -> RemovedCardSnapshot {
        try remove(activityID: activity.id, quantity: requestedQuantity)
    }

    func remove(
        activityID: UUID,
        quantity requestedQuantity: Int? = nil
    ) throws -> RemovedCardSnapshot {
        do {
            let selectedActivity = try self.activity(id: activityID)
            guard selectedActivity.kind.hasQuantityClaim,
                  selectedActivity.signedQuantity > 0,
                  selectedActivity.claimedQuantity > 0 else {
                throw CollectionStoreError.invalidActivity(selectedActivity.id)
            }
            let quantity = requestedQuantity ?? selectedActivity.remainingQuantity
            guard quantity > 0, quantity == selectedActivity.remainingQuantity else {
                throw CollectionStoreError.activityAlreadyResolved(selectedActivity.id)
            }
            guard let row = try card(forAnyKey: selectedActivity.collectionKey) else {
                throw CollectionStoreError.missingDestinationRow(selectedActivity.collectionKey)
            }
            guard row.quantity >= quantity else {
                throw CollectionStoreError.insufficientQuantity(selectedActivity.collectionKey)
            }
            _ = try preflightLineage(
                selectedActivity.ledgerOperationIDs,
                expectedCollectionKey: selectedActivity.collectionKey,
                expectedQuantity: selectedActivity.claimedQuantity
            )

            var snapshot = RemovedCardSnapshot(card: row, quantity: quantity)
            let operationID = UUID()
            try requireAppended(
                ledger.record(
                    row,
                    kind: .dispose,
                    source: .correction,
                    deltaQuantity: -quantity,
                    operationID: operationID
                )
            )
            snapshot.operationID = operationID
            let removed = try appendActivity(
                row,
                source: .correction,
                kind: .removed,
                deltaQuantity: -quantity,
                ledgerOperationIDs: [operationID],
                removalSnapshot: snapshot
            )
            _ = removed
            selectedActivity.resolvedQuantity += quantity

            if row.quantity == quantity {
                context.delete(row)
            } else {
                row.quantity -= quantity
            }
            try commit()
            return snapshot
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Removes an entire position, preserving the previous snapshot and the
    /// activity rows that explain how each copy entered it.
    func remove(_ card: CollectedCard) throws -> RemovedCardSnapshot {
        try remove(
            collectionKey: card.collectionKey,
            magicTreatmentIDsRaw: card.magicTreatmentIDsRaw
        )
    }

    func remove(
        collectionKey: String,
        magicTreatmentIDsRaw: [String] = []
    ) throws -> RemovedCardSnapshot {
        do {
            guard let row = try self.card(
                forAnyKey: collectionKey,
                magicTreatmentIDsRaw: magicTreatmentIDsRaw
            ) else {
                throw CollectionStoreError.missingDestinationRow(collectionKey)
            }
            let quantity = row.quantity
            var snapshot = RemovedCardSnapshot(card: row)
            let operationID = UUID()
            try requireAppended(
                ledger.record(
                    row,
                    kind: .dispose,
                    source: .correction,
                    deltaQuantity: -quantity,
                    operationID: operationID
                )
            )
            snapshot.operationID = operationID
            _ = try appendActivity(
                row,
                source: .correction,
                kind: .removed,
                deltaQuantity: -quantity,
                ledgerOperationIDs: [operationID],
                removalSnapshot: snapshot
            )

            for activity in try activities(forKey: row.collectionKey)
                where activity.kind.hasQuantityClaim && activity.remainingQuantity > 0 {
                activity.resolvedQuantity = activity.claimedQuantity
            }
            context.delete(row)
            try commit()
            return snapshot
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Restores a removal activity when its snapshot is still current. A row
    /// may remain when sibling copies survived a per-entry removal; the ledger
    /// proves that case safe. A later positive event for the same key is a
    /// re-acquisition and is rejected so restore cannot double the collection.
    func restore(_ activity: CollectionActivity) throws {
        try restore(activityID: activity.id)
    }

    func restore(activityID: UUID) throws {
        let selectedActivity = try self.activity(id: activityID)
        guard selectedActivity.kind == .removed else {
            throw CollectionStoreError.invalidActivity(selectedActivity.id)
        }
        guard let data = selectedActivity.removalSnapshotData,
              let snapshot = try? JSONDecoder().decode(RemovedCardSnapshot.self, from: data) else {
            throw CollectionStoreError.missingRemovalSnapshot(selectedActivity.id)
        }
        try restore(snapshot, removalActivity: selectedActivity)
    }

    /// Compatibility entry point used by the recent-removal banner. Current
    /// snapshots are also represented by a removal activity, so the same
    /// preflight and history append path is used.
    func restore(_ snapshot: RemovedCardSnapshot) throws {
        // Only removal rows carry a removal snapshot, so the kind is a query
        // predicate rather than a decode-everything-then-discard filter. The
        // order is now explicit as well: matching used to depend on whatever
        // the unpredicated fetch returned first, which decided arbitrarily
        // between two removals sharing an id or operation id. Newest-first is
        // the row the undo banner is offering.
        let removedKind = CollectionActivityKind.removed.rawValue
        var removalDescriptor = FetchDescriptor<CollectionActivity>(
            predicate: #Predicate { $0.kindRaw == removedKind }
        )
        removalDescriptor.sortBy = [SortDescriptor(\.occurredAt, order: .reverse)]
        let removalActivity = try context.fetch(removalDescriptor)
            .first { activity in
                guard let data = activity.removalSnapshotData,
                      let stored = try? JSONDecoder().decode(RemovedCardSnapshot.self, from: data)
                else { return false }
                return stored.id == snapshot.id
                    || (snapshot.operationID != nil && stored.operationID == snapshot.operationID)
            }
        if let removalActivity {
            guard let data = removalActivity.removalSnapshotData,
                  let storedSnapshot = try? JSONDecoder().decode(RemovedCardSnapshot.self, from: data) else {
                throw CollectionStoreError.missingRemovalSnapshot(removalActivity.id)
            }
            try restore(storedSnapshot, removalActivity: removalActivity)
        } else {
            try restore(snapshot, removalActivity: nil)
        }
    }

    private func restore(
        _ snapshot: RemovedCardSnapshot,
        removalActivity: CollectionActivity?
    ) throws {
        do {
            var snapshot = snapshot
            if let canonicalKey = try canonicalKeyForLegacyRow(snapshot.collectionKey) {
                snapshot.collectionKey = canonicalKey
                if snapshot.magicTreatmentIDsRaw?.isEmpty ?? true {
                    snapshot.magicTreatmentIDsRaw = MagicTreatmentKeyCodec
                        .collectionTreatmentIDs(from: canonicalKey)
                }
            }
            let existing = try card(
                forAnyKey: snapshot.collectionKey,
                magicTreatmentIDsRaw: snapshot.magicTreatmentIDsRaw ?? []
            )
            guard snapshot.quantity > 0 else {
                throw CollectionStoreError.restoreConflict("snapshot has no copies")
            }
            if existing != nil, removalActivity == nil {
                // A legacy snapshot has no disposal event with which to prove
                // that an existing row is merely a surviving sibling copy.
                // Treat it conservatively as a re-acquisition.
                throw CollectionStoreError.restoreConflict(
                    "\(snapshot.collectionKey) was acquired again"
                )
            }
            if removalActivity != nil, existing != nil {
                // A row can still exist because this removal took only the
                // copies claimed by one entry while sibling copies remained.
                // That is safe to merge back into. A positive ledger event
                // recorded after the disposal, however, proves the position
                // was acquired again and restoring would double it.
                guard let operationID = snapshot.operationID else {
                    throw CollectionStoreError.restoreConflict(
                        "\(snapshot.collectionKey) was acquired again"
                    )
                }
                let removalEvents = try ledger.events(forOperationID: operationID)
                let removalRecordedAt = removalEvents.map(\.recordedAt).max() ?? .distantPast
                let wasReacquired = try ledger.events(collectionKey: snapshot.collectionKey).contains {
                    $0.recordedAt >= removalRecordedAt && $0.deltaQuantity > 0
                }
                guard !wasReacquired else {
                    throw CollectionStoreError.restoreConflict(
                        "\(snapshot.collectionKey) was acquired again"
                    )
                }
            }
            if let removalActivity, let operationID = snapshot.operationID {
                guard removalActivity.ledgerOperationIDs == [operationID] else {
                    throw CollectionStoreError.invalidLedgerOperation(operationID)
                }
            }
            if let removalActivity {
                guard removalActivity.remainingQuantity == removalActivity.claimedQuantity else {
                    throw CollectionStoreError.activityAlreadyResolved(removalActivity.id)
                }
                guard Date.now.timeIntervalSince(removalActivity.occurredAt)
                    <= CollectionActivity.restoreWindow else {
                    throw CollectionStoreError.restoreConflict("removal is outside the restore window")
                }
            } else if let operationID = snapshot.operationID {
                let removalEvents = try ledger.events(forOperationID: operationID)
                let removalRecordedAt = removalEvents.map(\.recordedAt).max() ?? .distantPast
                guard Date.now.timeIntervalSince(removalRecordedAt)
                    <= CollectionActivity.restoreWindow else {
                    throw CollectionStoreError.restoreConflict("removal is outside the restore window")
                }
            }

            var restoredLineage: [UUID] = []
            if let operationID = snapshot.operationID {
                let lineage = try preflightLineage([operationID])
                guard lineage.count == 1,
                      lineage[0].1.count == 1,
                      lineage[0].1[0].kind == .dispose,
                      lineage[0].1[0].collectionKey == snapshot.collectionKey,
                      abs(lineage[0].1[0].deltaQuantity) == snapshot.quantity else {
                    throw CollectionStoreError.invalidLedgerOperation(operationID)
                }
                restoredLineage = try reverseLineage(lineage)
            } else {
                let restoredOperationID = UUID()
                try snapshot.reinsert(in: context)
                guard let row = try card(
                    forAnyKey: snapshot.collectionKey,
                    magicTreatmentIDsRaw: snapshot.magicTreatmentIDsRaw ?? []
                ) else {
                    throw CollectionStoreError.missingDestinationRow(snapshot.collectionKey)
                }
                try requireAppended(
                    ledger.record(
                        row,
                        kind: .recordExisting,
                        source: .correction,
                        deltaQuantity: snapshot.quantity,
                        operationID: restoredOperationID
                    )
                )
                restoredLineage = [restoredOperationID]
            }

            if snapshot.operationID != nil {
                try snapshot.reinsert(in: context)
            }
            guard let restoredCard = try card(
                forAnyKey: snapshot.collectionKey,
                magicTreatmentIDsRaw: snapshot.magicTreatmentIDsRaw ?? []
            ) else {
                throw CollectionStoreError.missingDestinationRow(snapshot.collectionKey)
            }
            _ = try appendActivity(
                restoredCard,
                source: .correction,
                kind: .restored,
                deltaQuantity: snapshot.quantity,
                ledgerOperationIDs: restoredLineage
            )
            if let removalActivity {
                removalActivity.resolvedQuantity = removalActivity.claimedQuantity
            }
            try commit()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func uniqueCard(forKey key: String) throws -> CollectedCard? {
        let rows = try cards(forKey: key)
        guard rows.count > 1 else { return rows.first }
        return try mergeCollectionRows(rows, canonicalKey: key)
    }

    private func uniqueCard(
        forAnyKey key: String,
        magicTreatmentIDsRaw: [String] = []
    ) throws -> CollectedCard? {
        try card(
            forAnyKey: key,
            magicTreatmentIDsRaw: magicTreatmentIDsRaw
        )
    }

    /// Removes every owned card while leaving catalog and price data alone.
    /// Each position gets its own snapshot and history row, while the whole
    /// destructive action still commits once.
    @discardableResult
    func deleteAll(
        shouldContinue: StorageGenerationContinuation? = nil
    ) throws -> Bool {
        do {
            guard shouldContinue?() ?? true else { return false }
            let physicalCards = try context.fetch(FetchDescriptor<CollectedCard>())
            let projection = LogicalCollection.project(cards: physicalCards, ledger: ledger)
            let collectionKeyAliases = LogicalCollection.readThroughAliases(
                projection: projection,
                eventKeys: Set(ledger.read().events.map(\.collectionKey))
            )
            let occurredAt = Date.now
            for position in projection.positions {
                guard shouldContinue?() ?? true else {
                    context.rollback()
                    return false
                }
                // If another device already rekeyed the ledger, address the
                // position through that canonical key so the row is repaired as
                // part of this deletion. This also keeps delete-all from
                // invoking the per-row legacy prefix probe for every card.
                let writeKey = collectionKeyAliases.first {
                    $0.value == position.collectionKey
                }?.key ?? position.collectionKey
                guard let card = try self.card(
                    forAnyKey: writeKey,
                    magicTreatmentIDsRaw: position.representative.magicTreatmentIDsRaw,
                    // `readThroughAliases` above is the bulk identity index
                    // for this destructive operation. Avoid rebuilding the
                    // prefix-scan alias search for every position.
                    resolveLegacyIdentity: false
                ) else {
                    throw CollectionStoreError.missingDestinationRow(position.collectionKey)
                }
                let quantity = card.quantity
                var snapshot = RemovedCardSnapshot(card: card)
                let operationID = UUID()
                try requireAppended(
                    ledger.record(
                        card,
                        kind: .dispose,
                        source: .correction,
                        deltaQuantity: -quantity,
                        operationID: operationID,
                        occurredAt: occurredAt
                    )
                )
                snapshot.operationID = operationID
                _ = try appendActivity(
                    card,
                    source: .correction,
                    kind: .removed,
                    deltaQuantity: -quantity,
                    ledgerOperationIDs: [operationID],
                    occurredAt: occurredAt,
                    removalSnapshot: snapshot
                )
                for activity in try activities(forKey: card.collectionKey)
                    where activity.kind.hasQuantityClaim && activity.remainingQuantity > 0 {
                    activity.resolvedQuantity = activity.claimedQuantity
                }
                context.delete(card)
            }
            guard shouldContinue?() ?? true else {
                context.rollback()
                return false
            }
            try commit()
            return true
        } catch {
            context.rollback()
            throw error
        }
    }

    /// SwiftData commits the ownership mutation, ledger rows, activity, and
    /// price metadata in one store transaction. On any persistence failure the
    /// in-memory context is rolled back before the error reaches the caller, so
    /// a later unrelated save cannot accidentally commit a half-failed action.
    private func commit(savesChanges: Bool = true) throws {
        guard savesChanges else { return }
        if CollectionWriteSerializer.enforcesOwnershipRule {
            assert(
                CollectionWriteSerializer.isHeldByCurrentThread,
                "Collection ownership changes must use CollectionWriteSerializer"
            )
        }
        do {
            try context.save()
            LocalArtworkOverrideRekeyer.removePendingFilesAfterSave(in: context)
            session.invalidate()
        } catch {
            context.rollback()
            LocalArtworkOverrideRekeyer.discardPendingFilesAfterRollback(in: context)
            throw error
        }
    }

    /// Clears the interactive alias memo after a successful save performed by
    /// a bulk or repair path that owns the context directly.
    func invalidateIdentityAliasCache() {
        session.invalidate()
    }

    /// Moves one copy from the variant it was recorded as to the one it really
    /// is. A different variant is a different physical object, so this is a move
    /// between rows rather than an edit in place.
    @discardableResult
    func recordVariantCorrection(
        for card: IdentifiedCard,
        from current: PhysicalVariant?,
        to corrected: ResolvedVariant,
        pokemonPrintRun: PokemonPrintRun? = nil,
        previousCollectionKey: String? = nil,
        previousLedgerOperationIDs: [UUID] = [],
        activityID: UUID? = nil,
        quantity: Int = 1,
        source: CollectionActivitySource = .correction
    ) throws -> CollectionMutation? {
        guard current != corrected.variant else { return nil }
        guard quantity > 0, quantity <= CollectionQuantityLimits.maximum else {
            throw CollectionStoreError.insufficientQuantity(card.providerID)
        }

        do {
        let previousBaseKey = card.collectionKey(variant: current)
        let requestedPreviousKey = previousCollectionKey
            ?? pokemonPrintRun.map { "\(previousBaseKey)@\($0.rawValue)" }
            ?? previousBaseKey
        let previousTreatmentIDs = card.magicTreatments(for: current)
        // A stale scanner entry can outlive the collection row it was created
        // from (for example, the row may have been removed on another screen or
        // device). Do not manufacture the destination row and then record a
        // `-1` correction for a source that is no longer present: that leaves
        // the ledger permanently ahead of the collection and triggers the
        // reconciliation warning on the next portfolio pass.
        guard let previous = try self.card(
            forAnyKey: requestedPreviousKey,
            magicTreatmentIDsRaw: previousTreatmentIDs.map(\.id)
        ) else { return nil }
        let previousKey = previous.collectionKey

        let candidates = try activities(forKey: previousKey)
            .filter {
                $0.kind.hasQuantityClaim
                    && $0.signedQuantity > 0
                    && $0.remainingQuantity >= quantity
            }
        let activityToRetarget: CollectionActivity?
        if let activityID {
            let selected = try activity(id: activityID)
            guard selected.collectionKey == previousKey else {
                throw CollectionStoreError.missingActivity(activityID)
            }
            guard selected.kind.hasQuantityClaim, selected.signedQuantity > 0 else {
                throw CollectionStoreError.invalidActivity(activityID)
            }
            guard previousLedgerOperationIDs.isEmpty
                    || selected.ledgerOperationIDs.isEmpty
                    || selected.ledgerOperationIDs == previousLedgerOperationIDs else {
                throw CollectionStoreError.invalidLedgerOperation(activityID)
            }
            activityToRetarget = selected
        } else if !previousLedgerOperationIDs.isEmpty {
            activityToRetarget = candidates.first {
                $0.ledgerOperationIDs == previousLedgerOperationIDs
            }
        } else {
            activityToRetarget = candidates.max(by: { $0.occurredAt < $1.occurredAt })
        }
        guard let activityToRetarget else { return nil }
        guard activityToRetarget.collectionKey == previousKey else {
            throw CollectionStoreError.missingActivity(activityToRetarget.id)
        }
        guard activityToRetarget.remainingQuantity == quantity else {
            throw CollectionStoreError.insufficientQuantity(previousKey)
        }
        guard previous.quantity >= quantity else {
            throw CollectionStoreError.insufficientQuantity(previousKey)
        }
        let operationIDs = activityToRetarget.ledgerOperationIDs.isEmpty
            ? previousLedgerOperationIDs
            : activityToRetarget.ledgerOperationIDs
        _ = try preflightLineage(
            operationIDs,
            expectedCollectionKey: previousKey,
            expectedQuantity: quantity
        )

        // A graded row's collection identity is the slab/grade/certificate,
        // not its raw-card finish. The printed finish can therefore be corrected
        // in place without manufacturing a second slab row. Move its price
        // lineage before changing the finish part of the price key.
        if previous.itemKind == .gradedCard {
            try updateGradedVariantIdentity(
                on: previous,
                to: corrected.variant,
                resolution: corrected.resolution
            )
            clearPendingCatalogFinish(on: previous)
            activityToRetarget.variantID = previous.variantID
            activityToRetarget.variantLabel = previous.variantLabel
            activityToRetarget.correctedAt = .now
            _ = try appendActivity(
                previous,
                source: source,
                kind: .corrected,
                deltaQuantity: 0,
                ledgerOperationIDs: operationIDs
            )
            try commit()
            return CollectionMutation(
                collectionKey: previousKey,
                activityID: activityToRetarget.id,
                didInsert: false,
                ledgerOperationIDs: operationIDs
            )
        }

        // Read the outgoing side's price key before the row is decremented or
        // deleted — afterwards there is nothing left to ask.
        let previousPriceStorageKey = ledger.priceStorageKey(for: previous)
        let preservesSourceArtwork = previous.quantity > quantity
        if previous.quantity == quantity {
            context.delete(previous)
        } else {
            previous.quantity -= quantity
            clearPendingCatalogFinish(on: previous)
        }

        let mutation = try add(
            card,
            resolved: corrected,
            source: source,
            pokemonPrintRun: pokemonPrintRun,
            quantity: quantity,
            writesInventoryEvent: false,
            savesChanges: false
        )
        try LocalArtworkOverrideRekeyer.rekey(
            from: previousKey,
            to: mutation.collectionKey,
            preservingSource: preservesSourceArtwork,
            destinationPolicy: .preserveExisting,
            in: context
        )

        // Two legs, one operation: −1 of the wrong identity and +1 of the right
        // one. Later price movement then follows the corrected identity by
        // itself, and the pair is what makes undo a group inversion.
        let correctionOperationID = UUID()
        guard let correctedRow = try uniqueCard(forKey: mutation.collectionKey) else {
            throw CollectionStoreError.missingDestinationRow(mutation.collectionKey)
        }
        clearPendingCatalogFinish(on: correctedRow)
        let correction = ledger.recordCorrection(
            fromCollectionKey: previousKey,
            fromPriceStorageKey: previousPriceStorageKey,
            toCard: correctedRow,
            source: source,
            quantity: quantity,
            operationID: correctionOperationID
        )
        for outcome in [correction.from, correction.to] {
            switch outcome {
            case .appended:
                break
            case .duplicate:
                throw CollectionStoreError.ledgerConflict("correction leg already exists")
            case let .conflict(defect):
                throw CollectionStoreError.ledgerConflict(defect.detail)
            case let .unreadableStore(defect):
                throw CollectionStoreError.ledgerConflict(defect.detail)
            }
        }

        guard let correctedCard = try uniqueCard(forKey: mutation.collectionKey) else {
            throw CollectionStoreError.missingDestinationRow(mutation.collectionKey)
        }

        // Remove the provisional correction event created by `add`, then move
        // the original acquisition event to the corrected row so history has
        // neither an orphan nor an extra card addition.
        if let provisionalID = mutation.activityID {
            let descriptor = FetchDescriptor<CollectionActivity>(
                predicate: #Predicate { $0.id == provisionalID }
            )
            if let provisional = try context.fetch(descriptor).first {
                context.delete(provisional)
            }
        }
        activityToRetarget.collectionKey = correctedCard.collectionKey
        activityToRetarget.name = correctedCard.name
        activityToRetarget.setName = correctedCard.setName
        activityToRetarget.setCode = correctedCard.setCode
        activityToRetarget.cardNumber = correctedCard.cardNumber
        activityToRetarget.variantID = correctedCard.variantID
        activityToRetarget.variantLabel = correctedCard.variantLabel
        activityToRetarget.magicTreatmentIDsRaw = correctedCard.magicTreatmentIDsRaw
        activityToRetarget.magicTreatmentQualifiersJSON = correctedCard.magicTreatmentQualifiersJSON
        activityToRetarget.magicContentKindRaw = correctedCard.magicContentKindRaw
        activityToRetarget.pokemonPrintRunRaw = correctedCard.pokemonPrintRunRaw
        activityToRetarget.correctedAt = .now
        activityToRetarget.ledgerOperationIDs = operationIDs + [correctionOperationID]
        _ = try appendActivity(
            correctedCard,
            source: source,
            kind: .corrected,
            deltaQuantity: 0,
            ledgerOperationIDs: [correctionOperationID]
        )
        try commit()

        return CollectionMutation(
            collectionKey: mutation.collectionKey,
            activityID: activityToRetarget.id,
            didInsert: mutation.didInsert,
            ledgerOperationIDs: operationIDs + [correctionOperationID]
        )
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Variant correction from an existing collection row. The stored row
    /// already contains the catalog metadata, so this overload shares the same
    /// preflight and transaction rules without reconstructing a provider
    /// response in a view or refresh worker.
    @discardableResult
    func recordVariantCorrection(
        for card: CollectedCard,
        to corrected: ResolvedVariant,
        activityID: UUID,
        quantity: Int,
        source: CollectionActivitySource = .correction
    ) throws -> CollectionMutation? {
        guard quantity > 0, corrected.variant != card.variant else { return nil }

        do {
            guard let previous = try self.card(
                forAnyKey: card.collectionKey,
                magicTreatmentIDsRaw: card.magicTreatmentIDs(for: card.variant)
            ) else {
                throw CollectionStoreError.missingDestinationRow(card.collectionKey)
            }
            let previousKey = previous.collectionKey
            let activityToRetarget = try activity(id: activityID)
            guard activityToRetarget.collectionKey == previousKey,
                  activityToRetarget.kind.hasQuantityClaim,
                  activityToRetarget.signedQuantity > 0 else {
                throw CollectionStoreError.invalidActivity(activityID)
            }
            guard activityToRetarget.remainingQuantity == quantity else {
                throw CollectionStoreError.insufficientQuantity(previousKey)
            }
            let operationIDs = activityToRetarget.ledgerOperationIDs
            _ = try preflightLineage(
                operationIDs,
                expectedCollectionKey: previousKey,
                expectedQuantity: quantity
            )
            guard previous.quantity >= quantity else {
                throw CollectionStoreError.insufficientQuantity(previousKey)
            }

            if previous.itemKind == .gradedCard {
                try updateGradedVariantIdentity(
                    on: previous,
                    to: corrected.variant,
                    resolution: corrected.resolution
                )
                clearPendingCatalogFinish(on: previous)
                activityToRetarget.variantID = previous.variantID
                activityToRetarget.variantLabel = previous.variantLabel
                activityToRetarget.correctedAt = .now
                _ = try appendActivity(
                    previous,
                    source: source,
                    kind: .corrected,
                    deltaQuantity: 0,
                    ledgerOperationIDs: operationIDs
                )
                try commit()
                return CollectionMutation(
                    collectionKey: previousKey,
                    activityID: activityToRetarget.id,
                    didInsert: false,
                    ledgerOperationIDs: operationIDs
                )
            }

            let parts = previous.collectionKey.split(separator: "@", maxSplits: 1)
            let base = parts.first.map(String.init) ?? previous.collectionKey
            let runSuffix = parts.dropFirst().first.map { "@\($0)" } ?? ""
            let identityBase = base.split(separator: "#", maxSplits: 1).first.map(String.init) ?? base
            let correctedTreatmentEvidence = MagicTreatmentEvidence(
                treatments: previous.magicTreatmentIDs(for: corrected.variant)
                    .compactMap(MagicTreatment.init(id:)),
                qualifiers: previous.magicTreatmentQualifiers
            )
            let correctedTreatments = correctedTreatmentEvidence.treatments
            let correctedTreatmentIDs = MagicTreatmentKeyCodec.storedIDs(
                from: correctedTreatments
            )
            let correctedTreatmentQualifiers = Dictionary(uniqueKeysWithValues: correctedTreatments.compactMap { treatment in
                correctedTreatmentEvidence.qualifier(for: treatment).map { (treatment.id, $0) }
            })
            let destinationKey = MagicTreatmentKeyCodec.finishQualifiedCollectionKey(
                base: identityBase,
                game: previous.cardGame,
                finish: corrected.variant,
                rawTreatmentIDs: correctedTreatmentIDs
            ) + runSuffix
            guard destinationKey != previous.collectionKey else {
                throw CollectionStoreError.invalidActivity(activityID)
            }
            try LocalArtworkOverrideRekeyer.rekey(
                from: previousKey,
                to: destinationKey,
                preservingSource: previous.quantity > quantity,
                destinationPolicy: .preserveExisting,
                in: context
            )
            let previousPriceStorageKey = ledger.priceStorageKey(for: previous)
            let previousSnapshot = RemovedCardSnapshot(card: previous, quantity: quantity)
            if previous.quantity == quantity {
                context.delete(previous)
            } else {
                previous.quantity -= quantity
                clearPendingCatalogFinish(on: previous)
            }

            let preserveDateAdded = source == .catalogUpdate || source == .catalogBackfill

            let correctedRow: CollectedCard
            if let existing = try self.card(
                forAnyKey: destinationKey,
                magicTreatmentIDsRaw: correctedTreatmentIDs
            ) {
                existing.quantity = try CollectionQuantityLimits.checkedAdd(existing.quantity, quantity)
                if !preserveDateAdded { existing.dateAdded = .now }
                if existing.magicTreatmentIDsRaw.isEmpty {
                    existing.magicTreatmentIDsRaw = correctedTreatmentIDs
                }
                if existing.magicTreatmentQualifiersJSON == nil {
                    existing.magicTreatmentQualifiers = correctedTreatmentQualifiers
                }
                existing.variantID = corrected.variant?.id
                existing.variantLabel = corrected.variant?.label
                let provenanceRank: (VariantResolution) -> Int = { resolution in
                    switch resolution {
                    case .userConfirmed, .imported: return 3
                    case .finishLock, .printedLabel: return 2
                    case .uniqueInCatalog, .deterministicSetRule: return 1
                    case .catalogSilent: return 0
                    }
                }
                if source == .correction
                    || provenanceRank(corrected.resolution)
                        >= provenanceRank(existing.variantResolution ?? .catalogSilent) {
                    existing.variantResolutionRaw = corrected.resolution.rawValue
                }
                clearPendingCatalogFinish(on: existing)
                correctedRow = existing
            } else {
                let inserted = CollectedCard(
                    collectionKey: destinationKey,
                    game: previousSnapshot.game,
                    providerID: previousSnapshot.providerID,
                    name: previousSnapshot.name,
                    setName: previousSnapshot.setName,
                    setCode: previousSnapshot.setCode,
                    cardNumber: previousSnapshot.cardNumber,
                    rarity: previousSnapshot.rarity,
                    imageURL: previousSnapshot.imageURL,
                    thumbnailURL: previousSnapshot.thumbnailURL,
                    variant: corrected.variant,
                    variantResolution: corrected.resolution,
                    identityResolution: previousSnapshot.identityResolution,
                    setReleaseOrder: previousSnapshot.setReleaseOrder,
                    quantity: quantity,
                    dateAdded: preserveDateAdded ? previousSnapshot.dateAdded : .now,
                    magicTreatments: correctedTreatments,
                    magicTreatmentQualifiers: correctedTreatmentQualifiers
                )
                inserted.catalogProviderID = previousSnapshot.catalogProviderID
                inserted.tcgplayerURL = previousSnapshot.tcgplayerURL
                inserted.tcgplayerProductID = previousSnapshot.tcgplayerProductID
                // A SKU is finish-specific just like the marketplace variant.
                // The correction must resolve the destination independently.
                inserted.tcgplayerSKUID = nil
                inserted.userArtworkFilename = previousSnapshot.userArtworkFilename
                inserted.itemKindRaw = previousSnapshot.itemKindRaw
                inserted.justTCGCardID = previousSnapshot.justTCGCardID
                // The old marketplace variant is exact for the outgoing row;
                // carrying it over would price the corrected finish as the old
                // one during the next refresh.
                inserted.justTCGVariantID = nil
                inserted.justTCGAPIVersion = previousSnapshot.justTCGAPIVersion
                inserted.pokemonPrintRunRaw = previousSnapshot.pokemonPrintRunRaw
                inserted.magicTreatmentIDsRaw = correctedTreatmentIDs
                inserted.magicTreatmentQualifiersJSON = MagicTreatmentKeyCodec.encodeQualifiers(
                    correctedTreatmentQualifiers
                )
                inserted.magicContentKindRaw = previousSnapshot.magicContentKindRaw ?? MagicContentKind.regular.rawValue
                inserted.catalogMetadataCheckedAt = previousSnapshot.catalogMetadataCheckedAt
                inserted.catalogMetadataVersion = previousSnapshot.catalogMetadataVersion
                inserted.gradingCompanyRaw = previousSnapshot.gradingCompanyRaw
                inserted.gradeRaw = previousSnapshot.gradeRaw
                inserted.gradeLabel = previousSnapshot.gradeLabel
                inserted.gradingQualifier = previousSnapshot.gradingQualifier
                inserted.certificationNumber = previousSnapshot.certificationNumber
                inserted.marketRegionRaw = previousSnapshot.marketRegionRaw
                clearPendingCatalogFinish(on: inserted)
                context.insert(inserted)
                correctedRow = inserted
            }

            let correctionOperationID = UUID()
            let correction = ledger.recordCorrection(
                fromCollectionKey: previousSnapshot.collectionKey,
                fromPriceStorageKey: previousPriceStorageKey,
                toCard: correctedRow,
                source: source,
                quantity: quantity,
                operationID: correctionOperationID
            )
            try requireAppended(correction.from)
            try requireAppended(correction.to)

            activityToRetarget.collectionKey = correctedRow.collectionKey
            activityToRetarget.name = correctedRow.name
            activityToRetarget.setName = correctedRow.setName
            activityToRetarget.setCode = correctedRow.setCode
            activityToRetarget.cardNumber = correctedRow.cardNumber
            activityToRetarget.variantID = correctedRow.variantID
            activityToRetarget.variantLabel = correctedRow.variantLabel
            activityToRetarget.magicTreatmentIDsRaw = correctedRow.magicTreatmentIDsRaw
            activityToRetarget.magicTreatmentQualifiersJSON = correctedRow.magicTreatmentQualifiersJSON
            activityToRetarget.pokemonPrintRunRaw = correctedRow.pokemonPrintRunRaw
            activityToRetarget.correctedAt = .now
            activityToRetarget.ledgerOperationIDs = operationIDs + [correctionOperationID]
            _ = try appendActivity(
                correctedRow,
                source: source,
                kind: .corrected,
                deltaQuantity: 0,
                ledgerOperationIDs: [correctionOperationID]
            )
            try commit()

            return CollectionMutation(
                collectionKey: correctedRow.collectionKey,
                activityID: activityToRetarget.id,
                didInsert: false,
                ledgerOperationIDs: operationIDs + [correctionOperationID]
            )
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Value-only entry point for async/UI callers. The row is resolved in the
    /// current write context so a model object captured before a suspension
    /// point is never used as the basis for a correction.
    @discardableResult
    func recordVariantCorrection(
        forCollectionKey collectionKey: String,
        magicTreatmentIDsRaw: [String] = [],
        to corrected: ResolvedVariant,
        activityID: UUID,
        quantity: Int,
        source: CollectionActivitySource = .correction
    ) throws -> CollectionMutation? {
        guard let card = try self.card(
            forAnyKey: collectionKey,
            magicTreatmentIDsRaw: magicTreatmentIDsRaw
        ) else {
            throw CollectionStoreError.missingDestinationRow(collectionKey)
        }
        return try recordVariantCorrection(
            for: card,
            to: corrected,
            activityID: activityID,
            quantity: quantity,
            source: source
        )
    }

    /// Moves a set of acquisition claims as one transaction. Catalog finish
    /// reconciliation passes every outstanding acquisition for the row so a
    /// failure cannot leave some copies under the old finish and others under
    /// the new one.
    @discardableResult
    func recordVariantCorrection(
        for card: CollectedCard,
        to corrected: ResolvedVariant,
        claims: [CollectionVariantCorrectionClaim],
        source: CollectionActivitySource,
        mode: CollectionVariantCorrectionMode
    ) throws -> CollectionMutation? {
        guard !claims.isEmpty, corrected.variant != card.variant else { return nil }
        guard claims.allSatisfy({
            $0.quantity > 0 && $0.quantity <= CollectionQuantityLimits.maximum
        }), Set(claims.map(\.activityID)).count == claims.count else {
            throw CollectionStoreError.insufficientQuantity(card.collectionKey)
        }

        do {
            guard let previous = try self.card(
                forAnyKey: card.collectionKey,
                magicTreatmentIDsRaw: card.magicTreatmentIDs(for: card.variant)
            ) else {
                throw CollectionStoreError.missingDestinationRow(card.collectionKey)
            }
            let previousKey = previous.collectionKey
            guard corrected.variant != previous.variant else { return nil }
            guard mode != .quietBackfill
                    || (source == .catalogBackfill
                        && previous.variantID == nil
                        && (previous.variantResolution == nil || previous.variantResolution?.isAutomatic == true)
                        && corrected.variant != nil) else {
                throw CollectionStoreError.invalidActivity(claims[0].activityID)
            }

            var totalQuantity = 0
            var selected: [(claim: CollectionVariantCorrectionClaim, activity: CollectionActivity, operationIDs: [UUID])] = []
            for claim in claims {
                totalQuantity = try CollectionQuantityLimits.checkedAdd(totalQuantity, claim.quantity)
                let activity = try activity(id: claim.activityID)
                guard activity.collectionKey == previousKey,
                      activity.kind.hasQuantityClaim,
                      activity.signedQuantity > 0 else {
                    throw CollectionStoreError.invalidActivity(claim.activityID)
                }
                guard activity.remainingQuantity == claim.quantity else {
                    throw CollectionStoreError.insufficientQuantity(previousKey)
                }
                let operationIDs = activity.ledgerOperationIDs
                _ = try preflightLineage(
                    operationIDs,
                    expectedCollectionKey: previousKey,
                    expectedQuantity: claim.quantity
                )
                selected.append((claim, activity, operationIDs))
            }
            guard previous.quantity >= totalQuantity else {
                throw CollectionStoreError.insufficientQuantity(previousKey)
            }

            if previous.itemKind == .gradedCard {
                guard mode == .visibleCorrection else {
                    throw CollectionStoreError.invalidActivity(claims[0].activityID)
                }
                try updateGradedVariantIdentity(
                    on: previous,
                    to: corrected.variant,
                    resolution: corrected.resolution
                )
                clearPendingCatalogFinish(on: previous)
                var operationIDs: [UUID] = []
                for entry in selected {
                    entry.activity.variantID = previous.variantID
                    entry.activity.variantLabel = previous.variantLabel
                    entry.activity.correctedAt = .now
                    operationIDs.append(contentsOf: entry.operationIDs)
                    _ = try appendActivity(
                        previous,
                        source: source,
                        kind: .corrected,
                        deltaQuantity: 0,
                        ledgerOperationIDs: entry.operationIDs
                    )
                }
                try commit()
                return CollectionMutation(
                    collectionKey: previousKey,
                    activityID: selected.first?.activity.id,
                    didInsert: false,
                    ledgerOperationIDs: operationIDs
                )
            }

            let parts = previousKey.split(separator: "@", maxSplits: 1)
            let base = parts.first.map(String.init) ?? previousKey
            let runSuffix = parts.dropFirst().first.map { "@\($0)" } ?? ""
            let identityBase = base.split(separator: "#", maxSplits: 1).first.map(String.init) ?? base
            let correctedTreatmentEvidence = MagicTreatmentEvidence(
                treatments: previous.magicTreatmentIDs(for: corrected.variant)
                    .compactMap(MagicTreatment.init(id:)),
                qualifiers: previous.magicTreatmentQualifiers
            )
            let correctedTreatments = correctedTreatmentEvidence.treatments
            let correctedTreatmentIDs = MagicTreatmentKeyCodec.storedIDs(from: correctedTreatments)
            let correctedTreatmentQualifiers = Dictionary(uniqueKeysWithValues: correctedTreatments.compactMap { treatment in
                correctedTreatmentEvidence.qualifier(for: treatment).map { (treatment.id, $0) }
            })
            let destinationKey = MagicTreatmentKeyCodec.finishQualifiedCollectionKey(
                base: identityBase,
                game: previous.cardGame,
                finish: corrected.variant,
                rawTreatmentIDs: correctedTreatmentIDs
            ) + runSuffix
            guard destinationKey != previousKey else {
                throw CollectionStoreError.invalidActivity(claims[0].activityID)
            }

            try LocalArtworkOverrideRekeyer.rekey(
                from: previousKey,
                to: destinationKey,
                preservingSource: previous.quantity > totalQuantity,
                destinationPolicy: .preserveExisting,
                in: context
            )
            let previousPriceStorageKey = ledger.priceStorageKey(for: previous)
            let previousSnapshot = RemovedCardSnapshot(card: previous, quantity: totalQuantity)
            if previous.quantity == totalQuantity {
                context.delete(previous)
            } else {
                previous.quantity -= totalQuantity
                clearPendingCatalogFinish(on: previous)
            }

            let preserveDateAdded = mode == .quietBackfill
                || source == .catalogUpdate
                || source == .catalogBackfill
            let correctedRow: CollectedCard
            let didInsert: Bool
            if let existing = try self.card(
                forAnyKey: destinationKey,
                magicTreatmentIDsRaw: correctedTreatmentIDs
            ) {
                existing.quantity = try CollectionQuantityLimits.checkedAdd(
                    existing.quantity,
                    totalQuantity
                )
                if !preserveDateAdded { existing.dateAdded = .now }
                if existing.magicTreatmentIDsRaw.isEmpty {
                    existing.magicTreatmentIDsRaw = correctedTreatmentIDs
                }
                if existing.magicTreatmentQualifiersJSON == nil {
                    existing.magicTreatmentQualifiers = correctedTreatmentQualifiers
                }
                existing.variantID = corrected.variant?.id
                existing.variantLabel = corrected.variant?.label
                let provenanceRank: (VariantResolution) -> Int = { resolution in
                    switch resolution {
                    case .userConfirmed, .imported: return 3
                    case .finishLock, .printedLabel: return 2
                    case .uniqueInCatalog, .deterministicSetRule: return 1
                    case .catalogSilent: return 0
                    }
                }
                if source == .correction
                    || provenanceRank(corrected.resolution)
                        >= provenanceRank(existing.variantResolution ?? .catalogSilent) {
                    existing.variantResolutionRaw = corrected.resolution.rawValue
                }
                clearPendingCatalogFinish(on: existing)
                correctedRow = existing
                didInsert = false
            } else {
                let inserted = CollectedCard(
                    collectionKey: destinationKey,
                    game: previousSnapshot.game,
                    providerID: previousSnapshot.providerID,
                    name: previousSnapshot.name,
                    setName: previousSnapshot.setName,
                    setCode: previousSnapshot.setCode,
                    cardNumber: previousSnapshot.cardNumber,
                    rarity: previousSnapshot.rarity,
                    imageURL: previousSnapshot.imageURL,
                    thumbnailURL: previousSnapshot.thumbnailURL,
                    variant: corrected.variant,
                    variantResolution: corrected.resolution,
                    identityResolution: previousSnapshot.identityResolution,
                    setReleaseOrder: previousSnapshot.setReleaseOrder,
                    quantity: totalQuantity,
                    dateAdded: preserveDateAdded ? previousSnapshot.dateAdded : .now,
                    magicTreatments: correctedTreatments,
                    magicTreatmentQualifiers: correctedTreatmentQualifiers
                )
                inserted.catalogProviderID = previousSnapshot.catalogProviderID
                inserted.tcgplayerURL = previousSnapshot.tcgplayerURL
                inserted.tcgplayerProductID = previousSnapshot.tcgplayerProductID
                // A finish-specific marketplace handle belongs to the outgoing
                // row. The corrected finish must be resolved independently.
                inserted.tcgplayerSKUID = nil
                inserted.userArtworkFilename = previousSnapshot.userArtworkFilename
                inserted.itemKindRaw = previousSnapshot.itemKindRaw
                inserted.justTCGCardID = previousSnapshot.justTCGCardID
                inserted.justTCGVariantID = nil
                inserted.justTCGAPIVersion = previousSnapshot.justTCGAPIVersion
                inserted.pokemonPrintRunRaw = previousSnapshot.pokemonPrintRunRaw
                inserted.magicTreatmentIDsRaw = correctedTreatmentIDs
                inserted.magicTreatmentQualifiersJSON = MagicTreatmentKeyCodec.encodeQualifiers(
                    correctedTreatmentQualifiers
                )
                inserted.magicContentKindRaw = previousSnapshot.magicContentKindRaw ?? MagicContentKind.regular.rawValue
                inserted.catalogMetadataCheckedAt = previousSnapshot.catalogMetadataCheckedAt
                inserted.catalogMetadataVersion = previousSnapshot.catalogMetadataVersion
                inserted.gradingCompanyRaw = previousSnapshot.gradingCompanyRaw
                inserted.gradeRaw = previousSnapshot.gradeRaw
                inserted.gradeLabel = previousSnapshot.gradeLabel
                inserted.gradingQualifier = previousSnapshot.gradingQualifier
                inserted.certificationNumber = previousSnapshot.certificationNumber
                inserted.marketRegionRaw = previousSnapshot.marketRegionRaw
                clearPendingCatalogFinish(on: inserted)
                context.insert(inserted)
                correctedRow = inserted
                didInsert = true
            }

            var returnedOperationIDs: [UUID] = []
            for entry in selected {
                let correctionOperationID = UUID()
                let correction = ledger.recordCorrection(
                    fromCollectionKey: previousSnapshot.collectionKey,
                    fromPriceStorageKey: previousPriceStorageKey,
                    toCard: correctedRow,
                    source: source,
                    quantity: entry.claim.quantity,
                    operationID: correctionOperationID
                )
                try requireAppended(correction.from)
                try requireAppended(correction.to)

                entry.activity.collectionKey = correctedRow.collectionKey
                entry.activity.name = correctedRow.name
                entry.activity.setName = correctedRow.setName
                entry.activity.setCode = correctedRow.setCode
                entry.activity.cardNumber = correctedRow.cardNumber
                entry.activity.variantID = correctedRow.variantID
                entry.activity.variantLabel = correctedRow.variantLabel
                entry.activity.magicTreatmentIDsRaw = correctedRow.magicTreatmentIDsRaw
                entry.activity.magicTreatmentQualifiersJSON = correctedRow.magicTreatmentQualifiersJSON
                entry.activity.magicContentKindRaw = correctedRow.magicContentKindRaw
                entry.activity.pokemonPrintRunRaw = correctedRow.pokemonPrintRunRaw
                entry.activity.ledgerOperationIDs = entry.operationIDs + [correctionOperationID]
                if mode == .visibleCorrection {
                    entry.activity.correctedAt = .now
                    _ = try appendActivity(
                        correctedRow,
                        source: source,
                        kind: .corrected,
                        deltaQuantity: 0,
                        ledgerOperationIDs: [correctionOperationID]
                    )
                }
                returnedOperationIDs.append(contentsOf: entry.operationIDs)
                returnedOperationIDs.append(correctionOperationID)
            }

            try commit()
            return CollectionMutation(
                collectionKey: correctedRow.collectionKey,
                activityID: selected.first?.activity.id,
                didInsert: didInsert,
                ledgerOperationIDs: returnedOperationIDs
            )
        } catch {
            context.rollback()
            throw error
        }
    }

    private func clearPendingCatalogFinish(on card: CollectedCard) {
        card.pendingCatalogFinishID = nil
        card.pendingCatalogFinishFirstSeenAt = nil
        card.pendingCatalogFinishRefreshID = nil
    }
}

/// Runs the whole-collection deletion on a context isolated from SwiftUI's
/// main-actor context. The continuation is checked before each position and
/// before commit so a storage transition rolls the operation back atomically.
@ModelActor
actor CollectionDeletionModelActor {
    func deleteAll(
        shouldContinue: @escaping StorageGenerationContinuation,
        exclusiveToken: UUID? = nil
    ) throws -> Bool {
        try CollectionWriteSerializer.perform(
            container: modelContext.container,
            timeout: .wait,
            exclusiveToken: exclusiveToken
        ) { context in
            try CollectionStore(context: context).deleteAll(shouldContinue: shouldContinue)
        }
    }
}

/// Everything needed to put a removed position back exactly as it was.
///
/// Lives beside `CollectionStore` because restoring is an ownership change, not
/// a view concern: it has to invert a ledger event, and only the store knows
/// how.
struct RemovedCardSnapshot: Identifiable, Codable {
    var id = UUID()
    /// The ledger operation that recorded the disposal, so restoring can invert
    /// exactly that rather than recording a fresh acquisition. `nil` only for a
    /// snapshot taken before the ledger existed.
    var operationID: UUID?
    var collectionKey: String
    let game: CardGame
    let providerID: String
    let catalogProviderID: String?
    let name: String
    let setName: String
    let setCode: String
    let cardNumber: String
    let rarity: String?
    /// Optional so snapshots written before treatment identity existed decode
    /// as the empty treatment axis during restore.
    var magicTreatmentIDsRaw: [String]?
    var magicTreatmentQualifiersJSON: String?
    var magicContentKindRaw: String?
    let imageURL: String?
    let thumbnailURL: String?
    let userArtworkFilename: String?
    let pokemonPrintRunRaw: String?
    let tcgplayerURL: String?
    let tcgplayerProductID: String?
    let tcgplayerSKUID: String?
    let catalogMetadataCheckedAt: Date?
    let catalogMetadataVersion: Int
    let itemKindRaw: String
    let justTCGCardID: String?
    let justTCGVariantID: String?
    let justTCGAPIVersion: String?
    let gradingCompanyRaw: String?
    let gradeRaw: String?
    let gradeLabel: String?
    let gradingQualifier: String?
    let certificationNumber: String?
    let marketRegionRaw: String?
    let quantity: Int
    let dateAdded: Date
    var variant: PhysicalVariant?
    let variantResolution: VariantResolution
    let identityResolution: IdentityResolution
    let setReleaseOrder: Int

    init(card: CollectedCard, quantity: Int? = nil) {
        collectionKey = card.collectionKey
        game = card.cardGame
        providerID = card.providerID
        catalogProviderID = card.catalogProviderID
        name = card.name
        setName = card.setName
        setCode = card.setCode
        cardNumber = card.cardNumber
        rarity = card.rarity
        magicTreatmentIDsRaw = card.magicTreatmentIDsRaw
        magicTreatmentQualifiersJSON = card.magicTreatmentQualifiersJSON
        magicContentKindRaw = card.magicContentKindRaw
        imageURL = card.imageURL
        thumbnailURL = card.thumbnailURL
        userArtworkFilename = card.userArtworkFilename
        pokemonPrintRunRaw = card.pokemonPrintRunRaw
        tcgplayerURL = card.tcgplayerURL
        tcgplayerProductID = card.tcgplayerProductID
        tcgplayerSKUID = card.tcgplayerSKUID
        catalogMetadataCheckedAt = card.catalogMetadataCheckedAt
        catalogMetadataVersion = card.catalogMetadataVersion
        itemKindRaw = card.itemKindRaw
        justTCGCardID = card.justTCGCardID
        justTCGVariantID = card.justTCGVariantID
        justTCGAPIVersion = card.justTCGAPIVersion
        gradingCompanyRaw = card.gradingCompanyRaw
        gradeRaw = card.gradeRaw
        gradeLabel = card.gradeLabel
        gradingQualifier = card.gradingQualifier
        certificationNumber = card.certificationNumber
        marketRegionRaw = card.marketRegionRaw
        self.quantity = quantity ?? card.quantity
        dateAdded = card.dateAdded
        variant = card.variant
        variantResolution = card.variantResolution ?? .catalogSilent
        identityResolution = card.identityResolution ?? .printedIdentifier
        setReleaseOrder = card.setReleaseOrder
    }

    /// Re-materialises the collection row. Ownership accounting is
    /// `CollectionStore.restore(_:)`'s job, not this type's. Isolation follows
    /// the caller's context, like the rest of the store.
    func reinsert(in context: ModelContext) throws {
        let key = collectionKey
        let rows = try context.fetch(
            FetchDescriptor<CollectedCard>(
                predicate: #Predicate { $0.collectionKey == key }
            )
        )
        if let existing = LogicalCollection.chooseRepresentative(from: rows) {
            let mergedQuantity = try rows.reduce(into: 0) { total, row in
                total = try CollectionQuantityLimits.checkedAdd(total, row.quantity)
            }
            existing.quantity = try CollectionQuantityLimits.checkedAdd(mergedQuantity, quantity)
            existing.dateAdded = max(existing.dateAdded, dateAdded)
            if existing.magicTreatmentIDsRaw.isEmpty {
                existing.magicTreatmentIDsRaw = MagicTreatmentKeyCodec.storedIDs(
                    from: magicTreatmentIDsRaw ?? []
                )
            }
            if existing.magicTreatmentQualifiersJSON == nil {
                existing.magicTreatmentQualifiersJSON = magicTreatmentQualifiersJSON
            }
            if existing.magicContentKindRaw == MagicContentKind.regular.rawValue,
               let magicContentKindRaw,
               magicContentKindRaw != MagicContentKind.regular.rawValue {
                existing.magicContentKindRaw = magicContentKindRaw
            }
            for row in rows where row !== existing {
                context.delete(row)
            }
        } else {
            let restored = CollectedCard(
                collectionKey: collectionKey,
                game: game,
                providerID: providerID,
                name: name,
                setName: setName,
                setCode: setCode,
                cardNumber: cardNumber,
                rarity: rarity,
                imageURL: imageURL,
                thumbnailURL: thumbnailURL,
                variant: variant,
                variantResolution: variantResolution,
                identityResolution: identityResolution,
                setReleaseOrder: setReleaseOrder,
                quantity: quantity,
                dateAdded: dateAdded,
                magicTreatments: (magicTreatmentIDsRaw ?? []).compactMap(MagicTreatment.init(id:)),
                magicTreatmentQualifiers: MagicTreatmentKeyCodec.decodeQualifiers(
                    magicTreatmentQualifiersJSON
                ),
                magicContentKind: MagicContentKind(rawValue: magicContentKindRaw ?? "") ?? .regular
            )
            restored.tcgplayerURL = tcgplayerURL
            restored.tcgplayerProductID = tcgplayerProductID
            restored.tcgplayerSKUID = tcgplayerSKUID
            restored.userArtworkFilename = userArtworkFilename
            restored.pokemonPrintRunRaw = pokemonPrintRunRaw
            restored.catalogProviderID = catalogProviderID
            restored.catalogMetadataCheckedAt = catalogMetadataCheckedAt
            restored.catalogMetadataVersion = catalogMetadataVersion
            restored.itemKindRaw = itemKindRaw
            restored.justTCGCardID = justTCGCardID
            restored.justTCGVariantID = justTCGVariantID
            restored.justTCGAPIVersion = justTCGAPIVersion
            restored.gradingCompanyRaw = gradingCompanyRaw
            restored.gradeRaw = gradeRaw
            restored.gradeLabel = gradeLabel
            restored.gradingQualifier = gradingQualifier
            restored.certificationNumber = certificationNumber
            restored.marketRegionRaw = marketRegionRaw
            restored.magicContentKindRaw = magicContentKindRaw ?? MagicContentKind.regular.rawValue
            context.insert(restored)
        }

    }
}
