import XCTest
import SwiftUI
import UIKit
@testable import TradingCardScanner

/// What a shared card image is allowed to state. Every rule here protects the
/// recipient from a claim the app cannot stand behind.
final class CardShareContentTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let locale = Locale(identifier: "en_US")
    private lazy var now = date(2026, 10, 31)

    // MARK: - Collector number

    func testNumberSplitsCardNumberFromSetTotal() {
        let number = CardShareNumber("087/165")
        XCTAssertEqual(number?.primary, "087")
        XCTAssertEqual(number?.total, "/165")
        XCTAssertEqual(number?.text, "087/165")
    }

    func testNumberWithoutTotalKeepsWholeValue() {
        XCTAssertEqual(CardShareNumber("TG12")?.primary, "TG12")
        XCTAssertNil(CardShareNumber("TG12")?.total)
        XCTAssertNil(CardShareNumber("  "))
        XCTAssertNil(CardShareNumber("/165"))
    }

    // MARK: - Finish badge

    func testStandardFinishesGetNoBadge() {
        XCTAssertNil(CardShareIdentity.finishBadge(for: .normal))
        XCTAssertNil(CardShareIdentity.finishBadge(for: .nonfoil))
        XCTAssertNil(CardShareIdentity.finishBadge(for: nil))
        XCTAssertEqual(CardShareIdentity.finishBadge(for: .reverse), .finish(PhysicalVariant.reverse.label))
        XCTAssertEqual(CardShareIdentity.finishBadge(for: .holo), .finish(PhysicalVariant.holo.label))
    }

    // MARK: - Price basis and attribution

    func testRawPriceIsLabelledWithProviderConditionNotTheCopy() {
        XCTAssertEqual(CardSharePrice.basis(itemKind: .rawCard, gradeLabel: nil, source: .tcgplayer), "Near Mint market")
        XCTAssertEqual(CardSharePrice.basis(itemKind: .rawCard, gradeLabel: nil, source: .justTCG), "Near Mint market")
        XCTAssertEqual(CardSharePrice.basis(itemKind: .rawCard, gradeLabel: nil, source: .tcgCSV), "Market price")
        XCTAssertEqual(CardSharePrice.basis(itemKind: .rawCard, gradeLabel: nil, source: .scryfall), "Market price")
        XCTAssertEqual(CardSharePrice.basis(itemKind: .gradedCard, gradeLabel: "PSA 10", source: .justTCG), "PSA 10 market")
        XCTAssertEqual(CardSharePrice.basis(itemKind: .sealedProduct, gradeLabel: nil, source: .tcgplayer), "Market price")
    }

    func testPriceRequiresUsableAmount() {
        XCTAssertNil(CardSharePrice(display: PriceDisplay(amount: nil, source: .tcgplayer), basis: "Near Mint market"))
        XCTAssertNil(CardSharePrice(display: PriceDisplay(amount: 0, source: .tcgplayer), basis: "Near Mint market"))
        XCTAssertNotNil(CardSharePrice(display: PriceDisplay(amount: 64.2, source: .tcgplayer), basis: "Near Mint market"))
    }

    func testSourceLineUsesShortSourceAndDate() {
        let display = PriceDisplay(amount: 64.2, source: .tcgCSV, sourceUpdatedAt: now)
        let price = CardSharePrice(display: display, basis: "Near Mint market")
        XCTAssertEqual(price?.sourceLine(now: now, calendar: calendar, locale: locale), "TCGplayer · Oct 31")
    }

    func testSourceLineIncludesYearForOlderQuote() {
        let price = CardSharePrice(amount: 10, currencyCode: "USD", basis: "Market price", source: "TCGplayer", asOf: date(2025, 12, 30))
        XCTAssertEqual(price.sourceLine(now: now, calendar: calendar, locale: locale), "TCGplayer · Dec 30, 2025")
    }

    // MARK: - Trend

    func testTrendNeedsEnoughHistory() {
        let fewPoints = points([(80, 50), (60, 52), (40, 54), (20, 56)])
        XCTAssertNil(CardShareTrend.make(points: fewPoints, now: now))

        let shortSpan = points([(10, 50), (8, 52), (6, 54), (4, 56), (2, 58)])
        XCTAssertNil(CardShareTrend.make(points: shortSpan, now: now), "Under two weeks of history makes no trend claim")
    }

    func testRisingTrendAtItsHigh() throws {
        let trend = try XCTUnwrap(CardShareTrend.make(points: points([
            (89, 57.32), (70, 56.40), (50, 59.00), (30, 61.20), (0, 64.20)
        ]), now: now))
        XCTAssertEqual(trend.direction, .up)
        XCTAssertEqual(trend.percentChange, 12)
        XCTAssertEqual(trend.position, .atHigh)
        XCTAssertTrue(trend.coversFullWindow)
        XCTAssertEqual(trend.headline(now: now, calendar: calendar, locale: locale), "Up 12% in 3 months")
        XCTAssertEqual(trend.positionText(now: now, calendar: calendar, locale: locale), "At its 3-month high")
    }

    func testFallingTrendNearLowWithPartialHistory() throws {
        let trend = try XCTUnwrap(CardShareTrend.make(points: points([
            (49, 100), (40, 96), (30, 98), (20, 89), (0, 90)
        ]), now: now))
        XCTAssertEqual(trend.direction, .down)
        XCTAssertEqual(trend.percentChange, 10)
        XCTAssertEqual(trend.position, .nearLow)
        XCTAssertFalse(trend.coversFullWindow)
        XCTAssertEqual(trend.headline(now: now, calendar: calendar, locale: locale), "Down 10% since Sep 12")
        XCTAssertEqual(trend.positionText(now: now, calendar: calendar, locale: locale), "Near its low since Sep 12")
    }

    func testMidRangePriceSaysNothingAboutPosition() throws {
        let trend = try XCTUnwrap(CardShareTrend.make(points: points([
            (85, 50), (60, 70), (40, 50), (20, 70), (0, 60)
        ]), now: now))
        XCTAssertNil(trend.position)
        XCTAssertNil(trend.positionText(now: now, calendar: calendar, locale: locale))
    }

    func testTrendIgnoresPointsOutsideWindowAndInvalidPrices() throws {
        let trend = try XCTUnwrap(CardShareTrend.make(points: points([
            (200, 5), (88, 40), (60, 0), (50, 42), (30, 43), (15, 44), (0, 44)
        ]) + [JustTCGHistoryPoint(p: .nan, t: now.timeIntervalSince1970)], now: now))
        XCTAssertEqual(trend.samples.count, 5)
        XCTAssertEqual(trend.samples.first?.amount, 40)
        XCTAssertEqual(trend.percentChange, 10)
    }

    func testFlatTrend() throws {
        let trend = try XCTUnwrap(CardShareTrend.make(points: points([
            (85, 20), (60, 20.02), (40, 19.99), (20, 20.01), (0, 20)
        ]), now: now))
        XCTAssertEqual(trend.direction, .flat)
        XCTAssertEqual(trend.headline(now: now, calendar: calendar, locale: locale), "Flat over 3 months")
    }

    // MARK: - Asking price

    func testAskComparedToMarket() {
        XCTAssertEqual(CardShareAsk(text: "55", market: 64.2, locale: locale)?.comparisonText, "14% under market")
        XCTAssertEqual(CardShareAsk(text: "70", market: 64.2, locale: locale)?.comparisonText, "9% over market")
        XCTAssertEqual(CardShareAsk(text: "64.20", market: 64.2, locale: locale)?.comparisonText, "At market")
    }

    func testAskParsingAcceptsLocaleAndPastedFormatting() {
        XCTAssertEqual(CardShareAsk.parse("$1,234.50", locale: locale), 1234.5)
        XCTAssertEqual(CardShareAsk.parse("55,00", locale: Locale(identifier: "de_DE")), 55)
        XCTAssertNil(CardShareAsk.parse("", locale: locale))
        XCTAssertNil(CardShareAsk.parse("0", locale: locale))
        XCTAssertNil(CardShareAsk.parse("1.2.3", locale: locale))
        for invalid in ["50–60", "50-60", "-25", "1e3", "12oops", "1,2", "€50", "NaN", "Infinity"] {
            XCTAssertNil(CardShareAsk.parse(invalid, locale: locale), invalid)
        }
        let arabic = Locale(identifier: "ar_EG")
        XCTAssertEqual(CardShareAsk.parse(55.25.formatted(.number.locale(arabic)), locale: arabic), 55.25)
        let german = Locale(identifier: "de_DE")
        let euros = 1234.5.formatted(.currency(code: "EUR").locale(german))
        XCTAssertEqual(CardShareAsk.parse(euros, locale: german, currencyCode: "EUR"), 1234.5)
        XCTAssertNil(CardShareAsk(text: "55", market: .infinity, locale: locale))
        XCTAssertNil(CardShareAsk(text: "55", market: .leastNonzeroMagnitude, locale: locale))
    }

    // MARK: - Plain-text summary

    func testSummaryCarriesTheSameFactsAsTheImage() throws {
        let identity = CardShareIdentity(
            name: "Voltfin ex",
            setCode: "STF",
            setName: "Stormfront Tides",
            number: CardShareNumber("087/165"),
            badge: .finish("Reverse")
        )
        let price = CardSharePrice(amount: 64.2, currencyCode: "USD", basis: "Near Mint market", source: "TCGplayer", asOf: now)
        let ask = try XCTUnwrap(CardShareAsk(text: "55", market: 64.2, locale: locale))
        let text = CardShareSummary.text(identity: identity, price: price, ask: ask, now: now, calendar: calendar, locale: locale)
        XCTAssertEqual(text, """
        Voltfin ex · Stormfront Tides STF 087/165 · Reverse
        $64.20 Near Mint market (TCGplayer, Oct 31)
        Asking $55.00 · 14% under market
        """)
    }

    func testOwnedFinishIsStatedEvenWhenStandardAndCanBeRemoved() {
        let identity = CardShareIdentity(name: "Sorceress's Schemes", setCode: "FIN", setName: "Final Fantasy",
            number: CardShareNumber("159"), badge: .grade("PSA 10"), finish: "Foil")
        XCTAssertEqual(identity.replacingFinish("Nonfoil").finish, "Nonfoil")
        XCTAssertEqual(identity.replacingFinish("Nonfoil").gradeBadge, .grade("PSA 10"), "A grade describes the slab, not the finish")
        XCTAssertNil(identity.replacingFinish(nil).finish)
        XCTAssertNil(identity.replacingFinish(nil).printingDetail)
        XCTAssertEqual(CardShareSummary.text(identity: identity.replacingFinish("Nonfoil"), price: nil, now: now, calendar: calendar, locale: locale),
            "Sorceress's Schemes · Final Fantasy FIN 159 · PSA 10 · Nonfoil")
    }

    func testShareOptionNamesSlabsByGradeAndFinish() {
        let identity = CardShareIdentity(name: "Charizard", setCode: "BS", setName: "Base Set",
            number: CardShareNumber("4/102"), badge: .grade("PSA 10"), finish: "Holo")
        let slab = CollectionShareOption(id: "slab", identity: identity, finishLabel: "Holo", price: nil,
            showsFinishSheen: false, localArtworkFilename: nil, remoteArtworkURLs: [])
        XCTAssertTrue(slab.isGraded)
        XCTAssertEqual(slab.choiceLabel, "PSA 10 · Holo")
        XCTAssertNil(slab.identity.finish, "The sheet decides whether the finish is stated")
        XCTAssertEqual(slab.identity.gradeBadge, .grade("PSA 10"))

        let raw = CollectionShareOption(id: "raw", identity: identity.replacingFinish(nil).replacingFinish("Holo"),
            finishLabel: " ", price: nil, showsFinishSheen: false, localArtworkFilename: nil, remoteArtworkURLs: [],
            isGraded: false)
        XCTAssertFalse(raw.isGraded)
        XCTAssertNil(raw.finishLabel)
    }

    func testSummaryOfAllFinishesListsEachFinishAndItsPrice() {
        let identity = CardShareIdentity(name: "Sorceress's Schemes", setCode: "FIN", setName: "Final Fantasy",
            number: CardShareNumber("159"), badge: nil, finish: "Foil")
        let price = { (amount: Double) in
            CardSharePrice(amount: amount, currencyCode: "USD", basis: "Market price", source: "Scryfall", asOf: self.now)
        }
        let priced = [
            CardShareFinishLine(id: "a", label: "Nonfoil", price: price(0.25)),
            CardShareFinishLine(id: "b", label: "Foil", price: price(0.9)),
            CardShareFinishLine(id: "c", label: "Etched Foil", price: nil)
        ]
        XCTAssertEqual(CardShareSummary.text(identity: identity, price: nil, finishes: priced,
            now: now, calendar: calendar, locale: locale), """
        Sorceress's Schemes · Final Fantasy FIN 159
        Nonfoil · $0.25
        Foil · $0.90
        Etched Foil · No price
        Market price (Scryfall, Oct 31)
        """)

        let unpriced = priced.map { CardShareFinishLine(id: $0.id, label: $0.label, price: nil) }
        XCTAssertEqual(CardShareSummary.text(identity: identity, price: nil, finishes: unpriced,
            now: now, calendar: calendar, locale: locale), """
        Sorceress's Schemes · Final Fantasy FIN 159
        Finishes: Nonfoil · Foil · Etched Foil
        """)
    }

    func testSummaryWithoutPriceStatesOnlyIdentity() {
        let identity = CardShareIdentity(name: "Booster Bundle", setCode: nil, setName: "Stormfront Tides", number: nil, badge: nil)
        XCTAssertEqual(CardShareSummary.text(identity: identity, price: nil, now: now, calendar: calendar, locale: locale),
                       "Booster Bundle · Stormfront Tides")
    }

    // MARK: - Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// (days before `now`, price)
    private func points(_ values: [(Double, Double)]) -> [JustTCGHistoryPoint] {
        values.map { JustTCGHistoryPoint(p: $0.1, t: now.addingTimeInterval(-$0.0 * 86_400).timeIntervalSince1970) }
    }
}

@MainActor
final class CardShareRenderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_448_000)

    func testBothImagesWithoutArtworkExportTheirIdentityAndPrice() throws {
        try checkExport(CollectionShareImage(identity: identity, price: price, artwork: nil,
            showsFinishSheen: true, now: now), name: "collection-without-artwork")
        try checkExport(BuyCheckShareImage(identity: identity, price: price, ask: nil, trend: nil,
            artwork: nil, now: now), name: "buy-without-artwork")
    }

    func testMissingSourcesFinishWithoutBlockingFactOnlyExport() async throws {
        let state = CardShareArtworkState()
        await state.load(localFilename: nil, remoteURLs: [])
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.artwork)
        XCTAssertEqual(state.revision, 1)
        try checkExport(CollectionShareImage(identity: identity, price: nil, artwork: state.artwork,
            showsFinishSheen: false, now: now), name: "manual-entry-without-artwork")
    }

    func testSlowLoadFailureAndRetryKeepBothSharesExportable() async throws {
        let state = CardShareArtworkState()
        let started = expectation(description: "Artwork load started")
        var completion: CheckedContinuation<CardShareArtwork?, Never>?
        let task = Task { @MainActor in
            await state.load(localFilename: nil, remoteURLs: []) { _, _ in
                await withCheckedContinuation { continuation in
                    completion = continuation
                    started.fulfill()
                }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(state.isLoading)
        let loading = try checkExport(CollectionShareImage(identity: identity, price: price,
            artwork: state.artwork, showsFinishSheen: true, now: now), name: "share-during-slow-load")
        completion?.resume(returning: nil)
        await task.value
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.artwork)
        try checkExport(BuyCheckShareImage(identity: identity, price: price, ask: nil, trend: nil,
            artwork: state.artwork, now: now), name: "share-after-load-failure")

        let recovered = artwork()
        await state.load(localFilename: nil, remoteURLs: []) { _, _ in recovered }
        XCTAssertTrue(state.artwork?.image === recovered.image)
        XCTAssertEqual(state.revision, 2)
        let retried = try checkExport(CollectionShareImage(identity: identity, price: price,
            artwork: state.artwork, showsFinishSheen: true, now: now), name: "share-after-retry")
        XCTAssertNotEqual(loading.pngData(), retried.pngData())
    }

    func testLateArtworkAttemptCannotOverwriteSuccessfulRetry() async throws {
        let state = CardShareArtworkState()
        let started = expectation(description: "Old artwork request started")
        var completion: CheckedContinuation<CardShareArtwork?, Never>?
        let oldTask = Task { @MainActor in
            await state.load(localFilename: nil, remoteURLs: []) { _, _ in
                await withCheckedContinuation { continuation in
                    completion = continuation
                    started.fulfill()
                }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        let current = artwork()
        await state.load(localFilename: nil, remoteURLs: []) { _, _ in current }
        completion?.resume(returning: artwork())
        await oldTask.value
        XCTAssertTrue(state.artwork?.image === current.image)
        XCTAssertFalse(state.isLoading)
        XCTAssertEqual(state.revision, 1)
    }

    func testPersonalPhotoBoundsAndCornerRadiusHandleExtremeShapes() {
        XCTAssertEqual(CardShareArtworkLayout.aspect(for: artwork(size: CGSize(width: 200, height: 300), kind: .userPhoto)), 2 / 3, accuracy: 0.001)
        XCTAssertEqual(CardShareArtworkLayout.aspect(for: artwork(size: CGSize(width: 360, height: 120), kind: .userPhoto)), 3)
        XCTAssertEqual(CardShareArtworkLayout.aspect(for: artwork(size: CGSize(width: 20, height: 400), kind: .userPhoto)), 1 / 3, accuracy: 0.001)
        XCTAssertEqual(CardShareArtworkLayout.aspect(for: artwork(size: CGSize(width: 400, height: 20), kind: .userPhoto)), 3)
        XCTAssertEqual(CardShareArtworkLayout.aspect(for: artwork(size: CGSize(width: 400, height: 20), kind: .catalog)), 20)
        XCTAssertLessThanOrEqual(CardShareArtworkLayout.cornerRadius(for: CGSize(width: 100, height: 20), kind: .userPhoto), 2)
    }

    func testCollectionExportsAtSocialImageResolutionAcrossVariants() throws {
        let cases: [(String, CardShareIdentity.Badge?, Bool, Bool)] = [
            ("normal", nil, false, true),
            ("holo", .finish("Holo"), true, true),
            ("reverse", .finish("Reverse"), true, true),
            ("foil", .finish("Foil"), true, true),
            ("graded", .grade("PSA 10"), false, true),
            ("sealed", nil, false, false),
            ("no-price", nil, false, true),
            ("long-name", .finish("Reverse"), true, true)
        ]
        for (name, badge, sheen, isCard) in cases {
            let identity = CardShareIdentity(
                name: name == "long-name" ? "A Very Long Legendary Trading Card Name With Extra Words" : (isCard ? "Share test card" : "Booster Bundle"),
                setCode: isCard ? "TST" : nil,
                setName: name == "long-name" ? "A Very Long Set Name With Extra Words" : "Test Set",
                number: isCard ? CardShareNumber("087/165") : nil,
                badge: badge
            )
            let scenarioPrice = CardSharePrice(amount: price.amount, currencyCode: price.currencyCode,
                basis: name == "graded" ? "PSA 10 market" : (isCard ? price.basis : "Market price"),
                source: name == "graded" ? "JustTCG" : price.source, asOf: now)
            let content = CollectionShareImage(identity: identity, price: name == "no-price" ? nil : scenarioPrice,
                artwork: artwork(), showsFinishSheen: sheen, now: now)
            try checkExport(content, name: "collection-" + name)
        }
    }

    func testCollectionExportsEveryOwnedFinishWithAndWithoutPrices() throws {
        let labels = ["Normal", "Holo", "Reverse Holo", "Poké Ball", "Master Ball", "Cosmos Holo"]
        let lines = labels.enumerated().map { index, label in
            CardShareFinishLine(id: label, label: label, price: CardSharePrice(amount: Double(index + 1) * 1.5,
                currencyCode: "USD", basis: "Near Mint market", source: "TCGplayer", asOf: now))
        }
        let accent = ArtworkAccent(red: 0.85, green: 0.35, blue: 0.25)
        try checkExport(CollectionShareImage(identity: identity, price: nil, artwork: artwork(),
            showsFinishSheen: false, finishes: Array(lines.prefix(3)), accent: accent, now: now), name: "collection-finishes-priced")
        try checkExport(CollectionShareImage(identity: identity, price: nil, artwork: artwork(),
            showsFinishSheen: false, finishes: lines, accent: accent, now: now), name: "collection-finishes-overflow")
        try checkExport(CollectionShareImage(identity: identity, price: nil, artwork: artwork(),
            showsFinishSheen: false, finishes: lines.prefix(3).map { CardShareFinishLine(id: $0.id, label: $0.label, price: nil) },
            accent: accent, now: now), name: "collection-finishes-unpriced")
        try checkExport(CollectionShareImage(identity: identity.replacingFinish("Normal"), price: price, artwork: artwork(),
            showsFinishSheen: false, accent: accent, now: now), name: "collection-standard-finish-stated")
    }

    func testExtremeIdentitiesStayInsideTheCanvas() throws {
        let longName = "Mr. Mime's Extraordinarily Long Tournament Champion ex"
        let longSet = "Scarlet & Violet—Prismatic Evolutions Elite Trainer Box Promos"
        let rarity = CardShareRarity(raw: "Special Illustration Rare", game: .pokemon, pokemonSetID: "sv08.5")
        let slab = CardShareIdentity(name: longName, setCode: "PRE", setName: longSet, number: CardShareNumber("TG30/TG30"),
            badge: .grade("CGC 9.5 Pristine"), rarity: rarity, finish: "Master Ball Reverse Holo", edition: "1st Edition")
        let raw = slab.replacingFinish("Master Ball Reverse Holo")
        let unrated = CardShareIdentity(name: longName, setCode: "PRE", setName: longSet,
            number: CardShareNumber("TG30/TG30"), badge: nil, rarity: rarity, finish: "Master Ball Reverse Holo")
        let bigPrice = CardSharePrice(amount: 12_345.67, currencyCode: "USD", basis: "CGC 9.5 Pristine market",
            source: "JustTCG", asOf: now)
        for (name, art) in [("art", artwork()), ("no-art", nil)] as [(String, CardShareArtwork?)] {
            try checkExport(CollectionShareImage(identity: slab, price: bigPrice, artwork: art,
                showsFinishSheen: false, now: now), name: "edge-slab-\(name)")
            try checkExport(CollectionShareImage(identity: unrated, price: bigPrice, artwork: art,
                showsFinishSheen: true, now: now), name: "edge-raw-\(name)")
            let lines = ["Normal", "Master Ball Reverse Holo", "Poké Ball Reverse Holo", "Cosmos Holo"].enumerated().map {
                CardShareFinishLine(id: $0.element, label: $0.element, price: $0.offset == 2 ? nil
                    : CardSharePrice(amount: 9_876.54 / Double($0.offset + 1), currencyCode: "USD",
                        basis: "Near Mint market", source: "TCGplayer", asOf: now))
            }
            try checkExport(CollectionShareImage(identity: raw, price: nil, artwork: art, showsFinishSheen: false,
                finishes: lines, now: now), name: "edge-all-finishes-\(name)")
            try checkExport(CollectionShareImage(identity: raw, price: nil, artwork: art, showsFinishSheen: false,
                finishes: lines.map { CardShareFinishLine(id: $0.id, label: $0.label, price: nil) }, now: now),
                name: "edge-all-finishes-unpriced-\(name)")
            try checkExport(BuyCheckShareImage(identity: slab, price: bigPrice,
                ask: CardShareAsk(text: "11000", market: bigPrice.amount, locale: Locale(identifier: "en_US")),
                trend: nil, artwork: art, now: now), name: "edge-buy-\(name)")
        }
        let points = [(89.0, 9_000.0), (70, 9_400), (50, 10_100), (30, 11_800), (0, 12_345.67)].map {
            JustTCGHistoryPoint(p: $0.1, t: now.addingTimeInterval(-$0.0 * 86_400).timeIntervalSince1970)
        }
        try checkExport(BuyCheckShareImage(identity: unrated, price: bigPrice, ask: nil,
            trend: CardShareTrend.make(points: points, now: now), artwork: artwork(), now: now), name: "edge-buy-history")
        let short = CardShareIdentity(name: "Mew", setCode: nil, setName: nil, number: nil, badge: nil)
        try checkExport(CollectionShareImage(identity: short, price: nil, artwork: nil, showsFinishSheen: false, now: now),
            name: "edge-minimal")
    }

    func testBuyCheckExportsHistoryAndAskingPricesOutsideHistoryRange() throws {
        let points = [(89.0, 57.32), (70, 56.4), (50, 59), (30, 61.2), (0, 64.2)].map {
            JustTCGHistoryPoint(p: $0.1, t: now.addingTimeInterval(-$0.0 * 86_400).timeIntervalSince1970)
        }
        let trend = try XCTUnwrap(CardShareTrend.make(points: points, now: now))
        for amount in ["", "20", "64.20", "100"] {
            let content = BuyCheckShareImage(identity: identity, price: price,
                ask: CardShareAsk(text: amount, market: price.amount, locale: Locale(identifier: "en_US")),
                trend: trend, artwork: artwork(), now: now)
            try checkExport(content, name: "buy-history-" + (amount.isEmpty ? "no-ask" : amount))
        }
        try checkExport(BuyCheckShareImage(identity: identity, price: price, ask: nil,
            trend: nil, artwork: artwork(), now: now), name: "buy-no-history")
    }

    func testUserPhotoExportsIncludeOrdinaryAndExtremeAspectRatios() throws {
        for size in [CGSize(width: 120, height: 360), CGSize(width: 360, height: 120),
                     CGSize(width: 20, height: 400), CGSize(width: 400, height: 20)] {
            let photo = artwork(size: size, kind: .userPhoto)
            try checkExport(CollectionShareImage(identity: identity, price: nil,
                artwork: photo, showsFinishSheen: true, now: now), name: "user-photo-\(Int(size.width))-\(Int(size.height))")
        }
    }

    private var identity: CardShareIdentity {
        CardShareIdentity(name: "Share test card", setCode: "TST", setName: "Test Set",
            number: CardShareNumber("087/165"), badge: .finish("Reverse"))
    }

    private var price: CardSharePrice {
        CardSharePrice(amount: 64.2, currencyCode: "USD", basis: "Near Mint market", source: "TCGplayer", asOf: now)
    }

    private func artwork(size: CGSize = CGSize(width: 215, height: 300), kind: CardShareArtwork.Kind = .catalog) -> CardShareArtwork {
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.systemMint.setFill()
            context.fill(CGRect(x: 8, y: 8, width: size.width - 16, height: size.height - 16))
            ("TEST ART" as NSString).draw(at: CGPoint(x: 15, y: 25),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 18), .foregroundColor: UIColor.black])
        }
        return CardShareArtwork(image: image, kind: kind)
    }

    @discardableResult
    private func checkExport<Content: View>(_ content: Content, name: String) throws -> UIImage {
        let image = try XCTUnwrap(CardShareRenderer.render(content))
        XCTAssertEqual(image.cgImage?.width, 1080, name)
        XCTAssertEqual(image.cgImage?.height, 1920, name)
        // Set TEST_RUNNER_SHARE_EXPORT_DIR to inspect every export as a PNG.
        if let directory = ProcessInfo.processInfo.environment["SHARE_EXPORT_DIR"], let data = image.pngData() {
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return image
    }
}
