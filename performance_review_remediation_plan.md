# Performance Review — Remediation Plan (revised)

Status: **implementation complete for the current iOS 17 target; runtime gates
remain explicit.** Slices 1–8 and 11 are implemented on the working branch,
R5 is closed by the deployment-target decision recorded below, and the
remaining P1/U2/U3 items are deliberately hardware-validation gates rather
than unmeasured code changes. Every claim below was re-read against the source
after a second-pass audit of the first review; the audit's corrections are
recorded in §1 with a verdict each. A third pass then checked the second pass's
own new claims — three needed correcting, and those corrections are applied in
the findings below and recorded in §1.4. Line numbers drift; follow symbol
names.

## 0. Progress

| Slice | State | Evidence |
|---|---|---|
| 1 — Measure | **done (simulator); device pass still worthwhile** | `OSSignposter` intervals at `PriceRefreshDataIndex.init`, `ProductIdentityIndex.init`, `coverageIndex`, `PortfolioComputationActor.compute` and `CollectionStore.add`, plus counted events at `makeCachedProjection` and `startRecompute`. `testAgedStoreBaseline` seeds an aged store and reports the two whole-table reads; opt-in via `PERF_BASELINE`, skipped in the default run. Numbers in §3.1. They un-gate slices 4 and 8. |
| 2 — R2 holding-detail projection | **done** | `PortfolioOwnedCardDestination` uses the closure overload; `testHoldingDetailResolvesTheSameInstrumentAsTheGrid` pins the C2 convergence on the one input where the two rules disagree. |
| 3 — R9 dead code | **done** | `LedgerIntegrityLog` and its three writes deleted; three test lines removed per T3; `startedAt(context:)` parameter dropped with all four call sites updated. `cancelRecompute` kept, as recommended. |
| 4 — R1 retention | **done; correction fixed 2026-09-05** | 400-day window, `.all` kept (decision taken 2026-09-05). `coverageIndexThrowing` clamps to the window and reports it; `PriceObservationLog.pruneCheckDays` discards rows behind it from the computation actor; `PortfolioEngine.publish` carries both stored coverage counts and `carriedForwardValue` from the close it already wrote. The non-zero retention fixture now proves a pruned day is not revised for lost evidence. Measured flat past the window — see §3.4. |
| 5 — R3 field trimming | **done (simulator; live count profile still recommended)** | The portfolio observer no longer hashes local fetch/check timestamps; the collection token keeps presence bits and only uses exact `fetchedAt` for unstamped providers. The focused stamped/unstamped test and full simulator suite pass. A live-provider signpost count was not available in this pass, so the magnitude claim remains intentionally unquantified — see §3.6. |
| 6 — R6 + R7 | **done, P4 deliberately not done** | `PortfolioView` and `CollectionView` no longer observe the refresh controller as whole screens: `PortfolioRefreshButton`, `PortfolioAttentionBadge` and a shared `PriceRefreshActivityRow` observe it instead, and `needsPortfolioAttention` is split so the parent keeps only the half that reads the portfolio. The fourth-pass root-observation correction also changed `ContentView` from an `@StateObject` observer to a plain app-scoped reference, so 250 ms progress publications no longer invalidate the whole tab tree. Collection's pull-to-refresh returns after 500 ms and reports the pass in its summary through the same row, so both screens describe one pass identically. P4 rejected — see below. |
| 7 — de-isolate write path | **done** | `ProductIdentityStore`, `ProductIdentityIndex`, `applyVendorBatchHit` (all three overloads) and `recordSealedArtwork*` are context-owned rather than `@MainActor`. The compiler then named three dependencies neither plan predicted — `materializedRows`, `rows(for:in:)` and two `CollectionCatalogNormalizer` statics — which is precisely the audit this slice exists to perform. The latest full simulator suite is 857 tests, 1 skipped, 0 failures. Slice 8's boundary is now what the scale plan wrongly assumed it already was. |
| 8 — R4 ModelActor | **done (simulator; runtime signpost capture still recommended)** | Refresh target construction, `PriceRefreshDataIndex`, `PriceStore`, identity indexes, writes and saves now run in `PriceRefreshModelActor`; the main actor retains queue/status/progress/budget UI. The latest full simulator suite is 857 tests, 1 skipped, 0 failures. No live-provider Instruments capture was taken in this pass, so the off-main signpost check remains an explicit runtime verification item. |
| 9 — device pass | **partly done; P1/U2/U3 remain hardware gates** | P3 and U4 are landed. The app-only iPhone build and signed test bundle build both succeed; the physical run executed 851 tests with 1 skip but exposed one device-only timing/fixture failure in `BrowseFeatureTests.testBrowseSearchDebouncesBeforeStartingBothSearchLanes` (a focused retry reproduced it). P1 (pixel format), U2 (tab bar) and U3 (camera restart) remain unmodified and unverified because no OCR/thermal or manual UI lifecycle measurement was taken. |
| 10 — R5 `#Index` | **closed by deployment decision (2026-09-05)** | The project remains iOS 17.0. `#Index` requires iOS 18, so no index or CloudKit schema migration is introduced under the current target. This follows the existing deployment guidance to keep the lower target and branch newer APIs when needed; revisit only as an explicit iOS 18 migration decision. |
| 11 — R10 checklist | **done** | BG task identifiers derive from `Bundle.main.bundleIdentifier`, and `Info.plist` from `$(PRODUCT_BUNDLE_IDENTIFIER)`; verified in the built plist. `progress.md:31` corrected. `price_refresh_scale_plan.md:316-318` corrected in place with a dated note. |

**P4 (artwork override fetch in `body`) was investigated and rejected, not deferred.** R7 was its main justification: the fetch cost 5 unindexed lookups per Portfolio render, and the render rate during a refresh was 4 Hz. With R7 landed, Portfolio re-renders only on genuine portfolio changes, so the cost is now negligible. Removing it entirely means resolving the override into `holdingSnapshots` on the computation actor — but `PortfolioInputObserver` does not query `LocalArtworkOverride`, so a snapshot-carried filename would not update until the next recompute, and setting a custom artwork would silently fail to appear in Portfolio. Fixing *that* means adding a fifth whole-table query to the observer R3 exists to slim down. The remedy costs more than the problem; the fetch stays.

Suite after slices 1, 2, 3, 4, 6, 7, 11, P3/U4 and R3: **851 tests, 1 skipped, 0 failures** (846 before: the C2 convergence test, the two R1 retention tests, the opt-in aged-store baseline that skips unless `PERF_BASELINE` is set, and the R3 freshness-token test).

The completed full simulator suite after the graded-lookup fixes and the two
source-only corrections recorded in §1.5 is **857 tests, 1 skipped, 0
failures** in 24.814 seconds. The focused post-correction run separately
covered 62 tests with 0 failures.

---

Guiding constraints (unchanged): smallest change that fixes a demonstrated
problem, no speculative abstractions, measure before restructuring, additional
code is a cost.

---

## 1. Audit of the first review — what was validated

### 1.1 Corrections to the first review

| # | Audit claim | Verdict | Evidence |
|---|---|---|---|
| C1 | "Slice A is not an hour with tests passing" — the three deletions are referenced by tests and by production callers. | **Confirmed.** | `LedgerIntegrityLog`: `PortfolioReconciliationTests.swift:211, 1688, 2413`. `cancelRecompute`: `:739`. `startedAt(context:)`: `:1086, 1412` plus production callers `ScannerSettingsView.swift:263` and `PortfolioHistoryEngine.swift:310`. Dead-code removal edits tests and two call sites. |
| C2 | F1's remedy is a behaviour change, not a pure optimisation. | **Confirmed, and one nuance added.** | `InventoryLedger.priceStorageKey(for:)` selects a key when the record is invalidated **or** the newest observation is an `explicitInvalidation` **or** either source yields a usable USD value. `PriceStore.priceStorageKey(for:in:)` reads records only. They diverge when (a) an invalidation exists only as an observation, or (b) an observation carries a usable value while the record is nil/non-USD. Nuance: the portfolio actor uses a third rule, `InstrumentValuationIndex.priceStorageKey`, which sees observations *and* records. Converging detail on the record-only rule makes detail agree with the grid, not necessarily with the portfolio. That is acceptable (it is what the grid already does) but must be stated in a test. |
| C3 | F3's grid-token trim needs a `sourceUpdatedAt`-conditional. | **Confirmed.** | `PriceRecord.effectiveAsOf = sourceUpdatedAt ?? fetchedAt`; `state()` returns `.unknown` when both `lastCheckedAt` and `fetchedAt` are nil and `.stale`/`.current` from `effectiveAsOf` against a 24 h threshold. Compact tiles render current vs stale as primary vs secondary. Dropping `fetchedAt` outright can freeze a tile as stale for unstamped providers. |
| C4 | F2 understated (index build runs concurrently with the 2.5 s recompute) and overstated (check-day fetch is day-bounded; "moderate risk" is light). | **Confirmed on all three points.** | `PortfolioInputObserver`'s task calls `portfolio.recompute` (returns immediately) then `refreshStalePricesIfNeeded`, so `PriceRefreshDataIndex.init` runs on main while the actor replays. `PriceRefreshDataIndex.init` predicate on `PriceCheckDay` is `portfolioDay == indexedDay`. `PortfolioReplaySnapshot.swift` records "replay is roughly 0.3s of a 2.5s recomputation". `performRefresh` is ~300 lines of main-actor local state; the move is a day's work, and `price_refresh_scale_plan.md` §3 Slice 6 already lists its hazards (model objects crossing actors, no merge policy, cross-store non-atomic saves). |
| C5 | P2 needs more than one child view. | **Confirmed.** | `refresh` is read in `isRefreshing` (drives `.disabled` on the Refresh button), `portfolioRefreshActivity`, `needsPortfolioAttention`, the `.finished` case in the hero, and is passed to `PortfolioDetailsView`. Isolation means one child owning button + activity row and one for the attention badge. |
| C6 | P1 should set an explicit native format rather than delete the assignment. | **Accepted.** | No consumer touches `CVPixelBufferGetBaseAddress`/`Lock`; every buffer goes through `VNImageRequestHandler` or `VNSequenceRequestHandler`. Setting `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` keeps the frame path deterministic across devices. |
| C7 | Two citation errors (U4 counterexample at `ScannerViewModel.swift:703/2115`; several line numbers drifted). | **Confirmed.** | `fallbackQuoteTasks` declared `:703`, keyed dedupe `:2115`. `PortfolioInputObserver` is at `ContentView.swift:342`, `refreshStalePricesIfNeeded` at `:489`, `isThumbZoneContested` at `ScannerView.swift:90/96`. This document references symbols, not lines, wherever it can. |
| C8 | `progress.md:31` ("nothing calls recordInvalidation today") is stale. | **Confirmed.** | `CollectionCatalogNormalizer.swift:147` calls `priceLog.recordInvalidation` on a marketplace-variant change. Update `progress.md`. |

### 1.2 Items the first review missed

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| M1 | Unbounded device-local history with no retention policy; root cause under F2 and the coverage cost. | **Confirmed, and promoted to the top finding.** | No `context.delete` of `PriceObservation` or `PriceCheckDay` anywhere in `Services/`; the only deletes are duplicate `PriceRecord` repair and a failed close rollback. `recordSuccessfulCheck` upserts one `PriceCheckDay` per instrument per day. Observations grow more slowly (`PriceObservationRules.decide` returns `.unchanged` for a same-value re-check, so the log grows only on value changes), but check days grow strictly with instruments × checked days. `coverageIndexThrowing` fetches `epoch → today`, so it widens monotonically. `PriceRefreshDataIndex.init` fetches all observations. |
| M2 | Bundle id is still `com.example.TradingCardScanner`; BG task identifiers are hardcoded in `BackgroundPriceRefresh.swift:45-46` and duplicated in `Info.plist:27-28`. | **Confirmed.** | No defect today (they agree). A rename before shipping must change all four together or `BGTaskScheduler.register` fails silently and background refresh dies. |
| M3 | Overlap with `price_refresh_scale_plan.md` (refresh ownership) and `design_slices_plan.md` (bundle id / deployment target). | **Confirmed.** | The scale plan's §2.1 makes a point this document adopts: moving refresh work to a `@ModelActor` does **not** stop `@Query` republish amplification, because a background context's save still propagates to the main context. Its Slice 6 is the same move as F2 and carries the hazard list. **That hazard list is incomplete and one of its claims is wrong — see T1; correcting `price_refresh_scale_plan.md:316-318` is part of R10.** `design_slices_plan.md` notes the bundle id when weighing an iOS 26 target. |

### 1.3 First-review findings that stand unchanged

F1, F2 (with C4's magnitude corrections), F3 (with C3's refinement), F4, P1 (with C6), P2 (with C5), P3, P4, U1–U4, the four dead-code items (with C1's cost), and the §5 joined-refresh silent drop (`PriceRefreshController.refresh` returns `Void`; `ContentView.refreshAllPrices` sets `didRefresh = true` unconditionally after awaiting it).

### 1.4 Third-pass corrections (applied to the findings below)

| # | Problem found in this document | Correction |
|---|---|---|
| T1 | R4 claimed the actor move needs no test changes because the tests touch only `nonisolated static` helpers. **Wrong, and inherited from `price_refresh_scale_plan.md:316-318`, which makes the same claim.** | `applyVendorBatchHit` (`PriceRefreshController.swift:1450`) is `static func` **without** `nonisolated` on a `@MainActor final class`, so it is main-actor isolated. It is the per-result write path — exactly what the move relocates — and it is called from `CollectionItemKindTests.swift:352, 392, 427`, which compile only because that class is `@MainActor` (`:7`). Nor can it simply be marked `nonisolated`: it takes a `ProductIdentityStore`, and both that type (`ProductIdentityStore.swift:44`) and `ProductIdentityIndex` (`:11`) are themselves `@MainActor`. R4 gains a prerequisite slice (slice 7) and an honest test-risk line. `JustTCGContractTests` was also named in that line and contains zero references to the controller. |
| T2 | R1's remedy (a) proposed reading pruned days' coverage back from `PortfolioDailyClose` without saying what that costs. | It makes pruned days immutable for coverage: `PortfolioEngine.matches` would compare recomputed coverage against the row it was derived from, so it always matches. That is fine for closed history, but a late CloudKit inventory event legitimately revises an old day (`revisionReason: .recomputed` exists for that case), and such a day's coverage would then be carried from a close computed against different holdings. Stated in R1, and the pruned-fixture assertion sharpened accordingly. |
| T3 | R9's action for `PortfolioReconciliationTests.swift:2413` was to rewrite the assertion. | Redundant: `:2412` already asserts `engine.integrityDefects == summary.defects`. Delete `:2413` outright. Separately, `:1688` asserts the log does *not* contain a defect in a test that never triggers a recompute — and the only three writers are `replaceAll` calls in `PortfolioEngine` — so it is near-vacuous today. Neither assertion carries coverage worth preserving. |

### 1.5 Fourth-pass correction (2026-09-05)

| # | Problem found | Correction |
|---|---|---|
| T4 | Slice 6 removed refresh observation from the two large screens but left `ContentView` as an `@StateObject` observer. Its 250 ms status publications still invalidated the `TabView`, causing `CollectionView.body` and its projection-token walk to rerun at refresh cadence. | `ContentView` now keeps `PriceRefreshController.shared` as a plain stored reference. Only the small refresh controls, attention badge and activity row observe progress. Commit `43c6dc6`. The focused post-correction simulator run passed 62 tests, the generic test build succeeded, and the full suite passed 857 tests with 1 skipped and 0 failures; a SwiftUI/Instruments body-count delta remains unmeasured because no live refresh profile was captured. |

---

## 2. Findings, re-prioritised

Ordering is by real-world value with M1 first because its cost grows with time even when the collection does not.

### R1 — Unbounded local history (M1)
**Where:** `PriceObservationLog.recordSuccessfulCheck`, `PortfolioReplaySnapshotBuilder.coverageIndexThrowing`, `PriceRefreshDataIndex.init`.
**What:** one `PriceCheckDay` per instrument per checked day, never pruned; every recompute reads all of them since epoch; every refresh reads every observation on main.
**Why it matters:** 1,500 instruments × 365 days ≈ 550k check-day rows in year one. Recompute and refresh both slow down with calendar time.
**Confidence:** high on growth; magnitude needs a seeded 12-month store.
**Remedy (smallest):** two parts. (a) Keep `PortfolioHistoryRange.all` as the user-facing history choice, but retain raw `PriceCheckDay` evidence for a 400-day recomputation window; coverage for older days is carried from the already-published `PortfolioDailyClose` rows, which store `refreshedInstrumentCount`/`carriedForwardInstrumentCount` per day. (b) Bound `coverageIndexThrowing` to the same window; closes before it are already published and `PortfolioEngine.publish` only revises days whose derived payload changed. Observations should **not** be pruned: they are the valuation history and grow only on value change.
**Consequence to accept explicitly (T2):** reading pruned days' coverage back from `PortfolioDailyClose` makes those days immutable for coverage — `PortfolioEngine.matches` would compare recomputed coverage against the row it derived it from, so it always matches. Closed history is meant to be immutable, so that is mostly the point. But a late-arriving CloudKit inventory event legitimately revises an old day (the publisher carries `revisionReason: .recomputed` for exactly that), and after pruning, that revised day's coverage counts are carried from a close computed against *different* holdings. Coverage on revised historical days therefore becomes approximate. Value, market and flow are unaffected — they replay from events and observations, neither of which is pruned.
**Benefit:** recompute and refresh costs stop growing with age. **Risk:** moderate; touches replay inputs. **Complexity:** increases slightly (one retention pass, one window constant).
**Verify:** row counts before/after a simulated year; `coverageIndexThrowing` and `PriceRefreshDataIndex.init` signpost durations. Extend `PortfolioReplayEngineTests` with a pruned fixture asserting the specific contract, not "same closes": **value, market, flow, added, removed and corrections reproduce identically; coverage counts on pruned days are carried from the stored close rather than recomputed** — including on a day revised by a late event, which is the case that would otherwise fail silently.

### R2 — Portfolio → holding detail runs thousands of fetches per render (F1)
**Where:** `PortfolioOwnedCardDestination` in `PortfolioView.swift`.
**What:** uses `LogicalCollection.project(cards:, ledger:)`, which resolves each position through `InventoryLedger.priceStorageKey(for:)` (2–4 unindexed fetches per candidate key per position), plus three whole-table `@Query`s so it re-renders on every save. `CollectionView`'s comment above `makeCachedProjection` documents removing exactly this.
**Confidence:** high.
**Remedy:** the closure overload with `PriceStore.priceStorageKey(for:in:)` and the records dictionary the view already builds. **This changes the `instrumentKey` handed to `CollectionCardDetailView` for cards whose invalidation exists only as an observation (C2).** Ship with a test asserting detail and grid choose the same instrument for that case.
**Benefit:** removes a main-thread stall on a primary navigation. **Risk:** low; grid already uses the rule. **Complexity:** reduces.
**Verify:** Instruments fetch count on holding push with a seeded large store.

### R3 — Save fan-out: whole-table `@Query` re-reads and O(N) hashes on main (F3)
**Where:** `PortfolioInputObserver.portfolioInputTaskID` (`ContentView.swift`), `CollectionProjectionToken.make` (`CollectionView.swift`).
**What:** every save re-fetches every observed `@Query`; the observer then hashes every field of four tables; the grid token hashes ~24 fields per card and ~13 per record. Checkpoint saves every 10 printings during refresh make this recur every few seconds; the observer's hash includes `record.fetchedAt` and `record.lastSuccessfulCheckAt`, so an unchanged price still triggers a full portfolio replay.
**Confidence:** high on mechanism; magnitude to measure.
**Remedy (refined per C3):**
- Observer: drop `lastSuccessfulCheckAt` (clean). Drop `fetchedAt` on the argument that the explicit `portfolio.recompute` after every refresh path is the trigger for coverage, not the observer. Note the observer does not query `PriceObservation`; `fetchedAt` was the only field firing when a refresh touched prices without changing a value. Live "x of y checked today" stops ticking mid-refresh and updates when the pass ends.
- Grid token: replace `fetchedAt`/`lastCheckedAt` with `lastCheckedAt != nil`, `fetchedAt != nil`, and `fetchedAt` itself **only when `sourceUpdatedAt == nil`**, so `state()`'s stale/current answer cannot go stale in the cache.
**Benefit:** fewer replays and grid rebuilds during refresh. **Risk:** low with the conditional; a tile rendering wrong staleness is the failure to test. **Complexity:** roughly neutral (fewer fields, one condition).
**Verify:** count `PortfolioEngine.startRecompute` and `makeCachedProjection` calls during a 200-card refresh before/after; a unit test on `CollectionProjectionToken` that an unstamped record's `fetchedAt` change alters the token and a stamped one's does not.

### R4 — Refresh index materialises the observation log on the main actor (F2)
**Where:** `PriceRefreshDataIndex.init` created in `PriceRefreshController.runRefreshQueue` (controller is `@MainActor`).
**What:** fetches all `PriceRecord` and all `PriceObservation` on main at the start of each refresh; the automatic stale check starts ~300 ms after portfolio start, so this runs concurrently with the first recompute. Check days are already day-bounded in this index. A **third** whole-table index is built on the same path and is named in neither plan: `ProductIdentityIndex.init` fetches every `ProductIdentity` (`ProductIdentityStore.swift:15`).
**Confidence:** high on mechanism, medium on magnitude; R1 changes the magnitude.
**Prerequisite (slice 7, from T1):** the isolation boundary is not where either plan assumed. `PriceStore` and `PriceRefreshDataIndex` are already context-owned rather than `@MainActor`, and say so in their doc comments. But `ProductIdentityStore` (`:44`), `ProductIdentityIndex` (`:11`), `recordSealedArtwork*` and `applyVendorBatchHit` (`PriceRefreshController.swift:1450`) are all main-actor isolated, and `applyVendorBatchHit` is the per-result write path this slice relocates. De-isolate them first, following the pattern `PriceStore` already establishes — context-owned, used on the executor owning its context. That is a separable commit provable by compilation alone, and it converts R4's largest unknown (which write helpers are actually main-bound) into a checked fact before the move begins. If any of them will not de-isolate, that failure *is* the audit R4 needs.
**Remedy:** measure after R1. If still >100 ms, do slice 7, then execute `price_refresh_scale_plan.md` Slice 6 (move context, `PriceStore`, both indexes, target construction and saves into a `@ModelActor`; main keeps status/budget UI), honouring its hazard list: no model objects across actors, decide a merge policy, do not widen the cross-store save window. Per that plan's §2.1, this fixes the main-thread fetch stall only; it does not reduce `@Query` republish (R3 does).
**Cost:** a day, not an afternoon, plus slice 7. **Complexity:** increases.
**Verify:** no `PriceObservation` or `ProductIdentity` fetch on main in Instruments during refresh. **Test risk, corrected (T1):** `ProductFallbackTests` (18 references) and `PricingTests` touch only `nonisolated static` helpers and are safe; `JustTCGContractTests` references the controller not at all. The file actually at risk is `CollectionItemKindTests.swift:352, 392, 427`, which calls `applyVendorBatchHit` and compiles today only because the class is `@MainActor`. Slice 7 is what keeps those three call sites compiling.

### R5 — No indexes on keyed lookups (F4)
**Where:** all `@Model` types; deployment target 17.0, `#Index` needs iOS 18.
**What:** every `collectionKey`, `key`, `instrumentKey`, `idempotencyKey`, `(instrumentKey, portfolioDay)` predicate is a table scan; a scan commit performs roughly 8–12 on main.
**Remedy:** if the target moves to 18, add `#Index` to those seven fields. Separate decision: it forces a schema migration on a CloudKit-mirrored store and intersects with `design_slices_plan.md`'s target discussion. R1 reduces the largest table this would index.
**Verify:** signposts around `CollectionStore.add` and `PriceStore.store` on a seeded store; migration on a copy of a real store.

### R6 — Pull-to-refresh holds the spinner for the whole pass (U1)
**Where:** `CollectionView.content` `.refreshable { await onRefresh() }`.
**Remedy:** start the refresh as an unstructured task and return after a short delay; surface `refresh.status` in the Collection summary so entry point and progress live together (Portfolio already does this via `portfolioRefreshActivity`). **Complexity:** preserves.

### R7 — Portfolio tree re-renders at 4 Hz during refresh (P2)
**Where:** before the fourth-pass correction, `ContentView` also observed `refresh` as a `@StateObject`. Its body did not read a published field, but each progress write still invalidated the root `TabView`, which passed non-`Equatable` closures and an existential catalog into `CollectionView`; `CollectionView.body` then reran its O(N) projection-token walk. `PortfolioView` had the same broad observation for `isRefreshing`, `portfolioRefreshActivity`, `needsPortfolioAttention`, the `.finished` hero case, and `PortfolioDetailsView`.
**Remedy (per C5, completed):** `ContentView` now holds `PriceRefreshController.shared` as a plain stored reference. Child view A owns the Refresh button and activity row (needs `isRefreshing` and `status`); child view B owns the attention badge (needs `fallbackStatus`). `PortfolioView` and `CollectionView` no longer observe `refresh` as whole screens, while `PortfolioDetailsView` keeps its own `@ObservedObject`. P4 remains deliberately rejected; see §0.
**Complexity:** preserves.

### R8 — Device items
- **P3 (done):** `ScannerViewModel.installMagicDefinitions` compares the
  directory before handing it to `useMagicDefinitions`, which compiled the
  vocabulary regex on the caller's thread before the vision queue got to make
  the same comparison. `start` runs on every Scan-tab appearance.
- **U4 (done):** `CatalogCardDetailView` dedupes fallback quotes by instrument
  key instead of cancelling the previous card's in-flight request, adopting the
  rule `ScannerViewModel.fallbackQuoteTasks` already used.
- **P1 pixel format:** set `videoOutput.videoSettings` to `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` explicitly (C6). Verify OCR hit rate and thermal state over a 10-minute session.
- **P3:** `useMagicDefinitions` compiles `MagicScanProfile` before the vision-queue equality guard, on every Scan-tab appearance. Compare definitions first.
- **U2:** tab bar hides per receipt (every scan, 5 s). Evaluate on device; if it reads as flicker, hide while `recent` is non-empty instead.
- **U3:** measure `startRunning` latency on tab return before deciding anything.
- **U4:** `CatalogCardDetailView.queueFallbackPrice` cancels the previous card's task; adopt `ScannerViewModel`'s keyed `fallbackQuoteTasks` dedupe.

### R9 — Dead code (cost corrected per C1)
- `LedgerIntegrityLog` (written 3× in `PortfolioEngine`, read only by tests): delete the type, the three `replaceAll` writes, and the test lines at `PortfolioReconciliationTests.swift:211, 1688, 2413`. Per T3, both assertions are safe to delete outright rather than re-expressed: `:2412` already asserts `engine.integrityDefects == summary.defects`, so rewriting `:2413` would only duplicate it; and `:1688` asserts the log does *not* contain a `conflictingPayloadForIdempotencyKey` defect in a test that never triggers a recompute, so with only three `PortfolioEngine.replaceAll` writers nothing writes the log on that path. Neither line covers behaviour that survives the type.
- `PortfolioEngine.cancelRecompute`: production-unused; test `:739` exercises the cancellation path — keep the test's intent by cancelling `computationTask` through a test-only seam, or accept keeping the method. Recommend keeping it; it is four lines and the test is valuable.
- `PortfolioEpoch.startedAt(context:)` unused parameter: remove and update `ScannerSettingsView.swift:263`, `PortfolioHistoryEngine.swift:310`, tests `:1086, 1412`.
- `PortfolioHistoryMode`: single value, optional cleanup, lowest priority.

### R10 — Release checklist items (M2, C8)
- Bundle id rename must update `PRODUCT_BUNDLE_IDENTIFIER`, both constants in `BackgroundPriceRefresh.swift`, and both `Info.plist` entries together. Derive the two identifiers from `Bundle.main.bundleIdentifier` so there is one source.
- Update `progress.md:31`: `recordInvalidation` **is** called, from `CollectionCatalogNormalizer` on a marketplace-variant change.
- Before slice 8, `PriceRefreshController.refresh` returned `Void`; a joined caller whose pending batch was cleared by `cancelRefresh` returned as if it ran. Slice 8 now returns `PriceRefreshResult.didRun` and surfaces target-build failure to the automatic stale-check caller.
- Correct `price_refresh_scale_plan.md:316-318` (T1): `applyVendorBatchHit` is **not** `nonisolated static`, so "all 34 test files touch only those, so this slice should not require test changes" is wrong. Its hazard list should also gain the `ProductIdentityStore` / `ProductIdentityIndex` isolation prerequisite. Two planning documents currently disagree with the source in the same place; fix it there as well as here.

---

## 3.1 Slice 1 results

Simulator (iPhone 17 Pro, in-memory store), from `testAgedStoreBaseline`.
Device numbers will differ; the *shape* is what these establish.

| instruments × days | `PriceCheckDay` rows | `coverageIndex` | `PriceRefreshDataIndex.init` |
|---|---|---|---|
| 300 × 90 | 27,000 | 0.37 s | 0.05 s |
| 300 × 365 | 109,500 | 1.47 s | 0.15 s |
| 900 × 365 | 328,500 | 4.55 s | 0.44 s |

Linear in rows, ~13.8 µs per check-day row. Extrapolating the plan's own
reference collection — 1,500 instruments, one year, 547,500 rows — puts
`coverageIndex` near **7 s inside every recompute**, against a documented whole
recomputation of 2.5 s today. That is R1, measured rather than inferred, and it
is why R1 sits above everything else: nothing else on this list has a cost that
grows when the user does nothing at all.

`PriceRefreshDataIndex.init` crosses the 100 ms threshold R4's remedy names at
300 instruments after one year, and reaches 0.44 s at 900. Note the index build
is driven by records and observations, not check days: observations were seeded
on 5 % of days, matching `PriceObservationRules.decide`.

## 3.2 Two corrections these numbers force

**R4 is not gated on R1.** R4's remedy said "measure after R1", on the
assumption that retention would shrink the index build. It cannot:
`PriceRefreshDataIndex.init`'s check-day fetch is *already* day-bounded to
today, and R1 explicitly does not prune observations. The two findings are
independent, and slice 8 can proceed on its own numbers as soon as someone
wants it. The dependency note in §4 is corrected accordingly.

**R1's product decision was made 2026-09-05.** Keep `.all` as the history
choice, use a 400-day raw coverage window, and carry older coverage from the
`PortfolioDailyClose` rows, which already store `refreshedInstrumentCount` and
`carriedForwardInstrumentCount` and are not pruned. This changes what a revised
historical day reports (T2), and that consequence is accepted and covered by
the non-zero retention fixture in §3.4. Slice 4 is therefore implemented; the
remaining question is whether a future product decision wants a narrower window
or resumable replay.

### Slice 8 boundary reconciliation (2026-09-05)

The refresh ownership boundary now agrees with `price_refresh_scale_plan.md`
Slice 6. `PriceRefreshController` remains the `@MainActor`
`ObservableObject` facade: it owns the migration gate, request queue,
cancellation, status/progress publication and fallback-budget UI. It passes a
small `Sendable` request (fallback preference, imported-row policy, retry mode,
and any background limit/order) to a `@ModelActor`; target arrays are not built
on main and are not passed across the boundary.

The model actor owns its `ModelContext`, builds `PriceRefreshDataIndex`,
`PriceStore` and the fallback `ProductIdentityIndex`/`ProductIdentityStore`
there, constructs `PriceTarget` values from the live context after the
migration gate is held, performs catalog/fallback/graded writes and checkpoint
saves, and returns value results/progress events. `PriceRefreshTargets` and
`JustTCGRefreshCoordinator` therefore have to be context-owned on this path.
No SwiftData model object crosses the actor boundary or a network suspension:
imported-card and artwork/identity row references remain
`PersistentIdentifier`s and are re-materialised in the actor's context.

The concurrent-writer decision is fail-closed: keep the dedicated refresh
context, never merge or retry stale in-memory `CollectedCard` objects, and use
the existing save/rollback behavior to report `persistenceFailed` when a
checkpoint cannot be saved. A successful save retains SwiftData/CloudKit's
existing conflict behavior; this slice does not introduce an application merge
policy. The actor keeps the current shared-context checkpoint ordering, so the
synced `PriceRecord`/`CollectedCard`/`ProductIdentity` writes and local-only
`PriceObservation` writes remain under the existing `PriceStore.save()` window;
the cross-store non-atomic window is not widened. As §2.1 records, this move
does not fix R3's `@Query` republish amplification.

## 3.4 Slice 4 result

Decision: keep `PortfolioHistoryRange.all` and retain raw check-day evidence for
400 days. Older coverage is carried from published closes.

Same fixture, after the window:

| instruments × days | `PriceCheckDay` rows | `coverageIndex` |
|---|---|---|
| 300 × 500 | 150,000 | 1.64 s |
| 300 × 800 | 240,000 | 1.66 s |

Flat. At the pre-R1 rate of 13.8 µs/row the 800-day store would have cost
~3.3 s, and would have kept climbing; the read is now bounded by the window
rather than by the store's age, and `pruneCheckDays` keeps the rows off disk as
well as out of the read. What remains inside the window is genuine work: ~1.6 s
for 300 instruments is still the largest single cost in a recompute, and
shrinking it further means a narrower window or a resumable replay, both of
which are product decisions rather than optimisations.

`testPrunedDaysKeepPublishedCoverage` pins the trade the window makes: a pruned
day is not revised merely because its evidence is gone, and a pruned day that a
late event genuinely does revise keeps its original coverage counts while its
value changes. The fixture uses a published `carriedForwardValue` of `$2` and
a pruned replay value of `$9`, so the value carry is tested rather than
accidentally equal on both sides.

## 3.3 Measurement plan and remaining runtime evidence

Seed a store representing 12 months of use for ~1,500 instruments (check days daily, observations on ~5% of checks). Add `os_signpost` intervals, no behaviour change:

| Signpost | Decides |
|---|---|
| `PriceRefreshDataIndex.init` and `ProductIdentityIndex.init` | R4 (both are whole-table builds on the same main-actor path) |
| `coverageIndexThrowing` and total `PortfolioComputationActor.compute` | R1 window size |
| `CollectionStore.add` + `PriceStore.store` + `commit` per scan | R5 priority; whether the choice-bar hitch is real |
| `makeCachedProjection` and `startRecompute` counts during a 200-card refresh | R3 |
| Row counts: `PriceObservation`, `PriceCheckDay` | R1 |
| `session.startRunning` latency | U3 |
| Thermal state, BGRA vs 420f, 10 min | P1 |

Without this, every magnitude in this document is inference.

## 3.5 Slice 8 result

The actor migration was compiled with the existing project and test target:

| Check | Result |
|---|---|
| `xcodebuild build-for-testing` | succeeded |
| Full simulator `xcodebuild test` | 850 tests, 1 skipped, 0 failures |
| Test-suite duration | 24.561 s |
| Main-actor model crossing audit | no model objects cross the request/progress/result boundary; persistent identifiers are re-materialised in the actor context |
| Runtime Instruments refresh capture | not taken in this pass; live-provider signpost verification remains recommended |

The controller now passes value-only `PriceRefreshRequest` values. Background
refresh also passes a request instead of building targets from
`container.mainContext`. A target-build failure is surfaced so the automatic
stale check can retry, and queued target limits merge with `nil` as unlimited
and otherwise by `max`, preserving foreground work when it joins a bounded
background request. The old main-actor catalog/fallback/graded implementation
and its provider properties were removed rather than retained as a second
refresh path.

## 3.6 Slice 5 result — R3 field trimming

The two refresh-sensitive invalidation fingerprints now retain only fields that
can change the value or freshness answer they drive:

- `PortfolioInputObserver.portfolioInputTaskID` still hashes the record key,
  effective price, currency, source, provider `sourceUpdatedAt`, and
  invalidation state, but not local `fetchedAt` or `lastSuccessfulCheckAt`.
  The explicit refresh completion recompute remains the coverage trigger.
- `CollectionProjectionToken.make` hashes the presence of `fetchedAt` and
  `lastCheckedAt`, and includes exact `fetchedAt` only when the provider has no
  `sourceUpdatedAt`. This preserves unknown/not-checked transitions and the
  unstamped-provider fallback without replaying a stamped tile for local clock
  churn.

Measured verification:

| Check | Result |
|---|---|
| Focused `CollectionProjectionTokenTests` | 2 tests, 0 failures |
| Full simulator `xcodebuild test` | 851 tests, 1 skipped, 0 failures |
| `git diff --check` | clean |
| Live-provider `makeCachedProjection` / `startRecompute` event count | not captured; no live refresh profile was available in this pass |

The code and regression coverage are landed. The last row is deliberately not
filled with a seeded-store number: the plan's question is refresh fan-out, and
only a live-provider pass can measure that event count honestly.

## 3.7 Slice 10 result — R5 deployment-target decision

The app and test targets remain `IPHONEOS_DEPLOYMENT_TARGET = 17.0`.
`#Index` is an iOS 18 API, so adding it would require a deliberate target
raise plus a CloudKit schema migration review. The existing deployment guidance
recommends keeping the lower target and branching newer APIs when practical.
Following that decision, R5 is closed for this target with no speculative
indexes or migration. If the product later raises the minimum to iOS 18, the
seven keyed fields listed in R5 can be re-evaluated as a separate migration
slice.

## 3.8 Device-pass result

The physical iPhone target is reachable and signs with the local development
team:

| Check | Result |
|---|---|
| App-only iPhone build | succeeded |
| Signed physical `build-for-testing` | succeeded with the local development team override |
| Full physical test run | 851 tests, 1 skipped, 1 failure |
| Failing physical test | `BrowseFeatureTests.testBrowseSearchDebouncesBeforeStartingBothSearchLanes`; a focused retry reproduced the provider-start count mismatch (`0` vs `2`) |
| P1/U2/U3 runtime validation | not performed; capture format, tab-bar behavior and camera restart code remain unchanged |

The physical result is not used to claim a remediation regression: the
simulator suite remains 851/1/0, and the failing test is a provider/timing
fixture path rather than a slice-5/8 assertion. It is recorded as a device
follow-up because it prevents calling the physical suite green. No OCR hit-rate,
thermal, tab-bar interaction or camera restart measurement was taken.

## 3.9 Slice 6 root-observation correction

The fourth-pass audit found that the original R7 split stopped `PortfolioView`
and `CollectionView` from observing refresh progress but left their owner,
`ContentView`, as an `@StateObject` observer. The source-only correction in
commit `43c6dc6` makes the root reference plain while leaving observation in
the small views that render refresh state.

| Check | Result |
|---|---|
| `ContentView` refresh ownership | plain stored reference to `PriceRefreshController.shared`; it does not observe progress publications |
| Focused post-correction simulator tests | 62 tests, 0 failures (`JustTCGContractTests` and `ViewConstructionSmokeTests`) |
| Generic simulator `build-for-testing` | succeeded |
| Full simulator suite after the correction | 857 tests, 1 skipped, 0 failures in 24.814 s |
| SwiftUI/Instruments body-count delta | not captured; no live refresh profile was run |
| `makeCachedProjection` / `startRecompute` event-count delta | not captured; the remaining measurement requires a live refresh profile |

This correction removes the root invalidation source identified in the scale
plan. It does not claim that checkpoint saves stop `@Query` republishing; that
residual is the separate R3 amplifier and remains a runtime measurement item.

---

## 4. Slices, in dependency order

1. **Measure** (§3). Signposts and a seeding fixture only.
2. **R2 alone**, with the C2 convergence test. Not bundled with deletions.
3. **R9 dead code**, tests and the two production call sites in the same diff.
4. **R1 retention + bounded coverage window**, after the measured slice 1 numbers and the `.all` decision recorded in §3.2. Extend `PortfolioReplayEngineTests` with a pruned fixture that reproduces the same closes. **Implemented.**
5. **R3 field trimming**, with the `sourceUpdatedAt` conditional and the token unit test; implemented and simulator-verified in §3.6. A live event-count profile remains recommended evidence.
6. **R6 + R7** (R7 as two child views; the root-observation correction is recorded in §1.5). **Implemented; P4 deliberately rejected.**
7. **De-isolate the refresh write path** (from T1): make `ProductIdentityStore`, `ProductIdentityIndex`, `recordSealedArtwork*` and `applyVendorBatchHit` context-owned rather than `@MainActor`, following `PriceStore`'s existing pattern. No behaviour change; proved by compiling, with `CollectionItemKindTests` still green. Do this whether or not slice 8 proceeds — it is cheap, independently valuable, and it is what tells you what slice 8 actually costs.
8. **R4 ModelActor**, after slice 7 and the ownership reconciliation in §3.2; implemented and simulator-verified in this working branch. Runtime Instruments confirmation remains recommended.
9. **Device pass**: P3/U4 are landed; P1 explicit format, U2 tab bar and U3 camera restart remain hardware validation gates.
10. **R5 `#Index`**: closed for the current iOS 17 target by the decision in §3.7; no index/migration code is added.
11. **R10 release checklist** at any point before the bundle id changes.

Dependencies (corrected by §3.2): slice 8 depends on slice 7 (done) and **not** on slice 4 — retention cannot shrink the index build. Slice 4's `.all` decision is recorded and implemented; no additional product decision blocks the current remediation. Slice 5's implementation is now landed; a profiled live refresh remains recommended if the magnitude of the fan-out reduction needs a runtime number.

---

## 5. Investigated and specifically not changing

- The 300 ms debounce and hash-driven `task(id:)` triggers (only the hashed fields change).
- `PortfolioComputationActor` and fetch-once-in-bulk replay.
- `CollectionStoreSession` LRU.
- The scanner acceptance pipeline (latch, confirmation window, spatial tracker, held-repeat authorization).
- Stopping the camera when the Scan tab is not visible, unless U3 measures badly.
- Device-local schema for observations and closes.
- `URLSession.shared` for TCGdex/Scryfall.
- Swift 5 language mode; no strict-concurrency migration for this release.
- Pruning `PriceObservation` rows: they are valuation history and grow only on change.

---

## 6. Coverage statement

Every production file in `App/`, `Services/`, `Models/`, `Views/` was read at outline level; these paths were traced end to end: launch and portfolio start, frame → latch → identification → commit → save, price refresh (catalog, fallback, graded, checkpoints), recompute and close publishing, Collection projection, Browse loading and image caching, CSV import, background refresh, both camera lifecycles. Read at outline only, judged low-risk because pure and densely tested (846 test functions): `ScanParser`, `CardLatch`, `MagicTreatmentMigration` planning internals, `CollectionCSV` row parsing, `PortfolioReplay` engine internals, `CardCenteringAnalyzer`.
