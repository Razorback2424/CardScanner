# Lorcana production acceptance checkpoint

**Status — 2026-10-14:** bundled ordinary pricing is enabled; collection integrity
and failure recovery pass simulator acceptance, with a later edge-case sweep
passing 162 shared/live cases after three additional fixes. Current candidate:
`feat/lorcana-implementation`, original clean starting HEAD
`ec6d64c` plus local changes. Earlier complete-target, live-provider and archive
evidence is retained below for its recorded candidate; the archive predates the
recovery fixes. **Not certified for App Store submission.** No commit, push,
device installation, portal change or upload was performed in this pass.

**Owner deferral — 2026-10-14:** privacy/support page publication, live-page
verification and app/App Store Connect URL configuration are deferred until
resumed. Retain the prepared files and walkthrough. This does not close the
submission prerequisite; other rollout work can proceed independently.
App Store exports are also explicitly deferred for the collection-integrity/
recovery pass; none was attempted.

The [implementation plan](../plans/lorcana_code_implementation.md) owns execution.
The [normal pricing checkpoint](../research/lorcana-normal-pricing-rollout.md)
owns the mapping/source decisions, live eight-set pricing and rendered iPhone/iPad
simulator evidence. This follow-up does not rerun or relabel that live acceptance.

## Candidate and regression evidence

### Holistic edge-case sweep — 2026-10-14

Continued from the preceding uncommitted recovery fixes on `ec6d64c`, preserving
that work. The sweep covers Lorcana and the shared product feed/refresh paths;
it does not claim a whole-repository review or reopen deferred export/web work.
Three new regressions failed before their fixes:

| Defect | Correction and regression boundary |
| --- | --- |
| An unreachable mapped feed was attempted again for each owned printing/finish, and did not set the refresh's unreachable-provider summary. | Stop the mapped-feed loop after the first classified unreachable response, retaining prior values and marking the actual failed attempt. A later refresh can retry. The mapped-feed reachability flag is separate from the legacy catalog flag, so a failing TCGCSV host does not stop healthy Pokémon batches. |
| An explicit no-price response was persisted but not counted as a completed provider check in the refresh summary. | Count observations with a named provider, including valid absence; `.unavailable(nil)` remains a no-provider no-op. No amount is fabricated for a missing quote. |
| Invalid decoded feed data entered the daily cache before product/lane/amount checks, so it could keep failing after relaunch. Finite amounts outside Money's range could also escape the transport as quotes. | Validate new responses before either cache accepts them and validate older disk snapshots on hydration. Reject duplicate product IDs/price lanes, cross-category/group products, negative and unrepresentable amounts. Existing invalid snapshots are ignored and replaced on a successful fetch. Null and zero prices remain valid and reusable. |

Rejecting an invalid group response uses the existing provider-failure cooldown
rather than trusting it for the daily cache window. This protects quote identity
and valuation while retaining last-good collection values. Request pacing,
transport retry behavior, generation/withdrawal watermarks, permanent UUIDs,
mappings and supported/held scope remain unchanged.

| Verification | Finalized result |
| --- | --- |
| Reproduction | `before-fix.xcresult`: three selected cases, three failed. Cache cases cover duplicate products, wrong category/group, duplicate lanes, negative and overflowing amounts, including legacy disk snapshots. |
| Intermediate Lorcana replay | `after-fix-replay.xcresult`: 50 passed, zero failed, three live skips / 53 cases; one internal QoS warning. This preceded the final mixed-provider regression addition. |
| Final rebuilt shared/live selection | **162 passed, zero failed/skipped**, two internal QoS runtime warnings. `final-shared-live.xcresult` includes Lorcana ownership/pricing, One Piece integration, CSV resume and refresh lifecycle checks. Five new tests cover the three failures plus valid null/zero caching and independent healthy-provider batches. |
| Fresh live matrix after validation changes | **3,232 priced lanes / 1,616 printings across eight sets; zero unavailable or mismatched.** New isolated cache contains eight valid group snapshots. Existing normal-app eight-set and Hades save/refresh/relaunch/withdrawal live cases also pass. |
| Ownership, CSV and cancellation regressions | PASS in the final selection; no collection schema, CSV format, printing mapping or UI change. |

An initial fix build caught a declaration-scope error in the reachability flag;
separate mapped/legacy flags corrected it before the successful replays. Build
and runtime diagnostics remain; this is not warning-free certification.

Evidence is external at `CodexBuilds/LorcanaEdgeSweep-20261014/`, including the
three fresh live reports and eight group snapshots. Report modification times
were checked against this run's opt-in time before retention. The temporary
one-hour, exact-seed opt-in was removed after the run. No App Store export,
webpage update, physical-device/card test, commit, push or portal change occurred.
Earlier complete-target and archive results remain earlier-candidate evidence;
no new full-target or archive/export run is claimed for these fixes.

### Collection integrity and failure recovery — 2026-10-14

The acceptance pass uses isolated simulator stores and the existing CollectionStore,
CSV importer/exporter, bound quote service, TCGCSV source and collection refresh
worker. No real collection or physical cards are used. Controlled URLProtocol
and actor failures exercise recovery without a live-provider opt-in. No pricing
mappings, ownership schema, CSV format, UI or supported printing scope changed.

Two defects were corrected:

1. The shared product feed cached network failures for 15 minutes as if the
   provider had rejected the request. An immediate retry after offline,
   connection-loss, timeout or URL cancellation therefore returned
   `providerUnavailable` even when the next transport response was valid.
   `TCGCSVProductPriceSource` now permits transport/cancellation retries while
   retaining its existing HTTP/feed rejection cooldown, request pacing, exact
   product/finish checks and cache identity/watermark rules. This also applies
   to One Piece through the already shared component.
2. The mapped collection-refresh path recorded URL cancellation as a provider
   failure. It now treats that cancellation like Swift task cancellation and
   checks the task's cancellation state before recording a caught failure.
   Abandoned quotes/checks are not published; a later refresh can resume.

| Check | Finalized result / acceptance |
| --- | --- |
| Pre-fix transport recovery regression | One selected case fails across offline, connection loss, timeout and URL cancellation. `recovery-before-fix.xcresult` retains the reproduction. |
| Final shared regression | **154 passed, zero failed, three skipped / 157 cases**, one internal QoS runtime warning. `shared-recovery-regression.xcresult` includes Lorcana ownership/pricing, One Piece integration, PriceRefreshLifecycleTests and CSVImportResumeTests. |
| Lorcana ownership subset | **25 passed**, zero failed/skipped. Includes the two new integrity/retry scenarios. |
| Lorcana pricing subset | **21 passed, zero failed, three skipped / 24 cases**. The three expiring-opt-in live checks are deliberately skipped; earlier live acceptance is separate evidence. |
| Normal/Foil quantity and identity integrity | PASS — bundled Ariel Normal ×2 and Foil ×3; duplicate Add/Undo restores Normal ×2, quantity edit produces Foil ×7, stale quantity edit and unsupported finish reject. Exact finish-qualified UUID keys survive disk reopen. |
| Stored reference price | PASS — a separately stored `importedCSV` owner-entered reference value survives local-store reopen. This is persistence evidence, not a new manual-price UI test. |
| CSV round-trip and repeat import | PASS — both finish-qualified rows and all nine copies survive the shared isolated export/import path; replaying the same plan adds zero copies. CSV remains inventory transfer, not a backup of separate price records/history/artwork. |
| Partial CSV failure and correction | PASS — unknown UUID row fails while a valid row commits; export only the failed entry, correct its exact UUID/key, retry, then replay. Two total copies remain without duplicating the first committed row. |
| Offline/provider failure retention | PASS — an old exact Foil quote remains available with its original fetch time and failure metadata after an unreachable refresh and disk reopen; Normal/Foil quantities remain separate. A recovered quote replaces the amount and clears failure metadata. |
| Cancellation and resume | PASS — URL cancellation creates no failed/successful provider check. Cancelling a paused worker publishes neither an abandoned quote nor a failure; its next run obtains the exact price without changing ownership. |
| Provider-data protection | PASS — malformed feed retains cooldown; exact lane mismatch, duplicate lane, mapping withdrawal and cached receipt tests remain green. |
| Missing artwork metadata | PASS in existing synthetic ownership/pricing fixtures with nil image URLs; artwork is not required for Add/Undo/CSV/pricing. A new rendered image-download failure pass was not performed. |

Seven focused acceptance tests were added. The earlier intermediate replay
reported 44 passed and three live skips before the final partial-import/task-
interruption additions; the finalized 157-case run rebuilt all final changes.
Artifacts use the external SSD at `CodexBuilds/LorcanaIntegrityRecovery-20261014/`
and the existing SSD derived-data/package caches. No live opt-in was enabled,
no personal collection export was retained, and no webpage or App Store export
work was performed. Existing compiler/test diagnostics remain; this is not a
warning-free run. The earlier full-target and development archive checkpoints
were not rerun and do not certify this changed binary. Physical-device, rendered
accessibility, source/artwork rights and deferred release tasks retain their
existing evidence boundaries.

### Independent rollout continuation — 2026-10-14

This continuation excludes physical-card checks and the owner-deferred
privacy/support publication and URL work. No production app code or bundled
catalog changed. Added `testLiveAllMappedPrintingPrices` to the existing pricing
suite: it uses the bundled registry, existing runtime/quote service and exact
TCGCSV adapter, with a fresh ephemeral session and isolated feed cache. Every
enabled printing/finish is checked; valid null prices are recorded as unavailable
rather than borrowed from another lane. The existing expiring, seed-bound local
opt-in prevents network calls during routine/offline testing. Removed redundant
nil fallbacks from test receipt serialization that generated compiler warnings.

| Check | Finalized result | Boundary |
| --- | --- | --- |
| Complete enabled live mapping matrix | **1,616 printings / 3,232 lanes priced, zero unavailable or mismatched**, across sets 1–8 | Eight fresh group snapshots through the shared adapter; no artwork download or physical-card claim. Retrieval is fresh; the provider's aggregate feed can itself be approximately 24 hours old, and `sourceUpdatedAt` remains unknown. |
| Existing pricing suite with live opt-in | **19 passed, zero failed/skipped**, two internal QoS runtime warnings | `live-all-mappings.xcresult`; includes the new full mapping matrix, normal eight-set workflow and Hades save/refresh/relaunch/withdrawal replay. No new pricing workflow was introduced. |
| Offline/default pricing suite | **16 passed, zero failed, three skipped**, one internal QoS runtime warning | `offline-pricing.xcresult`; the three live tests skip without opt-in. This preceded the receipt-only warning cleanup; the final live run rebuilt that cleanup. |
| Catalog/discovery Python tests | **12 passed** | Existing builder tests, including held ambiguity, stable allocation and prior-identity rejection. |
| Retained-source generator replay | PASS — market catalog and permanent UUID ledger byte-identical | 1,616 mapped printings, 3,232 lanes, same 15 held decisions. Ledger SHA-256 `596d4335b7f70f93a7cd57cc94e6e37ee239962bd8e1fa1dc6305c4985168787`; catalog SHA remains unchanged. No mappings or supported classes were broadened. |
| CloudKit source audit | PASS | Source audit only; no sync enrollment, schema or capability change. |
| Strict game-boundary architecture audit | FAIL — 48 existing matches, identical to `HEAD`, zero Lorcana matches | The audit intentionally includes legacy branches pending extraction. No new Lorcana branch was added; broad Pokémon/Magic extraction is outside this rollout. This is not a clean whole-repository architecture audit. |
| Local App Store distribution export | FAILED — no matching distribution provisioning profile installed | One valid development identity and zero local distribution identities. `app-store-connect` local export used automatic signing with provisioning updates disabled. No certificate/profile creation, portal change or upload. Development archive/export remains verified; distribution acceptance remains open. |
| Retained development archive | Strict signature verification passes after SSD retention | App source/resources are unchanged from the earlier verified archive. Test-only additions do not require a new production archive. |

The external SSD is reconnected. New evidence is under
`CodexBuilds/LorcanaRolloutCloseout-20261014/`; build-derived data reuses
`CodexBuilds/LorcanaCoverage-20261013/DerivedData`. The earlier complete simulator
bundle, focused timing bundle, archive, development IPA and stage measurements
are retained under `retained-previous-pass/`. No permanent cache redirection was
needed this time. Public live reports and eight cached group responses are kept
external; the temporary opt-in and private export options were removed afterward.
Resolve the simulator's current app container after tests before collecting
reports, because an Xcode reinstall can migrate its path.

The earlier complete target (2,200 cases) remains the full-app simulator baseline;
it was not rerun after this test-only addition. The 19-case finalized replay is
the new evidence, not a claim of a new complete-target run. Build diagnostics
still include existing test concurrency warnings; these are not warning-free builds.
Public JSON access policy does not establish artwork/publication rights, so that
owner-controlled gate remains unconfirmed. Privacy/support work remains deferred.

### Current follow-up — 2026-10-14

The external SSD is disconnected. This follow-up uses the internal fallback
`/private/tmp/LorcanaRollout-20261014/` for derived data, package caches, bundles,
archive/export and browser evidence. Existing SwiftPM cache symlinks pointed to
the unavailable SSD; a task-owned, serialized wrapper temporarily redirected
only those two links and restored them after each build/test. No permanent cache,
trust, signing, capability, provider or portal settings were changed.

| Check | Finalized result | Boundary |
| --- | --- | --- |
| REQ-022 baseline and named-stage diagnosis | Baseline fails unchanged 0.8 s median / 1.5 s maximum limits; REQ-041 wall median 1.728 s across 20 records | Ten raw HEIC fixtures, two repetitions for stage profiling. Scalar fields consume 59.3% of attributed time; candidate generation consumes 22.0%. Simulator evidence. |
| Native scalar and median optimization | Focused four-case replay: 4 passed, zero failed/skipped/warnings; REQ-022 upper median 0.540 s, maximum 0.615 s | `median-optimization.xcresult`. Existing strict C kernels now also perform RGBA decoding, gradient averages, silhouette counts and Float/Double median sorting. Resolution, samples, thresholds, selection, confidence and latency limits remain unchanged. |
| Arithmetic and geometry parity | Expanded kernel parity and exact geometry/profile comparison pass; full target rebuilt the final helper | All ten raw HEIC fixtures retain exact reference measurements/profiles. Native medians use a scratch copy; scalar references remain available in DEBUG. `-O2 -ffp-contract=off` remains the existing C policy. |
| REQ-041 optimized stages | Wall median 0.691 s, maximum 1.058 s across 20 records | `optimized-stage-timings.json`: scalar-field median 0.127 s, candidate-generation median 0.294 s. Instrumented wall time includes profiling overhead; it is separate from REQ-022. |
| Complete final simulator target | **2,188 passed, zero failed, 12 skipped / 2,200 cases**, five runtime warnings | Finalized `final-full-foreground.xcresult`, no selector exclusions. Final REQ-022 upper median **0.586 s**, maximum **0.649 s**. Expanded kernel parity, geometry/profile, guided correctness, Lorcana, Pokémon, Magic, One Piece and shared workflow cases pass. |
| Final actual iOS `ReleaseLocal` archive | `ARCHIVE SUCCEEDED`; strict signature verification passes | `TradingCardScanner-final.xcarchive`, rebuilt after the centering change. Five existing source warnings plus App Intents metadata warning; not a clean-warning or distribution build. |
| Final development IPA | `EXPORT SUCCEEDED`; strict signature verification passes | `development-export-final/TradingCardScanner.ipa`, existing automatic development signing, no provisioning updates/upload. Local-storage configuration has no iCloud entitlement. |
| Archive and IPA resource/configuration checks | PASS | Market/discovery bytes equal checkout; market SHA-256 `46617f651be5d6fe348a3e7a64a104ac220e7adb8821d4bc0945ed2307906c95`, discovery SHA-256 `8b5665f25aff880943f154902e42b27a6e80fd530f7e075f6c59246999af2ffd`. Privacy manifest present, iOS platform/minimum 17.0, version 1.0/build 1, DEBUG Lorcana review launch token absent. |
| Bluehost app-page package | Prepared and browser-checked; not published | [Upload guide](../legal/bluehost-publication.md), canonical privacy/support copy, self-contained HTML ZIP. Inspected mobile 390 × 844 and desktop 1280 × 900, working navigation/contact links, no overflow or console errors after the favicon fix. No messages sent. |
| Reviewer handoff without cards | Prepared | [Review notes](lorcana-app-review-notes.md) describe the normal Browse → Add → collection pricing path; not App Store Connect submission or hardware evidence. |

The first full follow-up returned 2,181 passed, seven failed and 12 skipped:
all seven failures were Browse render tests requiring a foreground UIWindowScene.
A native UI snapshot showed an outstanding camera-permission dialog. After
accepting that permission and foregrounding the ordinary app, all seven cases
passed in `browse-host-replay.xcresult` (one internal QoS warning), followed by
the clean complete rerun above. No pagination code or test assertion was changed.
Simulator camera permission is not physical-camera acceptance.

The 12 full-run skips retain the same device/live-provider/CloudKit/corpus/opt-in
boundaries listed below. The five runtime warnings are one internal QoS warning
and four SwiftUI Environment/State warnings from view-construction smoke tests.
Expected storage-negative-test database errors remain diagnostics, not failed
tests. This is a green full-target simulator baseline, not full-app release
certification or a hardware latency claim.

Live checks on 2026-10-14 still find a website-only `/privacy` (HTTP 200) and
`/support` (HTTP 404). The owner identified Bluehost; the prepared policy retains
the current website/FormSubmit disclosures and adds app practices. FormSubmit's
documented 30-day submission archive does not establish mailbox or other
providers' retention. The upload guide avoids password sharing and broad site
overwrites. Verified live publication, operator/mailbox/provider details,
source/artwork scope and distribution acceptance remain open. Submission URL
settings stay empty pending verification. No physical cards are available.

### Historical production-check snapshot — 2026-10-13

All build/cache/result artifacts use the external SSD under
`CodexBuilds/LorcanaProductionChecks-20261013/`; simulator builds reuse
`CodexBuilds/LorcanaCoverage-20261013/DerivedData`. Logs may contain private signing
or hardware identifiers and remain external; only sanitized conclusions belong here.

| Check | Result | Boundary |
| --- | --- | --- |
| Actual iOS `Release` archive, generic iOS destination, signing disabled | `ARCHIVE SUCCEEDED` | Initial packaging checkpoint before the footer-label correction; compiles/packages an iOS binary, without installability or distribution signing evidence. |
| Final actual iOS `ReleaseLocal` archive using the installed development identity/profile | `ARCHIVE SUCCEEDED`; strict code signature verification passes | `TradingCardScanner-development-local-final.xcarchive` includes the footer correction and same normal bundled catalog; local storage signing configuration, no CloudKit entitlement. Not a distribution candidate. |
| Final development IPA export using existing automatic signing, provisioning updates disabled | `EXPORT SUCCEEDED` | `development-export-final/TradingCardScanner.ipa` includes the footer correction. Existing paired iPhone is covered by the development profile. No distribution certificate was found; no App Store/TestFlight export or upload was attempted. |
| Archive and exported IPA resources | PASS | Bundled market bytes equal checkout: 1,617 physical records, including one unpriced oversized Hades; 3,232 lanes for 1,616 ordinary printings. Discovery SHA binding agrees. Privacy manifest is included. |
| Binary/configuration inspection | PASS | iOS platform, minimum iOS 17.0, version 1.0/build 1. Release compilation excludes the debug-only Lorcana review route; review launch token is absent from both archive binaries. |
| `PokemonTCGCSVPriceTests` | 25 passed, zero failed/skipped, zero warnings | Finalized `pricing-cache-regression.xcresult`. Fixes the previously reported `unknownSet` test failure. |
| Storage/schema/forward compatibility and Lorcana ownership/pricing selectors | 140 passed, zero failed, three skipped, zero warnings | Finalized `storage-compatibility.xcresult`; 143 selected cases. These are simulator checks, not live CloudKit or device protection evidence. |
| `bash scripts/audit_cloudkit_schema.sh` | PASS | Source prohibition audit; no schema enrollment or promotion. |
| Full simulator regression | Finalized: 2,186 passed, two failed, 12 skipped / 2,200 cases; five runtime warnings | `full-regression.xcresult`: three assertion failures across two cases, centering timing and stale sealed-provider expectation. The latter is corrected and passes in the final replay; this is not a green full-app baseline. |
| Final source targeted replay | Finalized: 276 passed, one failed, zero skipped / 277 cases; two internal QoS warnings | `final-targeted-replay.xcresult` confirms all 77 JustTCG contract tests and Lorcana discovery/parser/scanner selectors pass. Only centering timing fails (two assertions). |

**2026-10-30 source update:** the app and test targets now require iOS 18.0.
The 1,500-instrument × 365-day scan-write benchmark exceeded the owner-approved
50 ms gate, so the local `PriceCheckDay` and `PriceObservation` tables now declare
indexes. The minimum-iOS-17.0 row above describes the earlier archived build;
it is not the current deployment target. This source/simulator change does not
update that archive or certify a new distribution package.

**2026-10-31 verification:** the exact pre-index `e292646` build measures
**51.261084 ms** for a scan price write at 1,500 instruments × 365 days,
exceeding 50 ms. The indexed `ade96f1` product measures **29.578375 ms** in the
same in-memory fixture. Storage/replay suites pass 100 cases with one device
skip; expanded S2 passes 499 with six opt-in skips. The in-place simulator
upgrade retains collection, quotes, Portfolio history and a persisted chart
cache, but its local tables still list no physical indexes. See the
[refinement verification](../audits/production-refinement-master-review-2026-10-26.md#2026-10-31-refinement-follow-up-verification-and-accuracy-fixes)
for the measurements and fixture/provider limits. This does not certify an
App Store device upgrade or an on-disk index performance benefit.

The three focused skips are the first-unlock file-protection assertion (requires
a physical device) and the two intentionally disabled live-provider tests.
The earlier live replay remains separate evidence. Storage negative tests emit
expected database-open errors; no case failed in this focused bundle.

The full run's 12 skips comprise first-unlock device protection, five unavailable
CloudKit-mode transitions in the local-only build, the two disabled Lorcana live
tests, three unstaged Magic photographic/provider corpus tests and an opt-in
aged-portfolio performance baseline. They are not counted as passed evidence.
No selector was excluded from the full run. It compiled before the single-line
footer correction and the later JustTCG test correction; final source is rebuilt
for the separate targeted replay and signed package.

The five full-run runtime warnings include internal QoS priority inversions and
SwiftUI Environment/State access outside an installed view. They are recorded
as diagnostics, not a clean-warning run or proof of a rendered product defect.
The full bundle finalized about nine minutes after the last case ended; the
focused replay finalized sooner. Both summaries were read with `xcresulttool`.

The Pokémon mock advertised an empty set while requesting details for a card
that the app correctly requires to belong to that set. The fixture now returns
its exact card/set IDs. The production Browse membership check is unchanged.

The full run also found a stale JustTCG contract assertion that Lorcana sealed
discovery must throw. The existing client already serves those 177 products from
the bundled catalog without calling JustTCG. The test now checks that local path
and retains the pre-transport rejection assertion using an unknown future game.
No provider boundary was changed. All 77 JustTCG contract cases pass in the final
targeted replay, including the corrected assertion.

The centering timing test fails both runs. Full-run median/maximum were
1.680/2.114 seconds; the single-case replay, with no competing builds and the
full-run host already exited, reports 1.663/1.955 seconds against unchanged
0.8/1.5-second limits. This is an existing app-wide centering performance gate,
not a Lorcana pricing failure or physical-camera latency measurement. Its
governing [centering plan](../../review/opus-card-centering-implementation-plan.md)
and [production refinement plan](../plans/october-production-refinement-review-plan.md)
already retain latency acceptance. No centering algorithm or test budget was
changed during this Lorcana rollout; isolated reproduction prevents dismissing
the failure as build contention. The full run is not certified green.

The archive compiler also exposed an impossible `nil` pattern in
[`ScanSessionOverlays.swift`](../../TradingCardScanner/Views/ScanSessionOverlays.swift)
at line 449. `LegacyScanIdentifier` is a nonoptional enum; generic game identifiers
use `.opaque`. Matching that case restores the complete Lorcana footer text in
the existing finish chooser. Final DebugRemoteLocal simulator build and inspected
phone/tablet rendering pass below;
the full regression started before this presentation-only correction.

Both initial archives succeeded with six source diagnostics (two actor-isolated
logger accesses, two camera Sendable captures, the impossible nil pattern and
an unmutated Browse variable), plus the App Intents metadata extraction warning.
These are warnings under the current language mode, not clean-warning builds;
the final archive has five source diagnostics plus the metadata warning, and no
impossible-nil diagnostic. Broader concurrency
cleanup is outside this Lorcana rollout change.

### Focused footer-label rendering checklist

Target: existing scanner finish chooser, route `LorcanaReview`, state `standard`,
on dedicated iPhone 17 Pro and iPad Pro simulators. Uses isolated synthetic
storage and disables the camera. Normal collection data is preserved during
installation. This narrow replay does not repeat all earlier UI acceptance.

- [x] Full Lorcana footer is displayed in the identifier row on both devices:
  `23/204 EN 1` in this synthetic example.
- [x] Name, footer and set remain readable without clipping/overlap.
- [x] Existing Normal/Foil buttons and dismiss control remain visible and enabled;
  their callbacks are unchanged. Earlier finish/save interaction evidence remains
  in the UI checkpoint; this replay validates the label correction.
- [x] Review banner, navigation and safe-area layout remain intact.
- [x] Final screenshots inspected after the single-line enum correction:
  `ui-footer-iphone/ui-final.png` and `ui-footer-ipad/ui-final.png` in the SSD root.

Strict signature verification initially returned `CSSMERR_TP_NOT_TRUSTED` inside
the sandbox; verification of the unchanged archive outside it passed. No trust
settings, certificates or keys were changed. An initial export failed because
manual export settings cannot use the existing Xcode-managed profile; retrying
with the archive's automatic settings succeeded without provisioning updates.

## Device and release scope

The paired iPhone 15 Pro Max / iOS 27.0.1 was connected with developer mode
enabled and was locked. No new candidate was installed or launched. The user
confirmed that no physical Lorcana cards are currently available. Real camera
capture, footer/foil handling, save/relaunch on hardware, first-unlock protection,
spoken VoiceOver and sustained performance remain **NOT RUN** for this candidate.
Simulator rendering and public source images cannot close these checks.

Current app wiring uses `UnprovenCloudRestorationReadinessSource` in
[`CollectionStorageBootstrap.swift`](../../TradingCardScanner/Services/CollectionStorageBootstrap.swift)
at line 337; [`PrivacyAndSupportSettingsView.swift`](../../TradingCardScanner/Views/PrivacyAndSupportSettingsView.swift)
at line 25 says
1.0 stores the collection on this device and iCloud sync is unavailable.
Consequently, live mixed-client CloudKit convergence is a **future sync rollout
gate**, not a prerequisite for this on-device Lorcana release. Local storage
continuity and unknown-game preservation remain release responsibilities and
have the focused evidence above. The [CloudKit matrix](cloudkit-release-matrix.md)
and [schema audit](cloudkit-compatibility-audit.md) remain unexecuted for live sync.
No sync capability was enabled or schema changed by this work.

Remote catalog signing/hosting is also optional to the bundled release. Existing
transition contracts remain available; no production remote key or URL was added.
Held premium, promo, Quest, later-set and ambiguous records stay read-only and
unpriced. Broadening those classes is a separate coverage increment.

## HIG and App Store review

Applied the `swift-hig-appstore-review` workflow to this bounded rollout. The HIG
pass uses the inspected phone/tablet simulator flows from the normal-pricing
checkpoint: existing navigation, explicit finish selection, disabled held Add,
unavailable-pricing copy and a cleared refresh indicator. The footer-label defect
above was corrected; no additional confirmed HIG defect was found. Hardware interaction and spoken VoiceOver are
missing evidence, not passed checks. The App Store risk pass found these items:

| Title | Severity / risk / confidence | Evidence | Why it matters / recommended fix |
| --- | --- | --- | --- |
| App privacy/support publication incomplete | Major / Reject Risk / High | [`project.pbxproj`](../../TradingCardScanner.xcodeproj/project.pbxproj) submission URL settings are empty (Release at lines 1750–1751; ReleaseLocal at 1779–1780); [live privacy page](https://scan-stash.com/privacy) is HTTP 200 but explicitly covers the website/waitlist and defers mobile-app practices; [support route](https://scan-stash.com/support) is HTTP 404. | [Apple 5.1.1](https://developer.apple.com/app-store/review/guidelines/#privacy) requires an accessible app policy. Publish the completed app drafts, verify contact/retention details and live pages, configure both URLs, then check the release app and App Store metadata. Do not configure the website-only policy as the app policy. |
| Distribution candidate unavailable | Major / Advisory / High | Only a valid development identity and development profile were available. The exported IPA uses development signing and no CloudKit entitlement. | Development export is useful packaging evidence but cannot prove TestFlight/App Store delivery. Use the owner's distribution signing workflow and intended on-device release configuration, inspect the resulting entitlements/resources, then complete distribution acceptance. |
| Source/artwork publication scope unconfirmed | Major / Likely Question / Medium | [LorcanaJSON source site](https://lorcanajson.org/) references the Ravensburger community code and says charging for its content is prohibited; its generator's MIT license does not itself grant artwork rights. [TCGCSV FAQ](https://tcgcsv.com/faq) permits public JSON requests. | Public feed access establishes neither an unrestricted artwork license nor App Review authorization under [Apple 5.2](https://developer.apple.com/app-store/review/guidelines/#intellectual-property). Confirm the intended publication/attribution scope. Free 1.0 has no StoreKit or Lorcana paywall; this check does not assert that publication is prohibited or that authorization has already been obtained. |

The [app privacy draft](../legal/privacy-policy.md) now discloses the bundled
Lorcana metadata, public TCGCSV feed requests and referenced artwork hosts.
This is prepared copy, not a deployed policy or proof of provider retention.
The existing [legal publication checklist](../legal/README.md) owns those details.
No new permissions, account requirement, purchase flow or tracking SDK was added.

## Remaining release blockers and fix-first sequence

1. **Deferred by owner — 2026-10-14:** publish and verify the reviewed app
   privacy/support content and configure app/App Store Connect URLs when resumed;
   reconcile provider retention, contact details and App Privacy metadata.
2. Confirm source/artwork publication and attribution scope for the free app.
3. Complete hardware camera/ownership/performance/accessibility checks when an
   unlocked test device and representative physical cards are available. A lack
   of cards is an explicit evidence gap; no recognition accuracy claim is added.
4. Retain the green final simulator regression and corrected REQ-022 evidence
   above; obtain and inspect the intended distribution-signed candidate through
   the owner's release workflow. Hardware centering latency remains unmeasured.

Pre-submission checklist: verify supported/held scope in launch metadata; open
the live policy and support pages from the submitted build; inspect catalog and
privacy resources and entitlements in that exact distribution artifact; retain
sanitized hardware and TestFlight results. Existing repository-wide release
gates still apply; this is a Lorcana checkpoint, not full-app certification.

Open evidence: physical card availability, unlocked-device acceptance, actual
provider retention/rights confirmation, hosted app pages and distribution signing.
CloudKit and remote catalog delivery remain deferred unless their capabilities
are explicitly enabled for the candidate.
