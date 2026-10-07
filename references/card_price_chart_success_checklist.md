# Card price chart acceptance — 2026-10-07

- Target: owned card detail price chart.
- Route: `CardDetail`, state `price-chart`; isolated synthetic QA Simulator.
- Device: iPhone 17 Pro, iOS 26.5.
- Evidence: external SSD, `CodexBuilds/CardPriceChart-20261007/`.

## Visual and interaction checks

- [x] Currency labels and gridlines make the price scale readable.
- [x] Observations stay inside the plot; smaller dots keep the line legible.
- [x] Gaps remain visible and are identified as unchecked.
- [x] Scrubbing updates the headline amount/date and shows a cursor.
- [x] A gap shows no invented price; release restores the current value.
- [ ] Vertical scrolling and range selection remain usable.
- [ ] Accessibility text size preserves labels and source information.
- [x] Repeated settled capture inspected (`verified/ui-latest.png`); final
  accessibility action relocation changes no visible layout.

## Verification

- [x] Focused model regression: 15 tests passed, no failures (12 owned chart,
  3 Browse chart), including checked-step selection and unchecked-gap rejection.
- [x] Final Debug simulator build and whitespace check. The initial final build
  hit a SwiftUI type-checking limit; moving the reset action outside the chart
  modifier chain fixed it, and the final build succeeded.

## HIG review

Verdict: RISK. Platform patterns, clarity, ordinary-size legibility, interaction
cost and honest gap presentation pass the scoped review. VoiceOver stepping and
reset actions are implemented; actual VoiceOver and larger-text acceptance are
unverified. The owner requested testing conclude before those checks. No new
blocking prompts or navigation changes were introduced.
No physical-device, live historical-provider or release acceptance is claimed.
Provider backfill remains unimplemented; see the
[pricing-plan audit](../docs/plans/browse_pricing_coverage_plan.md#final-architectural-decision).
