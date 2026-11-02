# Pokémon finish evidence repair

**Date:** 2026-11-02. Bounded eight-set repair, merged in PR #20 after its
final native gate passed. The [consolidation receipt](repository-consolidation-2026-11-02.md)
records the current checkpoint and verified union selection. Earlier draft and
integration-failure statements below are historical. Release certification
remains open.
Starting main and reviewed baseline: `4a9d70b12d941877e2752fe9cfb5fd1508ce0520`.
Open PRs #18 and #19 were inspected before editing and concern separate repairs.
Implementation uses `fix/pokemon-finish-evidence` in an isolated worktree.

## Inputs and scope

The original [BOM CSV](../../TestFixtures/TradingCards/PokemonFinishEvidence/confirmed_repairs.csv)
is retained byte-for-byte, SHA-256
`51e71a2a68815bd4170f4cb2ae432b577d1a456d175becfdb7a2cf3e7292672c`.
The [v2 workbook](../../TestFixtures/TradingCards/PokemonFinishEvidence/pokemon_support_repairs_v2.xlsx)
has SHA-256 `d32090f2b276949cb77cdd263cd878cc95b7bc67b444897d7c1fe769226dd951`.
Its Confirmed, New This Pass, Observed, Controls, Holds, Sources and Source Receipts
sheets were read. The [normalized v2 CSV](../../TestFixtures/TradingCards/PokemonFinishEvidence/confirmed_repairs_v2.csv)
is mechanically checked against Confirmed; the original 277 requirements are unchanged.
All eight actual baseline Git blobs were verified, including the four originally
marked “selected fields only” in the workbook. Those historical receipt labels
are preserved rather than rewritten as a claim about the workbook's environment.

| Set | Affected IDs | Added memberships | Retained slots before | After |
| --- | ---: | ---: | ---: | ---: |
| Evolutions | 108 | 121 | 113 | 234 |
| Forbidden Light | 130 | 142 | 147 | 289 |
| Dragon Vault | 21 | 21 | 21 | 42 |
| Detective Pikachu | 18 | 18 | 18 | 36 |
| Shining Legends | 73 | 85 | 78 | 163 |
| Dragon Majesty | 70 | 80 | 78 | 158 |
| Double Crisis | 34 | 40 | 34 | 74 |
| Pokémon Rumble | 3 | 3 | 16 | 19 |
| Total | 457 | 510 | 505 | 1,015 |

The eight sets retain 504 distinct identities: 457 affected, 14 passing and
33 unassessed. The original extra slot is Exeggcute sm6-1's second finish.
All original memberships are preserved. Normal remains retained on 175 affected
identities requiring product review (115 from v1, 60 added in v2); retention does
not affirm its physical-product support. The 50 Celebrations/Classic Collection
Holo controls and six Yellow A reviewed identities are outside this census.

The workbook's Sources sheet retains the exact URLs, access methods and limits.
Official finish boxes and legends were visually inspected for
[Evolutions](https://assets.pokemon.com/assets/cms2/pdf/trading-card-game/checklist/xy12_web_cardlist_en.pdf),
[Forbidden Light](https://assets.pokemon.com/assets/cms2/pdf/trading-card-game/checklist/sm6_web_cardlist_en.pdf),
[Shining Legends](https://assets.pokemon.com/assets/cms2/pdf/trading-card-game/checklist/sm35_web_cardlist_en.pdf) and
[Dragon Majesty](https://assets.pokemon.com/assets/cms2/pdf/trading-card-game/checklist/sm75_web_cardlist_en.pdf).
Dragon Vault and Detective Pikachu use the ledger's numbered product/Holofoil
evidence. The Detective Pikachu identity checklist alone is insufficient.
Double Crisis and Rumble use the workbook's printing evidence, without claiming
an official finish matrix. Pullnomics and other TCGplayer-derived tables are
corroboration, not independent pricing providers. No prices or product bindings
were added from this evidence.

## Production boundaries

- `PokemonFinishMinimumCatalog` reads one generated exact-ID minimum table.
  `TCGdexCard.catalogVariants` adds those minimums without deleting retained
  options. Existing reviewed overrides and TCGCSV mappings remain effective.
- `PokemonChecklistReviewedProjection` applies the same table after downloaded
  precedence, including warm checklist reads and snapshot merges. The native
  generator uses this projection and the normal atomic writer. Only eight
  manifest entries/resources change; upstream canonical/probe fingerprints
  remain separate and unchanged.
- `PokemonOfflineCardFactory` preserves supported memberships and explicitly
  marks checklist evidence as incomplete. `LegacyResolvedCard` carries that
  provenance into `VariantEvidence`. The resolver removes the ledger's
  unverified Normal choices from supported selection options, while their
  checklist/collection records remain retained.
- Incomplete Pokémon evidence accepts a validated exact Finish Lock or printed
  label, or asks for an explicit choice. A sole supported option does not return
  `uniqueInCatalog`. Verified-coverage fixtures retain that resolution. Other
  games retain their existing gates. The global resolver default was not flipped.
- Empty evidence no longer generates Normal. The checklist builder keeps an
  identity-only row when no finish is known. Explicit Normal remains distinct.
- Resolved cache entries now persist coverage provenance. Old generation-2
  entries without that field remain usable as incomplete membership evidence.
  No cache purge or schema-generation bump is required. Exact ledger enrichment
  also protects stale provider payloads and refreshes.
- Existing physical-review and reconciliation guards hold the ambiguous Normal
  memberships. No collection migration is needed. Confirmed, imported, locked,
  ambiguous legacy and inferred holdings are never silently rekeyed by this
  repair. Existing pricing provenance/history is not rewritten.

The original resource-generating commit `8072f45` already retained Normal-only
rows and included the empty-evidence fallback. Retained inputs/logs do not show
whether fallback or upstream flags produced these particular rows. The fallback
is a confirmed mechanism, not a proven historical cause for each affected card.

## Reproduction and validation record

Tests-only reproduction commit: `7a44011`. Before production changes, all six
new native methods failed (59 assertion failures). The unchanged-code tests and
failing xcresult are retained. A subsequent v2-only method failed before the new
180 IDs were added; that run also exposed a control-fixture set-ID typo, corrected
to `cel25cc` without removing its 50-identity assertion.

The first expanded native run passed all nine new methods, including native
regeneration. The broader candidate run completed 597 methods: 593 passed,
three failed and one existing skip. Two failures were obsolete offline inference
expectations; they now require honest unresolved/single-choice outcomes and valid
Finish Lock behavior while retaining their membership assertions. The third
was `CollectionKeyTests.testREQ001UnderlyingPrintingIDUsesTheProductionSourceForEveryItemKind`
(sealed `direct-product`, outside these code changes). Result finalization failed
when T7 filled; the complete stdout remains retained. The first attempt to check
that unrelated method on baseline failed to build for the same storage reason,
so it is not claimed as a baseline native reproduction.

Pokémon core: 84 methods, 83 passed and one existing live-manifest skip.
Repository Python suite: 155 methods, 150 passed and five existing publisher
prerequisite skips. These are actual repository executions, not a claim to have
rerun the report author's separate 14 Python tests.

Final-head commands/results and CI links belong in the draft PR. Earlier runs
above are retained evidence, not substitutes for the expanded final-head run.
The complete source/test implementation at `2fd1325` then executed 597 native
methods: **595 passed, one failed, one existing live-provider skip**. All nine
new methods passed exactly once, including the extended stale-download/cache
cohort checks and four distinct persisted holding provenances. The sealed
`direct-product` assertion failed identically in a completed narrow native run
on unchanged baseline `4a9d70b`; it remains outside this repair. The finalized
bundle is retained, but `xcresulttool` summary access reports a local Library/Caches
write error. Counts are reconciled from 597 unique stdout method-completion records
and XCTest's total, not inferred from selection flags. See the
[method record](pokemon-finish-evidence-2026-11-02-results.json).
Subsequent CI-selection/documentation changes require another exact-head run;
its authoritative result is in [draft PR #20](https://github.com/Razorback2424/CardScanner/pull/20).
The catalog CI workflow explicitly selects `PokemonFinishEvidenceTests`, reviewed
TCGCSV corrections, collection keys and scanner tests, checks out the exact PR
head, and runs the ledger/blob audit with baseline history available.

Reproduce the data audit from the repository root:

```sh
python3 scripts/audit_pokemon_finish_repairs.py --check-table
```

For regeneration, run
`PokemonFinishEvidenceTests/testRegenerationUsesNativeWriterAndPreservesProviderFingerprints`,
then pass its printed generated directory to
`python3 scripts/audit_pokemon_finish_repairs.py --check-table --install-generated DIRECTORY`.
Reapplication is idempotent. The audit verifies exact source hashes, unique rows,
existing identities, no removed memberships, no held/unassessed additions and
unchanged unrelated metadata. Native expectations read the independent CSV,
not the implementation's finish table.

## Remaining holds and limits

No finish changes for xy12-109–113, sm6-132–146, sm3.5-74–78 or sm7.5-71–78.
The 13 Dragon Vault stamped/Cosmos/Regional/Staff leads remain HOLD. World
Championship Super Rod is a distinct printing, not evidence for ordinary
dv1-20 Normal. Entei-GX 10a/73 remains HOLD for provider identity/live fallback.
No Shining/GX/Prism Star/foil-logo finish inference, all-set audit, feed
publication, deployment, merge, device installation or real collection mutation.
Live provider, physical-device, CloudKit and release validation remain unexecuted.
