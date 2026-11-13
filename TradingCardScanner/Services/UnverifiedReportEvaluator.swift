import Foundation

/// Decides, read-only, what a newer catalog means for one unverified report.
///
/// Automatic linking needs genuinely new, unambiguous evidence: a newer
/// catalog revision than the one the report was made against, a structured
/// report that names exactly one catalog variant, and that variant must be one
/// the catalog did not list when the collector reported it missing. Anything
/// weaker goes to the collector or keeps waiting.
enum UnverifiedReportEvaluator {
    enum ReviewReason: String, Equatable, Sendable {
        /// "Other (describe)" or a note: only the collector can match it.
        case describedByCollector
        /// The catalog changed and the printing exists, but nothing matches.
        case noCatalogMatch
        /// The match was already listed when the report was made, so the
        /// catalog has not learned anything new about this card.
        case matchAlreadyKnown
        /// The observed set and number now resolve. Always confirmed by hand.
        case unknownSetResolved
        /// The collector undid an earlier link.
        case previouslyUnlinked
    }

    enum Decision: Equatable, Sendable {
        case waiting
        case needsReview(ReviewReason)
        case autoLink(PhysicalVariant)
    }

    /// - Parameters:
    ///   - baseCard: the report's base printing as the current catalog
    ///     describes it, or `nil` when it cannot be looked up.
    ///   - unknownSetMatch: for an unknown-set report, the catalog printing its
    ///     observed set and number now resolve to, if any.
    static func evaluate(
        _ report: UnverifiedReport,
        catalogRevision: Int,
        baseCard: IdentifiedCard?,
        unknownSetMatch: IdentifiedCard? = nil
    ) -> Decision {
        guard report.isUnderstood, report.linkedAt == nil else { return .waiting }
        if report.unlinkedAt != nil { return .needsReview(.previouslyUnlinked) }
        // The same catalog that could not describe the card cannot now link it.
        if let created = report.catalogRevisionAtCreation, catalogRevision <= created { return .waiting }

        switch report.kind {
        case .unknownSet:
            return unknownSetMatch == nil ? .waiting : .needsReview(.unknownSetResolved)
        case .knownCard:
            guard let baseCard, baseCard.game == .pokemon,
                  baseCard.providerID == report.baseProviderID else { return .waiting }
            guard report.note == nil, let reported = report.reportedVariant else {
                return .needsReview(.describedByCollector)
            }
            let matches = VariantResolver.options(for: baseCard.variantEvidence).filter { $0.id == reported.id }
            guard matches.count == 1, let match = matches.first else { return .needsReview(.noCatalogMatch) }
            guard !report.knownVariantIDsAtCreation.contains(match.id) else {
                return .needsReview(.matchAlreadyKnown)
            }
            return .autoLink(match)
        }
    }

    /// The catalog variants recorded on a new report, so a later revision can
    /// prove it added the variant the collector said was missing.
    static func knownVariantIDs(for baseCard: IdentifiedCard) -> [String] {
        VariantResolver.options(for: baseCard.variantEvidence).map(\.id)
    }
}

/// Runs the evaluator over every unverified report and applies the result
/// through the serialized writer. Reports already evaluated against the
/// current revision are skipped. Catalog lookups are injected so the same
/// pass runs on activation, at launch, and when synced rows arrive.
struct UnverifiedReportReconciler: Sendable {
    typealias CardLookup = @Sendable (_ providerID: String) async -> IdentifiedCard?
    typealias UnknownSetLookup = @Sendable (_ observed: UnverifiedReport.ObservedIdentity) async -> IdentifiedCard?

    let writer: ScannerCollectionWriter
    let baseCard: CardLookup
    let unknownSetMatch: UnknownSetLookup

    struct Outcome: Equatable, Sendable {
        var linked: [UUID] = []
        var needsReview: [UUID] = []
        var linkUnavailable: [UUID] = []
    }

    func run(catalogRevision: Int) async throws -> Outcome {
        var outcome = Outcome()
        for pending in try await writer.pendingReports() {
            try Task.checkCancellation()
            guard let report = UnverifiedReport.decode(pending.reportJSON),
                  report.lastEvaluatedCatalogRevision != catalogRevision else { continue }
            let base = await report.baseProviderID.asyncFlatMap(baseCard)
            let unknown = await report.observed.asyncFlatMap { report.kind == .unknownSet ? await unknownSetMatch($0) : nil }
            let decision = UnverifiedReportEvaluator.evaluate(report, catalogRevision: catalogRevision,
                                                              baseCard: base, unknownSetMatch: unknown)
            do {
                if case let .autoLink(variant) = decision, let base {
                    do {
                        _ = try await writer.linkUnverified(
                            reportID: report.reportID, expectedReportJSON: pending.reportJSON,
                            catalogRevision: catalogRevision, to: base, variant: variant,
                            resolution: .linkedFromReport, setReleaseOrder: base.setReleaseOrder)
                        outcome.linked.append(report.reportID)
                    } catch CollectionStoreError.reportLinkUnavailable {
                        try await writer.recordReportEvaluation(reportID: report.reportID,
                            expectedReportJSON: pending.reportJSON, catalogRevision: catalogRevision,
                            state: .linkUnavailable)
                        outcome.linkUnavailable.append(report.reportID)
                    }
                    continue
                }
                let state: UnverifiedReport.ReviewState
                if case .needsReview = decision { state = .needsReview } else { state = .waiting }
                try await writer.recordReportEvaluation(reportID: report.reportID,
                    expectedReportJSON: pending.reportJSON, catalogRevision: catalogRevision, state: state)
                if state == .needsReview { outcome.needsReview.append(report.reportID) }
            } catch CollectionStoreError.staleReport {
                // Edited, linked or re-evaluated elsewhere meanwhile; the next
                // pass sees the new state.
                continue
            }
        }
        return outcome
    }
}

private extension Optional {
    func asyncFlatMap<U>(_ transform: (Wrapped) async -> U?) async -> U? {
        guard let self else { return nil }
        return await transform(self)
    }
}
