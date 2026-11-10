# Release follow-ups

**Status:** current validation, measurement, and catalog-hardening backlog — latest review reconciliation 2026-11-10.

## Grade and finish review — 2026-11-10

Source: `2527c9b4163a4b9694e509ca245b9ca96d8ba38c` plus the combined dirty
working tree. Concurrent portfolio/detail work is preserved. Local fixes and
selected simulator verification are complete. This receipt does not close
device, provider or release gates.

| Finding | Validated behavior and focused change |
| --- | --- |
| F16, now demonstrated with synthetic OCR text | The baseline accepted all 18 original contradiction probes, including `PSA GEM MT 1`. [The parser](../../TradingCardScanner/Services/GradedLabelParser.swift) now checks the selected number against its grader-specific word range after layout-based selection, without substituting another number. The final table tests add explicit-plus and BCCG contradictions, preserve valid half grades and older CGC Gem Mint 9.5, and retain numeric-only TAG behavior. Existing misleading `EX 9` / `NM 8` positive fixtures now use valid grades; their contradictory forms have explicit negative coverage. |
| H1, exact finish correction | [The editor](../../TradingCardScanner/Views/CollectionActivityLogView.swift) loads the exact catalog printing instead of offering the game-wide finish list. It retains the current unsupported value for review, explains load failures, and drops stale/cancelled loads. Routing preserves hyphenated set IDs and imported catalog aliases; saving retains the catalog's variant label. The serialized history writer requires the catalog snapshot and checks matching game, printing and supported finish before moving ownership. The Tropius Normal/Reverse regression rejects Master Ball and another printing's evidence without changing quantities, ledger or activity; an allowed Reverse correction succeeds. Existing edition, lineage, storage and transaction guards remain. |
| H2, missing-price feedback | [Collection](../../TradingCardScanner/Views/CollectionView.swift) treats disabled optional fallback coverage as an informational missing-price state. Real failures still produce warnings. Unpriced tile text wraps separately from the finish label. No price amount, timestamp or observation meaning changed. |
| WP9 detail polish | [Detail](../../TradingCardScanner/Views/CollectionCardDetailView.swift) shows a text summary for one historical price, and no chart or repeated current-price block when only today's quote exists. A single-copy holding omits the duplicate total; multi-copy holdings retain it. [Catalog Undo](../../TradingCardScanner/Views/CatalogCardDetailView.swift) reserves the top safe area. The first maximum-text capture fragmented the message beside Undo; accessibility sizes now stack the message and action. History panels also reserve their full vertical text height after a maximum-text capture exposed overlapping explanations. |

The numeric policy was checked against [PSA's standards](https://www.psacard.com/gradingstandards),
[Beckett's published scale](https://beckett.com/grading),
[CGC's scale](https://www.cgccards.com/card-grading/grading-scale/) and
[legacy-label explanation](https://www.cgccards.com/about/help-center-faqs/about-cgc-cards/cgc-cards-merger/),
and [TAG's rubric](https://taggrading.com/pages/rubric). This is consistency
checking for supported label words, not expanded recognition of every historical
label or verification against a certification database. Real slab photos with
glare/dropped digits still need physical-device acceptance.

Verification on iPhone 17 Pro Simulator / iOS 27.0, Debug arm64, destination
`EC25844D-59BF-40D5-8D04-7C6A8FCBD049`:

- Broad selected run: 643 executed, 641 passed, two failed during Keychain setup
  in an unsigned host (`storeFailed(-34018)`). No pricing assertion ran in those
  two failed methods. All other selected classes passed.
- Signed rerun: all 142 `ScannerViewModelTests` passed, together with 89
  portfolio-history/replay/trust and background-refresh cases: 231/231 passed.
  Result-tree reconciliation gives 732 distinct passing app methods across
  these two runs; overlapping reruns are not additive.
- Final affected-suite verification: 270/270 passed, zero failures or skips,
  including 35 parser, 22 graded resolver, 97 activity/correction, 49 collection
  query, 15 chart-model, 14 detail-render, 36 Browse/collection and two
  view-construction cases. The exact final source builds for testing and
  `test-without-building -collect-test-diagnostics never` exits zero with a
  valid result bundle. Reconciliation with the broader/signed runs gives
  **734 distinct passing app methods**; no superseded failure remains unresolved.
- A 38-case banner follow-up and 31-case history-layout follow-up also completed
  their cases. An early failed render run and two later direct test drivers
  lingered during SDK metadata/result finalization and were stopped after their
  selected cases completed. Those stopped runs are not clean command receipts.
  The separate build-for-testing/test-without-building final run above resolves
  the runner issue without changing tests or product behavior.
- Fresh package runs: Pokémon 88 passed and one opt-in live CDN check skipped;
  Magic 18 passed; One Piece 46 passed. No package source changed.

The boundary audit was invoked through `bash` (the script is not executable).
It remains nonzero on existing legacy game branches. All five files it audits
are byte-identical to `HEAD`, so this change adds no boundary-audit hits.

The initial compile/harness attempts and the failed maximum-text banner image
are retained with the passing evidence. Screenshots use synthetic/in-memory
fixtures or preserve-data installs. The existing review simulator entry was not
corrected or deleted. No full-target, live-camera, centering, sandbox purchase,
iPad, physical VoiceOver, CSV-through-Files or performance acceptance is claimed.

Inspected final standard/maximum-text missing-price tiles, retained legacy
finish and failed-load editor states, the current-only detail screen, the
two-copy total, and standard/maximum-text Add/Undo. The synthetic quantity was
returned to one; Add/Undo was exercised only in an in-memory catalog fixture.
The final maximum-text capture shows the banner and Add button separately,
and the scrolled history explanations no longer overlap. Cold-start opening
screens are retained but are not UI acceptance evidence.

HIG verdict: **PASS for the inspected changes**. Native Form/Picker/button
patterns, clear missing/loading/failure states, full-size wrapping, existing
tap targets and the interaction path pass this scoped gate. The top issues
were unsupported finish choices, fragmented banner text and compressed history
explanations; the minimal fixes are recorded above. Physical VoiceOver and iPad
acceptance remain open.

Artifacts: `/Volumes/T7/CodexBuilds/GradeFinishReview-20261110/`, including
`parser-baseline.xcresult`, `final-regression.xcresult`,
`signed-scanner-and-neighbors.xcresult`, `final-results.xcresult`,
source fingerprints, reconciled test inventories, package logs, render
attachments and `ui-checklist.md`. Build products and dependency caches remain
on the external SSD. No commit, push, publication or collection reset occurred.

## Follow-up review remediation — 2026-11-10

Source: `aad6bd6bd967b734f7b7df24ea7d5eb1769d3d7a` plus the dirty working tree.
Existing uncommitted work is preserved. These are local implementation and
selected-suite simulator results; the launch contract's distribution, device
and provider gates remain open.

| Work package | Current disposition |
| --- | --- |
| WP1 operator-funded pricing | Owner selected paid JustTCG. The [contract](../release/launch-contract.md#pricing-service-for-launch-mandatory-product-and-licensing-prerequisite) records the published paid-tier terms checked today. Exact tier, active subscription, quota/cost budget, server-held credentials, authenticated proxy and no-key customer journeys remain open. The current app is still BYOK; no backend was implemented or deployed in this slice. |
| WP2 content delivery | Public `https://catalog.scan-stash.com/v1/current.json` returned HTTP 404 on 2026-11-10. Signed baseline publication, a real update round trip and candidate-freeze seed regeneration remain open. No catalog publication or live resource regeneration was performed. |
| WP3 flag separation | `NO_CLOUDKIT` controls entitlement-free foreground/headless storage. Release resolves to that flag alone, using local entitlements; `LOCAL_ONLY_SIGNING` remains restricted to the existing development/profile configurations. Final Release simulator readback has no `ownerRuntime`, owner-preference/file markers or owner resource directory. Debug is a positive control and retains all four. This supersedes the F8 Release compiler-flag choice recorded below. |
| WP4 scan-price states | Receipt and review use the existing lookup provenance: no provider answer says “Couldn’t check price”; a sourced missing quote says “Price unavailable.” Pending review explains that the card is saved and checking continues. The live review regression now covers priced, failed and provider-confirmed missing responses. No persistence or pricing observation semantics changed. |
| WP5 camera affordances | Scanner permission denial offers Open Settings. The maximum-text layout keeps the button visible and scrolls the message as needed. iPad multitasking interruptions show full-screen recovery guidance and clear it when the interruption ends, preserving independent failures. Notification tests pass; actual iPad Split View/camera recovery and permission changes still need a device. |
| WP6 Settings | Normal Settings shows version/build and Collection Diagnostics. The sync-diagnostics action is compiled out for entitlement-free storage. Existing collection exports remain. The collection-deletion/export flow was not changed. |
| WP7 centering disposition | [Reachability evidence](../audits/centering-guided-repair.md#release-reachability-disposition--2026-11-10) separates five DEBUG-reference research gates from the Release workflow. Their tests remain failing research checks; no skip or tolerance was changed. Shipped initial-guide accuracy remains open, with no owner acceptance recorded. |
| WP8 special printings | F16's contradictory slab word/number risk is reproduced and locally fixed; see the [grade/finish receipt](#grade-and-finish-review--2026-11-10). No new second-source printing sampling was performed. Unverified singleton zero-tap behavior and catalog authority remain unchanged; the audit/owner decision is still open. |
| WP9 finish correction and detail polish | Exact catalog/current finish choices and a serialized save guard replace the global finish picker. Missing-price feedback, tile wrapping, sparse history, duplicate single-copy totals and Undo placement are addressed in the [grade/finish receipt](#grade-and-finish-review--2026-11-10). |

Final Debug verification on iPhone 17 Pro Simulator, iOS 27.0, destination
`EC25844D-59BF-40D5-8D04-7C6A8FCBD049`: **309 executed, 303 passed, six skipped,
zero failures**. Selected classes:

- `ScannerViewModelTests` (142 passed), `CardLatchTests` (80 passed).
- `CollectionStorageBootstrapTests` (31 passed, one Simulator data-protection
  skip), `CollectionStoreModeTransitionTests` (two passed, five CloudKit-mode
  skips in the entitlement-free configuration).
- `OnePieceCatalogActivationTests` (14 passed), `OnePieceAvailabilityTests`
  (one passed), `CardGameForwardCompatibilityTests` (31 passed),
  `ViewConstructionSmokeTests` (two passed).

Earlier focused/split selections overlap this final run and are not additive.
The initial build caught and corrected a DEBUG screenshot-hook scope error;
no tests ran in that attempt. The first Release MCP call exceeded its tool wait,
but its retained build log reports success. A separate final-source Release
simulator build exits zero and reports `BUILD SUCCEEDED`; resolved flags and
binary/resource checks pass. This is not an archive or distribution receipt.

Inspected synthetic price-review images, normal/maximum-text permission recovery,
the scrolled maximum-text instructions, multitasking guidance, normal Settings,
expanded diagnostics and maximum-text version/build rows. The first maximum-text
camera capture clipped the action; the final bounded scrolling layout fixes it.
The failed iteration is retained as `before-scroll-fix.png`. Early cold-launch
opening states are not counted as UI acceptance. Open Settings opens iOS Settings
on Simulator. HIG gate: **PASS for these inspected changes** across native
patterns, clarity, scalable text, accessible layout and interaction cost; no
additional prompt or navigation layer was added. Physical VoiceOver/iPad and
live permission/camera acceptance remain open.

Artifacts: `/Volumes/T7/CodexBuilds/LaunchReview-20261110/`, including
`local-fixes-final.xcresult`, `final-test-summary.json`, `release-final.xcresult`,
`release-final.log`, `release-readback.json`, `verified-source-sha256.json`,
the `ui-*` folders and `ui-checklist.md`. All 410 retained source/build-setting
fingerprints match between final tests and Release readback. Screenshots, logs
and collection data are not committed. No launch gate is closed by this slice.

This document is the aggregation point for gates that source inspection or the
ordinary simulator suite cannot retire. Completed implementation plans are
archived under [`../legacy/`](../legacy/); they are historical context, not
open work queues.

This is the aggregation point for work that cannot be retired by the ordinary
simulator suite, plus small catalog-hardening follow-ups from review. Items
below are validation, measurement, or test/documentation gates, not suspected
defects. Close an item with the evidence described here, or record the measured
reason to leave it unchanged.

**Where these are picked up:** the active
[launch plan](../superpowers/plans/2026-09-13-phase-0-phase-1-app-store-launch.md)
§0.1.2 references this document, and §0.1.1 binds the open
[pass-2 findings](../audits/defect_review_pass_2.md) to the tasks they block.
RF-6 gates Task 1 and Task 11. F01/F02 source remediation is landed; RF-7 and
RF-8 remain open for the entitled-device and measurement evidence described
below. The 2026-09-22 code-review remediation, focused simulator results, and
open acceptance items are tracked in the root
[`app_review_fix_plan.md`](../../app_review_fix_plan.md); this document owns
the residual runtime, device, provider, and scale evidence.

## Release validation

### Owner-deferred launch links — 2026-11-08

Privacy and support pages do not exist yet. The owner explicitly deferred
publishing them and setting `CARD_SCANNER_PRIVACY_URL` / `CARD_SCANNER_SUPPORT_URL`
until the final launch preparation. Keep these values empty until approved HTTPS
pages are published; do not invent destinations or treat this as an unfinished
engineering fix. Before launch, configure `/privacy` and `/support`, inspect the
built Release Info.plist, and open both links from the installed app.

### Launch-review remediation — 2026-11-09

Implemented on `main`, based on `aad6bd6` plus the uncommitted working tree.
The supplied partial review was checked against source; its open BYOK decision
is superseded by the [commercial pricing launch prerequisite](../release/launch-contract.md#pricing-service-for-launch-mandatory-product-and-licensing-prerequisite).
This work does not certify the complete target or change the five-game boundary.

| Finding | Implementation and verification boundary |
| --- | --- |
| F2: offline scan prices | Successful raw commits can refresh through the existing game pricing adapter without a customer key. Receipts/review show `Checking price…` only while the task is active. Successful quotes update the same receipt; failure ends the pending state without manufacturing a provider miss; Undo and storage/session checks remain in force. New deterministic scanner regressions pass. Physical-camera and live-provider receipt acceptance remain open. |
| F3: owned marketplace links | Add/catalog metadata use the same exact-product resolver as Browse, with the row's independent print run. Normal price refresh now publishes guarded marketplace-only patches as well as the existing imported metadata patches. Shadowless/unsupported First Edition and conflicting products remain unbound. Refresh never changes ownership or substitutes source artwork. Existing fresh-price rows are backfilled when their next provider refresh runs. |
| F1: keyless history | Cached history/current prices remain usable; missing credentials produce a configuration explanation without an error/Retry loop. This is an interim improvement to the existing BYOK implementation, not completion of the required app-funded commercial service. Graded/sealed configuration gates remain intact. |
| F4: finish correction | Raw detail exposes the existing claim-aware history editor. Successful correction returns to Collection instead of the outgoing row's removed placeholder. Catalog-selected finishes carry a physical-card comparison caveat. Singleton auto-resolution and its provenance are unchanged; this does not close S03.01 or establish exhaustive physical coverage. |
| F6: first launch | Empty authoritative Portfolio shows a native explanation and a working scan action. Empty history has horizontal padding. Detail range controls use two columns at accessibility text sizes; single-price captions can wrap. |
| F7: Activity reads | A retained 1,500-card/1,500-event SQLite fixture measured the previous reload at 94–100 ms. Reads now cover the visible activity page's positions and lineage, including cross-position correction legs and their reversals. The same simulator case measures 20–24 ms. This is simulator evidence, not a physical-device latency certification. |
| F8: release configuration | Release uses the existing empty local entitlements and `LOCAL_ONLY_SIGNING`; background price fetch/processing remain, and `remote-notification` is removed. Resolved Release build settings confirm this selection. The local StoreKit display name is `ScanStash Collector Tools`. Privacy/support settings stay empty, reaffirmed by the owner in this session. Signed archive and App Store Connect metadata are separate gates. |

Verification (Debug, iOS 27.0 simulator, dedicated pricing-test destination):

- Combined selection: **624 executed, 622 passed, two skipped, zero failures**.
  Selection: `ScannerViewModelTests`, `TCGplayerLinkTests`,
  `RefreshStructuralWriteTests`, `DetailDeletionRenderTests`,
  `CollectionActivityHistoryTests`, `PricingTests`, `PriceRefreshLifecycleTests`,
  `VariantResolverTests`, `OwnershipLedgerCompletenessTests`,
  `CardGameForwardCompatibilityTests`, `CollectionKeyTests`,
  `PortfolioTrustPassTests`, `PortfolioHistoryEngineTests`,
  `PrivacyAndSupportSurfaceTests`, `CollectionStorageBootstrapTests`,
  `CloudKitSchemaCompatibilityTests`, `CollectorToolsTests`.
- Subsequent correction-navigation change: **104/104 passed** in
  `CollectionActivityHistoryTests` and `DetailDeletionRenderTests`.
  Subsequent accessibility layout change: **10/10 passed** in
  `DetailDeletionRenderTests`. These selections overlap; do not add the counts.
- The two skips are simulator data protection and local StoreKit's invalid
  interrupted-purchase fixture. Local purchase/restore/refund and pending
  approval now pass in the combined run after explicitly waiting for the local
  test configuration's product to become available. No production entitlement
  rule or interrupted-purchase acceptance assertion was weakened.
- Results initially written to scratch after Xcode stalled collecting failure
  diagnostics; passing runs use `-collect-test-diagnostics never`. Derived data
  remains on the external SSD. Final bundles/logs and synthetic UI artifacts are
  retained under `/Volumes/Keller Family Photos/TradingCardScannerDerivedData/launch-review-fixes-20261109/verified/`.
  No screenshots, credentials, collection exports or raw logs are committed.
- Rendered routes: `FirstLaunch`, `TrustScanReceipt/price-pending`,
  `CardDetail/price-chart-keyless`, `TrustCardDetail/uniqueInCatalog` on a separate
  iPhone 17 Pro simulator. Inspected the empty scan action, pending price,
  keyless explanation, finish correction and completed navigation. Large-text
  inspection includes accessibility sizes; physical VoiceOver/iPad acceptance
  is not claimed.

UI gate: **RISK** pending device/accessibility and commercial-service acceptance.
Platform patterns, clarity and interaction cost pass the inspected scenarios:
native controls/navigation, an obvious first action, nonblocking pricing and
optional correction. Typography uses scalable fonts, wrapping and adaptive
range layout. Accessibility labels and standard tap targets are present;
VoiceOver and iPad remain unverified. App Review readiness remains open because
the commercial pricing service, live legal/support destinations, production
One Piece activation, centering gates and signed distribution evidence are not
completed by these fixes. Provider timestamps and the 24-hour stale policy (F5)
are unchanged; source time is not replaced with retrieval time to hide staleness.

### Four uncommitted-review regressions — 2026-11-09

Corrected on `main` at `aad6bd6` plus the dirty working tree:

- Existing ownership rows keep their verified marketplace URL/product when
  another copy is added from an identity-only offline snapshot. Catalog metadata
  refresh remains responsible for authoritative mapping withdrawal.
- Post-commit pricing tries the configured independent fallback after a catalog
  transport failure or `.unavailable(nil)` result. Cancellation, capability,
  identity and mapping guards remain in place; failed transport is not recorded
  as a provider-confirmed missing price.
- An already-open scan review reads the current quote and pending flags together,
  so success and failure both end the checking state without reopening the sheet.
- First-card guidance requires an authoritative zero-copy summary and a loaded,
  empty history result. Historical chart/range controls remain available after
  the final holding is removed, including an anchor outside the selected range.
  This reuses existing history state rather than adding persistence or another
  history read.

Five retained regression methods and all marketplace-link tests pass in the
focused rerun: **29 passed, zero failures or skips**, Debug on the dedicated
pricing-test iOS 27.0 simulator (`0A8D5FA0-9FAD-4F60-855C-9DAF31BCCDC9`).
The initial run had one screenshot-test casing assertion failure; its rendered
unavailable state was correct, and the final assertion matches the user-facing
text. Final source and tests were rebuilt for the passing rerun.

Inspected final hosted-render PNGs for a completed and failed scan price, zero
holdings with recorded history, and a new collection with no history. HIG gate:
**PASS for these scoped states** (native patterns, clear feedback, preserved
typography and controls, no new prompt). Physical-device VoiceOver, iPad, live
provider and distribution acceptance remain separate. The existing broader UI
and commercial-service gates above remain open.

Artifacts are outside the repository under
`/Volumes/Keller Family Photos/TradingCardScannerDerivedData/launch-review-fixes-20261109/`:
`four-regression-fixes-focused-final.xcresult`, its adjacent log and
`four-fixes-ui-final/` (including the inspected screenshot checklist).

Final neighboring verification completed in two disjoint selections:

- `four-fixes-scanner-final.xcresult`: all **142/142** `ScannerViewModelTests`.
- `four-fixes-neighbors-final.xcresult`: **372/372** across
  `CollectionActivityHistoryTests`, `TCGplayerLinkTests`,
  `PortfolioHistoryEngineTests`, `OwnershipLedgerCompletenessTests`,
  `OwnershipConcurrencyStressTests`, `CollectionStoreContinuityTests`,
  `RefreshStructuralWriteTests`, `PriceRefreshLifecycleTests`,
  `DetailDeletionRenderTests`, `VariantResolverTests`, `CardLatchTests` and
  `PortfolioTrustPassTests`.

Together these are **514 passed, zero failures or skips**. The 29 focused cases
overlap them and must not be added. Configuration, source identity and simulator
are as above; adjacent logs retain the exact selections.

The earlier `four-regression-fixes-expanded.xcresult` ended after 378 passes
with test-host SIGKILL during
`testLateAdditionalCopyCompletionCannotReviveOldSessionPrompt` and a failed
host relaunch; no assertion failure was recorded. The interrupted test passes
alone in `four-fixes-interrupted-test.xcresult`, then the same selected coverage
passes in the two complete split runs above. The termination cause is not
attributed. These results are not complete-target evidence.

### Full-checkout regression status — 2026-11-09

The [current regression record](../../app_review_fix_plan.md#full-checkout-regression-investigation--2026-11-09)
supersedes older full-target failure inventories as current checkout evidence.
The unfiltered baseline reports 3,195 passed, 32 failed and 21 skipped; after
CSV replay, signed-finish cache and camera-lifecycle fixes, the broad final-source
rerun reports 3,174 passed, two failed and 21 skipped. All three catalog packages
pass (152 passed, one skipped). These are distinct runs, not additive coverage.
The broad selection does not repeat the two long centering research classes
wholesale; all five failed/interrupted cases were rerun separately. The interrupted
Prismatic library case passes. Six centering gates remain unmet: initial guides,
the supplied-layout probe, two foil Gengar checks, the Prismatic right edge, and
assisted-reference timing. Fresh-host DEBUG-assisted timing is 0.963 s upper
median / 2.393 s maximum against unchanged 0.8 / 1.5 s limits; profile/device
evidence is needed before changing performance behavior. The complete target
remains uncertified. Preserve the [centering accuracy authority](../audits/centering-guided-repair.md)
and the physical-device/provider gates below; no threshold or manual-review guard
was weakened to obtain passing workflow checks.

### Refinement runtime acceptance — 2026-11-09

The six source-review fixes are implemented; see the
[progress record](../../progress.md#2026-11-09--production-refinement-fixes).
Affected-scope signed Debug simulator verification passed 383 tests with
zero failures and one existing live-provider skip; the final scanner/catalog
rerun after completing the historical-choice policy passed 223 tests with zero
failures and zero skips. These checks do not close
the physical-device or live-provider gates.
Keep these runtime checks open:

- On iPad, verify the photo level indicator's correction directions in portrait,
  upside-down portrait and both landscape orientations. Unit vector checks do
  not establish physical-device acceptance.
- During collection intake with omitted provider artwork, verify prompt saves
  and subsequent exact artwork enrichment when Collection opens. Read-only
  presentation still supports recovery and its disk cache.
- Confirm cached Browse identity/actions remain usable during delayed pricing,
  and consecutive sealed additions followed by Undo retain the prior copies.

The review's native-detail crop measurement (about 5.3 ms cold on Simulator),
whole-store reconciliation observations and shared OCR/tracking scheduling do
not establish device performance defects. Use the existing hang inspection
protocol and representative device/collection workloads before changing them.

The [hang inspection protocol](hang-inspection-plan.md) defines the repeatable
capture, source-attribution and fix-verification workflow for responsiveness
work, including RF-1/RF-2. It does not close these gates; current device evidence
and measured completion remain required.

### RF-1 — Collection cold-launch first paint

**Status:** targeted simulator checks passed; full-target failures and device
measurements remain open — 2026-10-29. No persistence change justified yet.

Measure a Release build on a real device with a seeded collection of roughly
1,500 cards. Record the time from launch to the first real collection grid row,
using the existing collection projection signposts.

- If the first row appears in roughly 300 ms or less, close this as
  **won't-fix**; the launch spinner is not perceptible enough to warrant a
  persisted projection snapshot.
- If it is materially slower, evaluate persisting the last
  `CollectionProjectionSnapshot` and replacing it when the actor read completes.

Launch-path changes on branch `claude/launch-speed` at `c557499` (implemented;
native verification below, device timings pending): the Yu-Gi-Oh! bundled
catalog is registered from a per-build cache and decoded on first use; static
catalog price withdrawal runs after the
portfolio starts; browse catalog preparation waits for the opening handoff; and
the opening reveals after at most `AppOpeningModel.portfolioRevealBudget`
(350 ms) once content mounts, without a copy count if the portfolio is still
calculating. Record both the first launch after install (cache miss) and a
repeat launch, with the `Launch.*` signposts listed for H01 in the
[hang inspection plan](hang-inspection-plan.md).

**Native verification — 2026-10-29:** Xcode 27.1, dedicated iPhone 17 simulator
on iOS 27.0. The checkout included the existing listing-photo UI edits and a
test-only One Piece fixture correction: delayed responses now retain their
server capture dates on either side of the withdrawal watermark. Production
launch/transport code was not changed by this verification pass. Earlier shared
simulator attempts were superseded after concurrent photo UI launches terminated
the test host.

| Targeted suite | Passed |
| --- | ---: |
| `YuGiOhCatalogTests` | 15 |
| `LaunchModelActorTests` | 6 |
| `AppOpeningTests` | 12 |
| `LorcanaOwnershipTests` | 29 |
| `OnePieceIntegrationTests` | 98 |
| `MagicTreatmentMigrationTests` | 26 |
| **Total** | **186; zero failures/skips/runtime warnings** |

The subsequent full `TradingCardScannerTests` target finished with **2,693
passed, six failed, 16 skipped**. Eight runtime warnings concern reading SwiftUI
State/Environment outside an installed view in `UncoveredSurfaceTests.swift`.
The six-case isolated rerun had **two passed, three failed, one skipped**.
The StoreKit purchase/restore and pending-approval tests passed after failing to
load a product in the full run. Interrupted-purchase acceptance skipped because
local StoreKit supplied a verified entitlement before issue resolution; that
case still requires sandbox follow-up. These three assertions still fail in
isolation:

- `CollectionKeyTests.testREQ001UnderlyingPrintingIDUsesTheProductionSourceForEveryItemKind`:
  expected a nil catalog provider ID; actual value is `direct-product`.
- `JustTCGV2GradedSurfaceTests.testGradedIdentityGroupingAndOwnedFiltersUseExactFields`:
  the actual grouping key has an additional trailing `none` field.
- `SwiftDataConcurrencyCharacterizationTests.testDidSaveKeysAndPersistentIdentifierEntityName`:
  the actual notification keys also include `historyTokens` on this runtime.

The full target remains failed; the isolated StoreKit passes/skip do not
supersede that result. These assertions were left unchanged.

The device-target **Release build compiled successfully with
`CODE_SIGNING_ALLOWED=NO`**. Normal signed Release failed because the installed
provisioning profile lacks the app's iCloud capability/container entitlements.
No device app was installed or removed, no collection data was changed, and
neither first-install nor repeat-launch timing was captured. The approximately
1,500-card device workload/restoration setup still needs confirmation.

Local evidence is retained outside Git on the external SSD at
`/Volumes/Keller Family Photos/CodexBuilds/TradingCardScanner-launch-speed-20261029/`:
`targeted-dedicated.xcresult`, `full.xcresult`, `full-failure-rerun.xcresult`,
`release-build.xcresult` (signing failure), and `release-unsigned.xcresult`.

### RF-2 — Scanner tracking at 8 Hz

**Status:** hardware validation pending; simulator cannot retire this item.

The current [scanner module review](../audits/scanner_module_review.md) adds
three measurement concerns to this gate's scope. In particular, compare OCR
interval durations with tracking event rate and `trackerSeeded`/`trackerLost`
diagnostics on the slowest supported device at 4K, and record stationary-card
false spatial-exit prompts separately from true departures.

Run a physical-device scan pass with a stack of 30 cards and record duplicate
and missed-card rates, confirmation latency, and thermal behavior over a normal
session. Include ordinary cards, similar neighboring cards, and at least one
graded slab if available.

The 8 Hz change should remain unchanged unless this pass produces a concrete
regression.

### RF-6 — Centering corpus bundle wiring and executable suite baseline

**Status:** fixture wiring corrected 2026-09-16; gate remains open for analyzer
assertions and a complete, storage-safe verification run.

The centering corpus is repository-owned: 57 tracked files under
`TestFixtures/TradingCards/`, including the ten `IMG_03xx`/`IMG_07xx` HEICs,
their ground truth, and the supplementary manifest. The files were not reaching
the test bundle because `project.pbxproj` reused two IDs for the fixture
resource entries and `CardFinishRenderPlanTests.swift`, while the test group
pointed to an undefined fixture reference. The resource build file and folder
reference now have unique IDs, and the group and Copy Bundle Resources phase
refer to those exact objects. The root-cause correction is recorded in
[`../audits/defect_review_pass_2.md`](../audits/defect_review_pass_2.md) F06.

The 2026-09-16 focused simulator run reached the corpus and manifest. Its
interrupted result bundle reports 38 selected results: 28 passed, 9 test cases
failed on centering accuracy, invariant, or performance assertions, and 1
profile-dump test was canceled. The direct fixture-reachability and
cryptographic-manifest tests passed. These nine failing test cases correspond
to the already-open centering gates in the
[centering contract](../../review/opus-card-centering-implementation-plan.md);
the run is not a clean baseline, and the full simulator suite was not rerun.

Do **not** add `XCTSkipUnless` guards for these fixtures: they are committed
inputs, not optional host data. To close this item:

- Triage the existing centering accuracy, invariant, and latency failures under
  the centering contract without weakening its frozen thresholds.
- Make diagnostic-dump output configurable so the corpus suites write only to
  the external SSD, then rerun all four suites to completion. Their current
  output path rewrites tracked files under `review/centering-evidence/`.
- Keep the unrelated `OwnershipLedgerCompletenessTests` source-inventory path
  check and `ScannerViewModelTests` load-sensitive wait in the full-suite
  triage; do not classify them as fixture failures.
- Record a clean or explicitly triaged full-target baseline in
  [`../release/phase-1-integrity-evidence.md`](../release/phase-1-integrity-evidence.md).

### RF-7 — Storage-bootstrap production wiring, on an entitled device

**Status:** open for entitled-device/runtime evidence. The pass-2 F01/F02
source fixes are present in the committed tree; CloudKit enrollment and device
verification remain outstanding.

[`../audits/defect_review_pass_2.md`](../audits/defect_review_pass_2.md) F01 and
F02 are deterministic source traces and do not need a device to be believed.
What does need a device is the confirmation that their fixes behave correctly
end to end:

- Clean install on a simulator and on a device signed in to iCloud reaches the
  collection rather than the restoration screen, and `.restoringFromCloud(.failed)`
  offers a non-cloud continuation.
- A `BGAppRefresh` launch on a device whose manifest is `.suspended` resolves a
  `cloudKitDatabase` of `.none`, and no collection records appear in the private
  database afterwards.
- `TradingCardScannerApp.activeStorageMode` reflects the headless session, so
  `PortfolioEpoch`'s `isAwaitingInitialSync` gate is evaluated against the real
  container mode.

Coordinate with
[`../release/cloudkit-compatibility-audit.md`](../release/cloudkit-compatibility-audit.md);
that audit owns schema promotion, this item owns the bootstrap's runtime
behavior.

### RF-8 — Background price-check coverage budget

**Status:** open; the source dependency on pass-2 F02 is fixed, and the
remaining work is device-measured.

Slice B of [`price_history_chart_plan.md`](price_history_chart_plan.md) proposes
replacing `BackgroundPriceRefresh.appRefreshTargetLimit = 3` with an elapsed-time
budget, so a `BGAppRefresh` pass completes as many targets as its window allows.
The existing count is justified in source by JustTCG's 6.5 s pacer, which does
not apply to Scryfall-priced Magic rows.

This cannot be retired in the simulator, and it must not be started early:

- **Blocking.** The F02 source fix must remain in the candidate before raising
  background throughput; device evidence still needs to confirm that headless
  preflight resolves on-device-only stores without CloudKit mirroring.
- Measure the real `BGAppRefresh` window on device and record how many targets a
  budgeted pass completes, split by provider.
- Confirm a large collection does not trip `JustTCGQuota.backgroundDailyCeiling`
  (75).
- Re-measure per-card chart continuity on a real collection after a week.

Close each sub-item independently. A continuity improvement measured on a seeded
simulator collection does not close this item.

## Measurement-gated backlog

### RF-3 — Projection rebuild cost and coalescing

Capture rebuild frequency and `CollectionProjectionSnapshot` equality cost on a
seeded store during a representative refresh. Only replace deep equality with
an actor-computed revision token, or change completed-read coalescing, if the
profile shows meaningful main-thread or churn cost.

### RF-4 — Graded label parser coverage

When more real slab samples are available, add focused cases for BCCG/BVG,
ambiguous labels, proximity boundaries, and the confirmation window. Include
PSA labels with the observed 8- and 9-digit certificate formats before widening
the parser range again. This is test debt, not a reported misread.

### RF-5 — Existing performance device gates

**Status:** hardware/runtime profiling pending.

The remaining gates from the archived
[`performance_review_remediation_plan.md`](../legacy/performance_review_remediation_plan.md) are grouped
here so they do not get lost between plan revisions: verify the explicit camera
pixel format against OCR hit rate and thermal behavior, evaluate tab-bar
flicker during repeated scan receipts, measure camera restart latency on tab
return, and capture one live-provider refresh profile to confirm the off-main
signposts. The scanner module review also calls for measuring the
`offerHeldDuplicateRebuild` interval and its relationship to session length;
retain that evidence with the scanner performance result. Close each sub-item
independently when its evidence is available.

The current price-refresh scale plan is
[`price_refresh_scale_plan.md`](price_refresh_scale_plan.md); its actor boundary
is landed, while continuous resumable sweeps, Magic batching, and large-store
measurement remain open.

### RF-9 — Browse set-directory price-sort measurement

**Status:** open; implementation is landed, but this is a provider/device
measurement gate and was not retired by deterministic tests.

Record before/after evidence for the Browse remediation on `me02.5` ASC:

- time to first reorder after choosing Price: High to Low on the 629-slot set;
- total `fetchCard` calls, including the effect of provider-card deduplication;
- whether opening the set without choosing a price sort stays within the 400
  distinct-provider prefetch gate, including Low Power Mode behavior.

Keep the result separate from the simulator regression evidence. The source and
focused tests establish the incremental/cancellable ordering contract, not live
provider latency or quota behavior.

## Catalog fingerprint hardening follow-ups

These items are non-blocking follow-ups to the completed artwork-enrichment
fingerprint fix. The Core parity test protects the publisher-side enrichment
boundary; the items below preserve the remaining code intent and close the
publisher-to-device mapping seam.

### RF-10 — Document the descriptor artwork fallback rung

**Status:** open; documentation hardening.

Keep a code comment at
[`CatalogBuilder.swift`](../../PokemonCatalogCore/Sources/PokemonCatalogCore/CatalogBuilder.swift)
explaining that the directory row's `logo`/`symbol` fallback remains
load-bearing for a raw provider value of `""` when artwork resolution returns
`nil`. The fallback is descriptor-only and is not redundant with the resolved
artwork fields or the raw values hashed by `v1`; it should not be removed as a
cleanup.

Close when the comment lands and `git diff --check` remains clean.

### RF-11 — Add device-side canonical fingerprint parity coverage

**Status:** open; iOS test coverage follow-up.

Add a focused iOS catalog test that maps a `TCGdexSetCatalog` through the real
device-side `canonicalFingerprint` implementation in
[`PokemonChecklistSnapshot.swift`](../../TradingCardScanner/Services/PokemonChecklistSnapshot.swift)
and compares it with
`PokemonCatalogProviderFingerprint.v1` on the equivalent raw Core model. The
existing
[`ArtworkFingerprintParityTests.swift`](../../PokemonCatalogCore/Tests/PokemonCatalogCoreTests/ArtworkFingerprintParityTests.swift)
exercises `fetchFixture`, all three artwork-enrichment paths, and descriptor
resolution, but it uses a hand-built Core value rather than the app-target
mapping. Close when the focused iOS test passes and its test evidence is
recorded; this does not by itself retire physical-device acceptance.

### RF-12 — Collection write, refresh, and lifecycle acceptance

**Status:** implementation and simulator verification are present; scale,
OS-lifecycle, and device-timing evidence remains open.

**Latest simulator evidence (2026-09-23):** the iPhone 17 Pro / iOS 26.5
non-centering suite executed 1,510 tests with 7 skipped and no failures. A
separate Debug simulator build succeeded. Centering tests were excluded. This
does not close the physical-device or operating-system lifecycle checks below.

The current pass-2 remediation serializes ownership writes, applies refresh
metadata as guarded patches, suspends refresh around price-identity rewrites,
and makes CSV imports resumable. Focused tests cover the deterministic
concurrency, patching, retry, and resume rules. Before treating the paths as
operationally accepted, collect the remaining evidence:

- On a physical device, overlap a background-owned price pass with a foreground
  launch and confirm the foreground collection becomes usable promptly.
- Exercise real iOS background-task expiration during a long CSV import and a
  background refresh. Confirm the next launch resumes the import without
  double-counting and the refresh does not publish a partial completion.
- On the 300-card fixture, record the `scannerPersistence`,
  `priceRefresh.commitStaged`, and `portfolio.recompute` signpost counts and
  durations before and after the fresh-context writer and row-patch changes.
- Complete the planned simulator flows for removing a row and running
  delete-all during refresh, interrupting and resuming CSV import, retrying a
  first-open container failure, and sorting/filtering a native-currency row.

Simulator tests cannot establish actual background scheduling/expiration or
real-device timing. Do not use simulator-only results to claim those gates are
closed.

### RF-13 — October review performance measurements

**Status:** physical-device capture pending — 2026-10-02.

The [October review ledger](../audits/october-review-remediation.md#measurement-gate)
records the approved workload and acceptance boundary: actor and CSV thread
placement, centering export, artwork normalization, revision-monitor fetch cost,
and first paint with roughly 1,500 synthetic cards. Use
`TradingCardScanner-ProfileLocal` on the oldest supported device. The local
device listing showed only offline iPhone/iPad devices, so no trace or measured
duration is available. Keep F9, artwork worker changes, and actor placement
changes gated on those results; simulator test timings cannot retire this item.

### RF-14 — November production refinement acceptance

**Status:** local implementation and final focused simulator verification complete;
broader target remains non-green; device and publication gates open —
2026-11-04, working tree based on `a404f67`.

This checkpoint owns the seven findings from the November whole-production
review and its approved conservative implementation plan. The October findings
with the same F-numbers in older documents are separate historical work.
Existing catalog authoring and Browse lifecycle/pagination changes are retained.

| Finding | Implemented behavior | Verification boundary |
| --- | --- | --- |
| Scanner save recovery | Each authorized write captures its storage continuation and original session. Late failure retains a distinct acquisition row; late success retires its exact source row without publishing into a replacement session. Only the affected recovery row is locked against retry/dismissal; Clear is disabled while any recovery write runs. | Delayed success/failure beyond the departure drain, replacement storage, persisted recovery, durable quantity, and replacement-session summary tests. Native saving state and available Back/other-row actions inspected on Simulator. |
| Artwork latency | Price-only requests skip artwork recovery. Catalog resolution applies signed artwork first. Bulk refresh recovers artwork only for accepted imports needing an image and preserves existing saved artwork when enrichment is absent. Existing Browse/normalization service defaults retain recovery. | Recorded transport tests prove no probes for price-only fetches or rejected identities, signed-artwork ordering, retained saved images, and imported-row backfill. No measured wall-clock speed claim. |
| Live historical Magic | The adapter owns exact family/candidate validation. Final provider acquisition validation runs before write exclusivity; local context checks remain at the retry boundary. | Scanner selection/save uses two family searches and one exact-card fetch, including a forced exclusive-write retry. Recovery's existing preparation lookup remains a separate validation; no prepared-result cache was added. |
| All Games set filtering | Selected sets constrain card games, status, results, resume, and pagination. Sealed lanes keep the original game scope. | Single-game and mixed-game filters, explicit-game switching with retained selections, and card/sealed pagination tests. |
| Unavailable completion checklist | Owned collector numbers remain visible with an unknown denominator. Available empty checklists still mean zero matched slots. | Unchanged-manifest retry test now expects ownership-only progress, then exact progress after restoration. Unknown fractions remain last in Most Complete. Normal catalog publication/reappearance can rebuild; no retry timer was added. |
| Slab's ungraded reference | The query uses the exact price key, including Magic treatment and Pokémon print run. Same-key duplicate authority selection is retained. | Real SwiftData queries exclude newer quotes for other treatments, omit missing exact references, preserve print-run separation, and exclude ineligible/raw rows. |
| Release links | Empty target overrides were removed from all five configurations. The existing production xcconfig now owns both empty URL settings. | Release build succeeds; built plist still has empty URLs. Owner-approved public pages, real URL configuration, built-app navigation, and submission metadata remain open under the [publication checks](../legal/README.md). The price-feed endpoint remains deliberately unconfigured. |

Pre-change baseline: 372 selected cases, 369 passed and three scanner cases
failed (24 assertion failures). The failing cases were
`testChooseCardFromGradedRowPreservesSlabAndPrintedPrintRun`,
`testClassicPhotoFootersOfferBothPrintingsBeforeFinishOrCollectionWrite`, and
`testHeldRepeatIdentityMismatchClearsAcknowledgementWithoutWriting`.
Do not treat these baseline failures as new findings or claim a green baseline.

Post-change focused checks: 61 passed, followed by 27 passed and three skipped
in the live-Magic/signed-artwork selection. Debug test build and generic Release
simulator build passed. One initial regression test caught saved artwork being
cleared by absent enrichment; the metadata application was corrected and that
test now passes. The final selection after follow-up changes executed 118 cases:
115 passed, three skipped, zero failed. The final generic Release simulator
rebuild also passed. The focused selection includes all 17 recovery-store tests,
the current-session stale-storage interval cleanup, the exact-row merge contract,
and all live Magic recognition/choice tests. Shared Magic discovery-family
validation is retained; removing it broke the multi-oracle title case during
verification and was reverted before the final green selection.

The broad run attempted 3,110 cases: **3,077 passed, 19 skipped, 14 failed**
(including one test-host crash), confirmed from the result bundle's metrics.
It preceded the final exact-row test update and interval cleanup; it is not a
green full-target result for the final tree. Failure disposition:

| Cases | Evidence / remaining limit |
| --- | --- |
| Three scanner cases listed above | Reproduced the pre-change failures. |
| Historical recovery merge expectation | Updated to identify the exact retry row; distinct failed acquisitions now have an explicit regression assertion. Passes in the final selection. |
| Jumbo variant expectation | Untouched static expected list omits `.jumbo`, which the unchanged production variant policy includes. Reproduces in isolation. |
| Three automatic-finish repair/price cases | Reproduce in isolation, including a direct call to unchanged finish-reconciliation logic. Fixtures/policy expectations need a separate reconciliation; do not weaken physical-review rules to make them pass. |
| Three keychain cases | Fail with `storeFailed(-34018)` in the unsigned simulator test host. No credential fallback was introduced. |
| Native centering field blur | Two-second blur deadline fails in both broad and isolated runs. The field implementation/test is untouched by these slices. |
| SwiftData notification characterization | Untouched expected keys omit the observed `historyTokens`; reproduces in isolation. |
| Duplicate recovery-record test host crash | One broad-run `SIGTRAP` has SwiftData/SwiftUI frames. The exact test and all 17 recovery-store tests pass in fresh runs. The cause is unproven; keep lifecycle/runtime acceptance open. |

Generated logs/results and synthetic screenshots are on the T7 SSD under
`ScanStash_Refinement_20261104`, outside the repository. Result bundles are
`Baseline.xcresult`, `FullSuite.xcresult`, `FinalRegression.xcresult`, and
`FailureIsolation.xcresult`. No full-target or release-readiness claim follows
from the green focused selection.

Additional centering source/plan edits arrived concurrently after the final
focused test binary was built. They are preserved and are outside this slice's
behavioral verification; centering failure evidence above describes the tested
binary, not those later edits.

The normal-size recovery list/detail were visually checked, including disabled
Clear, visible Saving status, available Back, and usable other-row actions.
The largest Dynamic Type message wraps without overlap; its existing native
large navigation title truncates, and row scrolling was not verified in that
capture. These observations are not physical-device or VoiceOver acceptance.

Keep RF-1/RF-2/RF-3/RF-8/RF-9/RF-12/RF-13 open. No new queue architecture,
persistent cache, background artwork worker, completion retry loop, schema
migration, or speculative performance optimization was introduced. Measure
remaining launch/OCR/projection/rendering work before changing it.

## Closed cleanup

`PortfolioHistoryMode` was removed because the product exposes one history
presentation: additive market movement. The range remains user-selectable;
performance factors remain internal replay data. `PortfolioEngine.cancelRecompute`
is intentionally retained because its cancellation test protects a real task
lifecycle path.
