import XCTest
import SwiftData
@testable import TradingCardScanner

/// Identity resolution has to keep being attempted for exactly the cards that
/// have not got any, which is the case these tests protect.
@MainActor
final class CatalogNormalizationTests: XCTestCase {
    /// Held for the lifetime of the test. A `ModelContext` does not keep its
    /// container alive, and letting the container deallocate takes the store out
    /// from under the context mid-test.
    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CollectedCard.self, PriceRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container.mainContext
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func importedCard(
        setName: String,
        cardNumber: String,
        name: String
    ) -> CollectedCard {
        CollectedCard(
            collectionKey: "csv:\(setName)|\(cardNumber)#normal",
            game: .pokemon,
            providerID: "csv:\(setName)|\(cardNumber)",
            name: name,
            setName: setName,
            setCode: setName,
            cardNumber: cardNumber,
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .normal,
            variantResolution: .imported
        )
    }

    // MARK: - Japanese-exclusive sets

    /// The English edition does not carry these sets under any name, so they are
    /// routed to `ja` by an explicit map. Live call: it is the mapping against
    /// the real catalogue that is worth protecting, not a stubbed copy of it.
    func testJapaneseExclusiveSetResolvesAgainstTheJapaneseEdition() async throws {
        let context = try makeContext()
        let card = importedCard(setName: "Inferno X", cardNumber: "001/080", name: "Oddish")
        context.insert(card)
        try context.save()

        await CollectionCatalogNormalizer().normalizeImportedCards(in: context)

        XCTAssertEqual(card.catalogProviderID, "M2-001")
        XCTAssertEqual(card.setCode, "M2")
    }

    func testJapaneseSetNamesMapToTheirCatalogueIDs() {
        let expected = [
            "Inferno X": "M2",
            "Terastal Festival ex": "SV8a",
            "Mega Brave": "M1L",
            "Mega Symphonia": "M1S",
            "MEGA Dream ex": "M2a",
            "Ruler of the Black Flame": "SV3",
            "Paradigm Trigger": "S12",
            "Night Wanderer": "SV6a",
            "Stellar Miracle": "SV7",
            "Wild Force": "SV5K",
            "Future Flash": "SV4M"
        ]

        for (name, id) in expected {
            XCTAssertEqual(
                CatalogIdentityNormalization.japaneseSetID(forImportedName: name),
                id,
                "\(name) should route to \(id)"
            )
        }
    }

    /// Resolving identity is only half the job: the resolved id then has to be
    /// fetched from the edition it actually exists in.
    func testJapaneseCardIDsAreFetchedFromTheJapaneseEdition() {
        XCTAssertEqual(CatalogIdentityNormalization.locale(forCatalogCardID: "M2-001"), .ja)
        XCTAssertEqual(CatalogIdentityNormalization.locale(forCatalogCardID: "SV8a-014"), .ja)
        XCTAssertEqual(CatalogIdentityNormalization.locale(forCatalogCardID: "sv08.5-001"), .en)
        XCTAssertEqual(CatalogIdentityNormalization.locale(forCatalogCardID: "mep-008"), .en)
        XCTAssertEqual(CatalogIdentityNormalization.locale(forCatalogCardID: "nodashes"), .en)
    }

    /// Fetched from the right edition, a Japanese-exclusive printing is a real
    /// card with a real Cardmarket price. Fetched from the English one it is a
    /// 404, which is how these cards spent their whole life reported as
    /// unreachable.
    ///
    /// The price arrives in euros: these are not TCGplayer products, so there is
    /// no dollar figure to be had, and the currency travels with the number.
    func testJapaneseCardIsPriceableFromTheJapaneseEdition() async throws {
        let card = try await TCGdexService().fetchCard(id: "M2-001", locale: .ja)
        XCTAssertEqual(card.id, "M2-001")

        guard case let .price(price) = CardPricing.price(
            for: .pokemon(card, setCode: "M2"),
            variant: .normal
        ) else {
            return XCTFail("Expected a Cardmarket price")
        }

        XCTAssertEqual(price.source, .cardmarket)
        XCTAssertEqual(price.currencyCode, "EUR")
        XCTAssertGreaterThan(price.unitMarketPriceUSD, 0)
    }

    // MARK: - The starvation regression

    /// A card with no identity cannot be priced, so its price check fails. That
    /// failure must not be recorded as "identity was checked just now" — doing so
    /// made the normalizer skip the card as recently-seen, which left it without
    /// identity, which failed the next price check, forever.
    ///
    /// The field belongs to the normalizer. A failed price check must leave it
    /// exactly as it found it.
    func testFailedPriceCheckDoesNotClaimIdentityWasChecked() {
        let card = importedCard(setName: "Inferno X", cardNumber: "001/080", name: "Oddish")
        XCTAssertNil(card.catalogMetadataCheckedAt)

        let record = PriceRecord(
            key: "k",
            game: .pokemon,
            printingID: card.providerID,
            variantID: "normal"
        )
        record.recordFailure(at: .now)

        XCTAssertNotNil(record.lastFailureAt, "the failure belongs on the price record")
        XCTAssertNil(
            card.catalogMetadataCheckedAt,
            "a price failure must not stamp the normalizer's retry gate"
        )
    }

    /// A collection normalized by an older build must re-run when the resolver
    /// learns new rules, rather than waiting out the retry interval on a result
    /// that the current build would answer differently.
    func testRecentlyCheckedCardIsRetriedWhenTheResolverVersionMoves() async throws {
        let context = try makeContext()
        let card = importedCard(setName: "Inferno X", cardNumber: "002/080", name: "Gloom")
        // Exactly the state the starvation left behind: checked seconds ago, by
        // a build whose rules could not resolve this set.
        card.catalogMetadataCheckedAt = .now
        card.catalogMetadataVersion = 3
        context.insert(card)
        try context.save()

        await CollectionCatalogNormalizer().normalizeImportedCards(in: context)

        XCTAssertEqual(card.catalogProviderID, "M2-002")
        XCTAssertGreaterThan(card.catalogMetadataVersion, 3)
    }

    // MARK: - Definitive sealed misses

    func testDefinitiveSealedMissDoesNotRetryAfterEightHours() {
        let card = importedSealedProduct()
        card.catalogMetadataCheckedAt = Date(timeIntervalSince1970: 1)
        card.catalogMetadataVersion = -CollectionCatalogNormalizer.metadataVersion

        XCTAssertTrue(CollectionCatalogNormalizer.isDefinitiveSealedMiss(card))
        XCTAssertFalse(
            CollectionCatalogNormalizer.needsNormalization(
                card,
                now: Date(timeIntervalSince1970: 10 * 24 * 60 * 60)
            ),
            "a completed catalog miss must not consume one metered request every eight hours"
        )
        XCTAssertEqual(
            PricingDiagnostics.unpricedReason(for: card, record: nil),
            .sealedProductUnmatched
        )
    }

    func testTransientSealedResolutionFailureRemainsRetryable() {
        let card = importedSealedProduct()

        XCTAssertTrue(CollectionCatalogNormalizer.needsNormalization(card))
        XCTAssertEqual(
            PricingDiagnostics.unpricedReason(for: card, record: nil),
            .sealedProductPendingMatch
        )
    }

    func testTransientSealedFailureKeepsEightHourThrottle() {
        let card = importedSealedProduct()
        let checkedAt = Date(timeIntervalSince1970: 1_000)
        card.catalogMetadataCheckedAt = checkedAt
        card.catalogMetadataVersion = CollectionCatalogNormalizer.metadataVersion

        XCTAssertFalse(
            CollectionCatalogNormalizer.needsNormalization(
                card,
                now: checkedAt.addingTimeInterval(7 * 60 * 60)
            )
        )
        XCTAssertTrue(
            CollectionCatalogNormalizer.needsNormalization(
                card,
                now: checkedAt.addingTimeInterval(8 * 60 * 60)
            )
        )
    }

    func testResolverVersionUpgradeReopensDefinitiveSealedMiss() {
        let card = importedSealedProduct()
        card.catalogMetadataCheckedAt = .now
        card.catalogMetadataVersion = -(CollectionCatalogNormalizer.metadataVersion - 1)

        XCTAssertTrue(CollectionCatalogNormalizer.needsNormalization(card))
    }

    func testKnownSealedProductWithoutExactVariantReportsVariantPriceGap() {
        let card = importedSealedProduct()
        card.justTCGCardID = "product-uuid"

        XCTAssertEqual(
            PricingDiagnostics.unpricedReason(for: card, record: nil),
            .noExactVariantPrice
        )
    }

    private func importedSealedProduct() -> CollectedCard {
        let card = CollectedCard(
            collectionKey: "sealed:csv:Base Set|Booster Box",
            game: .pokemon,
            providerID: "csv:Base Set|Booster Box",
            name: "Booster Box",
            setName: "Base Set",
            setCode: "",
            cardNumber: "",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: nil,
            variantResolution: .imported
        )
        card.itemKindRaw = CollectionItemKind.sealedProduct.rawValue
        return card
    }
}
