# Native precision candidate — 2026-11-01

Base: `b592c914d2bae7ecfbea03218b20f94bdef90364` plus this isolated candidate.
Target route: `CenteringPrecision`; iPhone 17 Pro Simulator, SHA-verified original
Gengar plus analytic synthetic tests. Final draft-field captures: 2026-11-01
Mac local log clock, after `PrecisionFinalAggregate`. Independent review pending.

The REQ-045 guided contract and §5.1 tolerances remain unchanged. Decimal
controls describe adjustment granularity, not calibrated boundary accuracy.

- [x] Build and execute native precision/export tests; final aggregate includes all 31 native and 28 export cases, no skips.
- [x] Explicit frame/side selection, position/angle fields and native detail visible.
- [x] Maximum Dynamic Type labels wrap; numeric fields fit and content scrolls.
- [x] Fields and steppers have distinct frame/side/unit labels in source. VoiceOver traversal is pending.
- [x] Decimal/negative parsing tested for en_US/fr_FR/de_DE; French comma formatting rendered. Scene-backed UIKit editing events preserve all digits and commit on Done. Headless HID injection remains uncertain.
- [x] Raster tests cover eight EXIF orientations, rounded resize and UIImage scale 3; actual detail overlay stays within one device pixel.
- [x] Native detail follows the selected inner-left and outer-bottom guides in actual UI captures.
- [x] Fine edit and independent slope update actual guides; exact undo/reset tests pass.
- [x] Invalid edits retain exact last valid geometry with a reason; reason styling inspected in source.
- [x] Before confirmation, ratios/export are unavailable in actual UI and model tests.
- [x] Confirm → photo-only rotate invalidates confirmation and old export immediately.
- [x] Rotation reset also requires realignment/reconfirmation in actual UI.
- [x] Ten final UI captures inspected after the last UI change and verified against original SHA256.
- [x] Four actual model PNG exports retained; manual example exports are byte-identical across detail views. Fixed-guide photo rotation has rendered regression coverage.
- [x] Exact Gengar before/after geometry, branches and raw candidate evidence retained.
- [x] Ten development fixtures replayed for baseline/default/V1/V2/V2b; no sealed holdout opened.
- [x] Final production REQ-022: upper median 0.495113 s/max 0.542783 s, unchanged 0.8/1.5 s limits. Simulator only.
- [x] Native bounded-strip, 4032×3024, cache invalidation and cancellation tests pass; per-process replay peaks retained.
- [ ] Controlled peak-memory/leak profiling and representative 48 MP camera capture.
- [x] Native share popover visually opens from the actual confirmed PNG; receipt retained.
- [ ] Save Image completion (system action has no headless semantic target), HID keyboard verification and VoiceOver traversal.
- [ ] Independent visual reviewer, physical capture, sealed holdout and real-device gates.

Applicable aggregate executes 109 cases. An initial native benchmark fails two
timing assertions with unused DEBUG research generation enabled; its failure
receipt remains. A separate production-equivalent native measurement passes at
0.715 s upper median/1.414 s maximum. Final corrected-configuration applicable
aggregate passes all 109 cases with zero skips, production 0.491/0.536 s and
native 0.538/1.380 s. This is not a full-target test run.
The final draft-field binary adds UIKit editing coverage and passes **110/110,
zero failures/skips**, including unchanged-draft Double preservation;
production 0.495113/0.542783 s and native 0.549302/1.387473 s. Intermediate
counts remain historical receipts.

Native fit acceptance remains 3/36 development sides in V2b, including semantic
false fits. Gengar's top/right/bottom remain unresolved. Native accuracy is
**failed/open**, not promoted by timing or synthetic passes. Evidence paths,
configuration differences and exact limitations are in the
[current ledger](../docs/audits/centering-guided-repair.md#current-precision-candidate--2026-11-01).

Native local refinement is DEBUG opt-in and disabled in production. It may not
be promoted by this checklist alone: independent native registration, corpus,
performance, representative device/physical capture and release gates remain
required. Missing evidence must be `not run` or `pending`, never a pass.
