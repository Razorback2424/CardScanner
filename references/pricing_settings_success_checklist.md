Target screen: Pricing and storage Settings
- Routes: `PricingSettingsReview`, `StorageSettingsReview` (Debug/local only)
- Expected device: isolated iPhone 17, iOS 27 simulator
- Evidence root: `/Volumes/T7/CodexBuild/FeatureCompletenessFixes-20261029/`

Visual acceptance — inspected on 2026-10-29:
1. [x] JustTCG key field, Save action and specific gap-filling toggle are legible.
2. [x] History, graded and sealed key requirements wrap without overlap.
3. [x] The toggle's limited role is clear. Saved-key allowance text is source-checked; its rendered state remains to verify.
4. [x] Empty key disables Save and gap-filling; no key is displayed.
5. [x] Storage Settings distinguishes inventory CSV from full recovery.
6. [x] Navigation title, safe areas and scrolling remain usable at accessibility text size 2.
7. [x] Final standard-size captures match the tested UI build; only comments/formatting changed afterward.

Evidence: `pricing-final/ui-latest.png`, `storage-final/ui-latest.png`,
`storage-final/bottom.png`, `pricing-large/{ui-latest,scrolled}.png`, and
`storage-large/{ui-latest,scrolled,bottom}.png` under the evidence root. The
first fixed-delay captures showed startup, so the two routes now use an actual
view-appearance ready marker. These are Debug/local harness views of the shared
production Settings sections, not full navigation or VoiceOver acceptance.

The secure-field automation reported typing a synthetic value but did not
change the visible field or enable Save. No key was saved; saved-key rendering
and the save/remove interaction are not claimed verified by this loop.

These screens do not certify provider access, catalog coverage or full restore.
