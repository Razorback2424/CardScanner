# Guided centering success checklist

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
- [x] Rotation and zoom/pan move the image and guides together.
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
