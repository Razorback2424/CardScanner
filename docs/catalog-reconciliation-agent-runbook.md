# Catalog reconciliation: agent runbook

This is the step-by-step procedure for a coding agent continuing catalog reconciliation (Pokémon finish certification, Lorcana promo distributions and Yu-Gi-Oh! correspondence). Read [the playbook](catalog-reconciliation-playbook.md) first for the method. This page covers how to apply it without making the catalog less accurate or less stable.

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

## Yu-Gi-Oh!

**How "incomplete" works:**
- `build_yugioh_catalog.py` marks a printed code incomplete when its TCGplayer products and its YGOPRODeck `card_sets` rows do not correspond exactly.
- The reasons go to a `<report>.ledger.json` sidecar, never into the seed.
- An incomplete code **only withholds automatic scan selection**. Every printing can still be chosen explicitly.
- Automatic selection also needs a reviewed Konami release inventory (`scripts/yugioh_printing_inventories.json`). So clearing correspondence makes the ledger honest but does not make scanning faster by itself.
- Do not show "Partial catalog" for incompleteness. Browse marks a set partial only when one of its own coded rows cannot be added.

**Pass loop:**
1. Capture onto the SSD by running the builder without `--offline` into a fresh `--cache-dir`. It takes about 40 minutes for 660 groups.
2. Replay with `--offline` and `--price-receipt`. Pass a seed from a
   different provider capture as `--previous-seed`. To replay the capture
   behind the current bundle, use the earlier seed used to generate it.
3. Compare ledgers with `catalog_exceptions.py diff`.
4. Confirm the candidate changed only what the rule intended: compare printing IDs and fields against the previous build, check that `parentRegressions` is empty, and check that `autoEligibleCodes` is unchanged unless you meant to change it.
5. Copy the candidate over the bundled seed.
6. Run every `YuGiOh*Tests` class and `BrowseFeatureTests`.

**Release-name aliases (2026-11-19).**
- Command: `python3 scripts/reconcile_yugioh_release_names.py <ledger> --refusals <file> [--write --reviewed-at YYYY-MM-DD]`.
- It proposes `setNameAliases` per group and code prefix when the printed code and the card agree on exactly one YGOPRODeck set name.
- The decision and its gates are in [`research/yugioh-catalog/release-name-aliases.md`](research/yugioh-catalog/release-name-aliases.md).
- Result: open rows went from 24,204 to 8,671, and incomplete codes from 12,331 to 4,384, with 0 opened. Only the `correspondence` field changed, on 9,520 rows.
- Before writing, read every proposal sorted by name similarity, and review the refusals.

**Pass 2 (2026-11-20).**
- **Price receipts.** Replay with `--price-receipt`. `scripts/capture_yugioh_price_receipt.py <cache> --out <receipt>` binds a capture to TCGCSV's snapshot marker by fetching every group's prices again, before the next daily update (about 20:00 UTC), and comparing hashes. Without a receipt, every quote carries the local capture time instead of TCGplayer's snapshot time. PR #52 shipped that way, and `testRealListingOnlyPairAndBundledSnapshotNeverPretendLiveRefresh` caught it.
- **Previous seed.** Pass the last seed built from a *different* capture as `--previous-seed`. Passing a seed from the same capture adds duplicate history entries.
- **Code-level release-name aliases.** These cover groups that hold several sub-releases. Always regenerate from the pre-alias baseline ledger: `--write` replaces the whole list.
- **Rarity taxonomy.** Prismatic rules for RA01, RA03, RA04 and RA05, plus Short Print and Super Short Print read as Common. See [`research/yugioh-catalog/rarity-taxonomy.md`](research/yugioh-catalog/rarity-taxonomy.md).
- **Result:** open rows went from 8,671 to 5,211 and incomplete codes from 4,384 to 2,689, with 0 opened. `autoEligibleCodes` went from 262 to 274, from the PSV Short Prints that Konami's checklist lists as Common.

**Star Pack VRAINS pass (2026-11-21 on `467581b4`).**
Main already includes the HAC1 Duel Terminal taxonomy and the 2025 Mega-Pack
Tin inventory. The separate Star Pack VRAINS candidate clears 147 rows for
49 codes. Its bundled-capture replay went from 4,883 to 4,736 open rows,
with zero opened. The fresh replay closed the same rows, from 4,880 to
4,733. The bundled candidate has empty `parentRegressions` and 720 identical
automatic codes. The fresh replay separately flags four `MAMO-EN013` identity
changes. Evidence is on the SSD in `YuGiOhStarfoilReconciliation-20261121/`.
[Decision and scope](research/yugioh-catalog/rarity-taxonomy.md#star-pack-vrains-duplicate-starfoil-label-2026-11-21)

**Next Yu-Gi-Oh targets**

1. **Speed Duel source coverage.** The retained snapshot lacks exact
   YGOPRODeck rows for 367 codes across `SBC2`, `SGX4` and `STP7`. Validate
   exact English Konami printed codes and preserve existing parent canonical
   identities before admitting a secondary crosswalk.
2. **Reviewed Konami release inventories.** Prioritize clean correspondence
   and single-print, single-art families to improve automatic scan selection.

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
