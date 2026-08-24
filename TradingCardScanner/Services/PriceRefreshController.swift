import Foundation
import SwiftData

/// The result of one catalog fetch during a refresh.
///
/// The outcome distinguishes an ordinary provider failure from cancellation so
/// leaving the collection cannot turn an abandoned request into a recorded check.
/// File scope rather than nested, so it cannot inherit the controller's
/// main-actor isolation.
private struct PriceFetchOutcome: Sendable {
    let printing: PriceTarget.Printing
    let result: Result

    enum Result: Sendable {
        case card(IdentifiedCard)
        case failed
        case cancelled
    }
}

/// One priced thing: a printing plus the physical variant the user owns.
struct PriceTarget: Hashable, Identifiable, Sendable {
    let game: CardGame
    let printingID: String
    let catalogPrintingID: String?
    let setCode: String
    let variantID: String?
    let importedIdentity: ImportedPriceIdentity?
    let catalogMetadataCheckedAt: Date?
    let lastFailureAt: Date?
    let hasPrice: Bool
    /// When this app last asked about it, successfully or not.
    let lastCheckedAt: Date?

    var id: String { PriceRecord.key(game: game, printingID: printingID, variantID: variantID) }

    /// One catalog response answers every variant of the same printing, so a
    /// collection holding a normal and a reverse copy costs one request.
    var printing: Printing {
        Printing(
            game: game,
            printingID: catalogPrintingID ?? printingID,
            setCode: setCode,
            importedIdentity: importedIdentity
        )
    }

    struct Printing: Hashable, Sendable {
        let game: CardGame
        let printingID: String
        let setCode: String
        let importedIdentity: ImportedPriceIdentity?
    }
}

struct ImportedPriceIdentity: Hashable, Sendable {
    let name: String
    let setName: String
    let cardNumber: String
}

/// Keeps prices current without ever claiming more than it knows.
///
/// Three separate promises, all of which the UI depends on:
///
/// - a refresh that fails leaves the previous price in place, labelled with its
///   real age, because yesterday's price beats no price;
/// - "checked" and "current as of" are different facts and are reported
///   separately, so a check that found no newer market data says exactly that;
/// - refreshing is per unique printing-and-variant, not per owned copy.
@MainActor
final class PriceRefreshController: ObservableObject {
    struct Summary: Equatable {
        let checkedAt: Date
        let priced: Int
        let failed: Int
        /// The newest "market data current through" any provider reported.
        let latestSourceUpdate: Date?
        /// At least one successful provider response had no provider-side market
        /// timestamp. Such a response can be described as checked, but never as
        /// having no newer timestamp.
        let checkedUnstampedProvider: Bool
        /// Whether any stored unit price actually changed during this refresh.
        let changedPrices: Bool
        /// True when nothing the providers returned was newer than what was
        /// already stored. Saying so is more useful than implying an update.
        let foundNothingNewer: Bool
    }

    enum Status: Equatable {
        case idle
        case recentlyChecked
        case refreshing(completed: Int, total: Int)
        case finished(Summary)
    }

    @Published private(set) var status: Status = .idle

    private let tcgdex = TCGdexService()
    private let scryfall = ScryfallService()
    private let importedResolver = ImportedCardResolver()

    /// Below this age an automatic refresh is skipped. TCGplayer itself only
    /// republishes every few hours at best, so asking more often buys nothing and
    /// costs the user's battery and the provider's bandwidth.
    nonisolated static let automaticRefreshInterval: TimeInterval = 8 * 60 * 60

    /// Enough parallelism to make a few hundred cards quick, few enough to stay a
    /// polite client.
    private static let maxConcurrentRequests = 4

    private var isRefreshing: Bool {
        if case .refreshing = status { return true }
        return false
    }

    /// Targets that a refresh should bother with.
    nonisolated static func staleTargets(from targets: [PriceTarget], now: Date = .now) -> [PriceTarget] {
        targets.filter { target in
            // A previous "unavailable" result is not permanent. Manual refreshes
            // must always be able to revisit cards that still have no price.
            if !target.hasPrice { return true }

            let identityResolvedAfterFailure = target.catalogPrintingID != nil
                && target.lastFailureAt != nil
                && target.catalogMetadataCheckedAt.map {
                    $0 > (target.lastCheckedAt ?? .distantPast)
                } == true
            if identityResolvedAfterFailure { return true }

            let priceNeedsRefresh = target.lastCheckedAt.map {
                now.timeIntervalSince($0) >= automaticRefreshInterval
            } ?? true
            guard target.importedIdentity != nil else { return priceNeedsRefresh }
            let metadataNeedsRefresh = target.catalogMetadataCheckedAt.map {
                now.timeIntervalSince($0) >= automaticRefreshInterval
            } ?? true
            return priceNeedsRefresh || metadataNeedsRefresh
        }
    }

    /// - Parameter targets: already in display order, so whatever the user is
    ///   looking at becomes fresh first.
    func refresh(_ targets: [PriceTarget], store: PriceStore) async {
        guard !isRefreshing, !targets.isEmpty else { return }

        // Group by printing: every variant of one card shares a single response.
        var order: [PriceTarget.Printing] = []
        var byPrinting: [PriceTarget.Printing: [PriceTarget]] = [:]
        for target in targets {
            if byPrinting[target.printing] == nil { order.append(target.printing) }
            byPrinting[target.printing, default: []].append(target)
        }

        let previousLatest = latestKnownSourceUpdate(in: store)
        let importedCardsByProviderID = store.importedCardsByProviderID()
        var completed = 0
        var priced = 0
        var failed = 0
        var latestSourceUpdate: Date?
        var checkedUnstampedProvider = false
        var changedPrices = false
        var wasCancelled = false
        status = .refreshing(completed: 0, total: order.count)

        var cursor = 0
        await withTaskGroup(of: PriceFetchOutcome.self) { group in
            let initial = min(Self.maxConcurrentRequests, order.count)
            for _ in 0..<initial {
                let printing = order[cursor]
                cursor += 1
                group.addTask { [tcgdex, scryfall, importedResolver] in
                    await Self.fetch(
                        printing,
                        tcgdex: tcgdex,
                        scryfall: scryfall,
                        importedResolver: importedResolver
                    )
                }
            }

            while let outcome = await group.next() {
                let printing = outcome.printing
                let now = Date.now
                switch outcome.result {
                case let .card(card):
                    if printing.importedIdentity != nil {
                        for importedCard in importedCardsByProviderID[printing.printingID] ?? [] {
                            importedCard.applyCatalogMetadata(from: card, checkedAt: now)
                        }
                    }
                    if card.game == .magic {
                        // Scryfall never supplies a provider-side price timestamp,
                        // including when its price object contains no usable value.
                        checkedUnstampedProvider = true
                    }
                    for target in byPrinting[printing] ?? [] {
                        let lookup = CardPricing.price(
                            for: card,
                            variant: target.variantID.map(PhysicalVariant.resolving),
                            at: now
                        )
                        if case let .price(price) = lookup {
                            priced += 1
                            if let updated = price.sourceUpdatedAt,
                               updated > (latestSourceUpdate ?? .distantPast) {
                                latestSourceUpdate = updated
                            } else if price.sourceUpdatedAt == nil {
                                checkedUnstampedProvider = true
                            }
                        }

                        let key = PriceRecord.key(
                            game: target.game,
                            printingID: target.printingID,
                            variantID: target.variantID
                        )
                        let previousAmount = store.record(forKey: key)?.unitMarketPriceUSD
                        let newAmount: Double?
                        switch lookup {
                        case let .price(price): newAmount = price.unitMarketPriceUSD
                        case .unavailable: newAmount = previousAmount
                        }
                        if previousAmount != newAmount { changedPrices = true }

                        store.store(
                            lookup,
                            game: target.game,
                            printingID: target.printingID,
                            variantID: target.variantID,
                            at: now
                        )
                    }

                case .failed:
                    // Nothing is overwritten. The old price keeps its old age.
                    //
                    // `catalogMetadataCheckedAt` is deliberately *not* stamped
                    // here. It records when the catalog normalizer last tried to
                    // resolve this card's identity, and the normalizer uses it to
                    // decide when to try again. Writing it on a price failure
                    // starved exactly the cards that needed normalizing most: a
                    // card with no identity cannot be priced, the failed price
                    // check refreshed the timestamp, the normalizer then skipped
                    // the card as recently-checked, and the loop repeated forever.
                    // A price failure is already recorded on the price record.
                    failed += 1
                    for target in byPrinting[printing] ?? [] {
                        store.recordFailure(
                            game: target.game,
                            printingID: target.printingID,
                            variantID: target.variantID,
                            at: now
                        )
                    }

                case .cancelled:
                    wasCancelled = true
                }

                completed += 1
                status = .refreshing(completed: completed, total: order.count)

                if cursor < order.count, !wasCancelled, !Task.isCancelled {
                    let next = order[cursor]
                    cursor += 1
                    group.addTask { [tcgdex, scryfall, importedResolver] in
                        await Self.fetch(
                            next,
                            tcgdex: tcgdex,
                            scryfall: scryfall,
                            importedResolver: importedResolver
                        )
                    }
                }
            }
        }

        store.save()

        if wasCancelled || Task.isCancelled {
            status = .idle
            return
        }

        let checkedAt = Date.now
        status = .finished(
            Summary(
                checkedAt: checkedAt,
                priced: priced,
                failed: failed,
                latestSourceUpdate: latestSourceUpdate ?? previousLatest,
                checkedUnstampedProvider: checkedUnstampedProvider,
                changedPrices: changedPrices,
                foundNothingNewer: !isNewer(latestSourceUpdate, than: previousLatest)
            )
        )
    }

    /// A check that returns the same market timestamp is not an update, and
    /// saying "prices updated" when nothing moved is the kind of small lie that
    /// makes a whole collection feel untrustworthy.
    private func isNewer(_ candidate: Date?, than previous: Date?) -> Bool {
        guard let candidate else { return false }
        guard let previous else { return true }
        return candidate > previous
    }

    func dismissSummary() {
        switch status {
        case .finished, .recentlyChecked:
            status = .idle
        case .idle, .refreshing:
            break
        }
    }

    func markRecentlyChecked() {
        guard !isRefreshing else { return }
        status = .recentlyChecked
    }

    private func latestKnownSourceUpdate(in store: PriceStore) -> Date? {
        store.allRecords().compactMap(\.sourceUpdatedAt).max()
    }

    private nonisolated static func fetch(
        _ printing: PriceTarget.Printing,
        tcgdex: TCGdexService,
        scryfall: ScryfallService,
        importedResolver: ImportedCardResolver
    ) async -> PriceFetchOutcome {
        do {
            if let identity = printing.importedIdentity {
                let card = try await importedResolver.resolve(
                    game: printing.game,
                    identity: identity,
                    tcgdex: tcgdex,
                    scryfall: scryfall
                )
                return PriceFetchOutcome(printing: printing, result: .card(card))
            }

            switch printing.game {
            case .pokemon:
                let card = try await tcgdex.fetchCard(
                    id: printing.printingID,
                    // Japanese-exclusive printings are 404 on the English
                    // endpoint, and the Japanese one is where both their
                    // identity and their Cardmarket price live. Fetching the
                    // wrong edition turns a priceable card into an unreachable
                    // one.
                    locale: CatalogIdentityNormalization.locale(forCatalogCardID: printing.printingID),
                    ignoringCache: true
                )
                return PriceFetchOutcome(printing: printing, result: .card(.pokemon(card, setCode: printing.setCode)))
            case .magic:
                let card = try await scryfall.fetchCard(id: printing.printingID, ignoringCache: true)
                return PriceFetchOutcome(printing: printing, result: .card(.magic(card)))
            }
        } catch is CancellationError {
            return PriceFetchOutcome(printing: printing, result: .cancelled)
        } catch let error as URLError where error.code == .cancelled {
            return PriceFetchOutcome(printing: printing, result: .cancelled)
        } catch {
            return PriceFetchOutcome(printing: printing, result: .failed)
        }
    }
}

/// Resolves a CSV identity only when the user explicitly refreshes prices.
/// Directory requests are shared across the whole refresh, while each card is
/// fetched once and supplies both the verified identity and its current price.
private actor ImportedCardResolver {
    private var pokemonDirectoryTask: Task<[CatalogSetReference], Error>?
    private var magicDirectoryTask: Task<[CatalogSetReference], Error>?

    func resolve(
        game: CardGame,
        identity: ImportedPriceIdentity,
        tcgdex: TCGdexService,
        scryfall: ScryfallService
    ) async throws -> IdentifiedCard {
        let number = CatalogIdentityNormalization.localNumber(identity.cardNumber)
        guard !number.isEmpty else { throw TCGdexError.identityMismatch }

        switch game {
        case .pokemon:
            let sets = try await pokemonSets(using: tcgdex)
            let candidates = CatalogIdentityNormalization.matchingSets(
                named: identity.setName,
                cardName: identity.name,
                in: sets,
                game: game
            )
            for set in candidates {
                guard let card = try? await tcgdex.fetchCard(
                    setID: set.id,
                    localID: number,
                    ignoringCache: true
                ),
                      CatalogIdentityNormalization.namesMatch(
                        imported: identity.name,
                        catalog: card.name
                      ) else {
                    continue
                }
                let printedCode = SetCodeMap.definitions.values.first {
                    $0.tcgdexSetID.caseInsensitiveCompare(set.id) == .orderedSame
                }?.printedCode ?? set.id.uppercased()
                return .pokemon(card, setCode: printedCode)
            }
            throw TCGdexError.identityMismatch

        case .magic:
            let sets = try await magicSets(using: scryfall)
            let candidates = CatalogIdentityNormalization.matchingSets(
                named: identity.setName,
                cardName: identity.name,
                in: sets,
                game: game
            )
            for set in candidates {
                guard let card = try? await scryfall.fetchCard(
                    setCode: set.id,
                    collectorNumber: number,
                    language: "en",
                    ignoringCache: true,
                    requiresScannableCard: false
                ), CatalogIdentityNormalization.namesMatch(
                    imported: identity.name,
                    catalog: card.name
                ) else {
                    continue
                }
                return .magic(card)
            }
            throw ScryfallError.identityMismatch
        }
    }

    private func pokemonSets(using service: TCGdexService) async throws -> [CatalogSetReference] {
        if let pokemonDirectoryTask { return try await pokemonDirectoryTask.value }
        let task = Task { try await service.fetchSetDirectory() }
        pokemonDirectoryTask = task
        do {
            return try await task.value
        } catch {
            pokemonDirectoryTask = nil
            throw error
        }
    }

    private func magicSets(using service: ScryfallService) async throws -> [CatalogSetReference] {
        if let magicDirectoryTask { return try await magicDirectoryTask.value }
        let task = Task { try await service.fetchSetDirectory() }
        magicDirectoryTask = task
        do {
            return try await task.value
        } catch {
            magicDirectoryTask = nil
            throw error
        }
    }

}
