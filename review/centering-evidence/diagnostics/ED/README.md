# E-D deterministic outer-edge refinement

This directory documents the E-D production change and its focused validation. The experiment
uses the public analyzer entry point and the original working pixels. It does not read or tune
against ground-truth coordinates.

## Current result

On the pinned iOS 26.5 iPhone 17 Pro simulator
(`EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86`), with DerivedData and result bundles on the external
SSD:

- The test-first baseline correctly failed because no refinement was accepted.
- The initial unconstrained 10–90% normal-profile fit passed its acceptance smoke test but
  caused eight assertions across six retained synthetic analyzer tests by following interior
  artwork or banners.
- A general local-offset guard of `max(8 px, 2% of the short edge)` restored
`CardCenteringAnalyzerTests` to the historical 20/20, and the raw IMG_0783 acceptance test remained green.
  The latest post-E-REQ044 analyzer regression run is 21/21; the older 20/20 count is retained
  only to identify the pre-existing validation run.
- The initial post-fit invariant run exposed roll drift and produced 71 assertions. Preserving
  the Vision proposal's roll signal while retaining the refined quad for physical geometry
  restored INV-3.
- The pre-E-REQ044 post-roll targeted run executed 25 tests: the 20-test analyzer class passed;
  INV-3 passed; INV-4 failed at 1.4 pp; INV-5 failed at 0.7/1.4/1.1 pp for 90/180/270°;
  INV-7 failed at 1.4 pp; and INV-8 failed at 1.1 pp. Six assertions failed total.
- A pre-E-REQ044 confirmation run then executed the E-A raw-fixture diagnostic, the five-fixture
  E-B regression, and the E-D acceptance test. All three passed in 43.805 test seconds; E-A
  remained 8 confident / 2 declined, with IMG_0782 declined for missing inner reference.
- The REQ-038 E-E diagnostic then passed in 90.912 test seconds and wrote 24 variant/space
  snapshots with 96 per-edge records to `profile-normalization.json` and `.md`. Both raw and
  equalized records are identical at the active 1200-pixel working cap.
- The follow-up E-D2 telemetry test passed in 27.568 test seconds and recorded the complete
  per-edge acceptance decisions for all ten raw fixtures. It found coherent outward transitions
  roughly 28–35 working pixels from the Vision proposal on the left edges of IMG_0347, IMG_0350,
  IMG_0352, and IMG_0781; the current 14–15 pixel local guard rejects those transitions. IMG_0348
  instead failed on bottom-edge support (6 accepted samples versus 11 required). This is a guard
  hypothesis, not proof that the large transition is the physical edge, so no blanket widening was
  adopted. The artifact is `outer-refinement.json` and the per-fixture files in this directory.
- A follow-up feature-gate attempt used the ratio of median transition width to median peak-gradient
  strength, with a complete-quad extension when the ratio reached 6.0. It accepted the four E-D2
  photo cases but reproduced 7 retained synthetic regressions, because unrelated synthetic edges
  also activated the complete-quad extension. The attempt was discarded and the 2% per-edge guard
  restored; its expected-red and candidate result bundles are `ed3-baseline.xcresult` and
  `ed3-candidate.xcresult` on the external SSD.

The targeted invariant result bundle is `post-ED-roll-repair-invariants.xcresult`, and the
final-state confirmation bundle is `post-ED-branch-confirmation.xcresult`, both under the
configured external-SSD artifact directory. These are pre-E-REQ044 implementation records.
E-E closes the REQ-038 diagnostic-classification portion: the residual is attributable to both
outer-line displacement and profile depth selection, not to the raw/equalized harness difference
alone. E-D remains a partial implementation; the post-E-REQ044 full invariant/L1 rerun is
pending. The REQ-027 accuracy failures remain adjudicable but are not silently reinterpreted
as metamorphic results.

## Accepted raw-fixture refinements

The latest E-A telemetry reports `outerRefinementAccepted` for nine analyses; IMG_0348 has no
accepted side and retains the Vision proposal. This flag means at least one side was accepted,
not that every side was refined: the refreshed per-edge dump rejects broad/low-support left
edges on IMG_0347, IMG_0350, IMG_0352, and IMG_0781 while retaining good sibling proposals or
refinements. IMG_0782 can accept an outer refinement and still decline because its inner reference
is absent.

## Reproduction scopes

The focused post-roll command targeted:

```text
CardCenteringAnalyzerTests
CardCenteringInvariantTests/testINV3FittedSkewTracksTheAppliedRotationAcrossTheCorpus
CardCenteringInvariantTests/testINV4HorizontalMirrorComplementsLeftRightOnly
CardCenteringInvariantTests/testINV5QuarterTurnsMapThePerSideRatios
CardCenteringInvariantTests/testINV7UniformScaleDoesNotChangeRatios
CardCenteringInvariantTests/testINV8BenignCropWithEightPercentCardMarginPreservesRatios
```

The original signed post-REQ-027 E7 result bundle is pre-E-REQ044 and confirms IMG_0782 declines
at all four tested maxima; the original latency budget remains unmet. The tracked E7
resolution/low-detection files were later overwritten by the intermediate transition-width
guard run, before the final per-side fallback. They report the same tested no-inner decline
behavior, but are not a final post-change curve. Their ratio-error columns use the current
rederived GT and are descriptive benchmark data, not a closure of the failing L1 gate.
- E-REQ044 then added a general transition-width guard of `max(12 px, 2% of the short edge)` and
  changed rejection to be per-side. A side that fails support, median-offset, MAD, or transition
  width retains the original Vision proposal while accepted sibling sides remain usable. The
  focused physical-outer assertion first failed when any rejected side discarded the complete
  quad (`IMG_0347` right error 13.0348 px versus a 10.7449 px tolerance), then passed after
  the per-side fallback in `revision-e-req044-outer-per-side-fallback-2026-09-12.xcresult`.
  The broad-transition red/green test also remains green. This is a focused outer-geometry result,
  not completion of joint selection or stability-aware confidence.
