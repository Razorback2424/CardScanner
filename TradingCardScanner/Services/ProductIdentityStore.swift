import Foundation
import OSLog
import SwiftData

private enum ProductIdentitySelection {
    static func authoritativeIdentity(in identities: [ProductIdentity]) -> ProductIdentity? {
        identities.reduce(nil) { incumbent, candidate in
            guard let incumbent else { return candidate }
            let candidateDate = candidate.resolvedAt ?? candidate.unmatchedAt ?? .distantPast
            let incumbentDate = incumbent.resolvedAt ?? incumbent.unmatchedAt ?? .distantPast
            if candidateDate != incumbentDate {
                return candidateDate > incumbentDate ? candidate : incumbent
            }
            if (candidate.vendorCardID != nil) != (incumbent.vendorCardID != nil) {
                return candidate.vendorCardID != nil ? candidate : incumbent
            }
            return (candidate.vendorVariantID ?? "") > (incumbent.vendorVariantID ?? "")
                ? candidate
                : incumbent
        }
    }
}

/// Reads and writes `ProductIdentity` records.
///
/// Separate from `PriceStore` on purpose. A vendor handle and a price have
/// different lifetimes — the handle is resolved once and kept, the price is
/// replaced on every refresh — and keeping the writers apart is what stops one
/// subsystem's bookkeeping from becoming another's retry gate.
/// Context-owned rather than `@MainActor`, matching `PriceStore` and
/// `PriceRefreshDataIndex`: callers must create and use it on the executor that
/// owns its `ModelContext`. The foreground refresh currently owns both on the
/// main actor; the type does not impose that on other context owners.
final class ProductIdentityIndex {
    private(set) var byKey: [String: ProductIdentity]
    private let context: ModelContext
    private(set) var loadedSuccessfully: Bool

    init(context: ModelContext) {
        self.context = context
        let signpostState = PerformanceSignpost.signposter.beginInterval("ProductIdentityIndex.init")
        defer { PerformanceSignpost.signposter.endInterval("ProductIdentityIndex.init", signpostState) }
        self.byKey = [:]
        self.loadedSuccessfully = false
        reload()
    }

    func identity(forKey key: String) -> ProductIdentity? {
        byKey[key]
    }

    func insert(_ identity: ProductIdentity) {
        byKey[identity.key] = identity
    }

    var isUsable: Bool { loadedSuccessfully }

    /// Rollback invalidates references to inserted/deleted model objects. A
    /// refresh worker must rebuild its materialized index before attempting the
    /// next write, otherwise a rolled-back identity can be reused as if it were
    /// durable.
    func reload() {
        do {
            let identities = try context.fetch(FetchDescriptor<ProductIdentity>())
            byKey = Dictionary(grouping: identities, by: \.key)
                .compactMapValues(ProductIdentitySelection.authoritativeIdentity(in:))
            loadedSuccessfully = true
        } catch {
            byKey = [:]
            loadedSuccessfully = false
        }
    }

}

/// Context-owned rather than `@MainActor`. See `ProductIdentityIndex`.
struct ProductIdentityStore {
    let context: ModelContext

    func identity(forKey key: String) -> ProductIdentity? {
        guard let matches = try? context.fetch(
            FetchDescriptor<ProductIdentity>(predicate: #Predicate { $0.key == key })
        ) else { return nil }
        return ProductIdentitySelection.authoritativeIdentity(in: matches)
    }

    /// A write may create a missing identity only after a complete keyed read.
    /// An unreadable fetch returns nil and the caller leaves the context alone;
    /// it is never interpreted as permission to insert another row.
    private func identityForWrite(
        key: String,
        treatmentIDs: [String],
        using index: ProductIdentityIndex?
    ) -> ProductIdentity? {
        if let index, index.isUsable {
            if let existing = index.identity(forKey: key) { return existing }
            // The index is a snapshot. A sibling context may have created the
            // key after it was built, so an indexed miss still needs a keyed
            // read before creation.
            do {
                let matches = try context.fetch(
                    FetchDescriptor<ProductIdentity>(predicate: #Predicate { $0.key == key })
                )
                if let existing = ProductIdentitySelection.authoritativeIdentity(in: matches) {
                    index.insert(existing)
                    return existing
                }
            } catch {
                return nil
            }
            let created = ProductIdentity(
                key: key,
                vendor: .justTCG,
                magicTreatmentIDs: treatmentIDs
            )
            context.insert(created)
            index.insert(created)
            return created
        }

        do {
            let matches = try context.fetch(
                FetchDescriptor<ProductIdentity>(predicate: #Predicate { $0.key == key })
            )
            if let existing = ProductIdentitySelection.authoritativeIdentity(in: matches) {
                index?.insert(existing)
                return existing
            }
            let created = ProductIdentity(
                key: key,
                vendor: .justTCG,
                magicTreatmentIDs: treatmentIDs
            )
            context.insert(created)
            index?.insert(created)
            return created
        } catch {
            return nil
        }
    }

    private func identity(
        forKey key: String,
        using index: ProductIdentityIndex?
    ) -> ProductIdentity? {
        guard let index, index.isUsable else { return identity(forKey: key) }
        if let cached = index.identity(forKey: key) { return cached }
        guard let fetched = try? context.fetch(
            FetchDescriptor<ProductIdentity>(predicate: #Predicate { $0.key == key })
        ) else { return nil }
        let authoritative = ProductIdentitySelection.authoritativeIdentity(in: fetched)
        if let authoritative { index.insert(authoritative) }
        return authoritative
    }

    /// Whether the resolver should look this card up at all.
    ///
    /// A card with a current record — resolved *or* recently unmatched — is
    /// skipped, which is what keeps a collection full of vendor-less cards from
    /// re-running the same fruitless searches on every refresh.
    func needsResolution(
        forKey key: String,
        using index: ProductIdentityIndex? = nil
    ) -> Bool {
        guard let identity = identity(forKey: key, using: index) else { return true }
        return !identity.isCurrent()
    }

    /// The vendor's variant handle, which is what a batch request is built
    /// from. Present means this card can be repriced twenty-to-a-request
    /// instead of one search at a time.
    func cachedVariantID(
        forKey key: String,
        using index: ProductIdentityIndex? = nil
    ) -> String? {
        guard let identity = identity(forKey: key, using: index), identity.isCurrent() else {
            return nil
        }
        return identity.vendorVariantID
    }

    /// Remember what a batched response resolved, so the next refresh can go
    /// straight to the keyed lookup.
    @discardableResult
    func recordBatchResolution(
        forKey key: String,
        cardID: String?,
        variantID: String?,
        treatmentIDs: [String] = [],
        at date: Date = .now,
        using index: ProductIdentityIndex? = nil
    ) -> Bool {
        guard cardID != nil || variantID != nil else { return true }
        guard let identity = identityForWrite(
            key: key,
            treatmentIDs: treatmentIDs,
            using: index
        ) else { return false }
        if identity.magicTreatmentIDsRaw.isEmpty, !treatmentIDs.isEmpty {
            identity.magicTreatmentIDsRaw = MagicTreatmentKeyCodec.storedIDs(from: treatmentIDs)
        }
        identity.attemptVersion = ProductIdentity.currentAttemptVersion
        if let cardID { identity.vendorCardID = cardID }
        if let variantID { identity.vendorVariantID = variantID }
        identity.resolvedAt = date
        identity.unmatchedAt = nil
        return true
    }

    func cachedCardID(
        forKey key: String,
        using index: ProductIdentityIndex? = nil
    ) -> String? {
        guard let identity = identity(forKey: key, using: index), identity.isCurrent() else {
            return nil
        }
        return identity.vendorCardID
    }

    /// Records the outcome of one resolution attempt.
    ///
    /// A miss is written as deliberately as a hit. Network, budget and rate-limit
    /// outcomes write nothing at all: scheduling or transport state is not
    /// evidence about whether the vendor carries the card.
    @discardableResult
    func record(
        _ outcome: ProductPriceOutcome,
        forKey key: String,
        treatmentIDs: [String] = [],
        at date: Date = .now,
        using index: ProductIdentityIndex? = nil
    ) -> Bool {
        switch outcome {
        case .requestFailed, .unsupportedFinish, .unsupportedTreatment, .budgetReached, .rateLimited:
            return true
        case .price, .noListingForVariant, .noProductMatch:
            break
        }

        guard let identity = identityForWrite(
            key: key,
            treatmentIDs: treatmentIDs,
            using: index
        ) else { return false }
        if identity.magicTreatmentIDsRaw.isEmpty, !treatmentIDs.isEmpty {
            identity.magicTreatmentIDsRaw = MagicTreatmentKeyCodec.storedIDs(from: treatmentIDs)
        }

        identity.attemptVersion = ProductIdentity.currentAttemptVersion

        switch outcome {
        case let .price(_, vendorCardID, vendorVariantID):
            // Both handles. The variant id is what later batches are built
            // from, so failing to persist it would leave every refresh doing a
            // search it has already paid for once.
            identity.vendorCardID = vendorCardID
            identity.vendorVariantID = vendorVariantID
            identity.resolvedAt = date
            identity.unmatchedAt = vendorCardID == nil ? date : nil

        case let .noListingForVariant(vendorCardID):
            // The product exists. That it has no listing in this finish is a
            // fact about the listing, not about whether the card was found — so
            // the handle is kept and the search is not repeated.
            identity.vendorCardID = vendorCardID
            identity.resolvedAt = date
            identity.unmatchedAt = vendorCardID == nil ? date : nil

        case .noProductMatch:
            identity.vendorCardID = nil
            identity.vendorVariantID = nil
            identity.resolvedAt = nil
            identity.unmatchedAt = date

        case .requestFailed, .unsupportedFinish, .unsupportedTreatment, .budgetReached, .rateLimited:
            break
        }
        return true
    }

    @discardableResult
    func save(index: ProductIdentityIndex? = nil) -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            index?.reload()
            return false
        }
    }

}
