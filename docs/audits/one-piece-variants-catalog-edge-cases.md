# One Piece variants and catalog inclusion audit

**Date:** 2026-10-05. `merge/one-piece-integration`, `f40e704` plus local changes.
**Status:** nine confirmed edge cases fixed; selected regression verification complete.
**Scope:** retained corpus and signed admission, recognition, physical-printing
choices, finish locks/correction, Browse membership/details, CSV and exact pricing.
The [implementation ledger](../plans/one_piece_code_implementation.md) remains
the execution authority; the [catalog design](../plans/one_piece_catalog_integration_plan.md)
governs physical identity and evidence.

## Confirmed defects and fixes

| Boundary | Reproduced failure | Result |
| --- | --- | --- |
| External market SKU | Different descriptive qualifiers let one TCGplayer product/lane claim two physical UUIDs. Numeric aliases could describe the same product too. | Collision checks use the numeric product/lane identity independently of titles/groups. Quote fingerprints, payload bytes and ownership keys retain their existing formats. |
| Duplicate mapping | Repeating an identical exact mapping passed admission, then the app refused to quote its ambiguous array. | Duplicate mappings reject the candidate before activation. |
| Product appearance | Another printing/card's observation could authorize membership merely by mentioning the product. | Membership requires catalog evidence matching number/language and anchored to the exact printing's source alias or retained identity review. Explicit retained review preserves historical appearances after alias reassignment. |
| Product/finish metadata | Blank product labels, padded IDs and invalid/noncanonical calendar dates passed admission. | Reject malformed product/variant identifiers and product metadata; parse release dates strictly as UTC calendar days. Unknown dates remain optional. |
| CSV finish | A row could import a verified multi-finish printing without selecting any finish, creating a separate unknown-finish ownership key. | New One Piece imports require an explicit supported finish and report a row error. Denial leaves existing quantity, inventory and activities unchanged. Existing rows are not rekeyed. |
| English price authority | Verified Japanese printings entered the English runtime's managed quote map despite being unavailable to its catalog/Browse/import. | Price authority applies the same verified-English acquisition scope. |
| Release metadata | Resolved One Piece cards retained release order zero, losing their release date in scan/add and imported metadata. | Use the primary physical release's UTC day order, including when browsing a later product appearance. |
| Older recovery choices | Optional artwork/footer fields decoded successfully, but the shared catalog's equality guard rejected a valid older multi-printing choice. | Accept omitted optional fields while requiring all original identity/presentation fields to agree. Supplied new evidence and changed release labels still fail. |
| Finish lock identity | A case-insensitive lock match could return the lock's finish instead of the selected printing's supported finish. | One Piece requires an exact finish ID; successful locks return the catalog's finish metadata. Legacy games retain their case-insensitive fallback. |

## Retained inclusion snapshot

The checked-in registry contains 2,692 canonical cards and 2,745 physical UUIDs:
2,490 verified English printings, 224 provisional and 31 conflicted records.
Eligible finishes comprise 1,639 Normal-only and 851 Foil-only printings.
Nineteen numbers have multiple eligible physical printings; 221 numbers have
no eligible printing. There are 1,961 exact aggregate USD TCGCSV mappings.
All canonical physical-coverage flags remain false.

The read-only corpus pass found no duplicate external SKU assignments among
current exact mappings, no unusable identical collector labels among eligible
choices, and valid subject/printing anchors for all fourteen explicit product
appearances. Primary release membership also supplies Browse groups. These are
checks of the retained snapshot, not fresh upstream discovery or worldwide
completeness. Catalog data, statuses, permanent UUIDs and finish keys were not
rewritten or promoted during this pass.

Held records remain available as evidence/history. Held-only numbers go to
recovery; provisional/conflicted/superseded/foreign printings cannot become
acquisition options. DON!!, non-English acquisition, optical finish assignment,
unreviewed special/stamped/revision coverage and provider/release rights retain
their separate gates. A finish lock answers only the selected printing's finish
question, never its release/artwork identity.

## Verification

- Before fixes, three core cases failed on SKU collisions, appearance admission
  and product metadata; duplicate mapping also failed its separate recheck.
  Three app cases reproduced missing finish, foreign price authority and zero
  release order; the older-choice case failed through the shared catalog.
  A final dedicated resolver test reproduced the case-sensitive finish-lock
  mismatch before its fix.
- After fixes, all four focused core cases passed, followed by all **44 core
  tests**, including the retained full corpus, alias reassignment/supersession,
  finish evidence, signature and publication checks.
- All **49 offline Python tests** pass across One Piece discovery, capture,
  reconciliation, finish evidence, exact mappings and local review tooling.
- All **five affected app cases** pass, including the real ST11/ST16 finish-lock
  boundary and rejection without quantity/history changes. An intervening app
  test compilation caught a result-property typo in the new assertion; it was
  corrected before that passing run.
- All **389 selected app tests** passed before the final finish-lock identity
  adjustment. The selection includes a full-corpus walk: every eligible printing
  must remain reachable in Browse, every canonical number must resolve/ask or
  remain incomplete consistently, every admitted finish must round-trip CSV,
  and held/foreign records must fail direct resolution.
- After the last finish-lock adjustment, all **204 affected app tests** passed:
  74 One Piece, 96 scanner and 34 variant cases. This includes the full-corpus
  walk and the new exact-ID/catalog-finish lock regression. The 389-case run
  and this final affected recheck are separate passing selections.
- All 283 checked local Markdown links resolve; `git diff --check` passes.

Builds, results and logs remain on the external SSD under
`CardScannerBuild/OnePieceVariantAudit-2026-10-05/`, with `CoreBuild`,
`App-Focused-Final.xcresult`, `App-Regression.xcresult` and
`FinishLock-Final.xcresult`.
This pass does not establish physical-camera accuracy, live provider coverage,
CloudKit behavior, device performance or release readiness.
