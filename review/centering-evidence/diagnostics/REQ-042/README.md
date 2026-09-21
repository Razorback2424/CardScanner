# REQ-042 candidate recall ledger

Date: 2026-09-12
Device: iPhone 17 Pro, iOS 26.5
Simulator: `EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86`
Input: the original ten HEIC fixtures, not pre-downsampled renderer output

## Post-remediation checkpoint — 2026-09-20

The diagnostic writers were redirected to simulator temporary storage, with the
optional `CENTERING_DIAGNOSTIC_OUTPUT_ROOT` override; reruns no longer write
generated JSON or Markdown into this tracked review directory. The focused run
passed 1/1 and measured 34/40 outer edges and 34/36 gradeable inner edges at the
unchanged tolerances. The registered Pokémon/Magic back-template candidates and
the `front.art_window.bottom_generator` alternatives are now present in the
ledger. All five development backs select the registered branch; the remaining
inner recall misses are IMG_0352 left and IMG_0780 right. The 95% recall gate
and end-to-end accuracy gate remain open.

The checked-in JSON and Markdown below remain the signed 2026-09-12
pre-remediation snapshot; the post-remediation output is intentionally not a
tracked evidence artifact.

## Signed 2026-09-12 baseline run

`CardCenteringInvariantTests/testREQ042CandidateRecallDiagnosticCoversAllFixtures`
passed in the signed post-E-REQ044 run on the pinned simulator. The focused
evidence-generation rerun completed in `27.6` test seconds; the full-suite run
also regenerated the checked-in files. The focused result bundle is
`revision-f-req042-inner-corrected-2026-09-12.xcresult` on the external SSD.
The test wrote [`candidate-ledger.json`](candidate-ledger.json) and the readable
[`candidate-ledger.md`](candidate-ledger.md) from the final per-side-fallback
branch, using the original HEIC inputs.

## What the ledger contains

Each candidate records its family (`outer` or `inner`), side, proposing source,
working/native/normalized geometry, support, transition statistics where the
producer has them, a proposed semantic role, selection status, and rejection
reason. The ledger is DEBUG-only observational evidence; production selection
never reads it.

The signed all-fixture baseline run emitted a ledger for every fixture after E-REQ044.
Its analyzer result is nine confident and one declined: IMG_0782 correctly
returns `innerSource = none`; the other nine retain an inner source. The
earlier eight-confident/two-declined run and its ledger remain historical.

## Historical geometric recall

The harness compares each candidate line's reported native points with the
corresponding rederived ground-truth edge. `bestErrorPx` is the maximum
perpendicular distance of those points from that GT edge. `anyWithinTolerance`
uses `τ_e` for outer edges and the fixed `0.0035 * H` contract for inner edges.
This is a diagnostic pre-recall metric, not a semantic acceptance decision and
not a production score.

| Family | Gradeable edges | Edges with a candidate within tolerance | Current recall |
|---|---:|---:|---:|
| Outer | 40 | 34 | 85.0% |
| Inner | 36 | 28 | 77.8% |

The four IMG_0782 inner edges are intentionally excluded because the fixture's
ground truth has no gradeable inner reference. The current result is below
REQ-042's 95% target for both families. The earlier 29/36 (80.6%) result used
the outer GT-band tolerance for inner edges and is preserved only as preliminary
historical evidence. The ledger therefore does not authorize selector tuning as
if recall were solved.

## Interpretation

The candidate set is not empty: many edges have multiple scalar, Vision,
refinement, and profile proposals. At the same time, six outer and eight
gradeable inner edges have no proposal within the current tolerance. The inner
misses are left edges on IMG_0347 and IMG_0352; bottom edges on IMG_0348,
IMG_0351, IMG_0780, IMG_0781, and IMG_0783; and the right edge on IMG_0780.
Since `bestErrorPx` is the
best candidate available rather than the selected candidate, these are
candidate-generation failures. This means the next work needs two explicitly
separate tracks:

1. name and repair the deficient edge/reference candidate generators; and
2. give candidates meaningful semantic roles and select card, sleeve, and
   reference geometry jointly.

Most inner proposals are still labeled `untyped_inner_reference` or
`unknown_inner_candidate`, and the final analyzer output in the later focused
E-A probe continues to report `art_window` for every non-`none` result. That
confirms the semantic branch is not implemented yet. No sampling-level
experiment was reopened based on this run.
