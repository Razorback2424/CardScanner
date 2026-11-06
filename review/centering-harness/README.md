# Centering harnesses

## Preparing a debug print reference

`build_print_reference.py` takes a full publisher image, its reviewed
`reference-only.json` specification, and a new output path. It verifies the
publisher image hash and stores the artwork rectangle, small contrast patches
and design identity. The output can be passed to the debug Centering screen
by its caller, or to the screenshot script via
`UI_CENTERING_PRINT_REFERENCE_SOURCE`. The FIN 289 test reference is in
[`PrintReferences`](../../TestFixtures/TradingCards/PrintReferences/fin-289.json).
Use `CenteringPrintPilotTests` for the source-photo accuracy and fallback checks.

## Native annotation angle audit

The historical `gt_tool.py rederive` procedure selects an edge-wide profile
offset and translates the seed line. It does not independently measure that
line's angle. Its schema validation and repeated profile agreement therefore
cannot establish physical boundary identity or angle accuracy.

`edge_annotation_audit.py` instead fits individually observed native transition
points, retaining rejected samples, source hashes and an original-image overlay.
It uses no detector output and produces **review candidates only**, never new
ground truth. Yellow is the seed, cyan the fitted line, green retained points,
and red rejected points. Unsupported edges remain explicit failures. Boundary
identity must be adjudicated before adopting a candidate; a narrow residual
does not prove that it follows the right transition.

```sh
python3 -B review/centering-harness/edge_annotation_audit.py \
  TestFixtures/TradingCards/HEIC/IMG_0783.HEIC \
  TestFixtures/TradingCards/GroundTruth/IMG_0783.gt.json \
  /Volumes/T7/CodexBuilds/centering-annotation-review/new-unique-run
python3 -B -m unittest discover -s review/centering-harness \
  -p test_edge_annotation_audit.py -v
```

Requires Pillow, numpy, scipy, OpenCV and pillow-heif for HEIC. Use
`--geometry innerQuad --polarity either` to inspect an existing inner reference;
the default falling transition audits dark card cuts on light backgrounds.
These are explicit review assumptions, not universal detector defaults. The
output directory must be new so prior evidence cannot be overwritten.

## Bounded native research evaluator

`CenteringNativeResearchTests` is linked only into the test target. Select that
suite with `xcodebuild test -only-testing:TradingCardScannerTests/CenteringNativeResearchTests`
using the repository's usual scheme, simulator and external-SSD build paths.
Its development ablation uses only the ten already-exposed historical fixtures;
it never reads the sealed supplementary holdout. The full 36-setting experiment
is intentionally slower than production and must not be used as a production
latency result.

The xcresult contains one JSON attachment per input and `development-metrics-v1`.
Export the attachments with `xcrun xcresulttool export attachments --path <result>
--output-path <external-artifact-directory>`, then run:

```sh
python3 review/centering-harness/native_research_report.py <external-artifact-directory>
```

The summary preserves every configuration, unavailable ratios, abstentions,
per-axis median/p95/worst errors, and face/encasement subgroups. Two-native-pixel
line agreement is an evaluator diagnostic against the existing annotations; it
is neither the two-percentage-point ratio gate nor proof of physical identity.
The JSON retains annotation bands and ambiguity, input hashes, signed encoded
sRGB signal definitions, Gaussian scales, source line hypotheses, rejected fits,
supported positions and leave-one-band-out diagnostics. Process resident memory
and its lifetime peak are explicitly labeled; a bounded crop does not establish
a bounded decoder peak. See the
[current implementation/evidence ledger](../../docs/audits/centering-guided-repair.md).

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

## REQ-050 numerical sensitivity

`run_sensitivity.sh` compiles the analyzer with `DEBUG` observability and runs a
recorded numerical-parameter perturbation grid over every image in the supplied
fixture directory. The production 1200-pixel working cap remains fixed. The
grid is injected through `CardCenteringAnalyzer.NumericalParameters`, so the
production defaults are not edited for the experiment.

```sh
./run_sensitivity.sh
```

The harness writes `numerical-sensitivity.json` and
`numerical-sensitivity.md` to `artifacts/centering-sensitivity/` by default.
The JSON records the exact grid and per-fixture LR/TB mean, population σ, and
range, plus confident/declined/error counts. These are numerical-sensitivity
measurements only; they do not establish edge identity or accuracy.
