# Scanner edge cases: Pokémon, modern Magic and One Piece

**Date:** 2026-10-06, `412a09d` plus local changes.
**Status:** four focused regressions, 619/619 affected simulator tests (no
skips/failures), and Debug build-for-testing pass. No physical-device acceptance claim.

This follow-up reviews the three existing adapters alongside the
[historical Magic edge-case review](../research/magic-historical-corpus/edge-cases.md).
It preserves current catalog activation, ownership keys and finish-selection rules.

## Findings and fixes

| Path | Finding | Fix and verification |
| --- | --- | --- |
| Pokémon recognition | Split OCR such as `SVI` + `FR` + `001/198` could use the English expansion code/count. Compact foreign text could also reach secondary historical inference. | Known expansion/promo prefixes paired with explicit foreign language marks reject and block secondary fallback. Regulation marks, compact number joins, separated observations and bullet separators have tests. English and missing-language historical behavior stays supported; unrelated artist initials do not supply language evidence. |
| Pokémon adapter/recovery | Extra identifier fields could be ignored by the legacy projection and silently rebased on retry. | Exact field sets for modern, promo and historical namespaces. Tests reject unknown semantics in both initial preparation and explicit recovery retry. Frozen valid definition contexts remain intact. |
| Modern Magic | Ordinary exact lookups accepted future dates, missing/invalid release dates, missing layouts and explicit oversized metadata. | Require a valid released modern printing/layout and exclude provider-flagged oversized objects. Tests retain modern footer resolution for retro frames, split, transform, modal DFC, adventure, saga, meld and leveler layouts. Existing token/art child routing remains separate. This does not infer physical card size from a camera image. |
| One Piece recognition | A bounding box merely intersecting the OCR region could supply a printed number despite extending outside it. | Require full normalized-region containment. Partial overlap on all relevant edges and oversized bounds reject; a contained footer still identifies. |

The public [French SVI 001 control](https://assets.tcgdex.net/fr/sv/sv01/001/high.png)
was visually inspected: the lower-left footer displays the regulation mark and
`SVI FR`, with `001/198`. It remains externally under
`CodexBuilds/MagicHistorical/CrossGameEdges-20261006/`. The new tests exercise
these observed text forms and split/compact OCR variants; they do not claim a
fresh physical photograph or a Vision optical benchmark for Pokémon.
The retained PNG is 311,020 bytes, SHA-256
`f902b019547b6e1091276c51b719b68fc176d827bd2b29185adae93189a4ab90`.

## Existing edge-case coverage reviewed

- Pokémon: official versus secret totals, named subsets, leading zeroes and promo
  padding, historical title/number collisions, unique-denominator inference,
  provider identity disagreement/outage fallback, catalog invalidation, captured
  definition contexts and recovery requests.
- Modern Magic: English footer markers, suffixes and star collectors, separated
  footer lines, printed denominators, spatial ambiguity, token/art parent-child
  routing, paired token products, frame/treatment versus finish identity, and
  exact printing/variant ownership and pricing.
- One Piece: repeated and conflicting numbers, uncataloged supported-series
  numbers, provisional/conflicted/foreign catalog rows, alternate printings,
  distinguishing footer/region/artwork evidence, stale generations, import and
  recovery identity, supported finishes, finish locks, and exact pricing mappings.

One Piece's existing local owner catalog and production publication/write gates
retain the [release acceptance boundary](../plans/one_piece_release_acceptance.md).
A printed One Piece number alone does not prove physical language, artwork,
distribution or finish. The English catalog scope and explicit printing/finish
choices remain the current product policy. This review does not enable publication
or claim catalog completeness or unmarked foreign-card detection.

## Evidence

Four new targeted tests pass in `CrossGame-Focused-20261006.xcresult`; build evidence
is `CrossGame-Build-20261006-r2.log`. Both remain on the external SSD under
`CodexBuilds/MagicHistorical/`. The broader selection includes the three games'
parser/catalog/variant/collection/recovery tests and the staged historical Magic
corpus, so the new Pokémon fallback block is checked alongside cross-game behavior.
The final selection passes 619/619 tests, with no skips or failures, on iPhone
17 Pro / iOS 26.5. Evidence is `CrossGame-Final-20261006.log` and
`CrossGame-Final-20261006.xcresult` in the same external directory. All 27 original
historical Magic corpus references and the eleven retained provider edge searches
were staged for this run. This is an affected-suite result, not a full-suite or
release acceptance baseline.
