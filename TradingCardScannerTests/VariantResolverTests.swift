import XCTest
@testable import TradingCardScanner

final class VariantResolverTests: XCTestCase {
    private func pokemon(
        setID: String,
        variants: [PhysicalVariant],
        number: String = "074"
    ) -> VariantEvidence {
        VariantEvidence(game: .pokemon, setID: setID, cardNumber: number, catalogVariants: variants)
    }

    // MARK: - Zero friction where the app can already know

    func testSingleCatalogVariantResolvesWithoutAsking() {
        let outcome = VariantResolver.resolve(pokemon(setID: "sv03", variants: [.holo]))

        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .holo, resolution: .uniqueInCatalog)))
    }

    func testCatalogWithNothingToSayRecordsUnknownRatherThanGuessing() {
        let outcome = VariantResolver.resolve(pokemon(setID: "sv03", variants: []))

        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: nil, resolution: .catalogSilent)))
    }

    // MARK: - One tap where the human holds the missing fact

    func testTwoPossibleVariantsAskWithTheLikelierOptionFirst() {
        let outcome = VariantResolver.resolve(pokemon(setID: "sv03", variants: [.normal, .reverse]))

        XCTAssertEqual(outcome, .needsChoice(options: [.reverse, .normal], lockDidNotApply: nil))
    }

    // MARK: - Finish Lock is evidence, not an override

    func testFinishLockResolvesWhenTheCatalogAgreesItIsPossible() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "sv03", variants: [.normal, .reverse]),
            finishLock: .reverse
        )

        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .reverse, resolution: .finishLock)))
    }

    func testFinishLockNeverInventsAVariantThePrintingDoesNotHave() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "sv03", variants: [.normal, .reverse]),
            finishLock: .masterBall
        )

        XCTAssertEqual(outcome, .needsChoice(options: [.reverse, .normal], lockDidNotApply: .masterBall))
    }

    func testFinishLockDoesNotOverrideAPrintingThatOnlyExistsOneWay() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "sv03", variants: [.holo]),
            finishLock: .reverse
        )

        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .holo, resolution: .uniqueInCatalog)))
    }

    // MARK: - The supplemental rules layer

    func testBallPatternSetOffersThePatternsTheCatalogDoesNotModel() {
        let outcome = VariantResolver.resolve(pokemon(setID: "sv08.5", variants: [.normal, .reverse]))

        XCTAssertEqual(
            outcome,
            .needsChoice(options: [.reverse, .normal, .pokeBall, .masterBall], lockDidNotApply: nil)
        )
    }

    func testBallPatternRuleDoesNotFireWithoutAReverseHoloPrinting() {
        let outcome = VariantResolver.resolve(pokemon(setID: "sv08.5", variants: [.holo]))

        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .holo, resolution: .uniqueInCatalog)))
    }

    func testOrdinarySetsAreUntouchedByTheRulesLayer() {
        let outcome = VariantResolver.resolve(pokemon(setID: "sv03", variants: [.normal, .reverse]))

        guard case let .needsChoice(options, _) = outcome else {
            return XCTFail("Expected a choice")
        }
        XCTAssertFalse(options.contains(.masterBall))
        XCTAssertFalse(options.contains(.pokeBall))
    }

    func testMasterBallLockOnABallPatternSetRemovesTheTap() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "sv08.5", variants: [.normal, .reverse]),
            finishLock: .masterBall
        )

        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .masterBall, resolution: .finishLock)))
    }

    // MARK: - Stamped releases

    func testLostOriginGengarOffersItsExactStampedRelease() throws {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "swsh11", variants: [.holo, .reverse], number: "066")
        )
        guard case let .needsChoice(options, _) = outcome else {
            return XCTFail("Stamped eligibility must remain a user choice")
        }

        let stamped = try XCTUnwrap(options.first { $0.id == "trickOrTrade2023Holofoil" })
        XCTAssertEqual(stamped.label, "Stamped (2023)")
        XCTAssertEqual(
            PokemonStampedReleaseCatalog.entries(providerID: "swsh11-066").first?.tcgplayerProductID,
            "515661"
        )
        XCTAssertEqual(ProductFinish.printing(for: stamped), "Holofoil")
    }

    func testStampedPickerIsNotOfferedToSameNumberInAnotherSet() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "different", variants: [.holo], number: "066")
        )
        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .holo, resolution: .uniqueInCatalog)))
    }

    func testFinishLockCannotSilentlyDismissAStampedRelease() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "swsh11", variants: [.holo, .reverse], number: "066"),
            finishLock: .holo
        )
        guard case let .needsChoice(options, _) = outcome else {
            return XCTFail("A finish lock is not evidence that the stamp is absent")
        }
        XCTAssertTrue(options.contains { $0.id == "trickOrTrade2023Holofoil" })
    }

    func testStampedCatalogHasOneExactMarketplaceProductPerDocumentedCard() {
        XCTAssertEqual(PokemonStampedReleaseCatalog.entries.count, 90)
        XCTAssertEqual(
            Set(PokemonStampedReleaseCatalog.entries.map(\.tcgplayerProductID)).count,
            PokemonStampedReleaseCatalog.entries.count
        )
        XCTAssertTrue(PokemonStampedReleaseCatalog.entries.allSatisfy {
            !$0.providerID.isEmpty
                && Int($0.tcgplayerProductID) != nil
                && ["Normal", "Holofoil"].contains($0.printing)
        })
    }

    // MARK: - Magic

    func testMagicFinishesComeStraightFromTheCatalog() {
        let evidence = VariantEvidence(
            game: .magic,
            setID: "ecl",
            cardNumber: "218",
            catalogVariants: [.nonfoil, .foil]
        )

        XCTAssertEqual(
            VariantResolver.resolve(evidence),
            .needsChoice(options: [.nonfoil, .foil], lockDidNotApply: nil)
        )
    }

    func testPokemonRulesNeverApplyToMagic() {
        // A Magic set code could collide with a Pokémon set id in a naive table.
        let evidence = VariantEvidence(
            game: .magic,
            setID: "sv08.5",
            cardNumber: "218",
            catalogVariants: [.nonfoil, .foil]
        )

        guard case let .needsChoice(options, _) = VariantResolver.resolve(evidence) else {
            return XCTFail("Expected a choice")
        }
        XCTAssertEqual(options, [.nonfoil, .foil])
    }
}
