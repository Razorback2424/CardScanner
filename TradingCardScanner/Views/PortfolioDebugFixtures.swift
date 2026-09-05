#if DEBUG
import Foundation
import SwiftData

/// Deterministic portfolio inputs for screenshot routes. The production engine
/// still derives every close, reconciliation row, and chart point from them.
enum PortfolioDebugFixtures {
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
        UserDefaults.standard.set(PortfolioHistoryMode.marketMovement.rawValue, forKey: "portfolioHistoryMode")
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
            _ = try? store.addSealed(
                SealedProductSummary(
                    id: fixture.id,
                    name: fixture.name,
                    setName: "Portfolio QA",
                    variantID: "\(fixture.id)-variant",
                    marketPriceUSD: fixture.current,
                    updatedAt: .now,
                    imageURL: nil
                ),
                game: .pokemon
            )
        }

        let cards = (try? modelContext.fetch(FetchDescriptor<CollectedCard>())) ?? []
        for (card, fixture) in zip(cards.sorted { $0.name < $1.name }, fixtures.sorted { $0.name < $1.name }) {
            let instrument = InventoryLedger(context: modelContext).priceStorageKey(for: card)
        for event in (try? InventoryLedger(context: modelContext).events(collectionKey: card.collectionKey)) ?? [] {
                event.occurredAt = epoch.addingTimeInterval(60)
            }
            modelContext.insert(
                PriceObservation(
                    instrumentKey: instrument,
                    kind: .marketUpdate,
                    amount: Money(rounding: fixture.old),
                    source: .justTCG,
                    sourceVariantID: card.justTCGVariantID,
                    marketVariantID: card.justTCGVariantID,
                    effectiveAt: epoch.addingTimeInterval(3_600),
                    receivedAt: epoch.addingTimeInterval(3_600),
                    isSourceStamped: true
                )
            )
            modelContext.insert(
                PriceObservation(
                    instrumentKey: instrument,
                    kind: .marketUpdate,
                    amount: Money(rounding: fixture.current),
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
                record.unitMarketPriceUSD = fixture.current
                record.fetchedAt = .now
                record.sourceUpdatedAt = .now
                record.lastSuccessfulCheckAt = .now
            }
        }
        try? modelContext.save()
    }
}
#endif
