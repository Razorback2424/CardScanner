# Historical Magic photographic starting corpus

**Reviewed:** 2026-10-06, `412a09d` plus local changes.
**Status:** 27 decoded images; 20 photographic examples and seven clean-front
controls visually reviewed. General historical scanning now recognizes all 27
references and offers explicit printing choices in the normal raw/slab scan path.
See [general scanning and verification](general-scanning.md) for current behavior.
The [additional edge-case review](edge-cases.md) covers level-up cards, quoted and
ligature titles, back-face aliases, same-title identities and provider failures.
The calibrated Exodus results below describe the earlier optional index pilot.
Held-out/device acceptance remains pending. This is a starting corpus, not a
coverage denominator.

The user supplied `mtg_pre2014_cardscanner_image_sources.zip`. It contains a
27-row source manifest, README and downloader, rather than image binaries.
The embedded downloader was not executed. A separate intake downloaded the
manifest's HTTPS sources and verified every image decodes. Original source
labels remain intact; review corrections are separate in the
[hashed intake review](2026-10-06/intake-review.json).

Original images, source manifest, intake receipt and three inspection contact
sheets are retained on the external drive under
`CodexBuilds/MagicHistorical/Corpus-20261006`. Raw images and slab identifiers
are not included in repository evidence. Image hashes pin the downloaded bytes;
future downloads from the same URL may differ.

Photographic entries are 1–17, 19, 20 and 22. Clean-front controls are 18, 21,
23–27. This classification describes visible photographic character; it does
not establish card authenticity or original capture provenance. Manifest labels
span Alpha through 2013 and include ordinary cards, foils, slabs, split/flip/DFC
layouts, full-art basics and alternate frames. All three contact sheets were
inspected, with full-resolution follow-up for entries 6, 12 and 19.

| Entry | Observed evidence | Consequence |
| --- | --- | --- |
| 6 — Survival of the Fittest, labeled Exodus | English title and `129/143` visible in a photograph | Reconciled to Exodus printing `c060c178-3c0e-493f-b6f0-ead5b1d6f191`; current all-era capture has two printings, only Exodus uses `129`. |
| 12 — Forest, labeled Unhinged | Black border and full-art geometry; `140/140` visible | Correct the manifest's “silver-border” test-case assumption to a black-border full-art basic. Preserve its original text for provenance. |
| 19 — Command Tower, labeled Commander 2013 | `281/356` and 2013 copyright visible | Ordinary supplemental-product photographic control; not yet an exact-ID mapping. |
| 13 — Research // Development | Source is only 400×400 | Small-text evaluation has a resolution limit. |

## Corpus-backed Exodus slice

The live pilot and evaluator now share `MagicHistoricalOCR`: accurate English
Vision requests for card-relative title/footer bands, ROI-to-source coordinates
and the existing strict parser. The live path retains modern-first dispatch,
plausible-number gating, bounded attempts and explicit pilot injection. Historical
OCR does not alter modern set vocabulary. The index now includes photographic
visible-number review and a fourth complete-key receipt for Survival of the
Fittest. The 150-record projection retains all collision blockers; dated receipts
expire 2026-10-07 UTC. See the [reconciliation report](../magic-historical-pilot/2026-10-06/corpus-reconciliation-report.json).

The [evaluation manifest](2026-10-06/evaluation.json) pins source image and provider
capture hashes. Entry 6 is a **calibration positive**, with manually annotated
card bounds. These annotations supply framing, never OCR text. The other 26 are
current-pilot scope abstention controls using full-image bounds; their abstentions
do not measure future recognition coverage for those eras or layouts. There is
no held-out positive partition yet.

The [actual simulator OCR results](2026-10-06/ocr-results.json) record one expected
recognition, 26 expected abstentions and one exact saved row. Unknown language
produces a printing choice with zero collection writes; English confirmation
saves the exact Exodus printing through the normal scanner view model and writer.
The transport uses retained current-provider captures, rather than live requests
during tests. A repeated still exercises confirmation-window plumbing; it is not
independent video-frame evidence. All 27 focused tests pass with no skips, and
the broader affected regression passes 316/316 with no skips. All 20 Python
importer/reconciliation/staging tests pass. The Debug build-for-testing succeeds.
Result bundles are `Corpus-Focused-20261006-r2.xcresult` and
`Corpus-Regression-20261006.xcresult` on the external SSD.
The first run rejected a duplicate refreshed
source receipt; reconciliation now replaces it and has a refresh regression test.

To reproduce, first build for testing with derived data on the external SSD, then
stage the private images into that built test bundle before `test-without-building`:

```sh
BUILD_ROOT="/path/to/external-drive/CodexBuilds/MagicHistorical"
python3 -B scripts/stage_magic_historical_corpus.py \
  --manifest docs/research/magic-historical-corpus/2026-10-06/evaluation.json \
  --images "$BUILD_ROOT/Corpus-20261006/images" \
  --bundle "$BUILD_ROOT/DerivedData/Build/Products/Debug-iphonesimulator/TradingCardScanner.app/PlugIns/TradingCardScannerTests.xctest" \
  --provider-search "$BUILD_ROOT/Sources/2026-10-06/Review/Survival-of-the-Fittest-search.json"
```

Select `MagicHistoricalRecognitionTests/testPhotographicCorpusOCRChoiceAndExactCollectionSave`
for the corpus run. Without staged assets this optional private-corpus test skips;
normal deterministic historical tests still run. The stage helper checks every
image and provider hash before writing; changed sources, duplicate entries, path
escapes and incomplete provider pages reject. Original images remain unchanged.

Next work is broader exact printing/face labeling, reviewed collector templates
across the frame eras, and a separate held-out photographic batch. Slabs, full-art,
split, flip and double-faced images must not expand the ordinary-single pilot by
implication. Finish detection, independent camera-frame behavior, device optical
accuracy and thermal/memory budgets remain unverified.
Production historical acquisition remains disabled under the
[recognition plan](../../plans/magic_historical_recognition_plan.md).
