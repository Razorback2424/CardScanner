# Foil Effect Performance Remediation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the shiny/holo/foil presentation in collection tiles and card detail while removing the frame-time and scrolling regressions. If the optimized renderer still misses the measured performance budget, degrade the collection presentation surgically before considering a broader visual rollback.

**Architecture:** Measure the current path first, then separate motion sampling from SwiftUI view invalidation and give collection and detail independent delivery cadences. Re-profile that change before replacing the renderer: a custom renderer is a second-stage optimization only if the reusable SwiftUI gradient tree remains over budget, and its technology must be chosen by a small visual/performance spike because plain `CALayer` compositing cannot reproduce the current iOS blend modes. Preserve the existing treatment/variant eligibility rules and keep a static finish fallback available behind one policy boundary.

**Tech Stack:** SwiftUI, Core Motion, iOS 17, `OSSignposter` through the existing `PerformanceSignpost` helper, XCTest, and Instruments (`SwiftUI`, `Animation Hitches`, `Time Profiler`, and `Metal System Trace`). UIKit/Core Animation or another custom drawing path is conditional on the renderer spike. The project currently has no UI-test target.

---

## Investigation findings

### Code-backed cause

The current implementation exposes one confirmed invalidation multiplier and one plausible per-update rendering cost in the collection grid:

1. `TradingCardScanner/Views/CardFinishOverlay.swift` owns one app-scoped `CardFinishMotionSource`, but every eligible `CardFinishOverlay` observes it with `@ObservedObject`. Every `tilt` publication therefore invalidates every visible foil/reverse overlay. The source publishes from the main queue at 30 Hz for the grid and 60 Hz when detail is active, with no meaningful-change threshold.
2. Each invalidated overlay evaluates a masked `ZStack` containing four soft-light gradient bands plus a fifth plus-lighter specular gradient. Each gradient is oversized to twice the card diagonal, rotated, offset, and composited through a rounded-rectangle mask. That is a credible CPU/GPU cost, but repository inspection alone does not establish how much of each gradient subtree SwiftUI/Core Animation reuses or whether this renderer is independently over budget after the observation fan-out is removed. Treat it as a trace-backed question, not a proven second root cause.

There is a third multiplier in regular-width split view: `startDetail()` raises the shared source to 60 Hz while the collection grid can remain mounted and visible. The grid is then rendered at the detail cadence even though its intended cadence is 30 Hz.

### History-backed regression boundary

The feature was originally detail-only. Commit `ef142d1` extracted the private detail overlay into `CardFinishOverlay.swift`, introduced the shared source, and added the overlay to `CollectionCardTile`. Before that extraction, one detail view owned one 60 Hz motion model; there was no grid-wide observer fan-out. This makes the collection integration in `ef142d1` the first high-confidence regression boundary, while the gradient/mask renderer itself is an older cost that now affects many more surfaces.

### What is not currently implicated

- `CollectionRow.hasSpecularFinish` is a pure eligibility predicate defined in `TradingCardScanner/Services/CollectionQuery.swift` and covered by existing collection-query tests. It should remain the collection-grid source of truth for which rows can show a finish. Detail currently calls `CardFinishOverlay` unconditionally and lets the overlay enforce catalog/variant eligibility, so the plan must preserve that distinction rather than moving detail onto a `CollectionRow` API.
- Magic treatment persistence and compatibility rules are data behavior, not the per-frame bottleneck. They must remain unchanged.
- Artwork loading and `CollectionArtworkGlow` are not driven by `tilt`, so they do not explain the 30/60 Hz invalidation path. They still need identical local artwork in foil/non-foil controls so image decode, blur, or glow cost does not contaminate the comparison.

### Evidence limits

The repository inspection establishes the invalidation and rendering paths above, but there are no trace-backed frame, CPU, GPU, or hitch metrics yet. Existing visual QA and the current debug fixtures do not stress a grid containing many animated foil surfaces. Because `LazyVGrid` creates approximately the visible/prefetched subset, fixture totals of 12/24/48 exercise scroll and lifecycle behavior but do not imply 12/24/48 simultaneous renderers; diagnostics must record the active renderer count. Implementation work must begin with a reproducible fixture and release/device profiling. Any numeric acceptance threshold below is a proposed product budget to confirm against a baseline, not a measurement already present in the repository.

## Performance decision

Preserve the feature and proceed through measured gates:

1. Capture baseline traces and counters for the current implementation.
2. First separate collection/detail delivery, suppress noise, and tie the sensor to visible overlays. One sensor remains shared, but collection renderers receive at most 30 Hz and detail renderers can receive 60 Hz without promoting the grid. Re-profile here; this is the smallest change that attacks the confirmed cadence/lifecycle multipliers.
3. Only if that change still misses the budget and traces attribute the remainder to SwiftUI motion-driven updates, prototype renderer-local direct updates and compare both traces and visual fidelity. Candidates may include a fixed SwiftUI/`Canvas` drawing subtree or a UIKit/Core Animation surface. Do not assume one `CAGradientLayer` can preserve the existing four independently soft-light bands and plus-lighter core: `CALayer.compositingFilter` is not supported on iOS, and merging bands changes overlap/color behavior. Choose and document the public-API implementation that passes the visual baseline and performance gate before committing the full rewrite.

If the measured budget still fails after the staged changes, use the same policy boundary to make collection effects static while retaining a live detail effect. Only if detail also fails should live detail motion be disabled; the finish identity remains visible through the treatment badge/status and a centered static sheen. This is a presentation rollback, not a rollback of treatment data, collection identity, or the footer work.

## Files and responsibilities

| File | Planned responsibility |
| --- | --- |
| `TradingCardScanner/Views/CardFinishOverlay.swift` | Keep the public SwiftUI call site, extract a pure render plan, separate collection/detail delivery, and own source cadence/lifecycle policy. Keep the existing renderer through the first re-profile gate; replace observation with direct renderer registration only if traces require the custom-renderer phase. |
| `TradingCardScanner/Views/CardFinishSurfaceView.swift` (conditional) | Add only if update isolation is insufficient and the renderer spike selects a custom UIKit/Core Animation implementation. Configure drawing resources only when the plan or bounds changes; apply tilt without reconstructing the SwiftUI subtree. |
| `TradingCardScanner/Views/CollectionView.swift` | Keep `hasSpecularFinish` eligibility and stable tile identity; use the collection delivery channel and remove snapshot-wide motion lifetime assumptions that can outlive visible tiles. |
| `TradingCardScanner/Views/CollectionCardDetailView.swift` | Keep the existing detail placement and unrelated local changes; switch only the overlay delivery/lifecycle, plus the renderer if the measured gate selects one. |
| `TradingCardScanner/App/TradingCardScannerApp.swift` | Continue injecting one app-scoped motion source unless profiling shows a screen-scoped source is cleaner; do not create one motion manager per tile. For the opt-in performance build only, use an isolated local/in-memory store so fixtures never mix with or mutate a real collection. |
| `TradingCardScanner/Services/CollectionQuery.swift` | No behavior change expected. Preserve `CollectionRow.hasSpecularFinish` and treatment compatibility semantics. |
| `TradingCardScanner/Services/PriceStore.swift` (existing `PerformanceSignpost` owner) | Add narrowly scoped card-finish sampling/render signposts and debug counters if the existing helper supports them; keep diagnostics removable or cheap in release. |
| `TradingCardScanner/Views/ContentView.swift` | Add a deterministic performance-only debug route without changing the normal collection route. |
| `TradingCardScanner/Views/PortfolioDebugFixtures.swift` | Add a local/offline fixture containing controlled counts of foil, holo, reverse, non-foil, and sealed rows. |
| `TradingCardScannerTests/CardFinishRenderPlanTests.swift` | New pure tests for eligibility, family, fallback, cadence, and accessibility behavior. |
| `TradingCardScannerTests/CardFinishMotionSourceTests.swift` | New tests using a fake clock/sink; no Core Motion hardware required. |
| `TradingCardScannerUITests/CardFinishPerformanceTests.swift` (conditional) | The project has no UI-test target. Do not create one as part of the core remediation; add it only as a separately justified test-infrastructure step. The deterministic route plus Instruments is the required performance harness. |

Do not overwrite the pre-existing unrelated change in `CollectionCardDetailView.swift` that resolves `gradedVariantEvidence` through `underlyingPrintingID`. Do not reset or revert unrelated worktree changes.

## Implementation tasks

### 1. Freeze the behavioral contract and add a stress fixture

- [ ] Record the current finish contract in tests before changing the renderer: catalog-confirmed raw foil, holo, and reverse rows can animate; graded/sealed collection rows do not receive the overlay; incompatible required finishes disable the collection effect; `neonInk` keeps its neon family; nil, `.catalogSilent`, and `.imported` resolution do not render; Reduce Motion keeps a centered static sheen, while Reduce Transparency removes it and stops motion.
- [ ] Add a deterministic `CollectionFinishPerformance` route seeded entirely from local fixture data. Compile it under `#if DEBUG || CARD_FINISH_PERF_HARNESS`, and build Release profiling artifacts with the opt-in `CARD_FINISH_PERF_HARNESS` condition; do not expose the route in ordinary Release/App Store builds. Apply the same condition to the required `PortfolioDebugFixtures` code.
- [ ] Make the performance-harness launch use an isolated in-memory or dedicated local SwiftData store selected before `TradingCardScannerApp.container` is created. Never clear, reuse, or seed the user's normal CloudKit/local collection. Reset that isolated store between scenarios so total row counts are exact rather than “seed if empty.”
- [ ] Provide at least 12, 24, and 48 eligible raw rows, mixed across foil/holo/reverse and normal rows, plus a sealed/non-foil control set. Use the exact same bundled/local artwork payload and glow inputs for foil and non-foil controls so network latency, remote image decoding, and artwork-derived styling do not decide the result.
- [ ] Make the route expose stable launch arguments for row count and these cases: `grid-only`, `grid-with-detail`, `nonfoil-control`, `single-detail`, and `single-detail-control`. Keep the existing `CollectionTiles` and `CardDetail` routes unchanged.
- [ ] Add cheap signposts and debug-only counters for active finish renderers, sensor callbacks, delivered collection updates, delivered detail updates, and SwiftUI overlay body evaluations. Use signposts for timeline events/intervals and counters for accumulated totals; do not emit one persisted log message per renderer per frame.

Expected result: one repeatable route can compare identical local artwork/data with and without the finish, report how many renderers are actually active, and show whether a detail view promotes collection updates to 60 Hz.

### 2. Capture the baseline before changing the update path

- [ ] On a physical target device, record the `nonfoil-control`, `grid-only`, `single-detail`, and `single-detail-control` scenarios with the current implementation. Use the active-renderer counter to state how many overlays were actually alive during each interval.
- [ ] On a regular-width iPad, record `grid-with-detail`; an iPhone is not a valid device for proving the split-view cadence issue because the collection and detail generally do not remain side by side there.
- [ ] Capture update counts, hitch rate/count, main-thread samples, render/GPU work, device model, OS, build configuration, fixture size, active renderer count, and the exact interaction duration. Save the raw traces and a short baseline table before altering the implementation.
- [ ] Confirm from the SwiftUI instrument that `CardFinishOverlay.body` evaluations correlate with motion publications. If they do not, revise the diagnosis before continuing rather than optimizing an unobserved path.

Expected result: the plan has trace-backed baseline evidence and can attribute the symptom among update fan-out, main-thread work, render/GPU work, and unrelated scrolling cost.

### 3. Extract a pure render plan before changing rendering technology

- [ ] Add a value type near the overlay implementation, or in a new focused file, with only render inputs and derived values. Its shape should be equivalent to:

  ```swift
  struct CardFinishRenderPlan: Equatable, Sendable {
      enum Mode: Equatable, Sendable {
          case disabled
          case staticSurface
          case live(rateHz: Int)
      }

      let family: SheenFamily?
      let isReverse: Bool
      let mode: Mode
  }
  ```

- [ ] Build the plan from the existing variant, resolution, displayed treatment evidence, `motionUsage`, Reduce Motion, Reduce Transparency, and the eventual performance policy. Do not duplicate treatment compatibility logic in the renderer.
- [ ] Preserve the current visual families: dispersed foil for the ordinary supported foil/reverse variants and neon for `neonInk`. Keep concrete colors, stops, band overlap, and blend implementation in a renderer style/configuration rather than treating them as eligibility policy. Do not prematurely encode a one-gradient approximation in the pure plan.
- [ ] Make static mode a centered, non-updating plan rather than a hidden/removed identity. Disabled mode is reserved for Reduce Transparency or an explicit emergency fallback.

Expected result: eligibility, family, cadence policy, and accessibility behavior can be unit-tested without SwiftUI, Core Motion, or a simulator. Pixel output and blend fidelity still require rendered validation.

### 4. Separate collection/detail delivery and suppress immaterial updates

- [ ] Keep exactly one `CMMotionManager` for the app/environment and make `CardFinishMotionSource` main-actor isolated. Inject the motion sampler and monotonic clock/scheduler seams needed for deterministic tests; tests must not depend on Core Motion hardware or wall-clock sleeps.
- [ ] First implement separate collection and detail delivery channels. Collection subscribers receive no more than 30 Hz even while detail causes the sensor to sample at 60 Hz; detail subscribers may receive 60 Hz. This can retain a small observable endpoint per channel for the existing SwiftUI renderer during the first re-profile.
- [ ] Deduplicate negligible *delivered* tilt changes using a named, tested threshold. Keep internal smoothing fed by all sensor samples so the threshold does not change the filter response. Also deliver/reset the centered state when motion stops so the existing Reduce Motion behavior is preserved.
- [ ] Replace the root `gridIsActive` Boolean with visible eligible-overlay registration (or a reference-counted equivalent) so off-screen eligible data does not keep Core Motion active. Store registrations weakly or return idempotent registration tokens; do not depend on balanced `onAppear`/`onDisappear` calls alone.
- [ ] Re-run the baseline scenarios. If this phase meets the accepted budget, stop here: do not introduce a custom renderer solely because it was anticipated by the original plan.
- [ ] If traces still show SwiftUI body/update cost from motion delivery, introduce a main-actor sink API for a custom renderer similar to:

  ```swift
  @MainActor
  protocol CardFinishMotionSink: AnyObject {
      var requestedRateHz: Int { get }
      func applyCardFinishTilt(_ tilt: CGSize)
  }

  @MainActor
  final class CardFinishMotionSource: ObservableObject {
      func register(_ sink: any CardFinishMotionSink)
      func unregister(_ sink: any CardFinishMotionSink)
  }
  ```

- [ ] For the sink path, store weak sink registrations or idempotent registration tokens, track the maximum requested sensor rate, and throttle each sink by monotonic timestamps. A detail sink may receive 60 Hz; a collection sink receives no more than 30 Hz even when the sensor is sampling at 60 Hz for a simultaneously visible detail sink.
- [ ] Keep motion lifecycle and accessibility transitions explicit. When Reduce Motion becomes enabled, unregister/stop live updates and apply the centered static plan; when it becomes disabled, re-register only visible live sinks.

Expected result: a split-view detail never makes collection deliveries exceed 30 Hz, immaterial sensor noise does not cause deliveries, and the sensor stops when no visible live finish exists. If a custom renderer is required, its direct sink path causes no motion-driven `CardFinishOverlay.body` evaluations.

### 5. If still required, spike and implement a custom renderer

- [ ] Preserve the current renderer as a reference fixture and add a performance-harness-only synthetic-tilt input so centered and representative positive/negative tilts are deterministic. Capture those states for dispersed foil, neon, and reverse. Screenshot comparison cannot validate motion by itself, so also perform a short physical-device tilt review.
- [ ] Build the smallest spike needed to compare fixed SwiftUI/`Canvas` drawing and a UIKit/Core Animation custom view against the baseline. Record CPU, GPU/render, memory/allocation, and visual differences. Reject any option that depends on unsupported iOS `CALayer.compositingFilter` behavior.
- [ ] Select the renderer only after the spike. If a custom view wins, add `CardFinishSurfaceView.swift` with a `UIViewRepresentable` wrapper and a private drawing/layer owner implementing `CardFinishMotionSink`. If the existing SwiftUI renderer meets budget after delivery changes, do not create this file.
- [ ] Configure drawing resources only when the render plan, bounds, corner radius, or accessibility policy changes. The normal tilt path must mutate existing geometry/state directly, disable unintended implicit animation, and avoid recreating gradients, paths, masks, or color arrays per callback.
- [ ] Preserve the existing independent soft-light bands and plus-lighter core where the selected public API supports them. If the chosen renderer approximates those blends or merges bands, document the visual delta and require explicit visual acceptance; do not describe the result as behavior-preserving by construction. Reverse surfaces must retain the border-only mask.
- [ ] Preserve hit-testing behavior (`allowsHitTesting(false)`), corner radius, card clipping, and the existing detail visual placement.
- [ ] Keep `CardFinishOverlay` as the SwiftUI-facing wrapper so call sites remain small and the existing feature can be disabled at one boundary. It should choose the plan and host the selected rendering surface. If the custom-renderer phase is entered, the wrapper must not observe per-frame motion directly.
- [ ] Ensure the selected renderer cleans up its registration in the lifecycle hook appropriate to that implementation (`dismantleUIView` for `UIViewRepresentable`, or the equivalent disappearance/token cleanup) and does not leak renderer owners as a lazy grid scrolls.

Expected result: only if baseline evidence requires it, a tilt update becomes bounded renderer-local work with no motion-driven SwiftUI body evaluation, while the recorded visual baseline remains acceptably close.

### 6. Integrate collection, detail, and fallback policy

- [ ] In `CollectionView.swift`, keep `row.hasSpecularFinish` as the eligibility check and preserve stable `entry.id` identity. Use the collection delivery channel or selected custom renderer with `live(rateHz: 30)` when policy allows it.
- [ ] In `CollectionCardDetailView.swift`, preserve the hero layout and use the detail delivery channel or selected custom renderer with `live(rateHz: 60)` when the detail plan is active. Leave the unrelated graded-printing change intact.
- [ ] Remove the snapshot-wide `startGrid`/`stopGrid` coupling once visible-overlay registration owns lifetime. A collection containing eligible off-screen rows but no visible live renderer must not keep Core Motion active.
- [ ] Add a single `CardFinishPerformancePolicy` boundary with explicit collection and detail outcomes, for example `.live`, `.staticCollection`, `.staticAll`, and `.disabled`. Do not overload `.disabled` to mean static detail. The default remains `.live` while the optimized path is being profiled.
- [ ] If profiling shows only the grid misses budget, switch collection to centered static sheen while keeping detail live. If detail also misses budget after the selected renderer work, use static detail as the explicit rollback. Do not remove treatment labels, finish dots, variant identity, or persisted treatment evidence.
- [ ] Do not make an unmeasured active-tile threshold the primary fix. If an adaptive threshold is useful after profiling, derive it from measured device budgets, document it in the policy, and test the boundary.

### 7. Add regression tests before claiming the fix

- [ ] Add `CardFinishRenderPlanTests` covering:
  - raw foil, holo, and reverse eligibility;
  - ordinary dispersed and `neonInk` families;
  - incompatible required finish evidence;
  - graded and sealed rows;
  - catalog-silent/imported resolution;
  - Reduce Motion, Reduce Transparency, static collection fallback, and disabled plans;
  - stable renderer-configuration expectations only for the implementation selected by the measured gate; do not assert an arbitrary layer count in pure policy tests.
- [ ] Add `CardFinishMotionSourceTests` with a fake motion sampler and monotonic clock. Cover channel registration/unregistration, lifecycle cleanup, epsilon deduplication, 30 Hz collection delivery, 60 Hz detail delivery, and mixed-rate split view delivery. Add weak-sink cleanup tests only if the custom sink path is selected.
- [ ] Extend the existing collection-query tests only where the render policy depends on an existing eligibility rule. Do not move treatment semantics into performance tests.
- [ ] Use the deterministic debug route for a manual/device smoke pass that verifies the finish remains visible in live and static modes, the grid remains scrollable, and Reduce Motion stops live deliveries. If a UI-test target is separately added, automate the same route; do not make that new target a prerequisite for the fix.
- [ ] Keep Instruments/signposts as the performance harness. XCTest timing on Simulator is not a substitute for the device frame/hitch gate.

### 8. Profile on a release configuration and apply the decision gate

Run these only when implementation work is authorized; they are deliberately not being run during plan authoring.

- [ ] Profile on a physical 60 Hz iPhone representative of the supported device floor in a Release configuration; use Simulator only for smoke and route repeatability. Capture non-foil control, 24 and 48 total eligible rows, and single foil detail. Use a physical regular-width iPad for the grid-plus-detail scenario and report its refresh rate separately.
- [ ] Use Instruments `SwiftUI` and `Time Profiler` to record body/update fan-out and main-thread work. Use `Animation Hitches` for hitch duration/count and `Metal System Trace` for compositor/GPU pressure. Keep the trace and scenario metadata with the review artifacts.
- [ ] Compare before/after using the same device, OS, data fixture, route, and interaction sequence. Capture at least 10 seconds idle and one fixed-distance scroll for each scenario.
- [ ] Before remediation coding begins, record the accepted numeric budget beside the baseline table. The following are provisional gates, not repository facts; keep them only if the target-device baseline and product expectation make them meaningful:
  - on a 60 Hz target, collection p95 frame duration is at or below one 16.7 ms frame budget during the fixed scroll for the 48-row fixture (report active/prefetched renderer count too; do not call all 48 visible);
  - foil collection is no more than 2 ms p95 slower than the identical-artwork non-foil control, and Animation Hitches shows no new user-perceptible hitch interval attributable to the finish;
  - single foil detail stays at or below 16.7 ms p95 and remains within 10% of the identical-artwork non-foil detail control;
  - split view does not increase collection render updates above 30 per second per eligible tile when detail is open;
  - Reduce Motion produces zero live motion deliveries after the accessibility transition and no active motion source when no live sink remains;
  - active renderer counts return to the visible/prefetched steady-state range after scrolling, with no monotonic growth over a 60-second scroll/idle pass.
- [ ] If the selected optimized live path fails only the collection gate, set the default collection policy to `.staticCollection`, retain live detail, and record the measured reason. If it fails the detail gate too, use static detail as the last presentation fallback and preserve all finish identity surfaces.
- [ ] Run `git diff --check`, the focused render/motion tests, the existing collection-query tests, and then the full suite only after the performance decision is recorded. The final report must distinguish code-backed conclusions from trace-backed measurements.

## Future verification commands

These commands belong to implementation/verification, not this planning turn. First resolve the actual available simulator/device and Release executable rather than committing a machine-specific UDID or DerivedData path to the plan:

```sh
xcodebuild -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -showdestinations

xcodebuild test \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

xcrun xctrace list devices
xcrun xctrace list templates

xcodebuild build \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  OTHER_SWIFT_FLAGS='$(inherited) -DCARD_FINISH_PERF_HARNESS'
```

Use the listed simulator in place of `iPhone 17 Pro` if that runtime is unavailable. Then record each scenario with the resolved values using `xctrace record --template <template> --device <name-or-UDID> --time-limit 15s --output <unique.trace> --launch -- <Release-executable> -ui_debug_route CollectionFinishPerformance -scenario <scenario>`. Record the exact resolved command and Xcode version with the artifact; verify template names against `xctrace list templates` because they are toolchain-dependent. Expected test output is a passing focused suite and full suite with no new failures. Expected trace output is a saved trace for each scenario with frame/hitch and body-update measurements; a successful build alone is not evidence that the performance issue is fixed.

## Validation references

- Apple, [Performance analysis for SwiftUI](https://developer.apple.com/documentation/swiftui/performance-analysis): use Instruments to identify frequent or long view updates that contribute to hangs and hitches.
- Apple, [Demystify SwiftUI performance](https://developer.apple.com/videos/play/wwdc2023/10160/): reduce unnecessary dependencies and updates, and keep body evaluation cheap; this supports measuring the observation fan-out before replacing rendering technology.
- Apple, [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness): use the Animation Hitches template and its commit/render/GPU/frame-lifetime tracks for the scrolling comparison.
- Apple, [`CALayer.compositingFilter`](https://developer.apple.com/documentation/quartzcore/calayer/compositingfilter): the property is not supported on iOS, so it cannot be the assumed mechanism for preserving the current `.softLight`/`.plusLighter` composition.

## Rollback boundary

If the optimized implementation cannot meet the acceptance gate, make the smallest presentation-only change necessary:

1. Set collection finish mode to `.staticCollection` and keep the finish marker/treatment evidence plus live detail.
2. If detail still fails, set detail to centered static sheen while retaining the same card artwork, treatment family, and variant identity.
3. Only as a last resort remove the collection `CardFinishOverlay` call while retaining the detail path and all data behavior.

Do not revert the entire collection-footer commit, treatment persistence, or unrelated worktree changes. This keeps the feature’s product meaning while making the expensive motion/compositing path independently reversible.
