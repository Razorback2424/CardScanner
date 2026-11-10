# Views Guide

**Scope:** `TradingCardScanner/Views/`. Also follow [`../AGENTS.md`](../AGENTS.md).

Several files here carry workflow logic, not just layout: `ScannerViewModel` (scan acceptance), `CardCenteringView` (centering load/analysis and the precision editor), and the Collection/Browse navigation. Treat edits to them as behavior changes.

## Contracts to preserve

1. **Service ownership.** Use the session-scoped services passed in from the app; do not construct parallel stores or write ownership directly (see [`../Services/AGENTS.md`](../Services/AGENTS.md)). Keep high-frequency progress observation in the small view that renders it so it does not invalidate whole screens.
2. **Stable navigation identity.** Navigation destinations are keyed by stable identifiers (for example `Destination.card(entry.id)`), not by positions in a filtered result. An open detail must not disappear just because its card stops matching a filter or sort. Removal goes through `RemovedCardSnapshot` and the undo banner; preserve that state.
3. **Generation checks.** Async loads, analyses, and exports record a generation (`loadGeneration`, `analysisGeneration`, …) and drop results that no longer match. A cancelled or superseded photo load, analysis, or export must never publish into the current screen.
4. **Centering precision editor.** Done, ordinary blur, and removal are different paths: Done commits synchronously through `CardCenteringPrecisionCommitAction`; removal uses its own completion scheduler. Preserve locale-aware drafts (`LocalizedNumberInput`), the synchronous commit boundary, and the session tokens that ignore late events from an earlier editor.
5. **Coordinate spaces.** Native image pixels, working-image coordinates, view points, and screen pixels are different spaces. Convert with the existing mapping helpers; never substitute one for another.
6. **Reportable measurements.** Keep the confirmation and validity requirements before a centering result can be shared or exported.
7. **Shared components.** Reuse `ContentWidth`, `AppGlass`, and existing option/picker controls before inventing a new layout or visual convention.

## Visual verification

Do not claim a visual improvement without inspecting the rendered affected state: the relevant locale, Dynamic Type size, loading/empty/error state, and image scenario.

`scripts/ui_build_and_shoot.sh SCHEME BUNDLE_ID ROUTE [STATE]` builds, installs, launches a debug route, and screenshots. Know its defaults before running it:

- It **uninstalls the app (deleting its data)** on the target simulator unless `UI_PRESERVE_APP_DATA=1` or `UI_USE_INSTALLED_APP=1`. Use a dedicated test simulator via `UI_DEVICE_ID`, or preserve data deliberately.
- `DERIVED_DATA` defaults to `/tmp`; point it at the external SSD per the root guide, or reuse a build with `UI_PREBUILT_APP_PATH`.
- Debug routes write a ready marker; the script waits for it before capturing. For centering, set `UI_CENTERING_EXPECTED_SHA256` so the capture fails if the rendered input is not the intended image.
- Output goes to `ARTIFACTS_DIR` (default `./artifacts`). Screenshots are evidence, not commits.

Centering-specific capture: `scripts/centering_ui_build_and_shoot.sh`.

## Verification

Route to tests by behavior, not filename — see [`../../TradingCardScannerTests/AGENTS.md`](../../TradingCardScannerTests/AGENTS.md). Common picks: `ScannerViewModelTests`, `CenteringNativePrecisionTests`, `CenteringReviewTests`, `BrowseFeatureTests`/`BrowseCollectionTests`, `DetailDeletionRenderTests`, `ViewConstructionSmokeTests`.
