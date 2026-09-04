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
        variationOf: String? = nil
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

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            CollectedCard.self,
            PriceRecord.self,
            ProductIdentity.self,
            ReferenceQuote.self,
            CollectionActivity.self,
            InventoryEvent.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container.mainContext
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
