# Audited Yu-Gi-Oh! implementation evidence — 2026-10-21

**Candidate evidence captured 2026-10-21:** implementation based on
`402c7655be3ad94b08986d9d1b41d9b8774db2f0`; the source checkout was clean before
the candidate changes. No deployment, physical-device installation or
owner-data reset was part of this verification.
The [canonical plan](../../plans/yugioh_code_implementation.md) is the current
contract. Earlier verification/review-fix totals remain historical.

## Generic iPhone 17 interactive acceptance — 2026-10-21

**Follow-up on base `09c4a40`, preserving the concurrent residual F3/F4 changes
below.** At the owner's direction, interaction used the generic iPhone 17,
iOS 27.0, with isolated `YuGiOhAcceptance` collection/recovery storage and
fixture OCR. No physical camera input was used. Native accessibility actions
worked on this device. This supersedes the older QA-device input blocker for
the rendered paths recorded here, not every outstanding acceptance gate.

The no-camera preview lacked the geometry fallback needed by this route;
adding it restored the readable, tappable picker and separated its footer from
the snapshot notice. Optional code-based initial samples and a readiness marker
make `ui_build_and_shoot.sh` wait for an actual recognition outcome. Browse and
collection detail now disclose that Yu-Gi-Oh market history is unavailable;
collection detail skips the unsupported history request. Other games retain
their history controls.

| Executed interaction | Observed outcome |
|---|---|
| LOB-001, product 21792 | Explicit First Edition saved; listing-only price stayed unavailable. History correction to Unlimited showed the exact historical $125.98 quote. Delete and Undo restored ownership. |
| DCR-EN000 | Discovery product 476802 remained visible, disabled and explained in both the live picker and Needs attention detail. Supported 487277 required explicit Unlimited and saved at $7.93. Same-session reinjection reported already added. Cancellation retained recovery; reopening and choosing the supported sibling saved and removed that recovery entry. |
| RA02-EN001 | Fourteen labeled printing options preserved distinctions. Cancellation/recovery selected alternate-art Platinum Secret Rare product 550852, then explicit First Edition saved at $0.57. |
| IOC-SE1 | Product 26366 saved Limited Edition at $2.16 with Printed label provenance from fixture text. |
| MRL-E104 | Product 229392 required explicit First Edition and saved at $4.95. |
| LOB-EN001 | Reissue families stayed distinct; Worldwide English product 476160 required explicit Unlimited and saved at $60. |
| LOB-999 | Visible no-match diagnostic explicitly said no card was identified or added; saved count did not increase. |
| Browse Add | HA07-EN001 product 68033 required First Edition; returning to Browse showed Owned 1. |
| Reopen and quantity | All seven distinct holdings survived reinstall-with-data-preservation/relaunch. Gem-Knight quantity changed 1 → 2 → 1 with matching value changes. Detail retained the October 20 source/check date and displayed the history limitation. |

These are historical bundled quotes, not current provider checks. Before the
final recovery retry, the seven holdings were each quantity one, total $202.04.
The final DCR recovery retry added one further copy, then confirmed Undo Scan
removed that session addition; native stale-generation
and forged-action coverage remains the regression evidence below, rather than
a claim of visually exercising a concurrent catalog race.

Final app build succeeded. The affected Yu-Gi-Oh selection executed **54 tests,
zero failures**; the separate history/rotation/framing neighbor selection
executed **37 tests, zero failures**. These are overlapping follow-up selections
relative to earlier gates and must not be summed with them. Result bundles in
the external SSD's `CardScannerBuilds/yugioh/DerivedData/Logs/Test/`:
`Test-TradingCardScanner-2026.10.21_10-30-32--0600.xcresult` and
`Test-TradingCardScanner-2026.10.21_10-33-19--0600.xcresult`.
Screenshots, route metadata and readiness proof are retained outside the repo
under `CardScannerBuilds/yugioh/interactive-2026-10-21/`, including
`ui-latest.png`, `dcr-recovery-disabled.jpg`, `collection-reopened.jpg` and
`quantity-edit-and-history-limit.jpg`.

**Still pending:** Export CSV reached the system Files save sheet. Native UI
capture exposed only the underlying app, and browser-mirror HID clicks did not
activate Save. No completed exported file or interactive import is claimed.
CSV persistence/round-trip native tests remain separate evidence. Full B1
acceptance, physical camera, live signed production delivery, provider/image
permissions, CloudKit and release gates remain open. Deployment, personal-device
installation, owner-data reset and Journey interaction were outside this
acceptance run.

## Residual F3/F4 corrective pass after `09c4a40`

**2026-10-21; base `09c4a40de141c3ba8e0e123ed2bec409be3e185e`.** The
checkout was clean at start. The subsequent review identified three residual
paths; the earlier F3/F4 closure wording below describes only the paths tested
then. This pass preserves the seed, acquisition/verifier protections and F1/F2/F5/F6
behavior; F7 remains a recognition diagnostic, not physical-camera acceptance.

1. **Durable duplicate maintenance:** `CollectionStore` previously compared
   each physical row's quantity with a logical-key ledger delta. It now reads
   the durable contributing IDs, verifies the complete surviving/deleted row
   set and identities, and compares bounded logical quantities with that delta.
   Restore still requires an exact, unreversed durable disposal and snapshot;
   the destination of a correction still requires current acquisition authority.
   `testDurableDuplicateRemovalRollbackRetryReopenAndExactRestore` persists two
   quantity-1 rows, induces save failure, verifies both IDs/quantities and the
   original ledger/history, retries removal, reopens and checks ownership,
   disposal/history/snapshot agreement, rejects an inserted second restore row
   sharing one disposal inverse, rolls back, restores and rejects repeated restore.
   `testRetiredDuplicateReductionConservesLedgerAndRejectsIncrease` covers
   consolidation/reduction/reopen and rejects increases. The strengthened
   `testDurableEditionCorrectionAfterCoverageBecomesUnknownAtFinalSave` begins
   with separate durable rows, preserves quantities through supported correction,
   checks exactly two correction legs and one correction activity, and rejects
   forged inserts, unsupported destinations, additions/imports/increases while
   a supported sibling keeps collection writes available.
2. **Delete Entire Collection:** its preflight now uses maintenance eligibility;
   final ownership/ledger validation and confirmation behavior remain in place.
   `testMixedBrowseOnlyDuplicateDeleteAllCancellationFailureAndReopen` uses only
   an isolated mixed Pokémon/Yu-Gi-Oh store, including durable duplicate rows.
   It checks cancellation before and during staging, induced failure/rollback,
   preservation of physical IDs and ledger, one successful save for both games,
   and reopened per-position disposal history/snapshots and zero ownership.
3. **Needs attention:** compact printing controls now disable known-unavailable
   choices and expose the retained reason/VoiceOver hint. `ScannerViewModel`
   guards direct actions and the parent dismissal callback; the detail view
   checks current catalog authority before dismissal, including legacy missing
   availability metadata. Failure keeps the item/family and an explanation with
   another-choice/retry path; cancellation prevents the dismissal callback.
   `testDCRRecoveryAvailabilityReloadLegacyAuthorityAndDirectActions` covers real
   DCR-EN000 live choice → dismiss → compact eligibility/reason → rejected
   discovery product 476802 → persisted legacy reload → current-authority and
   direct-call rejection → stale authority → cancellation → supported 487277
   Unlimited selection, with exactly one ownership event. The existing stale
   live-picker and English/cross-game regressions remain in the affected gate.

Executed: builder **29 passed** unchanged; focused native selections
**5 passed** each before/after durable-baseline refinements (overlapping, not
additive); affected native gate **318 passed, zero failures/skips**, including
Yu-Gi-Oh catalog/resolution/recognition/workflow/import/pricing/delivery, scanner,
recovery storage, collection history/continuity, CSV resume, normalization,
variant resolution and Magic historical recovery. App/test targets compiled.
Neighbor native gate **196 passed, zero failures/skips**, including Yu-Gi-Oh
workflows/recovery, supplemental recognition registry, collection
history/continuity, Lorcana ownership and One Piece integration. Its bundle is
`Test-TradingCardScanner-2026.10.21_10-15-24--0600.xcresult`; its invocation log
is `logs/residual-final-neighbors.log`. It overlaps the 318 and is not additive.
The final five-test selection **passed all 5, zero failures/skips**, including
the inserted second-restore-row rejection, rollback/retry and repeated-restore
history invariance. This rebuilt the final app/test targets after the last
authority refinement. Bundle:
`Test-TradingCardScanner-2026.10.21_10-18-57--0600.xcresult`; invocation log:
`logs/residual-restore-final.log`. These five overlap both earlier gates and
are not additive. Build-only work is not test execution. The 318-test bundle is
`Test-TradingCardScanner-2026.10.21_10-12-28--0600.xcresult` in
`DerivedData/Logs/Test/`. Raw invocation logs are `logs/residual-focused.log`,
`logs/residual-focused-final.log` and `logs/residual-affected.log`.
Generated artifacts use the existing external SSD under
`CardScannerBuilds/yugioh/`; native tests use a newly created dedicated
`YuGiOh Integration QA` device because the documented device was absent.
No owner files, normal collection/recovery resets, personal devices or Journey
work were used. Concurrent acceptance-route edits in `CameraPreview.swift`,
`YuGiOhGameRuntime.swift`, `ScannerView.swift` and `ui_build_and_shoot.sh` are
preserved separately from these fixes.

**Interactive attempt, approximately 10:20 MDT:** the dedicated QA device booted
and native tests executed successfully. The first debugger launch used the wrong
argument field; it was corrected to `launchArgs` with
`-ui_debug_route YuGiOhAcceptance -ui_debug_state DCR-EN000`. A system camera
permission alert from the initial ordinary launch remained visible. The debugger
reported a successful tap on **Don't Allow** (element `e135`, x=127, y=571), but
the following snapshot still exposed only the same **Don't Allow / Allow**
controls; a subsequent screenshot confirmed the alert still covered the app.
The simulator privacy fallback rejected the unsupported `deny` action, so no
permission change was made. No simulator service restart, erase, owner-data
substitution or Journey interaction followed; the QA app was stopped. This is
an input/permission-presentation blocker, not evidence of an app hang. Live
picker → recovery-sheet navigation, rendered disabled/explanation behavior,
sheet retention and successful supported-choice interaction remain **pending**.
Their model/action/persistence regressions passed; no screenshot-based or
physical-camera acceptance is claimed.

**Closure within the reviewed scope:** F4's two residual paths are fixed and
native-verified. F3's residual compact controls/action/dismissal path is fixed and
native-verified, but full interactive acceptance remains open. Neither finding
is used to claim full Yu-Gi-Oh launch readiness, live pricing, CloudKit, physical
camera/device, archive or release readiness. Local links, project plist,
existing hosting-configuration validation and `git diff --check` pass.

HIG source verdict: **PASS**; no top issues. Native controls, wrapping semantic
text and VoiceOver hints preserve platform patterns, clarity, typography and
accessibility; no new prompt or navigation is introduced. Rendered interaction
and accessibility acceptance must be assessed separately.

## Corrective pass after four-commit review

**2026-10-21; candidate based on reviewed `1a3242d`.** The source checkout was
clean before these changes. No seed replacement, source census, owner-data reset,
publication or device installation was part of this verification. Phase A fixes are in runtime,
scanner/recovery, pricing, collection authority and builder admission. Phase B
adds `YuGiOhCandidateRelease.swift`, its project registration, delivery tests,
manifest revision/strict staging validation and snapshot limitation copy.

| Finding | Implemented correction and executable regression |
|---|---|
| F1 | Acceptance collection/recovery share the `YuGiOhAcceptance` scope. `testAcceptanceRecoveryPreservesPreexistingNormalBytesAcrossDismissAndClear` prepopulates a normal recovery file in an isolated root, loads acceptance, injects supported LOB-001, dismisses/removes/clears and checks normal bytes unchanged. No actual owner file is touched. |
| F2 | Missing historical quotes throw provider unavailable with and without a watermark. `testRealListingOnlyPairAndBundledSnapshotNeverPretendLiveRefresh` uses real 21792 First, PriceStore/PriceRecord/PriceCheckDay, a prior amount, and a dated positive quote control. Current negative answers from other providers retain existing semantics; exact zero quotes remain permitted. |
| F3 | Candidate availability/reason persists into compact/detail pickers, including VoiceOver hints. Unsupported DCR product 476802 stays visible/disabled; supported 487277 passes resolution and the save/export/import/reopen chain. Stale errors retain the full family with an explanation and cancellation/retry. Trial of Hell/Nightmare labels remain untouched. |
| F4 | Maintenance gate and final-save authority are independent of acquisition. Real-store tests cover discovery-only delete/restore, retired First → supported Unlimited with a safe sibling, save/reopen, ledger totals, rollback/retry, duplicate restore rejection, unsupported destinations and quantity-increase rejection. Authority comes from durable identity/ledger evidence, not a caller Boolean. |
| F5 | Complete independent review constrains the final historical merge. `test_complete_review_retracts_historical_lane_but_keeps_provenance` excludes prior Unlimited from First-only admission; the existing absence-without-contradiction control still retains membership. |
| F6 | Automatic eligibility requires identity/manual prerequisites. `test_invalid_association_reviewed_singleton_stays_quarantined` preserves safe rows; strict output validation runs before writes/staging. `testQuarantinedReviewedSingletonDoesNotPoisonSafeSiblingInActualLoader` checks actual Swift acceptance and contradictory auto-list rejection. These were latent builder defects, not bad automatic rows in the current seed. |
| F7 | The actual recognizer's `.nothing` outcome produces visible, explicitly labeled recognition diagnostic text with an accessibility ID. Native isolation test asserts the exact displayed string and no ownership write; rendered tapping remains pending. Production recognition is unchanged. |

New executable evidence, kept separate from earlier counts below:

- Phase A final gate: **425 native tests passed, zero failures/skips**. Includes
  all seven YGO classes, scanner, CSV resume, normalization, variant resolver,
  supplemental registry, recovery store, collection history/continuity,
  Lorcana ownership and One Piece integration. Both app and test targets built.
- Earlier corrective focused run: **47 passed**; overlaps the 425, not additive.
- Builder: **29 passed**, including two new adverse cases and strict staging
  rejection before artifact creation; rerun after strict
  staging/provenance validation. Earlier 26-test evidence below is historical.
- Local delivery/loader selection: **11 passed** (two new delivery cases plus
  nine overlapping loader cases). Later full-bundle delivery and maintenance
  selection: **17 passed** (three delivery cases plus overlapping workflows).
- Final stale-family/scanner selection: **133 passed**, including real DCR
  catalog drift → retained family/explanation → cancellation → Needs attention
  retry → supported Unlimited save. This overlaps earlier workflow/scanner runs.
  Build-only attempts are never counted as executed tests. Initial compile mistakes in the
  picker/test assertions were corrected before the successful runs.

External SSD result bundles under `CardScannerBuilds/yugioh/DerivedData/Logs/Test/`:
`Test-TradingCardScanner-2026.10.21_07-36-07--0600.xcresult` (425),
`Test-TradingCardScanner-2026.10.21_07-41-02--0600.xcresult` (11), and
`Test-TradingCardScanner-2026.10.21_07-46-21--0600.xcresult` (17).
Final stale-family/scanner bundle:
`Test-TradingCardScanner-2026.10.21_07-49-31--0600.xcresult` (133).
Final pricing selection (three overlapping tests, including the added real
positive-quote PriceStore timestamp assertion): **3 passed**,
`Test-TradingCardScanner-2026.10.21_07-52-05--0600.xcresult`.
Final adverse maintenance selection: **2 passed**, including actual isolated CSV
import rejection under discovery-only runtime and a forged existing-looking
inserted row rejected while a safe sibling keeps acquisition available;
`Test-TradingCardScanner-2026.10.21_07-54-08--0600.xcresult`. Both tests passed
again after the final durable-ID guard refinement (preserving maintenance of
persisted duplicate rows while rejecting inserted lookalikes):
`Test-TradingCardScanner-2026.10.21_07-55-35--0600.xcresult`; not additive.
`plutil` project validation, existing Firebase hosting configuration, local links
in all four changed Markdown documents and `git diff --check` passed.

Offline source replay with the fixed builder, census receipt and strict staging
produced byte-identical committed seed bytes (`cmp` passed). Generation, hash,
46,542 total / 46,303 explicit / 239 discovery / zero automatic counts and
59,965 membership / 58,264 quote / 1,701 listing-only pairs remain unchanged.
The local versioned manifest carries revision, generation, policy, captured time,
immutable path, exact SHA-256 and byte count. No live provider request was needed.

Phase B local fixtures verify signature/hash rejection, unknown keys, future and
stale snapshots, identity drift, revision rollback, corruption recovery to the
previous slot and bundled fallback. The real full bundled catalog also passes
signed consumer admission/provenance checks. The returned catalog/price-authority
pair is atomic local state; it is **not wired into live runtime activation**.
The seam has no endpoint or production keys and does not write collection/recovery
data. Durable previous-approved input and production signed publication/restore
still require the existing signing/hosting owner; the scheduled job continues to
use the repository bundle as parent. Nothing was deployed.

Interactive B1 remains incomplete. In the initial attempt, the dedicated simulator rendered the normal
fixture-OCR route, but Inject code and the sample menu produce no change from
automated taps. Computer-use inventory confirmed the Mac was locked and automatic
unlock failed. A process sample showed the app's main thread idle in its run loop,
not a demonstrated app hang. An unlock request was sent; no successful saved UI
outcome or new acceptance screenshot is claimed. Native fixture workflow tests
are not physical camera or interactive acceptance. Journey remains untouched.

**Follow-up after owner unlock — 2026-10-21, approximately 08:06 MDT:** computer-use
app inventory became accessible, confirming the earlier lock blocker cleared.
The dedicated simulator was relaunched with the normal `YuGiOhAcceptance` route.
Native taps still left Inject code, the sample menu and Collection unchanged.
The simulator-browser skill produced a live frame pinned to the same UDID; its
event log recorded touch delivery, but those controls still did not respond.
Restarting only that simulator, without erasing its stores, did not restore
automated input; even a simulated Home press left the rendered app unchanged.
This suggests an input/session problem but does not establish its cause. A
manual Collection-tab check was requested to distinguish automation failure
from app interaction failure; its result is pending. The temporary mirror was
closed and its scoped helper cleaned up. No saved UI outcome, new test execution,
code fix, personal-device action or Journey interruption is claimed in this follow-up.

HIG source verdict: **PASS**, with semantic wrapping text, native disabled buttons,
visible explanations, VoiceOver hints and no new prompt/navigation. Rendered
accessibility/interaction, physical-camera, commercial/image rights, CloudKit,
device performance, archive/TestFlight and App Store gates remain pending.

Smallest owner steps: report the manual Collection-tab input check so interactive
acceptance can resume through a working input path;
perform authorized physical-camera checks; have the existing publisher owner
define YGO production trust/signing plus durable approved-parent storage and
signed restore, then separately approve remote activation/deployment. The app
still uses **historical bundled data, without live YGO updates**.

## Evidence integrity and reproducibility

- Verified all 646 entries in the supplied package manifest against SHA-256
  and byte length before running its scripts.
- Replayed the four supplied analysis commands offline in an isolated temporary
  package copy. Price summary, correspondence diagnostics and case studies are
  structurally identical to the originals. The correspondence summary differs
  only in the declared factual-projection YGOPRODeck hash, as expected.
- Located the original external-SSD source cache and verified all 1,321 raw
  source hashes against the original repository build report. No source network
  census was repeated and the factual projection did not replace raw inputs.
- The census receipt binds all 610 recovered group price hashes to the stable
  provider snapshot `2026-10-20T20:05:18+0000`. Raw price responses lack their own
  `lastUpdated`; the receipt supplies that provider-snapshot fact. Ordinary
  captures without a receipt retain capture-time semantics instead.
- Rebuilt from all 659 cached groups / 47,910 raw products. An independent
  offline replay produces byte-identical production seed bytes.
- Compared every original retained product with the rebuilt seed: all 46,504
  printing UUIDs, canonical UUIDs, groups, codes, rarities and art labels match.

Generation: `yugioh-en-43128284032a`.
Seed SHA-256:
`f9506a0b9ea9f793100f8a8ab247bb21df84fbf9da55f9dceb4b76aa6c37d552`.
Size: 33,220,209 bytes. The app's actual Swift loader checks the full seed and
its product/membership/quote partition in `YuGiOhCatalogTests`.
The seed grows from 14.17 MB to 33.22 MB to keep offline membership provenance
and exact dated quotes together. This favors auditability and offline usefulness
over package size. Browse initialization now builds summaries directly, and
pricing authority checks choice labels once per family, avoiding repeated full
card resolution/date formatting. No device launch or memory benchmark is claimed.

## Admission, denominators and provenance

Policy: `yugioh-provider-membership-v1-2026-10-21`.
Correspondence rules: `yugioh-correspondence-v1-2026-10-21`.
See the [generated report](audited-rebuild.md),
[upstream ledger](audited-rebuild.exclusions.json),
[census receipt](price-census-receipt.json) and
[scoped rule registry](../../../scripts/yugioh_correspondence_rules.json).

| Status, with precedence applied once per product | In-app seed | All raw source products |
|---|---:|---:|
| Automatic acquisition eligible | 0 | 0 |
| Explicit-choice-only eligible | 46,303 | 46,303 |
| Discovery/review | 239 | 675 |
| Quarantined contradiction | 0 | 0 |
| Legitimately excluded by scoped source metadata | — | 932 |
| Total | 46,542 | 47,910 |

The 239 discovery records comprise 205 with no supported edition and 34 with
unsupported printed-code grammar. The additional 436 source records have no
usable printed identity and remain in the full diagnostic ledger. They are
not in-app scan identities. Of the 932 exclusions, 51 have explicitly foreign
codes and 881 match bounded sealed/accessory product-name metadata. The latter
classification describes provider metadata, not a physical inspection.

The original 1,406 upstream omissions therefore reconcile as four recovered
IOC-SE products, 34 newly discoverable unsupported-code products, 932 excluded
records and 436 pending identities. No denominator was silently dropped.

Supported exact-product/edition pairs: **59,965**; exact market quotes:
**58,264**; listing-only pairs without market valuation: **1,701**.
These are four more supported/quoted Limited pairs than the audited retained
cohort. Raw subtype observations are reported separately and may exceed admitted
membership. Zero products have independently complete physical coverage.

Membership requires exact category/group/product association, usable identity
fields and distinguishable source labels, recognized edition evidence with
finite positive observations, valid provenance, and no relevant contradiction.
It is not approval by price alone. Source-only canonical linkage is disclosed.
Non-rarity YGO labels do not change canonical IDs or add physical variants.
All 162 scoped RA02 taxonomy rows correspond under the pinned product hash;
the rule provides neither edition nor artwork certification.

## Native and Python verification

Simulator: dedicated **YuGiOh Integration QA**, iOS 27.0. Builds and dependencies
use the existing external SSD under `CardScannerBuilds/yugioh/`. No other
Simulator, Journey session or personal device was modified.

| Check | Candidate snapshot evidence |
|---|---|
| Full selected affected/neighboring native suite | **232 passed; 0 failed; 0 skipped** |
| Final catalog/runtime incremental selection | **16 passed; 0 failed** |
| Enhanced changed-catalog workflows and supplemental registry | **14 passed; 0 failed; 0 skipped** |
| Python builder policy tests | **26 passed** |
| Offline package analysis | Four commands passed; counters reproduced |
| Original source / seed replay / UUID compatibility | Passed |
| Firebase existing hosting configuration | Passed |
| Additional generic iOS build-for-testing | Succeeded; this build-only run did not execute tests |
| Game boundary audit | Fails on 48 pre-existing lexical branches; no new matched branch |
| Local Markdown links / whitespace | Validated at handoff |

Both the app and test target compiled through `xcodebuild test`. This is a
selected regression suite, not a full test-target execution or release archive.
Xcode emits an iOS runtime build-number diagnostic (`invalidDigitCount`), but
the result bundles report successful tests. Initial failures exposed a missing
Swift return, absent snapshot timestamps and obsolete blanket-disable test
expectations; these were repaired before the successful runs.

Final broader result bundle, relative to the external build root:
`DerivedData/Logs/Test/Test-TradingCardScanner-2026.10.21_06-29-19--0600.xcresult`.
Enhanced workflow/supplemental result:
`DerivedData/Logs/Test/Test-TradingCardScanner-2026.10.21_06-31-44--0600.xcresult`.
The earlier 43-test YGO run is additional evidence, not a sum added to 232.

Covered native classes: `YuGiOhCatalogTests`, `YuGiOhResolutionTests`,
`YuGiOhWorkflowTests`, `YuGiOhImportTests`, `YuGiOhPricingTests`,
`YuGiOhRecognitionTests`, `YuGiOhRecoveryTests`, `ScannerViewModelTests`,
`CSVImportResumeTests`, `CatalogNormalizationTests` and `VariantResolverTests`.
The supplemental registry class is `GameRecognitionRegistrySupplementalTests`;
it is included explicitly in the final supplemental selection.

Real bundled workflow cases use products 21792 (older regionless LOB), 476160
(same-code release distinction), 550852 (modern RA02 alternate art), 26366
(IOC-SE1 Limited) and 229392 (early E code). Fixture OCR passes through actual
printing/edition choice, collection mutation, pricing mapping, export/import
and reopen. The injected pricing source in those ownership chains proves
mapping/persistence only; separate real bundled quote tests prove null-market
and dated-snapshot behavior. No fixture quote is claimed as a real market value.

The maintenance regression acquires two copies under a reviewed fixture, installs
a newer generation with unknown coverage and supported exact membership, rejects
Limited, corrects First to Unlimited through the real store transaction, reopens,
and checks quantity and ledger identity. Enhanced assertions also exercise
delete/restore and import under a changed seed generation after quotes disappear.

## UI execution and HIG gate

The debug/local-signing route `-ui_debug_route YuGiOhAcceptance` uses a separate
`YuGiOhAcceptance` storage directory, real bundled records and the normal scanner
callback/choice UI. It disables camera startup and labels its input as fixture
OCR. The ordinary runtime and views remain the production paths.

Installed and launched the app on the dedicated simulator. Screenshots and the
semantic snapshot show the ScanStash launch, then the fixture-OCR scanner with
LOB-001/Inject code and the normal Collection/Auto controls. **Interactive UI
acceptance is incomplete:** the Mac is locked. The computer-use inventory twice
confirmed that automatic unlock cannot unlock it; Simulator taps produced no
navigation even for the Collection tab. An unlock request was sent to the owner.
No printing-choice, Browse Add or saved UI result is claimed from those taps.

HIG source gate: **PASS; no source-level top issues.** Existing system navigation,
printing/edition sheets, scrollable details and Dynamic Type styles are retained.
New limitation text and quote dates use semantic footnote/caption styles; source
identity/evidence and historical-price limits are visible in details. No release
navigation or monetization change. Rendered interaction/accessibility acceptance
remains open until the Mac can receive input.

## Provider delivery and remaining gates

The production YuGiOh price adapter consumes the bundled exact-lane snapshot;
it no longer calls the direct TCGCSV device transport. Listing values never
substitute for market quotes. Source/fetch dates remain historical and manual
freshness watermarks cannot make them current. Missing market values remain
unavailable. No synthetic provider history is introduced.

The daily server-side candidate workflow builds and tests an isolated namespace
for the existing Firebase host. Local immutable/hash staging passed. No workflow
was remotely run, published or deployed in this turn, and the app has no activated
remote YGO catalog endpoint. Durable daily previous-candidate continuity, signed
publication/restore and remote activation remain production integration gates.
Commercial/data/image permission review, physical-camera acceptance, CloudKit,
archive/TestFlight and release readiness remain separate owner/external gates.
No YGOPRODeck image hotlinking or private API/SKU assumptions were introduced.

## Reproduce

```bash
cache='/Volumes/<external-SSD>/YuGiOhSourceCache/2026-10-21'
out='/Volumes/<external-SSD>/CardScannerBuilds/yugioh'
python3 -I scripts/build_yugioh_catalog.py --self-test
python3 -I scripts/build_yugioh_catalog.py --offline --cache-dir "$cache" \
  --price-receipt docs/research/yugioh-catalog/price-census-receipt.json \
  --out /tmp/yugioh-replay.json --report /tmp/yugioh-replay.md
cmp /tmp/yugioh-replay.json TradingCardScanner/YuGiOhCatalogSeed/catalog.json
classes=(YuGiOhCatalogTests YuGiOhResolutionTests YuGiOhWorkflowTests
  YuGiOhImportTests YuGiOhPricingTests YuGiOhRecognitionTests YuGiOhRecoveryTests
  ScannerViewModelTests CSVImportResumeTests CatalogNormalizationTests
  VariantResolverTests GameRecognitionRegistrySupplementalTests
  UnresolvedScanStoreTests CollectionActivityHistoryTests CollectionStoreContinuityTests
  LorcanaOwnershipTests OnePieceIntegrationTests YuGiOhCandidateDeliveryTests)
only=(); for cls in "${classes[@]}"; do only+=(-only-testing:TradingCardScannerTests/"$cls"); done
xcodebuild test -project TradingCardScanner.xcodeproj -scheme TradingCardScanner \
  -configuration Debug -destination 'platform=iOS Simulator,name=YuGiOh Integration QA' \
  -derivedDataPath "$out/DerivedData" -clonedSourcePackagesDirPath "$out/SourcePackages" \
  -parallel-testing-enabled NO "${only[@]}" CODE_SIGNING_ALLOWED=NO
bash scripts/verify_pokemon_catalog_hosting_config.sh
git diff --check
```

For subsequent snapshots, pass a validated prior seed via `--previous-seed`.
For local host staging only, add `--hosting-root /tmp/yugioh-site`. Neither option
deploys anything. Never overwrite the original cache with the audit projection.

## Owner camera-check checklist

- Scan older under-art and modern footer codes, including an E code and IOC-SE1;
  compare the literal code with the selected release, rarity and artwork.
- Scan First, Unlimited without a stamp, and Limited. Confirm that absent text
  asks for an edition, and conflicting/unreadable stamps remain recoverable.
- Test RA02 alternate art and both LOB-EN001 reissues; confirm they remain separate
  products and that a representative image does not silently decide identity.
- Scan a held card twice, another copy, then a small stack. Test cancellation,
  retry, interruption and Needs attention with no unresolved spinner/save receipt.
- Correct an edition, change quantity, delete/undo, force quit/reopen and round-trip
  CSV. Compare identity, edition, quantities and ledger totals.
- Check a listing-only/no-market pair: it must remain unvalued. Verify snapshot
  dates, offline/missing-image behavior and the unavailable live-refresh state.
