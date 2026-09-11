# Opus implementation evidence

Date: 2026-09-10  
Repository: `TradingCardScannerMVP_fixed_v4`  
Plan: [`opus-implementation-plan.md`](opus-implementation-plan.md)

The implementation below covers every deterministic `REQ-001` through `REQ-016`. The four
physical-device checks remain `DEVICE-PENDING`, as required by the plan. The plan file itself was
not modified.

## Validation snapshot

The pre-implementation baseline was re-established before the change:

```text
xcodebuild -project TradingCardScanner.xcodeproj -scheme TradingCardScanner \
  -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /private/tmp/TradingCardScannerMVP_opus_baseline test

TradingCardScannerTests.xctest passed
Executed 1005 tests, with 1 test skipped and 0 failures
** TEST SUCCEEDED **
```

The final focused implementation-plan and scanner suites passed after all reviewer fixes:

```text
-only-testing:TradingCardScannerTests/OpusImplementationPlanTests
-only-testing:TradingCardScannerTests/ScannerViewModelTests
Executed 52 tests, with 0 test skipped and 0 failures
** TEST SUCCEEDED **
```

The two regressions found by the first full run were fixed without weakening assertions. The
targeted recheck passed:

```text
-only-testing:TradingCardScannerTests/ImportedItemKindTests/testAppExportIdentifiersRoundTripForGradedAndSealedRows
-only-testing:TradingCardScannerTests/PortfolioReconciliationTests/testCSVRoundTripKeepsDistinctCertificatesApart
Executed 2 tests, with 0 test skipped and 0 failures
** TEST SUCCEEDED **
```

Authoritative full regression gate, with the actual `xcodebuild` exit status captured:

```text
xcodebuild -project TradingCardScanner.xcodeproj -scheme TradingCardScanner \
  -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86' \
  -derivedDataPath /private/tmp/TradingCardScannerMVP_opus_final \
  -parallel-testing-enabled NO test

Executed 1034 tests, with 1 test skipped and 0 failures
All tests passed
** TEST SUCCEEDED **
```

The executed count is the 1005-test baseline plus 25 plan tests, four new production-shaped
counterpart/meta tests, and one refreshed scanner test. The explicitly named regression suites also
passed:

```text
CardLatchTests, VariantResolverTests, MagicTreatmentTests, PricingTests,
PortfolioReconciliationTests, PortfolioHistoryEngineTests, PortfolioReplayEngineTests,
CollectionItemKindTests, CollectionKeyTests, QuoteCacheTests, BrowseFeatureTests,
CollectionQueryTests, ScannerViewModelTests

Executed 420 tests, with 1 test skipped and 0 failures
** TEST SUCCEEDED **
```

The named-suite result contains 421 total tests: 420 passed, 1 skipped, and 0 failures. The final
targeted CSV compatibility recheck also passed 2/2 with 0 failures.

Release simulator build:

```text
xcodebuild -project TradingCardScanner.xcodeproj -scheme TradingCardScanner \
  -configuration Release -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/TradingCardScannerMVP_opus_release_final build

** BUILD SUCCEEDED **
Product: /private/tmp/TradingCardScannerMVP_opus_release_final/Build/Products/Release-iphonesimulator/TradingCardScanner.app
```

## Requirement evidence table

| ID | Implementation | Tests and validation | Literal result | Status |
| --- | --- | --- | --- | --- |
| REQ-001 | Added `CollectedCard.underlyingPrintingID` with the required catalog, sealed-product, and raw fallback order. Migrated the graded variant derivation to the accessor. | `CollectionKeyTests.testREQ001UnderlyingPrintingIDUsesTheProductionSourceForEveryItemKind`; focused suite; static gate `rg -n "\\.providerID\\.split" TradingCardScanner/ \| grep -v "catalogProviderID \\?\\? " \| true`. | Raw, graded, scanned-graded, and sealed rows return the supplied printing/product ID; no result begins with `graded:` or `sealed:`. The static gate produced 0 matches. | COMPLETE |
| REQ-002 | `CollectionCSV` exports and imports `collection_key`, preserves `catalog_provider_id`, uses explicit keys when present, and recognizes already-namespaced legacy keys without double-prefixing. | `OpusImplementationPlanTests.testREQ002ProductionRowsRoundTripCollectionKeysAndQuantities`; `testREQ002OlderCSVWithoutCollectionKeyPreservesAlreadyNamespacedKeys`; `testREQ002SealedProductionRoundTripRetainsPreImplementationKey`; targeted CSV regressions; full suite. | Raw, graded, scanned-graded, and sealed production rows import into one row each with byte-identical collection keys and quantities. Old namespaced rows remain unchanged. Sealed production keys remain unchanged from before the implementation. | COMPLETE |
| REQ-003 | `CollectionCardDetailView.gradedVariantEvidence` derives the set from `underlyingPrintingID` and `gradedVariantOptions` keeps the existing finish filtering and first-edition exclusion. | `OpusImplementationPlanTests.testREQ003GradedVariantOptionsUseUnderlyingPrintingSetID`; `testREQ003GradedVariantOptionsIncludeVerifiedStampedRelease`; focused and full suites. | The reverse `sv08.5` graded row derives exactly `sv08.5` and includes `.pokeBall` and `.masterBall`; the stamped-release fixture exposes its stamped option. | COMPLETE |
| REQ-004 | Added shared `ProductionRowFixtures` helpers that call production `CollectionStore` creation methods. The sealed helper then applies the catalog metadata that the real normalization/refresh path supplies. Added production-shaped meta/counterpart tests. | `CollectionItemKindTests.testREQ004ProductionShapedGradedAndSealedFixturesExposeProductionIdentityFields`; `CollectionKeyTests.testREQ004CollectionKeyCounterpartUsesProductionShapedGradedRow`; `PortfolioReconciliationTests.testREQ004ReconciliationCounterpartUsesProductionShapedCertifiedRow`; full suite. | Graded and sealed helper rows satisfy `providerID == collectionKey`, have non-nil `catalogProviderID`, and have `catalogProviderID != collectionKey`; the required identity/reconciliation counterparts pass. Existing synthetic-shape assertions remain. No pre-existing assertion was changed under REQ-004. | COMPLETE |
| REQ-005 | Added the single `PortfolioPriceEligibility` owner in `PriceRecord.swift`; `InventoryLedger`, `PortfolioEngine`, `PortfolioReplay`, observation snapshots, and `ObservationEntry` consult it. Replay now treats a non-USD successor as unpriced. | `OpusImplementationPlanTests.testREQ005NonUSDTransitionDepricesCurrentAndReplaySymmetrically`; sanctioned `PortfolioReplayEngineTests.testCurrencyFlipDepricesThePortfolioWithoutMarketMovement`; full and named-suite gates. | Full `PriceStore.store` USD-to-EUR transition yields ledger `.unpriced`, no replay USD price, market `.zero`, pricing adjustment `-$20` for two copies, unexplained `.zero`, zero engine residual defects, and zero unpriced copies in the tested projection. The only pre-existing assertion change was the explicitly authorized REQ-005 policy reversal from carry-forward `usd(10)` to `.zero`, with the stronger current/replay cross-check. | COMPLETE |
| REQ-006 | `PriceCheckCoordinator` gates local `PriceRecord` and `ReferenceQuote` evidence through the shared usable-USD predicate while retaining the local amount/currency and refresh behavior. `ScannerViewModel.PriceCheckResult.hasUsableAmount` uses the same predicate, including refreshed quotes. | `OpusImplementationPlanTests.testREQ006NonUSDLocalPriceRecordIsCheckingButStillVisible`; `testREQ006NonUSDReferenceQuoteIsCheckingButStillVisible`; `testREQ006USDLocalEvidenceRemainsCurrent`; `ScannerViewModelTests.testREQ006RefreshedNonUSDQuoteRemainsChecking`; full suite. | Non-USD local and refreshed evidence is visible but returns `.checking`; USD local evidence remains `.current`. | COMPLETE |
| REQ-007 | Added tracker encounter/presentation continuity stamps to slab evidence. Label-first late binding requires the matching continuity stamp; broken continuity clears the evidence before subject emission. | `OpusImplementationPlanTests.testREQ007BrokenContinuityCannotBindLabelToDifferentFooter`; `testREQ007ContinuousLabelFirstBootstrapBindsOriginalSlab`; existing `CardLatchTests`; full suite. | Different-footer/invalidated continuity cannot bind the old label evidence; continuous label-first evidence binds the original slab. | COMPLETE |
| REQ-008 | `endSession`, `stop`, and `invalidateSpatialContinuity` all clear active slab state and associated continuity/hint state on the vision queue. Added deterministic vision-queue drain support for tests. | `OpusImplementationPlanTests.testREQ008EveryRecognitionDiscontinuityClearsSlabState`; existing lifecycle/fencing suites; full suite. | Each of the three fresh-state paths produces a subsequently identified subject with `slab == nil`. Ordinary pause behavior remains separate. | COMPLETE |
| REQ-009 | Exposed `PortfolioHistoryDisplay.availableHistoryDisclosure(for:)`, corrected the fallback-anchor flag, and rendered the disclosure in `PortfolioHistoryView`. | `OpusImplementationPlanTests.testREQ009AvailableHistoryAnchorIsDisclosed`; `PortfolioHistoryEngineTests`; full suite. | With only older closes, the result flags the available anchor, the first point is before `requestedStart`, and the view disclosure is non-nil and distinct from “History is being recorded.” | COMPLETE |
| REQ-010 | Added optional persisted `PortfolioDailyClose.publishedAt` and production classification in `PortfolioEngine.publish` based on `occurredAt <= cutoff` and `recordedAt > existing.publishedAt`; legacy rows with no publication instant conservatively remain `.recomputed`. | `OpusImplementationPlanTests.testREQ010LateInventoryTruthRevisionIsClassified`; `testREQ010OrdinaryRevisionRemainsRecomputed`; `testREQ010LegacyCloseWithoutPublicationInstantDoesNotGuessLateTruth`; `testREQ010PublicationTimestampPersistsAcrossContainerReopen`; full suite. | A late-recorded, pre-cutoff event produces `.lateInventoryTruth`; ordinary and legacy-without-publication revisions produce `.recomputed`; the publication timestamp survives a disk-backed container reopen. | COMPLETE |
| REQ-011 | Added `MarketRefreshApplyResult`, separate `metadataUpdated` and `pricesWritten` report counts, and controller accumulation that increments `priced`/`changedPrices` only for written prices. | `OpusImplementationPlanTests.testREQ011NullPriceBatchReportsMetadataWithoutPricedCount`; `testREQ011NonNullPriceBatchReportsPricedCountAndChange`; existing null-price artwork/identity test; full suite. | Null-price batch writes identity/artwork, leaves no price amount, reports `metadataUpdated == 1`, `pricesWritten == 0`, `priced == 0`, and `changedPrices == false`. Non-null batch reports `priced == 1` and `changedPrices == true`. | COMPLETE |
| REQ-012 | `PriceStore.recordFailure` now clears both stale capability and invalid-provider-quote diagnoses while leaving the stored amount untouched. | `OpusImplementationPlanTests.testREQ012OrdinaryFailureClearsInvalidQuoteDiagnosisWithoutChangingAmount`; full suite. | The invalid-quote diagnosis is absent after the ordinary failure and the valid USD amount remains `17`. | COMPLETE |
| REQ-013 | `CollectionCatalogNormalizer` now rekeys an enriched legacy sealed row through `CollectionStore.rekey`, reapplies metadata to a merged representative, and preserves price/observation/check-day/inventory-event lineage. Test resolver injection keeps the path deterministic. | `OpusImplementationPlanTests.testREQ013ImportedSealedRowConvergesWithBrowseAdd`; existing sealed duplicate/rekey/lineage suites; full suite. | Legacy import without marketplace IDs plus Browse add converges to exactly one row, quantity `3`, ownership index quantity `3`, total added-activity quantity `3`, and canonical price/observation/check-day/inventory-event references. | COMPLETE |
| REQ-014 | Backfill uses a stable persistent-configuration identity for the UserDefaults watermark, persisted per-row `activityBackfillVersion`, and a durable activity anchor relationship. The guard uses cheap counts for legacy activities, cards, activities, anchored activities, and uncovered markers; only an incomplete store performs full fetches and one commit, then validates actual anchor IDs before skipping a row. | `OpusImplementationPlanTests.testREQ014BackfillRunsForASecondStoreDespiteSharedDefaultsAndIsIdempotent`; `testREQ014BackfillWatermarkSurvivesPersistentContainerReopen`; existing backfill/reconciliation suites; full suite. | Context A completes; context B with zero activities still receives one `.added` activity per card with the card quantity despite shared defaults; a second B run leaves activity count unchanged; a deleted anchor is recreated with a new activity identity; the persistent store reopens with the same scoped watermark and no duplicate activity. | COMPLETE |
| REQ-015 | `BrowseCatalog` freshness now requires `age >= 0 && age < maxAge`; cached values are still returned. | `OpusImplementationPlanTests.testREQ015FutureCacheEnvelopeIsReturnedButNotFresh`; `testREQ015RecentCacheEnvelopeRemainsFresh`; existing Browse cache test; full suite. | Future-stamped envelope returns a non-nil value with `isFresh == false`; recent envelope returns a non-nil value with `isFresh == true`. | COMPLETE |
| REQ-016 | Corrected README targets to `docs/plans/documentation_audit.md`, `progress.md`, and `docs/plans/release_followups.md`. | `rg -o '\]\([^)]*\)' README.md`; `ls -l docs/plans/documentation_audit.md progress.md docs/plans/release_followups.md`. | All three README link targets exist; the path-resolution check succeeded. | COMPLETE |

### Required REQ-014 launch-cost record

The backfill guard does not re-scan every complete collection row on every launch. It executes five
cheap count queries: legacy activity rows, total cards, total activities, anchored activities, and
uncovered backfill markers. A completed store with the scoped watermark and no uncovered rows returns
before the full activity/card fetches and before `commit()`. A store requiring repair performs the
normal fetches once, marks each row, appends only missing activities, and commits once. The durable
anchor plus per-row marker makes newly delivered/synced rows discoverable after the store-level
watermark was set, and the repair path verifies that an anchor still points to an existing activity.

### Test-change record

The only pre-existing assertion changed was the sanctioned REQ-005 block in
`TradingCardScannerTests/PortfolioReplayEngineTests.swift`. It now expects a newer non-USD
observation to withdraw the old USD value as `pricingAdjustment == usd(-10)` and
`currentValue == .zero`; this is the selected product policy and is cross-checked against current
valuation by the new full-SwiftData test. No existing assertion was changed under REQ-004; the
production-shaped tests are additive counterparts, and synthetic-shape tests remain intact.

### REQ-001 / REQ-004 specification tension

REQ-001 explicitly requires that production `addSealed` remain unchanged and documents that it
does not set `catalogProviderID`; its underlying product ID is `justTCGCardID`. REQ-004 separately
requires shared graded/sealed helpers with populated catalog metadata. The helper therefore calls
the real `addSealed` method and then applies the same `ImportedCatalogMetadata` enrichment used by
the catalog-normalization path. The REQ-001 test also directly calls `addSealed` and verifies the
documented fallback to `justTCGCardID`. This preserves the production creation contract while
making the identity tests production-shaped at the catalog-enriched stage.

## Invariant reconciliation

| Invariant | Evidence | Result |
| --- | --- | --- |
| INV-1: slab evidence requires same-physical continuity | REQ-007 negative and positive continuity tests, plus the full `CardLatchTests` suite | Broken footer/encounter continuity cannot bind; continuous label-first evidence can bind. |
| INV-2: lifecycle discontinuities clear active slab | REQ-008 test covers `endSession`, `stop`, and `invalidateSpatialContinuity` independently | All three paths clear slab evidence before the next subject is emitted. |
| INV-3: one currency-policy owner | `PortfolioPriceEligibility` references in `InventoryLedger`, `PortfolioReplay`, `PortfolioEngine`, `ObservationEntry`, `PriceCheckCoordinator`, and observation projection | Current valuation, replay, and Price Check use one USD eligibility rule. |
| INV-4: current/replay agreement across currency transitions | REQ-005 full-store USD-to-EUR test and sanctioned replay test | Non-USD transition de-prices symmetrically, is pricing adjustment, has zero market movement and zero residual. |
| INV-5: CSV identity is byte-identical | Three REQ-002 round-trip tests, including old-column tolerance and sealed pre-implementation key, plus existing distinct-certificate regression | Keys and quantities survive export/import without splits or double prefixes. |
| INV-6: one underlying-printing accessor | REQ-001 production-path test and static provider-ID parse gate | `underlyingPrintingID` is the sanctioned accessor; the static gate has 0 matches. |
| INV-7: Price Check `.current` means usable USD | Two non-USD tests plus USD companion | Non-USD evidence is `.checking`; usable USD is `.current` on both relevant paths. |
| INV-8: fixtures are production-shaped | REQ-004 meta-test and both required identity/reconciliation counterparts | Graded/sealed helpers have production collection keys, catalog IDs, and distinct underlying IDs. |
| INV-9: priced counts mean written prices | REQ-011 null/non-null coordinator-controller tests | Metadata-only hits do not increment priced counts; only a written amount changes price counters. |
| INV-10: history fallback is disclosed | REQ-009 engine and view-layer assertion | Available-history anchor and interval disclosure are exposed separately from the generic too-few-points message. |

## Cross-requirement and flow rechecks

The shared-subsystem rechecks required by the plan were executed after later changes landed:

- REQ-002 was re-executed after REQ-013 through all three REQ-002 tests and the full 1,031-test
  gate; CSV identity remained intact after sealed normalization/rekey changes.
- REQ-005 was re-executed after REQ-006 and REQ-011 through the full-store transition test, the
  sanctioned replay test, and the explicit named suite; valuation and refresh reporting remained
  separate and correct.
- REQ-007 and REQ-008 were re-executed together through the negative/positive continuity tests and
  the three-path lifecycle test.
- REQ-001, REQ-002, REQ-003, and REQ-013 were re-executed together through the focused suite, the
  targeted CSV regressions, and the final full gate.

The plan's end-to-end flows were also rechecked:

- Scan → resolve → collection mutation → activity/ledger → projection: `ScannerViewModelTests`,
  `CardLatchTests`, `CollectionItemKindTests`, `CollectionKeyTests`, and the full/named gates pass.
- Refresh → observation → record → current → replay → close: REQ-005, REQ-006, REQ-011 tests,
  `PortfolioReconciliationTests`, and `PortfolioReplayEngineTests` pass.
- CSV → import → projection → portfolio: REQ-002 and REQ-013 tests plus
  `PortfolioReconciliationTests` pass.
- Browse add → ownership index → projection: REQ-013 plus `BrowseFeatureTests` and the full gate
  pass.
- Launch → backfill → epoch → first projection: REQ-014 plus existing reconciliation/history
  tests pass.

## Scope and integrity checks

- `git diff --check`: passed.
- Static provider-ID parse gate: 0 matches.
- Added-line scan for `TODO`, `FIXME`, `follow-up`, and `stub`: no output.
- README target existence check: passed.
- Release product exists outside the repository under `/private/tmp`; no derived-data or build
  artifact was added to the repository.
- Persisted-field compatibility checks: `PortfolioDailyClose.publishedAt` survives a disk-backed
  container reopen; a legacy close with `publishedAt == nil` is tested conservatively; the
  collection backfill marker, anchor relationship, and scoped store identity survive a persistent
  container reopen. Live CloudKit schema delivery remains covered by DEVICE-PENDING DEV-03/DEV-04.
- No centering/rotation implementation was changed; no FX conversion was added; Magic model and
  `VariantResolver` behavior were left unchanged; QuoteCache remains isolated; canonical key
  migration paths and non-USD `PriceRecord` storage remain intact.

## Physical-device validation — DEVICE-PENDING

These checks cannot be honestly proven by the simulator/unit-test gates. They are preserved as
`DEVICE-PENDING` and do not block any deterministic REQ.

| ID | Implementation / scope | Tests or validation | Literal result | Status |
| --- | --- | --- | --- | --- |
| DEV-01 | `CardScanner` slab continuity and lifecycle paths changed under REQ-007/008. | Exact five-repeat physical slab swap/background sequence below; not executable on the simulator gate. | No physical device run was performed; the required manual pass rule remains open. | DEVICE-PENDING |
| DEV-02 | USD-only transition policy and Cardmarket EUR path under REQ-005. | Exact live-provider/device sequence below; automated REQ-005 criterion passed independently. | No qualifying live Cardmarket device run was performed; residual/attribution observation remains open. | DEVICE-PENDING |
| DEV-03 | Container-scoped activity backfill and durable anchor under REQ-014. | Exact two-device CloudKit legacy-delivery sequence below; local persistent-container tests passed. | CloudKit sync/tombstone delivery was not exercised; device authority/epoch result remains open. | DEVICE-PENDING |
| DEV-04 | External boundaries listed in the plan and Luna validation procedures. | The carried-forward scope statement is reproduced below unchanged. | Physical OCR rates, CloudKit account switching, live schemas, signing, and performance remain external validation items. | DEVICE-PENDING |

### DEV-01 — Slab evidence does not cross physical objects (REQ-007, REQ-008)

Status: **DEVICE-PENDING**

- **Setup.** iPhone running a Debug build. Two graded slabs, *ideally of the same printing* with
  different certification numbers (the hardest case for identity-change clearing), plus one raw card
  of that printing.
- **Sequence A (binding).** Present slab 1 so its label is read before the footer is legible. Before
  any footer identity resolves, swap to slab 2 **without** letting the footer band go empty (slide
  laterally, keeping text in the band). Continue until a scan is authorized.
- **Sequence B (lifecycle).** Activate slab 1's label. Background the app (home gesture) while the
  scanner tab is visible. Return to the foreground. Present the raw card. Scan.
- **Observe.** The grade and certification number written to the collection row.
- **Pass rule.** In Sequence A, the recorded row carries either slab 2's certification or no slab
  evidence — **never** slab 1's certification on slab 2's identity. In Sequence B, the raw card's row
  carries **no** slab evidence. Repeat each sequence **5 times**; any single failure fails the gate.
- **Depends on.** REQ-007, REQ-008.

### DEV-02 — Cardmarket EUR transition in the wild (REQ-005)

Status: **DEVICE-PENDING**

- **Setup.** Device with network. A Pokémon promo card whose TCGdex entry carries a Cardmarket price
  and no TCGplayer figure (the `PriceProvider.cardmarketPrice` path).
- **Sequence.** Add the card while a USD price is available. Force a refresh once the provider
  returns only the Cardmarket figure. Open the portfolio and the history chart.
- **Observe.** Current total, history value at the same instant, the card's pricing diagnostic, and
  any residual defect surfaced.
- **Pass rule.** Current total and history agree; the change is attributed as a pricing adjustment,
  not market movement; **zero** residual defects reported.
- **Note.** If a qualifying live card cannot be located, record the gate as DEVICE-PENDING-BLOCKED
  with the search performed. REQ-005's automated criterion stands on its own.
- **Depends on.** REQ-005.

### DEV-03 — CloudKit legacy delivery and backfill (REQ-014)

Status: **DEVICE-PENDING**

- **Setup.** Two devices on one iCloud account, CloudKit-backed store.
- **Sequence.** Complete the backfill on device A. Introduce collection rows lacking activities
  (restore a pre-activity backup, or install an older build, add cards, then upgrade). Allow sync to
  device B. Launch device B.
- **Observe.** Whether device B creates the missing activities before portfolio epoch establishment.
- **Pass rule.** Every synced card has at least one `added` activity, and portfolio history is
  authoritative (no epoch warning).
- **Depends on.** REQ-014.

### DEV-04 — Carried forward unchanged from Luna

Status: **DEVICE-PENDING**

The external boundaries in `05-rejected-hypotheses-and-uncertainties.md` (physical camera/OCR rates,
CloudKit account switching, live provider schemas, release signing, performance) and the procedures
in `06-device-and-environment-validation.md` remain open and are **not** superseded by this plan.
