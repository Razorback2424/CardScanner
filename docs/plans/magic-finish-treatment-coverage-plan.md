# Magic finish/treatment coverage — full automatic vocabulary, narrow lock menu

## Context

The scanner's Finish Lock menu offers only **Nonfoil / Foil / Etched Foil** for Magic. That list is
not a bug in itself: `PhysicalVariant` for Magic is Scryfall's `finishes` vocabulary verbatim
([CardVariant.swift:238-243](TradingCardScanner/Models/CardVariant.swift:238)), and Scryfall publishes exactly those three values. Surge Foil is deliberately modelled on a **second axis**,
`MagicTreatment` ([MagicTreatment.swift:15](TradingCardScanner/Models/MagicTreatment.swift:15)),
because a card is simultaneously `foil` (how the stock is finished) and `surgefoil` (what the printed face carries).

The real defect is one level down. `MagicTreatmentCatalog.treatments(for:)`
([MagicTreatmentCatalog.swift:206-227](TradingCardScanner/Services/MagicTreatmentCatalog.swift:206))
recognises a **closed allowlist of exactly two signals** — `surgefoil` and `neonink`. Every other treatment Scryfall publishes is discarded at the source: it does not even survive as
`.unclassified`. The same two-value list is duplicated in
[generate_magic_treatment_catalog.sh:24](scripts/generate_magic_treatment_catalog.sh:24).

Measured against the committed audit snapshot (`TradingCardScanner/MagicTreatmentSnapshot`, 41,142 audited cards, 738 sets), the cost is concrete:

| signal | cards | dual-finish | sets |
|---|---|---|---|
| surgefoil ✅ modelled | 2,509 | 693 | 22 |
| **silverfoil** | 369 | **369 (100%)** | 2 |
| **galaxyfoil** | 376 | 10 | 4 |
| **ripplefoil** | 352 | 312 | 3 |
| **serialized** | 299 | 0 | 20 |
| **doublerainbow** | 289 | 0 | 16 |
| **rainbowfoil** | 193 | 50 | 3 |
| **halofoil** | 159 | 0 | 5 |
| **firstplacefoil** | 137 | 0 | 2 |
| Other modeled signals (textured, stepandcompleat, raisedfoil, fracturefoil, manafoil, gilded, confettifoil, oilslick, invisibleink, embossed, thick, plastic, metal, glossy, …) | | | |
| neonink ✅ modelled | 28 | 0 | 6 |

The "dual-finish" column is where it actually hurts. **1,440 remaining printings** carry a treatment *and* publish more than one finish, so the scanner puts a choice bar in front of the user
([VariantChoiceBar](TradingCardScanner/Views/ScanSessionOverlays.swift:288)) whose buttons read
`Nonfoil` / `Foil` — when the truthful answer is `Nonfoil` / `Silver Foil`. Every Lord of the Rings silver-foil card is in this bucket. The user is being asked to press a button that does not describe the card in their hand, and the row that lands in the portfolio is a bare "Foil" with no treatment in its price key.

**Intended outcome, per the user's direction:**

1. The **lock menu stays short** — Magic gets Nonfoil / Foil / Etched Foil plus **Surge Foil** and
   **Neon Ink** only. No 31-item picker.
2. The **scanner resolves everything else automatically** from the Scryfall lookup, across the full treatment vocabulary (foil surfaces + serialized + alt stock), so a user is never asked to select an option that misdescribes their card.

---

## Design

### The vocabulary (31 signals, all attested in the snapshot — none speculative)

**Foil-surface treatments (26)** — `requiredFinishes = [.foil]` unless noted:
`surgefoil`, `galaxyfoil`, `silverfoil`, `ripplefoil`, `rainbowfoil`, `halofoil`, `doublerainbow`,
`firstplacefoil`, `textured`, `stepandcompleat`, `raisedfoil`, `fracturefoil`, `manafoil`, `gilded`,
`confettifoil`, `oilslick`, `invisibleink`, `embossed`, `neonink`,
`chocobotrackfoil`, `dazzlefoil`, `dragonscalefoil`, `facetfoil`, `cosmicfoil`, `singularityfoil`,
`gleaminggold`.

**Open-finish signals (5)** — `requiredFinishes = []` (no finish relationship; applies to any finish):
`serialized`, `thick`, `plastic`, `metal`, `glossy`.

**Art/frame signals deliberately excluded:** `magnified` and `doubleexposure` describe
borderless/showcase artwork rather than a foil surface. Their collector-number identities already
distinguish the printings, so modeling them as treatments would split price identity across both
finishes. They join `boosterfun`, `showcase`, `extendedart`, `borderless`, `fullart`,
`universesbeyond`, `prerelease`, `datestamped`, `promopack`, and the other product/provenance labels
below.

**Deliberately still excluded** (unchanged from today's documented rationale at
[MagicTreatmentCatalog.swift:210-214](TradingCardScanner/Services/MagicTreatmentCatalog.swift:210)):
`boosterfun`, `showcase`, `extendedart`, `borderless`, `fullart`, `universesbeyond`, `prerelease`,
`datestamped`, `promopack`, and the other ~82 product/provenance labels. These are printing identity
or product origin, already answered by the Scryfall id + collector number, and folding them in would split ordinary printings' price identities.

### One model change: `requiredFinish` → `requiredFinishes`

`ripplefoil` appears on `etched` stock (m3c 148–151), which today's single-value
`requiredFinish: PhysicalVariant?` cannot express. Widen it to `requiredFinishes: Set<PhysicalVariant>`
(empty = no known relationship, preserving today's `.unclassified` behaviour) and update the three consumers: `applicableTreatments(for:)`, `impliesFinish(_:)`
([MagicTreatment.swift:141-158](TradingCardScanner/Models/MagicTreatment.swift:141)) and
`MagicTreatmentCatalog.diagnostics(for:)`.

### Single source of truth for the allowlist

Replace the two hardcoded `{"surgefoil","neonink"}` lists with one derived list:
add `static let modelled: [MagicTreatment]` to `MagicTreatment`, have
`MagicTreatmentCatalog.treatments(for:)` match against `Set(MagicTreatment.modelled.map(\.providerSignal))`, and have the generator script read the vocabulary from a single committed JSON
(`TradingCardScanner/MagicTreatmentCatalog/vocabulary.json`) that the Swift enum is unit-tested against.
This kills the existing drift risk between the script and the app.

### Truthful choice-bar labels — reuse, don't build

`PendingVariantChoice` already carries the `IdentifiedCard`
([ScannerViewModel.swift:571](TradingCardScanner/Views/ScannerViewModel.swift:571)), and
`IdentifiedCard.finishAndTreatmentDisplayLabel(for:)` already exists and already does exactly the right finish-aware filtering
([TCGdexCard.swift:851-863](TradingCardScanner/Models/TCGdexCard.swift:851)). The choice bar just
needs to call it instead of reading `option.label` directly. No new model type, no change to
`VariantOutcome`.

---

## Requirements and completion gates

Each gate is a command or an assertion that passes or fails. No judgment calls.

### R1 — Treatment vocabulary widened to 31 modelled cases
Edit [MagicTreatment.swift](TradingCardScanner/Models/MagicTreatment.swift): add 29 cases, extend
`id`, `providerSignal`, `label`, `requiredFinishes`, `init?(id:)`, `encode(to:)`, add `modelled`.

**Gate:** a test asserts `MagicTreatment.modelled.count == 31`; that every element round-trips
`MagicTreatment(id: $0.id) == $0`; that `Set(modelled.map(\.id)).count == 31`; and that
`modelled.map(\.providerSignal)` equals the committed `vocabulary.json` list exactly.

### R2 — `requiredFinishes` replaces `requiredFinish`
**Gate:** `MagicTreatment.ripplefoil.requiredFinishes == [.foil, .etched]`;
`.serialized.requiredFinishes.isEmpty == true`; `.surgeFoil.requiredFinishes == [.foil]`.
Existing tests `testDualFinishTreatmentFollowsTheSelectedFinish`
([MagicTreatmentTests.swift:180](TradingCardScannerTests/MagicTreatmentTests.swift:180)) and
`testKnownTreatmentSuppressesItsImpliedFinish` (`:207`) pass unmodified in behaviour.

### R3 — Allowlist has exactly one source of truth
**Gate:** `grep -c '"surgefoil"' scripts/generate_magic_treatment_catalog.sh` returns `0`; a test
asserts the decoded `vocabulary.json` signal set `==` `Set(MagicTreatment.modelled.map(\.providerSignal))`.

### R4 — Bundled catalog regenerated
Run `scripts/generate_magic_treatment_catalog.sh` against the committed snapshot (offline; no
network). Bump `MagicTreatmentSnapshotVersion.auditRules` 1 → 2
([MagicTreatmentSnapshot.swift:8](TradingCardScannerTests/MagicTreatmentSnapshot.swift:8))
since the audit rules changed, and regenerate so `sourceAuditRulesVersion` matches.

**Gate:** `TradingCardScanner/MagicTreatmentCatalog/manifest.json` contains **exactly 5,150 entries**
(up from 2,537); 4,822 entries have 1 treatment, 327 have 2, 1 has 3; all 31 vocabulary signals appear
at least once; the 4 NEO Neon Ink qualifier rows survive with their colors. Update the hardcoded
count in `testBundledCatalogIsCompactAndContainsAuditedTreatmentCoverage`
([MagicTreatmentTests.swift:1103](TradingCardScannerTests/MagicTreatmentTests.swift:1103)) from
`2_537` to `5_150`.

### R5 — Lock menu gains Surge Foil and Neon Ink, and nothing else
The lock is currently typed `PhysicalVariant`
([ScannerViewModel.swift:923](TradingCardScanner/Views/ScannerViewModel.swift:923),
[FinishLockControl](TradingCardScanner/Views/ScannerView.swift:482)). Introduce a
`MagicFinishLock` value = `(finish: PhysicalVariant, treatment: MagicTreatment?)`; a treatment selection locks its required finish *and* asserts the treatment. Extend
`VariantResolver.resolve` ([VariantResolver.swift:100-105](TradingCardScanner/Services/VariantResolver.swift:100))
so a treatment lock applies **only where the catalog agrees the treatment exists for that printing** — the same authority rule the finish lock already follows — and otherwise returns
`.needsChoice(lockDidNotApply:)`.

**Gate:** the Magic submenu renders exactly 6 rows: `Auto`, `Nonfoil`, `Foil`, `Etched Foil`,
`Surge Foil`, `Neon Ink`. A test asserts the Magic lock option list has `count == 5` (excluding Auto).
A test asserts that locking Surge Foil on a printing whose catalog treatments do **not** include
`surgefoil` yields `.needsChoice(lockDidNotApply:)` and never writes `surgefoil`. Pokémon's menu is
byte-identical to today.

### R6 — Choice bar labels describe the actual card
Change `VariantChoiceBar.button(for:)`
([ScanSessionOverlays.swift:363](TradingCardScanner/Views/ScanSessionOverlays.swift:363)) and its
accessibility label to use `choice.card.finishAndTreatmentDisplayLabel(for: option)`. Same change in
`GradedVariantCorrectionOfferView` ([:205](TradingCardScanner/Views/ScanSessionOverlays.swift:205))
and the activity-log finish picker
([CollectionActivityLogView.swift:491](TradingCardScanner/Views/CollectionActivityLogView.swift:491)).

**Gate:** a test builds an `IdentifiedCard` for LTR silver foil (`finishes: [nonfoil, foil]`,
`promoTypes: [silverfoil]`) and asserts the choice options render `["Nonfoil", "Silver Foil"]`, not
`["Nonfoil", "Foil"]`. A second test asserts a treatment-free dual-finish printing still renders
`["Nonfoil", "Foil"]` — no regression for the ordinary case.

### R7 — Exhaustive-switch sites updated
Five sites switch exhaustively on `MagicTreatment` and will fail to compile until handled — this is the intended safety net:
- [CollectionCSV.swift:1504](TradingCardScanner/Services/CollectionCSV.swift:1504) — `isModeled` gate;
  rewrite as `MagicTreatment.modelled.contains(treatment)`.
- [CardFinishOverlay.swift:249-257](TradingCardScanner/Views/CardFinishOverlay.swift:249) — `bands`.
  Do **not** author 31 band sets: add `var sheenFamily: SheenFamily` to `MagicTreatment`
  (`.neon` for `neonInk`, `.dispersed` otherwise) and switch on that.
- [CardFinishOverlay.swift:194](TradingCardScanner/Views/CardFinishOverlay.swift:194) — counter-band
  tint; route through `sheenFamily`.
- [CollectionView.swift:804](TradingCardScanner/Views/CollectionView.swift:804) — filter `sortValue`
  hardcodes `neonInk`; sort by `MagicTreatment.modelled` index instead.
- [MagicTreatment.swift:98-106](TradingCardScanner/Models/MagicTreatment.swift:98) — `encode(to:)`.

**Gate:** `xcodebuild build` succeeds with zero warnings introduced, and
`grep -rn '\.neonInk' TradingCardScanner/Views` returns `0` matches.

### R8 — Existing collection rows re-keyed
Widening the vocabulary changes derived treatments for ~2,660 additional printings, which changes their collection keys (`magic:<id>#<finish>#treatment=…`) and price keys. Bump
`MagicTreatmentMigration.currentVersion` 1 → 2
([MagicTreatmentMigration.swift:19](TradingCardScanner/Services/MagicTreatmentMigration.swift:19)).
Rows with `magicTreatmentMigrationVersion < 2` are re-examined, re-derived and merged by the existing
tested path (`:221`, `:374`, `:823`, `:865`). Rows whose Scryfall id is in the bundled catalog resolve
**offline** via `runLocal`; only the remainder need `runNetwork`.

**Gate:** a migration test seeds a v1 LTR silver-foil row keyed `magic:<id>#foil` with a price row
`magic:<id>:foil`, runs the migration, and asserts the row is re-keyed to
`magic:<id>#foil#treatment=silverfoil` with the price row aliased to `magic:<id>:foil:treatment=silverfoil`,
**quantity preserved and no duplicate row created**. A second test asserts an already-v2 row is a no-op. A third asserts a v1 row with no new treatment keeps its exact key.

### R9 — Diagnostics stay quiet except where the data really is contradictory
**Gate:** running `diagnostics(for:)` across all 5,150 catalog entries produces **exactly 3**
mismatches (`plst` M3C-246 / M3C-272 / M3C-297, `ripplefoil` on a `nonfoil`-only printing). Assert the
count is 3 and that no *other* card produces a diagnostic — this is what catches a wrong
`requiredFinishes` mapping.

---

## Global definition of done

All nine must hold simultaneously:

1. `xcodebuild build` succeeds; **0** compiler errors, **0** new warnings.
2. `xcodebuild test` — **100%** of the existing suite passes, including the focused
   `MagicTreatmentTests` and `VariantResolverTests` suites.
3. `MagicTreatment.modelled.count == 31`; **0** signals in the vocabulary lack a snapshot-attested card.
4. `MagicTreatmentCatalog/manifest.json` has **exactly 5,150** entries and loads with
   `MagicTreatmentCatalogLoadStatus == .ready` (**0** fallback errors).
5. Across the 41,142-card snapshot, treatment derivation produces **exactly 3** finish/treatment diagnostics.
6. The Magic lock submenu renders **exactly 5** selectable options (+ Auto). The Pokémon submenu
   renders **exactly 10**, unchanged.
7. For the **1,440** remaining dual-finish treated printings, the choice bar renders the treatment label; a
   parameterised test over a **≥20-card** fixture asserts **0** options labelled with a bare finish
   name where a treatment applies.
8. Migration: over a **≥50-row** seeded v1 fixture, post-migration row count is **unchanged** (no
   duplicates), total quantity is **unchanged**, and **100%** of rows report
   `magicTreatmentMigrationVersion == 2`.
9. CSV export → import round-trip over a fixture containing **all 31** treatments returns **0**
   `invalidTreatmentID` errors and byte-identical treatment ids.

---

## Files to modify

| File | Change |
|---|---|
| [Models/MagicTreatment.swift](TradingCardScanner/Models/MagicTreatment.swift) | 29 new cases, `modelled`, exhaustive `requiredFinishes`, `sheenFamily` |
| [Services/MagicTreatmentCatalog.swift](TradingCardScanner/Services/MagicTreatmentCatalog.swift) | vocabulary-driven allowlist; `diagnostics` over `requiredFinishes` |
| [Models/CardVariant.swift](TradingCardScanner/Models/CardVariant.swift) | unchanged finishes; `selectable(for:)` stays 3 for Magic |
| [Services/VariantResolver.swift](TradingCardScanner/Services/VariantResolver.swift) | treatment-aware lock, catalog-authority rule |
| [Views/ScannerViewModel.swift](TradingCardScanner/Views/ScannerViewModel.swift) | `MagicFinishLock` type, `setFinishLock` plumbing |
| [Views/ScannerView.swift](TradingCardScanner/Views/ScannerView.swift) | `FinishLockControl` menu rows |
| [Views/ScanSessionOverlays.swift](TradingCardScanner/Views/ScanSessionOverlays.swift) | treatment-qualified option labels |
| [Views/CollectionActivityLogView.swift](TradingCardScanner/Views/CollectionActivityLogView.swift) | same label reuse |
| [Views/CardFinishOverlay.swift](TradingCardScanner/Views/CardFinishOverlay.swift) | `sheenFamily` switch |
| [Views/CollectionView.swift](TradingCardScanner/Views/CollectionView.swift) | filter ordering |
| [Services/CollectionCSV.swift](TradingCardScanner/Services/CollectionCSV.swift) | `isModeled` via `modelled` |
| [Services/MagicTreatmentMigration.swift](TradingCardScanner/Services/MagicTreatmentMigration.swift) | `currentVersion = 2` |
| [scripts/generate_magic_treatment_catalog.sh](scripts/generate_magic_treatment_catalog.sh) | read `vocabulary.json` |
| `TradingCardScanner/MagicTreatmentCatalog/vocabulary.json` | **new** — the one vocabulary list |
| `TradingCardScanner/MagicTreatmentCatalog/manifest.json` | regenerated, 5,150 entries |
| [Tests/MagicTreatmentSnapshot.swift](TradingCardScannerTests/MagicTreatmentSnapshot.swift) | `auditRules = 2` |
| Tests: `MagicTreatmentTests`, `VariantResolverTests`, `PricingTests`, `ScannerViewModelTests`, `CollectionKeyTests` | new + updated assertions |

**No schema change is needed.** `magicTreatmentIDsRaw` is already `[String]`, and
`PhysicalVariant.resolving` already carries unknown ids through verbatim.

---

## Verification

```bash
scripts/generate_magic_treatment_catalog.sh && python3 -c "import json;a=json.load(open('TradingCardScanner/MagicTreatmentCatalog/manifest.json'));print(len(a['entries']))"
```
Expect `5150`.

```bash
xcodebuild test -scheme TradingCardScanner -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Then drive the simulator end-to-end:
1. Scan an LTR silver-foil card (`finishes: [nonfoil, foil]`) → choice bar must read
   **Nonfoil / Silver Foil**.
2. Tap Silver Foil → collection row shows `Silver Foil`; its price key carries `:treatment=silverfoil`.
3. Set the lock to **Surge Foil**, scan an FIC surge printing → resolves with no prompt.
4. With the lock still on Surge Foil, scan a plain LTR card → choice bar appears with the
   "no Surge Foil printing exists" notice; **no** `surgefoil` is written.
5. Launch with a pre-existing v1 database → migration completes, portfolio total value and card count are unchanged.
