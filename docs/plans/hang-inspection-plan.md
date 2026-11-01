# Repeatable app hang inspection

**Status:** inspection protocol prepared, 2026-10-29. No new app capture or
performance fix performed by this planning change.
**Reviewed baseline:** `main` at `fe7ac88`, clean before this documentation patch.

**2026-11-01 local checkpoint:** the
[bounded image/bulk-observation review](../../review/catalog-image-bulk-polish-2026-11-01.md)
records completed-artwork reappearance and settled bulk-generation fixes at
`3ca908d`, with 19 focused passes after test-only review follow-up `8d01aab` and
349 aggregate passes (one existing opt-in skip). This is deterministic
lifecycle/scheduling evidence; new hang traces,
physical-device performance and action-to-visible-result measurements remain
open under this protocol.

This document owns the inspection workflow. The
[production refinement review](../audits/production-refinement-master-review-2026-10-26.md)
owns its M/P findings, the [Browse report](../audits/browse-performance-repair-2026-10-28.md)
owns its captures, and [release follow-ups](release_followups.md) retains device
and release acceptance. Link findings here rather than opening competing lists.

## What we are measuring

A hang is a period when the main run loop cannot respond. A slow catalog request
with working scrolling and cancellation is a loading delay; a dropped animation
frame is a hitch. Record these separately, because each needs different evidence.
An `async` function or `Task` does not by itself move synchronous work off the
main actor. Conversely, a long background operation is not itself a UI hang.

Use **250 ms** as the standard Hangs reporting threshold, matching Apple's
common tooling default. Inspect **100–249 ms** episodes in a separate sensitive
pass when a short interaction feels delayed. These are inspection thresholds,
not a claim that all work under 250 ms is acceptable or that every slow response
will be flagged. Also record action-to-visible-result latency: actor queues,
provider waits and publication delays can feel stuck while the run loop is free.

The target is no detected foreground hangs in the exercised interactions,
plus useful feedback and working cancellation during longer work. A clean
capture means only that the recorded scenario was clean under those conditions.

## What already exists

| Existing support | How to use it |
| --- | --- |
| `TradingCardScanner-ProfileLocal` scheme | Run/Profile use optimized `ReleaseLocal`; its Test action uses `DebugRemoteLocal`. Do not mistake ordinary tests for optimized timing evidence. |
| ReleaseLocal compiler settings | `-O` and dSYM generation already exist. This build includes local signing/Collector Tools differences; record those and later check the intended distribution configuration. |
| `PerformanceSignpost` in [PriceStore.swift](../../TradingCardScanner/Services/PriceStore.swift) | Subsystem `TradingCardScanner`, category `Performance`; available outside DEBUG. Existing string metadata is public, so add only safe counts, phases and opaque operation IDs. |
| Browse entry/search markers | `Browse.firstUsable`, `Browse.typing`, `Browse.prepare`, `Browse.project`, publication, directory and focus markers correlate work to routes. Publication is not proof a frame reached the display. |
| Collection/portfolio/store markers | `CollectionView.body`, `makeCachedProjection`, `coverageIndex`, `PortfolioComputationActor.compute`, `startRecompute`, `makeStoreRevisionFingerprint`, and `StoreRevisionMonitor.body`. Body events are not frame counters. |
| Scanner/persistence markers and metrics | `firstPlausibleReading`, `tracking`, `scannerPersistence` and [ScanSessionMetricsLog.swift](../../TradingCardScanner/Services/ScanSessionMetricsLog.swift). Preserve recognition and physical-encounter correctness while diagnosing latency. |
| Existing synthetic performance routes/tests | Reuse isolated fixtures for controlled comparisons. The finish harness is compile gated; it is not a normal production store or a general hang detector. |

The installed Instruments CLI lists Time Profiler, SwiftUI, Swift Concurrency,
App Launch, System Trace and Animation Hitches templates. Hangs is an instrument
to verify/add inside a recording template, not a separately listed template here.
No MetricKit subscriber was found in the reviewed app source. There is no need
to introduce a third-party SDK or an app-side watchdog to start this inspection.

## First inspection order

These are workload candidates, not newly confirmed source defects. Complete one
focused baseline and investigation at a time; fix a confirmed high-impact hang
before expanding the sweep. Do not change several suspected causes at once.

| ID / order | Reproduction and endpoint | First source boundary / evidence |
| --- | --- | --- |
| H01 — launch / initial Collection | Launch the installed app with an existing store; wait for the first usable grid, scroll, then stop. Separate process launch from warm foreground return. | [App entry](../../TradingCardScanner/App/TradingCardScannerApp.swift), [opening](../../TradingCardScanner/Views/AppOpeningView.swift), [bootstrap](../../TradingCardScanner/Services/CollectionStorageBootstrap.swift), [projection](../../TradingCardScanner/Services/CollectionProjectionActor.swift), [CollectionView](../../TradingCardScanner/Views/CollectionView.swift). Earlier device evidence includes a 478.61 ms initial-layout stall. Capture the `Launch.*` signposts (`catalogPrepare` per game, `storageStart`, `bind`, `scannerModel`, `backfill`, `magicLocal`, `contentMounted`, `handoff`), `portfolio.recompute`, `Catalog.priceAuthorityInstall` and `YuGiOh.catalogLoad`; a `YuGiOh.catalogLoad` with `main=1`, or one before `Launch.handoff` on a repeat launch of the same build, is a regression. |
| H02 — focused search → background → return | Open a set, focus search, type `cynthia`, clear/retype; background with focus active, return and check retained query and keyboard behavior. Record foreground and snapshot phases separately. | [BrowseView](../../TradingCardScanner/Views/BrowseView.swift), native field focus, UIKit snapshot/layout stacks. Earlier snapshot stall: 451.16 ms. Focus cleanup is installed according to the Browse report, but the final unmirrored comparison is pending. |
| H03 — Browse entry and rapid edits | Collection → Browse → Pokémon → Destined Rivals; empty query, incremental `c` → `cynthia`, clear, price sort, Back/reopen. Repeat on another available game; isolate delayed-provider conditions. | [CatalogSetPresentation](../../TradingCardScanner/Services/CatalogSetPresentation.swift), [completion](../../TradingCardScanner/Services/CatalogSetCompletion.swift), existing Browse markers and tests. Recheck responsiveness, stale-result rejection and exact progress together. |
| H04 — Collection search / scroll / refresh | Fixed collection: scroll, search/clear, sort/filter, open/back. Separately repeat during explicit price refresh. | CollectionView, [revision monitor](../../TradingCardScanner/Services/StoreRevisionMonitor.swift), PriceStore, [finish effects](../../TradingCardScanner/Views/CardFinishOverlay.swift). Use existing live/static/nonfoil controls only if traces implicate effects (P02). |
| H05 — Activity / portfolio / card chart | Open Activity with a fixed aged event history; separately open portfolio and one card chart, switch range, dismiss/reopen. | [CollectionActivityLogView](../../TradingCardScanner/Views/CollectionActivityLogView.swift), [PortfolioHistoryView](../../TradingCardScanner/Views/PortfolioHistoryView.swift), [card detail](../../TradingCardScanner/Views/CollectionCardDetailView.swift), [replay snapshot](../../TradingCardScanner/Services/PortfolioReplaySnapshot.swift). Measure P06 Activity projection and P04 chart work; do not assume both share a cause. |
| H06 — scan and persist while UI stays live | Physical device: raw, slab and difficult-recognition passes; a 30-card stack including removal and two identical copies separated by removal. Check receipt, finish choice, quantity and Undo. | [CardScanner](../../TradingCardScanner/Services/CardScanner.swift), [ScannerViewModel](../../TradingCardScanner/Views/ScannerViewModel.swift), [CollectionStore](../../TradingCardScanner/Services/CollectionStore.swift). Correlate OCR/tracking and persistence (P03 / RF-2); simulator input cannot certify camera performance. |
| H07 — bulk import / ownership updates | Disposable synthetic store: import fixed 1,000 then 5,000 rows; scroll while running, cancel/resume and verify totals. | [CollectionCSV](../../TradingCardScanner/Services/CollectionCSV.swift), CollectionStore and revision monitor. Separate copying/index cost (P05), writes, and publication. Never import into the owner's collection for a benchmark. |
| H08 — photo / centering tools | Fixed image and pixel dimensions: open analyzer, adjust, export; separately run batch photos and cancel. | [CardCenteringAnalyzer](../../TradingCardScanner/Services/CardCenteringAnalyzer.swift), tool views and image/export paths. Preserve existing centering accuracy gates; analysis duration and unresponsive UI are different measures. |

The table names source boundaries, not permanent line numbers. Before any fix, locate the
symbol in the exact captured revision rather than relying on old report lines.

## Capture protocol

1. **Identify the run.** Save date, SHA and working-tree diff/hash, scheme,
   configuration, executable UUID and matching dSYM UUID, Xcode version, OS,
   hardware, scenario ID and precise start/end actions. Record collection row
   and event counts without exporting contents, cache state, network condition,
   thermal state, power mode, accessibility settings and mirroring state.
2. **Choose the store.** Preserve the installed owner store and caches. Update
   in place only when a new instrumented build is needed. Use disposable,
   deterministic stores for size sweeps: empty, roughly 500 / 1,500 / 5,000
   rows, with fixed price/event/finish distributions. Label process-cold,
   first-route and warm-cache separately; never call relaunch “cold cache.”
3. **Build once for the comparison.** Use optimized code and keep its matching
   symbols. Prefer the mounted T7 for DerivedData, packages/compiler caches,
   results and raw traces under a unique `CodexBuild/HangInspection/<run>/`
   directory; use a temporary internal directory only if no external SSD is
   available. Record any diagnostic compile flags. A fixture build requiring
   DEBUG helpers must retain optimization and must be labeled as a fixture.
4. **Record one flow.** Product → Profile with the ProfileLocal scheme. Start
   with Time Profiler; verify a populated Hangs track and add Points of Interest
   / signposts filtered to the subsystem above. Save the configured template
   externally for repeat use. Use focused 20–60 second recordings where possible;
   extend only for a named long-running workflow. Keep LLDB detached for timing.
5. **Run an ordinary baseline first.** Use direct device touch, with mirroring
   off where possible. Repeat the same flow three times, keeping first-entry
   and warm results separate. Save individual durations and worst case; three
   runs do not establish a useful p95. Confirm required actions actually occurred
   using markers and observations; a capture without typing is not a typing pass.
6. **Add targeted diagnostics.** If main-thread CPU dominates, inspect sampled
   stacks within the Hangs interval. If blocked, add Thread State Trace or
   System Trace and follow the wait/owner chain. Use SwiftUI, Animation Hitches,
   Swift Concurrency, File Activity or Allocations only as the evidence warrants;
   separate heavier recordings so observer cost does not contaminate comparisons.
7. **Preserve immediately.** Save `.trace`, useful table exports, a source map
   and the run summary together. Keep raw traces/dSYMs/device metadata external
   and private. Commit only sanitized findings and relative source links.

The CLI can use a saved template after `xcrun xctrace list devices` and
`xcrun xctrace list templates` establish real targets. Do not hard-code a device
ID or assume a Time Profiler recording automatically includes signposts/Hangs.
If attaching fails, the prior device run succeeded by launching the installed
bundle from Instruments. Record the resulting startup work rather than treating
that run as an attach-only steady-state sample.

For a freeze that never recovers, save all-thread stacks with a debugger pause
and repeat samples if possible. Label this diagnostic capture; debugger stops
invalidate timing. A waiting run loop at idle is healthy, not evidence of a
deadlock. ETTrace is optional for a focused symbolicated simulator CPU question;
its flamegraph alone does not establish blocked-thread wall time or device hangs.

## Trace → source → smallest fix

Select the exact hang range first. Record wall duration and foreground state,
then distinguish busy main-thread work, a blocked thread, or a responsive UI
waiting for a result. Use both first-party and framework stacks: hiding system
libraries too early can conceal image decode, layout or persistence work invoked
by an app call. Inclusive stack sample counts overlap and are not additive.

Walk to the first responsible app call and record **file, symbol, captured SHA,
line and caller**. Swift optimization can inline frames; corroborate source
locations with matching symbols and the surrounding call path. For blocked work,
identify the waited-on thread/actor/resource. For asynchronous delay, correlate
request, queue wait, compute, publication and visible completion separately.
An overlapping signpost narrows the investigation; it does not prove causation.

If the boundary is unclear, add the smallest missing signpost using the existing
helper, with a unique operation ID for concurrent intervals and balanced endings
on success, error and cancellation. Candidate missing boundaries are bootstrap
phases, Activity read/project/publish, chart projection and import batches. Add
only after inspecting the trace; do not log every frame or move work solely to
make a timing marker shorter. Measure instrument overhead if it becomes material.

Open one evidence-backed finding, implement one focused change and verify the
same workload again. Preserve SwiftData actor isolation, cancellation and stale
publication guards, exact identity/finish/pricing, quantities, durable import
progress and Undo. Moving code to an actor does not justify passing live
SwiftData models across executors. Retest the behavior whose work was moved.

## Finding record and completion rule

Use the existing report for a known issue; for a new issue create a sanitized
entry under `docs/audits/` and link it here. Each entry needs:

```text
ID / status: suspected | reproduced | attributed | fixed-awaiting-retest | verified
Scenario, user impact, exact reproduction and completion event:
Baseline SHA/diff hash; build/configuration; device/OS; workload/cache/network:
Trace location (private external path), run number, interval start/end:
Hang count; each wall duration; action latency; foreground/background state:
Main thread busy/blocked or responsive wait; responsible stack/wait chain:
Source file + symbol + line + captured revision; symbol UUID check:
Hypothesis, missing evidence, and single proposed change:
After SHA/diff hash; identical run conditions and raw per-run results:
Correctness/build/test evidence; remaining limitations and next action:
```

Prioritize an indefinite freeze or blocked essential action first, then repeated
foreground hangs in core flows, then intermittent short stalls. Retain lifecycle
stalls for investigation even when they do not interrupt a visible touch; H02's
background phase must not be silently counted as a foreground typing failure.

A finding becomes **verified** only when the same trigger was exercised in at
least three comparable post-fix runs, the original hang no longer appears, no
new hang is introduced in that flow, action latency is not merely displaced,
and relevant correctness checks pass. If the original was rare, match or exceed
its baseline exposure and retain uncertainty; three clean runs alone cannot
prove it gone. Record all failed/interrupted captures rather than averaging them
away. No universal percentage improvement or full-app hang-free claim follows.

For a code fix, run the narrowest relevant native build/tests, then expand only
for affected shared boundaries. Recheck on a physical device for device findings.
Optimized deterministic fixture measurements can catch regressions, but timing
assertions on a shared simulator should remain diagnostic until variance and a
repeatable baseline justify a budget. Preserve existing functional tests.

## Ongoing cadence and later field evidence

After each confirmed fix, rerun that scenario and one adjacent core interaction.
After shared storage, projection, navigation, image or actor-boundary changes,
repeat the affected rows in the matrix. Before a release candidate, sweep all
applicable rows on the representative phone and the slowest supported available
hardware; record unavailable hardware explicitly. This is a development protocol,
not a scheduled automation or a claim of release certification.

Once local inspection is useful, consider Xcode Organizer hang reports for
distributed builds and a small MetricKit subscriber if field evidence is needed.
Keep exact build symbols and define private retention before persisting reports.
Field diagnostics depend on platform collection/delivery and are not a live
detector. Defer this integration until there is a concrete distribution need.

## 2026-10-31 review measurement batch

**Status:** instrumentation added on `refinement/production-review-2026-10-31`;
no device run yet. Findings R1–R10 and the implemented slices are recorded in the
[production refinement review](../audits/production-refinement-master-review-2026-10-26.md#2026-10-31-production-review-second-pass).
This section owns the owner's device run and the decision rules that follow it.

New intervals use the existing `PerformanceSignpost` helper (subsystem
`TradingCardScanner`, category `Performance`). Their metadata carries only
counts and outcomes:

| Signpost | Boundary | Metadata |
| --- | --- | --- |
| `CardShare.render` | One price-check or collection share bitmap | view type |
| `CardDetail.chartModel` | One card-detail chart model build | `points=`, `samples=` |
| `CardDetail.quantityWrite` | Quantity tap to updated value | `from=`, `to=`; outcome `saved`, `stale`, `error`, `cancelled`, `unavailable` or `superseded` |
| `PriceCheck.quoteSave` | One Price Check quote-cache save | `ok` or `rollback` |

Use the capture protocol above with two optimized builds: **A** = `b592c91`
(before the slices) and **B** = the branch tip. Record three runs per scenario,
per-run values, the worst case, device and OS. Build A has no new signposts, so
A/B comparisons use the SwiftUI instrument or visible behavior.

| # | Scenario | Builds | Record |
| --- | --- | --- | --- |
| M1 | H01 launch to first `priceRefresh.run` on the mature collection | B | `Launch.storageStart` → `priceRefresh.run` (last lower bound 6.9 s, before S6 landed); main-thread lock waits in `PortfolioEngine` and `MagicTreatmentMigration` |
| M2 | H06 10-card scan session | A, B | `ScannerChrome` / `ScannerView` body counts per card; hangs |
| M3 | H06 30-card stack as described above | B | Hangs; `scannerPersistence` timing |
| M4 | H05 card-detail chart drag on 1Y and All, oldest available device | B | Hangs; `CardDetail.chartModel` count and maximum duration during the drag |
| M5 | H05 Portfolio chart drag | B | Hangs during the drag |
| M6 | H04 500-card grid: scroll down, then back up | A, B | Visible placeholders on return; decode count |
| M7 | Price-check share: type `125.50` in the asking price | B | `CardShare.render` count and duration (expected: one render after typing pauses) |
| M8 | Quantity +/−: three quick taps | B | `CardDetail.quantityWrite` durations |
| M9 | Price Check during an explicit price refresh | B | `PriceCheck.quoteSave` durations overlapping `priceRefresh.run`; hangs |

Decision rules. Implement only the rows that trigger, one slice at a time:

| Measurement | Trigger | Action |
| --- | --- | --- |
| M4 | Any hang ≥ 100 ms during the drag, or `CardDetail.chartModel` maximum > 8 ms | S8: compute the chart model once per data or range change |
| M8 | Median `CardDetail.quantityWrite` > 150 ms | S9: coalesce rapid quantity taps into one follow-up write |
| M9 | Any `PriceCheck.quoteSave` > 100 ms, or a hang overlapping one | S10: stop; write a design note for the owner (persistence boundary) |
| M5 | Any hang ≥ 100 ms | Record a new finding; no fix in this batch |
| M1 | More than 1 s to refresh entry | Record under H01; no fix in this batch |
| M2, M3, M6, M7 | Informational | Record A/B results; they confirm or refute S2, S3 and S4 |

## Work queue

- [x] Review source, existing evidence, optimization/symbol settings and local templates.
- [x] Define repeatable capture, attribution, finding and verification protocol.
- [ ] Capture current H01 and H02 baselines with direct touch and matching symbols.
- [ ] Attribute the highest-impact reproduced interval; add a marker only if needed.
- [ ] Apply one measured fix and complete its before/after and correctness checks.
- [ ] Sweep H03–H08 in order, reusing linked authorities and recording coverage gaps.
- [ ] Run the [2026-10-31 review measurement batch](#2026-10-31-review-measurement-batch) (M1–M9) and apply its decision rules.

## Apple references

- [Understanding hangs in your app](https://developer.apple.com/documentation/xcode/understanding-hangs-in-your-app)
- [Analyze hangs with Instruments](https://developer.apple.com/videos/play/wwdc2023/10248/)
- [Getting started with hang analysis](https://developer.apple.com/tutorials/instruments/getting-started-with-hang-analysis)
- [Diagnosing performance issues early](https://developer.apple.com/documentation/xcode/diagnosing-performance-issues-early)
- [Analyzing responsiveness issues in your shipping app](https://developer.apple.com/documentation/xcode/analyzing-responsiveness-issues-in-your-shipping-app)
