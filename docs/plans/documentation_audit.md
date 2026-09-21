# Documentation and artifact audit

**Audit date:** 2026-09-20
**Purpose:** reconcile the chronological progress log, implementation plans,
QA checklists, and simulator evidence so that an old “pending” note is not
mistaken for a current defect—and a real validation gap is not lost in the
history.

## Current authority boundary — 2026-09-20

This is the repository-wide documentation index and reconciliation record.
Source code, tests, build settings, and evidence recorded against the current
checkout outrank dated plans. A document is current only when it is listed
below or linked from the current [documentation map](../README.md). Everything
under `docs/legacy/` or `review/legacy/` is retained for provenance and is not
release evidence.

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

| Area | Current authority | Code/evidence boundary |
| --- | --- | --- |
| Product scope and roadmap | [`README.md`](../../README.md), [`CardScanner Collection Integrity Strategy`](../vision/CardScanner%20Collection%20Integrity%20Strategy%20%E2%80%94%20Start-to-Finish%20Implementation%20Plan.md), and the [active launch plan](../superpowers/plans/2026-09-13-phase-0-phase-1-app-store-launch.md) | The current Swift target and tests decide what is implemented; roadmap prose does not add product behavior. The launch plan's §0.1.1 binds open pass-2 findings to the tasks they block, and §0.1.2 lists current plans outside launch scope; both are required reading before a task is started. |
| Browse/Catalog | [`browse_screen_spec.md`](browse_screen_spec.md), [`browse_success_checklist.md`](../../references/browse_success_checklist.md), `TradingCardScanner/Views/BrowseView.swift`, and `TradingCardScannerTests/BrowseFeatureTests.swift` | Browse is a Collection push destination. The focused set-directory hardening selectors pass 133/133 with 0 failures, including invalid/valid cache bodies and symbol-prefix recovery. A8/B6 remain closed by the settled light/dark rerun2 evidence in [`pokemon_browse_checklist.md`](../../artifacts/pokemon_browse_checklist.md); provider/device checks remain open. |
| Automatic Pokémon set updates | [`automatic_pokemon_catalog_updates_plan.md`](automatic_pokemon_catalog_updates_plan.md) | Slices A–E are implemented. Slice F's production-host revision-1 rehearsal and same-revision relaunch handling are complete as of 2026-09-19. The committed production app configuration is `remote-authority`; schema-1 additive fingerprinting, canonical publisher/device parity, fail-closed classification, durable targeted reconciliation, parent-artwork metadata, and set-specific Browse updates are implemented and the latest focused verification is Core 38/38 plus app 37/37. Protected baseline publication, auto-environment setup, four-hour scheduling, physical-device/offline evidence, the first real catalog update, and release gates remain open. |
| Magic catalog signing and publication | [`magic_catalog_key_handling_runbook.md`](magic_catalog_key_handling_runbook.md) | Current authority for Magic-specific key custody, signed catalog releases, protected/automatic publication routing, Scryfall boundaries, and rollout safeguards. The Magic-specific key pin remains owner input; rollout remains `legacy-live`. |
| Artwork fallbacks | [`artwork-fallback-plan.md`](artwork-fallback-plan.md), `TradingCardScanner/Services/ArtworkFallbacks.swift`, and Browse tests | P0–P3 are implemented in the current tree; TCGdex-only stem/WebP candidates, symbol sibling-prefix recovery, decode-before-persist, legacy-cache eviction, and coalesced requests pass in the 133/133 focused run. Broader provider behavior and licensing are still operational gates. |
| Scanner workflow | `TradingCardScanner/Views/ScannerViewModel.swift`, the current [scanner module review](../audits/scanner_module_review.md), [release follow-ups](release_followups.md), [`scan_cancellation_success_checklist.md`](../../references/scan_cancellation_success_checklist.md), and `progress.md` | The reviewed cancellation/task-lifecycle fixes are landed and focused-verified. The scanner module review is the current authority for the five confirmed module findings and three measurement concerns; camera, thermal, provider, and physical-device evidence remains open. |
| Pricing and portfolio performance | [`price_refresh_scale_plan.md`](price_refresh_scale_plan.md), [`release_followups.md`](release_followups.md), and the current services/tests | Actor-owned refresh persistence is landed; large-store measurement, Magic batching, resumable sweeps, and physical-provider profiling remain open. |
| App Review and release | [`app_review_fix_plan.md`](../../app_review_fix_plan.md), [`app_review_preflight.md`](../../app_review_preflight.md), [`card-scanner-1.0-go-no-go-framework.md`](../release/card-scanner-1.0-go-no-go-framework.md), and the [current evidence ledger](../release/phase-1-integrity-evidence.md) | The exact checkout is not certified: CloudKit/ownership, clean full-suite, physical-device, archive/TestFlight, centering, and App Store gates remain open. |
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

## Re-run rule

When a slice changes, update the smallest relevant checklist and add one line
to `progress.md`. When evidence is hardware- or provider-dependent, update
[`release_followups.md`](release_followups.md) instead of weakening a checklist
claim. A green simulator suite closes regressions; it does not close a physical
camera or live-network gate.
