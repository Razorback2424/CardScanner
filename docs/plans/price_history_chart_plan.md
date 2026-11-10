# Individual-card market price history

**Status:** implemented on `main` in `3527a29` — 2026-11-06. Focused simulator
verification is recorded in the root [progress log](../../progress.md); live-provider,
physical-device and release acceptance are separate checks.

**Portfolio movement correction — 2026-11-10:** owned card detail now shows
the selected period's portfolio impact from the same replay contribution as
Portfolio's movers, with the historical affected quantity. A single anchor
close plus live updates can already prove that impact. Market history remains
an independently labeled JustTCG series and no longer supplies the owned
card's movement summary. Verified against `2527c9b` plus the dirty working tree
in Debug on an arm64 iPhone 17 Pro / iOS 27.0 simulator: nine focused tests
passed; the related selection passed 249 tests with zero failures and one
opt-in aged-store performance baseline skipped (`PERF_BASELINE=1`).

The related selection covers `PortfolioHistoryEngineTests`,
`PortfolioReplayEngineTests`, `PortfolioCloseTests`, `PortfolioLedgerTests`,
`PortfolioReconciliationTests`, `PortfolioTrustPassTests`,
`PriceHistoryChartModelTests` and `DetailDeletionRenderTests`. The synthetic
$1.16 → $1.65 / +$0.49 case, quantities 1/2/16, one close plus live-day
movement, and flat/unavailable provider history pass. Standard and maximum
accessibility text renders were inspected, including the full production
`CardDetail / price-chart-portfolio` route and a final recapture. The artifacts
are on T7 at `CodexBuilds/PortfolioMovement-20261110/`: `Focused.xcresult`,
`Related.xcresult`, their summaries, `FocusedAttachments/`, `UIStandard/`,
`UIAccessibility/` and `UIFinal/`. This is filtered simulator evidence;
physical-device, live-provider and release acceptance remain separate.

**Current-quote correction — 2026-11-05:** the owner requires Portfolio,
Collection, card detail and today's chart value to use one selected quote.
The shared endpoint and regression coverage are implemented and verified by
275 related simulator tests (all passed, zero skipped). This supersedes the
earlier contract allowing today's JustTCG point to disagree with the current quote.

Verification used the source committed as `3527a29`, based on `0a11fc7`: 16
focused checks passed, followed by 275 pricing, chart, history-contract, portfolio-trust and
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
The owned card's portfolio impact uses the selected range's recorded price
changes while owned, with the same total and quantity breakdown as Portfolio.
It remains available when provider history is flat, missing or failed. A range
whose portfolio result is still calculating does not borrow an older result.
Catalog details allow finish selection when multiple finishes exist.

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
owned-collection performance ledger answer different questions. The owned
detail labels those sources explicitly and uses portfolio attribution for its
movement summary, so an unrelated flat market series cannot claim no portfolio
change.

## Historical decision

The [September continuity plan](../legacy/price_history_chart_continuity_plan_2026-09-14.md)
rejected provider backfill and proposed dashed local-check connectors. The
owner explicitly superseded that decision on 2026-10-18. Provider history now
has independent storage and never rewrites the portfolio replay. Historical
background-refresh proposals do not establish current chart requirements.
