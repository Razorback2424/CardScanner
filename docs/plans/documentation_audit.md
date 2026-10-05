# Documentation and artifact audit

**Audit date:** 2026-10-02; implementation evidence updated 2026-10-03
**Purpose:** reconcile the chronological progress log, implementation plans,
QA checklists, and simulator evidence so that an old “pending” note is not
mistaken for a current defect—and a real validation gap is not lost in the
history.

## Current authority boundary — updated 2026-10-03

**One Piece plan reconciliation — 2026-10-05, `6b64abe`:** the integrated code is
now committed on `merge/one-piece-integration`. The implementation ledger and
catalog design supersede older active wording that cached-price withdrawal,
exact finish correction, Pokémon/Magic catalog extraction or the ordinary
capture pipeline are missing. Current source retains 2,745 printings and 1,961
exact base mappings; all canonical physical-coverage flags remain false. Local
full-kit base-case acceptance is next. The read-only boundary audit still reports
eight Browse labels; legacy Browse/import/runtime work and production/device/
rights/sync gates remain open. This reconciliation reran no app/package tests;
the recorded 192-test checkpoint retains its original scope and provenance.

One Piece base pricing update — 2026-10-04, existing `one-piece-integration`
worktree at `69c714f`: exact TCGCSV pricing is now implemented for 1,961 reviewed
original base printings. This supersedes older “no pricing adapter / optional
pricing” notes for the local base-case milestone. TCGCSV exposes aggregate market
prices, not condition SKUs. Price Check, Browse detail/add and collection refresh
use permanent printing UUIDs and exact finish lanes; no name/number fallback is
allowed. The [implementation ledger](one_piece_code_implementation.md#base-case-pricing-priority--2026-10-04)
records source scope, implemented cached-quote withdrawal and remaining physical mapping,
device and production gates. The full 2,745-printing debug kit verifies;
production scanning/sync remain disabled.

2026-10-05: container-bound catalog publication now persists exact managed-price
withdrawals before consumers see the new generation. The selected One Piece and
pricing checkpoint passed 103/103; same-container startup/quote-cache checks passed
18/18. A relaunch-found stale feed cache now refreshes per catalog generation;
its affected recheck passes, and final full-kit relaunch/Refresh Prices restored
the saved Shanks quote to $8.16. A subsequent three-test checkpoint proves actual
single/multi-claim rejection without ownership/history mutation after signed
catalog quarantine, conflict/stale revision handling and storage-session retirement.
The subsequent Magic catalog extraction owns Scryfall and signed child routing
under `Games/Magic`; 55 focused catalog/compatibility tests pass. Prepared-identity
coalescing retains fetch timestamps and does not cache a user's printing answer.
Signed Magic activation and the remaining legacy modules are still pending.
The subsequent Pokémon catalog extraction moves provider/offline/disk-cache and
historical behavior under `Games/Pokemon`, preserving keys and captured modern
definitions. One consolidated checkpoint passed 192 selected catalog, One Piece,
pricing and quote-cache tests. The boundary audit remains red on eight matching
labels, all in Browse; full-plan completion is not implied. Base-case acceptance
is the next milestone; further framework
or special-printing expansion waits for findings from that local test.

This is the repository-wide documentation index and reconciliation record.
Source code, tests, build settings, and evidence recorded against the current
checkout outrank dated plans. A document is current only when it is listed
below or linked from the current [documentation map](../README.md). Everything
under `docs/legacy/` or `review/legacy/` is retained for provenance and is not
release evidence.

The newest boundary-failure implementation and simulator evidence is in the
[October review ledger](../audits/october-review-remediation.md), against
`fix/october-review-boundaries` through `248a61d`. Slices 1–10 are committed;
focused checks pass, while its historical complete runs report centering failures.
Older “latest full run” statements below describe their dated snapshots and do
not supersede the October execution record. Physical-device and release gates
remain open.

The [October refinement plan](october-refinement-implementation-plan.md) validates
the supplied follow-up review against `55b2d40` and now records the authorized
implementation of slices A–I and C1, followed by the verified guided centering
repair recorded below.
Subsystem acceptance contracts remain binding. Slice C resolves the source/test
disagreement with the hybrid requirement: edits and warning refresh remain
pending until explicit approval of valid outer and inner frames. Manual-recovery
and invariant helpers invoke that action too; numerical tolerances and automatic
detector gates stay unchanged. Slice K fixes the reproduced preview rotation
mismatch and retains individual diagnostic/accuracy triage. The older passing
confirmation selectors are historical. The owner supplied intended future
`scan-stash.com/privacy` and `/support` pages, but confirmed they are placeholders;
Release URL configuration remains open until approved live pages exist. On
2026-10-03 the owner confirmed Scanstash as the app name and Info@scan-stash.com
as the live contact. The existing legal drafts were revised against current
source and Apple guidance; [publication checks](../legal/README.md) track the
remaining contact/operator, retention, provider, hosting, and Release URL gates.

The [guided centering repair ledger](../audits/centering-guided-repair.md) records
the approved October-2 working-tree implementation at `73898e8`. It supersedes
older centering failure counts as current guided-workflow evidence: 109 centering
cases have one failing latency case (two assertions), and the remaining 1,661
cases have zero failures with seven existing skips. The final regression reruns
1,692 cases (including 31 centering UI/export cases), with seven existing skips
and zero failures; ReleaseLocal and final phone/tablet visual checks also pass.
Guided transform tests now
use independently annotated reviewed frames; original automatic comparisons and
their unchanged tolerances remain explicit open research gates. Automatic
reporting stays disabled. The owner accepted deferring latency, without weakening
the speed assertions. The approved immutable revision export work also supersedes
the earlier measure-only thread-placement restriction for that specific change;
device performance and manual/release acceptance are still separate gates.
Native phone share-sheet and iPad popover presentation were observed in the
simulator; physical-device share/save completion and VoiceOver remain open.

The later October-2 uncommitted-change review in that ledger adds two geometry
regressions and five focused fixes. Its seven-class run has 111 cases with only
the existing latency case failing; the final UI/export/input rerun passes 33
correctness cases. Earlier counts above remain dated snapshots. A locked Mac
blocks the final numeric-field accessibility-tree and incomplete inner-capture
rechecks, so earlier visual evidence does not certify those latest view edits.

The [additional production refinement review plan](october-production-refinement-review-plan.md)
records the source review at `73898e8`: transient cooldown/monthly-period
accounting, manual catalog recovery, batch/scanner stale-result publication,
Magic live directories, ownership/price display, activity read errors, and
publisher validation. On 2026-10-03 the user authorized implementation: slice A
unifies rate-limit cooldowns in the uncommitted working tree against `dd2a1e3`,
with 121 focused simulator tests passed. B–J are implemented: final regression
executes 1,714 cases (1,707 passed, seven existing skips, zero failures), and the
publisher package passes 74 tests. The initial full run was not clean; the plan
records its corrected mock/pricing failures and unchanged centering latency
failure. K preserves that latency disposition and the automatic accuracy gates.
The owner requested wrapping up without further screenshots or device-specific
testing; L/M measurement, rendered/native/device acceptance remain deferred.
Live legal/support pages remain placeholders.
The plan records this evidence separately
from its source-review baseline and does not replace the earlier October plan.
At the original review's documentation time, pre-existing uncommitted centering
changes already move export preparation off
the main actor; the review's centering-export hypothesis must be revalidated
against that work. The existing centering contract/triage, URL dependency, and
release-follow-up measurements remain their single respective authorities.

## One Piece design and implementation reconciliation — 2026-10-04

Latest coverage checkpoint: the full ordinary batch covers 58 product groups and
2,731 selected release/artwork identities. The adopted corpus has 2,692 canonical
cards and 2,745 printings (2,490 verified, 224 provisional, 31 conflicted),
8,237 combined observations, 2,940 captures and 257 open discrepancies. All 817
earlier printing/artwork records and 794 canonical records remain unchanged;
all five outputs replay exactly. Unsigned revision 13 validates against revision
12 as protected review. All 42 selected Python tests pass. The core run reports
39 passes and one new assertion failure: the test incorrectly assigned base
EB04-061 to OP17 rather than OP15; the corrected affected test now passes.
No full-suite repeat was needed. App coverage is 41 initial passes plus two
corrected affected tests: Browse contains 52 verified-target groups rather than
all 60 retained products; wholly provisional ST30/ST31 products remain unowned.
The expanded scan/save cases pass. A full-corpus isolated local kit is signed and
independently verified; its 16,119,026-byte envelope remains below the 48 MiB
transport limit. Cold activation/memory and rendered/device acceptance remain open.
No signed/public production release or complete physical universe is claimed.
The efficiency-audit figures below are historical snapshots.

Latest efficiency audit: the current worktree has 534 canonical cards, 547 physical
printing records (446 verified, 93 provisional, eight conflicted) and 1,727
observations. Reviewed standard coverage reaches ST-10 and OP-03, including two
ST-10 reprints of OP-01 numbers. Earlier milestone logs confirm 40 core and 40
One Piece integration tests passed. The subsequent correction checkpoint reports
41 of 42 selected tests passing, then a passing focused rerun after fixing the
remaining test fixture; no clean full 42-case rerun is recorded. This documentation
audit reran no tests. Earlier
canonical-only, synthetic-only and small-demo-next claims below are historical.
The [implementation ledger](one_piece_code_implementation.md) now prioritizes
remaining correctness gaps, reproducible larger catalog batches, necessary
legacy routing and integrated acceptance. It limits repeated builds/signing and
retains full coverage, physical identity, rights and sync gates. No implementation
or production change is authorized by this documentation-only pass.

The subsequent code/file-level handoff names the exact correction authority,
product manifest/capture pipeline, legacy extraction destinations, signed seed
filename, three-namespace hosting preservation and focused regression targets.
Proposed API/file names are explicitly distinguished from existing source.
External rights/key/sync inputs remain owner decisions, not choices delegated to
the implementing developer. This follow-up changes plans only.

The latest handoff review separates already-implemented correction work from the
remaining publication-order/withdrawal checks. It prescribes a container-bound
activation source boundary, product/discrepancy fields, retained-byte migration
before capture expansion and explicit capture-orphan recovery. It also corrects
verification to the recorded `TradingCardScanner`/`Debug` checkpoint and existing
test files. This adds implementation instructions, not new passing evidence.

The owner subsequently authorized the full code-level implementation after its
source review. The [implementation ledger](one_piece_code_implementation.md)
records the revised correctness contracts and A–N delivery gates in the
`one-piece-integration` worktree, based on `69c714f`. The integration design now
explicitly distinguishes its original documentation change from that later
authorization. One Piece production support and external acceptance remain
disabled/unverified until the ledger records direct evidence.

The [One Piece integration plan](one_piece_catalog_integration_plan.md) records
the owner's older multi-source audit against `dd2a1e3` plus the existing working
tree. The Pokémon/Magic-only architecture claim belongs to that historical
baseline. The 2026-10-04 worktree audit includes new/untracked files as well as
tracked diffs: open game identity, runtime/recognition adapters, One Piece core,
local scanner/Browse/import/recovery fixtures and signed preparation/bootstrap
now exist. They do not establish production support. The plan retains Bandai
discovery, Limitless reconciliation, Scrydex enrichment, and permanent local
printing IDs, but replaces the draft's
confidence-based automatic physical selection with the current deterministic
resolution and user-choice contract. Signed delivery requires its own One Piece
schema and key/rollout boundary; existing game releases are patterns, not a
ready-made One Piece physical-printing catalog. Historical vendor counts,
coverage percentages, image/licensing statements, and ship-readiness language are
explicitly unverified. Pricing-provider selection and shared-cache publication
remain governed by their current plans. A weekly thread monitor is scheduled;
neither that schedule nor this documentation is ingestion or release evidence.

The code-level ledger's earlier “next: generic picker/recovery, then core/runtime”
sequence was stale after those implementations. Its current priority is a usable
local slice with a small real reviewed English corpus, collector-distinguishable
printing choices and complete unsupported-row/recovery guards. Keep shared seams
needed for the owner's planned Lorcana integration; defer optional abstraction
and provider work. Remaining legacy catalog/Browse dispatch still fails the final
architecture audit; the script alone does not cover every explicit game branch.

The audit also records a shared-host delivery gap: existing Pokémon/Magic
deployments restore only their two namespaces. One Piece publication there must
first make every deployment preserve all namespaces. Synthetic fixtures, signing
artifact uploads and disabled bootstrap configuration are not corpus, protected
hosting, CloudKit or launch-performance acceptance. This pass changed plans only
and ran no builds/tests; prior checkpoint counts remain dated, overlapping evidence.

The subsequent 2026-10-04 plan-only follow-up inspected the current picker source
and existing 52-case passing log. Bounded scrolling, optional artwork/footer
metadata and old-choice compatibility are now implemented, so the unbounded-grid
finding is historical. The owner rejected the verbose presentation and requires
the same compact option-button format as Pokémon/Magic. The
[visual checklist](one_piece_printing_choice_visual_checklist.md) remains
unaccepted; detailed provenance belongs on demand, while essential distinctions
must stay visible. Finish resolution already uses the shared `VariantChoiceBar`.
This changes the next UI task, not physical identity, catalog completeness or
production gates. No source changes, build/test reruns or new simulator evidence
were produced by this follow-up.

The resumed implementation then replaced the verbose picker with that compact
format. The visual checklist now records scoped final fixture captures and
native Details/skip/final-candidate checks; it retains real-corpus, loaded-artwork,
VoiceOver/device and owner acceptance gaps. The current ledger separates this
implementation evidence from the earlier plan-only audit and rejected rendering.

The later source-ingestion checkpoint retained six exact Bandai/Limitless HTML
captures externally and 30 normalized observations in the
[English stress-source review inputs](../../OnePieceCatalogCore/ReviewCorpus/english-stress/README.md).
The earlier blanket description of all corpus inputs as synthetic is superseded:
real discovery metadata now exists, while physical-printing fixtures remain
synthetic and the real review registry has no physical UUIDs or automatic authority.
Eight bounded-parser/CLI tests and 31 core tests pass locally; no app build,
live workflow, physical corpus certification, asset redistribution or production
activation is claimed.

## Lorcana research import — 2026-10-03

**2026-10-04 recalibration:** the [Lorcana implementation plan](lorcana_code_implementation.md)
is now the execution authority for the existing uncommitted `one-piece-integration`
worktree at base `69c714f`. Shared runtime/recognition/catalog/recovery boundaries
replace the older proposal to start by importing the entire game. Slice 1 adds
local provisional print-family mappings, conservative complete-footer recognition
and generic incomplete lookup/recovery. Forty-four focused simulator tests pass,
including 13 new Lorcana cases. Provider codes are not assumed to be printed
markers; print-family keys are not physical ownership IDs. The imported research's
finish-classifier-first and variant/stamp hierarchy are superseded by the current
physical-printing-before-finish design. Real corpus, source rights, production
activation and collection sync remain open; the research release timeline is not
revalidated or adopted as completeness evidence.

The [Lorcana data, variant, and scanner-architecture audit](../audits/lorcana-data-variant-scanner-architecture-audit.md)
preserves an owner-supplied deep-research report as design input. Its proposed
footer-OCR and print/variant identity model is not implementation evidence:
current source and tests still determine supported games and behavior. The
report's inline citation identifiers belong to its originating research session
and cannot be resolved from this repository. Recheck time-sensitive release,
API, completeness, and licensing claims against their linked primary sources
before using them for implementation or release decisions.

## Latest two-set pricing evidence — 2026-09-30

The [pricing coverage plan](browse_pricing_coverage_plan.md) now records a
device-local TCGCSV exception for 30th Celebration and Classic Collection.
Statements below and in the older Phase 6 discussion that retain pokemontcg.io
as the bulk provider apply to the general Pokémon path; these two sets use
reviewed exact product/finish mappings. A general successor remains unresolved,
and published Stage 4B prices remain disabled. The focused simulator selection
passed 322/322 and the live production client validated all 188 mapped Holofoil
quotes. This evidence does not certify physical-device or release readiness.

## Latest catalog rollout evidence — 2026-09-20

The production catalog baseline is hosted revision 1, signed with the pinned
production public key. The committed app configuration is now
`remote-authority`. The validation-only online/relaunch rehearsal and the
focused/broader catalog suites passed after commit `54960fd` (8/8 focused,
64/64 broader); the one-off authority rehearsal activated hosted revision 1 on
the dedicated simulator, persisted `current = 1` with no previous slot, and
treated the identical relaunch fetch as `notModified` rather than a rejection.
The current checkout keeps release schema 1 and adds optional
`providerFingerprint` descriptors, a shared canonical provider-content
fingerprint, a separate local probe fingerprint, durable targeted device
reconciliation, and workflow classification that sends only post-baseline
content-only candidates to the automatic publication environment while routing
baseline, authority, new-set, and unknown changes through the protected
reviewer environment.

Workflow run [35443012617](https://github.com/Razorback2424/CardScanner/actions/runs/35443012617)
validated a no-op revision-2 candidate: all 28 descriptors, card counts,
provider fingerprints, and snapshot entries matched revision 1. The protected
publish job was canceled before signing or deployment, so hosted revision 1
remains current and the candidate is evidence only. Physical-device authority,
the genuine offline case, production cutover, synthetic behavior change, and
the first real catalog update remain open gates.

## Exact-candidate simulator evidence — 2026-09-20

The focused cross-area selection was run against `7dbaf40` on the iPhone 17 Pro
iOS 26.5 simulator with external-SSD DerivedData, module caches, package cache,
and result bundles. It executed 581 tests: 579 passed, 1 skipped, and 1 failed
in `ScannerViewModelTests/testCatalogMissVerificationStillFilesUnresolvedCard`.
The storage-safe full suite then executed 1,278 tests: 6 skipped and 4 failed
(1 unexpected), with failures in centering, ownership-ledger, and the same
scanner catalog-miss area. The external-SSD artifacts are under
`exact-7dbaf40/focused.xcresult` and `exact-7dbaf40/full-shell.xcresult`; the
prior `a4375df` suite remains historical.

## App Review remediation evidence — 2026-09-22 (snapshot at `main@9759050`)

At this snapshot, the workspace was clean at `main@9759050`. The scanner, price-refresh,
storage-bootstrap, manifest-protection, and bulk-operation remediation is
committed. The root [`app_review_fix_plan.md`](../../app_review_fix_plan.md) is
the implementation and acceptance authority; the
[`release_followups.md`](release_followups.md) document retains the residual
runtime, device, provider, and scale evidence. The affected 99-test simulator
selection with one Simulator-only protection-attribute skip, the separate
delete-actor integration test, and the broader normalization run were recorded
against the preceding `810954e` working-tree snapshot, not `9759050`. The full
suite and exact-HEAD device evidence remain open. The Release privacy/support
destinations are still owner input.

| Area | Current authority | Code/evidence boundary |
| --- | --- | --- |
| Product scope and roadmap | [`README.md`](../../README.md), [`CardScanner Collection Integrity Strategy`](../vision/CardScanner%20Collection%20Integrity%20Strategy%20%E2%80%94%20Start-to-Finish%20Implementation%20Plan.md), and the [active launch plan](../superpowers/plans/2026-09-13-phase-0-phase-1-app-store-launch.md) | The current Swift target and tests decide what is implemented; roadmap prose does not add product behavior. The launch plan's §0.1.1 binds open pass-2 findings to the tasks they block, and §0.1.2 lists current plans outside launch scope; both are required reading before a task is started. |
| Browse/Catalog | [`browse_screen_spec.md`](browse_screen_spec.md), [`browse_success_checklist.md`](../../references/browse_success_checklist.md), `TradingCardScanner/Views/BrowseView.swift`, and `TradingCardScannerTests/BrowseFeatureTests.swift` | Browse is a Collection push destination. The focused set-directory hardening selectors pass 133/133 with 0 failures, including invalid/valid cache bodies and symbol-prefix recovery. A8/B6 remain closed by the settled light/dark rerun2 evidence in [`pokemon_browse_checklist.md`](../../artifacts/pokemon_browse_checklist.md); provider/device checks remain open. |
| Automatic Pokémon set updates | [`automatic_pokemon_catalog_updates_plan.md`](automatic_pokemon_catalog_updates_plan.md) | Slices A–E are implemented. Slice F's production-host revision-1 rehearsal and same-revision relaunch handling are complete as of 2026-09-19. The committed production app configuration is `remote-authority`; schema-1 additive fingerprinting, canonical publisher/device parity, fail-closed classification, durable targeted reconciliation, parent-artwork metadata, and set-specific Browse updates are implemented and the latest focused verification is Core 38/38 plus app 37/37. Protected baseline publication, auto-environment setup, four-hour scheduling, physical-device/offline evidence, the first real catalog update, and release gates remain open. |
| Magic catalog signing and publication | [`magic_catalog_key_handling_runbook.md`](magic_catalog_key_handling_runbook.md) | Current authority for Magic-specific key custody, signed catalog releases, protected/automatic publication routing, Scryfall boundaries, and rollout safeguards. The Magic-specific key pin remains owner input; rollout remains `legacy-live`. |
| Artwork fallbacks | [`artwork-fallback-plan.md`](artwork-fallback-plan.md), `TradingCardScanner/Services/ArtworkFallbacks.swift`, and Browse tests | P0–P3 are implemented in the current tree; TCGdex-only stem/WebP candidates, symbol sibling-prefix recovery, decode-before-persist, legacy-cache eviction, and coalesced requests pass in the 133/133 focused run. Broader provider behavior and licensing are still operational gates. |
| Scanner workflow | `TradingCardScanner/Views/ScannerViewModel.swift`, the current [scanner module review](../audits/scanner_module_review.md), [explicit Raw / Slab scanning mode plan](explicit-raw-slab-scanning-mode.md), [scanner recognition remediation plan](scanner-recognition-remediation.md), [release follow-ups](release_followups.md), [`scan_cancellation_success_checklist.md`](../../references/scan_cancellation_success_checklist.md), and `progress.md` | The scanner module review remains authoritative for tracking/OCR findings and measurements. Explicit Raw / Slab mode is implemented in the 2026-09-23 working tree. The 2026-09-24 recognition/remediation implementation and 2026-09-25 review corrections are recorded in the linked plan and progress. The current focused correction selection passes 229/229; the earlier 1,561-test non-centering result was not rerun against this follow-up. Physical stack, live-provider, Instruments, and release acceptance remain open. The slab-specific automatic-detection and blocking-price recommendations in the archived scanning workflow review are superseded by the new plan. |
| Pricing and portfolio performance | [`price_refresh_scale_plan.md`](price_refresh_scale_plan.md), [`release_followups.md`](release_followups.md), and the current services/tests | The 2026-09-22 fix plan tracks no-provider sentinels and bounded refresh eligibility. Large-store measurement, Magic batching, resumable sweeps, and physical-provider profiling remain open. |
| App Review and release | [`app_review_fix_plan.md`](../../app_review_fix_plan.md), [`app_review_preflight.md`](../../app_review_preflight.md), [`card-scanner-1.0-go-no-go-framework.md`](../release/card-scanner-1.0-go-no-go-framework.md), and the [current evidence ledger](../release/phase-1-integrity-evidence.md) | The last clean app-review baseline is `main@9759050`; its recent focused evidence is from the preceding `810954e` worktree snapshot. The current working tree is based on `main@30bd84e` and includes the Raw / Slab scanner work recorded above. CloudKit/device, archive/TestFlight, centering, actual privacy/support URLs, and other App Store gates remain open. |
| Card centering | [`review/opus-card-centering-implementation-plan.md`](../../review/opus-card-centering-implementation-plan.md) and [`review/centering-evidence/`](../../review/centering-evidence/) | Dated experiment artifacts remain inside the current evidence ledger; the active contract and its open accuracy/invariant/latency/device gates are authoritative. |
| Legal and future website | [`legal/privacy-policy.md`](../legal/privacy-policy.md), [`legal/support.md`](../legal/support.md), and [`CardScanner-Website-Implementation-Spec.md`](../CardScanner-Website-Implementation-Spec.md) | The website specification is a future website contract; no website source is present in this iOS repository. Its canonical support route is `/support`. |
| Known production defects | [`../audits/defect_review_pass_2.md`](../audits/defect_review_pass_2.md) | The six-finding baseline was audited against `a4375df` (five confirmed, one suspected). F01–F03 source remediation is now landed and focused-verified; the audit has not been rerun at intended candidate `7dbaf40`, and entitled-device/runtime evidence remains open. Pass 1 in `docs/legacy/` is a 2026-09-09/10 snapshot and was not re-reproduced. |
| Browse set directory defects | [`browse_set_directory_remediation_plan.md`](browse_set_directory_remediation_plan.md) | Implementation landed 2026-09-15 for the set-tile artwork chain, extensionless/TCGdex-WebP recovery, checklist-backed denominators, empty-set exclusions, incremental/deduplicated price sort, shared-detail cancellation hardening, truthful price-load state, single completion-index ownership, deterministic candidate priority, retry-triggered rebuilds, duplicate-ID-safe checklist reuse, and memory-purge waiter safety. The 2026-09-16 focused selectors pass 133/133, including decode-before-persist, legacy-cache eviction, host gating, and symbol sibling-prefix regressions. A8/B6 remain closed by the final settled rerun2 capture; provider/device measurement C7/RF-9 remains open. |
| Pro tab and eBay listing photos | [`pro_tab_ebay_listing_photos_plan.md`](pro_tab_ebay_listing_photos_plan.md) | Slices A–C and the F1–F7 review remediation are implemented in `main` (merged 2026-09-20 from the isolated worktree based at `523f3e2`); the latest focused remediation selectors pass 14/14 and the Debug simulator build/run succeeds. It owns the Pro tab shell that replaces the centering tab and the new card-independent eBay listing-photo module. It changes where card centering is presented (one navigation level deeper, no inner `NavigationStack`) but not how it measures; the centering contract and its open gates stay in [`review/opus-card-centering-implementation-plan.md`](../../review/opus-card-centering-implementation-plan.md). Screenshot, manual, physical-device, provider, archive, and release gates remain open; SwiftData persistence against a card is out of scope. |
| Per-card price history chart | [`price_history_chart_plan.md`](price_history_chart_plan.md) | Proposed 2026-09-14, **not implemented**. Slice A is rendering only; the pass-2 F02 source dependency is remediated and focused-verified, while Slice B still requires the RF-8 device measurement. Provider history backfill is a recorded rejected option, not backlog. |

## Disposition — 2026-09-14

No documentation was deleted. Completed, superseded, or snapshot-specific
material was moved into explicit legacy locations, and current replacement
paths were kept where a caller or release workflow depends on them.

| Material | Legacy location | Current replacement or rule |
| --- | --- | --- |
| Duplicate app-review plans and old candidate evidence | `docs/legacy/app_review_fix_plan.md`, `docs/legacy/app_review_preflight.md`, `docs/legacy/phase-1-integrity-evidence.md`, `docs/legacy/ownership-ledger-completeness-audit.md` | Root app-review files and the current release/ownership ledgers are the only current authorities. |
| Old repository gap and first defect audit | `docs/legacy/collection-integrity-codebase-gap-analysis.md`, `docs/legacy/defect_review_pass_1.md` | Current source/tests, the launch plan, the release framework, and this audit. |
| Completed or superseded feature plans | `docs/legacy/collection_tile_*`, `design_slices_plan.md`, `graded_price_lookup_fix_plan.md`, `magic-finish-treatment-coverage-plan.md` | Current source, focused tests, `progress.md`, Browse/artwork plans, and release follow-ups. |
| Historical price/performance snapshots | `docs/legacy/performance_review_remediation_plan.md`, `docs/legacy/price_refresh_scale_plan.md` | Current [`price_refresh_scale_plan.md`](price_refresh_scale_plan.md) plus [`release_followups.md`](release_followups.md). |
| Scanner workflow review snapshot | `docs/legacy/scanning-workflow-review.md` | Its pre-remediation F1–F5 lifecycle findings remain historical. Use the current [scanner module review](../audits/scanner_module_review.md) for module-level defects and concerns, plus the cancellation checklist, release follow-ups, and dated progress entries for their respective scopes. |
| Graded slab scanning recommendations in the scanner workflow review | `docs/legacy/scanning-workflow-review.md` | The slab auto-detection and blocking vendor-resolution recommendations are superseded by [`plans/explicit-raw-slab-scanning-mode.md`](explicit-raw-slab-scanning-mode.md), the current proposed design for explicit Raw / Slab modes. The archived review remains available for provenance. |
| Trust-hardening and whole-repository review snapshots | `docs/legacy/2026-09-10-*`, `review/legacy/` | Current centering contract/evidence and current release ledgers; archived review findings are historical inputs only. |

## Plan contradictions requiring reconciliation

The table distinguishes contradictions that are already resolved in the current
tree from release decisions that still require evidence. An archived document
may continue to contain the old side of a contradiction; its legacy banner is
the required warning, not a reason to rewrite history.

| ID | Contradictory claims | Current code/evidence check | Resolution |
| --- | --- | --- | --- |
| C-01 | Earlier Browse material treated Browse as a fourth/top-level tab; the current navigation model treated it as a Collection child. | `TradingCardScanner/Views/ContentView.swift` now defines Portfolio, Collection, Scan, and Pro tabs; `ProView` owns the Pro stack, while `TradingCardScanner/Views/CollectionView.swift` defines `Destination.browse`. | Resolved. The current Browse plan and checklist say `Collection → Catalog`; the old wording is historical. The isolated Pro implementation does not move Browse or alter the Collection navigation contract. |
| C-02 | The Browse plan read like future implementation work while Browse/Catalog behavior was already present in source and progress. | `CatalogGameBrowseView`, `CatalogSearchResult`, sealed content, release rail, grouping, and fallbacks are in the current source; focused selectors pass 133/133, and A8/B6 have a settled light/dark capture. | Resolved. The current plan is labeled an implemented acceptance contract; only live-provider/device measurement C7/RF-9 remains open. |
| C-03 | The Magic treatment plan described two modeled signals and an unimplemented 5,150-entry target. | `MagicTreatment.modelled` contains 31 cases; `MagicTreatmentTests` assert 31 and a 5,150-entry catalog with schema version 2. | Resolved by archiving the old coverage plan. Use source/tests and progress for current coverage. |
| C-04 | The 2a collection-footer specification and 4a footer plan describe competing layouts and open work. | `TradingCardScanner/Views/CollectionView.swift` renders the settled name, set/number, price, and combined status footer; current collection tests cover the behavior. | Resolved by archiving both snapshots. The current UI/source and tests control; a new footer change needs a new dated plan. |
| C-05 | The scanner workflow review listed F1–F5 as open defects after their lifecycle fixes landed. | `ScannerViewModel` clears/cancels `identificationTask`; the old `resolutionTask`, `undoLastAdd`, and `activeFinishLocks` symbols are absent from production; focused receipt/cancellation evidence is recorded. | Resolved as documentation status. Physical camera, thermal, provider, and full-suite evidence remain separate open gates. |
| C-06 | The old performance/price plans described main-actor refresh work and Slice 6 as proposed, while later code moved persistence behind a model actor. | `PriceRefreshModelActor`, `CollectionProjectionActor`, and value snapshots exist; `ContentView` no longer observes refresh as a whole-screen object. `PortfolioInputObserver`, Magic batching, and resumable sweeps are still open. | Resolved by archiving the detailed snapshots and keeping a short current scale plan that separates landed slices from open measurements/work. |
| C-07 | Duplicate app-review plans used different candidate branches, SHAs, suite counts, and authority locations. | The intended candidate is clean `feature/catalog-and-scanner-hardening` at `7dbaf40`; root app-review files identify the earlier `codex/scanning-workflow-review-remediation`/`0b4ac34` and `fix/app-review-preflight`/`a115e4e` data as historical. | Resolved by keeping root files as current summaries and moving the duplicate snapshot plans into `docs/legacy/`. |
| C-08 | Older release evidence and ownership documents appeared to certify earlier candidate identities, while the current checkout is different. | Current ledgers identify clean `feature/catalog-and-scanner-hardening`/`7dbaf40` and explicitly say NOT CERTIFIED; the latest complete full run at `a4375df` executed 1,277 with 6 skipped and 40 failures. The earlier 1,256-discovered/48-failure snapshot is historical at `0b4ac34`; the 2026-09-16 centering rerun was focused and partial (see C-11). | Resolved as an authority conflict. Production CloudKit, ownership, archive/TestFlight, and clean-candidate evidence are still open. |
| C-09 | The release framework and CloudKit audit describe storage/sync continuity as source-hardened with only **external enrollment** outstanding, which reads as “no known code defect in this area.” | The pass-2 audit's F01/F02 were deterministic source traces at `a4375df`; their source remediation is now present and focused-verified in `main`, while entitled-device/runtime evidence remains open. | **Partially resolved.** The source findings are addressed, but the enrollment/runtime gate remains open. Keep the audit snapshot as historical diagnosis until it is rerun against the current tree; gate rows remain open in the release framework. |
| C-10 | C-05 records the scanner workflow F1–F5 as resolved, which reads as “this area has no open findings.” | Pass 2 F03 was a **new suspected** finding at `ScannerViewModel.swift:2271` (`beginPendingResolution` could discard a choose-handler operation), not a restatement of F1–F5. The C-05 lifecycle fixes were separately re-verified; F03's recoverable-retention remediation is now focused-verified, but the pass-2 audit has not been rerun. | **Resolved for current source status, open for release evidence.** C-05 stays resolved for its own scope; F03 remains a dated audit finding and its runtime/release implications remain subject to the current App Review and release gates. |
| C-11 | `progress.md` and the entries above characterise the full-suite failures in aggregate as “unrelated fixture/source-environment or signal-kill failures.” | The pass-2 run at `a4375df` executed 1,277 with 6 skipped and 40 failures; its 36 corpus lookup failures came from duplicate PBX IDs, not absent repository files. The 2026-09-16 focused rerun after the project fix reached the corpus: 38 results, 28 passed, 9 test cases failed on centering assertions, and 1 profile test was canceled. Fixture reachability and manifest tests passed; the full target was not rerun. | **Updated.** Preserve the pass-2 counts as historical and keep failures classified per suite. Do not add skip guards for the committed corpus. The PBX resource collision is fixed; the centering assertions and complete-suite evidence remain open under F06/RF-6. |
| C-15 | The launch plan's plan-authoring gap list called StoreKit/purchase gating part of the release, while the current strategy and framework define a free 1.0 with no StoreKit. | The active strategy and release framework say free 1.0/no StoreKit; no StoreKit implementation is required for this scope. | Resolved as a product decision. StoreKit remains a future, separately approved monetization experiment, not a current launch defect. |
| C-16 | The launch plan said the website specification still froze `/contact`; the tracked specification already uses exactly `/, /privacy, /terms, /support`. | `docs/CardScanner-Website-Implementation-Spec.md` lists `/support` as the fourth route and defines its support page. | Resolved at the document level. The launch plan now records the route task as reconciled; website implementation/deployment remains future work. |
| C-17 | The old 2026-09-12 progress checkpoint and earlier 940/1,205-test snapshots could be read as current repository readiness; 1,095 remains a valid result only for the separate centering experiment. | The latest complete full run is the `a4375df` pass-2 run (1,277 executed, 6 skipped, 40 failures). The 1,256-discovered/48-failure count at `0b4ac34` is historical; the 1,095 result remains a scoped centering baseline. | Resolved by retaining old general-suite entries under historical headings, preserving the scoped centering result, and adding dated current checkpoints. New evidence must be appended chronologically. |
| C-18 | The shared-pricing-backend plan calls its commercial/licensing preflight “Phase 0,” while the product strategy and launch plan call retention-contract freeze “Phase 0.” | `docs/plans/shared_pricing_cache_plan.md` describes a future backend with device-local pricing still current; `docs/experiments/collection-integrity-v1-retention-contract.md` freezes the active app Phase 0. | Resolved by making the backend phase name explicitly scoped to that future project. It cannot alter free 1.0 or start Firebase work before its own gates A–C. |
| C-19 | [`browse_screen_spec.md`](browse_screen_spec.md) § 8 specified the set tile footer as `3 of 207` — a distinct-collector-number numerator over `set.cardCount` with the unit `cards` — while the set screen showed master-set **variation** slots owned over the built checklist length. | The current source now treats an all-zero provider variation breakdown as unpublished, carries standard/expanded checklist slot counts in the manifest, and uses `CatalogSetCompletionIndex` for both the tile and set screen. The spec subsection was reconciled on 2026-09-15. | **Resolved in source, contract, deterministic evidence, and authorized visual evidence.** Focused Browse selectors pass 133/133 with 0 failures, and the external-SSD snapshot check confirms denominator parity for all 157 entries. Pokémon uses the checklist-backed `variations` unit, with the bounded overflow explicitly labeled `cards`; Magic retains provider card totals. A8/B6 visual confirmation is recorded in [`pokemon_browse_checklist.md`](../../artifacts/pokemon_browse_checklist.md); C7/RF-9 remains open. |
| C-20 | The archived scanner workflow review and broad release notes could be read as the complete current scanner review, with only lifecycle fixes and generic camera/thermal/8 Hz measurement work remaining. | The current scanner module review covers `CardScanner`, `CardLatch`, OCR/ROI and slab framing, camera capability selection, `CameraPreview`, and scanner callback paths. It records five confirmed findings (historical OCR retry exhaustion, debug ROI mapping, scan-band ROI mismatch, bad-frame accounting, and macro-lens focus-distance probing) plus three concerns requiring measurement. | **Superseded.** [`audits/scanner_module_review.md`](../audits/scanner_module_review.md) is the current authority for this module scope and its findings. The archived F1–F5 lifecycle status remains valid only for that narrower historical scope; RF-2/RF-5 remain open measurement gates and must include the new review's OCR/tracking and session-length evidence where applicable. |

## Update plan

1. Before changing a status line, inspect the named source type, test, build
   setting, or evidence artifact and record the exact current checkout identity.
2. Keep one current authority per concern in the [documentation map](../README.md);
   move completed or superseded snapshots to `docs/legacy/` or `review/legacy/`
   with a banner and a current pointer. Do not delete them.
3. Keep current plans concise and status-first: distinguish implemented code,
   deterministic verification, manual/device/provider evidence, and owner- or
   vendor-controlled gates. Do not turn an old unchecked task into a current
   defect without reproducing it.
4. Add a dated entry to `progress.md` for each verified implementation or
   evidence change, then update the smallest relevant checklist or ledger.
5. Run a repository Markdown-link check after moves and review all remaining
   current-document references for old branches, SHAs, test counts, routes, and
   monetization claims. Historical references may remain only inside clearly
   marked archives.
6. Re-run the release gates in the current ledgers before calling the checkout
   certified. The current open gates are not closed by this documentation pass:
   production CloudKit/ownership proof, clean exact-candidate regression,
   physical scanner/provider validation, Browse manual sign-off, centering,
   archive/TestFlight inspection, and App Store submission evidence.

> **Amended 2026-09-12.** The checkpoint below is the repository-audit snapshot captured on 2026-09-09. It is historical and must not be used as the current card-centering test count or readiness claim. The active card-centering contract, experiment ledger, simulator evidence, and current branch results are maintained in the [current card-centering plan](../../review/opus-card-centering-implementation-plan.md) and [centering evidence](../../review/centering-evidence/).

## Historical checkpoint — 2026-09-09

- The review-time Debug build ran on the iPhone 17 Pro simulator
  (`EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86`).
- The review-time simulator suite discovered 940 tests: **939 passed, 1 skipped,
  0 failed**. The skipped case is the opt-in aged-store/performance fixture.
- This run emitted 11 non-failing build notices: nine normal signed XCTest
  simulator-binary strip notices and two benign AppIntents metadata notices.
  No Swift compiler warning appeared in this run; if the test-only concurrency
  warnings from an earlier build recur, treat them as cleanup rather than a
  claimed release blocker.
- The deterministic `MagicTreatmentSlice4` route initially crashed because
  its debug overlay was outside the `CollectionProjectionStore` environment.
  `ContentView` now injects that environment object and the route was rebuilt,
  launched, scrolled, and inspected successfully. This was a real loose end,
  not documentation-only cleanup.

## Current card-centering pointer

The current centering branch retains the newer quad/Vision/rectification implementation and has a default raw-HEIC E-A/E-B result of 8 confident and 2 declined fixtures. The screenshot batch remains a pre-E-B historical 3-confident/7-declined snapshot. Ground truth was rederived on 2026-09-12 with two analyzer-free profile passes plus physical-silhouette adjudication; its provenance/schema gate passes 10/10, while the first current production-entry-point suite passes 8/12 test cases and fails 4 accuracy cases. The refreshed post-REQ-027 E7 resolution curve keeps the missing-inner-reference fixture declined at all four tested maxima in both benchmark curves. The exact sideways/skewed REQ-028 regression methods also pass 2/2 in a focused current run. The current contract and open gates are recorded in the [card-centering plan](../../review/opus-card-centering-implementation-plan.md), not in this 2026-09-09 audit snapshot.

## Historical evidence-backed status — 2026-09-09

“Closed” below meant the implementation had source/test evidence and, where
applicable, a simulator capture at audit time. “Partial” meant a deterministic
surface is verified but the remaining real-device, network, or interaction
evidence was still named explicitly at the time of this audit. This table is
historical for the broader repository; the current centering status is in the
pointer above and the linked centering contract.

| Area | Status at audit time | Evidence |
| --- | --- | --- |
| Finish Lock | **Closed for the current design** | One top-level `Auto` clears all locks; Pokémon and Magic expose variant-only submenus; game-qualified summaries and accessibility labels are present. Supporting `finish_lock_checklist.md` and `finish-lock-global-auto-*` captures are ignored local artifacts, not durable repository files. |
| Card detail / identity / sealed artwork | **Closed for the audited UI slices** | Current dark/light/accessibility-large captures and focused/full-suite coverage are recorded in the three existing checklists. |
| Collection navigation | **Closed for compact-width behavior** | Collection → card detail → Back returns to the collection grid; the `collection-navigation-current.jpg` capture is an ignored local artifact. The intentional iPad split-view empty pane remains a separate behavior. |
| Card movement | **Closed for the deterministic fixture** | Card detail and Movement Details show the selected period, unit movement, quantity, and holding impact; the three-copy `-$0.05 × 3 = -$0.15` case is captured in the ignored local `card-movement-current.jpg` artifact. |
| Portfolio Today / Phase 3 / market movement | **Closed for the current additive model** | Current-value hero, reconciliation, movement chart, contributors, and most-valuable-card ranking are captured in the `portfolio-*` artifacts. The old Performance/Collection Value presentation is intentionally gone; [`release_followups.md`](release_followups.md) records that cleanup. |
| Magic treatment Slice 4 | **Closed for the deterministic route after the environment fix** | Receipt and catalog detail show the FIC #10 treatment path; the nonfoil contradiction remains source/test evidence rather than a separate visual route. The supporting `magic_treatment_slice4_checklist.md` is an ignored local artifact. |
| Browse | **Partial but no longer unverified** | Browse root and the bundled Pokémon directory launch without a catalog request; full search, exact-printing add/undo, remote artwork, and fallback-provider behavior remain interaction/provider checks. |
| Price Check | **Partial but no longer unverified** | The native purpose control and no-add routing are visible. The “Value only · Nothing is added” explanation is intentionally shown at choice time and in the VoiceOver announcement, not as permanent camera copy. A real scan/result/refresh-failure pass remains device/provider work. |
| Whole-card scanner / scanner chrome | **Partial** | The deterministic route and source-level hit-target/state behavior are available. Real camera guide, OCR-rate, thermal, tab-return, and camera-restart claims remain hardware gates. |
| Centering | **Tracked in the current card-centering contract** | This 2026-09-09 capture predates E-A/E-B and must not be used for current centering readiness. See the [current plan](../../review/opus-card-centering-implementation-plan.md) and [centering evidence](../../review/centering-evidence/). |

## Live gates that remain open

These are intentionally not “90% implemented” items to be silently marked done.

- [`release_followups.md`](release_followups.md) is the source of truth for
  collection cold-launch timing, 8 Hz scanner tracking, projection coalescing,
  additional graded-label samples, and live refresh/camera profiling.
- [`app_review_fix_plan.md`](../../app_review_fix_plan.md) still has evidence or
  product-owner gates for stale vendor-variant invalidation, migration
  serialization, store/account epoch scope, fan-out and large-session
  measurement, ProductIdentity misses, and the production bundle ID and
  entitlements. Its unchecked items are deliberate review gates, not forgotten
  implementation tasks.
- [`performance_review_remediation_plan.md`](../legacy/performance_review_remediation_plan.md)
  and [`price_refresh_scale_plan.md`](price_refresh_scale_plan.md) distinguish
  landed simulator work from live-provider/Instruments measurements. Do not
  promote a “needs measurement” line to “done” because the simulator suite is
  green.
- [`shared_pricing_cache_plan.md`](shared_pricing_cache_plan.md) is a future
  backend project. Paid JustTCG licensing/key ownership (Gate A), the
  irreversible Firestore region choice (Gate B), and privacy/App Store review
  (Gate C) are all open before implementation should begin.
- Real-device scanner work remains open: camera pixel format versus OCR and
  thermal behavior, tab-bar flicker, camera restart latency, physical slab
  calibration, and the one physical Browse timing failure recorded by the
  performance plan.

## Documentation hygiene decisions

- `progress.md` remains a chronological engineering log. Old “pending” lines
  are preserved as history, but its current checkpoint now points here and to
  the live-gate documents. New status should be appended, not inferred from an
  old line.
- The portfolio history checklist was brought in line with the shipped
  additive market-movement design. It no longer asks for the removed
  Performance/Collection Value picker.
- The Price Check checklist now describes choice-time explanation and
  accessibility announcement rather than requiring stale persistent camera
  text.
- Deterministic route checklists now separate what the simulator proves from
  what requires a real camera, provider, or accessibility-size pass. Remaining
  unchecked boxes are therefore intentional.
- `artifacts/` is ignored local evidence. Root plans and this audit are the
  durable status record; captures are supporting proof and may need to be
  regenerated on another machine.

## October review reconciliation — 2026-10-02

The [October review ledger](../audits/october-review-remediation.md) owns the
new boundary-failure implementation and test evidence. The scanner recognition
plan's previous newest-50 backlog claim is superseded by unrestricted durable
retention. Interrupted collection recognition and pending duplicate prompts
are recovery work; explicit dismissals and Price Check still cancel.
[RF-13](release_followups.md#rf-13--october-review-performance-measurements)
keeps physical-device performance acceptance open. No executor hypothesis is
promoted to a measured defect or a release-readiness claim.

## Re-run rule

Review-fix reconciliation (2026-10-05; uncommitted changes on `6b64abe`): the
[One Piece handoff](../audits/one-piece-integration-review-handoff.md) now
distinguishes the committed integration from subsequent fixes and historical
transfer evidence. Its old eight-label audit count describes the former regex;
the expanded boundary gate reports 37 existing game branches across Browse and
collection normalization. The broader detection does not complete the deferred
legacy extraction. Review-fix test evidence is recorded in
[the progress log](../../progress.md); production rollout, trust anchors,
mixed-client collection-write policy, and device/release acceptance remain open.

When a slice changes, update the smallest relevant checklist and add one line
to `progress.md`. When evidence is hardware- or provider-dependent, update
[`release_followups.md`](release_followups.md) instead of weakening a checklist
claim. A green simulator suite closes regressions; it does not close a physical
camera or live-network gate.
