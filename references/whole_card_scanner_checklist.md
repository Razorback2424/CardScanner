# Whole-card scanner visual checklist

- Target screen: Scanner
- Route name: `WholeCardScanner`
- Expected device: PA Quality iPhone 17 Pro

The DEBUG route intentionally renders the production scanner surface without
starting camera capture and seeds a receipt for deterministic layout QA. That
proves the chrome and receipt layout, but not physical-camera framing or OCR
performance.

- [ ] A real-camera capture shows a single portrait card outline centered and
  fully visible.
- [x] The guide geometry is resolved to the physical 2.5:3.5 trading-card
  aspect ratio in source and scanner-focused tests.
- [ ] A real-camera capture shows the green footer band contained at the bottom
  of the card outline.
- [ ] A real-camera capture proves the guide leaves room for the top toolbar,
  bottom tab bar, and scan-session overlays.
- [x] The deterministic route contains no historical-title repositioning
  prompt.
- [x] Deterministic scanner chrome/receipt labels remain legible in the current
  iPhone 17 Pro simulator route.

Remaining gate: physical camera framing, OCR tracking rate, thermal behavior,
and slab calibration are tracked in [`release_followups.md`](../release_followups.md).
