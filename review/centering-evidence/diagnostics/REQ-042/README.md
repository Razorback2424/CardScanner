# REQ-042 candidate recall ledger

Date: 2026-09-12
Device: iPhone 17 Pro, iOS 26.5
Simulator: `EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86`
Input: the original ten HEIC fixtures, not pre-downsampled renderer output

## Run

`CardCenteringInvariantTests/testREQ042CandidateRecallDiagnosticCoversAllFixtures`
passed in `27.617` test seconds. The signed result bundle is
`revision-e-req042-recall-retry-2026-09-12.xcresult` on the external SSD.
The test wrote [`candidate-ledger.json`](candidate-ledger.json) and the readable
[`candidate-ledger.md`](candidate-ledger.md).

## What the ledger contains

Each candidate records its family (`outer` or `inner`), side, proposing source,
working/native/normalized geometry, support, transition statistics where the
producer has them, a proposed semantic role, selection status, and rejection
reason. The ledger is DEBUG-only observational evidence; production selection
never reads it.

The all-fixture run emitted a ledger for every fixture. That ledger was captured
before E-REQ044 and its analyzer result was eight confident and two declined:
the five sleeved fixtures retained an inner source, IMG_0781 declined for
rectification, and IMG_0782 correctly returned `innerSource = none`. The later
E-REQ044 branch probe is nine confident and one declined, but it has not yet
produced a replacement candidate ledger; the retained ledger must not be read
as the current branch count.

## Preliminary geometric recall

The harness compares each candidate line's reported native points with the
corresponding rederived ground-truth edge. `bestErrorPx` is the maximum
perpendicular distance of those points from that GT edge. `anyWithinTolerance`
uses the existing GT edge-band tolerance. This is a diagnostic pre-recall
metric, not a semantic acceptance decision and not a production score.

| Family | Gradeable edges | Edges with a candidate within tolerance | Preliminary recall |
|---|---:|---:|---:|
| Outer | 40 | 34 | 85.0% |
| Inner | 36 | 29 | 80.6% |

The four IMG_0782 inner edges are intentionally excluded because the fixture's
ground truth has no gradeable inner reference. The current result is below
REQ-042's 95% target for both families. The ledger therefore does not authorize
selector tuning as if recall were solved.

## Interpretation

The candidate set is not empty: many edges have multiple scalar, Vision,
refinement, and profile proposals. At the same time, six outer and seven
gradeable inner edges have no proposal within the preliminary tolerance. The
inner misses are bottom edges on IMG_0348, IMG_0780, IMG_0781, and IMG_0783,
plus left edges on IMG_0347, IMG_0350, and IMG_0352. Since `bestErrorPx` is the
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
