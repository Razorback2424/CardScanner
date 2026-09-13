# After-evidence directory

This directory is reserved for durable post-implementation evidence. The
required simulator loop writes one uniquely named screenshot and one JSON
metadata file per fixture, including a declined case. A manually corrected case
will be retained separately once the guide fields can be exercised:

```text
screenshots/<FIXTURE>_CenteringExpanded.png
metadata/centering-<FIXTURE>.json
```

The harness records the pinned simulator, OS, screen scale, presented image
frame, confidence/decline state, detected quads, ground-truth screen mapping,
per-corner screen deltas, ratio deltas, and the screenshot dimensions. It is
implemented in [`scripts/centering_ui_build_and_shoot.sh`](../../../scripts/centering_ui_build_and_shoot.sh).

## Simulator status

The simulator is **available and the real-fixture capture route completed**.
All ten fixture routes produced uniquely named PNG/JSON pairs on the pinned
iPhone 17 Pro. That screenshot batch was captured **before the E-B branch repair**;
its automatic snapshot was three confident and seven declined. It remains valid
as historical screenshot evidence, but it is not the current analyzer state.
The historical default raw-HEIC E-A/E-B diagnostic was eight confident and two
declined. The latest branch matrix is in
[`../diagnostics/EA/summary.json`](../diagnostics/EA/summary.json). The retained
availability, full-suite result, and failure classification are in
[`simulator-status-2026-09-11.md`](simulator-status-2026-09-11.md).

The latest focused branch probe after E-REQ044 is nine confident and one
declined: only IMG_0782 declines for the missing-inner-reference safety case;
IMG_0781 reaches a confident state after the outer-guard/per-side-fallback
change. This is branch-availability evidence, not an accuracy result. The
complete post-change L1/invariant/E7 rerun remains pending.

The original post-REQ-027 E7 result bundle is a pre-E-REQ044 benchmark and keeps
IMG_0782 declined at all four tested maxima (1200/1600/2000/2400) in both
benchmark curves. The tracked `diagnostics/E7/resolution-curve.*` and
`low-detection-curve.*` files were subsequently rewritten during the
intermediate transition-width-guard run, before the final per-side fallback;
they are retained as that intermediate snapshot, not promoted as final
post-change accuracy evidence. Both snapshots confirm the no-inner safety
behavior in their tested modes, while broader supported-mode coverage remains
open.

No synthetic screenshots or placeholder measurements are stored here. The
numeric REQ-021 screenshot-pixel measurement, injected-offset sensitivity
check, and a screenshot after entering manual guide values remain explicitly
open in
[`../evidence-table.md`](../evidence-table.md).
