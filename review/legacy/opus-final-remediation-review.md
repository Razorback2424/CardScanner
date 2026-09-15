# Opus Final Remediation Review

> **Legacy archive — historical/superseded snapshot, 2026-09-10.** This review evaluates the earlier Luna trust-hardening pass. Its readiness decision and test counts belong to that dated scope. Use the [current card-centering plan](../opus-card-centering-implementation-plan.md) and [centering evidence](../centering-evidence/) for active work.

Independent verification of the Luna Max remediation pass against
`review/legacy/opus-post-implementation-review.md` (RM-001 – RM-005) and
`review/legacy/opus-implementation-plan.md` (REQ-001 – REQ-016).

**Overall disposition: NOT READY.**

All five remediations are correctly implemented — I verified each against the real production path
and confirmed the three previously blocking defects are eliminated. However, the automated evidence
that underwrites the whole plan is **not reproducible**. I ran the full suite five times: two runs
failed, from two independent sources of non-determinism. One of those failures is in the flagship
REQ-005 / INV-4 test, and it failed *with the value of the original F-006 defect*. The blocker is
evidence integrity, not the remediation code.

No written remediation evidence document exists, so all conclusions below come from the code and
from validation I ran myself.

---

## Summary

| Metric | Result |
| --- | --- |
| RM VERIFIED | 4 (RM-001, RM-002, RM-004, RM-005) |
| RM VERIFIED WITH CONCERN | 1 (RM-003) |
| RM NOT SATISFIED | 0 |
| Original REQs reopened | 1 (REQ-005 — evidence integrity only, not code) |
| New defects found | 2 blocking (NF-7, NF-8), 2 minor (NF-9, NF-10) |
| Previously blocking defects eliminated | 3 of 3 (NF-1, NF-2, NF-3) |
| Full-suite determinism | **Fails** — 2 failures in 5 identical runs |
| Release simulator build | **Passes** (verified after clearing local disk pressure) |
| Remediation diff scope | Clean — 338 insertions / 34 deletions across 8 files |

---

## Validation I Performed

All runs on `iPhone 17 Pro` (`EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86`),
`-parallel-testing-enabled NO`, unmodified working tree.

| Run | Scope | Result |
| --- | --- | --- |
| 23:58 | `OpusImplementationPlanTests` only | 31 tests, **0 failures** |
| 23:59 | Full suite | 1041 tests, **1 failure** — `testREQ005NonUSDTransitionDepricesCurrentAndReplaySymmetrically` |
| 00:00 | Full suite | 1041 tests, 0 failures |
| 00:01 | Full suite | 1041 tests, 0 failures |
| 00:11 | Full suite | 1041 tests, 0 failures |
| 00:12 | Full suite | 1041 tests, **6 assertion failures in 1 test** — `testTreatmentQualifiedDisplayLabelsCoverAtLeastTwentyDualFinishFixtures` |
| ×6 | `testREQ005…` in isolation | 6/6 pass |
| — | Release simulator build | **BUILD SUCCEEDED** |

An earlier Release build failure was `ld: write() failed, errno=28 (No space left on device)` —
local disk exhaustion from accumulated derived data, **not** a code defect. After cleanup the
Release build succeeds. I have removed all derived-data directories I created.

---

## RM Adjudication

### RM-001 — Remove the crash from `underlyingPrintingID` — **VERIFIED**

`CollectedCard.underlyingPrintingID` is now `String?` and returns `nil` instead of trapping
(`CollectedCard.swift:163-172`). `CollectionCardDetailView.gradedVariantEvidence` falls back to
`card.providerID` (`:484`), which is exactly the pre-REQ-003 behavior — an unresolvable row is no
worse off than before REQ-003 rather than fatal.

Verified:
- `grep -c "preconditionFailure" TradingCardScanner/Models/CollectedCard.swift` → **0**.
- The only production caller of the property is `CollectionCardDetailView.swift:484`, correctly
  using `??`. The three other `underlyingPrintingID` hits in that file are the `gradedCollectionKey`
  *parameter label*, unrelated.
- `CollectionKeyTests` was adapted to the optional type and **strengthened**, not weakened: it now
  asserts `underlyingIDs.allSatisfy { $0 != nil }` before the prefix checks, so `compactMap` cannot
  silently skip a `nil` (`CollectionKeyTests.swift:255-263`).

The regression test is the real failure mode: `testRM001GradedCSVWithoutCatalogProviderIDCanRenderVariantOptions`
parses a graded CSV **with no `catalog_provider_id` column**, applies it through the production
`CollectionCSV.apply`, and calls `CollectionCardDetailView.gradedVariantOptions(for:)` on the
resulting row. Under the pre-remediation code this trapped. A sealed analogue covers the
`sealed:`-keyed row with neither `catalogProviderID` nor `justTCGCardID`.

Both of my completion criteria are met. **NF-1 is eliminated.**

### RM-002 — Previous-build namespaced CSV identity — **VERIFIED**

`alreadyNamespacedKey` no longer requires `catalogProviderID == nil` (`CollectionCSV.swift:1187-1197`).
The sealed-with-marketplace-IDs exception is preserved, so REQ-013's canonical sealed lineage is
untouched.

I re-ran my original transcription of the graded key derivation against the new logic:

```
original production key : graded:pokemon:sv08.5-074:g:psa-10:cert:123
A new export (collection_key present)          -> MATCH
B old export, no catalog_provider_id           -> MATCH
C PREVIOUS-BUILD export (the NF-2 defect)      -> MATCH   (was: graded:graded:pokemon:…#psa|10:cert:123)
D previous-build addGraded row with variant ID -> MATCH
```

The regression test is derived from real data rather than hand-written:
`testRM002PreviousBuildCSVWithCatalogProviderIDPreservesScannedGradedKey` builds a production
`scannedGradedRow`, exports it with the **current** exporter, then surgically removes the
`collection_key` column to reconstruct the previous-build format, imports into a fresh container,
and asserts exactly one row with the byte-identical key. That is precisely the NF-2 input shape.

The change also incidentally closes a latent sealed double-prefix case (namespaced `providerID`,
no marketplace IDs, but `catalogProviderID` present), which previously produced
`sealed:sealed:pokemon:…`. **NF-2 is eliminated; INV-5 now holds for the previously failing input.**

### RM-003 — Slab evidence versus tracker noise — **VERIFIED WITH CONCERN**

`markTrackerContinuityLost()` no longer clears the slab; it rotates `slabContinuityToken`
(`CardScanner.swift:1689-1692`). This is exactly the targeted alternative I specified:

- An already-bound slab survives ordinary tracker noise — **NF-3 eliminated**.
- Late binding is still refused, because `slabContinuityStillMatches` checks
  `stamp.presentationToken == slabContinuityToken` **first** (`:2249`) — so REQ-007's protection is
  preserved without destroying evidence.
- Positive spatial exit (`:1613`, reached only after `trackerLifecycle = .exited(proof:)`) is once
  again the only tracker-derived clear, restoring the distinction the file documents in two places.
  The comment on `markTrackerContinuityLost` was updated to state it correctly.

`receiveTrackerContinuityLossForTesting` is inside the `#if DEBUG` block (lines 2308–2417), so it
does not ship.

`testRM003FrameLevelTrackerLossPreservesBoundSlabEvidence` drives the **real production transition**
(`markTrackerContinuityLost`, the shared handler for no-observation and sub-threshold-confidence
frames) and asserts the latched subject still carries the original certification number. Under the
pre-remediation code this assertion fails. It is a genuine regression test.

**Concern (NF-9).** The mechanism RM-003 *substituted* for the removed clear — token rotation
refusing **late binding** — is untested. Both RM-003 tests call
`receiveSlabFooterPresenceForTesting` (binding the slab) **before**
`receiveTrackerContinuityLossForTesting`, so both exercise the already-bound path. The negative test
therefore proves `.identityChanged` clearing, which is pre-existing behavior, not the new token
check. `testREQ007BrokenContinuityCannotBindLabelToDifferentFooter` uses
`invalidateSpatialContinuity()`, which clears the slab outright, so it exercises a different branch.

I traced the untested branch by hand and it is correct: unbound slab → stamp `T0` → continuity loss
rotates token to `T1` → footer arrives → `activeSlabBaseIdentifier == nil` →
`slabContinuityStillMatches` returns false on the token → `clearActiveSlab(.spatialExit)` and no
binding. The risk is regression drift, not present incorrectness. Non-blocking; a test is suggested
below.

### RM-004 — Late-truth classification scope and fetch cost — **VERIFIED**

Both halves of NF-4 are addressed:

1. **Scope.** `hasLateInventoryTruth` now requires `event.occurredAt >= dayStart` in addition to
   `<= cutoff` (`PortfolioEngine.swift:920-926`), so an event must have occurred *within the day
   being revised*. The candidate set is further narrowed to days that actually changed —
   `guard !matches(existing, day, coverage: coverage), existing.publishedAt != nil`
   (`:783-796`) — which answers the requirement's "contributing events" language better than the
   original implementation did.
2. **Cost.** The unconditional full-table fetch is gone. `lateInventoryTruthDays` returns early when
   there are no candidates (so an ordinary replay that revises nothing performs **no**
   `InventoryEvent` fetch), and otherwise issues one date-bounded `#Predicate` fetch bounded by
   `earliestDay`, `latestCutoff`, and `earliestPublication` (`:875-902`). Using the *minimum*
   publication instant for the fetch and re-checking per-candidate is correct — a superset narrowed
   afterwards.

`testRM004PriceOnlyRevisionIgnoresUnrelatedLateEventFromBeforeThatDay` publishes a close, inserts an
unrelated event one hour **before** the day start with `recordedAt` after publication, republishes
with a changed value, and asserts `.recomputed`. Under the pre-remediation logic
(`occurredAt <= cutoff` only) this returned `.lateInventoryTruth` and the test fails. Exact failure
mode, correctly exercised.

Note the rule is now *stricter* than REQ-010's literal wording. That is a deliberate, defensible
narrowing: the day on which late truth landed is labeled `.lateInventoryTruth`, and downstream days
that merely recomputed are labeled `.recomputed`. The four original REQ-010 tests still pass.

### RM-005 — Reconciliation counterpart coverage — **VERIFIED**

`testREQ004ReconciliationCounterpartUsesProductionShapedCertifiedRow`
(`PortfolioReconciliationTests.swift:3911-3933`) now performs a real export → parse → apply round
trip with a production-shaped graded row and asserts `result.failedRows.isEmpty`, exactly one
imported row, the byte-identical `collectionKey`, and the preserved `quantity`. That is actual
identity/quantity coverage rather than a fixture-shape restatement.

The three shape assertions it dropped are not lost — they remain in
`CollectionItemKindTests.testREQ004ProductionShapedGradedAndSealedFixturesExposeProductionIdentityFields`
(`:232-243`), verified intact.

---

## Reopened Requirement

### REQ-005 — reopened on **evidence integrity**, not code

The implementation remains correct on inspection: `PortfolioReplay.apply` applies a non-USD
successor as `nil`, and the unconditional `state.setPrice` ensures the ending state de-prices. I did
not find a logic defect.

But its proof is unreliable. See **NF-7**. Until that is diagnosed, INV-4 — the agreement between
current valuation and replay across a currency transition, the highest-severity root cause in the
plan — is not demonstrated by repeatable evidence.

No other REQ required reopening; the remediation does not touch REQ-001–004 or REQ-006–016 behavior
beyond what is adjudicated above.

---

## New Findings

### NF-7 — The flagship REQ-005 / INV-4 test fails intermittently, in the direction of the original defect — **BLOCKING**

In the full-suite run beginning 23:59:08,
`OpusImplementationPlanTests/testREQ005NonUSDTransitionDepricesCurrentAndReplaySymmetrically`
failed:

```
XCTAssertEqual failed: ("$20.00") is not equal to ("$0.00")
```

`$20.00` is two copies × the pre-transition USD $10 — i.e. **replay retained the USD value**. The
preceding assertion, `XCTAssertNil(InventoryLedger…valuation(forPriceKey:).unitPrice)`, passed. So in
that run current valuation de-priced and replay did not: precisely the F-006 / RC-B divergence the
requirement exists to eliminate.

Reproduction data: 1 failure in 5 full-suite runs; 6/6 passes in isolation. The failing run is the
only one whose execution window crossed local midnight, and the test builds wall-clock-relative
stamps spanning 61 seconds (`firstPriceAt = Date.now + 1s`, `secondPriceAt = firstPriceAt + 60s`,
`through = secondPriceAt + 1s`) against a day-partitioned replay. That correlation is strong but I
could **not** derive a mechanism that produces exactly `$20.00` from a midnight straddle, and I could
not arrange another near-midnight execution to test it. Local disk pressure during that run
(125 MiB free) is an alternative environmental factor, but the container is
`isStoredInMemoryOnly` and the failure is a wrong computed value, not an I/O error, so I do not
consider it a likely cause.

**The mechanism is undiagnosed, and that is the problem.** Two outcomes are possible and they have
very different consequences:

- the test's clock-relative fixture is fragile (test defect, REQ-005 stands); or
- current/replay agreement has a genuine day-boundary hole (production defect, REQ-005 does not
  stand and DEV-02's pass rule is unsound).

Repository evidence cannot presently distinguish them, so REQ-005 cannot be treated as proven.

### NF-8 — `MagicTreatmentSnapshot.auditedCards` returns a non-deterministic order, breaking a committed test — **BLOCKING (evidence integrity)**

In the full-suite run beginning 00:12:21,
`MagicTreatmentTests/testTreatmentQualifiedDisplayLabelsCoverAtLeastTwentyDualFinishFixtures` failed
six assertions, e.g.:

```
XCTAssertEqual failed: ("Nonfoil · Plastic") is not equal to ("Nonfoil")
 - A foil treatment must not leak onto the nonfoil copy for 15597c74-0d47-44e3-87bb-f9174ca265c2
```

Root cause, confirmed in source:

```swift
var auditedCards: [MagicTreatmentSnapshotCard] {
    cardsBySetCode.values.flatMap { $0 }          // MagicTreatmentSnapshot.swift:154-156
}
```

`cardsBySetCode` is a `Dictionary`; `.values` iteration order varies across process launches because
Swift seeds its hashing per process. The test then takes `fixtures.prefix(20)`, so it draws a
**different 20 cards every run**. Most draws are foil-family treatments and pass. Some draws include
the five open-finish signals (`plastic`, `serialized`, `thick`, `metal`, `glossy`), whose
`requiredFinishes` is deliberately empty — they legitimately apply to a nonfoil copy. The test's
blanket assertion "a foil treatment must not leak onto the nonfoil copy" is simply wrong for that
population.

This is a **pre-existing latent defect in the committed Magic-treatment work**, not introduced by
this remediation — I flagged the `prefix(20)` order dependence as a nit in my first review and it has
now materialized. It is blocking here only because the plan's Definition of Done requires the full
regression suite to pass, and it currently does not do so reliably.

### NF-9 — RM-003's substituted late-binding refusal is untested — **Minor, non-blocking**

Described under RM-003. The branch is correct by inspection; only its test coverage is missing.

### NF-10 — Untracked `TestFixtures/TradingCards/HEIC/` — **Housekeeping**

An untracked directory of HEIC card photos appeared in the working tree. It is referenced by no test,
source file, or `project.pbxproj` entry (verified by grep). Presumably device-validation material.
It should be either committed deliberately, moved outside the repository, or added to `.gitignore`
before the change set is committed.

---

## Assessment of the Integrated Diff

Reviewed as one change set, the five remediations are coherent and do not interact badly.

- **RM-001 and RM-002 compose correctly.** RM-002 makes the importer preserve the original key for
  namespaced rows, which means fewer rows end up with an unresolvable `underlyingPrintingID`; RM-001
  makes the residual ones safe rather than fatal. Neither masks the other — RM-001's test still
  constructs a row that RM-002 cannot rescue (no `catalog_provider_id` *and* no resolvable catalog
  identity), and proves it renders safely.
- **RM-002 does not disturb REQ-013.** The sealed-with-marketplace-IDs exception is retained, so the
  normalizer's canonical rekey path is unaffected. The dedicated sealed round-trip test still passes.
- **RM-003 is self-contained** within `CardScanner` and does not touch the REQ-008 lifecycle clears,
  which remain explicit in `stop()` and `invalidateSpatialContinuity()`.
- **RM-004 is self-contained** within `PortfolioEngine.publish` and does not touch the REQ-005
  valuation path.
- **RM-005 is test-only.**

No production behavior outside the five targeted areas changed. The diff adds no new
`preconditionFailure`, no new force-unwrap on user data, and no new schema element. Scope discipline
is good.

The one cross-cutting observation is that **three of the five remediations depend on
`ProductionRowFixtures`**, which is now load-bearing for RM-001, RM-002, and RM-005. That is the
right design — it is the REQ-004 investment paying off — but it concentrates risk in one helper.

---

## Assessment of Automated Evidence

**Insufficient as it stands.**

The targeted evidence is strong: every RM regression test I examined exercises the real failure mode
rather than mirroring the implementation, and each would fail against the pre-remediation code. I
verified that claim by reading each test, not by trusting a report.

But the aggregate gate is unreliable. Two failures in five identical full-suite runs, from two
independent causes, means the suite cannot currently serve as the regression baseline the plan's
Definition of Done requires ("relevant pre-existing tests pass"; "the required full regression suite
passes"). Luna's claim that all automated validation passes is not reproducible on this machine.

No written remediation evidence document was produced, so there is also no record of what Luna
actually ran.

---

## Minimum Scoped Remediation

Only what this review established. No other work is requested.

### RM-006 — Make the REQ-005 test deterministic and close the day-boundary question

Two parts, both required.

1. Replace the wall-clock-relative fixture in
   `testREQ005NonUSDTransitionDepricesCurrentAndReplaySymmetrically` with fixed absolute instants and
   an explicit fixed `TimeZone` (not `.current`), so the observations, the epoch, and `through` cannot
   straddle a day boundary or drift with execution time.
2. **Separately**, add a test that pins the day-boundary case affirmatively: a USD observation on day
   *N* and a non-USD observation on day *N+1*, asserting that
   `InventoryLedger.valuation(forPriceKey:)` and the replay ending state still agree
   (INV-4), with the transition attributed as `pricingAdjustment` and `market == .zero`.

Part 2 is the point of the exercise. Part 1 alone would silence the symptom without establishing
whether the engine has a day-boundary hole.

- **Completion criterion.** The REQ-005 test and the new day-boundary test each pass **20
  consecutive** full-suite runs with zero failures. If the day-boundary test fails, stop and report a
  production defect in REQ-005 rather than adjusting the test.

### RM-007 — Make the Magic snapshot fixture selection deterministic and correct the assertion

1. Give `MagicTreatmentSnapshot.auditedCards` a stable order (e.g. sort by set code then card id)
   so `prefix(20)` selects the same fixtures every run.
2. Correct the assertion in `testTreatmentQualifiedDisplayLabelsCoverAtLeastTwentyDualFinishFixtures`:
   the "must not leak onto the nonfoil copy" rule applies only to treatments whose
   `requiredFinishes` is non-empty. Either filter the fixture population to foil-family treatments or
   branch the assertion on `requiredFinishes.isEmpty`.

Do **not** satisfy this by deleting the test or by shrinking the fixture count.

- **Completion criterion.** `grep -n "cardsBySetCode.values" TradingCardScannerTests/MagicTreatmentSnapshot.swift`
  shows a sorted accessor, and the test passes **20 consecutive** full-suite runs. The test must still
  assert the leak rule for at least one open-finish treatment in the correct direction (it *does*
  appear on the nonfoil copy).

### RM-008 — Test RM-003's late-binding refusal

Add a scanner test in which the slab is **unbound** (no `receiveSlabFooterPresenceForTesting`) when
`receiveTrackerContinuityLossForTesting()` is called, followed by a footer identity.

- **Completion criterion.** The emitted `ScanSubject.slab` is `nil`, and the existing
  `testRM003FrameLevelTrackerLossPreservesBoundSlabEvidence` still passes unchanged.

### RM-009 — Resolve the untracked `TestFixtures/` directory

Commit it deliberately, move it outside the repository, or add it to `.gitignore`.

- **Completion criterion.** `git status --short` shows no untracked `TestFixtures/` entry.

---

## Device Gates — Final Definitions

**DEV-01 — Slab evidence does not cross physical objects (REQ-007, REQ-008, RM-003).**
Still required and still the correct gate. Luna's revised **Sequence C** (10 normal-handling scans,
pass rule 10/10 record grade and certification) is **appropriate and now meaningful**: with NF-3
fixed, it is a genuine test of the corrected behavior rather than a recording of a known regression.
Sequences A and B are unchanged. Sequence A remains the only validation of the original F-001
smooth-swap scenario, which no automated test reaches.

**DEV-02 — Cardmarket EUR transition in the wild (REQ-005).**
Still required, but **do not run it until RM-006 is complete.** Its pass rule ("current total and
history agree; zero residual defects") is exactly the property NF-7 shows is not reliably
demonstrated. Running it first risks either a false pass or an unattributable failure.

**DEV-03 — CloudKit legacy delivery and backfill (REQ-014), plus schema deployment.**
Unchanged from my previous review, including the added requirement to confirm container schema
deployment for `PortfolioDailyClose.publishedAt`, `CollectedCard.activityBackfillVersion`, and the
`activityBackfillAnchor` ↔ `backfillAnchorCard` relationship, and that a card synced from a device on
the older schema produces no duplicate activities. The remediation did not change this surface.

**DEV-04 — External boundaries carried forward from Luna.** Unchanged.

**None can be resolved from repository or simulator evidence.** No new device-only validation became
necessary as a result of the remediation — RM-001 through RM-005 are all provable in the simulator,
and four of the five now are.

---

## Final Readiness Decision

**NOT READY.**

This is not a judgment on the remediation, which is good work. All three previously blocking defects
are genuinely eliminated, verified independently:

- the graded-card crash surface (NF-1) — the accessor no longer traps, and the regression test
  imports the exact legacy CSV shape that triggered it;
- previous-build namespaced CSV identity (NF-2) — all four export formats now round-trip
  byte-identically, proven by a test built from real exported data;
- scanner continuity loss versus positive spatial exit (NF-3) — tracker noise no longer discards
  bound slab evidence, and positive exit is once again the only tracker-derived clear.

RM-004 and RM-005 also resolve the quality concerns they targeted, with tests that exercise the real
failure modes.

What blocks readiness is that the repository's automated evidence is not reproducible. The full
suite failed in 2 of 5 identical runs. One of those failures is in the test that proves INV-4 for the
plan's highest-severity root cause, and it failed with the original defect's value. Until RM-006
establishes whether that is a fragile fixture or a real day-boundary hole in current/replay
agreement, REQ-005 is unproven — and DEV-02 exists to validate exactly that property on a device.

RM-006 through RM-009 are small and well-scoped. The scanner gates (DEV-01) could reasonably proceed
in parallel once RM-008 lands, since RM-003 is verified independently of the flaky tests.
