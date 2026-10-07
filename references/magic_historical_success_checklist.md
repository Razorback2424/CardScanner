# Historical Magic English confirmation verification

**Date:** 2026-10-06. Local D pilot; no production activation.

Target screen: existing native printing picker for Allay.
- Route: `PrintingChoice`, states `magic-historical` and `magic-historical-accessibility`.
- Expected device: iPhone 17 Pro simulator, iOS 26.5.
- Evidence: external SSD `CodexBuilds/MagicHistorical/UI/`.

Visual checklist:
1. [x] Card title, collector evidence and release remain readable.
2. [x] Native English toggle appears unchecked; printing action is disabled.
3. [x] Text wraps without clipping at accessibility size.
4. [x] Skip and Details retain their accessible controls and safe areas.
5. [x] No provider IDs, generation hashes or implementation details enter product copy.

Behavior checklist:
1. [x] Unknown English yields a choice, never automatic acquisition.
2. [x] Confirmed selection saves the exact printing/finish using existing keys.
3. [x] Next encounter asks again; persisted recovery retains scoped evidence.
4. [x] Malformed/stale evidence, provider drift and new collisions reject.

Evidence: `D-Final-20261006.xcresult` passed 314/314 selected cases; Python passed
13/13. Final Debug build passed after the direct Needs attention toggle was added.
Inspected `UI/final-standard/ui-latest.png`, `UI/final-accessibility/ui-latest.png`
and `UI/final-details.png`. Runtime UI showed switch `0` with no selectable
printing, switch `1` with a selectable printing, and the same `1` in Details.
The accessibility capture starts unchecked again. Native sheet Done/Skip controls
are exposed. Screenshots contain only fixture content and remain on the external SSD.
The initial 2.5-second capture caught catalog preparation; settled captures use
`UI_CAPTURE_DELAY_SECONDS=20`, preserving app data and reusing the tested binary.

HIG review verdict: **PASS** for the inspected picker/details scope. Platform
patterns, clarity, typography, accessibility labels/targets, skippable interaction
and native navigation pass source/rendered checks. Top issues: none outstanding
in this scope. Minimal fixes applied: shared confirmation within an encounter,
reset on a new choice, and the same English gate on direct recovery buttons.
Full VoiceOver traversal and device accessibility behavior are not certified.

The [corpus continuation](../docs/research/magic-historical-corpus/README.md)
adds actual Vision OCR on 27 images: one calibrated Exodus photograph and 26
scope abstentions, followed by exact choice/save integration. Focused 27/27,
affected regression 316/316 and Python 20/20 pass. Manually annotated card bounds
and repeated stills are not held-out positive or independent frame evidence.
Physical-camera acquisition, held-out geometry, device optical accuracy,
thermal/memory budgets and real-provider acquisition remain unverified.
