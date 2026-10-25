# Set pricing identity audit

**Status: current systematic audit checkpoint — 2026-10-24.** Evidence is from
`30a56af` plus the preserved working-tree changes. This is the current authority
for this set/pricing audit; it does not replace game-specific catalog admission
or release decisions.

The systematic passes fixed **61 additional set-lookup failures** after the
earlier spot checks: 50 from the directory census and 11 from independent
card-level review. The census covers every bundled directory entry, tests all
808 distinct Pokémon/Magic Browse set names, and independently checks every
installed exact One Piece/Lorcana pricing lane against retained public feeds.
Unresolved names, absent mappings, missing quotes and identity failures have
separate ledgers.
The next passes add exact Magic product lookup and reviewed Pokémon subset
products. A sampled match does not establish whole-set graded coverage.

## Inventory and results

The vendor directory capture contains **1,443 groups** across five games, tied
to upstream build `2026-10-24T20:05:44+0000`. The installed catalog inventory has
**1,804 entries**; these are directory entries, not 1,804 independent physical
sets or a complete market denominator.

| Game | Installed inventory | Verified boundary |
| --- | --- | --- |
| Pokémon | 157 Browse print-run entries; 146 distinct provider sets | 142 names resolve; four remain unaliased. Reviewed product routes cover all 28 Unown, five Futsal and six Yellow A cards (41 finish products). Best of still needs stamp provenance work. |
| Magic | 910 descriptors: 662 Browse and 248 hidden | 321 Browse names resolve; 341 remain in review. |
| One Piece | 60 declared releases, 2,490 verified English printings | All 2,367 installed exact mappings across 48 vendor groups match live product identity and have quotes. 123 verified printings have no installed mapping. |
| Lorcana | 18 discovery source sets, 3,582 discovery records, 1,749 reviewed physical printings | All 3,364 installed finish lanes across eight vendor groups match live identity and have quotes. These cover 1,748 printings; one reviewed printing has no mapping. Discovery does not grant physical or pricing authority. |
| Yu-Gi-Oh! | 659 snapshot sets, 46,542 records, 46,303 supported exact printings | 59,965 edition memberships across 608 mapped groups retain snapshot authority; 58,264 have quotes and 1,701 do not. The other 51 groups have no admitted membership lanes. Live per-card refresh remains disabled. |

The native name census now has **463 resolved / 345 unresolved / zero
directory-resolved-but-rejected** cases. Its vendor IDs are explicitly opaque
TCGplayer group IDs used to exercise production name resolution and matching;
they are **not fabricated JustTCG slugs** or evidence of graded-market coverage.
Ten initial unresolved rows were audit projection errors: the Browse snapshot
decorates edition titles, while detail pricing receives the underlying TCGdex
set name and a separate print-run discriminator. Correcting this audit projection
is not counted among the 50 application fixes.
The Pokémon census covers the bundled English Browse inventory; Japanese
identity paths have targeted regressions, not a complete directory census.
These are **directory-name** counts. Magic and reviewed Pokémon subsets can
resolve exact printings by product ID while their directory names remain
unaliased. The 345 names are not 345 demonstrated application failures.

## Fixes and identity safeguards

- **26 resolved sets failed the extra display-name check.** Exact vendor game
  and set IDs now establish set identity after directory resolution. An
  unresolved fallback still requires a matching set name. Card name, full
  collector number, game, finish and print-run checks remain independent.
  Examples include XY sets, Crown Zenith/Galarian Gallery, Mega Evolution sets,
  The Big Score, Kaladesh Inventions and Multiverse Legends.
- **24 aliases or ambiguity cases now resolve.** These cover seventh–tenth
  editions, Alpha/Beta, matching M10–M15 title suffixes, Commander 2011, four
  Commander titles, Game Night releases, Brothers' War Retro Artifacts, the
  main Lord of the Rings set, Scarlet & Violet Energy and Pokémon Rumble.
  A weak colon-stripped alias cannot prevent a unique full canonical match;
  genuine ambiguity still returns no set. Main expansions and Commander
  releases, mismatched year/code pairs, anthology reprints and annual promo
  sets remain distinct.
- **Rumble has independent whole-set evidence.** All 16 TCGdex cards match
  exactly one captured vendor product by name and number. A native regression
  uses those retained public records.

The [61-case regression ledger](set-pricing-audit/2026-10-24/fixed-set-regressions.csv)
records every affected set. Signed catalogs, keys, rollout flags, collections
and production hosting were not changed.

## Second card-level pass

All **58 Magic names with explicit source groups** were reviewed against
retained Scryfall card searches and **37 vendor product groups**. The search
covers 8,448 English paper prints, including layouts that the app may not admit:
7,471 product IDs belong to the suggested group, 800 prints have no source
product ID, and 177 point outside that group. Among matching products, 1,515
collector identifiers agree, 950 are missing and 5,006 differ. Number agreement
is diagnostic; it does not prove name uniqueness, physical eligibility or
graded availability. Four of the 58 sets returned no English paper cards.

Ten aliases passed production matching against **every product in each vendor
group**, with the exact expected product ID for **all 594 source cards**: both
Guild Kits, Marvel Universe, Modern Event Deck 2014, Champs and States,
European Land Program, Tarkir Dragonfury, Universes Within, Time Spiral
Timeshifted and Ugin's Fate. Neighboring expansions and releases remain
distinct. A proposed eleventh alias, Secret Lair: Ultimate Edition, was withheld:
the native proof rejected ten Pathways whose vendor names contain only the
front face plus “Borderless,” while the source names contain both faces.

Other concrete findings remain queued rather than receiving broad aliases:

- All 62 Elves vs. Goblins anthology product IDs are outside the suggested
  original-release group. Mythic Edition also spans multiple vendor groups.
- Mystery Booster playtest products omit collector numbers. The List commonly
  uses original-set-prefixed source numbers versus unprefixed vendor numbers.
- Coldsnap Theme Decks has two number disagreements; Deckmasters has two
  starred foil numbers that differ from vendor identifiers. Dropping those
  suffixes without printing evidence would remove meaningful identity.
- Annual promo groups repeat collector numbers. Each needs name/printing
  uniqueness checks; duplicate numbers alone do not prove a wrong match.

All **five remaining Pokémon names** also received independent whole-catalog
review (53 source cards). Poké Card Creator Pack now resolves to Kids WB
Promos, and all five cards match uniquely across that group's six products,
excluding its sealed pack. The other four dispositions are explicit: Best of
has Winner/non-Winner products with identical names/numbers; Unown's question
mark is encoded as `%3F` in the source identifier; Yellow A has numeric-prefix
zero differences and separate finish products; all five Futsal cards occur in
the broad Miscellaneous Cards & Products group. A shared parent group is not
automatically a source subset's printing authority.

See the [58-case metrics](set-pricing-audit/2026-10-24/magic-product-review.json),
[per-set dispositions](set-pricing-audit/2026-10-24/magic-product-dispositions.csv)
and [five Pokémon reviews](set-pricing-audit/2026-10-24/pokemon-product-review.json).
These retain public source receipts; raw card pages and product feeds remain
on the external SSD. Source product IDs still need release, number, finish and
eligibility checks before they can establish a durable pricing identity.

## Direct Magic printing identity

The graded picker, scanned slab resolver and owned-price refresh now use the
same exact-product route. A Scryfall UUID is re-resolved and must agree with
the requested name, set and complete collector identifier. The source must be
an English paper card with a supported layout, released date, declared finishes
and an explicit non-oversized value. Only then may its marketplace product ID supply the
documented `tcgplayer_id` request. Stored/imported marketplace handles do not
authorize this route.

Returned `external_ids.tcgplayer` and the exact Magic game ID must agree. If
Scryfall identity is also returned, it must agree too. Provider-declared face
names can verify a front-face vendor title; vendor number and group-display
differences no longer exclude an otherwise verified product. Wrong product IDs
never fall back to a permissive name match. Duplicate cards or slab IDs,
incomplete pagination and budget exhaustion remain incomplete searches;
catalog outages remain errors. A first-page 404 for an exact product is a
product miss. When source IDs do not cover every requested finish, the existing strict
name/set/number route remains available.

**Etched products stay separate.** The retained H1R source publishes a distinct
`tcgplayer_etched_id` for each of its 40 cards. The picker can query both ordinary
and etched products; a known-finish refresh queries only its own product. Each
product admits only its source-declared finishes, and foreign-language or raw
variants cannot become graded results. Legacy Magic “Normal” imports retain
their existing nonfoil meaning. This does not change catalog admission,
treatment ownership, stored collections or rollout flags.

The same finish-to-product selector now serves raw fallback pricing, market
history and marketplace links, including links saved when adding or refreshing
an owned row. These paths previously used the ordinary ID even for etched
copies. All 40 H1R pairs exercise both products through those projections as
well as graded HTTP requests. An unknown finish cannot choose between distinct
products or borrow the ordinary purchase URI; single-product cards retain their
existing route. This follows Scryfall's [separate etched product field](https://github.com/scryfall/api-types/blob/main/src/objects/Card/CardFields.ts).

Native HTTP replays cover **103 card cases across 52 release families**, plus
**all 40 H1R etched/ordinary pairs**. Together these are 141 distinct source
printings and 181 distinct product IDs, recorded in the
[183-row sample ledger](set-pricing-audit/2026-10-24/magic-direct-product-samples.csv).
The sample exercises 42 still-unaliased directory names, including playtest
editions with no vendor numbers, Coldsnap/Deckmasters number differences, List
prefixes, annual promo groups and the previously rejected Secret Lair Pathways.
These are real public printing/product identity facts projected into a
synthetic v2 response; quoted prices, JustTCG UUIDs/slugs and live graded
availability are not established by the fixture.

This replaces broad vendor-name searches with one product query, or two when
the picker needs separate ordinary/etched products. It adds a catalog lookup
when the UUID endpoint is not cached. Provider-backed timing and actual graded
coverage remain open. The retained product-ID sample covers no card whose
source product ID falls outside its captured group, so the EVG group
contradiction still needs independent vendor-product evidence.

Contract sources: [JustTCG v2 identifiers and response shape](https://justtcg.com/docs/api/cards-v2)
and [v2 batch limitations for graded discovery](https://justtcg.com/docs/api/cards-v2/batch).
Exact source fields, including etched IDs, are hash-bound to the retained
[H1R card search](https://api.scryfall.com/cards/search?q=set%3Ah1r%20lang%3Aen%20game%3Apaper&unique=prints&order=set).
The fixture verifier compares every projected source and vendor field with
those retained bytes.

## Reviewed Pokémon subset identity

All **28 Unseen Forces Unown Collection cards and five Pokémon Futsal cards**
now have reviewed per-card graded product identities. Each detailed TCGdex
record publishes exactly one standard English unstamped Holofoil object with
an explicit third-party TCGplayer product ID. Every ID belongs to its captured
vendor group. The app uses those reviewed IDs directly; Unown Collection and
Unseen Forces, and Futsal and Miscellaneous Cards & Products, remain distinct
catalog namespaces.

The reviewed projection checks catalog ID, name, source set, collector number,
Holofoil finish and absent/Unlimited print run before making a request. Returned
product ID, game, card name, graded type, language and physical finish still
have to agree. Wrong letters, denominators, first-edition/Shadowless claims and
other finishes cannot use the mapping. Only `exu-%3F` receives the scoped
question-mark translation, preserving any stated denominator and the original
provider ID. Printed numbers are not globally URL-decoded.

Native HTTP replays verify all **33 cards twice**, with absent and explicit
Unlimited print runs, and require one exact product request per lookup. The
same fixtures verify that existing raw product extraction agrees with each
per-object source ID. These tests establish identity and request behavior,
not actual graded-market availability. No collection, catalog admission,
signature or release flags changed.

**Best of game remains open.** Whole-source review of all nine cards establishes
15 standard products: seven unstamped and eight Winner objects. Eight jumbo
objects are excluded. Graded selection, binding, retained quotes and correction
must preserve the stamp/finish provenance before those products can be admitted.
A broad set alias is insufficient. The
[complete physical-object evidence](set-pricing-audit/2026-10-24/best-of-physical-evidence.json)
retains all nine detailed-card receipts.

The [Pokémon review ledger](set-pricing-audit/2026-10-24/pokemon-product-review.json)
retains the detailed-card and candidate-finish receipts. Runtime mappings are
checked against the [33 original source-reviewed cards](set-pricing-audit/2026-10-24/pokemon-subset-products.csv)
and the Yellow A review below. Complete source inventories are verified offline.
This adds no catalog request to the graded path and avoids a vendor group/name
search for these reviewed products.

## Yellow A finish reconciliation

All **six** detailed Yellow A records carry generated Normal metadata with no
product IDs. Whole-group product and price-lane evidence distinguishes **eight
physical products**: four EX Holofoil cards and separate Normal/Holofoil products
for each trainer. Reviewed variant choices now replace those generated flags;
raw product extraction, graded requests and marketplace links select the exact
finish product. Discovery requests both products for a trainer; a confirmed
finish requests one. Other cards are unaffected by these six reviewed overrides.

Bundled and downloaded offline Browse checklists receive the same reviewed
projection: the old six Normal slots become eight physical slots. Four EX cards
have a single Holofoil slot; both trainers have Normal and Holofoil slots.
Reopening and evicting decoded caches preserves these results, including set
counts, without changing source resources, manifest bytes or provider fingerprints.

Letter-suffix padding is reconciled only within the reviewed Yellow A
identities. `24a` and `024a` can identify that specific card; `24`, `24b`, or a
different stated total cannot. Displayed numbers use the actual printed total
(for example `24a/119`), rather than the subset's six-card inventory count.
Source/provider IDs and local collector identifiers remain stable. The same
reviewed display projection renders the Unown question mark as `?/28` while
retaining its encoded provider key.

A conflicting detailed Normal quote cannot override a reviewed Holofoil object.
Price Check also refuses cached/reference Normal quotes for an unreviewed EX
finish and issues no refresh request for it; cached data is retained. Existing
Normal EX holdings need a confirmed finish correction before new pricing. No
collection quantities, history or saved source identities are rewritten.

The scan resolver no longer infers a finish from the only published slab when
the catalog declares multiple physical choices. Price Check forwards the scan's
confirmed finish, and printed edition evidence reaches the vendor identity even
when no separate print-run argument was supplied. Legacy first-edition flags
are kept distinct from physical finish choices. These safeguards preserve
unknown identity rather than marking another finish's quote as this slab's value.

The [eight-product ledger](set-pricing-audit/2026-10-24/pokemon-yellow-a-products.csv)
and independent whole-source/whole-vendor verifier establish the reviewed
candidate scope. Native tests cover all eight finish queries, complete finish
discovery, exact links/totals, conflicting quote refusal, ambiguous scans and
Price Check propagation. Actual live JustTCG coverage remains unverified.

## Independent source checks

The audit also retains the complete **1,062-set Scryfall directory** and checks
its explicit TCGplayer group IDs against resolved Magic names. One disagreement
was found: Scryfall's `GN2` set-level field points to group `2359`, whereas the
vendor's Game Night 2019 group is `2562`. All **64 card-level TCGplayer product
IDs** returned by the GN2 search are in `2562`, none is in `2359`, and none is
outside both inventories. The name-based 2019 resolution is therefore retained;
the set-level contradiction is recorded rather than silently adopted.

Sources: [TCGCSV API and usage requirements](https://tcgcsv.com/docs),
[Scryfall set directory](https://api.scryfall.com/sets),
[TCGdex Rumble](https://api.tcgdex.net/v2/en/sets/ru1), and the source URLs/hashes
in the retained capture and test fixtures. The earlier HTTP 401 audit requests
used a generic User-Agent; a custom application User-Agent resolved access.
The app transport already supplied its own User-Agent, so this was not evidence
of an application transport defect.

## Remaining review queue

The [345-row queue](set-pricing-audit/2026-10-24/unresolved-sets.csv) is not a
list of cards proven absent at a vendor. Next passes should proceed in this
order and retain an explicit disposition for each reviewed row:

1. **48 remaining Magic names with a current explicit source group.** The
   card-level capture is complete; 42 now have exact-product native samples.
   Finish whole-inventory physical scope, absent source IDs and remaining
   provider-identity work using the per-set dispositions. Shared groups
   such as Judge Promos, Mystery Booster playtest editions and anthology
   reprints require product-level identity; a shared abbreviation or broad
   group label is insufficient. The List's sampled prefixed identifiers now
   resolve by exact product identity; prints without source product IDs still
   need conservative fallback work.
2. **One Pokémon identity gap: Best of game.** Preserve stamp/finish provenance
   through graded selection, storage, refresh and correction before admitting
   its 15 standard products. Unown, Futsal and Yellow A remain unaliased
   directory names but their complete 39-card/41-product routes pass native tests.
3. **293 Magic names without an explicit current Scryfall group.** Separate
   discovery-only or special releases, broad marketplace groups, future
   releases and absent source links. A missing link is not a vendor miss.
4. **123 One Piece / one Lorcana reviewed printings without mappings.** These
   are catalog authority/coverage gaps, separate from the clean installed
   mapping audit. Existing signed-catalog and production holds still apply.
5. **JustTCG and device verification.** This pass has no authenticated live
   JustTCG graded lookup or physical-device evidence. Current real JustTCG set
   slugs, grader/grade coverage and phone behavior remain unverified.

## Replay and future captures

[`scripts/audit_set_pricing.py`](../../scripts/audit_set_pricing.py) reads app
catalogs without modifying them. Offline replay verifies retained hashes and
makes no network requests. `--fetch-mapped-feeds` captures only the five group
directories and installed One Piece/Lorcana groups, with a custom User-Agent,
150 ms pacing, bounded responses and start/end build checks. Existing bytes
are reused and hash checked. Use a new external-SSD directory for a new daily
build; do not refresh or combine an older capture in place.

```sh
python3 scripts/audit_set_pricing.py \
  --capture-dir "$AUDIT_CAPTURE_DIR" \
  --output-dir /tmp/set-pricing-audit-replay \
  --native-report "$AUDIT_NATIVE_REPORT"

python3 -m unittest discover -s scripts/tests -p test_set_pricing_audit.py -v

python3 scripts/audit_magic_set_products.py \
  --queue docs/research/set-pricing-audit/2026-10-24/magic-product-review-input.csv \
  --capture-dir "$AUDIT_CAPTURE_DIR" \
  --output-dir /tmp/magic-product-review-replay \
  --verify-pinned-proof TestFixtures/TradingCards/SetPricingAudit/magic-product-proof.json \
  --verify-direct-proof TestFixtures/TradingCards/SetPricingAudit/magic-direct-product-proof.json

python3 scripts/verify_pokemon_subset_products.py \
  --capture-dir "$AUDIT_CAPTURE_DIR" \
  --proof TestFixtures/TradingCards/SetPricingAudit/pokemon-subset-product-proof.json

python3 scripts/verify_pokemon_yellow_a_products.py \
  --capture-dir "$AUDIT_CAPTURE_DIR" \
  --proof TestFixtures/TradingCards/SetPricingAudit/pokemon-yellow-a-product-proof.json
```

The Magic review uses a frozen [58-row input](set-pricing-audit/2026-10-24/magic-product-review-input.csv),
so resolved rows remain reproducible after the current queue shrinks. Offline
replay checks retained hashes and complete pagination without network access.
Its optional `--fetch` uses 750 ms Scryfall pacing and stops on HTTP 429,
retaining partial results. A rate-limited initial pass was replayed with slower
requests to complete all 58; the retained completed report has no missing or
rate-limited cases. HTTP 404 empty searches are recorded separately from 429.
Pinned-proof validation requires exact source card and complete vendor-product
projections, including sealed or numberless records that cannot match a
numbered card. The projection check caught 14 omitted records in the initial
Magic fixture; the fixture now includes them and has a dedicated regression
against such omissions.

Run the native census with the normal Xcode project/scheme and an external-SSD
derived-data/result location. The test is
`TradingCardScannerTests/JustTCGContractTests/testSystematicBundledSetDirectoryConcordance`.
It writes `set-pricing-concordance.json` to the test app's temporary directory,
prints its path as `SET_AUDIT_REPORT`, and retains the same JSON as an XCTest
attachment. Supply that file as `AUDIT_NATIVE_REPORT`. For a new capture,
`--export-vendor-fixture /tmp/vendor-groups-candidate.json` prepares a compact
candidate for the pinned test fixture; review the capture and fixture together.

Machine-readable artifacts:

- [All 1,804 installed directory entries](set-pricing-audit/2026-10-24/catalog-coverage.csv)
- [All 808 native name checks](set-pricing-audit/2026-10-24/set-concordance.csv)
- [Mapping totals, hashes and source-ID contradiction](set-pricing-audit/2026-10-24/mapping-summary.json)
- [Mapping issues: header only, zero detected](set-pricing-audit/2026-10-24/mapping-issues.csv)

## Verification

- Latest Magic/raw follow-up: **311 passed, zero failed** across graded
  contracts, pricing, variant resolution, marketplace links, catalog
  normalization and Magic treatments. Covers every retained H1R pair in the
  raw/history/owned-link paths as well as graded product discovery.
- Latest broad Debug iPhone 17 simulator selection: **356 passed, zero failed**.
  Adds exact-product/source/response guards, 103 release-family replays, all 40
  etched product pairs, Magic treatments, owned pricing and quote-cache tests.
- Yellow A targeted selection: **141 passed, zero failed**. Subsequent pipeline
  validation: **190 passed, zero failed** across graded contracts, scanner,
  reference cache and variant resolution. Final stale-cache review: **39 passed,
  zero failed**. These follow-ups verify the later edition/presentation guards.
- Offline Browse follow-up: **76 passed, zero failed**, including an upgraded
  six-slot Yellow A cache, repaired set counts and unchanged source files.
- Pokémon subset stage: **155 passed, zero failed**, including all 33 source
  cards under both print-run projections, metadata/edition/finish refusals,
  scoped question-mark behavior and existing Magic/scanner contracts. The
  latest broad selection includes these four new tests.
- Earlier Magic legacy-Normal compatibility follow-up: **182 passed, zero failed**
  across all graded contract and owned-pricing tests. The latest broad selection
  includes those contracts and the subsequent Pokémon work. Both pinned proof projections and the full
  installed cross-game mapping audit replay pass without network access.
- Alias-stage selection: **186 passed, zero failed**.
  Includes the complete name census, reviewed aliases, Rumble whole-set proof,
  wrong-game/set/number/denominator guards, ambiguity tests and focused pricing
  regressions across all five games.
- After the fixture completeness correction, all **31 ProductCatalogIdentityTests
  passed** again against every retained vendor-group record. This was a
  fixture-only follow-up to the 186-test alias-stage selection.
- Audit tooling: **15 Python tests passed**, including duplicate identities,
  wrong groups, incomplete exports, null versus zero prices, invalid amounts,
  hash-bound replay without network access, pagination boundaries, rate limits,
  empty searches, complete proof projections and collector suffix/denominator
  preservation, distinct etched-product source facts, and plain-holo subset
  scope with conflicting product IDs or collector totals rejected. Yellow A
  projection distinguishes finish products without dropping letter suffixes.
- The expanded Magic-stage selection completed **315 tests, six skipped,
  zero failed** (309 passed). Live Lorcana acceptance tests were explicitly
  skipped by their opt-in gates. The final focused selection above includes
  the subsequent Creator Pack fix and both new whole-set proofs.
- The card-level baseline rejected 11 proposed aliases and ten double-faced
  names. Only ten Magic aliases were admitted; the front-face naming issue
  is now addressed through verified product identity when a source ID exists.
  The alias fixture still covers the 594 verified cards.
- An intermediate etched-fixture run had nine assertions fail in its 40-card
  test. Corrected finish labels and independently reconciled vendor group
  display names; the complete 40-card rerun and broad selection above pass.
- The initial census completed and reported the 26 expected failures; Xcode
  then stalled finalizing diagnostics and was terminated. That incomplete
  baseline result bundle is not a passed or finalized test result. Subsequent
  verification disabled verbose failure diagnostics and completed normally.
- The final result bundle and raw public feed captures remain on the external
  SSD. Generated ledgers contain public catalog metadata only. No full-target,
  archive, provider-wide completeness, CloudKit or release readiness claim is
  made from this focused run.
