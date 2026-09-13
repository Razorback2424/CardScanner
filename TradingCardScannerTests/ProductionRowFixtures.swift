import Foundation
import SwiftData
@testable import TradingCardScanner

enum ProductionRowFixtureError: Error {
    case missingRow(String)
}

/// Shared fixtures for tests that need the same identity shape as collection
/// rows after their production constructor and catalog metadata paths run.
enum ProductionRowFixtures {
    static let pokemonPrintingID = "sv08.5-074"
    static let pokemonProductID = "p-uuid"
    static let pokemonProductVariantID = "v-uuid"

    static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: CollectedCard.self,
            PriceRecord.self,
            ProductIdentity.self,
            CollectionActivity.self,
            InventoryEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    static func pokemonCard() throws -> IdentifiedCard {
        let json = """
        {
          "id": "sv08.5-074", "localId": "074", "name": "Eevee",
          "image": "https://assets.tcgdex.net/en/sv/sv08.5/074",
          "set": { "id": "sv08.5", "name": "Prismatic Evolutions",
                   "cardCount": { "total": 180, "official": 131 } },
          "pricing": { "tcgplayer": {
            "normal": { "marketPrice": 0.42 },
            "reverse-holofoil": { "marketPrice": 3.75 }
          } }
        }
        """
        let card = try JSONDecoder().decode(
            TCGdexCard.self,
            from: Data(json.utf8)
        )
        return .pokemon(card, setCode: "PRE")
    }

    static func gradedRow(
        in context: ModelContext,
        certificationNumber: String = "REQ004-GRADED"
    ) throws -> CollectedCard {
        let store = CollectionStore(context: context)
        let mutation = try store.addGraded(
            underlying: try pokemonCard(),
            variant: GradedVariant(
                id: "REQ004-GRADED-VARIANT",
                cardID: "REQ004-GRADED-CARD",
                company: .psa,
                grade: CardGrade(value: "10", label: "Gem Mint"),
                marketPriceUSD: nil,
                updatedAt: nil
            ),
            certificationNumber: certificationNumber
        )
        return try row(for: mutation.collectionKey, in: context)
    }

    static func scannedGradedRow(
        in context: ModelContext,
        certificationNumber: String = "REQ004-SCANNED"
    ) throws -> CollectedCard {
        let store = CollectionStore(context: context)
        let mutation = try store.addScannedGraded(
            underlying: try pokemonCard(),
            company: .psa,
            grade: CardGrade(value: "9", label: "Mint"),
            certificationNumber: certificationNumber
        )
        return try row(for: mutation.collectionKey, in: context)
    }

    static func sealedRow(in context: ModelContext) throws -> CollectedCard {
        let product = SealedProductSummary(
            id: pokemonProductID,
            name: "Prismatic Evolutions Booster Box",
            setName: "Prismatic Evolutions",
            variantID: pokemonProductVariantID,
            marketPriceUSD: nil,
            updatedAt: nil,
            imageURL: nil
        )
        let store = CollectionStore(context: context)
        let mutation = try store.addSealed(product, game: .pokemon)
        let row = try row(for: mutation.collectionKey, in: context)

        // A sealed row written by addSealed carries its catalog identity in
        // justTCGCardID. The catalog-normalization step is the production path
        // that additionally fills catalogProviderID; use that same model method
        // here so shared identity fixtures cover the fully enriched row shape.
        row.applyCatalogMetadata(
            ImportedCatalogMetadata(
                providerID: product.id,
                setCode: "",
                rarity: nil,
                imageURL: product.imageURL?.absoluteString,
                thumbnailURL: nil,
                tcgplayerURL: nil,
                setReleaseOrder: 0,
                justTCGCardID: product.id,
                justTCGVariantID: product.variantID,
                justTCGAPIVersion: JustTCGV1Client.apiVersion
            )
        )
        try context.save()
        return row
    }

    private static func row(
        for collectionKey: String,
        in context: ModelContext
    ) throws -> CollectedCard {
        guard let row = try context.fetch(FetchDescriptor<CollectedCard>()).first(
            where: { $0.collectionKey == collectionKey }
        ) else {
            throw ProductionRowFixtureError.missingRow(collectionKey)
        }
        return row
    }
}
