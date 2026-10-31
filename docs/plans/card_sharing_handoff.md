# Card sharing — implementation hand-off

**Status:** post-merge artwork-recovery follow-up — 2026-10-31. Debug tests,
Release simulator build and scoped captures pass. Native sharing,
real-card interaction and physical-device acceptance remain open on `main`.

[PR #6](https://github.com/Razorback2424/CardScanner/pull/6) merged at
15:41:17 UTC as `3053218`, after its verified draft state at 15:37. Draft status
did not keep the feature off main. The remaining manual gates apply to main.

**Known regression at reviewed `main@3053218`:** `e503728` prevented placeholder
export by refusing all exports without artwork. That stranded manual entries,
unillustrated sealed products and failed/offline image loads. The original
guard-only test did not establish a usable recovery path. That behavior is
repaired separately on `fix/card-share-artwork-recovery`; its evidence follows.

## Post-merge review follow-up — 2026-10-31

- Based on `main@3053218`. Both sheet images now have an intentional layout
  without artwork, with identity and available prices and no photo placeholder.
  Share becomes available after rendering those facts, even while artwork is
  loading. A failed load offers **Retry** when there is a source to retry;
  items with no source can still share their facts and close the sheet.
- Removed the renderer's separate `artwork:` gate. Rendering depends only on
  the view supplied. A shared artwork state handles load completion and retry,
  discarding late results from older attempts.
- Personal photos between 1:3 and 3:1 keep their proportions. More extreme
  shapes receive a **centered crop** to those bounds, with corner radius based
  on the shorter edge. This replaces the earlier unrestricted thin-strip
  behavior; it does not promise that every extreme photograph stays whole.
- The accessibility asking field has symmetric insets and retains its required
  height when the recovery row is present. DEBUG review artwork is generated
  locally through an injected loader; its states require no provider or warm
  image cache.
- Final Debug selection: **33 passed, zero failed/skipped** (17 logic, eight
  render/recovery, eight detail-render tests). It exercises empty sources,
  suspended loading, failure, successful retry and a late superseded result.
  Both actual share-image views export without artwork; no unrelated image is
  passed to a renderer guard to make the tests pass.
- Inspected 23 exported fixtures and actual iPhone SE sheets, including a
  source-free collection share and a failed price-check share at accessibility3
  with German formatting. Close, Retry where applicable, and Share are visible;
  the asking field fits inside its background. Native taps, saved-file parity
  and physical-device acceptance remain manual.
- Final Release build passes with Xcode 27.1 for the arm64 iPhone 16 / iOS 27
  simulator, using `ONLY_ACTIVE_ARCH=YES`. The full suite was not rerun for this
  follow-up;
  the earlier full-run comparison below is historical evidence, not a fresh
  assertion about this branch.

Local evidence is on the external SSD under
`/Volumes/T7/CodexBuild/card-share-recovery-20261031/`. The source review's
functional dead end is tracked explicitly here rather than certified by the
original placeholder-prevention checkbox.

Follow-up design verdict: **RISK** pending native actions and spoken VoiceOver.
Platform patterns, clarity, captured typography and interaction cost pass for
the tested fixtures: Share stays primary and Retry is optional. Accessibility
and App Review interaction acceptance still require the manual checks below.

## Initial Mac verification — 2026-10-31 (historical)

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
- The initial export guard refused missing artwork, introducing the dead end
  described above. Its unlimited photo aspect ratio also allowed extreme thin
  strips. Those two earlier implementation claims are superseded by the
  post-merge follow-up; the initial build/test counts remain historical facts.

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
interaction cost pass for the inspected fixtures. The initial fixes addressed
placeholder export, personal-photo cropping and large-text truncation; review
found the first two incomplete as described above.
The remaining acceptance work is listed in the unchecked items below.

## What it does

A Share button replaces screenshots with a rendered 1080 × 1350 image plus the
same facts as plain text. The image is chosen by where Share is tapped:

| Entry point | Image | Only control |
|---|---|---|
| Collection card detail (pulls, trades) | Artwork — the user's own photo when present — name and collector number, set code and name, finish or grade badge, optional price | **Price** on/off, remembered (`@AppStorage("cardShare.includesPrice")`, default off) |
| Price Check result (should I buy this?) | Card thumbnail and identity, market price, optional asking price, 3-month trend and chart | Optional **Asking price** |

Product rules the code enforces:

- Missing, loading or failed artwork uses a deliberate layout without a photo;
  it does not block sharing. Retry is optional when an artwork source exists.
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

- [x] Follow-up: `CardShareContentTests` 17/17; render/recovery tests 8/8; detail render tests 8/8
- [x] Initial full suite had no new failures compared with clean main; six shared baseline failures remain (historical run, not repeated for the follow-up)

## 3. Simulator checks

Collection share (card detail → share icon left of the "…" menu):

- [x] Holo, Reverse or Foil export fixtures: sheen on catalog art; finish badge; `087` bright, `/165` dim
- [x] Normal export fixture: no badge, no sheen; unit test excludes Nonfoil badges
- [x] Graded export fixture: white PSA 10 pill, "PSA 10 market", JustTCG footer
- [x] Sealed export fixture: no number or set-code chip; "Market price"
- [x] Synthetic personal-photo fixtures: no sheen; ordinary proportions preserved and extreme shapes cropped to 1:3–3:1 with adaptive corners
- [x] No-price sheet fixture: disabled Price switch and readable explanation, including accessibility3
- [ ] Price choice persists across sheets; with price off the footer shows only the mark
- [x] Follow-up: Share is available after rendering the facts, including missing, suspended and failed artwork loads; Retry is visible when a source exists
- [ ] Native saved image is 1080 × 1350 and matches the preview; text arrives in Messages

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
- [x] Follow-up fixtures export the facts without a photo during missing/unfinished/failed loads, without exporting a photo placeholder
- [ ] With actual images missing or the network off, confirm native Share, Retry when applicable, and Close work; the earlier refusal-to-export guard was a known dead end
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
  opens the real sheets with locally generated artwork and named missing,
  failed, retry, slow and extreme-photo states for offline captures.

## Remaining manual acceptance

1. Exercise both entry points with actual collection cards and scan results,
   including graded, sealed, personal-photo and no-price cases; confirm Price
   persists after closing and reopening the sheet.
2. Open Share on a manual entry or sealed product with no image, and with the
   network off. Confirm the fact-only preview, native Share, optional Retry and
   Close. Share a very tall photo and panorama; assess the intentional centered
   crop when the source is outside 1:3–3:1.
3. Type asking prices, including `55,00` in Germany; verify live updates, Done
   and preview-tap keyboard dismissal. Perform the spoken VoiceOver checks.
4. Use Share → Save Image and compare that saved file with the preview,
   including the foil effect and 1080 × 1350 dimensions. Test slow networking.
5. On a real phone, send to Messages, Instagram Stories/feed, Discord and
   Facebook; verify cropping and which targets retain the text. Judge the
   colorful Share button on device.

See the dated verification entries in [`progress.md`](../../progress.md). These
manual gates apply to the feature already merged into main; neither the merge
nor follow-up automated evidence closes them.
