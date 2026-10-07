# Useful card coverage data

**Reviewed:** 2026-10-06 against `412a09d` plus local changes.
**Scope:** missing-data leads from the supplied 2026-10-05 handoff. No app
behavior, catalog UUIDs or completeness flags changed.

Only three useful tables are retained, unchanged from the attachment:

| Data | Why keep it | Evidence boundary |
| --- | --- | --- |
| [Pokémon parallel eligibility](2026-10-05/pokemon_parallel_slots.csv) | 471 explicit card/pattern rows improve on the current set-wide reverse-holo rule. Prismatic: 100 Poké Ball / 67 Master Ball; Black Bolt and White Flare: 80 / 72 each. Master Ball excludes 079–086 in both latter sets; Prismatic 093 has Poké Ball only. | Provider-explicit snapshot pinned to TCGdex commit `99c994747cf7519a3e51166cc932de79a88bd4b3`, not physical completeness certification. |
| [Magic set-filter regressions](2026-10-05/magic_set_filter_regressions.csv) | Two PLG20 examples expose the current 3–4-character discovery boundary. | Catalog regression input. A physical card's printed code and optical recognizability require separate evidence. |
| [One Piece candidate printings](2026-10-05/one_piece_seed_candidate_printings.csv) | 21 review leads across five families. The retained registry has one Shanks printing, one OP01-001 printing, one provisional OP01-003 printing, two P-001 printings and two ST11-003 printings, so these leads merit comparison. | Provider observations cannot allocate UUIDs or prove exact finishes/distributions. All supplied family-completeness flags remain false. |

Pokémon rows include source paths, commit and observation date; One Piece rows
include source URLs and observation date. The handoff attributes PLG20 to the
[Wizards promotion announcement](https://wpn.wizards.com/en/news/announcing-love-your-local-game-store-promotion).
The attached archive retains the full original provenance package.

## Excluded from adoption

- **NEO overrides:** all four red/green/blue/yellow collector-number mappings
  already exist in the bundled Magic treatment manifest.
- **Pokémon count discrepancies:** already documented; metadata issues do not
  supply additional missing cards.
- **One Piece pack totals:** the August summary supplies no exact missing
  printing identities or card-level reconciliation input.
- **Missing internal rows claim:** incorrect for this checkout. The retained
  registry contains the rows behind the 221 count; its discrepancy ledger
  contains 257 entries. No reconstruction from counts is necessary.
- **Magic generator:** omits the app's set-type exclusions and lacks a proven
  MTGJSON/Scryfall crosswalk, so its exact-filter-diff claim is unsupported.
- **One Piece reconciler:** does not validate required fields or adjudicate
  language/release/finish, and empty names can compare equal. Reuse the existing
  evidence-aware pipeline.
- **New schemas, rules, matrices and duplicate summaries:** add no missing
  card-level facts and would compete with existing contracts/plans.

## Validation

Retained files match original manifest hashes and sizes. Pokémon has 471 unique
set/number/pattern keys, the six stated totals, the pinned commit on every row,
and the negative eligibility cases above. Magic has two rows; One Piece has
21 candidates with completeness false throughout. Existing NEO mappings and
retained One Piece family counts were checked directly.

No live source recrawl, runtime adoption, build or device acceptance is claimed.
The [coverage audit](../../audits/card-coverage-gaps-and-research.md) remains the
research authority; these tables support its existing implementation work.
