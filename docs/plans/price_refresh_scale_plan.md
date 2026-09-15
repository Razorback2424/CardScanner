# Price refresh scale plan

**Status:** current scale backlog — reconciled 2026-09-14

This is the current plan for making automatic pricing continuous and unobtrusive
at large collection sizes. The detailed 2026-09-05 investigation is preserved in
the [legacy snapshot](../legacy/price_refresh_scale_plan.md); its old “main-actor
refresh” and suite-count statements are not current claims.

## Current implementation map

| Slice | Current status | Code evidence |
| --- | --- | --- |
| 1 — isolate progress observation | **Landed** | `ContentView` keeps the shared refresh controller as a plain reference; leaf controls observe only the state they render. |
| 2 — value-based collection projection | **Landed** | `CollectionProjectionStore` and `CollectionProjectionActor` build/send value snapshots rather than live SwiftData rows to the grid. |
| 3 — replace portfolio O(N) change detection | **Open; measurement first** | `PortfolioInputObserver` still derives its task identity from payload fields so CloudKit-delivered changes cannot be missed. |
| 4 — batch Magic catalog requests | **Open** | The refresh actor still calls `ScryfallService.fetchCard(id:…, ignoringCache: true)` per Magic printing; the existing 75-card batch API is used elsewhere, not by refresh. |
| 5 — continuous/resumable automatic sweep | **Open** | Background refresh remains bounded (`appRefreshTargetLimit = 3`); no durable sweep cursor and product/battery policy have been adopted. |
| 6 — actor-owned refresh persistence | **Landed** | `PriceRefreshModelActor` owns the refresh context, indexes, target construction, writes, and saves; the facade carries progress/value outcomes. |
| 7 — denormalized paging/search columns | **Conditional** | Defer until the remaining measurement gates show that projection and refresh work are still the bottleneck. |

The landed slices are implementation status, not release certification. A
successful simulator build does not retire the open profiling, provider, or
large-store gates.

## Open work and verification order

1. Capture a baseline with a seeded large collection and realistic price/history
   rows. Measure collection projection, `@Query` republishing, portfolio-input
   hashing, refresh index construction, and main-thread body counts.
2. Resolve the store-driven revision/debounce design for Slice 3. It must still
   notice CloudKit-delivered changes; a writer-only counter is insufficient.
3. Implement and test the Magic batch path with explicit `not_found` versus
   provider-unreachable classification and per-printing progress accounting.
4. Define the battery, cellular-data, and public-provider request budget before
   adding a persistent resumable automatic sweep.
5. Re-profile the actor boundary and checkpoint saves. Only then consider the
   conditional schema work in Slice 7.

The current release-facing measurement list remains in
[`release_followups.md`](release_followups.md). The archived plan retains the
source-level investigation, corrections, hazards, and proposed slice details.
