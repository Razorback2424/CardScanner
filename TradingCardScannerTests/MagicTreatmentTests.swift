import Foundation
import XCTest
@testable import TradingCardScanner

final class MagicTreatmentTests: XCTestCase {
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
