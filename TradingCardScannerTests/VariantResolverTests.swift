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

    private func identifiedPokemon(_ variants: [PhysicalVariant]) -> IdentifiedCard {
        let card = TCGdexCard(
            id: "sv03-053",
            localId: "053",
            name: "Pikachu ex",
            image: nil,
            rarity: nil,
            set: TCGdexSetBrief(
                id: "sv03",
                name: "Obsidian Flames",
                cardCount: TCGdexCardCount(total: 152, official: 152)
            ),
            variants: TCGdexVariants(
                firstEdition: variants.contains(.firstEdition),
                holo: variants.contains(.holo),
                normal: variants.contains(.normal),
                reverse: variants.contains(.reverse),
                wPromo: nil
            ),
            pricing: nil,
            variantsDetailed: nil
        )
        return .pokemon(card, setCode: "OBF")
    }

    func testResolutionCertaintyDoesNotReuseAutomaticRevisitSemantics() {
        XCTAssertTrue(VariantResolution.uniqueInCatalog.isAutomatic)
        XCTAssertEqual(VariantResolution.uniqueInCatalog.certainty, .catalogCertain)
        XCTAssertTrue(VariantResolution.catalogSilent.isAutomatic)
        XCTAssertEqual(VariantResolution.catalogSilent.certainty, .unresolved)
        XCTAssertFalse(VariantResolution.userConfirmed.isAutomatic)
        XCTAssertEqual(VariantResolution.userConfirmed.certainty, .userConfirmed)
    }

    func testPokemonFinishReconciliationRepairsOnlyUnambiguousAutomaticOrUnknownRows() {
        let holoOnly = identifiedPokemon([.holo])
        XCTAssertEqual(
            PokemonFinishReconciliation.repair(
                storedVariantID: PhysicalVariant.normal.id,
                storedResolution: .uniqueInCatalog,
                itemKind: .rawCard,
                printRun: nil,
                card: holoOnly
            ),
            ResolvedVariant(variant: .holo, resolution: .uniqueInCatalog)
        )

        let normalOnly = identifiedPokemon([.normal])
        XCTAssertEqual(
            PokemonFinishReconciliation.repair(
                storedVariantID: nil,
                storedResolution: nil,
                itemKind: .rawCard,
                printRun: nil,
                card: normalOnly
            ),
            ResolvedVariant(variant: .normal, resolution: .uniqueInCatalog)
        )
        XCTAssertEqual(
            PokemonFinishReconciliation.repair(
                storedVariantID: nil,
                storedResolution: .catalogSilent,
                itemKind: .rawCard,
                printRun: nil,
                card: normalOnly
            ),
            ResolvedVariant(variant: .normal, resolution: .uniqueInCatalog)
        )

        XCTAssertNil(
            PokemonFinishReconciliation.repair(
                storedVariantID: PhysicalVariant.normal.id,
                storedResolution: nil,
                itemKind: .rawCard,
                printRun: nil,
                card: holoOnly
            ),
            "A legacy finish without provenance may have been selected by the user"
        )
        for resolution in [
            VariantResolution.userConfirmed,
            .finishLock,
            .printedLabel,
            .imported
        ] {
            XCTAssertNil(
                PokemonFinishReconciliation.repair(
                    storedVariantID: PhysicalVariant.normal.id,
                    storedResolution: resolution,
                    itemKind: .rawCard,
                    printRun: nil,
                    card: holoOnly
                )
            )
        }

        XCTAssertNil(
            PokemonFinishReconciliation.repair(
                storedVariantID: PhysicalVariant.normal.id,
                storedResolution: .uniqueInCatalog,
                itemKind: .rawCard,
                printRun: nil,
                card: identifiedPokemon([.normal, .reverse])
            ),
            "Multiple possible finishes must remain unresolved"
        )
        XCTAssertNil(
            PokemonFinishReconciliation.repair(
                storedVariantID: PhysicalVariant.normal.id,
                storedResolution: .uniqueInCatalog,
                itemKind: .rawCard,
                printRun: nil,
                card: identifiedPokemon([.normal])
            ),
            "A finish that remains valid is not a repair"
        )
        XCTAssertNil(
            PokemonFinishReconciliation.repair(
                storedVariantID: PhysicalVariant.normal.id,
                storedResolution: .uniqueInCatalog,
                itemKind: .gradedCard,
                printRun: nil,
                card: holoOnly
            )
        )
    }

    func testPokemonFinishReconciliationSkipsSpecialRunsAndNonPokemonCards() throws {
        let cardWithFirstEditionPseudoFinish = identifiedPokemon([.firstEdition, .holo])
        for printRun in [PokemonPrintRun.firstEdition, .shadowless] {
            XCTAssertNil(
                PokemonFinishReconciliation.repair(
                    storedVariantID: PhysicalVariant.normal.id,
                    storedResolution: .uniqueInCatalog,
                    itemKind: .rawCard,
                    printRun: printRun,
                    card: cardWithFirstEditionPseudoFinish
                )
            )
        }
        XCTAssertEqual(
            PokemonFinishReconciliation.repair(
                storedVariantID: PhysicalVariant.normal.id,
                storedResolution: .uniqueInCatalog,
                itemKind: .rawCard,
                printRun: .unlimited,
                card: cardWithFirstEditionPseudoFinish
            ),
            ResolvedVariant(variant: .holo, resolution: .uniqueInCatalog)
        )

        let json = #"{"id":"11111111-1111-4111-8111-111111111111","name":"Fixture","set":"abc","set_name":"Fixture Set","collector_number":"1","lang":"en","digital":false,"finishes":["nonfoil","foil"]}"#
        let magic = IdentifiedCard.magic(
            try JSONDecoder().decode(ScryfallCard.self, from: Data(json.utf8))
        )
        XCTAssertNil(
            PokemonFinishReconciliation.repair(
                storedVariantID: "nonfoil",
                storedResolution: .uniqueInCatalog,
                itemKind: .rawCard,
                printRun: nil,
                card: magic
            )
        )
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
            "Finish unconfirmed"
        )
        XCTAssertEqual(
            VariantProvenancePresentation.text(
                finish: "Holofoil",
                resolution: .userConfirmed
            ),
            "Holofoil · You confirmed"
        )
    }

    func testReceiptCallsOutOnlyFinishesThatNeedAPerson() {
        XCTAssertFalse(VariantProvenancePresentation.needsAttention(finish: "Holo", resolution: .uniqueInCatalog))
        XCTAssertFalse(VariantProvenancePresentation.needsAttention(finish: "Foil Etched", resolution: nil))
        XCTAssertTrue(VariantProvenancePresentation.needsAttention(finish: nil, resolution: nil))
        XCTAssertTrue(VariantProvenancePresentation.needsAttention(finish: nil, resolution: .catalogSilent))
        XCTAssertTrue(VariantProvenancePresentation.needsAttention(finish: "Holofoil", resolution: .userConfirmed))
        XCTAssertEqual(VariantProvenancePresentation.text(finish: "Foil Etched", resolution: nil), "Foil Etched")
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
            "Finish unconfirmed"
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

    func testOnePieceFinishLockRequiresExactIDAndReturnsCatalogFinish() {
        let reviewedFoil = PhysicalVariant(id: "foil", label: "Reviewed Foil")
        let evidence = VariantEvidence(
            game: .onePiece, setID: "reviewed-release", cardNumber: "OP01-120",
            catalogVariants: [.normal, reviewedFoil]
        )
        let otherFinish = VariantLock(finish: PhysicalVariant(id: "Foil", label: "Other finish"))
        guard case .needsChoice(_, let rejectedLock) = VariantResolver.resolve(evidence, finishLock: otherFinish) else {
            return XCTFail("A different case-sensitive finish ID must not select this printing's foil")
        }
        XCTAssertEqual(rejectedLock, otherFinish)
        XCTAssertEqual(
            VariantResolver.resolve(evidence, finishLock: VariantLock(finish: .foil)),
            .resolved(ResolvedVariant(variant: reviewedFoil, resolution: .finishLock))
        )
    }

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

    func testBallPatternsUseExactEligibilityRatherThanEveryReverseHolo() {
        for (set, number) in [("sv08.5", "093"), ("sv10.5b", "079"), ("sv10.5w", "086")] {
            let evidence = pokemon(setID: set, variants: [.normal, .reverse], number: number)
            let options = VariantResolver.options(for: evidence)
            XCTAssertTrue(options.contains(.pokeBall))
            XCTAssertFalse(options.contains(.masterBall))
            guard case .needsChoice(_, let rejected) = VariantResolver.resolve(evidence, finishLock: .masterBall) else {
                return XCTFail("An ineligible Master Ball lock cannot select a finish")
            }
            XCTAssertEqual(rejected?.finish, .masterBall)
        }
        for number in ["006", "119", "131", "001a", "999"] {
            XCTAssertEqual(Set(VariantResolver.options(for: pokemon(setID: "sv08.5",
                variants: [.normal, .reverse], number: number))), Set([.normal, .reverse]))
        }
        XCTAssertEqual(VariantResolver.options(for: pokemon(setID: "sv08.5", variants: [.reverse], number: "1")),
                       VariantResolver.options(for: pokemon(setID: "sv08.5", variants: [.reverse], number: "001")))
        // An additive fallback must not erase newer exact provider evidence.
        XCTAssertTrue(VariantResolver.options(for: pokemon(setID: "sv08.5",
            variants: [.reverse, .masterBall], number: "093")).contains(.masterBall))
    }

    func testExactBallPatternInventoriesHaveAll471Slots() {
        let expected = ["sv08.5": ["pokeBall": 100, "masterBall": 67],
                        "sv10.5b": ["pokeBall": 80, "masterBall": 72],
                        "sv10.5w": ["pokeBall": 80, "masterBall": 72]]
        for (set, counts) in expected {
            for (variant, count) in counts {
                XCTAssertEqual((1...180).filter { number in
                    VariantResolver.options(for: pokemon(setID: set, variants: [.reverse], number: String(number)))
                        .contains(where: { $0.id == variant })
                }.count, count, "\(set) \(variant)")
            }
        }
    }

    func testBrowseSlotsAndScannerShareExactParallelEligibility() throws {
        let card = try JSONDecoder().decode(TCGdexCard.self, from: Data(#"""
        {"id":"sv08.5-093","localId":"093","name":"Amarys",
         "set":{"id":"sv08.5","name":"Prismatic Evolutions","cardCount":{"total":180,"official":131}},
         "variants":{"firstEdition":false,"holo":false,"normal":true,"reverse":true},
         "variants_detailed":[{"type":"reverse","foil":"masterball","languages":["ja"],"size":"standard"},
                                {"type":"holo","foil":"cosmos","languages":["en"],"size":"jumbo"},
                                {"type":"reverse","foil":"pokeball","languages":["ja"],"size":"standard","thirdParty":{"tcgplayer":11}},
                                {"type":"reverse","foil":"pokeball","languages":["en"],"size":"standard","thirdParty":{"tcgplayer":99}}]}
        """#.utf8))
        XCTAssertEqual(Set(PokemonMasterSetDefinition.requiredVariants(for: card).map(\.variant)),
                       Set([.normal, .reverse, .pokeBall]))
        XCTAssertEqual(Set(VariantResolver.options(for: IdentifiedCard.pokemon(card, setCode: "PRE").variantEvidence)),
                       Set([.normal, .reverse, .pokeBall]))
        XCTAssertNil(card.detailedVariant(for: .masterBall))
        XCTAssertNil(card.detailedVariant(for: PhysicalVariant.pokemonFoilPattern("cosmos")))
        XCTAssertEqual(card.detailedVariant(for: .pokeBall)?.thirdParty?.tcgplayer, 99)
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

    func testFinishLockSelectsExactUnstampedVariantAlongsideSupplementalStampedRelease() {
        let outcome = VariantResolver.resolve(
            pokemon(setID: "swsh11", variants: [.holo, .reverse], number: "066"),
            finishLock: .holo
        )
        XCTAssertEqual(outcome, .resolved(ResolvedVariant(variant: .holo, resolution: .finishLock)))
    }

    func testLilliesDeterminationNormalLockResolvesAlongsideCatalogStampsAndPatterns() throws {
        let prizePack = try XCTUnwrap(PokemonCatalogStampVariant.make(base: .normal, stamps: ["prize-pack"]))
        let regional = try XCTUnwrap(PokemonCatalogStampVariant.make(base: .normal, stamps: ["regional-championships"]))
        let staff = try XCTUnwrap(PokemonCatalogStampVariant.make(base: .normal, stamps: ["regional-championships", "staff"]))
        let evidence = pokemon(
            setID: "me01", variants: [.reverse, .normal, .holo, .pokemonFoilPattern("cosmos"), prizePack, regional, staff],
            number: "119"
        )

        XCTAssertEqual(
            VariantResolver.resolve(evidence, finishLock: .normal),
            .resolved(ResolvedVariant(variant: .normal, resolution: .finishLock))
        )
        guard case let .needsChoice(options, _) = VariantResolver.resolve(evidence) else {
            return XCTFail("Auto should retain all seven physical variants")
        }
        XCTAssertEqual(Set(options), Set(evidence.catalogVariants))
    }

    func testFinishLockDoesNotMatchStampedBaseWhenPlainFinishIsUnavailable() throws {
        let prizePack = try XCTUnwrap(PokemonCatalogStampVariant.make(base: .normal, stamps: ["prize-pack"]))
        let regional = try XCTUnwrap(PokemonCatalogStampVariant.make(base: .normal, stamps: ["regional-championships"]))
        let evidence = pokemon(setID: "me01", variants: [prizePack, regional], number: "119")
        guard case let .needsChoice(options, rejected) = VariantResolver.resolve(evidence, finishLock: .normal) else {
            return XCTFail("Normal must never substitute for a stamped Normal variant")
        }
        XCTAssertEqual(Set(options), [prizePack, regional])
        XCTAssertEqual(rejected, VariantLock(finish: .normal))
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
