#if DEBUG || CARD_FINISH_PERF_HARNESS
import Foundation
import SwiftData
import UIKit

/// Deterministic portfolio inputs for screenshot routes. The production engine
/// still derives every close, reconciliation row, and chart point from them.
enum PortfolioDebugFixtures {
    /// The performance route is repeatedly relaunched while comparing
    /// scenarios. A reserved filename lets each run replace its one fixture
    /// image instead of orphaning a new UUID-backed file in Application
    /// Support.
    static let cardFinishPerformanceArtworkFilename = "card-finish-performance.image"

    @MainActor
    static func seedMovementIfNeeded(in modelContext: ModelContext) {
        guard (try? modelContext.fetch(FetchDescriptor<CollectedCard>()))?.isEmpty != false else { return }

        let timeZone = PortfolioCalendar.pinnedTimeZone() ?? .current
        let today = PortfolioCalendar.day(containing: .now, in: timeZone)
        let epochDay = PortfolioCalendar.day(
            containing: today.addingTimeInterval(-3 * 86_400),
            in: timeZone
        )
        UserDefaults.standard.set(epochDay.timeIntervalSince1970, forKey: PortfolioEpoch.defaultsKey)

        let product = SealedProductSummary(
            id: "ui-movement-card",
            name: "Movement Details QA Card",
            setName: "Movement QA",
            variantID: "ui-movement-card-variant",
            marketPriceUSD: 9.95,
            updatedAt: .now,
            imageURL: nil
        )
        let store = CollectionStore(context: modelContext)
        _ = try? store.addSealed(product, game: .pokemon)
        _ = try? store.addSealed(product, game: .pokemon)
        _ = try? store.addSealed(product, game: .pokemon)

        guard let card = (try? modelContext.fetch(FetchDescriptor<CollectedCard>()))?.first else { return }
        let ledger = InventoryLedger(context: modelContext)
        let instrument = ledger.priceStorageKey(for: card)
        for event in (try? ledger.events(collectionKey: card.collectionKey)) ?? [] {
            event.occurredAt = epochDay.addingTimeInterval(60)
        }

        let first = epochDay.addingTimeInterval(3_600)
        modelContext.insert(
            PriceObservation(
                instrumentKey: instrument,
                kind: .marketUpdate,
                amount: Money(rounding: 10),
                source: .justTCG,
                sourceVariantID: card.justTCGVariantID,
                marketVariantID: card.justTCGVariantID,
                effectiveAt: first,
                receivedAt: first,
                isSourceStamped: true
            )
        )
        modelContext.insert(
            PriceObservation(
                instrumentKey: instrument,
                kind: .marketUpdate,
                amount: Money(rounding: 9.95),
                source: .justTCG,
                sourceVariantID: card.justTCGVariantID,
                marketVariantID: card.justTCGVariantID,
                effectiveAt: .now,
                receivedAt: .now,
                isSourceStamped: true
            )
        )
        modelContext.insert(
            PriceCheckDay(
                instrumentKey: instrument,
                portfolioDay: today,
                lastSuccessfulCheckAt: .now,
                source: .justTCG
            )
        )
        if let record = PriceStore(context: modelContext).record(forKey: instrument) {
            record.unitMarketPriceUSD = 9.95
            record.fetchedAt = .now
            record.sourceUpdatedAt = .now
            record.lastSuccessfulCheckAt = .now
        }
        try? modelContext.save()
    }

    @MainActor
    static func seedHistoryIfNeeded(in modelContext: ModelContext) {
        guard (try? modelContext.fetch(FetchDescriptor<CollectedCard>()))?.isEmpty != false else { return }

        let timeZone = PortfolioCalendar.pinnedTimeZone() ?? .current
        let today = PortfolioCalendar.day(containing: .now, in: timeZone)
        let epochDay = PortfolioCalendar.day(
            containing: today.addingTimeInterval(-5 * 86_400),
            in: timeZone
        )
        UserDefaults.standard.set(epochDay.timeIntervalSince1970, forKey: PortfolioEpoch.defaultsKey)
        UserDefaults.standard.set(PortfolioHistoryRange.all.rawValue, forKey: "portfolioHistoryRange")

        _ = try? CollectionStore(context: modelContext).addSealed(
            SealedProductSummary(
                id: "ui-history-product",
                name: "History QA Booster Box",
                setName: "Trustworthy History",
                variantID: "ui-history-variant",
                marketPriceUSD: 100,
                updatedAt: .now,
                imageURL: nil,
                tcgplayerProductID: "247241"
            ),
            game: .pokemon
        )

        guard let card = (try? modelContext.fetch(FetchDescriptor<CollectedCard>()))?.first else { return }
        let instrument = InventoryLedger(context: modelContext).priceStorageKey(for: card)
        for event in (try? InventoryLedger(context: modelContext).events(collectionKey: card.collectionKey)) ?? [] {
            event.occurredAt = epochDay.addingTimeInterval(60)
        }

        let prices: [Double] = [100, 104, 101, 112, 118, 125]
        for (offset, price) in prices.enumerated() {
            let day = PortfolioCalendar.day(
                containing: epochDay.addingTimeInterval(Double(offset) * 86_400),
                in: timeZone
            )
            let receivedAt = offset == prices.count - 1 ? Date.now : day.addingTimeInterval(3_600)
            modelContext.insert(
                PriceObservation(
                    instrumentKey: instrument,
                    kind: .marketUpdate,
                    amount: Money(rounding: price),
                    source: .justTCG,
                    sourceVariantID: "ui-history-variant",
                    marketVariantID: "ui-history-variant",
                    effectiveAt: receivedAt,
                    receivedAt: receivedAt,
                    isSourceStamped: true
                )
            )
            modelContext.insert(
                PriceCheckDay(
                    instrumentKey: instrument,
                    portfolioDay: day,
                    lastSuccessfulCheckAt: receivedAt,
                    source: .justTCG
                )
            )
        }

        if let record = PriceStore(context: modelContext).record(forKey: instrument), let latest = prices.last {
            record.unitMarketPriceUSD = latest
            record.fetchedAt = .now
            record.sourceUpdatedAt = .now
            record.lastSuccessfulCheckAt = .now
        }
        try? modelContext.save()
    }

    @MainActor
    static func seedTodayIfNeeded(in modelContext: ModelContext) {
        guard (try? modelContext.fetch(FetchDescriptor<CollectedCard>()))?.isEmpty != false else { return }

        let cardDetailArtworkURL = URL(string: "https://images.pokemontcg.io/base1/4_hires.png")
        let timeZone = PortfolioCalendar.pinnedTimeZone() ?? .current
        let today = PortfolioCalendar.day(containing: .now, in: timeZone)
        let epoch = PortfolioCalendar.day(
            containing: today.addingTimeInterval(-2 * 86_400),
            in: timeZone
        )
        UserDefaults.standard.set(
            epoch.addingTimeInterval(60).timeIntervalSince1970,
            forKey: PortfolioEpoch.defaultsKey
        )
        let fixtures: [(id: String, name: String, old: Double, current: Double)] = [
            ("ui-portfolio-charizard", "Charizard ex", 300, 342),
            ("ui-portfolio-umbreon", "Umbreon VMAX", 240, 271),
            ("ui-portfolio-mewtwo", "Mewtwo ex", 140, 126),
            ("ui-portfolio-box", "Pokémon 151 Booster Bundle", 90, 108)
        ]
        let store = CollectionStore(context: modelContext)
        for fixture in fixtures {
            if fixture.id == "ui-portfolio-charizard" {
                let charizard = TCGdexCard(
                    id: fixture.id,
                    localId: "004",
                    name: fixture.name,
                    image: cardDetailArtworkURL?.absoluteString,
                    rarity: "Rare",
                    set: TCGdexSetBrief(
                        id: "portfolio-qa",
                        name: "Portfolio QA",
                        cardCount: TCGdexCardCount(total: 4, official: 4)
                    ),
                    variants: TCGdexVariants(
                        firstEdition: false,
                        holo: true,
                        normal: false,
                        reverse: false,
                        wPromo: nil
                    ),
                    pricing: nil,
                    variantsDetailed: nil
                )
                // This route is the finish-rendering fixture. Keep it on the
                // normal collection path so the stored item kind, variant
                // provenance, artwork, and price key agree with one another.
                _ = try? store.add(
                    .pokemon(charizard, setCode: "PQA"),
                    resolved: ResolvedVariant(
                        variant: .holo,
                        resolution: .uniqueInCatalog
                    ),
                    identityResolution: .catalogSelected
                )
                continue
            }
            let product = SealedProductSummary(
                id: fixture.id,
                name: fixture.name,
                setName: "Portfolio QA",
                variantID: "\(fixture.id)-variant",
                marketPriceUSD: fixture.current,
                updatedAt: .now,
                imageURL: cardDetailArtworkURL
            )
            // Keep one duplicate position in the deterministic portfolio
            // route. Its $542 combined value must not outrank Charizard's
            // $342 single-card price; the row should still make the two-copy
            // total obvious.
            let quantity = fixture.id == "ui-portfolio-umbreon" ? 2 : 1
            for _ in 0..<quantity {
                _ = try? store.addSealed(product, game: .pokemon)
            }
        }

        let cards = (try? modelContext.fetch(FetchDescriptor<CollectedCard>())) ?? []
        if let charizard = cards.first(where: { $0.name == "Charizard ex" }) {
            let sourceVariantID = charizard.variantID ?? charizard.providerID
            _ = PriceStore(context: modelContext).store(
                .price(
                    NormalizedPrice(
                        unitMarketPriceUSD: 342,
                        currencyCode: "USD",
                        source: .justTCG,
                        sourceVariantID: sourceVariantID,
                        sourceUpdatedAt: .now,
                        fetchedAt: .now
                    )
                ),
                game: .pokemon,
                printingID: charizard.priceStorageID,
                variantID: charizard.variantID,
                marketVariantID: sourceVariantID,
                at: .now
            )
        }
        for (card, fixture) in zip(cards.sorted { $0.name < $1.name }, fixtures.sorted { $0.name < $1.name }) {
            let instrument = InventoryLedger(context: modelContext).priceStorageKey(for: card)
            for event in (try? InventoryLedger(context: modelContext).events(collectionKey: card.collectionKey)) ?? [] {
                event.occurredAt = epoch.addingTimeInterval(60)
            }
            let sourceVariantID = card.justTCGVariantID ?? card.variantID ?? card.providerID
            modelContext.insert(
                PriceObservation(
                    instrumentKey: instrument,
                    kind: .marketUpdate,
                    amount: Money(rounding: fixture.old),
                    source: .justTCG,
                    sourceVariantID: sourceVariantID,
                    marketVariantID: sourceVariantID,
                    effectiveAt: epoch.addingTimeInterval(3_600),
                    receivedAt: epoch.addingTimeInterval(3_600),
                    isSourceStamped: true
                )
            )
            // `addSealed` above records the current fixture price through
            // `PriceStore` and the matching successful check day. Backfill
            // only the earlier value here; inserting either current evidence
            // again creates duplicate rows at today's timestamp.
            if let record = PriceStore(context: modelContext).record(forKey: instrument) {
                record.unitMarketPriceUSD = fixture.current
                record.fetchedAt = .now
                record.sourceUpdatedAt = .now
                record.lastSuccessfulCheckAt = .now
            }
        }
        try? modelContext.save()
    }

    enum CardFinishPerformanceScenario: String, CaseIterable, Equatable, Sendable {
        case gridOnly = "grid-only"
        case gridWithDetail = "grid-with-detail"
        case nonfoilControl = "nonfoil-control"
        case singleDetail = "single-detail"
        case singleDetailControl = "single-detail-control"
    }

    struct CardFinishPerformanceFixtureSpec: Equatable, Sendable {
        let scenario: CardFinishPerformanceScenario
        let requestedRowCount: Int
        let eligibleFinishRowCount: Int
        let nonfoilControlRowCount: Int
        let sealedControlRowCount: Int

        init(scenario: CardFinishPerformanceScenario, rowCount: Int) {
            let normalizedRowCount = min(max(rowCount, 12), 48)
            self.scenario = scenario
            requestedRowCount = normalizedRowCount
            sealedControlRowCount = 1

            switch scenario {
            case .gridOnly, .gridWithDetail, .singleDetail:
                // The requested count is the number of eligible finish rows.
                // Controls are added separately so the named 12/24/48 sizes
                // remain honest rather than being diluted by normal cards.
                eligibleFinishRowCount = normalizedRowCount
                nonfoilControlRowCount = 1
            case .nonfoilControl, .singleDetailControl:
                eligibleFinishRowCount = 0
                nonfoilControlRowCount = normalizedRowCount
            }
        }

        var rawCardRowCount: Int {
            eligibleFinishRowCount + nonfoilControlRowCount
        }

        var totalRowCount: Int {
            rawCardRowCount + sealedControlRowCount
        }
    }

    static func cardFinishPerformanceScenario() -> CardFinishPerformanceScenario {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-scenario"),
              arguments.indices.contains(index + 1),
              let scenario = CardFinishPerformanceScenario(rawValue: arguments[index + 1]) else {
            return .gridOnly
        }
        return scenario
    }

    static func cardFinishPerformanceRowCount() -> Int {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-row-count"),
              arguments.indices.contains(index + 1),
              let requested = Int(arguments[index + 1]) else {
            return 24
        }
        return min(max(requested, 12), 48)
    }

    static func cardFinishPerformanceFixtureSpec(
        scenario: CardFinishPerformanceScenario,
        rowCount: Int
    ) -> CardFinishPerformanceFixtureSpec {
        CardFinishPerformanceFixtureSpec(scenario: scenario, rowCount: rowCount)
    }

    private static func prepareCardFinishPerformanceArtwork() -> String {
        guard let image = UIImage(named: "AppIcon"),
              let data = image.pngData(),
              let filename = CollectionArtworkStore.save(
                  data,
                  filename: cardFinishPerformanceArtworkFilename
              ) else {
            preconditionFailure("Could not prepare the bundled card-finish performance artwork.")
        }
        return filename
    }

    private static func makeCardFinishPerformanceCard(
        index: Int,
        rawCardRowCount: Int
    ) -> TCGdexCard {
        TCGdexCard(
            id: "card-finish-performance-\(index)",
            localId: String(format: "%03d", index + 1),
            name: "Finish Performance \(index + 1)",
            // The same local override is attached to every raw and sealed
            // fixture row below. The catalog object itself stays provider-like;
            // the local override exercises image decoding and accent caching
            // without any network dependency.
            image: nil,
            rarity: "QA",
            set: TCGdexSetBrief(
                id: "card-finish-performance",
                name: "Card Finish Performance",
                cardCount: TCGdexCardCount(
                    total: rawCardRowCount,
                    official: rawCardRowCount
                )
            ),
            variants: TCGdexVariants(
                firstEdition: false,
                holo: true,
                normal: true,
                reverse: true,
                wPromo: nil
            ),
            pricing: nil,
            variantsDetailed: nil
        )
    }

    /// Seeds a fresh, deterministic performance collection. The app selects an
    /// in-memory container before this method runs, so deleting the model rows
    /// here resets a scenario without ever touching a user's saved collection.
    @MainActor
    static func seedCardFinishPerformance(in modelContext: ModelContext) -> String? {
        let previousArtworkFilenames = Set(
            ((try? modelContext.fetch(FetchDescriptor<LocalArtworkOverride>())) ?? [])
                .map(\.filename)
                .filter { !$0.isEmpty }
        )
        for card in (try? modelContext.fetch(FetchDescriptor<CollectedCard>())) ?? [] {
            modelContext.delete(card)
        }
        for activity in (try? modelContext.fetch(FetchDescriptor<CollectionActivity>())) ?? [] {
            modelContext.delete(activity)
        }
        for event in (try? modelContext.fetch(FetchDescriptor<InventoryEvent>())) ?? [] {
            modelContext.delete(event)
        }
        for record in (try? modelContext.fetch(FetchDescriptor<PriceRecord>())) ?? [] {
            modelContext.delete(record)
        }
        for observation in (try? modelContext.fetch(FetchDescriptor<PriceObservation>())) ?? [] {
            modelContext.delete(observation)
        }
        for day in (try? modelContext.fetch(FetchDescriptor<PriceCheckDay>())) ?? [] {
            modelContext.delete(day)
        }
        for close in (try? modelContext.fetch(FetchDescriptor<PortfolioDailyClose>())) ?? [] {
            modelContext.delete(close)
        }
        for quote in (try? modelContext.fetch(FetchDescriptor<ReferenceQuote>())) ?? [] {
            modelContext.delete(quote)
        }
        for identity in (try? modelContext.fetch(FetchDescriptor<ProductIdentity>())) ?? [] {
            modelContext.delete(identity)
        }
        for artwork in (try? modelContext.fetch(FetchDescriptor<LocalArtworkOverride>())) ?? [] {
            modelContext.delete(artwork)
        }
        for filename in previousArtworkFilenames {
            CollectionArtworkStore.remove(filename: filename)
        }

        let scenario = cardFinishPerformanceScenario()
        let fixture = cardFinishPerformanceFixtureSpec(
            scenario: scenario,
            rowCount: cardFinishPerformanceRowCount()
        )
        let store = CollectionStore(context: modelContext)
        let artworkFilename = prepareCardFinishPerformanceArtwork()
        var firstEligibleCollectionKey: String?
        var insertedRowCount = 0

        for index in 0..<fixture.eligibleFinishRowCount {
            let variant: PhysicalVariant
            switch index % 3 {
            case 0: variant = .foil
            case 1: variant = .holo
            default: variant = .reverse
            }

            do {
                let mutation = try store.add(
                    .pokemon(
                        makeCardFinishPerformanceCard(
                            index: index,
                            rawCardRowCount: fixture.rawCardRowCount
                        ),
                        setCode: "CFP"
                    ),
                    resolved: ResolvedVariant(
                        variant: variant,
                        resolution: .uniqueInCatalog
                    ),
                    identityResolution: .catalogSelected,
                    setReleaseOrder: index,
                    quantity: 1
                )
                CollectionArtworkStore.set(
                    filename: artworkFilename,
                    for: mutation.collectionKey,
                    in: modelContext
                )
                insertedRowCount += 1
                if firstEligibleCollectionKey == nil {
                    firstEligibleCollectionKey = mutation.collectionKey
                }
            } catch {
                preconditionFailure("Could not seed card-finish performance row \(index): \(error)")
            }
        }

        for controlIndex in 0..<fixture.nonfoilControlRowCount {
            let index = fixture.eligibleFinishRowCount + controlIndex
            do {
                let mutation = try store.add(
                    .pokemon(
                        makeCardFinishPerformanceCard(
                            index: index,
                            rawCardRowCount: fixture.rawCardRowCount
                        ),
                        setCode: "CFP"
                    ),
                    resolved: ResolvedVariant(
                        variant: .normal,
                        resolution: .uniqueInCatalog
                    ),
                    identityResolution: .catalogSelected,
                    setReleaseOrder: index,
                    quantity: 1
                )
                CollectionArtworkStore.set(
                    filename: artworkFilename,
                    for: mutation.collectionKey,
                    in: modelContext
                )
                insertedRowCount += 1
            } catch {
                preconditionFailure("Could not seed nonfoil performance control \(controlIndex): \(error)")
            }
        }

        for controlIndex in 0..<fixture.sealedControlRowCount {
            let product = SealedProductSummary(
                id: "card-finish-performance-sealed-\(controlIndex)",
                name: "Finish Performance Sealed Control",
                setName: "Card Finish Performance",
                variantID: "card-finish-performance-sealed-variant-\(controlIndex)",
                marketPriceUSD: nil,
                updatedAt: .now,
                imageURL: nil
            )
            do {
                let mutation = try store.addSealed(product, game: .pokemon)
                CollectionArtworkStore.set(
                    filename: artworkFilename,
                    for: mutation.collectionKey,
                    in: modelContext
                )
                insertedRowCount += 1
            } catch {
                preconditionFailure("Could not seed sealed performance control \(controlIndex): \(error)")
            }
        }

        do {
            try modelContext.save()
        } catch {
            preconditionFailure("Could not save card-finish performance fixture: \(error)")
        }
        CardFinishPerformanceDiagnostics.shared.reset(
            scenario: scenario.rawValue,
            rowCount: insertedRowCount
        )
        PerformanceSignpost.emitEvent(
            "cardFinishScenario",
            "scenario=\(scenario.rawValue) rows=\(insertedRowCount) eligible=\(fixture.eligibleFinishRowCount) nonfoil=\(fixture.nonfoilControlRowCount) sealed=\(fixture.sealedControlRowCount)"
        )
        return firstEligibleCollectionKey
    }

    static func debugResolution() -> VariantResolution {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ui_debug_state"),
              arguments.indices.contains(index + 1),
              let resolution = VariantResolution(rawValue: arguments[index + 1]) else {
            return .catalogSilent
        }
        return resolution
    }

    @MainActor
    static func seedTrustProvenanceIfNeeded(
        in modelContext: ModelContext,
        resolution: VariantResolution
    ) -> String? {
        let providerID = "ui-trust-provenance-\(resolution.rawValue)"
        let existing = (try? modelContext.fetch(FetchDescriptor<CollectedCard>())) ?? []
        if let existingCard = existing.first(where: { $0.providerID == providerID }) {
            return existingCard.collectionKey
        }

        let variants: TCGdexVariants
        let selected: PhysicalVariant?
        switch resolution {
        case .catalogSilent:
            variants = TCGdexVariants(
                firstEdition: false,
                holo: false,
                normal: false,
                reverse: false,
                wPromo: nil
            )
            selected = nil
        case .finishLock:
            variants = TCGdexVariants(
                firstEdition: false,
                holo: false,
                normal: true,
                reverse: true,
                wPromo: nil
            )
            selected = .reverse
        case .userConfirmed:
            variants = TCGdexVariants(
                firstEdition: false,
                holo: true,
                normal: true,
                reverse: false,
                wPromo: nil
            )
            selected = .holo
        case .uniqueInCatalog, .deterministicSetRule, .printedLabel:
            variants = TCGdexVariants(
                firstEdition: false,
                holo: true,
                normal: false,
                reverse: false,
                wPromo: nil
            )
            selected = .holo
        case .imported:
            variants = TCGdexVariants(
                firstEdition: false,
                holo: false,
                normal: true,
                reverse: false,
                wPromo: nil
            )
            selected = .normal
        }

        let card = TCGdexCard(
            id: providerID,
            localId: "004",
            name: "Charizard — Provenance QA",
            image: "https://images.pokemontcg.io/base1/4_hires.png",
            rarity: "Rare",
            set: TCGdexSetBrief(
                id: "trust-provenance-qa",
                name: "Trust Provenance QA",
                cardCount: TCGdexCardCount(total: 1, official: 1)
            ),
            variants: variants,
            pricing: nil,
            variantsDetailed: nil
        )
        let store = CollectionStore(context: modelContext)
        _ = try? store.add(
            .pokemon(card, setCode: "TRUST"),
            resolved: ResolvedVariant(variant: selected, resolution: resolution),
            identityResolution: .catalogSelected
        )

        guard let stored = (try? modelContext.fetch(FetchDescriptor<CollectedCard>()))?
            .first(where: { $0.providerID == providerID }) else { return nil }
        let sourceVariantID = stored.justTCGVariantID ?? stored.variantID ?? stored.providerID
        _ = PriceStore(context: modelContext).store(
            .price(
                NormalizedPrice(
                    unitMarketPriceUSD: 42,
                    currencyCode: "USD",
                    source: .justTCG,
                    sourceVariantID: sourceVariantID,
                    sourceUpdatedAt: .now,
                    fetchedAt: .now
                )
            ),
            game: .pokemon,
            printingID: stored.priceStorageID,
            variantID: stored.variantID,
            marketVariantID: sourceVariantID,
            at: .now
        )
        try? modelContext.save()
        return stored.collectionKey
    }

    @MainActor
    static func seedCollectionFooter4aIfNeeded(in modelContext: ModelContext) {
        guard (try? modelContext.fetch(FetchDescriptor<CollectedCard>()))?.isEmpty != false else { return }

        let card = TCGdexCard(
            id: "ui-collection-footer-4a",
            localId: "084",
            name: "Bilbo Baggins, Ring-Bearer",
            image: "https://images.pokemontcg.io/base1/4_hires.png",
            rarity: "Rare",
            set: TCGdexSetBrief(
                id: "hobbit-eternal",
                name: "The Hobbit Eternal",
                cardCount: TCGdexCardCount(total: 1, official: 1)
            ),
            variants: TCGdexVariants(
                firstEdition: false,
                holo: false,
                normal: false,
                reverse: true,
                wPromo: nil
            ),
            pricing: nil,
            variantsDetailed: nil
        )
        let reverseHolo = PhysicalVariant(
            id: PhysicalVariant.reverse.id,
            label: "Reverse holo"
        )
        let store = CollectionStore(context: modelContext)
        _ = try? store.add(
            .pokemon(card, setCode: "HOB"),
            resolved: ResolvedVariant(
                variant: reverseHolo,
                resolution: .userConfirmed
            ),
            identityResolution: .catalogSelected,
            quantity: 12
        )

        guard let stored = try? modelContext.fetch(FetchDescriptor<CollectedCard>()).first else { return }
        let marketVariantID = stored.justTCGVariantID ?? stored.variantID ?? stored.providerID
        _ = PriceStore(context: modelContext).store(
            .price(
                NormalizedPrice(
                    unitMarketPriceUSD: 1_234.56,
                    currencyCode: "USD",
                    source: .justTCG,
                    sourceVariantID: marketVariantID,
                    sourceUpdatedAt: .now,
                    fetchedAt: .now
                )
            ),
            game: .pokemon,
            printingID: stored.priceStorageID,
            variantID: stored.variantID,
            marketVariantID: marketVariantID,
            at: .now
        )
        try? modelContext.save()
    }
}
#endif
