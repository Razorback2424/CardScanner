# Workflow source review — 20 October 2026

**Status:** source review complete; fixes have not been compiled or run.
**Starting point:** HEAD `0c04c63` with existing local scanner, collection,
regression and documentation changes preserved.

The requested review followed major workflow entry points through their service
and persistence boundaries. No builds, tests, simulator runs, purchases,
publication, device operations, commits or pushes were performed. Earlier native
verification in the [repair handoff](verified-bug-repairs-2026-10-20.md) predates
these changes and does not validate them.

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

## Verification boundary

Changes were checked by reading their callers, state/generation guards, error
paths, related existing contracts and final diffs. Local document links and
`git diff --check` pass. Runtime behavior and compilation remain unverified by
explicit user instruction. No additional concrete, high-confidence issues were
identified in the traced paths. This source-review completion does not certify
release readiness or close previously recorded runtime acceptance gaps.
