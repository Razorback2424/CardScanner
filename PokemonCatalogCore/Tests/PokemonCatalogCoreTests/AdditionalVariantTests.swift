import CryptoKit
import XCTest
@testable import PokemonCatalogCore

final class AdditionalVariantTests: XCTestCase {
    private func input() throws -> PokemonCatalogHumanInput {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let file = try JSONDecoder().decode(PokemonCatalogHumanInputFile.self,
            from: Data(contentsOf: root.appendingPathComponent("publisher/catalog-input.json")))
        let input = try XCTUnwrap(file.sets.first { $0.providerSetID == "svp" })
        return .init(providerSetID: input.providerSetID, recognitionKind: input.recognitionKind,
            printedPrefix: input.printedPrefix, catalogLocalIDPrefix: input.catalogLocalIDPrefix,
            localIDPadWidth: input.localIDPadWidth,
            additionalVariants: input.additionalVariants?.filter { $0.providerCardID == "svp-196" })
    }

    private func fixture(type: String = "lenticular", size: String = "jumbo") -> PokemonCatalogProviderFixture {
        let count = PokemonCatalogProviderCardCount(total: 1, official: 1)
        return .init(directory: [.init(id: "svp", name: "SV Promos", cardCount: count)], sets: [
            .init(id: "svp", name: "SV Promos", cards: [.init(id: "svp-196", localID: "196", name: "Charizard ex")],
                  releaseDate: "2025-01-01", cardCount: count)
        ], cards: [.init(id: "svp-196", localID: "196", name: "Charizard ex", setID: "svp", variantsDetailed: [
            .init(type: type, subtype: nil, stamp: nil, foil: nil, size: size, variantID: nil, languages: ["en"])
        ])])
    }

    func testSignedSupplementSurvivesBuilderFingerprintAndRoundTripWithProtectedClassification() throws {
        let input = try input()
        let now = Date(timeIntervalSince1970: 1_793_664_000)
        let before = try PokemonCatalogBuilder().build(.init(fixture: fixture(), humanInputs: [
            .init(providerSetID: "svp", recognitionKind: .promo, printedPrefix: "SVP",
                  catalogLocalIDPrefix: "", localIDPadWidth: 3)
        ], revision: 1, generatedAt: now))
        let after = try PokemonCatalogBuilder().build(.init(fixture: fixture(), activeRelease: before.release,
            humanInputs: [input], revision: 2, generatedAt: now))
        try PokemonCatalogCandidateValidator.validate(after)
        XCTAssertEqual(after.release.sets.first?.additionalVariants, input.additionalVariants)
        XCTAssertEqual(after.release.sets.first?.providerFingerprint, before.release.sets.first?.providerFingerprint)
        XCTAssertEqual(after.report.changeClass, .authority)
        let key = Curve25519.Signing.PrivateKey()
        let envelope = try PokemonCatalogSignatureVerifier.sign(release: after.release, privateKey: key, keyID: "fixture")
        let verified = try PokemonCatalogSignatureVerifier.verify(envelope: envelope, now: now,
            keys: [.init(id: "fixture", publicKey: key.publicKey)])
        XCTAssertEqual(verified.sets.first?.additionalVariants, input.additionalVariants)
        let omitted = try PokemonCatalogBuilder().build(.init(fixture: fixture(), activeRelease: after.release,
            humanInputs: [], revision: 3, generatedAt: now))
        XCTAssertEqual(omitted.release.sets.first?.additionalVariants, input.additionalVariants)
        let removed = try PokemonCatalogBuilder().build(.init(fixture: fixture(), activeRelease: after.release,
            humanInputs: [.init(providerSetID: "svp", recognitionKind: .promo, additionalVariants: [])],
            revision: 3, generatedAt: now))
        XCTAssertEqual(removed.release.sets.first?.additionalVariants, [])
        XCTAssertEqual(removed.report.changeClass, .authority)
    }

    func testJumboRequiresExactProviderObjectAndTwoIndependentEvidenceHosts() throws {
        let input = try input()
        let now = Date(timeIntervalSince1970: 1_793_664_000)
        for fixture in [fixture(type: "holo"), fixture(size: "standard")] {
            XCTAssertThrowsError(try PokemonCatalogBuilder().build(.init(fixture: fixture,
                humanInputs: [input], revision: 1, generatedAt: now)))
        }
        let bad = PokemonCatalogAdditionalVariant(providerCardID: "svp-196", canonicalName: "Charizard ex",
            variantID: "jumbo", providerType: "lenticular", evidenceURLs: [
                "https://example.com/first", "https://example.com/second"
            ])
        XCTAssertThrowsError(try PokemonCatalogBuilder().build(.init(fixture: fixture(), humanInputs: [
            .init(providerSetID: "svp", recognitionKind: .promo, printedPrefix: "SVP", catalogLocalIDPrefix: "",
                  localIDPadWidth: 3, additionalVariants: [bad])
        ], revision: 1, generatedAt: now)))
    }

    func testProtectedStampAndReplacementMetadataSurviveEncodingWithoutWeakeningObjectMatching() throws {
        let reviewed = PokemonCatalogAdditionalVariant(providerCardID: "svp-072", canonicalName: "Great Tusk ex",
            variantID: "jumbo", providerType: "holo", tcgplayerProductID: 666593,
            evidenceURLs: ["https://api.tcgdex.net/v2/en/cards/svp-072",
                           "https://mp-search-api.tcgplayer.com/v1/product/666593/details"], providerStamps: ["set-logo"])
        XCTAssertEqual(try JSONDecoder().decode(PokemonCatalogAdditionalVariant.self, from: JSONEncoder().encode(reviewed)), reviewed)
        for (stamp, size, language, expected) in [
            (["set-logo"], "jumbo", "en", true), (["horizons"], "jumbo", "en", false),
            (["set-logo"], "standard", "en", false), (["set-logo"], "jumbo", "ja", false),
            ([], "jumbo", "en", false)
        ] {
            XCTAssertEqual(reviewed.matchesProviderDetail(type: "holo", size: size, foil: nil,
                stamp: stamp, subtype: nil, languages: [language]), expected)
        }
        let replacement = PokemonCatalogAdditionalVariant(providerCardID: "svp-162", canonicalName: "Houndstone ex",
            variantID: "jumbo", providerType: "holo", tcgplayerProductID: 596423,
            evidenceURLs: reviewed.evidenceURLs, replacesProviderProductIDs: [791832])
        XCTAssertEqual(try JSONDecoder().decode(PokemonCatalogAdditionalVariant.self,
            from: JSONEncoder().encode(replacement)).replacesProviderProductIDs, [791832])
    }

    func testOrdinaryMinimumAndExclusionRoundTripAsProtectedAuthorityWithoutChangingProviderIdentity() throws {
        let evidence = ["https://api.tcgdex.net/v2/en/cards/svp-196", "https://www.pokemon.com/product-proof"]
        let minimum = PokemonCatalogAdditionalVariant(providerCardID: "svp-196", canonicalName: "Charizard ex",
            variantID: "holo", providerType: "holo", tcgplayerProductID: 641610,
            evidenceURLs: evidence, normalNeedsReview: true)
        let exclusion = PokemonCatalogAdditionalVariant(providerCardID: "svp-196", canonicalName: "Charizard ex",
            variantID: "pokemonStamp|cosmos|player-rewards-program|", providerType: "reverse",
            evidenceURLs: evidence, providerStamps: ["player-rewards-program"],
            excludedTCGplayerProductIDs: [651037], providerFoil: "cosmos")
        XCTAssertTrue(minimum.addsMembership)
        XCTAssertFalse(exclusion.addsMembership)
        XCTAssertTrue(exclusion.matchesProviderDetail(type: "reverse", size: "standard", foil: "cosmos",
            stamp: ["player-rewards-program"], subtype: nil, languages: ["en"]))
        for (size, stamp, language) in [("jumbo", ["player-rewards-program"], "en"),
                                       ("standard", [], "en"), ("standard", ["player-rewards-program"], "ja")] {
            XCTAssertFalse(exclusion.matchesProviderDetail(type: "reverse", size: size, foil: "cosmos",
                stamp: stamp, subtype: nil, languages: [language]))
        }
        let now = Date(timeIntervalSince1970: 1_793_664_000)
        let baseInput = PokemonCatalogHumanInput(providerSetID: "svp", recognitionKind: .promo,
            printedPrefix: "SVP", catalogLocalIDPrefix: "", localIDPadWidth: 3)
        let before = try PokemonCatalogBuilder().build(.init(fixture: fixture(type: "normal", size: "standard"),
            humanInputs: [baseInput], revision: 1, generatedAt: now))
        let after = try PokemonCatalogBuilder().build(.init(fixture: fixture(type: "normal", size: "standard"),
            activeRelease: before.release, humanInputs: [.init(providerSetID: "svp", recognitionKind: .promo,
                additionalVariants: [minimum, exclusion])], revision: 2, generatedAt: now))
        try PokemonCatalogCandidateValidator.validate(after)
        XCTAssertEqual(after.report.changeClass, .authority)
        XCTAssertEqual(before.release.sets.first?.providerFingerprint, after.release.sets.first?.providerFingerprint)
        let key = Curve25519.Signing.PrivateKey()
        let envelope = try PokemonCatalogSignatureVerifier.sign(release: after.release, privateKey: key, keyID: "fixture")
        let verified = try PokemonCatalogSignatureVerifier.verify(envelope: envelope, now: now,
            keys: [.init(id: "fixture", publicKey: key.publicKey)])
        XCTAssertEqual(verified.sets.first?.additionalVariants, [minimum, exclusion])
    }

    func testExclusionCannotAuthorizeMembershipBindAReplacementOrMislabelItsAxes() throws {
        let good = PokemonCatalogAdditionalVariant(providerCardID: "svp-196", canonicalName: "Charizard ex",
            variantID: "pokemonStamp|cosmos|player-rewards-program|", providerType: "reverse",
            evidenceURLs: ["https://api.tcgdex.net/card", "https://www.tcgplayer.com/product/651037"],
            providerStamps: ["player-rewards-program"], excludedTCGplayerProductIDs: [651037], providerFoil: "cosmos")
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(good)) as? [String: Any])
        for change in [
            ["tcgplayerProductID": 123], ["variantID": "cosmos"],
            ["excludedTCGplayerProductIDs": [-1]], ["excludedTCGplayerProductIDs": [651037, 651037]],
            ["normalNeedsReview": true], ["providerStamps": ["player-rewards-program|staff"]]
        ] as [[String: Any]] {
            let object = original.merging(change) { _, new in new }
            let bad = try JSONDecoder().decode(PokemonCatalogAdditionalVariant.self,
                from: JSONSerialization.data(withJSONObject: object))
            XCTAssertThrowsError(try PokemonCatalogBuilder().build(.init(fixture: fixture(), humanInputs: [
                .init(providerSetID: "svp", recognitionKind: .promo, printedPrefix: "SVP",
                    catalogLocalIDPrefix: "", localIDPadWidth: 3, additionalVariants: [bad])
            ], revision: 1, generatedAt: Date(timeIntervalSince1970: 1_793_664_000))), "\(change)")
        }
    }
}
