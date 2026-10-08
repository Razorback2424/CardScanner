# English stress-source review inputs

Status: 2,490 verified printings, 224 provisional records and 31 conflicted
records across 2,692 canonical cards;
broader physical reconciliation incomplete — 2026-10-04. This directory is
publisher review input, not a production seed or a complete printing corpus.
Nothing here enables production scanning, ownership, pricing or asset distribution.

Base pricing review (updated 2026-10-07): 2,367 exact original-release market
mappings, six held finish disagreements and 48 retained price-group responses.
The shared reviewer accepts an exact printed identifier in short parentheses,
full-number parentheses or a full-number hyphen suffix; treatment qualifiers,
wrong numbers, ambiguous products and incorrect finishes remain rejected.
The systematic pass adds 406 mappings across 39 sets without changing any
physical ID, finish or existing mapping. All 2,367 mappings separately passed
fresh public vendor identity/finish/quote checks. The dedicated
`base-market-*` files retain aggregate USD Normal/Foil crosswalks and evidence;
no condition-specific SKU is claimed. Physical IDs/counts are unchanged.
The explicit local debug review kit now enables exact mapped pricing.

The current ordinary review covers 58 OP/ST/EB/PRB product groups and 2,731
selected release/artwork rows. All 817 earlier printing/artwork records and 794
earlier canonical records remain unchanged. Captured source metadata totals
2,940 records; combined normalized observations total 8,237. The 257 open
discrepancies retain missing finish/revision/source-conflict and scope/rights
work. All physical-universe completeness flags remain false. Exact replay matches
the five reconciliation artifacts; unsigned revision 13 validates against
revision 12 as protected review. Later small-batch counts below are historical
milestones rather than current totals. No raw image redistribution or production
price mapping is approved.

Six exact HTML response bodies were retained on the external review artifact
drive at `OnePieceSourceReview/2026-10-04`. `captures.json` records request URLs,
response-body SHA-256, byte counts and completion timestamps from retained-file
mtime. Raw pages include third-party content and remain outside the repository
and app bundle. Subsequent private visual review retained eight exact Bandai
renders and eight exact TCGplayer thumbnails externally; no image bytes were
added to the repository or app bundle. The [image capture manifest](source-image-captures.json)
records hashes and URLs; retrieval for internal comparison does not establish
production caching, hosting or redistribution rights.

The normalizer reads only verified retained bytes. It isolates each provider's
numbered-card records, preserves independent provider aliases and retains the
separate Limitless reprint-appearance list. Price columns, affiliate market IDs,
rules text and unrelated records are excluded from normalized output. Provider
labels/markers such as `aa`, `manga` and `serial` remain source statements; they
are not assigned as physical variants or reviewed printing identities.

| Number | Official scoped page observations | Limitless observations | Unresolved distinctions |
| --- | --- | --- | --- |
| OP01-120 | Three OP01 artwork occurrences | Five print-table rows plus one separate reprint appearance | Identical-art PRB01 appearance versus original release; serialized prize identity; complete release/stamp/footer coverage |
| ST01-007 | One starter-page occurrence | Eight print-table rows | Tournament/full-art and prize distinctions, premium/event releases, stamp/footer evidence and grouped promos |
| P-001 | Four promo-page occurrences | Eight print-table rows | Super pre-release occurrences, premium/event/regional releases, stamps and grouped prize/promos |

These are counts within these six dated captures, not expected physical-printing
counts. Official product pages omit appearances listed on other official product
pages, and grouped vendor rows can cover multiple physical objects. All six
inventories therefore retain `paginationComplete: false`; all three canonical
cards retain `printingCoverageComplete: false`. The initial canonical-only input
has since gained the two durable award identities described below. It still has
no automatic candidates or market mappings. Regenerating observations cannot
silently allocate ownership IDs.

To reproduce normalized review files, supply the exact original raw bodies:

```sh
python3 scripts/normalize_one_piece_sources.py \
  --manifest OnePieceCatalogCore/ReviewCorpus/english-stress/captures.json \
  --capture-dir /path/to/retained/2026-10-04 \
  --output-dir /path/to/new/review-output
```

This regenerates the initial discovery proposal, not the subsequently reviewed
registry. Keep the durable `registry.json` and its allocated UUIDs; merge reviewed
evidence explicitly rather than replacing it with a provider-generated proposal.

The tool rejects changed bytes, foreign/non-English source URLs, missing target
numbers, unexpected provider structure, duplicate aliases within a page and changed existing
outputs. Identical reruns preserve the output. Later captures need a new dated
manifest and explicit review; do not edit the old hashes to conceal drift.

## Product capture and held-record queue — 2026-10-04

Latest ordinary batch: all 270 selected standard identities from OP-04/OP-05/
ST-11/ST-12 are retained. The corpus totals 794 canonical cards and 817 printings
(692 verified, 117 provisional, eight conflicted), with 2,515 observations and
856 raw captures. ST-11's ten OP-02 reprints and thirteen ST-12 records lack
explicit finish evidence and remain provisional. OP05-032 remains held for
original/revision evidence. OP-05 PSA Magazine/SP listings are retained as exact
exclusions from the standard-art batch. Physical-universe completeness, exact
market mappings and source-use rights remain unapproved. Unsigned revision 12
validated against revision 11; the earlier signed local kit has not been replaced.

The [reviewed product manifest](products.json) now drives the bounded capture
tool. Raw inputs remain private; its output does not grant artwork rights or
physical-universe completeness. An offline run verifies retained bytes and
observed pagination; a missing file stops instead of fetching it:

```sh
python3 scripts/capture_one_piece_products.py \
  --products OnePieceCatalogCore/ReviewCorpus/english-stress/products.json \
  --capture-root /path/to/retained/2026-10-04/starter-booster-review --offline
```

The initial official captures referenced by `captures.json` live in the capture
root's parent directory. Successful runs emit `captured-products.json` with
observed retailer page files and `product-capture-review.json` with scoped
pagination results. Pass that captured manifest to reconciliation:

```sh
python3 scripts/reconcile_one_piece_launch_products.py \
  --products /path/to/retained/2026-10-04/starter-booster-review/captured-products.json \
  --corpus OnePieceCatalogCore/ReviewCorpus/english-stress \
  --capture-root /path/to/retained/2026-10-04/starter-booster-review \
  --output-dir /path/to/new/review-output
```

Existing identities replay without allocation. Adding reviewed physical records
requires explicit `--allocate-new-printings`; inspect proposed outputs before
updating the durable registry. Interrupted/orphaned captures stop for repair and
are never silently overwritten. Use a fresh dated capture directory for changed
source bytes, rather than editing old hashes.

The [discrepancy ledger](discrepancies.json) retains 127 open review items: 93
original/revision distinctions, eight source conflicts, 24 missing finishes, and
the corpus-wide coverage and rights gaps. Resolutions require evidence references
and explicit review; generation never treats vanished rows as resolved. This
queue covers known held records and scope gaps, not every undiscovered printing.
Offline capture replay exercised all 13 current products/533 selected artworks;
That initial pipeline checkpoint recorded 32 Python passes; the latest coverage
checkpoint records 35 Python and 40 core passes. No production readiness is claimed.
The associated One Piece integration selection also passed all 43 tests,
including the new ordinary product flows and held starter-finish records.

Next: continue inspecting individual variant/product pages and permitted card evidence,
reconcile artwork reuse and physical footer/stamp differences, record discrepancies
and allocate permanent app-owned UUIDs in the durable reviewed registry only when
the physical distinction is supported. Source aliases that merely identify artwork
or market groupings cannot be assigned one-to-one to ownership by assumption.
Scrydex access, provider/asset rights, candidate-universe completeness and protected
production publication remain separate gates.

## Historical retail base-catalog expansion — earlier 2026-10-04 checkpoint

The [retail review](retail-review.json) adds all twelve alternate-art cards from
Premium Card Collection -FILM RED Edition-. The manufacturer's
[product specification](https://en.onepiece-cardgame.com/products/other/cardcollection_filmred.php)
explicitly identifies silver foil plus texture foil for its twelve cards, with
November 2023 delivery. Its [Other Product Card list](https://en.onepiece-cardgame.com/cardlist/?series=569801)
assigns each printed number/artwork to this collection. These sources support
one foil variant per reviewed printing; no optical foil inference was used.
Texture belongs to this product's treatment, not a separately selectable finish.

Sixteen exact source responses (four pages/presentations and twelve individual
card renders) are retained privately under the external `retail-review` directory.
The Nami, Luffy and Shanks renders were inspected alongside the product presentation.
The twelve product-scoped printing and artwork UUIDs were allocated once during
review. Manufacturer `_p` aliases remain evidence fields; they do not become
app ownership keys. No original physical-footer, stamp absence or geographic
sub-printing claim was inferred from watermarked current renders. The original
starter-deck Nami's finish remains unestablished; no normal variant was invented.

[Retail observations](retail-observations.json) add 36 separate identity/render/
manufacturer-specification records and one [incomplete inventory](retail-inventories.json).
The combined candidate now contains 103 observations, 14 canonical cards and
14 physical printings: 13 verified and one provisional. Every canonical coverage
flag remains incomplete and there are zero automatic candidates or market joins.
The full English universe is still unfinished. Image URLs remain absent pending
asset permission; the source bytes are not bundled or redistributed.

All 38 core tests and 39 selected app integration tests pass. The new Nami base
case recognizes ST01-007, requires the FILM RED printing choice, resolves the
manufacturer-supported foil and adds that UUID without price observations.
The prior real winner disk-reopen/CSV/Browse case remains green with the larger
signed catalog. Publisher revision 6 retains all previous UUIDs; revision 7
regeneration preserves the expanded registry and observations unchanged.
Both unsigned candidates and the expanded signed local kit remain external.
No rendered launch, physical-camera, production publication or sync pass follows
from these checks.

## Historical first standard starter/booster checkpoint — 2026-10-04

The [starter/booster review](starter-booster-review.json) retains all 17 ST-01
and 121 OP-01 standard-art records as separate, permanent app-owned UUIDs.
Parallel artwork, box toppers, DON!! and event cards are outside this expansion.
The manufacturer's [starter product](https://en.onepiece-cardgame.com/products/decks/st01-04.php)
and [booster product](https://en.onepiece-cardgame.com/products/boosters/op01.php)
establish the releases. The retained manufacturer card lists establish numbered
standard artwork; exact English base-card listings from CoreTCG independently
specify finishes. No rarity-to-finish rule or optical foil inference was used.

The [new observations](starter-booster-observations.json) contain 415 separate
identity/render/finish records. The combined corpus has 518 observations,
141 canonical cards and 152 retained printing records. Of the 138 new records,
69 are verified. Their standard release/artwork and finish agree: ten starter
and 59 booster cards, including non-foil Karoo, foil ST01-012 Luffy and foil
OP01-120 Shanks. Every canonical coverage flag remains incomplete, so number-only
recognition still requires explicit printing choice.

Sixty-eight new records remain provisional because the current manufacturer
render carries an errata notice; original versus revision artwork/text still
needs reconciliation. Starter Nami now has explicit retailer non-foil evidence,
but its original/revision physical identity remains provisional and cannot be
acquired by choosing its separate FILM RED printing. ST01-001 leader Luffy has
two conflicting retailer finish listings; that record remains conflicted with
no acquisition finish. Both listings are retained. The existing winner and
premium printings are unchanged.

The 144 new raw captures (six catalog/product pages and 138 standard renders)
remain private on the external artifact drive. Neither image bytes nor artwork
URLs are added to the app. Finish observations contain no prices and approve no
market joins. [Inventories](starter-booster-inventories.json) remain incomplete
for broader physical coverage; first-wave/footer distinctions are not certified.

The offline `scripts/reconcile_one_piece_launch_products.py` now requires
`--products OnePieceCatalogCore/ReviewCorpus/english-stress/products.json`.
That reviewed manifest contains the explicit inventory, selected artwork,
retained observation keys and manufacturer finish evidence for the current
13 standard starter/booster products. Migration replay preserves printing UUIDs,
artwork, aliases and source observations. Capture automation and broader physical
coverage remain separate unfinished work.

The offline `scripts/reconcile_one_piece_launch_products.py` requires an explicit
first-allocation flag. Subsequent reconciliation reuses the durable IDs and
refuses changed existing printing/artwork reviews. The catalog-core checkpoint
passes 39 cases. Protected publisher revision 8 retains the earlier fourteen
printing UUIDs, and a new signed local review kit was prepared externally.
All 40 One Piece integration tests pass, including standard Karoo, starter Luffy
and booster Shanks recognition/explicit choice/finish/collection cases, and the
existing premium/winner recovery and export cases. These scanner tests inject
recognized text; they do not prove physical-camera or device acceptance.

## Historical: all four launch starters — 2026-10-04

The later expansion adds ST-02, ST-03 and ST-04 using the same retained-byte
reconciliation workflow. The manufacturer lists seventeen numbered cards in
each deck. All 51 receive permanent review UUIDs; nine ST-02, eight ST-03 and
seven ST-04 printings are verified acquisition candidates. Twenty records remain
provisional and seven remain conflicted. Conflicts retain every retailer listing,
including incompatible normal/foil assertions; a duplicate vendor row cannot
silently overwrite finish evidence.

Across all four starters and OP-01, 189 standard numbered records are retained:
93 verified, 88 provisional and eight conflicted. Including the unchanged award
and premium printings, the corpus now holds 192 canonical cards, 203 printing
records and 678 observations. The shared [review manifest](starter-booster-review.json)
has 201 private captures, including all 189 standard renders. No image URL,
price or exact market mapping is published. All canonical coverage remains
incomplete, requiring explicit printing selection.

The offline replay preserves the full registry, observations, inventories and
review decisions without allocating IDs. Protected publisher revision 9 retains
revision 8's identities. The catalog-core checkpoint passes 39 cases; later
starter/booster products and original/revision text review remain unfinished.
All 40 One Piece integration cases pass against the expanded source data. The
standard scanner/collection case now covers all four starters, including foil
ST02-001 and normal ST03-008/ST04-005, with exact UUID/finish persistence and no
price observations. This is injected-recognition evidence, not device/camera or
new rendered UI acceptance.

## Current standard coverage: ST-01–ST-09 and OP-01–OP-02 — 2026-10-04

The next batch retains all 202 standard numbered rows from OP-02 and ST-05–ST-09.
OP-02 supplies 119 verified and two provisional revision records; all 81 new
starter rows are verified. ST-08 and ST-09 each contain fifteen standard cards.
Explicit Alternate Art listings are excluded alongside Parallel and Box Topper
listings. The exact retailer spelling Oniguma for OP02-095 is reviewed against
manufacturer Onigumo; unrelated spelling disagreements still stop the builder.

Standard scope now totals 391 records: 293 verified, 90 provisional and eight
conflicted. The complete review corpus holds 394 canonical cards, 405 printing
records and 1,284 observations. Its [review manifest](starter-booster-review.json)
retains 422 private captures, including all 391 standard renders. Earlier 203
printing records remain unchanged; offline replay reproduces all four artifacts
without allocating IDs, and publisher revision 10 validates against revision 9.
The expanded signed local kit has no image distribution, prices or market joins.

All 40 core and 40 One Piece integration tests pass. The scanner base case covers
one card per new product through injected recognition, explicit printing choice,
supported finish and persisted UUID. The timestamp validator accepts both whole
and fractional seconds; invalid timestamps still fail. Later products and held
original/revision distinctions remain unfinished. No physical-camera, production
or sync acceptance is claimed.

## First reviewed award identity — 2026-10-04

The [award review](award-review.json) retains five exact response hashes and the
once-allocated printing IDs. Six [normalized observations](event-observations.json)
and two [incomplete inventories](event-inventories.json) supplement the earlier
discovery captures. Raw bodies and images remain in the external `event-review`
directory. Normalized timestamps use the existing contract's second precision;
raw capture metadata retains fractional completion times.

The [official event page](https://en.onepiece-cardgame.com/events/2022/officialevents/super_pre-release.php)
specifies a silver-foil P-001 winner prize and separate participation distribution.
Its two linked images were inspected. The grading company's own
[article and physical-card photograph](https://www.cgcgrading.com/news/articles/unserialized-ace-one-piece-4PA9RXwgxW2kLLfiUwuqIQ/)
independently corroborate the 2022 winner identity, English text and WINNER
lettering. No certificate identifier was retained in normalized evidence.

Winner UUID `348ad90a-43d8-49b5-a384-4d9cc2a1fe27` is verified for that award
identity, with the `foil` finish supported by the manufacturer's specification.
Participation UUID `603d83b0-146a-4229-8eaf-b2f884087312` remains provisional with
an empty finish list. No participant stamp, original-footer detail, geographic
sub-printing or market join was inferred. Artwork IDs describe the full card
presentations, including different frame/layout treatments of reused illustration.
Image hashes identify exact retained renders; app image URLs remain absent
until asset rights are established.

All canonical coverage remains incomplete. The app adapter therefore requires
explicit winner choice even after English confirmation; participation is excluded
from exact acquisition and Browse ownership. This is a first real reviewed
printing, not completion of the Shanks/Nami/Luffy candidate universe.

Publisher revision 2 against the prior canonical-only candidate is protected
review; revision 3 regeneration retains the registry and observations unchanged.
Both unsigned candidates contain 67 observations, two printings and zero automatic
candidates. They remain external. The initial package run passed 32/34 cases;
after timestamp normalization and a canonical-order comparison correction, both
affected corpus tests pass. Three selected app cases pass, including real-corpus
OCR/choice/finish/offline-Browse checks and the two relevant scanner regressions.
No production signing, deployment, physical-device or CloudKit pass is claimed.

Finish-evidence follow-up: rules version 2 requires an explicit finish review
supported by a catalog specification for every finish. The winner review points
to the manufacturer's prize specification, not either photograph or market row.
Unsigned revision 4 migrates the evidence under protected review; revision 5
retains the same registry and UUIDs. Earlier candidates remain retained with their
original hashes. All 38 core/publisher tests pass, including unsupported finishes,
malformed/missing claims and market/image-only rejection. Participation stays
provisional with no finish; neither production assets nor market authority gained
permission from this contract change.
The batched app checkpoint also passes 43 selected cases: 35 One Piece integration
and eight signed-store cases. The xcodebuild process completed successfully; no
full-suite or device claim follows from this selection.

## TCGCSV discovery and artwork crosswalk — 2026-10-04

The owner supplied `one_piece_english_catalog_kit_2026-10-04.zip`. Its original
builder, README and coverage reference are retained unmodified beside the external
capture. [Discovery provenance](tcgcsv-discovery.json) records the kit, original
builder, response-manifest and generated-output hashes. The repository's
[adapted builder](../../../scripts/build_one_piece_catalog.py) adds bounded,
paced, hashed response retention/replay, success/count validation, explicit
empty-group gaps and protection against replacing differing reviewed output.
No Pullnomics dataset was copied; its supplied 7,255 benchmark remains a historical
reference, not an independently verified count or required output size.

The live category-68 capture retained 90 responses from upstream build
`2026-10-03T20:05:38+0000`, generating 7,408 review rows across 87 groups. It
includes 7,009 rows with source number metadata, 242 DON!! rows, 151 unnumbered
candidates and 53 metadata/sealed-signal conflict candidates. These cohorts can
overlap and are **not** counts of verified English physical cards. Another 276
products were excluded from the flat card projection; their complete source rows
remain in the retained raw responses. No price endpoints were requested.

Group `24834` (The Dominance of God Release Event Cards) returned an empty
successful product export without `totalItems`, so its inventory is explicitly
incomplete. This is not silently interpreted as a complete empty release.
The source is a daily market-product export, not official card-release or language
authority. TCGCSV does not export SKU-level language, printing and condition data;
stress market observations therefore retain `language: unknown` pending review.

The [market observations](tcgcsv-observations.json) retain 31 scoped products:
seven OP01-120, ten ST01-007 and fourteen P-001, with exact product names,
product/group aliases, raw response hashes and image/product URL pointers.
[Inventories](tcgcsv-inventories.json) remain incomplete scoped discovery inputs.
The [candidate crosswalk](tcgcsv-crosswalk.json) lists those market products beside
the original Bandai artwork aliases without allocating physical UUIDs or equating
provider product counts with printing counts.

[Visual comparison decisions](artwork-correspondences.json) record seven
illustration correspondences among eight privately retained thumbnail pairs.
Nami product `288236` has an Image Coming Soon placeholder; its artwork join is
unresolved. The comparisons do not prove finish, original physical footer or
candidate-universe completeness. Current Bandai renders display block 1, and
SAMPLE watermarks/low-resolution market images prevent exact byte/physical-footer
equivalence. The original catalog-only observations remain unchanged; subsequent
image captures and review decisions are separate evidence.

Reproduce the source catalog once, using a persistent daily capture directory:

```sh
python3 scripts/build_one_piece_catalog.py \
  --capture-dir /external/review/tcgcsv/source \
  --output-dir /external/review/tcgcsv/output \
  --user-agent CardScanner-OnePiece-SourceReview/1.1

python3 scripts/build_one_piece_catalog.py --offline \
  --capture-dir /external/review/tcgcsv/source \
  --output-dir /path/to/replay-output

python3 scripts/reconcile_one_piece_tcgcsv_sources.py \
  --catalog /external/review/tcgcsv/output/one_piece_catalog.json \
  --capture-dir /external/review/tcgcsv/source \
  --official-observations OnePieceCatalogCore/ReviewCorpus/english-stress/observations.json \
  --output-dir /path/to/review-crosswalk
```

Follow [TCGCSV's retrieval guidelines](https://tcgcsv.com/docs): identifiable
User-Agent, paced calls, at most one full sync per 24 hours and only after a newer
upstream build. Reusing the retained directory makes no repeated HTTP requests;
extending an old snapshot after 24 hours is rejected. Capture directories are
immutable daily snapshots, not an automatically scheduled sync service; coordinate
new daily captures with the last successful capture. `--include-prices` is optional
source evidence only, not an app price adapter or exact quote. TCGplayer product
IDs remain market aliases beneath the app-owned physical registry.

Verification: nine Python source/builder/crosswalk tests and 32 core/publisher
tests pass. The full catalog replayed offline with identical hashes for all four
CSV/JSON outputs. A focused follow-up confirms unchanged replay preserves manifest
and output timestamps. No app rebuild, production seed, exact market mappings,
physical UUIDs, finish assertions or collection-write enablement was added.

Sources: [official OP01 catalog](https://en.onepiece-cardgame.com/cardlist/?series=569101),
[official ST01 catalog](https://en.onepiece-cardgame.com/cardlist/?series=569001),
[official promo catalog](https://en.onepiece-cardgame.com/cardlist/?series=569901),
[Shanks](https://onepiece.limitlesstcg.com/cards/en/OP01-120),
[Nami](https://onepiece.limitlesstcg.com/cards/en/ST01-007),
[Luffy](https://onepiece.limitlesstcg.com/cards/en/P-001).
