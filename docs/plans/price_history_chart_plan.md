# Individual-card market price history

**Status:** implemented locally — 2026-10-18. Focused simulator verification
is recorded in the root [progress log](../../progress.md); live-provider,
physical-device and release acceptance are separate checks.

**Current-quote correction — 2026-11-05:** the owner requires Portfolio,
Collection, card detail and today's chart value to use one selected quote.
The shared endpoint and regression coverage are implemented and verified by
275 related simulator tests (all passed, zero skipped). This supersedes the
earlier contract allowing today's JustTCG point to disagree with the current quote.

Verification used the correction applied above `0a11fc7`: 16 focused checks
passed, followed by 275 pricing, chart, history-contract, portfolio-trust and
detail-render checks. The exact $651.85 saved quote / $635 provider-history
regression passes across ranges; earlier dates, quote refresh, local midnight,
stale/unavailable quotes and standard/accessibility rendering are covered.
The two synthetic render attachments were visually inspected. Artifacts are on
the external T7 SSD under `CardScannerPriceConsistency-20261105/`:
`FocusedReadySimulator.xcresult`, `Related.xcresult` and `RenderProof/`.
The initial `Focused.xcresult` records a test-host bootstrap termination with
zero tests executed; it is retained separately from the passing runs.
No physical-device, live-provider or release acceptance is inferred.

## Product contract

Collection and catalog card details show earlier JustTCG historical prices for
the exact printing and finish, or the selected graded listing. History does
not start at acquisition and is not limited to days the app checked a price.
The movement badge compares the first and last displayed prices in the selected
range. Catalog details allow finish selection when multiple finishes exist.

The collection detail's default headline uses the same current quote as its
holding value and collection total, with that quote's source and timestamp.
Loading history must not replace that quote. Today's plotted value and scrubbing
use that same `PriceDisplay`; catalog detail passes its selected finish's owned
quote, or its displayed catalog quote for an unowned finish. A quote refresh
updates the endpoint without waiting for the independent history cache.

Today follows the device's displayed local date. Provider points before today
retain their exact amounts and timestamps; today's provider points remain saved
in the history cache but are replaced only in presentation. The endpoint is a
current valuation snapshot, not an invented provider observation. Stale quotes
keep their actual source dates and saved-price attribution. An unavailable,
withdrawn or non-USD current quote cannot borrow today's provider price.
JustTCG history and its latest timestamp are labeled separately; a dragged
earlier price includes its date and time. Exact marketplace links are available across games
when the shared link builder has a trusted destination.

The chart draws a continuous linear price line with a restrained area fill.
Dragging selects an actual provider price and its timestamp; connected lines
do not create synthetic daily observations. Empty or failed provider results
remain explicit, and failures offer retry while retaining saved history.

## Retrieval and storage

**Reviewed Pokémon identity repair — 2026-10-29, `5be81c8` plus working-tree
changes:** requests from Collection and Browse now use the 196 reviewed
anniversary/Energy product mappings and all 90 reviewed Trick or Trade
product/finish mappings. These exact mappings take precedence over stored
handles from an original expansion. A saved Unlimited marker on these modern
products no longer causes a redundant name/set search. Product-bound cache
identities let corrected lookups bypass earlier unrelated cached misses.
Provider results must contain exactly one matching product and one English,
raw, USD, Near Mint listing for the reviewed finish; other products, finishes,
languages, conditions and grades cannot supply the chart.

The wider source/test sweep also covers normal-runtime Lorcana, One Piece,
Yu-Gi-Oh!, Magic product/cache controls and saved-card artwork projections.
It does not establish live JustTCG history availability for every card. A
current price can come from TCGCSV, Scryfall or another source while the
separate JustTCG service lacks historical points, credentials or a matching
listing. No quote is converted into invented historical data.

The final simulator selections executed 326 tests: 320 passed, six opt-in
Lorcana live/candidate checks skipped, zero failures. Exact history transport
checks use fixtures; there were no authenticated live history requests or
physical-device acceptance in this repair.

[CardMarketHistoryService](../../TradingCardScanner/Services/CardMarketHistoryService.swift)
requests v1 `include_price_history=true` and `priceHistoryDuration=1y`, the
longest [documented provider window](https://justtcg.com/docs/changelog).
Graded listings use v2 `include=price_history.1y`, scoped to the USD market.
Outside the reviewed mappings above, exact vendor variant handles take
precedence; unresolved identities reuse the existing finish/edition-aware
lookup rules. No other finish is substituted.

Provider series are saved separately from portfolio accounting, cached for six
hours, and merged by provider timestamp without a 90-day retention cutoff.
Previously retrieved points survive as the rolling API window advances, so
ALL can exceed one year over time. A fresh installation cannot retrieve dates
older than the provider exposes. Routine collection refreshes continue to
exclude historical payloads and share the existing quota/pacing infrastructure.

Neither `PriceObservation`, `PriceCheckDay`, inventory events nor published
portfolio closes are backfilled. The individual-card market chart and the
owned-collection performance ledger answer different questions.

## Historical decision

The [September continuity plan](../legacy/price_history_chart_continuity_plan_2026-09-14.md)
rejected provider backfill and proposed dashed local-check connectors. The
owner explicitly superseded that decision on 2026-10-18. Provider history now
has independent storage and never rewrites the portfolio replay. Historical
background-refresh proposals do not establish current chart requirements.
