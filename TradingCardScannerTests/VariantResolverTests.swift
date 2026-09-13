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

    func testResolutionCertaintyDoesNotReuseAutomaticRevisitSemantics() {
        XCTAssertTrue(VariantResolution.uniqueInCatalog.isAutomatic)
        XCTAssertEqual(VariantResolution.uniqueInCatalog.certainty, .catalogCertain)
        XCTAssertTrue(VariantResolution.catalogSilent.isAutomatic)
        XCTAssertEqual(VariantResolution.catalogSilent.certainty, .unresolved)
        XCTAssertFalse(VariantResolution.userConfirmed.isAutomatic)
        XCTAssertEqual(VariantResolution.userConfirmed.certainty, .userConfirmed)
    }

    func testReceiptProminenceKeepsRoutineCatalogAnswersQuiet() {
        XCTAssertEqual(VariantResolution.uniqueInCatalog.receiptProminence, .quiet)
        XCTAssertEqual(VariantResolution.deterministicSetRule.receiptProminence, .quiet)
        XCTAssertEqual(VariantResolution.finishLock.receiptProminence, .attention)
        XCTAssertEqual(VariantResolution.userConfirmed.receiptProminence, .attention)
        XCTAssertEqual(VariantResolution.catalogSilent.receiptProminence, .attention)
    }

    func testProvenancePresentationStatesFinishAndEvidence() {
        XCTAssertEqual(
            VariantProvenancePresentation.text(
                finish: "Reverse Holo",
                resolution: .uniqueInCatalog
            ),
            "Reverse Holo · Only variant printed"
        )
        XCTAssertEqual(
            VariantProvenancePresentation.text(
                finish: nil,
                resolution: .catalogSilent
            ),
            "Finish not published"
        )
        XCTAssertEqual(
            VariantProvenancePresentation.text(
                finish: "Holofoil",
                resolution: .userConfirmed
            ),
            "Holofoil · You confirmed"
        )
    }

    func testUncertaintyNeverHardensWhenItCrossesIntoTheScanReceipt() throws {
        let outcome = VariantResolver.resolve(pokemon(setID: "sv03", variants: []))
        guard case let .resolved(resolved) = outcome else {
            return XCTFail("Catalog silence should still produce a receipt, not a guessed variant")
        }

        XCTAssertNil(resolved.variant)
        XCTAssertEqual(resolved.resolution, .catalogSilent)
        XCTAssertEqual(resolved.resolution.certainty, .unresolved)

        let receipt = ScanReceipt(
            scanID: UUID(),
            name: "Eevee",
            identifier: "PRE 074",
            variantLabel: "Finish unknown",
            treatmentDiagnostics: [],
            thumbnailURL: nil,
            resolution: resolved.resolution
        )
        XCTAssertNil(resolved.variant)
        XCTAssertEqual(receipt.resolution?.certainty, .unresolved)
        XCTAssertEqual(
            VariantProvenancePresentation.text(
                finish: receipt.variantLabel,
                resolution: receipt.resolution
            ),
            "Finish not published"
        )
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

    func testSingleCatalogVariantWinsOverAConflictingPrintedLabel() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "sv03", variants: [.holo]),
            printedFinish: .reverse
        )

        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .holo, resolution: .uniqueInCatalog)))
    }

    func testPrintedLabelDisagreementFallsBackToCatalogOptions() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "sv03", variants: [.holo]),
            printedFinish: .reverse
        )

        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .holo, resolution: .uniqueInCatalog)))
    }

    func testPrintedLabelDisagreementLeavesMultipleCatalogOptionsForTheUser() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "sv03", variants: [.normal, .holo]),
            printedFinish: .reverse
        )

        XCTAssertEqual(outcome, .needsChoice(options: [.normal, .holo], lockDidNotApply: nil))
    }

    func testPrintedLabelCanResolveOnlyAfterTheCatalogLeavesMultipleUnstampedOptions() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "sv03", variants: [.normal, .holo]),
            printedFinish: .holo
        )

        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .holo, resolution: .printedLabel)))
    }

    func testFinishLockWinsOverAConflictingPrintedLabel() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "sv03", variants: [.normal, .holo]),
            finishLock: .normal,
            printedFinish: .holo
        )

        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .normal, resolution: .finishLock)))
    }

    func testPrintedLabelCannotSilentlyAnswerAStampedVariantQuestion() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "swsh11", variants: [.holo, .reverse], number: "066"),
            printedFinish: .holo
        )

        guard case let .needsChoice(options, lockDidNotApply) = outcome else {
            return XCTFail("A printed finish must not dismiss a catalog stamp choice")
        }
        XCTAssertNil(lockDidNotApply)
        XCTAssertTrue(options.contains { $0.id == "trickOrTrade2023Holofoil" })
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

        XCTAssertEqual(
            outcome,
            .needsChoice(
                options: [.reverse, .normal],
                lockDidNotApply: MagicFinishLock(finish: .masterBall)
            )
        )
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

    func testSerializedStampedVariantKeepsItsReadableLabel() throws {
        let detailed = try JSONDecoder().decode(
            TCGdexDetailedVariant.self,
            from: Data(#"{"type":"reverse","foil":"pokemonStamp|holo|set-logo|"}"#.utf8)
        )

        XCTAssertEqual(detailed.physicalVariant?.id, "pokemonStamp|holo|set-logo|")
        XCTAssertEqual(detailed.physicalVariant?.label, "Holo · Set Logo")
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

    func testMagicFinishLockMenuIsNarrowAndTreatmentAware() {
        let magicLocks = MagicFinishLock.selectable(for: .magic)
        XCTAssertEqual(
            magicLocks.map(\.label),
            ["Nonfoil", "Foil", "Etched Foil", "Surge Foil", "Neon Ink"]
        )
        XCTAssertEqual(
            magicLocks.map(\.id),
            [
                "nonfoil",
                "foil",
                "etched",
                "foil#treatment=surgefoil",
                "foil#treatment=neonink"
            ]
        )

        XCTAssertEqual(
            MagicFinishLock.selectable(for: .pokemon).map(\.finish),
            PhysicalVariant.selectable(for: .pokemon)
        )
        XCTAssertTrue(
            magicLocks.contains {
                $0.finish == .foil && $0.treatment == .surgeFoil
            }
        )
        for lock in magicLocks.compactMap({ $0.treatment }) {
            XCTAssertEqual(
                magicLocks.first(where: { $0.treatment == lock })?.finish,
                lock.requiredFinishes.first,
                "Treatment locks should derive their physical finish from the treatment"
            )
        }
    }

    func testMagicTreatmentLockRequiresMatchingEvidenceAndPhysicalFinish() {
        let lock = MagicFinishLock(finish: .foil, treatment: .surgeFoil)
        let dualFinishEvidence = VariantEvidence(
            game: .magic,
            setID: "fic",
            cardNumber: "10",
            catalogVariants: [.nonfoil, .foil],
            magicTreatments: [.surgeFoil]
        )

        XCTAssertEqual(
            VariantResolver.resolve(dualFinishEvidence, finishLock: lock),
            .resolved(ResolvedVariant(variant: .foil, resolution: .finishLock))
        )

        let missingTreatment = VariantEvidence(
            game: .magic,
            setID: "fic",
            cardNumber: "10",
            catalogVariants: [.nonfoil, .foil]
        )
        XCTAssertEqual(
            VariantResolver.resolve(missingTreatment, finishLock: lock),
            .needsChoice(options: [.nonfoil, .foil], lockDidNotApply: lock)
        )

        let wrongFinish = VariantEvidence(
            game: .magic,
            setID: "fic",
            cardNumber: "10",
            catalogVariants: [.nonfoil],
            magicTreatments: [.surgeFoil]
        )
        XCTAssertEqual(
            VariantResolver.resolve(wrongFinish, finishLock: lock),
            .resolved(ResolvedVariant(variant: .nonfoil, resolution: .uniqueInCatalog))
        )

        let differentTreatment = VariantEvidence(
            game: .magic,
            setID: "fic",
            cardNumber: "10",
            catalogVariants: [.nonfoil, .foil],
            magicTreatments: [.neonInk]
        )
        XCTAssertEqual(
            VariantResolver.resolve(differentTreatment, finishLock: lock),
            .needsChoice(options: [.nonfoil, .foil], lockDidNotApply: lock)
        )
    }

    func testMagicTreatmentLockReportsNonApplicationWhenTheCatalogIsSilent() {
        let lock = MagicFinishLock(finish: .foil, treatment: .surgeFoil)
        let evidence = VariantEvidence(
            game: .magic,
            setID: "unknown",
            cardNumber: "1",
            catalogVariants: [],
            magicTreatments: [.surgeFoil]
        )

        XCTAssertEqual(
            VariantResolver.resolve(evidence, finishLock: lock),
            .resolved(ResolvedVariant(variant: nil, resolution: .catalogSilent))
        )
    }

    func testMagicTreatmentLockDoesNotApplyAcrossGameBoundaries() {
        let lock = MagicFinishLock(finish: .holo, treatment: .surgeFoil)
        let evidence = VariantEvidence(
            game: .pokemon,
            setID: "sv08.5",
            cardNumber: "1",
            catalogVariants: [.normal, .holo],
            magicTreatments: [.surgeFoil]
        )

        XCTAssertEqual(
            VariantResolver.resolve(evidence, finishLock: lock),
            .needsChoice(options: [.normal, .holo], lockDidNotApply: lock)
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
