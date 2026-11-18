# One Piece production revision 7 candidate

This unsigned candidate is built on the signed production revision 6
([`previous-envelope.json`](previous-envelope.json), the live envelope read on
2026-11-18). Its payload bytes match
[`../../prb01-revision-6/candidate.json`](../../prb01-revision-6/candidate.json).
Revision 6's PRB-01 and PRB-02 market mappings, with their evidence, are
carried forward unchanged. The publisher validated the candidate against that
predecessor at revision 7.

| | Revision 6 | Revision 7 |
|---|---|---|
| Physical printings | 4,383 | 6,993 |
| Canonical cards certified complete | 0 of 2,969 | 2,670 of 2,969 |
| Bandai rows still under "Printing needs review" | 684 | 173 |
| Known printings with a marketplace gap (not yet priced, or no photo) | 0 | 318 |

## What changed

The batches below are reproducible with the scripts named in the
[publisher guide](../../../../OnePieceCatalogCore/README.md). Inputs are a fresh
Bandai English card-list capture and a complete TCGCSV category 68 snapshot
(upstream build `2026-11-17T20:05:43+0000`). Both were retained privately
outside the repository.

- **Deck and premium-booster reprints.** Each is its own printing under the
  product that reprinted it, following how TCGplayer files them. Where
  TCGplayer lists no separate product, the original printing gains an
  appearance in the reprinting product instead.
- **TCGplayer listings as finish evidence.** A product with one Normal or Foil
  price lane counts as the finish source; this covers singles that are out of
  stock at CoreTCG.
- **Stamped event-pack printings** for 17 pre-release, release-event and
  anniversary events, pinned to Bandai's event pages in
  [`event-stamp-products.json`](../../event-stamp-products.json). Visually
  reviewed pairs are recorded in
  [`event-stamp-photo-reviews.json`](../../event-stamp-photo-reviews.json).
  OP-16 and OP-18 have no TCGplayer photos and rely on Bandai's page.
- **Promotional printings, one per stamped tier** (Participant, Finalist,
  Winner, Judge and similar), from the TCGplayer promo group, plus deck sets,
  demo decks, revision packs and Super Pre-Release editions.
- **Errata holds resolved.** 94 printings held only for Bandai's "Errata Card"
  note are verified: the original release lists one product per card.
- **OP-18 base printings** come from TCGplayer presale data ahead of the
  2026-11-20 release. Recheck them after release.
- **EB05-055 `_p3`** (Kentaro Yabuki, gold stamp) comes from the visually
  reviewed record [`eb05-055-gold-stamp.json`](eb05-055-gold-stamp.json).
- **Coverage certification.** Cards certified by
  `scripts/certify_one_piece_coverage.py` are marked
  `printingCoverageComplete`, which also enables automatic printing
  selection for them.

## Known limits

- The signed envelope is about 47.6 MB, just under the 48 MB limit in
  `scripts/prepare_one_piece_hosting.py`. Further growth needs a higher limit.
- Remaining holds are true exceptions: Bandai art with no matching marketplace
  product, ambiguous photos, finish conflicts, and owner decisions on premium
  reissues that share base art.

Signing, publication and device activation are outside this candidate.
