# General historical Magic scanning

**Date:** 2026-10-06, `412a09d` plus local changes.
**Status:** implemented in normal raw/slab dispatch and the default Magic adapter.
Debug build-for-testing, latest affected simulator regression **432/432** and Python
checks **22/22** pass. Physical-device/release acceptance is open.

The user clarified that the 27 images are references for frame generations and
layouts, rather than a list of individually enabled cards. The implementation now
recognizes historical card families generally and resolves their actual printings
from current provider data. The 150-row reviewed Exodus index remains an optional
automatic-selection experiment; it is not required by this route.

## Recognition and printing identity

- A generated vocabulary contains **14,384** historical titles/face names across
  the retained AllPrintings source. It assists OCR and cross-game rejection; it
  contains no printing IDs or acquisition authority. Exact matches and unique
  one-edit matches for longer titles handle ordinary OCR character errors.
- General same-frame Vision OCR covers old/modern-era historical frames,
  Future Sight, full-art, planeswalker, foil and supplemental cards. Split title
  components join only into an actual known combined title. Photograph rectangle
  alternatives preserve combined split-card identity. Live frames use the raw
  guide or slab card window.
- Modern recognition and explicit fallback blocks stay first. Magic and Pokémon
  attempts remain separate; absent text, mode/lifecycle changes and new encounters
  reset confirmation/language. Two readings, six attempts and a 1.5-second window
  bound historical identification.
- General evidence uses `historical-live` with a version pin and encounter UUID.
  English is unknown until explicitly confirmed for that encounter. Persisted
  retries cannot turn another encounter's answer into confirmation.
- Complete current Scryfall searches retrieve English paper printings released
  before 2014-07-18. Bounded pagination checks totals, duplicates, warnings,
  identity/face names, trusted next-page URLs and the eight-second deadline.
  Filtering eligibility uses printing metadata, not corpus/set/card membership.
- Layouts are explicitly `normal`, `split`, `flip`, `transform`, `leveler`. Digital,
  oversized, non-English, token/art/emblem and modern/future printings cannot
  enter the historical picker. Multi-face provider printing IDs remain one row.
- Collector OCR ranks matches first; all eligible printing alternatives remain
  available. This accommodates unreadable numbers and prevents misread numbers
  from hiding the actual printing. The corpus Forest's weak number reading is
  retained in evidence rather than “corrected” from its reference label.
- Every scan asks for the exact printing, even a singleton, with English
  confirmation. No historical title or number automatically chooses a printing.
  Exact-ID hydration rechecks oracle/set/printing/name/date/layout/finishes;
  immediately pre-write validation refreshes membership. Choice retries refresh
  the family instead of reusing a frozen cached list. Existing printing/finish
  ownership, variant choice and collection/recovery formats remain.
- Native Details search filters large families by set, collector number or
  distinction text. Filtering does not reduce the complete-family evidence used
  to decide whether a row is selectable. English confirmation remains shared.

## Evidence

The first general `General-Final-20261006.xcresult` executes 388 affected tests with zero
failures and no skips. It includes actual OCR on all original references, modern
parser/catalog regressions, recovery/writer checks and raw/slab-related tests.
Generated builds, provider pages and result bundles remain on the external SSD.
The [edge-case follow-up](edge-cases.md) passes 432/432, including all 27 originals
under the expanded vocabulary and 11 retained provider searches. Those searches
verify 29 exact printing choices through the shared catalog.
The [native search checklist](../../../references/magic_historical_general_search_checklist.md)
records three inspected simulator captures: 61 unfiltered rows, one filtered row,
and accessibility3 text wrapping. Source/render HIG review passes; physical-device
interaction and VoiceOver remain unverified.

The [general result receipt](2026-10-06/general-ocr-results.json) records actual
Vision results for all 27 original images and printing choices from retained
complete provider pages. This covers the 20 photographic examples and seven
clean-front controls. The first broad run reached 25/27; split-card halves were
being framed separately. Combined-title framing plus a whole-frame fallback
brings both split examples through the general resolver.

An unlisted Counterspell fixture verifies lookup, rejected unconfirmed/automatic
acquisition, explicit English choice and one exact collection row through the
ordinary scanner view model. Pagination/new-membership, unsupported layouts,
title-only pre-Exodus, weak number, language, hydration, freshness and encounter
tests cover the general route independently of the corpus cards.

The general provider capture is retained externally as
`Corpus-20261006/general-provider-captures.json`, SHA-256
`94273137e82bc83ba5dcc33fba9b9a0049eed9db0a99cd5bbaf232bc6bb0a5c8`.
The original receipt pins the earlier vocabulary. The current 254,247-byte title
vocabulary has SHA-256
`5f342446b1959c609c6daa3e07848f2fb65e6bc4b4797826e711a4c754cba9f8`;
see the [additional edge-case review](edge-cases.md) for the expanded scope and
follow-up verification.
Neither original images nor slab certification text enter repository evidence.

Rebuild the vocabulary with `scripts/build_magic_historical_title_vocabulary.py`
using the retained AllPrintings and EXO metadata inputs. Stage the references
after `build-for-testing` using the [intake runner](README.md), adding:

```sh
--general-provider-captures "$BUILD_ROOT/Corpus-20261006/general-provider-captures.json"
```

Then select `MagicHistoricalRecognitionTests/testGeneralHistoricalCorpusAcrossAllFrameGenerations`
with `test-without-building`. The hashes in the evaluation manifest pin every
original image and both provider capture inputs. The corpus test skips when
private sources are not staged; deterministic general-route tests still run.

This is static reference-image verification. It is not held-out optical precision,
physical-device capture, automatic foil recognition, complete physical-printing
coverage, thermal/memory profiling, CloudKit or release certification. Normal
scanning is active with explicit printing choice; optional automatic historical
selection and remote signed profile publication retain their separate gates.
