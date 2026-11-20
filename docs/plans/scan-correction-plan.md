# Fixing a wrong scan

**Status:** proposed 2026-11-19, cut down 2026-11-20. Nothing below is built
yet. The "Today" section was checked against `main` at `4e3b7bb0`. No device
timing has been measured.

## The goal

When the scanner picks the wrong card, the person fixes it in a few taps
without leaving the scanner and without losing anything. Version 1 does one
thing well: **swap a scanned card for the right one.** Everything else waits
until that feels great on a real phone.

Targets:

1. **Trust:** a swap never loses the date or price paid, never shows up as a
   sale in portfolio history, and can be undone.
2. **Speed:** the sheet opens with likely matches already showing. Fixing the
   last scan takes three taps or fewer from the receipt.
3. **Joy:** the receipt changes in place to the right card, and scanning
   carries on.

## Today

| Situation | What exists | Gap |
| --- | --- | --- |
| Right card, wrong finish | [ScanReviewSheet](../../TradingCardScanner/Views/ScanReviewSheet.swift) changes the finish through `ScannerViewModel.correct(scanID:to:)` and `CollectionStore.correct(...)`, which rewrites in place. | Works. This is the model for a card swap. |
| Wrong card, auto-added | Receipt **Undo** calls `undoScan`, which deletes the card. | There is no way to pick a different card. Undo's accessibility hint promises it "lets you correct its scan details," but the card is just gone. |
| Scan failed ("Needs attention") | [UnresolvedScanDetailView](../../TradingCardScanner/Views/UnresolvedScanDetailView.swift) **Search catalog** opens the full `BrowseView`, then a detail page, then **Use This Card**. | Search opens empty even though the scanner read a number and title. About six steps. |

## Version 1

### Two entry points

- **`ScanReviewSheet`:** a **Not this card?** row under the card name. People
  already reach this sheet by tapping the receipt or a recent-scan thumbnail.
- **Needs attention:** **Search catalog** opens the same sheet instead of
  `BrowseView`.

No hidden gestures, and no new controls on the receipt.

### The Fix match sheet (`CardCorrectionPicker`)

- Half-height on iPhone, with the search field focused and the keyboard up.
- The field is pre-filled with what the scanner read: the printed number if it
  read one, otherwise the best title reading. The text is selected, so typing
  replaces it.
- It is scoped to the scanned game.
- **Likely matches** at the top: the scanner's other candidates, the same
  number in other sets, and the existing `printingCandidates`.
- **Results** for the typed query below that, from `BrowseCatalog.searchCards`.
- Each row shows artwork, name, and set and number. Tapping it saves the swap.
  If the printing has more than one finish, the row first expands into finish
  chips, with the current finish preselected when there is one.
- No detail page, set rails, filters, prices, or sealed products.

### The swap (`CollectionStore.replaceIdentity`)

- One write, built next to the existing `correct(...)` and following its
  pattern. It moves the copy to the new card and keeps the activity, the date
  added, and the price paid. The market price comes from the new card.
- The ledger records a correction, not a sale plus a purchase. It reuses the
  `previousLedgerOperationIDs` pattern.
- If the new card is already owned, the copy joins that row. The receipt says
  "Now 2 ×" so the merge is visible.
- Undo on the receipt after a swap reverts the swap. It does not delete the
  card.
- It keeps the same `RecentScan.id`, so the thumbnail updates in place.
- On failure, the original card stays and the sheet says "Couldn't change
  card." Nothing is half-written.
- Read the [Services guide](../../TradingCardScanner/Services/AGENTS.md) and
  the [Models guide](../../TradingCardScanner/Models/AGENTS.md) first. This
  changes persisted identity.

### Left out of version 1, on purpose

| Left out | Why | Meanwhile |
| --- | --- | --- |
| Graded slabs | The cert, label, and graded quote make the swap much harder to get right. | **Not this card?** is hidden for slabs. Remove and rescan. |
| Changing cards from the collection screen | The one-copy-or-all question adds a decision people don't need while scanning. | Remove and re-add, as today. |
| Switching to a different game | Each game's write rules would need checking. | The sheet stays in the scanned game. |
| Offline Magic search | It may need catalog changes. | Magic searches online, and the sheet says so while it searches. Likely matches still work offline. |
| Remembering past choices and correction metrics | Learning that guesses wrong would quietly mislabel cards. It needs its own review. | Nothing. Revisit once version 1 has real use. |

## Plan

- [ ] **Step 1, the swap:** add `CollectionStore.replaceIdentity` and
      `ScannerViewModel.replace(scanID:with:variant:)`, with tests for
      quantity, joining an existing row, the ledger, portfolio replay, Undo,
      and failure.
- [ ] **Step 2, the sheet:** add `CardCorrectionPicker` with pre-fill, Likely
      matches, search, and finish chips, plus UI fixtures in the style of the
      existing `PrintingChoice` fixtures.
- [ ] **Step 3, wire it up:** add **Not this card?** to `ScanReviewSheet`,
      point Needs attention's **Search catalog** at the sheet, have receipt
      Undo revert a swap, and fix the Undo accessibility hint.
- [ ] **Step 4, polish on a real phone:** time it from opening the sheet to
      the first results, count taps, and check each game at default and
      accessibility text sizes on iPhone and iPad. Fix what feels slow before
      calling it done.

**Done when:** on a physical phone, fixing a wrong auto-add takes three taps
or fewer plus any typing, results feel instant on installed catalogs,
portfolio history shows no sale for a swapped card, and Undo brings back the
original.

**Verification:** `xcodebuild` with the `TradingCardScanner-ProfileLocal`
scheme and `-only-testing` for `CollectionStore`, `ScannerViewModel`,
`InventoryLedger`, portfolio replay, and the picker tests; simulator
screenshots for layout; and a physical device for the speed targets.
