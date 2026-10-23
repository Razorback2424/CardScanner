# Five-game launch readiness follow-up

**Date:** 2026-10-23. **Candidate:** `c4e1198` plus this working tree.
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
| StoreKit implementation | Existing `CollectorToolsStore` and `CollectorToolsTests` include local purchase/relaunch/restore/refund and two-card ZIP coverage. New execution evidence is recorded below; local simulation does not establish sandbox, TestFlight or production availability. |
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

### Verification on this working tree

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
  the local purchase/relaunch/restore/refund/ZIP test pass. The test now aborts
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
