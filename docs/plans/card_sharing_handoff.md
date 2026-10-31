# Card sharing — implementation hand-off

**Status:** verified on Mac for Debug/Release builds, focused tests, exported
fixtures and scoped simulator layouts — 2026-10-31. Native sharing, real-card
interaction and physical-device acceptance remain open.

Branch `claude/card-share-sheet` now includes committed `main@17658c9` through
merge `f1ff681`. The original Linux-only implementation at `a9b48c7` has been
compiled and exercised on Mac. The original checkout's unrelated uncommitted
changes were preserved in place; verification used an isolated worktree.

## Mac verification — 2026-10-31

- Xcode 27.1, iOS 27.0, arm64 iPhone 16 simulator: Debug and Release pass.
  Release used `ONLY_ACTIVE_ARCH=YES`; this is simulator evidence, not an
  archive or physical-device build. No Xcode file-reference repair was needed.
- `CardShareContentTests`: **17/17 passed**, without changing its expectations.
  Four added `CardShareRenderTests` and eight `DetailDeletionRenderTests` also
  pass: **29/29**, including a rerun after the accessibility repair.
- Full-suite comparison: sharing branch **2,780 passed, 16 skipped, six failed**
  out of 2,802; clean `main@17658c9` **2,758 passed, 16 skipped, seven failed**
  out of 2,781. Comparing failed test identifiers found **zero new failures**.
  The six shared failures are the underlying-printing assertion in
  `CollectionKeyTests`, three local-StoreKit cases in `CollectorToolsTests`,
  the grouping-key assertion in `JustTCGV2GradedSurfaceTests`, and the
  notification-key assertion in `SwiftDataConcurrencyCharacterizationTests`.
  Main additionally timed out in `AppOpeningTests`; that case passed on the
  sharing branch. The full suite is not green, and these baseline failures
  remain outside this feature's verification scope.
- Fifteen generated-artwork export fixtures were inspected at 1080 × 1350:
  normal/Holo/Reverse/Foil, graded, sealed, unpriced, long names, portrait and
  panoramic personal photos, and history with no/under/equal/over-market asks.
  Graded and sealed fixtures use their correct price basis and attribution.
- Real sheet captures cover iPhone SE (3rd generation), standard and
  accessibility3 text, German currency formatting, and iPad Pro 11-inch (M4).
  The large-text asking row initially truncated its label, explanation and
  currency field; the corrected stacked row was rebuilt and recaptured.
- Export now refuses missing artwork instead of enabling Share with a
  placeholder. Personal photos retain their actual aspect ratio rather than
  being cropped to an arbitrary ratio range.

Build data, logs, result bundles and uncommitted captures are on the external
SSD under `/Volumes/T7/CodexBuild/card-share-20261031/`. Interrupted runs and the
build-database-lock attempt are not counted as completed verification.
After all full-suite test cases finished, Xcode stalled collecting optional
`simctl diagnose` output. Stopping only that diagnostic client finalized the
result bundle normally with the six baseline test failures preserved.

The full regression was launched before the final accessibility-only control
layout repair; the final Debug/Release builds, focused 29-test rerun and rendered
control-row captures cover that repair. Checked items below describe fixture or
capture evidence, not acceptance of every real card or external share target.

Design gate: **RISK** pending spoken VoiceOver and native share-target checks.
Native presentation/control patterns, clarity, captured typography and
interaction cost pass for the inspected fixtures. The three repaired issues
were placeholder export, personal-photo cropping and large-text truncation.
The remaining acceptance work is listed in the unchecked items below.

## What it does

A Share button replaces screenshots with a rendered 1080 × 1350 image plus the
same facts as plain text. The image is chosen by where Share is tapped:

| Entry point | Image | Only control |
|---|---|---|
| Collection card detail (pulls, trades) | Artwork — the user's own photo when present — name and collector number, set code and name, finish or grade badge, optional price | **Price** on/off, remembered (`@AppStorage("cardShare.includesPrice")`, default off) |
| Price Check result (should I buy this?) | Card thumbnail and identity, market price, optional asking price, 3-month trend and chart | Optional **Asking price** |

Product rules the code enforces:

- A raw price is labelled with the provider's condition ("Near Mint market"
  for TCGplayer, TCGCSV and JustTCG; otherwise "Market price"), never as the
  copy's condition, which the app does not record.
- The trend and chart need at least 5 observations spanning 14 days within 90
  days; otherwise both are omitted rather than guessed. "Near" the high or low
  means the top or bottom 10% of the range; mid-range says nothing.
- Graded price checks send no chart: market history is keyed to the raw printing.
- The image never states a verdict such as "buy" or "wait".

Design reference: the "ScanStash Share Cards" design canvas from the same
session (collection share, buy check, and their variants).

## Files

| File | Contents |
|---|---|
| `TradingCardScanner/Services/CardShareContent.swift` (new) | Pure logic: `CardShareIdentity`, `CardShareNumber`, `CardSharePrice`, `CardShareTrend`, `CardShareAsk`, `CardShareSummary`, `CardShareFormat` |
| `TradingCardScanner/Views/CardShareViews.swift` (new) | `CollectionShareImage`, `BuyCheckShareImage`, `CollectionShareSheet`, `BuyCheckShareSheet`, artwork loading, `ImageRenderer` rendering |
| `TradingCardScannerTests/CardShareContentTests.swift` (new) | 17 unit tests for the logic file |
| `TradingCardScanner/Views/CollectionCardDetailView.swift` | Share toolbar button, sheet, foil-sheen rule |
| `TradingCardScanner/Views/PriceCheckResultView.swift` | Share toolbar button (top leading), sheet, history request |
| `TradingCardScanner.xcodeproj/project.pbxproj` | Hand-edited entries `A0019001`/`B0019001`, `A0019002`/`B0019002`, `A0029001`/`B0029001` |

## 1. Build

```bash
git fetch origin claude/card-share-sheet && git checkout claude/card-share-sheet
xcodebuild build \
  -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath "<SSD>/DerivedData"
```

Build Release once as well. If Xcode shows a missing file, remove the three
hand-added references and re-add the files through Xcode.

Original compile-risk notes (none required a fix with Xcode 27.1):

| Location | Risk | Fix |
|---|---|---|
| `CardShareViews.swift` `CardShareButton` | `ShareLink(item:message:preview:)` without `subject:` | Add `subject: nil`, or share `[image]` and send the text separately |
| `CardShareContent.swift` `positionText` | `switch` expression assigned to a labelled tuple | Use a plain `switch` returning two strings |
| `CardShareArtworkLoader.load` | `UIImage` returned from `Task.detached` | Mirrors `ArtworkAccentStore`; otherwise load on the main actor |
| `ShareBadge`, `ShareTrendChart` bodies | `let` inside view builders | Move to computed properties |
| Any `nilIfEmpty` ambiguity | File-private helper also exists in `CollectionItemKind.swift` | Rename the share helper |

- [x] Debug build passes
- [x] Release build passes (arm64 simulator)

## 2. Unit tests

```bash
xcodebuild test \
  -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath "<SSD>/DerivedData" \
  -only-testing:TradingCardScannerTests/CardShareContentTests
```

Expected 17 passed. Expected values were computed by hand; if one fails, check
`testFallingTrendNearLowWithPartialHistory`, the German-locale case in
`testAskParsingAcceptsLocaleAndPastedFormatting`, and the exact summary text in
`testSummaryCarriesTheSameFactsAsTheImage` first.

- [x] `CardShareContentTests` 17/17; added render tests 4/4; detail render tests 8/8
- [x] Full suite has no new failures compared with clean main; six shared baseline failures remain

## 3. Simulator checks

Collection share (card detail → share icon left of the "…" menu):

- [x] Holo, Reverse or Foil export fixtures: sheen on catalog art; finish badge; `087` bright, `/165` dim
- [x] Normal export fixture: no badge, no sheen; unit test excludes Nonfoil badges
- [x] Graded export fixture: white PSA 10 pill, "PSA 10 market", JustTCG footer
- [x] Sealed export fixture: no number or set-code chip; "Market price"
- [x] Synthetic personal-photo fixtures: no sheen, portrait/panoramic proportions preserved
- [x] No-price sheet fixture: disabled Price switch and readable explanation, including accessibility3
- [ ] Price choice persists across sheets; with price off the footer shows only the mark
- [ ] Share reads "Preparing…" until artwork loads; saved image is 1080 × 1350 and matches the preview; text arrives in Messages

Buy check (Price Check result → share icon, top leading):

- [x] Raw history export fixture: trend headline, extreme-position text, end dot and dates
- [x] No-history export fixture: no chart or trend; larger thumbnail; insufficient-history unit tests pass
- [ ] Graded check: no chart
- [ ] No usable price: share icon disabled
- [ ] Asking price: decimal pad, keyboard Done and tapping the preview dismiss it; under (mint), over (pink), at market; dashed "Asking $X" line, still visible when the ask is below the 3-month low
- [ ] German region: `55,00` parses

Export fixtures verify under/over/at-market colors and the asking line below
the history low. German `55,00` parsing passes the unit test, and the German
large-text sheet was captured; actual typing and keyboard dismissal remain
manual. Graded-history suppression and no-price toolbar disabling were
inspected in source, but need a real result-flow check.

Both sheets:

- [x] Long-name export fixture truncates without hiding the number or badge; full identity remains in the text summary
- [x] Sheets stay dark over light simulator surfaces
- [x] iPhone SE: preview shrinks; controls and Share stay visible
- [x] iPad sizing: price-check and graded collection sheet captures
- [x] Accessibility3: both control rows remain readable; asking row clipping repaired
- [ ] VoiceOver: "Share card", "Share price check", "Image to share" with the summary, "Asking price"

## 4. Rendering questions

- [ ] The sheen's soft-light and overlay blend modes survive `ImageRenderer`; if the export differs from the preview, replace them with low-opacity white gradients
- [x] Missing/unfinished artwork cannot be exported (renderer guard and regression test); live slow-network timing remains manual
- [x] Exported chart end dot is not clipped, including asks outside the history range

## 5. Device checks

- [ ] Share to Messages, Instagram (Stories and feed), Discord and Facebook: no cropping; note where the text is dropped
- [ ] Image sharpness on device
- [ ] Owner judgment: is the foil-gradient Share button too loud beside the preview?

## Not implemented

- Share from catalog card detail and sealed-product browsing. Both would reuse
  `BuyCheckShareSheet` with a `CardSharePrice` and a
  `CardMarketHistoryRequest` from those screens. Sealed items already in the
  collection are covered by the collection share.
- End-to-end UI automation for the native ShareLink activity sheet. Render
  fixtures now live in `CardShareRenderTests`; `-ui_debug_route CardShareReview`
  opens the real sheets with named fixture states for repeatable captures.

## Remaining manual acceptance

1. Exercise both entry points with actual collection cards and scan results,
   including graded, sealed, personal-photo and no-price cases; confirm Price
   persists after closing and reopening the sheet.
2. Type asking prices, including `55,00` in Germany; verify live updates, Done
   and preview-tap keyboard dismissal. Perform the spoken VoiceOver checks.
3. Use Share → Save Image and compare that saved file with the preview,
   including the foil effect and 1080 × 1350 dimensions. Test slow networking.
4. On a real phone, send to Messages, Instagram Stories/feed, Discord and
   Facebook; verify cropping and which targets retain the text. Judge the
   colorful Share button on device.

See the dated verification entry in [`progress.md`](../../progress.md). These
manual gates remain open even when the pull request is available for review.
