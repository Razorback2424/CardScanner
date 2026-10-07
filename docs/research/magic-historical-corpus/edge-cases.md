# Historical scanning edge-case review

**Date:** 2026-10-06, `412a09d` plus local changes.
**Status:** fixes implemented; nine focused tests and **432/432** broader affected
simulator tests pass, with no failures/skips. Debug build-for-testing and **22/22**
Python checks pass. All 27 original images still reach the expected titles/choices.

The historical adapter takes an OCR title, fetches the complete current English
paper printing search before M15, and presents explicit printing choices. The
selected row retains its provider printing ID and oracle ID. Exact hydration and
pre-save membership checks prevent stale choices from silently becoming another
printing. Collector OCR assists ordering and never chooses a printing.

## Findings and fixes

| Edge case | Previous behavior | Current behavior |
| --- | --- | --- |
| Rise of the Eldrazi level-up cards | `leveler` layout excluded from both title vocabulary and adapter | Included as ordinary card printing choices; vocabulary regenerated across the source, adding 24 titles. |
| Quotes in titles | Kongming, Pang Tong and “Ach! Hans, Run!” failed evidence/search validation | Exact-name query omits quote punctuation; every returned title must still match the full quoted name. Control characters and backslashes still reject. |
| Old ligatures and typographic punctuation | Printed `Æther` could disagree with current `Aether`; curly quotes failed exact vocabulary matches | General recognition/provider agreement normalizes ligatures and typographic quotes. Printing IDs and collector numbers remain exact. |
| Different oracle identities sharing a title | Both B.F.M. halves caused whole-family rejection | Explicit choices can span logical IDs within the historical title search group. Each selected row hydrates and retains its own oracle/printing identity; automatic selection remains forbidden. |
| Two unrelated recognized titles | Highest title could win, or the parser could construct a nonexistent split title | All recognized title components must belong to one known title; unrelated objects abstain. |
| Malformed ordinary metadata beside valid printings | Invalid ordinary rows could disappear from a complete choice list | Fail as incomplete. Explicitly unsupported tokens/layouts and oversized objects remain scope exclusions. |

Back-face searches (`Insectile Aberration`, `Erayo's Essence`) and split-half
searches (`Fire`, `Ice`) already returned the root printing correctly. New tests
verify exact hydration and ownership identity through these aliases. `Illusion`
also returns tokens; they are excluded while the ordinary split printing remains.

## Verification and boundaries

Eleven real provider searches are retained externally under
`CodexBuilds/MagicHistorical/EdgeCases-20261006/`. They are public metadata,
not a card activation list. Replay tests use those captured responses and verify
29 eligible printings by exact resolution through the shared catalog. The
[hash receipt](2026-10-06/edge-case-results.json) records each capture and choice
family. Deterministic tests additionally
cover collector leading zeroes/suffixes/stars, low-confidence text, power/toughness,
duplicate/truncated/looping pages, changing totals, malformed ordinary metadata,
and changed exact-ID oracle/set/number/layout/date/finish/oversized evidence.

The first edge run passed 8/9 tests; the real-response replay exposed that
backslash-escaped internal quotes produce a Scryfall warning even when the returned
card is correct. Warning-free exact queries were then verified against all three
quoted historical names. Strict returned-name agreement remains in place.
Final evidence is `Edge-Focused-20261006-r2.xcresult` and
`Edge-Final-20261006.xcresult` on the external SSD. The broader run adds shared
catalog/product identity and Pokémon historical request tests to the earlier
scanner/raw/slab/adapter/writer regression. Original corpus title/choice outcomes
are retained in the edge receipt under the current vocabulary hash.

The current title artifact contains **14,384** names, 254,247 bytes, SHA-256
`5f342446b1959c609c6daa3e07848f2fb65e6bc4b4797826e711a4c754cba9f8`.
The earlier [27-image receipt](2026-10-06/general-ocr-results.json) retains its
original vocabulary hash as dated evidence; the final edge run rechecks that
corpus using the expanded artifact.

Provider capture replay does not prove optical recognition of new photographs.
Textless fronts, heavily obscured titles, unusually long multiline joke titles,
non-English cards, oversized specialty products and unsupported layouts retain
their recovery/scope boundaries. A B.F.M. search can distinguish both catalog
halves by collector number; this does not certify camera OCR of each physical
half. Foil identification remains an explicit finish choice. Live-camera/device
precision and full printing coverage remain unverified.
