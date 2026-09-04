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
        let catalog = try XCTUnwrap(
            [Bundle.main, Bundle(for: MagicTreatmentTests.self)]
                .lazy
                .compactMap { try? MagicTreatmentCatalogStore.bundled(bundle: $0) }
                .first
        )

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
