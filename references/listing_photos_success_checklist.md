# Listing photo controls acceptance

Target screen: eBay Listing Photos, single card.
Route: `ListingPhotos`; synthetic states `empty`, `front`, `back`, `generated`.
Device: iPhone 17 / iOS 27 Simulator.
Evidence: `/Volumes/T7/CodexBuild/ListingPhotos-20261029/`.

## Visual and interaction checks

- [x] Each side has one Add / Replace menu with camera, Photos and Files options.
- [x] Attached photos have a visible remove action; clearing one leaves the other usable.
- [x] Empty state explains optional sides and disables generation.
- [x] Front-only and back-only states offer five-photo generation.
- [x] Both attached sides expose Both sides / Front only / Back only selection.
- [x] Five-photo output exposes export actions with the correct count.
- [x] Light/dark appearance, large text, safe areas and navigation remain usable.
- [x] Final screenshot inspected after the last code change.

## Regression checks

- [x] Front-only and back-only export tests check five files, preview/dimension counts,
  native full-photo bytes, correct crop dimensions and side-specific ZIP contents.
- [x] Empty-source requests fail before creating a temporary run.
- [x] Existing pair, file ownership, cancellation and crop tests pass.

Verification is limited to synthetic Simulator data. Actual camera capture,
photo-library saves, physical-device sharing and VoiceOver remain manual checks.

## UI / UX review

Verdict: **PASS** for the inspected screen and interactions. The three original
issues were competing source controls, no attachment removal, and a silent
requirement for both sides. The focused fixes are in `EbayListingPhotosView` and
`EbayListingPhotoExport`.

- Platform patterns — **PASS**: native menus, pickers and existing navigation.
- Clarity / cognitive load — **PASS**: one source menu per side, optional-side copy,
  visible removal and an explicit generation action with the expected photo count.
- Typography — **PASS**: accessibility sizes use vertical source rows and a menu
  for generation scope; maximum Dynamic Type no longer splits short labels.
- Accessibility baseline — **PASS** for inspected layout/source: named actions,
  44-point source/removal targets, text plus status symbols, no custom motion or material.
- Interaction cost — **PASS**: related source choices take two taps as requested;
  generation is one tap after choosing its scope. This is outside Now/autoscheduler.
- App Review design — **PASS** for this scoped change; release readiness is not assessed.

Generation is now deliberate instead of automatic, adding one tap to the old
two-source path so users can choose which side to process. Side-only output keeps
01–05 / 06–10 filenames and exports only those five photos, allowing replacement
of the matching half of an existing set.

Focused Debug Simulator tests: **38 passed, 1 skipped, 0 failures**. The skipped
StoreKit interrupted-purchase scenario reports an existing sandbox follow-up.
The final UI build succeeds. The first capture targeted the startup screen;
subsequent route captures allow 20 seconds for existing startup work to settle.
Small screenshot staging uses system temporary storage because Simulator cannot
write directly to the removable volume; build outputs and evidence use the T7.
