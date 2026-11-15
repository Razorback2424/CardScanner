# One Piece Browse artwork findings

**November 14, 2026.** Source review at `fac57701` plus the local Browse and catalog-startup changes. Data baseline is signed One Piece production revision 4. The owner confirmed on an iPhone that OP-18 is visible, EB-05 prices work, and many entries labeled “Printing needs review” still have blank art.

## Findings

The remaining blanks have a separate cause from the earlier catalog startup bug. The [One Piece Browse adapter](../../TradingCardScanner/Games/OnePiece/OnePieceBrowseAdapter.swift) groups manufacturer discovery observations into one row per set and collector number. It explicitly sets the card and thumbnail URLs to nil for those rows. The detail route disables acquisition for the same records because they lack a reviewed physical printing and finish. The app can show a manufacturer preview while retaining that restriction.

I compared the signed discovery observations with 41 live Bandai English card lists. I used the existing [coverage parser](../../scripts/audit_one_piece_coverage.py) to check the series and its advertised inventory count. For each signed observation I matched the source series, exact artwork alias and printed number, then extracted the image URL from that specific official card modal. I retained the image query string and accepted a single official PNG reference per modal. No URL was inferred from a collector number.

| Scope | Signed observations with an official image reference | Browse rows | Rows with one image | Rows with multiple images |
| --- | ---: | ---: | ---: | ---: |
| All signed discovery entries | 684 of 684 | 609 | 556 | 53 |
| [OP-18](https://en.onepiece-cardgame.com/cardlist/?series=569118) | 119 of 119 | 119 | 119 | 0 |
| [EB-05](https://en.onepiece-cardgame.com/cardlist/?series=569205) | 32 of 32 | 26 | 22 | 4 |

EB-05’s multiple-image rows are EB05-006, EB05-010, EB05-046 and EB05-055. The 26 EB-05 discovery rows are separate from the 64 verified EB-05 printings whose exact market mappings and current quotes were checked previously. Of the 609 discovery rows, the highest counts are Promotion card (120), OP-18 (119), PRB-01 (58), Other Product Card (28) and OP-01 (27).

The count measures exact image references in the official HTML. A direct request for OP18-001 Karoo also returned HTTP 200 with an image/png response. The audit did not download every image or render a new app build. [Bandai card list](https://en.onepiece-cardgame.com/cardlist/)

## Overlap with verified printings

I joined discovery rows to verified English printings by exact product ID and collector number. The product membership includes the printing's primary release and its explicit product appearances, the same memberships used by Browse.

| Existing verified row in the same product | One official preview | Multiple official previews | Total |
| --- | ---: | ---: | ---: |
| Yes | 124 | 18 | 142 |
| None found | 432 | 35 | 467 |
| Total | 556 | 53 | 609 |

All 119 OP-18 rows lack a verified match in that product. For EB-05, 13 of its 26 discovery rows share a collector number with a verified row in the same product. Eleven of those 13 have a single official preview and two have multiple. The overlap identifies a shared collector number and product membership. Whether the rows show the same artwork or physical printing remains a separate check.

## Recommended scope

1. Extend the existing Bandai capture and candidate builder to carry the official preview URL on each exact discovery observation. Preserve the matching alias and source receipt. Validate the official host and image path when reading the signed data.
2. Evaluate every discovery observation in the product/card group. Show the single-image matches as representative previews and use them as a fallback for set thumbnails. Keep “Printing needs review” and the existing acquisition and pricing behavior. Preserve distinct verified and discovery identities where a collector number overlaps. The 53 multiple-image groups can retain their current presentation in the first pass.
3. Verify that the next candidate changes preview metadata only. Cover a single-image row, a conflicting multi-image row, a mismatched number or source, and a legacy discovery row with no preview. On the iPhone, check OP-18 and EB-05 thumbnails, card rows and detail, then confirm that verified EB-05 cards still display prices.

The existing local build uses recorded Bandai imagery for verified printings. The [One Piece implementation notes](../plans/one_piece_code_implementation.md) track public app artwork approval separately. This report introduces no app, catalog, or publication changes.
