import Foundation
import SwiftData

/// Reads and writes `ProductIdentity` records.
///
/// Separate from `PriceStore` on purpose. A vendor handle and a price have
/// different lifetimes — the handle is resolved once and kept, the price is
/// replaced on every refresh — and keeping the writers apart is what stops one
/// subsystem's bookkeeping from becoming another's retry gate.
@MainActor
struct ProductIdentityStore {
    let context: ModelContext

    func identity(forKey key: String) -> ProductIdentity? {
        var descriptor = FetchDescriptor<ProductIdentity>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Whether the resolver should look this card up at all.
    ///
    /// A card with a current record — resolved *or* recently unmatched — is
    /// skipped, which is what keeps a collection full of vendor-less cards from
    /// re-running the same fruitless searches on every refresh.
    func needsResolution(forKey key: String) -> Bool {
        guard let identity = identity(forKey: key) else { return true }
        return !identity.isCurrent()
    }

    /// The vendor's variant handle, which is what a batch request is built
    /// from. Present means this card can be repriced twenty-to-a-request
    /// instead of one search at a time.
    func cachedVariantID(forKey key: String) -> String? {
        guard let identity = identity(forKey: key), identity.isCurrent() else { return nil }
        return identity.vendorVariantID
    }

    /// Remember what a batched response resolved, so the next refresh can go
    /// straight to the keyed lookup.
    func recordBatchResolution(
        forKey key: String,
        cardID: String?,
        variantID: String?,
        at date: Date = .now
    ) {
        guard cardID != nil || variantID != nil else { return }
        let identity = self.identity(forKey: key) ?? {
            let created = ProductIdentity(key: key, vendor: .justTCG)
            context.insert(created)
            return created
        }()
        identity.attemptVersion = ProductIdentity.currentAttemptVersion
        if let cardID { identity.vendorCardID = cardID }
        if let variantID { identity.vendorVariantID = variantID }
        identity.resolvedAt = date
        identity.unmatchedAt = nil
    }

    func cachedCardID(forKey key: String) -> String? {
        guard let identity = identity(forKey: key), identity.isCurrent() else { return nil }
        return identity.vendorCardID
    }

    /// Records the outcome of one resolution attempt.
    ///
    /// A miss is written as deliberately as a hit. Network, budget and rate-limit
    /// outcomes write nothing at all: scheduling or transport state is not
    /// evidence about whether the vendor carries the card.
    func record(
        _ outcome: ProductPriceOutcome,
        forKey key: String,
        at date: Date = .now
    ) {
        switch outcome {
        case .requestFailed, .budgetReached, .rateLimited:
            return
        case .price, .noListingForVariant, .noProductMatch:
            break
        }

        let identity = self.identity(forKey: key) ?? {
            let created = ProductIdentity(key: key, vendor: .justTCG)
            context.insert(created)
            return created
        }()

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
            identity.resolvedAt = nil
            identity.unmatchedAt = date

        case .requestFailed, .budgetReached, .rateLimited:
            break
        }
    }

    func save() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
