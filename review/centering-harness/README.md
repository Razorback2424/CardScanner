# Centering harnesses

`gt_tool.py` is the independent ground-truth tool. It contains no import of
the Swift analyzer and can validate the checked-in geometry or draw review
overlays from PNG/JPEG exports of the HEIC fixtures:

```sh
python3 review/centering-harness/gt_tool.py validate \
  TestFixtures/TradingCards/GroundTruth
python3 review/centering-harness/gt_tool.py overlay \
  /path/to/IMG_0347.jpg \
  TestFixtures/TradingCards/GroundTruth/IMG_0347.gt.json \
  review/centering-evidence/ground-truth/IMG_0347_gt.png
```

The overlay command uses the oriented image pixels and draws the physical-card
quad in red, the sleeve/encasement quad in amber, and the inner reference in
cyan. The JSON validator recomputes the rectified aspect and ratios directly
from the checked-in quads.

The review-only E4 probe can generate transition candidates without importing
the analyzer:

```sh
python3 review/centering-harness/gt_tool.py profile-candidates \
  <oriented-PNG-directory> \
  TestFixtures/TradingCards/GroundTruth \
  review/centering-evidence/diagnostics/E4
```

E4 candidates are not ground truth and must not be copied into the `*.gt.json`
records automatically. Multiple luminance transitions are possible on sleeve,
glare, and artwork edges; human adjudication is required before provenance can
be upgraded. The current records were produced later by the analyzer-free
`rederive` command, with a reviewed selection manifest and visual-silhouette
adjudication:

```sh
python3 review/centering-harness/gt_tool.py rederive \
  <oriented-PNG-directory> \
  <seed-ground-truth-directory> \
  <selection-manifest.json> \
  <output-directory> \
  --write-ground-truth
```

The current rederivation diagnostics and manifest are retained in
`review/centering-evidence/diagnostics/GT-rederived/`; the previous
five-pixel-grid records are archived under
`review/centering-evidence/ground-truth/provisional-2026-09-11/`.

## Baseline production harness (investigation only)

Reproduces the 2026-09-11 baseline in
`review/centering-evidence/baseline-2026-09-11/`. It compiles the **unmodified production
sources** `CardCenteringAnalyzer.swift` + `CardCenteringMeasurement.swift` for the iOS
simulator and runs them over `TestFixtures/TradingCards/HEIC`.

This is investigation tooling, not the evaluation harness the plan requires. The plan's
L1 harness must be an in-target XCTest that enters through the production API
(see REQ-004, REQ-025).

    ./run_meta.sh          # metamorphic sweep -> artifacts/centering-baseline/metamorphic.csv

`baseline_main.swift` produces `baseline.json` plus annotated PNGs; `meta_main.swift`
produces the metamorphic CSV. Both need a booted simulator (`xcrun simctl list devices`).

Note: `artifacts/` is gitignored. Copy anything durable into
`review/centering-evidence/` (REQ-023). E0 and the historical E1 records start
from a pre-downsampled 900x1200 render and remain diagnostic-only. E-C is the
named raw-HEIC/equalized replacement for the two E0 fixtures; it passes the
working-short-edge construction check and retains raw/equalized measurements,
but it is not an accuracy pass and does not replace the current rederived-GT
accuracy or final invariant gates.
