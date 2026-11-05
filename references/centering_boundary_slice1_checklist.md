# Centering geometry and review — 2026-11-04

Target: guided centering, pending and confirmed independent inner edges.
Route: existing DEBUG centering route; synthetic `pending`, `confirmed`, and
`independent` states. Device: dedicated iPhone 17 Pro / iOS 27.0 Simulator.

Evidence belongs to the [guided repair ledger](../docs/audits/centering-guided-repair.md).
Synthetic frames validate presentation and editing, not physical boundary accuracy.

## Visual acceptance

- [x] Pending state shows hidden ratios, one Confirm action, and unavailable sharing.
- [x] Confirmed state describes human review without asserting detector certainty.
- [x] Independent slopes show positional variation even when average tilt is near zero.
- [x] Square remains explicit and discoverable; normal guide adjustments remain available.
- [x] Export retains independently sloped cyan lines, review provenance, and variation text.
- [x] Standard text has no new clipping, overlapping controls, or unsafe-area collisions.
- [x] Accessibility text layout inspected, with limitations recorded rather than inferred.
- [x] Final capture uses the tested centering source with existing local-only/UI-entitlement flags; its binary identity is retained separately.

## Behavior acceptance

- [x] Confidence alone cannot authorize ratios; confirmation retains exact detector evidence.
- [x] Ten development photographs preserve the analyzer's independent geometry and variation.
- [x] Valid edits stay live; invalid geometry, new input, and photo rotation close approval.
- [x] Square and Undo recover exact geometry; precision Done/removal/locale regressions pass.
- [x] Export pixel tests preserve independent lines; stale shares stay invalidated.
- [x] Existing production latency limit passes without tuning thresholds or enabling native refinement.

Final normal/maximum-text captures and actual Simulator Confirm, scroll,
Square and Undo actions pass. The largest-type layout keeps the image outside
the scrolling controls so reading gestures preserve guide geometry. Earlier
clipping and gesture-conflict captures remain in the evidence directory.

Physical-device interaction, VoiceOver traversal, independent boundary accuracy,
and release acceptance are outside this simulator receipt and remain open.
