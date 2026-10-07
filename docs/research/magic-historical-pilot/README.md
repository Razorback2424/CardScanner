# Historical Magic index pilot

**Recorded:** 2026-10-06 at `412a09d` plus local changes.
**Status:** optional automatic index pilot implemented locally and disabled.
The [general historical scanner](../magic-historical-corpus/general-scanning.md)
supersedes this pilot as the normal manual printing-choice implementation; it
does not require individually reviewed cards. All disabled-production statements
below describe this dated automatic pilot. Physical-device acceptance remains open.

## Corpus-backed optical integration — 2026-10-06

The [corpus slice](../magic-historical-corpus/README.md) supersedes the provider-only
projection below. The [new report](2026-10-06/corpus-reconciliation-report.json)
records 150 reconciled IDs, three provider fronts plus a photographic Exodus
Survival of the Fittest `129/143`, and four complete keys. Its 392,730-byte artifact
has SHA-256 `7eb7a47976abd39719768e45506bb33ebd85d2d05facdc5e609d194229df4972`.
The [new capture manifest](2026-10-06/corpus-cross-era-capture.json) binds six
complete all-era searches and the mixed [front review](2026-10-06/corpus-front-review.json).
Only Exodus uses collector `129` in the two-printing Survival family. Allay and
Survival are reviewed singleton keys; language still requires confirmation.

Live and corpus requests share the same card-relative Vision OCR implementation.
The staged 27-image simulator test recognizes the calibrated Exodus photo,
abstains on the other 26 current-scope controls, and saves its exact printing
after English confirmation. Focused 27/27 and the build-for-testing pass; actual
results and reproduction instructions are in the corpus report. The broader
affected regression passes 316/316 and Python verification passes 20/20.
Photographic
calibration is separate from held-out positive, live-provider acquisition,
independent camera frames and device acceptance. Production remains disabled.
The earlier provider-front projection and deterministic results below are dated
evidence, not the current artifact hash. Current output is retained externally
under `CorpusReviewed-20261006`.

## Reviewed projection and D integration — 2026-10-06

The current [review report](2026-10-06/review-reconciliation-report.json) and
[capture manifest](2026-10-06/cross-era-capture.json) supersede the initial artifact
hash below. The 392,444-byte projection has SHA-256
`b98b25fb47865eab834ab0bc3fa7c97b749848afb887894691e60c2b168d5a9b`.
All 150 IDs reconcile. Three [provider fronts](2026-10-06/provider-front-review.json)
were inspected for title and printed `number/143`: Allay, Cataclysm and Monstrous
Hound. Five complete all-era English/paper name searches and seven exact-ID
captures reconcile collision membership. Three complete-key receipts expire
2026-10-07 00:00 UTC. Source rows and provider fronts remain separate from physical
camera evidence. The subsequently supplied [27-image starting corpus](../magic-historical-corpus/README.md)
adds 20 photographic examples and seven clean-front controls, including an
Exodus Survival of the Fittest review lead. Printing-ID labeling and optical/
device acceptance remain pending; the runtime projection is unchanged.

Cataclysm/V14 and Monstrous Hound/PEXO remain blockers outside the Phase-1
interval. PEXO's provider printing date is 1998-06-01, before its enclosing set's
1998-06-15. The PS11 Spanish record normalizes to `es`; an English result filter
does not erase it. Allay is the only eligible reviewed singleton in this subset.

The injected OCR pilot uses the same oriented image's title/footer regions and
bounded two-frame confirmation. Historical identifiers capture profile/index
generations and encounter-specific language provenance. The native printing
picker requires an unchecked English confirmation. Explicit choices hydrate by
exact ID; automatic resolution additionally performs an eight-second bounded,
uncached current collision check at lookup and immediately before save. Search
pagination, warnings, changed membership, transport failures and expiry abstain.
Exact hydration checks oracle/set/printing IDs, collector, language, layout,
paper/digital/oversized flags, per-printing date and finishes. Generic save/recovery
uses the existing ownership keys; stale profile candidates reject. No production
caller enables the scanner or adapter pilot injection.

Reproduce the reviewed projection after the initial importer:

```sh
python3 scripts/reconcile_magic_historical_pilot.py \
  --index "$INITIAL_OUTPUT/pilot-index.json" \
  --review docs/research/magic-historical-pilot/2026-10-06/provider-front-review.json \
  --captures "$CAPTURES/Review" --output "$REVIEWED_OUTPUT" --observed-on 2026-10-06
python3 -B -m unittest discover -s scripts/tests -p 'test_magic_historical*.py'
```

The reviewed inputs/output are retained under external-drive
`CodexBuilds/MagicHistorical/Sources/2026-10-06/Review` and `Reviewed-20261006`.
Final D regression passed all **314 selected simulator tests**, including ten
pilot OCR/adapter/save/recovery tests, 96 scanner view-model tests and the modern
Magic/Pokémon, activation, recovery and variant controls. All **13 Python tests**
pass. Results are retained in `D-Final-20261006.xcresult`; the targeted real store
reload recheck passed 10/10 in `D-Recovery-20261006-r2.xcresult`. The first integration
test exposed a missing provider-generation pin at identifier creation, now fixed.
The initial repeated-card recovery fixture incorrectly expected a second save in
an active held-card session; the final test reloads the actual store into a fresh
scanner session and verifies the existing exact printing row increments to two.

Current simulator index load p50/p95 was 61.0/62.3 ms (10 samples); warm query
p50/p95 was 0.052/0.056 ms (1,000 samples). Artifact hashes/bytes and relative
documentation links were checked. These measurements do not establish device
optical, memory or thermal budgets.

The final Debug simulator build also passes after adding the same native English
gate to direct Needs attention selection. Standard/accessibility picker and native
Details captures were inspected. Confirmation enables selection, carries into
Details within the encounter and resets on the next choice. The
[UI checklist](../../../references/magic_historical_success_checklist.md) records
the inspected scope and remaining device/VoiceOver limits. Screenshots remain on
the external SSD under `UI/final-standard`, `UI/final-accessibility` and
`UI/final-details.png`.

## Historical initial C evidence

The streaming importer retained the complete dated MTGJSON AllPrintings input and
inventoried 123,822 source rows, including faces, tokens, pre-Exodus products and
excluded/uncertain rows. Source-row counts are **not** a physical-printing denominator.
The [reconciliation report](2026-10-06/reconciliation-report.json) contains input
URLs, metadata dates, processing version and SHA-256 hashes for all inputs, the
full ledger and the bundled artifact.

The initial projection had 150 printing identities: 143 Exodus printings reconciled by exact MTGJSON
Scryfall IDs against a complete 143-result English Scryfall set response, and
seven unverified matching name/collector identities from other products. Neither
an English provider record nor an English result filter establishes an encounter's
language. The initial projection marked no provider number physically visible.

Known collision records include Angelic Blessing, Charging Paladin, Cataclysm and
Monstrous Hound. Cataclysm's V14 printing demonstrates why the index must search
outside the historical interval. These records are retained as blockers; they
are not automatically admitted as verified acquisition candidates.

## Contracts and failure behavior

- Printing entries preserve source UUIDs, exact collector strings, names/face aliases,
  set identity/release, layout/language/paper evidence, finishes, artwork/frame
  references and explicit unresolved distinctions. Finish-specific MTGJSON SKU
  references belong to their printing and finish; they are not hydrated provider
  SKU payloads or duplicate picker rows.
- Repeated provider IDs require complete reciprocal face links and matching enclosing
  set/collector identity. Missing/ambiguous mappings remain in the source ledger or
  rejection report; names and numbers never allocate a printing identity.
- Title/collector lookup is dictionary-backed and preserves suffixes, punctuation and
  leading zeroes. Matching records retain other eras and unsupported layouts; only
  independently reviewed `normal` Phase-1 records can enter the eligible list.
- A set-only download cannot certify uniqueness. Current-universe claims require
  an all-era provider source, an exact per-key membership receipt and an external
  matching card-level source context. Receipts must reconcile every indexed match;
  source data must be at most one day behind the observation date. Validity lasts
  at most 24 hours from that observation day, with strict expiry at lookup.
- The initial artifact had no complete keys, no receipts, no validity or source
  context, and explicit missing reconciliation/physical-review sources. Every
  query remained incomplete; all historical profiles remained disabled.
- Profile/index pins and full catalog descriptor/revision contexts must match.
  Compatible profiles/index publish atomically; captured request/choice generations
  reject after changes. D now wires these checks into lookup and immediately
  before save, independently of encounter language and finish resolution.
- Partial/truncated JSON, incomplete/warned provider pages, unsupported versions,
  duplicate identities and incompatible snapshots fail closed. No new signed schema,
  remote publication or production rollout change is introduced.

The runtime artifact embeds the frozen set context so compatibility can be validated
with the same Swift encoder as the registry. It contains candidate presentation
metadata, not an acquisition payload; D now supplies exact live hydration.
No database or sharding was introduced for this small pilot.

## Reproduction and retained inputs

Raw provider captures and the full 29 MB reconciliation ledger are retained on the
external drive under `CodexBuilds/MagicHistorical/Sources/2026-10-06` and
`CodexBuilds/MagicHistorical/IndexReceipts-20261006`. They are not added as app
resources. The report's hashes, rather than a mutable live URL or recent download
time, identify the inputs used here. To reproduce with those retained inputs:

```sh
python3 scripts/build_magic_historical_index.py \
  --all-printings "$CAPTURES/AllPrintings.json.gz" \
  --pilot "$CAPTURES/EXO.json" \
  --scryfall "$CAPTURES/scryfall-exo.json" \
  --catalog TradingCardScanner/MagicCatalogSeed/catalog.json \
  --output "$OUTPUT" \
  --observed-on 2026-10-06
python3 -B -m unittest discover -s scripts/tests -p test_magic_historical_index.py
```

Set `CAPTURES` and `OUTPUT` to the retained capture and generated-output directories.
The CLI requires the full AllPrintings stream to finish and the pilot set to match
the separate EXO capture. A fresh download is a new input and must be reconciled
again; it cannot silently inherit this report's completeness or identities.

Source-model references: [MTGJSON card/face model](https://mtgjson.com/data-models/card/card-set/)
and [identifier model](https://mtgjson.com/data-models/identifiers/).

## Verification — 2026-10-06

All 145 focused simulator tests passed, including nine index acceptance/measurement
tests and the existing parser, token/art, activation and identity selection. Eight
Python importer tests cover partial/truncated sources, reciprocal face consolidation,
metadata disagreements, finish references, exact suffix/number keys, missing
crosswalks, cross-era blockers and deterministic output. Projection regeneration,
artifact/report hashes, byte size and disposition totals were checked.

The artifact is 383,009 bytes. Simulator load p50/p95 were 67.9/68.3 ms across
10 samples; warm dictionary-query p50/p95 were 0.034/0.036 ms across 1,000 samples.
The first load precedes the repeated warm samples; this is not a cold physical-device
measurement. Memory, thermal behavior and release performance budgets remain open.
Results are retained in `IndexReceiptFinal-20261006.xcresult` under the external
`CodexBuilds/MagicHistorical` directory. No camera or device acceptance is claimed.

## Remaining acceptance

The [implementation plan](../../plans/magic_historical_recognition_plan.md) retains
the full scope. The three reviewed fronts and their dated key receipts are a small
pilot, not complete physical-printing coverage. Camera-photo/held-out geometry,
number/layout exceptions for broader sets, independent OCR language evidence,
catalog-refresh publication and device/thermal/memory budgets remain open.
The current local namespace/adapter/printing/save/recovery paths have deterministic
evidence; no real-camera acquisition or physical-device readiness is certified.
