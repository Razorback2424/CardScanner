# October refinement implementation plan

**Status:** slices A–I and C1 implemented and committed on `fix/october-review-boundaries`; final verification and centering triage in progress; live Release URLs remain an owner dependency — 2026-10-02.

Reviewed checkout: `fix/october-review-boundaries` at `55b2d40`, initially clean.
Scope: the ten findings, small centering cleanup, and measurement targets in
the supplied whole-codebase review. This document owns their disposition and
implementation sequence. Existing subsystem contracts and release ledgers
continue to own their requirements and acceptance evidence.

## Review conclusion

All ten numbered findings have supporting evidence in this checkout. Their
confidence boundaries differ: the listing-photo race has a demonstrable
ownership conflict but has not been reproduced against Photos; UI findings
combine current source with dated screenshots; portfolio duplication establishes
unnecessary requests, not measured latency. Release URLs are a configuration
dependency. Remaining centering failures require individual diagnosis rather
than a preselected numerical fix.

The [October remediation ledger](../audits/october-review-remediation.md)
records 1,743 tests, seven skipped, and 25 assertion failures across ten
centering cases against earlier tested binaries through `248a61d`. Those are
historical results, not a test run at `55b2d40`. No new build, XCTest run,
simulator capture, device profile, provider check, or Photos save was performed
during the initial review. Implementation evidence is recorded separately below
and in the ledger. No crash has been established by this review.

| Review finding | Disposition and current evidence | Priority / change risk |
| --- | --- | --- |
| 1. Warm-session collection prices | Valid. `StoreRevisionMonitor.refreshStalePricesIfNeeded` suppresses an unchanged target fingerprint; its observation identity has no foreground trigger. `ContentView` foreground work does not retry stale collection targets. | High / medium |
| 2. Centering confirmation bypass | Valid. Both manual edge setters assign `.legacyConfident` when an inner reference exists. `isDeclined` depends on confidence, and export checks it. One edge edit therefore approves both frames. | High / medium |
| 3. Detail contrast | Valid. `CollectionCardDetailView` uses a black backdrop and semantic body colors; only the navigation toolbar receives a dark scheme. No parent establishes dark content appearance. Dated light-appearance captures agree. | High / low |
| 4. Graded finish correction | Valid. The query limits added/restored activities to one before `latestGradedAcquisition` checks `remainingQuantity`. Undo resolves the newest activity while an older acquisition can survive. | High / low |
| 5. Listing-photo cleanup | Valid ownership defect. The sweep guard is view-scoped, while a save task can outlive that view. The sweep removes both entire roots and bypasses the save-directory exemption. Actual Photos timing remains unverified. | High / low–medium |
| 6. Unresolved-scan load failure | Valid. `load` conflates missing/read/decode failures with an empty list. Reload assigns the merged list, whose observer schedules `save`; the existing malformed-file test asserts only an empty result. | High / low–medium |
| 7. Browse detail freshness | Valid. `details(for:)` returns memory-cached content without an age check. Only the sort-price path evicts expired details. The original quote timestamp is preserved when adding; there is no demonstrated false timestamping. | High / low–medium |
| 8. Magic portfolio duplication | Valid. Migration precedes an awaited ownership replay, followed by another Magic replay. `magicCards` hashes quantity/treatment, so ordinary Magic additions can enter both paths. Sequential completed requests are not coalesced. | Medium / medium |
| 9. Collection accessibility layout | Valid. `quietLine` truncates finish and unavailable-price text beside price/quantity. The header fixes height to 44 and keeps a single-line scaled title beside two actions. Dated largest-text captures show crowding. | High / low |
| 10. Release privacy/support URLs | Valid. Release build settings are empty and Settings renders unavailable-link text. Actual hosted destinations have not been supplied or validated. | Submission dependency / low |

Source locations below are relative repository links; cited line numbers refer
to this reviewed checkout and will shift during implementation.

## Implementation checkpoint — 2026-10-02

The authorized implementation is local and uncommitted, based on `55b2d40`.
The disposition table above records the pre-fix findings; it is not a claim
that the implemented defects remain present.

| Slice | Implemented boundary | Verification / remaining acceptance |
| --- | --- | --- |
| A | The black detail content resolves semantic colors in a local dark environment. | Build; rendered checks pending. |
| B | Stored-field claim eligibility precedes the graded query's one-row limit, including legacy added and signed restored quantities. | Initial activity suite passed 29 tests; final persistent-store and correction/ledger regressions pending. |
| C | Edits remain pending; Confirm frames validates nested finite convex quads. Invalid subsequent geometry suppresses ratios and both export actions; new analysis clears approval. | Focused approval cases passed; final recovery/new-photo/rotation checks pending. Test helpers now explicitly confirm rather than using edit/warning-refresh approval. |
| D | Read failures preserve the file and runtime list. A store-owned load token blocks writes until the merged snapshot is saved; superseded queued saves are skipped. | Store preservation cases passed; final scanner read/write failure and successful-recovery regressions pending. |
| E | Static one-time preparation precedes both single and batch creation; reopening a view cannot sweep process-owned exports. | Export ownership/repeated-preparation cases passed. Real Photos/share and fresh-process orphan acceptance remain open. |
| F | Foreground return reconsiders existing per-target age eligibility, retaining the event through bulk writes or an active pass. Fresh targets do not start an empty pass. | Hosted monitor regression and lifecycle selection passed; final integration suite pending. No timer or forced unsupported retry added. |
| G | Direct detail requests expire positive quotes at 24 hours and missing/mixed quotes at six hours; failed refresh preserves stale content/time, including supplemental Pokémon quotes, and the detail displays retrieval time. | Direct Magic detail/coalescing/failure, supplemental offline retention/provenance, and shared-waiter cancellation checks pass 31 focused simulator tests; remaining acceptance cases below stay open. |
| H | An awaited baseline replay covers the same Magic change; the redundant later replay is skipped. | Hosted Magic quantity-change regression passed with exactly one recomputation; final portfolio suite pending. No speed claim. |
| I | Header actions wrap onto a second row when needed; accessibility tile footers wrap essential price/finish text. | Build; rendered checks pending. |
| J | No placeholder destination was enabled in Release. | Owner confirmed that `https://scan-stash.com/privacy` and `https://scan-stash.com/support` are intended future pages, not live approved destinations. Hosting, contact/content verification, Release configuration, and link acceptance remain open. |
| K / C1 | Removed the permanently nil inner-presentation branch. Fixed the reproduced preview transform so photo and guides rotate together, matching export. | Final invariant/export/profile triage pending. Automatic detector gates and numerical tolerances remain unchanged; the sealed holdout is not used for debugging. |

The 2026-10-02 follow-up review reproduced an expired Pokémon detail losing its
cached $28.98 Holofoil quote when both providers failed. The fix retains the
original detail when supplemental refresh fails; successful snapshots, including
missing quotes, remain authoritative. The permanent regression covers fresh and
expired cached details, retrieval time, quote provenance, and replacement by a
successful missing quote. On the uncommitted working tree based on `55b2d40`,
`PokemonTCGCSVPriceTests` and `BrowseLoadingRefinementTests` pass 30 tests, followed
by one passing `PokemonChecklistBrowseTests.testCancellingOneSharedDetailWaiterDoesNotCancelTheOther`
case using `test-without-building`. Exact commands and results are saved as
`OfflineSupplementFix-20261002.log` / `.xcresult` and
`OfflineSupplementWaiter-20261002.log` / `.xcresult` under the external SSD's
`CodexBuilds/TradingCardScannerRefinement` directory.
This focused evidence does not replace the full-suite or device/provider gates.

The initial 157-test focused selection passed 156 cases. Its one scanner
write-failure fixture could fail during reading under the new preservation
contract; that fixture now explicitly exercises missing-file initialization
followed by a write failure, with a separate corrupt-file/runtime-recovery
regression. `CenteringAndRecovery` was intentionally interrupted after additional
source/test changes; its partial output is not a completed suite result.
`FullFinal` verifies the consolidated implementation. Artifacts and caches use
the external SSD; the earlier MCP-created test-product copy was moved there too.

An attempted external-drive iPad simulator failed when CoreSimulator could not
copy its sample content (permission error). Internal space is insufficient for
another simulator; no existing user simulator is erased to make room. Device,
live-provider, accessibility-assistive-technology, and real Photos acceptance
remain distinct from deterministic simulator tests.

## Implementation constraints

- Use one focused slice at a time. Preserve existing user work, and inspect
  status/diffs before editing. No broad rewrite, file splitting, dependency
  addition, database migration, or general resource/cache framework is warranted.
- Retain exact identity, print-run, finish/treatment, grade/certificate, price
  provenance, ledger lineage, serialized fresh-context writes, and storage
  generation fences. Preserve native navigation, sharing, and Photos behavior.
- Prefer existing test clocks, provider fakes, gates, and computation hooks.
  Add only a narrow seam when an essential regression cannot otherwise be tested.
  Test the user-visible contract, including integration wiring, not merely a
  helper that mirrors its implementation.
- Do not relax numerical tolerances, label a failed suite as passing, evaluate
  the sealed centering holdout for ordinary debugging, or change recognition
  thresholds/capture quality to make these fixes easier.
- Preserve normal-size UI density. Make the narrow local appearance/layout
  change and verify the rendered result instead of redesigning Collection.

## Ordered implementation slices

### A. Make detail appearance coherent — finding 3

**Files:** [CollectionCardDetailView.swift](../../TradingCardScanner/Views/CollectionCardDetailView.swift),
body around line 164 and `AppCardDetailBackdrop` around line 1593.

Apply a dark `colorScheme` environment to the existing intentionally black
detail surface so semantic text, material, and system-background fills resolve
consistently. Keep the existing dark navigation chrome. Scope the environment
to this destination; verify propagation to its sheets and printing details.
Use an adaptive backdrop only if rendered verification shows a local dark
environment cannot preserve those surfaces coherently. Do not recolor every
text element or force the entire application into dark appearance.

**Acceptance:** capture raw, graded, sealed, unpriced, and long-title details
from both Collection and Portfolio in light/dark system appearance on compact
iPhone and iPad. Inspect default/largest text, Increase Contrast, and Reduce
Transparency; verify navigation and returning to the parent appearance.
No new unit test is needed for a single appearance modifier; build and rendered
inspection are the meaningful checks. Risk: presentation appearance leakage.

### B. Select the newest eligible graded acquisition — finding 4

**Files:** [CollectionCardDetailView.swift](../../TradingCardScanner/Views/CollectionCardDetailView.swift),
query around line 123 and selection around line 635;
[CollectionActivity.swift](../../TradingCardScanner/Models/CollectionActivity.swift),
`signedQuantity`, `claimedQuantity`, and `remainingQuantity`;
[CollectionActivityHistoryTests.swift](../../TradingCardScannerTests/CollectionActivityHistoryTests.swift).

Keep the collection-key, graded-kind, and added/restored restrictions, newest
first. Apply remaining-claim eligibility before `fetchLimit = 1`. Translate the
existing persisted quantity semantics faithfully: nonzero deltas use absolute
quantity; zero-delta **added** rows fall back to legacy `quantity`, while
zero-delta restored rows have no claim. Do not use a computed model property
inside a SwiftData predicate or assume `deltaQuantity > resolvedQuantity`
handles legacy rows.

Prefer a supported stored-field predicate with the same semantics. If SwiftData
cannot express it reliably, remove only this graded query's limit and use the
existing `remainingQuantity` selection over matching acquisitions; do not add
a schema field or materialized eligibility index. Choose after compiling and
testing the actual predicate against a persistent store. Keep raw/sealed
queries disabled and keep correction's transactional store preflight.

**Acceptance:** two matching uncertified slabs, undo newest, then correct finish
through the surviving acquisition. Cover partially consumed, restored, legacy
zero-delta added, fully resolved, and unrelated-key/kind activities. Assert
quantities and ledger lineage as well as action visibility. Risk: legacy
quantity disagreement or an unsupported query translation.

### C. Make centering approval explicit — finding 2

**Files:** [CardCenteringMeasurement.swift](../../TradingCardScanner/Models/CardCenteringMeasurement.swift),
eligibility around line 706 and setters around line 821;
[CardCenteringView.swift](../../TradingCardScanner/Views/CardCenteringView.swift),
update methods around line 150 and export around line 224;
[OpusImplementationPlanTests.swift](../../TradingCardScannerTests/OpusImplementationPlanTests.swift),
`testREQ045AutomaticInnerCandidateRequiresConfirmationBeforeRatio`;
[CenteringExportTests.swift](../../TradingCardScannerTests/CenteringExportTests.swift).

Add one explicit model transition and a clearly labeled **Confirm frames**
action beside the existing outer/inner guide controls. It accepts the currently
reviewed pair without requiring an arbitrary edit. Guide edits and
`refreshWarnings()` must not convert pending automatic geometry into approval.
Reuse the existing confidence state; independent per-edge approval flags and
a new persisted state machine are unnecessary.

The model transition validates usable geometry before approval. Use the same
geometry eligibility for displayed ratios and export: an inner reference must
exist, coordinates/borders must be finite and valid, and the inner guides must
lie inside a usable outer frame. Validate actual quad geometry when quads are
in use, not just their bounding-box projections. Detection notes can remain
informative and must not be treated as a universal veto on manually corrected
geometry. Keep declined-image recovery through manual outer/inner placement.

Preserve live ratio updates after a valid confirmation, while invalid subsequent
edits suppress reportable ratios/export. New photo/analysis results reset to
their own pending or declined state; confirmation cannot carry across images.
Keep rotation as the existing display adjustment and keep export generation
keyed to measurement/image/rotation, so old files cannot remain shareable while
current geometry is ineligible.

**Contract reconciliation:** the current REQ-045 test expects the gate to stay
closed after both setters and then open after `refreshWarnings()`. The view
calls that method on every edit, so this is not an explicit user action.
Update both that test and the synthetic automatic-confirmation export test to
invoke the new explicit transition; retain assertions that arbitrary edits and
warning refreshes cannot approve detector candidates. This makes the test agree
with the existing [hybrid confirmation contract](../../review/opus-card-centering-implementation-plan.md),
particularly its binding boundary and hybrid DoD. It does not waive accuracy
or rendering requirements.

**Acceptance:** outer-only edit, inner-only edit, both edits, warning refresh,
valid confirmation without edits, invalid/missing-inner geometry, recovery from
a declined image, valid edits after confirmation, invalid edits after
confirmation, another photo, stale analysis completion, rotation, and export
eligibility. Use injected geometry for approval/arithmetic tests, plus the
existing production-fixture confirmation selector. Render the full manual
interaction and inspect VoiceOver/Dynamic Type. Risk: accidentally preventing
manual recovery or restoring the premature approval path elsewhere.

### D. Preserve unresolved evidence after a failed load — finding 6

**Files:** [UnresolvedScanStore.swift](../../TradingCardScanner/Services/UnresolvedScanStore.swift),
`load` around line 25 and `save`;
[ScannerViewModel.swift](../../TradingCardScanner/Views/ScannerViewModel.swift),
observer around line 1424 and reload/save around line 2084;
[UnresolvedScanStoreTests.swift](../../TradingCardScannerTests/UnresolvedScanStoreTests.swift) and
[ScannerViewModelTests.swift](../../TradingCardScannerTests/ScannerViewModelTests.swift).

Return an explicit missing/loaded/failed result (or equivalent typed result).
Treat only an actual file-not-found error as initialization; a permission,
protection, read, or decoding error must remain a failure. Preserve original
bytes in place. Keep a store-owned write gate after failure, so direct saves
and already queued runtime saves cannot replace the unreadable recovery file.
Ensure a save before the initial load cannot overwrite an unexamined existing
file; establish load state before enabling writes or make the store enforce it.

On failure, leave the in-memory list actionable and use the existing problem
note surface to explain that earlier Needs attention work could not be loaded
and new changes are not durable. Retry through existing reload entry points;
clear the gate only after a successful read/merge or verified missing-file
initialization. Preserve revision checks, ordered save tasks, unsupported-set
read-only records, and additional-copy markers. A general backup service or
an automatic destructive reset is outside this fix.

**Acceptance:** missing file and valid round trip; malformed/truncated JSON;
deterministically injected read failure; reload with empty and nonempty runtime
lists; add/remove/dismiss while blocked; save queued before load; successful
retry merges runtime work and resumes persistence. Assert original bytes remain
identical until recovery succeeds. Replace the test that considers corrupt
content equivalent to an empty store with preservation assertions. Risk:
losing runtime work during retry or leaving persistence disabled after recovery.

### E. Sweep export leftovers once before any process-owned run — finding 5

**Files:** [EbayListingPhotoExport.swift](../../TradingCardScanner/Services/EbayListingPhotoExport.swift),
sweep around line 247, `RunDirectoryStore`, and `makeBatchDirectory`;
[EbayListingPhotosView.swift](../../TradingCardScanner/Views/EbayListingPhotosView.swift),
`onAppear` around line 178, Photos save around line 523;
[EbayQuadrantCropperTests.swift](../../TradingCardScannerTests/EbayQuadrantCropperTests.swift),
which also contains `EbayListingPhotoExportTests`.

Move sweep ownership out of view `@State` into one process-scoped,
thread-safe initialization boundary. A Swift static initialization can provide
the one-time guard without a new manager. Invoke that boundary **before both
single-run and batch-directory creation**, including direct exporter callers,
then remove the view sweep/guard. Guarding only first `onAppear` is insufficient
if a worker creates a directory first; guarding only `RunDirectoryStore` misses
batch creation. Never expose an unguarded repeated whole-root sweep to a view.

Retain UUID run containers, per-run cancellation/failure cleanup, the active
Photos directory exemption, and deferred cleanup after save completion. Do not
cancel Photos work solely because navigation disappears or change JPEG output.

**Acceptance:** seed crash leftovers in isolated test roots, initialize once,
create active single and batch outputs, then repeat preparation and simulated
view reopen; active files survive. Stall a fake Photos saver across dismissal
and reopen; completion/failure releases only its owned directory. Test
concurrent preparation and a fresh process/bootstrap using isolated roots,
without resetting the production singleton around live work. Then exercise
real Photos/share/inspection interaction. Risk: initialization ordering; no
actual Photos race reproduction is claimed yet.

### F. Reconsider stale collection prices on foreground return — finding 1

**Files:** [StoreRevisionMonitor.swift](../../TradingCardScanner/Services/StoreRevisionMonitor.swift),
observation around line 396 and refresh gate around line 698;
[ContentView.swift](../../TradingCardScanner/Views/ContentView.swift), scene work around line 283;
[PriceRefreshController.swift](../../TradingCardScanner/Services/PriceRefreshController.swift),
`staleTargets` around line 2946;
[StoreRevisionMonitorTests.swift](../../TradingCardScannerTests/StoreRevisionMonitorTests.swift),
[PriceRefreshLifecycleTests.swift](../../TradingCardScannerTests/PriceRefreshLifecycleTests.swift),
[PricingTests.swift](../../TradingCardScannerTests/PricingTests.swift), and
[ProductFallbackTests.swift](../../TradingCardScannerTests/ProductFallbackTests.swift).

Add one explicit foreground-active eligibility event through the existing
monitor/controller path. Foreground return is sufficient for the reported
return-to-app gap; do not add both tab-entry and foreground triggers unless
there is a separately reproduced need. A continuously active app that never
returns to foreground is outside this event-based guarantee.

The lifecycle event must reach eligibility even when durable fingerprints are
unchanged: merely adding `scenePhase` to the observation identity still leaves
both the unchanged `apply` branches and target-fingerprint guard to address.
Bypass fingerprint-only suppression for this eligibility event, without setting
`forceUnsupportedRetry`. Keep ordinary mutation-trigger coalescing. Use the
existing per-target `staleTargets(now:)` decision; avoid a global eight-hour
time bucket that can refresh early or delay a due row.

Preserve storage readiness/generation, bulk-write deferral, migration/refresh
serialization, active-pass sharing, provider pacing/budgets, and controller
terminal replay ownership. If a foreground event arrives while writes suppress
eligibility, retain it until the existing coordinator resumes. No polling task,
new scheduler, or cancellation on a routine tab switch is required.

**Acceptance:** unchanged collection, first refresh, advance clock just below
and beyond eight hours, background/foreground without background delivery.
Assert one eligible provider pass beyond expiry and no provider calls inside
the interval. Cover rapid transitions, in-flight sharing, background-owned
work, new/imported targets, bulk writes, storage replacement, failed target
build retry, and price writes that must not feed back into another pass.
Keep weekly fallback/graded-coverage and 30-day unsupported cooldowns; verify
fallback-off and explicit manual retry behavior. Risk: metered request loops.

### G. Expire Browse details where they are requested — finding 7

**Files:** [BrowseCatalog.swift](../../TradingCardScanner/Services/BrowseCatalog.swift),
`details(for:)` around line 866 and sort-price invalidation around line 1084;
[BrowseCatalogModels.swift](../../TradingCardScanner/Models/BrowseCatalogModels.swift),
`CatalogCardDetails.retrievedAt`;
[CatalogCardDetailView.swift](../../TradingCardScanner/Views/CatalogCardDetailView.swift),
price presentation around line 207;
[BrowseFeatureTests.swift](../../TradingCardScannerTests/BrowseFeatureTests.swift).

Apply a small shared age-policy helper at the detail entry point using existing
Browse conventions: 24 hours for a positive quote and six hours for a checked
missing quote. For a shared response containing positive and missing finishes,
use the earliest applicable expiry so a quoted finish cannot freeze its missing
sibling. Test that policy against the supported market-price rows rather than
assuming a nonempty array means a USD quote exists.

Fresh cache hits retain their current fast path. Stale requests join the
existing detail task/waiter machinery; retain the stale cached object while
refetching and replace it only on success. On provider failure return useful
stale content with its original timestamp and a visible retrieval-age caption.
Propagate caller cancellation rather than converting it into stale success.
Keep the existing supplemental Pokémon source's independent provenance and
cache policy; a supplement must not restamp the underlying provider quote.

Preserve cache keys, exact finish/print-run authority, catalog invalidation and
memory-pressure behavior. Reuse provider pacing/backoff; add only a small
failure-retry guard if counted requests demonstrate rapid offline retries.
Do not add a second cache, persist Browse into the collection database, invent
a source update time, or require continuous updates to an already-open detail.

**Acceptance:** Magic search directly to detail, advance clock, change response,
reopen without sort-price loading. Cover fresh/expired positive, negative and
mixed-finish results; offline stale retention/retry; adding stale content keeps
its original timestamp; Pokémon supplement behavior; concurrent callers;
cancelling one/all waiters; memory purge and catalog invalidation during a fetch.
Retain `testCancellingOneSharedDetailWaiterDoesNotCancelTheOther`. Risk: request
amplification or overwriting a newer result after actor suspension.

### H. Remove only the redundant Magic portfolio replay — finding 8

**Files:** [StoreRevisionMonitor.swift](../../TradingCardScanner/Services/StoreRevisionMonitor.swift),
`apply` around line 553;
[PortfolioEngine.swift](../../TradingCardScanner/Services/PortfolioEngine.swift),
`recomputeAndWait`, coalescing, and price-refresh replay gate;
[PortfolioReconciliationTests.swift](../../TradingCardScannerTests/PortfolioReconciliationTests.swift) and
[PriceRefreshLifecycleTests.swift](../../TradingCardScannerTests/PriceRefreshLifecycleTests.swift).

Use one local record of a completed baseline replay within `apply`, or combine
equivalent replay conditions before the stale-price call. When that replay has
already incorporated the post-migration Magic inputs, omit the later
`magicChanged` replay for the same observation. Keep migration before baseline
valuation, and retain the Magic-only path when no earlier branch covered it.

An active price pass continues to own the trailing replay. Do not remove the
controller's terminal replay, including its existing empty-pass behavior, or
globally suppress new work because a prior apply computed once. Recheck
generation/storage fences after suspension; genuinely newer input still needs
its existing follow-up observation/replay.

**Acceptance:** count actual computation starts using existing
`PortfolioEngine.computationProvider`/signposts for Magic addition, correction,
import, migration, Magic-only changes, empty price pass, price-changing pass,
and inventory changes during a pass. Remove the extra monitor replay, while
retaining the baseline plus controller-owned terminal work when required.
Assert identical quantities, totals, unpriced coverage, daily history, and
ledger attribution. Measure latency only after count/equivalence tests pass.
Risk: skipping a necessary post-migration or terminal replay.

### I. Finish accessibility layout adaptation — finding 9

**Files:** [CollectionView.swift](../../TradingCardScanner/Views/CollectionView.swift),
`collectionNavigationHeader` around line 402 and `quietLine` around line 1639;
existing `CollectionTilesLongContent` debug route and screenshot scripts.

At accessibility sizes, put the full finish/status label on a separate wrapping
line from price and quantity, and let unavailable-price explanations wrap.
Keep the existing combined VoiceOver label, colors, dot, and normal-size row.
Adapt the custom header with content-driven height and a stacked arrangement
only when the title/actions cannot fit; preserve both labeled 44-point actions
and their destinations. Do not shrink Dynamic Type or hide actions in a new
menu simply to fit the current fixed-height header.

**Acceptance:** compact widths and iPad; normal and all accessibility sizes;
long treatment/finish labels, large quantities, quoted/unavailable prices,
light/dark appearance, VoiceOver order and full status. Retain ordinary-size
density and existing search/filter adaptation. Build and rendered interaction
are sufficient; do not add brittle source-text/layout-mirroring tests.
Risk: grid height/focus/navigation regression.

### J. Supply real Release destinations — finding 10

**Files:** [project.pbxproj](../../TradingCardScanner.xcodeproj/project.pbxproj),
Release settings around lines 1352–1353;
[CardScannerExternalLinks.swift](../../TradingCardScanner/Services/CardScannerExternalLinks.swift);
[PrivacyAndSupportSurfaceTests.swift](../../TradingCardScannerTests/PrivacyAndSupportSurfaceTests.swift);
[privacy policy](../legal/privacy-policy.md) and [support copy](../legal/support.md).

Configure owner-approved hosted HTTPS destinations at exact `/privacy` and
`/support` paths accepted by the current validator. Keep unavailable-link
fallbacks for genuinely unconfigured development builds. Do not loosen the
validator, invent a domain/contact channel, or deploy a new website as part of
this iOS fix. Website work has its own
[specification](../CardScanner-Website-Implementation-Spec.md).

**Acceptance:** inspect resolved build settings and built Release `Info.plist`,
open both links from the app, and verify hosted content, effective date, working
contact mechanism, and matching App Store Connect metadata. Extend existing
configuration tests only where missing; validate actual pages separately.
Dependency: approved live URLs/contact details; absent from this review.

### K. Triage the remaining centering failures before further fixes

**Authority:** [centering implementation/validation contract](../../review/opus-card-centering-implementation-plan.md),
[centering evidence](../../review/centering-evidence/README.md), and
[recorded failure groups](../audits/october-review-remediation.md).

After slice C, rerun the affected confirmation selectors, then the recorded
invariant/export/profile selectors against one known build. Record each failing
assertion, actual/expected result, whether it concerns hybrid or automatic
behavior, fixture/ground-truth authority, and the smallest responsible layer.
Separate geometry/ratio arithmetic, presentation/export mapping, detector
reference selection, diagnostic expectations, and latency.

Use injected known geometry to isolate arithmetic/rendering from detector
selection. Repair only reproduced production defects, one independently
verified change per root cause. If a test applies an obsolete reporting contract,
reconcile it explicitly with the adopted hybrid boundary while preserving the
automatic detector requirements and their open status. Do not make a blanket
ratio, threshold, coordinate, fixture, or tolerance change from failure counts.
Profile-dump failures require checking their assertions; their names alone do
not make them disposable diagnostics. Simulator latency assertions are recorded
as such and do not establish physical-device responsiveness.

**Optional cleanup C1:** `presentationProfileResult` in
[CardCenteringAnalyzer.swift](../../TradingCardScanner/Services/CardCenteringAnalyzer.swift)
around line 1092 is always `nil`. Remove that local and unreachable branch,
directly map the selected inner quad and retain `detectedInnerSupport`. Keep
this separate from numerical changes; check equivalent quads, confidence,
ratios, and exports for rotated/unrotated injected geometry. It is maintenance
cleanup, not a release blocker or claimed speed improvement.

## Measurement-only backlog

These targets are credible but do not yet justify production optimization.
Keep them under the existing [release follow-ups](release_followups.md) and
[October measurement gate](../audits/october-review-remediation.md).

| Target | Establish before changing implementation |
| --- | --- |
| Centering export preparation | Measure large-photo guide-step latency and main-thread render/PNG/write cost with and without Share. Only a material hitch justifies on-demand preparation; preserve native share behavior and stale-export fencing. |
| Model-actor executor placement | Capture real stacks for actors created from main-actor workflows. Serialization does not prove executor placement; do not scatter detached tasks or replace write ownership speculatively. |
| Revision/projection work and portfolio | Synthetic approximately 1,500-holding collection plus realistic ledger/history. Measure cold launch, scan-session exit, import settle, computation/read counts, main-thread stalls, and memory. Count reduction in slice H is established separately from speed. |
| CSV export and historical-price reads | Measure tap-to-exporter latency, fetch duration, history growth, and peak memory. Only then consider immutable preparation or bounded reads; avoid a new schema/cache first. |
| Camera/OCR and finish effects | Supported physical hardware, glare/dim light, rapid cards, long sessions, lifecycle transitions, and scrolling. Retain recognition policy absent representative device evidence. |
| Listing-photo processing | Native-resolution images and meaningful batch sizes; peak memory during workers, inspection, share, Photos save, and navigation. Preserve output quality absent a measured need. |

Compare identical workloads before/after with commit, device/OS, build
configuration, input sizes, repetitions, operation counts, elapsed time,
main-thread stalls, peak memory, and final values. A faster but differently
valued or identified collection fails acceptance.

## Scoped HIG and submission disposition

The scoped HIG pass identifies detail legibility and accessibility-size
Collection layout as **Major / Advisory / High confidence** issues. Centering
approval and lost correction/recovery workflows also materially affect clarity
and trust; their source evidence is high confidence, with export save timing
remaining an explicit runtime limit. Follow
[Apple's accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility)
when verifying rendered text and interactions.

The subsequent submission pass identifies missing privacy/support destinations
as **Major / Reject Risk / High confidence** for the checked-in Release
configuration. Apple's privacy guideline requires an accessible policy link in
the app and App Store Connect; its developer-information guideline calls for a
working contact route in the app and Support URL. These are scoped readiness
risks, not a prediction of an actual rejection.
[Privacy requirement](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage),
[support requirement](https://developer.apple.com/app-store/review/guidelines/#developer-information).

Fix-first order is A–G for concrete reliability/accuracy/legibility, then H–I.
Start the owner-controlled URL dependency J in parallel with that work if inputs
are available. Run K after C before deciding further centering changes. This
sequence does not reduce J's submission priority or reopen prior fixed defects.

Scoped release blockers: frame approval must not expose unconfirmed/invalid
results; recovery persistence must preserve unreadable existing files; Photos
ownership must survive reopen; price-return behavior, graded correction, and
core legibility must meet their acceptance cases; submission URLs must be live.
Unresolved centering accuracy/rendering and existing device/provider/storage
gates retain their original release authority. This is not a full App Store,
privacy-manifest, payments, account, or CloudKit re-audit.

## Verification and handoff

1. For each code slice, run the narrowest applicable `xcodebuild` build/test
   selection on a disposable simulator with synthetic fixtures. Use the external
   SSD for DerivedData, packages, compiler caches, and results when available.
   Record exact commands, commit/build identity, selection, and actual outcome.
2. For slices A/C/I, inspect real rendered screens and native interactions;
   source review or a compilation cannot retire visual/VoiceOver acceptance.
   For E/J, complete real Photos/hosted-page checks when the required runtime
   and destinations are available.
3. After C/K, run the complete relevant centering classes. After the integrated
   persistence/lifecycle/portfolio changes, run the full app test suite once.
   Report known and newly introduced failures separately, without treating
   preexisting failures as acceptance of regressions.
4. Record implementation and evidence in the appropriate subsystem plan and
   October ledger, with a dated `progress.md` entry. Update this plan's
   dispositions only when backed by current evidence. Validate changed Markdown
   links and run `git diff --check` for documentation changes.

Open evidence/input dependencies: fresh centering failure reproduction; native
Photos consumption timing; current light/largest-text captures and VoiceOver;
approved live privacy/support URLs and contact details; representative physical
hardware/performance traces. None is silently considered complete by this plan.
