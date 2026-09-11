import Foundation

/// A scanner finish lock may name either a physical finish or a reviewed Magic
/// treatment. Treatment locks remain anchored to their physical finish so they
/// can never invent a printing that the exact catalog does not publish.
struct MagicFinishLock: Equatable, Hashable, Sendable, Identifiable {
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
    static func selectable(for game: CardGame) -> [MagicFinishLock] {
        let finishes = PhysicalVariant.selectable(for: game).map {
            MagicFinishLock(finish: $0)
        }
        guard game == .magic else { return finishes }
        return finishes + MagicTreatment.lockable.compactMap { treatment in
            guard treatment.requiredFinishes.count == 1,
                  let finish = treatment.requiredFinishes.first else {
                return nil
            }
            return MagicFinishLock(finish: finish, treatment: treatment)
        }
    }
}

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

    init(
        game: CardGame,
        setID: String,
        cardNumber: String,
        catalogVariants: [PhysicalVariant],
        magicTreatments: [MagicTreatment] = []
    ) {
        self.game = game
        self.setID = setID
        self.cardNumber = cardNumber
        self.catalogVariants = catalogVariants
        self.magicTreatments = magicTreatments
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
            magicTreatments: magicTreatments
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
    case needsChoice(options: [PhysicalVariant], lockDidNotApply: MagicFinishLock?)
}

/// Sits between identity and collection mutation.
///
/// The question is never "what does this shiny thing look like". It is "given the
/// exact printing we just identified, which physical variants actually exist, and
/// do we hold trusted evidence that picks one". Surface appearance is not on that
/// list and must never be added to it: an optical model may one day *rank* the
/// options under the user's thumb, but it may not answer for them.
enum VariantResolver {
    static func resolve(
        _ evidence: VariantEvidence,
        finishLock: MagicFinishLock? = nil,
        printedFinish: PhysicalVariant? = nil
    ) -> VariantOutcome {
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
        // A finish lock describes Normal/Holo/Reverse, not whether the pumpkin
        // stamp is present. It must not silently answer the stamped question.
        let includesCatalogStampChoice = possible.contains(where: PokemonCatalogStampVariant.isStamped)
        if let finishLock, stamped.isEmpty, !includesCatalogStampChoice {
            let physicalFinishMatches = possible.contains(where: {
                $0.id.caseInsensitiveCompare(finishLock.finish.id) == .orderedSame
            })
            guard physicalFinishMatches else {
                return .needsChoice(options: ordered(possible), lockDidNotApply: finishLock)
            }

            if let treatment = finishLock.treatment {
                let treatmentAppliesToFinish = treatment.requiredFinishes.isEmpty
                    || treatment.requiredFinishes.contains(finishLock.finish)
                guard evidence.game == .magic,
                      evidence.magicTreatments.contains(treatment),
                      treatmentAppliesToFinish else {
                    return .needsChoice(options: ordered(possible), lockDidNotApply: finishLock)
                }
            }

            return .resolved(
                ResolvedVariant(variant: finishLock.finish, resolution: .finishLock)
            )
        }

        // A graded label is useful evidence only when the catalog agrees that
        // the asserted finish exists for this exact printing. It follows the
        // same authority rule as Finish Lock, but keeps its provenance distinct
        // so later audits can tell the two automatic paths apart. It must stay
        // below the unique-catalog tier and the user's Finish Lock, and it must
        // never answer a stamped-release question.
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
            finishLock: MagicFinishLock(finish: finishLock),
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
    /// Prismatic Evolutions and the Black Bolt / White Flare pair print Poké Ball
    /// and Master Ball parallel patterns alongside the ordinary reverse holo.
    /// Nothing on the card's identifier strip distinguishes them, which is exactly
    /// the case where the human holds information the scanner cannot have.
    static let all: [PokemonVariantRule] = [
        PokemonVariantRule(
            id: "pokemon.ballPatterns",
            setIDs: ["sv08.5", "sv10.5b", "sv10.5w"],
            requiredCatalogVariant: .reverse,
            adds: [.pokeBall, .masterBall],
            removes: []
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
        var applied = false

        for rule in rules where rule.setIDs.contains(evidence.setID) {
            guard variants.contains(rule.requiredCatalogVariant) else { continue }
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
