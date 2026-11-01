import Foundation

/// A scanner finish lock may name either a physical finish or a reviewed Magic
/// treatment. Treatment locks remain anchored to their physical finish so they
/// can never invent a printing that the exact catalog does not publish.
struct VariantLock: Equatable, Hashable, Sendable, Identifiable {
    let finish: PhysicalVariant
    let treatment: MagicTreatment?

    init(finish: PhysicalVariant, treatment: MagicTreatment? = nil) {
        self.finish = finish
        self.treatment = treatment
    }

    var id: String {
        guard let treatment else { return finish.id }
        return "\(finish.id)#treatment=\(treatment.id)"
    }

    var label: String {
        treatment?.label ?? finish.label
    }

    /// The intentionally narrow menu surface. Magic exposes its three
    /// provider finishes plus the two reviewed treatment locks; Pokémon keeps
    /// the existing physical-variant menu unchanged.
    static func selectable(for game: CardGame, registry: CardGameRegistry = .standard) -> [VariantLock] {
        registry.variantPolicy(for: game)?.lockOptions ?? []
    }
}

/// Source compatibility for callers during the runtime migration. IDs, labels,
/// treatment qualification and lock applicability are unchanged.
typealias MagicFinishLock = VariantLock

/// Everything the resolver is allowed to reason from. Deliberately a plain value
/// rather than the catalog card itself: the resolver must be testable without a
/// network response, and it must be impossible for it to reach for a "confidence"
/// signal that does not belong in this decision.
struct VariantEvidence: Equatable, Sendable {
    let game: CardGame
    /// TCGdex set id for Pokémon, lowercase Scryfall set code for Magic.
    let setID: String
    let cardNumber: String
    /// What the catalog itself publishes. Empty means the catalog is silent —
    /// which is a fact, not a licence to guess.
    let catalogVariants: [PhysicalVariant]
    /// Exact Magic treatment evidence from the identified printing. Pokémon
    /// leaves this empty so the resolver remains game-neutral.
    let magicTreatments: [MagicTreatment]
    let physicalCoverageVerified: Bool
    /// Exact supported membership permits an explicit choice without claiming
    /// that the provider enumerates every physical edition.
    let explicitMembershipSupported: Bool

    init(
        game: CardGame,
        setID: String,
        cardNumber: String,
        catalogVariants: [PhysicalVariant],
        magicTreatments: [MagicTreatment] = [],
        physicalCoverageVerified: Bool = true,
        explicitMembershipSupported: Bool = false
    ) {
        self.game = game
        self.setID = setID
        self.cardNumber = cardNumber
        self.catalogVariants = catalogVariants
        self.magicTreatments = magicTreatments
        self.physicalCoverageVerified = physicalCoverageVerified
        self.explicitMembershipSupported = explicitMembershipSupported
    }

    /// The same evidence with 1st Edition removed from the finish list.
    ///
    /// TCGdex publishes 1st Edition as a `variants` boolean beside normal, holo
    /// and reverse, so it arrives here looking like a finish. It is not one: it
    /// is the print run, and every surface that has already established the run
    /// — the virtual Browse set, or the scanner's print run question — would
    /// otherwise ask the identical question a second time under a different
    /// name. Removing it also keeps a 1st Edition Holo representable as both
    /// rather than collapsing the finish onto the edition.
    ///
    /// Only call this once the run is known; without it, 1st Edition is the
    /// only signal the catalog gives that the card had two runs at all.
    func excludingFirstEditionPseudoFinish() -> VariantEvidence {
        VariantEvidence(
            game: game,
            setID: setID,
            cardNumber: cardNumber,
            catalogVariants: catalogVariants.filter { $0.id != PhysicalVariant.firstEdition.id },
            magicTreatments: magicTreatments, physicalCoverageVerified: physicalCoverageVerified,
            explicitMembershipSupported: explicitMembershipSupported
        )
    }
}

enum VariantOutcome: Equatable {
    case resolved(ResolvedVariant)
    /// Two or more physically possible variants remain and the card carries no
    /// deterministic signal separating them. `lockDidNotApply` is set when the
    /// user's Finish Lock named a variant or treatment this printing does not
    /// exist in — the
    /// catalog stays authoritative about what is physically possible.
    case needsChoice(options: [PhysicalVariant], lockDidNotApply: VariantLock?)
}

/// Sits between identity and collection mutation.
///
/// The question is never "what does this shiny thing look like". It is "given the
/// exact printing we just identified, which physical variants actually exist, and
/// do we hold trusted evidence that picks one". Surface appearance is not on that
/// list and must never be added to it: an optical model may one day *rank* the
/// options under the user's thumb, but it may not answer for them.
enum VariantResolver {
    static func resolveAcquisition(_ evidence: VariantEvidence, printedEdition: PrintedEditionEvidence,
                                   finishLock: VariantLock? = nil, printedFinish: PhysicalVariant? = nil) -> VariantOutcome {
        gate(evidence, printedEdition: printedEdition)
            ?? resolve(evidence, finishLock: finishLock, printedFinish: printedFinish)
    }
    /// Empty options mean the existing Needs attention path, never an unknown
    /// persisted identity. Contradictory positives cannot be erased by a lock.
    static func gate(_ evidence: VariantEvidence, printedEdition: PrintedEditionEvidence) -> VariantOutcome? {
        guard evidence.physicalCoverageVerified || evidence.explicitMembershipSupported else { return .needsChoice(options: [], lockDidNotApply: nil) }
        if !evidence.physicalCoverageVerified && printedEdition == .absent {
            return .needsChoice(options: ordered(evidence.catalogVariants), lockDidNotApply: nil)
        }
        guard printedEdition != .absent else { return nil }
        let possible = ordered(evidence.catalogVariants)
        guard !printedEdition.isConflict else { return .needsChoice(options: [], lockDidNotApply: nil) }
        if let observed = printedEdition.observed.first {
            guard possible.contains(observed) else { return .needsChoice(options: [], lockDidNotApply: nil) }
            return .resolved(.init(variant: observed, resolution: .printedLabel))
        }
        return .needsChoice(options: possible, lockDidNotApply: nil)
    }

    static func resolve(
        _ evidence: VariantEvidence,
        finishLock: VariantLock? = nil,
        printedFinish: PhysicalVariant? = nil
    ) -> VariantOutcome {
        guard evidence.physicalCoverageVerified else {
            return .needsChoice(options: evidence.explicitMembershipSupported ? ordered(evidence.catalogVariants) : [], lockDidNotApply: nil)
        }
        let resolutionID = PerformanceSignpost.makeID()
        let resolutionState = PerformanceSignpost.beginInterval(
            "variantResolution",
            id: resolutionID,
            "set=\(evidence.setID)"
        )
        defer {
            PerformanceSignpost.endInterval(
                "variantResolution",
                resolutionState,
                "set=\(evidence.setID)"
            )
        }

        let ruled = PokemonVariantRules.apply(to: evidence)
        let stamped = stampedVariants(for: evidence)
        let possible = ScanText.unique(ruled.variants + stamped)

        // The catalog knows nothing. Record "unknown" honestly rather than
        // offering a menu of finishes we have no reason to believe exist.
        guard !possible.isEmpty else {
            return .resolved(ResolvedVariant(variant: nil, resolution: .catalogSilent))
        }

        if possible.count == 1 {
            return .resolved(
                ResolvedVariant(
                    variant: possible[0],
                    resolution: ruled.wasNarrowedByRule ? .deterministicSetRule : .uniqueInCatalog
                )
            )
        }

        // Finish Lock is contextual evidence the user supplied — a stack of
        // Master Ball parallels really is a fact about the cards on the table.
        // It is not an override: it applies only where the catalog agrees the
        // variant is physically possible.
        // Locks select an exact physical variant: Normal means plain Normal,
        // not Normal with a Prize Pack or championship stamp. Other catalog
        // variants must not disable that explicit choice (Auto still asks).
        if let finishLock {
            // One Piece finish IDs are exact ownership/price keys. Preserve
            // legacy games' fallback, but always return the catalog's finish.
            let catalogFinish = possible.first(where: { $0.id == finishLock.finish.id })
                ?? (evidence.game == .onePiece ? nil : possible.first(where: {
                    $0.id.caseInsensitiveCompare(finishLock.finish.id) == .orderedSame
                }))
            guard let catalogFinish else {
                return .needsChoice(options: ordered(possible), lockDidNotApply: finishLock)
            }

            if let treatment = finishLock.treatment {
                let treatmentAppliesToFinish = treatment.requiredFinishes.isEmpty
                    || treatment.requiredFinishes.contains(catalogFinish)
                guard evidence.game == .magic,
                      evidence.magicTreatments.contains(treatment),
                      treatmentAppliesToFinish else {
                    return .needsChoice(options: ordered(possible), lockDidNotApply: finishLock)
                }
            }

            return .resolved(
                ResolvedVariant(variant: catalogFinish, resolution: .finishLock)
            )
        }

        // A graded label is useful evidence only when the catalog agrees that
        // the asserted finish exists for this exact printing. It follows the
        // same authority rule as Finish Lock, but keeps its provenance distinct
        // so later audits can tell the two automatic paths apart. It must stay
        // below the unique-catalog tier and the user's Finish Lock, and it must
        // never answer a stamped-release question.
        let includesCatalogStampChoice = possible.contains(where: PokemonCatalogStampVariant.isStamped)
        if let printedFinish, stamped.isEmpty, !includesCatalogStampChoice {
            if possible.contains(printedFinish) {
                return .resolved(
                    ResolvedVariant(variant: printedFinish, resolution: .printedLabel)
                )
            }
            return .needsChoice(options: ordered(possible), lockDidNotApply: nil)
        }

        return .needsChoice(options: ordered(possible), lockDidNotApply: nil)
    }

    /// Compatibility entry point for callers that lock an ordinary physical
    /// variant. Treatment-aware scanner callers use the overload above.
    static func resolve(
        _ evidence: VariantEvidence,
        finishLock: PhysicalVariant,
        printedFinish: PhysicalVariant? = nil
    ) -> VariantOutcome {
        resolve(
            evidence,
            finishLock: VariantLock(finish: finishLock),
            printedFinish: printedFinish
        )
    }

    /// Options for correcting an already-recorded card, which is the same
    /// question asked after the fact.
    static func options(for evidence: VariantEvidence) -> [PhysicalVariant] {
        ordered(ScanText.unique(
            PokemonVariantRules.apply(to: evidence).variants + stampedVariants(for: evidence)
        ))
    }

    private static func stampedVariants(for evidence: VariantEvidence) -> [PhysicalVariant] {
        guard evidence.game == .pokemon else { return [] }
        let providerID = "\(evidence.setID)-\(evidence.cardNumber)"
        return PokemonStampedReleaseCatalog.entries(providerID: providerID).map(\.variant)
    }

    private static func ordered(_ variants: [PhysicalVariant]) -> [PhysicalVariant] {
        variants.sorted { left, right in
            left.choicePriority == right.choicePriority
                ? left.id < right.id
                : left.choicePriority < right.choicePriority
        }
    }
}

/// One claim about what a real set physically contains.
///
/// Each row is a statement about printed product, so each row has to be verified
/// against actual cards before it lands. Being wrong by *adding* a variant costs
/// the user one tap; being wrong by *omitting* one silently writes the wrong
/// finish into the collection, so an unverified set belongs here only when the
/// extra variant is more likely than not.
struct PokemonVariantRule: Equatable, Sendable {
    let id: String
    let setIDs: Set<String>
    /// The rule fires only when the catalog already agrees this printing has the
    /// base variant the special patterns are printed on top of. An ultra rare
    /// with no reverse-holo printing has no Poké Ball pattern either.
    let requiredCatalogVariant: PhysicalVariant
    let adds: [PhysicalVariant]
    let removes: [PhysicalVariant]
    /// Exact provider-backed eligibility. nil is reserved for genuinely set-wide rules.
    var cardNumbers: Set<Int>? = nil
}

/// The small supplemental layer this app owns.
///
/// TCGdex models identity superbly and publishes normal/holo/reverse, but it does
/// not model the newer parallel patterns the way the resolver needs. Rather than
/// pretend the catalog can answer something it does not track, add the missing
/// physical facts here and keep the scanning architecture untouched:
///
///     TCGdex card + our set-specific variant metadata = possible physical variants
enum PokemonVariantRules {
    /// Reviewed public TCGdex objects (2026-10-20). Broad booleans do not
    /// establish a plain reverse or a promotional stamp on these identities.
    /// This is checklist evidence, not a claim that an unlisted object cannot exist.
    static func reviewedVariants(cardID: String) -> [PhysicalVariant]? {
        switch cardID {
        case "me02.5-155":
            return [.holo, .pokeBall, .pokemonFoilPattern("energy")] + [
                PokemonCatalogStampVariant.make(base: .normal, stamps: ["player-rewards-program"]),
                PokemonCatalogStampVariant.make(base: .pokemonFoilPattern("cosmos"), stamps: ["player-rewards-program"])
            ].compactMap { $0 }
        case "me02.5-178": return [.holo, .loveBall, .pokemonFoilPattern("energy")]
        // Whole Yellow A review: generated Normal flags omit the actual EX
        // Holofoil products and the trainers' separate Normal/Holofoil objects.
        case "xya-24a", "xya-28a", "xya-54a", "xya-55a": return [.holo]
        case "xya-92a", "xya-107a": return [.normal, .holo]
        default:
            // Hidden Fates Shiny Vault: TCGdex flags all 94 as Normal, while every
            // TCGplayer product (group 2594, checked 2026-11-01) is Holofoil only.
            guard cardID.hasPrefix("sma-SV"), let number = Int(cardID.dropFirst(6)),
                  (1...94).contains(number), cardID == "sma-SV\(number)" else { return nil }
            return [.holo]
        }
    }

    static func requiresPhysicalReview(cardID: String, variant: PhysicalVariant) -> Bool {
        reviewedVariants(cardID: cardID).map { !$0.contains(variant) } ?? false
    }

    /// A stored finish the reviewed list does not contain. Only a person
    /// holding the card can replace it; no automatic path may rekey it.
    static func requiresPhysicalReview(cardID: String, variantID: String?) -> Bool {
        guard let variantID else { return false }
        return reviewedVariants(cardID: cardID).map { reviewed in
            !reviewed.contains { $0.id == variantID }
        } ?? false
    }
    /// Exact rows from the retained provider-explicit eligibility table, pinned to
    /// tcgdex/cards-database 99c994747cf7519a3e51166cc932de79a88bd4b3.
    /// Trainers and ex cards cannot inherit both patterns merely by having reverse.
    static let all: [PokemonVariantRule] = [
        PokemonVariantRule(
            id: "pokemon.sv08.5.masterball",
            setIDs: ["sv08.5"], requiredCatalogVariant: .reverse,
            adds: [.masterBall], removes: [],
            cardNumbers: [
                1, 2, 3, 4, 5, 7, 8, 9, 10, 13, 15, 16, 18, 19, 20, 21,
                22, 24, 25, 29, 33, 35, 36, 37, 38, 39, 40, 42, 43, 44, 45, 46,
                47, 48, 49, 50, 52, 53, 54, 55, 57, 59, 61, 62, 63, 65, 66, 67,
                68, 69, 70, 71, 72, 74, 77, 78, 79, 80, 81, 83, 84, 85, 86, 87,
                88, 89, 90,
            ]
        ),
        PokemonVariantRule(
            id: "pokemon.sv08.5.pokeball",
            setIDs: ["sv08.5"], requiredCatalogVariant: .reverse,
            adds: [.pokeBall], removes: [],
            cardNumbers: [
                1, 2, 3, 4, 5, 7, 8, 9, 10, 13, 15, 16, 18, 19, 20, 21,
                22, 24, 25, 29, 33, 35, 36, 37, 38, 39, 40, 42, 43, 44, 45, 46,
                47, 48, 49, 50, 52, 53, 54, 55, 57, 59, 61, 62, 63, 65, 66, 67,
                68, 69, 70, 71, 72, 74, 77, 78, 79, 80, 81, 83, 84, 85, 86, 87,
                88, 89, 90, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105,
                106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 118, 120, 121, 122, 123, 124,
                125, 126, 127, 130,
            ]
        ),
        PokemonVariantRule(
            id: "pokemon.sv10.5b.masterball",
            setIDs: ["sv10.5b"], requiredCatalogVariant: .reverse,
            adds: [.masterBall], removes: [],
            cardNumbers: [
                1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
                18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 29, 30, 31, 32, 33, 35,
                36, 37, 38, 39, 40, 41, 42, 43, 45, 47, 48, 49, 50, 51, 52, 53,
                54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 68, 69, 70,
                71, 72, 73, 74, 75, 76, 77, 78,
            ]
        ),
        PokemonVariantRule(
            id: "pokemon.sv10.5b.pokeball",
            setIDs: ["sv10.5b"], requiredCatalogVariant: .reverse,
            adds: [.pokeBall], removes: [],
            cardNumbers: [
                1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
                18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 29, 30, 31, 32, 33, 35,
                36, 37, 38, 39, 40, 41, 42, 43, 45, 47, 48, 49, 50, 51, 52, 53,
                54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 68, 69, 70,
                71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86,
            ]
        ),
        PokemonVariantRule(
            id: "pokemon.sv10.5w.masterball",
            setIDs: ["sv10.5w"], requiredCatalogVariant: .reverse,
            adds: [.masterBall], removes: [],
            cardNumbers: [
                1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
                18, 19, 21, 22, 23, 24, 25, 26, 27, 28, 29, 31, 32, 33, 34, 35,
                36, 37, 38, 39, 40, 41, 42, 43, 44, 46, 47, 48, 49, 50, 51, 52,
                53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 68, 69,
                70, 71, 72, 73, 74, 75, 76, 78,
            ]
        ),
        PokemonVariantRule(
            id: "pokemon.sv10.5w.pokeball",
            setIDs: ["sv10.5w"], requiredCatalogVariant: .reverse,
            adds: [.pokeBall], removes: [],
            cardNumbers: [
                1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
                18, 19, 21, 22, 23, 24, 25, 26, 27, 28, 29, 31, 32, 33, 34, 35,
                36, 37, 38, 39, 40, 41, 42, 43, 44, 46, 47, 48, 49, 50, 51, 52,
                53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 68, 69,
                70, 71, 72, 73, 74, 75, 76, 78, 79, 80, 81, 82, 83, 84, 85, 86,
            ]
        )
    ]

    struct Result: Equatable {
        let variants: [PhysicalVariant]
        /// True when a rule, rather than the catalog on its own, produced the
        /// final answer. Drives `VariantResolution.deterministicSetRule`.
        let wasNarrowedByRule: Bool
    }

    static func apply(to evidence: VariantEvidence, rules: [PokemonVariantRule] = all) -> Result {
        guard evidence.game == .pokemon else {
            return Result(variants: evidence.catalogVariants, wasNarrowedByRule: false)
        }

        var variants = evidence.catalogVariants
        if let reviewed = reviewedVariants(cardID: evidence.setID + "-" + evidence.cardNumber) {
            variants = reviewed
        }
        var applied = false

        for rule in rules where rule.setIDs.contains(evidence.setID) {
            guard variants.contains(rule.requiredCatalogVariant) else { continue }
            if let numbers = rule.cardNumbers {
                guard evidence.cardNumber.allSatisfy({ $0.isASCII && $0.isNumber }),
                      let number = Int(evidence.cardNumber), numbers.contains(number) else { continue }
            }
            applied = true
            variants.removeAll { rule.removes.contains($0) }
            for addition in rule.adds where !variants.contains(addition) {
                variants.append(addition)
            }
        }

        // Provenance is only interesting when the rule changed the answer. A rule
        // that widened the field still ends in a human tap, and that tap is what
        // gets recorded.
        return Result(
            variants: variants,
            wasNarrowedByRule: applied && variants.count == 1 && evidence.catalogVariants.count != 1
        )
    }
}

/// Re-evaluates only finishes whose stored provenance says the app chose them
/// automatically. A legacy row with no finish and no provenance is also safe to
/// revisit: there is no user choice to preserve. A legacy row with a finish but
/// no provenance remains protected because that finish may have been chosen by
/// the user before provenance was recorded.
enum PokemonFinishReconciliation {
    static func repair(
        storedVariantID: String?,
        storedResolution: VariantResolution?,
        itemKind: CollectionItemKind,
        printRun: PokemonPrintRun?,
        card: IdentifiedCard
    ) -> ResolvedVariant? {
        guard card.game == .pokemon,
              itemKind == .rawCard,
              printRun == nil || printRun == .unlimited else {
            return nil
        }

        if let storedResolution {
            guard storedResolution.isAutomatic else { return nil }
        } else {
            guard storedVariantID == nil else { return nil }
        }
        guard !PokemonVariantRules.requiresPhysicalReview(
            cardID: card.providerID,
            variantID: storedVariantID
        ) else { return nil }

        let evidence = card.variantEvidence
        let currentEvidence = printRun == nil
            ? evidence
            : evidence.excludingFirstEditionPseudoFinish()
        guard case let .resolved(resolved) = VariantResolver.resolve(currentEvidence),
              let variant = resolved.variant,
              variant.id != storedVariantID else {
            return nil
        }
        return resolved
    }
}
