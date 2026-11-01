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
| Gengar POR 050/088 | TCGdex already publishes exact unstamped Cosmos **709697**, separate from ordinary **684431**, GameStop **685555**, and EB Games **686505**. Its Cosmos USD quote is null. | **Passed offline:** existing direct-product route chooses only the exact Near Mint listing and rejects the other products. No live JustTCG response was available to establish why the reported request remained unpriced. No duplicate mapping added. |
| Genesect EX, 30th Classic Collection | Existing mapping `30th-c-004` → **716158**, printed **11/101**, Genesect EX (Team Plasma), is correct. The inspected ReleaseLocal bundle has an empty feed URL; the trusted public feed marker returns **404**. TCGdex has no quote/handle. | **Implemented:** reuse the existing mapping for exact paid-provider lookup when the daily feed cannot answer. Only Holo with nil/Unlimited print run; no new identity table. Historical request failure and live paid quote remain unverified. Feed activation remains an operational gate. |
| N's Zekrom ASC 155, Pokémon Center Holo | Reviewed physical objects do not establish this stamped combination. A retained EUR observation is not a USD price for it. | **Protected:** identity review, excluded foreign valuation, no automatic rekey or borrowed price. Physical evidence is still required. |
| Terapagos ASC 178, plain Reverse | Reviewed exact objects do not establish plain Reverse. | **Protected:** physical identity review and no automatic correction. |
| Spinarak Team Rocket Returns 78, CGC 10 Gem Mint, Normal | Public card identity is `ex7-78`, ordinary product **89455**. A local `cardNotTracked` outcome can include rejected response identities; it does not prove provider absence. | **Passed offline:** exact set/name/number, CGC numeric filter, Normal finish, grade label and qualifier checks. Authenticated response/match-rejection diagnosis **unavailable**; no assertion that the provider lacks this slab. No certificate retained. |
| Oshawott WHT 021, Tinsel | TCGdex declares Tinsel but gives that object only a Cardmarket handle. The base product **642133** has a flat Holofoil quote; that is insufficient proof of a Tinsel USD lane. | **Coverage gap:** remains unpriced. No Tinsel-to-Holo/Reverse alias or EUR conversion. |

## Evidence and change boundary

The two supplied card photos were inspected as pixels in a private local input
directory. The CSV was read there; photos, export, quantities and certificate
identifiers are excluded from the repository. Public-only regression resources:

- [Exact Cosmos catalog/product proof](../../TestFixtures/TradingCards/PokemonCatalogCoverageAudit/reported-parallel-review.json): five full public card objects and their selected TCGplayer/TCGCSV product records, scoped URLs and canonical content hashes.
- [Other exact catalog cases](../../TestFixtures/TradingCards/PokemonCatalogCoverageAudit/reported-unpriced-review.json): public TCGdex objects only, without collection fields.
- The existing `PokemonTCGCSVMapping` and retained 30th fixtures remain the Genesect mapping authority. The public marketplace detail response independently confirmed product 716158, name and 11/101.

The runtime patch adds four reviewed Cosmos bindings, augments exact-card
choices and cached Browse slots, and reuses the existing daily-feed mappings
for direct paid-provider lookup. Provider conflicts reject the binding. It does
not change stored collection identities, generic `ProductFinish` aliases,
grading matching, signed resources, catalog publication or release settings.

The census now checks the five exact Cosmos proofs and reports the two missing
raw slots separately from the runtime projection. The all-Normal cohort remains
a risk queue; it is not classified as proven bad data.

## Verification

- Focused native run: 347 cases, **345 passed, one skipped, one failed**. The failure was existing graded-picker fixture Keychain storage `-34018` in an unsigned simulator build; it was not a failed catalog assertion.
- Independent rerun of the three new Cosmos tests: **3 passed**.
- Final ad hoc signed simulator aggregate on Xcode 27.1 / iOS 27.0: **821 cases, 820 passed, zero failures, one skipped** (`testLivePublishedMistyRefresh`, requiring explicit live-feed opt-in). Includes every native selection in `catalog-coverage-tests.yml`, plus JustTCG contracts, scanned graded matching, refresh lifecycle and supplemental-feed tests. The earlier fixture Keychain failure passes in this final run.
- Python ingestion/audit aggregate: **154 cases, 149 passed, five skipped** (optional shared Swift Yu-Gi-Oh publisher binary not supplied).
- Yu-Gi-Oh membership/printing-family aggregate: **33 passed**.
- Pokémon catalog core: **84 cases, 83 passed, one skipped**.
- Magic catalog core: **18 passed**.
- Retained-data census: **zero structural errors**, five Cosmos product proofs checked. Hosting configuration and whitespace checks pass. Hosting configuration validity does not establish a published feed.

The raw census contains **4,421** all-Normal risk rows at this baseline. The
previous 4,321 figure is not adopted as a current count; neither count proves
that those cards have incorrect physical finishes.

## Remaining gates

Authenticated JustTCG raw and graded replay was blocked: automatic approval
review denied extracting the app-scoped Mac Keychain pricing secret, stating
that credential access was not authorized. The denied action did not execute;
no credential was read or exported, and it was not retried through another
route. Public provider queries and offline work continued. This is a pending
authorization/availability gate, not evidence of missing vendor coverage.

A prior local-task receipt records a successful iPhone install. The inspected
ReleaseLocal app bundle reports **1.0 (1)**, Xcode **27A9275**, iPhoneOS **27.1**,
and an empty `TCGCSV_PRICE_BASE_URL`. That version is not unique to a source
revision, and current device enumeration reports the physical iPhone
disconnected. Current installed source identity, live refresh on the device and
physical rescanning are unverified. No app was installed, no collection was
changed, and no signed catalog was published in this task.
