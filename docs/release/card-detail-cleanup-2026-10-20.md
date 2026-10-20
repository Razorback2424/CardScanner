# Bounded card-detail cleanup

**Status: concrete cleanups verified; incident root cause remains unconfirmed — 2026-10-20.** Starting
HEAD `e2c37adb6e7ba033ec19cc5f785f4bc9a284bcf0`, retaining the existing uncommitted
F1–F13 repairs. This work is separate from that repair handoff and Collector
Tools. No captured reproduction of the owner's nine-second hang is available.

## Changes and regression evidence

1. `CollectionCardDetailView.swift`: one `yDomain` evaluation outside the mark
   loops, reused for area floors and the Y scale. No samples, gaps, dates,
   prices, range selection, scrubbing or zero/one-point behavior removed.
   `PriceHistoryChartModelTests.testDenseProviderHistoryKeepsEveryExactSampleAndDomain`
   retains 5,000 exact samples; the existing flat, near-flat, low-price and
   nonnegative-domain tests remain. A hosted chart layout/snapshot test uses
   1,000 points and three sequential samples on the same simulator; this is
   simulator/debug evidence, not physical-device or incident performance proof.
2. `BrowseView.swift`: source URL/reload token and pixel derivative identities
   are distinct. Same-source size reloads keep usable artwork, including on
   derivative failure; URL/token changes reset it. Generation and cancellation
   checks reject old completions; identical requests do not restart. The
   existing quantization, cache bounds, decode/MIME validation and fallback
   ordering remain. `BrowseFeatureTests` adds gated loader-state coverage and
   a hosted cold/warm size-transition test.
3. `CollectionCardDetailView.swift`: a detail-scoped `@Query` filters the live
   collection key, orders newest override first and limits to one result.
   Every detail consumer receives the same effective filename in memory.
   Empty overrides suppress legacy filenames; missing overrides permit a
   nonempty legacy filename. `DetailDeletionRenderTests` covers these rules
   and hosted sibling-context replacement/removal, legacy changes and key
   changes. Existing save/cancellation, file ownership and orphan cleanup paths
   are retained. This does not claim SwiftData queries run off-main.
4. `PriceRefreshController.swift` and `ContentView.swift`: explicit manual
   intent bypasses only the recent primary-check gate for supported raw
   targets. Existing requests default to automatic; coalescing preserves manual
   intent, including suspension/resume. Unsupported, identity, migration,
   checkpoint, cancellation, cap, deduplication and vendor policies are retained.
   `PricingTests` compares the same recent normal target under both intents;
   `PriceRefreshLifecycleTests` exercises joins/coalescing and suspension/resume.
5. `PriceRecord.swift` and the detail view: source-date wording, a separate
   check-attempt timestamp, missing-source-date/quote-received wording and an
   explicit last-refresh failure message. `PriceDisplay.state` still uses
   `sourceUpdatedAt ?? fetchedAt` and 24 hours. Tests retain an old USD quote
   through a current check and assert truthful stale attribution.

`ProductFallbackTests.testUsableOldUSDPrimaryQuoteDoesNotSpendSupplementaryRequests`
guards the existing usable-USD-primary policy. History remains a separate
JustTCG series and never substitutes into portfolio valuation. No paid fallback
requests were made; fixtures and deterministic gates supply provider responses.

## Native execution

All runs use `TradingCardScanner.xcodeproj`, scheme `TradingCardScanner`, Debug,
the isolated Collection Quote QA simulator, existing external-SSD DerivedData
and SourcePackages. Logs are local `/tmp/cardscanner-detail-*.log`; xcresults
are external-SSD `CodexBuilds/CollectorTools-20261020/DetailCleanup-*.xcresult`.

- First focused run: 21 executed, one failure. The newly added manual test
  exposed use of the stored-printing capability for Pokémon, whose primary
  refresh uses the catalog path. The implementation now checks registered
  primary pricing capability. Chart, image-state and hosted artwork checks
  passed in this run. This failed run is not counted as passing verification.
- Second focused run: **26 tests, zero failures**, including hosted artwork,
  manual joins/coalescing/resume and old-source refresh. Its chart marks
  temporarily used the original repeated domain expressions solely to record
  the comparison baseline; the optimized expressions were restored afterward.
- Combined affected suites: **508 tests, zero failures, zero skips**. Selected
  suites: `PriceHistoryChartModelTests`, `PricingTests`, `ProductFallbackTests`,
  `PokemonCatalogFallbackTests`, `BrowseFeatureTests`,
  `BrowseLoadingRefinementTests`, `CatalogSetArtworkTests`,
  `BrowseCollectionTests`, `PokemonChecklistBrowseTests`,
  `ArtworkOrphanSweepTests`, `CollectionActivityHistoryTests`,
  `DetailDeletionRenderTests`, `PriceRefreshLifecycleTests`,
  `JustTCGContractTests`, `CardFinishRenderPlanTests`.
- Final targeted fallback/failure checks: **5 tests, zero failures**. Exact
  selectors under `TradingCardScannerTests/`:
  `BrowseFeatureTests/testHostedInitialArtworkFailureAdvancesToBundledFallback`,
  `BrowseFeatureTests/testArtworkResizeRetainsSourceAndRejectsSupersededCompletions`,
  `BrowseFeatureTests/testHostedColdAndWarmArtworkSizeTransitions`,
  `PricingTests/testFailedRefreshKeepsThePreviousPrice`,
  `PricingTests/testDetailAttributionKeepsOldSourceDateSeparateFromTodayAndFailure`.
  Same shared command plus these selectors, `test`, and result bundle
  `DetailCleanup-FinalFocused.xcresult`; log
  `/tmp/cardscanner-detail-final-focused.log`.
- Final source-removal image guard checks: **3 tests, zero failures**, using
  the three image selectors above, same shared flags, `test`, result bundle
  `DetailCleanup-FinalImage.xcresult`; log `/tmp/cardscanner-detail-final-image.log`.
- Final app-target build: **BUILD SUCCEEDED**, same shared arguments plus
  `build`; log `/tmp/cardscanner-detail-app-build.log`.

The 508-test combined run precedes only the final remote-source-removal
cancellation guard and additional test assertions. The three image tests were
rerun after that guard; final build covers the final source. The focused counts
overlap the combined run and must not be added as unique tests.

New behavior-specific regressions additionally include:

- `DetailDeletionRenderTests/testArtworkOverrideValueRules`
- `DetailDeletionRenderTests/testHostedArtworkQueryTracksSiblingReplacementRemovalAndKeyChanges`
- `DetailDeletionRenderTests/testHostedDenseChartLayoutAndSnapshot`
- `PricingTests/testManualPrimaryRefreshBypassesOnlyTheRecentCheckGate`
- `PriceRefreshLifecycleTests/testManualIntentSurvivesAutomaticJoinAndPendingCoalescing`
- `PriceRefreshLifecycleTests/testSuspendedManualIntentSurvivesCoalescingAndResume`
- `PricingTests/testDetailAttributionKeepsOldSourceDateSeparateFromTodayAndFailure`

Exact shared command arguments:

```sh
xcodebuild -project TradingCardScanner.xcodeproj -scheme TradingCardScanner \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=97F6D99C-3B99-422E-8395-EEAA10943CBC' \
  -derivedDataPath '/Volumes/Keller Family Photos/CodexBuilds/CollectorTools-20261020/DerivedData' \
  -clonedSourcePackagesDirPath '/Volumes/Keller Family Photos/CodexBuilds/CollectorTools-20261020/SourcePackages'
```

Combined test command appends `-only-testing:TradingCardScannerTests/<suite>`
for each suite listed above, then `test`, with
`-resultBundlePath '/Volumes/Keller Family Photos/CodexBuilds/CollectorTools-20261020/DetailCleanup-Combined.xcresult'`.
Its complete output is `/tmp/cardscanner-detail-combined.log`. Earlier logs are
`/tmp/cardscanner-detail-focused1.log` and
`/tmp/cardscanner-detail-focused2-baseline.log`, with result-bundle suffixes
`DetailCleanup-Focused1.xcresult` and
`DetailCleanup-Focused2-BaselineChart.xcresult` respectively.

Comparable hosted chart layout/snapshot measurements, same QA simulator,
Debug build, same 1,000 provider points and three sequential snapshots:

| Mark implementation | Samples (milliseconds) |
| --- | --- |
| Original repeated domain | 3870.02, 3173.26, 3180.59 |
| Domain reused outside loops | 2566.30, 2532.70, 2560.97 |

These are end-to-end hosted layout/snapshot timings, not an isolated chart CPU
profile, navigation latency or a device benchmark. Three samples do not
establish the incident's cause or eliminate renderer variability. Dense chart
rendering remains substantial; this pass intentionally preserves all samples.

## Native UI smoke and unexecuted checks

The final build ran only on Collection Quote QA. The first launcher/install
attempt encountered the simulator in Shutdown state (CoreSimulator code 405);
booting that existing isolated simulator resolved it. No owner device, app or
database was targeted. Existing launch arguments were:
`-ui_debug_route PortfolioAdditions cards -ui_debug_state price-chart`.

Cards Added rendered its two existing synthetic sealed fixtures. Opening QA
Booster Bundle reached the shared detail, with a rendered two-point chart,
separate source/check labels and quantity three. Returning to Cards Added and
reopening the same item rendered those values again. No hang was observed in
this limited cold/warm route. No ownership control was used. The QA app was
stopped afterward, and the prior tool-session profile was restored.

This route supplies sealed fixtures, not the reported raw-normal card. A full
raw-normal Cards Added route with delayed history/artwork and a mocked manual
refresh gesture **was not executed**; the existing debug route cannot inject
those delays/results. Delayed cold/warm artwork is covered by hosted native
tests, and manual refresh returning old source data is covered by native model
actor tests. Neither substitutes for that complete interactive scenario or a
captured failing incident. No new diagnostics framework or live paid calls
were introduced to bridge that gap.

`git diff --check`: passed. Changed documentation links: 8 checked, none missing.

## Limits and preservation

Concrete cleanups are distinct from the hang incident. Establishing its root
cause still needs a captured failing Cards Added → raw-normal detail path with
main-thread stacks, chart/artwork/history publication timing and a comparable
post-change capture. A visible history spinner and a successful repeat alone
do not establish causation.

Existing F1–F13 edits and Collector Tools/StoreKit work remain intact. No
collection data resets/exports, owner-app installation, cache/database resets,
signing changes, rollout changes, new games, cloud/backend/analytics work,
monetization changes, purchases, commits, pushes or commercial actions.
