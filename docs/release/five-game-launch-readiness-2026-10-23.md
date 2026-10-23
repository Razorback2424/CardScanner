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
| StoreKit implementation | Existing `CollectorToolsStore` and `CollectorToolsTests` include local purchase/store reconstruction/restore/refund and two-card ZIP coverage. Store reconstruction occurs in one process; actual app termination/restart remains unrun. Local simulation does not establish sandbox, TestFlight or production availability. |
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

### Remaining bounded manual acceptance — unrun

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
