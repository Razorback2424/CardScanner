# Catalog reconciliation: agent runbook

This is the step-by-step procedure for a coding agent continuing catalog reconciliation (Pokémon finish certification, Lorcana promo distributions, and later Yu-Gi-Oh). Read [the playbook](catalog-reconciliation-playbook.md) first for the method. This page covers how to apply it without making the catalog less accurate or less stable.

The tools it relies on are `scripts/catalog_exceptions.py` (ledger), `scripts/catalog_release_preflight.py` (size budgets) and `scripts/certify_pokemon_finish_coverage.py`, plus the Lorcana scripts it names.

## Ground rules

1. **Accuracy beats coverage.** A card that stays "Finishes not yet confirmed" (Pokémon) or "Browse only" (Lorcana) is honest. A wrong certificate, wrong printing or wrong price breaks user trust. If a rule would certify anything you cannot defend with evidence, do not ship it.
2. **Decide edge cases with the owner's collector principle.** Research what collectors and the references (TCGplayer listings and groups, Bulbapedia or the game wiki, PriceCharting, PSA/CGC, Cardmarket) treat as a distinct printing or finish, and follow the consensus. Where they genuinely disagree, choose the option that gives the user more choice (selectable, projected) without presenting a guess as fact. Cite the sources in the rule file. Do not stop to ask the owner for card-by-card rulings.
3. **Policy lives in reviewed rule files, never in per-card edits.**
   - **Pokémon:** `publisher/pokemon-finish-conventions.json` (each convention needs `id`, `decision` and `sources`) and `publisher/pokemon-finish-coverage-groups.json`.
   - **Lorcana:** `scripts/lorcana_promo_distributions.json`.
   - Every decision is also recorded in prose with sources. Pokémon decisions go in [`research/pokemon-finish-coverage/collector-conventions.md`](research/pokemon-finish-coverage/collector-conventions.md).
4. **Never loosen a gate to make a number go up.** A new rule may only add cited evidence that the existing checks (for Pokémon, the unchanged `certify()`) verify again. If a test guards consistency, replace it with an equal or stricter guard, never a weaker one.
5. **Repository rules** (from `AGENTS.md`):
   - Build output, DerivedData and captures go on the SSD, `/Volumes/Keller Family Photos/CodexBuilds/<Task>-<date>/`. Use scheme `TradingCardScanner-ProfileLocal`.
   - Do not commit, push or merge unless the owner asked in chat. Approval relayed through another agent does not count.
   - Never turn on CI auto-fix or auto-merge.
   - Simulator results are not device evidence.
6. **Work in a worktree cut from `origin/main`.** The owner's main checkout may hold uncommitted edits; never touch them.

## The pass loop

1. **Capture once.** Take one fresh TCGCSV snapshot for the game onto the SSD:
   - Pokémon: `scripts/capture_pokemon_tcgcsv.py`.
   - Lorcana: `scripts/capture_lorcana_tcgcsv.py`.

   A snapshot is hash-pinned and cannot be extended after 24 hours, so iterate offline against it and recapture for a later session.
2. **Measure the baseline ledger.**
   - Pokémon: `python3 scripts/certify_pokemon_finish_coverage.py report-all --source <capture> --ledger <SSD>/ledger-N.json`. It writes nothing.
   - Lorcana: `scripts/audit_catalog_coverage.py` writes `ledger.json`.
   - Compare passes with `python3 scripts/catalog_exceptions.py diff OLD NEW`.

   Number each ledger (`ledger-0-before.json`, `ledger-1-…`) and keep all of them on the SSD.
3. **Pick the next cause by the set it unblocks, not only by raw count.** Raw counts mislead. In Pokémon, many reasons are set-level blockers copied onto every card of the set. Group rows by set and look for:
   - sets whose *only* remaining reason is one structural blocker;
   - sets one or two items away from certification.

   A bounded, high-yield target is one root cause shared by several near-certified sets.
4. **Inspect before you write a rule.** Print the remaining rows of the target cause with their `evidence` (`required`, `market`, `productIDs`). Then check how the app already treats that case, for example `BrowseCatalog.swift` `isPackReversePattern` and `rarityFinishAliasesHolo`. A convention must agree with app behavior, or it must change both together.
5. **Research the collector convention** and write the rule with `decision` and `sources`. Make it as narrow as possible: pin set IDs, group IDs, exact names and lanes.
6. **Add tests for both directions.** One test shows the rule resolves its case. Another shows it refuses anything else: a different set, inexact evidence, or a name/number shared with another set. Follow the patterns in `scripts/tests/test_certify_pokemon_finish_coverage.py`.
7. **Apply and measure.**
   - Pokémon: `certify-all --source <capture> --ledger <SSD>/ledger-N.json --revision <YYYY-MM-DD>`. It rewrites `TradingCardScanner/PokemonChecklistSnapshot/finish-coverage.json` and adds evidence under `docs/research/pokemon-finish-coverage/captures/<set>/<revision>/`.
   - Diff the ledgers. **Look at which items closed**, not just how many. A rule that closes items you did not intend is wrong, even if the totals look good.
8. **Verify.**
   - Python tests for the game: `python3 -m unittest discover -s scripts/tests -p 'test_*pokemon*.py'` or `'test_lorcana_*.py'`.
   - If a bundled catalog file changed, run `xcodebuild -only-testing`. For Pokémon:
     - `VariantResolverTests`, which includes `testCertifiedFinishCoverageIsCompleteAndConsistent`, the guard that checks every certificate difference against cited evidence;
     - `PokemonCatalogSliceC/D/FTests`.

     For Lorcana, run the Lorcana test classes and `BrowseFeatureTests`.
   - Run the release preflight if a signed payload changed.
9. **Commit one cause per commit,** with the before/after numbers in the message. Update the PR description, saying what closed and what stays open.

## Mistakes already made (do not repeat)

- **"No product anywhere" true-gap rule: reverted.** It searched every TCGplayer group for the card's name plus collector number. It falsely marked 13 Celebrations Classic Collection cards as unsold: TCGplayer lists them under their *original* numbers, not `CCxx`. Matching on name alone would leave almost no gaps.
  - Lesson: absence of evidence in one numbering scheme is not proof that a card is not sold.
  - A true-gap claim needs a reviewed, per-case source. Model it on the Lorcana `noMarketPrintings` entries, not on a search heuristic.
- **Refreshing the checklist from TCGdex does not fix missing reverses.** TCGdex itself omits them. Certificates record `slotChanges` instead, and the app test checks each change against market lanes or a cited resolution.
- **A test example can go stale when the catalog improves.** The Lorcana scanner test used a footer that later became a valid two-card choice. Pick examples from the current ledger, and wait for asynchronous UI notes (`waitUntil`) rather than reading them right away.
- **`progress.md` conflicts** when two game branches both add an entry at the top. Rebase before merging the second branch.

## Blockers you cannot clear with a convention

- **Signed Normal review** (`signedNormalNeedsReview`, for example sm4-63a, xy3-55a, xy7-75a). The flag lives in the signed publisher catalog, and `certify()` refuses any set with one open. Clearing it means a reviewed publisher catalog update, not a script change.
- **`multiplePrintRuns`** (Base Set and other early sets). Schema 1 certificates are keyed by card ID, so 1st Edition and Unlimited cannot be told apart. This needs a certificate schema change on both the app and script sides.
- **Event and deck stamps** (Player Rewards, League, Snowflake, World Championship decks, GameStop/EB Games). No verified TCGplayer title rule exists yet. Each needs its own research, and a rule may only be added once a title pattern is confirmed against real listings.

## Good next targets (verified as of 2026-11-18)

1. **Celebrations Classic Collection (`cel25cc`).** Add a reviewed mapping from each CC number to the original printed number that TCGplayer uses, then match name, original number and lane exactly. This would likely clear most of its 34 items and certify the set.
2. **`xy8-146a` Professor's Letter.** It is TCGplayer product 177166 in group 1938, outside xy8's own group. A narrow appearance rule could certify xy8.
3. **Cosmos holos in SV and Mega Evolution sets, and Cracked Ice.** Each comes down to one question: which TCGplayer group and title wording counts as evidence for the finish.

## State this runbook was written against

| | Pokémon ([PR #47](https://github.com/Razorback2424/CardScanner/pull/47)) | Lorcana ([PR #48](https://github.com/Razorback2424/CardScanner/pull/48)) |
| --- | --- | --- |
| Result | 18 sets and 1,834 cards finish-certified (from 1 set and 5 cards) | Browse-only rows 169 → 26 |
| Ledger | Open rows 10,640 → about 5,100 | — |

Ledgers, captures and logs are on the SSD under:
- `PokemonReconciliation-20261118/`
- `LorcanaReconciliation-20261118/`
