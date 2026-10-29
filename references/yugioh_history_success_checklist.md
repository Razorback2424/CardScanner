# Yu-Gi-Oh! market history acceptance — 2026-10-28

- Target: shared market-history panel used by catalog detail; collection detail
  uses the same chart content.
- Route: `YuGiOhHistoryReview`; states `chart`, `missing-key`, `unavailable`.
- Device: isolated iPhone 17, iOS 27 Simulator.
- Inputs: real bundled product/edition identity, synthetic history; read-only QA.

## Visual checklist

- [x] History chart and USD/date labels render without clipping or overlap.
- [x] Edition picker names the selected edition and remains readable.
- [x] Missing credentials explain that a JustTCG key belongs in Settings.
- [x] Missing history displays the existing unavailable state.
- [x] Chart safe areas, ordinary Dynamic Type and dark appearance remain usable.
- [x] Complete chart and missing-key captures are inspected.
- [ ] Repeated-launch full-header capture is stable; see the limitation below.

## Behavior and verification

- [x] Native tests separate all three editions, conditions, language and currency.
- [x] Native tests verify persisted-cache reuse and catalog withdrawal/races.
- [x] Native tests verify missing credentials and existing game history contracts.
- [x] Simulator build and `git diff --check` pass.

Final focused result: **149 passed, zero failures/skips**, including the six
Yu-Gi-Oh! history regressions, existing pricing/contracts and chart/render tests.
Results and synthetic screenshots are external under
`/Volumes/T7/CodexBuild/YuGiOhHistory-20261028/`; `Verified.xcresult` records the
final selection. `verified-chart/ui-latest.png` and
`isolated-missing-key/ui-latest.png` contain complete inspected presentations.
`final-unavailable/ui-latest.png` also shows the full empty-state presentation.
A successful final Debug rebuild adds explicit dark appearance to the QA route.
Some subsequent captures lose static header glyphs while retaining the chart or
error body; the cause is unverified. Repeated full-shell visual acceptance is
therefore open, despite the complete individual captures and passing render tests.

HIG verdict: RISK for complete visual acceptance; the changed production patterns
pass the source/individual-capture review. Top issue: intermittent header loss
in the QA captures. Minimal fix to close visual acceptance: reproduce consistent
full-shell captures in a stable Simulator/device session. Reusing the existing
chart/picker and showing actionable credential failures are implemented.

| Gate | Status | Rationale / remaining fix |
| --- | --- | --- |
| Platform patterns | PASS | Existing charts, picker and navigation; no fix needed. |
| Clarity | PASS | Exact edition selection and Settings recovery are explicit. |
| Typography | PASS | Existing Dynamic Type styles; ordinary-size captures are legible. |
| Accessibility baseline | PASS | Existing chart/control semantics retained; no new custom controls. |
| Interaction cost | PASS | Existing inline retry; no blocking prompts added. |
| App Review design | PASS | Snapshot valuation and independent provider history retain honest labels. |

Live provider coverage, physical-device behavior and larger-text/VoiceOver
acceptance are separate from these fixtures. Current valuation quotes retain
their bundled source and dates; this change adds a separate provider series.
