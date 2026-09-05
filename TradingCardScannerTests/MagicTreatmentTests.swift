import Foundation
import SwiftData
import XCTest
@testable import TradingCardScanner

private actor MagicTreatmentBatchRecorder {
    private var values: [[String]] = []

    func record(_ batch: [String]) {
        values.append(batch)
    }

    func batches() -> [[String]] {
        values
    }
}

private actor MagicTreatmentMigrationGate {
    private var hasStarted = false
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?

    func markStarted() {
        hasStarted = true
    }

    func started() -> Bool {
        hasStarted
    }

    func waitUntilOpen() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiter = continuation
        }
    }

    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }
}

private actor MagicTreatmentMigrationRunCounter {
    private var count = 0

    func increment() -> Int {
        count += 1
        return count
    }

    func value() -> Int {
        count
    }
}

final class MagicTreatmentTests: XCTestCase {
    func testScryfallCollectionIdentifierEncodesExactID() throws {
        let id = "cb82d614-13d8-40ec-9213-8e6852d37c9c"
        let data = try JSONEncoder().encode(ScryfallCardIdentifier(id: id))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["id"] as? String, id)
        XCTAssertNil(object["set"])
        XCTAssertNil(object["collector_number"])
        XCTAssertNil(object["name"])
    }

    func testTreatmentsHaveStableIDsAndRemainSeparateFromFoil() throws {
        XCTAssertEqual(MagicTreatment.surgeFoil.id, "surgefoil")
        XCTAssertEqual(MagicTreatment.surgeFoil.label, "Surge Foil")
        XCTAssertEqual(MagicTreatment.surgeFoil.requiredFinish, .foil)

        let neonInk = MagicTreatment.neonInk
        XCTAssertEqual(neonInk.id, "neonink")
        XCTAssertEqual(neonInk.label, "Neon Ink")
        XCTAssertEqual(neonInk.requiredFinish, .foil)
        XCTAssertEqual(MagicTreatment(id: "NEONINK"), neonInk)

        let future = try XCTUnwrap(MagicTreatment(id: "RainbowFoil"))
        XCTAssertEqual(future, .unclassified("RainbowFoil"))
        XCTAssertEqual(future.id, "rainbowfoil")
        XCTAssertEqual(future.label, "Unclassified · RainbowFoil")
        XCTAssertNil(future.requiredFinish)
        XCTAssertEqual(
            try JSONDecoder().decode(
                MagicTreatment.self,
                from: JSONEncoder().encode(future)
            ),
            future
        )
    }

    func testUnclassifiedTreatmentsCompareAndHashByNormalizedID() throws {
        let uppercase = try XCTUnwrap(MagicTreatment(id: "FutureFoil"))
        let lowercase = try XCTUnwrap(MagicTreatment(id: "futurefoil"))

        XCTAssertEqual(uppercase, lowercase)
        XCTAssertEqual(Set([uppercase, lowercase]).count, 1)
        XCTAssertNotEqual(uppercase.id, "FutureFoil")
    }

    func testScryfallDecodesTreatmentEvidenceBesideFoil() throws {
        let card = try decodeMagic(
            finishes: ["foil"],
            promoTypes: ["surgefoil"],
            frameEffects: ["showcase"],
            variation: true,
            variationOf: "base-card"
        )
        let catalog = try makeCatalog(entries: [])

        XCTAssertEqual(card.catalogVariants, [.foil])
        XCTAssertEqual(
            card.magicTreatmentEvidence(using: catalog).treatments,
            [.surgeFoil]
        )
        XCTAssertEqual(card.promoTypes, ["surgefoil"])
        XCTAssertEqual(card.frameEffects, ["showcase"])
        XCTAssertEqual(card.variation, true)
        XCTAssertEqual(card.variationOf, "base-card")
    }

    func testExactCatalogAddsPublisherBackedQualifier() throws {
        let cardID = "4826991d-c3c3-45ff-9dfc-4246a84b40e0"
        let card = try decodeMagic(
            id: cardID,
            setCode: "neo",
            collectorNumber: "429",
            finishes: ["foil"],
            promoTypes: ["boosterfun", "neonink"]
        )
        let catalog = try makeCatalog(entries: [
            MagicTreatmentCatalogEntry(
                id: cardID,
                setCode: "neo",
                collectorNumber: "429",
                treatments: ["neonink"],
                qualifiers: ["neonink": "red"]
            )
        ])

        let evidence = card.magicTreatmentEvidence(using: catalog)
        XCTAssertEqual(
            evidence.treatments,
            [.neonInk]
        )
        XCTAssertEqual(evidence.qualifier(for: .neonInk), "red")
        XCTAssertEqual(card.catalogVariants, [.foil])
    }

    func testTreatmentDisplayComposesFinishAndQualifier() throws {
        let card = try decodeMagic(
            finishes: ["foil"],
            promoTypes: ["neonink"]
        )
        let catalog = try makeCatalog(entries: [
            MagicTreatmentCatalogEntry(
                id: card.id,
                setCode: card.setCode,
                collectorNumber: card.collectorNumber,
                treatments: ["neonink"],
                qualifiers: ["neonink": "red"]
            )
        ])

        XCTAssertEqual(
            card.magicTreatmentDisplayLabel(using: catalog),
            "Neon Ink · Red"
        )
        XCTAssertEqual(
            IdentifiedCard.magic(card).finishAndTreatmentDisplayLabel(for: .foil),
            "Foil · Neon Ink"
        )
    }

    func testDualFinishTreatmentFollowsTheSelectedFinish() throws {
        // FIC #10 is an audited dual-finish Surge Foil printing: the number
        // identifies the treatment, but the copy's finish still decides
        // whether that treatment applies.
        let card = try decodeMagic(
            id: "cb82d614-13d8-40ec-9213-8e6852d37c9c",
            setCode: "fic",
            collectorNumber: "10",
            finishes: ["foil", "nonfoil"],
            promoTypes: ["surgefoil"]
        )
        let evidence = card.magicTreatmentEvidence(using: .empty)

        XCTAssertEqual(evidence.displayLabel(with: .foil), "Foil · Surge Foil")
        XCTAssertEqual(evidence.displayLabel(with: .nonfoil), "Nonfoil")
        XCTAssertEqual(card.magicTreatmentDisplayLabel(using: .empty), "Surge Foil")
        XCTAssertTrue(card.magicTreatmentDiagnostics(using: .empty).isEmpty)
        XCTAssertEqual(
            IdentifiedCard.magic(card).finishAndTreatmentDisplayLabel(for: .nonfoil),
            "Nonfoil"
        )
        XCTAssertEqual(
            IdentifiedCard.magic(card).finishAndTreatmentDisplayLabel(for: nil),
            "Unknown finish · Surge Foil"
        )
    }

    func testMagicScanFlowsThroughCatalogToFinishQualifiedTreatmentKey() throws {
        let profile = MagicScanProfile(definitions: [
            .init(code: "FIC", printedSize: nil)
        ])
        let identifier = try XCTUnwrap(profile.parse(["FIC • EN", "0010"]))
        XCTAssertEqual(identifier.displayIdentifier, "FIC 10 EN")

        let appBundle = try XCTUnwrap(Bundle(identifier: "com.example.TradingCardScanner"))
        let catalog = try MagicTreatmentCatalogStore.bundled(bundle: appBundle)
        let card = try decodeMagic(
            id: "cb82d614-13d8-40ec-9213-8e6852d37c9c",
            setCode: "fic",
            collectorNumber: "10",
            finishes: ["foil", "nonfoil"],
            promoTypes: ["surgefoil"]
        )
        XCTAssertEqual(
            try XCTUnwrap(catalog.entry(forCardID: card.id)).decodedTreatments,
            [.surgeFoil]
        )

        let identified = IdentifiedCard.magic(card)
        let evidence = card.magicTreatmentEvidence(using: catalog)
        XCTAssertEqual(
            evidence.displayLabel(with: .nonfoil),
            "Nonfoil"
        )
        XCTAssertEqual(
            identified.collectionKey(variant: .nonfoil),
            "magic:cb82d614-13d8-40ec-9213-8e6852d37c9c#nonfoil"
        )
        XCTAssertEqual(
            evidence.displayLabel(with: .foil),
            "Foil · Surge Foil"
        )
        XCTAssertEqual(
            identified.collectionKey(variant: .foil),
            "magic:cb82d614-13d8-40ec-9213-8e6852d37c9c#foil#treatment=surgefoil"
        )
    }

    func testSlice9BundledNeoNeonInkQualifiersCoverAllFourExactPrintings() throws {
        let appBundle = try XCTUnwrap(
            Bundle(identifier: "com.example.TradingCardScanner"),
            "The runtime catalog must be validated from the application bundle"
        )
        let catalog = try MagicTreatmentCatalogStore.bundled(bundle: appBundle)
        let fixtures = [
            (
                id: "4826991d-c3c3-45ff-9dfc-4246a84b40e0",
                number: "429",
                color: "red"
            ),
            (
                id: "c046b0b3-05f0-4468-817f-355e87552faf",
                number: "430",
                color: "green"
            ),
            (
                id: "92da2c98-afe0-4e7a-9510-5a74cc2cdde4",
                number: "431",
                color: "blue"
            ),
            (
                id: "78c0b64b-cade-414d-b893-ac1b633c66d0",
                number: "432",
                color: "yellow"
            )
        ]

        for fixture in fixtures {
            let entry = try XCTUnwrap(catalog.entry(forCardID: fixture.id))
            XCTAssertEqual(entry.setCode, "neo")
            XCTAssertEqual(entry.collectorNumber, fixture.number)
            XCTAssertEqual(entry.decodedTreatments, [.neonInk])
            XCTAssertEqual(entry.qualifiers, [MagicTreatment.neonInk.id: fixture.color])

            let card = try decodeMagic(
                id: fixture.id,
                setCode: "neo",
                collectorNumber: fixture.number,
                finishes: ["foil"],
                promoTypes: ["neonink"]
            )
            let evidence = catalog.evidence(for: card)
            XCTAssertEqual(evidence.treatments, [.neonInk])
            XCTAssertEqual(evidence.qualifier(for: .neonInk), fixture.color)
        }
    }

    func testSlice9FinalFantasySuffixesRemainDistinctThroughScanAndCompletion() throws {
        let profile = MagicScanProfile(definitions: [
            .init(code: "FIN", printedSize: nil)
        ])
        let numbers = ["523b", "525a", "525b", "527a", "527b"]
        let identifiers = try numbers.map { number in
            try XCTUnwrap(profile.parse(["FIN • \(number) • EN"]))
        }

        XCTAssertEqual(
            identifiers.map(\.displayIdentifier),
            numbers.map { "FIN \($0) EN" }
        )
        XCTAssertEqual(Set(identifiers).count, numbers.count)

        let set = CatalogSet(
            catalogID: CatalogSetID(game: .magic, providerID: "fin"),
            name: "Final Fantasy",
            code: "FIN",
            logoURL: nil,
            symbolURL: nil,
            cardCount: numbers.count,
            releaseDate: nil,
            sortRank: 1
        )
        let owned = numbers.map { number in
            CollectedCard(
                collectionKey: "magic:fin-\(number)#foil",
                game: .magic,
                providerID: "fin-\(number)",
                name: "Fixture \(number)",
                setName: "Final Fantasy",
                setCode: "FIN",
                cardNumber: number,
                rarity: nil,
                imageURL: nil,
                thumbnailURL: nil,
                variant: .foil,
                variantResolution: .userConfirmed
            )
        }
        let treatedCopyOfOneNumber = CollectedCard(
            collectionKey: "magic:fin-523b#foil#treatment=surgefoil",
            game: .magic,
            providerID: "fin-523b",
            name: "Fixture 523b",
            setName: "Final Fantasy",
            setCode: "FIN",
            cardNumber: "523b",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .foil,
            variantResolution: .userConfirmed,
            magicTreatments: [.surgeFoil]
        )

        XCTAssertEqual(
            SetCompletionCalculator.progress(
                for: set,
                cards: owned + [treatedCopyOfOneNumber]
            ),
            SetCompletion(owned: numbers.count, total: numbers.count, unit: "cards")
        )
    }

    func testSlice9DualFinishFICIsKeyedAndPricedOnlyForSelectedFinish() throws {
        let card = try decodeMagic(
            id: "slice9-fic-10",
            setCode: "fic",
            collectorNumber: "10",
            finishes: ["foil", "nonfoil"],
            promoTypes: ["surgefoil"],
            prices: ["usd": "1.25", "usd_foil": "6.40"]
        )
        let identified = IdentifiedCard.magic(card)
        let foilTreatments = identified.magicTreatments(for: .foil)
        let nonfoilTreatments = identified.magicTreatments(for: .nonfoil)

        XCTAssertEqual(foilTreatments, [.surgeFoil])
        XCTAssertTrue(nonfoilTreatments.isEmpty)
        XCTAssertEqual(
            identified.collectionKey(variant: .nonfoil),
            "magic:slice9-fic-10#nonfoil"
        )
        XCTAssertEqual(
            identified.collectionKey(variant: .foil),
            "magic:slice9-fic-10#foil#treatment=surgefoil"
        )
        XCTAssertEqual(
            CardPricing.price(
                for: identified,
                variant: .foil,
                magicTreatments: foilTreatments
            ),
            .unavailable(.scryfall)
        )
        guard case let .price(nonfoilPrice) = CardPricing.price(
            for: identified,
            variant: .nonfoil,
            magicTreatments: nonfoilTreatments
        ) else {
            return XCTFail("The nonfoil FIC copy should retain its ordinary Scryfall price")
        }
        XCTAssertEqual(nonfoilPrice.unitMarketPriceUSD, 1.25)
        XCTAssertEqual(nonfoilPrice.sourceVariantID, "usd")
    }

    func testSharedTreatmentRuleDrivesCollectionKeysForEachFinish() throws {
        let card = try decodeMagic(
            id: "dual-finish-treatment",
            finishes: ["foil", "nonfoil"],
            promoTypes: ["surgefoil"]
        )
        let identified = IdentifiedCard.magic(card)

        XCTAssertEqual(
            identified.collectionKey(variant: .nonfoil),
            "magic:dual-finish-treatment#nonfoil"
        )
        XCTAssertEqual(
            identified.collectionKey(variant: .foil),
            "magic:dual-finish-treatment#foil#treatment=surgefoil"
        )
        XCTAssertEqual(
            identified.finishAndTreatmentDisplayLabel(for: .nonfoil),
            "Nonfoil"
        )
        XCTAssertEqual(
            identified.finishAndTreatmentDisplayLabel(for: .foil),
            "Foil · Surge Foil"
        )
    }

    func testTreatmentKeyCodecsPreserveTheirIndependentBaseFormats() {
        let treatments: [MagicTreatment] = [
            .surgeFoil,
            .unclassified("Rainbow / Foil")
        ]

        XCTAssertEqual(
            MagicTreatmentKeyCodec.appendCollectionSuffix(
                to: "magic:printing#foil",
                treatments: treatments
            ),
            "magic:printing#foil#treatment=rainbow%20%2F%20foil#treatment=surgefoil"
        )
        XCTAssertEqual(
            MagicTreatmentKeyCodec.appendPriceSuffix(
                to: "magic:printing:foil",
                treatments: treatments
            ),
            "magic:printing:foil:treatment=rainbow%20%2F%20foil:treatment=surgefoil"
        )
    }

    func testCollectionReadThroughRemovesTreatmentForEveryIdentityFamily() {
        XCTAssertEqual(
            MagicTreatmentKeyCodec.legacyCollectionKeys(
                for: "magic:printing#foil#treatment=surgefoil"
            ),
            ["magic:printing#foil"]
        )
        XCTAssertEqual(
            MagicTreatmentKeyCodec.legacyCollectionKeys(
                for: "graded:magic:printing:variant#treatment=neonink"
            ),
            ["graded:magic:printing:variant"]
        )
        XCTAssertEqual(
            MagicTreatmentKeyCodec.legacyCollectionKeys(
                for: "graded:magic:printing:variant:cert:1234#treatment=neonink"
            ),
            ["graded:magic:printing:variant:cert:1234"]
        )
        XCTAssertEqual(
            MagicTreatmentKeyCodec.legacyCollectionKeys(
                for: "sealed:magic:product:variant#treatment=surgefoil"
            ),
            ["sealed:magic:product:variant"]
        )
        XCTAssertEqual(
            MagicTreatmentKeyCodec.legacyCollectionKeys(
                for: "magic:printing#foil#treatment=surgefoil@firstEdition"
            ),
            ["magic:printing#foil@firstEdition"]
        )
        XCTAssertTrue(
            MagicTreatmentKeyCodec.legacyCollectionKeys(
                for: "magic:printing#foil"
            ).isEmpty
        )
    }

    func testCollectionKeyPartsRecognizeEveryMagicIdentityFamily() throws {
        let fixtures: [
            (String, MagicCollectionKeyShape, String, String?, String?, [String])
        ] = [
            (
                "magic:printing",
                .rawLegacy,
                "magic:printing",
                "printing",
                nil,
                []
            ),
            (
                "magic:printing#foil",
                .rawFinish,
                "magic:printing#foil",
                "printing",
                "foil",
                []
            ),
            (
                "magic:printing#foil#treatment=surgefoil",
                .rawFinishTreatment,
                "magic:printing#foil",
                "printing",
                "foil",
                ["surgefoil"]
            ),
            (
                "graded:magic:printing:variant",
                .graded,
                "graded:magic:printing:variant",
                "printing",
                nil,
                []
            ),
            (
                "graded:magic:printing:variant:cert:1234#treatment=neonink",
                .gradedCertified,
                "graded:magic:printing:variant:cert:1234",
                "printing",
                nil,
                ["neonink"]
            ),
            (
                "sealed:magic:product:variant#treatment=surgefoil",
                .sealed,
                "sealed:magic:product:variant",
                nil,
                nil,
                ["surgefoil"]
            ),
            (
                "magic:vendor:opaque#foil#treatment=surgefoil",
                .rawImported,
                "magic:vendor:opaque#foil",
                nil,
                "foil",
                ["surgefoil"]
            ),
            (
                "graded:magic:vendor#psa|10||#treatment=neonink",
                .gradedImported,
                "graded:magic:vendor#psa|10||",
                nil,
                nil,
                ["neonink"]
            ),
            (
                "sealed:magic:vendor#treatment=surgefoil",
                .sealedImported,
                "sealed:magic:vendor",
                nil,
                nil,
                ["surgefoil"]
            )
        ]

        for (key, shape, baseKey, exactID, finishID, treatmentIDs) in fixtures {
            let parts = try XCTUnwrap(
                MagicTreatmentKeyCodec.collectionKeyParts(from: key),
                "Expected a valid Magic key: \(key)"
            )
            XCTAssertEqual(parts.shape, shape)
            XCTAssertEqual(parts.baseKey, baseKey)
            XCTAssertEqual(parts.exactPrintingID, exactID)
            XCTAssertEqual(parts.finishID, finishID)
            XCTAssertEqual(parts.treatmentIDs, treatmentIDs)
        }
    }

    func testPriceKeyPartsKeepVendorNativeColonSegmentsOpaque() throws {
        let legacy = "magic:justtcg:v2:vendor-variant:foil"
        let treated = legacy + ":treatment=Rainbow%20Foil:treatment=surgefoil"

        let legacyParts = try XCTUnwrap(
            MagicTreatmentKeyCodec.priceKeyParts(from: legacy)
        )
        XCTAssertEqual(legacyParts.baseKey, legacy)
        XCTAssertTrue(legacyParts.treatmentIDs.isEmpty)

        let treatedParts = try XCTUnwrap(
            MagicTreatmentKeyCodec.priceKeyParts(from: treated)
        )
        XCTAssertEqual(treatedParts.baseKey, legacy)
        XCTAssertEqual(treatedParts.treatmentIDs, ["Rainbow Foil", "surgefoil"])
        XCTAssertEqual(
            MagicTreatmentKeyCodec.priceBaseKey(treated),
            legacy
        )
    }

    func testMigrationOperationIDIsStableButPairScoped() {
        let first = MagicTreatmentMigration.operationID(
            sourceRecordIdentity: "record",
            oldKey: "magic:printing#foil",
            newKey: "magic:printing#foil#treatment=surgefoil"
        )
        let retry = MagicTreatmentMigration.operationID(
            sourceRecordIdentity: "record",
            oldKey: "magic:printing#foil",
            newKey: "magic:printing#foil#treatment=surgefoil"
        )
        let otherPair = MagicTreatmentMigration.operationID(
            sourceRecordIdentity: "record",
            oldKey: "magic:printing#nonfoil",
            newKey: "magic:printing#nonfoil#treatment=surgefoil"
        )

        XCTAssertEqual(first, retry)
        XCTAssertNotEqual(first, otherPair)
        XCTAssertEqual(
            InventoryEvent.idempotencyKey(operationID: first, leg: .from),
            "\(first.uuidString):from"
        )
        XCTAssertEqual(
            InventoryEvent.idempotencyKey(operationID: first, leg: .to),
            "\(first.uuidString):to"
        )
    }

    func testCollectionCSVRoundTripsTreatmentIdentityAndCollectionKey() throws {
        let card = CollectedCard(
            collectionKey: "magic:printing#foil#treatment=neonink",
            game: .magic,
            providerID: "printing",
            name: "Fixture",
            setName: "Fixture Set",
            setCode: "FIC",
            cardNumber: "10",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .foil,
            variantResolution: .userConfirmed,
            magicTreatments: [.neonInk],
            magicTreatmentQualifiers: ["NEONINK": "red"],
            magicContentKind: .token
        )

        let document = CollectionCSV.export([card])
        let plan = try CollectionCSV.parse(Data(document.text.utf8))
        let entry: CollectionCSVEntry = try XCTUnwrap(plan.entries.first)

        XCTAssertEqual(entry.magicTreatmentIDsRaw, ["neonink"])
        XCTAssertEqual(entry.magicTreatmentQualifiers, ["neonink": "red"])
        XCTAssertEqual(entry.magicContentKindRaw, MagicContentKind.token.rawValue)
        XCTAssertEqual(entry.collectionKey, card.collectionKey)
        XCTAssertEqual(entry.variant, PhysicalVariant.foil)
    }

    func testCollectionCSVPreservesUnknownTreatmentAndContentKindValues() throws {
        let unknown = try XCTUnwrap(MagicTreatment(id: "Future / Foil"))
        let key = MagicTreatmentKeyCodec.finishQualifiedCollectionKey(
            base: "magic:printing",
            game: .magic,
            finish: .foil,
            treatments: [unknown]
        )
        let card = CollectedCard(
            collectionKey: key,
            game: .magic,
            providerID: "printing",
            name: "Fixture",
            setName: "Fixture Set",
            setCode: "FIC",
            cardNumber: "10",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .foil,
            variantResolution: .userConfirmed,
            magicTreatments: [unknown],
            magicTreatmentQualifiers: ["Future / Foil": "publisher stamp"],
            magicContentKind: .regular
        )
        card.magicContentKindRaw = "future-face"

        let plan = try CollectionCSV.parse(
            Data(CollectionCSV.export([card]).text.utf8)
        )
        let entry = try XCTUnwrap(plan.entries.first)

        XCTAssertEqual(entry.magicTreatmentIDsRaw, ["Future / Foil"])
        XCTAssertEqual(entry.magicTreatmentQualifiers, ["future / foil": "publisher stamp"])
        XCTAssertEqual(entry.magicContentKindRaw, "future-face")
        XCTAssertEqual(entry.collectionKey, key)
    }

    func testCollectionCSVKeepsUnknownTreatmentAsTreatmentNotAFakeFinish() throws {
        let unknown = try XCTUnwrap(MagicTreatment(id: "Future / Foil"))
        let key = MagicTreatmentKeyCodec.finishQualifiedCollectionKey(
            base: "magic:printing",
            game: .magic,
            finish: .foil,
            treatments: [unknown]
        )
        let card = CollectedCard(
            collectionKey: key,
            game: .magic,
            providerID: "printing",
            name: "Fixture",
            setName: "Fixture Set",
            setCode: "FIC",
            cardNumber: "10",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .foil,
            variantResolution: .userConfirmed,
            magicTreatments: [unknown]
        )

        let plan = try CollectionCSV.parse(
            Data(CollectionCSV.export([card]).text.utf8)
        )
        let entry = try XCTUnwrap(plan.entries.first)

        XCTAssertEqual(entry.magicTreatmentIDsRaw, ["Future / Foil"])
        XCTAssertEqual(entry.variant, .foil)
        XCTAssertEqual(entry.collectionKey, key)
        XCTAssertEqual(entry.variant?.id, PhysicalVariant.foil.id)
    }

    func testCollectionCSVCanonicalizesPaddedMagicSuffixWithoutDroppingIt() throws {
        let csv = """
        game,provider_id,card_name,set_name,set_code,card_number,quantity
        magic,printing,Fixture,Final Fantasy,FIN,0523b,1
        """

        let plan = try CollectionCSV.parse(Data(csv.utf8))

        XCTAssertEqual(plan.entries.first?.cardNumber, "523b")
    }

    func testCSVNamespacedFallbackKeysRetainMagicTreatmentsWithoutVendorUUIDs() throws {
        let csv = """
        game,provider_id,card_name,set_name,set_code,card_number,quantity,item_kind,grading_company,grade,magic_treatment_ids
        magic,printing,Fixture,Fixture Set,FIC,10,1,gradedCard,psa,10,"[""neonink""]"
        magic,box,Fixture Box,Fixture Set,FIC,,1,sealedProduct,,,"[""surgefoil""]"
        """

        let plan = try CollectionCSV.parse(Data(csv.utf8))
        let entriesByID = Dictionary(
            plan.entries.map { ($0.providerID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        XCTAssertEqual(
            entriesByID["printing"]?.collectionKey,
            "graded:magic:printing#psa|10||#treatment=neonink"
        )
        XCTAssertEqual(
            entriesByID["box"]?.collectionKey,
            "sealed:magic:box#treatment=surgefoil"
        )
    }

    func testKnownProviderSignalStillWorksForCardsNotYetInCompactCatalog() throws {
        let card = try decodeMagic(
            setCode: "fin",
            collectorNumber: "523",
            finishes: ["foil"],
            promoTypes: ["surgefoil"]
        )

        XCTAssertEqual(
            card.magicTreatmentEvidence(using: .empty).treatments,
            [.surgeFoil]
        )
    }

    func testNeonInkWithoutManualEvidenceRemainsUnqualified() throws {
        let card = try decodeMagic(
            setCode: "lci",
            collectorNumber: "410",
            finishes: ["foil"],
            promoTypes: ["neonink"]
        )

        XCTAssertEqual(
            card.magicTreatmentEvidence(using: .empty).treatments,
            [.neonInk]
        )
        XCTAssertNil(
            card.magicTreatmentEvidence(using: .empty).qualifier(for: .neonInk)
        )
    }

    func testFoilOnlyTreatmentReportsExplicitNonfoilContradiction() throws {
        let card = try decodeMagic(
            finishes: ["nonfoil"],
            promoTypes: ["surgefoil"]
        )

        let diagnostics = card.magicTreatmentDiagnostics(using: .empty)
        let diagnostic = try XCTUnwrap(diagnostics.first)
        XCTAssertEqual(diagnostic.treatment, .surgeFoil)
        XCTAssertEqual(diagnostic.requiredFinish, .foil)
        XCTAssertEqual(diagnostic.publishedFinishes, [.nonfoil])
        XCTAssertEqual(diagnostic.title, "Surge Foil / Foil mismatch")
        XCTAssertTrue(diagnostic.detail.contains("published as Nonfoil"))
        XCTAssertTrue(diagnostic.detail.contains("requires Foil"))
    }

    func testMissingFinishMetadataDoesNotInventAContradiction() throws {
        let card = try decodeMagic(
            finishes: [],
            promoTypes: ["surgefoil"]
        )

        XCTAssertTrue(card.magicTreatmentDiagnostics(using: .empty).isEmpty)
    }

    func testCatalogEnrichmentRequiresTheExactPrintingIdentity() throws {
        let card = try decodeMagic(
            id: "same-id",
            setCode: "neo",
            collectorNumber: "430",
            finishes: ["foil"]
        )
        let catalog = try makeCatalog(entries: [
            MagicTreatmentCatalogEntry(
                id: "same-id",
                setCode: "neo",
                collectorNumber: "429",
                treatments: ["neonink"],
                qualifiers: ["neonink": "red"]
            )
        ])

        XCTAssertTrue(card.magicTreatmentEvidence(using: catalog).isEmpty)
    }

    func testUnrelatedPromoMetadataDoesNotBecomeATreatment() throws {
        let card = try decodeMagic(
            finishes: ["foil"],
            promoTypes: ["boosterfun", "serialized"],
            frameEffects: ["showcase", "borderless"]
        )

        XCTAssertTrue(card.magicTreatmentEvidence(using: .empty).isEmpty)
    }

    func testBundledCatalogIsCompactAndContainsAuditedTreatmentCoverage() throws {
        let appBundle = try XCTUnwrap(
            Bundle(identifier: "com.example.TradingCardScanner"),
            "The runtime catalog must be validated from the application bundle"
        )
        let catalog = try MagicTreatmentCatalogStore.bundled(bundle: appBundle)

        XCTAssertEqual(catalog.artifact.schemaVersion, MagicTreatmentCatalog.schemaVersion)
        XCTAssertEqual(catalog.artifact.sourceAuditSchemaVersion, 2)
        XCTAssertEqual(catalog.artifact.sourceAuditRulesVersion, 1)
        XCTAssertEqual(catalog.artifact.sourceBulkDataType, "default_cards")
        XCTAssertEqual(catalog.artifact.entries.count, 2_537)

        let neon = try XCTUnwrap(
            catalog.entry(forCardID: "4826991d-c3c3-45ff-9dfc-4246a84b40e0")
        )
        XCTAssertEqual(neon.setCode, "neo")
        XCTAssertEqual(neon.collectorNumber, "429")
        XCTAssertEqual(neon.decodedTreatments, [.neonInk])
        let neonCard = try decodeMagic(
            id: neon.id,
            setCode: neon.setCode,
            collectorNumber: neon.collectorNumber,
            finishes: ["foil"],
            promoTypes: ["neonink"]
        )
        XCTAssertEqual(
            catalog.evidence(for: neonCard).qualifier(for: .neonInk),
            "red"
        )
        XCTAssertEqual(neonCard.magicTreatmentEvidence.treatments, [.neonInk])
        XCTAssertEqual(
            neonCard.magicTreatmentEvidence.qualifier(for: .neonInk),
            "red"
        )

        let surge = try XCTUnwrap(
            catalog.entry(forCardID: "bbd46c0d-cd9d-4e48-b6bf-f619e141100c")
        )
        XCTAssertEqual(surge.setCode, "fin")
        XCTAssertEqual(surge.collectorNumber, "523")
        XCTAssertEqual(surge.decodedTreatments, [.surgeFoil])
    }

    func testBundledDefaultReportsAUsableCatalogStatus() {
        XCTAssertEqual(MagicTreatmentCatalogStore.bundledDefaultStatus, .ready)
        XCTAssertNil(MagicTreatmentCatalogStore.bundledDefaultStatus.error)
    }

    func testCatalogPreservesUnknownTreatmentIDsAsUnclassified() throws {
        let artifact = MagicTreatmentCatalogArtifact(
            schemaVersion: MagicTreatmentCatalog.schemaVersion,
            sourceAuditSchemaVersion: 2,
            sourceAuditRulesVersion: 1,
            sourceBulkDataID: "bulk",
            sourceBulkDataType: "default_cards",
            sourceContentSHA256: "sha",
            generatedAt: "2026-09-03T00:00:00Z",
            entries: [
                MagicTreatmentCatalogEntry(
                    id: "future-card",
                    setCode: "fin",
                    collectorNumber: "999",
                    treatments: ["unknown-treatment"]
                )
            ]
        )

        let catalog = try MagicTreatmentCatalog(artifact: artifact)
        let card = try decodeMagic(
            id: "future-card",
            setCode: "fin",
            collectorNumber: "999",
            finishes: ["foil"]
        )
        XCTAssertEqual(
            catalog.treatments(for: card),
            [.unclassified("unknown-treatment")]
        )
    }

    func testCatalogRejectsUnsupportedSchemaVersions() throws {
        let artifact = MagicTreatmentCatalogArtifact(
            schemaVersion: 1,
            sourceAuditSchemaVersion: 2,
            sourceAuditRulesVersion: 1,
            sourceBulkDataID: "bulk",
            sourceBulkDataType: "default_cards",
            sourceContentSHA256: "sha",
            generatedAt: "2026-09-03T00:00:00Z",
            entries: []
        )

        XCTAssertThrowsError(try MagicTreatmentCatalog(artifact: artifact)) { error in
            XCTAssertEqual(error as? MagicTreatmentCatalogError, .unsupportedArtifact)
        }
    }

    private func makeCatalog(entries: [MagicTreatmentCatalogEntry]) throws -> MagicTreatmentCatalog {
        try MagicTreatmentCatalog(
            artifact: MagicTreatmentCatalogArtifact(
                schemaVersion: MagicTreatmentCatalog.schemaVersion,
                sourceAuditSchemaVersion: 2,
                sourceAuditRulesVersion: 1,
                sourceBulkDataID: "fixture",
                sourceBulkDataType: "default_cards",
                sourceContentSHA256: "fixture",
                generatedAt: "2026-09-03T00:00:00Z",
                entries: entries
            )
        )
    }

    private func decodeMagic(
        id: String = "fixture-card",
        setCode: String = "fin",
        collectorNumber: String = "523",
        finishes: [String] = [],
        promoTypes: [String]? = nil,
        frameEffects: [String]? = nil,
        variation: Bool? = nil,
        variationOf: String? = nil,
        prices: [String: String] = [:]
    ) throws -> ScryfallCard {
        var optionalFields = ""
        if let promoTypes {
            optionalFields += #", "promo_types": ["#
                + promoTypes.map { "\"\($0)\"" }.joined(separator: ",")
                + #"]"#
        }
        if let frameEffects {
            optionalFields += #", "frame_effects": ["#
                + frameEffects.map { "\"\($0)\"" }.joined(separator: ",")
                + #"]"#
        }
        if let variation {
            optionalFields += ", \"variation\": \(variation)"
        }
        if let variationOf {
            optionalFields += ", \"variation_of\": \"\(variationOf)\""
        }
        if !prices.isEmpty {
            let encodedPrices = prices.keys.sorted().compactMap { key in
                prices[key].map { "\"\(key)\": \"\($0)\"" }
            }.joined(separator: ",")
            optionalFields += ", \"prices\": {\(encodedPrices)}"
        }

        let json = """
        {
          "id": "\(id)",
          "name": "Fixture",
          "set": "\(setCode)",
          "set_name": "Fixture Set",
          "collector_number": "\(collectorNumber)",
          "lang": "en",
          "digital": false,
          "layout": "normal",
          "finishes": [\(finishes.map { "\"\($0)\"" }.joined(separator: ","))]\(optionalFields)
        }
        """
        return try JSONDecoder().decode(ScryfallCard.self, from: Data(json.utf8))
    }
}

@MainActor
final class MagicTreatmentMigrationTests: XCTestCase {
    private var container: ModelContainer?

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    func testPriceRefreshPlanningWaitsForNetworkTreatmentMigration() async throws {
        let context = try makeContext()
        let gate = MagicTreatmentMigrationGate()
        let coordinator = MagicTreatmentMigrationCoordinator(
            networkRunner: { _, _ in
                await gate.markStarted()
                await gate.waitUntilOpen()
                return MagicTreatmentMigration.Report()
            }
        )

        let migration = Task { @MainActor in
            await coordinator.runNetwork(in: context)
        }
        for _ in 0..<10_000 {
            if await gate.started() { break }
            await Task.yield()
        }
        let migrationStarted = await gate.started()
        XCTAssertTrue(migrationStarted)

        var refreshEntered = false
        let refresh = Task { @MainActor in
            await coordinator.withPriceRefresh(in: context) {
                refreshEntered = true
            }
        }
        for _ in 0..<100 {
            await Task.yield()
        }
        XCTAssertFalse(refreshEntered)

        await gate.open()
        _ = await migration.value
        await refresh.value
        XCTAssertTrue(refreshEntered)
    }

    func testBackgroundStylePriceRefreshDoesNotWaitForNetworkMigration() async throws {
        let context = try makeContext()
        let counter = MagicTreatmentMigrationRunCounter()
        let coordinator = MagicTreatmentMigrationCoordinator(
            networkRunner: { _, _ in
                _ = await counter.increment()
                return MagicTreatmentMigration.Report()
            }
        )

        var operationEntered = false
        _ = await coordinator.withPriceRefresh(
            in: context,
            runsNetworkMigration: false
        ) {
            operationEntered = true
        }

        XCTAssertTrue(operationEntered)
        let networkRunCount = await counter.value()
        XCTAssertEqual(
            networkRunCount,
            0,
            "the short background lane must not spend its budget on deferred Scryfall migration"
        )
    }

    func testBackgroundStylePriceRefreshWaitsForAnAlreadyRunningNetworkMigration() async throws {
        let context = try makeContext()
        let gate = MagicTreatmentMigrationGate()
        let coordinator = MagicTreatmentMigrationCoordinator(
            networkRunner: { _, _ in
                await gate.markStarted()
                await gate.waitUntilOpen()
                return MagicTreatmentMigration.Report()
            }
        )

        // Populate the cached local report first. This is the state that used
        // to let the local core return before noticing the active network task.
        _ = await coordinator.runLocal(in: context)
        let migration = Task { @MainActor in
            await coordinator.runNetwork(in: context)
        }
        for _ in 0..<10_000 {
            if await gate.started() { break }
            await Task.yield()
        }
        let networkStarted = await gate.started()
        XCTAssertTrue(networkStarted)

        var operationEntered = false
        let refresh = Task { @MainActor in
            await coordinator.withPriceRefresh(
                in: context,
                runsNetworkMigration: false
            ) {
                operationEntered = true
            }
        }
        for _ in 0..<100 {
            await Task.yield()
        }
        XCTAssertFalse(operationEntered)

        await gate.open()
        _ = await migration.value
        await refresh.value
        XCTAssertTrue(operationEntered)
    }

    func testTreatmentMigrationWaitsForAnActivePriceRefresh() async throws {
        let context = try makeContext()
        let refreshGate = MagicTreatmentMigrationGate()
        let networkRuns = MagicTreatmentMigrationRunCounter()
        let coordinator = MagicTreatmentMigrationCoordinator(
            networkRunner: { _, _ in
                _ = await networkRuns.increment()
                return MagicTreatmentMigration.Report()
            }
        )

        let refresh = Task { @MainActor in
            await coordinator.withPriceRefresh(
                in: context,
                runsNetworkMigration: false
            ) {
                await refreshGate.markStarted()
                await refreshGate.waitUntilOpen()
            }
        }
        for _ in 0..<10_000 {
            if await refreshGate.started() { break }
            await Task.yield()
        }
        let refreshStarted = await refreshGate.started()
        XCTAssertTrue(refreshStarted)

        let migration = Task { @MainActor in
            await coordinator.runNetwork(in: context)
        }
        for _ in 0..<100 {
            await Task.yield()
        }
        let networkRunsWhileRefreshing = await networkRuns.value()
        XCTAssertEqual(
            networkRunsWhileRefreshing,
            0,
            "migration must not enter its network runner while a price refresh owns the gate"
        )

        await refreshGate.open()
        await refresh.value
        _ = await migration.value
        let completedNetworkRuns = await networkRuns.value()
        XCTAssertEqual(completedNetworkRuns, 1)
    }

    func testMigrationRechecksRowsAddedDuringAnInFlightPass() async throws {
        let context = try makeContext()
        let gate = MagicTreatmentMigrationGate()
        let counter = MagicTreatmentMigrationRunCounter()
        let coordinator = MagicTreatmentMigrationCoordinator(
            networkRunner: { _, _ in
                let call = await counter.increment()
                if call == 1 {
                    await gate.markStarted()
                    await gate.waitUntilOpen()
                }
                return MagicTreatmentMigration.Report()
            }
        )

        let migration = Task { @MainActor in
            await coordinator.runNetwork(in: context)
        }
        for _ in 0..<10_000 {
            if await gate.started() { break }
            await Task.yield()
        }
        let migrationStarted = await gate.started()
        XCTAssertTrue(migrationStarted)

        coordinator.invalidateCompletedReports()
        await gate.open()
        _ = await migration.value
        let runCount = await counter.value()
        XCTAssertEqual(runCount, 2)
    }

    func testMigrationInvalidationClearsCompletedReport() async throws {
        let context = try makeContext()
        let counter = MagicTreatmentMigrationRunCounter()
        let coordinator = MagicTreatmentMigrationCoordinator(
            networkRunner: { _, _ in
                _ = await counter.increment()
                return MagicTreatmentMigration.Report()
            }
        )

        _ = await coordinator.runNetwork(in: context)
        _ = await coordinator.runNetwork(in: context)
        let cachedRunCount = await counter.value()
        XCTAssertEqual(cachedRunCount, 1)

        coordinator.invalidateCompletedReports()
        _ = await coordinator.runNetwork(in: context)
        let refreshedRunCount = await counter.value()
        XCTAssertEqual(refreshedRunCount, 2)
    }

    func testLocalMigrationDefersCatalogMissesToBatchedNetworkPhase() async throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 900)
        let ids = (0..<76).map { String(format: "batch-card-%03d", $0) }

        for id in ids {
            context.insert(
                makeRow(
                    key: "magic:\(id)#foil",
                    providerID: id,
                    quantity: 1,
                    treatments: []
                )
            )
        }
        try context.save()

        let local = await MagicTreatmentMigration.runLocal(in: context, now: date)
        XCTAssertEqual(local.exactLookups, 0)
        XCTAssertFalse(local.didChange)
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<CollectedCard>())
                .allSatisfy { $0.magicTreatmentMigrationVersion == 0 }
        )

        var responseMap: [String: ScryfallCard] = [:]
        for id in ids {
            responseMap[id] = try makeScryfallCard(
                id: id,
                finishes: ["foil"],
                promoTypes: ["surgefoil"]
            )
        }
        let responses = responseMap
        let recorder = MagicTreatmentBatchRecorder()
        let network = await MagicTreatmentMigration.runNetwork(
            in: context,
            now: date
        ) { requestedIDs in
            await recorder.record(requestedIDs)
            return requestedIDs.compactMap { responses[$0] }
        }

        let batches = await recorder.batches()
        XCTAssertEqual(batches.count, 2)
        XCTAssertEqual(batches.map(\.count), [75, 1])
        XCTAssertEqual(Set(batches.flatMap { $0 }), Set(ids))
        XCTAssertEqual(network.exactLookups, ids.count)
        XCTAssertEqual(network.rekeyedRows, ids.count)
        XCTAssertTrue(network.isComplete)
    }

    func testMigrationDoesNotMergeGradedRowsWithMissingOptionalIdentity() async throws {
        let context = try makeContext()
        let legacyKey = "graded:magic:graded-identity:vendor-variant"
        let canonicalKey = legacyKey + "#treatment=surgefoil"
        let legacy = makeRow(
            key: legacyKey,
            providerID: "graded-identity",
            quantity: 1,
            treatments: [],
            variant: nil,
            itemKind: .gradedCard
        )
        let canonical = makeRow(
            key: canonicalKey,
            providerID: "graded-identity",
            quantity: 1,
            treatments: [.surgeFoil],
            variant: nil,
            itemKind: .gradedCard
        )
        canonical.gradeRaw = "10"
        context.insert(legacy)
        context.insert(canonical)
        try context.save()

        let response = try makeScryfallCard(
            id: "graded-identity",
            finishes: ["foil"],
            promoTypes: ["surgefoil"]
        )
        let report = await MagicTreatmentMigration.run(
            in: context,
            now: Date(timeIntervalSince1970: 950)
        ) { _ in response }

        XCTAssertFalse(report.isComplete)
        XCTAssertEqual(report.mergedCollisions, 0)
        let rows = try context.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(Set(rows.map(\.collectionKey)), Set([legacyKey, canonicalKey]))
        XCTAssertEqual(rows.map(\.quantity).sorted(), [1, 1])
    }

    func testMigrationEnrichesAndRekeysAnExactRawRow() async throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 1_000)
        let oldKey = "magic:migration-card#foil"
        let row = makeRow(
            key: oldKey,
            providerID: "migration-card",
            quantity: 2,
            treatments: []
        )
        context.insert(row)
        try appendLineage(for: row, quantity: 2, at: date, in: context)
        let activity = try XCTUnwrap(
            context.fetch(FetchDescriptor<CollectionActivity>()).first
        )
        activity.removalSnapshotData = try JSONEncoder().encode(
            RemovedCardSnapshot(card: row)
        )
        let genericPrice = PriceRecord(
            key: PriceRecord.key(
                game: .magic,
                printingID: "migration-card",
                variantID: PhysicalVariant.foil.id
            ),
            game: .magic,
            printingID: "migration-card",
            variantID: PhysicalVariant.foil.id
        )
        genericPrice.unitMarketPriceUSD = 12.50
        genericPrice.sourceRaw = PriceSource.scryfall.rawValue
        context.insert(genericPrice)
        try context.save()

        let response = try makeScryfallCard(
            id: "migration-card",
            finishes: ["foil"],
            promoTypes: ["surgefoil"]
        )
        let report = await MagicTreatmentMigration.run(
            in: context,
            now: date
        ) { requestedID in
            guard requestedID == response.id else {
                throw NSError(domain: "MagicTreatmentMigrationTests", code: 1)
            }
            return response
        }

        XCTAssertEqual(report.exactLookups, 1)
        XCTAssertEqual(report.rekeyedRows, 1)
        XCTAssertEqual(report.enrichedRows, 1)
        XCTAssertTrue(report.isComplete)

        let canonicalKey = "magic:migration-card#foil#treatment=surgefoil"
        let rows = try context.fetch(FetchDescriptor<CollectedCard>())
        let migrated = try XCTUnwrap(rows.first)
        XCTAssertEqual(migrated.collectionKey, canonicalKey)
        XCTAssertEqual(migrated.magicTreatmentIDsRaw, ["surgefoil"])
        XCTAssertEqual(
            migrated.magicTreatmentMigrationVersion,
            MagicTreatmentMigration.currentVersion
        )

        let events = try context.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.collectionKey, canonicalKey)
        XCTAssertEqual(events.first?.priceStorageKey, "magic:migration-card:foil")

        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities.first?.collectionKey, canonicalKey)
        XCTAssertEqual(activities.first?.magicTreatmentIDsRaw, ["surgefoil"])
        XCTAssertEqual(activities.first?.variantID, PhysicalVariant.foil.id)
        let snapshotData = try XCTUnwrap(activities.first?.removalSnapshotData)
        let snapshot = try JSONDecoder().decode(RemovedCardSnapshot.self, from: snapshotData)
        XCTAssertEqual(snapshot.collectionKey, canonicalKey)
        XCTAssertEqual(snapshot.magicTreatmentIDsRaw, ["surgefoil"])
        XCTAssertEqual(snapshot.variant, .foil)
        let prices = try context.fetch(FetchDescriptor<PriceRecord>())
        XCTAssertEqual(prices.map(\.key), ["magic:migration-card:foil"])
        XCTAssertEqual(prices.first?.unitMarketPriceUSD, 12.50)
    }

    func testMigrationEnrichesBareRawRowOnlyWhenExactPrintingHasOneFinish() async throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 1_500)
        let row = makeRow(
            key: "magic:bare-migration-card",
            providerID: "bare-migration-card",
            quantity: 1,
            treatments: [],
            variant: nil
        )
        context.insert(row)
        try context.save()

        let response = try makeScryfallCard(
            id: "bare-migration-card",
            finishes: ["foil"],
            promoTypes: ["surgefoil"]
        )
        let report = await MagicTreatmentMigration.run(
            in: context,
            now: date
        ) { _ in response }

        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.rekeyedRows, 1)
        let migrated = try XCTUnwrap(
            context.fetch(FetchDescriptor<CollectedCard>()).first
        )
        XCTAssertEqual(
            migrated.collectionKey,
            "magic:bare-migration-card#foil#treatment=surgefoil"
        )
        XCTAssertEqual(migrated.variant, .foil)
        XCTAssertEqual(migrated.magicTreatmentIDsRaw, ["surgefoil"])
    }

    func testMigrationDoesNotGuessFinishForBareDualFinishRow() async throws {
        let context = try makeContext()
        let row = makeRow(
            key: "magic:bare-dual-finish",
            providerID: "bare-dual-finish",
            quantity: 1,
            treatments: [],
            variant: nil
        )
        context.insert(row)
        try context.save()

        let response = try makeScryfallCard(
            id: "bare-dual-finish",
            finishes: ["foil", "nonfoil"],
            promoTypes: ["surgefoil"]
        )
        let report = await MagicTreatmentMigration.run(in: context) { _ in response }

        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.rekeyedRows, 0)
        let retained = try XCTUnwrap(
            context.fetch(FetchDescriptor<CollectedCard>()).first
        )
        XCTAssertEqual(retained.collectionKey, "magic:bare-dual-finish")
        XCTAssertTrue(retained.magicTreatmentIDsRaw.isEmpty)
        XCTAssertEqual(
            retained.magicTreatmentMigrationVersion,
            MagicTreatmentMigration.currentVersion
        )
    }

    func testMigrationConsolidatesPreLedgerCollisionBeforePortfolioBaseline() async throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 1_750)
        let legacyKey = "magic:pre-ledger-collision#foil"
        let canonicalKey = "magic:pre-ledger-collision#foil#treatment=surgefoil"
        let legacy = makeRow(
            key: legacyKey,
            providerID: "pre-ledger-collision",
            quantity: 2,
            treatments: []
        )
        let canonical = makeRow(
            key: canonicalKey,
            providerID: "pre-ledger-collision",
            quantity: 1,
            treatments: [.surgeFoil]
        )
        context.insert(legacy)
        context.insert(canonical)
        context.insert(
            CollectionActivity(
                card: legacy,
                source: .scan,
                quantity: 2,
                occurredAt: date,
                kind: .added,
                deltaQuantity: 2
            )
        )
        context.insert(
            CollectionActivity(
                card: canonical,
                source: .scan,
                quantity: 1,
                occurredAt: date,
                kind: .added,
                deltaQuantity: 1
            )
        )
        try context.save()

        let response = try makeScryfallCard(
            id: "pre-ledger-collision",
            finishes: ["foil"],
            promoTypes: ["surgefoil"]
        )
        let report = await MagicTreatmentMigration.run(
            in: context,
            now: date
        ) { _ in response }

        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.mergedCollisions, 1)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CollectedCard>()).map(\.collectionKey),
            [canonicalKey]
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CollectedCard>()).first?.quantity,
            3
        )
        XCTAssertTrue(try context.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CollectionActivity>()).map(\.collectionKey),
            [canonicalKey, canonicalKey]
        )
    }

    func testMigrationDoesNotChooseBetweenTwoTreatmentDestinations() async throws {
        let context = try makeContext()
        let legacyKey = "magic:ambiguous-collision#foil"
        let surgeKey = "magic:ambiguous-collision#foil#treatment=surgefoil"
        let neonKey = "magic:ambiguous-collision#foil#treatment=neonink"
        let legacy = makeRow(
            key: legacyKey,
            providerID: "ambiguous-collision",
            quantity: 1,
            treatments: []
        )
        let surge = makeRow(
            key: surgeKey,
            providerID: "ambiguous-collision",
            quantity: 1,
            treatments: [.surgeFoil]
        )
        let neon = makeRow(
            key: neonKey,
            providerID: "ambiguous-collision",
            quantity: 1,
            treatments: [.neonInk]
        )
        context.insert(legacy)
        context.insert(surge)
        context.insert(neon)
        try context.save()

        let response = try makeScryfallCard(
            id: "ambiguous-collision",
            finishes: ["foil"],
            promoTypes: ["surgefoil"]
        )
        let report = await MagicTreatmentMigration.run(in: context) { _ in response }

        XCTAssertFalse(report.isComplete)
        XCTAssertEqual(report.mergedCollisions, 0)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CollectedCard>()).map(\.collectionKey).sorted(),
            [legacyKey, neonKey, surgeKey].sorted()
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CollectedCard>()).map(\.quantity),
            [1, 1, 1]
        )
    }

    func testMigrationMergesCanonicalAndLegacyRowsWithTwoCorrectionLegs() async throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 2_000)
        let legacyKey = "magic:collision-card#foil"
        let canonicalKey = "magic:collision-card#foil#treatment=surgefoil"
        let legacy = makeRow(key: legacyKey, quantity: 2, treatments: [])
        let canonical = makeRow(
            key: canonicalKey,
            quantity: 1,
            treatments: [.surgeFoil]
        )
        context.insert(legacy)
        context.insert(canonical)
        try appendLineage(for: legacy, quantity: 2, at: date, in: context)
        try appendLineage(for: canonical, quantity: 1, at: date, in: context)
        try context.save()

        let response = try makeScryfallCard(
            id: "collision-card",
            finishes: ["foil"],
            promoTypes: ["surgefoil"]
        )
        let report = await MagicTreatmentMigration.run(
            in: context,
            now: date
        ) { _ in response }

        XCTAssertEqual(report.mergedCollisions, 1)
        XCTAssertTrue(report.isComplete)

        let rows = try context.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.collectionKey, canonicalKey)
        XCTAssertEqual(rows.first?.quantity, 3)

        let events = try context.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(InventoryLedger.quantities(from: events), [canonicalKey: 3])
        XCTAssertEqual(
            events.filter { $0.kind == .correction }.map(\.leg).compactMap { $0 }.sorted {
                $0.rawValue < $1.rawValue
            },
            [.from, .to]
        )
        XCTAssertEqual(
            Set(events.filter { $0.kind == .correction }.map(\.priceStorageKey)),
            Set(["magic:collision-card:foil", canonicalKey.replacingOccurrences(of: "#", with: ":")])
        )

        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertEqual(
            CollectionActivity.integrityDefects(activities: activities, events: events),
            []
        )

        let retry = await MagicTreatmentMigration.run(in: context, now: date) { _ in response }
        XCTAssertTrue(retry.isComplete)
        XCTAssertEqual(retry.exactLookups, 0)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CollectedCard>()).first?.quantity,
            3
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<InventoryEvent>()).count, 4)
    }

    func testMigrationCompletesAPreviouslySyncedCorrectionLegWithoutDoubleCounting() async throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 2_500)
        let legacyKey = "magic:partial-collision#foil"
        let canonicalKey = "magic:partial-collision#foil#treatment=surgefoil"
        let legacy = makeRow(
            key: legacyKey,
            providerID: "partial-collision",
            quantity: 2,
            treatments: []
        )
        let canonical = makeRow(
            key: canonicalKey,
            providerID: "partial-collision",
            quantity: 1,
            treatments: [.surgeFoil]
        )
        context.insert(legacy)
        context.insert(canonical)
        try appendLineage(for: legacy, quantity: 2, at: date, in: context)
        try appendLineage(for: canonical, quantity: 1, at: date, in: context)

        let sourceIdentity = [
            legacy.game,
            legacy.collectionKey,
            legacy.providerID,
            legacy.itemKindRaw,
            legacy.certificationNumber ?? "-"
        ]
        .map { "\($0.utf8.count):\($0)" }
        .joined(separator: "|")
        let operationID = MagicTreatmentMigration.operationID(
            sourceRecordIdentity: sourceIdentity,
            oldKey: legacyKey,
            newKey: canonicalKey
        )
        let partial = InventoryLedger(context: context).record(
            collectionKey: legacyKey,
            priceStorageKey: legacy.priceKey,
            valuation: .unpriced,
            kind: .correction,
            source: .correction,
            deltaQuantity: -2,
            operationID: operationID,
            leg: .from,
            occurredAt: date
        )
        guard case .appended = partial else {
            throw NSError(domain: "MagicTreatmentMigrationTests", code: 3)
        }
        try context.save()

        let response = try makeScryfallCard(
            id: "partial-collision",
            finishes: ["foil"],
            promoTypes: ["surgefoil"]
        )
        let report = await MagicTreatmentMigration.run(in: context, now: date) { _ in response }

        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.mergedCollisions, 1)
        let rows = try context.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.quantity, 3)
        let events = try context.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(InventoryLedger.quantities(from: events), [canonicalKey: 3])
        XCTAssertEqual(events.filter { $0.kind == .correction }.count, 2)
    }

    func testMigrationTreatsSamePayloadCorrectionRetryAsIdempotent() async throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 2_750)
        let legacyKey = "magic:duplicate-correction#foil"
        let canonicalKey = "magic:duplicate-correction#foil#treatment=surgefoil"
        let legacy = makeRow(
            key: legacyKey,
            providerID: "duplicate-correction",
            quantity: 2,
            treatments: []
        )
        let canonical = makeRow(
            key: canonicalKey,
            providerID: "duplicate-correction",
            quantity: 1,
            treatments: [.surgeFoil]
        )
        context.insert(legacy)
        context.insert(canonical)
        try appendLineage(for: legacy, quantity: 2, at: date, in: context)
        try appendLineage(for: canonical, quantity: 1, at: date, in: context)

        let sourceIdentity = [
            legacy.game,
            legacy.collectionKey,
            legacy.providerID,
            legacy.itemKindRaw,
            legacy.certificationNumber ?? "-"
        ]
        .map { "\($0.utf8.count):\($0)" }
        .joined(separator: "|")
        let operationID = MagicTreatmentMigration.operationID(
            sourceRecordIdentity: sourceIdentity,
            oldKey: legacyKey,
            newKey: canonicalKey
        )
        let duplicateFrom = InventoryEvent(
            operationID: operationID,
            leg: .from,
            kind: .correction,
            source: .correction,
            collectionKey: legacyKey,
            priceStorageKey: legacy.priceKey,
            deltaQuantity: -2,
            occurredAt: date,
            valuation: .unpriced
        )
        let firstFrom = InventoryLedger(context: context).record(
            collectionKey: legacyKey,
            priceStorageKey: legacy.priceKey,
            valuation: .unpriced,
            kind: .correction,
            source: .correction,
            deltaQuantity: -2,
            operationID: operationID,
            leg: .from,
            occurredAt: date
        )
        guard case .appended = firstFrom else {
            throw NSError(domain: "MagicTreatmentMigrationTests", code: 4)
        }
        context.insert(duplicateFrom)
        try context.save()

        let response = try makeScryfallCard(
            id: "duplicate-correction",
            finishes: ["foil"],
            promoTypes: ["surgefoil"]
        )
        let report = await MagicTreatmentMigration.run(in: context, now: date) { _ in response }

        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.mergedCollisions, 1)
        XCTAssertEqual(
            InventoryLedger(context: context).read().defects,
            []
        )
        XCTAssertEqual(
            InventoryLedger.quantities(from: InventoryLedger(context: context).read().events),
            [canonicalKey: 3]
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<InventoryEvent>()).filter { $0.kind == .correction }.count,
            3
        )
    }

    func testCertifiedCollisionIsNotMergedOrRebalanced() async throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 3_000)
        let legacyKey = "graded:magic:certified-collision:variant:cert:1234"
        let canonicalKey = legacyKey + "#treatment=surgefoil"
        let legacy = makeRow(
            key: legacyKey,
            providerID: "certified-collision",
            quantity: 1,
            treatments: [],
            variant: nil,
            itemKind: .gradedCard,
            certificationNumber: "1234"
        )
        let canonical = makeRow(
            key: canonicalKey,
            providerID: "certified-collision",
            quantity: 1,
            treatments: [.surgeFoil],
            variant: nil,
            itemKind: .gradedCard,
            certificationNumber: "1234"
        )
        context.insert(legacy)
        context.insert(canonical)
        try appendLineage(for: legacy, quantity: 1, at: date, in: context)
        try appendLineage(for: canonical, quantity: 1, at: date, in: context)
        try context.save()

        let beforeEvents = try context.fetch(FetchDescriptor<InventoryEvent>())
        let response = try makeScryfallCard(
            id: "certified-collision",
            finishes: ["foil"],
            promoTypes: ["surgefoil"]
        )
        let report = await MagicTreatmentMigration.run(in: context, now: date) { _ in response }

        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.skippedCertifiedCollisions, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectedCard>()).count, 2)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CollectedCard>()).map(\.quantity).sorted(),
            [1, 1]
        )
        XCTAssertEqual(
            InventoryLedger.quantities(from: try context.fetch(FetchDescriptor<InventoryEvent>())),
            InventoryLedger.quantities(from: beforeEvents)
        )
    }

    func testMigrationClearsOnlyStaleTreatmentVendorNegatives() async throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 4_000)
        // The cleanup is part of the gated migration phase. Keep one pending
        // Magic row in the fixture so this test exercises that phase instead
        // of the steady-state no-op path.
        context.insert(
            makeRow(
                key: "magic:stale-negative-cleanup#foil",
                providerID: "stale-negative-cleanup",
                quantity: 1,
                treatments: []
            )
        )
        let treated = ProductIdentity(
            key: "magic:printing:foil:treatment=surgefoil",
            vendor: .justTCG,
            unmatchedAt: date,
            attemptVersion: 1,
            magicTreatmentIDs: ["surgefoil"]
        )
        let generic = ProductIdentity(
            key: "magic:printing:foil",
            vendor: .justTCG,
            unmatchedAt: date,
            attemptVersion: 1
        )
        context.insert(treated)
        context.insert(generic)
        try context.save()

        let report = await MagicTreatmentMigration.run(in: context, now: date)

        XCTAssertEqual(report.clearedVendorNegatives, 1)
        XCTAssertNil(treated.unmatchedAt)
        XCTAssertEqual(treated.attemptVersion, ProductIdentity.currentAttemptVersion)
        XCTAssertEqual(generic.unmatchedAt, date)
        XCTAssertEqual(generic.attemptVersion, 1)
    }

    func testSteadyStateMigrationLeavesTreatmentVendorNegativesUntouched() async throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 4_100)
        let currentRow = makeRow(
            key: "magic:steady-state-negative#foil",
            providerID: "steady-state-negative",
            quantity: 1,
            treatments: []
        )
        currentRow.magicTreatmentMigrationVersion = MagicTreatmentMigration.currentVersion
        let treated = ProductIdentity(
            key: "magic:steady-state:foil:treatment=surgefoil",
            vendor: .justTCG,
            unmatchedAt: date,
            attemptVersion: 1,
            magicTreatmentIDs: ["surgefoil"]
        )
        context.insert(currentRow)
        context.insert(treated)
        try context.save()

        let report = await MagicTreatmentMigration.runLocal(in: context, now: date)

        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.examinedRows, 0)
        XCTAssertEqual(report.clearedVendorNegatives, 0)
        XCTAssertEqual(treated.unmatchedAt, date)
        XCTAssertEqual(treated.attemptVersion, 1)
    }

    func testSlice9MigrationConvergesAcrossTwoDevicesWithoutChangingQuantity() async throws {
        let date = Date(timeIntervalSince1970: 4_500)
        let legacyKey = "magic:two-device-collision#foil"
        let canonicalKey = "magic:two-device-collision#foil#treatment=surgefoil"

        func seed(_ context: ModelContext) throws {
            let legacy = makeRow(
                key: legacyKey,
                providerID: "two-device-collision",
                quantity: 2,
                treatments: []
            )
            let canonical = makeRow(
                key: canonicalKey,
                providerID: "two-device-collision",
                quantity: 1,
                treatments: [.surgeFoil]
            )
            context.insert(legacy)
            context.insert(canonical)
            try appendLineage(for: legacy, quantity: 2, at: date, in: context)
            try appendLineage(for: canonical, quantity: 1, at: date, in: context)
            try context.save()
        }

        let deviceA = try makeContainer()
        let deviceB = try makeContainer()
        let contextA = deviceA.mainContext
        let contextB = deviceB.mainContext
        try seed(contextA)
        try seed(contextB)

        func quantityTotal(_ context: ModelContext) throws -> Int {
            let events = try context.fetch(FetchDescriptor<InventoryEvent>())
            return InventoryLedger.quantities(from: events).values.reduce(0, +)
        }

        XCTAssertEqual(try quantityTotal(contextA), 3)
        XCTAssertEqual(try quantityTotal(contextB), 3)

        let response = try makeScryfallCard(
            id: "two-device-collision",
            finishes: ["foil"],
            promoTypes: ["surgefoil"]
        )
        let reportA = await MagicTreatmentMigration.run(
            in: contextA,
            now: date
        ) { _ in response }
        let reportB = await MagicTreatmentMigration.run(
            in: contextB,
            now: date
        ) { _ in response }

        XCTAssertTrue(reportA.isComplete)
        XCTAssertTrue(reportB.isComplete)
        XCTAssertEqual(reportA.mergedCollisions, 1)
        XCTAssertEqual(reportB.mergedCollisions, 1)

        func correctionSignature(_ context: ModelContext) throws -> [String] {
            let events = try context.fetch(FetchDescriptor<InventoryEvent>())
                .filter { $0.kind == .correction }
                .sorted { ($0.legRaw ?? "") < ($1.legRaw ?? "") }
            XCTAssertEqual(events.count, 2)
            return events.map {
                [
                    $0.operationID.uuidString,
                    $0.idempotencyKey,
                    $0.legRaw ?? "-",
                    $0.collectionKey,
                    $0.priceStorageKey,
                    String($0.deltaQuantity),
                    String($0.occurredAt.timeIntervalSince1970)
                ].joined(separator: "|")
            }
        }

        XCTAssertEqual(
            try correctionSignature(contextA),
            try correctionSignature(contextB)
        )
        let correctionsA = try contextA.fetch(FetchDescriptor<InventoryEvent>())
            .filter { $0.kind == .correction }
        let correctionsB = try contextB.fetch(FetchDescriptor<InventoryEvent>())
            .filter { $0.kind == .correction }
        XCTAssertEqual(
            Set(correctionsA.map(\.operationID)),
            Set(correctionsB.map(\.operationID))
        )

        for context in [contextA, contextB] {
            let rows = try context.fetch(FetchDescriptor<CollectedCard>())
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows.first?.collectionKey, canonicalKey)
            XCTAssertEqual(rows.first?.quantity, 3)
            XCTAssertEqual(
                InventoryLedger.quantities(
                    from: try context.fetch(FetchDescriptor<InventoryEvent>())
                ),
                [canonicalKey: 3]
            )
            XCTAssertEqual(try quantityTotal(context), 3)
            XCTAssertTrue(
                CollectionActivity.integrityDefects(
                    activities: try context.fetch(FetchDescriptor<CollectionActivity>()),
                    events: try context.fetch(FetchDescriptor<InventoryEvent>())
                ).isEmpty
            )
        }

        let retry = await MagicTreatmentMigration.run(in: contextA, now: date) { _ in response }
        XCTAssertTrue(retry.isComplete)
        XCTAssertEqual(retry.exactLookups, 0)
        XCTAssertEqual(try contextA.fetch(FetchDescriptor<InventoryEvent>()).count, 4)
    }

    /// The local phase runs on the main actor before portfolio startup and has
    /// no suspension points across its planning loops, so a quadratic pass
    /// freezes launch outright for a large collection. The indexes that make it
    /// linear are invisible to every other test here: the biggest fixture is a
    /// few dozen rows, which a quadratic implementation handles just as well.
    ///
    /// The bound was chosen by measurement, not by feel: at this row count the
    /// indexed form takes ~0.25s and the per-row-scan form it replaced takes
    /// ~8.4s on the same simulator. 4s sits an order of magnitude above the
    /// former and comfortably below the latter, so it separates the two
    /// implementations rather than merely timing the machine.
    func testLocalMigrationPlanningScalesLinearly() async throws {
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 900)
        let rowCount = 4_000

        for index in 0..<rowCount {
            let id = String(format: "scale-card-%05d", index)
            context.insert(
                makeRow(
                    key: "magic:\(id)#foil",
                    providerID: id,
                    quantity: 1,
                    treatments: []
                )
            )
        }
        try context.save()

        let started = Date.now
        let report = await MagicTreatmentMigration.runLocal(in: context, now: date)
        let elapsed = Date.now.timeIntervalSince(started)

        XCTAssertEqual(report.examinedRows, rowCount)
        // No exact ids resolve locally, so this pass plans nothing and its cost
        // is entirely the planning loops under test.
        XCTAssertEqual(report.exactLookups, 0)
        XCTAssertLessThan(
            elapsed,
            4,
            "Local migration planning took \(elapsed)s for \(rowCount) rows, which indicates the per-row scans have returned."
        )
    }

    private func makeContext() throws -> ModelContext {
        let container = try makeContainer()
        self.container = container
        return container.mainContext
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CollectedCard.self,
            PriceRecord.self,
            ProductIdentity.self,
            ReferenceQuote.self,
            CollectionActivity.self,
            InventoryEvent.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeRow(
        key: String,
        providerID: String = "collision-card",
        quantity: Int,
        treatments: [MagicTreatment],
        variant: PhysicalVariant? = .foil,
        itemKind: CollectionItemKind = .rawCard,
        certificationNumber: String? = nil
    ) -> CollectedCard {
        let card = CollectedCard(
            collectionKey: key,
            game: .magic,
            providerID: providerID,
            name: "Fixture",
            setName: "Fixture Set",
            setCode: "FIC",
            cardNumber: "10",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: variant,
            variantResolution: .userConfirmed,
            quantity: quantity,
            magicTreatments: treatments
        )
        card.itemKindRaw = itemKind.rawValue
        card.certificationNumber = certificationNumber
        return card
    }

    private func appendLineage(
        for row: CollectedCard,
        quantity: Int,
        at date: Date,
        in context: ModelContext
    ) throws {
        let operationID = UUID()
        let outcome = InventoryLedger(context: context).record(
            row,
            kind: .acquire,
            source: .scan,
            deltaQuantity: quantity,
            operationID: operationID,
            occurredAt: date
        )
        guard case .appended = outcome else {
            throw NSError(domain: "MagicTreatmentMigrationTests", code: 2)
        }
        context.insert(
            CollectionActivity(
                card: row,
                source: .scan,
                quantity: quantity,
                occurredAt: date,
                kind: .added,
                deltaQuantity: quantity,
                ledgerOperationIDs: [operationID]
            )
        )
    }

    private func makeScryfallCard(
        id: String,
        finishes: [String],
        promoTypes: [String]
    ) throws -> ScryfallCard {
        let encodedFinishes = finishes.map { "\"\($0)\"" }.joined(separator: ",")
        let encodedPromos = promoTypes.map { "\"\($0)\"" }.joined(separator: ",")
        let json = """
        {
          "id": "\(id)",
          "name": "Fixture",
          "set": "fic",
          "set_name": "Fixture Set",
          "collector_number": "10",
          "lang": "en",
          "digital": false,
          "layout": "normal",
          "finishes": [\(encodedFinishes)],
          "promo_types": [\(encodedPromos)]
        }
        """
        return try JSONDecoder().decode(ScryfallCard.self, from: Data(json.utf8))
    }
}
