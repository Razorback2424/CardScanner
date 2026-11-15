# Catalog health export

## On-device active catalog report

In ScanStash, open **Settings → Advanced → Collection Diagnostics →
Collection Exports & Price Coverage → Export Catalog Health Report**.
This button sits beside **Export Cards Excluded from USD Value**, but is
independent of the user's collection and works even if no cards are owned.

The device report exports a CSV from the **currently active Browse catalogs**
for Pokémon, Magic, One Piece, Lorcana and Yu-Gi-Oh. It includes all visible
cards/printings, product memberships, current catalog generation and release
revision where available, per-set expected versus enumerated row counts,
verification warnings, finish/edition evidence, and active market mapping IDs.
Its `record_type` separates `card`, `set_summary`, `set_notice`,
`set_error`, and `game_error`; failed pages are not silently treated as
healthy sets. A catalog activation during export rejects the mixed snapshot.

**Check live catalog prices** is on by default. It requests price statuses
through the same Browse price resolution path and reports `priced`,
`no_usd_quote`, `mapping_missing`, `printing_needs_review`,
`unresolved` or `not_checked`. The displayed
`browse_aggregate_price_usd` is a **card-summary aggregate**, not proof
that every finish has a distinct usable quote. The exact mapping evidence is
recorded separately by printing and finish/edition. Price checking the
entire catalog may require significant network activity; switch it off for
a quicker mapping/verification-only export. A cancelled run never presents
a partial report. The report does not change any catalog or collection data.

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

See [CATALOG_HEALTH_FAILURE_MODES.md](CATALOG_HEALTH_FAILURE_MODES.md) for the
source-grounded, five-game inventory of publisher validation failures, app
error messages, runtime-only outcomes, exact export classifications, and
remaining unobservable coverage. No offline absence of a failure row is proof
that the corresponding live path is free from errors.
