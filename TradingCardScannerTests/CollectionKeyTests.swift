import XCTest
@testable import TradingCardScanner

/// Covers the join between what a catalog publishes and the row a scan mutates.
final class CollectionKeyTests: XCTestCase {
    private func decodePokemon(variantsJSON: String?) throws -> TCGdexCard {
        let variants = variantsJSON.map { "\"variants\": \($0)," } ?? ""
        let json = """
        {
          "id": "sv08.5-074",
          "localId": "074",
          "name": "Eevee",
          "image": "https://assets.tcgdex.net/en/sv/sv08.5/074",
          "rarity": "Common",
          "set": { "id": "sv08.5", "name": "Prismatic Evolutions",
                   "cardCount": { "total": 180, "official": 131 } },
          \(variants)
          "pricing": { "tcgplayer": {
            "normal": { "marketPrice": 0.42 },
            "reverse-holofoil": { "marketPrice": 3.75 }
          } }
        }
        """
        return try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8))
    }

    private func decodeMagic() throws -> ScryfallCard {
        let json = """
        {
          "id": "3f0a1f52-0000-4000-8000-000000000001",
          "name": "Llanowar Elves",
          "set": "ecl",
          "set_name": "Eclipse",
          "collector_number": "218",
          "lang": "en",
          "digital": false,
          "frame": "2015",
          "rarity": "common",
          "finishes": ["nonfoil", "foil"],
          "image_uris": {
            "small": "https://cards.example/s.jpg",
            "normal": "https://cards.example/n.jpg"
          }
        }
        """
        return try JSONDecoder().decode(ScryfallCard.self, from: Data(json.utf8))
    }

    func testCatalogVariantsComeFromTheCatalogAlone() throws {
        let card = try decodePokemon(
            variantsJSON: #"{ "firstEdition": false, "holo": false, "normal": true, "reverse": true }"#
        )

        XCTAssertEqual(card.catalogVariants, [.normal, .reverse])
    }

    /// A record that omits variants is a catalog with nothing to say about
    /// finish, not a failed identification.
    func testMissingVariantsBlockDecodesToSilenceRatherThanThrowing() throws {
        let card = try decodePokemon(variantsJSON: nil)

        XCTAssertTrue(card.catalogVariants.isEmpty)
        XCTAssertEqual(
            VariantResolver.resolve(IdentifiedCard.pokemon(card, setCode: "PRE").variantEvidence),
            .resolved(ResolvedVariant(variant: nil, resolution: .catalogSilent))
        )
    }

    func testMarketPricesCarryTheVariantTheyBelongTo() throws {
        let card = IdentifiedCard.pokemon(
            try decodePokemon(variantsJSON: #"{ "firstEdition": false, "holo": false, "normal": true, "reverse": true }"#),
            setCode: "PRE"
        )

        XCTAssertEqual(
            card.marketPrices.map(\.variantID),
            [PhysicalVariant.normal.id, PhysicalVariant.reverse.id]
        )
    }

    /// A Master Ball copy and a plain reverse copy are different physical objects
    /// and must never share a quantity.
    func testVariantsGetSeparateCollectionRows() throws {
        let card = IdentifiedCard.pokemon(
            try decodePokemon(variantsJSON: #"{ "firstEdition": false, "holo": false, "normal": true, "reverse": true }"#),
            setCode: "PRE"
        )

        XCTAssertNotEqual(
            card.collectionKey(variant: .masterBall),
            card.collectionKey(variant: .reverse)
        )
        XCTAssertEqual(card.collectionKey(variant: .masterBall), "sv08.5-074#masterBall")
    }

    /// Collections built before finish resolution keep incrementing their row.
    func testUnknownVariantKeepsTheLegacyProviderKey() throws {
        let card = IdentifiedCard.pokemon(try decodePokemon(variantsJSON: nil), setCode: "PRE")

        XCTAssertEqual(card.collectionKey(variant: nil), "sv08.5-074")
    }

    func testMagicFinishesBecomePhysicalVariants() throws {
        let card = IdentifiedCard.magic(try decodeMagic())

        XCTAssertEqual(card.variantEvidence.catalogVariants, [.nonfoil, .foil])
        XCTAssertEqual(card.variantEvidence.setID, "ecl")
        XCTAssertEqual(card.collectionKey(variant: .foil), "magic:3f0a1f52-0000-4000-8000-000000000001#foil")
    }

    /// An unfamiliar finish must survive rather than be dropped: silently
    /// discarding one would make a multi-variant printing look unique.
    func testUnknownCatalogFinishIsCarriedThroughVerbatim() {
        let variant = PhysicalVariant.resolving("galaxyFoil")

        XCTAssertEqual(variant.id, "galaxyFoil")
        XCTAssertEqual(
            VariantResolver.resolve(
                VariantEvidence(game: .magic, setID: "ecl", cardNumber: "218", catalogVariants: [.foil, variant])
            ),
            .needsChoice(options: [.foil, variant], lockDidNotApply: nil)
        )
    }
}
