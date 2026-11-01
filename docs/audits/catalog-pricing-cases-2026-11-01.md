# Exact Pokémon finish and pricing cases — 2026-11-01

**Baseline:** `main@0ab3b0e6c59bb8561f3ee4610bccd0f311bb716b`.
**Candidate:** `fix/catalog-owner-cases-2026-11-01`.
**Status:** bounded implementation and deterministic verification; live paid-provider
and physical-device acceptance remain open. This extends the
[catalog audit](catalog-coverage-audit-2026-11-01.md) and
[pricing correctness authority](../plans/pricing_correctness_and_coverage.md).

## Case matrix

Statuses distinguish a verified public identity, a tested route, and an actual
market response. Synthetic test prices are never production quotes.

| Case | Public evidence and diagnosis | Candidate / remaining acceptance |
| --- | --- | --- |
| Marshadow PBL 040/084 | TCGdex `me05-040` omits Cosmos. Exact Blister Exclusives product **714065**, full number and card text agree. | **Implemented:** Cosmos choice and exact binding, including cached checklist projection. Authenticated quote unavailable. |
| Team Rocket's Mimikyu ASC 097/217 | TCGdex `me02.5-097` omits Cosmos. Exact Blister Exclusives product **714066** agrees. | **Implemented:** Cosmos choice and exact binding. Existing Energy/Team Rocket choices remain distinct. Authenticated quote unavailable. |
| Charmander PAF 007/091 | Cosmos exists in TCGdex and the bundled checklist, but its object has only a Cardmarket handle. Exact Cosmos product **641613** is separate from ordinary **534142**. | **Implemented:** reviewed exact USD product route; no conversion of EUR or flat-price borrowing. Authenticated quote unavailable. |
| Charmeleon PAF 008/091 | Same missing-handle case; exact Cosmos **641614**, ordinary **534143**. | **Implemented:** exact route. Authenticated quote unavailable. |
| Gengar POR 050/088 | TCGdex already publishes exact unstamped Cosmos **709697**, separate from ordinary **684431**, GameStop **685555**, and EB Games **686505**. Its TCGdex Cosmos USD quote is null. | **Passed offline:** shared reviewed product proof reaches raw and graded binding; wrong products/stamps/languages/grades/qualifiers reject. Live JustTCG response unavailable. |
| Genesect EX, 30th Classic Collection | Existing mapping `30th-c-004` → **716158**, printed **11/101**, Genesect EX (Team Plasma), is correct. The inspected ReleaseLocal bundle has an empty feed URL; the trusted public feed marker returns **404**. TCGdex has no quote/handle. | **Implemented:** reuse the existing mapping for exact paid-provider lookup when the daily feed cannot answer. Only Holo with nil/Unlimited print run; no new identity table. Historical request failure and live paid quote remain unverified. Feed activation remains an operational gate. |
| N's Zekrom ASC 155, Pokémon Center Holo | Reviewed physical objects do not establish this stamped combination. A retained EUR observation is not a USD price for it. | **Protected:** identity review, excluded foreign valuation, no automatic rekey or borrowed price. Physical evidence is still required. |
| Terapagos ASC 178, plain Reverse | Reviewed exact objects do not establish plain Reverse. | **Protected:** physical identity review and no automatic correction. |
| Spinarak Team Rocket Returns 78, CGC 10 Gem Mint, Normal | Public card identity is `ex7-78`, ordinary product **89455**. A local `cardNotTracked` outcome can include rejected response identities; it does not prove provider absence. | **Passed offline:** exact set/name/number, CGC numeric filter, Normal finish, grade label and qualifier checks. Authenticated response/match-rejection diagnosis **unavailable**; no assertion that the provider lacks this slab. No certificate retained. |
| Oshawott WHT 021, Tinsel | TCGdex declares Tinsel but gives that object only a Cardmarket handle. The base product **642133** has a flat Holofoil quote; that is insufficient proof of a Tinsel USD lane. | **Coverage gap:** remains unpriced. No Tinsel-to-Holo/Reverse alias or EUR conversion. |
| Bidoof Pokémon GO 059/078 | Public `swsh10.5-059` has ordinary Reverse product **276982** and Reverse with `peelable-ditto` subtype **277788**. | **Implemented:** distinct stable string IDs for ordinary Reverse and Peelable Ditto. Legacy generic Reverse requires physical review; no holding migration or merge. |
| Charmander 151 004/165 | Public `sv03.5-004` distinguishes Holo + Cosmos (Cardmarket **791827**) from Reverse + Cosmos (**794909**). | **Implemented:** Cosmos Holo and Cosmos Reverse remain separate. Legacy generic Cosmos requires review. These physical proofs do not establish USD product coverage. |

## Evidence and change boundary

The two supplied card photos were inspected as pixels in a private local input
directory. The CSV was read there; photos, export, quantities and certificate
identifiers are excluded from the repository. Public-only regression resources:

- [Exact Cosmos catalog/product proof](../../TestFixtures/TradingCards/PokemonCatalogCoverageAudit/reported-parallel-review.json): five full public card objects and their selected TCGplayer/TCGCSV product records, scoped URLs and canonical content hashes.
- [Other exact catalog cases](../../TestFixtures/TradingCards/PokemonCatalogCoverageAudit/reported-unpriced-review.json): public TCGdex objects only, without collection fields.
- The existing `PokemonTCGCSVMapping` and retained 30th fixtures remain the Genesect mapping authority. The public marketplace detail response independently confirmed product 716158, name and 11/101.

The runtime patch supplies four missing Cosmos bindings and shares Gengar's
existing product proof through raw and graded paths. It augments exact-card
choices and cached Browse slots, and reuses existing daily-feed mappings for
direct paid-provider lookup. All mapped families have source name, set, local
number, product-conflict and forbidden-print-run regressions. No generic
`ProductFinish` alias, holding migration, signed publication or release-setting
change is included.

Graded safety commits `8d84619` and `da72b2c` reject unlabeled substitutes for
premium BGS/CGC designations, preserve ordinary Gem Mint normalization, parse
PSA OC/ST/MK/PD/MC as qualifiers, and retain explicit imported slab finishes.
New unbound imports use finish-qualified ownership keys; existing explicit keys
are preserved. On-disk reopen tests distinguish Normal, Reverse, unknown finish,
PSA 8 and PSA 8 OC. v2 language and exact product proof survive resolution,
matching, binding and save/reload. The existing persisted printing spelling
retains Japanese language without adding SwiftData fields. Raw Japanese direct
lookup also verifies its language lane. TCGCSV sharing says **Market price**;
this aggregate feed is not condition-specific Near Mint evidence.

The independently declared three-card blister fixture names Marshadow, Mimikyu
and Gengar, supported by the public sealed product 714361. Its retained daily
feed observation is dated **2026-10-31T20:05:59+0000**: 3 expected members,
3 exact product links and 3 non-null aggregate quote rows. These are dated
provider observations, not current authenticated acceptance or hardcoded app
prices. Tests cover persisted checklist reload without a bundle, unchanged
provider probe/count repair, offline scanner reconstruction, Browse choices,
and collection save/reopen with valid unpriced Cosmos choices. Provider evidence
still does not establish whole-catalog physical completeness; the generic
`physicalCoverageVerified` default remains a broader contract concern.

Commit `12ee460` adds the two finite physical-object repairs above. Matching
keeps base finish, foil pattern and subtype; special editions and incompatible
objects reject. Read-time checklist projection includes those exact reviewed
sets. Ambiguous saved rows keep their identity, resolution and quote evidence;
current collection snapshots, imported aliases, CSV diagnostics and portfolio
valuation exclude them. Late price deltas cannot restore an ambiguous value.
The quote observation history is preserved rather than rewritten. Native tests
save/reopen both canonical and imported rows and check these boundaries.
Follow-up `412bef3` keeps the qualified GO reverse objects in Master pack scope;
the two 151 retail Cosmos objects remain Grand Master. The official
[GO expansion announcement](https://www.pokemon.com/uk/news/pokemon-go-expansion-more-iconic-and-powerful-pokemon-revealed)
describes peelable Ditto as an expansion mechanic. Combined with the retained
numbered common-product evidence, this supports this bounded scope inference.
The 151 scope gains one distinct physical slot; GO gains one after its existing
ten rarity aliases are removed. This is no claim of complete promo coverage.

Commit `87aa90f` decodes JustTCG current/expired/unpriced status, historical
amount, last sale and expiry. Exact graded responses persist this evidence in a
backward-compatible envelope inside the existing graded metadata JSON field;
no SwiftData field or collection schema is added. Explicit expiry withdraws the
old value through the existing observation invalidation path; a timeout retains
it. A published elapsed expiry also excludes a quote from current value. New
sales can restore value; stale expiry responses cannot withdraw newer quotes.
Historical amounts never become current quotes. This closes the **graded**
expiry path; general raw-provider cached-expiry handling is not claimed here.

Bound graded refresh uses retained `card_id`, or exact `variant_id` when a card
handle is absent, and verifies the returned identity before final binding.
Discovery requests include all-null cards to avoid confusing omitted unpriced
cards with absence. Direct-handle 404 or incompatible identity remains an
unresolved identity, not terminal provider absence. Finishes, languages, stamps,
grades and qualifiers still reject independently. TAG/Authentic intake and
parsing do not establish vendor price coverage; existing tests retain those
distinctions. The broader first-graded-check provenance concern has not been
reproduced and is not claimed fixed.

Contract sources checked on this date: [v2 graded](https://justtcg.com/docs/api/cards-v2/graded),
[thin markets and expiry](https://justtcg.com/docs/thin-markets),
[changelog](https://justtcg.com/docs/changelog), and the official public OpenAPI
identifier parameters. The OpenAPI parameter list omits the all-null discovery
flag for v2 while the current v2 documentation explicitly specifies it; live
acceptance is still required. The Oct 30 weighted-median change is not modeled
by the app: only the exact amount served by the provider may be used.

The census now checks the five exact Cosmos proofs and reports the two missing
raw slots separately from the runtime projection. The all-Normal cohort remains
a risk queue; it is not classified as proven bad data.

## Verification

- Focused native run: 347 cases, **345 passed, one skipped, one failed**. The failure was existing graded-picker fixture Keychain storage `-34018` in an unsigned simulator build; it was not a failed catalog assertion.
- Independent rerun of the three new Cosmos tests: **3 passed**.
- Initial ad hoc signed simulator aggregate at `df261179`, Xcode 27.1 / iOS 27.0: **821 cases, 820 passed, zero failures, one skipped** (`testLivePublishedMistyRefresh`, requiring explicit live-feed opt-in). Includes every native selection in `catalog-coverage-tests.yml`, plus JustTCG contracts, scanned graded matching, refresh lifecycle and supplemental-feed tests. The earlier fixture Keychain failure passes in this run.
- Expanded graded/family native selection for `da72b2c`: **465 cases, 464 passed, zero failures, one live-feed skip**. Includes pricing, JustTCG contracts, scanned graded resolution, imported item kinds, item kinds, refresh lifecycle, TCGCSV, share content and product fallback.
- Physical collision selection for `12ee460`: **97 pricing tests passed**, including durable ambiguous-row exclusion and retained quote history.
- Lifecycle selection: **269 passed**; extended retained-handle selection: **270 passed**, zero failures.
- Expanded aggregate at `87aa90f`: 1,057 passing results, two deliberate skips, and one collector-scope test failing three assertions because it still expected the collapsed 151 Cosmos slot. This prompted the explicit GO pack-scope regression above. Its narrow rerun confirmed Master membership but caught an expected-total calculation using raw rows before existing rarity-alias removal; `b9177dd` corrects that calculation from retained data. Final aggregate for `b9177dd` is recorded below.
- **Completed aggregate before chronology review, source `b9177dd844221497ae89e05dc810227a870ac59d`: 1,062 cases, 1,060 passed, zero failures, two deliberate skips** (`testLivePublishedMistyRefresh` and opt-in `testAgedStoreBaseline`). Xcode 27.1 / iOS 27.0, ad hoc signed simulator. All 28 catalog workflow selections plus item-kind, TCGCSV, fallback and full portfolio reconciliation classes ran. The required workflow retains graded contracts, scanned graded resolution, lifecycle, share content and price snapshot regression suites. This is a selected aggregate, not every repository test.
- A broader stage-one selection had one `CollectionKeyTests.testREQ001UnderlyingPrintingIDUsesTheProductionSourceForEveryItemKind` assertion failure (expected nil, actual `direct-product`). The exact assertion was separately reproduced on untouched `main@0ab3b0e` using a separate baseline worktree and DerivedData. This is a baseline defect, not a green full-suite claim.
- Updated Python ingestion/audit aggregate: **155 cases, 150 passed, five skipped** (optional shared Swift Yu-Gi-Oh publisher binary not supplied). Rehashed negative proofs reject wrong subtype, base finish and physical product.
- Yu-Gi-Oh membership/printing-family aggregate: **33 passed**.
- Pokémon catalog core: **84 cases, 83 passed, one skipped**.
- Magic catalog core: **18 passed**.
- Retained-data census: **zero structural errors across 914 source files**, five Cosmos product proofs and two physical collisions checked. The dated family quote coverage is counted separately. Hosting configuration validity does not establish a published feed.

The raw census contains **4,421** all-Normal risk rows at this baseline. The
previous 4,321 figure is not adopted as a current count; neither count proves
that those cards have incorrect physical finishes.

## Expiry chronology review follow-up

Review of `132a4f7` found three confirmed chronology defects in the first expiry
implementation. Commit `72bcbeb` addresses them within the same quote path:

- Replay passes its cutoff through lifecycle eligibility, record amounts and
  canonical/legacy key selection. A valid quote before its published expiry
  stays valued at that cutoff, even after it expires today. Expiry blocks a
  legacy imported-value fallback. Explicit withdrawal still follows the
  observation log's knowledge timestamp rather than rewriting earlier cutoffs.
- A newer positive exact JustTCG observation can supersede an older mutable
  expired record while the record catches up. The instrument key, market UUID,
  any source UUID, USD eligibility and local chronology must agree. Stale,
  future-at-cutoff, foreign and wrong-identity observations do not revive it.
  Follow-up `bd26f35` also rejects a later receipt with a provably older or
  identical provider price-update clock; receipt order cannot turn a cached old sale
  into a new sale.
- A later fetch of an expired upstream snapshot cannot withdraw a newer known
  sale with a later provider sale/update clock. The comparison includes exact
  stamped observations when the record lags. Equal sale clocks still allow
  genuine expiry. Imported-valuation timestamps are not provider sale clocks.

The existing metadata JSON gains an optional source timestamp; older envelopes
remain decodable and no SwiftData field is added. Six regression tests cover
these cases, including record-only and observation-backed cutoff valuation.
Focused pricing/portfolio run: **194 total, 193 passed, one opt-in performance
skip, zero failures**. Aggregate at `72bcbeb`: **1,068 total, 1,066 passed,
two deliberate skips, zero failures**. The three historical/observation cases
are selected by the required catalog CI workflow. **Final source
`bd26f35ab46a0a8e0890bc29093b188e0d736786`: six focused passes; aggregate
1,068 total = 1,066 passed + two deliberate live-feed/performance skips,
zero failures.** The aggregate includes all 31 workflow selections plus
item-kind, TCGCSV, fallback and full portfolio reconciliation classes.

Review of `4ca368a` then reproduced a mixed-clock defect before source changes:
one test failed seven assertions when a current quote had different sale and
update times, then genuine expiry retained its sale time with an equal or newer
update. The old comparator pooled unlike clocks and kept the old quote.
`b5eb58b` compares `last_sale_at` only with known sale time, and `updated_at`
only with known price-update times. A missing field is not inferred from the
other clock. Exact-observation recovery likewise compares its update clock only
with known update clocks. Genuine same-sale expiry works, while older sale or
update evidence still rejects.

The official OpenAPI describes `updated_at` as price-observation time and
`last_sale_at` as most-recent-sale time; the synthetic regressions deliberately
keep those roles distinct. They are contract tests, not live provider evidence.
Focused pricing/portfolio run: **197 total, 196 passed, one opt-in performance
skip, zero failures**. **Final source `b5eb58bec60020fc40309c92ed85aaca7bb20ae4`:
1,071 total = 1,069 passed + two deliberate live-feed/performance skips,
zero failures.** All 32 workflow selections and the four broader classes ran;
the mixed-clock observation regression is included in CI.

## Remaining gates

The initial app-specific Keychain read was denied by automatic approval review
before execution because credential access had not been specifically authorized.
After the owner explicitly approved the exact read and JustTCG-only use, the
same bounded lookup executed once at **20:18:36 UTC**, returned **exit 44**
(app-specific item unavailable), and read no key. **Zero authenticated requests**
were made; no secret was displayed, saved, logged or transmitted, and no other
store or extraction route was attempted. Permission is resolved; the current
blocker is key availability. Vendor coverage and Spinarak match-rejection
diagnosis remain unverified.

A prior local-task receipt records a successful iPhone install. The inspected
ReleaseLocal app bundle reports **1.0 (1)**, Xcode **27A9275**, iPhoneOS **27.1**,
and an empty `TCGCSV_PRICE_BASE_URL`. That version is not unique to a source
revision. Device enumeration during this pass reported the physical iPhone
disconnected; the public feed marker was rechecked at final verification and
still returned **404**. Current installed source identity, live refresh on the device and
physical rescanning are unverified. No app was installed, no collection was
changed, and no signed catalog was published in this task.

HIG source review: **PASS** for the bounded finish labels and price-status copy.
Platform patterns, clarity, semantic typography, accessibility structure,
interaction cost and design risk pass by source inspection; existing controls
and layout are retained. No rendered-device or spoken VoiceOver acceptance is
claimed. The remaining product risk is inaccurate source evidence or provider
coverage, explicitly separated from a valid selectable finish.
