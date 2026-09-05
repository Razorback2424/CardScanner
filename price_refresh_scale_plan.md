# Price Refresh Scale Plan

Target: automatic price checking with no refresh button, and a UI that stays
responsive while thousands of prices are checked, at collection sizes up to
tens of thousands of distinct printings.

Status: **planning only.** No code changed. No builds or tests run. Every
runtime claim below is marked as either *traced statically* (I read the code
path) or *needs measurement* (I inferred cost but did not profile).

---

## 1. What the code does today

### 1.1 Automatic refresh already exists, in two weak forms

| Path | Trigger | Scope | File |
|---|---|---|---|
| `BGProcessingTask` | ~2:30am, **requires external power**, requires network | all stale targets | `Services/BackgroundPriceRefresh.swift:87` |
| `BGAppRefreshTask` | opportunistic, ≥1h apart | **3 targets** (`appRefreshTargetLimit`) | `Services/BackgroundPriceRefresh.swift:49` |
| Foreground sweep | once per process launch, latched by `hasCheckedForStalePrices` | all stale targets | `Views/ContentView.swift:484` |
| Manual button | user tap | all stale targets, `forceUnsupportedRetry` | `Views/ContentView.swift` → `refreshAllPrices` |

Staleness is `automaticRefreshInterval = 8h` (`PriceRefreshController.swift:224`).

So the button is not the only path — but the foreground sweep fires **once per
process lifetime** and never again, and the background paths need either a
charger or are capped at three cards. On a device that stays warm for days, or
a large collection where one sweep cannot finish, the app effectively depends
on the button.

### 1.2 The refresh is main-actor work

`PriceRefreshController` is `@MainActor` (`PriceRefreshController.swift:151`).
It creates a *separate* `ModelContext` for transactional isolation
(`:410`) — but that context is still driven **from the main thread**. On the
main thread, per pass:

- `PriceRefreshDataIndex(context:)` fetches **every `PriceRecord` and every
  `PriceObservation` in the store** (`PriceStore.swift:200-203`).
- `PriceRefreshTargets.make` is `@MainActor` and runs a full
  `LogicalCollection.project` over every card (`PriceRefreshTargets.swift:10`).
- Every response is decoded into records, ingested into the observation log,
  and saved — all inside the `withTaskGroup` loop on the main actor
  (`PriceRefreshController.swift:556-755`).

### 1.3 Three separate main-thread amplifiers fire during a refresh

**(a) Checkpoint saves republish unbounded `@Query`s.**
The catalog stage commits every 10 printings (`catalogCheckpointInterval`,
`:1603`). Each save invalidates:

- `@Query private var priceRecords: [PriceRecord]` — unbounded — in
  `CollectionView:81`, `ContentView` `PortfolioInputObserver:349`,
  `ScannerSettingsView:27`
- `@Query ... cards: [CollectedCard]` — unbounded — in the same three views

**(b) Two O(N) hash walks run in `body`.**

- `CollectionProjectionToken.make` hashes **~24 fields per card + ~12 per price
  record + 1 per artwork override** (`CollectionView.swift:8-70`).
- `PortfolioInputObserver.portfolioInputTaskID` hashes **every card, every
  `InventoryEvent`, every `CollectionActivity`, and every `PriceRecord`**
  (`ContentView.swift:404-460`).

Both are honest engineering — the comment at `CollectionView.swift:621` says
so: *"SwiftData has no cheap query revision; this fingerprint is still much
less work than … rebuilding every tile row."* That is true at 500 cards. At
20,000 cards with a long event history it is not.

**(c) Progress publication re-renders the whole tab tree — likely the
dominant cost, and previously unnoticed.**
`ContentView` holds `@StateObject private var refresh` (`ContentView.swift:17`).
`publishRefreshingProgress` writes `status` up to **4× per second**
(`progressPublishInterval = 0.25`, `:1607`). Each write invalidates
`ContentView.body`, which rebuilds the `TabView` and passes `CollectionView`
non-`Equatable` closures (`onOpenScanner`, `onRefresh`) and an existential
`catalog`, so `CollectionView.body` re-evaluates — which calls
`makeProjectionToken()` — which is the O(N) walk in (b).

**Net: the O(N) hash over the entire collection plausibly runs 4× per second
for the entire duration of a refresh, purely from the progress indicator.**
*Needs measurement* — confirm with `Self._printChanges()` on `CollectionView`
before relying on it — but it is consistent with "becomes almost unresponsive"
and it is the cheapest thing on this list to fix.

**(d) A recompute storm rides along.** Each checkpoint changes
`portfolioInputTaskID` → 300 ms debounce → `portfolio.recompute` → a full
`PortfolioComputationActor` replay, documented at **~2.5 s**
(`PortfolioReplaySnapshot.swift:384`). ~100 checkpoints over a 1,000-printing
pass means the portfolio is recomputing continuously for the whole refresh.
The replay is correctly off-main, but its result application, including
`PortfolioEngine.publish` writing close rows on the **main** context
(`PortfolioEngine.swift:510`), is not.

### 1.4 A full sweep is inherently long

- Catalog stage: `maxConcurrentRequests = 4` (`:228`), **one HTTP request per
  printing** (`PriceRefreshController.swift:1707`).
- 10,000 distinct printings ÷ 4 concurrent × ~200 ms ≈ **8+ minutes of
  continuous network**, before any vendor fallback.
- The JustTCG fallback is separately budgeted and rate-limited.

**This is the finding that reframes the goal.** Even with every main-thread
problem fixed, a full sweep of a 20,000-card collection cannot be fast. It has
to become *continuous, resumable and invisible*, not *fast*.

### 1.5 One large, already-built win is being left on the table

`ScryfallService.fetchCards(identifiers:)` posts to
`/cards/collection` and accepts **75 identifiers per request**
(`TCGdexService.swift:417`). It already exists and is already used by
`CollectionCatalogNormalizer:698`. The refresh calls `fetchCard(id:)` one card
at a time instead. For Magic that is a **75× reduction in requests**.

Pokémon has no equivalent: `fetchSet(id:)` returns `TCGdexCardBrief` values
with **no pricing fields** (`Models/TCGdexCard.swift:203-226`), so Pokémon
stays 1 request per printing on the free path. A large Pokémon collection is
therefore permanently incremental. *Traced statically; the Scryfall batch
response's ordering and `not_found` handling still needs care — see 4.2.*

---

## 2. Corrections to what I proposed in the previous message

I want these on the record before we build anything.

**2.1 "Move the refresh to a `@ModelActor`" would NOT have fixed the freeze on
its own.** `CollectionCSVImportActor` (`CollectionCSV.swift:1554`) already runs
imports off the main actor, and the audit still found imports janky — because
a background context's save still propagates to the main context and still
republishes every `@Query`. Moving work off-main does nothing about amplifiers
(a), (b) and (c). Slice ordering must reflect that.

**2.2 My "page the collection grid" slice was wrong as described.** I said push
predicate and sort into SwiftData. Reading `CollectionQuery` (`:294-400`) and
`LogicalCollection.project` (`:110`), that is not possible without schema
changes:

- Sorting uses `CollectorNumber.compare`, a custom Swift parser that splits
  `GG01a` into `("GG", 1, "a")`. Not expressible as a `SortDescriptor`.
- Price sort reads `unitPrice`, which lives in a **different table**
  (`PriceRecord`) with **no SwiftData relationship** to `CollectedCard`.
- Name search uses `CardNameSearch.normalize/matches`, not `CONTAINS`.
- Treatment filters do set-intersection over decoded JSON.
- The projection is a **whole-collection group-by** on `collectionKey` with a
  representative-row election; positions do not map 1:1 to rows, so you cannot
  page rows and get correct quantities.
- The summary total (`CollectionView:411`) and every filter-option count
  (`setOptions`, via `rowsForOptions`) are aggregates over the *entire*
  collection, so paging breaks them unless they become separate aggregate
  queries.

Real paging needs denormalized, maintained columns (a stored normalized name,
a stored collator-safe sort key, a stored unit price mirrored onto the row).
That is a genuine schema-and-invariants project, not a slice. It should be
last, and only if measurement says the projection is still the bottleneck once
1–5 below are done.

**2.3 My "monotonic revision counter bumped by writers" idea is unsafe as
stated.** CloudKit-delivered changes do not pass through our writers, so a
writer-incremented counter would silently miss remote updates — exactly the
case `portfolioInputTaskID`'s payload-field hashing was written to catch
(`ContentView.swift:414-416` says so explicitly). Any replacement signal must
be driven by the store, not by our call sites. See 4.1.

---

## 3. Proposed slices, in dependency order

Each slice is independently shippable and independently revertible.

### Slice 1 — Stop progress publication from re-rendering the collection
*Addresses 1.3(c). Smallest change, plausibly the largest single win.*

- Move `refresh` out of `ContentView`'s observation. `ContentView` should not
  be an `@StateObject` observer of a 4 Hz publisher. Put the status observation
  in the leaf views that draw it (`PortfolioView` already takes it as
  `@ObservedObject`; the collection's refresh affordance should observe it in
  its own small subview).
- Give `CollectionView` stable, `Equatable`-friendly inputs, or hoist the
  closures so a parent re-render does not force a body pass.
- Reduce progress publication to a coarser cadence (≥1 s) and to *whole-percent
  changes only*; there is no user value in 4 Hz on a multi-minute job.

**Regression risk:** low. **Watch for:** the refresh spinner/label must still
update, and `isTransientSuccessStatus` dismissal behavior
(`PriceRefreshController:1599`) must be unchanged.
**Verify:** `Self._printChanges()` on `CollectionView` during a refresh —
body passes should drop from ~4/s to ~0.

### Slice 2 — Make the collection projection a value snapshot, computed off-main
*Addresses 1.3(a)+(b) for the Collection tab.*

The pattern already exists in this codebase and is proven:
`PortfolioEngine` + `PortfolioComputationActor` produce
`[PortfolioHoldingSnapshot]` value types off-main, and `PortfolioView` renders
those. `CollectionView` should work the same way.

- Introduce a `CollectionProjectionStore` (`@MainActor` `ObservableObject`)
  fed by a `@ModelActor` that builds `[CollectionRow]` + the per-row diagnostic
  inputs as **`Sendable` value types**.
- `CollectionView` renders snapshots; it stops holding
  `@Query priceRecords` and stops calling `CollectionProjectionToken.make`.
- Recomputation is **coalesced and throttled** (e.g. 500 ms trailing), so a
  100-checkpoint refresh causes a handful of projections, not 100.

**Two things the tiles need that are currently live models:**
- `CollectionCardTile` reads only `name`, `setName`, `lowImageURL`,
  `highImageURL`, `itemKind`, `itemKindLabel`, `variant`,
  `displayedMagicTreatmentEvidence`, `quantity` (`CollectionView:834-930`).
  All trivially snapshot-able.
- `CollectionCardDetailView` and `MovementDetailsView` genuinely need a live
  `CollectedCard` because they edit it (`CollectionView:309`, `:332`). Resolve
  that with a single-row fetch by `collectionKey` at navigation time.

**Behavior change to decide deliberately:** today the detail column resolves
from `snapshot.entries`, which is the *filtered* list, so changing a filter
while a card is open replaces the detail with "Card not shown"
(`CollectionView:321-327`). Fetching by key would keep the card visible.
That is arguably better, but it is a deliberate documented behavior — we
should choose, not drift.

**Regression risk:** medium — this is the largest view change. The projection
logic itself (`LogicalCollection.project`, representative election,
`duplicatePositionPricingConflict` defects) must move **unchanged**; only its
host changes.

### Slice 3 — Replace `portfolioInputTaskID`'s O(N) walk
*Addresses 1.3(b) for the Portfolio observer, and 1.3(d).*

Must satisfy the CloudKit constraint in 2.3: the signal has to come from the
store. Two candidate mechanisms, **needs measurement / needs a runtime
spike** to choose:

- **(i) Narrow the observing query.** Keep a tiny observer view whose `@Query`
  carries a `FetchDescriptor` with `fetchLimit: 1` and a `propertiesToFetch`
  subset. SwiftUI still invalidates on any change to that entity, but the
  fetch itself is O(1) instead of O(N). The body then bumps a counter and lets
  a throttled, off-main pass decide whether anything really changed.
  *Assumption to verify: `@Query` invalidation is entity-scoped, not
  result-scoped.* If it is result-scoped this does not work.
- **(ii) Observe the store directly.** `ModelContext.didSave` notifications,
  plus whatever the CloudKit mirroring layer posts. Needs a spike to confirm
  remote-change delivery; if it does not fire for CloudKit imports, (i) is the
  answer.

Either way, add a **debounce with a floor** so a long refresh triggers at most
one portfolio recompute per N seconds, and one final recompute on completion.

**Regression risk:** medium-high — this is the mechanism that notices a
late-arriving CloudKit event or a repaired row. Getting it wrong means a stale
portfolio on a second device, which is exactly finding 3 of the last audit.
**Verify:** two-store test — mutate in store B, confirm store A recomputes.

### Slice 4 — Batch Magic catalog requests 75× per call
*Addresses 1.4 for Magic. Uses an existing, already-exercised client method.*

- Group Magic printings into chunks of ≤75 and call
  `fetchCards(identifiers:)` instead of per-card `fetchCard(id:)`.
- **Must preserve the identity guard.** The current code rejects a response
  whose `card.id` does not match the requested printing
  (`PriceRefreshController:1739-1742`) — that guard exists so a redirect
  cannot value a different row. In batch form: map the response **by id**, and
  treat any requested id absent from the response (Scryfall returns these in
  `not_found`) as `.failed`, **not** `.unreachable`. Conflating them would
  make a batch of missing cards look like an outage and would trip
  `consecutiveUnreachable` / `unreachableThreshold` (`:233`).
- Cache policy: the per-card path passes `ignoringCache: true`. The batch path
  is a POST and is not URL-cached; confirm that is acceptable and intentional.
- Progress accounting is currently per-printing (`completed += 1`). Batching
  changes the unit; keep the *displayed* unit as printings so the user-visible
  meaning does not change.

**Regression risk:** medium, concentrated in error classification.
**Pokémon is explicitly out of scope for this slice** — no free batch endpoint
exists (1.5).

### Slice 5 — Continuous, budgeted, resumable auto-refresh
*This is the slice that removes the button, and it depends on 1–4.*

- Delete the `hasCheckedForStalePrices` process-lifetime latch. Replace with a
  persisted `lastAutomaticSweepAt` plus the existing per-record `lastCheckedAt`
  staleness, so state survives relaunch.
- Add a **persistent cursor** so a sweep that cannot finish resumes where it
  stopped instead of restarting at the oldest target every launch. Ordering by
  `lastCheckedAt` ascending already exists
  (`BackgroundPriceRefresh.swift:196`); make it durable.
- **Budget each sweep** (e.g. N printings or T seconds, whichever first) rather
  than draining all stale targets. A 20,000-card collection converges over many
  small sweeps instead of one 20-minute pass.
- Trigger on: foreground activation (subject to a minimum interval), a low
  frequency timer while foregrounded, after an import or scan, and the existing
  BG tasks — with `appRefreshTargetLimit` raised once the work is cheap.
- Keep the button as an explicit "do it all now, ignore the budget", which is
  also the only path that sets `forceUnsupportedRetry`.

**Regression risk:** medium. Automatic network work is a battery, data and
third-party-politeness question, not just a performance one. TCGdex is a free
public API and a 10,000-request sweep should be paced deliberately.
**Watch for:** the sweep must stay behind
`MagicTreatmentMigrationCoordinator.withPriceRefresh`
(`MagicTreatmentMigration.swift:1932`), which is `@MainActor` — acquire the
gate on main, then hop to the actor, holding it across the whole slice.

### Slice 6 — Move the refresh's SwiftData work to a `@ModelActor`
*Deliberately after 1–5, not first.*

Mirror `CollectionCSVImportActor` and `PortfolioComputationActor`. The main
actor keeps status/progress and the fallback budget UI; the actor owns the
context, the index, target construction, record writes and saves.

Boundary is mostly clean: `PriceTarget`, `PriceLookup`, `IdentifiedCard` and
the summary types are already value types, and the pure statics tests depend on
(`staleTargets`, `needsFallback`, `permitsVendorWork`, `hasFinishedPrice`,
`isTransientSuccessStatus`, `applyVendorBatchHit`) are already `nonisolated
static` and must stay exactly where they are — **all 34 test files touch only
those**, so this slice should not require test changes.

**Hazards specific to this slice:**
- The refresh mutates `CollectedCard` rows (`applyCatalogMetadata`,
  `recordCatalogMetadataCheck`, `PriceRefreshController:576-583`) and resolves
  them through `store.context.model(for:)` with `PersistentIdentifier`s from
  `importedCardIDsByProviderID`. Persistent IDs are safe to cross actors;
  **model objects are not**. Audit every crossing.
- Genuinely concurrent writes to `CollectedCard` become possible with the main
  context, the CSV import actor and `CollectionCatalogNormalizer` (which also
  writes on its own schedule, `CollectionCatalogNormalizer.swift:179`).
  There is **no merge policy configured anywhere in the app** — `PriceStore.save()`
  simply rolls back on failure (`PriceStore.swift:731`). Decide the policy
  explicitly rather than discovering it.
- The container has **two configurations** — `PriceRecord` is in the synced
  store, `PriceObservation` in the local-only store
  (`TradingCardScannerApp.swift:56-91`) — and `PriceStore.store()` writes both
  under one `save()`. Cross-store saves are not atomic. This is pre-existing,
  but the batching redesign must not widen the window.

### Slice 7 — Only if measurement demands it
Denormalized sort/search columns and true grid paging, per 2.2.

---

## 4. Open questions to resolve before coding

1. **`@Query` invalidation granularity** — entity-scoped or result-scoped?
   Slice 3(i) depends on it. One spike answers it.
2. **CloudKit remote-change delivery** — does anything user-visible post when
   the mirroring layer imports? Determines Slice 3(ii)'s viability and is the
   single biggest correctness risk in this plan.
3. **Detail-view filtering behavior** (Slice 2) — keep "Card not shown" on
   filter change, or keep the card visible? Product call.
4. **Auto-refresh aggressiveness** (Slice 5) — how much cellular data and
   battery is acceptable, and what is a polite request rate against a free
   public API for a 20,000-card collection?
5. **Whether `PriceRefreshDataIndex` should stop loading full observation
   history.** It already narrows to newest-per-instrument in memory
   (`PriceStore.swift:192-195`) but **fetches every row first** (`:203`). At
   tens of thousands of instruments with months of history this is a large
   allocation on every pass.

## 5. What I have not established

- No profiling. The relative weights of (a) save republish, (b) hash walks and
  (c) progress re-render are **inferred from reading the code**, not measured.
  (c) is a prediction, and Slice 1 is cheap enough to be worth doing as its own
  experiment before committing to Slice 2.
- No seeded large-collection store exists to measure against. Building one
  (10k and 50k rows with realistic event history) should precede Slice 2, or we
  will not be able to tell whether any of this worked.
- No build or test run in this session, per instruction.
