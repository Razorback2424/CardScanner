# Documentation and artifact audit

**Audit date:** 2026-09-09
**Purpose:** reconcile the chronological progress log, implementation plans,
QA checklists, and simulator evidence so that an old “pending” note is not
mistaken for a current defect—and a real validation gap is not lost in the
history.

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
- [`app_review_fix_plan.md`](app_review_fix_plan.md) still has evidence or
  product-owner gates for stale vendor-variant invalidation, migration
  serialization, store/account epoch scope, fan-out and large-session
  measurement, ProductIdentity misses, and the production bundle ID and
  entitlements. Its unchecked items are deliberate review gates, not forgotten
  implementation tasks.
- [`performance_review_remediation_plan.md`](performance_review_remediation_plan.md)
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
