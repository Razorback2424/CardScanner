# Centering review and qualified results — 2026-11-04

Target screen: guided centering, optional edge/perspective comparison, PNG report.
Routes: `Centering`, `CenteringPrecision`, plus deterministic comparison entry.
Expected devices: dedicated iPhone 17 Pro and iPad simulators.
Evidence: external SSD `CodexBuilds/CardScanner-CenteringSlice5-20261104`.

## HIG gate — implementation preflight

Verdict: **RISK** pending rendered accessibility-size and iPad verification.
No top-level navigation change; review is optional from More or an edge alternative.

| Category | Status | Evidence / smallest remaining check |
| --- | --- | --- |
| Platform patterns | PASS | Native sheet, navigation, Done, scrolling and disclosure controls. |
| Clarity | PASS | Current/alternative labels, solid/dashed lines, one undoable selection. |
| Typography | RISK | Dynamic Type layouts implemented; inspect maximum size on both devices. |
| Accessibility | RISK | Semantic labels and 44-point actions; inspect large text and retain physical VoiceOver as open. |
| Interaction cost | PASS | Default confirmation unchanged; comparison is optional, with no extra confirmation prompt. |
| Design integrity | RISK | Verify raster landmarks and stale comparison/export rejection before acceptance. |

Top three checks: maximum text wrapping; raster/guide alignment; stale report exclusion.
Minimal fixes are confined to the review layout, renderer or snapshot guard if a check fails.
The first phone screenshot (`ui-v1-edge`) shows readable ratios, current/alternative
lines and recorded support/exclusions; the perspective panel is below the fold.

## Visual acceptance

- [x] Original image remains authoritative; the optional perspective view preserves independent lines.
- [x] Current and alternative edges are distinguished by labels and line pattern as well as color.
- [x] Recorded support/exclusion bands appear only on the reviewed side; missing evidence stays unknown.
- [x] Normal and maximum text wrap without clipped controls, horizontal scrolling or obscured actions.
- [x] iPhone and iPad pending, ambiguous, corrected, invalid and no-reference states are inspected.
- [x] Optional comparison has clear loading/unavailable states and native navigation/dismissal (source/test checks for error paths; actual dismissal exercised).
- [x] PNG keeps the original-photo result and readable reference/variation/sensitivity qualifications.
- [x] Final screenshots are captured and inspected after the last UI change.

## Behavior acceptance

- [x] Normal reference choice/confirmation adds no new step; direct side choice and Undo remain available.
- [x] Accessible numeric controls, 44-point actions and semantic labels remain usable (simulator scope).
- [x] Comparison ranges never appear before valid human review and do not upgrade detector certainty.
- [x] Edits/reset/rotation/new input invalidate comparisons, previews and old export snapshots.
- [x] Native Done/removal/locale and stale-share tests remain green.
- [x] Known landmarks verify raster rectification against the same outer-derived point transform.
- [x] Actual SwiftUI display agreement meets ≤1 device pixel and ≤0.5 point at 2×/3× scale, 240/362-point widths and three photo rotations (48 landmarks; worst 0.857242 pixels / 0.290788 points).
- [x] Ordinary More → Exact Values → Compare this edge opens the nested review; selection returns to Exact Values, Undo restores the original ratios and Done returns to the card.
- [x] Correction action count and simulator-observed timing are recorded with their scope.
- [x] Relevant final native tests and an optimized Release build pass (208 passed, one expected skip; arm64 simulator Release).

Physical VoiceOver/device interaction and capture-diverse accuracy remain separate
open gates unless actually exercised. Research refinement remains disabled.

## Rendered gate — final v5

Simulator verdict: **PASS** for platform patterns, clarity, typography,
interaction cost and design integrity. Accessibility: **RISK** for physical
VoiceOver/device behavior, which was not exercised; semantic labels, native
menus, scrolling and maximum-text actions pass the simulator check.

No remaining implementation issue was observed. The three remaining evidence
limits are physical VoiceOver, device performance and calibrated diverse-card
accuracy. Closing them requires their corresponding device/data work, not more
prompts in this flow. Initial copy and intrinsic-width issues were fixed before
`final-v5-*` captures. The iPad comparison is side by side at normal size;
maximum text stacks panels and wraps action labels without horizontal scrolling.

Actual phone correction: one selection tap after inspection (4.166 s tool wall
time, including automation/snapshot overhead), followed by More → Undo restoring
the original ratios. Pending correction on both devices leaves ratios hidden;
the existing reference choice then confirms both frames in one menu action.
The matched iPad corrected receipt records 53.6/46.4 LR, 50.0/50.0 TB and no
stale compared-candidate IDs. This is not human usability timing or physical truth.

Supplemental test-only verification: `Display-alignment-v1.xcresult`, 23 passed,
zero skipped/failed, exact inventory; ordinary phone entry evidence is in
`entry-path-audit`. Production source still matches the full regression/Release
snapshot. The supplemental manifest preserves the strengthened test separately.
