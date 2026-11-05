# Centering reference review — 2026-11-04

Target: guided centering reference choice and side-specific candidate repair.
Routes: existing `Centering` and `CenteringPrecision`, synthetic pending/confirmed
states and the existing image importer. Dedicated iPhone 17 Pro / iOS 27 Simulator.
Evidence: external SSD `CodexBuilds/CardScanner-CenteringSlice2-20261104`.

## Acceptance

- [x] Unverified guides show no ratio; choosing a reference confirms the reviewed frames.
- [x] No usable reference keeps the result unavailable; adding a frame is only a placement aid.
- [x] Screen and export label the chosen geometric reference without grading equivalence.
- [x] Side alternatives are discoverable beside native detail and remain undoable.
- [x] A side choice changes only its supporting line, retaining the other seven and detector evidence.
- [x] Input hash, orientation and mappings bind candidates to original native coordinates.
- [x] Normal and maximum accessibility text remain readable and controls reachable.
- [x] Relevant native tests, Release compilation and production latency are verified.
- [x] Final screenshot is inspected after the final UI change.

Physical boundary accuracy, physical-device interaction and VoiceOver traversal
remain outside simulator-only acceptance. No holdout evaluation or automatic
reporting is authorized by this checklist.

The first normal-size capture exposed a truncated primary label. The final
separate action row, wrapped caveat, native controls and matched export receipts
pass inspection. Actual side choice and Undo are also compared in native
coordinates. The design gate and precise test/build scope are recorded in the
[guided repair ledger](../docs/audits/centering-guided-repair.md#reference-identity-and-competing-boundaries--2026-11-04).
