# Product-surface plan: shared glass, scan price, and card detail

Design spec for the scanner chrome, scan receipt, and owned-card detail.
No new persistence tables and no top-level navigation changes.

## Reconciliation note — 2026-09-06

The original statement that these visual slices were independent was wrong.
Visual-language work shares a foundation: S0 is a common dependency, and S6
must follow the stabilized card-detail treatment so Collection and Portfolio do
not grow a third dialect. The implementation decisions are:

- S0 extracts app-scoped glass names and tokens from the scanner surface.
- S1 uses a neutral gradient. Artwork-derived colour is deferred until a later
  cache-boundary decision; it must never be computed from `body`.
- S1 uses iOS 17-compatible linear/radial gradients. `MeshGradient` remains an
  optional iOS 18 enhancement, not part of this implementation.
- S6 is included in the definition of done and is implemented after S1–S5.
- Card detail keeps its instrument-key predicates and the chart's step/gap,
  observation-kind, and degraded-state semantics unchanged.

---

## Slice A — Liquid Glass instead of custom glass

### The seam already exists

S0 is complete. `AppGlass.swift` now owns the shared `AppGlassBackground`
modifier and the app-scoped `appGlass`, `appPillGlass`,
`appGlassOptionButton`, and `appGlassEffectID` surfaces. The fifteen scanner
call sites remain in `ScannerView.swift` and `ScanSessionOverlays.swift`; the
rename was mechanical and the iOS 17 fallback is still in place.

### The deployment-target decision

`glassEffect` is iOS 26; the project targets iOS 17.0. Two options:

1. **Raise the target to 26.** Simplest, and the bundle id is still
   `com.example.TradingCardScanner`, so there is no installed base to strand.
2. **Keep 17 and branch inside `appGlass()`.** `if #available(iOS 26)` uses
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
| Receipt, choice bars, rail, assistance, held-duplicate | `appGlass()` | `.glassEffect(.regular, in: .rect(cornerRadius:))` | One call site |
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

## Slice C — Card detail redesign

The card is the screen, not a row in it. The redesign keeps the scoped
instrument-key predicates, the chart's economic data rules, and all existing
collection actions. It changes hierarchy and presentation only.

### S0 — Promote the house style

Move the shared glass implementation into an app-scoped surface file and rename
`scannerGlass`, `scannerGlassEffectID`, `scannerPillGlass`, and
`scannerOptionButton` to app-scoped names. Scanner call sites remain behaviorally
identical. Keep the iOS 26 branch and the iOS 17 fallback.

### S1 — Hero

Remove the gray artwork tray and make catalog or personal artwork full-bleed at
the top of the scroll surface. Use `.scrollTransition` and `.visualEffect` for
subtle scale/parallax, with no movement when Reduce Motion is enabled. Use a
neutral iOS 17-compatible gradient behind the screen; do not extract artwork
colour during rendering and do not add `MeshGradient` in this slice.

The artwork menu remains attached to the artwork. The old `Card` section header
goes away. Missing-artwork, loading, and personal-artwork behavior do not change.

### S2 — Identity

Replace the separate identity facts with one leading-aligned block containing
name, set, collector number, rarity, print run, and item kind. Finish, treatment,
grading company, and grade appear as compact, accessible badges beside the
identity. No raw enum is the primary label.

### S3 — Price as the hero block

Keep price, source/freshness, range control, chart, and movement together. The
chart remains a step line only across checked days, with visible gaps across
unchecked spans; `.marketUpdate` remains visually distinct from restatement,
transition, and invalidation points. A single observation is a confident point
with its date, not an axis-heavy empty chart. The holding-impact amount appears
once, with the unit-movement explanation secondary.

### S4 — Finish rendering

Upgrade the existing finish overlay with a treatment-aware, motion-driven sheen.
Use the existing `CMMotionManager` pattern, throttle it at the same 30 Hz ceiling,
and stop it when the hero disappears. Surge Foil and Neon Ink get distinct visual
signatures only when the persisted catalog evidence confirms them. Reduce Motion
uses the static fallback; Reduce Transparency uses an opaque surface fallback.

### S5 — Action strip

Replace separate Marketplace, History, and Quantity sections with one quiet
action strip. Marketplace remains a direct exact-printing link; History opens the
existing per-card activity rows; Quantity retains increment/decrement and removal
with the existing confirmation and save behavior. The strip must not draw a
second chevron inside a `NavigationLink`.

### S6 — Propagate

Apply the shared card-detail language to Collection tiles and Portfolio holding /
contribution rows: neutral art treatment, one identity hierarchy, and the same
badge vocabulary. Do this after the detail screen is stable so the shared
components are real reuse rather than a third approximation.

### Accessibility and verification gate

- Dynamic Type must keep the identity and actions readable without clipping.
- VoiceOver receives meaningful grouped labels for the hero, price state, chart,
  and action strip; visual finish is never the only source of finish meaning.
- Reduce Motion removes scroll and sensor-driven visual motion.
- Reduce Transparency replaces translucent surfaces with opaque system colors.
- Verify a rich card and a plain card, one-observation and no-history states,
  light/dark appearance, and an accessibility-size layout in deterministic
  simulator captures.

### Suggested order

`S0 → mockup route/checklist → S1 → S2 → S3 → S4/S5 → S6`

S4 and S5 may be implemented independently after S1, but both must reuse the
same hero/detail surface. S6 is part of the completion gate, not an optional
follow-up.

## Implementation record — 2026-09-06

S0–S6 are implemented. Card detail now uses a full-bleed hero with bounded
scroll parallax, a neutral iOS 17-compatible backdrop, a unified identity
block, shared accessible badges, a price/movement block that preserves the
scoped instrument-key queries and chart semantics, a treatment-aware
motion-bounded finish overlay, and one action strip. Collection tiles and
Portfolio holding/contribution rows reuse the same badge vocabulary. No
artwork-derived colour extraction or `MeshGradient` was added.

The simulator app build succeeds and the full scheme suite passes with 861
tests, 1 skipped, and 0 failures. The deterministic `CardDetail` route
launched successfully, but CoreSimulatorService disconnected before the
screen could be captured; the visual checklist records that capture as
pending rather than treating launch as visual verification.
