# Per-card price history chart — continuity plan

**Status:** current plan — proposed 2026-09-14, **not implemented**. No code in
this plan has landed; every acceptance box below is open.

**Where this is picked up:** the active
[launch plan](../superpowers/plans/2026-09-13-phase-0-phase-1-app-store-launch.md)
§0.1.2 lists this plan as current work outside launch scope, so it is not lost
when Phase 0/1 execution resumes. Slice A is independent of that plan. The
source dependency identified by pass-2 F02 was remediated and focused-verified
on 2026-09-19; Slice B remains unimplemented and is measured by RF-8.

**Concern owned:** why the per-card price chart renders as isolated dots, and
what may honestly be done about it. The chart itself is
`PriceHistoryChartModel` / `PriceHistoryChartView` in
[`CollectionCardDetailView.swift`](../../TradingCardScanner/Views/CollectionCardDetailView.swift).

## The observed problem

On the 1M range the card detail chart shows six points, of which only the first
three are joined by a line. The rest render as free-floating dots with a
footnote reading "Gaps mean the app did not have a successful price check for
that span."

The chart is not wrong. It is reporting a coverage fact, and the shape is the
honest consequence of three mechanisms:

| # | Mechanism | Location |
| --- | --- | --- |
| 1 | Two samples are joined only when **every** calendar day between them has a `PriceCheckDay` row for that instrument. One missing day breaks the segment. | `CollectionCardDetailView.swift:1762`, `allDaysChecked(from:to:in:calendar:)` |
| 2 | A `PriceCheckDay` row exists only for a day on which a refresh actually succeeded for that instrument — "the row's existence is the fact coverage actually reads." | `PriceObservationLog.swift:308`, `recordSuccessfulCheck` |
| 3 | A `BGAppRefresh` launch prices at most **three** cards, so on days the app is not opened a given card almost certainly gets no row. | `BackgroundPriceRefresh.swift:59`, `appRefreshTargetLimit = 3` |

Foreground passes are uncapped and the staleness interval is 8 hours
(`PriceRefreshController.swift:1657`, `automaticRefreshInterval`), so a user who
opens the app daily already gets a continuous line. The dotted chart is what a
normal, intermittent usage pattern produces.

## The constraint that shapes every option

`PriceObservation` and `PriceCheckDay` are **not chart tables**. They are the
portfolio valuation ledger: `PortfolioReplaySnapshotBuilder` builds the replay
from `PriceObservation` rows, and market movement, contribution attribution, and
every published `PortfolioDailyClose` derive from them.

> Writing backfilled or synthesized price rows into either table would silently
> rewrite portfolio history and re-cut closes that have already been shown.

This is the governing rule for this plan. Nothing here may add, interpolate, or
infer a `PriceObservation` or a `PriceCheckDay`.

## Scope

**In scope**

- **Slice A — carried-forward rendering.** Make the chart read as a line without
  claiming a measurement the app does not have.
- **Slice B — coverage.** Reduce how often a gap occurs at all.

**Explicitly out of scope**

- **Provider history backfill.** JustTCG publishes a per-day `priceHistory`
  array (`include_price_history`, `priceHistoryDuration`), and the parameter is
  already plumbed through `JustTCGV1Client.fetchPrices(includePriceHistory:)`
  with every caller passing `false` and no decoder for the response field. It is
  deliberately **not** pursued here: this card is priced by Scryfall, so a
  JustTCG series would be a source change that `PortfolioReplay` classifies as
  pricing adjustment rather than market movement, and a safe implementation
  needs its own table outside the replay plus the free tier's 900-request
  monthly ceiling. Recorded as a rejected option, not a backlog item. Reopen
  only with a new dated plan.
- Extending any line to "now." The header already states the current price and
  its check time; drawing to the right edge would assert a value for a span with
  no evidence.
- Changing `allDaysChecked`, the segment rule, or which samples exist.
- Scryfall and TCGdex history. Scryfall publishes current prices only and its
  own docs call price data "dangerously stale after 24 hours"; TCGdex exposes
  `avg7`/`avg30`/`trend` (`TCGdexCard.swift:388`), which are rolling aggregates.
  Plotting either as a daily series would be fabrication.

## Slice A — carried-forward rendering

### Rationale

On an unchecked day the app does not know the price held steady; it knows the
last value it recorded. Those are different claims, and the chart must keep them
visually distinct rather than collapsing them into one line. A dashed,
de-emphasised connector between two real samples asserts exactly "last known
value, not verified in between" — which is true — while giving the eye a
continuous series.

`.interpolationMethod(.stepEnd)` is already in use and is the correct shape: a
connector drawn step-end runs flat at the earlier sample's value until the later
sample's date, then steps. That is a literal picture of "carried forward."

### A1 — model

Add a derived bridge type to `PriceHistoryChartModel`:

- `PriceHistoryBridge: Identifiable, Equatable` holding `id`, `from:
  PriceHistorySample`, `to: PriceHistorySample`.
- Derive `bridges` in `make(...)` **after** `segments` is built: for each
  adjacent pair of segments, one bridge from `previous.samples.last` to
  `next.samples.first`.
- Gate on `observationCount >= 2`, matching the existing segment gate, so the
  single-observation path is untouched.

Invariants, to be asserted by test:

- A bridge references existing sample endpoints only. It never introduces a
  sample, a date, or an amount.
- `segments`, `samples`, `observationCount`, `checkedDayCount`, and `hasGaps`
  keep their current meaning and values. `segments` remains the authoritative
  "verified span" concept.
- `bridges.count == max(0, segments.count - 1)` whenever `observationCount >= 2`.

### A2 — view

In `PriceHistoryChartView`'s `Chart` body, emit bridges **before** the existing
segment `LineMark`s and `PointMark`s so verified marks draw on top:

- `LineMark` per bridge with its own `series`, `.interpolationMethod(.stepEnd)`,
  a dashed `StrokeStyle`, and a reduced-emphasis foreground style.
- The **dash pattern**, not opacity alone, must carry the meaning, so the
  distinction survives high contrast, grayscale, and
  `accessibilityReduceTransparency` (already read by this file).

### A3 — copy and accessibility

Replace the single "Gaps mean…" footnote with two-state copy that names both
conditions. It must not say or imply the price was flat. Working text, subject
to a copy pass:

> Solid line: checked every day in that span. Dashed: no check in between — the
> last known price, carried forward.

The chart's accessibility label and value must state the same distinction; a
VoiceOver user must be able to tell a measured span from a carried-forward one.

### A4 — deterministic verification

`PriceHistoryChartModelTests` (`PricingTests.swift:684`) already has
`observation(day:)` and `checkDay(day:)` helpers, so these are cheap:

- [ ] One unchecked day between two checked days yields exactly one bridge, and
      its endpoints are the two segments' adjoining samples.
- [ ] A fully checked span yields zero bridges and one segment.
- [ ] `observationCount == 1` yields zero bridges and no check-day samples.
- [ ] N segments yield N−1 bridges; no bridge precedes the first sample or
      follows the last.
- [ ] No bridge endpoint has a date or amount absent from `samples`.
- [ ] `samples` and `segments` are byte-identical to the pre-change model for a
      fixture with no gaps (a no-regression anchor).

### A5 — visual verification

Deterministic capture through the existing `CardDetail` debug route and
`scripts/ui_build_and_shoot.sh`. `PortfolioDebugFixtures` currently seeds
**contiguous** check days (`PortfolioDebugFixtures.swift:120`–`150`), so a
gapped fixture must be added — one that omits check days for a middle span —
otherwise the route cannot render the state this plan exists to fix.

- [ ] Gapped fixture route added and seeded without touching the contiguous one.
- [ ] Light, dark, and AX5 captures inspected; dashed and solid spans remain
      distinguishable in all three.
- [ ] Capture recorded under `docs/artifacts/` per existing checklist practice.

## Slice B — coverage

Slice A changes how a gap is drawn. Slice B reduces how often one occurs. The
two are independent and A does not depend on B.

There is no honest shortcut here: a `PriceCheckDay` row requires an actual
successful price check, so coverage is bounded by provider allowance and by the
background-task budget. Slice B is therefore a measurement exercise before it is
a code change.

### B1 — sequencing gate (blocking)

**Do not raise background throughput until pass-2 F02 is fixed.** The headless
preflight currently builds a CloudKit-mirrored container for exactly the
`.neverAttached`/`.suspended` stores it then reports as `.onDevice`
([`../audits/defect_review_pass_2.md`](../audits/defect_review_pass_2.md) F02).
Running background refresh more often multiplies exposure to that defect.

- [ ] F02 fixed and verified before any B2/B3 work begins.

### B2 — replace the count cap with a budget

`appRefreshTargetLimit = 3` is justified in source by JustTCG pacing — "Three
vendor fall-throughs fit comfortably within an opportunistic app-refresh window
even when each needs one paced identity request" — against the transport's
6.5 s `minimumRequestInterval`. That rationale is provider-specific and does not
obviously apply to Scryfall-priced Magic rows, which do not go through the
JustTCG pacer.

Proposed change: express the cap as an elapsed-time budget checked between
targets rather than a fixed count, so a pass completes as many targets as the
window actually allows and stops cleanly before expiration. Background passes
already set `sortOldestFirst: true`, so longest-unchecked cards rotate to the
front and a budgeted pass spreads coverage without extra bookkeeping.

- [ ] Budget replaces the count cap; `BGTask.expirationHandler` still completes
      the task cleanly.
- [ ] No change to foreground behavior.

### B3 — device measurement (cannot be retired in the simulator)

Tracked as RF-8 in [`release_followups.md`](release_followups.md).

- [ ] Measure the real `BGAppRefresh` window on device and record how many
      targets a budgeted pass completes, split by provider.
- [ ] Confirm the pass does not trip JustTCG's daily allowance
      (`JustTCGQuota.backgroundDailyCeiling = 75`) on a large collection.
- [ ] Re-measure chart continuity on a real collection after a week.

## What this plan does not promise

Slice A makes an intermittently-checked card **read** as a continuous series
while remaining truthful about which spans are measured. It does not add data.
A user who opens the app twice a month will still see two verified points joined
by a long dashed carry-forward, because that is what the app actually knows.
Making that line dense is Slice B's job, and Slice B is bounded by provider
allowances that this plan does not attempt to escape.

## Re-run rule

Update the smallest relevant box above as each slice lands, then add one dated
line to [`../../progress.md`](../../progress.md). Slice B3 is a device gate and
must be closed in [`release_followups.md`](release_followups.md), not by
weakening a claim here. When this plan is complete or superseded, move it to
[`../legacy/`](../legacy/) with a banner per [`../AGENTS.md`](../AGENTS.md)
rule 3 and update the [documentation map](../README.md) and
[`documentation_audit.md`](documentation_audit.md).
