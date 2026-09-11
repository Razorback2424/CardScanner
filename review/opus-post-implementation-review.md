# Opus Post-Implementation Review

Independent review of the implementation executed from `review/opus-implementation-plan.md`,
against the evidence in `review/opus-implementation-evidence.md` and, authoritatively, against the
current working tree.

**Overall disposition: NOT READY.**

One user-reachable crash (NF-1) and one functional regression on the primary graded-scan path
(NF-3) were introduced by the implementation. Both are in code paths the new tests do not cover,
which is why the 1,034-test suite passes. The remaining fourteen requirements are sound, and
several are implemented better than the plan specified.

---

## Summary

| Metric | Result |
| --- | --- |
| Requirements VERIFIED | 9 |
| Requirements VERIFIED WITH CONCERN | 7 |
| Requirements NOT SATISFIED | 0 |
| New defects introduced by the implementation | 3 (NF-1 High, NF-2 Medium, NF-3 Medium-High) |
| New quality/maintenance findings | 3 (NF-4, NF-5, NF-6) |
| Target invariants holding | 8 of 10 (INV-1 partial, INV-6 violated by NF-1) |
| Scope discipline | Good — `project.pbxproj` change adds only the two new files to the **test** target |
| Device gates still correct | Yes, with one required addition to DEV-01 and DEV-03 |

The evidence report is accurate about what it measured. Its weakness is not dishonesty but
coverage: every claim I checked was true, and the two serious defects live outside what was
measured.

---

## Requirement Adjudication

### REQ-001 — Single accessor for underlying printing ID — **VERIFIED WITH CONCERN**

`CollectedCard.underlyingPrintingID` (`CollectedCard.swift:156-176`) implements the required
resolution order (`catalogProviderID` → `justTCGCardID` for sealed → `providerID` for raw), and the
static gate is genuinely satisfied:

```
$ grep -rn "\.providerID\.split" TradingCardScanner/ | grep -v "catalogProviderID ?? "
(0 matches)
```

The already-correct `BrowseView.swift:361` compensator was left intact as the plan required.

**Concern:** the failure branch is `preconditionFailure`, which traps in Release
(`SWIFT_OPTIMIZATION_LEVEL = -O`, `project.pbxproj:891`). This converts a resolvable data condition
into a crash. See **NF-1** — this is the blocking issue. The plan's wording ("treated as a failure,
not returned") was imprecise and contributed to this choice; the correct reading for a `var`
accessor is an optional return or a safe fallback, never a trap.

Note also that `CollectionCSV.swift:1218` inlines `catalogProviderID ?? providerID` rather than
using the new accessor, so INV-6 is not uniformly applied. That inlining is currently *safer* than
the accessor, so it should not be "fixed" until NF-1 is resolved.

### REQ-002 — CSV identity preservation — **VERIFIED WITH CONCERN**

The `collection_key` column is added and consumed (`explicitCollectionKey ?? key`,
`CollectionCSV.swift:1264`), the graded UUID path now uses `catalogProviderID ?? providerID`
(`:1218`), and the `alreadyNamespacedKey` guard (`:1187-1194`) handles column-less legacy files.
The sealed path was correctly left alone, as the plan's scope-precision note required, and
`testREQ002SealedProductionRoundTripRetainsPreImplementationKey` proves it.

**Concern:** one input class still reproduces the original F-010 defect. See **NF-2**.

### REQ-003 — Graded variant options — **VERIFIED**

`CollectionCardDetailView.gradedVariantEvidence` (`:483-495`) derives the set ID from
`underlyingPrintingID`, and the extraction into static functions makes it directly testable.
`testREQ003GradedVariantOptionsUseUnderlyingPrintingSetID` asserts the derived set ID is exactly
`sv08.5` and that `.pokeBall` / `.masterBall` appear. The stamped-release companion exists. The
underlying N-001 defect is genuinely fixed.

(This surface is the sole production caller of `underlyingPrintingID` and is therefore the crash
site for NF-1; that is an NF-1 defect, not a REQ-003 defect.)

### REQ-004 — Production-shaped fixtures — **VERIFIED WITH CONCERN**

`ProductionRowFixtures` builds rows through the real `CollectionStore` methods, and the meta-test
asserts `providerID == collectionKey`, `catalogProviderID != nil`, and
`catalogProviderID != collectionKey`. No pre-existing assertion was weakened — verified directly in
the diff of `CollectionKeyTests`, `CollectionItemKindTests`, and `PortfolioReconciliationTests`;
all three are pure additions.

**Concern:** the required reconciliation counterpart,
`PortfolioReconciliationTests.testREQ004ReconciliationCounterpartUsesProductionShapedCertifiedRow`
(`:3912-3917`), performs **no reconciliation**. It asserts only the fixture's field shape —
duplicating the meta-test — inside a reconciliation file. See **NF-5**.

### REQ-005 — Non-USD transition policy — **VERIFIED**

This is the strongest work in the change. `ObservationEntry.participatesInPortfolioValue` became a
computed property delegating to `PortfolioPriceEligibility` (`PortfolioClose.swift:41-48`), the
false comment about current-value carry-forward was deleted, and `PortfolioReplay.apply` now
applies a non-USD successor as `nil` rather than returning early (`PortfolioReplay.swift:469-476`).

I specifically verified the risk that attribution and ending state could disagree: there is an
unconditional `state.setPrice(new, for: instrument)` at `PortfolioReplay.swift:535`, with the
market-movement branch returning early after its own `setPrice`. The ending state de-prices
correctly.

`testREQ005NonUSDTransitionDepricesCurrentAndReplaySymmetrically` is a real full-SwiftData test: it
drives an actual `PriceStore.store` with a Cardmarket EUR `NormalizedPrice` — the exact production
trigger — asserts `InventoryLedger.valuation(forPriceKey:).unitPrice == nil`, then runs
`PortfolioReplaySnapshotBuilder.compute`. This is the cross-check the plan demanded and Luna's
handoff requested.

The sanctioned test change is exactly as authorized: `testCurrencyFlipKeepsUSDFallbackAsPortfolioEvidence`
→ `testCurrencyFlipDepricesThePortfolioWithoutMarketMovement`, with `pricingAdjustment` moving from
`.zero` to `-usd(10)` and `currentValue` from `usd(10)` to `.zero`. That is a policy reversal with
strictly stronger assertions, not a weakening.

### REQ-006 — Price Check USD gate — **VERIFIED**

`PriceCheckCoordinator.present` gates the local branch through `isUsableUSD`
(`PriceCheckCoordinator.swift:278-288`) while still returning the native amount for display, and
`isUsableUSD` now routes through `PortfolioPriceEligibility` (`:512-518`), unifying INV-3 and INV-7.
I confirmed `PriceCheckResult.shouldAutoRefresh` defaults to `true` (`ScannerViewModel.swift:426`),
so the non-USD branch still schedules its one permitted background attempt — the requirement's
constraint is met, not accidentally dropped.

The extension to the refreshed-quote path (`ScannerViewModel.swift:3178`,
`latest.quoteState = latest.hasUsableAmount ? .current : .checking`) is scope creep, but correct
and consistent with INV-7. Both the required negative and positive tests exist.

### REQ-007 — Slab binding continuity — **VERIFIED WITH CONCERN**

The `SlabContinuityStamp` mechanism (`CardScanner.swift:798-803, 2232-2256`) is a reasonable design:
a rotating `slabContinuityToken` plus tracker encounter/presentation identity, checked before late
binding (`:2123-2127`).

**Concern 1 — the test does not exercise the original defect.**
`testREQ007BrokenContinuityCannotBindLabelToDifferentFooter` (`OpusImplementationPlanTests.swift:1132`)
breaks continuity by calling `scanner.invalidateSpatialContinuity()` — a *lifecycle* path, which is
REQ-008's subject. F-001's actual scenario is a smooth physical swap with footer text continuously
present and **no** explicit invalidation. In that case `slabContinuityStillMatches` falls through to
`guard let stampedEncounter = stamp.trackerEncounterID else { return true }` (`:2249`) — and
label-first bootstrap typically stamps *before* any tracker exists, so the encounter is `nil` and
the guard passes on the token alone. Protection then depends entirely on the tracker detecting
loss. This is defensible given the architecture, but INV-1 is satisfied as
"no discontinuity was detected" rather than "positive same-object proof." DEV-01 Sequence A remains
the real gate and is now more important, not less.

**Concern 2:** see **NF-3** — the mechanism chosen to cover the no-tracker case has a significant
side effect.

### REQ-008 — Lifecycle clearing — **VERIFIED WITH CONCERN**

The three required paths are correct and directly verified: `stop()` (`CardScanner.swift:1022-1026`),
`invalidateSpatialContinuity()` (`:1180-1184`), and `endSession()` via the pre-existing
`resetObservationState`. `drainVisionQueueForTesting` is correctly `#if DEBUG` (`:2306-2311`) and
does not ship. `testREQ008EveryRecognitionDiscontinuityClearsSlabState` covers all three from fresh
state, as required.

**Concern:** the implementation additionally placed `clearActiveSlab(cause: .spatialExit)` inside
`markTrackerContinuityLost()` (`:1687-1689`), which is beyond what REQ-008 required and introduces
**NF-3**.

### REQ-009 — History fallback disclosure — **VERIFIED**

`PortfolioHistoryDisplay.availableHistoryDisclosure` (`PortfolioHistoryTypes.swift:402-412`) and the
view rendering (`PortfolioHistoryView.swift:23-28`) satisfy the requirement, and the disclosure is
correctly distinct from "History is being recorded."

Notably the implementer found and fixed a real inversion the plan and Luna both missed:
`trackingBeganDate` was previously set when `requestedStart < anchor.date` — i.e. in the *normal*
case, never in the fallback case. It is now `anchor.date < requestedStart`
(`PortfolioHistoryEngine.swift:138`). My plan's assumption that "`trackingBeganDate` records the
fallback" was wrong, inherited from Luna F-004; the implementer corrected it rather than building on
it. I verified there are no other consumers of `trackingBeganDate`, so the semantic flip breaks
nothing: the only readers are the new disclosure function and one test fixture passing `nil`.

### REQ-010 — Late inventory truth — **VERIFIED WITH CONCERN**

`PortfolioDailyClose.publishedAt` is optional with a conservative `nil` path for migrated rows
(`PortfolioDailyClose.swift:76`, `PortfolioEngine.swift:857-861`), and all four tests exist
including a disk-backed container-reopen check. `.lateInventoryTruth` is now reachable in
production.

**Concern:** see **NF-4** — the classification is over-broad relative to the requirement's wording
("examines **contributing** `InventoryEvent`s"), and the implementation adds an unconditional
full-table `InventoryEvent` fetch to every `publish()`.

### REQ-011 — Priced counts — **VERIFIED**

`MarketRefreshApplyResult` with separate `metadataApplied`/`priceWritten`
(`JustTCGRefreshCoordinator.swift:87-104`), separate `metadataUpdated`/`pricesWritten` report
counters (`:114-118`), and `changedPrices = changedPrices || fallbackResult.changedPrices`
(`PriceRefreshController.swift:521`) correctly separate the two outcomes. Metadata backfill is
preserved, and the pre-existing null-price artwork test still passes. Both the null and non-null
companion tests exist. Minor API note in **NF-6**.

### REQ-012 — Invalid-quote diagnosis clearing — **VERIFIED**

`PriceStore.recordFailure` now clears `.invalidProviderQuote` alongside `.noSupportedProvider`
(`PriceStore.swift:922-924`). Minimal, correct, and the companion assertion that the stored amount
is unchanged is present.

### REQ-013 — Sealed convergence — **VERIFIED**

The normalizer rekeys through the existing `CollectionStore.rekey` (`CollectionStore.swift:1105`),
reusing the established lineage/merge machinery rather than inventing a parallel path, and rolls
back on failure (`CollectionCatalogNormalizer.swift:181-208`). I specifically checked for use of a
potentially-deleted model object after a merge: the post-rekey code uses only `normalizedRow` and
previously captured locals (`previousVariantID`, `previousPriceKey`), never `row`. The
`JustTCGV1Client` injection is a reasonable test seam.

### REQ-014 — Backfill precondition — **VERIFIED WITH CONCERN**

The container-scoped watermark (`CollectionStore.swift:406-425`) correctly distinguishes the
local-only and CloudKit configurations, which is the F-012 scenario. The guard now requires five
conditions, and the per-row `activityBackfillVersion` defaulting to `0` guarantees one repair pass
for every existing store.

**Concerns:**
1. **Disproportionate mechanism.** The plan said "A cheap check is acceptable (e.g. compare
   `fetchCount` of cards against the count of distinct activity collection keys)." The
   implementation added a persisted `Int` on `CollectedCard` **and** a new one-to-one SwiftData
   `@Relationship` between `CollectedCard` and `CollectionActivity`
   (`CollectedCard.swift:94-99`, `CollectionActivity.swift:126-129`). Two shipping CloudKit-backed
   models now carry migration bookkeeping. The per-row version marker alone would have satisfied the
   requirement; the relationship's stated benefit (tombstone-driven rediscovery) is real but does
   not obviously justify a permanent schema element.
2. **Non-convergence edge.** Because the relationship is one-to-one, two `CollectedCard` rows
   sharing a `collectionKey` would both resolve `activitiesByKey[key]?.first` to the same activity
   and repeatedly steal the anchor from each other, leaving `hasUncoveredCards == true` forever and
   running the full fetch + `commit()` on **every** launch. Duplicate exact keys are supposed to be
   merged, so this is narrow, but the merge path exists precisely because the state occurs.
3. The in-memory branch keys on `ObjectIdentifier(container).hashValue`, so two in-memory containers
   *always* get distinct watermarks. `testREQ014BackfillRunsForASecondStoreDespiteSharedDefaults...`
   therefore passes somewhat by construction; the disk-backed reopen test carries the real weight.

None of these is a correctness defect in the F-012 scenario, which is genuinely fixed.

### REQ-015 — Cache future skew — **VERIFIED**

`age >= 0 && age < maxAge` (`BrowseCatalog.swift:907-910`), value still returned, both companion
tests present, `BrowseCatalogStore.markRefreshSucceeded` untouched.

### REQ-016 — README links — **VERIFIED**

All three targets resolve. Independently confirmed by path existence.

---

## Independent Finding Search

### NF-1 — `underlyingPrintingID` crashes the app on CSV-imported graded rows — **High — BLOCKING**

`CollectedCard.underlyingPrintingID` (`CollectedCard.swift:156-176`) ends in `preconditionFailure`
when no candidate resolves. For a row with `itemKind == .gradedCard` and
`catalogProviderID == nil`, the candidate chain yields `nil`:

```swift
let candidate = catalogProviderID                                  // nil
    ?? (itemKind == .sealedProduct ? justTCGCardID : nil)          // nil (graded)
    ?? (itemKind == .rawCard ? providerID : nil)                   // nil (graded)
guard let candidate, ... else { preconditionFailure(...) }
```

**Such rows are created by supported production input.** `CollectionCSV.apply` assigns
`card.catalogProviderID = entry.catalogProviderID` (`CollectionCSV.swift:814`), which is `nil` for
any CSV lacking a `catalog_provider_id` value — older exports, hand-authored files, and
third-party files, all explicitly supported import boundaries. No path backfills it for graded rows.

**Reachability chain:**
1. Import such a CSV → graded row with `catalogProviderID == nil`.
2. `CollectionCSV.apply` appends an activity (`:868`); REQ-014's backfill would also create one.
3. Opening that card's detail view evaluates `gradedVariantCorrectionBlock`
   (`CollectionCardDetailView.swift:434-447`), gated on `latestGradedAcquisition`, which is now
   non-nil.
4. `gradedVariantOptions` → `gradedVariantEvidence` → `card.underlyingPrintingID` → **trap**.

`preconditionFailure` traps in Release (`SWIFT_OPTIMIZATION_LEVEL = -O`), so this is a shipping
crash, not a debug assertion.

The plan's own REQ-002 test constructs exactly this row shape —
`testREQ002OlderCSVWithoutCollectionKeyPreservesAlreadyNamespacedKeys`
(`OpusImplementationPlanTests.swift:43-56`) imports a graded row with no `catalog_provider_id` — but
stops at `parse` and never reads the accessor. Every test that does call
`gradedVariantOptions` uses `ProductionRowFixtures`, whose rows always have `catalogProviderID`
populated. That is why 1,034 tests pass.

This is strictly worse than the N-001 defect it was introduced to fix: N-001 silently omitted menu
options; NF-1 terminates the process.

### NF-2 — The previous build's own export still mangles scanned-graded keys — **Medium**

`alreadyNamespacedKey` requires `catalogProviderID == nil` (`CollectionCSV.swift:1187`), and the
graded no-UUID branch still derives from `baseKey`, which comes from `providerID`
(`:1223-1236`). But `catalog_provider_id` was **already present** in the pre-implementation export
header, while `collection_key` was not. A camera-scanned slab (`addScannedGraded`) has no
`justTCGVariantID`. So a backup taken with the immediately-preceding build hits neither guard.

Traced against the current code:

```
original production key : graded:pokemon:sv08.5-074:g:psa-10:cert:123
A) new export (collection_key present)        -> identical            PASS
B) old export, no catalog_provider_id (tested) -> identical            PASS
C) previous-build export: catalog_provider_id
   present, no collection_key, no variant UUID -> graded:graded:pokemon:sv08.5-074:g:psa-10:cert:123#psa|10:cert:123
                                                                       FAIL
```

Case C is untested; the only "older CSV" test omits `catalog_provider_id` entirely. INV-5 therefore
does not hold for the most likely real-world legacy backup. The remedy is small — let the
namespace-prefix detection apply regardless of `catalogProviderID`, or use
`catalogProviderID ?? providerID` in the no-UUID branch as the UUID branch already does.

### NF-3 — Routine tracker noise now discards confirmed slab evidence — **Medium-High**

`markTrackerContinuityLost()` now clears the active slab (`CardScanner.swift:1687-1689`). That
function is not a discontinuity boundary — it is called on ordinary frame-level tracking outcomes:

| Site | Trigger |
| --- | --- |
| `CardScanner.swift:1576` | tracking request returned **no observation** for one frame |
| `:1582` | `observation.confidence < minimumConfidence` — one **low-confidence** frame |
| `:1555`, `:1634` | Vision `perform` **threw** |
| `:1213` | `keepPresentationSuppressed` — suppressed duplicate candidate |
| `:1241` | `restoreAcceptedPresentation` |
| `:1372` | lens switch |

A graded slab is a glossy, reflective holder; single low-confidence or missing tracker observations
are expected during normal handling. Each one now destroys confirmed slab evidence and rotates
`slabContinuityToken`, forcing the label through `slabEvidenceWindow` (2 matches in 4 frames) again.
Under intermittent tracking the slab may never bind, and the scan silently degrades to a raw-card
record — **the grade and certification number are simply not written**.

This directly violates REQ-007's stated constraint, *"Must not make a genuine slab unscannable,"*
and contradicts two documented invariants in the file it modifies:

- `invalidateSpatialContinuity`'s own comment (`:1177-1179`): *"Recognition invalidation is allowed
  to clear OCR evidence, but it must not turn an active tracker into an exit proof."*
- The pre-existing slab clear at `:1613`, reached only after `trackerLifecycle = .exited(proof:)`,
  documented as *"A slab label is presentation state… **Positive spatial exit is the authoritative
  boundary**."*

The new call sets `trackerLifecycle = .continuityLost` and then clears with cause `.spatialExit`,
conflating the two states the file deliberately separates and polluting the
`slabClearSpatialExit` diagnostic counter.

REQ-008 does not require this change — `stop()` and `invalidateSpatialContinuity()` each clear
directly. It appears to have been added to cover REQ-007's no-tracker stamp case. A targeted
alternative exists: rotate `slabContinuityToken` on continuity loss **without** clearing confirmed
evidence. Late binding would then be correctly refused, while an already-bound slab keeps working.

No test covers this: the REQ-007/008 tests drive explicit lifecycle calls, never frame-level
tracker outcomes.

### NF-4 — Late-truth classification is over-broad and adds a full-table fetch per publish — **Low-Medium**

`PortfolioEngine.hasLateInventoryTruth` (`:851-864`) scans **all** `InventoryEvent` rows:

```swift
inventoryEvents.contains { $0.occurredAt <= cutoff && $0.recordedAt > publishedAt }
```

The requirement said "examines **contributing** `InventoryEvent`s." As written, one late-recorded
historical event marks **every** republished day at or after its `occurredAt` as
`.lateInventoryTruth`, including days republished for an unrelated reason such as a price
recomputation. The user is then told "reconciled after another device synced" for a change that was
not a reconciliation — the same class of mislabeling F-005 existed to remove, in the opposite
direction. The effect decays because `publishedAt` advances on each revision, which limits the
severity.

Separately, `let inventoryEvents = (try? context.fetch(FetchDescriptor<InventoryEvent>())) ?? []`
(`:783`) is **unconditional** — it runs on every `publish()` even when no close is being revised —
and the per-day check is a linear scan, making the pass O(days × events). The plan required a
launch-cost record for REQ-014 but not here; it should be measured or bounded (filter by
`recordedAt > publishedAt` in the predicate, or fetch only when at least one `existing` close is
present).

### NF-5 — The REQ-004 reconciliation counterpart exercises no reconciliation — **Low**

`testREQ004ReconciliationCounterpartUsesProductionShapedCertifiedRow`
(`PortfolioReconciliationTests.swift:3912-3917`) asserts only `providerID == collectionKey`,
`catalogProviderID != nil`, and `catalogProviderID != collectionKey`. It runs no reconciliation,
no CSV round trip, and no ledger comparison — it duplicates the REQ-004 meta-test in a different
file. The plan's intent was that reconciliation *behavior* be exercised against a production-shaped
row, since N-002 established that the synthetic shape is what hid F-010. As written this satisfies
the wording of the completion criterion without delivering the coverage it was meant to create.

### NF-6 — `JustTCGRefreshCoordinator.refresh` has a silently-failing default — **Low**

`apply:` now defaults to `{ _, _, _ in false }` (`JustTCGRefreshCoordinator.swift:204`). A caller
that supplies neither `apply` nor `applyDetailed` compiles cleanly and marks every response
`batchPersistenceFailed = true`. All current production callers pass one, so this is a latent API
footgun rather than a live defect; making the two parameters mutually exclusive at the type level
would remove it.

---

## Target Invariant Reconciliation

| Invariant | Holds? | Evidence |
| --- | --- | --- |
| INV-1 slab binding | **Partial** | Mechanism sound; satisfied as "no detected discontinuity," not positive same-object proof. The automated test exercises the lifecycle path, not the smooth-swap case. DEV-01 remains the gate. |
| INV-2 slab lifetime | Yes | All three teardown paths clear. Over-applied — see NF-3. |
| INV-3 one currency-policy owner | Yes | `PortfolioPriceEligibility` consulted by `InventoryLedger`, `PortfolioReplay`, `PortfolioEngine.observationEntry`, `PriceCheckCoordinator`, `PriceCheckResult`. |
| INV-4 current/replay agreement | Yes | Verified in code (unconditional `setPrice` at `PortfolioReplay.swift:535`) and by the full-SwiftData REQ-005 test. |
| INV-5 CSV identity byte-identical | **No** | Holds for new exports and column-less legacy files; fails for previous-build exports of scanned-graded rows (NF-2). |
| INV-6 one underlying-printing accessor | **No** | The accessor exists but traps (NF-1); `CollectionCSV.swift:1218` still inlines the resolution. |
| INV-7 `.current` means usable USD | Yes | Both `present` and the refreshed-quote path gate through the shared predicate. |
| INV-8 fixtures production-shaped | Yes | `ProductionRowFixtures` uses real `CollectionStore` methods; no existing assertion weakened. |
| INV-9 priced means written | Yes | Separate counters; `changedPrices` driven by writes. |
| INV-10 history fallback disclosed | Yes | Plus a genuine inversion fix in the engine. |

---

## Adequacy of the Automated Evidence

The evidence report's measurements are accurate — every claim I spot-checked held. Its limitation is
that the new tests validate the *mechanisms* the implementer built rather than the *input space* the
requirements targeted:

- REQ-002's legacy coverage tests a CSV shape that never shipped, while the shape that did ship
  (NF-2) is untested.
- REQ-007's negative test breaks continuity through an API call, not through the frame-level path
  where F-001 and NF-3 both live.
- REQ-001's accessor is only ever exercised with rows that cannot reach its failure branch.

The full-suite, named-suite, and Release-build gates are legitimate and were clearly run. No test was
weakened; the one sanctioned change is a genuine policy reversal with stronger assertions.

---

## Device Gates

**DEV-01 — still required, and now broader.** REQ-007's automated test does not cover the smooth
physical swap, so Sequence A remains the only validation of the original F-001 scenario. **Add a
Sequence C** to detect NF-3: present a single graded slab under normal handling (including moderate
glare and hand movement) and scan it 10 times; the pass rule is that the grade and certification
number are recorded on **10 of 10** attempts. NF-3 should be fixed before this runs, or Sequence C
will simply document the regression.

**DEV-02 — unchanged and still correct.** REQ-005's automated criterion is strong enough that DEV-02
is confirmation rather than proof.

**DEV-03 — still required, and now larger.** REQ-010 and REQ-014 added three persisted elements to
CloudKit-backed models: `PortfolioDailyClose.publishedAt`, `CollectedCard.activityBackfillVersion`,
and the `CollectedCard.activityBackfillAnchor` ↔ `CollectionActivity.backfillAnchorCard`
relationship. All are optional or defaulted, which is CloudKit-compatible, but **schema deployment
and cross-device relationship delivery are unverified**. Add: confirm the container schema updates
without error, and that a card synced from a device on the older schema is handled without duplicate
activities.

**DEV-04 — unchanged.**

**None can be resolved without a device.** No new device gate became necessary beyond the two
additions above.

---

## Required Remediation

Scoped strictly to what this review established. No other change is requested.

### RM-001 — Remove the crash from `underlyingPrintingID` (blocks readiness)

Replace the `preconditionFailure` with a non-trapping contract. Recommended: make the accessor
optional (`var underlyingPrintingID: String?`) and have `CollectionCardDetailView.gradedVariantEvidence`
fall back to today's pre-implementation behavior when it is `nil` — the graded menu is then
no worse than before REQ-003 for rows that cannot resolve, rather than fatal. Do **not** satisfy
this by making the CSV importer always populate `catalogProviderID`; that narrows one entry point
while leaving the trap for every future caller.

- **Completion criterion.** A test imports a graded CSV row with **no** `catalog_provider_id`
  column, then calls `CollectionCardDetailView.gradedVariantOptions(for:)` on the resulting row and
  asserts it returns without trapping. A second test asserts the sealed analogue (a
  `sealed:`-keyed row with neither `catalogProviderID` nor `justTCGCardID`) also returns without
  trapping. `grep -rn "preconditionFailure" TradingCardScanner/Models/CollectedCard.swift` returns
  0 matches.

### RM-002 — Close the NF-2 CSV gap

Make graded key reconstruction correct when `catalog_provider_id` is present but `collection_key`
is absent. Either drop the `catalogProviderID == nil` condition from `alreadyNamespacedKey`
(`CollectionCSV.swift:1187`) or use `catalogProviderID ?? providerID` in the no-UUID graded branch
(`:1226`), matching the UUID branch.

- **Completion criterion.** A test builds a CSV containing the **pre-implementation** header set
  (with `catalog_provider_id`, without `collection_key`) for a row created by
  `CollectionStore.addScannedGraded`, imports it into a fresh context, and asserts the resulting
  `collectionKey` is byte-identical to the original and that exactly one row exists.

### RM-003 — Stop discarding slab evidence on routine tracker loss

Remove the `clearActiveSlab(cause: .spatialExit)` call from `markTrackerContinuityLost()`
(`CardScanner.swift:1687-1689`). To retain REQ-007's protection for the no-tracker stamp case,
rotate `slabContinuityToken` on continuity loss **without** clearing confirmed evidence, so late
binding is refused while an already-bound slab continues to work. Positive spatial exit
(`:1613`) must remain the only tracker-derived clear.

- **Completion criterion.** A test activates slab evidence, drives a frame-level tracker
  continuity loss (no observation and/or sub-threshold confidence), and asserts the active slab
  evidence **survives** and a subsequently identified same-identity subject still carries the
  original grade and certification number. A companion test asserts that after the same continuity
  loss, a **different** footer identity does **not** receive the stale evidence. Both required, and
  `REQ-008`'s three-path test must still pass unchanged.

### RM-004 — Bound the REQ-010 classification and its fetch

Restrict `hasLateInventoryTruth` to events that could have contributed to the day being revised,
and avoid the unconditional full-table fetch when no close is being revised.

- **Completion criterion.** A test asserts that a close republished for a **price-only** change,
  in a store that also contains an unrelated late-recorded event predating that day, is classified
  `.recomputed` and **not** `.lateInventoryTruth`. The existing four REQ-010 tests must still pass.
  Record the fetch strategy and its cost, as REQ-014 required for its guard.

### RM-005 — Give the REQ-004 reconciliation counterpart real coverage

Replace the shape-only assertion at `PortfolioReconciliationTests.swift:3912` with a test that
performs an actual reconciliation or CSV round trip using the production-shaped graded row and
asserts identity and quantity survive.

- **Completion criterion.** The test exercises a reconciliation or export/import path and asserts
  on its outcome, not on fixture fields.

**Not required, recorded only:** NF-6 (the `apply:` default), the REQ-014 anchor-steal
non-convergence edge, and the REQ-014 schema-weight concern. None is a correctness defect; the
schema element is now shipped and reverting it would cost another migration.

---

## Final Judgment

**NOT READY.**

Fourteen of sixteen requirements are correctly implemented, and REQ-005, REQ-009, and REQ-013 are
better than the plan specified — REQ-005 delivers exactly the full-SwiftData cross-check the root
cause demanded, and REQ-009 corrects an inverted condition that both Luna and the plan had wrong.
Scope discipline was good and no test was weakened.

But the implementation introduced a Release-mode crash reachable by importing a CSV backup and
opening a card (NF-1), and a regression that can silently drop grade and certification data on the
primary graded-scan path (NF-3). Both sit in exactly the blind spots the new tests do not reach, so
the passing suite is not evidence against them. NF-2 leaves the original F-010 defect alive for the
most likely real-world legacy backup.

RM-001 and RM-003 must be corrected before device validation: DEV-01 cannot meaningfully evaluate
slab binding while NF-3 is present, and NF-1 is a shipping crash. RM-002, RM-004, and RM-005 should
accompany them.
