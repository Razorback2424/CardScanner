# One Piece integration review handoff

**Snapshot:** 2026-10-05; `merge/one-piece-integration`, based on
`69c714f9f6e7064231e45c34d6a3fed1f1ea7555`. Implementation is uncommitted.

## Checkout and review scope

The One Piece worktree was transferred to the main checkout without conflicts:
67 modified tracked files and 116 new files. `main` remains at
`cdd60e1f86531820141c3363243e9c46402a83f2`; no merge commit was created.
The source worktree remains intact. The destination preserves its pre-existing
`TCGdexCard.swift` whitespace edit and untracked `undefined/` folder; these are
not integration changes. Transfer comparison found only that whitespace
difference across the 183 implementation files.

Review both `git diff HEAD` and files listed by
`git ls-files --others --exclude-standard`; the diff alone omits new packages,
adapters, tests and catalog data. The branch also includes the earlier
`fix/october-review-boundaries` commits; this report describes the uncommitted
integration delta, not all differences from `main`.

## Changed code

Paths below are relative to the repository; app paths start with
`TradingCardScanner/`.

| Area | Files and behavior |
| --- | --- |
| Game identity | `Models/CardGame.swift`, `CardGameRegistry.swift`; `Services/SetCodeMap.swift`, `CollectionCSV.swift`, `Models/CollectedCard.swift`: replace the closed game enum with a string-backed value retaining single-string Codable encoding. Preserve unknown game identities; capability checks gate adapters and collection writes. |
| Runtime and app binding | `Games/Core/CardGameRuntime.swift`, adapter protocols, `App/TradingCardScannerApp.swift`, `Views/ContentView.swift`: register game runtimes and bind consumers to the actual collection container. `CollectionAuthorizedActivationSource.swift` applies collection/price authority before exposing catalog activation. |
| Recognition | `Services/ScanParser.swift`, `CardScanner.swift`; game recognition adapters: generic field-based identifiers, generation and suppression identities; aggregate recognizer outcomes and reject ambiguity. One Piece vocabulary comes from the active registry. Number evidence alone does not establish an exact physical printing. |
| Catalog resolution | `Services/CardCatalog.swift`, `Games/Core/GameCatalogAdapter.swift`: resolved/incomplete/printing-choice outcomes, bounded lookup caching, task coalescing and generation checks. User printing selections are not cached as defaults for the printed number. |
| Existing game extraction | `Games/Pokemon/PokemonCatalogAdapter.swift`, `PokemonCatalogSupport.swift`, `PokemonHistoricalCatalog.swift`; `Games/Magic/MagicCatalogAdapter.swift`: move provider/offline/cache and Magic child-card routing out of central catalog lookup. Retain Pokémon disk keys and captured modern/promo definitions; historical membership changes reject stale completion. |
| Ownership and recovery | `Models/ResolvedCatalogCard.swift`, `Games/Core/LegacyResolvedCard.swift`, `Services/CollectionStore.swift`, `UnresolvedScanStore.swift`, `Views/ScannerViewModel.swift`: use exact physical IDs, generic printing candidates and versioned identifier snapshots. Retain legacy recovery decoding and Pokémon print-run keys; validate new-game writes/corrections against catalog authority. |
| One Piece app module | `Games/OnePiece/`: recognition, catalog, Browse, import, variant and pricing behavior through the shared seams. Catalog resolution selects only verified printings. Incomplete coverage/language evidence retains an explicit choice even when one eligible printing exists. |
| UI | `Views/ScanSessionOverlays.swift`, scanner/recovery views and Browse/card details: compact physical-printing choices, separate finish resolution, unresolved retention, and mapped-price display/refresh. |
| Signed releases | `Services/SignedCatalogReleaseStore.swift`, `SignedCatalogUpdateClient.swift`, migrated Pokémon/Magic stores and One Piece coordinator/registry/bootstrap/update/rollout files: shared transport/storage mechanics with separate domain contracts. Added local package references, source files, configuration and One Piece workflow. |

## Catalog and pricing scope

`OnePieceCatalogCore/` adds canonical cards, artwork, permanent physical UUIDs,
aliases, source observations, market mappings, reconciliation/validation,
signing and a publisher CLI. `scripts/` adds capture, discovery, normalization,
reconciliation, base-market review and local-kit generation tools with tests.

The retained `ReviewCorpus/english-stress` contains 2,692 canonical cards and
2,745 printing records: 2,490 verified, 224 provisional and 31 conflicted.
Ordinary review covers 58 product groups; Browse exposes 52 groups with verified
targets. Physical-universe completeness remains false.

`Games/OnePiece/OnePiecePriceAdapter.swift` supplies exact TCGCSV USD product
Normal/Foil lanes for 1,961 reviewed original-base mappings; 412 decisions remain
held. Prices are aggregate market observations, not condition-specific SKUs.
Requests validate exact product/group/name/number/finish, coalesce/cache feeds
and disable borrowed-printing fallback. Wiring covers scanner save, Price Check,
Browse detail/add and collection refresh. Mapping fingerprints in `PriceRecord`
and `ReferenceQuote` support withdrawal and reject older receipts; manual values
are preserved. Unmapped printings return unavailable.

## Additional included work

`Games/Lorcana/` and `LorcanaIntegrationTests.swift` contain the first research
slice: footer/print-family recognition and incomplete catalog recovery. It is
explicitly injected, absent from app defaults, and supplies no owned physical
resolution, pricing or collection-write capability. The `undefined/` copies of
pricing files are pre-existing destination files, not runtime registration.

## Verification and remaining work

The latest source-worktree simulator checkpoint passed **192 tests, zero
failures/skips**: full One Piece integration, pricing/quote-cache suites,
forward compatibility, Pokémon activation/historical cases, Magic routing and
11 selected offline/fallback/cache/artwork regressions. Result bundle:
`test_sim_2026-10-05T13-01-49-160Z_pid18958_cc372487.xcresult`.
The installed full-kit build relaunched with the saved Shanks quote/portfolio
displaying $8.16; this was cached display continuity, not a new provider check.
No builds/tests were repeated after the content-equivalent transfer.
`git diff --check` passed on the destination.

Known incomplete work: Browse/import legacy extraction, signed legacy runtime
activation migration, broader special-printing reconciliation, production
keys/seed/hosting/rights and mixed-client sync policy. The architecture audit
still fails on eight game-case labels, all in `Services/BrowseCatalog.swift`.
`Config/OnePieceCatalogProduction.xcconfig` keeps rollout disabled with no
production key/endpoint; the private signed local review kit is not a bundled
production release. Camera/device, full regression and release acceptance remain
open. Immediate priority is local scan → printing choice → finish → save →
relaunch/price-refresh acceptance before further architecture expansion.

Current detailed authority: [implementation ledger](../plans/one_piece_code_implementation.md),
[catalog design](../plans/one_piece_catalog_integration_plan.md) and
[printing-choice checklist](../plans/one_piece_printing_choice_visual_checklist.md).
