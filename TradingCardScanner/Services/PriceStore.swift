import Foundation
import OSLog
import SwiftData

/// Signposts for the measurements the remediation plan's slice 1 gates its
/// later slices on. `OSSignposter` costs a predicate check when no profiler is
/// attached, so these stay compiled in: the numbers that matter come from a
/// real device with a store that has aged, and an instrument you have to add
/// before you can measure is an instrument nobody adds.
enum PerformanceSignpost {
    static let signposter = OSSignposter(
        subsystem: "TradingCardScanner",
        category: "Performance"
    )

    static func makeID() -> OSSignpostID {
        signposter.makeSignpostID()
    }

    @discardableResult
    static func beginInterval(
        _ name: StaticString,
        id: OSSignpostID,
        _ metadata: String
    ) -> OSSignpostIntervalState {
        signposter.beginInterval(name, id: id, "\(metadata, privacy: .public)")
    }

    static func endInterval(
        _ name: StaticString,
        _ state: OSSignpostIntervalState,
        _ metadata: String
    ) {
        signposter.endInterval(name, state, "\(metadata, privacy: .public)")
    }

    static func emitEvent(_ name: StaticString, _ argument: String) {
        signposter.emitEvent(name, "\(argument, privacy: .public)")
    }
}

/// A stable diagnosis for an owned item that has no exact market price.
///
/// The raw value is intentionally support-friendly: it is written to diagnostic
/// CSVs and shown in the detail UI, so a screenshot and an export describe the
/// same state without someone having to infer it from a blank price.
enum PricingDiagnosticReason: String, Equatable, Sendable {
    case notChecked = "not_checked"
    case identityResolvedAfterFailedCheck = "identity_resolved_after_failed_check"
    case sealedProductPendingMatch = "sealed_product_match_pending"
    case sealedProductUnmatched = "sealed_product_unmatched"
    case noExactVariantPrice = "no_exact_variant_price"
    case gradedVariantUnavailable = "graded_variant_unavailable"
    case providerRequestFailed = "provider_request_failed"
    case gradedMarketPriceNull = "graded_market_price_null"
    case justTCGVariantUnresolved = "justtcg_variant_unresolved"
    case invalidProviderQuote = "invalid_provider_quote"
    case noSupportedProvider = "no_supported_provider"

    var title: String {
        switch self {
        case .notChecked: return "Price not checked"
        case .identityResolvedAfterFailedCheck: return "Ready to retry pricing"
        case .sealedProductPendingMatch: return "Product match pending"
        case .sealedProductUnmatched: return "Product not matched"
        case .noExactVariantPrice: return "Exact variant has no price"
        case .gradedVariantUnavailable: return "Graded variant not found"
        case .providerRequestFailed: return "Price provider request failed"
        case .gradedMarketPriceNull: return "Graded market price unavailable"
        case .justTCGVariantUnresolved: return "Market variant not resolved"
        case .invalidProviderQuote: return "Invalid provider quote rejected"
        case .noSupportedProvider: return "No supported price provider"
        }
    }

    var detail: String {
        switch self {
        case .notChecked:
            return "Refresh prices to check this item."
        case .identityResolvedAfterFailedCheck:
            return "The catalog identity was resolved after the last failed price check. Refresh prices to try again."
        case .sealedProductPendingMatch:
            return "The imported sealed product has not completed a marketplace match yet."
        case .sealedProductUnmatched:
            return "The sealed marketplace catalog was searched, but no unambiguous product matched this imported row. It will not retry automatically until matching rules improve."
        case .noExactVariantPrice:
            return "The provider does not publish a price for the exact variant you own."
        case .gradedVariantUnavailable:
            return "No exact marketplace variant matches this grader and grade."
        case .providerRequestFailed:
            return "The last provider request failed. A later refresh can try again."
        case .gradedMarketPriceNull:
            return "The exact graded listing exists, but the provider currently reports no market price."
        case .justTCGVariantUnresolved:
            return "The marketplace card was identified, but its exact physical variant was not."
        case .invalidProviderQuote:
            return "The provider returned a non-finite or unrepresentable amount. The quote was rejected and the prior value was kept."
        case .noSupportedProvider:
            return "This item has no provider that can answer its exact identity. It will be retried occasionally rather than on every refresh."
        }
    }
}

enum PricingDiagnostics {
    static func unpricedReason(
        for card: CollectedCard,
        record: PriceRecord?
    ) -> PricingDiagnosticReason {
        if record?.lastFailureReasonRaw == PricingDiagnosticReason.noSupportedProvider.rawValue {
            return .noSupportedProvider
        }
        if record?.lastFailureReasonRaw == PricingDiagnosticReason.invalidProviderQuote.rawValue {
            return .invalidProviderQuote
        }
        if card.itemKind == .sealedProduct, card.justTCGVariantID == nil {
            if card.justTCGCardID != nil { return .noExactVariantPrice }
            return CollectionCatalogNormalizer.isDefinitiveSealedMiss(card)
                ? .sealedProductUnmatched
                : .sealedProductPendingMatch
        }

        if card.itemKind == .gradedCard, card.justTCGVariantID == nil {
            return .gradedVariantUnavailable
        }

        guard let record, record.lastCheckedAt != nil else { return .notChecked }

        if card.catalogProviderID != nil,
           record.lastFailureAt != nil,
           let metadataCheckedAt = card.catalogMetadataCheckedAt,
           metadataCheckedAt > (record.lastCheckedAt ?? .distantPast) {
            return .identityResolvedAfterFailedCheck
        }

        switch card.itemKind {
        case .sealedProduct:
            return .noExactVariantPrice
        case .gradedCard:
            return record.lastFailureAt != nil
                ? .providerRequestFailed
                : .gradedMarketPriceNull
        case .rawCard:
            if record.lastFailureAt != nil { return .providerRequestFailed }
            if card.justTCGVariantID == nil, card.justTCGCardID != nil {
                return .justTCGVariantUnresolved
            }
            return .noExactVariantPrice
        }
    }
}

/// Why an owned item still has no artwork. Kept separate from price diagnostics
/// because a provider can publish either fact without publishing the other.
enum ArtworkDiagnosticReason: String, Equatable, Sendable {
    case lookupPending = "artwork_lookup_pending"
    case productNotMatched = "catalog_identity_not_resolved"
    case providerHasNoArtwork = "provider_has_no_artwork"

    var title: String {
        switch self {
        case .lookupPending: return "Artwork lookup pending"
        case .productNotMatched: return "Product artwork not matched"
        case .providerHasNoArtwork: return "Provider has no artwork"
        }
    }

    var detail: String {
        switch self {
        case .lookupPending:
            return "The next eligible refresh will ask the marketplace for this product image."
        case .productNotMatched:
            return "This imported product has not been matched unambiguously to a marketplace listing."
        case .providerHasNoArtwork:
            return "The marketplace listing was checked but does not publish a usable product image. You can add your own photo."
        }
    }
}

enum ArtworkDiagnostics {
    static func reason(
        for card: CollectedCard,
        hasLocalOverride: Bool = false
    ) -> ArtworkDiagnosticReason? {
        guard !hasLocalOverride, card.userArtworkFilename == nil, card.imageURL == nil else {
            return nil
        }

        if card.itemKind == .sealedProduct {
            if CollectionCatalogNormalizer.isDefinitiveSealedMiss(card) {
                return .productNotMatched
            }
            if card.justTCGVariantID == nil { return .productNotMatched }
            return shouldRetrySealedArtwork(for: card)
                ? .lookupPending
                : .providerHasNoArtwork
        }

        if card.catalogMetadataCheckedAt == nil { return .lookupPending }
        return card.catalogProviderID == nil ? .productNotMatched : .providerHasNoArtwork
    }

    /// Existing rows and rows last checked by older matching rules receive one
    /// marketplace backfill. A current-version response with no image is a
    /// terminal provider fact and must not consume quota forever.
    static func shouldRetrySealedArtwork(for card: CollectedCard) -> Bool {
        guard card.itemKind == .sealedProduct,
              card.imageURL == nil,
              card.justTCGVariantID != nil else {
            return false
        }
        return card.catalogMetadataCheckedAt == nil
            || card.catalogMetadataVersion != CollectionCatalogNormalizer.metadataVersion
    }
}

/// The record-backed instrument-selection rule shared by the collection
/// projection and portfolio replay. The observation log still supplies the
/// valuation for whichever instrument is selected; it does not change which
/// legacy or canonical record-backed instrument the UI attributes the position
/// to.
struct PriceRecordKeySelection: Sendable {
    private let existingKeys: Set<String>
    private let valuedKeys: Set<String>
    private let invalidatedKeys: Set<String>

    static let empty = PriceRecordKeySelection(
        existingKeys: [],
        valuedKeys: [],
        invalidatedKeys: []
    )

    init(records: [PriceRecord]) {
        self.init(
            existingKeys: Set(records.map(\.key)),
            valuedKeys: Set(
                records
                    .filter { $0.effectiveUnitMarketPriceUSD != nil }
                    .map(\.key)
            ),
            invalidatedKeys: Set(records.filter(\.isInvalidated).map(\.key))
        )
    }

    private init(
        existingKeys: Set<String>,
        valuedKeys: Set<String>,
        invalidatedKeys: Set<String>
    ) {
        self.existingKeys = existingKeys
        self.valuedKeys = valuedKeys
        self.invalidatedKeys = invalidatedKeys
    }

    func priceStorageKey(for card: CollectedCard) -> String {
        let keys = card.priceLookupKeys
        guard let primaryKey = keys.first(where: existingKeys.contains) else {
            return keys.first ?? card.priceKey
        }
        if invalidatedKeys.contains(primaryKey) { return primaryKey }
        return keys.first(where: valuedKeys.contains) ?? primaryKey
    }
}

/// The refresh pipeline owns one of these for its isolated context. It replaces
/// the three per-instrument predicate scans with one materialization per pass,
/// while keeping the scalar store APIs best-effort when no pass index is used.
/// This type is context-owned rather than `@MainActor`: callers must create and
/// use it on the executor that owns its `ModelContext`, just like `PriceStore`
/// and `CollectionStore`. The foreground refresh currently owns both on the
/// main actor, but the type does not impose that policy on other context owners.
final class PriceRefreshDataIndex {
    struct CheckDayKey: Hashable {
        let instrumentKey: String
        let portfolioDay: Date
    }

    private let context: ModelContext
    private(set) var recordsByKey: [String: [PriceRecord]]
    /// Refresh decisions only need the newest observation for each instrument.
    /// Keeping the full append-only history here made a multi-minute refresh
    /// retain every observation ever recorded on the device.
    private(set) var newestObservationsByInstrumentKey: [String: PriceObservation]
    private(set) var checkDaysByKey: [CheckDayKey: PriceCheckDay]
    private(set) var indexedPortfolioDays: Set<Date>
    private(set) var loadedSuccessfully: Bool

    init(context: ModelContext) {
        self.context = context
        let signpostState = PerformanceSignpost.signposter.beginInterval("PriceRefreshDataIndex.init")
        defer { PerformanceSignpost.signposter.endInterval("PriceRefreshDataIndex.init", signpostState) }
        self.recordsByKey = [:]
        self.newestObservationsByInstrumentKey = [:]
        self.checkDaysByKey = [:]
        self.indexedPortfolioDays = []
        self.loadedSuccessfully = false
        reload()
    }

    /// Rebuilds all materialized reads after a context rollback. Model objects
    /// inserted or deleted before a failed save are not safe cache entries for
    /// the next provider response.
    func reload() {
        do {
            let records = try context.fetch(FetchDescriptor<PriceRecord>())
            let observations = try context.fetch(FetchDescriptor<PriceObservation>())
            let indexedDay = PortfolioCalendar.day(
                containing: .now,
                in: PortfolioCalendar.pinnedTimeZone() ?? .current
            )
            let checkDays = try context.fetch(
                FetchDescriptor<PriceCheckDay>(
                    predicate: #Predicate { $0.portfolioDay == indexedDay }
                )
            )
            self.recordsByKey = Dictionary(grouping: records, by: \.key)
            var newestByInstrumentKey: [String: PriceObservation] = [:]
            for observation in observations {
                guard let incumbent = newestByInstrumentKey[observation.instrumentKey] else {
                    newestByInstrumentKey[observation.instrumentKey] = observation
                    continue
                }
                if Self.isNewer(observation, than: incumbent) {
                    newestByInstrumentKey[observation.instrumentKey] = observation
                }
            }
            self.newestObservationsByInstrumentKey = newestByInstrumentKey
            self.checkDaysByKey = Dictionary(
                grouping: checkDays,
                by: { CheckDayKey(instrumentKey: $0.instrumentKey, portfolioDay: $0.portfolioDay) }
            ).compactMapValues { PriceCheckDay.preferred(from: $0) }
            self.indexedPortfolioDays = [indexedDay]
            self.loadedSuccessfully = true
        } catch {
            self.recordsByKey = [:]
            self.newestObservationsByInstrumentKey = [:]
            self.checkDaysByKey = [:]
            self.indexedPortfolioDays = []
            self.loadedSuccessfully = false
        }
    }

    var isUsable: Bool { loadedSuccessfully }

    func records(forKey key: String) -> [PriceRecord] {
        recordsByKey[key] ?? []
    }

    func allRecords() -> [PriceRecord] {
        recordsByKey.values.flatMap { $0 }
    }

    func setRecords(_ records: [PriceRecord], forKey key: String) {
        if records.isEmpty { recordsByKey.removeValue(forKey: key) }
        else { recordsByKey[key] = records }
    }

    func insert(_ record: PriceRecord) {
        recordsByKey[record.key, default: []].append(record)
    }

    func newestObservation(forInstrumentKey key: String) -> PriceObservation? {
        newestObservationsByInstrumentKey[key]
    }

    func insert(_ observation: PriceObservation) {
        guard let incumbent = newestObservationsByInstrumentKey[observation.instrumentKey] else {
            newestObservationsByInstrumentKey[observation.instrumentKey] = observation
            return
        }
        if Self.isNewer(observation, than: incumbent) {
            newestObservationsByInstrumentKey[observation.instrumentKey] = observation
        }
    }

    func checkDay(instrumentKey: String, day: Date) -> PriceCheckDay? {
        checkDaysByKey[CheckDayKey(instrumentKey: instrumentKey, portfolioDay: day)]
    }

    func canReadCheckDay(_ day: Date) -> Bool {
        indexedPortfolioDays.contains(day)
    }

    func insert(_ checkDay: PriceCheckDay) {
        let key = CheckDayKey(instrumentKey: checkDay.instrumentKey, portfolioDay: checkDay.portfolioDay)
        if let existing = checkDaysByKey[key],
           let preferred = PriceCheckDay.preferred(from: [existing, checkDay]) {
            checkDaysByKey[key] = preferred
        } else {
            checkDaysByKey[key] = checkDay
        }
        indexedPortfolioDays.insert(checkDay.portfolioDay)
    }

    private static func isNewer(
        _ candidate: PriceObservation,
        than incumbent: PriceObservation
    ) -> Bool {
        if candidate.receivedAt != incumbent.receivedAt {
            return candidate.receivedAt > incumbent.receivedAt
        }
        return candidate.id.uuidString > incumbent.id.uuidString
    }
}

/// Moves one local price identity to its canonical vendor identity while the
/// owning collection mutation is still in the same SwiftData transaction.
///
/// A vendor bind changes more than the mutable `PriceRecord` key: local price
/// observations, coverage rows, and synced ledger events all name the old
/// instrument explicitly. Moving only the current record leaves replay and
/// historical attribution split across two instruments. This helper keeps the
/// four stores together and fails closed when any source table is unreadable.
enum PriceIdentityLineageMigration {
    /// Promotes an unbound non-raw row to a vendor variant identity.
    /// Callers must invoke this before assigning the vendor id to the row so
    /// `card.priceKey` still names the complete source identity.
    static func promoteUnboundPriceIdentity(
        for card: CollectedCard,
        toMarketVariantID marketVariantID: String,
        apiVersion: String,
        in context: ModelContext,
        index: PriceRefreshDataIndex? = nil
    ) throws {
        guard card.itemKind != .rawCard,
              card.justTCGVariantID == nil,
              !marketVariantID.isEmpty else { return }

        let oldKey = card.priceKey
        let printingID = "justtcg:\(apiVersion):\(marketVariantID)"
        let newKey = PriceRecord.key(
            game: card.cardGame,
            printingID: printingID,
            variantID: card.variantID,
            treatmentIDs: card.priceTreatmentIDs
        )
        try migrate(
            from: oldKey,
            to: newKey,
            game: card.cardGame,
            printingID: printingID,
            variantID: card.variantID,
            treatmentIDs: card.priceTreatmentIDs,
            in: context,
            index: index
        )
    }

    /// Retargets every persisted reference to one price instrument. The
    /// canonical record wins by the same authority rule used by refresh and
    /// display; duplicate coverage rows are reduced to their monotonic
    /// preferred row after retargeting.
    @discardableResult
    static func migrate(
        from oldKey: String,
        to newKey: String,
        game: CardGame,
        printingID: String,
        variantID: String?,
        treatmentIDs: [String],
        in context: ModelContext,
        index: PriceRefreshDataIndex? = nil
    ) throws -> Bool {
        guard oldKey != newKey else { return false }

        let oldRecords = try context.fetch(
            FetchDescriptor<PriceRecord>(predicate: #Predicate { $0.key == oldKey })
        )
        let newRecords = try context.fetch(
            FetchDescriptor<PriceRecord>(predicate: #Predicate { $0.key == newKey })
        )
        let records = oldRecords + newRecords
        if let authoritative = PriceStore.authoritativeRecord(in: records) {
            let marketVariantID = records.compactMap(\.marketVariantID).first
            let canonicalMarketID = records.compactMap(\.canonicalMarketID).first
            let itemKindRaw = records.compactMap(\.itemKindRaw).first

            for record in records where record !== authoritative {
                context.delete(record)
            }
            authoritative.key = newKey
            authoritative.game = game.rawValue
            authoritative.printingID = printingID
            authoritative.variantID = variantID
            authoritative.magicTreatmentIDsRaw = MagicTreatmentKeyCodec.storedIDs(
                from: treatmentIDs
            )
            if authoritative.marketVariantID == nil {
                authoritative.marketVariantID = marketVariantID
            }
            if authoritative.canonicalMarketID == nil {
                authoritative.canonicalMarketID = canonicalMarketID
            }
            if authoritative.itemKindRaw == nil {
                authoritative.itemKindRaw = itemKindRaw
            }
        }

        let observations = try context.fetch(
            FetchDescriptor<PriceObservation>(
                predicate: #Predicate { $0.instrumentKey == oldKey }
            )
        )
        for observation in observations {
            observation.instrumentKey = newKey
        }

        let oldCheckDays = try context.fetch(
            FetchDescriptor<PriceCheckDay>(
                predicate: #Predicate { $0.instrumentKey == oldKey }
            )
        )
        let newCheckDays = try context.fetch(
            FetchDescriptor<PriceCheckDay>(
                predicate: #Predicate { $0.instrumentKey == newKey }
            )
        )
        for checkDay in oldCheckDays {
            checkDay.instrumentKey = newKey
        }
        for rows in Dictionary(grouping: oldCheckDays + newCheckDays, by: \.portfolioDay).values
            where rows.count > 1 {
            guard let preferred = PriceCheckDay.preferred(from: rows) else { continue }
            for duplicate in rows where duplicate !== preferred {
                context.delete(duplicate)
            }
        }

        let events = try context.fetch(
            FetchDescriptor<InventoryEvent>(
                predicate: #Predicate { $0.priceStorageKey == oldKey }
            )
        )
        for event in events {
            event.priceStorageKey = newKey
        }

        // A refresh index may have been materialised before the binding
        // response arrived. Do not let it resurrect the old record or miss the
        // observations just moved into the canonical key.
        index?.reload()
        return true
    }
}

/// Reads and writes `PriceRecord`s.
///
/// Prices are keyed by printing plus variant, never by collection row, so eight
/// owned copies of one printing are one record to fetch, one to refresh and one
/// to keep fresh.
struct PriceStore {
    let context: ModelContext
    let index: PriceRefreshDataIndex?

    init(context: ModelContext, index: PriceRefreshDataIndex? = nil) {
        self.context = context
        self.index = index
    }

    func record(forKey key: String) -> PriceRecord? {
        if let index, index.isUsable {
            let indexedMatches = index.records(forKey: key)
            if !indexedMatches.isEmpty {
                return Self.authoritativeRecord(in: indexedMatches)
            }

            // The refresh index predates writes made through a sibling
            // context. Recheck an indexed miss before treating the instrument
            // as unknown; the same stale window that can duplicate a write can
            // otherwise make an unchanged price look like a new one.
            let fetchedMatches = (try? context.fetch(
                FetchDescriptor<PriceRecord>(predicate: #Predicate { $0.key == key })
            )) ?? []
            if !fetchedMatches.isEmpty {
                index.setRecords(fetchedMatches, forKey: key)
            }
            return Self.authoritativeRecord(in: fetchedMatches)
        }

        let matches = (try? context.fetch(
            FetchDescriptor<PriceRecord>(predicate: #Predicate { $0.key == key })
        )) ?? []
        return Self.authoritativeRecord(in: matches)
    }

    /// The CloudKit schema has no unique constraint, so a concurrent first
    /// write can deliver more than one row for one instrument. Reads must not
    /// depend on SwiftData's fetch order while a repair is pending.
    static func authoritativeRecord(in records: [PriceRecord]) -> PriceRecord? {
        records.reduce(nil) { current, candidate in
            guard let current else { return candidate }
            return isPreferred(candidate, over: current) ? candidate : current
        }
    }

    /// Selects the row with the newest knowledge/invalidation watermark. An
    /// invalidation wins ties so a duplicate cannot resurrect a withdrawn
    /// value. The remaining fingerprint is only a deterministic tie-breaker;
    /// price magnitude is deliberately not part of the preference rule.
    static func isPreferred(_ candidate: PriceRecord, over incumbent: PriceRecord) -> Bool {
        let candidateDate = knowledgeDate(for: candidate)
        let incumbentDate = knowledgeDate(for: incumbent)
        if candidateDate != incumbentDate { return candidateDate > incumbentDate }
        if candidate.isInvalidated != incumbent.isInvalidated {
            return candidate.isInvalidated
        }
        return fingerprint(for: candidate) > fingerprint(for: incumbent)
    }

    /// Repairs all duplicate keys visible in this context before a refresh.
    /// The returned count is the number of redundant rows removed, so callers
    /// can report a repair only after the surrounding save succeeds.
    @discardableResult
    func reconcileDuplicateRecords() -> Int {
        let recordsByKey = Dictionary(grouping: allRecords(), by: \.key)
        var removed = 0
        for records in recordsByKey.values where records.count > 1 {
            guard let authoritative = Self.authoritativeRecord(in: records) else { continue }
            for duplicate in records where duplicate !== authoritative {
                context.delete(duplicate)
                removed += 1
            }
            index?.setRecords([authoritative], forKey: authoritative.key)
        }
        return removed
    }

    private static func knowledgeDate(for record: PriceRecord) -> Date {
        [
            record.invalidatedAt,
            record.lastSuccessfulCheckAt,
            record.fetchedAt
        ]
        .compactMap { $0 }
        .max() ?? .distantPast
    }

    private static func fingerprint(for record: PriceRecord) -> String {
        [
            record.isInvalidated ? "1" : "0",
            record.sourceRaw ?? "",
            record.sourceVariantID ?? "",
            record.marketVariantID ?? "",
            record.currencyCode,
            record.unitMarketPriceUSD.map { String($0) } ?? "",
            record.sourceUpdatedAt?.timeIntervalSince1970.description ?? "",
            record.fetchedAt?.timeIntervalSince1970.description ?? ""
        ].joined(separator: "\u{1F}  ")
    }

    /// Resolves the record for a write without treating an unreadable store as
    /// an absent record. A failed lookup must not create a second price row, and
    /// duplicate rows must not be silently updated through an arbitrary first
    /// match. The public read helper remains best-effort because UI callers use
    /// `nil` to mean that no display value is available.
    private func recordForWrite(
        key: String,
        game: CardGame,
        printingID: String,
        variantID: String?,
        treatmentIDs: [String] = []
    ) -> PriceRecord? {
        do {
            let matches: [PriceRecord]
            if let index, index.isUsable {
                let indexedMatches = index.records(forKey: key)
                // The refresh index predates writes made through a sibling
                // context. Recheck the store before creating a row so a scan
                // that saved this instrument after the index was built cannot
                // cause a duplicate PriceRecord.
                matches = indexedMatches.isEmpty
                    ? try context.fetch(
                        FetchDescriptor<PriceRecord>(predicate: #Predicate { $0.key == key })
                    )
                    : indexedMatches
            } else {
                matches = try context.fetch(
                    FetchDescriptor<PriceRecord>(predicate: #Predicate { $0.key == key })
                )
            }
            if matches.count > 1,
               let authoritative = Self.authoritativeRecord(in: matches) {
                for duplicate in matches where duplicate !== authoritative {
                    context.delete(duplicate)
                }
                index?.setRecords([authoritative], forKey: key)
                return authoritative
            }
            if let existing = matches.first {
                if existing.magicTreatmentIDsRaw.isEmpty, !treatmentIDs.isEmpty {
                    existing.magicTreatmentIDsRaw = MagicTreatmentKeyCodec.storedIDs(
                        from: treatmentIDs
                    )
                }
                return existing
            }

            let created = PriceRecord(
                key: key,
                game: game,
                printingID: printingID,
                variantID: variantID,
                magicTreatmentIDs: treatmentIDs
            )
            context.insert(created)
            index?.insert(created)
            return created
        } catch {
            return nil
        }
    }

    func allRecords() -> [PriceRecord] {
        if let index, index.isUsable { return index.allRecords() }
        return (try? context.fetch(FetchDescriptor<PriceRecord>())) ?? []
    }

    nonisolated static func record(
        for card: CollectedCard,
        in recordsByKey: [String: PriceRecord]
    ) -> PriceRecord? {
        let candidates = card.priceLookupKeys.compactMap { recordsByKey[$0] }
        guard let primary = candidates.first else { return nil }

        // The canonical record is authoritative once it has explicitly been
        // invalidated. Falling through to a legacy key in that state would
        // resurrect the very value the invalidation withdrew.
        if primary.isInvalidated { return primary }

        // Prefer a real record value over an empty canonical placeholder. The
        // legacy value is for the same exact object and remains better evidence
        // until the new key receives its own price.
        return candidates.first(where: { $0.effectiveUnitMarketPriceUSD != nil }) ?? primary
    }

    /// The key of the record `record(for:in:)` would choose.
    ///
    /// A position's instrument and the price shown for that position must be one
    /// decision, not two rules that drift. The bulk form is record-backed so it
    /// can be shared by the portfolio without observation-log fetches from a
    /// view's `body`.
    nonisolated static func priceStorageKey(
        for card: CollectedCard,
        in recordsByKey: [String: PriceRecord]
    ) -> String {
        PriceRecordKeySelection(records: Array(recordsByKey.values))
            .priceStorageKey(for: card)
    }

    func importedCardsByProviderID() -> [String: [CollectedCard]] {
        let cards = (try? context.fetch(FetchDescriptor<CollectedCard>())) ?? []
        return Dictionary(
            grouping: cards.filter { $0.providerID.hasPrefix("csv:") },
            by: \.providerID
        )
    }

    /// Persistent identifiers are safe to retain while a paced provider request
    /// is suspended. Model objects are not: another context operation can delete
    /// or invalidate them before the response returns.
    func importedCardIDsByProviderID() -> [String: [PersistentIdentifier]] {
        let cards = (try? context.fetch(FetchDescriptor<CollectedCard>())) ?? []
        return cards.filter { $0.providerID.hasPrefix("csv:") }
            .reduce(into: [String: [PersistentIdentifier]]()) { result, card in
                result[card.providerID, default: []].append(card.persistentModelID)
            }
    }

    /// Records what a provider said about one variant, creating the record if
    /// this is the first time the app has asked.
    ///
    /// This is also where the append-only observation log is written. Both
    /// successful outcomes — a price, and an explicit "nothing for this
    /// variant" — funnel through here, while failures go through
    /// `recordFailure`, so the three outcomes stay cleanly separable without
    /// any caller having to know the log exists.
    ///
    /// `marketVariantID` is passed in rather than read back off the record
    /// because provenance is part of what is being observed: a vendor remapping
    /// a card from one variant object to another worth the same $42 has changed
    /// what is priced, and the record still holds the *old* id at this point.
    @discardableResult
    func store(
        _ lookup: PriceLookup,
        game: CardGame,
        printingID: String,
        variantID: String?,
        marketVariantID: String? = nil,
        at date: Date = .now,
        treatmentIDs: [String] = []
    ) -> Bool {
        let key = PriceRecord.key(
            game: game,
            printingID: printingID,
            variantID: variantID,
            treatmentIDs: treatmentIDs
        )
        guard let record = recordForWrite(
            key: key,
            game: game,
            printingID: printingID,
            variantID: variantID,
            treatmentIDs: treatmentIDs
        ) else { return false }

        let observationDecision = PriceObservationLog(context: context, index: index).ingest(
            lookup,
            instrumentKey: key,
            marketVariantID: marketVariantID ?? record.marketVariantID,
            at: date
        )

        if observationDecision == .rejectedInvalidQuote {
            record.recordFailure(at: date)
            record.lastFailureReasonRaw = PricingDiagnosticReason.invalidProviderQuote.rawValue
            return false
        }
        if observationDecision == .ignoredAfterInvalidation {
            return false
        }

        switch lookup {
        case let .price(price):
            guard record.apply(price) else { return false }
            record.lastFailureReasonRaw = nil
        case let .unavailable(source):
            record.applyUnavailable(source: source, at: date)
            // A real amount clears every prior diagnosis. "The provider had
            // nothing for this variant" does not: it is the same answer the
            // capability stamp already records, and the scanner writes it on
            // every commit of a treatment-qualified Magic card. Clearing here
            // let one scan withdraw the 30-day terminal state and put the card
            // back into the refresh queue it was just taken out of.
            if record.lastFailureReasonRaw != PricingDiagnosticReason.noSupportedProvider.rawValue {
                record.lastFailureReasonRaw = nil
            }
        }

        if let marketVariantID {
            record.marketVariantID = marketVariantID
        }
        return true
    }

    func storeImported(
        amount: Double,
        sourceUpdatedAt: Date?,
        game: CardGame,
        printingID: String,
        variantID: String?,
        at importedAt: Date = .now,
        treatmentIDs: [String] = []
    ) {
        guard Money(rounding: amount) != nil else { return }
        let key = PriceRecord.key(
            game: game,
            printingID: printingID,
            variantID: variantID,
            treatmentIDs: treatmentIDs
        )
        guard let record = recordForWrite(
            key: key,
            game: game,
            printingID: printingID,
            variantID: variantID,
            treatmentIDs: treatmentIDs
        ) else { return }
        guard record.effectiveUnitMarketPriceUSD == nil else { return }

        // Value-setting, so it belongs in the observation log — without a row
        // here an entire imported collection would be invisible to the close
        // engine and its whole value would surface as unexplained. But an
        // import is not a provider check, so it writes no `PriceCheckDay`:
        // coverage means "a provider answered today", and a CSV did not.
        PriceObservationLog(context: context, index: index).ingest(
            .price(
                NormalizedPrice(
                    unitMarketPriceUSD: amount,
                    currencyCode: "USD",
                    source: .importedCSV,
                    sourceVariantID: variantID ?? key,
                    sourceUpdatedAt: sourceUpdatedAt,
                    fetchedAt: importedAt
                )
            ),
            instrumentKey: key,
            marketVariantID: record.marketVariantID,
            recordsCoverage: false,
            at: importedAt
        )

        _ = record.applyImported(amount: amount, sourceUpdatedAt: sourceUpdatedAt, importedAt: importedAt)
    }

    /// A refresh attempt that never reached an answer. The previous price stays
    /// exactly where it was — an offline phone should show yesterday's price
    /// labelled as yesterday's, not nothing at all.
    @discardableResult
    func recordFailure(
        game: CardGame,
        printingID: String,
        variantID: String?,
        at date: Date = .now,
        treatmentIDs: [String] = []
    ) -> Bool {
        let key = PriceRecord.key(
            game: game,
            printingID: printingID,
            variantID: variantID,
            treatmentIDs: treatmentIDs
        )
        guard let record = recordForWrite(
            key: key,
            game: game,
            printingID: printingID,
            variantID: variantID,
            treatmentIDs: treatmentIDs
        ) else { return false }
        record.recordFailure(at: date)
        // A target can become supported after a catalog/schema/provider update.
        // Once that target is actually attempted, the old capability stamp must
        // not continue to suppress it for the long terminal retry interval.
        if record.lastFailureReasonRaw == PricingDiagnosticReason.noSupportedProvider.rawValue
            || record.lastFailureReasonRaw == PricingDiagnosticReason.invalidProviderQuote.rawValue {
            record.lastFailureReasonRaw = nil
        }
        return true
    }

    /// Stamps a capability gap rather than a provider failure. This is used for
    /// identities the live catalog cannot represent at all (for example a
    /// treatment-qualified Magic card or a graded row without a vendor handle).
    /// It intentionally writes no observation and no coverage row: no provider
    /// answered the question.
    @discardableResult
    func recordUnsupportedProvider(
        game: CardGame,
        printingID: String,
        variantID: String?,
        at date: Date = .now,
        treatmentIDs: [String] = []
    ) -> Bool {
        let key = PriceRecord.key(
            game: game,
            printingID: printingID,
            variantID: variantID,
            treatmentIDs: treatmentIDs
        )
        guard let record = recordForWrite(
            key: key,
            game: game,
            printingID: printingID,
            variantID: variantID,
            treatmentIDs: treatmentIDs
        ) else { return false }
        record.lastCheckedAt = date
        record.lastFailureReasonRaw = PricingDiagnosticReason.noSupportedProvider.rawValue
        record.lastFailureAt = nil
        return true
    }

    /// Saves only this store's context. A failed save is rolled back immediately
    /// so a later caller cannot inherit a half-staged price write and commit it
    /// together with unrelated work. Production refreshes use a dedicated
    /// context as an additional isolation boundary.
    @discardableResult
    func save() -> Bool {
        guard context.hasChanges else { return true }
        let saveState = PerformanceSignpost.beginInterval(
            "PriceStore.save",
            id: PerformanceSignpost.makeID(),
            "changed=true"
        )
        var outcome = "failed"
        defer {
            PerformanceSignpost.endInterval(
                "PriceStore.save",
                saveState,
                "outcome=\(outcome)"
            )
        }
        do {
            try context.save()
            outcome = "saved"
            return true
        } catch {
            context.rollback()
            index?.reload()
            return false
        }
    }
}
