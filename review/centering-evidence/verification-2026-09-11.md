# Verification record — 2026-09-11 (amended 2026-09-12, revision-E-REQ044)

Worktree: `opus-card-centering-implementation`.

## Completed checks

| Check | Command / scope | Result |
|---|---|---|
| Device SDK compile | `xcodebuild build-for-testing -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -destination 'generic/platform=iOS' -derivedDataPath .codex_build_device_final CODE_SIGNING_ALLOWED=NO` | `TEST BUILD SUCCEEDED` |
| Ground-truth validator | `python3 review/centering-harness/gt_tool.py validate TestFixtures/TradingCards/GroundTruth` | 10 records validated |
| Ground-truth rederivation | Analyzer-free `gt_tool.py rederive` with two generic profile passes, TLS edge fits, and explicit visual adjudication; source diagnostics and selection manifest retained under `diagnostics/GT-rederived/` | 10 current records regenerated; coordinates are no longer five-pixel-grid estimates; exact `ambiguousEdges` rule applied; prior records archived under `ground-truth/provisional-2026-09-11/` |
| Baseline immutability | `shasum -a 256 -c SHA256SUMS` (run from `review/centering-evidence/baseline-2026-09-11/`) | 14/14 files `OK` |
| Shell syntax | `bash -n scripts/centering_ui_build_and_shoot.sh && bash -n review/centering-harness/run_meta.sh` | pass |
| Patch hygiene | `git diff --check` | pass |
| Focused analyzer XCTest | iOS 26.5 iPhone 17 Pro `EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86`, external-SSD DerivedData | Historical run 20/20; latest post-E-REQ044 run 21/21 passed in 24.326 s |
| REQ-028 exact regression rerun | Exact `CardCenteringAnalyzerTests/testACardPhotographedSidewaysIsStillFound` and `CardCenteringAnalyzerTests/testStraightensASkewedCardBeforeMeasuring` methods on the pinned iOS 26.5 simulator; external-SSD artifacts | 2/2 passed in 4.827 test seconds; `req028-correct-before.xcresult` retained on the external SSD. An earlier incorrectly filtered invocation executed 0 tests and is discarded. |
| Centering invariant XCTest class | Same pinned simulator and DerivedData; retained pre-E-B and pre-roll-repair complete-class records | Historical pre-E-B record: 13/16; post-E-D/pre-roll-repair complete class: 17 tests with 71 assertions; superseded for current E-D state by the targeted run below |
| E-A raw-fixture branch diagnostic | Same pinned simulator; ten original HEIC inputs; `diagnostics/EA/` | 10/10 records written; historical E-B branch was 8/2, latest post-E-REQ044 focused probe is 9 confident / 1 declined; IMG_0782 is the only decline |
| E-B sleeved-inner regression | Same pinned simulator; five sleeved HEIC fixtures | passed after the pinned-profile and shape-gated repair |
| IMG_0782 no-inner safety test | `CardCenteringGroundTruthTests/testMaskFailureDeclinesWithoutAnInnerReference` | passed at the default 1200-pixel path; refreshed post-REQ-027 E7 artifacts also decline at 1200/1600/2000/2400 |
| E0/E1 historical plus E7 evidence generation | Same pinned simulator; diagnostics and resolution curves written under `diagnostics/` | Historical E0/E1 and the earlier post-roll E7 run passed in 333.179 s; E0/E1 are not production-equivalent. The refreshed post-REQ-027 E7 run is recorded separately below |
| E-C raw-HEIC metamorphic harness | `CenteringProfileDumpTests/testE1MetamorphicVariantsCanBeResolutionEqualizedFromRawHEIC`; same pinned simulator and external-SSD paths | Passed in 85.941 s; 12 raw/equalized records written; all GT-derived working short-edge assertions within ±0.5%; IMG_0347 declines at rot90/rot270 in both records |
| E-D / E-REQ044 guarded outer refinement | Test-first baseline, initial fit, local-offset guard, roll-preservation repair, transition-width guard, and per-side fallback; same pinned simulator and external-SSD paths | Initial fit caused eight assertions across six legacy analyzer tests; the historical guard restored 20/20; the final per-side physical-outer test passed, and the latest analyzer class passed 21/21. The post-change full invariant/L1 rerun is now complete and remains red on the recorded accuracy/invariant gates |
| Post-E-D targeted invariant run | `CardCenteringAnalyzerTests` plus INV-3, INV-4, INV-5, INV-7, and INV-8; `post-ED-roll-repair-invariants.xcresult` | 25 tests; 20 analyzer tests and INV-3 passed; six invariant assertions failed: INV-4 1.4 pp, INV-5 0.7/1.4/1.1 pp, INV-7 1.4 pp, INV-8 1.1 pp |
| E-E post-refinement profile classification | `CenteringProfileDumpTests/testEEDumpPostRefinementProfileNormalization`; raw and resolution-equalized variants for IMG_0783/IMG_0347 | Passed in 90.912 s; 24 snapshots and 96 per-edge records retained; residual classified as both outer-line displacement and profile depth selection |
| REQ-027 complete production accuracy baseline | `CardCenteringGroundTruthTests` against the rederived records on the pinned simulator; external-SSD result bundle | Pre-E-REQ044 baseline: 12 cases, 8 passed / 4 failed; the complete L1 accuracy comparison remains open after the later production change. Bundle: `Artifacts/req027-ground-truth-after-rederive.xcresult` |
| Historical E7 benchmark before the final per-side fallback | `CardCenteringInvariantTests/testREQ031ResolutionAccuracyAndLatencyCurve` and `testREQ031LowResolutionDetectionFullResolutionRefinement`; pinned simulator and external-SSD paths | 2/2 tests passed in 330.965 s; the signed pre-change bundle measured full-resolution max/median latency 2.706/2.935 s at 1200 and 7.971/9.723 s at 2400; low-detection/full-refinement was 2.724/2.952 s at 1200 and 3.660/3.848 s at 2400. The tracked E7 files were later overwritten by the intermediate transition-width-guard run before the final per-side fallback (2.733/2.972 s at 1200; 7.974/9.748 s at 2400; low-detection 3.685/3.861 s at 2400). IMG_0782 declined at every tested maximum in both snapshots; the current post-change curve is recorded in `diagnostics/E7/` |
| Historical REQ-039 signed full-suite baseline | Direct `xcodebuild test` on iPhone 17 Pro / iOS 26.5 with no `CODE_SIGNING_ALLOWED=NO`, external-SSD DerivedData and result bundle | 1088 test cases: 1078 passed, 1 skipped, 9 failed test cases / 116 console assertion failures; eight centering test cases and one pre-existing Magic-treatment test. Summary: [baseline-2026-09-12.md](baseline-2026-09-12.md) |
| Current post-E-REQ044 signed full-suite baseline | Direct signed `xcodebuild test` on the same pinned simulator with external-SSD DerivedData/result bundle | 1095 result entries: 1085 passed, 1 skipped, 9 failed; all nine failed entries are centering failures. The known pre-existing Magic-treatment failure from an older baseline did not recur; there were 66 console failure entries including repeated assertions/retries. Summary: [baseline-post-ereq044-2026-09-12.md](baseline-post-ereq044-2026-09-12.md) |
| REQ-041 repeated stage profile | `CardCenteringInvariantTests/testREQ041ProfilesNamedStageTimingsAcrossAllFixtures`; signed DEBUG run on the pinned iOS 26.5 simulator with external-SSD result bundle | Passed: 20 analyses (two per fixture); named stages accounted for 0.999 median/max wall time. Median wall time 2.7548 s; scalar fields 1.4909 s (54.6%) and inner candidate generation 0.8349 s (30.0%) are the measured bottlenecks. Records: [REQ-041 profile](diagnostics/REQ-041/README.md). Bundle: `revision-e-req041-profile-retry2-2026-09-12.xcresult` |
| REQ-042 all-fixture candidate ledger | `CardCenteringInvariantTests/testREQ042CandidateRecallDiagnosticCoversAllFixtures`; signed DEBUG run on the pinned iOS 26.5 simulator with external-SSD result bundle | Passed as an evidence-generation test: all 10 original HEIC fixtures emitted complete post-E-REQ044 ledgers. Corrected geometry recall is 34/40 outer (85.0%) and 28/36 gradeable inner (77.8%) using the fixed `0.0035 * H` inner tolerance; eight inner misses are generator failures and semantic roles remain mostly untyped, so the 95% gate is not met. Records: [REQ-042 README](diagnostics/REQ-042/README.md). Bundle: `revision-f-req042-inner-corrected-2026-09-12.xcresult` |
| E-REQ044 broad-transition guard regression | `CenteringProfileDumpTests/testREQ044OuterRefinementRejectsBroadAmbiguousTransitions` plus `CardCenteringInvariantTests/testREQ044SelectedOuterTracksPhysicalCardOnDevelopmentBacks`; pinned iOS 26.5 simulator and external-SSD result bundles | Expected-red broad-transition test failed before the guard; guard test passed; all-or-nothing outer selection failed IMG_0347 right, then final per-side fallback passed the physical-outer test. No tolerance or GT change |
| E-A branch refresh after E-REQ044 | `CenteringProfileDumpTests/testEADiagnoseInnerReferenceBranchForAllRealFixtures`; pinned iOS 26.5 simulator and external-SSD result bundle | 1/1 passed; latest focused branch probe 9 confident / 1 declined; `IMG_0782` is the only decline; all nine non-none outputs still report `art_window` |
| REQ-043 semantic reference rerun | `CardCenteringInvariantTests/testREQ043ReferenceTypeIsChosenSemanticallyAcrossDevelopmentCorpus`; pinned iOS 26.5 simulator and external-SSD result bundle | 1 test executed, 5 assertions failed: all five backs remain `art_window` instead of `printed_border` |
| REQ-033 exact documentation guard rerun | `CardCenteringInvariantTests/testREQ033EvidenceStatusClassifiesRecoveredRuntimeAndProvisionalGT`; pinned iOS 26.5 simulator and external-SSD result bundle | 1/1 passed. The first post-edit invocation targeted the wrong class and executed 0 tests; it is discarded. Current bundle: `/Volumes/Keller Family Photos/June 10 2026 dump (move)/AdditionalStorage/TradingCardScannerMVP_fixed_v4/Results/revision-f-docs-guard-2026-09-12.xcresult` |
| Real-fixture L3 route | `scripts/centering_ui_build_and_shoot.sh` over all ten HEIC fixtures on the pinned simulator | 10/10 screenshot/metadata pairs captured **before E-B**; historical snapshot 3 confident / 7 declined; all final PNGs under 1.5 MB |

## Not completed

The fresh signed REQ-039 baseline is immutable historical evidence from before
the latest E-REQ044 production change. The current post-E-REQ044 full-suite
baseline is recorded above and in
[`baseline-post-ereq044-2026-09-12.md`](baseline-post-ereq044-2026-09-12.md).
The latest change is narrow and test-first:
it adds a transition-width guard and per-side fallback for outer refinement.
It improves the focused physical-outer assertion and preserves the 21/21 analyzer
regression class, but it does not yet establish current L1, invariant, or latency
performance:

- REQ-027 is complete; the current complete accuracy comparison is now the
  post-E-REQ044 full-suite/E7 result. At 1200 px it reports 9 confident / 1
  declined and 3/10 descriptive ratio passes. The L1 accuracy gate still fails;
  the pre-E-REQ044 result remains historical.
- All nine latest E-A records carrying an inner reference still report `art_window`,
  including all five backs; IMG_0782 correctly reports `none`. `outlineHasInner` is mixed.
- The original holdout is development-exposed and must be replaced.
- Higher resolution is unsafe as well as slow; 1200 is the provisional cap.
- Candidate recall, semantic reference branches, joint
  selection, and the hard frozen-holdout go/no-go gate are open under
  REQ-039–REQ-045.
- REQ-041 stage attribution is complete: 20 signed analyses across all ten
  development fixtures accounted for 0.999 median/max wall time. The original
  0.80/1.50-second budget remains unmet; the profile identifies scalar fields
  and inner candidate generation as the next optimization targets.
- REQ-042 candidate telemetry is now complete as an evidence run, not as an
  acceptance pass: all ten fixtures emitted post-E-REQ044 ledgers. Corrected
  geometry recall is 34/40 outer (85.0%) and 28/36 gradeable inner edges
  (77.8%), below the 95% gate. The eight inner misses are IMG_0347 left,
  IMG_0352 left, IMG_0348 bottom, IMG_0351 bottom, IMG_0780 right and bottom,
  IMG_0781 bottom, and IMG_0783 bottom; because `bestErrorPx` is the best
  available candidate, these are generator failures. The inner roles are also
  not yet semantically typed. See
  [`diagnostics/REQ-042/README.md`](diagnostics/REQ-042/README.md).
- The current signed full-suite baseline completed on the pinned simulator with
  1095 result entries, 1085 passed, 1 skipped, and 9 failed. All nine failed
  entries are centering failures; the known pre-existing Magic-treatment label
  leak from an older baseline did not recur in this run. No Keychain entitlement
  failures appeared. See
  [`baseline-post-ereq044-2026-09-12.md`](baseline-post-ereq044-2026-09-12.md).

The required final L1/L2 accuracy pass and REQ-021 screenshot-pixel
measurement are not complete. The current production-entry accuracy run has
now been executed against the rederived records: 8 of 12 cases passed and 4
failed, so the current L1 result is failing rather than unadjudicated. The ten
real-fixture screenshots and markers remain retained, including the declined
IMG_0782 route; the injected 2 px sensitivity check and a screenshot after
actual manual guide entry remain open. See
[`after/simulator-status-2026-09-11.md`](after/simulator-status-2026-09-11.md).

No final runtime pass is claimed for L1/L2 or L3. REQ-021 is open and REQ-022
is explicitly failing its original budget; the refreshed resolution curves
are retained for the required decision under REQ-031. The E-C harness remains
limited to its two diagnostic fixtures. The refreshed E7 benchmark confirms
IMG_0782 declines at all four tested resolution overrides, but the original
latency budget remains unmet.

The containing `CardCenteringInvariantTests` class was also included in the
current full suite; its current failures are the recorded INV-4, INV-5, INV-7,
and REQ-022 gates. The earlier single `storeFailed(-34018)` failure came from
the `CODE_SIGNING_ALLOWED=NO` harness run and remains excluded. The exact guard
test above passed independently and is the result counted for REQ-033.
