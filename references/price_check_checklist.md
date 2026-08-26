Target screen:
- Route name: `PriceCheck`
- Expected device: PA Quality iPhone 17 Pro

Visual checklist (verify against `./artifacts/ui-latest.png`):
1. [ ] Native Collection | Price Check control is above the camera area.
2. [ ] Price Check is selected and “Value only · Nothing is added” is visible.
3. [ ] The persistent status text is readable against the camera surface.
4. [ ] No collection receipt, recent-scan rail, or undo control appears.
5. [ ] The selector, settings affordance, scan guide, and safe areas do not overlap.

Behavior checklist:
1. [ ] Switching purpose clears a pending scan without changing collection data.
2. [ ] A confirmed Price Check scan opens a one-card result and pauses recognition.
3. [ ] Dismissing the result rearms Price Check; refresh failure preserves the last-known quote.
4. [ ] VoiceOver announces the changed purpose and its no-add guarantee.
