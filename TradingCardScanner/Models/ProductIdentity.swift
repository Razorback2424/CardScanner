import Foundation
import SwiftData

/// The cached link between one physical variant this app owns and the price
/// vendor's handle for that same object.
///
/// Resolving a vendor handle is the expensive, non-deterministic half of the
/// fallback: for the cards that need it there is no shared product id, so the
/// match comes from a scoped text search. That search must happen once per
/// variant, ever — after which every refresh is a cheap keyed lookup.
///
/// A miss is cached too. A card the vendor has genuinely never heard of must not
/// re-run a search on every refresh forever.
@Model
final class ProductIdentity {
    /// `game:printingID:variantID[:treatment=...]` — the same shape as
    /// `PriceRecord.key`, because
    /// a vendor handle belongs to a printing *and* a finish, exactly as a price
    /// does. One handle per card would reintroduce the finish-collapsing bug the
    /// pricing layer exists to prevent.
    // CloudKit does not support unique constraints, so uniqueness for this key
    // is enforced in code (ProductIdentityStore fetches by `key` before every
    // insert) rather than by the store.
    @Attribute var key: String = ""

    /// Which vendor this handle belongs to. Stored so a second vendor can be
    /// added later without the two silently sharing a row.
    var vendorRaw: String = ""

    var vendorCardID: String?
    /// The finish-specific handle, when the vendor exposes one. This is what a
    /// keyed refresh actually sends.
    var vendorVariantID: String?
    var resolvedAt: Date?
    /// Mirrors the treatment-qualified price identity. A vendor handle belongs
    /// to a treatment-bearing object only when its cache key says so; it must
    /// not fall through to the generic foil handle.
    var magicTreatmentIDsRaw: [String] = []

    /// Set when the vendor was searched and had nothing. Distinct from "never
    /// asked", which is this whole record being absent.
    var unmatchedAt: Date?

    /// Bumped in code when the matching rules improve, so previously unmatched
    /// cards are retried on the next pass instead of waiting out a retry
    /// interval on a verdict the current build would reach differently.
    var attemptVersion: Int = ProductIdentity.currentAttemptVersion

    /// # Ownership
    ///
    /// `unmatchedAt` and `attemptVersion` are written by the product-identity
    /// resolver and by nothing else.
    ///
    /// This is not a style preference. The price refresher used to stamp
    /// `catalogMetadataCheckedAt`, which was the catalog normalizer's retry gate:
    /// a card with no identity failed its price check, the failure refreshed the
    /// gate, the normalizer then skipped the card as recently-checked, and 248
    /// cards were locked out of identity resolution permanently. Two subsystems
    /// sharing one timestamp is that bug. A field has exactly one writer.
    init(
        key: String,
        vendor: PriceSource,
        vendorCardID: String? = nil,
        vendorVariantID: String? = nil,
        resolvedAt: Date? = nil,
        unmatchedAt: Date? = nil,
        attemptVersion: Int = ProductIdentity.currentAttemptVersion,
        magicTreatmentIDs: [String] = []
    ) {
        self.key = key
        self.vendorRaw = vendor.rawValue
        self.vendorCardID = vendorCardID
        self.vendorVariantID = vendorVariantID
        self.resolvedAt = resolvedAt
        self.unmatchedAt = unmatchedAt
        self.attemptVersion = attemptVersion
        self.magicTreatmentIDsRaw = MagicTreatmentKeyCodec.storedIDs(from: magicTreatmentIDs)
    }

    /// Raise this when the matcher learns to resolve something it previously
    /// could not.
    ///
    /// 1: initial text-search matching.
    /// 2: retry prior matcher misses while retaining resolved vendor handles.
    static let currentAttemptVersion = 2

    var vendor: PriceSource? {
        PriceSource(rawValue: vendorRaw)
    }

    /// Whether this record still answers the question, or whether the resolver
    /// should look again.
    func isCurrent(now: Date = .now, retryUnmatchedAfter: TimeInterval = 30 * 24 * 60 * 60) -> Bool {
        // A resolved handle remains valid across matcher revisions. Only a
        // negative match needs reopening; invalidating handles would degrade
        // batch refreshes into one paid search per card.
        if vendorCardID != nil { return true }
        guard attemptVersion >= Self.currentAttemptVersion else { return false }
        guard let unmatchedAt else { return false }
        // A miss is not necessarily permanent — vendors add products. Re-ask
        // rarely rather than never, and far less often than a price refresh.
        return now.timeIntervalSince(unmatchedAt) < retryUnmatchedAfter
    }

    static func key(
        game: CardGame,
        printingID: String,
        variantID: String?,
        treatmentIDs: [String] = []
    ) -> String {
        PriceRecord.key(
            game: game,
            printingID: printingID,
            variantID: variantID,
            treatmentIDs: treatmentIDs
        )
    }
}
