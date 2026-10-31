# Card sharing — implementation hand-off

**Status:** implemented, **not built or tested** — 2026-10-31, branch
`claude/card-share-sheet` from `main` at `36c2a64`.

The code was written in a Linux session without Xcode; downloading a Swift
toolchain was blocked by that session's network policy. Nothing below has been
compiled, run, or seen on a simulator or device. This document is the checklist
for finishing it on a Mac.

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

Most likely compile issues:

| Location | Risk | Fix |
|---|---|---|
| `CardShareViews.swift` `CardShareButton` | `ShareLink(item:message:preview:)` without `subject:` | Add `subject: nil`, or share `[image]` and send the text separately |
| `CardShareContent.swift` `positionText` | `switch` expression assigned to a labelled tuple | Use a plain `switch` returning two strings |
| `CardShareArtworkLoader.load` | `UIImage` returned from `Task.detached` | Mirrors `ArtworkAccentStore`; otherwise load on the main actor |
| `ShareBadge`, `ShareTrendChart` bodies | `let` inside view builders | Move to computed properties |
| Any `nilIfEmpty` ambiguity | File-private helper also exists in `CollectionItemKind.swift` | Rename the share helper |

- [ ] Debug build passes
- [ ] Release build passes

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

- [ ] `CardShareContentTests` 17/17
- [ ] Full suite has no new failures (two existing screens changed; start with `DetailDeletionRenderTests`)

## 3. Simulator checks

Collection share (card detail → share icon left of the "…" menu):

- [ ] Holo, Reverse or Foil raw card: still sheen on catalog art; finish badge; `087` bright, `/165` dim
- [ ] Normal or Nonfoil card: no badge, no sheen
- [ ] Graded card: grade pill (e.g. PSA 10), "PSA 10 market", JustTCG in the footer
- [ ] Sealed product: no number or set-code chip; "Market price"
- [ ] Card with the user's own photo: photo used, no sheen, correct aspect
- [ ] Card with no price: Price switch disabled with "No market price available yet"
- [ ] Price choice persists across sheets; with price off the footer shows only the mark
- [ ] Share reads "Preparing…" until artwork loads; saved image is 1080 × 1350 and matches the preview; text arrives in Messages

Buy check (Price Check result → share icon, top leading):

- [ ] Raw card with history: trend headline, position text when near an extreme, chart with today's dot, start/end dates
- [ ] Too little history: no chart or trend; larger thumbnail
- [ ] Graded check: no chart
- [ ] No usable price: share icon disabled
- [ ] Asking price: decimal pad, keyboard Done and tapping the preview dismiss it; under (mint), over (pink), at market; dashed "Asking $X" line, still visible when the ask is below the 3-month low
- [ ] German region: `55,00` parses

Both sheets:

- [ ] Long card and set names wrap, shrink or truncate without hiding the number or badge
- [ ] Sheets stay dark with the system in light mode
- [ ] iPhone SE: preview shrinks; controls and Share stay visible
- [ ] iPad sheet sizing
- [ ] Larger Dynamic Type sizes in the control rows
- [ ] VoiceOver: "Share card", "Share price check", "Image to share" with the summary, "Asking price"

## 4. Rendering questions

- [ ] The sheen's soft-light and overlay blend modes survive `ImageRenderer`; if the export differs from the preview, replace them with low-opacity white gradients
- [ ] No placeholder image is shared on a slow network
- [ ] Chart end dot is not clipped

## 5. Device checks

- [ ] Share to Messages, Instagram (Stories and feed), Discord and Facebook: no cropping; note where the text is dropped
- [ ] Image sharpness on device
- [ ] Owner judgment: is the foil-gradient Share button too loud beside the preview?

## Not implemented

- Share from catalog card detail and sealed-product browsing. Both would reuse
  `BuyCheckShareSheet` with a `CardSharePrice` and a
  `CardMarketHistoryRequest` from those screens. Sealed items already in the
  collection are covered by the collection share.
- UI tests or screenshot fixtures for the sheets.

## When verified

Update the 2026-10-31 card-sharing entry in [`progress.md`](../../progress.md)
with the build and test results, update this document's status line, then open
a pull request from `claude/card-share-sheet`.
