# Current catalog, pricing, and diagnostic checkpoint

**Source review:** 2026-11-15, `main@a8d3103ab24b` (commits dated
2026-11-16 UTC). This is a source/documentation checkpoint, **not**
a newly run test suite, complete catalog census, signed-publication receipt,
or release acceptance.

## Five most recent commits in main history

| Commit | Observed implementation | Important limit |
| --- | --- | --- |
| [`a8d3103a`](https://github.com/Razorback2424/CardScanner/commit/a8d3103ab24b05bb23b1fbf38ebd094e0ab77c5b) | Merged One Piece printing reconciliation with exact-price detail changes. | Merge conflicts involved the catalog-health workflow and exporter; compare the **merged tree**, not either parent alone. |
| [`3372ee69`](https://github.com/Razorback2424/CardScanner/commit/3372ee69e1fb3b29ea4ab24a19b595891f243d7d) | Added earlier copies of four catalog-health files on the integration branch. | The merge kept PR #37's versions of all four files. |
| [`c149d50d`](https://github.com/Razorback2424/CardScanner/commit/c149d50da094a57fedd648b5707bac25cc985870) | Replaced six pinned EB-05 titles with paired retailer and marketplace treatment checks. | The shared feed validator already rejected duplicate price lanes. |
| [`24fb6382`](https://github.com/Razorback2424/CardScanner/commit/24fb63821b563d61c625eb698667f5889ef261b1) | Added current exact JustTCG quote fallback in card detail and safe owned-price fill. | A chart's historical observations do not themselves qualify as a current exact quote. |
| [`c114ff6a`](https://github.com/Razorback2424/CardScanner/commit/c114ff6a45312769fdaff54b0493f0362788ffe8) | Merged active iPhone catalog-health CSV export and selected simulator regression test. | A configured test is not a newly observed passing run. |

The list follows GitHub's chronological main-history view, including commits
reached through the merge. For first-parent-only releases, review merge
commits separately from their feature-branch parents.

## Current One Piece authority

The signed production seed exists at
[`TradingCardScanner/OnePieceCatalogSeed/one-piece-catalog-release.json`](../TradingCardScanner/OnePieceCatalogSeed/one-piece-catalog-release.json).
[`Config/OnePieceCatalogProduction.xcconfig`](../Config/OnePieceCatalogProduction.xcconfig)
currently specifies `remote-authority`, a dedicated public-key pin and
`ONE_PIECE_COLLECTION_WRITES = YES`. Its Release comments specify
`NO_CLOUDKIT` on-device storage. That supersedes historical assertions
that production registration or collection writes are always disabled.

[`publisher/one-piece/production/revision-4/candidate.json`](../publisher/one-piece/production/revision-4/candidate.json)
is a retained **unsigned** OP-18 discovery candidate; a candidate is not
a signed or active device release. Discovery entries and official preview
images can be shown without granting verified physical printing identity,
finish, collection writes, or market mapping. Do not infer the device's active
revision from the repository alone.

The [One Piece publisher guide](../OnePieceCatalogCore/README.md) and
[release resource guide](../TradingCardScanner/OnePieceCatalogSeed/README.md)
are the current operator references. The
[October production proposal](release/one-piece-production-setup-2026-10-23.md),
[EB-05 candidate inventory](audits/one-piece-eb05-candidate-inventory-2026-11-15.md),
and [Browse preview audit](audits/one-piece-browse-artwork-2026-11-14.md)
remain **dated evidence**, not automatic authorization to publish.

## Prices and historical charts are different evidence

A selected catalog printing/finish may have a valid historical JustTCG chart
while its current catalog price is unavailable. The new detail path can ask
for a **current**, uniquely matched exact product/variant quote and display it.
For owned cards it only fills a missing eligible price when the ownership,
current catalog authority, storage generation and source-identity checks
remain valid. Existing eligible owned prices are not overwritten by this
missing-price fill. A withdrawn, expired, ambiguous, non-USD or merely
historical observation does not establish a current quote.

Source:
[`PriceFallbackQuoteResolver.swift`](../TradingCardScanner/Services/PriceFallbackQuoteResolver.swift),
[`CardMarketHistoryService.swift`](../TradingCardScanner/Services/CardMarketHistoryService.swift),
[`CatalogCardDetailView.swift`](../TradingCardScanner/Views/CatalogCardDetailView.swift),
[`CollectionCardDetailView.swift`](../TradingCardScanner/Views/CollectionCardDetailView.swift),
and [`JustTCGContractTests.swift`](../TradingCardScannerTests/JustTCGContractTests.swift).

The owner's **paid JustTCG** choice for eventual launch is separate from the
current credential implementation. The app's transport still checks for
a configured API key; the [launch contract](release/launch-contract.md)
does **not** yet certify no-customer-key commercial pricing or distribution.

## Two different catalog-health reports

The iPhone report is exposed under **Settings → Diagnostics → Catalog Health →
Export Catalog Health Report** (Settings reorganized Nov. 19, 2026). Its **Check catalog prices** toggle starts off (changed Nov. 16,
2026) and, when on, makes explicit per-finish checks, subject to provider and
cache limits. **Export Price Audit** prices only mapped finishes for one game
or set; see the [catalog-health guide](../scripts/CATALOG_HEALTH.md). When off,
`not_checked` is **not** a missing quote. Magic page failures and deferred
sets must not be interpreted as a complete enumeration. The export can
include all five game catalogs even if the owner has no cards.

The repository-only `scripts/catalog_health_export.py` creates an offline
retained-source inventory, actionable exceptions, issue summary, census
findings, and metadata. It is not a device export. The manual
[`Catalog Health Audit`](../.github/workflows/catalog-health-audit.yml)
workflow can optionally capture mapped TCGCSV feeds. It preserves a
`catalog-run-failure.json` on validation failure; do not call a failed or
partial run complete. See the [operator guide](../scripts/CATALOG_HEALTH.md)
and [failure classifications](../scripts/CATALOG_HEALTH_FAILURE_MODES.md).

For EB-05, [`prepare_one_piece_eb05_market.py`](../scripts/prepare_one_piece_eb05_market.py)
requires independently verified physical/retailer evidence, exact product
identity and title treatment, and **one** matching Normal/Foil quote lane.
The feed validator rejects duplicate lanes before matching. The live-image
audit and its report are read-only research.

## Verification

On November 15, the Release simulator build of `a8d3103a` passed on Xcode 27.2.
On an iPhone 17 Pro simulator running iOS 27.0, 302 targeted
`DebugRemoteLocal` tests passed across JustTCG, Browse, card detail, and
catalog-health export. The working tree included one additional local
JustTCG write-guard test. The EB-05 and offline catalog-health Python suites
passed all 10 tests. The retained EB-05 feed reproduced all 64 committed
mappings, including the six previously pinned titles.

Full-target, physical-device export and live-provider acceptance remain open.
A fresh device export is needed to diagnose the November 15 Magic failures.
The current [launch contract](release/launch-contract.md) remains the release
acceptance authority. Older test counts and open gates should not be silently
reinterpreted as current successes.
