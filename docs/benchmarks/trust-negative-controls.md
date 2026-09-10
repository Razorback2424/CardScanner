# Trust-hardening negative controls

Recorded 2026-09-10 against pre-change commit `3c390e6`.

This matrix separates regression barriers from tests that only describe the
trust-hardening surface. The pre-change source was checked in the disposable
worktree `/private/tmp/trust-negative-controls-baseline`; the throwaway probe
methods were discarded with that worktree after recording their source below.

The complete post-change test target cannot be compiled against the old source:
the old target stops at the new test-only `ScannerCollectionWriter
setSaveOverrideForTesting` seam. Bucket 1 tests were therefore copied into the
old target and run individually. Bucket 2 properties were expressed with the
old public API and run as probes. A Bucket 1 result is only a regression barrier
when the old implementation actually fails it.

## Matrix

| Test | Bucket | Evidence against pre-change source | Follow-up |
| --- | --- | --- | --- |
| `CollectionItemKindTests.testGradedPrintRunSurvivesThePickerPersistenceRoundTrip` | 3 — specification/non-barrier | **PASS** in the old source. The test calls `CollectionStore.addGraded` directly; that API already accepted and persisted `pokemonPrintRun`. | Reclassified: it cannot observe the picker omission. The new picker initializer/call-site handoff is covered by the current view-construction surface test. |
| `CollectionQueryTests.testCollectionShownValueUsesTheSharedUSDValuationRule` | 2 — old-term probe | `CURRENCY_FAST_PATH` failed: old fast path returned `$60.00`, while the old CollectionView USD-only reduction returned `$30.00`. | Keep the new helper test as the named rule; the probe is the negative control for the invariant. |
| `JustTCGContractTests.testGradedIdentityRequiresTheSetAndFullCollectorNumberToMatch` | 1 — old source compiles | **FAIL**: wrong-set and wrong-denominator assertions both failed; old result compared only the stripped local number. | None. |
| `JustTCGContractTests.testGradedIdentityRejectsAnAmbiguousMissingCollectorNumber` | 1 — old source compiles | **FAIL**: old set-only fallback returned true for a numbered request and an unnumbered response. | None. |
| `JustTCGContractTests.testGradedIdentityProjectionNamesMatchStoredProperties` | 3 — new surface | **New surface**: `exhaustiveProjection` did not exist before this change. | No pre-change negative control exists. |
| `JustTCGContractTests.testGradedVendorProductMustMatchGameSetAndPrintRunBeforeBinding` | 3 — new surface | **New surface**: the `matches(_:variant:game:expectedSetSlug:)` product-boundary overload did not exist before this change. | No pre-change negative control exists for the combined card-plus-variant contract. |
| `JustTCGContractTests.testDifferentPokemonPrintRunsDoNotShareAGradedLookupGroup` | 1 — old source compiles | **FAIL**: both identities produced `pokemon|base set|004/102|charizard`; print run was omitted. | None. |
| `JustTCGContractTests.testDeferredBatchCheckpointNeedsADurableFinalSaveBeforeAdvancingDelta` | 2 — old-term probe | `CHECKPOINT_DURABILITY` failed: old `refresh(... checkpoint: { true })` advanced the delta cutoff even while the probe's final-save flag remained false. | The exact test uses new `finalCheckpoint`; the old-term probe pins the pre-change behavior. |
| `PortfolioReconciliationTests.testNewerSourceClockIsAcceptedEvenWhenItsReceiptIsOlderThanLocalKnowledge` | 1 — old source compiles | **FAIL**: old source kept one row at `$20.00` instead of appending the `$30.00` source-newer value. | None. |
| `PortfolioReconciliationTests.testEqualSourceClockAcceptsAChangedValueForDecisionRules` | 1 — old source compiles | **FAIL**: old source kept one row at `$20.00` instead of allowing the decision rules to see the changed `$30.00` value. | None. |
| `PortfolioReconciliationTests.testLiveComputationUsesACutoffAfterSamePassReconciliationBackfill` | 1 — old source compiles | **FAIL**: old actor result was `$0.00` with a nil holding price instead of `$42.00`; its past cutoff excluded the same-pass backfill. | None. |
| `PortfolioReconciliationTests.testLivePriceDeltasExcludeUnsupportedCurrenciesAndHandleTransitions` | 1 — old source compiles | **FAIL**: old fast path retained `$25.00` and `$5.00` EUR values instead of reverting to zero/unpriced. | None. |
| `PortfolioReconciliationTests.testFastAndAuthoritativeValuationAgreeAcrossCurrencyAndInvalidationTransitions` | 2 — old-term probe | `CURRENCY_FAST_PATH` failed on the same mixed collection: old incremental state diverged from the authoritative/CollectionView USD total, `$60.00` versus `$30.00`. | The current test additionally covers USD↔EUR and invalidation transitions through the new `CollectionValuation` surface. |
| `PortfolioReplayEngineTests.testAsyncPriceArrivalOrderCannotChangeFinalStateWhenKnowledgeTimesAreStable` | 3 — specification/non-barrier | **PASS** in the old source: replay already sorted/processed the supplied knowledge times independently of array order. | Reclassified: retain as specification coverage, but do not count it as evidence for a newly fixed defect. |
| `PricingTests.testEligibleUnitPriceIsTheSingleUSDGate` | 2 — old-term probe | `CURRENCY_FAST_PATH` failed: old `applyPriceDeltas` accepted the EUR display that the existing USD-only collection rule excluded. | The helper test is the new single-rule surface; the probe demonstrates the old divergence. |
| `UncoveredSurfaceTests.testScannerWriterRollsBackAStagedAddWhenTheFinalSaveFails` | 3 — new testability surface | **New surface**: the old source had no `setSaveOverrideForTesting` failure-injection seam, so a final-save failure could not be induced through the pre-change API. | No honest old-source negative control exists; keep this as a specification test of the new rollback seam. |
| `UncoveredSurfaceTests.testPriceFingerprintIncludesAllFreshnessWatermarks` | 1 — old source compiles | **FAIL**: changing `fetchedAt`, `lastCheckedAt`, or `lastSuccessfulCheckAt` left the old fingerprint unchanged (the same hash was reported for each assertion). | None. |
| `VariantResolverTests.testResolutionCertaintyDoesNotReuseAutomaticRevisitSemantics` | 3 — new surface | **New surface**: `certainty` did not exist before this change. | No pre-change negative control exists. |
| `VariantResolverTests.testReceiptProminenceKeepsRoutineCatalogAnswersQuiet` | 3 — new surface | **New surface**: `receiptProminence` did not exist before this change. | No pre-change negative control exists. |
| `VariantResolverTests.testProvenancePresentationStatesFinishAndEvidence` | 3 — new surface | **New surface**: `VariantProvenancePresentation` did not exist before this change. | No pre-change negative control exists. |
| `VariantResolverTests.testUncertaintyNeverHardensWhenItCrossesIntoTheScanReceipt` | 3 — new surface | **New surface**: the receipt provenance/certainty presentation path did not exist before this change. | No pre-change negative control exists. |

## Bucket 2 probe source

These are the old-API probes referred to by the matrix. They deliberately avoid
`PortfolioPriceEligibility`, `CollectionValuation.shownValue`, and
`finalCheckpoint`.

### `CURRENCY_FAST_PATH`

The probe created two owned cards: quantity two at a USD `$10.00` record and
quantity one at a EUR `€20.00` record. After authoritative recomputation it
changed the records to USD `$15.00` and EUR `€30.00`, then called the old
`PortfolioEngine.applyPriceDeltas` API. It compared the result with the
pre-change CollectionView rule:

```swift
await engine.recomputeAndWait(context: context, now: now)
// ...apply USD 15 and EUR 30 displays...
engine.applyPriceDeltas([
    PriceDelta(key: usdRecord.key, display: usdRecord.display),
    PriceDelta(key: eurRecord.key, display: eurRecord.display)
])

let legacyCollectionTotal = Money(rounding: 15)! * usdCard.quantity
XCTAssertEqual(engine.summary?.currentValue, legacyCollectionTotal)
```

Observed old-source failure: `Optional($60.00)` was not equal to
`Optional($30.00)`.

### `CHECKPOINT_DURABILITY`

The old coordinator had only `checkpoint`. The probe supplied a successful
checkpoint while explicitly keeping its durable-final-save flag false, then
asserted that the sync cutoff remained unset:

```swift
var finalSaveDidComplete = false
let report = await coordinator.refresh(
    [target(key: "priced", variant: "variant-priced", requiresFullResponse: false)],
    game: .pokemon,
    apply: { _, _, _ in true },
    checkpoint: {
        finalSaveDidComplete = false
        return true
    }
)

XCTAssertTrue(report.completedFully)
XCTAssertFalse(finalSaveDidComplete)
XCTAssertNil(syncLedger.deltaCutoff(
    game: .pokemon,
    apiVersion: JustTCGV1Client.apiVersion
))
```

Observed old-source failure: the delta cutoff was advanced despite the false
durable-save flag.

## Interpretation

Bucket 1 provides the strongest negative controls: each old-source-compatible
test failed on the old implementation. Bucket 2 proves the important
invariants without depending on newly introduced names. Bucket 3 is explicitly
specification coverage; it should not be reported later as proof that a
pre-existing defect was fixed.

The 150–300-card adversarial benchmark remains unexecuted and is tracked
separately in `trust-adversarial-benchmark.md`.
