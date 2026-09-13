# Card Centering — Authoritative Implementation & Validation Plan

**Status:** Contract for a Luna Max *Pursue Goal* run. Written 2026-09-11 from a read-only
investigation plus a measured baseline over the full HEIC corpus; amended 2026-09-12 through
revision E with raw-fixture branch evidence, the safety-preserving E-B repair, the E-D
outer-refinement checkpoint, the E-E classification, the REQ-027 ground-truth rederivation,
and the perception-architecture pivot.
**Investigation author:** Opus; no production code was changed while establishing this plan.
Subsequent implementation changes and experiment provenance are recorded in the status and
evidence sections below.
**Baseline evidence:** `review/centering-evidence/baseline-2026-09-11/`

> Luna: read §0–§8 before writing code. §9 (REQ table) is the contract. §13 (Definition of
> Done) is the completion gate and was fixed **before** implementation began; it may not be
> weakened during implementation. If a requirement proves wrong, stop and escalate — do not
> silently retarget it.

---

## 0.0 STATUS — read this first (amended 2026-09-12, revision E decision)

**The plan below is unchanged in intent. Revision B added what the first implementation
run measured and seven requirements (`REQ-027`–`REQ-033`); revision C added five measured
follow-up requirements (`REQ-034`–`REQ-038`); revision D recorded the REQ-027 ground-truth
rederivation and its first adjudicable production-entry-point result; revision E closes the
sampling-level experiment class and replaces further local detector tuning with a bounded
perception-architecture spike (`REQ-039`–`REQ-045`).** No existing
tolerance has been loosened, renumbered, or waived. `REQ-031` is the one place a target may
move, and only on written evidence.

**Where the work stands.** The reusable geometry/product architecture landed and is sound:
quad geometry, rectification with residuals, explicit coordinate mapping, confidence/decline
state, manual adjustment, and both rendering fixes are genuinely implemented. The
**perception architecture is not validated**: Vision/nested-quad proposals, outer-edge
arbitration, and the generic inner profile do not reliably identify the physical card edge or
the face-appropriate gradeable reference. They are retained as the measured baseline for the
revision-E spike, not described as complete architecture.
The evidence half is now partially exercised: the E0 diagnostic, the named raw-HEIC E-C
replacement, the E5 EXIF self-check, focused XCTest runs, the E7 resolution curves, the
guarded E-D outer-refinement experiment, the post-refinement E-E per-edge diagnostic, all ten
real-fixture app-route screenshots, and the REQ-027 analyzer-free ground-truth rederivation
are retained. Independent screenshot-pixel measurement, the injected-offset sensitivity
check, and the manual-correction screenshot are still not complete.

**Historical full-suite result before E-A/E-B/E-D, iPhone 17 Pro / iOS 26.5 /
`EB1F0EB1-…`, 294 s:**

```
1076 tests · 1045 passed · 24 failed · 7 skipped   ** TEST FAILED **
    6 keychain  (storeFailed -34018) — harness artifact, see §12.1, not counted
    1 MagicTreatment label leak      — pre-existing, outside this branch's diff
   17 genuine centering failures     — see §3.5
```

**Current blocking items:**

1. **Adjudicated production accuracy failures** (`REQ-001`, `REQ-025`, `REQ-027`). The
   ground-truth provenance gate is complete: all ten records were rederived by two independent
   analyzer-free profile passes, visually adjudicated against the physical silhouette, and
   validated for aspect, agreement, non-integral coordinates, and exact ambiguity metadata.
   The first current production-entry-point run against that rederived set executed 12 tests:
   8 passed and 4 failed. The failing test cases are the holdout ratio helper (IMG_0349,
   IMG_0783, IMG_0351), the IMG_0780 art-window ratio check, the all-fixture L1 gate (with
   outer/inner geometry, ratio, and reference-selection failures), and the IMG_0348
   portrait-art-window check. The result bundle is
   `req027-ground-truth-after-rederive.xcresult` on the external SSD. The more direct E7
   product result is stronger: at 1200 px the analyzer returns 8 confident and 2 declined, but
   `ratioPassAt2PP` is 1/10, and the sole pass is IMG_0782's correct no-ratio decline. Thus
   **0/8 confident numeric readings meet both ratio tolerances** at the default resolution.
   These are now adjudicable detector failures, subject only to the explicit IMG_0783
   re-audit below; they are not provisional-GT disputes.
2. **Residual metamorphic drift** (`REQ-029`): the current post-E-D targeted run reports
   mirror `1.4 pp`, quarter-turn `0.7/1.4/1.1 pp` at 90/180/270 degrees, scale `1.4 pp`,
   and benign-crop `1.1 pp`, all above their limits. The roll-preservation repair restored
   INV-3 and the guarded refinement preserved the legacy analyzer class, but E-D did not
   close the resampling/geometry invariants. E-E classifies the residual as both outer-line
   motion and profile depth selection; it does not justify another unmeasured tuning change.
3. **Latency and resolution safety** (`REQ-031`, `REQ-041`): the refreshed post-REQ-027 E7 curve measures `2.706/2.935 s`
   median/max at 1200 px, rising to `7.971/9.723 s` at 2400 px, against `0.80/1.50 s`.
   The refreshed low-detection/full-resolution-refinement curve measures `3.660/3.848 s` at
   2400 px. The lowest measured resolution is already 3.4x over the median budget, so reducing
   image dimensions alone cannot close the gap. Higher resolution also changes branch outcomes:
   IMG_0349 declines at 1600/2000, then becomes confident at 2400 with 42.83/39.67 pp errors;
   IMG_0781's LR error grows 11.70 -> 27.17 -> 44.04 -> 45.37 pp. A stage-level profile is
   required before redesign, and 1200 is the provisional safety cap. No budget revision has
   been agreed.
4. **L3/REQ-021 and device-only evidence** remain incomplete. All ten real-fixture app routes
   now produced screenshot/metadata pairs on the pinned simulator, including a declined
   IMG_0782 case. Independent screenshot-pixel measurement, the injected 2 px sensitivity check,
   a manually corrected screenshot, and the physical-device gates still need execution.

5. **Raw-fixture branch availability is repaired but the broader gate remains open**
   (`REQ-034`, `REQ-035`). The raw HEIC branch diagnostic found scalar pinning behind the
   five sleeved declines. The retained E-B repair now yields 8 confident and 2 declined
   fixtures at the default 1200-pixel path; `IMG_0781` declines for rectification and
   `IMG_0782` declines for missing inner reference. The refreshed post-REQ-027 E7 artifacts show
   IMG_0782 declined at 1200/1600/2000/2400 in both benchmark curves. This benchmark confirms
   the safety behavior at all four tested
   maxima. This is availability/safety evidence; the current rederived-GT L1 run still has
   implementation failures to resolve.
6. **The old E0/E1 metamorphic measurements remain diagnostic-only** (`REQ-036`). E0 and
   historical E1 start from a 900x1200 pre-downsampled bitmap and their drift numbers must not
   drive detector tuning. E-C now starts from the original HEIC bytes, retains raw/equalized
   records, and passes the ±0.5% effective-resolution construction check for IMG_0783 and
   IMG_0347. It exposes a reproducible IMG_0347 rot90/rot270 decline at matched resolution,
   but does not close INV-5 or replace the current production-entry-point accuracy result.

7. **Reference type is not being classified** (`REQ-012`, `REQ-039`, `REQ-043`). The E-A
   artifact stores its requested branch fields under each record's `finalAnalysis` object:
   `outlineHasInner`, `scalarOuterAgreesWithVision`, `scalarPinned`, and `innerSource` are all
   present for 10/10 records. It also shows `innerReference = art_window` for all nine records
   that carry any inner reference, including both scalar-inner results and all five card backs whose GT requires
   `printed_border`. The artifact is complete for its branch-diagnostic purpose, but it proves
   that `innerReference` is currently a default/reporting value rather than a successful
   reference-type decision.

8. **The original HOLDOUT is development-exposed** (`REQ-002`, `REQ-040`). All ten fixtures
   have been inspected, profiled, visually adjudicated, and used in repeated benchmark runs;
   the five-sleeved E-B work included holdouts IMG_0349 and IMG_0351. The old TUNE/HOLDOUT labels
   remain useful chronology, but they can no longer measure generalisation. A new holdout must
   vary photographer/background/lens/session and be frozen before the revision-E spike.

**Revision-E decision.** Sampling-level work is closed as an experiment class. Mean/median,
luminance scoring, smoothing, centroid/parabolic refinement, normalized depth/radius,
canonical resampling/rotation, upscaling, and additional local offset/transition-width gates
may not be reopened without new candidate-level evidence showing that the correct semantic
edge is already selected and only its subpixel placement is wrong. The next work is a bounded
candidate-generation, semantic-reference, joint-selection, confidence, and performance spike
under `REQ-039`–`REQ-045`.

The focused analyzer regression class is now 20/20, including sideways/skewed legacy coverage,
and the no-inner-reference safety assertion passes for IMG_0782 at the default path. The
two exact REQ-028 regression tests were also rerun under the correct XCTest class on the
pinned iOS 26.5 simulator and passed 2/2; the earlier incorrectly filtered 0-test invocation
is discarded. The
guarded E-D acceptance test also passes on raw IMG_0783. In the current post-roll targeted
invariant run, INV-3 passes while INV-4, INV-5, INV-7, and INV-8 remain above tolerance; the
run executed 25 tests with six assertion failures. E-E's post-refinement diagnostic also
passes, with 24 variant/space snapshots and 96 per-edge records. E-C's
raw/equalized harness test also passes, with its twelve records retained under
`review/centering-evidence/diagnostics/E1/resolution.json`.

**The simulator is not blocked.** `CoreSimulatorService` had transiently died; a fresh
`xcrun simctl list devices` recovers it. `review/centering-evidence/after/simulator-status-2026-09-11.md`
now records both the transient interruption and the recovered runs (`REQ-033`).

### Amendment log

| Rev | Date | Change |
|---|---|---|
| A | 2026-09-11 | Original contract, 26 requirements, written from the pre-implementation baseline. |
| B | 2026-09-11 | Added §3.5 (measured after-run), §4.1 (RC-11…RC-15), §5.2 (adjudication and latency-decision rules), Group H (`REQ-027`–`REQ-033`), §12.1 (environment facts), and revised §13. No tolerance loosened. |
| B-evidence | 2026-09-11 | Recorded E0–E7 results, corrected RC-12 from an unproven discrete-argmax diagnosis to the measured axis/scale parameterization problem, and amended simulator/evidence status after the recovered iOS 26.5 run. No tolerance loosened. |
| B-evidence-2 | 2026-09-11 | Captured all ten real-fixture app routes on the pinned iOS 26.5 simulator, repaired the evidence harness's simulator-shell/quad-shape assumptions, and recorded the remaining screenshot-pixel/manual-correction gaps. No tolerance loosened. |
| C | 2026-09-12 | Added REQ-034–REQ-038 after raw-HEIC E-A diagnosis; recorded the scalar-pinned branch, the unsafe global coverage experiment and its reversion, and the passing shape-gated E-B repair. Corrected E0/E1's pre-downsample/resolution confound. No tolerance loosened. |
| C-doc | 2026-09-12 | Reconciled the evidence/status documents with the post-E-B E7 artifacts, labeled the 3/7 screenshot capture as pre-E-B, and recorded the then-current higher-resolution IMG_0782 result. This is historical and was superseded by the post-roll E7 rerun; no tolerance loosened. |
| C-doc-2 | 2026-09-12 | Marked earlier whole-repository and trust-hardening documents as historical snapshots, updated README/progress/audit pointers, and removed stale “current” wording from those records. No implementation or acceptance change. |
| C-E-C | 2026-09-12 | Replaced the pre-downsampled E1 measurement with the raw-HEIC/equalized E-C harness for IMG_0783 and IMG_0347; retained raw and equalized records and documented the matched-resolution IMG_0347 quarter-turn declines. No production or ground-truth change. |
| C-E-D | 2026-09-12 | Added and measured the deterministic outer-edge refinement. The initial unconstrained fit regressed eight legacy assertions; a local-offset guard restored the 20/20 analyzer class, and preserving the proposal roll restored INV-3. The current targeted run still fails INV-4/5/7/8; no tolerance was loosened and no GT was used. |
| C-E-E | 2026-09-12 | Added and ran the post-refinement raw/equalized per-edge profile diagnostic: 24 snapshots and 96 records passed. Raw/equalized records matched at the 1200-pixel cap; the residual was classified as both outer-line displacement and profile depth selection. No production tuning or GT change followed. |
| C-REQ-028 | 2026-09-12 | Reran the exact sideways/skewed regression tests under the correct XCTest class on the pinned iOS 26.5 simulator; 2/2 passed. The earlier 0-test filter was discarded. No tolerance changed. |
| D-REQ-027 | 2026-09-12 | Re-derived all ten GT records with two analyzer-free profile passes plus visual physical-silhouette adjudication; promoted non-integral records, regenerated overlays and diagnostics, and validated 10/10. The first current 12-test production-entry-point run passed 8 and failed 4 accuracy test cases; no tolerance or detector behavior changed. |
| E | 2026-09-12 | Recorded REQ-027 complete and the adjudicable E7 result (0/8 confident numeric readings within both ratio tolerances at 1200); documented universal `art_window` reporting whenever any inner reference is present, the resolution-invariant front T/B wrong-feature signature, higher-resolution safety regressions, development exposure of the old holdout, and the need for stage-level profiling. Closed the sampling-level experiment class and added the bounded perception-architecture spike `REQ-039`–`REQ-045`. No tolerance loosened. |


---

## 0. What "centering" means in this repository

This is not a "place the card in the middle of the screen" feature. `Tab: Centering` is a
**card-centering grading tool**. It answers the question a grader asks: *given the physical
card's cut edge (outer) and the printed frame inside it (inner), what is the
left/right and top/bottom border ratio?* — e.g. `52.3 / 47.7`.

The brief's metric vocabulary maps onto this pipeline as follows, and this mapping is
binding for the rest of the document:

| Brief's term | This repository |
|---|---|
| detection accuracy | is a card found at all, and is the found object the card (not the sleeve, not a sub-region) |
| corner/edge localization | position of the four **outer** cut edges (and their virtual corners) |
| estimated card center | midpoint of the outer quadrilateral |
| rotation/orientation | EXIF orientation + in-plane skew of the card |
| perspective normalization | rectification of the card quad to a fronto-parallel rectangle |
| **final rendered centering** | guide lines drawn on screen/export landing on the geometry that was decided |
| **crop/margin symmetry** | the L/R and T/B border ratios — the product's actual output |
| stability/repeatability | invariance of the ratio under rotation, mirroring, and re-runs |

There is **no crop stage and no scale-to-fit stage** in the current product. `REQ-016`
introduces rectification; it does not introduce a user-facing crop. Do not add one.

---

## 1. Baseline architecture at plan authoring

### 1.1 Files and symbols in scope

| File | Role |
|---|---|
| `TradingCardScanner/Services/CardCenteringAnalyzer.swift` (826 L) | the whole detector: `analyze(_:rotationDegrees:)`, `prepare`, `cardOutline`, `verticalSilhouetteEdges`, `borderEnd`, `chooseInner`, `candidates`, `slope`, `longestRun`, `rgbToLab` |
| `TradingCardScanner/Models/CardCenteringMeasurement.swift` (59 L) | `CardCenteringEdges` (4 `Int`s), `CardCenteringMeasurement`, `refreshWarnings`, ratio formatting |
| `TradingCardScanner/Views/CardCenteringView.swift` (706 L) | `CardCenteringViewModel` (3 input paths, manual guide/rotation editing), `CardCenteringImage` (on-screen guide overlay) |
| `TradingCardScanner/Views/CenteringCameraView.swift` (376 L) | `CenteringCameraController` — capture session, lens selection, level indicator |
| `TradingCardScanner/Services/CardCenteringExport.swift` (396 L) | `render(image:measurement:rotationDegrees:)`, `drawGuides`, `filename(for:)` |
| `TradingCardScannerTests/CenteringExportTests.swift` (538 L) | 27 tests, **all on synthetic flat-colour rectangles** |
| `TradingCardScannerTests/UncoveredSurfaceTests.swift` | `CardCenteringSurfaceTests` — export plumbing only |
| `scripts/ui_build_and_shoot.sh`, `scripts/ui_screenshot_simctl.sh` | existing screenshot harness (writes one overwritten file into gitignored `artifacts/`) |

### 1.2 The pipeline, end to end

All three input paths converge on one entry point — this is a genuine strength:

```
PhotosPicker  ─ loadTransferable(Data) ─┐
File importer ─ Data(contentsOf:)      ─┼─→ CardCenteringViewModel.analyze(Data)
Camera        ─ photo.fileData…()      ─┘        │
                                                 ▼
                        CardCenteringAnalyzer.analyze(data, rotationDegrees: 0)
                                                 │
   prepare(): UIImage(data:) → image.size (EXIF-corrected) → downscale to max 1200px
              → optional rotation into an enlarged canvas padded with ring-median colour
                                                 │
   pixels() → sRGB → CIE Lab (per-pixel, pure Swift)
                                                 │
   gx / gy  : full-image ΔE gradient fields
                                                 │
   cardOutline(): ring-median background → per-pixel ΔE threshold → per-column and
                  per-row foreground counts → longestRun(≥60 % of peak) → bounding box
                  + skew from least-squares dx/dy of firstForeground / lastForeground
                                                 │
   if |skew| ∈ [0.35°, 25°] → RE-RENDER rotated and RE-RUN the entire analysis once
                                                 │
   outer = outline.edges  ?? (gradient-candidate + silhouette fallback)
   inner = borderEnd(side:) ?? chooseInner(side:)   — per side, independently
                                                 │
   CardCenteringMeasurement{ outer, inner, warnings, detectionNotes }
                                                 │
   CardCenteringImage (screen)  /  CardCenteringExport.render (PNG)
```

### 1.3 Facts established by inspection

- **The geometry model is four axis-aligned scalars.** `CardCenteringEdges { left, top, right,
  bottom: Int }`. There are no corners, no quadrilateral, no homography. `grep VNDetect` finds
  rectangle detection only in the *scanner* feature; the centering feature uses none.
- **Perspective is detected but never corrected.** `cardOutline` computes `edgesAreParallel` and,
  when false, emits a warning string. Nothing rectifies.
- **EXIF orientation is handled correctly.** `prepare` uses `image.size` and `image.draw(in:)`,
  both orientation-aware; the baseline run confirms all ten landscape-stored fixtures emerge
  portrait. This is one of the few parts that needs no change.
- **Working resolution is capped at 1200 px on the long edge.** All reported guide coordinates
  are in that space; the native capture is 3024 × 4032, so 1 working px ≈ 3.36 native px.
- **Skew correction re-runs the whole analysis**, doubling an already-expensive pass.
- **The camera path always prefers the ultra-wide** (`CameraCapabilities.hasMacroLens()
  ? .builtInUltraWideCamera : .builtInWideAngleCamera`) at `minAvailableVideoZoomFactor`, with
  **no geometric distortion correction enabled** and no user lens choice.
- **Zero real-photograph test coverage.** No test references `TestFixtures/`; the fixtures are
  not members of any Xcode target.

### 1.4 Current implementation checkpoint (2026-09-12)

The table and facts above are the pre-implementation baseline. They must not be read as a
description of the current tree. The current implementation now has ordered quadrilateral
geometry, Vision rectangle proposals with nested sleeve/card selection, explicit working/native
coordinate mapping, rectification residuals, confidence/decline state, and rotation-synchronized
screen/export guides. The real-fixture test target and review artifacts are present.

The current branch-specific evidence is deliberately recorded separately: the default raw-HEIC
E-A/E-B run yields 8 confident and 2 declined fixtures, while the captured screenshot batch was
made before E-B and still shows 3 confident and 7 declined. Neither count is by itself an
accuracy pass. The rederived GT and current production-entry-point accuracy result are recorded
under REQ-027. See §3.6 and
`review/centering-evidence/experiments-log.md`.

---

## 2. The fixture corpus, characterised

`TestFixtures/TradingCards/HEIC` — **10 images**, all `4032 × 3024` stored,
**all EXIF orientation = 6** (displayed 3024 × 4032 portrait), all iPhone 15 Pro Max,
all `2.22 mm f/2.2` (the ultra-wide) with `FocalLenIn35mmFilm = 24–25`.

> That combination — physical ultra-wide at a 24 mm-equivalent field of view — is the
> signature of **Apple's system macro mode**, which crops the ultra-wide and applies Apple's
> own geometric distortion correction. **Every fixture is a macro capture made by Camera.app,
> not by this app.** See §7.3; this is a material coverage gap, not a detail.

| Fixture | Subject | Face | Notable conditions |
|---|---|---|---|
| IMG_0347 | Pokémon card back | back | sleeve, soft shadow, pale-on-pale left edge |
| IMG_0348 | Charmander full-art | front | foil glare across the whole card |
| IMG_0349 | Zapdos ex full-art | front | heavy foil glare, sleeve |
| IMG_0350 | Pokémon card back | back | sleeve, pronounced corner shadow |
| IMG_0351 | Clefairy ex full-art | front | foil, sleeve |
| IMG_0352 | Pokémon card back | back | sleeve |
| IMG_0780 | MTG *Starting Town* | front | borderless-ish full-art frame |
| IMG_0781 | MTG card back | back | high-contrast black edge on white |
| IMG_0782 | MTG *Walls of Ba Sing Se* | front | **light-grey text box** — breaks the mask |
| IMG_0783 | MTG card back | back | high-contrast black edge |

**Composition risks the plan must absorb:** 5 of 10 are **card backs** (no artwork window, so
the "inner frame" concept differs); ≥6 are **sleeved**; 0 are non-iPhone / flatbed / web
images; 0 are normal-lens captures; 0 are graded slabs; all share one background (white paper)
and one photographer. A detector tuned only on this set will overfit — see `REQ-002`.

---

## 3. Measured baseline (the contract's "before")

Reproduced with the **unmodified production `CardCenteringAnalyzer`** compiled for the iOS
simulator and run over all ten fixtures.
Harness: `review/centering-harness/` · Raw output: `review/centering-evidence/baseline-2026-09-11/`

### 3.1 Per-fixture result

| Fixture | working px | detected outer (l,t,r,b) | box w×h | aspect | L,R,T,B border | auto-rot | flagged |
|---|---|---|---|---|---|---|---|
| IMG_0347 | 927×1220 | 49, 59, 848, 1136 | 799×1077 | 0.742 | 27, 82, 39, 11 | +1.25° | ⚠︎ |
| IMG_0348 | 939×1229 | 58, 60, 873, 1165 | 815×1105 | 0.738 | 23, 29, 21, 28 | +1.86° | — |
| IMG_0349 | 919×1214 | 50, 22, 849, 1166 | 799×1144 | 0.698 | 8, 29, 82, 11 | +0.89° | ⚠︎ |
| IMG_0350 | 915×1212 | 21, 47, 858, 1168 | 837×1121 | 0.747 | 31, 48, **155**, 11 | −0.72° | ⚠︎ |
| IMG_0351 | 900×1200 | 55, 57, 826, 1156 | 771×1099 | 0.702 | 9, 29, 25, 11 | 0.00° | ⚠︎ |
| IMG_0352 | 915×1212 | 38, 85, 846, 1164 | 808×1079 | 0.749 | 27, 43, 41, 11 | +0.71° | ⚠︎ |
| IMG_0780 | 923×1218 | 60, 56, 859, 1206 | 799×1150 | 0.695 | 28, 9, 29, 44 | +1.10° | — |
| IMG_0781 | 918×1214 | 64, 62, 856, 1168 | 792×1106 | 0.716 | 37, 39, 42, 72 | +0.84° | — |
| IMG_0782 | 909×1207 | 54, 39, 846, **661** | 792×**622** | **1.273** | 49, 61, 37, 6 | +0.40° | ⚠︎ |
| IMG_0783 | 900×1200 | 53, 55, 847, 1161 | 794×1106 | 0.718 | 41, 37, 42, **102** | 0.00° | — |

- **6 / 10 raise a detection note.** Latency **1.8 – 3.8 s** per image.
- Detected aspect ranges **0.695 – 0.749** (excluding 0782). A true card is 0.714 and a sleeve
  ≈ 0.72. A ±4 % spread proves the detector is **not landing on a consistent physical boundary**.
- `B = 11` on five fixtures is `minY = round(cardHeight × 0.01)` — the inner-bottom search
  terminated at its own first step on half the corpus.

### 3.2 Metamorphic behaviour (`metamorphic.csv`, 60 analyses)

| Invariant | Expected | Measured |
|---|---|---|
| ±3° rotation → same ratio | ≈ 0 pp change | **median LR swing 16.6 pp, median TB swing 18.6 pp, max 63.1 pp** |
| Mirror X → LR complements, TB identical | 0 pp | median 1.3 pp, **max 13.0 pp** (IMG_0350) |
| 180° → LR and TB both complement | 0 pp | up to **16.5 pp** (IMG_0347 LR) |
| auto-skew recovers an applied +3° | ≈ −3.0° | **0.00° on 5/10 fixtures**; −0.60° to −2.28° on the rest |
| auto-skew is symmetric (+3 vs −3) | equal magnitude | IMG_0347: −2.18° vs +1.04°; IMG_0350: −2.28° vs +0.70° |
| detection note correlates with error | — | **anti-correlated at least once**: IMG_0347 @ −3° reports "clean" while returning TB 16.1 vs 78.0 at base |

**65 % of all 60 analyses raise a detection note.** The existing note is not a usable
confidence signal: it fires on most good results and stays silent on at least one catastrophic one.

### 3.3 The dominant failure, proven numerically

Horizontal luminance profile across IMG_0347 at mid-card (80-row average, working resolution):

```
x      39   43   47   51   55   59   63   67   71   75   79   83
value 234  231  224  210  191  179  179  175  173  170   15   16
                      ▲                              ▲
             detected outer.left = 49        detected inner.left = 76
```

- `234 → 170` over x≈47…75 is the **paper → shadow → translucent sleeve** ramp.
- `170 → 15` at x = 76–77 is a **hard step: the card's actual cut edge**.

The detector labelled the **sleeve/shadow boundary as the card's outer edge** and the **card's
own edge as the "inner printed frame."** IMG_0350 is identical (`210 → 20` step at x = 52,
detected outer.left = 21). The reported "27 px left border" is the sleeve offset, not a border.
Visual confirmation: `review/centering-evidence/baseline-2026-09-11/corner_zoom.png`.

### 3.4 Edge ambiguity, measured (this sets every tolerance below)

10–90 % transition width across the detected left edge, working resolution:

| Fixture | condition | 10–90 % rise | contrast |
|---|---|---|---|
| IMG_0781 | black card edge on white paper | **1 px** | 240/255 |
| IMG_0780 | black card edge on white paper | **2 px** | 243/255 |
| IMG_0347 | pale sleeve + shadow on white paper | **14 px** | 58/255 |

Edge localisability is content-dependent and spans an order of magnitude. §5.1 turns this into
the tolerance policy rather than picking a round number.

### 3.5 Measured "after" run — 2026-09-11 (revision B, pre-E-A/E-B snapshot)

Same production entry point, same pinned simulator. **17 genuine centering failures.**
This subsection is a retained historical snapshot: its fixture accuracy comparisons used the
then-current provisional five-pixel-grid references. The current rederived-GT accuracy result is
recorded under REQ-027 and must be used for present adjudication.

**(a) Ten of the 27 retained legacy synthetic tests now fail.** DoD-11 required them retained
*and still passing*. They were retained; they are red.

```
testACardPhotographedSidewaysIsStillFound        borders (0,0,0,0)  vs (25,20,55,60)
testStraightensASkewedCardBeforeMeasuring        borders (0,0,0,0)  vs (20,25,60,55)
testRecoversBordersWhenTheCardFillsTheFrame           (14,20,56,50) vs (20,25,60,55)
testRecoversBordersWhenTheOuterEdgeIsLowContrast      (14,20,56,50) vs (20,25,60,55)
testArtworkDetailDoesNotDisplaceTheInnerGuides        (14,19,48,50) vs (20,25,60,55)
testFaintBorderIsFollowedPastLouderArtwork            (31,82,31,31) vs (40,40,40,40)
testUnequalBordersAreEachMeasuredOnTheirOwnEvidence   (11,15,70,66) vs (15,20,75,70)
testOneOddBorderIsNotPulledTowardTheOthers            (11,11,10,66) vs (15,15,15,70)
testArtworkBannerDoesNotWinOverAThinBorder            (50, 5,50,51) vs (60,15,60,60)
testVerticalOuterEdgesUsePhysicalSilhouette           inner.left 35 vs 67
```

Two are total detection failure. The remaining eight share one signature — **every border is
~5–6 px short, on both axes, in the same direction.** Treat that as one defect, not eight.

**(b) Safety gate fails.** `testMaskFailureDeclinesWithoutAnInnerReference` — IMG_0782 does
not decline. Meanwhile `confidentCount >= 8` *passed* while IMG_0349 was `confident` with a
60.3 px right-edge error against a 24.0 px tolerance. **"Confident" and "wrong" co-occurred**,
which is the one thing `REQ-018` exists to prevent.

**(c) The worst-failing edge is the one the ground-truth audit already flagged.**

```
L1 assertion      : IMG_0349 outer right edge error 60.3 px  (tolerance 24.0 px)
independent probe : IMG_0349 GT right edge sits ~+65 px outside the luminance step
```

Those agreeing at ~60 px is not coincidence. The likelier reading is that **the detector is
near the true edge and the reference is wrong there.** Right-edge ground truth is biased
outward on 10/10 fixtures (median ≈ +22 px). This is why `REQ-033` forbids closing accuracy
failures against provisional ground truth.

**(d) Remaining numeric failures.**

| Test | Measured | Required |
|---|---|---|
| Holdout GT ratio, IMG_0349 | 54.69 | 48.6 ± 2.0 pp |
| Art window not replaced by printed border, IMG_0780 | 48.1 | 53.7 ± 2.0 pp |
| Portrait front art window, IMG_0348 | 49.8 | 57.8 ± 2.0 pp |
| INV-3 skew, IMG_0348 @ −3° | −2.468° | −3.0 ± 0.25° |
| REQ-022 median latency | **1.99 s** (focused run 1.85 s median / 2.16 s max) | ≤ 0.80 s / ≤ 1.50 s |

**(e) Focused `CardCenteringInvariantTests`** — 10 pass, 5 fail:

| Invariant | Measured | Limit |
|---|---|---|
| INV-4 mirror | LR ≈ 1.8 pp, TB ≈ 0.6 pp | 0.5 pp |
| INV-5 quarter turns | ≈ 3.4 / 4.0 / 4.8 pp | 0.5 pp |
| INV-6 EXIF equivalence | several large mismatches | 0.5 pp |
| INV-7 scale @ 0.6× | ≈ 1.8 pp | 1.0 pp |
| REQ-022 latency | above budget | — |

INV-3 is real progress against the baseline (which recovered 0.00–2.28° of an applied 3°;
now 2.468°) but still outside tolerance.

### 3.6 Current raw-fixture branch result — 2026-09-12 (revision C)

The following is the current default-resolution analyzer result after E-A and the retained
shape-gated E-B repair. It is not a replacement for the pre-E-B screenshot capture in §3.5.
It is availability/branch evidence; the separate REQ-027 run records accuracy against the
rederived ground truth.

| Fixture | State | Inner source | Scalar pinned | Scalar/Vision agree | Current reason |
|---|---|---|---:|---:|---|
| IMG_0347 | confident | profile | yes | no | — |
| IMG_0348 | confident | scalarInner | no | no | — |
| IMG_0349 | confident | profile | yes | yes | — |
| IMG_0350 | confident | profile | yes | no | — |
| IMG_0351 | confident | profile | yes | yes | — |
| IMG_0352 | confident | profile | yes | no | — |
| IMG_0780 | confident | profile | no | no | — |
| IMG_0781 | declined | scalarInner | no | no | rectification failure |
| IMG_0782 | declined | none | yes | no | missing inner reference |
| IMG_0783 | confident | profile | no | yes | — |

`outlineHasInner` was false for all ten raw fixtures. The five sleeved initial decliners all had
scalar pinning, but IMG_0349 and IMG_0351 also had scalar/Vision agreement, so the 2% agreement
predicate was not sufficient to explain the original decline pattern. Running the profile from
the selected Vision outer recovered two fixtures; the final shape-gated coverage rule recovered
the remaining three without making the malformed IMG_0782 candidate confident at the default
1200-pixel path.

The diagnostic fields above are nested under each JSON record's `finalAnalysis` object, not at
the record root. All four requested fields are present for 10/10 records. The same records expose
a stronger semantic defect: **all nine records with any inner reference report
`innerReference = art_window`**, including the two `scalarInner` paths and all five card backs
whose GT reference is `printed_border`; IMG_0782 correctly reports `none`. Availability was
repaired, but reference-type classification was not implemented successfully.

The refreshed post-REQ-027 E7 resolution artifacts add an important qualification: IMG_0782 declines
at 1200, 1600, 2000, and 2400 pixels in both the full-resolution and low-detection curves.
The default focused assertion and this benchmark safety check both pass; broader supported-mode
and accuracy closure remain open under REQ-035.

### 3.7 Adjudicable accuracy and resolution signature — 2026-09-12 (revision E)

REQ-027 is complete, so the E7 comparisons against the current records are detector evidence,
not provisional-reference disputes. At the default 1200-pixel path, eight fixtures are confident
and two decline; `ratioPassAt2PP` is true only for IMG_0782's required no-ratio decline. None of
the eight confident numeric readings meets both ratio tolerances.

The two front art-window failures show a resolution-invariant, axis-specific signature:

| Fixture / metric | 1200 | 1600 | 2000 | 2400 | Interpretation |
|---|---:|---:|---:|---:|---|
| IMG_0348 T/B error | 19.49 pp | 22.48 pp | 22.18 pp | 22.78 pp | deterministic wrong T/B feature |
| IMG_0780 T/B error | 21.12 pp | 21.04 pp | 21.04 pp | 21.18 pp | deterministic wrong T/B feature |
| IMG_0780 L/R error | 5.62 pp | 4.97 pp | 5.81 pp | 5.46 pp | materially closer than T/B, but still failing |

This is not a subpixel-precision problem. On these fronts, the selected left/right transitions
are materially closer to the reviewed art-window geometry while top/bottom reproducibly select
another printed transition, consistent with competition from title/header and type/text-box
boundaries. Candidate-level evidence must verify the exact winner before implementation, but
sampling density and interpolation are not plausible primary fixes.

Higher resolution is also a safety failure, not merely a cost trade. IMG_0349 declines at 1600
and 2000, then becomes confident at 2400 with 42.83/39.67 pp error; IMG_0781's L/R error rises
from 11.70 to 45.37 pp over the same sweep. Until a stability-aware selector is validated,
production analysis must not exceed the 1200-pixel safety cap.

One GT caveat remains explicitly scoped: IMG_0783 has `agreementPx = 4.43`, about 1.6x the next
largest record, and also reports large detector errors. Re-audit that record's selected outer
and printed-border transitions before using its exact error magnitude to tune or reject a
candidate. This does not make the overall 0/8 confident-numeric result unadjudicated.


---

## 4. Root causes

Ordered by how many fixtures they explain. Fixture-specific hacks are forbidden (`REQ-024`);
each of these is a general mechanism.

**RC-1 — The geometry model cannot represent a photographed card.**
Four axis-aligned scalars describe a rectangle. A hand-held photo of a card is a *quadrilateral*:
in-plane rotation plus out-of-plane tilt. Every downstream stage (`borderEnd`'s column/row
sampling, `verticalScores`' whole-column averaging, the guide overlay) assumes edges are axis
aligned. With 2° of skew a border transition smears over ~22 px of a 1100 px card, which is why
the inner search collapses. **Explains: rotation instability (all 10), inner-guide failure (≥6).**

**RC-2 — Sleeve/shadow is indistinguishable from card in the current outer model.**
`cardOutline` takes the *first* deviation from ring-median background. A translucent sleeve and
its cast shadow deviate before the card does. There is no notion of "two concentric boundaries;
pick the card." **Explains: the 0.695–0.749 aspect spread and the wrong absolute ratios on ≥6 fixtures.**

**RC-3 — The foreground mask has no shape or connectivity constraint.**
`longestRun(counts, ≥60 % of peak)` is computed independently on column sums and row sums. A
light region *inside* the card (IMG_0782's grey text box) drops the row count below threshold
and truncates the card at the artwork boundary — producing a 1.273-aspect "card" that still
passes the `0.50…2.00` gate and still reports a confident-looking ratio.
**Explains: IMG_0782 catastrophically; contributes everywhere.**

**RC-4 — The inner reference is modelled as "a front's artwork window."**
`borderEnd` walks in from the outer edge sampling a "border colour" at depths 1–3. On a card
**back** there is no artwork window; on a sleeved card, depths 1–3 sample *sleeve*, so the walk
terminates at its own first step (`B = 11` on five fixtures). Half this corpus is backs.
**Explains: the pinned-bottom pattern and the `-3°/base` ratio flips.**

**RC-5 — Skew is estimated from a contaminated mask.**
`slope(of: firstForeground…)` fits the same mask that contains sleeve, shadow, and (after the
corrective re-render) the padded canvas wedges. Measured recovery of an applied 3° is **0 % on
half the corpus and 20–76 % on the rest, asymmetrically**. A partially corrected card is worse
than an uncorrected one because the downstream code believes it is straight.

**RC-6 — Rendering ignores rotation.**
`CardCenteringImage` applies `.rotationEffect(rotationDegrees)` to the image and then draws
`guideLines` in **unrotated** image coordinates. `CardCenteringExport.render` does the same:
the photo is drawn inside a rotated `CGContext`, `drawGuides` is called **after
`restoreGState()`**. Any manual rotation desynchronises the guides from the card, and the export
bakes that into a shareable PNG. This is a pure rendering defect, independent of detection.

**RC-7 — Confidence is unreliable in both directions.**
`detectionNotes` fires on 65 % of analyses and missed a 62 pp error. There is no numeric
confidence, and no path that declines to state a ratio.

**RC-8 — The camera path is optically unlike the corpus and unlike itself across devices.**
Always ultra-wide when available, at full ultra-wide FOV, with `isGeometricDistortionCorrection`
never enabled — so this app's own captures carry **more** barrel distortion than the Camera.app
macro fixtures. On a non-macro device the same code silently uses the wide lens. Nothing
normalises the two.

**RC-9 — Cost.** 1.8–3.8 s per analysis; skew correction runs the pipeline twice. Per-pixel Lab
conversion and two full gradient fields over ~1.1 Mpx in scalar Swift.

**RC-10 — No real-image evidence exists.** All 27 tests use flat-colour synthetic rectangles
with hard step edges, no sleeve, no glare, no shadow, no perspective, and no card backs. Every
root cause above is invisible to the current suite, which passes.

### 4.1 Root causes discovered during implementation (revision B)

**RC-11 — Historical Vision aspect-gate regression; fixed in REQ-028.**
The pre-REQ-028 code set `visionCardOutline`'s request-level
`minimumAspectRatio = 0.45`, `maximumAspectRatio = 0.90`, while its post-filter admitted
`0.45...2.0`. The sideways-card fixture is a 680 × 480 card (aspect **1.417**), so Vision
could not emit the observation that the post-filter expected. The pre-rewrite `cardOutline`
deliberately accepted `0.50...2.00` with the comment *"either way up, because a card
photographed sideways is still a card."* That capability was silently narrowed to
portrait-only in the historical implementation. The current tree widens the request-level
maximum to `2.0` and retains the `0.45...2.0` post-filter. The correctly targeted current
run passed `testACardPhotographedSidewaysIsStillFound` and
`testStraightensASkewedCardBeforeMeasuring` 2/2 on the pinned iOS 26.5 simulator; the
earlier `(0,0,0,0)` result is historical, not a current failure.

**RC-12 — Profile parameterization is axis- and scale-dependent, with outer-quad motion
mixed into the residual.** The original `innerQuadFromProfiles` sampled across an edge on an
integer working-pixel depth grid (`2...maxIndex`), used an absolute-pixel radius switch
(`min(cardWidth, cardHeight) >= 600 ? 2 : 1`), and computed the left/right and top/bottom
normalized depth with different pixel pitches (`depth / cardWidth` versus `depth /
cardHeight`). Its absolute baseline/MAD thresholds therefore saw different samples after a
mirror, quarter-turn, or scale change. E0's normalized-depth dumps and signed-line
comparison confirm corresponding peaks often translate rather than simply switch identity:
the transformed outer lines move by roughly 1–5 px in the two diagnostic fixtures, while
selected inner lines usually move less; residual selected-depth shifts still reach about
0.0073 normalized. The continuous-centroid experiment worsened the focused invariants, so a
discontinuous `argmax` is not established as the primary mechanism.

E2 addressed the measured parameterization defect without resampling image pixels: it uses a
fixed normalized depth grid, a card-relative derivative radius, edge-origin plus inward-normal
sampling, normalized statistics, and a unified score scale. It passed INV-7 and preserved the
20/20 legacy analyzer tests, but mirror and quarter-turn residuals remained. The remaining
work must therefore separate fitted-outer translation, profile phase/resampling, and
threshold behavior; it must not be treated as evidence for another arbitrary pixel-radius or
Vision/scalar arbitration experiment.

**RC-13 — The synthetic legacy corpus exercises the fallback path, not the Vision path.**
The 27 retained tests draw flat-colour rectangles with no texture. `VNDetectRectanglesRequest`
behaves differently on such images than on photographs, so those tests largely measure the
scalar Lab/gradient fallback. That is *useful* — it is the only coverage of the fallback — but
it means their failures and the HEIC failures may have different causes and must be
diagnosed separately.

**RC-14 — Detection resolution and the latency budget are now in direct conflict.** Working
resolution moved 1200 → 2400 px for accuracy, and two `VNDetectRectanglesRequest` passes were
added. The refreshed curve is 2.706 s median at 1200 and 7.971 s at 2400 against a 0.80 s
budget, while ratio pass remains 1/10 at both points. Revision A set that budget before either
change existed; stage cost is now an unresolved engineering problem, not a reason to trade
accuracy for more pixels. See `REQ-031`, `REQ-041`, and RC-21/RC-23.

**RC-15 — The record of what was tried needed to become durable.** Several experiments were
run and reverted (mean-vs-median aggregation, luminance-based profile evidence,
canonical/homography profile sampling, forcing the scalar path, parabolic depth refinement,
and additional arbitration/smoothing variants). Their negative results are now recorded in
`review/centering-evidence/experiments-log.md`; the intentional E0 diagnostics are retained
under `diagnostics/E0`, and the source scan no longer finds `TEMP_*` markers in production.
The EXIF helper was rebuilt and INV-6 now passes its self-checked fixture variants. See
`REQ-032` for the remaining cleanup/traceability gate.

**RC-16 — The scalar-pinned branch discarded independent inner evidence.** *Confirmed as a
branching defect, not as the sole physical cause of every sleeve failure.* On the raw HEIC run,
Vision supplied no inner quad and the original path skipped the working profile whenever scalar
evidence was pinned. That made a pinned scalar result look like absence of a gradeable inner
reference. Evaluating the profile against the selected outer quad, then relaxing coverage only
for an independently card-shaped pinned outline, recovers the five sleeved fixtures while
preserving the malformed IMG_0782 decline at the default resolution. The E-A telemetry also
shows that scalar/Vision agreement is true for two original decliners, so this finding must not
be simplified into "the 2% gate was the cause."

**RC-17 — The original E0/E1 harness did not hold the production input and effective resolution
constant.** The diagnostic renderer first draws each HEIC into 900x1200, and its 0.6x variant
changes the card from about 631 to about 470 working pixels. E0 and historical E1 remain valid
diagnostics of that harness, but their drift values are not production-equivalent evidence and
must not drive detector tuning. E-C is the named raw-HEIC/equal-card-size replacement; its
construction check passes for the two E0 fixtures, while its matched-resolution branch results
remain diagnostic rather than accuracy adjudication.

**RC-18 — An unconstrained outer-edge fit follows interior artwork transitions.** *Confirmed
by the E-D regression run.* A deterministic 10–90% normal-profile fit applied to every Vision
proposal moved several synthetic outer edges onto banners or artwork, producing eight legacy
assertion failures across six retained tests. Constraining the fit to a local offset of at most
`max(8 px, 2% of the short edge)` restores the 20/20 legacy analyzer class and still accepts
the raw IMG_0783 refinement smoke test, but it means E-D is conservative rather than proven
equivariant: only four of the ten raw-fixture analyses accepted a refinement in the current
E-A telemetry (`IMG_0349`, `IMG_0351`, `IMG_0780`, and `IMG_0782`). The follow-up E-D2 telemetry
shows coherent left-edge transitions about 28–35 working pixels outward from the Vision proposal
on IMG_0347, IMG_0350, IMG_0352, and IMG_0781, beyond the current 14–15 pixel guard; IMG_0348
instead fails on bottom-edge support. This identifies a guard hypothesis but does not justify
blanket widening, because the retained synthetic regressions still define the safety boundary.
The E-D4 broad-transition feature gate accepted those four photo contracts but reproduced seven
retained synthetic regressions by allowing an unrelated synthetic edge to authorize the complete
quad. It was discarded; the 2% per-edge guard is current.
The first post-fit invariant
run also showed that refit line angles perturbed the presentation roll; preserving the Vision
proposal's roll signal fixed INV-3 in the current targeted rerun. INV-4, INV-5, INV-7, and
INV-8 still fail. E-E's raw/equalized per-edge comparison classifies the residual as both
outer-line displacement and profile depth selection; the remaining failures are not explained
by the harness's raw/equalized resolution difference.

**RC-19 — The implementation has no effective inner-reference-type classifier.** *Confirmed
by E-A plus current GT.* All nine `finalAnalysis` records that carry an inner reference report
`innerReference = art_window`, including both scalar-inner results and all five backs whose GT
requires `printed_border`; IMG_0782 correctly reports `none`. Vision supplies no inner rectangle in this corpus. The current profile
therefore finds a plausible inset transition and assigns a default semantic label; it does not
decide whether that transition is an art window, printed back border, unrelated printed feature,
or no gradeable reference. This is a selection-level defect, not a subpixel-placement defect.

**RC-20 — Front art-window top/bottom selection is deterministically wrong.** IMG_0348's T/B
error remains 19.49–22.78 pp and IMG_0780's remains 21.04–21.18 pp across the complete
1200/1600/2000/2400 sweep. IMG_0780's L/R error stays materially smaller at 4.97–5.81 pp.
The resolution invariance and axis asymmetry localize the failure to repeatable selection of a
different horizontal printed boundary, consistent with title/header and type/text-box lines
competing with the intended art-window top/bottom. Candidate telemetry must name the exact
winning features, but additional sampling precision cannot resolve this class.

**RC-21 — Resolution changes are a confidence-safety input.** IMG_0349 declines at 1600 and
2000, then becomes confident at 2400 with 42.83/39.67 pp errors; IMG_0781's L/R error rises from
11.70 to 45.37 pp as resolution increases. A resolution override can change candidate identity
and convert uncertainty into a confident catastrophe. Resolution must be capped at 1200 until
the selector includes an explicit stability criterion; it is not merely a latency knob.

**RC-22 — The original holdout is no longer independent.** Every fixture has been inspected,
profiled, visually adjudicated, and repeatedly benchmarked. The E-B five-sleeved experiment
included IMG_0349 and IMG_0351 from the declared holdout. The source remains free of fixture-name
branches, but the old split cannot estimate generalisation and must be replaced by a frozen set
with genuinely different capture conditions.

**RC-23 — The current cost centre is unmeasured.** The 1200-pixel path already takes 2.706 s
median, 3.4x the target. The normalized inner profile performs roughly 240 along-edge samples by
320 depth samples across four edges, so a large fixed sampling cost is plausible, but this is a
hypothesis rather than an attribution. Stage-level timing must measure image preparation, Vision,
scalar fields, outer refinement, inner candidate generation, and selection before performance
work or a budget revision.


---

## 5. What "correct" means

### 5.1 Is zero-pixel accuracy meaningful? — answered per layer

**No, not at the detection layer — and the reason is physical, not an excuse.** §3.4 measures
the card-edge transition at 1–2 px where a black card meets white paper and **14 px** where a
pale sleeve meets white paper under a soft shadow. The cut edge is also *rounded* at the corners,
and for a sleeved card there are genuinely **two** boundaries. "The card edge" is a band, not a line.

**Yes, at the rendering layer — and this must not be diluted.** Once geometry has been decided,
placing it at the intended screen or output coordinate is arithmetic. `REQ-019`/`REQ-020` require
placement accuracy of **≤ 0.5 pt and ≤ 1 device pixel** against *injected, known* geometry, tested
without any detector in the loop. A detection tolerance may never be cited to excuse a rendering error.

**The tolerance policy** (scale-free; `H` = ground-truth card height in working pixels):

| Layer | Metric | Tolerance | Justification |
|---|---|---|---|
| Outer edge | signed normal offset per edge | `τ_e = clamp(measured 10–90 % band of that edge, 0.25 % H, 1.0 % H)` | ties the tolerance to the measured ambiguity of *that* edge; 0.25 % H ≈ 2.8 px ≈ the 1–2 px best case; 1.0 % H ≈ 11 px ≈ the 14 px worst case |
| Outer corner | Euclidean distance to GT virtual corner | `√2 · τ_e` | two independent edge errors compose |
| Card centre | ‖Δcentre‖ | **0.20 % H** | the mean of four edges; independent errors cancel, so this is *tighter* than any single edge |
| Rotation | absolute angle error | **≤ 0.20°** | 0.20° over an 1100 px edge = 3.8 px end-to-end drift, below the edge band — the natural floor |
| Perspective | opposite-edge parallelism after rectification | **≤ 0.30°**; rectified aspect within **1.5 %** of the GT object aspect; GT-corner reprojection RMS ≤ `τ_e` | a rectification that is "centred but distorted" must fail |
| Inner edge | signed normal offset per edge | **0.35 % H** | printed transitions are high contrast; §3.4-class ambiguity does not apply |
| **Reported ratio** | absolute error in percentage points | **≤ 2.0 pp** per axis | the product's actual output; bounded by the inner+outer tolerances above |
| **Rendered guide** | position in the presented view / export | **≤ 0.5 pt and ≤ 1 device px** | pure arithmetic; no physical ambiguity exists |
| Determinism | byte equality of the measurement over 5 runs | **exact** | no tolerance is defensible here |

Every fixture-edge whose measured band exceeds 1.0 % H is recorded `AMBIGUOUS` in ground truth.
Such an edge is excluded from the strict pass/fail metric **but must still fall inside its own
recorded band**, and a fixture with any `AMBIGUOUS` edge may not be counted toward the
high-confidence success rate in `REQ-021`.

### 5.2 Adjudication and budget-revision rules (revision B)

**5.2.1 — Provisional ground truth cannot decide an accuracy dispute.** While any fixture's
`provenance.method` is `provisional_*`, a disagreement between detector and reference is
*unadjudicated*, not a detector failure. It may not be closed by changing the detector to
match, and it may not be closed by editing the reference to match the detector. It is closed
only by re-deriving that fixture's ground truth per §6.2 (`REQ-027`) and then re-measuring.
This rule exists because §3.5(c) is a live example: the largest L1 failure is, on independent
evidence, most likely a reference error.

**5.2.2 — A tolerance may be revised only with evidence, never for convenience.** Revision A
fixed every number in §5.1 from a measurement. One of them — the latency budget — was set
before the accuracy work chose its working resolution, so it may now be genuinely wrong rather
than merely unmet. `REQ-031` defines the only procedure by which it may move: measure the
accuracy-vs-resolution curve, show what is lost at each step down, and record the decision.
No other §5.1 tolerance is open for revision under this revision.

**5.2.3 — Environmental failures are named, not absorbed.** A failure caused by the harness
(§12.1) is excluded from the centering count *and* listed explicitly in the evidence table, so
that "24 failed" is never silently reported as "17 failed" without the reader seeing why.


---

## 6. Ground truth

**Non-negotiable: the detector under test may not produce, seed, initialise, or adjust ground
truth.** Any GT produced with assistance from `CardCenteringAnalyzer` output is void (`REQ-001`).

### 6.1 Representation

One JSON file per fixture at `TestFixtures/TradingCards/GroundTruth/<NAME>.gt.json`, plus a
schema doc. Coordinates are in the **native oriented pixel space** (3024 × 4032 after applying
EXIF orientation 6) so GT is independent of any working resolution the implementation chooses.

```jsonc
{
  "schema": 1,
  "fixture": "IMG_0347.HEIC",
  "sourcePixelSize":   { "w": 4032, "h": 3024 },
  "orientedPixelSize": { "w": 3024, "h": 4032 },
  "exifOrientation": 6,

  "face": "back",                  // front | back
  "encasement": "penny_sleeve",    // none | penny_sleeve | toploader | graded_slab
  "capture": "macro_systemcamera", // macro_systemcamera | wide | import_unknown | synthetic

  // Virtual corners: intersections of the four fitted edge LINES, extrapolated past the
  // rounded corners. Order is fixed: TL, TR, BR, BL in the oriented image.
  "cardOuterQuad": [[x,y],[x,y],[x,y],[x,y]],
  "cardCornerRadiusPx": 21.0,

  // Present only when encasement != none. Same convention. Lets a test assert that the
  // detector chose the CARD and not this.
  "encasementOuterQuad": [[x,y],[x,y],[x,y],[x,y]],

  // The printed reference the ratio is measured to. For a front this is the artwork/frame
  // window; for a back it is the printed border. null when the face has no gradeable
  // inner reference, which makes the fixture a DECLINE case (REQ-018).
  "innerQuad": [[x,y],[x,y],[x,y],[x,y]] | null,
  "innerReference": "art_window" | "printed_border" | "none",

  // Per-edge measured ambiguity, produced by the band tool (§6.3), not by hand.
  "edgeBands": { "left": 14.2, "top": 3.1, "right": 2.8, "bottom": 3.4 },
  "ambiguousEdges": ["left"],

  "expected": { "lrRatio": 51.8, "tbRatio": 48.9, "skewDegrees": -1.35 },
  "conditions": ["glare", "shadow", "sleeve", "low_contrast_edge"],

  "provenance": {
    "method": "manual_annotation_plus_subpixel_edge_fit",
    "annotators": ["A", "B"],
    "agreementPx": 2.4,
    "toolVersion": "gt-tool 1.0",
    "date": "2026-09-11",
    "notes": "left edge is sleeve-over-paper under shadow; band recorded as ambiguous"
  }
}
```

### 6.2 Procedure (must be repeatable by a second engineer without redoing the investigation)

1. **Annotate independently, twice.** Two passes (two people, or one person and one
   non-`CardCenteringAnalyzer` tool such as a generic corner-click utility) mark 4 points per
   edge — well away from corners — on the oriented full-resolution image.
2. **Fit, don't click, the edges.** Each edge line is a total-least-squares fit through its
   points. Corners are the **intersections of adjacent fitted lines**, extrapolated. This is
   how a 21 px corner radius is handled without inventing a point that does not exist.
3. **Sub-pixel refine.** For each edge, sample the luminance profile along the edge normal at
   ≥ 200 positions, average, and place the edge at the **50 % crossing of the 10–90 % band**.
   Record the band width. This is the `edgeBands` value and the tolerance input.
4. **Reconcile.** If the two independent annotations disagree by more than `τ_e` on any edge,
   both annotators re-examine that edge together and record the reason in `provenance.notes`.
   `agreementPx` is the max pre-reconciliation disagreement and must be reported.
5. **Annotate the encasement separately** whenever one is present, so `REQ-011` can be tested.
6. **Sanity-check physics.** Rectified `cardOuterQuad` aspect must be within 2 % of 0.7143.
   A fixture failing this is re-annotated — it is an annotation error, not a card.
7. **Record `expected.lrRatio` / `tbRatio`** from the annotated quads, not from any detector.

### 6.3 Tooling

A `gt-tool` target under `review/centering-harness/` performs steps 2, 3, 6 and writes the
JSON. It must not import `CardCenteringAnalyzer`. Its edge-band routine is the same code the
evaluator uses to compute `τ_e`, so tolerance and ground truth cannot drift apart.

### 6.4 Review protocol

`REQ-003` requires a per-fixture **GT overlay sheet** — the oriented image with the annotated
card quad, encasement quad, inner quad, and corner labels drawn on it, at a legible size, in a
tracked directory. A reviewer audits GT by looking at those sheets and the `provenance` block;
they never need to rerun the annotation.

---

## 7. Evaluation harness

### 7.1 Layers (all three are required; none substitutes for another)

**L1 — Numeric geometry tests (XCTest, in-target).**
`CardCenteringGroundTruthTests` iterates every `*.gt.json`, runs **the production entry point**
`CardCenteringAnalyzer.analyze(_:)` on the real HEIC bytes, and asserts every §5.1 metric.
Fixtures must be added to the test target as resources (`REQ-004`). Tests call the same API the
view model calls — no private helper, no re-implemented sub-step (`REQ-025`).

**L2 — Metamorphic tests (XCTest).** §8.

**L3 — Simulator end-to-end with screenshots.** §10.

### 7.2 Metric implementation notes

- All comparisons happen in **oriented native pixel space**. The evaluator upscales the
  analyzer's working-resolution output by the exact ratio the analyzer used, and that ratio must
  be exposed on the result (`REQ-005`) rather than inferred.
- Edge error is the **signed distance from the GT edge line to the corresponding detected edge**,
  measured along the GT edge normal at the edge midpoint — not a difference of scalars, so it
  stays meaningful once the model is a quadrilateral.
- Rotation error is `|detected − GT| ` reduced modulo 90° **only** when the fixture is a
  deliberate 90° metamorphic variant; otherwise it is absolute, so a 90° confusion fails loudly.

### 7.3 Normal-lens and import coverage — the corpus cannot supply it

The corpus is 10 macro-mode system-camera captures. It contains **no** normal-lens capture, **no**
non-iPhone import, **no** flatbed scan and **no** graded slab. Two consequences, both binding:

- `REQ-013` requires a **supplementary fixture set** (`TestFixtures/TradingCards/Supplementary/`)
  covering: wide-lens capture, a flatbed/scanner-style image, a downloaded/re-encoded JPEG with
  EXIF orientation 1, 3 and 8, and a graded-slab photo. These need ground truth to the same
  standard. Where a real capture cannot be obtained before implementation, a **DEVICE-PENDING**
  gate is opened instead (§12) — the requirement is *not* closed by the HEIC corpus.
- `REQ-014` requires the normal-lens and macro-lens paths to **converge into one normalised
  pipeline** at a defined point, or to be justified in writing as needing to diverge. The
  investigation found no evidence they should diverge: both produce a `Data` blob with EXIF and
  both hit the same analyzer. The real difference is *optical distortion*, which is a
  preprocessing concern, not a branch.

---

## 8. Target invariants

Each is a test, not a sentiment. `R(θ)` = the fixture re-rendered rotated by θ on a padded canvas.

| ID | Invariant | Tolerance | Baseline |
|---|---|---|---|
| INV-1 | `analyze(x)` run 5× → identical measurement | exact | assumed, untested |
| INV-2 | `analyze(R(+3°))` ≈ `analyze(R(−3°))` ≈ `analyze(x)` in reported ratio | ≤ 1.5 pp | **median 16.6 / 18.6 pp, max 63.1 pp** |
| INV-3 | recovered skew tracks applied rotation | ≤ 0.25° over θ ∈ {−8…+8} | 0° recovered on 5/10 at θ=3° |
| INV-4 | `analyze(mirrorX(x))` → LR complements, TB unchanged | ≤ 0.5 pp | median 1.3, max 13.0 pp |
| INV-5 | `analyze(R(90°))`, `R(180°)`, `R(270°)` → ratios map exactly | ≤ 0.5 pp | up to 16.5 pp |
| INV-6 | EXIF orientation 1/3/6/8 of the same pixels → identical result | ≤ 0.5 pp | untested |
| INV-7 | uniform scale 0.6× / 1.0× / 1.5× → same ratio | ≤ 1.0 pp | untested |
| INV-8 | benign crop (≥ 8 % margin retained around the card) → same ratio | ≤ 1.0 pp | untested |
| INV-9 | the detected card quad never coincides with `encasementOuterQuad` when both exist | corner distance > 3 × `τ_e` toward the card | **violated on ≥ 6 fixtures today** |
| INV-10 | `analyze` never returns a confident measurement whose rectified aspect deviates > 4 % from 0.7143 | hard gate | **violated by IMG_0782 (1.273)** |

INV-7 and INV-8 exist specifically to catch a detector that has memorised "the card occupies
roughly this part of the frame" — the most likely overfitting mode for a 10-image corpus.

---

## 9. Implementation requirements

**45 requirements.** Format per the brief: objective · rationale · subsystem · required
behaviour · constraints/must-preserve · validation · completion criterion.

Where several correct implementations exist, the choice is Luna's. Revision A deliberately did
not name an algorithm for `REQ-009`–`REQ-012`; revision E now constrains the next attempt to the
candidate-recall, semantic-reference, joint-selection spike in `REQ-039`–`REQ-045` because the
generic per-edge sampling family has been falsified.

---

### Group A — Ground truth and harness (must land first; nothing else is measurable without it)

#### REQ-001 — Independent ground truth for every HEIC fixture
- **Objective.** Produce reviewable GT geometry for all 10 fixtures per §6.
- **Rationale.** No real-image reference exists; all 27 current tests are synthetic. Without GT
  the remaining requirements are unfalsifiable.
- **Subsystem.** `TestFixtures/TradingCards/GroundTruth/`, `review/centering-harness/gt-tool`.
- **Required behaviour.** One `<NAME>.gt.json` per fixture conforming to §6.1, produced by §6.2.
- **Constraints.** `gt-tool` must not link or import `CardCenteringAnalyzer`, and no GT field may
  be initialised from its output. Both independent annotation passes retained in `provenance`.
- **Validation.** Schema test; a test asserting rectified GT card aspect ∈ 0.7143 ± 2 %; a test
  asserting `agreementPx` is recorded and ≤ `τ_e` after reconciliation.
- **Completion.** 10/10 files exist, pass schema + aspect tests, and each carries two annotators
  and a measured `edgeBands`.

#### REQ-002 — Hold-out discipline against corpus overfitting
- **Objective.** Make overfitting to 10 images detectable.
- **Rationale.** One photographer, one background, one lens, one session. A detector tuned to
  convergence on this set proves little.
- **Subsystem.** harness + fixture layout.
- **Required behaviour.** Partition fixtures into **TUNE (6)** and **HOLDOUT (4: IMG_0349,
  IMG_0782, IMG_0783, IMG_0351 — one glare, one mask-failure, one high-contrast back, one
  sleeved front)**. Tuning constants may be chosen only against TUNE. HOLDOUT is evaluated at
  the end and its results reported separately in the evidence table.
- **Constraints.** No constant, threshold, or branch may reference a fixture name.
- **Validation.** `grep` test asserting no fixture identifier appears in production sources;
  evidence table reports TUNE and HOLDOUT pass rates separately.
- **Current status (revision E).** The original four HOLDOUT fixtures are now development-exposed:
  all ten records were visually adjudicated and repeatedly benchmarked, and E-B's five-sleeved
  experiment included IMG_0349 and IMG_0351. No fixture-specific production branch was added,
  but the old split can no longer estimate generalisation.
- **Completion.** A new capture-condition-diverse holdout is frozen before the revision-E spike;
  its pass rate is reported and is within 15 percentage points of the development set. The old
  TUNE/HOLDOUT split remains labeled as historical chronology only.

#### REQ-003 — Ground-truth overlay sheets
- **Objective.** Let a reviewer audit GT visually without rerunning anything.
- **Rationale.** §6.4; the brief requires GT reviewable by another engineer/model.
- **Subsystem.** `review/centering-evidence/ground-truth/`.
- **Required behaviour.** One PNG per fixture showing the oriented image with card quad,
  encasement quad, inner quad, corner indices and the `edgeBands` values legibly drawn.
- **Constraints.** Tracked by git (**not** `artifacts/`, which is gitignored — see `REQ-023`).
  Downscale to keep each file < 1.5 MB.
- **Validation.** File-existence test; manual review checklist item in §13.
- **Completion.** 10 sheets present and named `<FIXTURE>_gt.png`.

#### REQ-004 — Real fixtures reachable from the test target
- **Objective.** Let XCTest read the real HEIC bytes.
- **Rationale.** The fixtures are currently in no Xcode target; `project.pbxproj` uses explicit
  file lists, so this is a real integration step and not a given.
- **Subsystem.** `TradingCardScanner.xcodeproj`, test bundle resources.
- **Required behaviour.** Fixtures + GT JSON resolvable from `Bundle(for:)` in the test bundle.
- **Constraints.** Must not be added to the **app** target (bundle size). Must not change any
  existing target's membership.
- **Validation.** A test that loads all 10 HEICs and all 10 GT files from the bundle.
- **Completion.** That test passes on a clean checkout + clean DerivedData.

#### REQ-005 — Analyzer result exposes the coordinate mapping it used
- **Objective.** Make working-resolution → native-pixel conversion exact, not inferred.
- **Rationale.** Guides are reported in a ≤1200 px space; every metric in §5.1 is defined in
  native oriented pixels. Inferring the scale factor invites an off-by-one that masquerades as
  detection error, and would let a screenshot-scaling artefact be mistaken for geometry error.
- **Subsystem.** `CardCenteringAnalysis` / `CardCenteringMeasurement`.
- **Required behaviour.** The result carries the oriented source pixel size, the working size,
  the scale factor, and any rotation applied, sufficient to map any reported coordinate back to
  oriented native pixels exactly.
- **Constraints.** Additive only; `CardCenteringMeasurement`'s existing public surface and
  `Equatable` semantics used by `CardCenteringViewModel` and the export must keep working.
- **Validation.** Round-trip test: a known native point → working → native is exact.
- **Completion.** Round-trip test passes; the evaluator uses the exposed value, never a computed guess.

#### REQ-006 — Baseline regression record
- **Objective.** Freeze §3 so improvement is demonstrable and regression is detectable.
- **Rationale.** "All tests pass" cannot distinguish improvement from a rewritten test.
- **Subsystem.** `review/centering-evidence/`.
- **Required behaviour.** Retain the 2026-09-11 baseline; add an `after/` directory in the same
  format. The evidence table (`REQ-026`) shows before → after per fixture per metric.
- **Constraints.** Baseline files are immutable; never regenerate them with new code.
- **Validation.** A test asserting the baseline directory exists, is non-empty, and is byte-identical
  to its committed state (a checksum manifest); the evidence table's before-column is read from it.
- **Completion.** Both directories present; evidence table cites both.

---

### Group B — Geometry model

#### REQ-007 — Quadrilateral card geometry
- **Objective.** Replace the four-scalar outer model with a four-corner model.
- **Rationale.** RC-1. A photographed card is a quadrilateral; every instability in §3.2 traces
  to representing it as an axis-aligned box.
- **Subsystem.** `CardCenteringMeasurement`, `CardCenteringAnalyzer`.
- **Required behaviour.** Detection produces an ordered outer quad (TL, TR, BR, BL) and an inner
  quad in the same convention. Axis-aligned edges become a derived projection for the existing
  UI and export, not the source of truth.
- **Constraints.** **Manual guide editing must keep working** (`REQ-017`). The exported filename
  format and the `leftRightCentering` / `topBottomCentering` string format are user-visible and
  must not change. `CardCenteringEdges` may remain as the manual-adjustment representation.
- **Validation.** L1 corner metric vs GT; INV-10.
- **Completion.** Corner error ≤ `√2·τ_e` on ≥ 9/10 fixtures; the 10th within its recorded band.

#### REQ-008 — Ratio computed from the quad, not from a bounding box
- **Objective.** Make the reported ratio a property of the geometry, not of its bounding box.
- **Rationale.** With any skew, a bounding box overstates the card and biases every border.
- **Subsystem.** `CardCenteringMeasurement`.
- **Required behaviour.** Borders are measured as perpendicular distances between corresponding
  outer and inner edges (or in a rectified space), per side.
- **Constraints.** Output string format unchanged.
- **Validation.** Synthetic quad with known borders at 0°, 2°, 5° skew → identical ratios.
- **Completion.** ≤ 0.3 pp variation across that sweep.

---

### Group C — Detection

#### REQ-009 — Shape-constrained card detection
- **Objective.** Stop truncating the card at internal light regions.
- **Rationale.** RC-3; IMG_0782 returns a 1.273-aspect "card" with a confident ratio.
- **Subsystem.** `CardCenteringAnalyzer` detection stage.
- **Required behaviour.** The detected object must be a single connected region with four
  dominant straight edges and an aspect consistent with a card. Independent per-row and
  per-column run analysis is insufficient. *Algorithm choice is Luna's* — contour/hull +
  quad fit, Vision rectangle detection, or a line-based fit are all acceptable.
- **Constraints.** Must not require the card to occupy a fixed fraction of the frame (INV-7/8).
  Must not depend on background colour being white.
- **Validation.** L1 on all fixtures; INV-10; INV-7; INV-8.
- **Completion.** 10/10 fixtures produce a quad whose rectified aspect is within 4 % of 0.7143;
  IMG_0782 specifically recovers its full card height.

#### REQ-010 — Robustness to glare, shadow and low-contrast edges
- **Objective.** Handle the corpus's actual conditions.
- **Rationale.** Foil glare (0348/0349/0351) and cast shadow (0347/0350) are present in most fixtures.
- **Subsystem.** detection preprocessing.
- **Required behaviour.** Detection succeeds, or declines explicitly (`REQ-018`), on every
  fixture. A cast shadow may not be admitted as card area.
- **Constraints.** No fixture-specific branch.
- **Validation.** L1 with `conditions` from GT reported per fixture in the evidence table.
- **Completion.** Outer-edge error within `τ_e` on every non-`AMBIGUOUS` edge across all 10.

#### REQ-011 — Sleeve / encasement disambiguation
- **Objective.** Measure the **card**, never the sleeve.
- **Rationale.** RC-2 and §3.3 — the single largest source of absolute error. ≥ 6 fixtures are
  sleeved and the detector currently returns the sleeve boundary as the card.
- **Subsystem.** detection.
- **Required behaviour.** When two nested near-concentric quads of card-like aspect exist, the
  **inner** one is the card. When the distinction cannot be made confidently, decline
  (`REQ-018`) rather than pick.
- **Constraints.** Must not break un-sleeved cards (IMG_0780/0781/0783 look un-sleeved or
  tightly sleeved; GT records which). Must not assume a fixed sleeve width.
- **Validation.** INV-9 against `encasementOuterQuad`; L1 outer-edge metric.
- **Completion.** INV-9 holds on every fixture whose GT carries an `encasementOuterQuad`.

#### REQ-012 — Inner reference appropriate to the face
- **Objective.** Define and find the inner reference for **backs** as well as fronts.
- **Rationale.** RC-4; 5 of 10 fixtures are backs, and the bottom border pins at its minimum on
  half the corpus.
- **Subsystem.** detection inner stage.
- **Required behaviour.** Support `art_window` (fronts) and `printed_border` (backs). The search
  must start from the corrected **card** edge (post-`REQ-011`), not from a sleeve. When no
  gradeable inner reference exists, return `innerReference: none` and decline the ratio.
- **Constraints.** Must not reintroduce the removed "borders resemble each other" prior — the
  tool exists to report *unequal* borders (see the comment on `chooseInner`). Each side stays
  independently evidenced.
- **Validation.** L1 inner-edge metric; a test that no fixture's inner border equals the search
  minimum unless GT agrees.
- **Completion.** Inner-edge error ≤ 0.35 % H on every fixture with a non-null `innerQuad`; zero
  occurrences of a pinned inner border that GT does not corroborate.

---

### Group D — Orientation, rotation, perspective

#### REQ-013 — Orientation and input-path coverage
- **Objective.** Prove EXIF handling and extend coverage beyond one orientation.
- **Rationale.** All 10 fixtures are orientation 6; orientation handling is currently correct but
  wholly untested, and untested-correct is one refactor from broken.
- **Subsystem.** `prepare`, supplementary fixtures.
- **Required behaviour.** Identical geometry for the same pixels stored with EXIF 1, 3, 6, 8.
  Supplementary fixtures per §7.3 with GT.
- **Constraints.** Preserve today's correct `UIImage.size` / `draw(in:)` behaviour; do not switch
  to raw `cgImage` dimensions.
- **Validation.** INV-6 on re-encoded variants of ≥ 3 fixtures; L1 on supplementary set.
- **Completion.** INV-6 passes; supplementary fixtures either pass or have an open DEVICE-PENDING gate.

#### REQ-014 — One normalised pipeline for both lenses
- **Objective.** Remove unjustified divergence between normal and macro capture.
- **Rationale.** RC-8. Both paths already converge on `Data`; the real difference is lens
  distortion, which is preprocessing.
- **Subsystem.** `CenteringCameraController`, analyzer preprocessing.
- **Required behaviour.** Either both lenses feed one normalised path, or the divergence is
  documented with evidence. Geometric distortion correction must be enabled where the device
  supports it, and the capture must record which lens produced it.
- **Constraints.** Do not regress the existing level indicator, one-shot capture guard, or
  permission/lifecycle handling in `CenteringCameraController`.
- **Validation.** L1 on the supplementary wide-lens fixture; a unit test asserting distortion
  correction is requested when supported.
- **Completion.** Requirement met on simulator-testable parts; optical behaviour recorded as
  **DEVICE-PENDING-1/2** (§12).

#### REQ-015 — Rotation estimation from fitted card edges
- **Objective.** Recover in-plane skew accurately and symmetrically.
- **Rationale.** RC-5; measured recovery is 0 % on half the corpus and asymmetric elsewhere.
- **Subsystem.** analyzer rotation stage.
- **Required behaviour.** Skew derived from the `REQ-007` quad's fitted edges, using all four
  edges, uncontaminated by sleeve, shadow, or rotation padding. Correction must not require a
  full second analysis pass (see `REQ-022`).
- **Constraints.** **Manual rotation must still override automatic correction** — the existing
  rule that a user-supplied `rotationDegrees` disables auto-skew is a deliberate product
  decision and must survive (`testManualRotationIsNotOverriddenByAutoCorrection`).
- **Validation.** INV-3 across θ ∈ {−8, −5, −3, −1, 0, +1, +3, +5, +8} on all 10 fixtures.
- **Completion.** Recovered angle within 0.25° of applied at every θ on ≥ 9/10 fixtures, and
  `|error(+θ) − error(−θ)| ≤ 0.15°`.

#### REQ-016 — Perspective rectification with a distortion guard
- **Objective.** Measure borders in a fronto-parallel space.
- **Rationale.** A tilted card has genuinely unequal apparent borders; measuring in image space
  reports tilt as miscentring.
- **Subsystem.** analyzer geometry stage.
- **Required behaviour.** Rectify the outer quad to a rectangle before measuring, and validate
  the result: opposite edges parallel ≤ 0.30°, rectified aspect within 1.5 % of the GT object
  aspect, GT-corner reprojection RMS ≤ `τ_e`.
- **Constraints.** A rectification failing those checks must **decline** (`REQ-018`), not ship a
  centred-but-distorted answer. Keep the existing honest behaviour of telling the user when the
  photo is too angled rather than silently guessing.
- **Validation.** L1 reprojection metric; a synthetic known-homography test with exact expected corners.
- **Completion.** All three residual checks pass on every fixture that does not decline.

---

### Group E — Confidence, fallback, product behaviour

#### REQ-017 — Manual adjustment preserved and made quad-aware
- **Objective.** Keep the fallback genuinely usable.
- **Rationale.** The brief requires manual adjustment to survive; `REQ-007` changes the model underneath it.
- **Subsystem.** `CardCenteringViewModel`, `CardCenteringView` guide controls.
- **Required behaviour.** Every currently adjustable guide remains adjustable and still updates
  the ratio and warnings live. If geometry is now a quad, manual editing must remain
  comprehensible (adjusting a projected edge is acceptable).
- **Constraints.** `updateOuter` / `updateInner` clamping, `refreshWarnings`, and the
  `detectionNotes`-survive-adjustment behaviour must be preserved
  (`testDetectionNotesSurviveAGuideAdjustment`).
- **Validation.** Existing surface tests plus a new test driving a manual correction to a
  declined fixture and reaching a correct ratio.
- **Completion.** A declined fixture can be brought within 2.0 pp of GT by manual adjustment alone.

#### REQ-018 — Explicit confidence and decline
- **Objective.** Never present a confidently wrong ratio.
- **Rationale.** RC-7. The current note fires on 65 % of analyses and missed a 62 pp error;
  IMG_0782 states `86.0 / 14.0` from a half-card box.
- **Subsystem.** analyzer result, view model, view.
- **Required behaviour.** A numeric confidence with documented inputs (edge support, aspect
  residual, rectification residual, sleeve ambiguity, inner-reference presence). Below
  threshold: the tool **declines to state a ratio**, says why, and presents manual adjustment.
- **Constraints.** Decline must be visually distinct from a measurement. Existing `detectionNotes`
  survival semantics preserved.
- **Validation.** A test asserting no fixture returns `confident` while exceeding 2.0 pp ratio
  error; a test asserting IMG_0782-class geometry (aspect > 4 % off) can never be `confident`.
- **Completion.** Zero confident-and-wrong outcomes across all fixtures and all metamorphic
  variants (60+ analyses).

---

### Group F — Rendering (the zero-tolerance layer)

#### REQ-019 — On-screen guides track the rendered image exactly
- **Objective.** Fix RC-6 in `CardCenteringImage`.
- **Rationale.** `.rotationEffect` is applied to the image while `guideLines` are drawn in
  unrotated coordinates. Under manual rotation the guides do not lie on the card.
- **Subsystem.** `CardCenteringView.CardCenteringImage`.
- **Required behaviour.** Guides undergo the same transform as the image. Placement accuracy
  ≤ 0.5 pt and ≤ 1 device px against **injected known geometry**.
- **Constraints.** Preserve zoom, pan, double-tap-to-zoom and the accessibility label.
- **Validation.** A view test that injects a synthetic image with known edge positions plus a
  known rotation, renders through `ImageRenderer`, and locates the drawn guides in the output.
  **No detector in the loop.**
- **Completion.** ≤ 0.5 pt at rotations {0, ±0.01, ±1, ±7, ±45}° and at ≥ 2 container aspect ratios.

#### REQ-020 — Exported PNG guides track the rotated photo exactly
- **Objective.** Same fix in `CardCenteringExport.render`.
- **Rationale.** `drawGuides` is called after `restoreGState()`, so the export has the same
  defect, baked into a shareable artifact. The export is the feature's durable output.
- **Subsystem.** `CardCenteringExport`.
- **Required behaviour.** Guides transformed with the photo; the rotated photo must not be
  silently clipped by `photoRect`.
- **Constraints.** Panel layout, colour palette, the black casing under each guide line, and
  `filename(for:rotationDegrees:)` output must not change — all are covered by existing tests.
- **Validation.** Render with known geometry + rotation, then locate guide pixels in the PNG.
- **Completion.** ≤ 1 px guide placement error at the same rotation set as `REQ-019`.

#### REQ-021 — End-to-end displayed-result accuracy
- **Objective.** Prove the product, not just the algorithm.
- **Rationale.** Numeric tests can pass on a pipeline whose screen output is still wrong.
- **Subsystem.** simulator harness (§10).
- **Required behaviour.** For every fixture: load through a realistic app flow, let automatic
  detection run, screenshot, and **measure the guide positions in the screenshot** against GT
  mapped into screen space.
- **Constraints.** Measurement must account for device scale; the harness must record
  `UIScreen.scale` and the presented image frame so screenshot scaling cannot silently absorb error.
- **Validation.** Per-fixture screenshot + per-fixture JSON of measured vs expected.
- **Completion.** ≥ 8/10 fixtures within 2.0 pp of GT ratio **and** guides within 1.5 % H of GT
  edges in screen space; the remainder must **decline** (never be confidently wrong).

---

### Group G — Cost, hygiene, evidence

#### REQ-022 — Analysis cost
- **Objective.** Make the screen feel responsive.
- **Rationale.** 1.8–3.8 s measured, doubled by the corrective re-render.
- **Subsystem.** analyzer.
- **Required behaviour.** Single-pass geometry (no full re-analysis for skew). Measured wall
  time ≤ 800 ms per image on the reference simulator for a 4032 × 3024 input.
- **Constraints.** Accuracy requirements take precedence; do not buy speed by lowering working
  resolution below what `τ_e` needs.
- **Validation.** A performance test over all 10 fixtures reporting median and max.
- **Completion.** Median ≤ 800 ms, max ≤ 1500 ms, recorded in the evidence table.

#### REQ-023 — Evidence lives in a tracked directory
- **Objective.** Make results auditable from a clean checkout.
- **Rationale.** `.gitignore:11` ignores `artifacts/`, and `ui_build_and_shoot.sh` writes a single
  overwritten `artifacts/ui-latest.png`. The existing screenshot infrastructure produces exactly
  the ephemeral output the brief forbids.
- **Subsystem.** `review/centering-evidence/`, `scripts/`.
- **Required behaviour.** All durable evidence written under `review/centering-evidence/`, named
  per fixture and per requirement, committed.
- **Constraints.** Keep total added weight reasonable (downscale screenshots; < 1.5 MB each).
- **Validation.** A test asserting every artifact path named in the evidence table resolves inside
  `review/` and is not matched by `.gitignore`.
- **Completion.** A clean clone contains every artifact §13 requires.

#### REQ-024 — No fixture-specific behaviour
- **Objective.** Forbid hacks that satisfy the corpus without generalising.
- **Rationale.** Explicit brief requirement; `REQ-002` makes it measurable.
- **Subsystem.** all production sources.
- **Required behaviour.** No constant, threshold, branch, or lookup keyed to a fixture identity,
  exact dimension, or image hash.
- **Constraints.** A legitimate general rule that happens to help one fixture is allowed and must be
  documented with the physical reason it generalises; a threshold fitted to one image's histogram is not.
- **Validation.** A test asserting no fixture name or hash appears in `TradingCardScanner/`;
  human review item in §13.
- **Completion.** Test passes and the reviewer confirms no disguised equivalent (e.g. a threshold
  tuned to one image's exact histogram).

#### REQ-025 — Tests exercise the production pipeline
- **Objective.** Prevent a passing suite that tests a simplified helper.
- **Rationale.** Explicit brief concern, and a real risk given the amount of new internal structure.
- **Subsystem.** test target.
- **Required behaviour.** Every accuracy test enters through the same public API the view model
  uses. Internal stages may have their own unit tests **in addition**, never instead.
- **Constraints.** Do not widen production visibility purely to make a test easier; if a stage needs
  direct testing, expose it deliberately and keep the end-to-end assertion as the gating one.
- **Validation.** Review item; a test asserting the L1 suite calls the public entry point.
- **Completion.** Confirmed in review and by the call-graph of the accuracy suite.

#### REQ-026 — Evidence table
- **Objective.** One artifact mapping every fixture × every REQ to a measured result.
- **Rationale.** §13 requires it; the brief requires it.
- **Subsystem.** `review/centering-evidence/evidence-table.md`.
- **Required behaviour.** Rows = 10 HEIC + supplementary fixtures; columns = each metric in
  §5.1 plus each applicable REQ; cells = measured value and pass/fail, with before → after from
  `REQ-006`. TUNE/HOLDOUT marked. DEVICE-PENDING rows listed separately as open.
- **Constraints.** Every cell must cite the committed artifact it came from. No cell may be filled
  from memory, from a console log that was not retained, or from a run whose artifacts were overwritten.
- **Validation.** Review item in §13; a link-check that every cited artifact path exists.
- **Completion.** Table complete with no blank cells; every claimed pass traceable to a committed artifact.

---

### Group H — Revision B: unblock, repair, and close out

These seven requirements were added after the first implementation run. They do not replace
any earlier requirement; they are what the measured result showed is still missing.
**The procedural `REQ-027` ground-truth gate is complete, but the first accuracy run against
the rederived records is failing and the broader `REQ-030` closure remains open. The focused
`REQ-028` regression gate is green, with full-suite confirmation still pending. The rest
follow.**

#### REQ-027 — Re-derive ground truth
- **Objective.** Replace the provisional 5 px-grid estimates with geometry produced by the
  §6.2 procedure, so accuracy results become adjudicable.
- **Rationale.** The original audit found all 200 coordinates on a five-pixel grid and a
  provenance block that claimed work had not been performed. The old records were archived
  under `review/centering-evidence/ground-truth/provisional-2026-09-11/`; the current records
  are the independent reference used by the accuracy run below.
- **Subsystem.** `TestFixtures/TradingCards/GroundTruth/`, `review/centering-harness/gt_tool.py`.
- **Required behaviour.** Run §6.2 steps 2–7 for real: total-least-squares edge fits, corners
  as extrapolated line intersections, sub-pixel placement at the 50 % crossing of each edge's
  measured 10–90 % band, two independent passes with a recorded pre-reconciliation
  `agreementPx`, and the §6.2 step 6 aspect sanity check. Coordinates must be non-integral
  where the fit says so — a re-run that again lands on a 5 px grid has not been performed.
  `ambiguousEdges` must be exactly the set whose band exceeds 1.0 % H; revision A's records
  over-marked four edges (IMG_0347 right, IMG_0349 left, IMG_0350 right, IMG_0352 left) whose
  bands are below the cap. That over-marking was numerically harmless — `groundTruthEdgeTolerance`
  returns `max(band, clampedBand)`, which equals `clampedBand` below the cap — but the metadata
  must match the stated rule.
- **Constraints.** `gt_tool.py` must remain free of any `CardCenteringAnalyzer` import, and no
  field may be seeded from detector output. Do not adjust a reference to make a test pass.
  Existing overlay sheets are good and should be regenerated, not discarded.
- **Validation.** A test asserting no fixture's `provenance.method` begins `provisional_`; a
  test asserting the coordinate set is not wholly integral; the §6.2 aspect check; the
  `ambiguousEdges` rule check.
- **Current evidence (2026-09-12).** `gt_tool.py rederive` ran two analyzer-free profile
  passes over all ten oriented PNGs, reconciled fitted edge lines, applied the reviewed
  physical-silhouette selections, and wrote full diagnostics under
  `review/centering-evidence/diagnostics/GT-rederived/`. The ten current records use
  `analyzer_free_dual_profile_fit_with_visual_adjudication`, name both generic profile passes,
  retain non-integral coordinates and `agreementPx`, and pass the repository validator.
  `ambiguousEdges` is empty for all ten records under the measured-band rule. The IMG_0349
  right edge was resolved inward by approximately 63 px onto the reviewed physical card edge,
  not moved to match detector output. The prior records and new overlays remain separately
  traceable.
- **Validation.** The focused ground-truth XCTest run on the pinned iOS 26.5 iPhone 17 Pro
  executed 12 test cases: 8 passed and 4 failed. Provenance, schema, aspect, reachability,
  baseline, camera, and no-inner safety checks passed. The four failed test cases are the
  holdout ratio helper, the IMG_0780 art-window check, the all-fixture L1 production-entry
  point gate, and the IMG_0348 portrait-art-window check. The result bundle is
  `req027-ground-truth-after-rederive.xcresult` on the configured external SSD. These failures
  are now accuracy evidence against the current implementation; they do not invalidate the
  provenance procedure.
- **Completion.** The REQ-027 ground-truth/provenance gate is complete. Overall L1 accuracy and
  the remaining Definition-of-Done gates are not complete.

#### REQ-028 — Restore sideways and skewed detection (blocking)
- **Objective.** Eliminate the two `(0,0,0,0)` regressions.
- **Rationale.** The historical RC-11 regression was that the card-focused Vision request's
  `0.45…0.90` aspect gate could not emit an observation for a 1.417-aspect card, while the
  `0.45…2.0` post-filter could not recover an observation Vision never produced. The current
  request-level gate is widened to `0.45…2.0`, restoring the documented pre-rewrite capability
  that "a card photographed sideways is still a card"; the prior `(0,0,0,0)` result is retained
  as historical evidence.
- **Subsystem.** `CardCenteringAnalyzer.visionCardOutline`, fallback path.
- **Required behaviour.** Both orientations detect. Widen the request-level aspect admission
  (or run a second orientation-complementary request) so the gate matches the documented
  `0.50…2.00` policy, and diagnose the skewed case separately — it may be the fallback path
  (RC-13) rather than the same cause.
- **Constraints.** Widening the gate must not let the art window or a text box outrank the
  physical card; `REQ-009`'s shape constraint and INV-10's 4 % aspect guard still bind.
- **Validation.** `testACardPhotographedSidewaysIsStillFound` and
  `testStraightensASkewedCardBeforeMeasuring` pass; INV-10 still passes.
- **Current evidence (2026-09-12).** The correctly targeted focused run executed those two
  exact methods on the pinned iOS 26.5 iPhone 17 Pro simulator and passed 2/2 in 4.827 test
  seconds. The result bundle is `req028-correct-before.xcresult` on the external SSD. A first
  invocation named the wrong XCTest class and executed zero tests; it is explicitly discarded.
- **Completion.** The two focused regression tests are green, with no new failure observed in
  the focused analyzer class (20/20). The full final suite remains pending.

#### REQ-029 — Make inner-edge selection resampling-stable
- **Objective.** One fix for the mirror, quarter-turn, scale and EXIF invariants and the
  systematic ~5–6 px border shortening.
- **Rationale.** RC-12. E0 shows both fitted-outer translation and residual normalized-depth
  shifts across corresponding variants; the centroid experiment worsened the focused
  invariants, so the fix must address the measured axis/scale parameterization and phase
  behavior rather than assume that a different peak-selection rule is sufficient. Raising
  density 72 → 240 improved small-skew stability but moved none of mirror, quarter-turn,
  scale, or EXIF.
- **Subsystem.** `CardCenteringAnalyzer` inner-profile selection.
- **Required behaviour.** Make the selection continuous and resampling-invariant. *Mechanism is
  the implementer's choice* — sub-pixel interpolation about a stable peak, selecting by a
  physically-motivated criterion rather than raw `argmax`, hysteresis across candidates, or
  aggregating evidence before deciding are all acceptable. Investigate the ~5–6 px shortening
  as part of the same defect before treating it separately.
- **Constraints.** Must not reintroduce the "borders resemble each other" prior removed from
  `chooseInner` — unequal borders are what the tool exists to report. Each side stays
  independently evidenced.
- **Validation.** INV-4 ≤ 0.5 pp, INV-5 ≤ 0.5 pp, INV-6 ≤ 0.5 pp, INV-7 ≤ 1.0 pp; the eight
  ~5 px legacy failures in §3.5(a) resolve.
- **Revision-E decision.** The completion tolerances remain binding, but the sampling-level
  mechanisms listed above are closed by RC-19/RC-20 and may not receive further direct tuning.
  Candidate recall, semantic reference typing, and joint selection under REQ-042–REQ-044 must
  establish the next implementation mechanism.
- **Completion.** All four invariants pass and the legacy border errors are within their
  existing 4 px tolerance.

#### REQ-030 — IMG_0782 must decline (blocking)
- **Objective.** Restore the safety property.
- **Rationale.** The initial run showed `testMaskFailureDeclinesWithoutAnInnerReference`
  failing: a fixture whose GT carries `innerQuad: null` still produced a measurement.
  The focused post-change assertion now passes for IMG_0782 (`innerReference = .none`,
  `geometryInnerQuad = nil`, and no exposed ratio). Separately, IMG_0349 was reported
  `confident` while 60.3 px outside the then-current provisional GT; that historical comparison
  was resolved by the REQ-027 rederivation. `REQ-018` exists precisely so neither failure can be
  hidden.
- **Subsystem.** `CardCenteringConfidence`, decline path.
- **Required behaviour.** Absence of a gradeable inner reference forces `declined` with a
  reason, and no ratio is exposed. The confidence score must not reach `confident` when the
  outer geometry disagrees with the reference beyond `τ_e`. Do not satisfy this by
  desensitising the detector to a reference coordinate.
- **Constraints.** Declining must stay visually distinct from a measurement, and
  `detectionNotes` survival across manual adjustment must be preserved.
- **Validation.** `testMaskFailureDeclinesWithoutAnInnerReference`; the "never confidently
  wrong" assertion in `testL1PublicPipelineReportsEveryFixtureAndNeverConfidentlyWrong`.
- **Current evidence.** The no-inner-reference safety assertion passes at the default 1200-pixel
  path after the E-B shape gate, and the raw-fixture branch run produces 8 confident / 2 declined.
  The refreshed post-REQ-027 E7 resolution artifacts also show IMG_0782 declined at 1200,
  1600, 2000, and 2400 pixels. The no-inner safety behavior is confirmed at the four tested
  benchmark maxima. The current rederived-GT production-entry run executed 12 cases and
  passed 8 / failed 4; its all-fixture accuracy gate remains failing, so broader REQ-030
  closure is still open even though the missing-inner-reference assertion is green.
- **Completion.** The missing-inner-reference safety test and the four tested benchmark-mode
  decline checks pass; the all-fixture "never confidently wrong" gate remains failing.

#### REQ-031 — Resolve the latency-versus-resolution trade with evidence
- **Objective.** Reach a defensible budget rather than an unmet one.
- **Rationale.** RC-14. Revision A set ≤ 0.80 s median before the implementation chose 2400 px
  and two Vision passes. The current post-REQ-027 curve measures 2.706 s even at 1200 px. This
  may be a miss or a wrong budget; the plan does not currently know which stage dominates.
- **Subsystem.** `CardCenteringAnalyzer`, `REQ-022`'s test.
- **Required behaviour.** Measure accuracy against working resolution at, at minimum, 1200 /
  1600 / 2000 / 2400 px, reporting the §5.1 metrics at each. Then either (a) meet ≤ 0.80 s /
  ≤ 1.50 s at a resolution that still satisfies §5.1, or (b) propose a revised budget with the
  curve as evidence and the user's explicit agreement recorded in the evidence table. Cheaper
  wins — running the two Vision requests once, or detecting at lower resolution and refining
  edges at full resolution — should be explored before either.
- **Constraints.** Accuracy takes precedence over speed (`REQ-022`). A budget may be revised
  only under §5.2.2; it may not simply be edited in the test.
- **Validation.** The resolution/accuracy table, committed; `REQ-022`'s test passing at
  whichever budget is agreed.
- **Current evidence (2026-09-12).** The refreshed E7 tests passed 2/2 after REQ-027 ground-truth
  rederivation. Full-resolution detection measured median/max `2.706/2.935 s` at 1200 and
  `7.971/9.723 s` at 2400; low-resolution detection with full-resolution refinement measured
  `2.724/2.952`, `3.130/3.369`, `3.368/3.599`, and `3.660/3.848 s` at 1200/1600/2000/2400.
  The original `0.80/1.50 s` budget is therefore still failing at every tested point, and no
  revised budget has been agreed. Resolution reduction alone cannot close a 3.4x default-path
  median gap, and higher resolutions create safety regressions under RC-21. REQ-041 stage-level
  attribution precedes any optimization or budget proposal; 1200 remains the safety cap.
- **Completion.** Either the original budget is met, or a revised one is recorded with the
  curve and an explicit note of who agreed to it.

#### REQ-032 — Remove temporary diagnostics and record the negative results
- **Objective.** Leave the tree clean and the dead ends documented.
- **Rationale.** RC-15. `TEMP_PATH`, `TEMP_PROFILE`, `TEMP_VARIANT`, `TEMP_EXIF` and an
  unfinished EXIF test helper are in the tree; five reverted experiments exist only in
  conversation and will otherwise be repeated by the next person.
- **Subsystem.** `CardCenteringAnalyzer`, test target, `review/centering-evidence/`.
- **Required behaviour.** Every `TEMP_*` diagnostic is removed or promoted to an intentional,
  named test. The EXIF helper is finished or deleted — not left half-built. A short
  `review/centering-evidence/experiments-log.md` records each reverted experiment, what it was
  meant to fix, and what it measured: profile density 72 → 240 (kept), mean-vs-median
  aggregation (reverted), luminance-based profile evidence (reverted), canonical/homography
  profile sampling (reverted, made things worse), forcing the scalar path (reverted, invariants
  unchanged — a useful negative result), parabolic depth refinement (temporary), and the
  decision not to re-run detection after presentation rotation (kept, with the reason).
- **Constraints.** A `grep` for `TEMP_` in `TradingCardScanner/` must return nothing.
- **Validation.** Source-scan test; the log exists and names all seven.
- **Completion.** Scan clean, log committed.

#### REQ-033 — Correct the stale status record and enforce the adjudication rule
- **Objective.** Stop a stale document from misdirecting the next run, and make §5.2.1 binding.
- **Rationale.** `after/simulator-status-2026-09-11.md` states the simulator was unavailable;
  it was recovered and the full suite ran for 294 s. Left as-is, it justifies skipping the
  runtime work indefinitely. Separately, §5.2.1 needs somewhere it is checked.
- **Subsystem.** `review/centering-evidence/`.
- **Required behaviour.** Rewrite the status file to record both periods honestly: the
  transient `CoreSimulatorService` loss, the recovery command, and the 2026-09-11 full-suite
  result with its 1045/24/7 split and the three-way failure classification of §12.1. The
  evidence table gains a column or note distinguishing historical *unadjudicated* results
  (captured before `REQ-027`) from current *failing* results. No cell may read
  `OPEN — simulator unavailable` once the suite has run.
- **Constraints.** Do not delete the original observation; it happened. Amend, don't erase.
- **Validation.** A test asserting the status file contains the post-recovery run result; a
  review item that no evidence cell claims simulator unavailability after 2026-09-11.
- **Completion.** Status file amended, evidence table distinguishes the three states.

### Group I — Revision C: raw-fixture diagnosis and profile follow-up

These requirements record the work prompted by the raw-HEIC E-A diagnosis and the E0/E1
measurement audit. They do not loosen any existing tolerance. REQ-034 and REQ-035 are
evidence/availability gates; REQ-036 through REQ-038 must be completed before another
detector-tuning experiment is treated as meaningful.

#### REQ-034 — Record the raw-fixture inner-branch diagnosis
- **Objective.** Make the reason for each automatic inner-reference branch auditable on the real
  HEIC corpus.
- **Rationale.** The pre-E-B screenshot result was 3 confident / 7 declined, and the decline
  pattern suggested scalar pinning. A branch-level count cannot be explained by a ratio result
  alone.
- **Subsystem.** DEBUG-only analyzer diagnostics and `OpusImplementationPlanTests`.
- **Required behaviour.** Run all ten raw HEIC fixtures through the public analyzer entry point
  and retain one named JSON record per fixture containing `scalarOuterAgreesWithVision`,
  `scalarPinned`, `outlineHasInner`, `innerSource`, selected outer source, and profile failure
  reasons. The diagnostic must not affect production behavior.
- **Constraints.** Records must identify the actual input and run state; a generated filename
  must never collapse multiple fixtures into one file.
- **Validation.** `testEADiagnoseInnerReferenceBranchForAllRealFixtures` and the ten records under
  `review/centering-evidence/diagnostics/EA/`.
- **Completion.** All ten records are present and the branch table is reproduced in the evidence
  table and experiments log.

#### REQ-035 — Restore independent inner evidence without breaking the decline safety gate
- **Objective.** Prevent scalar pinning from discarding a gradeable inner reference while keeping
  an image with no inner reference declined.
- **Rationale.** The original raw run lost all five sleeved inner references. Running the profile
  from the selected outer recovered evidence; a global coverage relaxation incorrectly made
  IMG_0782 confident.
- **Subsystem.** `CardCenteringAnalyzer` inner-profile arbitration and confidence/decline path.
- **Required behaviour.** When scalar evidence is pinned but the selected outer remains
  approximately card-shaped, evaluate independent inner evidence relative to that selected outer.
  Do not use a malformed scalar outline to bypass the strict coverage guard. No-inner-reference
  input must still expose no ratio and no geometry inner quad at every supported analysis mode.
- **Constraints.** This is a general shape/evidence rule; no fixture name, hash, or exact image
  dimensions may enter production code. Accuracy is evaluated against the rederived GT, but
  this requirement does not waive any L1 tolerance.
- **Validation.** The five-fixture E-B regression test, the IMG_0782 safety test, and a resolution
  sweep covering the E7 benchmark maxima.
- **Completion.** The five sleeved fixtures retain independent inner evidence and the no-inner
  safety property declines IMG_0782 at the default and benchmark resolutions, without a new
  confident-and-wrong result after GT is re-derived.

**Current evidence.** The default raw-HEIC E-A/E-B path is 8 confident / 2 declined. The refreshed
post-REQ-027 E7 artifacts show IMG_0782 declined at all four benchmark maxima in both the
full-resolution and low-detection curves. The safety behavior is confirmed for the tested
benchmark modes; broader supported-mode coverage remains open. The first current accuracy
run against rederived GT is separately recorded under REQ-027 and still fails its L1-related
test cases.

#### REQ-036 — Make metamorphic diagnostics production-equivalent
- **Objective.** Measure mirror, quarter-turn, and scale behavior from the original HEIC input at
  a common effective card resolution.
- **Rationale.** E0 and historical E1 render to 900x1200 before applying variants, and the card
  size changes materially across variants. Their displacement values are useful for
  localization but are not safe detector-tuning evidence. E-C is the named replacement.
- **Subsystem.** The in-target metamorphic harness and its retained diagnostics.
- **Required behaviour.** Start every variant from the original fixture bytes, preserve the same
  declared orientation/display path, and rescale each variant from its GT quad so the card's
  working-pixel size matches the base within ±0.5%. Retain both the unnormalized and equalized
  measurements and state which one is used for each conclusion.
- **Constraints.** The harness must not alter production code or ground truth and must not call
  private analyzer helpers in place of the public entry point.
- **Validation.** A per-variant record includes source dimensions and GT-derived working card
  dimensions; a test asserts the equalized values are within ±0.5%.
- **Completion.** E-C starts from the original HEIC bytes, records raw and equalized variants
  with source dimensions, passes the ±0.5% GT-derived working-card-size assertion, and is
  retained as `diagnostics/E1/resolution.json`. The old E0/E1 values remain labeled historical.

#### REQ-037 — Refine the proposed outer quad with deterministic subpixel edge fits
- **Objective.** Separate Vision's region proposal from the physical card-edge measurement.
- **Rationale.** E0 shows fitted-outer translation contributing to residual drift, while E4 shows
  that the same 10–90%/50% edge definition can be applied independently of the detector.
- **Subsystem.** `CardCenteringAnalyzer` outer-edge refinement.
- **Required behaviour.** Vision may propose a region; each outer edge is then refined from the
  original working pixels using a deterministic normal profile, a measured 10–90% band, and a
  line fit with virtual-corner intersections. The operation must be equivariant under mirror,
  quarter-turn, and uniform scale within the stated tolerances.
- **Constraints.** Do not fit to provisional GT or choose a transition because it matches a
  provisional reference. Preserve sleeve/card disambiguation and the existing shape guard.
- **Validation.** A failing regression test precedes the production change; raw-HEIC metamorphic
  tests and the legacy analyzer class are rerun afterward.
- **Current evidence.** The pre-change acceptance test failed because no refinement was
  accepted. The initial unconstrained fit passed that acceptance test but caused eight legacy
  assertions across six retained synthetic tests. A local-offset guard of
  `max(8 px, 2% of the short edge)` restored `CardCenteringAnalyzerTests` to 20/20, and the
  E-D acceptance test passed again on raw IMG_0783. The first post-fit invariant run also
  exposed roll drift; preserving the proposed roll restored INV-3 in the current targeted
  rerun. E-D2 then showed coherent 28–35 px outward left-edge candidates on four fixtures that
  the 14–15 px guard rejects, plus a separate low-support bottom-edge rejection on IMG_0348;
  no widening was adopted. INV-4/5/7/8 remain above tolerance, so the completion criterion is
  not met. Accuracy
  is now adjudicable against the rederived GT: the current L1 result remains failing and does
  not close the REQ-037 completion criterion.
- **Completion.** Outer-line drift is reduced with evidence from REQ-036 and no legacy
  regression is introduced. The current targeted invariants and rederived-GT L1 run still
  leave the overall completion criterion open.
- **Revision-E decision.** The 2% guarded implementation is frozen as the baseline. Further
  guard widening or single-feature acceptance rules are closed; REQ-042–REQ-044 replace that
  execution path with candidate recall and joint physical-role selection.

#### REQ-038 — Re-evaluate inner-profile normalization after outer refinement
- **Objective.** Determine whether residual inner-edge drift remains after the outer reference is
  stable.
- **Rationale.** The earlier E2 normalized profile changed the sampling mechanism but could not
  distinguish outer-line movement from inner-depth movement. It must not be used to mask an
  upstream geometry error.
- **Subsystem.** `innerQuadFromProfiles` and its E0/E1 successor diagnostics.
- **Required behaviour.** Re-run the normalized-depth, card-relative-radius, inward-normal
  profile experiment after REQ-037, comparing selected normalized depths, support, threshold, and
  line displacement per edge.
- **Constraints.** Keep the 240-point along-edge median and bounded refinement unless a new
  failing test and measured reason justify changing them. Do not tune a profile solely to
  reproduce a reviewed reference coordinate.
- **Validation.** The production-equivalent metamorphic harness, legacy analyzer tests, and a
  retained per-edge comparison artifact.
- **Current evidence.** E-D now runs the profile from the proposed/refined outer geometry.
  The E-E diagnostic passed on raw and effective-resolution-equalized HEIC variants, producing
  24 snapshots and 96 per-edge records in `diagnostics/ED/profile-normalization.json` and
  `.md`. Raw/equalized records matched at the active 1200-pixel cap. Across the hard sleeved
  fixture, outer-line displacement reached 5.19 working px and selected normalized-depth
  displacement reached 0.0061; clean-fixture scale displacement stayed below 1 px. Threshold
  and support changes were generally small, so the residual is classified as both outer-line
  motion and profile depth selection rather than as a raw/equalized harness artifact. The
  current targeted invariant failures remain metamorphic evidence; the separate rederived-GT
  production run is now adjudicable and is recorded under REQ-027.
- **Completion.** Complete for diagnostic classification: the residual is both outer geometry
  and profile depth selection. Revision E does not authorize another sampling change from this
  result; further production work proceeds through REQ-039–REQ-045.


### Group J — Revision E: bounded perception-architecture spike

The evidence above closes the prior local-tuning sequence. `REQ-029` and `REQ-037` remain
unmet acceptance requirements, and `REQ-038` remains the completed cause classification, but
no further sampling, smoothing, radius, interpolation, fixed-offset, or transition-width tweak
is authorized directly under them. The next implementation work must proceed through
`REQ-039`–`REQ-045`. This preserves the plan's original tolerances while replacing the failed
perception hypothesis.

#### REQ-039 — Freeze the current baseline and close the sampling experiment class
- **Objective.** Prevent repeated rediscovery of sampling-level approaches that cannot resolve
  semantic wrong-feature selection.
- **Rationale.** Thirteen-plus experiments changed aggregation, colour evidence, resampling,
  radius, smoothing, refinement, canonicalization, or local acceptance. E7 still reports 0/8
  correct confident numeric readings at 1200, and the front T/B error remains approximately
  21 pp over a 2x resolution sweep.
- **Required behaviour.** Preserve the current 1200-pixel, 2%-guard implementation and its
  focused 20/20 analyzer baseline as the comparison point. Run a fresh full-suite baseline on
  the pinned iOS 26.5 simulator before the spike. Prefer a normally signed test run; if
  `CODE_SIGNING_ALLOWED=NO` is unavoidable, pre-declare the six expected Keychain
  `errSecMissingEntitlement` exclusions in the baseline record before interpreting failures.
  Re-audit IMG_0783's GT transitions because its `agreementPx = 4.43` is materially higher than
  the other records.
- **Constraint.** The closed experiment class may be reopened only when candidate-level evidence
  shows that the correct semantic feature already wins and only its subpixel placement remains
  outside tolerance.
- **Completion.** A dated baseline bundle and summary are retained; IMG_0783 is confirmed or
  corrected through the existing analyzer-free GT procedure; the experiment ledger names the
  closed class explicitly.

#### REQ-040 — Replace the development-exposed holdout with varied capture evidence
- **Objective.** Restore a meaningful generalisation test.
- **Rationale.** The original ten fixtures share one photographer, background, lens, and session,
  and every old holdout has been exposed to analysis or tuning decisions.
- **Required behaviour.** Add at least 30 new captures spanning different photographers or
  capture sessions, backgrounds, devices/lenses, Camera.app and in-app capture, imports,
  sleeved/unsleeved cards, backs, conventionally framed fronts, foil/full-art fronts, and slabs
  where available. Freeze at least 10 as HOLDOUT before feature design; the holdout must differ
  in capture conditions, not merely card identity. The current ten become `DEV-HISTORICAL`.
- **Ground-truth requirement.** Apply the REQ-027 analyzer-free process. For a physical subset,
  compare image-derived ratios with caliper or calibrated-flatbed measurements to test the
  remaining absolute-GT assumption.
- **Completion.** The new manifest records cohort and capture provenance; no spike constant or
  branch was chosen after inspecting frozen-holdout outcomes.

#### REQ-041 — Profile stages and cap resolution as a safety control
- **Objective.** Attribute the 2.706-second minimum-path median before optimizing or revising the
  budget, and prevent resolution-induced confidence catastrophes.
- **Required behaviour.** Record wall time separately for decode/orientation/downscale, colour
  preparation, Vision requests, scalar fields, outer candidate/refinement, inner candidate
  generation, joint selection, rectification, and result construction over all development
  fixtures. Record repeated-run median and max for each stage. Until REQ-044 passes its stability
  gate, production and benchmark decisions use a maximum working dimension of 1200.
- **Constraint.** Do not infer the cost centre from loop counts; the approximately 300k profile
  samples are a hypothesis to measure. Do not revise the 0.80/1.50-second target here.
- **Completion.** At least 90% of measured time is attributed to named stages, and the next
  performance task names a measured bottleneck rather than a resolution guess.

#### REQ-042 — Separate candidate recall from candidate selection
- **Objective.** Determine whether failures occur because the correct feature is absent or
  because the selector chooses the wrong available feature.
- **Required behaviour.** For every outer and inner side, retain all candidate lines/regions with
  source, native/normalized geometry, support, transition statistics, proposed semantic role,
  and rejection reason. Compare candidate geometry to GT only in the evaluation harness, never
  in production selection. Report role-specific candidate recall before tuning a selector.
- **Validation.** The ledger must expose the candidates competing with IMG_0348/IMG_0780
  art-window top/bottom, the card-versus-sleeve candidates in the E-D2 cases, and the absence of
  a gradeable reference for IMG_0782.
- **Completion.** Correct candidate recall is at least 95% on the development set for each
  declared automatically supported reference class, or the deficient generator is named and
  the selector spike does not proceed for that class.

#### REQ-043 — Make reference type an explicit semantic decision
- **Objective.** Replace the universal `art_window` default with a verifiable choice of
  `printed_border`, `art_window`, or `none`.
- **Back-first branch.** Attempt automatic card-back recognition before generic inner searching.
  Pokémon and Magic backs come from a small set of fixed designs; when a reviewed template or
  robust feature match clears its false-positive margin, derive the printed border from the
  template's card-relative coordinates rather than searching each side independently. Validate
  against transformed/resampled backs and fronts that must not match. A failed or ambiguous
  template match falls through; it never forces a result.
- **Front branches.** Distinguish conventionally framed fronts from full-art/borderless and
  no-reference cases. A framed-front detector may search for a coherent art-window region;
  title/header and type/text-box boundaries must be retained as competing candidates rather
  than silently accepted as top/bottom. Full-art/borderless ambiguity declines to guided manual
  adjustment unless a separately validated detector exists.
- **Constraint.** OCR/card identification is not required. If upstream product state already
  knows the face/reference class, consume it; otherwise permit a lightweight user confirmation
  only when the automatic margin is insufficient.
- **Completion.** Reference type is correct on every confident development and frozen-holdout
  result. All five current backs report `printed_border` when confident; IMG_0782 reports `none`.

#### REQ-044 — Select physical geometry jointly and make stability part of confidence
- **Objective.** Replace independent per-edge winners and hard local guards with one coherent
  interpretation of card, sleeve, and inner reference.
- **Required behaviour.** Vision, contours, templates, and profiles may propose candidates. A
  joint selector chooses four outer edges and the role-appropriate inner geometry using aspect,
  line continuity, parallelism, nesting, sleeve/card ordering, complete-edge support, and the
  score margin to the next valid interpretation. Opposite edges and reference role are decided
  together; one broad transition may not authorize an unrelated complete quad.
- **Stability requirement.** Candidate identity and confidence state must remain stable under
  the declared mirror, quarter-turn, crop, scale, and supported-resolution transforms. A result
  that changes semantic candidate or crosses from decline to confident with a large ratio change
  must decline.
- **Completion.** REQ-029 and REQ-037 tolerances pass without breaking the retained synthetic
  suite, and confidence includes semantic-role correctness, independent-source agreement,
  best-versus-second-best margin, and transform/resolution stability.

#### REQ-045 — Apply a hard go/no-go gate and choose the product path
- **Objective.** Bound the spike and prevent indefinite heuristic tuning.
- **Hard safety gate.** **Zero confidently-wrong outputs on the frozen holdout.** A confident
  reading exceeding either 2.0 pp ratio tolerance is a failure and cannot be traded against
  automation rate, average error, latency, or visual plausibility.
- **Quality gates.** For declared automatically supported reference classes: at least 95%
  correct-candidate recall, at least 80% confident-and-correct automatic coverage, HOLDOUT pass
  rate within 15 percentage points of development, all applicable invariants green, and a
  measured path toward approximately one-second on-device response without exceeding the
  current budget unless REQ-031 is formally revised.
- **Decision.** If all gates pass, continue the automatic architecture through L1/L2/L3/device
  completion. If the hard safety gate fails, stop automatic release. If safety passes but
  coverage or semantic separation fails—especially for full-art/foil inputs—ship the reliable
  automatic subset with immediate guided manual correction as a first-class path. Do not reopen
  the closed sampling experiment class as the fallback plan.
- **UX completion for the hybrid path.** Show the image and editable guides immediately, state
  why automation declined, preserve live ratio updates, and complete the pending manual-correction
  screenshot and interaction review under REQ-017/REQ-021.


---

## 10. Simulator validation loop

Model on `scripts/ui_build_and_shoot.sh`, but **fix its two defects**: one overwritten filename,
and output into gitignored `artifacts/`.

**Required flow per fixture:**
1. Build and install to a pinned simulator (record device name, OS version, `UIScreen.scale`).
2. Launch with a debug route that loads **the real HEIC fixture** through
   `CardCenteringViewModel.loadImageData` — the same entry the file importer uses.
   *(The existing `Centering` route calls `loadDebugFixtureIfNeeded()`, which loads a synthetic
   drawn rectangle. That route cannot validate anything and must be extended, not reused as-is.)*
3. Wait for analysis to settle deterministically — poll for a settled state, do not `sleep 2.5`.
4. Capture a screenshot to `review/centering-evidence/after/screenshots/<FIXTURE>_<ROUTE>.png`.
5. Emit `<FIXTURE>_<ROUTE>.json`: presented image frame, screen scale, measured guide positions,
   GT mapped to screen space, per-metric deltas, confidence, decline state.
6. Also capture at least one **declined** fixture and one **manually corrected** fixture, so the
   fallback path has screenshot evidence too.

**Screenshot scaling is a known measurement hazard.** The harness must record the screen scale
and the presented image rect and perform all comparisons in a single declared space. A test must
verify that a deliberately injected 2 px guide offset is *detected* by the screenshot measurement
— otherwise the measurement is not sensitive enough to be evidence.

---

## 11. Required tests

**Numeric (L1).** Per fixture: detection success; outer-edge normal error ×4; corner error ×4;
centre displacement; rotation error; rectification residuals; inner-edge error ×4; ratio error;
confidence sanity.

**Metamorphic (L2).** INV-1 … INV-10 (§8). Derived variants are generated in-test from the real
fixtures so the expected answer is known exactly. Rotation variants must be padded with a
plausible background, not white, so the padding does not itself become the detection target.

**Rendering (L3a).** `REQ-019`, `REQ-020` with injected geometry and no detector.

**End-to-end (L3b).** `REQ-021` simulator loop over all 10 fixtures.

**Regression.** The historical pre-implementation suite (987 tests were recorded as passing in
the original plan) must still pass after the change. The 27
existing synthetic centering tests must be **kept and must still pass**; if a genuine behaviour
change invalidates one, the change must be justified in the evidence table, not deleted quietly.

---

## 12. Device-only validation (cannot pass in the simulator)

Open as explicit **DEVICE-PENDING** gates. They may not be marked passed by simulator work.

- **DEVICE-PENDING-1 — Macro/ultra-wide capture geometry.** The app's own ultra-wide capture at
  `minAvailableVideoZoomFactor` has a wider field of view and more barrel distortion than the
  Camera.app macro fixtures. Requires real captures through `CenteringCameraView` on a
  macro-capable iPhone, run through the full pipeline, with GT annotated.
- **DEVICE-PENDING-2 — Wide-lens capture on a non-macro device.** Exercises the
  `!hasMacroLens()` branch, which no simulator run reaches.
- **DEVICE-PENDING-3 — Geometric distortion correction.** Whether
  `isGeometricDistortionCorrectionEnabled` is supported and what it does to card straightness is
  device- and lens-specific.
- **DEVICE-PENDING-4 — Level indicator vs measured tilt.** `CMMotionManager` gravity is
  unavailable in the simulator; confirming that "Level" corresponds to a rectification residual
  inside `REQ-016` needs hardware.
- **DEVICE-PENDING-5 — On-device latency.** `REQ-022`'s budget must be re-measured on device;
  simulator timings are not predictive.

### 12.1 Environment facts the next run needs (revision C)

**Simulator recovery.** `CoreSimulatorService` dies transiently. It recovers on a fresh
`xcrun simctl list devices`, then `xcrun simctl boot EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86`
and `xcrun simctl bootstatus … -b`. A device-SDK `build-for-testing` is **not** a substitute:
the 2026-09-11 compile succeeded while 17 runtime failures were present. Treat a green compile
as evidence of compilation only.

**Keychain failures are a harness artifact, not a defect.** Running with
`CODE_SIGNING_ALLOWED=NO` makes six tests fail with `storeFailed(-34018)` =
`errSecMissingEntitlement`: `ProductIdentityTests` (×3),
`AppleAccountCredentialsSurfaceTests/testCredentialsTrimAndClearWithoutLosingTheStoredDisplayName`,
`ProductFallbackTests/testDirectMagicTreatmentHandleReachesVendorAndReturnsPrice`,
`OpusImplementationPlanTests/testREQ013ImportedSealedRowConvergesWithBrowseAdd`. Either run
signed, or exclude them explicitly and say so (§5.2.3). Do not chase them as centering bugs.

**One pre-existing failure is outside this branch.**
`MagicTreatmentTests/testTreatmentQualifiedDisplayLabelsCoverAtLeastTwentyDualFinishFixtures`
("Nonfoil · Plastic" leaking onto a nonfoil copy) — `git diff` shows this branch touches no
Magic treatment source. Report it; do not fix it here.

**Disk.** The internal Data volume was previously measured at ~4.4 GiB free against ~535 GiB on
the external volume. The user-provided external artifact/cache root is
`/Volumes/Keller Family Photos/June 10 2026 dump (move)/AdditionalStorage`; subsequent build and
benchmark commands must place DerivedData and other repeatable large outputs there where the
tool permits. XcodeBuildMCP wrapper logs may still land under its own workspace directory.
Confirm free space before a full run; a truncated run is not a result.


---

## 13. Definition of Done — fixed before implementation

Success requires **all** of the following. Passing tests alone is explicitly **not** sufficient.

> **Revision E gating order.** Items 0a–0c below were added after the first implementation run;
> 0d and 0e record the raw-branch and resolution-stability checks added on 2026-09-12. The
> REQ-027 provenance gate is now complete, so the current L1 failures are adjudicable rather
> than provisional. Nothing in 1–17 has been weakened.
>
> - **0a — `REQ-027`.** Ground truth is non-provisional. The ten current records satisfy the
>   provenance, subpixel, agreement, aspect, non-integral-coordinate, and ambiguity checks;
>   the first production-entry-point accuracy run against them is recorded as 8/12 test cases
>   passed and 4 failed.
> - **0b — `REQ-028`, `REQ-030`.** No `(0,0,0,0)` detection, and IMG_0782 declines.
> - **0c — `REQ-033`.** The stale simulator-status record is corrected, and the evidence table
>   distinguishes *passing* / *failing* / *unadjudicated*.
> - **0d — `REQ-034`, `REQ-035`.** Raw-fixture branch evidence is retained, the five sleeved
>   fixtures have independent inner evidence, and IMG_0782 still declines at the default path.
> - **0e — `REQ-036`.** Metamorphic evidence is production-equivalent, or the older harness is
>   explicitly labeled diagnostic-only and is not used to tune the detector.
> - **0f — `REQ-039`–`REQ-045`.** The current detector is frozen as baseline; a varied fresh
>   holdout replaces the exposed split; stage cost and candidate recall are measured; reference
>   type and geometry are selected semantically and jointly; and the bounded spike reaches a
>   documented automatic-versus-hybrid product decision.
>
> Additional revision-B/C gates, evaluated after 0a–0f: `REQ-029` (all four resampling
> invariants), `REQ-031` (latency met or formally revised with the resolution/accuracy curve
> and recorded agreement), `REQ-032` (no `TEMP_*` in production, experiments log committed),
> `REQ-037` (deterministic outer refinement), and `REQ-038` (post-refinement inner-profile
> classification).

1. All 10 HEIC fixtures have committed, independently produced ground truth (`REQ-001`) with
   overlay sheets (`REQ-003`).
2. All 10 evaluated through the **production** entry point (`REQ-025`), every §5.1 metric recorded.
3. Outer-edge, corner, centre, inner-edge and ratio tolerances met per §5.1; any fixture not
   meeting them **declines** and is never confidently wrong.
   **The frozen holdout permits zero confidently-wrong outcomes; this is a hard, non-tradeable
   gate.**
4. Rotation: INV-3 satisfied across the full θ sweep on ≥ 9/10 fixtures, symmetric within 0.15°.
5. Orientation: INV-6 satisfied for EXIF 1/3/6/8.
6. Metamorphic INV-1, 2, 4, 5, 7, 8, 9, 10 all satisfied at the stated tolerances.
7. Upload/import path and camera-originated path both covered; lens convergence resolved
   (`REQ-014`) or an open DEVICE-PENDING gate recorded.
8. Simulator screenshots produced for all 10 fixtures plus ≥ 1 decline and ≥ 1 manual-correction
   case, committed under `review/centering-evidence/after/screenshots/`.
9. Numeric screenshot validation passed (`REQ-021`), including the injected-offset sensitivity check.
10. **Screenshots independently reviewed by a human or a second model** against a written
    checklist, with the reviewer's name/date recorded. Metrics passing does not waive this.
11. Full regression suite green; the 27 pre-existing synthetic centering tests retained
    **and passing** — 10 of them were red on 2026-09-11 (§3.5a), which the device-SDK
    compile did not reveal. Environmental failures (§12.1) are named and excluded
    explicitly, never silently.
12. `REQ-024` satisfied — no fixture-specific behaviour, confirmed by test *and* review.
13. `REQ-002` / `REQ-040` satisfied — a capture-condition-diverse, previously unseen HOLDOUT
    pass rate is reported and within 15 pp of development. The exposed historical split does
    not satisfy this item.
14. Manual fallback demonstrably functional (`REQ-017`), including recovering a declined fixture.
15. Evidence table complete (`REQ-026`) with before → after, and every claimed pass traceable to
    a committed artifact.
16. Performance budget met and recorded (`REQ-022`), with the device gate left open.
17. Every DEVICE-PENDING gate listed as **open**, not silently closed.

**Explicitly insufficient:** "all tests pass"; "the screenshots look centred"; a green suite whose
tolerances were widened during implementation; ground truth adjusted after seeing detector output;
**a successful `build-for-testing` offered in place of a test run** (2026-09-11: the compile
succeeded while 17 runtime failures were present); **a detector changed to agree with provisional
ground truth** (§5.2.1); a failure count that quietly omits environmental failures instead of
classifying them (§5.2.3).

---

## 14. Non-goals

- No user-facing crop, auto-straighten-and-save, or "corrected image" export.
- No change to the scanner feature (`CardScanner`, `CardLatch`, `ScannerViewModel`). It has its
  own in-flight work; do not touch it.
- No change to the exported PNG's panel layout, palette, or filename format.
- No OCR-based card identification in the centering path.
- No grading-company score prediction — the tool reports geometry, not a grade.
- No ML model unless it can be justified against §5.1 *and* run inside `REQ-022`'s budget; the
  default assumption is classical geometry.
- No support for multiple cards in one frame.
- No new persistence or collection integration.

---

## 15. Self-falsification review

The plan was tested against the brief's challenge list; each answer changed the plan.

**"Could Luna pass the tests while still visually mis-centring a card?"**
Mitigated three ways: `REQ-021` measures guides *in the screenshot*, DoD-10 requires independent
human review of those screenshots, and `REQ-019`/`REQ-020` test rendering with injected geometry
so a rendering bug cannot hide behind detection tolerance. Residual risk: a systematic bias
present in both GT and detector. `REQ-001`'s two-annotator rule and the aspect-physics check
(§6.2 step 6) are the guards.

**"Could the detector overfit 10 images?"** Very likely without help — one photographer, one
background, one lens, one session. The original holdout has now been development-exposed, so
its label no longer supplies the intended protection. `REQ-040` replaces it with a frozen set
that varies capture conditions; `REQ-024` still forbids fixture identity, INV-7/INV-8 still
break location heuristics, and `REQ-013` still requires supplementary input paths.

**"Are GT annotations independent enough?"** Strengthened after this question: `gt-tool` may not
link the analyzer, two independent passes are required, `agreementPx` is recorded, and edge
positions come from a sub-pixel profile fit rather than a click.

**"Are rotation and centring measured separately?"** Yes — `REQ-015` (angle vs applied angle) is
independent of `REQ-008`/`REQ-021` (ratio). INV-3 sweeps angle without reference to the ratio.
This matters because §3.2 shows the two failures are currently entangled.

**"Are camera and import paths actually equivalent?"** At the analyzer, yes — verified: all three
inputs converge on `Data`. They differ in *optics* and in *EXIF variety*. `REQ-014` addresses
optics; `REQ-013` addresses EXIF; DEVICE-PENDING-1/2 cover what the simulator cannot.

**"Could screenshot scaling make pixel measurements misleading?"** Yes. §10 requires recording
`UIScreen.scale` and the presented image rect, comparing in one declared space, and an
**injected-offset sensitivity test** proving the measurement can actually see a 2 px error.

**"Are coordinate-space conversions tested?"** `REQ-005` makes the mapping explicit and
round-trip tested, precisely so a conversion bug cannot be mistaken for detection error.

**"Could perspective correction produce a centred but distorted result?"** This is the plan's
most dangerous failure mode, because such a result *looks* better. `REQ-016` therefore gates on
three independent residuals (parallelism, aspect, GT-corner reprojection) and must decline rather
than ship a plausible-looking rectification.

**"Are tolerances justified or convenient?"** Every number in §5.1 derives from a measurement in
§3.4 or from geometry (0.20° ⇒ 3.8 px over an 1100 px edge). The per-edge `τ_e` is computed from
that edge's own measured transition band, so it cannot be loosened without changing recorded GT.

**"Could a reviewer audit every claimed success from retained artifacts?"** Only after `REQ-023`
— the existing harness writes one overwritten file into a gitignored directory. That was found
during this investigation and is why `REQ-023` exists.

**Two weaknesses this review could not fully remove, stated plainly:**
- The corpus includes sleeved and apparently un-sleeved cards, but has no non-iPhone, normal-lens,
  flatbed, or slab image and still comes from one photographer/background/session. `REQ-013` and
  `REQ-040` require those conditions before generalisation may be claimed.
- `expected.lrRatio` in ground truth is derived from annotated geometry, not from a calibrated
  physical measurement of the cards. It is therefore *consistent* ground truth, not *absolute*
  ground truth. `REQ-040` requires a physical or calibrated-flatbed cross-check on a subset.
