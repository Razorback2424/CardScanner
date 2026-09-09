Target screen:
- Route name: `PriceCheck`
- Expected device: PA Quality iPhone 17 Pro

The simulator route proves the purpose-selection and camera-chrome contract.
It does not prove a real camera identification or live-provider refresh.

Visual checklist (verify against `./artifacts/ui-latest.png`):
1. [x] The native Collection | Price Check control is above the camera area.
2. [x] Price Check is selected in the deterministic route.
3. [x] The purpose menu shows “Value only · Nothing is added” at the choice point.
   The same guarantee is included in the VoiceOver announcement; it is not
   persistent camera copy by design.
4. [x] No collection receipt, recent-scan rail, or undo control appears while
   the route is idle.
5. [x] The selector, settings affordance, scan guide, and safe areas do not
   overlap in the captured iPhone 17 Pro frame.

Behavior checklist:
1. [x] Switching purpose clears pending scan state without entering the
   collection write path; covered by the scanner view-model behavior.
2. [ ] A confirmed Price Check scan opens a one-card result and pauses
   recognition on a real camera device.
3. [ ] Dismissing the result rearms Price Check; refresh failure preserves the
   last-known quote on a live-provider/device pass.
4. [x] VoiceOver announces the changed purpose and its no-add guarantee.

Remaining gate: perform one physical-device Price Check scan and one forced
refresh-failure pass. Keep the simulator evidence above; it is not a substitute
for camera/OCR/provider validation.
