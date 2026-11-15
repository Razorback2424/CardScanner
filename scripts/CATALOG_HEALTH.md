# Catalog health export

Run `python3 scripts/catalog_health_export.py --output <directory>` or trigger
the **Catalog Health Audit** workflow and download its artifact. The three CSVs
are deterministic for the checkout; the inventory contains all records in the
retained inputs described below, exceptions are its rows with issues, and the
summary counts each issue separately. Severity distinguishes review,
availability, refresh, and unchecked work. `catalog-metadata.json` records
source hashes and freshness parameters. CSV values are raw data and should be
treated as untrusted when opened in a spreadsheet.

This is an offline evidence census, not a complete live catalog or price audit.
It reads Pokémon's raw checklist slots, Magic's **test-only treatment subset**,
the installed One Piece owner registry, Lorcana discovery and physical records,
the Yu-Gi-Oh seed and reference printings, and the retained October 2026 One
Piece unmatched marketplace report. The latter is an incomplete historical
discovery lead; products already mapped in the current owner registry are
excluded, and number-only candidate matches are not physical identity proof.
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
date, is the quote snapshot date. A zero price is usable; a missing or null lane
in a complete feed is `NO_MARKET_QUOTE`. A non-null quote older than the
threshold is `PRICE_STALE`. Missing feeds or products remain unchecked and
invalid captures fail the export. Product ID, name, and printed number must
agree before a feed can change a row's price status. No request-failure
classification is fabricated. The workflow uploads captured source bytes in a
separate artifact so the export can be replayed; the metadata includes the
capture manifest hash.
Exact missing mappings are reported for verified One Piece and Lorcana finishes
and supported Yu-Gi-Oh editions whose retained records expose those mappings.
Blank evidence fields mean unknown, not absent. The source validation and
boundaries are shared with `audit_catalog_coverage.py`; structural errors fail
the run instead of publishing a partial result. The output should not be used
to claim total cross-game catalog completeness.
