# Production Defect Audit — Pass 1

Audit performed September 9–10, 2026. Scope: the existing `TradingCardScanner` scheme and repository state. No application code, tests, schemas, or configuration were changed. This report is the only repository addition.

## Result and evidence standard

Nine findings: **eight confirmed and one suspected**. Six isolated simulator probes reproduced defective intermediate results; two additional findings are deterministic source traces. The scanner failure-recovery finding remains suspected because a real SwiftData save failure was not injected. A passing baseline does not disprove these findings: the temporary probes deliberately assert the observed defective result, whereas the proposed regression tests below must assert the corrected invariant.

High severity means materially incorrect persistent identity/value or potentially lost pricing updates. Medium means incorrect presentation or recoverable metadata loss. Confidence is separate from severity. “Confirmed” does not imply that a physical device, real provider, or CloudKit account was exercised.

The audit used repository-wide inventory/hazard screening and selected deep end-to-end traces. It is **not a claim that every one of the 61,686 production Swift lines received equal manual scrutiny**. Coverage and remaining limitations are recorded below. Existing release/audit claims were treated as hypotheses, not evidence.

## Prioritized findings

| ID | Severity | Confidence | Classification | Defect |
|---|---|---|---|---|
| D01 | High | High | Confirmed; reproduced | Newer source price rejected after delayed delivery |
| D02 | High | High | Confirmed; predicate reproduced, downstream path traced | Graded identity accepts another set with the same local number |
| D03 | High | High | Confirmed; grouping reproduced, downstream path traced | Graded refresh merges different Pokémon print runs |
| D04 | High | High | Confirmed; static | Delta checkpoint can advance before prices are durable |
| D05 | Medium | High | Confirmed; reproduced | Reconciliation creates evidence after its own live replay cutoff |
| D06 | Medium | High | Confirmed; reproduced | Live portfolio deltas count EUR amounts as USD |
| D07 | Medium | High | Confirmed; reproduced | Freshness-only price changes do not change store revision |
| D08 | Medium | High | Confirmed; static | Graded browse confirmation drops selected print run |
| D09 | High | Medium | Suspected; concrete failure path | Failed scanner save can leave an unsaved add in its reusable context |

D09 is last despite its potential impact because failure recovery has not been dynamically demonstrated.

## D01 — Newer source prices rejected after delayed delivery

**Location:** `TradingCardScanner/Services/PriceObservationLog.swift:687`, `isOutOfOrder(record:comparedTo:)`; callers at lines 530 and 556 in reconciliation. Valuation consumers: `Services/PortfolioReplaySnapshot.swift:402`, `valuationIndex`, and `InventoryLedger` observation resolution.

**Mechanism and trigger:** The guard compares a remote record's maximum fetched/check timestamp against the previous observation's *local received timestamp*. Both branches return `remoteKnowledge <= previous.receivedAt`; a newer source timestamp does not rescue the record. Suppose price 10 has source stamp 100 but arrives locally at 300. Price 20 has source stamp 200 and fetch stamp 210 and arrives afterward. Reconciliation rejects 20 because 210 <= 300. This is valid delayed delivery, not an older source update.

**Result / guards:** The mutable PriceRecord can show 20 while the observation-backed portfolio remains at 10. The out-of-order guard itself causes the loss; subsequent reconciliation continues to see the same rejected record. Comparing clocks from different stages does not establish source ordering.

**Evidence:** Simulator probe `testAuditDelayedNewerSourceStampIsDropped` inserted exactly these records, reconciled at 400, and observed one observation still worth 10 while PriceRecord was 20. No real CloudKit traffic was needed to reproduce the resolver behavior.

**Fix / verification:** Order comparable source-stamped values by their source evidence; use local reception time for local knowledge without treating it as a remote watermark. Define tie/unstamped/invalidation rules explicitly. Regression: deliver two increasing source stamps whose remote fetch times both predate the first local receipt; expect the second price and portfolio value. Include genuinely older and invalidation cases.

**Existing coverage / missing evidence:** `PortfolioReconciliationTests.testSyncedPriceRecordChangeBecomesLocalKnowledgeAtReconciliationTime` places receipt and fetch in a favorable order; its out-of-order counterpart covers an actually old record. Real CloudKit delivery frequency remains unmeasured; the deterministic rejection is confirmed.

## D02 — Wrong graded product accepted by matching only the local number

**Location:** `Services/JustTCGV2GradedClient.swift:71`, `GradedCardIdentity.matches`; lookup filtering around line 267 and optional set resolution around line 235. Consumer: `Services/ScannedGradedResolver.swift:109`, `matchingVariant`.

**Mechanism and trigger:** After matching the name, the predicate immediately returns the comparison of normalized local collector numbers when both exist. It never verifies the set in this branch and removes denominator distinctions. Requested Charizard, Base Set, 4/102 therefore accepts returned Charizard, Base Set 2, 4/130. When set-directory resolution is unavailable, the request is allowed to omit the set, so broader results can reach this predicate.

**Result / guards:** A sole matching grader/grade variant can be bound to the requested collection identity even though its provider product belongs to another set. The persisted vendor handle and value can then represent the wrong card. Grade/qualifier checks do not repair an incorrect underlying product match.

**Evidence:** `testAuditGradedIdentityAcceptsWrongSetWithSameLocalNumber` decoded a local provider fixture and reproduced `matches == true`. The downstream auto-binding path was statically traced; no provider call was made.

**Fix / verification:** Require compatible set identity independently of a local number; preserve meaningful denominator evidence and reject ambiguous underlying products. Regression: same name/number across two sets, missing directory resolution, and equal grades must not auto-bind the wrong product.

**Existing coverage / missing evidence:** `JustTCGContractTests` tests accepting the intended card, rejecting a card with different identity fields, and omitting unresolved sets. Those do not prove rejection of a same-name/local-number collision. Live occurrence rates are unknown; acceptance of the wrong fixture is confirmed.

## D03 — Graded refresh batches different print runs together

**Location:** `Services/JustTCGV2GradedClient.swift:65`, `GradedCardIdentity.groupingKey`; `Services/PriceRefreshController.swift:1028`, `refreshGraded` grouping, representative lookup around 1170 and per-target application around 1198. Edition-specific request construction: `JustTCGV2GradedClient.swift:203`.

**Mechanism and trigger:** The grouping key includes game, set name, collector number, and name but omits `pokemonPrintRun`. Two unbound slabs of the same card and grade, one first edition and one unlimited, enter one group. The first target determines the edition-specific lookup; its returned variants are then considered for both targets.

**Result / guards:** One slab can receive the other edition's price and persistent market variant binding. Per-target grade matching cannot distinguish print runs already discarded by grouping.

**Evidence:** `testAuditGradedRefreshGroupsDifferentPrintRuns` reproduced equal grouping keys for otherwise identical first-edition and unlimited identities. Edition request selection and reuse of the representative response were traced in production code.

**Fix / verification:** Group by every underlying-product discriminator that affects the request, including print run; independently validate returned product identity before binding. Regression: two same-grade slabs of different print runs must issue appropriately distinct lookups and retain distinct correct bindings regardless of input order.

**Existing coverage / missing evidence:** Existing grouping contracts cover shared underlying cards across graders, while edition tests exercise request construction individually. They do not cover mixed-edition aggregation. No live vendor payload or persisted mixed-edition UI session was exercised.

## D04 — Delta watermark advances before durable persistence

**Location:** `Services/PriceRefreshController.swift:638`, `checkpointActiveContextIfDue`, especially line 656; production callback at 874; final forced checkpoint at 977. `Services/JustTCGRefreshCoordinator.swift:284` checkpoint acceptance and line 309 `recordCompleteSync`.

**Mechanism and trigger:** The coordinator treats a successful checkpoint callback as durable batch persistence. The production callback returns true when saving is *not due*. A small fast batch below 500 staged writes and the 10-second budget can therefore advance the UserDefaults sync watermark before the final context save. A process interruption in this window, or failure of that final save, loses the staged update while retaining the newer delta cutoff.

**Result / guards:** A previously priced card retains its old price. Its next delta query can omit the lost update because the provider change predates the advanced cutoff. `requiresFullResponse` at controller line 848 protects unpriced/artwork-needing rows, not an already-priced row with an old persisted value. The coordinator's failure guard only works when the callback actually attempts and reports a save.

**Evidence:** Deterministic production callback/control-flow trace. Neither a kill at the vulnerable instruction nor a disk failure was injected. This finding concerns the ordering contract, not a claim of observed storage failure.

**Fix / verification:** Distinguish “deferred” from “durably saved”; advance the watermark only after all covered writes commit. Persist enough checkpoint state to recover interrupted operations. Regression: run the actual production callback with a subthreshold batch, fail/defer its final save, and verify the watermark stays unchanged and the update is requested again.

**Existing coverage / missing evidence:** `JustTCGContractTests.testFailedCheckpointIsReportedAndDoesNotAdvanceDelta` supplies a callback returning false. It does not exercise the production callback returning true without saving. Actual interruption and storage-pressure behavior remain untested.

## D05 — Live recomputation excludes its own newly reconciled evidence

**Location:** `Services/PortfolioReplaySnapshot.swift:620`, `PortfolioComputationActor.compute`; line 402 `valuationIndex`, receipt filter at 410, and line 450 `recordsForValuation`. Caller: `Services/PortfolioEngine.swift:377`, recompute scheduling.

**Mechanism and trigger:** The caller captures a `through` cutoff before invoking the actor. Reconciliation then stamps a newly backfilled observation with its later current time. The builder excludes that observation because it is after the cutoff, and excludes the underlying PriceRecord because the same key has a future observation. A valid existing price with no local observation thus contributes nothing on that pass.

**Result / guards:** A holding can temporarily become unpriced and portfolio value zero until a later recomputation. Historical anti-lookahead guards are reasonable individually but conflict with live reconciliation ordering. StoreRevisionMonitor does not fingerprint observation-only writes, so that save alone does not guarantee a corrective recomputation; other app activity may provide one.

**Evidence:** `testAuditBackfillFallsAfterItsOwnReplayCutoff` inserted one card and an older price of 20, captured a cutoff, and computed: first result zero/unpriced; second computation at a later cutoff returned 20.

**Fix / verification:** Establish a coherent live snapshot cutoff after reconciliation, while retaining strict historical cutoffs and truthful reception times. Regression: the first live computation of a store containing prices but no observations must include those prices. Keep historical no-lookahead tests.

**Existing coverage / missing evidence:** Replay/reconciliation tests heavily cover individual temporal rules but do not establish this first-pass live invariant. The zero first result was reproduced; the duration of visible incorrect UI depends on subsequent scheduling and was not timed.

## D06 — EUR price deltas become USD portfolio values

**Location:** `Services/PortfolioEngine.swift:244`, `applyPriceDeltas`, especially line 254; `Services/PriceRefreshController.swift:1694`, forwarding live deltas. Cardmarket fallback in `Services/PriceProvider.swift` produces EUR displays.

**Mechanism and trigger:** The incremental path converts `display.amount` directly to `Money` without checking currency. Receiving EUR 25 for one previously unpriced card adds 25 to the USD headline and rankings. The authoritative replay filters unsupported currencies, so its later result differs.

**Result / guards:** Incorrect live valuation during refresh; terminal recomputation can repair it. The live path bypasses the currency guard used by full valuation.

**Evidence:** `testAuditLiveEuroDeltaIsCountedAsDollars` seeded a portfolio summary and applied an EUR 25 PriceDelta; the live USD current value became 25.

**Fix / verification:** Share currency eligibility with authoritative valuation; do not imply exchange conversion. Regression: EUR insertion and USD-to-EUR/EUR-to-USD transitions must preserve agreement between live and terminal totals.

**Existing coverage / missing evidence:** Currency coverage in valuation tests does not invoke this incremental method. The method-level result was reproduced; a full live-provider refresh was intentionally not run.

## D07 — Freshness-only changes are invisible to store revisions

**Location:** `Services/StoreRevisionMonitor.swift:49`, `StoreRevisionFingerprinting.priceValues`; price-shape fingerprint around line 511. Consumers include PriceSnapshotStore/projection refresh scheduling.

**Mechanism and trigger:** Value fingerprinting includes amount, currency, source, sourceUpdatedAt, invalidation and failure metadata, but omits fetchedAt/lastCheckedAt/lastSuccessfulCheckAt. A successful same-price refresh with no source timestamp can change a display from stale to current while leaving both value and shape fingerprints unchanged.

**Result / guards:** A sibling-context or synced update relying on the revision monitor can leave stale price-status UI until some other revision forces refresh. Controller-owned direct deltas can mask this in ordinary local refresh tests; they do not repair the general monitor contract.

**Evidence:** `testAuditFreshnessOnlyUpdateHasIdenticalFingerprint` advanced fetch time from 100 to 200000 with unchanged price: display state changed from stale to current but fingerprints remained equal.

**Fix / verification:** Include display-relevant freshness fields in revisions, or provide an explicit independent freshness revision. Regression: same-value refresh from another context must update the derived display without a collection mutation.

**Existing coverage / missing evidence:** Existing revision/race coverage does not establish this freshness-only case. Fingerprint and display-state behavior were reproduced; real CloudKit notification delivery was not tested.

## D08 — Graded browse loses the chosen print run on save

**Location:** `Views/GradedVariantPickerView.swift:104`, navigation to `GradedSlabConfirmationView`; lookup uses `pokemonPrintRun` at 134, but confirmation's save at 240 does not pass it. `Services/CollectionStore.swift:1716`, `addGraded`, stores its optional argument at 1884.

**Mechanism and trigger:** Browse a first-edition Pokémon card, choose a graded variant, and confirm. The lookup receives the print run, but the next view has no corresponding field and calls addGraded with the default nil value.

**Result / guards:** The new collection row loses edition metadata. A vendor binding may preserve the initial quote, but it does not populate the missing collection field or guarantee correct future edition-specific lookup. This is a deterministic parameter-loss path.

**Fix / verification:** Carry print run through confirmation and into addGraded. Regression: add a first-edition slab through this view path, refetch the saved row, and assert edition metadata and subsequent request identity.

**Existing coverage / missing evidence:** Direct store/request tests can supply the parameter and therefore bypass this navigation omission. View-construction smoke tests do not assert a saved row. This UI flow was source-traced, not interactively driven.

## D09 — Scanner save failure may contaminate the next add

**Location:** `Services/CollectionStore.swift:66`, `ScannerCollectionWriter.add`, staged add at 106 and final save at 121. Caller failure handling: `Services/ScannerViewModel.swift:2810`, commit path; writer lifetime established around 1228.

**Mechanism and trigger:** Raw scanning calls store.add with savesChanges false, resolves the resulting row, stages its price, then performs a final save outside an encompassing rollback handler. An exception from that save or intervening throwing fetch returns a failure to the UI while the reusable writer may retain pending changes. A subsequent successful add/retry could commit the previously reported failed add and duplicate ownership/ledger effects.

**Why suspected:** The missing outer rollback is concrete, but this audit did not induce a SwiftData save failure and prove exactly which changes remain registered afterward. The UI's failure report alone is not proof of a clean context. The missing-destination guard rolls back only its own explicit branch.

**Fix / verification:** Treat the full writer operation as a transaction and roll back all thrown paths after staging, or discard the failed context. Fault-inject final-save and post-stage-fetch failures; assert no ownership, activity, ledger, or price changes survive, and a retry adds exactly once.

**Existing coverage / missing evidence:** Store-level mutation rollback and scanner success tests do not prove writer-level failure atomicity. Required evidence is an injected save/fetch failure followed by another operation on the same writer. No production fix is proposed as already verified.

## Five findings most likely to affect real users

1. **D01:** delayed synchronization can leave portfolio prices behind collection prices.
2. **D05:** first valuation of newly reconciled prices can show missing value.
3. **D07:** successful same-value updates can continue to look stale.
4. **D08:** the normal graded browse save path drops a selected edition.
5. **D06:** EUR fallback updates can temporarily inflate USD totals.

This is a code-path exposure ranking, not measured incidence. D02/D03 can have greater financial impact when their narrower graded-card triggers occur.

## Shared causes

- **D01/D05:** source time, reception time, and replay cutoff are used across boundaries without one consistent temporal contract.
- **D02/D03/D08:** product identity is narrowed or discarded between lookup, grouping, navigation, and persistence.
- **D04/D09:** outer orchestration assumes a stronger transaction guarantee than its persistence boundary provides.
- **D06/D07:** incremental updates/revisions omit information that the authoritative display or valuation path uses.

## Baseline and exact verification commands

Environment: Xcode 26.6 (17F113), iOS 26.5 simulator, iPhone 17 Pro, UDID `EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86`. Build products and diagnostics were isolated under `/tmp/tcs-audit-pass1`. Commands below ran from the repository root unless an absolute project path is shown.

```sh
xcodebuild -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -configuration Debug -destination 'platform=iOS Simulator,id=EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86' -derivedDataPath /tmp/tcs-audit-pass1/DerivedData build > /tmp/tcs-audit-pass1/debug-build-access.log 2>&1

xcodebuild -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -configuration Debug -destination 'platform=iOS Simulator,id=EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86' -derivedDataPath /tmp/tcs-audit-pass1/DerivedData -resultBundlePath /tmp/tcs-audit-pass1/full-tests.xcresult -only-testing:TradingCardScannerTests test > /tmp/tcs-audit-pass1/full-tests.log 2>&1

xcodebuild -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/tcs-audit-pass1/ReleaseDerivedData build > /tmp/tcs-audit-pass1/release-build.log 2>&1

xcodebuild -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -configuration Debug -destination 'platform=iOS Simulator,id=EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86' -derivedDataPath /tmp/tcs-audit-pass1/DerivedData -resultBundlePath /tmp/tcs-audit-pass1/focused-tests.xcresult -only-testing:TradingCardScannerTests/ScannerViewModelTests -only-testing:TradingCardScannerTests/CollectionActivityHistoryTests -only-testing:TradingCardScannerTests/ImportedItemKindTests -only-testing:TradingCardScannerTests/MagicTreatmentMigrationTests -only-testing:TradingCardScannerTests/JustTCGContractTests -only-testing:TradingCardScannerTests/PortfolioReconciliationTests -only-testing:TradingCardScannerTests/PriceStoreRefreshRaceTests test > /tmp/tcs-audit-pass1/focused-tests.log 2>&1
```

| Run | Result |
|---|---|
| Fresh-derived-data Debug build | BUILD SUCCEEDED |
| Complete TradingCardScannerTests | 960 executed, 1 skipped, 0 failures; TEST SUCCEEDED |
| Separate-derived-data Release simulator compile | BUILD SUCCEEDED; arm64 and x86_64 |
| Focused rerun | 213 executed, 1 skipped, 0 failures; TEST SUCCEEDED |
| Temporary probes | 6 executed across three runs, 0 failures; all asserted the reported defective behavior |

The skipped test in both original-suite runs was `PortfolioReconciliationTests.testAgedStoreBaseline` (line 478), opt-in via `PERF_BASELINE=1`. It is a measurement gate, not a newly reported defect. The first Debug attempt used the same build arguments but output `debug-build.log`; restricted sandbox access prevented CoreSimulator service/runtime access. Re-running with approved simulator access succeeded. Release emitted the non-blocking AppIntents metadata extraction warning because no AppIntents dependency was present.

### Temporary reproduction commands and fixtures

An unmodified production-source copy and the existing test target were placed at `/tmp/tcs-audit-pass1/diagnostic-repo`. Six methods were added **only to the copied** `PortfolioReconciliationTests.swift`, using its existing in-memory context/card helpers. The following exact shell loop expresses the three executed invocations (the original calls were issued individually):

```sh
for run in 1 2 3; do
  case "$run" in
    1) suffix=''; a=testAuditDelayedNewerSourceStampIsDropped; b=testAuditFreshnessOnlyUpdateHasIdenticalFingerprint ;;
    2) suffix='-2'; a=testAuditBackfillFallsAfterItsOwnReplayCutoff; b=testAuditLiveEuroDeltaIsCountedAsDollars ;;
    3) suffix='-3'; a=testAuditGradedIdentityAcceptsWrongSetWithSameLocalNumber; b=testAuditGradedRefreshGroupsDifferentPrintRuns ;;
  esac
  xcodebuild -project /tmp/tcs-audit-pass1/diagnostic-repo/TradingCardScanner.xcodeproj -scheme TradingCardScanner -configuration Debug -destination 'platform=iOS Simulator,id=EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86' -derivedDataPath /tmp/tcs-audit-pass1/DiagnosticDerivedData -resultBundlePath "/tmp/tcs-audit-pass1/diagnostic-tests${suffix}.xcresult" -only-testing:"TradingCardScannerTests/PortfolioReconciliationTests/$a" -only-testing:"TradingCardScannerTests/PortfolioReconciliationTests/$b" test > "/tmp/tcs-audit-pass1/diagnostic-tests${suffix}.log" 2>&1
done
```

These existing result-bundle paths must be removed or changed before rerunning. Temporary files are local audit evidence, not permanent regression coverage. The finding descriptions preserve the fixture values and expected defective outcomes if `/tmp` is cleared.

## Audit coverage inventory

Repository inventory: **105 production Swift files / 61,686 lines; 43 test/support Swift files; 921 JSON files parsed successfully**. File/symbol/test-method inventory and SHA-256 hashes are in `/tmp/tcs-audit-pass1/source-inventory.json`; hazard and mutation indexes are adjacent. Parsing JSON establishes syntax, not correctness of every catalog entry.

| Area | Inspection and verification | Boundaries |
|---|---|---|
| Intended behavior | README, current documentation/release followups, app review baseline, model contracts, app entry points, scheme, test contracts | Prior audit conclusions were not treated as proof |
| Scanner pipeline | Camera/OCR lifecycle sections, parser, latch, variant resolver, catalog lookup, scanner commit/undo paths; full suite and focused ScannerViewModel rerun | No physical-camera, optical-quality, thermal, or rapid real-camera session evidence |
| Collection/persistence | Add and graded add, alias/lineage handling, projection, ledger entry flow, mutation/rollback indexes, CSV parsing/import paths; activity/import tests rerun | Failure injection incomplete; not every mutation branch manually stepped |
| Pricing | Provider/caches, transport, fallback, graded batching, sync ledger, checkpoints, live deltas, snapshot revisions; fixture contract/race tests rerun | No live-provider quotas consumed; production payload prevalence unknown |
| Portfolio | Money, epoch/calendar, observations, replay snapshot, reconciliation, current valuation and incremental totals; targeted temporal/currency probes | Genuine multi-device ordering and old deployed stores not exercised |
| Browse/sealed/graded | Catalog identity, product edition, product pricing, graded resolver/client/navigation; original browse/product/graded tests | Interactive browse journey not run; mixed-edition downstream persistence source-traced |
| CSV and upgrades | Import/export boundary code, item-kind contracts, treatment migration and normalization paths; focused import/migration tests | No independently sourced legacy database corpus; no exhaustive malformed/very-large CSV fuzzing |
| Centering/settings/credentials | Source/hazard screening and suite contracts, credential service and local configuration reads | Centering rendered UI and real images not manually validated; no account authentication performed |
| Launch/lifecycle | App entry and delegate, container selection/recovery, background/foreground paths, observer/task screening, revision monitor | No account-backed CloudKit container migration/recovery, process-kill matrix, or real OS background scheduling |
| Bundled data/configuration | JSON syntax validation, production/test snapshot distinction, manifests, plist/privacy and build integration inspection | No authoritative upstream comparison of all 921 JSON contents; successful compile does not validate provisioning/distribution |
| Tests | All test/support files inventoried, entire suite executed; relevant contract assertions and fixture wiring cross-referenced | View-construction tests do not prove navigation or mutation behavior; baseline tests do not cover identified boundary combinations |

### Thoroughly traced paths with no additional significant defect found

Within the examined local contracts, no additional reportable defect was established in checked money conversion/arithmetic, basic latch/variant selection, quote-cache boundedness, collection projection deduplication, or the covered ordinary collection activity/CSV item-kind flows. Existing tests passed for these areas. This is scoped negative evidence, not a guarantee about every input or failure mode. Style, optional refactors, hypothetical architecture concerns, and existing performance measurement gates were excluded.

### Limited confidence and precise missing evidence

The remaining confidence limits are real camera capture/thermal behavior; genuine account-backed multi-device CloudKit delivery and migration; storage-failure injection at transaction boundaries; interruption between price staging and checkpoint commit; real provider product ambiguity prevalence; exhaustive old-store and malformed/large-import corpora; and interactive centering/settings/background lifecycle runs. Repository-wide screening covered the inventory, but manual inspection concentrated on the cross-subsystem paths above. A further pass could deepen the less-inspected UI and migration branches without repeating the successful baseline builds.
