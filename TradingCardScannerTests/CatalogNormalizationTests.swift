import XCTest
import SwiftData
@testable import TradingCardScanner

private actor SealedNormalizationFixture: SealedBrowseProviding {
    var calls = 0
    let product: SealedProductSummary
    init(product: SealedProductSummary) { self.product = product }
    func sealedSets(game: CardGame) -> [SealedSetSummary] {
        calls += 1
        return [SealedSetSummary(id: "base", name: "Base Set", sealedCount: 1, game: game, releaseDate: nil)]
    }
    func searchSealedProducts(game: CardGame, setID: String?, query: String?, offset: Int) -> MarketCatalogPage<SealedProductSummary> {
        calls += 1
        return MarketCatalogPage(items: [product], total: 1, offset: 0, limit: 20, hasMore: false)
    }
}

private struct RecordedTCGdexSource: TCGdexCatalogSource {
    func fetchSetDirectory(locale: TCGdexLocale) async throws -> [CatalogSetReference] {
        []
    }

    func fetchSet(id: String, locale: TCGdexLocale) async throws -> TCGdexSetCatalog {
        guard id == "M2", locale == .ja else {
            throw TCGdexError.cardNotFound
        }
        return try JSONDecoder().decode(TCGdexSetCatalog.self, from: Self.setResponse)
    }

    func fetchCard(id: String, locale: TCGdexLocale) async throws -> TCGdexCard {
        guard id == "M2-001", locale == .ja else {
            throw TCGdexError.cardNotFound
        }
        return try JSONDecoder().decode(TCGdexCard.self, from: Self.cardResponse)
    }

    func fetchCard(
        setID: String,
        localID: String,
        locale: TCGdexLocale,
        ignoringCache: Bool
    ) async throws -> TCGdexCard {
        try await fetchCard(id: "\(setID)-\(localID)", locale: locale)
    }

    private static let setResponse = Data(
        """
        {
          "id": "M2",
          "name": "Inferno X",
          "cards": [
            {
              "id": "M2-001",
              "localId": "001",
              "name": "Oddish",
              "image": null
            },
            {
              "id": "M2-002",
              "localId": "002",
              "name": "Gloom",
              "image": "https://assets.example.test/m2-002"
            }
          ],
          "logo": null,
          "symbol": null,
          "releaseDate": null,
          "tcgOnline": null,
          "cardCount": {
            "total": 80,
            "official": 80
          }
        }
        """.utf8
    )

    private static let cardResponse = Data(
        """
        {
          "id": "M2-001",
          "localId": "001",
          "name": "Oddish",
          "image": "https://assets.tcgdex.net/en/swsh/m2/001",
          "rarity": "Common",
          "set": {
            "id": "M2",
            "name": "Inferno X",
            "cardCount": {
              "total": 80,
              "official": 80
            }
          },
          "variants": {
            "firstEdition": false,
            "holo": false,
            "normal": true,
            "reverse": false,
            "wPromo": false
          },
          "pricing": {
            "tcgplayer": null,
            "cardmarket": {
              "updated": "2026-01-01T00:00:00Z",
              "unit": "EUR",
              "avg30": 1.20,
              "avg7": 1.15,
              "trend": 1.25,
              "avg": 1.10
            }
          },
          "variants_detailed": null
        }
        """.utf8
    )
}

/// Identity resolution has to keep being attempted for exactly the cards that
/// have not got any, which is the case these tests protect.
@MainActor
final class CatalogNormalizationTests: XCTestCase {
    func testBrowseSealedNormalizationConvergesWithoutChangingOwnershipIdentity() async throws {
        let container = try ProductionRowFixtures.makeContainer()
        self.container = container
        let product = SealedProductSummary(id: "product", name: "Booster Box", setName: "Base Set",
            variantID: "sealed-variant", marketPriceUSD: 100, updatedAt: nil,
            imageURL: URL(string: "https://example.test/box.png"))
        let mutation = try CollectionStore(context: container.mainContext).addSealed(product, game: .pokemon)
        // Cover a row from the previous build as well as the ordinary add path.
        let row = try XCTUnwrap(CollectionStore(context: container.mainContext).card(forKey: mutation.collectionKey))
        row.catalogProviderID = nil
        try container.mainContext.save()
        let fixture = SealedNormalizationFixture(product: product)
        let normalizer = CollectionCatalogNormalizer(tcgdex: RecordedTCGdexSource(), justTCG: fixture,
            sealedCredentialsAvailable: true)
        await normalizer.normalizeImportedCards(in: container.mainContext)
        let first = try XCTUnwrap(CollectionStore(context: ModelContext(container)).card(forKey: mutation.collectionKey))
        XCTAssertEqual(first.catalogProviderID, "product")
        XCTAssertEqual(first.justTCGVariantID, "sealed-variant")
        XCTAssertEqual(first.quantity, 1)
        let calls = await fixture.calls
        await normalizer.normalizeImportedCards(in: container.mainContext)
        let after = await fixture.calls
        XCTAssertEqual(after, calls)
    }

    func testSealedNormalizationRepairsMissingArtworkAndRejectsConflictingVendorIdentity() async throws {
        for conflicting in [false, true] {
            let container = try ProductionRowFixtures.makeContainer()
            self.container = container
            let saved = SealedProductSummary(id: "product", name: "Booster Box", setName: "Base Set",
                variantID: "variant", marketPriceUSD: 100, updatedAt: nil, imageURL: nil)
            let mutation = try CollectionStore(context: container.mainContext).addSealed(saved, game: .pokemon)
            let found = SealedProductSummary(id: conflicting ? "other-product" : "product", name: saved.name,
                setName: saved.setName, variantID: conflicting ? "other-variant" : "variant",
                marketPriceUSD: 100, updatedAt: nil, imageURL: URL(string: "https://example.test/box.png"))
            let fixture = SealedNormalizationFixture(product: found)
            await CollectionCatalogNormalizer(tcgdex: RecordedTCGdexSource(), justTCG: fixture,
                sealedCredentialsAvailable: true).normalizeImportedCards(in: container.mainContext)
            let row = try XCTUnwrap(CollectionStore(context: ModelContext(container)).card(forKey: mutation.collectionKey))
            XCTAssertEqual(row.justTCGCardID, "product")
            XCTAssertEqual(row.justTCGVariantID, "variant")
            XCTAssertEqual(row.quantity, 1)
            XCTAssertEqual(row.imageURL, conflicting ? nil : found.imageURL?.absoluteString)
        }
    }

    /// Held for the lifetime of the test. A `ModelContext` does not keep its
    /// container alive, and letting the container deallocate takes the store out
    /// from under the context mid-test.
    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CollectedCard.self, PriceRecord.self, LocalArtworkOverride.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container.mainContext
    }

    private func persistedCard(
        withKey collectionKey: String,
        from context: ModelContext
    ) throws -> CollectedCard {
        let verificationContext = ModelContext(context.container)
        return try XCTUnwrap(
            try verificationContext.fetch(
                FetchDescriptor<CollectedCard>(
                    predicate: #Predicate { $0.collectionKey == collectionKey }
                )
            ).first
        )
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
    /// routed to the Japanese edition by an explicit map. The recorded source
    /// proves the normalizer asks that edition without relying on the live catalog.
    func testJapaneseExclusiveSetResolvesAgainstTheJapaneseEdition() async throws {
        let context = try makeContext()
        let card = importedCard(setName: "Inferno X", cardNumber: "001/080", name: "Oddish")
        context.insert(card)
        try context.save()

        await CollectionCatalogNormalizer(tcgdex: RecordedTCGdexSource())
            .normalizeImportedCards(in: context)

        let savedCard = try persistedCard(withKey: card.collectionKey, from: context)
        XCTAssertEqual(savedCard.catalogProviderID, "M2-001")
        XCTAssertEqual(savedCard.setCode, "M2")
        XCTAssertEqual(savedCard.imageURL, "https://assets.tcgdex.net/en/swsh/m2/001")
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

    /// Fetched from the right edition, a Japanese-exclusive printing resolves
    /// identity, but its Cardmarket EUR observation is not a canonical USD quote.
    func testJapaneseCardmarketPriceDoesNotBecomeCanonicalUSD() async throws {
        let card = try await RecordedTCGdexSource().fetchCard(id: "M2-001", locale: .ja)
        XCTAssertEqual(card.id, "M2-001")

        XCTAssertEqual(
            CardPricing.price(
            for: .pokemon(card, setCode: "M2"),
            variant: .normal,
            magicTreatments: []
            ),
            .unavailable(.tcgplayer)
        )
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

        await CollectionCatalogNormalizer(tcgdex: RecordedTCGdexSource())
            .normalizeImportedCards(in: context)

        let savedCard = try persistedCard(withKey: card.collectionKey, from: context)
        XCTAssertEqual(savedCard.catalogProviderID, "M2-002")
        XCTAssertGreaterThan(savedCard.catalogMetadataVersion, 3)
    }

    func testPreviouslyResolvedMissingArtworkRetriesAfterArtworkResolverVersionMoves() {
        let card = importedCard(setName: "Inferno X", cardNumber: "001/080", name: "Oddish")
        card.catalogProviderID = "M2-001"
        card.catalogMetadataCheckedAt = .now
        card.catalogMetadataVersion = CollectionCatalogNormalizer.metadataVersion - 1

        XCTAssertTrue(CollectionCatalogNormalizer.needsNormalization(card))
    }

    func testSavedScrydexArtworkKeepsItsCompleteExtensionlessURL() {
        let card = importedCard(setName: "30th Classic Collection", cardNumber: "003", name: "Metagross")
        card.imageURL = "https://images.scrydex.com/pokemon/me55c-003/large"
        card.thumbnailURL = nil

        XCTAssertEqual(card.highImageURL?.absoluteString, card.imageURL)
        XCTAssertEqual(card.lowImageURL?.absoluteString, card.imageURL)

        card.imageURL = "https://assets.tcgdex.net/en/me/me55c/003"
        XCTAssertEqual(card.highImageURL?.absoluteString, card.imageURL! + "/high.png")
        XCTAssertEqual(card.lowImageURL?.absoluteString, card.imageURL! + "/low.png")
    }

    func testClassicCollectionArtworkRepairsSavedGridAndDetailURLsWithoutProviderDirectory() async throws {
        let artwork = CatalogCardArtwork(
            localID: "003",
            thumbnailURL: "https://images.scrydex.com/pokemon/me55c-003/small",
            imageURL: "https://images.scrydex.com/pokemon/me55c-003/large"
        )
        let descriptor = PokemonCatalogSetDescriptor(
            providerSetID: "30th-c", displayName: "30th Celebration Classic Collection",
            releaseDate: nil, releaseOrder: 23, recognitionKind: .notScannable,
            printedCode: "30C", officialCount: nil, printedPrefix: nil,
            catalogLocalIDPrefix: nil, localIDPadWidth: nil, scanEnabled: false,
            logoURL: nil, symbolURL: nil, cardArtwork: [artwork]
        )
        let registry = PokemonCatalogRegistry(release: PokemonCatalogRelease(
            schemaVersion: PokemonCatalogRelease.currentSchemaVersion,
            revision: 1, generatedAt: .now, sets: [descriptor]
        ))
        let context = try makeContext()
        let card = CollectedCard(
            collectionKey: "30th-c-003#holo", game: .pokemon, providerID: "30th-c-003",
            name: "Metagross", setName: "30th Classic Collection", setCode: "30TH-C",
            cardNumber: "003", rarity: nil, imageURL: nil, thumbnailURL: nil,
            variant: .holo, variantResolution: .imported
        )
        card.catalogProviderID = card.providerID
        card.catalogMetadataCheckedAt = .now
        card.catalogMetadataVersion = CollectionCatalogNormalizer.metadataVersion - 1
        context.insert(card)
        try context.save()

        // This source has no English directory: signed artwork must work offline
        // and despite the saved set name differing from Browse's display name.
        await CollectionCatalogNormalizer(
            tcgdex: RecordedTCGdexSource(), pokemonRegistry: { registry }
        ).normalizeImportedCards(in: context)

        let saved = try persistedCard(withKey: card.collectionKey, from: context)
        XCTAssertEqual(saved.highImageURL?.absoluteString, artwork.imageURL)
        XCTAssertEqual(saved.lowImageURL?.absoluteString, artwork.thumbnailURL)
        XCTAssertEqual(saved.setCode, "30TH-C")
        XCTAssertEqual(saved.variant, .holo)
        XCTAssertFalse(CollectionCatalogNormalizer.needsNormalization(saved))
        let projection = await CollectionProjectionActor.makeBackground(modelContainer: context.container)
        let snapshot = await projection.snapshot()
        let row = try XCTUnwrap(snapshot.rowsByCollectionKey[card.collectionKey])
        XCTAssertEqual(row.highImageURL, saved.highImageURL)
        XCTAssertEqual(row.lowImageURL, saved.lowImageURL)
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

    // MARK: - Rows imported with a real provider id

    /// A CSV that carries a real `provider_id` keeps that id verbatim; only a
    /// row without one is given a synthetic `csv:` identity. Gating
    /// normalization on the `csv:` prefix therefore excluded exactly the rows
    /// that arrive with catalog identity and rarity unset, and left them that
    /// way permanently.
    private func importedCardWithRealProviderID() -> CollectedCard {
        CollectedCard(
            collectionKey: "magic:6c45a5df-048e-4b73-89c6-5cdaa330319e#foil",
            game: .magic,
            providerID: "6c45a5df-048e-4b73-89c6-5cdaa330319e",
            name: "Prison Break",
            setName: "Marvel's Spider-Man",
            setCode: "spm",
            cardNumber: "61",
            rarity: nil,
            imageURL: "https://cards.scryfall.io/normal/front/6/c/6c45a5df.jpg",
            thumbnailURL: "https://cards.scryfall.io/small/front/6/c/6c45a5df.jpg",
            variant: .foil,
            variantResolution: .imported
        )
    }

    func testRowImportedWithRealProviderIDStillNormalizes() {
        let card = importedCardWithRealProviderID()

        XCTAssertTrue(
            CollectionCatalogNormalizer.needsNormalization(card),
            "a row imported with a real provider id has no catalog identity and no rarity, so it must still be repairable"
        )
    }

    func testMissingRarityAloneDoesNotKeepExactCatalogRowEligible() {
        let card = importedCardWithRealProviderID()
        card.catalogProviderID = "6c45a5df-048e-4b73-89c6-5cdaa330319e"

        XCTAssertFalse(
            CollectionCatalogNormalizer.needsNormalization(card),
            "the current Pokémon resolver cannot supply rarity, so an exact row must not retry for it"
        )
    }

    func testNormalizerFillsMissingMetadataWithoutReplacingKnownIdentityFields() {
        let card = importedCardWithRealProviderID()
        card.catalogProviderID = card.providerID
        card.setCode = "SPM"
        card.setReleaseOrder = 42
        card.imageURL = "https://images.example.test/exact-card.png"

        card.applyCatalogMetadata(
            ImportedCatalogMetadata(
                providerID: card.providerID,
                setCode: "OTHER",
                rarity: "Rare",
                imageURL: "https://images.example.test/other-card.png",
                thumbnailURL: "https://images.example.test/other-card-small.png",
                tcgplayerURL: "https://shop.example.test/card",
                setReleaseOrder: 99
            ),
            fillMissingOnly: true
        )

        XCTAssertEqual(card.catalogProviderID, card.providerID)
        XCTAssertEqual(card.setCode, "SPM")
        XCTAssertEqual(card.setReleaseOrder, 42)
        XCTAssertEqual(card.imageURL, "https://images.example.test/exact-card.png")
        XCTAssertEqual(card.rarity, "Rare")
        XCTAssertEqual(
            card.thumbnailURL,
            "https://cards.scryfall.io/small/front/6/c/6c45a5df.jpg",
            "normalization must not replace artwork already attached to the exact printing"
        )
        XCTAssertEqual(card.tcgplayerURL, "https://shop.example.test/card")
    }

    func testExactProviderRowNormalizationFillsArtworkButKeepsKnownIdentityAndMissingRarityQuiet() async throws {
        let context = try makeContext()
        let card = CollectedCard(
            collectionKey: "M2-001#normal",
            game: .pokemon,
            providerID: "M2-001",
            name: "Oddish",
            setName: "Inferno X",
            setCode: "SPM",
            cardNumber: "001/080",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: "https://images.example.test/exact-small.png",
            variant: .normal,
            variantResolution: .uniqueInCatalog,
            setReleaseOrder: 42
        )
        card.catalogProviderID = card.providerID
        context.insert(card)
        try context.save()

        await CollectionCatalogNormalizer(tcgdex: RecordedTCGdexSource())
            .normalizeImportedCards(in: context)

        let savedCard = try persistedCard(withKey: card.collectionKey, from: context)
        XCTAssertEqual(savedCard.catalogProviderID, "M2-001")
        XCTAssertEqual(savedCard.setCode, "SPM")
        XCTAssertEqual(savedCard.setReleaseOrder, 42)
        XCTAssertEqual(savedCard.imageURL, "https://assets.tcgdex.net/en/swsh/m2/001")
        XCTAssertEqual(savedCard.thumbnailURL, "https://images.example.test/exact-small.png")
        XCTAssertNil(savedCard.rarity)
        XCTAssertFalse(
            CollectionCatalogNormalizer.needsNormalization(savedCard),
            "an exact printing without a Pokémon rarity must not cycle through normalization"
        )
    }

    func testFullyResolvedRowIsNotACandidate() {
        let card = importedCardWithRealProviderID()
        card.catalogProviderID = "6c45a5df-048e-4b73-89c6-5cdaa330319e"
        card.rarity = "uncommon"

        XCTAssertFalse(
            CollectionCatalogNormalizer.needsNormalization(card),
            "a row with catalog identity, artwork and rarity has nothing left to repair"
        )
    }

    /// Sealed product is not a printing and carries no rarity by construction,
    /// so the rarity clause must never make it a permanent candidate.
    func testResolvedSealedProductIsNotHeldOpenByMissingRarity() {
        let card = importedSealedProduct()
        card.catalogProviderID = "product-uuid"
        card.imageURL = "https://example.invalid/product.png"
        card.justTCGCardID = "product-uuid"
        card.catalogMetadataCheckedAt = .now
        card.catalogMetadataVersion = CollectionCatalogNormalizer.metadataVersion

        XCTAssertNil(card.rarity)
        XCTAssertFalse(
            CollectionCatalogNormalizer.needsNormalization(card),
            "sealed product has no rarity to find, so a resolved row must go quiet"
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
