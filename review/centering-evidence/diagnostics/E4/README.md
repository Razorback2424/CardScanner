# E4 ground-truth profile candidates (historical candidate report, generated 2026-09-12)

These files are an analyzer-free review aid, not verified ground truth. They
were generated from the oriented PNG exports of the ten HEIC fixtures with:

```text
python3 review/centering-harness/gt_tool.py profile-candidates \
  <oriented-PNG-directory> TestFixtures/TradingCards/GroundTruth \
  review/centering-evidence/diagnostics/E4
```

For every edge, each JSON file contains two independent sampling passes using
240 and 257 along-edge positions, spanning 12–88% and 14–86% respectively.
Each pass records the full averaged normal profile, local transition
candidates, linearly interpolated 10–90 crossings, 50% crossing, band width,
five or more TLS-fit points, fitted edge line, virtual quad, aspect, and the
candidate ambiguity set implied by the selected transition. This is not the
final profile/reconciliation record used by REQ-027.

The provisional quad is used only as a starting seed. The report deliberately
does not rewrite the `*.gt.json` records because a difficult fixture can have
several real luminance transitions. In particular, IMG_0349's right edge
selects a transition about 63.8 px inward from the provisional edge in both
passes, while IMG_0348 has competing left-edge transitions and the two passes
do not agree. Those are review decisions, not detector targets.

`status` in every JSON file remains
`candidate_only_needs_human_adjudication` because these files are preserved as
the pre-adjudication candidate report. REQ-027 subsequently ran the separate
`rederive` command, applied the reviewed selection manifest, and promoted the
current records under `TestFixtures/TradingCards/GroundTruth/`. See
`../GT-rederived/` and `../../ground-truth-review.md`; do not treat this
historical candidate status as the status of the current records.
