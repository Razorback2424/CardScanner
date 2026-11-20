# Fixing a wrong scan

**Status — 2026-11-20 (`main@146161c` source review):** Steps 0–4 below
are implemented, with the recorded simulator tests and source checks. Step 5
(real-phone timing, interactions and accessibility acceptance) remains open;
the sheet's entry-point taps and save flows were not exercised on screen in
the recorded simulator pass. The "Today" table and original review findings
below describe the **pre-implementation** baseline at `90554874`, not the
current app. No physical-device timing has been measured.

## The goal

When the scanner picks the wrong card, the person fixes it in a few taps
without leaving the scanner and without losing anything. Version 1 does one
thing well: **swap a scanned card for the right one.** Everything else waits
until that feels great on a real phone.

Targets:

1. **Trust:** a swap never loses the date added or the card's history, never
   shows up as a sale in portfolio history, and is easy to reverse.
2. **Speed:** the sheet opens with likely matches already showing. When the
   right card has one finish, fixing the last scan takes three taps from the
   receipt: open the review sheet, **Not this card?**, the right row. A finish
   choice adds one tap.
3. **Joy:** the receipt and the thumbnail change in place to the right card,
   and scanning carries on.

## Today

| Situation | What exists | Gap |
| --- | --- | --- |
| Right card, wrong finish | [ScanReviewSheet](../../TradingCardScanner/Views/ScanReviewSheet.swift) changes the finish through `ScannerViewModel.correct(scanID:to:)` and `CollectionStore.recordVariantCorrection(...)`, which moves the copy and records a two-leg correction in the ledger. | Works for finish only. It refuses a change where the finish stays the same, checks the finish against the *old* printing, and does not refresh the receipt. |
| Wrong card, auto-added | Receipt **Undo** and the review sheet's **Undo Scan** call `undoScan`, which removes the card, including after a finish correction. | There is no way to pick a different card. Undo's accessibility hint promises it "lets you correct its scan details," but the card is just gone. |
| Scan failed ("Needs attention") | [UnresolvedScanDetailView](../../TradingCardScanner/Views/UnresolvedScanDetailView.swift) **Search catalog** opens the full `BrowseView`, then a detail page, then **Use This Card**. | Search opens empty even though the scanner read a number and title. About six steps. |

## Decisions from the code review

These came out of checking the first draft against the code. Each one changes
what gets built.

1. **A swap compares identity, not finish.** The usual wrong scan keeps the
   same finish (Normal Pikachu → Normal Raichu). The existing correction
   returns early when the finish is unchanged
   ([CollectionStore.swift (reviewed line 6289)](../../TradingCardScanner/Services/CollectionStore.swift),
   [ScannerViewModel.swift (reviewed line 3981)](../../TradingCardScanner/Views/ScannerViewModel.swift)),
   so the swap must not reuse that guard. A swap is a no-op only when printing,
   finish, Pokémon print run, and Magic treatments all match.
2. **The new card is checked as a new card.** The existing finish check runs
   against the old row's printing
   ([CollectionStore.swift (reviewed line 2333)](../../TradingCardScanner/Services/CollectionStore.swift)).
   The swap checks the finish against the *new* printing and runs the same
   acquisition checks a scan of that card would pass.
3. **Undo always means "remove this card."** That is what receipt Undo and
   **Undo Scan** do today, including after a finish correction. Swapping back
   is done through the sheet: the card it replaced is always the first
   **Likely match**, so reversing a swap is one tap through the same safe write.
   This keeps one meaning for Undo and avoids a second identity write that would
   have to rebuild a deleted row, its artwork overrides, and its price.
4. **The sheet has two save paths, named separately.** From the review sheet it
   *replaces* a card already in the collection. From Needs attention there is
   nothing to replace, so it *adds* the card and resolves the unresolved record.
   One sheet, two saves, two failure messages.
5. **Search by number is per game.** What each game's search accepts is
   recorded under [Step 0 results](#step-0-results). The scanner's own display
   text is not always searchable, so the sheet builds its pre-fill per game
   rather than reusing it.
6. **Likely matches come from what the scan already keeps.** An auto-added
   scan resolved to exactly one card (`CatalogLookupOutcome.resolved`), so
   there are no "other candidates" to store. Only a scan where the collector
   picked a printing had alternatives. The sheet builds Likely matches from
   the scan's own identifier and title readings, which `RecentScan.subject`
   already holds. (Checked 2026-11-20 while building step 1.)

## Version 1

### Two entry points

- **`ScanReviewSheet`:** a **Not this card?** row under the card name. People
  already reach this sheet by tapping the receipt or a recent-scan thumbnail.
  This entry *replaces* the card.
- **Needs attention:** **Search catalog** opens the same sheet instead of
  `BrowseView`. This entry *adds* the card.

No hidden gestures, and no new controls on the receipt.

### The Fix match sheet (`CardCorrectionPicker`)

- Half-height on iPhone. The keyboard starts **down** so Likely matches are
  visible; tapping the field brings it up.
- **Replacing a card:** the field starts empty, with the placeholder "Name or
  number". The scanner's number already led to the wrong card, so searching it
  again mostly shows that same card; Likely matches cover the other sets.
- **Needs attention:** the field is pre-filled with what the scanner read, in
  the form that game's search accepts (see [Step 0 results](#step-0-results)).
  Focusing the field selects the text, so typing replaces it.
- It is scoped to the scanned game.
- **Likely matches** at the top, in this order:
  1. When replacing, the card currently saved, marked **Current**, so a swap
     can be reversed in one tap.
  2. The same number in other sets, from the scan's identifier (for
     Yu-Gi-Oh, the same name in other sets).
  3. Name matches for the scan's title readings, where it has them.
- **Results** for the typed query below that.
- Each row shows artwork, name, and set and number. Tapping it saves. If the
  printing has more than one physical choice (finish, Pokémon print run, or
  Magic treatment), the row first expands into chips, with the current choice
  preselected when it still applies.
- If the chosen card is already owned, the row says so ("You have 1"), so the
  merge isn't a surprise.
- No detail page, set rails, filters, prices, or sealed products.
- While an online search runs (Magic, or any game without an installed
  catalog), the sheet says it is searching online; offline it says search needs
  a connection and Likely matches still work.

### The swap (`CollectionStore.replaceIdentity`)

- One write, built next to `recordVariantCorrection` and sharing its ledger and
  activity pattern, but with its own guards (decisions 1 and 2). It moves the
  copy to the new card and keeps the scan's activity and date added. History
  shows a correction, not a removal plus an addition.
- The ledger records one correction operation with two legs, the same as a
  finish correction, appended to the scan's `ledgerOperationIDs`. Portfolio
  history shows no sale.
- If the new card is already owned, the copy joins that row. The receipt says
  "Now 2 ×" so the merge is visible.
- Artwork overrides are re-keyed the same way a finish correction does it.
- Price comes from the new card. A card picked from search results has no
  price in hand, so the receipt shows the new card with the price pending and
  fills it in when the lookup finishes, the same as a fresh scan.
- It keeps the same `RecentScan.id`, so the thumbnail updates in place, and it
  refreshes the receipt if that receipt is still showing this scan. A swap made
  from an older thumbnail shows a short "Changed to …" receipt rather than
  editing one that has already gone.
- On failure, the original card stays and the sheet says "Couldn't change
  card." Nothing is half-written.
- Read the [Services guide](../../TradingCardScanner/Services/AGENTS.md) and
  the [Models guide](../../TradingCardScanner/Models/AGENTS.md) first. This
  changes persisted identity.

### The add (Needs attention)

- Already built: the sheet hands its pick to
  `ScannerViewModel.resolveUnresolved(id:choice: .catalog(...))`, the path
  Browse's **Use This Card** uses today. It saves through the same write as a
  successful scan, keeps the original scan evidence, and removes the record
  only after the save succeeds, so the record never disappears without the
  card being saved. (If the app quits between the save and the removal, the
  record can outlive the save; that is true of every scan today.)
- On failure, the record stays in Needs attention with the pick kept for
  **Retry save**, and the row says "Couldn't add card. Tap Retry save to try
  again." Before step 2 the only message was a scanner note behind the
  Needs attention screen.

### Left out of version 1, on purpose

| Left out | Why | Meanwhile |
| --- | --- | --- |
| Graded slabs | The cert, label, and graded quote make the swap much harder to get right. | **Not this card?** is hidden for slabs. Remove and rescan. |
| Changing cards outside the scanning session | The collection screen adds a "one copy or all of them?" question people don't need while scanning. `RecentScan` lives only for the session, so once the person leaves the scanner the fix is remove and re-add. | Remove and re-add, as today. |
| Switching to a different game | Each game's write rules would need checking. | The sheet stays in the scanned game. |
| Offline Magic search | It may need catalog changes. | Magic searches online, and the sheet says so. Likely matches still work offline. |
| A separate "revert swap" Undo | It is a second identity write for something one tap in the sheet already does (decision 3). | Pick **Current** in the sheet. |
| Remembering past choices and correction metrics | Learning that guesses wrong would quietly mislabel cards. It needs its own review. | Nothing. Revisit once version 1 has real use. |

## Plan

- [x] **Step 0, search by number:** done 2026-11-20; see
      [Step 0 results](#step-0-results).
- [x] **Step 1, the swap:** done 2026-11-20 (simulator only).
      `CollectionStore.replaceIdentity` shares one move-the-copy helper with
      the scanner finish correction; `ScannerCollectionWriter.replace` runs the
      same catalog-pick admission as a Browse addition (now a shared
      `validateCatalogSelection`) and stages the new card's price in the same
      save; `ScannerViewModel.replace(scanID:with:variant:pokemonPrintRun:)`
      updates the scan, rail and receipt in place. A swapped scan shows the
      saved card's set and number, not the scanner's reading. Tested:
      - [x] a swap with the **same finish** moves the copy as a correction:
        acquisition kept, no disposal, ledger nets to the new card
      - [x] picking the saved card again changes nothing
      - [x] the finish is checked against the new printing (Yu-Gi-Oh: a 1st
        Edition copy can't move to an Unlimited-only printing; nothing written)
      - [x] slabs are refused
      - [x] joining an owned card, then **Undo** removes only the swapped copy
      - [x] swap, then swap back; the ledger nets to the original card, and
        Undo removes it with no disposal
      - [x] the source was removed elsewhere: nil, nothing written
      - [x] a save failure leaves the scan as it was
      - [x] view model: swap in place, receipt updated, Undo still removes
      - [ ] **not tested:** artwork overrides moving with the copy (same code
        path as a finish correction), and a writer-level admission rejection
        (shared with Browse additions, which have their own tests)
- [x] **Step 2, the add:** done 2026-11-20 (simulator only). The save
      already existed (see [The add](#the-add-needs-attention)); step 2 made
      a failed save say so on the Needs attention row and clears that message
      when a new attempt starts or the record is resolved. Tested:
      - [x] success, every Browse game, raw and slab: the card is saved with
        the original evidence and the record is gone (existing test)
      - [x] failure keeps the record and its pick, writes nothing (existing)
      - [x] failure shows "Couldn't add card" on the row; **Retry save**
        clears it before trying again (new)
- [x] **Step 3, the sheet:** done 2026-11-20 (simulator only; not yet
      reachable from the app, which is step 4).
      [CardCorrectionPicker](../../TradingCardScanner/Views/CardCorrectionPicker.swift)
      searches the shared Browse catalog. Each game's recognition adapter now
      says what to type for a scan (`catalogSearchText(for:)`, per
      [Step 0 results](#step-0-results)); Magic and the unchecked Pokémon
      forms return nothing and fall back to the title. Likely matches run the
      number search and then the title readings, six results each, eight in
      all, without the current card. When that finds nothing while replacing,
      they search the saved card's name instead; that is how Yu-Gi-Oh finds
      reprints, with no game branch in the sheet. Results don't repeat
      Likely matches. A row with one finish saves on tap; one with several
      opens chips, with the current finish highlighted. "You have N" counts
      every copy of that printing, of any finish. Debug fixture:
      `-ui_debug_route CardCorrection -ui_debug_state replace|add|fail`, with
      `-large` for accessibility text, over the app's real catalog.
      Differences from the plan above:
      - The sheet doesn't announce "searching online" for Magic; it says
        "Searching…" for every game, and when a search fails offline it says
        "Search needs a connection. Likely matches still work." That avoids a
        game branch and covers any game whose search is online.
      - In the add path the chips are optional: with no finish picked, the
        scanner's own finish question asks, as Browse's **Use This Card**
        does today.
      Tested: the request builder (pre-fill, Likely queries, title fallback);
      each game's search text; installed Pokémon search finding the cards
      from a Trainer Gallery and a modern reading; the **Current** lookup
      and its finish choices. Simulator screenshots: replace and add in
      light mode, replace in dark mode and at accessibility text size. Not
      checked: tapping a row, the chips, the failure message and the "You
      have N" badge on screen (this session couldn't tap in the simulator);
      Magic, Lorcana, One Piece and Yu-Gi-Oh on screen. Trainer Gallery rows
      show placeholder art in the fixture, which comes from the catalog's
      artwork, not the sheet.
- [x] **Step 4, wire it up:** done 2026-11-20 (simulator only).
      - `ScanReviewSheet` has **Not this card?** under the card's details,
        hidden for slabs and for a scan no longer in the session. A swap
        saves through `ScannerViewModel.replace`, then closes both sheets;
        the receipt and thumbnail already show the new card (step 1). A
        failed swap says "Couldn't change card. Try again." on the row.
      - Needs attention's **Search catalog** opens the sheet in add mode
        instead of `BrowseView`. The pick goes through the same `.catalog`
        resolution as before, after the sheet closes; a failed save shows on
        the record (step 2). For a graded record the sheet offers no finish
        chips, and a card with one finish is left for the scanner to settle,
        matching what Browse passed before.
      - Receipt **Undo**'s hint now says it removes the card and that
        **Not this card** is how to swap it.
      - `BrowseView`'s `recoveryGame` parameter has no caller now; left in
        place.
      Tested: requests built from a saved scan and from Needs attention
      records (slab and raw). Not checked on screen: opening the sheet from
      either place and saving, because this session couldn't tap in the
      simulator.
- [ ] **Step 5, polish on a real phone:** time it from opening the sheet to
      the first results, count taps, and check each game at default and
      accessibility text sizes on iPhone and iPad. Fix what feels slow before
      calling it done.

### Step 0 results

Checked 2026-11-20 at `90554874`. Pokémon was measured with a throwaway test
(since removed) that searched the bundled checklists across every set, in the
simulator; it made no network requests. The other games are from reading their
search code plus the existing tests named below. None of this is device
evidence.

| Game | Scanner reads | Search accepts | Pre-fill for Needs attention |
| --- | --- | --- | --- |
| Pokémon, set number | `SVI 25/198` for sets that print a code (Scarlet & Violet on); `25/195` for older sets | `25/195` finds the one card across all sets, and a printed code narrows it (`SUM 163/149`). Every set that prints a code stores the same code in the checklist. A bare `25` returns 60+ results. | `25/195`, no set code |
| Pokémon, subset (TG, GG, RC) | `TG05/TG30` | `TG05/TG30` and `TG05` both find the four Trainer Gallery cards with that number (fixed 2026-11-20; the printed form used to find nothing). | `TG05/TG30` |
| Pokémon, promos, energy, older cards | various | Not checked. | Title, until checked |
| Pokémon, name + number | — | `Gardevoir TG05` finds the two Gardevoir TG05 cards (fixed 2026-11-20; it used to find nothing). | — |
| Magic | `MH3 123 EN` | Name only (Scryfall `name:` query, online). | Title |
| Lorcana | `5/204 EN 1` | `5/204`, alone or with a name (`LorcanaDiscoveryCatalogTests`). | `5/204` |
| One Piece | `OP01-001` | The printed number, alone or with a name, across all sets (`OnePieceIntegrationTests`). | `OP01-001` |
| Yu-Gi-Oh | `LOB-EN001` | The printed code across all sets (`YuGiOhIntegrationTests`). | `LOB-EN001` |

Effects on the plan:

- In Yu-Gi-Oh a reprint has a different code, so "same number in other sets"
  finds nothing there. For Yu-Gi-Oh, Likely matches use the same card name in
  other sets instead.
- Browse search shares this search, so the 2026-11-20 fix for printed subset
  numbers and name plus number applies there too. Tested in
  `PokemonChecklistBrowseTests`.

**Done when:** on a physical phone, fixing a wrong auto-add takes three taps
(four with a finish choice) plus any typing, results feel instant on installed
catalogs, portfolio history shows no sale for a swapped card, picking
**Current** reverses a swap, and Undo removes the card.

**Verification:** `xcodebuild` with the `TradingCardScanner-ProfileLocal`
scheme and `-only-testing` for `CollectionStore`, `ScannerViewModel`,
`InventoryLedger`, portfolio replay, unresolved scans, and the picker tests;
simulator screenshots for layout; and a physical device for the speed targets.
