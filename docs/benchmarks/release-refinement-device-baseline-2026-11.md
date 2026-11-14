# ScanStash 1.0 — non-graded refinement performance baseline

**Status:** protocol only, not executed or accepted. **Baseline:** `main` at `4c4a2e6f3720` (2026-11-13).
**Scope:** ordinary raw-card scanning, collection/navigation, pricing snapshots, Browse, import/export, artwork, opening. This pass deliberately excludes graded/slab workflows.

This is a small, reproducible measurement slice using the app's existing `PerformanceSignpost` intervals. It does not create a new analytics framework and cannot certify device performance until the runs and evidence are attached.

## Conditions to record for every run

- Exact commit/build configuration; actual device model, OS, available storage, battery/thermal state, power mode, connectivity, and whether cached artwork/catalog data is warm or cold.
- Collection size, game distribution, quantity of collection rows, price records, inventory events and activity rows. Use a **disposable** store or synthetic fixtures; never clear or overwrite an owner's collection for testing.
- Release/profile configuration with the same entitlements and storage mode as the intended candidate. Distinguish simulator runs from physical-device evidence.
- Run a separate cold launch, then at least three warm journeys per condition. For high-percentile action latency, gather at least 30 comparable action samples before reporting p95; with fewer, report the individual timings/median and mark p95 **insufficient sample**. Report the sample count, outliers, cancellations and raw traces. Never fabricate benchmark results.

## Journeys and checkpoints

| Journey | What to measure | Relevant existing instrumentation |
| --- | --- | --- |
| Launch after process termination; warm relaunch | Time to interactive Portfolio/Collection; blank frame or blocked navigation | `measureLaunch`, `Launch.handoff`, `priceSnapshot.rebuild` |
| Raw scan to acknowledged save; immediate next scan | OCR confirmation → catalog resolution → durable save → visible receipt; misses and duplicate suppression | Scan session metrics and `collectionWriteLockWait` |
| Collection tab, filtering, sorting and opening detail | Tap → updated view; frame-time spikes; peak memory while scrolling | `makeCachedProjection`, `storeRevision.projectionRebuild` |
| Ordinary price refresh while browsing and editing | Checkpoint-to-visible-price latency; stalled UI and failed/duplicate refreshes | `priceRefresh.run`, `priceRefresh.commitStaged`, `priceSnapshot.apply` |
| Browse search and set detail with artwork | Search keystroke → results; first stable artwork; cache-hit/miss differences | Browse/cache instrumentation plus Instruments network |
| Background and return during a raw save or refresh | Consistency of receipt, ownership and price; time to usable camera | `App.scenePhase`, store generation/revision events |
| Offline cold start and existing collection navigation | Local usability and clear provider-unavailable feedback | Launch, projection and scene-phase intervals |

Use Instruments Time Profiler, Hangs, SwiftUI and Allocations alongside OSLog signposts, not timestamped UI screenshots alone. Also follow the existing [hang inspection protocol](../plans/hang-inspection-plan.md).

## Minimum representative fixtures

1. 100 logical raw holdings: basic control.
2. ~1,000 mixed raw holdings, with Pokémon and Magic variants, priced/unpriced items and repeat copies.
3. ~5,000 mixed holdings or the largest trustworthy disposable dataset available, with an aged event/price history.

Distinguish `row count` from `quantity`: 5,000 copies of one printing do not exercise the same projection as 5,000 distinct holdings.

## Result recording template

| Commit + device + store | Journey | n | Median ms | p95 ms | Max ms | Hangs/failed actions | Trace path |
| --- | --- | ---: | ---: | ---: | ---: | --- | --- |
| Not yet run | Not yet run | — | — | — | — | — | — |

A performance change is worth proposing only if the trace identifies a repeatable user-visible delay or resource problem, and the same workload after the change materially improves without worsening accuracy, storage behavior or battery/memory use. Do **not** optimize a hot-looking function solely because it is large or allocates often.

## Exit criteria

- Attach actual device traces and a completed table (or explicitly mark the missing runs).
- Classify each delay by camera/Vision, catalog, network, SwiftData/lock, derived snapshot, image decode, or SwiftUI rather than guessing.
- Record any unresolved regression as a release-gate input; do not call this slice "passed" because the protocol was written.
- Do not fold later performance fixes into this measurement PR; each demonstrated fix gets its own reviewable slice.
