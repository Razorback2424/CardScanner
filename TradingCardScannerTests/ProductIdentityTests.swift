import XCTest
import SwiftData
@testable import TradingCardScanner

@MainActor
final class ProductIdentityTests: XCTestCase {
    private var container: ModelContainer?

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CollectedCard.self, PriceRecord.self, ProductIdentity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container.mainContext
    }

    /// A vendor handle belongs to a printing *and* a finish. One handle per card
    /// would collapse the parallels the pricing layer exists to keep apart.
    func testKeyIsPerPrintingAndVariant() {
        let pokeBall = ProductIdentity.key(game: .pokemon, printingID: "sv08.5-001", variantID: "pokeBall")
        let masterBall = ProductIdentity.key(game: .pokemon, printingID: "sv08.5-001", variantID: "masterBall")

        XCTAssertNotEqual(pokeBall, masterBall)
    }

    func testMagicTreatmentGetsItsOwnPriceAndVendorIdentityKey() {
        let generic = ProductIdentity.key(
            game: .magic,
            printingID: "printing",
            variantID: PhysicalVariant.foil.id
        )
        let treated = ProductIdentity.key(
            game: .magic,
            printingID: "printing",
            variantID: PhysicalVariant.foil.id,
            treatmentIDs: ["SurgeFoil"]
        )

        XCTAssertEqual(generic, "magic:printing:foil")
        XCTAssertEqual(treated, "magic:printing:foil:treatment=surgefoil")
        XCTAssertNotEqual(generic, treated)
        XCTAssertEqual(
            PriceRecord.key(
                game: .magic,
                printingID: "printing",
                variantID: PhysicalVariant.foil.id,
                treatmentIDs: ["surgefoil"]
            ),
            treated
        )
    }

    func testMagicTreatmentMissDoesNotSuppressTheOrdinaryFoilIdentity() throws {
        let context = try makeContext()
        let store = ProductIdentityStore(context: context)
        let genericKey = ProductIdentity.key(
            game: .magic,
            printingID: "printing",
            variantID: PhysicalVariant.foil.id
        )
        let treatmentKey = ProductIdentity.key(
            game: .magic,
            printingID: "printing",
            variantID: PhysicalVariant.foil.id,
            treatmentIDs: ["surgefoil"]
        )

        store.record(
            .price(
                NormalizedPrice(
                    unitMarketPriceUSD: 6.40,
                    currencyCode: "USD",
                    source: .justTCG,
                    sourceVariantID: "vendor-foil",
                    sourceUpdatedAt: nil,
                    fetchedAt: .now
                ),
                vendorCardID: "generic-card",
                vendorVariantID: "vendor-foil"
            ),
            forKey: genericKey
        )
        store.record(
            .noProductMatch,
            forKey: treatmentKey,
            treatmentIDs: ["surgefoil"]
        )

        XCTAssertFalse(store.needsResolution(forKey: genericKey))
        XCTAssertEqual(store.cachedCardID(forKey: genericKey), "generic-card")
        XCTAssertEqual(store.cachedVariantID(forKey: genericKey), "vendor-foil")
        XCTAssertFalse(store.needsResolution(forKey: treatmentKey))
        XCTAssertNil(store.cachedCardID(forKey: treatmentKey))
        XCTAssertNil(store.cachedVariantID(forKey: treatmentKey))
        XCTAssertEqual(
            store.identity(forKey: treatmentKey)?.magicTreatmentIDsRaw,
            ["surgefoil"]
        )
    }

    func testUnknownTreatmentIdentityRoundTripsWithoutCreatingGenericAlias() throws {
        let context = try makeContext()
        let key = ProductIdentity.key(
            game: .magic,
            printingID: "printing",
            variantID: PhysicalVariant.foil.id,
            treatmentIDs: ["Future Foil"]
        )
        let identity = ProductIdentity(
            key: key,
            vendor: .justTCG,
            vendorCardID: "card",
            resolvedAt: .now,
            magicTreatmentIDs: ["Future Foil"]
        )
        context.insert(identity)
        try context.save()

        let stored = try XCTUnwrap(
            context.fetch(FetchDescriptor<ProductIdentity>()).first
        )
        XCTAssertEqual(stored.magicTreatmentIDsRaw, ["Future Foil"])
        XCTAssertEqual(
            stored.key,
            "magic:printing:foil:treatment=future%20foil"
        )
        XCTAssertEqual(
            ProductIdentity.key(
                game: .magic,
                printingID: "printing",
                variantID: PhysicalVariant.foil.id,
                treatmentIDs: stored.magicTreatmentIDsRaw
            ),
            stored.key
        )
    }

    func testResolvedRecordIsCurrent() {
        let identity = ProductIdentity(
            key: "k",
            vendor: .justTCG,
            vendorCardID: "some-card",
            vendorVariantID: "some-card_near-mint_holofoil",
            resolvedAt: .now
        )

        XCTAssertTrue(identity.isCurrent())
    }

    /// A miss is cached so the search does not repeat every refresh — the whole
    /// point of the record for cards the vendor does not carry.
    func testRecentMissIsTreatedAsCurrentSoTheSearchIsNotRepeated() {
        let identity = ProductIdentity(key: "k", vendor: .justTCG, unmatchedAt: .now)

        XCTAssertTrue(identity.isCurrent())
    }

    /// But a miss is not permanent. Vendors add products.
    func testOldMissIsRetried() {
        let identity = ProductIdentity(
            key: "k",
            vendor: .justTCG,
            unmatchedAt: Date.now.addingTimeInterval(-60 * 24 * 60 * 60)
        )

        XCTAssertFalse(identity.isCurrent())
    }

    /// Matcher revisions reopen stored misses, but a verified vendor handle is
    /// still valid and must stay batchable instead of paying for a new search.
    func testVersionBumpRetriesMissesWhileKeepingResolvedHandlesCurrent() {
        let resolved = ProductIdentity(
            key: "resolved",
            vendor: .justTCG,
            vendorCardID: "some-card",
            resolvedAt: .now,
            attemptVersion: ProductIdentity.currentAttemptVersion - 1
        )
        let missed = ProductIdentity(
            key: "missed",
            vendor: .justTCG,
            unmatchedAt: .now,
            attemptVersion: ProductIdentity.currentAttemptVersion - 1
        )

        XCTAssertTrue(resolved.isCurrent())
        XCTAssertFalse(missed.isCurrent())
    }

    func testStoredMissStillSuppressesTheBackgroundResolutionGate() throws {
        let context = try makeContext()
        let store = ProductIdentityStore(context: context)
        store.record(.noProductMatch, forKey: "missed")

        XCTAssertFalse(store.needsResolution(forKey: "missed"))
    }

    func testUnsupportedFinishDoesNotCreateANegativeIdentity() throws {
        let context = try makeContext()
        let store = ProductIdentityStore(context: context)
        store.record(.unsupportedFinish, forKey: "unsupported")

        XCTAssertNil(store.identity(forKey: "unsupported"))
        XCTAssertTrue(store.needsResolution(forKey: "unsupported"))
    }

    func testUnsupportedTreatmentDoesNotCreateANegativeIdentity() throws {
        let context = try makeContext()
        let store = ProductIdentityStore(context: context)
        store.record(
            .unsupportedTreatment,
            forKey: "magic:printing:foil:treatment=surgefoil",
            treatmentIDs: ["surgefoil"]
        )

        XCTAssertNil(store.identity(forKey: "magic:printing:foil:treatment=surgefoil"))
        XCTAssertTrue(store.needsResolution(forKey: "magic:printing:foil:treatment=surgefoil"))
    }

    func testRecordPersistsAndReadsBack() throws {
        let context = try makeContext()
        let key = ProductIdentity.key(game: .magic, printingID: "abc", variantID: "nonfoil")
        context.insert(ProductIdentity(key: key, vendor: .justTCG, vendorCardID: "v1", resolvedAt: .now))
        try context.save()

        let all = try context.fetch(FetchDescriptor<ProductIdentity>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.vendor, .justTCG)
        XCTAssertEqual(all.first?.vendorCardID, "v1")
    }

    // MARK: - Credentials

    /// The key is a billable secret. It must not be readable from anywhere the
    /// app writes plaintext, and the UI must be able to ask "is one set?"
    /// without reading the value back.
    func testCredentialRoundTripAndRemoval() throws {
        try PriceVendorCredentials.store("spike-test-value")
        XCTAssertTrue(PriceVendorCredentials.hasKey)
        XCTAssertEqual(PriceVendorCredentials.key, "spike-test-value")

        PriceVendorCredentials.remove()
        XCTAssertFalse(PriceVendorCredentials.hasKey)
        XCTAssertNil(PriceVendorCredentials.key)
    }

    /// Clearing the settings field means "forget this", not "save an empty key"
    /// — otherwise the app would believe it had credentials and fail every call.
    func testStoringBlankRemovesTheKey() throws {
        try PriceVendorCredentials.store("something")
        try PriceVendorCredentials.store("   ")

        XCTAssertFalse(PriceVendorCredentials.hasKey)
    }

    func testKeyIsNeverPersistedToUserDefaults() throws {
        try PriceVendorCredentials.store("secret-value")
        defer { PriceVendorCredentials.remove() }

        let defaults = UserDefaults.standard.dictionaryRepresentation()
        for (_, value) in defaults {
            if let string = value as? String {
                XCTAssertFalse(string.contains("secret-value"))
            }
        }
    }
}
