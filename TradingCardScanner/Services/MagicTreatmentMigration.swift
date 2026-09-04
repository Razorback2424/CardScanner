import CryptoKit
import Foundation
import SwiftData

/// Repairs Magic collection rows written before treatment identity was
/// persisted.
///
/// This is deliberately a data migration rather than a second resolver. The
/// only provider identity it trusts is the Scryfall printing id already inside
/// a validated raw/graded collection key. Set code plus collector number is not
/// enough: the same number can have several printings, and a dual-finish
/// printing still needs the selected finish before a foil-only treatment can be
/// attached.
@MainActor
enum MagicTreatmentMigration {
    /// Bump this when the exact-printing enrichment rules change. The watermark
    /// lives on each collection row so a new import, or a row arriving from
    /// another CloudKit device after an earlier launch, is still considered.
    nonisolated static let currentVersion = 1

    struct Report: Equatable, Sendable {
        var examinedRows = 0
        var exactLookups = 0
        var failedExactLookups = 0
        var enrichedRows = 0
        var rekeyedRows = 0
        var mergedCollisions = 0
        var clearedVendorNegatives = 0
        var skippedCertifiedCollisions = 0
        var failures: [String] = []

        var isComplete: Bool {
            failedExactLookups == 0 && failures.isEmpty
        }

        var didChange: Bool {
            enrichedRows > 0
                || rekeyedRows > 0
                || mergedCollisions > 0
                || clearedVendorNegatives > 0
        }

        mutating func fail(_ detail: String) {
            failures.append(detail)
        }

        /// Combines the reports from the local repair and deferred enrichment
        /// phases. The examined-row count is a snapshot, not a per-phase event;
        /// the network phase may see the same still-unwatermarked rows after
        /// local planning has finished.
        mutating func absorb(_ other: Report) {
            examinedRows = max(examinedRows, other.examinedRows)
            exactLookups += other.exactLookups
            failedExactLookups += other.failedExactLookups
            enrichedRows += other.enrichedRows
            rekeyedRows += other.rekeyedRows
            mergedCollisions += other.mergedCollisions
            clearedVendorNegatives += other.clearedVendorNegatives
            skippedCertifiedCollisions += other.skippedCertifiedCollisions
            failures.append(contentsOf: other.failures)
        }
    }

    /// A source row and its treatment-qualified destination. The old key is
    /// opaque identity, not a collection-key component to be reconstructed by
    /// splitting on colons.
    struct MigrationPair: Hashable, Sendable {
        let oldKey: String
        let newKey: String
    }

    /// Deterministic identity used by migration correction legs. The source
    /// record identity is stable across devices; old/new keys remain separate
    /// inputs even though the source usually contains the old key already.
    nonisolated static func operationID(
        migrationVersion: Int = currentVersion,
        sourceRecordIdentity: String,
        oldKey: String,
        newKey: String
    ) -> UUID {
        deterministicUUID(
            material: [
                "magic-treatment-migration",
                "v\(migrationVersion)",
                sourceRecordIdentity,
                oldKey,
                newKey
            ]
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "|")
        )
    }

    /// Runs both migration phases for callers that need the complete result.
    /// The app uses the two phase-specific entry points so portfolio startup
    /// is never held behind network enrichment.
    @discardableResult
    static func run(
        in context: ModelContext,
        now: Date = .now
    ) async -> Report {
        var report = await runLocal(in: context, now: now)
        let networkReport = await runNetwork(in: context, now: now)
        report.absorb(networkReport)
        return report
    }

    /// Performs only work that can be completed from the local collection and
    /// the compact catalog. This phase is safe to run before portfolio startup:
    /// it repairs identities already proven by their keys, resolves reviewed
    /// catalog entries, and leaves ordinary catalog misses untouched for the
    /// deferred network phase.
    @discardableResult
    static func runLocal(
        in context: ModelContext,
        now: Date = .now
    ) async -> Report {
        await runPhase(in: context, now: now, fetchBatch: nil)
    }

    /// Enriches still-unresolved exact printing ids after the portfolio is
    /// available. Scryfall's collection endpoint is used in batches of at most
    /// 75 so an ordinary collection does not turn launch into one sequential
    /// request per Magic row.
    @discardableResult
    static func runNetwork(
        in context: ModelContext,
        now: Date = .now
    ) async -> Report {
        await runNetwork(in: context, now: now) { ids in
            try await ScryfallService().fetchCards(
                identifiers: ids.map { ScryfallCardIdentifier(id: $0) }
            )
        }
    }

    /// Injectable batch form used by migration tests and support tooling. No
    /// test needs to contact Scryfall, while production still uses exact-id
    /// identifiers and the same bounded request shape.
    @discardableResult
    static func runNetwork(
        in context: ModelContext,
        now: Date = .now,
        fetchCards: @escaping @Sendable ([String]) async throws -> [ScryfallCard]
    ) async -> Report {
        await runPhase(in: context, now: now, fetchBatch: fetchCards)
    }

    /// Injectable per-card compatibility form used by existing migration
    /// tests and support tooling. The production path above is batched; this
    /// adapter preserves the old fixture API without reintroducing a
    /// one-request-per-row launch path.
    @discardableResult
    static func run(
        in context: ModelContext,
        now: Date = .now,
        fetchCard: @escaping @Sendable (String) async throws -> ScryfallCard
    ) async -> Report {
        var report = await runLocal(in: context, now: now)
        let networkReport = await runNetwork(in: context, now: now) { ids in
            var responses: [ScryfallCard] = []
            responses.reserveCapacity(ids.count)
            for id in ids {
                try Task.checkCancellation()
                responses.append(try await fetchCard(id))
            }
            return responses
        }
        report.absorb(networkReport)
        return report
    }

    private static func runPhase(
        in context: ModelContext,
        now: Date,
        fetchBatch: (@Sendable ([String]) async throws -> [ScryfallCard])?
    ) async -> Report {
        var report = Report()

        let cards: [CollectedCard]
        do {
            cards = try context.fetch(FetchDescriptor<CollectedCard>())
        } catch {
            report.fail("Could not read Magic collection rows: \(error)")
            return report
        }

        clearTreatmentVendorNegatives(in: context, report: &report)

        let candidates = cards.filter {
            $0.cardGame == .magic
                && $0.magicTreatmentMigrationVersion < currentVersion
        }
        report.examinedRows = candidates.count

        var descriptors: [ObjectIdentifier: MagicCollectionKeyParts] = [:]
        for card in cards where card.cardGame == .magic {
            if let parts = MagicTreatmentKeyCodec.collectionKeyParts(from: card.collectionKey) {
                descriptors[ObjectIdentifier(card)] = parts
            }
        }

        let catalog = MagicTreatmentCatalogStore.bundledDefault
        var exactIDs: Set<String> = []
        for card in candidates {
            guard let parts = descriptors[ObjectIdentifier(card)],
                  let exactID = parts.exactPrintingID,
                  !parts.isTreatmentQualified,
                  card.magicTreatments.isEmpty else {
                continue
            }
            exactIDs.insert(exactID)
        }

        var evidenceByExactID: [String: ExactEvidence] = [:]
        var failedExactIDs: Set<String> = []
        var remoteExactIDs: [String] = []
        for exactID in exactIDs.sorted() {
            let rows = candidates.filter {
                descriptors[ObjectIdentifier($0)]?.exactPrintingID
                    .map { $0.caseInsensitiveCompare(exactID) == .orderedSame } == true
            }
            let requiresProviderFinish = rows.contains { row in
                let rowParts = descriptors[ObjectIdentifier(row)]
                return row.itemKind == .gradedCard
                    || (row.itemKind == .rawCard
                        && row.variant == nil
                        && rowParts?.finishID == nil)
            }

            if let entry = catalog.entry(forCardID: exactID),
               !requiresProviderFinish {
                evidenceByExactID[exactID.lowercased()] = ExactEvidence(
                    evidence: MagicTreatmentEvidence(
                        treatments: entry.decodedTreatments,
                        qualifiers: entry.qualifiers
                    ),
                    catalogVariants: nil
                )
                continue
            }

            if fetchBatch != nil {
                remoteExactIDs.append(exactID)
            }
        }

        if let fetchBatch {
            let maximumBatchSize = 75
            for batchStart in stride(from: 0, to: remoteExactIDs.count, by: maximumBatchSize) {
                guard !Task.isCancelled else { return report }
                if batchStart > 0 {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return report }
                }
                let batchEnd = min(batchStart + maximumBatchSize, remoteExactIDs.count)
                let batch = Array(remoteExactIDs[batchStart..<batchEnd])
                report.exactLookups += batch.count

                do {
                    let responses = try await fetchBatch(batch)
                    var responseByID: [String: ScryfallCard] = [:]
                    var duplicateResponseIDs: Set<String> = []

                    for response in responses {
                        guard let requestedID = batch.first(where: {
                            $0.caseInsensitiveCompare(response.id) == .orderedSame
                        }) else {
                            report.fail(
                                "Scryfall returned unexpected exact id \(response.id) in migration batch"
                            )
                            continue
                        }
                        let key = requestedID.lowercased()
                        if responseByID[key] != nil {
                            duplicateResponseIDs.insert(key)
                        } else {
                            responseByID[key] = response
                        }
                    }

                    for exactID in batch {
                        let key = exactID.lowercased()
                        guard !duplicateResponseIDs.contains(key),
                              let response = responseByID[key] else {
                            failedExactIDs.insert(key)
                            report.failedExactLookups += 1
                            report.fail(
                                "Exact Scryfall enrichment did not return \(exactID)"
                            )
                            continue
                        }
                        guard response.id.caseInsensitiveCompare(exactID) == .orderedSame else {
                            failedExactIDs.insert(key)
                            report.failedExactLookups += 1
                            report.fail(
                                "Scryfall returned \(response.id) for requested \(exactID)"
                            )
                            continue
                        }
                        evidenceByExactID[key] = ExactEvidence(
                            evidence: response.magicTreatmentEvidence(using: catalog),
                            catalogVariants: response.catalogVariants
                        )
                    }
                } catch {
                    for exactID in batch {
                        failedExactIDs.insert(exactID.lowercased())
                        report.failedExactLookups += 1
                        report.fail(
                            "Exact Scryfall enrichment failed for \(exactID): \(error)"
                        )
                    }
                }
            }
        }

        var plans: [MigrationPair: PairPlan] = [:]
        for card in cards where card.cardGame == .magic {
            guard let parts = descriptors[ObjectIdentifier(card)] else {
                if candidates.contains(where: { $0 === card }) {
                    report.fail("Unrecognised Magic collection key: \(card.collectionKey)")
                }
                continue
            }

            // A treatment-qualified row is already carrying the new identity.
            // It still participates in collision repair and metadata hydration,
            // but it never needs a network request.
            if parts.isTreatmentQualified {
                let hasPendingLegacyRow = candidates.contains {
                    $0 !== card && $0.collectionKey == parts.baseKey
                }
                guard card.magicTreatmentMigrationVersion < currentVersion
                    || hasPendingLegacyRow else {
                    continue
                }
                guard treatmentIDsAreFinishCompatible(
                    parts.treatmentIDs,
                    card: card,
                    parts: parts
                ) else {
                    report.fail(
                        "Treatment ids do not match the finish in \(card.collectionKey)"
                    )
                    continue
                }
                let normalizedKey = parts.canonicalKey
                let qualifiers = mergedReviewedQualifiers(
                    for: card,
                    parts: parts,
                    treatmentIDs: parts.treatmentIDs,
                    catalog: catalog
                )
                addPlan(
                    for: MigrationPair(oldKey: parts.baseKey, newKey: normalizedKey),
                    treatmentIDs: parts.treatmentIDs,
                    qualifiers: qualifiers,
                    finishID: card.variant?.id ?? parts.finishID,
                    to: &plans,
                    report: &report
                )
                continue
            }

            guard candidates.contains(where: { $0 === card }) else { continue }

            let existingIDs = existingTreatmentIDs(for: card)
            if !existingIDs.isEmpty {
                guard treatmentIDsAreFinishCompatible(
                    existingIDs,
                    card: card,
                    parts: parts
                ) else {
                    report.fail(
                        "Stored treatment ids do not match the finish in \(card.collectionKey)"
                    )
                    continue
                }
                if let newKey = treatmentQualifiedKey(
                    for: card,
                    parts: parts,
                    treatmentIDs: existingIDs
                ) {
                    let qualifiers = mergedReviewedQualifiers(
                        for: card,
                        parts: parts,
                        treatmentIDs: existingIDs,
                        catalog: catalog
                    )
                    addPlan(
                        for: MigrationPair(oldKey: card.collectionKey, newKey: newKey),
                        treatmentIDs: existingIDs,
                        qualifiers: qualifiers,
                        finishID: card.variant?.id ?? parts.finishID,
                        to: &plans,
                        report: &report
                    )
                } else {
                    report.fail("Could not derive a finish-qualified key for \(card.collectionKey)")
                }
                continue
            }

            guard let exactID = parts.exactPrintingID else {
                // Imported/provider-native identities and sealed product
                // identities are valid legacy rows, but they do not prove a
                // Scryfall printing. Never enrich them from set/number or from
                // a vendor string that only happens to contain colons.
                card.magicTreatmentMigrationVersion = currentVersion
                continue
            }
            guard !failedExactIDs.contains(exactID.lowercased()),
                  let exactEvidence = evidenceByExactID[exactID.lowercased()] else {
                continue
            }
            guard let metadata = treatmentMetadata(
                for: card,
                parts: parts,
                exactEvidence: exactEvidence
            ) else {
                // A successful exact response with no applicable treatment, a
                // dual-finish nonfoil row, and a missing finish are all known
                // no-op outcomes. None should be fetched again on every launch.
                card.magicTreatmentMigrationVersion = currentVersion
                continue
            }
            guard let newKey = treatmentQualifiedKey(
                for: card,
                parts: parts,
                treatmentIDs: metadata.treatmentIDs,
                finish: metadata.finish
            ) else {
                report.fail("Could not derive a treatment-qualified key for \(card.collectionKey)")
                continue
            }
            addPlan(
                for: MigrationPair(oldKey: card.collectionKey, newKey: newKey),
                treatmentIDs: metadata.treatmentIDs,
                qualifiers: metadata.qualifiers,
                finishID: metadata.finish?.id,
                to: &plans,
                report: &report
            )
        }

        let pairCountsByLegacyKey = Dictionary(
            grouping: plans.keys,
            by: \.oldKey
        ).mapValues(\.count)
        for pair in plans.keys.sorted(by: pairSort) {
            guard let plan = plans[pair] else { continue }
            do {
                try process(
                    pair,
                    plan: plan,
                    hasAmbiguousLegacyPair: pairCountsByLegacyKey[pair.oldKey, default: 0] > 1,
                    context: context,
                    now: now,
                    report: &report
                )
            } catch {
                report.fail("Could not migrate \(pair.oldKey) to \(pair.newKey): \(error)")
            }
        }

        do {
            if context.hasChanges {
                try context.save()
            }
        } catch {
            context.rollback()
            report.fail("Magic treatment migration could not be saved: \(error)")
        }
        return report
    }

    // MARK: - Planning

    private struct PairPlan: Sendable {
        var treatmentIDs: [String]
        var qualifiers: [String: String]
        /// The exact finish that makes a raw treatment applicable. It is
        /// carried separately from the treatment ids so a bare legacy row can
        /// be safely compared with a canonical foil row after exact enrichment.
        var finishID: String?
    }

    /// A fully decoded history rewrite. Preparing these values before changing
    /// any SwiftData object keeps a malformed removal snapshot from leaving a
    /// partially retargeted history projection behind a failed migration.
    private struct PreparedActivityRetarget {
        let activity: CollectionActivity
        let removalSnapshotData: Data?
    }

    /// A deterministic correction activity is prepared separately from its
    /// insertion. That lets collision validation finish before either ledger
    /// leg or history object is mutated.
    private struct PreparedCorrectionActivity {
        let id: UUID
        let existing: CollectionActivity?
        let quantity: Int
        let operationID: UUID
        let occurredAt: Date
    }

    private struct ExactEvidence: Sendable {
        let evidence: MagicTreatmentEvidence
        /// Nil for the local compact-catalog path. Graded rows require the
        /// provider's finish list before a treatment can be attached.
        let catalogVariants: [PhysicalVariant]?
    }

    private struct TreatmentMetadata: Sendable {
        let treatmentIDs: [String]
        let qualifiers: [String: String]
        let finish: PhysicalVariant?
    }

    private enum MigrationError: LocalizedError {
        case multipleRows(String)
        case ambiguousLegacy(String)
        case conflictingIdentity(String)
        case unbalancedSource(String)
        case unbalancedDestination(String)
        case incompatibleActivities(String)
        case ledgerWrite(String)

        var errorDescription: String? {
            switch self {
            case let .multipleRows(key):
                return "more than one collection row claims \(key)"
            case let .ambiguousLegacy(key):
                return "more than one treatment-qualified position claims legacy key \(key)"
            case let .conflictingIdentity(detail):
                return detail
            case let .unbalancedSource(key):
                return "source ledger does not balance with \(key)"
            case let .unbalancedDestination(key):
                return "destination ledger does not balance with \(key)"
            case let .incompatibleActivities(detail):
                return detail
            case let .ledgerWrite(detail):
                return detail
            }
        }
    }

    private static func addPlan(
        for pair: MigrationPair,
        treatmentIDs: [String],
        qualifiers: [String: String],
        finishID: String?,
        to plans: inout [MigrationPair: PairPlan],
        report: inout Report
    ) {
        let storedIDs = MagicTreatmentKeyCodec.storedIDs(from: treatmentIDs)
        let targetSet = Set(MagicTreatmentKeyCodec.canonicalIDs(from: storedIDs))
        guard !targetSet.isEmpty else { return }
        let storedQualifiers = MagicTreatmentKeyCodec.storedQualifiers(from: qualifiers)
            .filter { targetSet.contains($0.key) }

        if var existing = plans[pair] {
            let existingSet = Set(
                MagicTreatmentKeyCodec.canonicalIDs(from: existing.treatmentIDs)
            )
            guard existingSet == targetSet else {
                report.fail("Treatment evidence disagrees for migration pair \(pair.oldKey) -> \(pair.newKey)")
                return
            }
            for (key, value) in storedQualifiers {
                if let prior = existing.qualifiers[key], prior != value {
                    report.fail("Treatment qualifier disagrees for migration pair \(pair.oldKey) -> \(pair.newKey)")
                    return
                }
                existing.qualifiers[key] = value
            }
            if let existingFinishID = existing.finishID,
               let finishID,
               existingFinishID.caseInsensitiveCompare(finishID) != .orderedSame {
                report.fail("Finish evidence disagrees for migration pair \(pair.oldKey) -> \(pair.newKey)")
                return
            }
            if existing.finishID == nil { existing.finishID = finishID }
            plans[pair] = existing
        } else {
            plans[pair] = PairPlan(
                treatmentIDs: storedIDs,
                qualifiers: storedQualifiers,
                finishID: finishID
            )
        }
    }

    private static func treatmentMetadata(
        for card: CollectedCard,
        parts: MagicCollectionKeyParts,
        exactEvidence: ExactEvidence
    ) -> TreatmentMetadata? {
        let finish: PhysicalVariant?
        switch card.itemKind {
        case .rawCard:
            if let rowFinish = card.variant {
                if let keyFinish = parts.finishID,
                   rowFinish.id.caseInsensitiveCompare(keyFinish) != .orderedSame {
                    return nil
                }
                finish = rowFinish
            } else if let keyFinish = parts.finishID {
                finish = PhysicalVariant(id: keyFinish, label: keyFinish.capitalized)
            } else {
                // A bare legacy raw row has an exact Scryfall id but no
                // selected finish. It is safe to enrich only when the exact
                // response proves that this printing has one finish; a
                // dual-finish response cannot tell us which physical copy the
                // old row represents.
                guard let variants = exactEvidence.catalogVariants,
                      variants.count == 1 else { return nil }
                finish = variants.first
            }
        case .gradedCard:
            // A graded row has no raw finish selector. The exact provider
            // response must publish one and only one finish before its foil-only
            // treatment can be attached.
            guard let variants = exactEvidence.catalogVariants,
                  variants.count == 1 else { return nil }
            finish = variants.first
        case .sealedProduct:
            return nil
        }

        let applicable = exactEvidence.evidence.applicableTreatments(for: finish)
        let treatmentIDs = MagicTreatmentKeyCodec.storedIDs(from: applicable)
        guard !treatmentIDs.isEmpty else { return nil }
        let treatmentSet = Set(MagicTreatmentKeyCodec.canonicalIDs(from: treatmentIDs))
        var qualifiers: [String: String] = [:]
        for treatment in applicable {
            guard treatmentSet.contains(treatment.id),
                  let qualifier = exactEvidence.evidence.qualifier(for: treatment) else {
                continue
            }
            qualifiers[treatment.id] = qualifier
        }
        return TreatmentMetadata(
            treatmentIDs: treatmentIDs,
            qualifiers: qualifiers,
            finish: finish
        )
    }

    /// A persisted treatment is trusted only when its known finish relationship
    /// agrees with the raw row/key. Unknown treatments have no asserted finish
    /// and therefore remain valid on any finish-bearing identity. Graded and
    /// sealed rows have no raw finish selector, so their persisted treatment
    /// identity is already the strongest available evidence.
    private static func treatmentIDsAreFinishCompatible(
        _ treatmentIDs: [String],
        card: CollectedCard,
        parts: MagicCollectionKeyParts
    ) -> Bool {
        guard card.itemKind == .rawCard else { return true }

        let finish: PhysicalVariant?
        if let rowFinish = card.variant {
            if let keyFinish = parts.finishID,
               rowFinish.id.caseInsensitiveCompare(keyFinish) != .orderedSame {
                return false
            }
            finish = rowFinish
        } else {
            finish = parts.finishID.map {
                PhysicalVariant(id: $0, label: $0.capitalized)
            }
        }
        guard let finish else { return false }

        let treatments = MagicTreatmentKeyCodec.storedIDs(from: treatmentIDs)
            .compactMap(MagicTreatment.init(id:))
        let applicable = MagicTreatmentEvidence(treatments: treatments)
            .applicableTreatments(for: finish)
        return Set(MagicTreatmentKeyCodec.canonicalIDs(from: treatments))
            == Set(MagicTreatmentKeyCodec.canonicalIDs(from: applicable))
    }

    private static func existingTreatmentIDs(for card: CollectedCard) -> [String] {
        guard card.cardGame == .magic else { return [] }
        switch card.itemKind {
        case .rawCard:
            return MagicTreatmentKeyCodec.storedIDs(from: card.magicTreatmentIDsRaw)
        case .gradedCard, .sealedProduct:
            return MagicTreatmentKeyCodec.storedIDs(from: card.magicTreatments)
        }
    }

    /// A canonical treated row may have been written before a reviewed
    /// qualifier (such as a Neon Ink color) was added to the compact catalog.
    /// Hydrate only from the exact id already present in the collection key,
    /// and only when the catalog's integrity fields agree with the row. Existing
    /// row values win so a later artifact cannot silently overwrite persisted
    /// evidence with a different qualifier.
    private static func mergedReviewedQualifiers(
        for card: CollectedCard,
        parts: MagicCollectionKeyParts,
        treatmentIDs: [String],
        catalog: MagicTreatmentCatalog
    ) -> [String: String] {
        var merged = card.magicTreatmentQualifiers
        guard let exactID = parts.exactPrintingID,
              let entry = catalog.entry(forCardID: exactID),
              entry.setCode.caseInsensitiveCompare(card.setCode) == .orderedSame,
              entry.collectorNumber.caseInsensitiveCompare(card.cardNumber)
                == .orderedSame else {
            return merged
        }
        let treatmentSet = Set(MagicTreatmentKeyCodec.canonicalIDs(from: treatmentIDs))
        for (key, value) in MagicTreatmentKeyCodec.storedQualifiers(from: entry.qualifiers)
            where treatmentSet.contains(key) && merged[key] == nil {
            merged[key] = value
        }
        return merged
    }

    private static func treatmentQualifiedKey(
        for card: CollectedCard,
        parts: MagicCollectionKeyParts,
        treatmentIDs: [String],
        finish: PhysicalVariant? = nil
    ) -> String? {
        guard !treatmentIDs.isEmpty else { return nil }
        switch parts.shape {
        case .rawLegacy, .rawFinish, .rawFinishTreatment, .rawImported:
            let finishID = card.variant?.id ?? parts.finishID ?? finish?.id
            guard let finishID, !finishID.isEmpty else { return nil }
            let base = parts.baseKey.contains("#")
                ? parts.baseKey
                : "\(parts.baseKey)#\(finishID)"
            return MagicTreatmentKeyCodec.appendCollectionSuffix(
                to: base,
                rawIDs: treatmentIDs
            )
        case .graded, .gradedCertified, .sealed, .gradedImported, .sealedImported:
            return MagicTreatmentKeyCodec.appendCollectionSuffix(
                to: parts.baseKey,
                rawIDs: treatmentIDs
            )
        }
    }

    // MARK: - Applying a pair

    private static func process(
        _ pair: MigrationPair,
        plan: PairPlan,
        hasAmbiguousLegacyPair: Bool,
        context: ModelContext,
        now: Date,
        report: inout Report
    ) throws {
        let legacyRows = try rows(for: pair.oldKey, in: context)
        let canonicalRows = try rows(for: pair.newKey, in: context)

        guard canonicalRows.count <= 1 else {
            throw MigrationError.multipleRows(pair.newKey)
        }

        guard !hasAmbiguousLegacyPair || legacyRows.isEmpty else {
            // A treatment-free row cannot be assigned to one of multiple
            // treatment-qualified destinations without a persisted finish and
            // treatment proof. Leave every row and lineage untouched instead of
            // making the sorted plan order decide ownership.
            throw MigrationError.ambiguousLegacy(pair.oldKey)
        }

        if legacyRows.isEmpty, let canonical = canonicalRows.first {
            let changed = try applyTreatmentMetadata(
                to: canonical,
                treatmentIDs: plan.treatmentIDs,
                qualifiers: plan.qualifiers
            )
            restoreRawFinishIfNeeded(on: canonical, canonicalKey: pair.newKey)
            canonical.magicTreatmentMigrationVersion = currentVersion
            if changed { report.enrichedRows += 1 }
            return
        }

        guard !legacyRows.isEmpty else { return }
        guard legacyRows.count == 1 else {
            throw MigrationError.multipleRows(pair.oldKey)
        }

        if let canonical = canonicalRows.first {
            try mergeCollision(
                legacyRows: legacyRows,
                canonicalRow: canonical,
                pair: pair,
                plan: plan,
                context: context,
                now: now,
                report: &report
            )
            return
        }

        let legacy = legacyRows[0]
        let changed = try validateTreatmentMetadata(
            legacy,
            treatmentIDs: plan.treatmentIDs,
            qualifiers: plan.qualifiers
        )
        let store = CollectionStore(context: context)
        try store.rekey(
            legacy,
            to: pair.newKey,
            magicTreatmentIDsRaw: plan.treatmentIDs,
            magicTreatmentQualifiers: plan.qualifiers
        )
        let rekeyed = legacy
        restoreRawFinishIfNeeded(on: rekeyed, canonicalKey: pair.newKey)
        let qualifierChanged = try applyTreatmentMetadata(
            to: rekeyed,
            treatmentIDs: plan.treatmentIDs,
            qualifiers: plan.qualifiers
        )
        rekeyed.magicTreatmentMigrationVersion = currentVersion
        if changed || qualifierChanged { report.enrichedRows += 1 }
        report.rekeyedRows += 1
    }

    private static func mergeCollision(
        legacyRows: [CollectedCard],
        canonicalRow: CollectedCard,
        pair: MigrationPair,
        plan: PairPlan,
        context: ModelContext,
        now: Date,
        report: inout Report
    ) throws {
        let allRows = legacyRows + [canonicalRow]
        let sourceIsCertified = MagicTreatmentKeyCodec
            .collectionKeyParts(from: pair.oldKey)?.isCertified == true
        let destinationIsCertified = MagicTreatmentKeyCodec
            .collectionKeyParts(from: pair.newKey)?.isCertified == true
        guard !sourceIsCertified,
              !destinationIsCertified,
              allRows.allSatisfy({ $0.allowsQuantityAggregation }) else {
            // Certified rows are intentionally left alone. Marking them as
            // passed prevents a known-safe non-merge from retrying forever;
            // the collision remains visible to CollectionStore's normal
            // integrity diagnostic.
            for row in allRows { row.magicTreatmentMigrationVersion = currentVersion }
            report.skippedCertifiedCollisions += 1
            return
        }
        guard legacyRows.allSatisfy({ $0.quantity > 0 }), canonicalRow.quantity >= 0 else {
            throw MigrationError.conflictingIdentity("non-positive quantity in \(pair.oldKey)")
        }
        guard legacyRows.allSatisfy({
            compatibleIdentity($0, canonicalRow, fallbackRawFinishID: plan.finishID)
        }) else {
            throw MigrationError.conflictingIdentity(
                "canonical and legacy rows disagree about the physical object"
            )
        }

        let targetTreatmentSet = Set(
            MagicTreatmentKeyCodec.canonicalIDs(from: plan.treatmentIDs)
        )
        var collisionQualifiers = plan.qualifiers
        for row in allRows {
            for (key, value) in row.magicTreatmentQualifiers
                where targetTreatmentSet.contains(key) {
                if let existing = collisionQualifiers[key], existing != value {
                    throw MigrationError.conflictingIdentity(
                        "treatment qualifier disagrees while merging \(pair.oldKey)"
                    )
                }
                collisionQualifiers[key] = value
            }
        }
        let nonRegularContentKinds = Set(
            allRows
                .map(\.magicContentKindRaw)
                .filter { $0 != MagicContentKind.regular.rawValue }
        )
        guard nonRegularContentKinds.count <= 1 else {
            throw MigrationError.conflictingIdentity(
                "canonical and legacy rows disagree about printed content kind"
            )
        }
        let resolvedContentKindRaw = nonRegularContentKinds.first

        let changed = try validateTreatmentMetadata(
            canonicalRow,
            treatmentIDs: plan.treatmentIDs,
            qualifiers: collisionQualifiers
        )
        for row in legacyRows {
            _ = try validateTreatmentMetadata(
                row,
                treatmentIDs: plan.treatmentIDs,
                qualifiers: collisionQualifiers
            )
        }

        let ledger = InventoryLedger(context: context)
        let sourceEventsIncludingMigration = try ledger.events(collectionKey: pair.oldKey)
        let destinationEventsIncludingMigration = try ledger.events(collectionKey: pair.newKey)
        let sourceQuantity = legacyRows.reduce(0) { $0 + $1.quantity }
        let destinationQuantity = canonicalRow.quantity
        let correctionOperationID = operationID(
            sourceRecordIdentity: sourceRecordIdentity(for: legacyRows[0]),
            oldKey: pair.oldKey,
            newKey: pair.newKey
        )

        // A previous device may already have synced one or both correction
        // legs. Exclude only this deterministic operation while validating the
        // pre-correction lineages; all other events remain part of the ledger
        // balance. The leg payload is checked again below before any retry is
        // appended, so a same-key/different-payload sync conflict is surfaced.
        let existingCorrectionEvents = try ledger.events(
            forOperationID: correctionOperationID
        )
        let existingCorrectionEventsByKey = Dictionary(
            grouping: existingCorrectionEvents,
            by: \.idempotencyKey
        )
        let expectedCorrectionLegKeys = Set(
            [InventoryCorrectionLeg.from, .to].map {
                InventoryEvent.idempotencyKey(
                    operationID: correctionOperationID,
                    leg: $0
                )
            }
        )
        let correctionLegGroupsAreValid = existingCorrectionEventsByKey.values.allSatisfy {
            group in
            guard let first = group.first,
                  expectedCorrectionLegKeys.contains(first.idempotencyKey),
                  first.operationID == correctionOperationID,
                  first.kind == .correction,
                  let firstLeg = first.leg else {
                return false
            }
            return group.allSatisfy {
                $0.operationID == correctionOperationID
                    && $0.kind == .correction
                    && $0.leg == firstLeg
                    && $0.idempotencyKey == first.idempotencyKey
                    && $0.payload == first.payload
            }
        }
        let existingCorrectionLegs = Set(
            existingCorrectionEventsByKey.values.compactMap { $0.first?.leg }
        )
        guard existingCorrectionEventsByKey.count <= 2,
              correctionLegGroupsAreValid,
              existingCorrectionLegs.count == existingCorrectionEventsByKey.count else {
            throw MigrationError.ledgerWrite(
                "migration operation \(correctionOperationID.uuidString) has conflicting correction legs"
            )
        }

        let isPreLedgerMerge = sourceEventsIncludingMigration.isEmpty
            && destinationEventsIncludingMigration.isEmpty
            && existingCorrectionEvents.isEmpty
        if isPreLedgerMerge {
            // ContentView runs this before PortfolioEpoch establishes its
            // baseline. A legacy collection can therefore have activity rows
            // but no ownership events yet. It is safe to consolidate that
            // pre-ledger state; the later baseline will be created from the
            // single canonical row. If any event exists elsewhere, however,
            // this position is missing lineage and must not be guessed.
            let hasAnyLedgerEvent = try ledger.hasAnyEvent()
            guard !hasAnyLedgerEvent else {
                throw MigrationError.unbalancedSource(pair.oldKey)
            }
        }

        let sourceEvents = sourceEventsIncludingMigration.filter {
            $0.operationID != correctionOperationID
        }
        let destinationEvents = destinationEventsIncludingMigration.filter {
            $0.operationID != correctionOperationID
        }
        let sourceLedgerQuantity = sourceEvents.reduce(0) { $0 + $1.deltaQuantity }
        let destinationLedgerQuantity = destinationEvents.reduce(0) { $0 + $1.deltaQuantity }

        if !sourceEvents.isEmpty, sourceLedgerQuantity != sourceQuantity {
            throw MigrationError.unbalancedSource(pair.oldKey)
        }
        // A source with no ownership lineage can only be merged before the
        // destination has entered the ledger. Otherwise adding its quantity
        // would make a later correction look like an unexplained acquisition.
        if sourceEvents.isEmpty, !existingCorrectionEvents.isEmpty {
            throw MigrationError.unbalancedSource(pair.oldKey)
        }
        if sourceEvents.isEmpty, !destinationEvents.isEmpty {
            throw MigrationError.unbalancedSource(pair.oldKey)
        }

        let destinationAlreadyIncludesSource =
            !existingCorrectionEvents.isEmpty
                && destinationQuantity == destinationLedgerQuantity + sourceQuantity
        guard isPreLedgerMerge
                || destinationQuantity == destinationLedgerQuantity
                || destinationAlreadyIncludesSource else {
            throw MigrationError.unbalancedDestination(pair.newKey)
        }

        let sourceActivities = try activities(for: pair.oldKey, in: context)
        let destinationActivities = try activities(for: pair.newKey, in: context)
        if isPreLedgerMerge {
            if !sourceActivities.isEmpty,
               sourceActivities.reduce(0, { $0 + $1.signedQuantity }) != sourceQuantity {
                throw MigrationError.incompatibleActivities(
                    "source history does not balance with \(pair.oldKey)"
                )
            }
            if !destinationActivities.isEmpty,
               destinationActivities.reduce(0, { $0 + $1.signedQuantity }) != destinationQuantity {
                throw MigrationError.incompatibleActivities(
                    "destination history does not balance with \(pair.newKey)"
                )
            }
        }
        if !sourceEvents.isEmpty,
           !sourceActivities.isEmpty,
           sourceActivities.reduce(0, { $0 + $1.signedQuantity }) != sourceLedgerQuantity {
            throw MigrationError.incompatibleActivities(
                "source history does not balance with \(pair.oldKey)"
            )
        }
        if existingCorrectionEvents.isEmpty,
           !destinationEvents.isEmpty,
           !destinationActivities.isEmpty,
           destinationActivities.reduce(0, { $0 + $1.signedQuantity }) != destinationLedgerQuantity {
            throw MigrationError.incompatibleActivities(
                "destination history does not balance with \(pair.newKey)"
            )
        }
        if !sourceEvents.isEmpty, destinationEvents.isEmpty, !destinationActivities.isEmpty,
           existingCorrectionEvents.isEmpty {
            throw MigrationError.incompatibleActivities(
                "destination history has no ledger lineage for \(pair.newKey)"
            )
        }

        let oldPriceKeys = Set(sourceEvents.map(\.priceStorageKey))
        guard oldPriceKeys.count <= 1 else {
            throw MigrationError.conflictingIdentity(
                "source lineage uses multiple price identities for \(pair.oldKey)"
            )
        }

        let correctionDate = sourceEvents.map(\.occurredAt).max()
            ?? legacyRows.map(\.dateAdded).max()
            ?? now

        // All decoding, identity checks, ledger-balance checks, and
        // idempotency-payload checks happen before the first mutation. Once
        // this point is reached, the remaining operations are assignments,
        // inserts, and deletes that cannot introduce a new validation error.
        let preparedActivityRetargets = try prepareActivityRetargets(
            sourceActivities,
            from: pair.oldKey,
            to: canonicalRow,
            treatmentIDs: plan.treatmentIDs,
            qualifiers: collisionQualifiers
        )
        let preparedCorrectionActivity: PreparedCorrectionActivity?
        let sourceOperationIDs = Set(sourceEvents.map(\.operationID))
        let destinationActivityOperationIDs = Set(
            destinationActivities.flatMap(\.ledgerOperationIDs)
        )
        let sourceHistoryAlreadyRetargeted = !sourceOperationIDs.isEmpty
            && sourceOperationIDs.isSubset(of: destinationActivityOperationIDs)
        if sourceActivities.isEmpty,
           !sourceEvents.isEmpty,
           !sourceHistoryAlreadyRetargeted {
            preparedCorrectionActivity = try prepareCorrectionActivity(
                to: canonicalRow,
                quantity: sourceQuantity,
                operationID: correctionOperationID,
                occurredAt: correctionDate,
                context: context
            )
        } else {
            preparedCorrectionActivity = nil
        }

        let destinationPriceKey = PriceRecord.key(
            game: canonicalRow.cardGame,
            printingID: canonicalRow.priceStorageID,
            variantID: canonicalRow.variantID
                ?? MagicTreatmentKeyCodec.collectionKeyParts(from: pair.newKey)?.finishID,
            treatmentIDs: plan.treatmentIDs
        )
        let correctionLegs: (from: Bool, to: Bool)
        if !sourceEvents.isEmpty {
            let sourcePriceKey = oldPriceKeys.first ?? legacyRows[0].priceKey
            correctionLegs = (
                from: try correctionLegIsNeeded(
                    operationID: correctionOperationID,
                    leg: .from,
                    collectionKey: pair.oldKey,
                    priceStorageKey: sourcePriceKey,
                    deltaQuantity: -sourceQuantity,
                    occurredAt: correctionDate,
                    context: context
                ),
                to: try correctionLegIsNeeded(
                    operationID: correctionOperationID,
                    leg: .to,
                    collectionKey: pair.newKey,
                    priceStorageKey: destinationPriceKey,
                    deltaQuantity: sourceQuantity,
                    occurredAt: correctionDate,
                    context: context
                )
            )
        } else {
            correctionLegs = (from: false, to: false)
        }

        if correctionLegs.from {
            let sourcePriceKey = oldPriceKeys.first ?? legacyRows[0].priceKey
            let from = ledger.record(
                collectionKey: pair.oldKey,
                priceStorageKey: sourcePriceKey,
                valuation: .unpriced,
                kind: .correction,
                source: .correction,
                deltaQuantity: -sourceQuantity,
                operationID: correctionOperationID,
                leg: .from,
                occurredAt: correctionDate
            )
            guard isAccepted(from) else {
                throw MigrationError.ledgerWrite("source correction leg was rejected")
            }
        }
        if correctionLegs.to {
            let to = ledger.record(
                collectionKey: pair.newKey,
                priceStorageKey: destinationPriceKey,
                valuation: .unpriced,
                kind: .correction,
                source: .correction,
                deltaQuantity: sourceQuantity,
                operationID: correctionOperationID,
                leg: .to,
                occurredAt: correctionDate
            )
            guard isAccepted(to) else {
                // The payload was preflighted above, so this is only reachable
                // if the context is mutated re-entrantly during this method.
                // Keep the staged operation safe if that ever happens.
                if correctionLegs.from,
                   let operationEvents = try? ledger.events(forOperationID: correctionOperationID),
                   let stagedFrom = operationEvents.first(where: { $0.leg == .from }) {
                    context.delete(stagedFrom)
                }
                throw MigrationError.ledgerWrite("destination correction leg was rejected")
            }
        }

        _ = try applyTreatmentMetadata(
            to: canonicalRow,
            treatmentIDs: plan.treatmentIDs,
            qualifiers: collisionQualifiers
        )
        if let resolvedContentKindRaw {
            canonicalRow.magicContentKindRaw = resolvedContentKindRaw
        }
        restoreRawFinishIfNeeded(on: canonicalRow, canonicalKey: pair.newKey)
        applyActivityRetargets(
            preparedActivityRetargets,
            to: canonicalRow,
            treatmentIDs: plan.treatmentIDs,
            qualifiers: collisionQualifiers
        )

        if let preparedCorrectionActivity {
            applyCorrectionActivity(preparedCorrectionActivity, to: canonicalRow, context: context)
        }

        if !destinationAlreadyIncludesSource {
            canonicalRow.quantity += sourceQuantity
        }
        canonicalRow.magicTreatmentMigrationVersion = currentVersion
        for row in legacyRows {
            context.delete(row)
        }
        if changed { report.enrichedRows += 1 }
        report.mergedCollisions += 1
    }

    private static func compatibleIdentity(
        _ left: CollectedCard,
        _ right: CollectedCard,
        fallbackRawFinishID: String? = nil
    ) -> Bool {
        let leftVariantID = left.variantID
            ?? (left.itemKind == .rawCard ? fallbackRawFinishID : nil)
        let rightVariantID = right.variantID
            ?? (right.itemKind == .rawCard ? fallbackRawFinishID : nil)
        return left.game == right.game
            && left.itemKindRaw == right.itemKindRaw
            && left.providerID.caseInsensitiveCompare(right.providerID) == .orderedSame
            && compatibleVariantIdentity(leftVariantID, rightVariantID)
            && left.certificationNumber == right.certificationNumber
            && compatibleOptionalIdentity(left.justTCGCardID, right.justTCGCardID)
            && compatibleOptionalIdentity(left.justTCGVariantID, right.justTCGVariantID)
            && compatibleOptionalIdentity(left.justTCGAPIVersion, right.justTCGAPIVersion)
            && compatibleOptionalIdentity(left.gradingCompanyRaw, right.gradingCompanyRaw)
            && compatibleOptionalIdentity(left.gradeRaw, right.gradeRaw)
            && compatibleOptionalIdentity(left.gradingQualifier, right.gradingQualifier)
    }

    private static func compatibleOptionalIdentity(_ left: String?, _ right: String?) -> Bool {
        switch (left, right) {
        case (nil, nil):
            return true
        case let (left?, right?):
            return left.caseInsensitiveCompare(right) == .orderedSame
        default:
            // A missing field is not evidence that two physical identities
            // agree. This is especially important for graded rows, where an
            // absent grade must not silently match a row with a grade.
            return false
        }
    }

    private static func compatibleVariantIdentity(_ left: String?, _ right: String?) -> Bool {
        switch (left, right) {
        case (nil, nil): return true
        case let (left?, right?):
            return left.caseInsensitiveCompare(right) == .orderedSame
        default:
            return false
        }
    }

    /// A legacy raw row can have a finish in its collection key but no mirrored
    /// `variantID` after an interrupted older write. The key is already the
    /// authoritative identity in that case, so restoring this non-treatment
    /// field keeps future price/key derivation consistent without guessing a
    /// treatment.
    private static func restoreRawFinishIfNeeded(
        on row: CollectedCard,
        canonicalKey: String
    ) {
        guard row.itemKind == .rawCard,
              row.variantID == nil,
              let finishID = MagicTreatmentKeyCodec
                .collectionKeyParts(from: canonicalKey)?.finishID else {
            return
        }
        row.variantID = finishID
        row.variantLabel = finishID.capitalized
    }

    private static func applyTreatmentMetadata(
        to row: CollectedCard,
        treatmentIDs: [String],
        qualifiers: [String: String]
    ) throws -> Bool {
        let changed = try validateTreatmentMetadata(
            row,
            treatmentIDs: treatmentIDs,
            qualifiers: qualifiers
        )
        let normalizedIDs = MagicTreatmentKeyCodec.storedIDs(from: treatmentIDs)
        if row.magicTreatmentIDsRaw.isEmpty {
            row.magicTreatmentIDsRaw = normalizedIDs
        }
        var mergedQualifiers = row.magicTreatmentQualifiers
        for (key, value) in MagicTreatmentKeyCodec.storedQualifiers(from: qualifiers) {
            mergedQualifiers[key] = value
        }
        if !mergedQualifiers.isEmpty {
            row.magicTreatmentQualifiers = mergedQualifiers
        }
        return changed
    }

    private static func validateTreatmentMetadata(
        _ row: CollectedCard,
        treatmentIDs: [String],
        qualifiers: [String: String]
    ) throws -> Bool {
        let targetIDs = MagicTreatmentKeyCodec.storedIDs(from: treatmentIDs)
        let targetSet = Set(MagicTreatmentKeyCodec.canonicalIDs(from: targetIDs))
        let existingIDs = MagicTreatmentKeyCodec.storedIDs(from: row.magicTreatmentIDsRaw)
        let existingSet = Set(MagicTreatmentKeyCodec.canonicalIDs(from: existingIDs))
        guard existingSet.isEmpty || existingSet == targetSet else {
            throw MigrationError.conflictingIdentity(
                "stored treatment ids disagree with \(row.collectionKey)"
            )
        }

        let existingQualifiers = row.magicTreatmentQualifiers
        let requestedQualifiers = MagicTreatmentKeyCodec.storedQualifiers(from: qualifiers)
            .filter { targetSet.contains($0.key) }
        for (key, value) in existingQualifiers where targetSet.contains(key) {
            if let requested = requestedQualifiers[key], requested != value {
                throw MigrationError.conflictingIdentity(
                    "stored treatment qualifier disagrees with \(row.collectionKey)"
                )
            }
        }
        return existingSet.isEmpty
            || requestedQualifiers.contains { existingQualifiers[$0.key] == nil }
    }

    // MARK: - History and identity cleanup

    private static func prepareActivityRetargets(
        _ activities: [CollectionActivity],
        from oldKey: String,
        to row: CollectedCard,
        treatmentIDs: [String],
        qualifiers: [String: String]
    ) throws -> [PreparedActivityRetarget] {
        let targetIDs = MagicTreatmentKeyCodec.storedIDs(from: treatmentIDs)
        let targetSet = Set(MagicTreatmentKeyCodec.canonicalIDs(from: targetIDs))
        let targetQualifiers = MagicTreatmentKeyCodec.storedQualifiers(from: qualifiers)
        var prepared: [PreparedActivityRetarget] = []

        for activity in activities {
            let activityIDs = MagicTreatmentKeyCodec.storedIDs(
                from: activity.magicTreatmentIDsRaw
            )
            let activitySet = Set(MagicTreatmentKeyCodec.canonicalIDs(from: activityIDs))
            guard activitySet.isEmpty || activitySet == targetSet else {
                throw MigrationError.incompatibleActivities(
                    "history treatment ids disagree with \(row.collectionKey)"
                )
            }
            let activityQualifiers = activity.magicTreatmentQualifiers
            for (key, value) in activityQualifiers where targetSet.contains(key) {
                if let requested = targetQualifiers[key], requested != value {
                    throw MigrationError.incompatibleActivities(
                        "history treatment qualifier disagrees with \(row.collectionKey)"
                    )
                }
            }
            guard activity.collectionKey == oldKey else {
                throw MigrationError.incompatibleActivities(
                    "history entry \(activity.id.uuidString) points at a different key"
                )
            }

            let preparedSnapshotData: Data?
            if let data = activity.removalSnapshotData {
                guard var snapshot = try? JSONDecoder().decode(
                    RemovedCardSnapshot.self,
                    from: data
                ), snapshot.collectionKey == oldKey || snapshot.collectionKey == row.collectionKey else {
                    throw MigrationError.incompatibleActivities(
                        "removal snapshot for history entry \(activity.id.uuidString) is unreadable"
                    )
                }
                let snapshotIDs = MagicTreatmentKeyCodec.storedIDs(
                    from: snapshot.magicTreatmentIDsRaw ?? []
                )
                let snapshotSet = Set(MagicTreatmentKeyCodec.canonicalIDs(from: snapshotIDs))
                guard snapshotSet.isEmpty || snapshotSet == targetSet else {
                    throw MigrationError.incompatibleActivities(
                        "removal snapshot treatment ids disagree with \(row.collectionKey)"
                    )
                }
                let snapshotQualifiers = MagicTreatmentKeyCodec.decodeQualifiers(
                    snapshot.magicTreatmentQualifiersJSON
                )
                for (key, value) in snapshotQualifiers where targetSet.contains(key) {
                    if let requested = targetQualifiers[key], requested != value {
                        throw MigrationError.incompatibleActivities(
                            "removal snapshot qualifier disagrees with \(row.collectionKey)"
                        )
                    }
                }
                snapshot.collectionKey = row.collectionKey
                if snapshotIDs.isEmpty { snapshot.magicTreatmentIDsRaw = targetIDs }
                if snapshot.variant == nil, row.itemKind == .rawCard {
                    snapshot.variant = row.variant
                }
                if snapshot.magicContentKindRaw == nil,
                   row.magicContentKindRaw != MagicContentKind.regular.rawValue {
                    snapshot.magicContentKindRaw = row.magicContentKindRaw
                }
                var mergedSnapshotQualifiers = snapshotQualifiers
                for (key, value) in targetQualifiers where mergedSnapshotQualifiers[key] == nil {
                    mergedSnapshotQualifiers[key] = value
                }
                if mergedSnapshotQualifiers != snapshotQualifiers {
                    snapshot.magicTreatmentQualifiersJSON =
                        MagicTreatmentKeyCodec.encodeQualifiers(mergedSnapshotQualifiers)
                }
                preparedSnapshotData = try JSONEncoder().encode(snapshot)
            } else {
                preparedSnapshotData = nil
            }

            prepared.append(
                PreparedActivityRetarget(
                    activity: activity,
                    removalSnapshotData: preparedSnapshotData
                )
            )
        }
        return prepared
    }

    private static func applyActivityRetargets(
        _ prepared: [PreparedActivityRetarget],
        to row: CollectedCard,
        treatmentIDs: [String],
        qualifiers: [String: String]
    ) {
        let targetIDs = MagicTreatmentKeyCodec.storedIDs(from: treatmentIDs)
        let targetQualifiers = MagicTreatmentKeyCodec.storedQualifiers(from: qualifiers)

        for rewrite in prepared {
            let activity = rewrite.activity
            let activityIDs = MagicTreatmentKeyCodec.storedIDs(
                from: activity.magicTreatmentIDsRaw
            )
            let activityQualifiers = activity.magicTreatmentQualifiers
            activity.collectionKey = row.collectionKey
            activity.name = row.name
            activity.setName = row.setName
            activity.setCode = row.setCode
            activity.cardNumber = row.cardNumber
            activity.variantID = row.variantID
            activity.variantLabel = row.variantLabel
            if activityIDs.isEmpty { activity.magicTreatmentIDsRaw = targetIDs }
            var mergedActivityQualifiers = activityQualifiers
            for (key, value) in targetQualifiers where mergedActivityQualifiers[key] == nil {
                mergedActivityQualifiers[key] = value
            }
            if mergedActivityQualifiers != activityQualifiers {
                activity.magicTreatmentQualifiersJSON =
                    MagicTreatmentKeyCodec.encodeQualifiers(mergedActivityQualifiers)
            }
            if activity.magicContentKindRaw == MagicContentKind.regular.rawValue,
               row.magicContentKindRaw != MagicContentKind.regular.rawValue {
                activity.magicContentKindRaw = row.magicContentKindRaw
            }
            activity.pokemonPrintRunRaw = row.pokemonPrintRunRaw
            if let removalSnapshotData = rewrite.removalSnapshotData {
                activity.removalSnapshotData = removalSnapshotData
            }
        }
    }

    private static func prepareCorrectionActivity(
        to row: CollectedCard,
        quantity: Int,
        operationID: UUID,
        occurredAt: Date,
        context: ModelContext
    ) throws -> PreparedCorrectionActivity {
        let activityID = deterministicUUID(
            material: [
                "magic-treatment-migration-activity",
                row.collectionKey,
                String(quantity),
                operationID.uuidString
            ].joined(separator: "|")
        )
        let existing = try context.fetch(
            FetchDescriptor<CollectionActivity>(
                predicate: #Predicate { $0.id == activityID }
            )
        )
        if let existing = existing.first {
            guard existing.collectionKey == row.collectionKey,
                  existing.source == .correction,
                  existing.kind == .corrected,
                  existing.quantity == quantity,
                  existing.deltaQuantity == quantity else {
                throw MigrationError.incompatibleActivities(
                    "migration activity id \(activityID.uuidString) has a conflicting payload"
                )
            }
            guard existing.ledgerOperationIDs == [operationID],
                  existing.occurredAt == occurredAt else {
                throw MigrationError.incompatibleActivities(
                    "migration activity id \(activityID.uuidString) has a conflicting payload"
                )
            }
            return PreparedCorrectionActivity(
                id: activityID,
                existing: existing,
                quantity: quantity,
                operationID: operationID,
                occurredAt: occurredAt
            )
        }

        return PreparedCorrectionActivity(
            id: activityID,
            existing: nil,
            quantity: quantity,
            operationID: operationID,
            occurredAt: occurredAt
        )
    }

    private static func applyCorrectionActivity(
        _ prepared: PreparedCorrectionActivity,
        to row: CollectedCard,
        context: ModelContext
    ) {
        guard prepared.existing == nil else { return }
        let activity = CollectionActivity(
            card: row,
            source: .correction,
            quantity: prepared.quantity,
            occurredAt: prepared.occurredAt,
            kind: .corrected,
            deltaQuantity: prepared.quantity,
            ledgerOperationIDs: [prepared.operationID]
        )
        activity.id = prepared.id
        context.insert(activity)
    }

    private static func correctionLegIsNeeded(
        operationID: UUID,
        leg: InventoryCorrectionLeg,
        collectionKey: String,
        priceStorageKey: String,
        deltaQuantity: Int,
        occurredAt: Date,
        context: ModelContext
    ) throws -> Bool {
        let idempotencyKey = InventoryEvent.idempotencyKey(
            operationID: operationID,
            leg: leg
        )
        let matches = try context.fetch(
            FetchDescriptor<InventoryEvent>(
                predicate: #Predicate { $0.idempotencyKey == idempotencyKey }
            )
        )
        let expected = InventoryEventPayload(
            kindRaw: InventoryEventKind.correction.rawValue,
            sourceRaw: CollectionActivitySource.correction.rawValue,
            collectionKey: collectionKey,
            priceStorageKey: priceStorageKey,
            deltaQuantity: deltaQuantity,
            occurredAt: occurredAt,
            unitPriceUSDTenThousandths: nil,
            reversesEventID: nil
        )
        guard matches.allSatisfy({
            $0.operationID == operationID
                && $0.leg == leg
                && $0.payload == expected
        }) else {
            throw MigrationError.ledgerWrite(
                "correction leg \(idempotencyKey) has a conflicting payload"
            )
        }
        return matches.isEmpty
    }

    private static func clearTreatmentVendorNegatives(
        in context: ModelContext,
        report: inout Report
    ) {
        guard let identities = try? context.fetch(FetchDescriptor<ProductIdentity>()) else {
            return
        }
        for identity in identities {
            let isMagicIdentity = identity.key
                .lowercased()
                .hasPrefix("magic:")
            let isTreatmentQualified =
                isMagicIdentity
                    && (MagicTreatmentKeyCodec.containsPriceTreatmentSuffix(in: identity.key)
                        || !identity.magicTreatmentIDsRaw.isEmpty)
            guard identity.vendorCardID == nil,
                  identity.unmatchedAt != nil,
                  isTreatmentQualified else { continue }
            identity.unmatchedAt = nil
            identity.attemptVersion = ProductIdentity.currentAttemptVersion
            report.clearedVendorNegatives += 1
        }
    }

    // MARK: - Reads and deterministic ids

    private static func rows(
        for key: String,
        in context: ModelContext
    ) throws -> [CollectedCard] {
        try context.fetch(
            FetchDescriptor<CollectedCard>(
                predicate: #Predicate { $0.collectionKey == key }
            )
        )
    }

    private static func activities(
        for key: String,
        in context: ModelContext
    ) throws -> [CollectionActivity] {
        try context.fetch(
            FetchDescriptor<CollectionActivity>(
                predicate: #Predicate { $0.collectionKey == key }
            )
        )
    }

    private static func sourceRecordIdentity(for row: CollectedCard) -> String {
        [
            row.game,
            row.collectionKey,
            row.providerID,
            row.itemKindRaw,
            row.certificationNumber ?? "-"
        ]
        .map { "\($0.utf8.count):\($0)" }
        .joined(separator: "|")
    }

    private static func pairSort(_ left: MigrationPair, _ right: MigrationPair) -> Bool {
        if left.oldKey != right.oldKey { return left.oldKey < right.oldKey }
        return left.newKey < right.newKey
    }

    private static func isAccepted(_ outcome: InventoryLedger.WriteOutcome) -> Bool {
        switch outcome {
        case .appended, .duplicate: return true
        case .conflict, .unreadableStore: return false
        }
    }

    nonisolated private static func deterministicUUID(material: String) -> UUID {
        var bytes = Array(Insecure.MD5.hash(data: Data(material.utf8)))
        bytes[6] = (bytes[6] & 0x0F) | 0x30
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private extension MagicCollectionKeyParts {
    var canonicalKey: String {
        guard !treatmentIDs.isEmpty else { return baseKey }
        return MagicTreatmentKeyCodec.appendCollectionSuffix(
            to: baseKey,
            rawIDs: treatmentIDs
        )
    }
}

/// Serializes the treatment migration with work that snapshots price identity.
///
/// Network enrichment deliberately runs after portfolio startup, but the rows
/// it enriches can still be rekeyed while a foreground or background price
/// refresh is being planned. Keeping the migration task here gives every app
/// entry point one gate: target construction happens only after the network
/// phase has finished, so a refresh cannot write a generic price through a
/// treatment-qualified row's superseded key.
@MainActor
final class MagicTreatmentMigrationCoordinator {
    typealias NetworkRunner = @MainActor (
        ModelContext,
        Date
    ) async -> MagicTreatmentMigration.Report

    static let shared = MagicTreatmentMigrationCoordinator()

    private let networkRunner: NetworkRunner
    private var localTask: Task<MagicTreatmentMigration.Report, Never>?
    private var localTaskRevision: Int?
    private var networkTask: Task<MagicTreatmentMigration.Report, Never>?
    private var networkTaskRevision: Int?
    private var localReport: MagicTreatmentMigration.Report?
    private var networkReport: MagicTreatmentMigration.Report?
    private var collectionRevision = 0

    init(
        networkRunner: @escaping NetworkRunner = { context, now in
            await MagicTreatmentMigration.runNetwork(in: context, now: now)
        }
    ) {
        self.networkRunner = networkRunner
    }

    /// A new collection row can arrive after the first migration pass,
    /// including from another CloudKit device. Keep completed reports tied to
    /// the collection revision they examined. An active task may finish, but
    /// its result must not be cached if the collection changed while it ran.
    func invalidateCompletedReports() {
        collectionRevision += 1
        localReport = nil
        networkReport = nil
    }

    /// Runs the local phase once for all callers currently waiting on it.
    /// A network caller also waits for this phase, so the two migration phases
    /// can never mutate the same collection concurrently.
    @discardableResult
    func runLocal(
        in context: ModelContext,
        now: Date = .now
    ) async -> MagicTreatmentMigration.Report {
        while true {
            if let localReport {
                return localReport
            }
            if let networkTask {
                let taskRevision = networkTaskRevision ?? collectionRevision
                let report = await networkTask.value
                guard taskRevision == collectionRevision else { continue }
                return report
            }
            if let localTask {
                let taskRevision = localTaskRevision ?? collectionRevision
                let report = await localTask.value
                guard taskRevision == collectionRevision else { continue }
                return report
            }

            let taskRevision = collectionRevision
            let task = Task { @MainActor in
                await MagicTreatmentMigration.runLocal(in: context, now: now)
            }
            localTask = task
            localTaskRevision = taskRevision
            let report = await task.value
            localTask = nil
            localTaskRevision = nil
            guard taskRevision == collectionRevision else { continue }
            localReport = report
            return report
        }
    }

    /// Runs the deferred network phase once for all callers. The task remains
    /// owned by the coordinator rather than by a view, so a disappearing view
    /// cannot cancel shared migration work while another entry point is waiting
    /// for the same result.
    @discardableResult
    func runNetwork(
        in context: ModelContext,
        now: Date = .now
    ) async -> MagicTreatmentMigration.Report {
        while true {
            if let networkReport {
                return networkReport
            }
            if let networkTask {
                let taskRevision = networkTaskRevision ?? collectionRevision
                let report = await networkTask.value
                guard taskRevision == collectionRevision else { continue }
                return report
            }

            _ = await runLocal(in: context, now: now)
            if let networkReport {
                return networkReport
            }
            if let networkTask {
                let taskRevision = networkTaskRevision ?? collectionRevision
                let report = await networkTask.value
                guard taskRevision == collectionRevision else { continue }
                return report
            }

            let taskRevision = collectionRevision
            let runner = networkRunner
            let task = Task { @MainActor in
                await runner(context, now)
            }
            networkTask = task
            networkTaskRevision = taskRevision
            let report = await task.value
            networkTask = nil
            networkTaskRevision = nil
            guard taskRevision == collectionRevision else { continue }
            networkReport = report
            return report
        }
    }

    /// Builds and executes a price refresh only after treatment migration has
    /// finished. The operation closure is intentionally inside the gate: its
    /// target snapshot must be made after rekeying, not merely its network
    /// writes.
    func withPriceRefresh<Result>(
        in context: ModelContext,
        now: Date = .now,
        operation: @escaping @MainActor () async -> Result
    ) async -> Result {
        _ = await runNetwork(in: context, now: now)
        return await operation()
    }
}
