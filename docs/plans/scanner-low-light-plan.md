# Scan light for dim rooms

**Status:** 2026-11-11. The lens shortcut is implemented and verified in
Simulator. ProfileLocal includes the Macro hardware check. Scan light awaits
that result.

Revised after code review 2026-11-11.

Use the rear LED as a steady **Scan light** so it illuminates the live preview and
the video frames the scanner reads for recognition. Use the torch controls on
the existing authorized camera session in Collection and Price Check, for raw
cards and slabs. [CardScanner](../../TradingCardScanner/Services/CardScanner.swift)
· [AVFoundation lighting](https://developer.apple.com/documentation/avfoundation/capture-device-lighting)

## What the user sees

Add one flashlight button immediately before Settings in `ScannerTopBar` and
keep the gear at the trailing edge. Use 8 pt spacing. At standard Dynamic Type
sizes, use `ViewThatFits(in: .horizontal)` to try a single row at the controls’
full width, then use two rows when it does not fit. Use two rows at accessibility
sizes. Keep the purpose, light and gear in row one. Let the card type and finish
summary wrap in row two, with the slow identification spinner beside it. Showing
the spinner in row two fixes its current omission at accessibility sizes.
At accessibility sizes, show the finish name for a single lock and the count
for multiple locks. The menu and VoiceOver retain the full finish detail.
Both rows stay above the reading band.
[ScannerTopBar](../../TradingCardScanner/Views/ScannerView.swift)
· [ViewThatFits](https://developer.apple.com/documentation/swiftui/viewthatfits)

```text
Regular width          [Collection ▾] [Auto ▾] [spinner] … [light] [gear]
Narrow or large text   [Price Check ▾]              [light] [gear]
                       [Slabs ▾] [spinner]
```

Match `settingsButton` with a 44 × 44 pt target and a white
`flashlight.off.fill` glyph. Use `.buttonStyle(.glass)` on iOS 26 in the same
`GlassEffectContainer`, with `appGlassEffectID("scanner-light", in: glassNamespace)`.
Use a `Color.black.opacity(0.55)` circle with the same hairline stroke on
earlier versions. When on, invert the chip with a white fill and a black
`flashlight.on.fill` glyph. Use `.glassProminent` tinted white on iOS 26 and a
white circle in the fallback. The two shapes and inverted fill convey state
without borrowing the amber Price Check uses. Swap the symbol and fill directly
and respect Reduce Motion. Give VoiceOver the label “Scan light,” the value
“Off,” “On,” or “Unavailable,” and the `.isToggle` trait.
[Apple button guidance](https://developer.apple.com/design/human-interface-guidelines/buttons)
· [Prominent glass style](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent)

### Why the top bar

The top bar keeps the light one tap away and shows its state while scanning.
Settings takes two taps and opens a sheet that turns the light off. Showing
the control only after low light is detected would miss total darkness and
shift the toolbar as the hint changes. The purpose and finish menus group scan
decisions and would hide the light state. The space below the reading band
already carries receipts and acknowledgements. A long press on the gear has
no visible cue. [Scanner view](../../TradingCardScanner/Views/ScannerView.swift)

| Situation | Behavior |
| --- | --- |
| Viewfinder opens on a compatible lens | The light starts off. Tap once to turn it on and again to turn it off. It stays on between cards and during inline choices while the viewfinder is visible. |
| Scanner has sustained evidence of low light | Show passive “Turn on light” text when the light is off and available. Suppress the low light hint while the light is on. Show “Add light” when the torch is absent or unavailable. |
| Active input reports `hasTorch == false` | Omit the button and its spacing. |
| Light becomes temporarily unavailable | Keep the off button in place and disable it. VoiceOver reports “Unavailable.” Use the existing passive guidance when low light is detected. |
| Lens changes from the Scan menu | Carry an active light request to the new input if it can light and the viewfinder stays active. If the new input cannot light, clear the request and let the button reflect its capability. |
| Scanner loses the viewfinder or camera | Clear the request and turn the light off when leaving Scan, becoming inactive or backgrounded, presenting a covering sheet (Settings, review or Price Check), or during a camera interruption or reset. Settings clears the request before its lens picker can be used. Returning starts with the request Off, even if Control Center’s flashlight or another client changed the LED while Scan was inactive. |

Use a low, fixed output tuned on hardware. Foils, sleeves and slab cases can
reflect the LED into the reading band. The user can turn the light off in one
tap and tilt the card or use diffuse room light.

## Lens access from the scan screen

Today a lens change takes four taps to get back to scanning. Open Settings,
choose Scanning, select the lens in Camera, then dismiss the sheet. Add a
**Camera** inline picker to the existing scan-options menu in `FinishLockControl`
when `availableLenses.count > 1`. Put it between the Raw/Slabs picker and the
finish controls. Opening the menu and choosing a lens takes two taps and keeps
the viewfinder live. The existing pill keeps its card type and finish label.
A separate lens chip would take permanent space, and a menu on the flashlight
button would add a tap to the light action. Manual selection keeps the framing
predictable.
[Scan-options menu](../../TradingCardScanner/Views/ScannerView.swift)
· [Scanning settings](../../TradingCardScanner/Views/ScannerSettingsView.swift)

```text
[Auto ▾]
  Scanning
    ✓ Raw cards
      Slabs
  Camera
    ✓ Macro, close-up
      Standard
  ─────────
  Auto / finish locks …
```

Give the picker the VoiceOver title “Camera” and the options “Macro, close-up”
and “Standard.” Keep the Settings picker and its explanatory footer. Bind both
pickers to `CardScannerUIState.lens` and send selections through `setLens`.
Keep the checkmark on the last confirmed lens until the hardware swap succeeds.
Observe `lens` and `availableLenses` at the toolbar boundary and pass both
values through. Include them in the equality functions for `ScannerTopBar`
and `FinishLockControl` so the menu updates when the camera changes. Keep the
selection in memory. A fresh launch starts in Macro when supported and Standard
otherwise.
[Scanner toolbar](../../TradingCardScanner/Views/ScannerView.swift)
· [Camera state and lens selection](../../TradingCardScanner/Services/CardScanner.swift)
· [ScannerCameraSettingsSection](../../TradingCardScanner/Views/ScannerSettingsView.swift)

Fix duplicate protection before exposing the picker. Today `setLens` calls
`resetObservationState()`, which forgets the consumed printing through
`latch.releaseAndForget()`. Replace that reset with
`invalidateSpatialContinuity()` and enqueue it before swapping the input.
It marks the tracker lost and clears partial recognition evidence while
preserving the active latch and consumed records. This keeps the new framing
from supplying exit evidence for the old tracker. A lens change also respects
any recognition pause already in force for a choice or sheet.
[CardScanner lens and tracking](../../TradingCardScanner/Services/CardScanner.swift)
· [CardLatch](../../TradingCardScanner/Services/CardLatch.swift)

Serialize lens and torch operations on `sessionQueue`. When an in-view switch
starts with Scan light On, turn off the outgoing input before detaching it
and carry the existing request through that swap. Reapply it only after the
new input becomes active, passes the torch capability and availability checks,
and still belongs to the same eligible Scan session. Treat the old input’s
shutoff as expected and discard its late observations. Clear the request if
the swap or relight fails, the new input cannot light, or the viewfinder becomes
ineligible during the swap. Use the existing restore path on a failed swap.
Publish On once the new input reports an active torch. A flashlight tap is
the only way to create an On request.
[Camera session and input swap](../../TradingCardScanner/Services/CardScanner.swift)

The manual lens shortcut is independent of the Macro torch check. That check
gates Scan light, including its torch behavior during a lens switch.

## Run the manual check

1. In Xcode, use **TradingCardScanner-ProfileLocal** with your iPhone selected
   and press Run to install the current build. Open **Pro → Macro light check**
   and allow Camera if prompted. The check uses the same Macro input as Scan.
2. Read the status on screen. If the Macro camera has no usable torch, record
   the message and end the light trial. If it reports temporary unavailability,
   record that separately from hardware support.
3. In dim light, hold a raw card 2–5 cm away. Compare **Off**, **Low** and
   **Medium** at the same distance and angle. Check the footer on a matte
   card and then on a foil or sleeved card. Try a slab label at its normal
   working distance. Record the lowest useful setting and any reflection
   that obscures text.
4. Tap **Done** and confirm the LED goes off if it was on. Open **Scan** in
   Collection mode. Hold a test card at a distance both lenses can read. After
   one add, keep it in the reading band and switch between Macro and Standard
   under **Camera** in the scan-options menu. Reopen the menu to check the
   active lens. Check that quantity increased once, then undo the test add if
   desired.

## Scan light implementation order

1. **Verify Macro before implementing Scan light.** The scanner defaults to
   the physical ultra wide input when it supports close focus. Check whether
   that input has a usable torch and find the lowest output that helps. Test
   raw card footers at 2–5 cm and slab labels at their working distance. If
   the input lacks usable torch support, or the LED offset or hotspot makes
   footers unreadable at working distance, stop work on Scan light and record
   the result. Standard remains a manual lens choice.
   [Camera and lens handling](../../TradingCardScanner/Services/CardScanner.swift)
   · [ScannerCameraSettingsSection](../../TradingCardScanner/Views/ScannerSettingsView.swift)
2. **Keep torch ownership on the camera session.** Use the running session’s
   `videoInput.device` on `sessionQueue`. Check `hasTorch`,
   `isTorchModeSupported(.on)` and `isTorchAvailable`. Hold the device
   configuration lock while calling `setTorchModeOn(level:)` or setting
   `torchMode = .off`. Observe `isTorchAvailable` and `isTorchActive` and
   publish a deduplicated state to `CardScannerUIState` on the main actor.
   Only a tap on the light button can request On. Activity observations report
   hardware state. Failed activation and unexpected shutoff clear the request.
   Wire `scenePhaseChanged`, `cameraInterruptionStarted`,
   `pauseForPresentation` and the separate Price Check result path into
   cleanup. Turn the light off before stopping or detaching the input. When
   Scan regains the camera with the request Off, apply `.off` if the torch is
   still active. Serialize taps and discard late callbacks from earlier
   sessions or inputs. Carry an existing On request across an eligible in-view
   lens change as described above.
   [Scanner lifecycle](../../TradingCardScanner/Views/ScannerViewModel.swift)
   · [Torch level](https://developer.apple.com/documentation/avfoundation/avcapturedevice/settorchmodeon%28level%3A%29)
   · [Torch availability](https://developer.apple.com/documentation/avfoundation/avcapturedevice/istorchavailable)
   · [Torch activity](https://developer.apple.com/documentation/avfoundation/avcapturedevice/istorchactive)

   Give the button its own small view that observes `CardScannerUIState`,
   following `ScannerStatusView`. Pass the state object through the top bar
   and keep changing light values out of `ScannerTopBar`’s Equatable inputs.
   Show On only when the scanner requested On and the torch is active.
   [Scanner toolbar and status views](../../TradingCardScanner/Views/ScannerView.swift)
   · [Views guide](../../TradingCardScanner/Views/AGENTS.md)
3. **Invalidate spatial tracking on each torch transition.** Use
   `invalidateSpatialContinuity()`, which queues the work on `visionQueue`.
   For a tap, enqueue it before changing the LED. For system changes, enqueue
   it from the activity observer. Tracker loss clears the Vision request and
   exit accumulator. A false `SpatialResetProof` would make the held card
   eligible again through `latch.confirmSpatialExit` and could surface a
   duplicate confirmation. The invalidation preserves consumed-card
   suppression, cancels any pending held-repeat authorization and clears slab
   label evidence so the scanner can read it again. Leave recognition pause
   and resume with the existing lifecycle and choice paths. Keep
   `resetObservationState()` for its current callers, since it clears the
   consumed record. [CardScanner](../../TradingCardScanner/Services/CardScanner.swift)

   Let the existing absence rules handle a brief exposure change. The active
   latch can clear after four blank OCR observations (`releaseAfterAbsences`).
   Duplicate admission through the ordinary blank-band path also requires
   2.0 seconds since the last matching read (`minimumAbsenceBeforeRelatch`).
   The separate six-second `presumedGoneAfter` backstop still applies. Revisit
   the approach if device measurements show exposure taking more than about
   a second to settle. [CardLatch](../../TradingCardScanner/Services/CardLatch.swift)
4. **Map the existing hint in `ScannerStatusView`.** When
   `CaptureAssistanceMonitor` reports `.lowLight`, choose the passive
   `ScanAssistanceView` message from the light state as shown above.
   `ScanAssistance.message` already returns no text for `.cameraSettling`.
   Keep the current guidance placement in `topStack`. The existing detector
   depends on readable footer text to establish a stable presentation, so the
   toolbar button also serves users in darkness where the hint never appears.
   [Assistance monitor](../../TradingCardScanner/Services/CardScanner.swift)
   · [Scanner status](../../TradingCardScanner/Views/ScannerView.swift)
   · [Passive guidance view](../../TradingCardScanner/Views/ScanSessionOverlays.swift)

## Acceptance

- **Focused tests.** Simulate absent, available and temporarily unavailable
  torch states, successful and failed taps, rapid taps and late callbacks
  after a modal, backgrounding or interruption. After inactivity, the request
  stays Off even if the hardware reports active. Start with the exit accumulator
  one observation short of a proof. A tracker box jump immediately after a user
  or system torch change produces no `SpatialResetProof`. Test two gaps since
  the last read, one with a third blank OCR observation at 2.0 seconds and
  one with a fourth blank before 2.0 seconds. In both cases an identical read
  stays suppressed. A genuine removal or replacement still scans.
  Hold a scanned card in the band, switch lenses and read it again. Confirm
  the switch emits no exit proof and the collection quantity stays the same.
  For the light, exercise a successful switch to a usable torch, a switch to
  an absent or unavailable torch, a failed swap and scene inactivity during
  a swap. After the request is cleared, switching back to a usable torch
  leaves it Off until the next tap. On a failed swap, check that the picker
  still shows the restored lens. A late callback from the old lens must leave
  the current request and checkmark alone.
  Verify the passive hint in each light state and that the button updates
  when light state changes while `ScannerTopBar`’s equality inputs stay fixed.
  [CardLatchTests](../../TradingCardScannerTests/CardLatchTests.swift)
  · [ScannerViewModelTests](../../TradingCardScannerTests/ScannerViewModelTests.swift)
  · [WholeCardHistoricalCaptureTests](../../TradingCardScannerTests/WholeCardHistoricalCaptureTests.swift)
- **Rendered UI.** At 320–375 pt (including iPhone SE widths), exercise the
  single-row fit check with the longest finish summary, the spinner, light and
  gear. Verify that fitting controls use one row and the longer configuration
  wraps with the spinner visible. On an iPad without a torch, compare the
  toolbar to the existing layout and check that the light leaves no empty slot.
  Open the scan-options menu at standard and largest text. Check that Camera
  is inline and present only with multiple lenses. After a successful switch,
  reopen the menu and confirm its checkmark matches Settings. Verify the
  picker title and option labels with VoiceOver.
  At standard and largest text in supported orientations, check that controls
  clear the reading band. Check contrast with Increase Contrast and Reduce
  Transparency, Reduce Motion, and VoiceOver focus and state announcements.
- **Physical devices.** Cover a Macro-capable iPhone and an iPad without a
  torch. Repeat paired off/on trials on the iPhone at the same working distance
  and ambient light with matte, foil, sleeved and slabbed cards. Record correct
  reads in a fixed window, time to first correct read, misses, false matches,
  duplicate adds and thermal dropouts. Require better reads in dim light, zero
  wrong or extra adds in the trial, reliable shutoff on exit and interruption,
  and usable sustained stack scanning. Hold a card in place through a toggle,
  including after a brief glare gap. Keep a scanned card in the band through a
  lens switch and confirm the quantity stays the same. Switch lenses with the
  light on where both inputs have usable torches and verify it comes back on
  once the new input is active. Check that a lens without a torch clears the
  request and hides the light control. Verify that a fresh launch chooses the
  default lens. Open Control Center, use its flashlight
  if available, and confirm the LED is off when Scan regains the camera. Check
  the normal light baseline with the light off to catch changes in
  responsiveness. [Launch camera and duplicate checks](../release/launch-contract.md)

**Design review verdict — RISK until rendered and tested on hardware.** Verify
toolbar fit, contrast against the live preview and VoiceOver state changes.

| Design check | Proposed disposition |
| --- | --- |
| Platform patterns | PASS — a familiar camera button beside Settings, with no navigation change. |
| Clarity and cognitive load | PASS — one control for the light. The existing guidance is passive text. |
| Typography and legibility | RISK — reflow before text clips and verify on the smallest supported layout. |
| Accessibility | RISK — verify the on/off glyphs, contrast, touch targets and spoken state over the real preview. |
| Interaction cost | PASS — one tap for the light and two taps for a lens change through the existing menu. |
| App Review design risk | PASS in the proposal — show the hardware state and keep the scanner usable when the light is unavailable. |

## Lens shortcut checkpoint — 2026-11-11

- The scan menu and Settings show the same confirmed lens. The switch queues
  tracker invalidation before changing inputs. A failed swap attempts to
  restore the previous input and leaves the checkmark on the last confirmed
  lens. These paths use the existing camera and recognition queues.
- Debug on iOS 27.0 Simulator at `d1d7fb8` plus the working tree executed
  234 tests across `CardLatchTests`, `ScannerViewModelTests` and
  `WholeCardHistoricalCaptureTests` with zero failures. The new cases cover
  a held card through a switch and a failed swap during an existing pause.
  Result bundle:
  `/Volumes/T7/CodexBuilds/ScannerLens-20261111.lp3Bwmky/LensTestsAccessibility.xcresult`.
- On the 375 pt iPhone 13 mini fixture, switching to Standard updated the
  menu checkmark and the Settings picker. The long finish summary moved to
  row two with its spinner. At largest text the lock count cleared the
  reading band and the native menu placed the lens rows below its first
  viewport. The iPad single-lens fixture showed neither lens choice. Real
  lens swaps and spoken VoiceOver remain to be verified on hardware.
- The paired iPhone 15 Pro Max was reachable over Wi-Fi for app launch,
  but the debugger did not return the camera capability. The Macro torch
  check and close-range optical trial remain pending.
