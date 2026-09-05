# Performance Review — Remediation Plan (revised)

Status: **planning only.** No code changed. Every claim below was re-read
against the source after a second-pass audit of the first review; the audit's
corrections are recorded in §1 with a verdict each. A third pass then checked
the second pass's own new claims — three needed correcting, and those
corrections are applied in the findings below and recorded in §1.4. Line
numbers drift; follow symbol names.

## 0. Progress

| Slice | State | Evidence |
|---|---|---|
| 1 — Measure | **blocked (device)** | Signposts are code; the profiles they exist to capture need Instruments on a device with a seeded 12-month store. Not attempted in a headless session — an unmeasured signpost is not slice 1. Slices 4, 5 and 8 stay gated behind it. |
| 2 — R2 holding-detail projection | **done** | `PortfolioOwnedCardDestination` uses the closure overload; `testHoldingDetailResolvesTheSameInstrumentAsTheGrid` pins the C2 convergence on the one input where the two rules disagree. |
| 3 — R9 dead code | **done** | `LedgerIntegrityLog` and its three writes deleted; three test lines removed per T3; `startedAt(context:)` parameter dropped with all four call sites updated. `cancelRecompute` kept, as recommended. |
| 4 — R1 retention | gated on 1 | |
| 5 — R3 field trimming | gated on 1 | |
| 6 — R6 + R7 | **done, P4 deliberately not done** | `PortfolioView` no longer observes the refresh controller: `PortfolioRefreshButton`, `PortfolioAttentionBadge` and a shared `PriceRefreshActivityRow` observe it instead, and `needsPortfolioAttention` is split so the parent keeps only the half that reads the portfolio. Collection's pull-to-refresh returns after 500 ms and reports the pass in its summary through the same row, so both screens describe one pass identically. P4 rejected — see below. |
| 7 — de-isolate write path | **done** | `ProductIdentityStore`, `ProductIdentityIndex`, `applyVendorBatchHit` (all three overloads) and `recordSealedArtwork*` are context-owned rather than `@MainActor`. The compiler then named three dependencies neither plan predicted — `materializedRows`, `rows(for:in:)` and two `CollectionCatalogNormalizer` statics — which is precisely the audit this slice exists to perform. Build clean, 847 tests green. Slice 8's boundary is now what the scale plan wrongly assumed it already was. |
| 8 — R4 ModelActor | gated on 1 and 7 | |
| 9 — device pass | blocked (device) | |
| 10 — R5 `#Index` | not started | deployment-target decision |
| 11 — R10 checklist | **done** | BG task identifiers derive from `Bundle.main.bundleIdentifier`, and `Info.plist` from `$(PRODUCT_BUNDLE_IDENTIFIER)`; verified in the built plist. `progress.md:31` corrected. `price_refresh_scale_plan.md:316-318` corrected in place with a dated note. |

**P4 (artwork override fetch in `body`) was investigated and rejected, not deferred.** R7 was its main justification: the fetch cost 5 unindexed lookups per Portfolio render, and the render rate during a refresh was 4 Hz. With R7 landed, Portfolio re-renders only on genuine portfolio changes, so the cost is now negligible. Removing it entirely means resolving the override into `holdingSnapshots` on the computation actor — but `PortfolioInputObserver` does not query `LocalArtworkOverride`, so a snapshot-carried filename would not update until the next recompute, and setting a custom artwork would silently fail to appear in Portfolio. Fixing *that* means adding a fifth whole-table query to the observer R3 exists to slim down. The remedy costs more than the problem; the fetch stays.

Suite after slices 2, 3, 6, 7 and 11: **847 tests, 0 failures** (846 before; the new one is the C2 convergence test). Nothing below slice 1's gate has been touched.

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

---

## 2. Findings, re-prioritised

Ordering is by real-world value with M1 first because its cost grows with time even when the collection does not.

### R1 — Unbounded local history (M1)
**Where:** `PriceObservationLog.recordSuccessfulCheck`, `PortfolioReplaySnapshotBuilder.coverageIndexThrowing`, `PriceRefreshDataIndex.init`.
**What:** one `PriceCheckDay` per instrument per checked day, never pruned; every recompute reads all of them since epoch; every refresh reads every observation on main.
**Why it matters:** 1,500 instruments × 365 days ≈ 550k check-day rows in year one. Recompute and refresh both slow down with calendar time.
**Confidence:** high on growth; magnitude needs a seeded 12-month store.
**Remedy (smallest):** two parts. (a) A retention window for `PriceCheckDay` older than the longest history range the UI can show (the `PortfolioHistoryRange.all` case needs a decision; if "all" is kept, coverage for days beyond the window can be summarised into the already-published `PortfolioDailyClose` rows, which store `refreshedInstrumentCount`/`carriedForwardInstrumentCount` per day). (b) Bound `coverageIndexThrowing` to the same window; closes before it are already published and `PortfolioEngine.publish` only revises days whose derived payload changed. Observations should **not** be pruned: they are the valuation history and grow only on value change.
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
**Where:** `PortfolioView` observes `refresh` for `isRefreshing`, `portfolioRefreshActivity`, `needsPortfolioAttention`, the `.finished` hero case, and passes it to `PortfolioDetailsView`.
**Remedy (per C5):** child view A owns the Refresh button and activity row (needs `isRefreshing` and `status`); child view B owns the attention badge (needs `fallbackStatus`). Parent stops observing `refresh`; `PortfolioDetailsView` keeps its own `@ObservedObject`. Fold P4 (`PortfolioArtwork` override fetch in `body`) in here by resolving the override filename once in `holdingSnapshots`.
**Complexity:** preserves.

### R8 — Device-only items
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
- `PriceRefreshController.refresh` returns `Void`; a joined caller whose pending batch is cleared by `cancelRefresh` returns as if it ran. Return a `didRun: Bool` if this path is ever touched; not a release blocker.
- Correct `price_refresh_scale_plan.md:316-318` (T1): `applyVendorBatchHit` is **not** `nonisolated static`, so "all 34 test files touch only those, so this slice should not require test changes" is wrong. Its hazard list should also gain the `ProductIdentityStore` / `ProductIdentityIndex` isolation prerequisite. Two planning documents currently disagree with the source in the same place; fix it there as well as here.

---

## 3. Measurement plan (Slice 1 — gates everything below)

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

---

## 4. Slices, in dependency order

1. **Measure** (§3). Signposts and a seeding fixture only.
2. **R2 alone**, with the C2 convergence test. Not bundled with deletions.
3. **R9 dead code**, tests and the two production call sites in the same diff.
4. **R1 retention + bounded coverage window**, gated on slice 1 numbers and the `PortfolioHistoryRange.all` decision. Extend `PortfolioReplayEngineTests` with a pruned fixture that reproduces the same closes.
5. **R3 field trimming**, with the `sourceUpdatedAt` conditional and the token unit test.
6. **R6 + R7** (R7 as two child views; P4 folded in).
7. **De-isolate the refresh write path** (from T1): make `ProductIdentityStore`, `ProductIdentityIndex`, `recordSealedArtwork*` and `applyVendorBatchHit` context-owned rather than `@MainActor`, following `PriceStore`'s existing pattern. No behaviour change; proved by compiling, with `CollectionItemKindTests` still green. Do this whether or not slice 8 proceeds — it is cheap, independently valuable, and it is what tells you what slice 8 actually costs.
8. **R4 ModelActor**, only if slice 1 (re-measured after slice 4) says the init is still expensive, only after slice 7, and only after reconciling with `price_refresh_scale_plan.md` Slice 6 so the two plans agree on refresh ownership.
9. **Device pass**: P1 explicit format, P3, U2, U3, U4.
10. **R5 `#Index`**: separate decision tied to the deployment-target choice in `design_slices_plan.md`.
11. **R10 release checklist** at any point before the bundle id changes.

Dependencies: slice 4 changes what slice 1 measured for R4, so re-run the R4 signpost after 4. Slice 8 depends on slice 7. Everything else is independent.

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
