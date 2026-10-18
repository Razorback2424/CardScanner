# Individual-card market price history

**Status:** implemented locally — 2026-10-18. Focused simulator verification
is recorded in the root [progress log](../../progress.md); live-provider,
physical-device and release acceptance are separate checks.

## Product contract

Collection and catalog card details show JustTCG historical market prices for
the exact printing and finish, or the selected graded listing. History does
not start at acquisition and is not limited to days the app checked a price.
The movement badge compares the first and last provider prices in the selected
range. Catalog details allow finish selection when multiple finishes exist.

The collection detail's default headline uses the same current quote as its
holding value and collection total, with that quote's source and timestamp.
Loading history must not replace that quote. JustTCG history changes and the
latest history timestamp are labeled separately; a dragged historical price
is explicitly dated. Exact marketplace product links are available across games
when the shared link builder has a trusted destination.

The chart draws a continuous linear price line with a restrained area fill.
Dragging selects an actual provider price and its timestamp; connected lines
do not create synthetic daily observations. Empty or failed provider results
remain explicit, and failures offer retry while retaining saved history.

## Retrieval and storage

[CardMarketHistoryService](../../TradingCardScanner/Services/CardMarketHistoryService.swift)
requests v1 `include_price_history=true` and `priceHistoryDuration=1y`, the
longest [documented provider window](https://justtcg.com/docs/changelog).
Graded listings use v2 `include=price_history.1y`, scoped to the USD market.
Exact vendor variant handles take precedence; unresolved identities reuse
the existing finish/edition-aware lookup rules. No other finish is substituted.

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
