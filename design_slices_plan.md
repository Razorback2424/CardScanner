# Three slices: glass, scan price, card detail

Design spec for three changes. No new screens, no navigation changes, no new
tables. Each slice is independently shippable and none depends on another.

---

## Slice A — Liquid Glass instead of custom glass

### The seam already exists

`ScanSessionOverlays.swift` defines `GlassBackground` as a `ViewModifier` behind
one `scannerGlass(cornerRadius:)` extension, used at eleven call sites. **The
material can be replaced in that one file.** Nothing else has to change for the
basic swap. This is the cheapest slice in the document and it deletes code.

### The deployment-target decision

`glassEffect` is iOS 26; the project targets iOS 17.0. Two options:

1. **Raise the target to 26.** Simplest, and the bundle id is still
   `com.example.TradingCardScanner`, so there is no installed base to strand.
2. **Keep 17 and branch inside `scannerGlass()`.** `if #available(iOS 26)` uses
   the real material, else the current black capsule. One branch, one file, no
   call site changes.

Recommend (2) even if you intend (1) later — it makes this slice reversible and
decouples it from every other iOS 26 decision.

### Material choice per element

The hard constraint: **this glass floats over a live camera feed.** Liquid Glass
samples what is behind it, and what is behind it here is a brightly lit white
card that moves. `.clear` will wash out white label text unpredictably as the
card enters and leaves frame.

| Element | Today | Becomes | Why |
|---|---|---|---|
| Purpose pill, Finish Lock (unlocked) | `.black.opacity(0.62)` + hairline | `.glassEffect(.regular, in: .capsule)` | `.regular` carries adaptive dimming; `.clear` does not survive a white card |
| Finish Lock (locked) | solid `Color.red` capsule | `.glassEffect(.regular.tint(.red), in: .capsule)` | Must stay unmissable — a silently applied lock is the thing that most needs to be visible. Tint keeps it loud and joins the material family |
| Settings button | hand-rolled black circle + white stroke | `.buttonStyle(.glass)` | Deletes the custom circle entirely |
| Unresolved chip | `.orange.opacity(0.85)` | `.glassEffect(.regular.tint(.orange), in: .capsule)` | Same reasoning as the lock |
| Receipt, choice bars, rail, assistance, held-duplicate | `scannerGlass()` | `.glassEffect(.regular, in: .rect(cornerRadius:))` | One call site |
| Variant / print-run / identity option buttons | `.white.opacity(0.16)` rects | `.buttonStyle(.glass)` | See constraint below |
| **Scan band** | green stroke + fill on `CALayer` | **unchanged** | It is an alignment guide, not chrome. It must be a crisp stroke against the card, and it lives in the preview layer where glass does not apply |
| **`ScanNoteView` problem tone** | solid orange capsule | **unchanged, or tinted glass only if it stays clearly orange** | A problem note that becomes ambiguous is worse than an unfashionable one |
| Card thumbnails | opaque | **unchanged** | Content, not chrome |

### Two things worth doing while in here

**Group the top bar in a `GlassEffectContainer`.** The purpose pill, the lock
pill and the slow-lookup spinner are adjacent. A container makes them share one
light sample and blend when near each other, which is the difference between
three floating blobs and one control cluster. This is the actual reason the
container type exists.

**Morph the bottom stack with `glassEffectID`.** Today the duplicate bar,
identity bar, print-run bar, variant bar and receipt are mutually exclusive
views that swap with `.move(edge: .bottom) + .opacity`. Given a shared namespace
they morph between one another instead. This adds no motion — it replaces an
existing transition with a better-matched one, so it costs nothing on a path
taken hundreds of times per session.

### One rule that must survive

**No option button may become `.glassProminent`.** `VariantResolver` deliberately
refuses to rank when two or more variants remain possible, and a visually
promoted button is a ranking. All options stay the same weight. The only place
prominence is correct is the duplicate confirmation, where "Same card" is
already the safe no-mutation default and is already tinted.

### Also in scope, same file area

`.toolbar(.hidden, for: .tabBar)` while a scan session is active. The tab bar
currently takes ~100 pt out of the thumb zone directly under the choice bar and
receipt. This is a one-line change and it is the single biggest layout gain in
the slice.

### Accessibility / reliability notes

- Glass respects Reduce Transparency automatically; the current hand-rolled
  capsules do not. This slice **improves** accessibility rather than costing it.
- Verify white label text on the pills against a white card in real light before
  committing. If `.regular` still washes out, add a tint rather than reverting.
- Nothing here touches the acceptance pipeline, the latch, or any state machine.

---

## Slice B — Price on the Collection scan receipt

### The value is already in hand

`CollectionCommitCandidate` computes `price: PriceLookup` at construction, from
the catalog response the identification already made. `ScanReceipt` is built
from that same candidate a few lines later and simply does not carry it. **No
new fetch, no new round trip, no change to the critical path.**

### What to show

Add `price: PriceLookup` to `ScanReceipt`. Two states exist at scan time:

- `.price(NormalizedPrice)` → the amount
- `.unavailable(source)` → **"Price unavailable"**, never blank, never borrowed
  from another finish

The stored-record states (stale, not checked, refresh failed) do not apply here:
a scan price is fresh by construction.

### Layout

Trailing edge of the receipt, right-aligned, the largest text on the card.
Name stays leading and primary. Identifier and variant stay as the caption line.

### Three decisions that matter

**Unit price, not position value.** If the scan incremented an existing position
to ×3, show the price of one copy. This is the collection's own stated rule —
"ten copies of a $2 card is still a $2 card" — and consistency with the grid
matters more than a bigger number.

**No running session total.** A "42 cards · $1,284" figure updating on every
card is a number that changes eight hundred times and rewards watching the
screen, which is the opposite of what the scanner is for. Deliberately omitted.

**Leave the recent rail alone.** At 38 pt, price text would be illegible. The
rail stays purely visual. `ScanReviewSheet` should carry the price, since that
is where a single scan is actually inspected.

### Optional, separable: the tick carries the value

Once the price is on the receipt, `feedback.added()` has it available at the same
moment. A second haptic — firmer, doubled — above a threshold set in Settings
tells you whether to pull the card out of the pile without looking at the phone.

- Threshold is the user's, default around $5.
- **Silent when the price is unavailable.** No price, no claim — the same rule
  the rest of the app follows.
- Nothing is haptic-only: the receipt still shows the number, so this is an
  additional channel rather than a substituted one.
- Cost: one generator in `ScanFeedback`, one `@AppStorage` value, one branch.

Take this or leave it independently of the display change.

---

## Slice C — Card detail overhaul, with a per-card price chart

### C1. The chart, and what the data actually permits

This is the interesting part, and the data model dictates the design.

**`PriceObservation` is a change log, not a time series.** A row is appended only
when the value or its provenance changes; an unchanged price writes nothing, by
explicit design ("appending here would fill the log with thousands of rows a day
that say still $42").

**`PriceCheckDay` is the knowledge record.** One row per instrument per day the
app successfully asked.

Together they permit an honest chart and forbid a dishonest one:

- Between two observations **with check days in between**, the price was known
  and flat → draw a solid step.
- Across a span **with no check days**, the app did not know → **do not draw a
  line there.** A continuous line across an unchecked gap is a claim the app
  cannot support.

So the chart is a **step line with visible gaps**: solid where knowledge exists,
broken where it does not. This is the pricing promise rendered as a shape, and
it falls straight out of tables that already exist. It is also the reason this
chart can be drawn honestly here and essentially nowhere else.

**Observation kind must be respected.** Only `.marketUpdate` is the market
moving. A `.sourceRestatement`, `.sourceTransition` or `.explicitInvalidation`
changes the number for reasons that are not appreciation. Draw the value change
— the price genuinely was that — but **annotate** the point rather than letting
it read as a move. This mirrors what the portfolio already does by separating
`market` from `pricingAdjustments`.

**Degradation, in order of how often it will happen:**

| Situation | What the chart shows |
|---|---|
| No observations for this instrument | "History is being recorded" — the phrase already in use |
| One observation | The single point and its date. No line, no axis pretending to a range |
| Two or more, sparse | Steps and gaps. Correct and slightly ugly, which is the honest outcome |
| Restored to a new device | Say so: this table is local-only by design, so history does not travel. Do not show an empty chart and let it read as "flat" |

**Range control:** reuse `PortfolioHistoryRange` bound to the shared
`PortfolioHistoryStore.range`, exactly as the movement summary already is. No new
vocabulary, no per-screen range state.

**Performance constraint, non-negotiable:** query both tables with a
`#Predicate` on `instrumentKey`. At 428 cards a year of check days is ~156,000
rows; a fetch-all-then-filter in `body` will not survive it. Several existing
views do fetch-all — do not copy that pattern here.

### C2. Chart and price are one block, not two panels

Today "pricing" is one bordered panel and "movement" is another, with no stated
relation. They become a single block:

```
$342.00
JustTCG · current as of Sep 4, 3:20 PM      [1W 1M 3M 1Y ALL]
┌──────────────────────────────────────────┐
│   step chart, gaps where unchecked       │
└──────────────────────────────────────────┘
Market movement · 1M      +$42.00 holding impact   ›
```

The chart is the unit price over time. The movement row underneath is what that
did to *your holding* — unit movement × quantity. Those are genuinely different
quantities and the app already distinguishes them; putting them adjacent makes
the distinction legible instead of leaving it implied across two cards.

### C3. Structure of the rest

Current state: eight `.quaternary.opacity(0.4)` panels stacked in a `ScrollView`
— pricing, movement, finish, treatment, marketplace, history, conflict notice,
stepper, remove. Everything is a card, so nothing is emphasised.

**Recommendation: make this screen a `List` with sections.** This is *less*
custom UI than what is there now. It gets section grouping, separators, Dynamic
Type behaviour and inset styling from the system instead of from eleven repeated
background modifiers, and it matches every other detail screen in iOS.

Order:

1. **The card.** Sized to what it has. The current 460 pt frame is reserved
   whether or not artwork exists — when it does not, the most prominent control
   on a card's own screen is *Choose Photo*. Fix by sizing to content and moving
   the photo picker into a menu on the artwork itself.
2. **Identity** — name, set, number, rarity, print run. Leading-aligned, not
   centred; nothing else in the app centres text.
3. **Price + chart + movement** (C2).
4. **Facts** — finish, treatment, grading company, grade — as one
   `LabeledContent` section. Today finish and treatment are two separate
   full-width bordered panels each containing one row.
5. **Marketplace.**
6. **History.**
7. **Quantity and removal** in a final section. The stepper currently sits
   between the history list and the destructive button with no grouping.

**The one complication:** the existing `ViewThatFits` two-column iPad layout.
A `List` can hold the two-column arrangement in its first section, but this needs
checking at iPad width before the rest is converted. Do it first, not last.

### C4. Finish rendered, not spelled

Where the card is drawn large, draw the finish: holo foils the art window,
reverse holo foils the border, because that is what those cards physically are.
Static — a gradient and a mask, no shader, no motion, no sensor, no
reduced-motion branch. It carries the information the teal capsule with a
recycling arrow currently carries in words.

Only where the catalog confirmed the printing exists in that finish. Drawn
difference is a claim and answers to the same accuracy policy as the rest.

---

## Suggested order

| | Slice | Why here |
|---|---|---|
| 1 | **A — glass** | One file, deletes code, reversible, improves Reduce Transparency behaviour. Lowest risk, immediate visible payoff |
| 2 | **B — scan price** | Small, self-contained, no new data. Take the haptic or not |
| 3 | **C1 — the chart** | The real work. Build the derivation and its four degraded states before touching layout |
| 4 | **C2–C4 — the screen** | Restructure once the chart exists, so the layout is designed around real content rather than a placeholder |

Nothing in A or B blocks C. C1 should land before C2 so the price/chart block is
laid out around a chart that actually renders sparse real data.
