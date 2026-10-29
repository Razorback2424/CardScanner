# Listing Photos redesign acceptance

Status: implementation and scoped Simulator verification complete — 2026-10-29.

Target: Listing Photos, single-card empty, ready and review/export states.
Route: `ListingPhotos`; synthetic states `empty`, `front`, `back`,
`collection` (metadata fixture), and `generated`.
Device: iPhone 17 / iOS 27 Simulator.
Build and capture evidence: `/Volumes/T7/CodexBuild/ListingPhotosRedesign-20261029/`.

The supplied HTML is a design reference, including its three state layouts.
Native navigation is retained for the existing Pro destination instead of drawing
a simulated sheet, grabber or status bar. Colors follow system appearance.
Collection has one device-local saved artwork photo per card; its picker adds that
photo as the front and explains this limitation. It never substitutes catalog
artwork for a photo of the user's card. Photos saves to the library, so its button
is named “Photos” rather than promising an album.

## Visual and interaction checks

- [x] Empty state has two dashed source tiles, Collection entry and disabled CTA.
- [x] Ready state shows both source images, inclusion checks and corner previews.
- [x] Review state separates source editing from selected-photo preview and two side grids.
- [x] Selecting a thumbnail changes the large preview; tapping it retains full-size inspection.
- [x] Generation and export remain pinned above the safe area; content scrolls.
- [x] Final light/dark and maximum Dynamic Type source/results captures inspected.
  Accessibility sizes stack tiles/buttons and keep primary labels inside padded
  capsules; decorative source symbols stay within their fixed badges.
- [x] Source menus, removal, styles/scope and Collection empty state verified.
  Removing the back after choosing Back only restores front-only generation and
  front preview numbering. Expanding the Styles sheet exposes all scope choices.
- [x] Files/share cancellation and reordering verified in the rendered app.
  Make Cover Photo moves the back to upload position 1 and updates the preview,
  both side grids and filenames. Full-size inspection still opens after Files
  cancellation. The share sheet contains 10 images; dismissing it keeps results.

## Regression checks

- [x] Final run: all 31 photo export/crop tests pass with no failures or skips,
  including preview ratios, lossless
  reordering across sides, original-file survival, numbered ZIP entries,
  back-only replacement numbering, and invalid-order rejection.
- [x] Wider focused run: 40 passed, one StoreKit test skipped and one failed.
  The unchanged purchase/reconstruction/restore test failed its immediate
  entitlement assertions at lines 196–197, then passed when rerun alone.
  This does not establish live purchase or sandbox readiness.
- [x] Final build/test compilation and `git diff --check` pass.

The first large-text capture caught startup; the settled capture exposed an
oversized checkmark and cramped Generate label. Both were corrected and the
source/results recaptured. Use `UI_CAPTURE_DELAY_SECONDS=20` with the existing
screenshot script to allow this checkout's startup work to settle. Simulator
appearance and content size were restored to light / large after verification.

The existing batch pipeline, single-card free access and paid batch ownership
checks remain in place. Reordering writes a fresh run without re-encoding pixels;
old files remain safe for an in-flight share. The old archive is allowed to
finish before its source run is retired.

## HIG gate

Verdict: **PASS** for implemented patterns and inspected layouts.
Top issues addressed: competing source actions,
source/result content competing on one screen, and dark teal text contrast.

- Platform patterns — **PASS**: system navigation, source menus, segmented picker,
  sheets, Photos picker and native Files export.
- Clarity — **PASS**: one primary action per state; photo count, cover and upload
  numbers describe the actual generated files.
- Typography — **PASS**: semantic fonts, stacked source tiles and export buttons
  at accessibility sizes; inspected at maximum Dynamic Type.
- Accessibility — **PASS** in source: labeled photo buttons and selection,
  alternative move actions, system materials and no added animation. Dark text
  uses a lighter teal; solid primary buttons keep white text on the darker teal.
- Interaction cost — **PASS**: generation and each export action take one tap;
  source removal remains in the source menu and long-press menu.
- App Review design — **PASS** for this feature's navigation and honest copy.

Minimal fixes are scoped to source/result layout, labels, contrast and Dynamic
Type in `EbayListingPhotosView`; lightweight previews and lossless order copies
are in `EbayListingPhotoExport`. No remaining scoped gate failure was identified.

Reference: [Apple accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility).
No physical-device, camera, live photo-library, provider, CloudKit, archive or
release readiness claim. VoiceOver behavior, populated Collection selection,
the drag gesture itself, photo-library saves and physical-device exports remain
manual checks; reordering was exercised through the equivalent context-menu
action. Earlier controls-only evidence is recorded in the 2026-10-29
entry in [progress](../progress.md).
