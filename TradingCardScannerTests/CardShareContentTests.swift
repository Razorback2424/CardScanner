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
        XCTAssertEqual(image.cgImage?.height, 1350, name)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return image
    }
}
