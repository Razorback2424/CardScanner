# Card centering ground-truth schema

Each `<fixture>.gt.json` stores geometry in the native, EXIF-oriented pixel space.
The ten source HEIC files are 4032 × 3024 storage pixels with orientation 6 and
therefore expose a 3024 × 4032 oriented canvas to the app.

`cardOuterQuad` and `innerQuad` are ordered `[top-left, top-right, bottom-right,
bottom-left]`. They are intersections of fitted edge lines, not rounded-corner
pixel clicks. `encasementOuterQuad` is recorded separately when a sleeve is
visible. `edgeBands` are the measured 10–90% transition widths in pixels;
`ambiguousEdges` records exactly the edges whose band exceeds 1% of the card
height.

The checked-in records were re-derived on 2026-09-12 with the analyzer-free
dual-pass procedure required by REQ-001. Their current provenance method is
`analyzer_free_dual_profile_fit_with_visual_adjudication`; the two named
annotators, `generic_profile_pass_A` and `generic_profile_pass_B`, are
independent generic-image profile passes, not `CardCenteringAnalyzer` runs.
Each record retains the maximum pre-reconciliation `agreementPx`, and the full
profile diagnostics plus the reviewed transition choices are retained under
`review/centering-evidence/diagnostics/GT-rederived/`. The selection manifest
used for visual adjudication is beside those diagnostics.

For sleeved captures, a stable sleeve boundary is recorded separately. Where
the sleeve has no stable luminance transition, its reviewed virtual trace is
kept as encasement geometry and is not used to derive the card ratios. The
previous five-pixel-grid records remain recoverable under
`review/centering-evidence/ground-truth/provisional-2026-09-11/` and are not
the current ground truth.
