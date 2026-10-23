# Five-game launch readiness follow-up

**Date:** 2026-10-23. **Candidate:** `872dbf2` plus the focused working-tree follow-up below.
**Status:** bounded identity safeguard and local StoreKit acceptance verified;
full five-game launch remains blocked by the gates below.

This reviews the supplied `cardscanner_launch_readiness_2026-10-23.txt` against
its exact pinned checkout. Recommendations in the attachment are review input;
they do not establish source rights, release approval, catalog authority or
permission to change the agreed product scope. Full five-game support remains
the requested outcome. A reviewed subset is not adopted as a substitute.

## Validated findings

| Finding | Current evidence and disposition |
| --- | --- |
| One Piece absent from App Store Release | Confirmed: Release includes `PokemonCatalogProduction.xcconfig`, which includes the disabled One Piece configuration. `ownerRuntime` is compiled only with `LOCAL_ONLY_SIGNING`. Production keys/origin/activation and write acceptance remain open; local review credentials must not be promoted as production authority. |
| Known One Piece singleton ambiguity | Confirmed modeled risk: P-001 retains verified winner and provisional participant identities, while the adapter automatically selected the filtered winner. Require explicit choice when a retained active sibling is ineligible. Keep valid single-printing families automatic, even when global coverage is incomplete. Physical misidentification has not been reproduced. |
| Lorcana later physical coverage | Recomputed local payload: 1,749 physical records across sets 1–8. Parsed discrepancy CSV: 1,833 discovery-only rows; sets 9–14 have 243, 242, 243, 243, 247 and 242 rows respectively. These are source records, not a certified physical-printing denominator. |
| Hyperia City release status | Corrected: the [official announcement](https://www.disneylorcana.com/en-US/news/2026/09/hyp-press-release/) gives October 16 prerelease and October 23 general availability. Set 14 belongs in the current released-set reconciliation. |
| Privacy/support configuration | Confirmed: Release build settings contain empty URLs. Publication and mailbox operation need actual acceptance; source placeholders are not working pages. |
| StoreKit implementation | Existing `CollectorToolsStore` and `CollectorToolsTests` include local purchase/store reconstruction/restore/refund and two-card ZIP coverage. The later app-process follow-up verifies owned-state reload and paid access across termination/relaunch; the Files destination follow-up closes local save/reopen acceptance. Fresh purchase provenance remains open. Local simulation does not establish sandbox, TestFlight or production availability. |
| Other game coverage and pricing | Existing source and dated evidence support the attachment's qualified descriptions. No new exhaustive physical identity census or live pricing census was performed. Yu-Gi-Oh pricing remains dated bundled data. |

The installed Xcode reports 27.1. Apple's [upload SDK requirement](https://developer.apple.com/news/?id=ueeok6yw)
requires iOS/iPadOS 26 SDK or later from April 28, 2026. Tool availability alone
does not establish a valid distribution archive or upload.

## Local safeguard and acceptance

The One Piece change is bounded to numbers with known retained provisional or
conflicted siblings. It presents only verified printings and rechecks the same
decision at automatic acquisition. Explicit resolution, Browse and persisted
choices remain supported; superseded history does not create a live ambiguity.
This addresses the concrete modeled witness without claiming complete coverage
or requiring an exhaustive catalog for every automatic scan.

The reviewed corpus contains 33 numbers with one verified printing and at least
one other active ineligible printing. The safeguard covers those known
ambiguities; it does not prove absence of unrecorded alternates or distinguish a
physical participant automatically.

### Earlier verification recorded at `872dbf2`

- **Native pass:** Xcode 27.1, iPhone 17 / iOS 27 Simulator, Debug:
  `OnePieceIntegrationTests` 91 passed and `CollectorToolsTests` 8 passed;
  one finalized selection of **99 tests, zero failures**, `xcodebuild` exit 0.
  External SSD result: `CardScannerBuilds/yugioh/launch-readiness-final.xcresult`.
- P-001 rejects automatic acquisition, stays unsaved until explicit winner
  choice, then saves/reopens/exports the exact winner UUID and foil finish.
  Provisional, conflicted and quarantined sibling regressions pass. Real-corpus
  retail/starter/booster expectations now exercise explicit selection where a
  known held sibling exists. Ordinary unambiguous singletons still save directly.
- **StoreKit setup repair:** the first unchanged run returned no products and
  stalled at restore; it was interrupted. The shared Debug launch scheme lacked
  a StoreKit configuration reference. Attaching `CollectorTools.storekit` makes
  the local purchase/store reconstruction/restore/refund/ZIP test pass. The test now aborts
  early on missing products and verifies twenty JPEG signatures, decodable images
  and exact ordered filenames across two card folders. Archive/Release actions
  retain their production configurations.
- An intermediate native selection exposed three obsolete direct-save/picker
  expectations, with 39 assertion failures. Those expectations were corrected
  for the new policy; the finalized pass above supersedes that run. Counts from
  different runs are not accumulated.
- **Resolved Release settings:** One Piece mode `disabled`, writes `NO`, URL and
  pins empty; no `LOCAL_ONLY_SIGNING`; privacy/support URLs empty. `SDKROOT`
  resolves to iPhoneOS 27.1. These confirm configuration blockers, not readiness.
- Markdown local links, shared-scheme XML and `git diff --check` pass. Attempts
  to read the planned public privacy/support URLs through web retrieval were
  unsuccessful; their current publication/content/mailbox state is unverified.

- **Normal Release build:** `xcodebuild build`, configuration `Release`, generic
  iOS Simulator, `CODE_SIGNING_ALLOWED=NO`, succeeded with exit 0 for arm64 and
  x86_64. Inspection of the resulting app confirms display name `ScanStash`,
  One Piece disabled, writes `NO`, empty pins/privacy/support URLs and no
  `one-piece-catalog-release.json` resource. This verifies compilation and the
  actual production-path packaging gap; it is not a distribution archive.
- **Production preparation core:** all 46 `OnePieceCatalogCore` package tests
  pass in a separate macOS run, exit 0. The unsigned bootstrap candidate also
  validates and replays byte-identically through the existing publisher CLI.
  These are a different selection from the 99 native app tests above.

No new physical-camera, provider-census, sandbox/TestFlight, distribution-signing,
production activation or source-rights acceptance is claimed.

## Remaining finish sequence

1. Establish the measurable English physical-single denominator across ordinary
   sets, starters, promos, alternate art and marketed finishes. Reconcile other
   languages and exceptional objects separately without silently shrinking scope.
   A missing price does not invalidate a supported ownership identity.
2. Complete Lorcana sets 9–14 and special distributions using release-level
   physical/finish evidence, exact joins, durable UUIDs and held exceptions. Keep
   the 373 earlier/special/Quest rows visible in the discrepancy ledger.
3. Prepare and approve One Piece production signing, retained registry, hosting,
   pins and collection-write activation using the
   [existing acceptance authority](../plans/one_piece_release_acceptance.md).
   Revision 3 and held pricing decisions remain separate review work.
4. Freeze the resulting candidate and execute all five games: identify/select,
   printing/finish/edition, save, duplicates/additional copies, quantity edits,
   corrections, delete/Undo, failed-write retry, reopen and mixed-game Files CSV.
   Check exact USD/currency/freshness semantics and Price Check without ownership.
   Include physical P-001 participant/alternate captures and ordinary singleton
   samples. Fixture scans do not replace physical camera evidence.
5. Finish paid-tools interruption/offline/pending/accessibility acceptance and
   real sandbox/TestFlight purchase lifecycle, including retained prepared work,
   free one-card output, ordered two-card ZIP and guided centering output.
6. Owner-controlled gates: commercial catalog/artwork/export permission, published
   privacy/support and accurate privacy metadata, paid agreement/tax/banking,
   product `com.seankeller.CardScanner.collectorTools`, review material, signed
   archive inspection, exact-build TestFlight acceptance and app plus first-IAP
   submission. No sale, submission or account change is claimed here.

Production collections remain on device for v1; future sync gates do not become
launch blockers unless sync is enabled. The existing November 2, 2026 Colorado
commercial target remains a target, without an approval or sale guarantee.

## Owner-directed production preparation

The owner requested a dedicated production setup using the existing host, with
approval before creating/provisioning the production key or publishing. The
[concrete production proposal](one-piece-production-setup-2026-10-23.md) identifies
the validated unsigned revision-1 candidate, exact SHA-256, protected environment
and secret configuration, shared-host deployment changes and app resource/pin
requirements. The [receipt](one-piece-production-candidate-2026-10-23.json) retains
2,748 printings and 2,367 exact mappings. Key material and production publication
remain untouched; the app stays disabled for production One Piece.

## Final acquisition boundary follow-up — 2026-10-23

Base: `872dbf2b170dfdfa7eea46314f14e77839a417a4`, plus the uncommitted focused
changes in this checkout. The two supplied review/prompt files were treated as
proposals to validate. No production provisioning or activation is authorized
by their contents.

The retained automatic-finish gap was reproduced using disk-backed SwiftData,
a signed revision-2 coordinator activation, and the container-bound snapshot
publication path. With the reviewed One Piece gates unwired, selecting the old
finish incorrectly committed one collection row, quantity event, activity and
success signal. `acquisition-baseline-repro.xcresult` records one failing test
with five assertion failures. The first harness attempt stopped at an invalid
fixture key prefix and is not evidence of the product defect.

The writer now checks current One Piece acquisition authority synchronously
inside `CollectionWriteSerializer`, including automatic versus explicit
printing resolution and the selected finish. Bound authority publication uses
the same serializer. There is no await between that check and the save.
Scanner preflight/retry also revalidate; rejection preserves printed evidence
in Needs attention for a new lookup instead of retaining a stale automatic
commit. No scan-generation reset is needed: still-valid explicit selections
can survive activation, while stale automatic selections cannot bypass it.
Rebasing validates the original identifier fields and changes only generation.
Known held siblings require choice; unknown global completeness alone does not.

The StoreKit test is named for store reconstruction rather than app relaunch.
Its ZIP acceptance now extracts all central-directory entries (stored or
deflated), checks the exact twenty relative JPEG paths beneath the two card
folders (the platform ZIP omits directory entries), decodes every archived JPEG with positive dimensions, and
compares extracted bytes to the generated originals. It does not establish
system share presentation or a completed destination handoff.

The six new One Piece regressions are:

- `testRetainedAutomaticFinishRequiresCurrentPrintingChoice`
- `testFailedAutomaticSaveRetryRequiresCurrentPrintingChoice`
- `testRetainedExplicitFinishSurvivesKnownHeldSibling`
- `testRetainedExplicitFinishRejectsWithdrawnIdentity`
- `testSerializedWriterRejectsAutomaticAcquisitionAfterScannerPreflight`
- `testSerializedWriterRejectsRetiredExplicitIdentityWithoutChangingHistoricalOwnership`

They cover coordinator/snapshot activation, live and retry persistence,
post-preflight authority change, reopen consistency, success/receipt suppression,
exactly-once retry, and preserving historical ownership/Undo while rejecting
removed, superseded, provisional, conflicted or quarantined acquisition targets.
Existing P-001, ordinary singleton, explicit-choice and persisted-recovery
tests remain part of the selected integration suite. Test fixtures now install
the same collection authority as the app and explicitly mark chosen ambiguous
printings; missing writer authority is not bypassed for tests.

### Follow-up execution record

Xcode 27.1, Debug (`DEBUG LOCAL_ONLY_SIGNING`), iPhone 17 Simulator / iOS 27.0,
normal local ad-hoc simulator signing. No distribution signing was performed.
The machine-local destination UUID is retained in the external command log,
not committed here. The final command uses that value as
`CARD_SCANNER_SIMULATOR_ID`:

```sh
xcodebuild test -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner -configuration Debug \
  -destination "platform=iOS Simulator,id=$CARD_SCANNER_SIMULATOR_ID" \
  -derivedDataPath '/Volumes/Keller Family Photos/CardScannerBuilds/yugioh/DerivedData' \
  -resultBundlePath '/Volumes/Keller Family Photos/CardScannerBuilds/yugioh/acquisition-verified.xcresult' \
  -only-testing:TradingCardScannerTests/OnePieceIntegrationTests \
  -only-testing:TradingCardScannerTests/CollectorToolsTests \
  > '/Volumes/Keller Family Photos/CardScannerBuilds/yugioh/logs/acquisition-verified.log' 2>&1
```

Intermediate runs are not accumulated into a pass count:

- `acquisition-baseline.xcresult`: fixture key-prefix error before the witness.
- `acquisition-baseline-repro.xcresult`: reviewed gates unwired, one test fails
  with five assertions proving the stale automatic commit; exit 65.
- `acquisition-fixed.xcresult`: 105 tests, 32 assertion failures across fixture
  authority/explicit-selection assumptions, finish-label comparison, retired
  fixture validity, and missing local StoreKit product in the unsigned run.
- `acquisition-final.xcresult`: all 97 One Piece tests pass; nine Collector Tools
  tests execute with two failures, both expecting explicit ZIP directory entries.
  The JPEG extraction/decoding and real local StoreKit lifecycle complete.
  The final ZIP expectation uses the actual exact twenty-file entry set.

**Final pass:** `acquisition-verified.xcresult`, **106 tests, zero failures**:
97 `OnePieceIntegrationTests` and nine `CollectorToolsTests`; `xcodebuild` exit 0.
The latter includes seven injected-client tests, one real local `SKTestSession`
lifecycle test using the production StoreKit adapter, and one independent ZIP
extraction test. Final test execution finished at 14:18 America/Chicago on
2026-10-23. This is fresh focused simulator evidence; the earlier 99-test result
remains a separate historical selection. Markdown local links and
`git diff --check` also pass.

All named bundles and matching `logs/*.log` are under external SSD
`/Volumes/Keller Family Photos/CardScannerBuilds/yugioh/`. These results concern
the base SHA plus local changes, not a committed or published release.

### Earlier bounded manual checklist — historical at `bb72741`

The current XCTest harness owns and clears its local StoreKit session in one
app process; it has no controlled cross-process purchase/share fixture. Do not
infer restart from reconstruction or add an entitlement override as proof.

1. In Xcode, select `TradingCardScanner`, Debug, an iOS Simulator, and Run's
   local `CollectorTools.storekit` configuration. Keep this distinct from any
   later sandbox/TestFlight run, which must use the real store configuration.
2. Launch normally, open **Pro → Collector Tools**, complete the local purchase,
   and confirm the owned state and access to Card Centering and a two-card photo
   batch. Record build identity and simulator/runtime.
3. Stop the app process completely without resetting transactions, deleting the
   app, or clearing its data. Relaunch the same app/configuration; record new
   process identity. Before buying/restoring, verify ownership reloads through
   `StoreKitCollectorToolsClient.currentOwnership` and both paid tools unlock.
   Record loading/offline behavior separately; do not inject ownership.
4. In **Pro → eBay Listing Photos**, use synthetic front/back samples to prepare
   a two-card batch, open its ZIP share action, and record whether the system
   sheet presents. Cancel once and verify the prepared work remains usable.
5. Open sharing again and choose **Save to Files**, select an available local
   folder, and complete Save. Reopen that saved ZIP in Files and verify the
   two named card folders and ten ordered JPEGs per card. Record destination
   handoff separately from share-sheet presentation. Check the single-card
   free export separately when unowned.

Neither step 3 nor steps 4–5 were completed in this session. Simulator results
do not certify physical-device, third-party destination, real-store,
TestFlight, or production product availability. Production One Piece remains
disabled; signing, keys, pins, publication and pricing scope are unchanged.

## App-process and Files acceptance follow-up — 2026-10-23

**Candidate:** clean `bb72741e19fe69ce12ca5ae323a99c8712ff73e0` at entry,
remote `Razorback2424/CardScanner`, reviewed checkout path unchanged. The three
commits after `872dbf2` contain the supplied eight-file review snapshot:
`git diff --binary 872dbf2..HEAD` SHA-256 is exactly
`e68040ccaa6c4f296300aad095744b06ebca89a3cfe045ac58f70d676f9e3312`.
Entry unstaged/staged diff is empty (SHA-256
`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`).
No pre-existing changes or untracked files were present.

The existing external `logs/acquisition-verified.log` was read, not rerun.
Its SHA-256 is `e23721bcb8745f8e9ceb635705ce54894ab65f6dfccdf7b33be6780e1bbb4dd4`;
it records **106 passed, zero failed**, comprising 97 One Piece and nine
Collector Tools cases. The exact reviewed-delta match establishes relevance
to this candidate. These remain historical XCTest results, not new UI passes.

### Build and process evidence

Used existing **iPhone 17 / iOS 27.0 Simulator**, Xcode **27.1 (27A9275)**,
Debug app version **1.0**. Installed the
existing 14:16 external artifact from
`CardScannerBuilds/yugioh/DerivedData/Build/Products/Debug-iphonesimulator/TradingCardScanner.app`;
the previously installed Simulator binary differed and was excluded from
acceptance. Installed and external `TradingCardScanner.debug.dylib` match at
SHA-256 `756f9a92c05805de7f776b5c78db9908d26e3dbb9fa1560c70211370331fc8a6`.
Launcher executable hash is
`d8d6a524785266224e336dc967d9992e5d722f29ec1b6762b3e8f417cbefb2bd`.
No new build or XCTest run was needed; another project's subsequent external
build was left running.

All accepted launches used existing `-ui_debug_route YuGiOhAcceptance`, with
its separate collection and no injected scan. Earlier exploration also used
the isolated synthetic `LorcanaReview` route. Neither grants ownership.
The shared StoreKit scheme was temporarily pointed at the existing executable
with isolated arguments for Xcode Run Without Building; it was restored
byte-for-byte before documentation edits. No transactions or acceptance data
were cleared between owned-state checkpoints.

| Check | Observed result and limit |
| --- | --- |
| Purchase/interruption | In PID `50377`, Pro → Collector Tools showed $9.99; one purchase action reached “Contacting the App Store…” with purchase/restore disabled. The process was subsequently terminated. No second purchase or Restore action was sent. A completed purchase confirmation and local transaction identifier/environment were not captured; fresh local purchase completion and transaction-count reconciliation remain unverified. |
| Ownership before restart | Following an Xcode local-configuration launch attempt (PID `51811`) and direct launch PID `52218`, the offer reported **Collector Tools unlocked**, and centering opened Take Photo / Choose Photo / Choose File. This uses the production adapter, without an ownership override. It does not establish when the interrupted purchase completed. |
| Actual owned-process restart | Stopped PID `52218`; `ps -p 52218` returned no process (exit 1). Relaunched as **PID `52845`**. Before buying/restoring, the offer again reported **Collector Tools unlocked**; centering source controls and Batch → Choose an even number of photos were accessible. **Entitlement reload and both paid access gates pass across an actual process boundary.** Fresh purchase provenance remains the separate gap above. |
| Share cancellation | Prepared four synthetic 900×1260 JPEG inputs into `Card-01` and `Card-02`. System sharing displayed “Listing photos” and Save to Files. Dismissed the popover once; the pairs, Start Over and generated ZIP remained. Reopening sharing succeeded without preparing again. |
| Background/resume | Opened system Files (PID `55046`), then resumed CardScanner using plain `simctl launch`, which returned the same **PID `52845`**. Prepared pairs and ZIP remained. This is background/resume, separate from termination and explicit generation cancellation. |
| Files handoff | Reopened sharing → Save to Files reached **On My iPhone** and created a new empty “untitled folder.” Naming, entering that folder and Save did not yield a verifiable final copy through available input tooling. A SaveToFiles extension **temporary staging ZIP** exists; it is not a completed destination save. **Completed isolated destination handoff remains unverified.** |
| Reopened content | Independently opened the app's retained temporary ZIP with Python ZipFile/Pillow: exact twenty relative JPEG paths, ten per card folder, every JPEG fully decoded with positive dimensions and bytes equal to generated originals. ZIP SHA-256 `fe11d996ea102dff0e8822ff0742ba5e00a3c8f90c663f4c23a34b279e28c74e`. **This is not reopening a saved Files destination.** |
| Unowned free export / other interruptions | Actual unowned single-card export, explicit purchase cancellation/pending approval, duplicate transaction counts and cancellation during photo generation were not completed. No new restart-persistence promise is imposed on temporary prepared photos. |

### Tooling limits and remaining manual steps

Simulator snapshots worked, but some reported successful taps without a
corresponding visible change. Native Device Hub controls were the fallback.
`wait_for_ui(textContains: "Save to Files", timeoutMs: 15000)` returned
`WAIT_TIMEOUT`; a later screenshot did show the share popover. The Files save
view remained absent from both automation trees; typing and Save attempts
returned unchanged trees. The later `wait_for_ui(textContains: "Save",
timeoutMs: 10000)` also returned `WAIT_TIMEOUT`. No final saved ZIP was found;
only the app output and SaveToFiles staging copy were found. These observations
do not isolate a product defect, so no app fix or regression was added.

Xcode initially retained a physical-device destination despite an attempted
Simulator row selection. The unexpected Run Without Building action was
stopped immediately; only after the destination visibly read iPhone 17 was
the Simulator attempt continued. No successful physical-device install,
collection access or device acceptance is established by this pass.
Native keyboard capture was restored to off. The generated images, app's
prepared batch, staging copy and empty test folder were left available.

Manual checklist recorded at `bb72741` (local StoreKit only; step 2 is now
completed by the Files destination follow-up below):

1. In Xcode, verify **iPhone 17 Simulator**, Debug and
   `CollectorTools.storekit` before Run; retain isolated collection arguments.
   Use StoreKit transaction management to record the local transaction and
   environment. Capture a fresh purchase completion through the production
   adapter in an unowned isolated test context, without clearing this pass's
   retained transactions. Verify exactly one request/transaction after
   cancellation, pending approval and interrupted-process reconciliation.
2. In **Pro → eBay Listing Photos → Batch**, reopen the retained batch share,
   choose **Save to Files**, create/enter an acceptance-only local folder and
   finish Save. In system **Files**, reopen that destination ZIP. Expect
   `eBay Listing Photos/Card-01` and `Card-02`, each containing
   `01-Front.jpg`, `02-Front-TL.jpg`, `03-Front-TR.jpg`, `04-Front-BR.jpg`,
   `05-Front-BL.jpg`, `06-Back.jpg`, `07-Back-TL.jpg`, `08-Back-TR.jpg`,
   `09-Back-BR.jpg`, `10-Back-BL.jpg`; decode all twenty destination JPEGs.
3. In a separately unowned isolated local context, **Pro → eBay Listing Photos
   → Single card**: choose synthetic front/back, generate and complete free
   export. During batch preparation, exercise **Cancel** separately from
   backgrounding and process termination; expect retained source pairs and no
   stale completed archive according to the current workflow.

**Final scope:** only this evidence ledger and `progress.md` changed. No source,
tests or scheme changes remain; no commit/push, production configuration or
catalog publication was performed. Local StoreKit evidence is not real
sandbox/TestFlight/production purchase proof. Next launch workstreams remain
**released Lorcana coverage** and **approved One Piece production setup**;
neither was begun in this bounded pass.

## Files destination save and reopen — 2026-10-23

**Candidate:** clean `14c1c95` at entry. Continued the retained synthetic
two-card batch on the existing **iPhone 17 / iOS 27.0 Simulator** without a
build, reinstall, purchase/restore action or new XCTest run. The installed debug
dylib still matches the earlier accepted artifact at SHA-256
`756f9a92c05805de7f776b5c78db9908d26e3dbb9fa1560c70211370331fc8a6`.

The Save to Files view was already inside the empty acceptance folder. A native
Device Hub tap on **Save** completed the handoff; the view subsequently
dismissed back to the retained batch. The first immediate screenshot was
unchanged, so completion was verified from the later UI and actual destination
rather than the tap response alone.

Opened system **Files** from the Simulator Home screen. Recents displayed the
133 KB ZIP; **Show in Enclosing Folder** navigated to
**On My iPhone → CardScanner-Acceptanc** (the actual retained folder spelling).
Tapped **eBay Listing Photos.zip** in that destination. Files extracted
**eBay Listing Photos**, and opening it displayed **Card-01** and **Card-02**,
each labeled **10 items**. Opened Card-01 and observed the numbered front/back
JPEG thumbnails. Extraction was performed by Files, not by the verification
script.

Independent read-only Python ZipFile/Pillow verification of the destination
and Files-extracted output passed:

- The destination is a separate file in
  `group.com.apple.FileProvider.LocalStorage` under
  `File Provider Storage/CardScanner-Acceptanc/eBay Listing Photos.zip`,
  outside the app temporary directory and SaveToFiles extension staging.
- The **133,164-byte** destination ZIP equals the retained prepared archive;
  SHA-256 is
  `fe11d996ea102dff0e8822ff0742ba5e00a3c8f90c663f4c23a34b279e28c74e`.
  CRC checking passes, with exactly the twenty expected relative JPEG paths
  listed in checklist step 2, ten per card and no extra entries. Numbered
  filenames establish display order; ZIP member storage order is not sorted.
- Every archived JPEG and every JPEG extracted by Files fully decodes with
  positive dimensions. All twenty destination/extracted byte sequences equal
  their generated originals; the extracted tree contains exactly those files.

Local synthetic-only receipt:
`/private/tmp/cardscanner-files-20261023/saved-zip-verification.json`, SHA-256
`91909191bc2c70aacc3be9af8bc2ed646c146c24da6190e3c30f199aeaf910a8`.
The verification script is beside the receipt. The saved ZIP, Files-extracted
folders and app batch remain available; keyboard capture stayed off.

**Closed:** actual local Save to Files handoff and reopening/extracting that
saved archive in system Files. This supersedes the earlier unverified Files
handoff row and checklist step 2 only. The existing ownership restart is already
closed. Fresh purchase/interruption reconciliation, unowned single-card export
through the UI and cancellation during generation remain unperformed. Real
device, third-party destination, sandbox/TestFlight and production/catalog
gates remain separate.

Only this ledger and `progress.md` changed. The prior **106 passed, zero
failures** result remains historical and relevant; no broad test rerun, source
change, commit, push or production action was performed.
