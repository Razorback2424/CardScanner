# Catalog health export

## On-device active catalog report

In ScanStash, open **Settings → Advanced → Collection Diagnostics →
Collection Exports & Price Coverage → Export Catalog Health Report**.
This button sits beside **Export Cards Excluded from USD Value**, but is
independent of the user's collection and works even if no cards are owned.

The device report exports a CSV from the **currently active Browse catalogs**
for Pokémon, Magic, One Piece, Lorcana and Yu-Gi-Oh. Card rows contain
exceptions by product, printing and finish. Set coverage rows include Browse
notices and shared Yu-Gi-Oh printed-code families in `shared_family_codes`,
with the affected record count in `shared_issue_records`. A family may
appear in several products. Product rows and finish counts describe appearances,
so summing them does not yield a unique-card or unique-family count.

Game coverage counts completed, incomplete and deferred sets, along with
checked and unevaluated finish records, specific exception rows and blocked
price checks. Failed Magic pages report the number of printing records
retrieved before the failure. Deferred sets were never requested. Missing
directory or marketplace evidence has its own notice. A catalog activation
or cancellation rejects the export before it can be saved.

**Check catalog prices** is off by default: pricing every finish in all five
games sends many provider requests. Use a targeted price audit (below) to check
mapped prices. When the toggle is on, price evidence is finish specific and
can come from the existing price resolver cache. The CSV reports
the provider, listing, observation time and provider data date when available.
With pricing off, all rows use `not_checked` and price amounts are empty.
With pricing on, distinguish `no_usd_quote` from provider failures, stale
evidence and unsupported checks.

The full report reads Magic from Scryfall's daily **Default Cards** bulk
file, as Scryfall requires for large lookups: one metadata request plus one
download (about 80 MB) from the unmetered `data.scryfall.io` origin,
replacing roughly 750 per-set searches. The download must match the published
size, every record must decode, gzip's checksum must verify, and printing IDs
must be unique; otherwise all Magic sets are deferred rather than partially
reported. English, non-digital paper printings are spooled to a temporary
directory in Caches, read back one set at a time, and deleted after the
export. Bulk prices carry the file's `updated_at` as their observation time,
so a file more than 24 hours old reports stale price evidence. CSV rows from
this source use the `scryfall_bulk_data` evidence scope. A set with no bulk
printings is a set-level error, not a provider outage. On Nov. 16, 2026 the
live file held 120,139 records (108,316 kept across 973 sets), every record
decoded under the app's field rules, and per-set counts matched the
previous search (`e:SET lang:en game:paper`, unique prints, variations) for
14 sampled sets including token, scheme, plane and oversized sets.

A single-set price audit still uses the paced printing search, which requires
a complete page sequence with matching provider totals. Every Scryfall API
request in the app (Browse, scanner and export) shares one pacer: card
searches start at least 600 ms apart (published limit 2 per second) and other
methods 120 ms apart (limit 10 per second). A 429 locks every caller out for
at least 30 seconds, matching Scryfall's documented penalty, or longer when
Retry-After says so. Transient HTTP and network errors get one retry, while a
rate limit or access denial defers the remaining sets. The Nov. 15, 2026 device
report's 657 generic Magic errors occurred while searches were spaced 200 ms
apart, above the 2-per-second search limit. That is the likely cause, but the
original HTTP statuses were not retained, so it is not proven.

### Targeted price audit

**Export Price Audit** (beside the report button) prices one game, or one of
its sets, and is meant for verifying marketplace mappings such as new One
Piece releases without scanning every catalog:

- Only verified printings with an approved exact marketplace mapping are
  priced: One Piece and Lorcana `exact` mappings, supported Yu-Gi-Oh editions
  with a market product, Pokémon cards with a reviewed TCGplayer product,
  and each Magic printing's own Scryfall prices. Other finishes are counted
  in `price_audit_excluded_finishes` and never requested.
- Prices go through the same resolver as Browse, so cached quotes and the
  grouped, 24-hour-cached hosted feeds are reused. JustTCG is not used.
- One rate-limit response, or three consecutive provider failures, stops
  price requests. The remaining finishes stay unevaluated in the coverage
  rows and later sets are `set_deferred` with `PRICE_AUDIT_STOPPED`.
- Rows are `price_failure` records carrying only pricing issue codes
  (`NO_USD_QUOTE`, `PRICE_EVIDENCE_STALE`, `PRICE_PROVIDER_UNAVAILABLE`,
  `PRICE_MAPPING_MISSING`, `PRICE_IDENTITY_MISMATCH`, …). Catalog identity
  and coverage findings are left to the full report. An `audit_scope` row
  states what was examined; a set missing from the active catalog is
  reported as `AUDIT_SET_NOT_ACTIVE`.

**Interpretation matters:** a price-history chart can have dated
observations while the selected finish still lacks an eligible **current**
quote. The November 15 current-quote fallback in the detail views checks a
unique exact physical product/finish and provider quote lifecycle; the report
must not infer a current price merely from historical chart points.
A valid existing price is not replaced simply because a history lookup
returns older or no data. See the
[implementation checkpoint](../docs/current-implementation-2026-11-15.md).

The on-device report is independent of the offline repository audit below.
The latter's `candidate` and historical observations are **not**
automatically assumed to be activated on the iPhone. Conversely, offline
test-only Magic coverage must not be mistaken for the device's live Scryfall
Browse results. Some providers and releases may not enumerate when the
device is offline; those failures are explicit in the CSV.

## Offline repository audit

Run `python3 scripts/catalog_health_export.py --output <directory>` or trigger
the **Catalog Health Audit** workflow and download its artifact. The four CSVs
are deterministic for the checkout; the inventory contains all records in the
retained inputs described below, exceptions contain actionable rows, and the
summary counts each issue separately including unchecked coverage, per source scope.
The fourth CSV, `catalog-census-findings.csv`, preserves the existing five-game
census's source/set-level diagnostic codes and dispositions instead of
silently omitting them. It is not one row per physical printing. Filter the
inventory's `assessment` to distinguish actionable issues from
`coverage_not_evaluated` and `no_known_exception`. Severity distinguishes review,
availability, refresh, and unchecked work. `catalog-metadata.json` records
source hashes and freshness parameters. Spreadsheet-dangerous leading characters
are prefixed with an apostrophe in the CSV, including after leading whitespace;
this changes the CSV representation of those values.
Use a fresh output directory for each run. Existing catalog health output files
are never overwritten or mixed with a later failed run.

This is an offline evidence census, not a complete live catalog or price audit.
It reads Pokémon's raw checklist slots, Magic's **test-only treatment subset**,
the bundled One Piece owner registry and Bandai Browse discovery observations,
Lorcana discovery and physical records,
the Yu-Gi-Oh seed and reference printings, and the retained October 2026 One
Piece unmatched marketplace report. The latter is an incomplete historical
discovery lead; products already mapped in the current owner registry are
excluded, and number-only candidate matches are not physical identity proof.
Browse observations are grouped by product and printed number, as in the
app; multiple artwork aliases are retained together as evidence.
The bundled owner seed is not proof of device activation (rollout/configuration is separate).
Additional discoveries from the retained revision-4 candidate are labeled
`candidate_discovery`; they are not necessarily present in installed Browse.
`product_set_code` identifies the release where a One Piece entry appears;
`printed_set_marker` identifies the number printed on the card. A blank product
code means the release label does not identify exactly one code.
Magic card data is live and the
retained subset is not exhaustive. Pokémon read-time corrections and mapping
logic are not evaluated. The census does not include unretained provider data,
prove physical completeness, or verify the One Piece signature. A Lorcana
discovery row can coexist with reviewed printing rows where its family remains
incomplete; it is a separate unresolved source record, not another printing.
Yu-Gi-Oh editions appear in the finish column and are not physical foil finishes.

By default no provider lookup or snapshot is consumed. Consequently
`PRICE_NOT_CHECKED` does not mean there is no quote. The optional workflow input
captures current TCGCSV feeds for installed One Piece and Lorcana mappings;
the capture uses the existing paced audit and can take time or fail when the
provider is unavailable or changes its upstream build. For offline replay use:

```sh
python3 scripts/catalog_health_export.py --output <directory> \
  --capture-dir <retained-audit-set-pricing-capture> --as-of 2026-11-15 --max-age-days 30
```

The capture must have a completed matching upstream build and hash-bound,
valid product and price feeds. The feed's upstream date, not the workflow run
date, is the quote snapshot date. A zero price is usable; a missing or null lane in a complete feed is
`NO_MARKET_QUOTE`. An older *feed snapshot* is `PRICE_SNAPSHOT_STALE`;
this does not assert the source's per-quote update time. A stale null quote
retains both issues and does not establish current availability. A missing capture
group remains unchecked. A missing/changed product in a complete captured
group is `MARKET_MAPPING_MISMATCH`, not a missing price. Incomplete retained
mapping evidence is `MARKET_MAPPING_INCOMPLETE` even without a capture.
Invalid captures fail the export. Product ID, name and printed number must
agree before the feed is trusted as a price observation. No request-failure
classification is fabricated. The workflow uploads captured source bytes in a
separate artifact so the export can be replayed; the metadata includes the
capture manifest hash.
Exact missing mappings are reported for verified One Piece and Lorcana finishes
and supported Yu-Gi-Oh editions. Yu-Gi-Oh's current-price path uses the printing
product/edition even when historical membership evidence is absent. One Piece
retains distinct unapproved, conflicting and absent mapping states, as well as
all associated product appearances of verified printings.
Blank evidence fields mean unknown, not absent. The source validation and
boundaries are shared with `audit_catalog_coverage.py`; structural errors fail
the run instead of publishing a partial inventory. When structural or market
capture validation fails, `catalog-run-failure.json` records the stage/error,
while existing census findings remain available. The GitHub artifact upload
runs even after these validation failures. The output should not be used
to claim total cross-game catalog completeness.

## EB-05 publisher-side follow-up

The separate [EB-05 mapping preparer](prepare_one_piece_eb05_market.py)
evaluates already verified, English, exact-artwork-and-finish EB-05 records
missing an exact marketplace mapping. Its current title validation requires
the retailer's supported treatment and exact product ID, and one unique
Normal/Foil price lane. The feed validator rejects duplicate price lanes before
matching. Missing lanes, reused product IDs, mismatched titles, and insufficient
retailer evidence leave the mapping **held**. Physical-card verification
requires independent evidence. The preparer does not authorize any unverified
Browse discovery record or publish a new signed release. Focused regression:
`scripts/tests/test_one_piece_eb05_market.py`.

The GitHub [live artwork audit](../.github/workflows/one-piece-eb05-artwork-audit.yml)
compares pictures as read-only candidate evidence. An image match alone cannot
authorize a printing, finish, or market mapping.

## Reproducible evidence and failures

The [Catalog Health Audit workflow](../.github/workflows/catalog-health-audit.yml)
is **manual**. It always attempts to retain its output, even after a
structural failure, and may upload `catalog-run-failure.json` instead of
a usable census. With `capture_prices=true`, the workflow separately
uploads retained market captures, subject to provider availability and
upstream-build validation. A workflow artifact's presence is **not** proof
that the inventory completed or that every iPhone Browse game was enumerated.
Recheck the output's metadata, source hashes, assessment and failure file
before comparing it to an on-device export.

See [CATALOG_HEALTH_FAILURE_MODES.md](CATALOG_HEALTH_FAILURE_MODES.md) for the
source-grounded, five-game inventory of publisher validation failures, app
error messages, runtime-only outcomes, exact export classifications, and
remaining unobservable coverage. No offline absence of a failure row is proof
that the corresponding live path is free from errors.
