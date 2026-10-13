# Lorcana browse and scanner coverage

**Status:** English source discovery and sealed browse implemented — 2026-10-13.
322 focused simulator tests and eight builder tests pass. Physical acquisition,
collection writes, pricing, signed production delivery and real-camera acceptance
remain open. This expands discovery; it does not approve the real-card corpus.

## Inventory and source reconciliation

The bundled [snapshot](../../TradingCardScanner/LorcanaCatalogSeed/discovery.json)
contains all **3,556 English LorcanaJSON records** from its 2026-10-10 17:54:17
snapshot, **26 additional TCGCSV card/product observations**, and **177 sealed
products**. Metadata is available offline without a pricing key. Artwork remains
an HTTPS reference; no images or prices are bundled.

Cards include expansions 1–14, Promo Sets P1–P4, D23, Challenge Years C1/C2,
Disney Lorcana Day, Disney Parks, Ravensburger Play Hub, Curator’s Collection,
and Quest Q1–Q3. Challenge Year 3 now has two inspected promo records and is
explicitly marked partial. Announced sets 15/16 have no source cards and are not
presented as populated sets. Hyperia City's upcoming label follows the current
date on relaunch; its release transition also invalidates older browse cursors.
Q3 is marked partial because its source `hasAllCards` flag is false. Promo dates
remain unknown rather than borrowing an original expansion's release date.

All 21 TCGCSV category-71 product groups were reconciled. Booster packs, boxes,
cases, sleeved packs, starter decks/displays, troves, gift sets, bundles,
collector sets, Gateway and Quest products are retained. Puzzle, rules, lore
and case-file inserts are not counted as sealed or playable cards. Foreign
exclusives are outside this English pass. Ordinary foil market SKUs that
uniquely join an existing source card do not allocate another card identity.
Exact title matching tolerates omitted accents and known rarity qualifiers,
requires the same source set, and rejects ambiguous joins. Cross-directory promo
aliases require inspected image evidence. The initial 3,636-record inventory
contained 53 redundant marketplace listings and a five-card marketplace bundle;
these are now reconciled without losing their product receipts or alias joins.
The resulting card inventory has **3,582 records**.
Inspected oversized gift cards and errata records now appear with their printed
expansions rather than an unrelated marketplace promo group. The First Chapter
and Rise of the Floodborn each show 218 known records; Into the Inklands shows
229. These are discovery-record counts, not verified physical-set completion.

The snapshot's `coverage` receipt retains the card-source SHA-256, format,
source set counts and completeness flags, every product-group SHA-256/count,
unique product joins and resulting inventory counts. These associate input
observations; they are not release signatures.

## Scanner corrections and authority

Previously, app defaults had no real Lorcana catalog. The initial parser also
missed bullet separators, artwork suffixes, early D23 footer order and collector
zero. The [recognizer](../../TradingCardScanner/Games/Lorcana/LorcanaRecognitionAdapter.swift)
now accepts real separators, retains `4A`–`4E` and `24A`/`24B`, and recognizes
`1 TFC • EN • 2/P1` without substituting a provider code for a printed marker.
Fabled's Bruno Madrigal — Undetected Uncle is numbered `0/204`; OCR accepts zero
only when that exact footer is installed. Unknown or conflicting readings never
select a nearby card. Five reviewed unnumbered records now require an exact
title (or both exact character-name/version lines) and the matching English
Quest footer: Vine Tendril/Q3, Ursula/Q1, The Encounter/Q1, The Lair/Q1 and
Jafar/Q2. Missing versions, wrong markers and multiple matches cannot identify
one record. No collector numbers are invented; even the source's internal Vine
Tendril sequence number now displays as Unnumbered instead of a printed number.

The camera previously fed only its footer band to game recognizers. It now asks
for same-frame full-card text only after an unidentified, supported Quest footer
is read in raw-card mode. Existing identified, conflicting and fallback-blocked
frames retain their outcome. Only the requesting adapter receives card-body
text; another game's parser cannot identify unrelated rules/artwork text.
An unreadable Quest title blocks unrelated historical fallback. Numbered and
separate unnumbered footer evidence in one batch is ambiguous.

A bounded macOS Vision diagnostic succeeded in CPU-only mode on six public
images after the accelerated host engine failed. It observed hyphens replacing
bullets and `S7` replacing `57`. The parser now accepts hyphen/dash separators
and repairs numeric confusions only to installed footer mappings. Valid artwork
suffixes remain literal, and competing numeric/suffix repairs stay ambiguous.
Three numeric readings are covered by sanitized regression examples; raw OCR
logs and artwork remain temporary. The other three images confirmed separate
Ursula/Jafar name/version lines and The Encounter's title with `EN - Q1/Q2`
footers. This diagnostic is not an iOS camera or physical-device acceptance run.

Default registration enables Browse, scanner catalog candidates and sealed
discovery. Every source footer produces explicit source candidates, not automatic
physical acquisition. Selection may show source metadata, but final acquisition
and collection mutation reject it. Source IDs retain `lorcanajson:en:` or
`tcgcsv:71:` namespaces, without manufactured physical UUIDs, signatures or
verified review states. The schema-2 physical and signed activation adapters
retain their existing finish, size, stamp and complete-universe requirements.

Of the 26 supplemental records, **19 have inspected numbered footers**, including
serialized, autograph, Challenge C2/C3, oversized and errata records. Four are
reviewed unnumbered Quest components. The remaining **three Palace Heist
components** have unavailable artwork: The Reforged Crown, Jafar's Throne Room
// Secret Passage and The Crown Chamber // Full Alert. They remain discoverable
and now support explicit scanner recovery through a catalog-record identifier.
That identifier is generated only after selection, never inferred from OCR.
All 3,582 records support manual recovery; those three still lack automatic
recognition evidence. Unknown finishes remain unknown.

[The product evidence ledger](../../scripts/lorcana_product_evidence.json)
retains 58 inspected public-image references/digests: 19 new numbered footer
mappings, four unnumbered mappings and 35 source aliases. Generation checks exact
product names, source membership, inspected footer/number consistency and evidence
coverage. A name/number match alone no longer supplies a supplemental footer.
No artwork bytes or physical review approvals are committed.

Source `foilTypes` remain observations. `None` displays Normal; a sole foil
type displays Foil. Multiple foil treatments retain separate IDs and labels
instead of collapsing into one finish. Prices never determine available
finishes. LorcanaJSON cautions that this metadata, especially Special rarity,
is not fully physically verified. No physical completeness claim is made.

## Rebuild and verification

[The builder](../../scripts/build_lorcana_discovery_catalog.py) validates source
format/language, duplicate IDs, per-set counts, product counts/category/group
membership and classification. Changed footer formats and unclassified products
stop generation. Run it with fresh public input captures:

```sh
python3 scripts/build_lorcana_discovery_catalog.py \
  --cards /private/tmp/lorcana-allCards.json \
  --groups /private/tmp/lorcana-groups.json \
  --products /private/tmp/lorcana-products \
  --output TradingCardScanner/LorcanaCatalogSeed/discovery.json
python3 -m unittest discover -s scripts/tests -p test_lorcana_discovery_catalog.py
```

[Swift coverage](../../TradingCardScannerTests/LorcanaDiscoveryCatalogTests.swift)
walks all 3,582 Browse records/details and all-record explicit scanner recovery,
checks all 3,574 numbered footers through recognition/lookup/explicit selection,
and exercises all five unnumbered records, actual promo scopes, duplicate removal,
release transitions, sealed pagination, stale scopes/generations, blocked ownership
and credential-free sealed browsing. Eight Python tests cover source/count changes,
footer formats, classification, accents/qualifiers/set scopes, evidence conflicts
and price exclusion. All 58 inspected image digests match the retained ledger.

The final continuation simulator run passes **322 tests**, zero failures/skips, using
`TradingCardScanner-DebugRemoteLocal` on the isolated iOS 26.5 simulator. It
includes 16 coverage tests, all existing Lorcana integration/physical/ownership/
activation cases, forward compatibility, 100 scanner-model tests, 83 parser tests
and eight sealed surfaces. Artifacts are on the external SSD under
`CodexBuilds/LorcanaCoverage-20261013/Continuation-4.xcresult`.
The last browse-grouping change passes a separate 16-test coverage replay at
`Final-Browse-Grouping.xcresult`, with zero failures/skips. That follow-up records
two internal QoS warnings; the broader 322-test run records one.
The 135-test `Continuation-1.xcresult` covers the initial continuation before
the camera path and observed OCR corrections were added.
The earlier 134-test `Focused-3.xcresult` remains historical evidence for the
initial implementation and three sealed-search regressions. This is not a
full-suite, device, camera, CloudKit,
archive, provider-price or release certification.
The result bundle records one internal QoS priority-inversion runtime warning.

Sources: [LorcanaJSON fields](https://lorcanajson.org/#field-explanation),
[English dataset](https://lorcanajson.org/files/current/en/allCards.json),
[TCGCSV Lorcana groups](https://tcgcsv.com/tcgplayer/71/groups),
[Lorcast cards](https://lorcast.com/docs/api/cards) and
[Lorcast sets](https://lorcast.com/docs/api/sets).
Ravensburger's [Palace Heist product inventory](https://www.ravensburger.us/en-US/pdp/11098525)
also distinguishes the Reforged Crown tile and battleground components from
ordinary numbered cards; it does not establish their unreadable printed footers.
