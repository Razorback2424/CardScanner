# PRB-01 mapping-only revision 6 candidate

This unsigned candidate adds 251 exact marketplace mappings on the signed
production revision 5 predecessor. The supplied inventory has 252 unique
printings and product IDs (236 Foil, 16 Normal). The per-row gap report records
all decisions. No printing identity, existing mapping, or other registry state
changed; this includes the unrelated PRB-01 printings requiring review.

The single hold is Sanji PRB01-001, product 586607: the inventory's reviewed
title is `Sanji`, while the captured TCGCSV product title is `Sanji (PRB01-001)`.
The requested exact-title rule prevents promotion despite the inventory's
independent evidence links. No retailer image hash was invented for this row.

Two mapped Foil lanes have a null captured market price: OP02-013 Portgas.D.Ace
(587709) and OP05-119 Monkey.D.Luffy (587963), both non-textured Manga artwork.
Their exact lanes exist; the capture does not establish an available quote.

The retained capture has matching source-build markers, timestamps, and hashes.
The 251 CoreTCG/Bandai observation IDs and bytes match both the signed baseline
and `../prb02-revision-5/observations.json`. The supplied research validation
JSON covers the same 252 UUIDs, but explicitly marks all 252 unresolved and
zero mappings approved. The CSV marks them verified; the relationship between
these conflicting handoffs needs owner clarification before relying on the
candidate. The separately described findings Markdown was not supplied.

Reproduce with `scripts/prepare_one_piece_prb01_market.py` using the retained
predecessor, inventory, and capture, then build with the One Piece publisher
against the decoded predecessor at revision 6. The publisher validated this
candidate. Signing, publication, and activation are outside this change.
