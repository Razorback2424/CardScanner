# Workflow source review — 20 October 2026

**Status:** source review complete; the requested ReleaseLocal app build and
installation succeeded on 2026-10-20. The app was not launched, so workflow
runtime behavior remains unverified.
**Starting point:** HEAD `0c04c63` with existing local scanner, collection,
regression and documentation changes preserved.

The requested review followed major workflow entry points through their service
and persistence boundaries. At the end of that source-only review, no builds,
tests, simulator runs, purchases, publication, device operations, commits or
pushes had been performed. The later requested commits, build and install are
recorded below. Earlier native verification in the
[repair handoff](verified-bug-repairs-2026-10-20.md) predates the source-review
changes and does not validate them.

## Coverage

| Workflow | Source path traced |
| --- | --- |
| Launch and storage recovery | App preparation → storage policy/bootstrap → session generation → opening readiness and content services |
| Raw and slab scanning | Camera lifecycle and recognition → catalog resolution → printing/edition/finish choices → authorized collection writes → graded binding and receipts |
| Scan recovery and undo | Interruption → unresolved persistence/merge → retry or catalog selection → duplicate confirmation → ownership writer and inverse ledger operations |
| Price Check | Resolved scan → coordinator → catalog/graded/fallback quote → reference cache → result refresh and cancellation |
| Collection management | Projection/filter/detail → compare-and-set quantity or finish correction → serializer/store → ledger/activity → removal and restore |
| Browse and manual acquisition | Set/search/pagination → catalog details → raw, graded or sealed addition → pricing and undo |
| CSV portability | File selection → parse/identity consolidation → resumable isolated import → per-row commit/rollback → collection, failed-row and history export |
| Pricing and history | Target selection → foreground/background queue → exact mapped or fallback lookup → checkpoint and snapshot publication → individual market history |
| Portfolio | Epoch/day boundaries → replay/valuation → integrity status and daily closes → history range, accounting and contributions |
| Listing photos | Camera/picker → single/batch preparation → crop/output files → ZIP, inspection, sharing or Photos save → cancellation and cleanup |
| Guided centering | Image load → analysis → guide/rotation confirmation → export snapshot → artifact ownership and sharing |
| Purchases and settings | Product/entitlement loading → verified purchase/restore/update reconciliation → tool gates; settings deletion, diagnostics and external links |
| Catalog maintenance | Signed fetch → validation/two-slot storage → activation and consumer fencing; publisher signing and filesystem pointer updates |

## Repairs

1. **Listing-photo retry:** failed or cancelled front/back photo loads retained
   their picker item, so choosing the same asset again could not trigger a new
   load. The current request now releases that selection. A superseded request
   cannot clear a newer selection. See
   [EbayListingPhotosView.swift](../../TradingCardScanner/Views/EbayListingPhotosView.swift).
2. **Centering-photo retry:** the same retained-selection problem existed when
   the photo loader failed or returned into a cancelled task. The current load
   now clears its picker selection. See
   [CardCenteringView.swift](../../TradingCardScanner/Views/CardCenteringView.swift).
3. **CSV preparation ordering:** an older detached parse could replace a newer
   file's confirmation or error. Preparation now has a request ID checked on
   success and failure. See
   [ScannerSettingsView.swift](../../TradingCardScanner/Views/ScannerSettingsView.swift).
4. **CSV stale error publication:** the import success path checked the storage
   generation, while its failure path could publish into the shared coordinator
   after storage changed. Failure publication now uses the same generation
   guard, in the settings file above.
5. **Magic publication rollback:** the filesystem publisher checked only its
   optional caller baseline before overwriting `current.json`. A stale or
   omitted baseline allowed an older revision to replace a newer persisted
   pointer. It now reads the persisted pointer before any publication writes,
   rejects unreadable pointers and lower revisions, and rejects different bytes
   at the same revision. Identical repeat publication remains allowed when no
   stricter caller baseline rejects it. See
   [CatalogPublisher.swift](../../MagicCatalogCore/Sources/MagicCatalogCore/CatalogPublisher.swift).

## Requested device build and installation — 2026-10-20

The source-review changes were committed and pushed to `origin/main` before the
requested device build. Xcode 27.1 built the `TradingCardScanner-ProfileLocal`
scheme with the `ReleaseLocal` configuration for the paired iPhone 15 Pro Max.
The first attempt exposed a mismatch between the local provisioning profile and
the available Apple Development certificate. After the user's keychain
authorization, Xcode automatic provisioning resolved the mismatch and the app
build succeeded. `codesign --verify --deep --strict` confirmed the app signature.
CoreDevice installed bundle `com.seankeller.CardScanner` over the existing app;
the app was not uninstalled, reset or launched.

DerivedData, package caches and the build log remain on the external build
volume under `CodexBuilds/WorkflowReviewBuild-20261020/`. The app-target build
compiled the source-review fixes. No tests were run for those fixes, and the
earlier 167-test result applies to the certified-rescan/scanner-prompt repairs.
No device UI, purchase, provider or collection-data behavior was checked after
installation.

## Verification boundary

Changes were checked by reading their callers, state/generation guards, error
paths, related existing contracts and final diffs. Local document links and
`git diff --check` pass. The app compiles and installs, but the source-review
changes have no test-suite or post-install runtime evidence. No additional
concrete, high-confidence issues were identified in the traced paths. This does
not certify release readiness or close previously recorded runtime acceptance
gaps.
