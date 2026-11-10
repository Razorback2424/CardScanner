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

## Startup and unpriced export implementation — 2026-11-09

The owner authorized startup repairs and export timing after reporting two
launch hangs and further hangs during the Developer export in an Xcode build.
No incident call stacks were available. These changes address source-level
blocking work; they do not establish the cause of those individual incidents or
a clean physical-device capture. Baseline: `91f9491` plus the existing working
tree changes.

- Storage container opening and the legacy database probe now run off-main.
  Opens remain serialized, and superseded successes/failures cannot replace a
  newer ready session. Cloud readiness is still armed before opening a container.
- Magic migration keeps its public context access on the main actor and passes
  only the container into an explicitly concurrent phase. Fresh read/transaction
  contexts stay with their synchronous operation. The writer lock, cancellation
  and storage continuation remain in force; empty exact-ID work skips the lazy
  treatment catalog. The executor hop preserves the same task and its rewrite
  authorization.
- Portfolio epoch establishment and close persistence use the dedicated
  background model executor. Presentation waits for persistence; a live price
  delta arriving during that await keeps its newer headline and queues a replay.
  Epoch and close workers check storage currency before transactions and saves.

`CSVExport` console diagnostics use subsystem `TradingCardScanner`, category
`CSVExport`; Instruments intervals/events use the existing `Performance`
category. Each operation has an opaque `id`, its export kind, phase and
`main=true/false`. Completed intervals include `elapsed_ms`. Metadata contains
counts, byte sizes and fixed outcomes, without card identities, collection keys,
destination paths, credentials or error descriptions.

For an Xcode reproduction, filter the console for `CSVExport` and retain all
lines for one `id`. `tapToReady` covers the button-to-ready wait, including UI
resumption; `createWorker`, `workerRoundTrip`, `fetchCards`, `fetchPrices`,
`filterIndex`, `filterUnpriced`, `rowIndex`, `sort`, `formatRows` and
`assembleCSV` separate preparation costs. `encodeUTF8`, `fileWrapper` and
`serialized` cover document serialization. `presentationRequested` and
`presentationBinding` record the handoff request, **not proof of a displayed
frame**. `pickerLifecycle` ends at saved/failed/cancelled and **includes user
selection time**, so it must not be reported as a hang duration.
`releaseDocument` times the completion cleanup. A begin without its matching
end identifies the unfinished phase; correlate it with a Hangs/Time Profiler
capture to establish main-thread attribution.

Startup adds `Launch.containerOpen`, `Launch.magicPhase`,
`Launch.portfolioEpoch` and `Portfolio.persistCloses` alongside the existing
launch/ownership-lock markers. An off-main duration can include database or
network waiting; it is not itself evidence of an unresponsive UI. Simulator
correctness/executor tests do not replace the optimized device protocol below.

**Simulator verification:** the final DebugRemoteLocal selection on iPhone 17
Pro / iOS 27.0 executes 262 cases: **255 passed, 7 skipped, zero failed**.
It covers opening, bootstrap/policy/continuity/mode transitions, worker executor
and writer-contention checks, Magic migration, portfolio eligibility/replay,
revision monitoring and diagnostic CSV content. Superseded container successes
and failures retain the newer ready session. Export timing preserves the CSV
payload and carries one operation ID into the document. An initial expanded run
exposed an iteration-count wait in the queued-container lifetime test; its
completion helpers now use a bounded asynchronous deadline rather than counting
task yields. The complete selection then passes. Result:
`/Volumes/T7/CodexBuild/HangInspection/20261109-startup-fixes-final.xcresult`.
No full-target, physical-device, provider, CloudKit or release acceptance is
claimed.

**UI smoke-check limit:** the built simulator app reached the ordinary portfolio
and the isolated Lorcana synthetic review. Simulator remote automation initially
timed out and subsequently returned a stale hierarchy after actions, so the
native Files save/cancel workflow is not certified by this pass. Preparation
timing was observed in the test console with `main=false`; serialization and
picker markers are installed but still need an ordinary Xcode/device export
reproduction. No incident hang duration is inferred from these checks.

## On-device 804 ms startup follow-up — 2026-11-09

The owner reports a further **804 ms** startup hang from on-device hang
detection in **ProfileLocal**, with optional pricing fallback **enabled**. The
supplied console excerpt contains no stalled main-thread stack.
It records a roughly 20 ms persisted Pokémon catalog load and a later HTTP 404
from the catalog refresh. Those lines do not attribute the detected hang.

Source review at `df6d4c0` first identified eager Keychain preparation in the
entitled storage dependency factories. **ProfileLocal excludes that path via
`LOCAL_ONLY_SIGNING`**, so it cannot explain this incident; the exploratory
Keychain patch was removed.

A second Keychain path **is present in ProfileLocal**: `ContentView` calls
`PriceRefreshController.updateFallbackAvailability` shortly after portfolio
startup. With fallback pricing enabled and pending targets, the main actor read
`PriceVendorCredentials.hasKey`; its first uncached access synchronously called
`SecItemCopyMatching`. Apple's
[Keychain performance guidance](https://developer.apple.com/documentation/security/secitemcopymatching%28_%3A_%3A%29)
identifies this API as a possible UI blocker. That credential-presence read now
runs in a detached utility task, with a revision/cancellation/preference fence
before publishing either credentials or budget results. Starting a price-refresh
queue invalidates an earlier availability check. Disabled fallback and empty
queues still skip the read. Credential contents are neither changed nor logged.

Console-visible synchronous timing now uses subsystem `TradingCardScanner`,
category `Startup`, including optimized ProfileLocal builds. Filter for
`stage=Launch.`. Each stage has `phase=begin` and `phase=end`; completion includes
`elapsed_ms` and `main`. The stages cover initial catalog-task scheduling, storage
dependency creation, background-task registration and scheduling, capture-session
and video-output construction, Vision configuration, complete scanner-core and
scanner-view-model construction, `ContentView` initialization, and vendor
credential presence (`Launch.vendorCredentialPresence`, now off-main). These intervals
contain no asynchronous suspension. Nested intervals overlap and must not be
summed. `contentViewInit` measures construction, **not a rendered frame**, and
can appear again when its parent re-evaluates. The existing Performance signposts
remain available alongside these timings. Only fixed stage names, thread flags
and elapsed times are logged.

This removes a source-confirmed main-thread Keychain path, conditional on enabled
fallback and pending work; it does not attribute the reported 804 ms incident.
Repeat on-device hang detection with the rebuilt ProfileLocal app and retain the Startup lines. A long
`main=true` interval narrows attribution; a stalled main-thread stack or a
Hangs/Time Profiler trace is still the strongest evidence. If no timed stage
accounts for the stall, investigate first rendering, later publication and system
framework work in that trace. The catalog HTTP 404 remains a separate refresh
failure; this change does not alter its origin, signature checks, or persisted
catalog fallback.

**Focused simulator verification:** DebugRemoteLocal, arm64, iOS 27.0:
**37 passed, zero failed** (29 pricing lifecycle cases and eight launch worker
cases). Four new lifecycle cases cover a deliberately blocked credential read
leaving the main thread, a newer empty availability check, a refresh that completes
before the old read, cancellation, and disabled-fallback avoidance. These use an
injected presence check, not live Keychain or provider credentials. The logs
confirm `Launch.vendorCredentialPresence main=false`. Result:
`/Volumes/T7/CodexBuild/HangInspection/20261109-profile-startup-tests.xcresult`.
These are correctness/executor results, not device performance measurements.

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
