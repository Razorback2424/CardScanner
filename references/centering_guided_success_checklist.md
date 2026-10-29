# Guided centering success checklist

**Rotation correction — 2026-10-29:** rotation moves only the photo beneath fixed
red/cyan guides, on screen and in exports. Zoom/pan still move both layers
together. This supersedes the rotation expectation in the historical checklist
below. Current verification is recorded in the [repair ledger](../docs/audits/centering-guided-repair.md).

### Current rotation acceptance

Target: `CenteringRotation`, synthetic `rotated` state, iPhone 17 Simulator.
Captures: external SSD `CodexBuild/CenteringRotation-20261029/Artifacts/`.

- [x] Photo visibly rotates beneath stationary red/cyan guide outlines.
- [x] Rotation controls, labels, title and safe areas remain legible and unclipped.
- [x] Pixel tests verify positive/negative photo rotation and fixed guide positions.
- [x] Export and zoom/pan guide-position regression checks pass.
- [x] Final capture inspected after the last code change.

Final iPhone 17/iOS 27 Simulator capture uses the existing local
`LOCAL_COLLECTOR_TOOLS` build flag to open the paid tool without a StoreKit
purchase; the normal Debug test run passes 28 cases. The initial normal-build
route capture correctly stopped at the unowned purchase gate. Verification is
limited to synthetic Simulator rendering and native pixel tests.

## Historical 2026-10-02 checkpoint

**Candidate:** `73898e8` plus the 2026-10-02 repair working tree.
**Target:** Centering; DEBUG routes `Centering`, `CenteringExpanded`,
`CenteringOuterControls`, `CenteringInnerControls`, and `CenteringRotation`.
**Devices:** iPhone 17 Pro and iPad Pro 11-inch simulator, iOS 26.5.
**Captures:** external SSD `TradingCardScannerCenteringRepair/UI/`.

## Visual checklist

- [x] Final title, toolbar, safe areas, and guide/control hierarchy fit.
- [x] Default and maximum accessibility typography wrap without overlap.
- [x] Light and dark appearances keep labels and red/cyan guides legible.
- [x] Pending frames show Review frames and disable export.
- [x] Confirmed frames expose ratios and export; invalid/missing frames do not.
- [x] Zoom/pan move the image and guides together. The original shared-rotation
  expectation is superseded by the 2026-10-29 correction above.
- [x] Phone and tablet numeric controls remain reachable through scrolling.
- [x] Final capture inspected after the last UI change.

## Deterministic behavior checklist

- [x] One explicit confirmation is required before a new image reports ratios.
- [x] Valid edits stay live; malformed/inverted/singular geometry is unreportable.
- [x] Newest input owns the result through loading, errors, and cancellation.
- [x] Immutable exports preserve files already handed to an in-flight share.
- [x] Independent preview expectations satisfy 0.5-point/one-device-pixel limits.
- [x] Guide fields and steppers name the frame/side and pixel value for accessibility.
- [x] Native simulator confirmation and live edge increment update the reading.
- [x] Export presents the native phone share sheet and anchored iPad popover with a prepared PNG.
- [ ] Actual VoiceOver navigation and share/save completion: physical-device/manual gate.

See the [repair ledger](../docs/audits/centering-guided-repair.md) for test counts,
accepted latency deferral, and automatic accuracy limits.
