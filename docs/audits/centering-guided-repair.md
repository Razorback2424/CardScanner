# Guided centering repair

## Exact printing and artwork placement — 2026-11-05

**The offline Starting Town control recovered all four artwork edges.** With the
normal detector's physical-cut proposal, the horizontal and vertical shares of
the visible margins differed from the photo review by 0.755 and 0.320 percentage
points. The largest distance from a measured line to any of 16 independently
marked native photo points was 1.08 pixels. The limits were four native pixels
at each point and two percentage points on each axis. These results apply to one
known English FIN 289 printing on an exposed development photo.
[Machine-readable receipt](../../review/centering-evidence/exact-print-control-2026-11-05.json)

The review began with the four unmarked, oriented HEIC originals. Visual traces
identified the physical cut and the printed feature. The existing native edge
audit sampled 61 positions per side in a fixed 16-pixel window around each
trace. Missing support ends the full numerical reading for that card in this pass.

| Photo | Supported cut / print sides | Measurement decision |
| --- | --- | --- |
| Pokémon back, IMG_0347 | 4 / 3 | The dark blue perimeter is visible. Its inner bottom lacks support for a single straight guide. |
| Charmander, IMG_0348 | 3 / 4 | All print-to-silver lines are supported. The silver physical bottom near the sleeve lacks straight-edge coverage. |
| Clefairy, IMG_0351 | 3 / 3 | The cut bottom and print top failed the fixed audit. The bowed printed perimeter requires an approximation. |
| Starting Town, IMG_0780 | 4 / 4 | The black footer merges with the cut. The gold-to-black rule around the illustration gives four corresponding boundaries in the photo and the publisher's image. |

For Starting Town, four additional cross sections per side identified the
illustration's **outer black rule against the surrounding gold strip**. The
results of scoring those manually read points and the sampled lines agreed
within 0.14 pp on each axis. The initial quarter-size visual trace agreed with
the native point review within 0.97 pp. One reviewer used multiple methods
on the same photo. These are provisional guides for a local experiment.

The reviewed top share was 19.84%, compared with 20.03% in the publisher's
displayed design. The illustration sits high on both. The useful measurement is
its placement relative to this design. Manufacturing trim and professional grade
require separate evidence. The reference was the publisher's exact card image,
whose name, collector number, language and illustration matched the capture.
[Publisher release notes](https://magic.wizards.com/en/news/feature/final-fantasy-release-notes)
and [FIN 289 image](https://media.wizards.com/2025/fin/d7HaGQos5Ezg/en_4388e7eeb0.webp).

Recognition used only features inside the publisher's illustration to locate
it in the photo. It then selected among the prior Swift probe's 34 real edge
candidates and measured the selected transitions in the native capture using
the existing research fitter. The prediction was saved before scoring against
the photo guides. There were 312 inlier matches across four quadrants. Known
translation and perspective controls had maximum corner errors of 0.01 and
0.12 working pixels, and the unrelated Pokémon back correctly abstained.

| Margin share | Independently reviewed | Selected using normal cut | Absolute error |
| --- | ---: | ---: | ---: |
| Left | 49.92% | 49.16% | 0.755 pp |
| Top | 19.84% | 20.16% | 0.320 pp |

Substituting only the reviewed cut reduced the errors to 0.127 and 0.030 pp.
The remaining discrepancy in this example comes mainly from physical-cut
placement. The experiment supplied the printing and a generic artwork-window
candidate pool. It establishes an offline selection result. Normal detector
accuracy has its separate historical receipt of 5/9 plus one correct abstention.
Reporting requires human confirmation. The four native audit tests passed and
all ten historical annotations validated. This pass changed research evidence
and documentation only.

The input images, cross sections, overlays, frozen inputs and prediction,
scripts, dependency versions and full score are on T7 under
`CodexBuilds/CardScanner-ReferenceReview-20261105/`. The receipt records their
hashes. The colored result overlay is `starting-town-recognized.png`.

## Controlled layout experiment — 2026-11-05

**Status: stopped at the first accuracy gate; no automatic routing promoted.**
The owner requested a bounded implementation of the proposed methodology and
an explicit stop when the expected improvement failed. A DEBUG-only probe now
supplies broad layout regions to the existing pixel fitter, separately from
normal analysis. It preserves the baseline physical-cut proposal, verifies the
capture hash, samples the original detector raster before presentation rotation,
and retains native candidates, profile curves, failures and comparison overlays.
It cannot replace the user's frames or enable reporting.

The two fixed plans are a perimeter printed frame (2–9% inward on each side)
and a landscape artwork window (left/right 4–12%, top 8–18%, bottom 36–50%).
Artwork side sampling covers the shared upper span, 20–48% down the card,
excluding the title and type banners. These are supplied design knowledge,
not automatic recognition, exact corners or ratio targets. The fitter's
thresholds, coherence rules and selection policy are unchanged.

Before the run, original-image review fixed broad native midpoint bands for
each intended side. These assess identity, not subpixel accuracy. They neither
replace the historical annotations nor certify centering ratios.

| Existing front | Baseline matching sides | Controlled matching sides | Outcome |
| --- | --- | --- | --- |
| IMG_0348 / Charmander | 4/4 | 4/4 | Already matched these coarse regions; maximum corner movement 0.30 native pixels. |
| IMG_0351 / Clefairy | 4/4 | 4/4 | Already matched; curvature remains, with up to 10.17 native pixels of corner movement. No precision improvement established. |
| IMG_0780 / Starting Town | 0/4 | 1/4 | Top reaches the reviewed region; sides still follow the surrounding frame and bottom includes the type banner. |

Starting Town's controlled side midpoints are x=257.30/2711.24 and bottom
y=2455.79, outside the predefined artwork bands x=335–375/2600–2670 and
y=2190–2250. Its candidate list **does contain transitions in all intended
regions**. For example, the bottom candidate at y=2219.92 is rejected as
`later_than_supported_frame_transition`. Broad layout windows fix search
reachability but do not fix selection between adjacent design elements. No
bands were narrowed after observing results, and no thresholds were swept.
All three comparison overlays were inspected.

`Layout-control-v1.xcresult` contains four methods: two pass (known artwork
windows at two positions and rejection of another capture's geometry), and two
fail (the new three-front acceptance gate and the existing historical accuracy
method). The synthetic windows are recovered within two pixels. Baseline
measurements before and after the probe are equal on all three fronts. All ten
normal-analysis records, including candidate evidence, exactly equal the saved
`front-curvature-final-attachments/initial-guide-accuracy.json`. The historical
accuracy result remains **5/9 passing both 2 pp limits, four failing, one correct
no-reference result**; the new control does not change that claim.

`Preservation-regression-v1.xcresult` passes **35/35 methods**, with no skips,
missing selections or duplicate methods. It covers the analyzer, independent
geometry/provenance, curved-border uncertainty after confirmation, candidate
evidence, five-repeat determinism on all ten images, optimized/reference
equivalence, no fixture-identity branches and latency. The timing upper median
is **0.627064 s**, maximum **0.801566 s**, within the unchanged 0.8/1.5 s limits.
The arm64 Release simulator build passes in `Release-build-v2.xcresult`,
verifying the non-DEBUG compilation path. Its first command failed before
compilation because of an unsupported command-line option; that log is retained
separately. Neither simulator verification nor coarse identity checks establish
physical-device or calibrated measurement acceptance.
Evidence is retained under `/Volumes/T7/CodexBuilds/CardScanner-BoundaryResolver-20261105/`;
the tested working tree is based on `0a11fc7`, with unrelated concurrent app
changes preserved. The experiment remains an explicit failing research gate,
not a new user-facing correction step. Automatic reporting stays disabled.
`layout-control-decision.json` records the fixed bands, baseline/probe checks,
candidate presence, exact baseline equality and source/annotation/artifact
hashes; the associated five-file source snapshot is retained alongside it.

## Bowed printed borders — 2026-11-05

**Status: incomplete; 5/9 historical references pass both unchanged 2 pp ratio
limits, with one correct no-reference result.** All 44 existing files remain in
scope; 34 remain unannotated/unscored. Automatic reporting remains disabled.

Original-pixel inspection identifies a concrete reason for Clefairy's incorrect
bottom guide: the visible printed boundary bows across the photo. The straight
consensus rejected this coherent boundary and fell back to an internal text bar.
The retained change checks a bounded quadratic only after straight fitting fails.
It requires at least 25/31 observed positions across all five spatial bins, stays
inside the existing local search window, and must explain the observations
substantially better than a straight line. No filename, reference coordinate or
desired centering ratio participates in detection.

The displayed guide remains a straight approximation fitted to the actual points.
Clefairy's bottom corners now lie at native y=3724.78/3708.50, instead of about
3555/3554 through text. Its 27 observed points retain a 6.00 native-pixel straight
fit residual. A warning explains the curvature, and detector confidence declines
the automatic reading. User confirmation does not erase that uncertainty.
This is better boundary selection, not an exact curved-boundary measurement.

| Changed fixture | Previous LR / TB error (pp) | Current LR / TB error (pp) |
| --- | --- | --- |
| IMG_0349 | 0.27 / 0.94 | 0.26 / 1.62 |
| IMG_0351 | 2.36 / 9.53 | 2.30 / 8.61 |

The other eight outputs are unchanged. Both final foil-card overlays were
inspected. The historical Clefairy bottom reference also sits above the visible
boundary; no annotation or tolerance was moved to follow the detector.

`Front-curvature-regression-v2.xcresult` on T7 contains **147 methods: 145 passed,
one expected opt-in skip, one failed accuracy method with six axis assertions**.
Exact inventory reconciliation has no missing, unexpected or duplicate methods.
The new bowed-border regression, analyzer, provenance, native interaction,
export, all-ten-image five-run determinism, optimized/reference equivalence,
no-fixture-identity branch check and corpus integrity pass. Production latency
upper median is **0.557495 s**, maximum **0.608998 s**, within unchanged limits.
The preceding regression-v1 attempt failed to compile due to an optional-chaining
typo in the new test; v2 corrects it. No new full metamorphic, Release, UI-rendering
or physical-device acceptance is claimed.

The unsuccessful `Front-strip-v1` and `Front-strip-v2` experiments are absent from
the retained source. Their exact prepared pixels helped expose curvature instead
of texture as the cause. Their artifacts, the first `Front-curvature-v1` result,
and the final source/evidence snapshot remain on T7.

Original-image review also corrected two manifest game labels: IMG_0797 is
Pokémon/Ferrothorn and IMG_0803 is Magic/Spinerock Tyrant. The manifest records
those corrections; all 44 image hashes and the sealed holdout split are unchanged.

## Front border coherence — 2026-11-05

**Historical checkpoint: incomplete; 5/9 historical references pass both unchanged 2 pp ratio
limits.** The no-reference card still abstains. The full scope remains all 44
available images; 34 are not yet annotated/scored. Automatic reporting is disabled.

The front profile now checks earlier peaks for spatially supported straight
edges before allowing a stronger internal banner to win. It fits observed local
positions using a deterministic consensus followed by least squares, retains
independent edge angles and records the supporting points. Unsigned Lab contrast
keeps unknown polarity instead of inventing a signed signal. The existing
amplitude fallback remains when no earlier candidate has sufficient support.

| Front fixture | Before LR / TB error (pp) | Current LR / TB error (pp) | Both axes ≤ 2 pp |
| --- | --- | --- | --- |
| IMG_0348 | 1.16 / 7.71 | 0.16 / 6.50 | Fail |
| IMG_0349 | 0.71 / 26.39 | 0.27 / 0.94 | Pass |
| IMG_0351 | 2.15 / 9.71 | 2.36 / 9.53 | Fail |
| IMG_0780 | 5.49 / 21.83 | 4.15 / 10.97 | Fail |

Back results are unchanged from the Magic checkpoint below. Inspected final
Zapdos and Clefairy overlays confirm that Zapdos now follows its thin outer
print boundary; Clefairy's bottom still follows an internal text feature.
Starting Town's proposed full frame still disagrees with the historical artwork
reference. No reference was changed to follow a detector output.

`Front-final-regression-v1.xcresult` on T7 has **144 methods: 142 passed, one
expected opt-in skip, one failed accuracy method (six axis assertions)**. It
covers analyzer, provenance, native interaction, export, latency, determinism
and the no-fixture-identity-branch source check. Method inventory reconciles
exactly. Production latency upper median is **0.522911 s**, maximum **0.599924 s**.
The subsequent `Front-determinism-reference-v1.xcresult` has **2/2 passes**:
the expanded determinism test now checks all ten images five times each, and
optimized/reference calculations match geometry and profile evidence exactly.
That follow-up changes only test scope, not production code. Full detector
metamorphic, Release and physical-device acceptance remain unclaimed.

`Front-coherence-v1`, `Front-regression-v1`, `Front-coherence-diagnostic` and
`Front-consensus-v1` retain intermediate results. The rejected
`Front-joint-line-v1` broader search regressed Zapdos/Clefairy LR and invented a
reference on IMG_0782. Its source and failed receipt remain separate; that
experiment is absent from the retained implementation.

Original-image review sheets now cover the 24 additional development files.
Independent native reference proposals exist for IMG_0798 and IMG_0800 (four
outer and four inner line candidates each), plus IMG_0810 (outer complete;
inner left unsupported). They use generic pixel-derived search windows and no
app output. They remain unscored review candidates. The review also identifies
two historical manifest category errors: IMG_0797 is Pokémon/Ferrothorn and
IMG_0803 is Magic/Spinerock Tyrant; those labels require reconciliation before
subgroup evaluation. The holdout remains sealed.

The original-pixel Charmander audit confirms the old bottom reference crosses
text. A separate provisional window yields a visible print/silver transition,
but widening the outer search also selects an interior print edge. These results
are retained under `front-reference-reconciliation`, not adopted as ground
truth. They reinforce that a supported straight line does not decide boundary
identity. Reference adjudication remains necessary alongside detector repairs.

## Magic borders and reference audit — 2026-11-05

**Status: incomplete.** The current goal covers all 44 files in the existing
manifest. All 44 file hashes were checked. The
[per-image inventory](../../review/centering-evidence/existing-corpus-status-2026-11-05.json)
records four historical ratio passes, five failures, one correct no-reference
result, and 34 unannotated/unscored images. The 24 additional development images
and ten sealed interim holdout images are not counted as passes. No new captures
are required for this work; automatic reporting remains disabled.

Classic Magic backs now select the first supported dark-to-light entrance into
the printed field. Opposite-direction cut transitions are excluded; the free
fit that mixed separate rules is omitted for this family. Candidates within the
sampling width of the first fitted boundary compete on existing evidence score.
This distinguishes a blurred entrance from stronger decorative rules farther
inside the artwork without preferring any centering ratio.

| Fixture | Previous LR / TB error (pp) | Current LR / TB error (pp) | Both axes ≤ 2 pp |
| --- | --- | --- | --- |
| IMG_0781 | 8.19 / 3.68 | 0.84 / 0.88 | Pass |
| IMG_0783 | 14.00 / 3.37 | 0.40 / 1.61 | Pass |

The other eight results are unchanged from the preceding table below. The
first Magic iteration passed IMG_0781 but left IMG_0783 TB at 3.14 pp; comparing
nearby fits of the same transition corrected that remaining choice. Both final
overlays were retained. **4/9 annotated references now pass both ratio limits**;
this is not full geometry acceptance or proof that the references are correct.

T7 `CodexBuilds/CardScanner-ExistingCards-20261105/Magic-regression-v1.xcresult`
contains **142 methods: 140 passed, one expected opt-in skip, one failed accuracy
method (seven axis assertions)**. Inventory reconciliation has no missing,
unexpected or duplicate methods. Analyzer, provenance, native interaction,
export and production latency checks pass. Latency upper median is **0.544637 s**,
maximum **0.621313 s**, within unchanged 0.8/1.5 s limits. No new Release,
physical-device or full invariant acceptance is claimed.

### Reference limitation exposed by the overlays

The historical `gt_tool.py` rederivation averages profiles along an entire
seed edge, selects one offset, then calls `shifted_edge_points`. Its fitted
points are generated from the translated seed, not individually observed edge
locations. Consequently it preserves the seed angle. Its two parameter passes
do not establish independently observed angles or independent human annotations.
The older REQ-027 completion record remains historical; it cannot certify these
angles. Visual review also finds suspect front reference identity: IMG_0348's
bottom line crosses printed text, and IMG_0780's top line crosses the title area.
These must be adjudicated before tuning the detector to reproduce them.

The separate [native annotation audit](../../review/centering-harness/edge_annotation_audit.py)
samples local strips, retains actual transition points and rejected observations,
and fits their independent line. It never imports the app, reads detector
outputs, overwrites annotations or promotes candidates to ground truth. Four
known-pixel tests pass: recovery of a sloped edge from a vertical seed,
interrupted support, polarity reversal, and rejection of flat/wrong-polarity
signals. Native source and annotation hashes accompany each retained audit.

`annotation-angle-audit-v1` contains ten outer audits: nine have four supported
line candidates; IMG_0348 bottom lacks sufficient straight-edge coverage.
`annotation-inner-audit-v1` retains nine reference audits including explicit
unsupported sides. The inspected IMG_0783 outer and IMG_0347 inner overlays
confirm visible angle disagreements with the historical seeds. These are
review candidates, not substitute accuracy evidence; a low fit residual does
not establish boundary identity. **All checked-in annotations and tolerances
remain unchanged.** The next work is reference adjudication alongside remaining
front boundary selection, followed by annotation/scoring of every available file.

## Existing-card accuracy first — 2026-11-05

**Status: incomplete.** The owner explicitly prioritized getting the existing
test cards right over expanding the corpus. REQ-040 remains a generalization
gate, but no longer blocks this authorized development work. The earlier
guided/UI passes establish editing and reporting behavior, not accurate initial
guides. Automatic reporting remains disabled and annotations are unchanged.

Added `testInitialGuidesMatchExistingDevelopmentAnnotations`: it calls the normal
production entry point, compares untouched proposals with the existing annotated
quads using the current rectified headline convention, requires both axes within
the unchanged 2 pp limit, and verifies that the no-reference fixture remains
without an inner frame. It never inserts annotated geometry into the result.
Per-card native coordinates, candidates and actual overlays are retained.

The first correction is confined to identified classic Pokémon backs. Signed
dark-to-light brightness evidence rejects the opposite artwork transition that
the unsigned RGB distance rewarded. Candidate scoring also accounts for the
actual straight-line fit residual, reducing mixed-transition fits. Both changes
use image evidence rather than filenames, hashes, annotated coordinates or
preferred ratios. Magic registration keeps its original scoring: applying the
same residual weighting there regressed a fixture and was rejected.

| Existing fixture | Previous LR / TB error (pp) | Current LR / TB error (pp) | Current 2 pp ratio gate |
| --- | --- | --- | --- |
| IMG_0347 | 10.72 / 0.10 | 3.20 / 1.00 | Fail |
| IMG_0348 | 1.16 / 7.71 | 1.16 / 7.71 | Fail |
| IMG_0349 | 0.71 / 26.39 | 0.71 / 26.39 | Fail |
| IMG_0350 | 24.90 / 4.61 | 0.89 / 0.45 | Pass |
| IMG_0351 | 2.15 / 9.71 | 2.15 / 9.71 | Fail |
| IMG_0352 | 14.12 / 2.16 | 0.94 / 1.51 | Pass |
| IMG_0780 | 5.49 / 21.83 | 5.49 / 21.83 | Fail |
| IMG_0781 | 8.19 / 3.68 | 8.19 / 3.68 | Fail |
| IMG_0782 | No reference | No reference | Correct abstention |
| IMG_0783 | 14.00 / 3.37 | 14.00 / 3.37 | Fail |

At this first checkpoint, **2/9 annotated references** met both ratio limits; previously
none did. This is improvement, not perfection or full acceptance. The remaining
work includes the third Pokémon back, both Magic backs, front boundary identity
and physical-outline placement. Starting Town's existing annotation uses an
artwork window, so the requested default reference (full printed frame versus
artwork window) is being clarified before changing that contract. No annotation
was moved to follow a detector result.

T7 `CodexBuilds/CardScanner-ExistingCards-20261105/Focused-regression-v1.xcresult`
contains **141 selected methods: 139 passed, one expected opt-in native V2b
benchmark skip, one failed accuracy method (11 failing axis assertions)**.
Inventory reconciliation has no missing, unexpected or duplicate methods.
The analyzer, native interaction, boundary provenance and export regressions
pass. The three final Pokémon overlays were inspected; the persistent right
edge disagreement on IMG_0347 remains visible. This run does not include a new
Release build, full invariant suite or physical-device acceptance.

The separate production latency selector passes in `Production-latency.xcresult`:
upper median **0.553710 s**, maximum **1.019690 s**, within the unchanged
0.8/1.5 s limits. The maximum is the first fixture in that fresh test process.

`Baseline.xcresult` retains the initial harness compile failure, corrected before
`Baseline-v2.xcresult`. That diagnostic first used unrectified normal distances;
the retained final test uses the app's rectified headline convention. The
previous column above comes from the unchanged November 4 production-path
research receipt, which uses that same convention. `Signed-back-v1.xcresult`
and `Coherent-back-v1.xcresult` retain intermediate outcomes, including the
rejected Magic regression. The final source snapshot and evidence manifest
distinguish this change from the earlier guided implementation.

## Optional review and qualified reports — 2026-11-04

**Status:** slice 5 implemented and simulator-tested; the final ten-suite selection
has 208 passes, one expected skip and zero failures. This is guided
implementation evidence, not automatic detection or physical accuracy acceptance.

The optional **Compare Perspective…** action preserves the original overlay
and presents a display-only, outer-derived perspective view. Independent inner
lines use the same point transform. The bounded renderer works from the existing
presentation image, caps each output at 1,200 pixels per dimension, renders off
the main actor and rejects cancelled/stale jobs. No corrected raster is saved
or used to measure ratios. The default PNG remains the original-photo result.

Each retained alternative also offers **Compare this edge** beside the existing
direct choice. Its sheet labels solid/current and dashed/alternative lines,
shows an enlarged native crop and both-axis scenario results after valid review,
and provides one undoable **Use This Edge** action. Pending review permits
inspection and selection but hides all ratios. Recorded sample/exclusion bands
appear only for that alternative; an excluded interpretation without a recorded
spatial band is never invented as an image mask. Synthetic UI bands are explicitly
labeled fixtures and do not establish detector image support.

Common-axis variation replaces the older endpoint-interpolated *detail*, while
the headline method remains unchanged. Optional variation stays in a disclosure.
Reports distinguish the selected reference, human review, spatial variation and
an explicitly inspected boundary-choice range. Other uncertainty stays unknown;
the range is explicitly not an accuracy interval. Input, geometry, mapping,
reference, review state and photo rotation bind comparisons and snapshots.
Editing, Undo/reset, rotation or replacement input retires the comparison and
old report. No new confirmation, entitlement, scanner, persistence or grade flow
is introduced; the prior §14 amendment is the scope authority.

### Rendered and interaction evidence

T7 `CodexBuilds/CardScanner-CenteringSlice5-20261104/final-v5-*` retains actual
screenshots, matched PNGs and geometry receipts. Inspected iPhone 17 Pro and iPad
Air 11-inch (M4), iOS 27.0, at normal and maximum accessibility text sizes:
pending, invalid, no-reference and ambiguous states; independent-line perspective
comparison; and actual corrected/confirmed states. The final iPad uses side-by-side
panels when they fit; maximum text and narrow screens stack them. No horizontal
scrolling or clipped action labels was observed. Content can extend vertically
and uses native scrolling. Native Done, reference menus and single-side selection
remain available. Initial screenshots exposed overly dominant introductory copy
and an intrinsic-width fallback that stacked the iPad panels; the final captures
follow the layout and copy corrections.

Actual maximum-text **Use This Edge** changes LR from 50.0/50.0 to 53.6/46.4,
with TB unchanged. More → Undo restores 50.0/50.0. That choice is one tap after
inspection; the recorded tool call took 4.166 s including automation and snapshot
settling, **not** human correction time or measured app latency. A separate pending
choice on each device keeps ratios hidden, then the existing reference menu's
Printed border action confirms them without an added prompt. The matched iPad
receipt shows the corrected geometry, user-confirmed state and cleared comparison.
The PNG comparison receipt states its 50.0–53.6% left-share assumption and unknown
accuracy. These are synthetic UI checks, not calibrated card measurements.

The [slice 5 checklist](../../references/centering_boundary_slice5_checklist.md)
records the design gate. Simulator layout/interaction checks pass; physical
VoiceOver, device performance and capture-diverse accuracy remain open. Loading
and unavailable views have explicit source paths; cancellation, invalid rendering
and stale publication are covered by native tests, not forced screenshot states.

### Verification and retained limits

`Review-v1.xcresult` retains a test-fixture initializer-label build failure;
the corrected `Review-v2.xcresult` has **9 passed, zero failed**, with no missing,
unexpected or duplicate methods. Tests exercise actual raster landmarks against
the outer point transform at 0°, −7° and 12° photo rotation (1.5 output-pixel
centroid tolerance), bounded raster dimensions, cancellation, invalid geometry,
selected-side-only support/exclusion rendering, legacy exclusion decoding,
pending selection/Undo and rejection of stale comparison/report provenance.

The finalized `Final-centering.xcresult` executes **209 methods: 208 passed,
one expected opt-in V2b performance skip, zero failed**. The ten suites cover
boundary evidence, native precision/input interaction, exports, analyzer,
ground-truth guided safety, invariants, view surfaces, spatial measurement,
review and native research. Inventory reconciliation finds no missing,
unexpected or duplicate methods. Production REQ-022 upper median is **0.502201 s**,
maximum **0.555615 s**, within the unchanged 0.8/1.5 s limits.

The final optimized **arm64 Release simulator build passes** with Xcode 27.1
(27A9275), standard Release conditions and signing disabled for simulator build
verification. Debug UI captures use the local-only signing/Collector Tools harness.
Source snapshots, Debug/test/Release binary hashes, input/capture hashes, method
receipts and logs are retained in `source-and-evidence-manifest.json` on T7.
This is not an archive, physical-device, CloudKit or release-readiness claim.

The final 36-configuration research accuracy summaries exactly match slice 3;
its failed accuracy exit is unchanged. Research upper-median time is 15.623557 s,
maximum 16.294320 s per development image. This combined test-host process's
lifetime peak is 2,364,850,176 bytes after the earlier invariant tests; it is
neither an isolated decoder peak nor a production memory guarantee. Raw
attachments and summaries remain on the external SSD.

Production refinement and automatic reporting remain disabled. Slice 3's
identity/accuracy exit still failed; no new diverse capture set is available,
as confirmed by the user. REQ-040, independent annotations, calibrated physical
measurements, device checks and the broader acceptance contract remain open.

### Supplemental display and ordinary-entry verification

The follow-up changes only the review test, strengthening its existing landmark
check at the actual SwiftUI display surface. Four landmarks across 0°, −7° and
12° rotation, 240/362-point panel widths and 2×/3× display scale give 48 checks.
Worst Euclidean disagreement is **0.857242 device pixels**; worst point error is
**0.290788 points**. Both unchanged limits (one device pixel and half a point)
pass. This validates synthetic display alignment, not physical edge identity.

`Display-alignment-v1.xcresult` has **23 passed, zero skipped/failed**, covering
all nine review tests, all thirteen spatial tests and the non-square native
detail alignment regression. The finalized receipt has no missing, unexpected
or duplicate methods. The earlier 209-method receipt and Release build remain
separate evidence for the unchanged production source; they were not rerun for
this test-only addition. `supplemental-verification-manifest.json` retains the
new test snapshot, hashes, receipt and UI evidence without replacing the prior
source manifest.

The ordinary phone flow also passes with the direct DEBUG review route disabled:
More → Compare Perspective → Done; More → Exact Values → Precision adjustments
→ Other detected edges → Compare this edge. **Use This Edge** dismisses the nested
review back to Exact Values and changes LR from 50.0/50.0 to 53.6/46.4, with TB
unchanged. **Undo adjustment** restores 50.0/50.0, and Done returns to the card.
`entry-path-audit` retains inspected screenshots and action snapshots. The input
is the synthetic comparison fixture, so this checks navigation and interaction
rather than capture accuracy. No production code or automatic gate changed.

## Spatial measurement and explicit sensitivity — 2026-11-04

**Status:** slice 4 model implemented and simulator-tested; slice 5 presentation
is recorded above. The prespecified `common_axis_samples_v1` contract is recorded in the
[authoritative plan](../../review/opus-card-centering-implementation-plan.md).
The headline remains `rectified_endpoint_average_v1`; no detector, confidence,
validity tolerance or automatic-reporting gate changes.

The new spatial model derives one homography from the current selected cut and
applies it to the independent inner lines. LR pairs intersect the same row, TB
pairs the same column, at 10/30/50/70/90% of the rectified card span. Samples
outside either selected inner segment or with nonpositive/nonfinite margins are
unavailable. The model retains positional ratios, margin ranges, midpoint,
median, side tilt and geometric sample coverage. Image-observation coverage and
native fit residual remain separate and unknown unless evidence still matches
the current line. It never normalizes the inner reference independently or
forces standard aspect to repair an estimate.

Actual forward/inverse compositions are checked at 25 interior positions in
both directions. They establish numerical consistency only. Explicit candidate
comparisons replace one supporting line per scenario, rebuild the cut transform
where needed, and recompute both axes. Invalid/missing alternatives retain their
rejection; no Cartesian product silently combines incompatible edges. Optional
caller-specified native-normal perturbations have a separate range. Neither
range is a confidence interval, and uncertainty outside the stated alternatives
stays unknown. All derived values are computed from current input identity,
quads, mapping, reference and review state; manual edits retire unmatched
observation provenance while immutable proposal evidence remains intact.

Thirteen new analytical tests cover centered/translated and unequal-slope
geometry, thin subpixel borders, absent/crossed/nonpositive margins, missing
sample positions, unequal scale, perspective, rotation, EXIF 1–8/mirrors,
interior round trips, cut/shadow alternatives 4–5 native pixels apart,
independent perturbations, stale evidence, Undo, photo rotation and input
replacement. The angled shadow scenario changes the full homography and both
ratios while preserving the other seven supporting lines.

`Final-centering.xcresult` on T7 at `CodexBuilds/CardScanner-CenteringSlice4-20261104`
reports **192 passed, one expected opt-in V2b performance skip, zero failed**
across 193 methods in eight selected suites. The finalized inventory has no
missing, unexpected or duplicate methods. REQ-022 upper median is **0.498864 s**,
maximum **0.544352 s**. Source snapshots and source/binary/inventory hashes are
retained before slice 5 edits. No new UI or physical-device acceptance is claimed.

Two initial builds exceeded Swift's expression type-checking limit; the
arithmetic was split without changing values. The first runtime run had 11
passes and one failed assertion comparing an immutable proposal to a subsequent
floating-point line intersection. The assertion now checks the original
proposal itself; no numeric tolerance was widened. Only that completed run's
optional `simctl diagnose` collector was stopped to finalize its failed receipt.

## Bounded native research evaluation — 2026-11-04

**Status:** slice 3 evaluator implemented and tested; accuracy exit **not met**.
No refinement setting is promoted. Working tree remains based on `main@a404f67`.
The user confirmed that no additional capture-diverse set is currently available;
REQ-040 and independent physical calibration remain open. The sealed interim
holdout was not read. Independent guided measurement work in slices 4–5 can
continue without changing production perception or weakening this gate.

`CenteringNativeResearchTests` contains the evaluator and revision-keyed,
cancellable single-request cache in the test target only. Production retains
the 1200-pixel proposal path and disabled native-refinement defaults. The shared
crop helper accepts an explicit color space for research; ordinary callers keep
their existing DeviceRGB default. Research uses encoded sRGB values, explicitly
distinguishing weighted brightness, arithmetic mean, chroma, red-minus-green and
blue-minus-green from linear-light luminance. The 36 recorded configurations
cover signed gradients at Gaussian sigma 0.6/1/1.5/2/3, the attachment's six
RGB-mean crossings, and five sigma-1 chroma crossings. These are correlated
experiments, not independent votes or calibrated production thresholds.

Work is capped at seven existing seeds per side, 56 total, with bounded crops,
25 positions in the middle 12–88% of each seed, retained competing tracks,
residual rejection, spatial coverage, omitted-band variation and held-out-band
residuals. Invalid seeds, missing samples, unsupported fits and invalid joint
intersections remain explicit abstentions. Research never replaces outer cuts
using gradient strength. Each input attachment retains its byte hash, settings,
native hypotheses and per-stage process-memory observations. One current key
includes original bytes, input/geometry revisions, seed geometry and settings;
replacement cancels stale work and completed requests are reused.

### Outcome and decision

The full experiment ran on all ten exposed development images: nine with
annotated inner references (36 sides) and one unavailable reference. Across
configurations, coarse candidate agreement was 2/36 sides within two native
pixels; refined candidate agreement ranged from 0/36 to 8/36. Of 141 experimental
unique-line selections across the correlated configurations, 139 exceeded that
two-pixel line-agreement diagnostic; the largest discrepancy was 1,191.12 native
pixels. These counts are not independent trials, and the diagnostic is neither
the two-percentage-point ratio gate nor independently calibrated physical truth.
Existing annotation ambiguity and bands remain in the records.

Raw proposal LR error had upper median 8.1897 pp and worst/p95 24.9040 pp; TB had
upper median 4.6061 pp and worst/p95 26.3889 pp, over the nine measurable images.
Some settings improved aggregate ratios while selecting the wrong boundary;
others worsened them. Therefore no setting satisfies the identity/accuracy exit.
The next perception investigation must address role-correct candidate generation
and annotation quality, rather than relax local-fit gates or select a favorable
ratio. These raw-proposal errors are not errors in user-corrected measurements;
all production proposals still require deliberate review.

The complete 36-setting research pass took upper median **15.985 s**, maximum
**17.054 s** per input. It is an offline ablation and is not added to interaction
work. Process-lifetime resident peaks during that pass ranged from 678.9 to
721.7 MB; they include the test host and earlier allocations. The separate
real-flow native-detail check took 5.245 ms cold and 0.0069 ms cached on one
simulator fixture. Neither that observation nor the two-million-pixel crop cap
establishes a bounded decoder peak or physical-device interaction acceptance.

### Verification

Evidence is retained on T7 at `CodexBuilds/CardScanner-CenteringSlice3-20261104`.
`Final-research-and-regression.xcresult` reports **92 passed, one expected opt-in
V2b performance skip, zero failed**, across 93 selected methods. The seven new
research methods, 48 native-precision methods, 24 analyzer methods, 13
ground-truth methods and production latency method have no missing, unexpected
or duplicate inventory entries. REQ-022 upper median is **0.532916 s**, maximum
**0.585268 s**, within unchanged 0.8/1.5 s limits.

The initial research run retains three passes and two failed methods: a partial
coverage fixture could not generate the assumed hypothesis, and competing edges
produced more than two line hypotheses. The corrected fixtures assert sufficient
coverage and preservation of both real transitions/ambiguity without an arbitrary
hypothesis count. The next six-method run passed. A final seventh regression
verifies supersession and explicit invalid-seed abstention. No acceptance
threshold was relaxed to obtain a pass. The
[harness instructions](../../review/centering-harness/README.md#bounded-native-research-evaluator)
and summary script make the experiment repeatable; full per-input, per-side and
per-configuration records are retained, including face/encasement subgroups.

## Reference identity and competing boundaries — 2026-11-04

**Status:** second slice implemented and verified locally.
Working tree remains based on `main@a404f67`, with unrelated user changes retained.
This implements slice 2 of the [boundary evidence plan](../plans/centering-boundary-evidence-plan.md).
Automatic ratios and sharing still require valid geometry and human review.

The analyzer retains candidates from its existing scalar, Vision, profile,
outer-refinement and registered-back stages before final frame assembly. Each
candidate has an original-oriented-native line, proposing source, possible
roles and a selection/rejection reason. Existing observed outer-fit samples,
coverage, signed inside/outside luminance polarity and native fit residuals are
retained where available; unsupported fields stay nil. A rejected stage proposal
is not proof of physical identity. No new detector, threshold, native-refinement
default or favorable-ratio selector was introduced. Candidate IDs are stable
within a repeated analysis; scalar border-walk records now use explicit side order.

The input record binds exact received bytes by SHA-256 and byte count, with raw
raster dimensions, EXIF orientation, available source color-space name, and named
detector/presentation mappings. Prior processing history stays unknown. Candidate
geometry remains in original-oriented-native coordinates; current working guide
quads are canonical and legacy scalar fields are derived projections. Only the
outer quad supplies perspective correction. No inner-reference normalization is
introduced.

Reference definitions distinguish the existing versioned Pokémon/Magic classic
back paths from unverified designs. The historical `artWindow` detector tag is
retained for diagnostic compatibility; it cannot authorize measurement. For an
unverified design, **Choose Reference** identifies a printed border, artwork
frame or other reference and confirms the reviewed guides in the same action.
There is no separate confirmation dialog. **No usable reference** keeps ratios
and sharing unavailable. An added default inset remains an unverified placement
aid. User-selected results and PNGs identify a geometric estimate; artwork
asymmetry may be intentional and the choice does not establish grading equivalence.

Exact Values includes alternative edges beside native detail. It shows six
nearest distinct supporting lines first, with all retained alternatives available.
Ordering uses distance from the current guide, never proximity to 50/50. A choice
changes one supporting line and its intersections, preserving the other seven
supporting lines. Undo/reset restore geometry and provenance together; subsequent
manual changes cannot retain a stale candidate attribution. Reviewing one side
does not approve the remaining frames or change detector certainty.

Evidence is retained on T7 at `CodexBuilds/CardScanner-CenteringSlice2-20261104`.
The [slice checklist](../../references/centering_boundary_slice2_checklist.md)
tracks rendered normal/maximum-text review and native verification. Analytic
cut/shadow and printed-border/artwork line fixtures test evidence retention and
side replacement; they do not establish detector recall on the missing historical
Gengar/Mew images. Ten existing development photographs exercise real candidate
retention, input provenance and unchanged geometry. The sealed holdout is untouched.

Initial boundary tests passed 4/4. The first broad run retained its original
receipt: 175 passed, three failed methods, one expected opt-in skip (179 total).
One failure expected obsolete confirmation copy; two exposed nondeterministic
dictionary ordering in the newly retained candidate records. The ordering is
fixed, and test expectations now require explicit reference choice. A fifth
boundary test for photo-rotation mapping was added after that run. All test
processes finished; only optional `simctl diagnose` collection was terminated
when it delayed finalizing the original failed bundle.

### Final verification

Xcode 27.1, dedicated iPhone 17 Pro / iOS 27.0 Simulator. Finalized xcresult
inventories, source/binary hashes, development-input hashes and captures are
retained in `source-and-evidence-manifest.json` on T7.

| Run | Passed | Failed methods | Skipped |
| --- | ---: | ---: | ---: |
| Boundary model, `Boundary-v1` | 4 | 0 | 0 |
| Initial broad selection, `Centering-v2` | 175 | 3 | 1 |
| Seven suites after evidence fixes, `Centering-v3` | 179 | 0 | 1 |
| Six core suites + Square + latency after UI repair, `Final-focused` | 147 | 0 | 1 |
| Boundary + export after DEBUG receipt correction, `Final-receipt` | 55 | 0 | 0 |

The three final passing inventories have no missing, duplicate or unexpected
methods. Their combined latest-method coverage is 179 passed / one expected
opt-in native-V2b performance skip across 180 methods; this is combined evidence,
not one full-final-binary run. Only the view changed after the broad pass:
presentation repair first, then a DEBUG-only receipt correction. The final
REQ-022 upper median is **0.506341 s**, maximum **0.557617 s**, within unchanged
0.8/1.5 s limits. Optimized non-DEBUG Release builds passed for the production
changes, including the final layout. The subsequent receipt correction is
excluded from Release. No physical-device or release-readiness claim follows.

Normal and maximum-text reference choice, no-reference abstention, native-detail
alternatives, actual side choice and Undo, independent geometry, and PNG labels
pass visual inspection. The first capture exposed a truncated primary action;
the final layout gives it a separate row and wraps the estimate caveat. An actual
choice moved the inner-left line and changed the synthetic ratio from 50.0/50.0
to 49.4/50.6; the matched export receipt proves the other seven supporting lines,
all candidates and detector confidence stayed fixed. Actual Undo restored all
eight lines, reference and review state exactly. A stale DEBUG analysis marker
found during this check is preserved as such; export receipts now refresh from
the matched snapshot and identify synthetic/user-adjusted geometry. These are
analysis/export snapshots, not a continuous gesture log.

### Design gate

Reviewed against Apple's [menu guidance](https://developer.apple.com/design/human-interface-guidelines/menus)
and [accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility).

| Category | Status | Evidence / minimal remaining check |
| --- | --- | --- |
| Platform patterns | PASS | Native menus, disclosure groups and undo; top-level navigation unchanged. |
| Clarity | PASS | Explicit reference action, geometric-estimate label, and no-reference path. |
| Typography | PASS | Final standard and maximum-text captures wrap without truncating the primary action. |
| Accessibility | RISK | Largest text and semantic controls inspected; physical VoiceOver traversal remains unverified. |
| Interaction cost | PASS | An unsupported reference adds the necessary menu choice in place of Confirm, with no second confirmation dialog; alternatives remain optional. |
| Design claims | PASS | Review does not upgrade certainty or imply a grade; original image and independent guides remain visible. |

**Verdict: RISK** solely for the remaining physical-device/VoiceOver check.
The minimal remaining check is real-device traversal of reference selection,
alternative choice and Undo. No additional production UI change is identified
by this simulator receipt. Accuracy calibration, held-out perception, common-row
ratio sampling and native-refinement promotion remain later work.

## Independent inner geometry and human review — 2026-11-04

**Status:** implemented locally on `main`, base `a404f67470db20352b9b8f79925e2b96fe0597a9`;
uncommitted and preserving unrelated working-tree changes. This is the authorized
first slice of the [boundary evidence plan](../plans/centering-boundary-evidence-plan.md).
Simulator evidence is scoped below; no release acceptance or new automatic
boundary-accuracy claim follows from this change.

The analyzer now returns its independent inner lines without squaring them.
Original proposal quads and detector confidence are immutable within a
measurement; `reviewState` separately records pending or user-confirmed review.
Every new measurement starts pending, so even high detector confidence cannot
expose ratios or enable sharing. Confirming valid frames leaves the detector's
scores, decline reason and original geometry unchanged. Historical diagnostic
confidence states remain decodable; there is no persisted-measurement migration.

The existing one-action confirmation remains. Valid edits stay live; invalid
geometry, replacement input and photo-only rotation revoke approval. Explicit
Square and Undo retain exact snapshots, while a small-angle detent cannot flatten
independently sloped edges. The screen and PNG describe human review and show
endpoint-based positional variation even when opposing slopes cancel the mean
tilt. The headline ratio method is unchanged; DEBUG receipts label it
`rectified_endpoint_average_v1`. Variation is not an accuracy interval.

Detector thresholds, native refinement defaults, geometry validity rules and
the 0.8 s upper-median / 1.5 s maximum latency limits are unchanged. Native
refinement remains DEBUG opt-in. Boundary-identity types, competing-candidate
review, a full native input-provenance record and common-row/column diagnostics
remain later slices.

Evidence is retained on T7 at `CodexBuilds/CardScanner-CenteringSlice1-20261104`.
The [visual/behavior checklist](../../references/centering_boundary_slice1_checklist.md)
records the screenshot loop and its accessibility limitations. No private images
or raw logs are added to the repository.

### Native test receipt

Xcode 27.1, dedicated iPhone 17 Pro / iOS 27.0 Simulator, standard Debug with
automatic reporting disabled. Finalized `.xcresult` method inventories were
extracted with `xcresulttool get object --legacy`; stdout alone was not used
as acceptance evidence.

| Run | Passed | Failed methods | Skipped |
| --- | ---: | ---: | ---: |
| Unchanged centering baseline, three suites | 118 | 0 | 1 |
| First implementation selection, `Focused-v1` | 136 | 4 | 1 |
| Broad six-suite selection, `Final-centering` | 173 | 1 | 1 |
| Core five suites plus explicit Square and latency, `Final-focused` | 142 | 0 | 1 |
| Same selection after final accessibility repair, `Final-verified` | 142 | 0 | 1 |

The first four failures were test-fixture assumptions: an out-of-image small
frame, a sheared quad outside its canvas, confirmation of zero-width borders,
and the previous export-note height. Fixtures now supply valid bounds or
explicitly stay unconfirmed, and the note-height test checks wrapping of long
warnings. Geometry validity rules were not relaxed. The broad failure was one
obsolete automatic-parallelization test with nine assertions; it now explicitly
invokes Square and verifies pending review plus retained original geometry.
Its amended version passes in both final focused runs. All 143 final selected methods
are present exactly once, with no missing/unexpected methods. The sole skip is
the existing opt-in native V2b development-performance benchmark.

The broad run's optional `simctl diagnose` collection lingered after test
execution. Only that collection process was terminated; Xcode finalized the
bundle with its original one-method failure intact. No test process was stopped
or rerun to conceal a crash. Both final passing runs exited normally. The combined
latest-result inventory covers all 175 current methods in the six relevant
suites: 174 passed and the one expected skip, with no missing methods. This
combines the broad unchanged geometry checks with the final focused run; it
is not one all-suite run of the final binary.

Coverage includes the ten-development-photo geometry replay, opposing slopes,
unaltered detector evidence, independent cyan export pixels, explicit review,
live valid editing, invalid/rotation/new-input revocation, exact undo/reset,
stale exports, coordinate/render invariants and native Done/removal/localized
editing. The final REQ-022 run has upper median **0.519570 s**, maximum
**0.570662 s** under the unchanged 0.8/1.5 s limits. These are simulator timings.
No sealed holdout was evaluated and no physical measurement accuracy is claimed.

### Visual and interaction receipt

The screenshot build uses the same centering source with the existing
`DEBUG LOCAL_ONLY_SIGNING LOCAL_COLLECTOR_TOOLS` flags, in separate
`UIDerivedData`. The ordinary unowned build correctly stopped at the purchase
gate. An initial local capture build omitted `LOCAL_ONLY_SIGNING` and trapped in
CloudKit account initialization; the corrected local configuration launched
without a production-code change. This is not StoreKit or CloudKit acceptance.

The final normal-size view and PNG retain the independent cyan lines, show
40.4/59.6 LR and 54.0/46.0 TB for the synthetic opposing-slope case, and expose
top-to-bottom/left-to-right variation. The raw detector state remains `declined`
in both pending and user-confirmed markers. The final PNG is byte-identical to
the visually inspected export. Source hashes, binary hashes, ten development
input hashes and method reconciliation are retained in
`source-and-evidence-manifest.json` beside the result bundles.

Maximum Dynamic Type initially clipped readings and allowed an oversized overlay
to hide the image. A first scroll-container attempt revealed a real gesture
collision: a swipe beginning on the image moved a guide. The final accessibility
layout keeps the editable image visible in a separate pane and scrolls the
readings and controls. Actual Simulator swipes preserve ratios; Square removes
variation without changing the headline ratios, and Undo restores it. Confirm
was tapped successfully at ordinary and maximum text sizes; sharing becomes
available only after that action. The native toolbar remains reachable.

Final inspected captures are `ui-final-normal`, `ui-final-ax-pane` (including
`scrolled-controls.png`) and `ui-final-pending-ax` (including
`confirm-controls.png`). Earlier failed captures remain retained. No extra
confirmation prompt was added; the normal-size direct-editing layout remains.

**HIG gate verdict: RISK — manual accessibility acceptance remains open.**

| Category | Status | Evidence / smallest remaining action |
| --- | --- | --- |
| Platform patterns | PASS | Existing navigation, native menus, buttons and sharing retained. |
| Clarity | PASS | One Confirm action, explicit human-review copy and directional variation labels. |
| Typography | PASS | Normal and maximum text inspected; long text wraps and controls scroll. |
| Accessibility baseline | RISK | Semantic labels and Simulator gestures inspected; run actual VoiceOver focus traversal and physical-device touch/pinch before closing this gate. |
| Interaction cost | PASS | No new prompt; one confirmation and live valid edits retained. |
| Design claims | PASS | Guided-estimate wording retained; review does not assert detector accuracy. |

Top remaining issue: VoiceOver/device interaction is unverified. Minimal follow-up
is a traversal and touch/pinch check of this final centering screen; no additional
prompt or navigation redesign is required. The full target, provider, physical
capture, held-out accuracy and release gates remain outside this receipt.

## Consolidated Done and removal repair — 2026-11-02

**Current status:** repaired and squash-merged in PR #19. The exact final
integration tree passed hosted CI. The [consolidation receipt](repository-consolidation-2026-11-02.md)
records source identities, the pending extra branch runs and the combined
1,734 passed / 3 expected skips / zero failures. Removal tests hold the real
production completion through B, verify same/different-field outcomes and
delivery-time validity, and reconcile every locally selected method with its
finalized result bundle. The original allocator abort remains a failed
historical result; its trigger is not claimed proven. Device, toolbar-tapping
and release gates remain open.

## Historical localized Done investigation — 2026-11-01

This investigation is isolated in [draft PR #19](https://github.com/Razorback2424/CardScanner/pull/19),
on `fix/centering-done-event-sequence`, from merged main
`4a9d70b12d941877e2752fe9cfb5fd1508ce0520` (tree
`6809ca82f89cea5cb69ed10d64c25b679181e042`). It is separate from the portfolio,
token and Reset Guides work in draft PR #18. Existing worktrees, edits and
stashes were preserved. No merge or release acceptance is part of this work.

The earlier passing native precision receipts below remain historical evidence.
They do not supersede the later merged-main failure or establish that it is a
harmless flake.

### Explicit Done boundary repair — 2026-11-02

**Current status:** superseded by the merged, final-head-verified consolidation
receipt above. The following local investigation and failure records are
historical checkpoints tied to their stated source identities.

#### Local removal-race repair and verification — 2026-11-02

**Historical checkpoint:** before publication and subsequent hosted fixture
corrections. Its counts and hashes apply only to that earlier local patch.

The local follow-up starts at `7d15be1`, in an isolated checkout. The original
race tests removed a native text field directly from SwiftUI's hierarchy. The
same-field fixture also placed a child hosting controller's view directly in
the window rather than its parent view. Both operations are removed. SwiftUI
now owns removal and replacement through conditional fixture views.

The production commit action has a per-instance Debug scheduler hook around
only the real removal finalizer. The default remains a main-queue deferred
completion; Done and ordinary blur remain synchronous. A guard belongs to
each scheduled completion, so duplicate delivery cannot repeat publication or
teardown and cannot suppress a later session. Fixture teardown restores the
hook and drains pending work on success and error paths.

The repaired tests hold A's real production removal completion, assert that
no model update occurred through ordinary blur and that A is still pending
before B starts, then deliver the held completion twice. A newer same-field
valid, invalid or untouched boundary suppresses A; a different-field B commits
first and A then commits once to its own field. Another edit after delivery
still commits. Separate native methods check synchronous ordinary blur while
A is held and delivery-time invalidation after a real image-load request,
failed image loading, model replacement, field-owner replacement and a newer
authoritative value. The existing live-value and field-token checks pass these
cases; capture-time validity alone is not used as proof. No new production
context-validation defect is claimed.

The original two-second event deadlines and observer-before-Done assertions
remain. An intentionally held completion is timed from explicit release;
the tests separately prove that it did not execute before release.

**Crash/evidence reconciliation:** the retained hosted focused bundle reports
10 passed / 3 failed. Its delayed-end case contains a crash attachment despite
the stdout pass; it is not an ordinary assertion failure that can be discarded.
The attachment and a local baseline reproduce a `SIGABRT` with
`freed pointer was not the last allocation`, through Swift concurrency task
deallocation and XCTest's `XCTSwiftErrorObservation._observeErrors(in:)`.
The hosted stdout starts the next same-field test before that abort. These
records explain why stdout alone was insufficient. They do not establish the
trigger of the runtime abort or prove that controller hierarchy caused it.
The invalid hierarchy is removed, and every final local selection completes
without an abort or restart. The old bundle remains authoritative for its head.

Native evidence is retained on the external SSD under
`CodexBuilds/CardScanner-PR19-Removal-20261102`:

| Local selection | Passed | Failed methods | Skipped |
| --- | ---: | ---: | ---: |
| Baseline at `7d15be1`, three selected methods | 1 | 2 | 0 |
| First five-method repair attempt | 4 | 1 | 0 |
| First fifteen-method repair attempt | 14 | 1 | 0 |
| Final focused selection, `repair-focused-2` | 15 | 0 | 0 |
| Final native class, `repair-native-class` | 46 | 0 | 1 |
| Final affected suites, `repair-affected-suites` | 131 | 0 | 1 |
| Final unchanged combined selection, `repair-combined` | 1,513 | 0 | 2 |

The baseline reproduces the same-field crash and premature A publication in
the different-field test. The two intermediate failures remain retained: the
new image test first bypassed the real load-revision path, then unnecessarily
waited for image analysis within an editing deadline. The final test uses the
production load entry point and checks deferred delivery while loading; it
retires that analyzer afterward. Editing deadlines were not increased.

Final verification used Xcode 27.1, iPhone 17 Pro / iOS 27.0 Simulator. Every
expected method is present exactly once in each finalized bundle, with no
stdout/bundle status conflicts, missing methods, unexpected skips, restarts,
SwiftUI publication-warning matches or bundle runtime warnings. The two known
combined skips are the native development-performance and aged-store opt-in
benchmarks. The evidence-gate Python suite also passes 9/9.

The local verification receipts include raw extraction output, exact method
lists and SHA-256 identities for the unchanged tested source:

- `CardCenteringView.swift`: `2337feeb622f5196d4bcb5a6edc2801d9389cf4490a6fa16951df4af76cebe95`
- `CenteringExportTests.swift`: `8ba27d80ec4abaa466a78e2adb33914575df4d5a091a844f0defc136bd8e53d5`

This is component/simulator evidence for the uncommitted local patch. It does
not replace final-commit CI or establish keyboard-toolbar tapping, VoiceOver,
physical-device, provider, CloudKit or release acceptance.

The complete decoded [job 125081729300](https://github.com/Razorback2424/CardScanner/actions/runs/41384336534/job/125081729300)
was inspected before editing. Its exact checkout was `47279260010de4d6d1c4ab1c9062115334e0ae4d`.
This supersedes the older PR/ledger statement that this candidate was queued
without execution. It reproduced a production event-sequencing defect:

| Starting-head selection, run 41384336534 attempt 1 | Methods | Passed | Failed methods | Skipped |
| --- | ---: | ---: | ---: | ---: |
| Localized focused attempt 1 | 1 | 0 | 1 | 0 |
| Localized focused attempt 2 | 1 | 1 | 0 | 0 |
| Localized focused attempt 3 | 1 | 1 | 0 | 0 |
| Complete native precision class | 35 | 33 | 1 | 1 |
| Affected centering/export suites | 120 | 118 | 1 | 1 |
| Original combined selection | 1,503 | 1,500 | 1 | 2 |

The rapid-refocus method fails in each of the last three selections. XCTest's
two failure assertions, one unexpected, belong to **one failed method**.
Focused attempt 1 separately fails while waiting for the initial untouched
Done/blur/unchanged-display guard; later focused passes do not erase it.

In the combined rapid-refocus trace, Done for A (`119,1193`) arrives at
1,874.201 ms, UIKit ends editing at 1,924.061 ms, and the fixture refocuses at
1,926.280 ms while SwiftUI still reports true. B (`119,2297`) reaches the draft
at 2,003.449 ms. A never commits. The later teardown blur at 4,188.576 ms
enters commit and publishes B at 4,188.770 ms as callback 1. The full-class
trace independently delivers B's Done at 2,003.445 ms with SwiftUI focus false;
the delayed focus-true observation arrives at 2,043.016 ms, and B only commits
during teardown at 4,477.379 ms. Times are per-case monotonic milliseconds.

The cause is the dependency on an observed SwiftUI focus transition, not the
locale parser or a value subscription installed too late. These traces do
**not** establish the cause of every historical French-locale timeout.

The starting run retained `catalog-native-results`, artifact `13114804763`,
139,792,040 bytes, SHA-256
`49f911d657ac2cea7c5789aadb658d58924053e37b6ef56df58ace8dbcb461fd`.
It contains the commands/attempt manifest, logs, keyboard diagnostics, per-run
result bundles and combined execution summary. The original artifact's stated
expiry is 2026-11-16 04:07:24 UTC. Complete decoded logs were inspected; local
result-bundle extraction is unavailable through this workspace's configured
network route.

A single fresh [pre-fix reproduction, attempt 2](https://github.com/Razorback2424/CardScanner/actions/runs/41384336534/job/125260500820),
again checked out the unchanged `4727926` head. It **reproduced** the rapid-refocus
failure while waiting for commit 2 in the native class, affected suites and
combined selection. No second retry was requested. The three localized focused
attempts each passed 1/1; native was 33 passed / 1 failed / 1 skipped (35 total),
affected 118 / 1 / 1 (120 total), and combined 1,500 / 1 / 2 (1,503 total).
Each failed selection again has one failed method and two assertions, not two
failed methods. The earlier focused failure in attempt 1 remains recorded.
Attempt 2 retains native artifact `13142235545`, SHA-256
`d958f0b8f2f1996835afc745a55ceafe774de15accff309b46e745dcc40576b3`;
the original attempt's artifact remains separately available.

#### First repaired native run — retained failed attempt

[Run 41444747470, job 125274962125](https://github.com/Razorback2424/CardScanner/actions/runs/41444747470/job/125274962125)
checked out repair commit `ecb4d6a7d6cf108a06a4c7a5a1cacecb216f086a` exactly.
The job was **cancelled**, its execution gate **failed**, and its native
artifact upload **failed**. Passing method totals do not make this a passing
workflow:

| Repaired-head selection | Methods | Passed | Failed methods | Skipped | Execution receipt |
| --- | ---: | ---: | ---: | ---: | --- |
| Localized focused attempt 1 | 1 | 0 | 1 | 0 | Focus-readiness polling deadline |
| Localized focused attempt 2 | 1 | 0 | 1 | 0 | Untouched-Done readiness polling deadline |
| Localized focused attempt 3 | 1 | 1 | 0 | 0 | Exact method completion |
| Focused sequencing/removal | 9 | 9 | 0 | 0 | All nine exact methods completed |
| Complete native precision class | 42 | 41 | 0 | 1 | All 42 exact methods completed |
| Affected centering/export suites | 127 | 126 | 0 | 1 | XCTest total; one completion line was interleaved, so the method gate failed |
| Original combined selection | 1,510 | 1,508 | 0 | 2 | All methods completed; result finalization was cancelled |

The preserved rapid-refocus trace commits A (`119,1193`) at 167.906 ms after
Done at 160.196 ms, before requesting dismissal at 180.140 ms. Immediate
refocus occurs at 287.764 ms with SwiftUI still reporting true. B's own Done
at 341.519 ms commits `119,2297` at 350.633 ms; the first observed blur is only
at 479.071 ms. The stale-focus regression delivers Done with focus false at
1,491.180 ms and publishes at 1,510.091 ms, before focus true at 1,891.670 ms.
The saved-old-end regression replays A's end at 1,392.173 ms without a second
publication; B's legitimate blur at 1,506.189 ms commits B at 1,507.006 ms.
These are production-component traces, not simulated commit implementations.

The two focused failures remain failures in this receipt. Their traces identify
an additional fixture timing defect: the waiter judged its own delayed resume
time rather than the recorded completion time. In attempt 1, focus was observed
at 1,176.348 ms, within the deadline that began after native focus returned at
218.681 ms; the waiter resumed at 2,278.184 ms with `condition=true`. In attempt
2, Done was requested at 2,591.300 ms, the unchanged guard ran at 2,602.600 ms,
UIKit ended at 3,647.440 ms and SwiftUI observed blur at 3,649.689 ms. All required
events were within two seconds, but the waiter resumed at 4,761.701 ms. The
follow-up uses the latest timestamp of **every** required event from the same
field/request, while still requiring the original live condition. Missing,
contrary, stale or post-deadline events cannot satisfy it. The original two-second
limit, observer-before-Done ordering and no-premature-update assertions remain.

Eight new SwiftUI runtime warnings, each also reported by XCTest, occurred in
context replacement and valid focused removal across the four broader phases.
They identify the model publication in the fixture's `accept` callback: native
removal was committing during SwiftUI reconciliation. The follow-up consumes
the immutable removal snapshot synchronously, then publishes only that captured
removal value outside the view-update transaction, with per-field session fences
and context revalidation. Done and ordinary blur still commit synchronously.

The affected-suite stdout split
`testPrecisionDoneReentrantRepeatedActionAndRemovalPublishOnce` across an
unrelated simulator message. Its pass is visible in the fragments and the other
three selections, but the original exact-method gate correctly remained failed.
The follow-up retains raw stdout and extracts exact method identities/statuses
from each finalized `.xcresult`; it does not infer missing methods from totals.
Missing or invalid result data and failures from either evidence source still
fail verification.

The combined XCTest summary finished at 13:02:20 UTC with 1,508 passes and two
skips. Cancellation at 13:02:34 UTC interrupted result finalization after the
35-minute job budget. The subsequent upload failed with `ENOENT` for a moving
file inside `catalog-tests.xcresult/Staging`; only the separate census artifact
survived. **No native result bundle from this candidate was successfully retained.**
The decoded job log remains available at the job link and was inspected in full
(SHA-256 `370c165692fcf6d8ebebfe32a4f403af3344b928f5ab517ddaff2f0836e609b9`).
This evidence loss is a remaining limit of that attempt, not a successful upload.
The follow-up combines the redundant focused launches into one fixed selection
and uploads completed comparison bundles before starting the original combined
selection. It does not increase the job or test timeouts or retry until green.

#### Bounded production change

Only the precision number input owns a native editing session. The enclosing
SwiftUI labels, stepper, reason and model validation remain. A plain SwiftUI
focus Boolean cannot distinguish A's delayed blur from B's legitimate blur,
so the field uses a small `UITextField` representable with a captured native
responder boundary. Other inputs retain their existing behavior.

- Toolbar Done synchronously captures the active editor, field, session,
  locale and native text. It consumes that session before invoking its
  captured update callback, then separately dismisses that same responder.
- Native resignation captures an immutable end event before UIKit can begin
  another edit. Delayed end callbacks carry that event; they never read the
  latest field or draft. Consumed/older sessions cannot publish again.
- Ordinary blur and focused removal still commit valid edits. Removal consumes
  its captured session immediately and publishes the validated captured value
  after SwiftUI reconciliation; a later callback never reads a live draft.
  Per-field boundary tokens also protect against replacement native editors.
  Invalid and
  untouched drafts are consumed without publication. No global next-blur
  suppression is used. Typing alone only changes the native draft.
- The existing locale parser and finite-number validation are unchanged.
  The untouched guard uses the edit's starting display; a captured live-value
  getter preserves unrounded precision, rejects invalidated image contexts,
  avoids duplicate writes before SwiftUI rerenders and restores the actual
  accepted geometry if model validation rejects a parsed value.
- The existing field identity now includes image revision. Captured side,
  frame, image revision, getter and updater remain tied to the same context.
  SwiftUI focus observations affect UI/diagnostics only. The `view.appear` and
  `view.disappear` trace events now identify the owned native window lifecycle;
  a delayed SwiftUI disappearance callback is not a commit source.

#### Regression and execution contract

The preserved rapid-refocus interaction waits only for UIKit blur before
refocusing. The localized observer still precedes Done, all original
precision/text/no-premature-update assertions remain, and the timeout remains
two seconds. Seven additional methods exercise stale focus, immediate
equivalent-value refocus, delayed old end callbacks, legitimate B blur,
context replacement/invalidation, reentrant/repeated Done, removal, invalid
and untouched drafts. The follow-up adds one exact readiness-deadline method
and two native removal methods: a distinct editor's newer same-field boundary
must suppress A, while a different field's boundary must preserve A's legitimate
removal publication. Trace assertions compare native identity, session identity,
exact values, callback counts and Done → consumption → update → dismissal order.

The follow-up recorder runs one fixed `focused-regressions` selection containing
the original localized method and every sequencing/removal/readiness regression,
then the full native class and affected suites. The original combined selection
is unchanged. Every selected method must have an exact completion record from
stdout or a finalized result bundle; aggregate totals cannot supply missing
methods. Missing/duplicate methods, unexpected skips, conflicting status and
earlier failures remain gates. Each invocation records its command, commit,
toolchain, simulator state, raw log, result extraction and `.xcresult`. Completed
comparison bundles are uploaded before combined execution as well as in the
final native artifact. The final head must execute this entire plan; its current
receipt is linked from PR #19 rather than inferred from an earlier commit.
Source discovery at `7d15be1` selected 13 focused methods, 45 native-class
methods and 130 affected methods; the unchanged combined selection gains ten
methods over the 1,503-method starting head. These are expected selection counts,
not an assertion that the new head has passed.

Local checks cover Python syntax, selection completeness and rejection of
missing/failed/skipped/duplicate completion records, plus `git diff --check`.
Nine persisted Python tests exercise exact result recovery, status conflicts,
failure preservation, wrong-target/missing/duplicate cases and malformed data.
The original Linux authoring workspace had neither Swift nor Xcode. Its native execution
used the existing GitHub Actions workflow with an exact-head checkout check;
the unavailable local proxy was not bypassed. The hosted input regressions
exercise the production Done action; actual keyboard-toolbar visibility,
manual VoiceOver/keyboard interaction and physical-device behavior remain
separate UI limits unless explicitly verified below.

### Original failure and evidence limits

The complete [failed job](https://github.com/Razorback2424/CardScanner/actions/runs/41375910704/job/125055978381)
was inspected and retained privately (7,962 log lines). The native result
artifact is available in that run as `catalog-native-results`, artifact
`13111359872`, with a 14-day retention period. Its connector download reference
was obtained, but local transfer failed because the configured proxy was
unreachable. No alternate network route was used; the result bundle's internal
records have not been inspected.

| Historical selection | Executed | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: | ---: |
| Combined native selection | 1,501 | 1,498 | 1 | 2 |
| Native precision class, included above | 33 | 31 | 1 | 1 |
| Export class, included above | 47 | 47 | 0 | 0 |
| Pokémon package, separate from native | 84 | 83 | 0 | 1 |
| Magic package, separate from native | 18 | 18 | 0 | 0 |

`testTypedLocalizedDraftPreservesAllDigitsAndCommitsOnlyOnDone` took 57.321
seconds. Its only failure was the two-second `fr_FR` Done expectation; later
numeric/text assertions did not separately fail. Both French inputs shared the
description, so the failed signed input cannot be recovered from this log.

No test failure preceded it. The preceding classes were Browse (72), sharing
(17), catalog normalization (40), and centering export (47), all passing.
There is no recorded simulator reset, test-process restart or crash. The same
application process continued through later tests. Absence of a reset message
does not establish simulator health.

| Original clock | UTC, November 2 | Observed event |
| --- | --- | --- |
| Application | 02:17:36.318812 | Keyboard main-thread queue timeout. |
| Application | 02:17:39.434007 | Invalid keyboard session ID. |
| Application | 02:18:05.205657; 02:18:19.547168 | Remote keyboard connection invalidation. |
| GitHub log ingestion | 02:18:28.651157 | French Done expectation timeout received. |
| GitHub log ingestion | 02:18:35.406104 | Test failure result received, duration 57.321 s. |

GitHub ingestion and application clocks are buffered/interleaved by up to
approximately 26 seconds here. This table cannot establish the order or delay
of focus, Done, commit, parse, publication or fulfillment; those events were
not instrumented. Keyboard disruption is established, infrastructure-only
causation is not.

Source inspection establishes that commit, parsing and probe publication are
synchronous once invoked, and the value subscription precedes the Done token.
It also establishes unobserved 80/40 ms fixture assumptions and hide-only
window cleanup. Neither source observation alone identifies the failed event.

### Observational baseline

Diagnostic head `b0c6ae3ad548e6d8e11f55bd273e776b91e71b1b` adds unique
locale/signed-input identifiers and per-host monotonic events. It retains the
three inputs, every original assertion, fixed sleeps, original cleanup,
production commit decisions and the two-second deadline. The app installs no
default trace sink or input logging. Instrumented bindings forward the original
transaction, and notification observers add no dispatches or waits.

The recorded events cover UIKit responder/editing calls, the actual draft
binding, observed SwiftUI focus, Done delivery, commit and parse outcomes,
model assignment/publication, fulfillment and teardown. Baseline callbacks
after a case ends are detected during subsequent cases; this does not prove
absence of callbacks after the entire test method has ended.

[Native comparison run](https://github.com/Razorback2424/CardScanner/actions/runs/41381240608)
uses three predetermined focused attempts, one whole-class attempt and one
affected-suite attempt, followed by the unchanged combined selection. It
retains logs, result bundles and an attempt manifest, uses the exact PR head,
and checks actual test-completion records. It reuses the selected simulator
without erasing or resetting it. A failed attempt remains failed even if a
later attempt passes.

| Baseline selection | Executed | Passed | Failed | Skipped | Localized test duration |
| --- | ---: | ---: | ---: | ---: | ---: |
| Focused attempt 1 | 1 | 1 | 0 | 0 | 26.579 s |
| Focused attempt 2 | 1 | 1 | 0 | 0 | 6.689 s |
| Focused attempt 3 | 1 | 1 | 0 | 0 | 7.370 s |
| Full native precision class | 33 | 32 | 0 | 1 | 17.958 s |
| Affected centering suites | 118 | 117 | 0 | 1 | 4.252 s |
| Original combined selection | 1,501 | 1,499 | 0 | 2 | 5.067 s |

These are six executions of the localized method, containing 18 locale/input
cases. They are repeated selections, not a count of distinct methods. The
combined total is XCTest's authoritative suite summary; one unrelated
completion line was interleaved with another log stream. Every required
centering method was individually confirmed. The recorder now preserves both
the suite summary and raw completion counts, and never substitutes an aggregate
count for a missing required method.

All 18 edited drafts were in SwiftUI before Done, and Done arrived with SwiftUI
focus true. Each published exactly once after the request, in 70.264–645.461 ms.
Observed blur to commit took 4–14 microseconds; commit to publication took
0.095–12.498 ms, and publication to fulfillment approximately 0–1 microseconds.
This baseline does not demonstrate a parsing, subscription or publication race.

The baseline had 31 invalid keyboard-session warnings but none of the original
queue timeouts or remote-keyboard invalidations. One initial UIKit focus call
blocked for 5.086 seconds. The original two-second edited-Done failure did not
reproduce; its precise cause remains unresolved, and it is not classified as
infrastructure-only.

### Demonstrated fixture sequencing and cleanup defects

**Eight of 18 initial unchanged-Done blur transitions coalesced across refocus.**
The assertions about preserving the untouched Double passed without executing
the unchanged-display commit guard. **Fourteen disappearance callbacks arrived
after cases were marked ended.** Those callbacks all had focus false; no late
model update or publication was observed.

The affected-suite English case supplies a complete 50-event example. Times
are milliseconds from that case's monotonic origin:

| Time | Event |
| ---: | --- |
| 145.109 | SwiftUI observed focus true. |
| 239.388 | Fixture requested unchanged Done. |
| 242.610 | Field received Done while focused. |
| 292.750 | Fixture requested refocus; UIKit was no longer first responder. |
| 405.738 | UIKit refocus returned true. |
| 498.533 | Fixture inserted `123.45`. |
| 501.235 | SwiftUI draft contained `123.45`. |
| 545.658 | Fixture requested edited Done. |
| 548.526 | Edited Done arrived with focus true and the correct draft. |
| 706.189 | SwiftUI observed its only blur. |
| 706.195 | Commit entered for the edited draft. |
| 706.427 | Model published `123.45`. |
| 706.428 | Expectation was fulfilled. |

There is no intermediate observed blur/refocus pair or unchanged-display
commit. This demonstrates that the original fixed-sleep fixture did not
complete its intended first focus cycle. It does not prove that this caused
the historical edited-Done timeout.

### Fixture correction and behavioral coverage candidate

The corrected localized test retains the same single-field host, locale/input
cases, precision/text/no-premature-update assertions, and Combine subscription
before Done with the original two-second fulfillment timeout. It observes
mounting, fresh UIKit and SwiftUI focus, and the actual draft. Before asserting
untouched-value preservation or refocusing, it requires Done delivery, native
responder loss, a fresh observed SwiftUI blur, and the real unchanged-display
commit guard. Exact callback-count and request-to-mutation deadline assertions
are added.

The shared fixture ends only its own editing session, observes blur and
disappearance, detaches the host, restores the previously visible key window,
and removes its observers before marking the case ended. No cleanup task is
launched from a synchronous defer. Retained traces detect callbacks during
subsequent cases; they do not claim observation forever after the test method.

Two new native cases cover the latest full-precision draft, repeated Done,
rapid native refocus before SwiftUI blur acknowledgment, movement between two
fields, and focused removal with valid, invalid and untouched input. The rapid
refocus case deliberately does not add the ordinary readiness gate that would
remove the interaction under test. Production commit behavior remains
unchanged at this checkpoint. These new cases and the fixture correction are
written and source-reviewed at that historical checkpoint. Their subsequently
failed native execution is recorded in the explicit-boundary repair section
above; the earlier pending statement is no longer current evidence.

The initial diagnostic head `26cad32794930de0e4c13500ecb6a44580eac2be` had a
missing computed-property brace caught in source review. Its superseded
[run](https://github.com/Razorback2424/CardScanner/actions/runs/41381093991)
was canceled during its first build and executed **zero native test cases**.
Its package step passed 101 cases with one skip. That cancellation is not a
reproduction or native pass.

## Current precision candidate — 2026-11-01

Branch provenance: `refinement/centering-native-2026-11-01`, based on
`b592c914d2bae7ecfbea03218b20f94bdef90364`; implementation commit `f5f2e14`.
This section supersedes historical candidate and timing claims below for this
patch only. No publication, automatic-release or calibrated accuracy acceptance
is implied. The REQ-045 guided contract and §5.1 tolerances are unchanged.

Implemented guided changes use actual raster dimensions and all eight EXIF
orientations, independent X/Y transforms and rounded presentation canvases.
Advanced controls translate either frame's selected line in 0.1 native-pixel
steps and turn it about its midpoint in 0.01-degree steps. Adjacent supporting
lines stay fixed; invalid intersections retain the last valid geometry with a
reason. Undo/reset, a registered source-pixel detail crop and locale-aware
numeric fields support manual recovery. Decimal granularity is not accuracy.
Typed values keep a localized draft until Done/focus loss. Actual UIKit editing
events preserve French `119,11` and `-0,25`, and English `123.45`, then commit the
exact values; incomplete drafts do not move guides. Focus/Done without editing
preserves the authoritative unrounded Double. Headless HID text injection
reported success without changing even a distinct replacement, so keyboard
tool automation is not counted as acceptance. A scene-less first test harness
failed before locating a field; its scene-backed correction passes.
Original compressed bytes plus one small cached crop are retained for detail;
the disclosure does not retain a full decoded camera raster.

Photo-only rotation remains intentional. Rotation and reset revoke frame
confirmation and immediately invalidate stale share snapshots. Pending or
invalid frames cannot expose ratios/export. Existing homography, candidate
precedence and automatic-reporting safety remain in place.

Native independent-slope refinement is **DEBUG opt-in and disabled in
production**. Development iterations preserve bounded strip sampling, spatial
coverage, residual, slope, nesting and ambiguity gates. V1 accepted 1/36 available
development inner sides; coherent multi-peak V2 accepted 1/36; deduplicated-track
V2b accepted 3/36. These are fit-gate counts, not accuracy. V1's narrow band
included the development reference at enough positions on only 11/36 sides.
Existing profile alternatives repaired some seed coverage, but stable artwork
edges can still win with the wrong semantic identity. One accepted V2b bottom
line is about 1,186 native pixels from a short art-window development reference.
No threshold relaxation can certify that selection. Automatic reporting and
the failed joint selector remain disabled; no sealed holdout was opened.

The exact original Gengar JPEG (1112×1536; SHA256
`d174c27d5aaba21dd4602d926488eb6d93a535f31eabdee5937c13bc4a405562`)
takes `scalarInner` with a Vision outer proposal throughout. Confirming its
unchanged starting guides gives baseline 64.5/35.5 LR, 44.4/55.6 TB; default
candidate 64.4/35.6, 44.0/56.0; experimental V2b 49.8/50.2, 44.2/55.8.
V2b repairs only the left side, leaving top/right/bottom unresolved. The actual
manual-control example gives 52.2/47.8, 50.4/49.6 after explicitly human-selected
guide placement. None of these is calibrated ground truth or automatic success.

Executed scope: 58 selected guided/export tests, 57 passes and one intentional
experimental-benchmark skip; then 109 applicable analyzer, development ground
truth, invariant, export and native tests with 108 cases passing and two latency
assertions failing in the single native benchmark. That failed run included an
unused legacy DEBUG research generator. Its receipt is preserved. A separate
production-equivalent native run with that generator off passes the unchanged
0.8/1.5-second limits (upper median 0.715 s, max 1.414 s). The final applicable
recheck passes **109/109 with zero skips**, including the enabled native gate;
production REQ-022 measures 0.491/0.536 s and native V2b 0.538/1.380 s.
The earlier aggregate's production measurement was 0.493/0.540 s. These are existing ten-fixture Debug
Simulator methods, without new repetitions or device performance acceptance;
they are not a full-target run. Earlier failed raster-test receipts and their
pure-color test correction are also retained, without relaxing its one-device-
pixel registration tolerance.

After adding the draft-field and scene-backed UIKit editing regression, the
final binary, including unchanged-draft preservation, passes **110/110
applicable cases, zero failures or skips**. Production REQ-022 is
0.495113/0.542783 s (upper median/maximum); native V2b is
0.549302/1.387473 s. These final measurements supersede the intermediate 109-case
recheck for this candidate; all earlier receipts remain available.

Evidence is private under `/Volumes/T7/ScanStash-Centering-Evidence-20261101/`:
raw baseline/default/V1/V2/V2b proposals, native points/lines and rejection
reasons, actual app screenshots and model exports, logs and `.xcresult` bundles.
The [precision checklist](../../references/centering_native_precision_checklist.md)
separates executed evidence from pending acceptance. Independent visual review,
VoiceOver traversal, native save completion, representative physical
capture, held-out accuracy and real-device gates remain open.
Native share-popover presentation is visually verified with the confirmed
manual example and retained PNG. Save Image is visible but absent from the
headless semantic target list, so no save completion is claimed. A later
off-viewport semantic rotation target misdirected to Pro; that attempt is
retained as a tooling limit and excluded from rotation acceptance.

## Historical checkpoints

**Rotation correction — 2026-10-29, base `f306918` plus working-tree patch:**
manual rotation now applies only to the photo, leaving the red/cyan measurement
guides fixed on screen and in the shared export. Zoom/pan still move both layers
together. Updated pixel regression expectations supersede the earlier shared
rotation contract; helper text now reads “Rotates photo only.” The focused
`CenteringExportTests` run passes all 28 cases with zero failures/skips. An initial
run used reversed expected signs for the photo stripe's rendered slope; the
corrected test verifies opposite slopes and their magnitudes in both directions.
Evidence is retained externally under `CodexBuild/CenteringRotation-20261029/`.
The [current checklist](../../references/centering_guided_success_checklist.md)
records Simulator visual acceptance separately from historical evidence.

**Latest timing follow-up — 2026-10-14:** the previously failing REQ-022 case
passes in the current Lorcana working tree after exact native scalar/median
optimization. Final full-target results: 2,188 passed, zero failed, 12 skipped;
REQ-022 upper median 0.586 s, maximum 0.649 s at unchanged 0.8/1.5 s limits.
Kernel and ten-fixture geometry/profile parity pass. See the
[production checkpoint](../release/lorcana-production-acceptance.md) for candidate,
stage measurements and archive/export evidence. This replaces the simulator
timing failure status in the historical checkpoints below; hardware/automatic
held-out and rendered accessibility acceptance remain separate.

**Status:** guided correctness and regression checks pass apart from the known
latency case; review follow-up fixes applied; final numeric-field accessibility
and inner-capture rechecks await an unlocked Mac — 2026-10-02.

**Candidate:** uncommitted working tree on `fix/october-review-boundaries`, based
on `73898e8`. This records the approved centering repair, not release certification.
The [centering contract](../../review/opus-card-centering-implementation-plan.md)
continues to govern automatic accuracy and held-out acceptance.

**2026-10-03 refinement checkpoint:** the full signed simulator run against
`dd2a1e3` plus B–J working-tree changes retains REQ-022 as the single observed
centering failing case (upper-middle/median statistic 1.6244 s; maximum 1.9206 s).
Other centering correctness/diagnostic assertions passed. Final post-fix
regression includes the UI/export/input cases and passes 1,707 cases with seven
existing skips across the remaining target. No centering source or tolerance
was changed by this pass. The owner requested wrapping up without further
screenshots or device-specific testing; latest rendered/accessibility/native
acceptance is deferred, not blocked on an inferred locked-Mac state. See the
[refinement evidence](../plans/october-production-refinement-review-plan.md).

## Implemented behavior

- Moving a perspective guide changes its supporting line and adjacent corners,
  preserving the opposite corners, frame roles, and rectification. Valid edits
  after one explicit confirmation update the reading immediately. Invalid,
  inverted, crossing, nonfinite, out-of-bounds, non-nested, or singular geometry
  cannot expose ratios or an export. A new input revokes approval before loading.
- Pending valid frames say **Review frames**. Invalid or missing frames say
  **Reading unavailable**. Confirmation is beside the guide controls and requires
  valid outer and inner frames. Numeric fields, steppers, zoom, and pan remain
  available; accessibility text uses stacked controls and a smaller preview.
  Camera, Photos, and file choices share one toolbar menu so the title fits.
- Loading and analysis use request generations: a late transfer, analysis,
  failure, or cancellation cannot restore an older measurement. Exports capture
  an immutable revision, render away from the main actor, and publish only while
  current. Each export has its own directory, preserving an in-flight share's
  file while subsequent edits prepare a new one.
- Diagnostic options, callbacks, and timing ledgers belong to each analysis.
  Registered-back detection can legitimately bypass scalar profiles. E0/E-E
  checks record the branch and still require four sides when profiles run;
  synthetic profile and concurrent-request tests provide dedicated coverage.
- Pixel preparation reuses RGB/Lab data, caches byte linearization and repeated
  profile transitions, and uses three private C kernels for existing Lab,
  gradient, and foreground arithmetic. Strict floating-point contraction is
  disabled. Resolution, detection thresholds, and selection policy are retained.
  DEBUG keeps the original calculation path for parity tests.

## Test contract and evidence

Guided transform tests apply independently annotated final frames to the
rendered rotation, mirror, quarter-turn, EXIF, scale, and crop variants, then
explicitly confirm them. Their original numerical tolerances remain unchanged.
Nine gradeable exposed development annotations are checked within two percentage
points; the tenth has no gradeable inner reference. The sealed holdout was not
used. No ground truth was changed and no new skips were introduced.

The original automatic transform comparisons are also executed and recorded
under `automatic-transform-gates/results.json`, with their original transforms
and tolerances. They are research evidence, not proof of the guided contract.
Twelve EXIF comparisons pass; ten rotation/mirror/quarter-turn/scale/crop
comparisons remain outside tolerance. Automatic reporting remains disabled, and
all ten original detector outputs must remain unreportable before confirmation.
These automatic gates remain open.

| Verification | Dated result |
| --- | --- |
| Seven centering classes, `Centering-v1` | 109 cases; 108 pass; only `testREQ022AnalysisPerformanceOverAllFixtures` fails, with two latency assertions. No skips. |
| Remaining test target, `NonCentering-v1` | 1,661 cases; seven existing skips; zero failures. |
| Optimized calculations versus original Swift path | Identical measurement geometry and full profile arrays for all ten exposed fixtures. |
| Private pixel kernels | Bit-exact Lab/gradient/mask comparisons, including 65,536 RGB combinations and all byte channel values. |
| Preview geometry | Independent expected positions within 0.5 point and rendered guide centers within one device pixel at scales 2/3, rotations 0/+7/−3 degrees, and zoom/pan. |
| Final UI/export/input rerun, `FinalUI-correctness-v2` | 31 cases pass after toolbar and accessibility refinements. |
| Final regression, `Final-regression` | 1,692 cases; seven existing skips; zero failures after the final DEBUG route correction. Includes those 31 cases and the remaining 1,661; excludes the five already-covered analyzer/corpus/invariant/profile classes. |
| ReleaseLocal simulator build, `Release-build-v3` | Passed for arm64 and x86_64; no archive or release acceptance implied. |
| Physical device | Device build succeeded using the existing signing team. Test launch encountered a locked-device preflight and lost the runner connection; no passing physical-device result claimed. |

The first two rows partition the test target; they are separate runs, not one
passing full-suite invocation. The final regression reruns the UI/export cases
and the rest of the target against the final working-tree binary. The only
observed XCTest failure remains the unchanged latency case in the centering run.
ReleaseLocal used a project-metadata copy on the SSD with links to the current
source, configuration, fixtures, and local packages after macOS file coordination
blocked the project in Documents; the repository project was not relocated.

REQ-022 retains its median ≤0.8 second and maximum ≤1.5 second assertions. The
centering selection measured median **1.6149 seconds**, maximum **1.9211 seconds**.
The earlier October-2 baseline was approximately 3.0119/3.3811 seconds. These are
simulator measurements, not a controlled physical-device comparison. The owner
explicitly accepted wrapping up correctness work while leaving latency open;
the budget was neither relaxed nor skipped.

## Visual verification before the uncommitted-change review

Final phone/tablet captures were visually inspected against the completed
[success checklist](../../references/centering_guided_success_checklist.md).
They cover pending, confirmed, invalid, missing-reference, rotation, zoom/pan,
numeric controls, light/dark appearance, and maximum accessibility-text states.
The initial phone capture exposed toolbar crowding; the first accessibility
capture prompted the smaller preview. Final controls remain readable and
reachable by scrolling; rotation increments keep their complete labels.

Native simulator interaction confirmed that one explicit confirmation exposes
the reading and a subsequent valid edge increment updates it without another
confirmation. Export Image presented the native phone share sheet and anchored
iPad share popover with the prepared PNG and descriptive filename. Both were
dismissed without choosing a destination. Actual VoiceOver traversal and
share/save completion on physical hardware were not verified.

## Evidence location and remaining gates

Builds, logs, result bundles, and captures are on the external SSD under
the external SSD under `CodexBuilds/TradingCardScannerCenteringRepair`.
Generated diagnostics use an explicit `CENTERING_DIAGNOSTIC_OUTPUT_ROOT` when
provided, otherwise simulator temporary storage; they do not rewrite tracked
evidence. Current diagnostics are copied into the SSD evidence directory.
CoreSimulator could not create/capture directly on that removable volume, so
task-owned simulator state and brief screenshot staging use system temporary
storage. A custom-set iPad installer also failed, so final iPad captures used a
task-owned device in the standard simulator set. Existing simulator data is
preserved, and temporary appearance/text-size settings were restored.

Latency, automatic accuracy/held-out acceptance, physical-device responsiveness,
VoiceOver interaction, share/save completion, and release/archive/provider/
CloudKit acceptance remain separate gates. Passing injected rendering and
snapshot tests or simulator share presentation does not certify those manual or
hardware gates.

This repair supersedes the earlier measure-only export-thread-placement
restriction for the authorized immutable revision export implementation. Device
profiling remains necessary before making responsiveness claims or pursuing
further performance work. Other measurement-only backlog items are unchanged.

## Uncommitted-change review — 2026-10-02

The follow-up review at `73898e8` plus the repair working tree found and fixed
five issues with focused changes:

- Crossing a perspective guide swapped the displayed left/right or top/bottom
  positions. Scalar projections now keep each named side's own coordinate.
- Moving a guide exactly onto its opposite erased adjacent supporting lines,
  preventing later edits. Such collapsing edits leave the editable frame intact.
- Inverting both inner axes restored clockwise winding and exposed a false
  reading. Eligibility now checks named side direction as well as winding.
- Confirmed `CenteringOuterControls` and `CenteringInnerControls` fixtures opened
  with collapsed controls. Those routes now initialize the requested disclosure.
- Regular-size numeric fields were embedded in a Stepper label and absent as
  editable elements in the observed simulator accessibility tree. Fields now sit
  beside the Stepper with their own labels and bindings, matching the existing
  accessibility-size separation.

All three geometry regressions failed before the fix and passed afterward. The
seven-class `Uncommitted-review-centering` run executed 111 cases: 110 passed,
with only REQ-022 failing its two unchanged latency assertions. Analyzer/kernel
parity and profile coverage passed. After the view changes,
`Uncommitted-review-final-ui` passed all 33 UI/export/input correctness cases;
its separate REQ-022 recheck still failed at median **1.5814 seconds**, maximum
**1.8764 seconds**, without concurrent compilation. This does not change the
existing latency disposition or establish a performance improvement.
The final `Uncommitted-review-release-final` ReleaseLocal simulator build passed
for arm64 and x86_64 after the view fixes. Project parsing, shell syntax,
all 202 local Markdown link targets, and `git diff --check` also passed.

The final outer-control phone capture shows the expanded, readable controls and
aligned preview. The inner route exposes its requested controls, but its capture
has an incomplete preview/navigation frame while the Mac is locked. The final
accessibility-tree and inner-capture rechecks await an unlocked Mac; no completed
VoiceOver traversal is claimed. Evidence is retained on the SSD under the
`Uncommitted-review-*` names, alongside the earlier evidence.

**HIG verdict: RISK pending final accessibility verification.** Platform patterns,
clarity, typography in the inspected outer capture, interaction cost, and design
behavior pass the scoped review: native controls remain, labels fit, no extra
confirmation is added, and invalid frames cannot expose readings. Accessibility
remains a risk until the final numeric fields and focus order are verified. The
top issues were the hidden numeric fields, misleading inverted readings, and
unrecoverable collapsed guides; the minimal fixes are confined to
`CardCenteringView.swift` and `CardCenteringMeasurement.swift`. To close the risk,
verify independent field editing and focus order and repeat the incomplete
inner capture after unlocking the Mac.
