> **Legacy archive — scanning workflow review snapshot, 2026-09-14.** This
> review records the pre-remediation F1–F5 findings and is not a current defect
> list. Use the current scanner source, [`release_followups.md`](../plans/release_followups.md),
> and [`progress.md`](../../progress.md) for current status.

I've read through the scanning workflow end to end: `CardScanner` (Vision/cadence/latch/slab), `ScannerViewModel` (session lifecycle, identification queue, routing, commit), `CardCatalog` (prefetch, offline/disk/session caches, circuit breakers), `CollectionStore`/`ScannerCollectionWriter` (persistence), and the SwiftUI surface (`ScannerView`, `CameraPreview`, `ScanSessionOverlays`, `ScanReviewSheet`, `ContentView`/`StoreRevisionMonitor`).

---

# Scanning workflow review

## 1. Overall assessment

This is a genuinely well-built pipeline, and unusually so in the places that normally go wrong. The hard problem — *"how do you automatically add cards without ever adding a phantom duplicate"* — has been solved with a coherent, layered evidence model (latch → confirmation window → spatial tracker proof → explicit held-repeat permit), and the invariants are documented where they're enforced rather than in a design doc. Speculative prefetch overlapping OCR confirmation, the two-phase recognized/saved acknowledgement, per-provider circuit breakers, generation + session-token fencing on every async completion, and bounded caches keyed to OCR instability are all correct and load-bearing decisions. I would not restructure any of it.

The problems I found are not architectural. They're a handful of small state-management slips whose blast radius is disproportionate to their size, some per-card work that scales with session length, and one or two UI behaviours that read as bugs to a user even though the state underneath is correct. Most of the fixes are one to ten lines.

Two caveats on scope: I could not run or profile anything, so everything I label a *performance* claim is either a complexity argument I can defend from the code, or explicitly routed to §7 for measurement. And this codebase is already heavily instrumented with `OSSignposter` intervals carrying `sessionScans.count` metadata — the authors clearly anticipated the scaling questions — so several of my §7 items are "you already built the instrument; go read it on a device."

---

## 2. Highest-value issues to address before release

### F1 — `identificationTask` is never cleared on invalidation, stalling every session departure by 2 seconds

**Where:** [ScannerViewModel.swift:1592](../../TradingCardScanner/Views/ScannerViewModel.swift:1592) and [ScannerViewModel.swift:3135](../../TradingCardScanner/Views/ScannerViewModel.swift:3135) (`invalidatePendingScan`, `invalidateResolutionForDuplicatePrompt`), consumed at [ScannerViewModel.swift:1365](../../TradingCardScanner/Views/ScannerViewModel.swift:1365).

**What it does now:** Both invalidation paths do `identificationTask?.cancel(); activeIdentificationRequestID = nil` but leave `identificationTask` non-`nil`. The only place that clears it is `finishIdentificationRequest`, which opens with `guard activeIdentificationRequestID == requestID else { return }` — and that guard now fails, because the invalidation just nulled it. So the cancelled task completes, returns early, and `identificationTask` stays permanently non-`nil` until some *later* identification runs to completion.

`beginSessionFinalization` then waits on exactly that variable:

```swift
while self.identificationTask != nil, !Task.isCancelled, Date.now < deadline {
    try? await Task.sleep(for: .milliseconds(10))
}
```

and it calls `invalidatePendingScan()` itself immediately beforehand.

**Why it matters in practice:** Scan a card, and while the catalog lookup is in flight switch to another tab. The drain loop now burns its full `sessionFinalizationDrainTimeout` of 2 seconds — polling the main actor every 10 ms — before publishing the departure summary and calling `endScannerBulkWriteIfNeeded()`. Three user-visible consequences: the "12 cards · $340 added" banner arrives 2 s late; the derived-state generation bump (and therefore the Collection/Portfolio refresh) is delayed by the same 2 s on top of its own 300 ms debounce; and — worst — if the user taps back onto Scan within that window, `start()` sees `sessionFinalizationTask != nil`, parks the request in `pendingSessionStart`, and **does not start the camera**. The scanner is a frozen black rectangle for up to two seconds. The same stale state is left behind by backgrounding mid-lookup (`scenePhaseChanged(isActive:false)`) and by the duplicate prompt, so the stall can also fire on a departure long after the triggering event.

**Confidence:** High on the mechanism — it's directly readable from the three call sites. Medium on frequency, since it needs an in-flight identification at invalidation time; on a slow network that's most departures.

**Smallest remedy:** Add `identificationTask = nil` immediately after `identificationTask?.cancel()` at both invalidation sites. Cancellation is already the invalidation fence — every completion from a cancelled task is rejected by `isCurrent(request)` — so there is nothing left for the drain to wait for.

**Expected benefit:** Departure summary and derived-state refresh become immediate; re-entering Scan is never dead.
**Regression risk:** Very low. The drain's real purpose is `pendingWriteCounts`, which is untouched.
**Complexity:** Reduces (removes a latent invariant nobody can see).
**How to verify:** Instruments on the existing signposts — a `derivedStateBulkWrite` interval that ends ~2000 ms after the tab change today should end within a few ms. By hand: start a lookup on airplane-mode-slow network, switch tabs, switch straight back, confirm the preview is live immediately.

---

### F2 — Returning to the Scan tab fires a false "card added" flash

**Where:** [CameraPreview.swift](../../TradingCardScanner/Views/CameraPreview.swift) `syncSuccessCount` / `syncRecognitionCount`, driven by the reset in [ScannerViewModel.swift:1288](../../TradingCardScanner/Views/ScannerViewModel.swift:1288).

**What it does now:** `start()` sets `successCount = 0` and `recognitionCount = 0` when a new session begins. `PreviewView` survives the tab switch (SwiftUI retains tab content), so `lastSuccessCount` is still, say, `7`. The guard is `guard count != lastSuccessCount` plus `isFirstSync = (lastSuccessCount == 0 && count == 0)`. With `7 → 0` neither fires, so both the green success flash and the cyan recognition pulse animate on the scan band.

**Why it matters in practice:** In this app the green band flash *is* the statement "a card was just added to your collection" — it's the acknowledgement the user watches instead of the screen. Firing it on an empty band, before any card has been presented, is exactly the signal the rest of the design works hard to keep honest. It happens on every return to Scan after a session with at least one scan, i.e. constantly.

**Confidence:** High on the logic. High-but-not-certain on `PreviewView` surviving the tab switch — trivially confirmed with a breakpoint in `makeUIView`.

**Smallest remedy:** A counter only ever increases within a session, so a decrease *is* the session reset. Change the early-out to skip the animation when `count < lastSuccessCount` (still updating `lastSuccessCount`). That also lets `isFirstSync` go away.

**Expected benefit:** Removes a false success signal.
**Regression risk:** Very low.
**Complexity:** Reduces (deletes the `isFirstSync` special case).
**How to verify:** Scan one card, switch to Portfolio, switch back — the band must stay steady green.

---

### F3 — The tab bar hides and shows on every scan, shifting the whole bottom stack

**Where:** [ScannerView.swift:116](../../TradingCardScanner/Views/ScannerView.swift:116) — `.toolbar(isThumbZoneContested ? .hidden : .visible, for: .tabBar)`.

**What it does now:** `isThumbZoneContested` is true whenever an acknowledgement, receipt, or any choice bar is on screen. A normal scan drives it `false → true` at OCR confirmation and back to `false` about five seconds after the receipt expires. Hiding the tab bar changes the bottom safe-area inset, and `ScannerChrome` respects the safe area — so the receipt card, the recent-scan rail, and the "needs attention" chip all translate vertically by roughly a tab bar's height and back, once per card.

**Why it matters in practice:** During a fast burst the receipt keeps being replaced and the bar stays hidden, so it's invisible. But the realistic cadence — pick up a card, present it, put it down, pick up the next — is slower than the five-second receipt lifetime, so the entire bottom UI pumps up and down once per card, and the rail thumbnails the user is glancing at move while they're looking at them. The intent behind the modifier (documented as "the tab bar only yields its space while a transient surface occupies the thumb zone") is right; the trigger is too twitchy.

**Confidence:** High on the mechanism. Medium on how objectionable it looks — this is worth watching on a device for thirty seconds before deciding.

**Smallest remedy:** Narrow the trigger to the surfaces that actually contest the thumb zone — the four choice/confirmation bars — and drop `receipt` and `scanAcknowledgement` from it. Those two are informational and don't need the tab bar's space. That leaves the tab bar stable through an ordinary scan and yielding only for a real question.

**Expected benefit:** The bottom of the scanner stops moving during routine scanning.
**Regression risk:** Low; the receipt may sit slightly closer to the tab bar. Check the receipt's Undo button still clears it.
**Complexity:** Reduces (two fewer terms).
**How to verify:** Record the screen while scanning six cards at a human pace; nothing below the viewfinder should translate except the receipt's own transition.

---

## 3. Performance / responsiveness worth fixing

### F4 — The offline historical-Pokémon catalog is rebuilt from scratch for every OCR spelling of the title

**Where:** `PokemonOfflineCatalog.historicalCard(for:)` at [CardCatalog.swift:258](../../TradingCardScanner/Services/CardCatalog.swift:258), reached first in `CardCatalog.start(_:)` at [CardCatalog.swift:938](../../TradingCardScanner/Services/CardCatalog.swift:938).

**What it does now:** For a `.pokemonHistorical` identifier it resolves candidate set IDs from the denominator, loads each candidate's merged checklist, assembles a fresh `PokemonChecklistSnapshot` value, then walks every summary in every candidate set to build two dictionaries before handing off to the pure resolver. This is keyed on nothing — there's no memo.

Meanwhile the identifier for a historical card is deliberately unstable: `historicalIdentifier(...)` does `attempt.titleCandidates.formUnion(...)` across up to six retries within a 1.5 s window, so the `ScanSubject` changes on most frames. `announcePlausible` only suppresses an *identical* repeat, so each new spelling fires `onPlausibleCandidate` → `catalog.prefetch(identifier)` → a brand-new `start(_:)` → another full snapshot rebuild. `persistentKey(for:)` correctly returns `nil` for historical, so the disk cache can't absorb it either.

The network side of this is already handled well — `PokemonHistoricalCatalog` memoizes directory, set, and card tasks by stable provider key precisely because of this instability, and the `BoundedCache` doc comment explains the identifier churn. The offline path, which runs **before** it, just didn't get the same treatment.

**Why it matters in practice:** Vintage Pokémon is the slowest identity path in the app and the one where the user is already waiting. Up to ~6 redundant multi-hundred-row dictionary builds per card presentation, serialized on the `CardCatalog` actor — which means they're also queued ahead of the *confirmed* lookup the user is actually waiting for. This is the one place where the speculative-prefetch design works against itself.

**Confidence:** High that the work is repeated; unknown magnitude. The checklists are LRU-cached at capacity 10 per tier so the file I/O is usually avoided, but the dictionary construction is not.

**Smallest remedy:** The candidate identity map depends only on `evidence.number` (the stable part) — never on the title candidates. Memoize `identitiesByProviderID` / `summariesByProviderID` in the actor keyed by `evidence.number`, and let the varying title evidence hit only the pure `PokemonHistoricalIdentityResolver.resolve` call. That is one small dictionary plus a lookup.

**Expected benefit:** Repeat spellings of the same physical card become near-free; time-to-identity for vintage cards improves by whatever the rebuild costs.
**Regression risk:** Low — the memo is keyed on the input the result actually depends on, and the resolver stays pure. Make sure the memo is cleared when the checklist store publishes a refresh.
**Complexity:** Slight increase (one memo), mirroring the memo pattern already used one layer down.
**How to verify:** Instruments on the existing `cardCatalogResolution` signpost while scanning one vintage card: count the intervals per physical card presentation, and compare the `historical-fallback`/`cache-hit` durations before and after.

---

### F5 — `queueFallbackPrice` walks the whole session on every commit that needs a fallback quote

**Where:** [ScannerViewModel.swift:2916](../../TradingCardScanner/Views/ScannerViewModel.swift:2916).

**What it does now:** After a successful add whose catalog quote was unusable, it computes

```swift
let interestedScanIDs = Set(
    sessionScans.filter { fallbackPriceKey(for: $0) == key }.map(\.id)
)
```

`fallbackPriceKey(for:)` is not a stored property — it rebuilds the printing ID string and re-derives `MagicTreatmentKeyCodec.storedIDs(...)` per scan. So this is O(session length) with a string build per element, on the main actor, inside the per-card commit path. Over a long session it's O(n²) total.

**Why it matters in practice:** This app's own design documents assume hundred-card sessions and five-thousand-card collections. It's gated behind `needsFallback` and `PriceVendorCredentials.hasKey`, so it doesn't fire for every card — but it fires for exactly the cards the catalog couldn't price, which in a vintage or Magic-heavy box is a large fraction. The adjacent `applyFallbackQuote` and `offerHeldDuplicate` have the same shape and are *both* wrapped in signpost intervals carrying `sessionScans.count` for precisely this reason; this one isn't instrumented at all, and it's the one on the latency path.

**Confidence:** High on the complexity. Medium on whether it's currently perceptible — a few hundred string builds is sub-millisecond, so this is a "it degrades as sessions get long" problem rather than a present-tense hitch.

**Smallest remedy:** Maintain a `[String: Set<UUID>]` keyed by fallback price key, appended to in `appendCommittedScan` and maintained in `undoScan`/`correct`. Every previously-added scan with this key already registered itself when it was added, so the commit path only needs to insert the new one. That also makes `applyFallbackQuote`'s loop a direct lookup rather than a scan.

**Expected benefit:** Per-card commit cost becomes flat in session length.
**Regression risk:** Low-moderate — the index must be kept correct across undo and correction, which is exactly what the existing `sessionScans`/`recent` maintenance already does at those sites.
**Complexity:** Roughly neutral: adds one dictionary, deletes two O(n) scans and the `fallbackPriceKey(for: RecentScan)` overload.
**How to verify:** Add the same signpost wrapper the two sibling functions already use, then plot `oneCardScan` duration against the `sessionScans=` metadata across one long session — the existing `endOneCardScan` comment says this is already the intended decisive test.

---

### F6 — Every Magic scan may pay three unindexed prefix scans across three tables

**Where:** `canonicalKeyForLegacyRow` at [CollectionStore.swift:632](../../TradingCardScanner/Services/CollectionStore.swift:632), reached from `card(forAnyKey:)` at [CollectionStore.swift:1035](../../TradingCardScanner/Services/CollectionStore.swift:1035).

**What it does now:** For a treatment-free `magic:` key it fetches `CollectedCard`, `CollectionActivity`, and `InventoryEvent` filtered by `collectionKey.starts(with:)`. `ScannerCollectionWriter.add` reaches `card(forAnyKey:)` twice per scan (once via `uniqueCard(forAnyKey:)` inside `store.add`, once directly at line 125 to stage the price), so a fresh Magic identity can cost six of these.

There *is* a memo (`CollectionStoreSession`), and importantly the scanner path passes `savesChanges: false` so `commit()`/`session.invalidate()` doesn't run per scan — the memo does survive within a scanning run. So the cost is per *distinct* Magic printing, not per card. But any undo, correction, or background price write goes through `commit()` and wipes it for everyone.

**Why it matters in practice:** `starts(with:)` on an unindexed string column is a table scan. `InventoryEvent` is append-only and is the largest table in the schema for a long-lived user. For a 5,000-card collection with years of ledger history this is the single most expensive thing on the commit path, and it exists to catch a migration edge case (a newer device synced a treatment-qualified row that this device lacks).

**Confidence:** Medium. I'm confident about the query shape and the call count; I am *not* confident about the actual cost, because I don't know whether SwiftData/Core Data materialises a usable index here or how large these tables get in practice. This is a measure-first item, not a change-now item — see §7.

**Smallest remedy if measurement confirms it:** The cheapest correct fix is to stop invalidating the whole memo on every `commit()` and invalidate only the keys a save could have affected — or, if that's too fiddly, cache negative results (`.noMatch`) across commits, since a "no legacy row exists" answer can only be falsified by a sync arrival, which `StoreRevisionMonitor` already detects and already calls `invalidateIdentityAliasCache()` for. Do not add an index or restructure the keys for this.

**Regression risk:** Moderate — this guards a correctness property (not creating a duplicate position). Don't touch it without the measurement.

---

## 4. UX / polish worth fixing

Beyond **F2** and **F3** above:

### F7 — A transient scene-phase blip cancels an in-flight scan

**Where:** [ScannerView.swift:84](../../TradingCardScanner/Views/ScannerView.swift:84) → `scenePhaseChanged(isActive: phase == .active)` → `invalidatePendingScan()`.

Anything that makes the scene merely `.inactive` — pulling down Notification Centre, a call banner, the app switcher gesture, a system permission alert — takes the same path as a real background transition and discards the card currently being resolved. The user gets no message; the card simply doesn't appear, and (via F1) leaves the stale task behind.

**Confidence:** High on the code path, medium on whether it's worth changing — treating `.inactive` conservatively is a defensible choice, and the fix (distinguishing `.inactive` from `.background`) adds a state. I'd note it, watch for it in testing, and only change it if it actually bites. If you do change it: only `.background` should invalidate; `.inactive` should pause recognition without bumping `scanGeneration`.

### F8 — `ScanReviewSheet` shows a frozen price

`ScanReviewSheet` takes `scan: RecentScan` by value. If a JustTCG fallback quote lands while the sheet is open, `applyFallbackQuote` updates `sessionScans`, `recent`, and the receipt — but not the open sheet. The user sees "Price unavailable" on a card that now has a price. Low frequency, low severity; the smallest fix is to look the scan up from `model.sessionScans` by ID inside the sheet rather than capturing it. Only worth doing if you happen to be in that file.

---

## 5. Complexity that can safely be removed

All of these are dead or near-dead and cost nothing to delete:

| What | Where | Note |
|---|---|---|
| `resolutionTask` | [ScannerViewModel.swift:979](../../TradingCardScanner/Views/ScannerViewModel.swift:979) | Declared, `.cancel()`ed in two invalidation paths, **never assigned anywhere**. Pure noise that reads like a real fence. |
| `undoLastAdd()` + the entire `lastAdd` property | [ScannerViewModel.swift:2104](../../TradingCardScanner/Views/ScannerViewModel.swift:2104) | `undoLastAdd` has no callers in app or tests. `lastAdd` is read *only* by it, but is written and maintained at four sites (commit, correct, undo, fallback-apply). Deleting the method lets all four maintenance sites go. |
| `activeFinishLocks` and `finishLock(for:)` | [ScannerViewModel.swift:1885](../../TradingCardScanner/Views/ScannerViewModel.swift:1885) | No callers. `FinishLockControl` computes its own `activeLocks` locally. |
| `onObservedCandidate` main-actor hop | [CardScanner.swift:1815](../../TradingCardScanner/Services/CardScanner.swift:1815) → `observeCatalogMissVerification` | Fires a `Task { @MainActor }` for **every** parsed frame, and the handler's first line returns unless `catalogMissVerification` is non-nil — which is almost never. The scanner already mirrors `catalogMissSuppressionKey` on the vision queue for exactly this kind of hot-path decision; guarding the callback with `parsed.suppressionKey == catalogMissSuppressionKey` is equivalent and removes ~4 pointless main-actor tasks per second during scanning. |

I'd also flag, but not necessarily remove, the signpost instrumentation *inside* `CardLatch.observeSubject` ([CardLatch.swift:126](../../TradingCardScanner/Services/CardLatch.swift:126)): it calls `PerformanceSignpost.makeID()` and builds an interpolated `String` on every OCR frame, inside what is otherwise a pure, fake-clockable value type. The cost is negligible; the *placement* is the issue — it's the one thing in that file that isn't pure policy. Move it to the caller in `handleFooterOutcome` if you touch it.

---

## 6. Concrete correctness / reliability problems

- **F1** is the real one, and it's a state-machine bug, not a style issue.
- **F2** is a correctness bug in the acknowledgement channel: the app asserts "added" when nothing was added.
- **Latent, low-probability:** `beginPendingResolution` opens with `guard !isProcessingIdentification else { return }` ([ScannerViewModel.swift:2299](../../TradingCardScanner/Views/ScannerViewModel.swift:2299)), but its callers (`choose(_ variant:)`, `choose(_ printRun:)`, `choose(_ candidate:)`) clear their pending state *before* calling it. If a tap were ever delivered in the window between `resolveVariant` publishing `pendingChoice` and the enclosing task reaching `finishIdentificationRequest`, the bar would vanish and the card would be silently dropped. I traced the window and believe it is not reachable in practice — SwiftUI needs a render pass plus a human tap, and the task continuation resumes far sooner — and the duplicate-prompt path explicitly clears `isProcessingIdentification` in `invalidateResolutionForDuplicatePrompt` to avoid exactly this. **I am reporting it as an observation, not recommending a change**; there's no evidence it fires, and "fixing" it would mean either dropping a guard that's protecting ordering or adding a queue. Worth a comment at the guard noting why the callers are safe.
- **Not a bug, but worth knowing:** `ScannerView` attaches five `.sheet` modifiers to one view. Only one can present at a time; a second binding set while another sheet is up would leave `isBlockedByPresentation == true` with no dismissal callback to clear it, wedging recognition. I could not construct a reachable path — every route into a sheet goes through `pauseForPresentation()`, which stops recognition and therefore stops anything else from wanting a sheet. Leave it; just don't add a sixth.
- **Memory, not correctness:** `sessionScans` retains the full decoded `IdentifiedCard` plus its `options` array for every card, unbounded, for the life of the session — deliberately, so the review sheet stays complete. `committedSessionHistory` is capped at 6 with a comment about not retaining "every decoded catalog payload forever", which `sessionScans` then does. That's a defensible trade for the feature, but at a thousand cards it's tens of megabytes. Not worth changing now; worth watching in a long-session memory graph.

---

## 7. Things to measure before changing anything

1. **The 4K preset under sustained load.** `applyBestPreset` takes `.hd4K3840x2160` when available, and the reasoning is sound — the identifier strip is ~4 mm of print and pixels on it are the binding constraint for `.accurate` OCR. But the cadence scheduler consumes at most ~4 OCR frames and ~8 tracker frames per second out of 30, so the session is moving roughly 370 MB/s of pixel buffers to discard most of them. Capping `activeVideoMinFrameDuration` would recover that, **but it also slows the preview**, which is the product surface. Do not change this blind: run a 10-minute continuous scanning session on the oldest supported device and watch thermal state and frame-drop. If it doesn't throttle, leave it exactly as it is.
2. **Liquid Glass surfaces over a live 4K preview.** Up to five or six `glassEffect` surfaces can be on screen at once, each sampling and blurring a continuously-updating backdrop. Same test as above; separate the variable by running once with the pre-iOS-26 fallback path forced.
3. **F6 — the legacy-key prefix probe.** Instrument `CollectionStore.add` (the signpost already exists) against a store seeded to a realistic size: 5,000 cards, and an `InventoryEvent` table with a few years of history. If `scannerPersistence` stays in single-digit milliseconds, close the item.
4. **The graded slab path's 2.5 s vendor gate.** `resolvePrintRun` awaits `ScannedGradedResolver.resolve` *before* the commit, because the outcome selects between `addGraded` and `addScannedGraded` — different row shapes, not just different prices. So the block is load-bearing and I am **not** recommending you make it asynchronous. But measure how often it actually hits the 2.5 s timeout in the field. If it's common, the right conversation is about the timeout value or the vendor lane, not about the ordering.
5. **SwiftUI rebuild count per card.** Both `ScannerView` (via `@EnvironmentObject`) and `ScannerChrome` (via `@ObservedObject`) depend on the whole view model, and a single card publishes `recognitionCount`, `scanAcknowledgement`, `receipt`, `recent`, `sessionScans`, and `successCount` — roughly six full re-evaluations of the hierarchy, each re-running the `.toolbar` and five `.sheet` modifiers. `ScannerTopBar` and `FinishLockControl` are already `Equatable` to blunt this, which suggests it was considered. Count it with `_printChanges()` or the `StoreRevisionMonitor.body` signpost pattern before deciding whether batching the publishes is worth the coupling it would introduce.
6. **F5's actual magnitude**, via the signpost described in that item.

---

## 8. Investigated and specifically recommend NOT changing

- **The duplicate-prevention architecture.** Latch + confirmation window + spatial tracker proof + held-repeat permit is more machinery than a naive reading would suggest is necessary, and every layer is doing real work: the strict `SpatialExitObservationAccumulator`, the `SpatialTrackerSeedGate`'s sticky lost-identity marker, the one-shot proof consumption in `routeCollectionCandidate`. The trade is stated explicitly in `CardLatch`'s header and it is the right one. Leave it alone.
- **Speculative prefetch on plausible candidates.** `max(confirmation, network)` instead of their sum, with speculation structurally inert because results are filed under the identifier nobody will ask for. Correct.
- **The two-phase `recognized` → `saved` acknowledgement.** Distinguishing the OCR boundary from the durable-write boundary is what keeps the receipt honest under a slow catalog. Don't collapse it.
- **The circuit breakers** (`TCGdexCircuitBreaker.shared` / `.scryfallShared`, with failure-kind-dependent backoff and a failure count that deliberately survives cooldown expiry). The per-host separation and the "a 5xx is not the same outage as a refused connection" distinction are both correct and hard-won-looking.
- **`BoundedCache` and the `PokemonHistoricalCatalog` task memos.** Keyed exactly where OCR instability demands it. The `usage.removeAll { $0 == key }` in `touch` is O(n) on a ≤256-element array; that's a non-issue and converting it to a linked list would be pure cost.
- **`ScannerCollectionWriter` as a `@ModelActor` with only value types crossing the boundary.** This is the correct shape and is why the persistence path is as clean as it is.
- **The `savesChanges: false` + explicit `saveModelContext()` transaction in `ScannerCollectionWriter.add`,** with `modelContext.rollback()` on any failure. Genuinely atomic across row, ledger, activity, and price. Don't refactor it into the generic `add` path.
- **The `.pauseForPresentation()` / `settingsDismissed()` recognition-eligibility gate** (`ScannerRecognitionEligibility` as a single value with one `allowsRecognition`). This is the tidy version of a class of bug that usually sprawls. Keep.

---

## 9. Conservative remediation roadmap

Each slice is independently shippable and independently testable. Slices 1–3 are the ones I'd want in before launch.

**Slice 1 — `identificationTask` lifecycle (F1).** Two lines. Verify: `derivedStateBulkWrite` ends promptly after a mid-lookup tab change; re-entering Scan within 2 s shows a live preview.

**Slice 2 — false success flash (F2).** One line in `syncSuccessCount`, one in `syncRecognitionCount`, delete `isFirstSync`. Verify: scan → leave tab → return → band steady.

**Slice 3 — dead code removal (§5, first three rows).** `resolutionTask`, `undoLastAdd` + `lastAdd` and its four maintenance sites, `activeFinishLocks` + `finishLock(for:)`. Verify: compiles, full suite green. Do this *after* slices 1–2 so the diffs stay readable.

**Slice 4 — tab bar trigger (F3).** Narrow `isThumbZoneContested` to the four choice/confirmation bars. Verify: screen recording of a six-card slow-paced session; nothing below the viewfinder translates.

**Slice 5 — `onObservedCandidate` guard (§5, fourth row).** One guard in `CardScanner`. Verify: the catalog-miss verification window still fires after three of five matching reads — `ScanSubjectSuppressionTests` and the catalog-miss tests should cover this; confirm before changing.

**Slice 6 — measurement pass (§7).** No code changes beyond adding the one missing signpost around `queueFallbackPrice`. Produce numbers for F5, F6, the 4K/glass thermal question, and the graded timeout rate. **This slice gates 7 and 8.**

**Slice 7 — offline historical memo (F4),** if slice 6 shows the rebuild is material.

**Slice 8 — fallback price key index (F5),** if slice 6 shows per-card commit cost growing with session length. Note this one touches undo and correction, so it needs the most test attention of anything here.

**Not scheduled:** F6 (needs slice 6's answer and is correctness-adjacent), F7 (watch for it in testing first), F8 (only if you're already in that file).

---

Want me to write this up as a shareable page, or turn any of the slices into a concrete patch?
