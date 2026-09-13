# Card-centering experiments log

This is the durable record of centering experiments run against the current
implementation. A result is only called a pass when the stated test gate
passed. The checked-in ground truth is now the rederived analyzer-free set;
references below to provisional GT describe historical runs before REQ-027 and
are not current accuracy status.

## Baseline and validation context

### V0 — First full simulator run

- **Question:** Was the implementation actually runnable, and what did the
  full suite say rather than a compile-only check?
- **Run:** iOS 26.5 iPhone 17 Pro simulator
  (`EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86`), full `xcodebuild test`.
- **Result:** 1,076 tests; 1,045 passed, 24 failed, 7 skipped. Six keychain
  failures were harness failures caused by `CODE_SIGNING_ALLOWED=NO`; one Magic
  failure was pre-existing and outside the centering diff; 17 were genuine
  centering failures. The run took about 294 seconds. The earlier
  simulator-unavailable report was therefore not a valid reason to leave the
  runtime gates open.

### V1 — Ground-truth provenance audit

- **Question:** Do the checked-in references support the methodology claimed in
  their provenance blocks?
- **Method:** Count coordinate quantization and independently probe clean
  luminance steps in the oriented fixture rasters.
- **Result:** All 200 coordinates in the ten records were integral and exact
  multiples of five. The records claimed sub-pixel/manual reconciliation but
  used annotators `A` and `B` without a recorded independent pass. The audit
  also found a systematic outward right-edge bias (median about 22 px) and 32
  of 40 edges outside the crude strongest-step probe. The probe is not itself
  ground truth and can latch onto glare/artwork; it is supporting evidence only.
  All ten records were consequently made explicitly provisional. No detector
  tuning was based on the disputed IMG_0349 result.

## Historical implementation experiments

### X1 — Vision aspect range widened

- **Change:** Widened the `VNDetectRectanglesRequest` aspect range so
  sideways cards could be emitted (`0.45...2.0` post-filter; request maximum
  changed from portrait-only `0.90` to `2.0`).
- **Question:** Was the sideways `(0,0,0,0)` regression caused before the
  post-filter?
- **Result:** Yes. The retained sideways-card analyzer test passed, and the
  focused `CardCenteringAnalyzerTests` run was 20/20. This change is retained.

### X2 — Profile density 72 → 240 samples

- **Change:** Increased the number of samples along each long edge.
- **Question:** Was the profile too sparsely sampled for small skew?
- **Result:** Small-skew stability improved. Mirror, quarter-turn, scale, and
  EXIF invariant failures did not move. The higher density was retained, but it
  did not address the common metamorphic defect.

### X3 — Mean instead of median profile aggregation

- **Change:** Replaced the along-edge median aggregation with a mean.
- **Question:** Was the median suppressing the correct transition?
- **Result:** No useful invariant or legacy-gate improvement was recorded. The
  change was reverted. Exact assertion numbers were not preserved in the prior
  scratch output, so this entry deliberately does not invent them.

### X4 — Luminance-only profile evidence

- **Change:** Used luminance evidence in place of the existing colour-distance
  profile score.
- **Question:** Was Lab colour distance selecting unstable artwork peaks?
- **Result:** No useful invariant improvement was recorded; the change was
  reverted. It did not produce a durable gate pass.

### X5 — Canonical/homography image resampling

- **Change:** Resampled the image into a canonical rectified card space before
  running the profile.
- **Question:** Would removing perspective and orientation from the sampled
  image make the profile invariant?
- **Result:** It made the measurements worse. The extra image interpolation
  blurred/changed the evidence, so the experiment was reverted. This is not
  the same as later changing only profile sample coordinates.

### X6 — Force the scalar fallback path

- **Change:** Forced the scalar Lab/gradient fallback instead of allowing the
  Vision-first route to choose.
- **Question:** Was the defect in Vision rectangle selection or in shared
  profile evidence?
- **Result:** The metamorphic invariant results were unchanged. This is the
  strongest evidence that changing the Vision/quad arbitration alone would not
  solve the defect. The forcing change was reverted.

### X7 — Equal-border/shallowness preference

- **Change:** Tried preferring an inner candidate whose border depth agreed with
  the other three sides / was shallower.
- **Question:** Could a geometric prior suppress a noisy artwork transition?
- **Result:** It changed no useful measurements in the constructed cases and
  violated the requirement that unequal borders be measured independently. It
  was reverted.

### X8 — Profile state-transition experiment

- **Change:** Tried a state-transition interpretation of the profile rather
  than the existing candidate selection.
- **Question:** Would an explicit transition state be more stable than the
  current local-maximum selection?
- **Result:** 15 invariant assertions produced 13 failures and one skip. The
  result was worse, so it was reverted.

### X9 — Force `sampleRadius = 2`

- **Change:** Used a two-pixel derivative radius at every working resolution.
- **Question:** Was the one/two-pixel radius switch causing the scale failure?
- **Result:** The 0.6× scale error worsened to about 9.5 percentage points from
  about 1.8 points. The 20/20 legacy analyzer tests still passed, proving that
  legacy synthetic coverage did not expose the metamorphic regression. The
  change was reverted.

### X10 — Five-point score smoothing

- **Change:** Smoothed the profile score curve before selecting a candidate.
- **Question:** Would local smoothing make the winner less sensitive to
  resampling?
- **Result:** The targeted three-invariant run had six assertion failures.
  Quarter-turn errors were about 3.3, 4.7, and 3.8 pp; scale errors were about
  1.9 and 2.0 pp. Legacy analyzer tests remained 20/20. The change was
  reverted.

### X11 — Profile-only canonical upscaling

- **Change:** Upscaled small images only for profile analysis, leaving the
  surrounding detection path unchanged.
- **Question:** Was the 0.6× failure caused primarily by too few pixels?
- **Result:** Mirror measurements were about 1.8 and 0.6 pp; quarter-turns
  were about 3.4, 4.8, and 4.0 pp; 0.6× scale was about 2.0 pp. It did not
  establish a pass and was reverted.

### X12 — Vision-first inner selection

- **Change:** Preferred Vision's inner rectangle over the profile/scalar
  evidence.
- **Question:** Would the nested Vision rectangle be a more stable inner
  reference?
- **Result:** A targeted invariant run produced 12 failures and one skip.
  Mirror errors were about 12.6/7.3 pp; quarter-turn errors about
  3.4/12.6/4.0 pp; EXIF about 28.5/28.7 pp; scale about 12.5/14.0 pp; and
  the benign-crop invariant about 13.1 pp. The change was reverted.

### X13 — Scalar-area outer arbitration

- **Change:** Let the scalar silhouette replace the Vision outer when its area
  or aspect appeared more plausible.
- **Question:** Was the outer quad, rather than the inner profile, the common
  cause?
- **Result:** INV-2 and INV-9 passed in the targeted run, but INV-4, INV-5, and
  INV-7 remained failures. Pairing the scalar axis-aligned outer with a fitted
  Vision hypothesis was also geometrically unsafe. The change was reverted.

### X14 — Continuous centroid refinement

- **Change:** Replaced the bounded parabolic sub-sample refinement with a
  continuous centroid calculation.
- **Question:** Would averaging the local peak avoid a discontinuous argmax?
- **Result:** The focused three-invariant run produced five assertion failures;
  quarter-turn 180° was about 5.3 pp, quarter-turn 270° about 4.2 pp, and scale
  about 2.6 pp. The existing parabolic refinement was restored.

### X15 — Exact 90° profile canonicalization

- **Change:** Rotated the Lab pixel array by exact quarter turns, transformed
  the outer quad into portrait coordinates, ran the profile, then mapped the
  result back.
- **Question:** Could exact array rotation remove the 90° sampling asymmetry?
- **Result:** The focused three-invariant run still had six assertion failures
  and showed no improvement. The helper and production change were reverted.

### X16 — EXIF helper diagnostic

- **Change:** Tested the then-current JPEG/CIImage EXIF fixture helper before
  trusting INV-6.
- **Question:** Do orientations 1/3/6/8 actually decode to the same displayed
  pixels?
- **Result:** No. Orientation 1 differed from the canonical display by about
  118.524 average byte value; the other generated variants were similarly
  different (about 118.514 in the observed output). Raw comparisons also hit
  dimension mismatches/infinite results. INV-6 was therefore unadjudicated,
  not detector evidence. The helper was subsequently rebuilt under E5.

## Diagnostic and current experiments

### E0 — Differential profile dump

- **Change:** Added a DEBUG-only, named diagnostic test; no production choice
  depends on the sink. It dumps all 320 normalized-depth scores, support,
  baseline/MAD/threshold, candidates, selected depth before/after parabolic
  refinement, radius, distance scale, and the outer quad for IMG_0783 and
  IMG_0347 across base/mirror/90/180/270/0.6× variants.
- **Result:** The test passed for all 12 fixture/variant records. The updated
  normalized grid still shows real selection shifts. Examples:

  | Fixture/edge mapping | Base depth | Variant depth | Delta |
  |---|---:|---:|---:|
  | IMG_0783 right → rot90 bottom | 0.043938 | 0.048293 | +0.004355 |
  | IMG_0783 top → rot180 bottom | 0.034816 | 0.040453 | +0.005637 |
  | IMG_0783 left → rot270 bottom | 0.081870 | 0.089152 | +0.007282 |
  | IMG_0347 top → rot180 bottom | 0.032814 | 0.038533 | +0.005719 |

  The corresponding outer-line disagreement is as high as roughly 5 px on
  the same transformed edges, so the table does not support a claim that all
  residual error is threshold-only. It localizes a mixed problem: profile
  peaks translate with the fitted outer line, while some strong peaks also
  move under rotated/resampled pixels. In the scalar-needed cases the final
  measurement does use this profile result; it is not merely a dead
  diagnostic path.

- **Coordinate-space correction:** The comparison script was briefly changed
  to inverse-transform `outerQuadWorking`, which double-counted the analyzer's
  downscale and produced obviously wrong 200–288 px line distances. The script
  was restored to `outerQuadNative`, which is native to the rendered input PNG
  (including E0's margin); the working quad remains in each raw dump for audit.

- **Signed-line follow-up:** The comparison was extended to reconstruct the
  selected inner lines from each edge's normalized depth, inverse-transform
  those lines into the base source space, and report signed outer/inner offsets.
  Across both fixtures, the median absolute outer-line displacement was about
  2.2 px for mirror, 1.5 px for 90°, 4.8 px for 180°, 3.2 px for 270°, and
  1.1 px for 0.6×. The corresponding median absolute inner-line displacement
  was about 1.4, 0.8, 2.0, 1.4, and 0.4 px. The largest selected-depth shifts
  were `+0.004355` (IMG_0783 right → rot90 bottom), `+0.005637`
  (IMG_0783 top → rot180 bottom), `+0.007282` (IMG_0783 left → rot270
  bottom), and `+0.005719` (IMG_0347 top → rot180 bottom). This rules out a
  pure outer-quad explanation and also does not support calling the residual a
  pure peak-identity switch: both fitted geometry and profile depth contribute.

- **Later harness audit:** E0's `normalisedImage` first draws each HEIC into a
  900x1200 bitmap before applying its metamorphic transform. The JSON's
  `sourceWidth`/`sourceHeight` therefore describe that pre-downsampled bitmap,
  not the original production HEIC. The variant card width also changes from
  about 631 working pixels at base to about 470 at 0.6x. E0 remains useful for
  locating behavior inside that harness, but its displacement values are not
  yet production-equivalent; E-C is required before tuning against them.

### E1 — Resolution-normalized metamorphic measurement (historical harness)

- **Change:** Added a harness-only record that computes the GT-derived card
  height in the analyzer's working pixels for raw and scale-equalized variants.
  It does not rewrite the invariant pass/fail claims. The later audit found
  that this helper starts from the same pre-downsampled 900x1200 image as E0,
  so it equalizes that synthetic renderer's variants but does not yet measure
  raw-HEIC variants at a common effective resolution. E-C below is the named
  replacement for that missing measurement.
- **Initial result:** The first binary-search solver chose the end of a
  1,200-pixel cap plateau (`scale = 3`), which was a harness bug, not a
  detector result.
- **Corrected result:** For both fixtures, base/mirror/90/180 raw working card
  heights were equal; 270° was 0.999328 of base; 0.6× was 0.744 of base. The
  corrected 0.6× equalization chose scale `0.8064516129` and matched base
  height exactly. The ±0.5% assertions passed. Raw and equalized records are
  both retained, but only as evidence about the pre-downsampled harness. E-C
  below is the named raw-HEIC replacement; these values must not be used as
  current production-input measurements.

### E-C — Raw-HEIC, effective-resolution-equalized metamorphic harness

- **Change:** Reworked the E1 diagnostic to start every variant from the
  original HEIC bytes, retain the source storage/display dimensions, compute
  the GT-derived working quad after each metamorphic transform, and preserve
  both raw and equalized analyzer measurements. Equalization targets the
  fixture's base working short edge and asserts a maximum relative error of
  0.5%. This is test-only; it does not call private analyzer helpers, change
  production code, or modify ground truth.
- **Run:** `CenteringProfileDumpTests/testE1MetamorphicVariantsCanBeResolutionEqualizedFromRawHEIC`
  on the pinned iOS 26.5 iPhone 17 Pro simulator, using the external-SSD
  DerivedData/result-bundle paths. The run completed in 85.941 s and wrote
  twelve records to `diagnostics/E1/resolution.json`.
- **Result:** The raw and equalized working short edges were within the
  required ±0.5% for all twelve records. Because the 1200-pixel analyzer cap
  is already active, the raw short edge was already constant across variants:
  643.2 px for IMG_0783 and 631.2 px for IMG_0347. The 0.6× equalized scale
  remained 0.6; no hidden scale amplification was needed. IMG_0783 was
  `confident` for base, mirrorX, rot90, rot180, rot270, and scale0.6. IMG_0347
  was `confident` for base, mirrorX, rot180, and scale0.6, but `declined` for
  rot90 and rot270 in both raw and equalized records.
- **Interpretation:** E-C closes the harness-construction requirement for the
  selected E0 diagnostic fixtures and removes the pre-downsampled-input
  confound from this measurement. It does not close INV-5 or REQ-035, and it
  does not adjudicate accuracy while GT is provisional. The IMG_0347
  quarter-turn declines are now reproducible at matched effective resolution;
  they are the next branch/refinement investigation target.

### E-A — Raw-fixture inner-branch diagnosis

- **Change:** Added a DEBUG-only analyzer hook that records
  `scalarOuterAgreesWithVision`, `scalarPinned`, `outlineHasInner`, and an
  enumerated `innerSource`, plus profile failure reasons and selected depths.
  The test runs the ten original HEIC fixtures rather than E0's rendered
  900x1200 variants. A first run exposed a filename bug that wrote literal
  `(fixture).json`; the summary was valid, the per-fixture path was corrected,
  and the test was rerun successfully with ten independently named records.
- **Initial result:** Vision supplied no inner quad on any of the ten raw
  fixtures. All five sleeved decliners had `scalarPinned = true` and
  `innerSource = none`; two of them had scalar/Vision outer agreement true.
  The result therefore rejected the 2% agreement predicate as the primary
  explanation. `IMG_0348` was confident through `scalarInner`; `IMG_0780` and
  `IMG_0783` used `profile`; `IMG_0782` correctly remained `none`.
- **Follow-up result:** After allowing the existing working-pixel profile to
  run when scalar evidence was pinned, `IMG_0349` and `IMG_0351` recovered via
  `profile`. `IMG_0347`, `IMG_0350`, and `IMG_0352` reached the profile but
  failed its portrait coverage guard. The added failure telemetry recorded
  `inner_coverage_too_small` and selected profile depths around 0.07–0.10.

### E-B.1 — Global shallow profile-coverage experiment

- **Change:** Lowered the portrait profile coverage thresholds from `.85/.88`
  to `.80/.80` for every profile result.
- **Result:** The five-fixture E-B inner-evidence test passed, but the correctly
  targeted `CardCenteringGroundTruthTests/testMaskFailureDeclinesWithoutAnInnerReference`
  failed: `IMG_0782` became confident with a profile inner quad. The earlier
  safety invocation had targeted the wrong XCTest class and was not evidence;
  the corrected run exposed this failure. The change was reverted.

### E-B.2 — Pinned scalar + card-shaped scalar-outline gate

- **Change:** Retained the pinned-profile fallback, but relaxed profile
  coverage to `.80/.80` only when scalar evidence is pinned and the independent
  scalar outline remains approximately card-shaped (within an 8% aspect
  residual). Malformed scalar outlines retain the original `.85/.88` gate.
- **Result:** The five-fixture E-B test passed, and the correctly targeted
  `IMG_0782` safety test passed. The final E-A rerun produced 8 confident and
  2 declined fixtures: `0347`, `0348`, `0349`, `0350`, `0351`, `0352`, `0780`,
  and `0783` confident; `0781` declined for rectification and `0782` declined
  for missing inner reference at the default 1200-pixel path. The historical
  pre-E-D E7 sweep then recorded `IMG_0782` as confident at larger benchmark
  resolutions; that result was superseded by the later post-roll E7 rerun,
  which keeps it declined at all four tested maxima. This is a
  branch/availability result; current accuracy is measured separately against
  the rederived GT.

### E3 — Missing inner reference must decline

- **Change:** No production change was needed; the current branch already
  declines IMG_0782 when the inner reference is absent.
- **Result:** `testMaskFailureDeclinesWithoutAnInnerReference` passed on the
  pinned iOS 26.5 simulator. The result had `innerReference = .none`,
  `geometryInnerQuad = nil`, and no exposed ratio. This gate is green. The
  former IMG_0349 confident/wrong comparison is now replaced by the current
  rederived-GT production run.
  The refreshed post-REQ-027 E7 sweep also keeps IMG_0782 declined at all four tested
  working maxima. REQ-030 is therefore green for the tested benchmark modes,
  while broader supported-mode coverage remains open.

### E4 — Analyzer-free ground-truth candidate generation

- **Change:** Added a review-only `gt_tool.py profile-candidates` command. It
  samples each seeded edge normal at 200 positions between 12% and 88% of the
  edge, aggregates luminance profiles, detects 10–90% transition candidates,
  fits candidate edge lines, and reports candidate corners/aspect/agreement.
  It does not import the analyzer and does not overwrite any GT record.
- **Result:** Candidate JSON and README were written under
  `diagnostics/E4`. The candidate pass supports the prior IMG_0349 audit:
  its right-edge candidate is about 63.6–63.8 px inward from the provisional
  right edge, with two-pass agreement about 0.29 px. Other records show
  multiple-transition ambiguity, including IMG_0348 (agreement about 130.1
  px) and larger candidate disagreements for IMG_0347/IMG_0352 (about 8.8/8.2
  px). Candidate aspect estimates range roughly 0.700–0.723 on the usable
  records, but the multi-transition cases were not safe for automatic
  replacement. The output was evidence for the subsequent visual adjudication
  step; it did not itself replace the records. REQ-027 was completed by the
  dual-pass rederivation below.

### REQ-027 — Ground-truth rederivation and first adjudicable accuracy run

- **Test-first baseline:** The updated provenance test was run before replacing
  any record. It correctly failed: 1 test case with 61 assertions, because all
  ten records still carried the provisional method, unverified annotator list,
  null agreement, and wholly integral coordinates. The retained result bundle
  is `req027-tdd-baseline.xcresult` on the external SSD.
- **Change:** Extended the analyzer-free `gt_tool.py` with a `rederive`
  command. It runs two independent profile passes over the oriented fixture
  PNGs, uses the 10–90% band and 50% crossing, fits edge lines and virtual
  corners, reconciles the passes, applies a separately reviewed physical-
  silhouette selection manifest where glare/artwork produces competing
  transitions, and writes full profile diagnostics. It does not import or call
  `CardCenteringAnalyzer`.
- **Review decisions:** All ten current records were promoted with method
  `analyzer_free_dual_profile_fit_with_visual_adjudication`, annotators
  `generic_profile_pass_A` and `generic_profile_pass_B`, non-integral geometry,
  measured `agreementPx`, and exact measured-band ambiguity metadata. The
  IMG_0349 right edge was resolved approximately 63 px inward onto the
  physical card silhouette rather than moved to match detector output. Sleeved
  encasement traces with no stable luminance boundary remain separately
  reviewed virtual traces and are not used for card ratios.
- **Static/visual result:** `gt_tool.py validate` passed for all 10 records;
  the tracked overlay sheets were regenerated and visually reviewed. The old
  records are archived under
  `ground-truth/provisional-2026-09-11/`, and the full current diagnostics are
  under `diagnostics/GT-rederived/`.
- **Runtime result:** The first XCTest run against the promoted records ran on
  the pinned iOS 26.5 iPhone 17 Pro simulator and executed 12 test cases: 8
  passed and 4 failed. Provenance/schema/aspect/reachability, baseline,
  camera-configuration, evidence-table, and IMG_0782 no-inner checks passed.
  The failed test cases were the holdout ratio helper, the IMG_0780 art-window
  ratio check, the all-fixture L1 production-entry-point gate, and the IMG_0348
  portrait-art-window check. The result bundle is
  `req027-ground-truth-after-rederive.xcresult` on the external SSD.
- **Decision:** REQ-027's provenance/rederivation gate is complete. Overall
  L1 accuracy is not complete; the four failed test cases are current
  detector/reference evidence and must be debugged without changing GT merely
  to satisfy the implementation.

### E2/E6 — Card-normalized profile and unified score scale

- **Change:** Replaced the integer 2...max-depth loop with a fixed 320-point
  0.004...0.20 normalized-depth grid; made the derivative radius a continuous
  0.0015 card-relative value; sampled from edge origin plus an inward normal;
  retained the 240-point along-edge median and bounded parabolic refinement;
  and changed the profile call sites to one `distanceScale` of 1.
- **Result:** `CardCenteringAnalyzerTests` stayed 20/20. The uniform-scale gate
  INV-7 passed. INV-4 still failed at 2.1 pp; INV-5 still failed at 3.9, 5.1,
  and 4.2 pp for 90/180/270°. The focused run executed three invariant tests
  with four assertion failures. E2 therefore improved scale stability but did
  not close mirror/quarter-turn invariance. The E0 table indicates that the
  next experiment must address fitted-outer translation and/or threshold
  stability, not add another arbitrary pixel-radius constant.

### E-D — Deterministic outer-edge refinement

- **Question:** Can the Vision outer-region proposal be refined against the
  physical edge with a deterministic normal-profile fit, without inheriting
  the proposal's subpixel drift or breaking the retained synthetic fallback
  behavior?
- **Test-first baseline:** Added the E-D acceptance test before enabling the
  production refinement. The baseline run failed because
  `outerRefinementAccepted` was false and no refined quad was present. This
  was the expected red test; it is retained as the pre-change result bundle
  `ED-regression-baseline.xcresult` on the external-SSD artifact path.
- **Initial change:** Vision's proposal was refined from the original working
  RGB pixels using edge-normal luminance profiles, a sampled 10–90% crossing,
  median aggregation over the edge, line fitting, and adjacent-line
  intersections. The refinement was deliberately proposal-relative and did
  not read ground truth or choose a transition by matching a GT coordinate.
  The raw IMG_0783 acceptance test passed after the initial implementation.
- **Initial regression result:** The unconstrained fit caused eight assertion
  failures across six retained `CardCenteringAnalyzerTests`. Synthetic
  interior transitions won over the physical proposal in the low-contrast,
  thin-banner, odd-border, landscape, and skewed-card cases; the resulting
  border readings were displaced by roughly 5–30 px in the affected tests.
  This showed that a globally applied 10–90% fit is not safe when the proposed
  region is already correct and interior artwork has a stronger transition.
- **Guarded repair:** Added a general local-offset guard: an accepted edge fit
  must remain within `max(8 px, 2% of the card short edge)` of the proposed
  edge, in addition to the existing shape, aspect, parallelism, and support
  checks. This is not a fixture exception and does not use provisional GT.
  The focused legacy analyzer class then returned to 20/20, and the E-D raw
  IMG_0783 acceptance test still passed. Current E-A telemetry shows accepted
  refinement flags for `IMG_0349`, `IMG_0351`, `IMG_0780`, and `IMG_0782`; the
  other six raw-fixture analyses retain the Vision proposal. `IMG_0782` can
  accept an outer refinement and still correctly decline because its inner
  reference is absent.
- **Roll-preservation repair:** The first post-fit invariant run changed the
  presentation roll when fitted-line angle noise was fed into the rotation
  control. That pre-repair run produced 71 assertions across the targeted
  invariant cases. The implementation now preserves the proposal's roll and
  parallelism signals while using the refined quad for physical geometry.
- **Current post-roll result:** On the pinned iOS 26.5 iPhone 17 Pro
  simulator, the combined run executed 20 analyzer tests plus five targeted
  invariant tests. The analyzer class passed 20/20. INV-3 passed. INV-4
  failed at `1.4 pp` (limit `0.5`); INV-5 failed at `0.7/1.4/1.1 pp` for
  90/180/270 degrees (limit `0.5`); INV-7 failed at `1.4 pp` (limit `1.0`);
  and INV-8 failed at `1.1 pp` (limit `1.0`). There were six assertion
  failures total. The retained result bundle is
  `post-ED-roll-repair-invariants.xcresult` on the external-SSD artifact
  path.
- **Interpretation:** E-D fixed the legacy regression introduced by the
  unconstrained fit and restored INV-3, but it has not closed the metamorphic
  invariants. It is a conservative partial implementation, not evidence that
  the outer geometry is now stable. A post-refinement per-edge E0 successor
  diagnostic is still required to classify the remaining drift as outer-line
  motion, profile phase/statistics, or both. This diagnostic did not make an
  accuracy claim; the current rederived-GT accuracy run is recorded separately.
  A final-state confirmation run subsequently executed E-A, E-B, and
  the E-D acceptance test; all three passed in 43.805 test seconds, with the
  same 8-confident/2-declined E-A branch result. Its result bundle is
  `post-ED-branch-confirmation.xcresult` on the external-SSD artifact path.

### E-E — Post-refinement profile classification

- **Question:** After E-D, is the remaining metamorphic drift coming from the
  refined outer geometry, the normalized inner-profile selection, the profile
  statistics, or the E-C harness itself?
- **Change:** Added a DEBUG-only diagnostic that runs the public analyzer on
  raw and effective-resolution-equalized variants of `IMG_0783` and
  `IMG_0347`. It records the selected normalized depth before/after bounded
  refinement, score, support, baseline, MAD, threshold, candidate count, and
  line displacement per edge. Variant lines are inverse-transformed to the
  base working coordinate system; no provisional GT coordinate is used to
  select a transition.
- **Run/result:** `CenteringProfileDumpTests/testEEDumpPostRefinementProfileNormalization`
  passed in 90.912 test seconds on the pinned iOS 26.5 iPhone 17 Pro simulator.
  It wrote 24 variant/space snapshots and 96 per-edge records to
  `diagnostics/ED/profile-normalization.json` and `.md`. The raw and
  equalized records are identical at the active 1200-pixel cap, so the E-C
  equalization construction is not the source of this residual.
- **Measured classification:** For hard sleeved `IMG_0347`, outer-line
  displacement reaches 5.19 working px on the quarter-turn set and selected
  normalized-depth displacement reaches 0.0061; inner-line displacement
  reaches 4.39 px. For clean `IMG_0783`, scale displacement stays below 1 px,
  while mirror/quarter-turn depth shifts remain, including 0.0037 on the
  mirrored left/right correspondence and up to 3.28 px of inner-line
  displacement. Support/threshold changes are small for the `IMG_0347`
  rotations (at most 0.096 and 0.12 respectively); `IMG_0783` has a
  scale-right threshold delta of 1.29 as an isolated outlier. The residual is
  therefore classified as both outer-line motion and profile depth selection,
  not as a raw/equalized harness mismatch alone.
- **Decision:** No additional production tuning was accepted from this
  diagnostic. REQ-038's classification artifact is complete; REQ-029 still
  fails the stated INV-4/5/7/8 tolerances. The separate rederived-GT accuracy
  run is now adjudicable and is recorded below.

### E-D2 — Per-edge outer-refinement acceptance telemetry

- **Question:** When the guarded E-D refinement is rejected, is the rejection
  caused by incoherent edge evidence, or by a coherent physical transition
  that lies outside the conservative local-offset guard?
- **Change:** Added a DEBUG-only sink and a real-fixture test that records every
  accepted normal-profile offset for each edge, the minimum support count,
  median/MAD, local guard, rejection distance, and rejection reason. This is
  observational only: it does not alter the analyzer decision or read current
  ground-truth coordinates.
- **Run:** `CenteringProfileDumpTests/testEDumpOuterRefinementDecisionsForAllRealFixtures`
  on the pinned iOS 26.5 iPhone 17 Pro simulator
  (`EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86`), with the result bundle and build
  products on the external SSD. The test passed in 27.568 test seconds and
  wrote `diagnostics/ED/outer-refinement.json` plus per-fixture JSON files.
- **Result:** The coherent large-offset cases are:

  | Fixture/edge | Accepted samples | Median offset (working px) | MAD | Guard | Outcome |
  |---|---:|---:|---:|---:|---|
  | IMG_0347/left | 25 | −35.03 | 0.98 | 14.17 | rejected as outside guard |
  | IMG_0350/left | 26 | −28.45 | 1.62 | 14.80 | rejected as outside guard |
  | IMG_0352/left | 25 | −31.59 | not reported | 14.32 | rejected as outside guard |
  | IMG_0781/left | 26 | −28.79 | not reported | 14.68 | rejected as outside guard |

  The negative sign means the detected transition is outward from the Vision
  proposal along the normal toward the card exterior. In these four cases the
  profile is internally consistent across most of the edge, but it is too far
  from the proposal for the current `max(8 px, 2% of short edge)` rule. That
  makes the guard a concrete next hypothesis, not proof that the transition is
  the physical cut edge.
- **Other observations:** `IMG_0348` accepted left/top/right corrections of
  about −5.56/−10.09/−7.06 px, but its bottom edge had only 6 accepted samples
  against the minimum 11 and therefore rejected the complete quad. `IMG_0349`,
  `IMG_0351`, `IMG_0780`, `IMG_0782`, and `IMG_0783` produced complete
  accepted refinements; the remaining reported fixtures short-circuited on
  their first rejected side. The telemetry therefore distinguishes a coherent
  large-offset rejection from a low-support rejection, but does not establish
  a safe global guard widening.
- **Decision:** No production change was accepted from E-D2. The next guard
  experiment must be feature-based and must be checked against the retained
  synthetic tests before any real-fixture accuracy claim is made. A fixed
  fixture exception or a blanket 28–35 px widening would violate the purpose
  of the E-D safety repair.

### E-D3 — Blanket 8% local-offset guard (discarded)

- **Question:** Would allowing the deterministic outer fit to move up to 8% of
  the short edge recover the coherent 28–35 px sleeve transitions identified
  by E-D2?
- **Change:** Temporarily changed only the production guard from
  `max(8 px, 2% of short edge)` to `max(8 px, 8% of short edge)`. No fixture
  identifiers, GT coordinates, or other selection logic were changed.
- **Run:** `CardCenteringAnalyzerTests` on the pinned iOS 26.5 iPhone 17 Pro
  simulator, with artifacts on the external SSD. The result bundle is
  `guard8-synthetic.xcresult`.
- **Result:** The 20-test class failed 7 assertions. The sideways-card case
  reported `(0, 1, 55, 61)` instead of `(25, 20, 55, 60)`; the thin-banner
  case reported `(51, 5, 51, 50)` instead of `(60, 15, 60, 60)`; the odd-border
  case reported `(10, 10, 10, 65)` instead of `(15, 15, 15, 70)`; three of the
  five small-skew cases failed with `(15, 19, 54, 49)` instead of
  `(20, 25, 60, 55)`; and the unequal-border case reported
  `(10, 14, 69, 65)` instead of `(15, 20, 75, 70)`. Thirteen tests passed.
- **Decision:** Discarded and restored the 2% guard. A larger blanket distance
  is not safe: coherent interior transitions can pass the same normal-profile
  test and corrupt the retained fallback behavior. E-D2's large sleeve offsets
  require an additional feature/physical-silhouette discriminator, not a
  wider scalar threshold.

### E-D4 — Broad-transition feature gate (discarded)

- **Question:** Can a transition-width-to-peak-gradient feature distinguish the
  broad real-photo edges from the sharp synthetic decoys, and permit an
  extended offset only when that evidence is present?
- **Test-first contract:** Added a temporary E-D3 regression test requiring the
  four coherent large-offset photo cases identified by E-D2
  (`IMG_0347`, `IMG_0350`, `IMG_0352`, and `IMG_0781`) to retain a refined
  outer quad. With the conservative 2% guard, the test correctly failed all
  four assertions; this expected-red result is `ed3-baseline.xcresult`.
- **Change:** Temporarily collected all four edge records before applying the
  guard. If any edge's median 10–90% transition width divided by its median
  peak-gradient strength was at least `6.0`, the candidate widened the guard
  to `max(2% of short edge, 6% of short edge)` for the complete quad. The
  feature was based only on the original working pixels; it used no fixture
  identifiers or GT coordinates.
- **Run/result:** The E-D3 photo contract passed 4/4, but the retained
  `CardCenteringAnalyzerTests` class failed 7 assertions. The failures were the
  sideways case `(0, 1, 55, 61)`, the thin-banner case `(51, 5, 51, 50)`, the
  odd-border case `(10, 10, 10, 65)`, three small-skew cases `(15, 19, 54, 49)`,
  and the unequal-border case `(10, 14, 69, 65)`. The broad-transition feature
  was triggered by unrelated synthetic edges on the same proposed card, so
  it did not provide the required separation. The candidate run is retained
  as `ed3-candidate.xcresult` on the external SSD.
- **Decision:** Discarded the feature gate and its temporary E-D3 contract;
  restored the last known-good per-edge 2% guard. The richer transition
  telemetry and passing synthetic diagnostic remain available for a future
  physical-silhouette discriminator, but no selective acceptance claim is
  made from this experiment.

## Validation runs after E2

### V2 — Retained analyzer regressions

- **Run:** `CardCenteringAnalyzerTests` on the pinned iOS 26.5 iPhone 17 Pro
  simulator, with DerivedData on the external SSD.
- **Result:** 20/20 passed, including the sideways and skewed-card tests.

### V2a — Correctly targeted REQ-028 regression rerun (2026-09-12)

- **Attempt discarded:** The first new invocation used an incorrect
  `CenteringExportTests` filter. It built successfully but executed zero tests,
  so it is not evidence for REQ-028.
- **Run:** Reran the exact methods
  `CardCenteringAnalyzerTests/testACardPhotographedSidewaysIsStillFound` and
  `CardCenteringAnalyzerTests/testStraightensASkewedCardBeforeMeasuring` on the
  pinned iOS 26.5 iPhone 17 Pro simulator, with build artifacts on the external
  SSD.
- **Result:** 2/2 passed in 4.827 test seconds. The result bundle is
  `req028-correct-before.xcresult` on the external SSD.
- **Decision:** The current focused sideways/skewed regression gate is green;
  the full final suite remains pending. No production change or tolerance change
  was made as part of this validation.

### V3 — Current metamorphic gate subset

- **Run:** INV-4, INV-5, INV-7, and the E0/E1 diagnostics.
- **Result:** E0/E1 passed; INV-7 passed; INV-4 and all three quarter-turn
  cases failed at the values recorded under E2/E6 above.

### V4 — Complete invariant class after E5

- **Run:** All 14 tests in `CardCenteringInvariantTests` on the pinned iOS
  26.5 iPhone 17 Pro simulator, with DerivedData on the external SSD.
- **Result:** INV-1, INV-2, INV-3, INV-6, INV-7, INV-8, INV-9, INV-10,
  REQ-017, REQ-018, and REQ-024 passed. INV-4 failed at 2.1 pp; INV-5
  failed at 3.9/5.1/4.2 pp for 90/180/270 degrees. REQ-022 failed with
  median 1.8439 s and max 2.6823 s. Six assertions failed total.

### V5 — Post-documentation exact-device rerun (historical pre-E-B record)

- **Run:** Rebuilt and ran `CardCenteringAnalyzerTests` and the complete
  `CardCenteringInvariantTests` class on iOS 26.5 iPhone 17 Pro
  (`EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86`), with DerivedData on the external
  SSD. This run included the signed-line diagnostic-script changes, the
  benchmark-path edits, and regenerated both E7 artifacts.
- **Result:** `CardCenteringAnalyzerTests` passed 20/20. The invariant class
  completed 13/16 tests: E7 resolution and low-detection benchmark tests,
  E0/E1 diagnostics, EXIF self-check, safety/manual/source-scan tests, and the
  other invariants passed. The three failing test cases were unchanged:
  INV-4 mirror `2.1 pp` over the `0.5 pp` limit; INV-5 quarter-turns
  `3.9/5.1/4.2 pp` for 90/180/270 degrees over `0.5 pp`; and REQ-022 median
  `1.821915 s` / max `2.734323 s` over `0.80/1.50 s`. The result bundle is
  retained on the external SSD; the device/OS identity is recorded in the
  amended simulator status.
- **Documentation guard:** The new REQ-033 consistency test passed on the same
  simulator, checking the recovered full-suite result, the pinned device ID,
  and the evidence table's `FAILING` versus `UNADJUDICATED` vocabulary.

This record predates the E-A/E-B branch repair. Its earlier screenshot count
and timing values remain historical; the post-E-B E7 JSON/Markdown artifacts
are the current benchmark record.

### V6 — Real-fixture L3 screenshot route (pre-E-B snapshot)

- **Question:** Does the app route load each real HEIC fixture, settle through
  the production view model, and render the image and guides together on the
  requested simulator?
- **Run:** `scripts/centering_ui_build_and_shoot.sh` for all ten fixtures on
  iPhone 17 Pro / iOS 26.5
  (`EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86`), with build products and caches on
  the external SSD. The route used the real fixture path and waited for the
  `presentedImageFrame` settle marker before capturing each screen.
- **Harness repairs made during the run:** The simulator shell did not expose
  bare `cat` or `grep` on its PATH, so the route was corrected to use
  `/bin/cat` and `/usr/bin/grep`. The postprocessor was also corrected to accept
  the app's named-corner quad dictionaries as well as the ground-truth point
  arrays. These were evidence-harness defects; the app build had already
  succeeded in both failed attempts.
- **Result:** 10/10 automatic routes completed and produced one uniquely named
  PNG plus one JSON marker each. The final artifacts are 920×2,000 pixels and
  under 1.5 MB each after the deliberate evidence downscale; every marker
  retains `screenScale = 3`, the presented image frame, coordinate mapping,
  detected quads, confidence state, and mapped metric deltas. Three fixtures
  (`IMG_0348`, `IMG_0780`, `IMG_0783`) rendered confident readings and seven
  declined. `IMG_0782` declined with `innerReference = none`, a nil inner quad,
  and no ratios; its screenshot visibly shows the manual guide controls. This
  3-confident/7-declined result predates E-B and is a retained screenshot
  snapshot, not the current default analyzer branch count.
- **Interpretation:** This closes the real-fixture route/capture portion of
  L3. It does **not** close REQ-021: the current postprocessor maps marker
  geometry into the presented SwiftUI frame but does not independently locate
  the colored guide pixels in the downscaled screenshot, and the injected-2 px
  sensitivity check has not run. A screenshot after actually entering manual
  guide values has also not been captured. The screenshot batch predates the
  current rederived-GT accuracy run, which is recorded separately under REQ-027.

### Manual-correction UI interaction attempt

- **Attempt:** Use the simulator's visible guide fields to turn the declined
  IMG_0782 route into a reportable manual reading.
- **Result:** The native Computer Use surface reported that the Mac was locked,
  so no UI action was taken and no manual-correction screenshot is claimed.
  The existing `REQ-017` XCTest still proves the model setters recover a
  declined measurement; the real UI screenshot remains open.

### E7 — Resolution and latency curve (historical bundle plus intermediate snapshot)

- **Change:** Added a DEBUG-only benchmark entry point that changes only the
  analyzer's maximum working dimension, plus a tracked 40-analysis curve
  artifact at `diagnostics/E7/resolution-curve.json` and `.md`. The same
  maximum dimension is used for scalar evidence so the comparison does not
  silently mix a high-resolution Vision pass with a fixed 1,200-pixel profile.
- **Run:** Both E7 benchmark tests were rerun after the REQ-027 GT promotion on the pinned
  iOS 26.5 iPhone 17 Pro simulator. They passed in 330.965 test seconds; the signed result
  bundle is `req027-groundtruth-e7-refresh.xcresult` on the external-SSD artifact path.
  That bundle is the original complete post-REQ-027 run and predates E-REQ044.
- **Artifact-state correction:** The tracked JSON/Markdown files under `diagnostics/E7/` were
  later overwritten while the intermediate transition-width-guard invariant run was executing
  (`revision-e-invariant-class-after-outer-guard-2026-09-12.xcresult`, before the final
  per-side fallback). They are therefore an intermediate snapshot, not the final post-E-REQ044
  benchmark. The original result bundle above remains the authoritative record of the
  pre-E-REQ044 run; a complete post-per-side-fallback curve is still pending.

  **Original signed pre-E-REQ044 bundle:**

  | Max dimension | Median seconds | Max seconds | Confident | Descriptive ratio pass at 2 pp |
  |---:|---:|---:|---:|---:|
  | 1200 | 2.706 | 2.935 | 8/10 | 1/10 |
  | 1600 | 3.852 | 4.639 | 8/10 | 1/10 |
  | 2000 | 5.301 | 6.560 | 8/10 | 1/10 |
  | 2400 | 7.971 | 9.723 | 9/10 | 1/10 |

  **Tracked intermediate snapshot (transition guard, before per-side fallback):**

  | Max dimension | Median seconds | Max seconds | Confident | Descriptive ratio pass at 2 pp |
  |---:|---:|---:|---:|---:|
  | 1200 | 2.733 | 2.972 | 9/10 | 2/10 |
  | 1600 | 3.895 | 4.703 | 7/10 | 1/10 |
  | 2000 | 5.316 | 6.558 | 7/10 | 1/10 |
  | 2400 | 7.974 | 9.748 | 8/10 | 1/10 |

  The ratio counts are comparisons against the rederived GT, but remain
  descriptive rather than closing the broader L1 gate. Both snapshots decline
  IMG_0782 at 1200, 1600, 2000, and 2400. The intermediate low-resolution
  detection/full-resolution refinement files currently report median/max seconds
  of 2.722/2.975, 3.153/3.337, 3.401/3.570, and 3.685/3.861 at those maxima.
  Those files have the same intermediate implementation state and are not a
  post-per-side-fallback result. The low-detection path remains a cost direction,
  not an adopted fix; the original 0.80/1.50-second budget is unmet in every
  retained E7 snapshot.

### E7 profiler availability

- **Attempt:** The iOS ETTrace workflow was checked before relying on wall-clock
  timing. The configured environment does not provide an `ettrace` executable,
  and the repository does not vendor one, so an ETTrace profile could not be
  captured in this run.
- **Result:** E7 uses deterministic XCTest `CFAbsoluteTimeGetCurrent()` timing
  around the public analyzer entry point instead. This is suitable for the
  relative resolution curve and exposes the budget miss, but it is not a
  stack-level ETTrace attribution. The limitation is recorded rather than
  presenting XCTest wall time as an ETTrace result.

## Revision-E architecture decision (documentation-only)

- **Ground-truth status:** REQ-027 is complete. The current
  `analyzer_free_dual_profile_fit_with_visual_adjudication` records are
  non-integral, off the former five-pixel grid, and carry measured
  `agreementPx` values from 0.308 to 4.432 px. Current E7 accuracy failures
  are therefore adjudicable detector evidence. IMG_0783's 4.432 px agreement
  is approximately 1.6x the next-largest record and receives a focused
  re-audit before its exact error magnitude drives a decision.
- **Default product result:** At 1200 px, eight fixtures are confident and two
  decline. Only IMG_0782's correct no-ratio decline has
  `ratioPassAt2PP = true`; none of the eight confident numeric readings meets
  both ratio tolerances.
- **Reference-type result:** The E-A fields are present under each record's
  nested `finalAnalysis` object. All nine records with an inner reference
  report `art_window`, including both scalar-inner paths and all five backs
  whose GT requires `printed_border`; IMG_0782 correctly reports `none`.
  Reference type is not effectively classified.
- **Front-axis result:** IMG_0348 T/B error stays 19.49–22.78 pp and IMG_0780
  T/B stays 21.04–21.18 pp over 1200/1600/2000/2400. IMG_0780 L/R is materially
  closer at 4.97–5.81 pp. This is a repeatable horizontal wrong-feature
  selection, not a sampling-precision defect; candidate telemetry must verify
  whether title/header and type/text-box lines are the exact winners.
- **Resolution-safety result:** IMG_0349 declines at 1600/2000 and becomes
  confident at 2400 with 42.83/39.67 pp errors; IMG_0781 L/R error rises from
  11.70 to 45.37 pp. Resolution is now a confidence-safety input. The current
  implementation is capped provisionally at 1200 until a stability-aware
  selector passes.
- **Holdout status:** The original holdout is development-exposed. All ten
  fixtures have been inspected or repeatedly benchmarked, and E-B included
  holdouts IMG_0349 and IMG_0351. The labels remain chronology only; REQ-040
  requires a fresh capture-condition-diverse frozen holdout.
- **Performance status:** The lowest measured path is already 2.706 s median,
  3.4x the target. Rough profile-loop counts suggest a fixed cost but do not
  prove attribution. Stage-level timing under REQ-041 precedes optimization or
  a budget proposal.
- **Closed experiment class:** Further mean/median, colour/luminance, smoothing,
  centroid/parabolic, normalized-depth/radius, canonical-resampling/rotation,
  upscaling, fixed-offset, or single transition-width experiments are closed.
  They may reopen only after candidate-level evidence shows that the correct
  semantic feature already wins and only placement remains wrong.
- **Next experiment family:** The authoritative plan's REQ-039–REQ-045 defines
  a bounded spike: fresh baseline and holdout, stage timing, candidate recall,
  back-template/semantic front branches, joint selection, stability-aware
  confidence, and a hard zero-confidently-wrong frozen-holdout gate. No
  production code changed as part of this decision record.

## REQ-039 fresh signed full-suite baseline — 2026-09-12

- **Question:** Is the current worktree runnable on the required iOS 26.5
  simulator, and what is the clean full-suite baseline before the perception
  spike?
- **Run:** Direct signed/default `xcodebuild test` from the
  `opus-card-centering-implementation` worktree, scheme `TradingCardScanner`,
  destination iPhone 17 Pro / iOS 26.5 /
  `EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86`. No `CODE_SIGNING_ALLOWED=NO`
  override. DerivedData and the result bundle were placed on the external SSD.
- **Result:** `1088` test cases, `1078` passed, `1` skipped, and `9` failed
  test cases. The console reported `116` assertion failures because several
  failed cases contain multiple assertions. The XCTest session took
  `1037.664 s`; the result-bundle start/finish interval was approximately
  `1092.439 s`.
- **Failure classification:** Eight failed test cases are centering failures:
  the rederived-GT/L1 accuracy test, the front art-window test, the all-fixture
  L1 gate, the portrait art-window test, INV-4, INV-5, INV-7, and REQ-022. The
  ninth is the known `MagicTreatmentTests` nonfoil/plastic label leak, outside
  the centering diff. There were no Keychain `-34018` failures.
- **Passing centering signal:** `CardCenteringAnalyzerTests` passed `21/21`;
  IMG_0782's no-inner-reference decline passed; INV-2, INV-3, INV-6, INV-8,
  INV-9, INV-10, manual recovery, and no-ratio safeguards passed. The E0,
  E-C, E-A, E-B, E-D, and E-E diagnostic cases also passed in the same run.
- **Interpretation:** This satisfies the fresh-baseline portion of REQ-039 and
  confirms the simulator is usable. It leaves REQ-039's focused IMG_0783
  re-audit open and does not alter the revision-E decision to close the
  sampling-level experiment class. Full details are in
  [`baseline-2026-09-12.md`](baseline-2026-09-12.md).

## Open experiments

- **REQ-027 follow-up:** The ground-truth provenance/rederivation gate is
  complete, but the first production-entry-point run against the promoted
  records failed 4 of 12 test cases. Those failures are current accuracy work,
  not a reason to revert to the archived provisional records.
- **E5 (completed; retained as harness evidence):** Rebuilt the EXIF fixture helper from one canonical displayed bitmap,
  inverse-transformed raw pixels with exact-axis UIKit rendering, and wrote PNG
  orientation metadata. The self-check uses a fixed RGBA buffer and passed
  (maximum displayed channel delta 1 on the diagnostic holdout). An interim
  Core Image implementation failed INV-6 for IMG_0783 at 27.3 pp for every
  orientation even though its self-check passed; the identity case was then
  made byte-preserving and the quarter-turn transform directions were
  corrected. The complete INV-6 run over IMG_0348, IMG_0780, and IMG_0783,
  with orientations 1/3/6/8, passed with zero failures. This closes the EXIF
  harness issue; it does not claim the remaining mirror/quarter-turn failures
  are fixed.
- **E7 follow-up:** The separately scoped low-resolution detection/full-resolution
  edge-refinement experiment was refreshed after GT rederivation. Its exact-device
  curve reports 3.660/3.848 s at 2400 working pixels, compared with 7.971/9.723 s
  for the full-resolution detection curve at that point, but still misses the
  original budget. Ratio-error columns are now based on the rederived GT, but the
  broader L1 gate remains failing. Do not revise the 0.80/1.50-second budget
  without an accuracy/resolution decision and explicit agreement.

## REQ-041 — Named stage profile (2026-09-12)

- **Question:** Which analyzer stages account for the 2.706-second minimum-path
  median, and can the cost be attributed before optimization?
- **Test-first contract:** A DEBUG-only diagnostic field and a focused XCTest
  were added first. The red test failed because `stageTimings` was absent. The
  minimal analyzer instrumentation then exposed the nine required stage names
  without changing release behavior or detector decisions.
- **Run:** Signed `xcodebuild test` on iPhone 17 Pro / iOS 26.5 /
  `EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86`, with DerivedData and the result bundle
  on the external SSD. The final diagnostic analyzed all ten development HEIC
  fixtures twice (20 analyses). Bundle:
  `revision-e-req041-profile-retry2-2026-09-12.xcresult`.
- **Result:** The test passed in 54.902 test seconds. Independently measured
  wall-time median/max was `2.7548/3.0003 s`. Named-stage attribution was
  `0.999/0.999` median/max. Median stage cost was scalar fields `1.4909 s`
  (54.6%), inner candidate generation `0.8349 s` (30.0%),
  decode/orientation/downscale `0.2058 s` (7.6%), colour preparation `0.1324 s`
  (4.5%), outer candidate/refinement `0.1180 s` (4.1%), and Vision requests
  `0.0216 s` (0.8%). Joint selection, rectification, and result construction
  were each below `0.0001 s` at the displayed precision.
- **Discarded harness attempt:** A first 30-analysis single-test version
  produced 23 valid timing lines, then the test process received `signal kill`
  while CoreSimulatorService became unavailable. It had no assertion failure
  and no complete artifact, so it is not counted as REQ-041 evidence. The final
  two-pass test stayed below the per-test watchdog and completed all fixtures.
- **Interpretation:** Scalar fields plus inner candidate generation account for
  roughly 85% of median wall time. The lowest-resolution 1200 path still misses
  the original 0.80/1.50-second budget, so the next performance work must reduce
  those measured stages while preserving candidate recall and the 1200 safety
  cap. This closes REQ-041's attribution requirement but does not close REQ-031.
  Records: [`diagnostics/REQ-041/README.md`](diagnostics/REQ-041/README.md).

## REQ-042 — Candidate recall ledger (2026-09-12)

- **Question:** Are the current failures caused by missing candidate evidence or
  by a selector choosing the wrong available visual feature?
- **Test-first step:** A DEBUG-only focused test was added before the producer
  wiring. Its first run failed at the intended assertion because the analyzer
  exposed no candidate ledger. Candidate telemetry was then added as an
  observational reference context; it is not read by production selection.
- **Intermediate discarded build attempts:** The first producer patch tried to
  splice `#if DEBUG` arguments into shared function signatures/calls, which
  Swift rejects syntactically; that compile result was discarded after the
  ledger was moved to a DEBUG-only active reference context. The next compile
  exposed a missing explicit initializer for the DEBUG ledger class; adding the
  initializer produced the green focused test. The corpus harness then had one
  test-only overload-shadowing error in its GT line helper; that was corrected
  without changing analyzer code.
- **Run:** Signed `xcodebuild test` on iPhone 17 Pro / iOS 26.5 /
  `EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86`, using the original HEIC bytes and
  external-SSD DerivedData/result output. The final all-fixture test passed in
  `27.617` seconds and emitted ten ledgers. Candidate totals by fixture were
  `255, 167, 242, 262, 262, 256, 193, 282, 197, 263` in fixture order
  IMG_0347, IMG_0348, IMG_0349, IMG_0350, IMG_0351, IMG_0352, IMG_0780,
  IMG_0781, IMG_0782, IMG_0783.
- **Result:** The analyzer branch was `8 confident / 2 declined`; the five
  sleeved fixtures retained an inner source, IMG_0781 declined for rectification,
  and IMG_0782 correctly retained no inner source. Using the diagnostic's
  preliminary metric—maximum perpendicular distance of every reported candidate
  line point from the corresponding rederived-GT edge, compared with the
  existing GT edge-band tolerance—at least one candidate was within tolerance
  for `34/40` outer edges (`85%`) and `29/36` gradeable inner edges (`80.6%`).
  The seven inner misses are bottom edges on IMG_0348, IMG_0780, IMG_0781, and
  IMG_0783, plus left edges on IMG_0347, IMG_0350, and IMG_0352. The four
  IMG_0782 inner edges are excluded because its ground truth correctly has no
  inner quad. `bestErrorPx` is the best candidate available, not the selected
  candidate, so these seven are generator-recall failures.
- **Interpretation:** This is the first evidence that both mechanisms exist:
  many correct geometric candidates are present but the current role/selector
  does not distinguish them, while six outer and seven gradeable inner edges have
  no candidate within the preliminary tolerance. Inner candidates are mostly
  `untyped_inner_reference` or `unknown_inner_candidate`; the final output's
  universal `art_window` label therefore remains a reporting/semantic defect.
  REQ-042 is not complete, and the next implementation work should name and
  repair deficient generators before tuning joint selection. The closed
  sampling experiment class remains closed.
- **Artifacts:** [`README`](diagnostics/REQ-042/README.md),
  [`candidate-ledger.md`](diagnostics/REQ-042/candidate-ledger.md),
  [`candidate-ledger.json`](diagnostics/REQ-042/candidate-ledger.json), and
 result bundle `revision-e-req042-recall-retry-2026-09-12.xcresult` on the
 external SSD.

## E-REQ044 — Broad-transition outer guard and per-side fallback (2026-09-12)

- **Question:** Can the outer refinement reject broad ambiguous transitions
  without discarding good refinements on the other three edges?
- **Test-first red run:** Added
  'CenteringProfileDumpTests/testREQ044OuterRefinementRejectsBroadAmbiguousTransitions'
  for IMG_0347 and IMG_0350. With the then-current implementation, both
  assertions failed because the broad left-edge transitions were accepted.
  This expected-red run is retained as
  'revision-e-req044-broad-transition-red-2026-09-12.xcresult'.
- **First production change:** Added a general transition-width guard,
  'maximumTransitionWidth = max(12 px, 2% of the card short edge)', alongside
  the existing local-offset guard. The focused red test then passed in
  'revision-e-req044-broad-transition-green-2026-09-12.xcresult' (1 test,
  2 fixture assertions green).
- **Intermediate result:** The first implementation treated any rejected side
  as a reason to discard the complete outer refinement. The focused physical
  outer test then failed on IMG_0347's right edge:
  '13.0348 px' error versus a '10.7449 px' tolerance. This showed that the
  broad left edge was being rejected correctly, but valid sibling refinements
  were being thrown away. That result is retained in
  'revision-e-req044-outer-after-transition-guard-current-2026-09-12.xcresult'.
- **Second production change:** Changed the rejection behavior to be
  per-side. A side that fails the support, median-offset, MAD, or
  transition-width guard retains the original Vision proposal; accepted
  sibling sides continue into the fitted quad. The analyzer returns no
  refinement only when no side is accepted. This remains general and does not
  use fixture names or ground-truth coordinates.
- **Focused green result:** The physical-outer test
  'CardCenteringInvariantTests/testREQ044SelectedOuterTracksPhysicalCardOnDevelopmentBacks'
  passed in 'revision-e-req044-outer-per-side-fallback-2026-09-12.xcresult'
  (1 test, 13.78 s). The broad-transition regression test also remained green.
- **Diagnostic result:** The refreshed E-D outer-refinement dump passed in
  'revision-e-ed-dump-after-transition-guard-2026-09-12.xcresult' (1 test,
  about 27.7 s). It records the broad/low-support left-side rejections while
  retaining good opposite-edge refinements. The current report does not yet
  expose rejected-candidate counts separately from surviving narrow candidates,
  so it is evidence of the decision path, not an accuracy claim.
- **Regression result:** The latest signed
  'CardCenteringAnalyzerTests' run passed '21/21' in 24.326 test seconds on
  the pinned iOS 26.5 iPhone 17 Pro simulator. This includes the sideways,
  skewed, low-contrast, unequal-border, thin-banner, and physical-silhouette
  synthetic cases. The new 21st test is why older 20/20 documentation is
  historical rather than current.
- **Current branch probe:** The refreshed E-A diagnostic passed in
  'revision-e-ea-after-outer-guard-2026-09-12.xcresult' (1 test, about
  27.649 s). The latest post-change branch result is 9 confident / 1
  declined: IMG_0782 declines for missing inner reference; IMG_0781 now
  reaches a confident state. 'outlineHasInner' is mixed across the corpus,
  not false for all ten. All nine non-none outputs still report
  'innerReference = art_window'.
- **Semantic follow-up:** The focused
  'CardCenteringInvariantTests/testREQ043ReferenceTypeIsChosenSemanticallyAcrossDevelopmentCorpus'
  run executed 1 test and failed 5 assertions, exactly the five backs
  (IMG_0347, IMG_0350, IMG_0352, IMG_0781, IMG_0783), each still labelled
  'art_window' instead of 'printed_border'. The result bundle is
  'revision-e-req043-semantic-current-2026-09-12.xcresult' on the external SSD.
  This isolates the remaining semantic defect; no semantic production change was attempted.
- **Scope and decision:** No ground-truth coordinate, tolerance, or ratio
  target changed. The transition-width guard and per-side fallback are a
  narrow outer-geometry experiment, not completion of REQ-044. A full
  invariant/L1 rerun after the final per-side change remains pending, and the
  joint selector, semantic branches, stability-aware confidence, and latency
  gates remain open.
