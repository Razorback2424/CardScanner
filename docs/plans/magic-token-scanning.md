# Magic token scanning

**Status:** current design authority — 2026-11-01. Engine implemented on
`claude/mtg-token-scanner-g4un9y`; **not built or tested** (authored in an
environment without Xcode or a Swift toolchain). Scanner, persistence, pricing
and UI integration are not started. No physical-card, provider or device
evidence is claimed.

## The problem

The scanner reads one printed face. The collection owns cardboard. For
ordinary cards they are the same thing. For tokens they are not:

- A **double-sided token** is two faces printed back to back, each with its
  own footer (`T 0006 MSH • EN` on one side, `T 0018 MSH • EN` on the other).
- **One face can be printed against several backs.** Reading that face
  perfectly still does not say which card is in hand. The pairing was decided
  at packaging, not printed on the face.
- **Turning a card over** shows a second, valid, different identifier. To the
  existing latch that looks like a new card.

## Scope: what "token cards" are

Evidence below comes from this repository: the bundled Scryfall snapshot
(`TradingCardScanner/MagicTreatmentSnapshot`: 213 source token sets totaling
2,950 cards, of which 132 sets containing 1,112 records are retained evidence)
and TCGplayer listings in
[`magic-product-proof.json`](../../TestFixtures/TradingCards/SetPricingAudit/magic-product-proof.json).

| Kind | Examples in repo data | In scope |
| --- | --- | --- |
| Creature / artifact / named tokens | TMSH Soldier, Clue, Treasure; legendary Galactus, Smaug | Yes |
| Collector Booster-only reprints at their own numbers | TMSH 23–27, TLTR 14–25 (surge foil only) | Yes — distinct faces |
| Emblems, alone or backing a token | AKH Gideon emblem; MD1 `Emblem - Elspeth // Soldier` | Yes |
| Game helpers in token sets | `Undercity // The Initiative`, `The Ring // The Ring Tempts You` (number `H13`), `Gremlin // Energy Reserve`, `Punchcard // Punchcard` | Yes, as catalog entries. `H13`-style numbers do not parse today (safe miss) |
| Deck/kit/event tokens | GRN/RNA Guild Kits, Modern Event Deck 2014, Commander token sets | Yes |
| Promo token sets sharing a parent code | `WFIN`, `PT*`, League `L1x`, FNM `F1x` | Routing gap (see risks) |
| Substitute cards (`S*` sets), checklists, ad/tip backs | SNEO, SMOM… | Not collection objects. A token whose back is one of these is **single-sided** |
| Art cards | memorabilia `A*` sets | Separate existing model |
| Pre-modern-footer tokens, non-English, digital | — | Out of scope (same boundary as historical Magic) |

How the cardboard is put together:

1. **Single-sided** — one token face. The back is an ad, a tip, a substitute or
   some other non-token.
2. **Double-sided, 1:1** — each face appears on exactly one card (`Merfolk // Doombot`, `6 // 18`).
3. **Double-sided, 1:N** — one face on several cards. GK1 Saproling #8 is printed
   against Voja, Wurm and Elf Knight. GK1 Goblin #4 is on three cards. MD1
   Soldier #1 and Spirit #2 are each on two.
4. **Same face on both sides** — `Punchcard // Punchcard`. This is double-sided
   and never the same object as a single-sided Punchcard.
5. **Same name, different faces** — `Soldier (002) // Soldier (006)`.
6. **One cardboard, several listings** — foil/nonfoil, or the same token sold in
   two decks. This is one physical object: a finish or packaging fact, not a
   pairing question.

What the data says about providers:

- **Scryfall usually models a double-sided token as two unrelated `token`
  records** (TMSH 6 and 18) with no pairing. Only a few cards are a single
  `double_faced_token` record, and that record carries one number even where
  the card prints two. TGK1 #11 `Voja // Saproling` is listed by TCGplayer
  as `8 // 11`.
- **TCGplayer names the physical card**: `Merfolk // Doombot Double-Sided Token`
  at number `6 // 18`. Naming is not consistent (`Soldier (002) // Goblin Token`).
- **A face's number is not unique, even within one listing group.** GK1 reuses
  2 (Soldier/Horror), 5 (Insect/Saproling) and 6 (Elf Knight/Soldier). RNA
  Guild Kit reuses 6 (Frog Lizard/Goblin). **A face is identified by token set
  plus number**, with the printed name as a cross-check.

## Model (implemented)

[`MagicPhysicalObjects.swift`](../../TradingCardScanner/Models/MagicPhysicalObjects.swift):

- `MagicTokenFaceID` — token set + normalized number (`0017` = `17`; the `H13`
  prefix and suffixes are kept). The name is not identity.
- `MagicPhysicalTokenKey` — one or two face ids, sorted, so either side may come
  first. Storage form is `TMSH:6|TMSH:18`, which is provider-independent.
- `MagicPhysicalToken` — faces in display order plus every TCGplayer listing id.
- `MagicTokenProductCatalog` — maps each face to the cards that carry it
  (one-to-many). Listings of the same key are merged.
- **Coverage per token set** (`complete` / `partial` / absent). Only a reviewed
  `complete` claim lets an *absence* mean something. A complete claim that does
  not know the face is not trusted for that face.
- A published JSON wire format (`MagicTokenProductCatalogFile`). The whole file
  is refused if the schema is unknown, the generation is missing, a set appears
  twice, a product does not have 1–2 non-blank faces, an id is blank, a coverage
  value is unknown, or **one face id carries two names** (the GK1 failure).

Resolution:

| Read | Catalog says | Result |
| --- | --- | --- |
| One face | set complete, one card | **resolved** — zero friction |
| One face | several cards, or coverage not complete | **needs reverse** — candidates + whether they are exhaustive |
| Two faces | one card carries both | **resolved** |
| Two faces | none, and either side's set is complete | **different cards** |
| Two faces | none, and coverage cannot rule it out | **uncatalogued pair** — needs a person |
| Same face twice | — | **not evidence** |

## Scan flow (implemented as a pure state machine)

[`MagicTokenPairingSession.swift`](../../TradingCardScanner/Services/MagicTokenPairingSession.swift)
sits after the card latch and catalog face lookup, and before the add.

```
face read ─┬─ unique (complete set) ───────────────→ add · hold
           └─ ambiguous ──→ "Flip it"  [back tiles] [No token on back]* [Skip]
                               │ recognition keeps running
                               ├─ other side read, catalogued ───→ add (no tap)
                               ├─ tap a back tile ────────────────→ add
                               ├─ other side read, uncatalogued ─→ "Same card?" [Yes] [No]
                               ├─ face never printed with it ────→ park · start new card
                               └─ ordinary card / skip ──────────→ park (Needs Attention)
held card: its other side read → "same card" (never added again)
```

`*` "No token on back" is offered only when it is possible: the catalog is not
exhaustive, or it lists a single-sided printing.

Rules and why:

- **Fast.** Pairing lookups are local dictionary reads; there is no network on
  the decision path. The flip *is* the input: a 1:N face costs one turn of the
  wrist and no tap. Recognition never pauses during the flip, unlike the finish
  choice, because the answer is the other side of the card.
- **Accurate.** A back is never picked. Coverage gates certainty. Anything
  uncatalogued needs both faces *and* a person. Listings never turn finish
  into a pairing question. A contradiction parks the face and mutates nothing.
  Every record carries a `MagicTokenPairingBasis` (`uniqueFace`,
  `bothFacesCatalogued`, `userChoseCandidate`, `userDeclaredSingleFaced`,
  `userConfirmedObservedPair`) plus the catalog generation, so a wrong coverage
  claim can be traced and reassessed without touching rows a person decided.
- **A joy to use.** Turning a token over to look at it never duplicates it: the
  other side of the held card is "same card", even across an empty band. The
  open question survives the empty band a flip produces. A parked face keeps
  its candidates and any unconfirmed back on one Needs Attention entry.
- **Unchanged latch rules.** The same side after the band empties is another
  copy. A different card releases the hold. Quick flip-and-back is already
  covered by `CardLatch.minimumAbsenceBeforeRelatch` (2 s).

**Explicit tradeoff.** While "Flip it" is showing, suppose the person ignores it
and presents a *different* card whose visible face happens to be one of the
candidate backs. That card is recorded as the pair. Mitigations: the prompt is
explicit, the receipt names both faces, and undo is one tap. The alternative,
a confirmation tap after every flip, taxes the common case for a rare one.

## Integration slices (not started)

1. **Catalog publication.** Generate `MagicTokenProductCatalog` offline from
   TCGCSV TCGplayer groups (`A // B` names, `n // m` numbers) and Scryfall
   `double_faced_token` records. Assign each face its Scryfall token set and
   number with a name cross-check, and add reviewed corrections with
   provenance. Bundle it like `MagicTreatmentCatalog`, then later deliver it
   through the signed Magic catalog. Coverage starts absent. `complete` is set
   per set only after review.
2. **Scanner.** In `ScannerViewModel`, route resolved Magic faces with
   `contentKind == .token` through the session before the add. Map latch
   release to `.bandCleared` and non-token confirmations to
   `.otherCardConfirmed`. On add, the latch must consume **every face** of the
   key. When a question opens, prefetch the candidate faces' records and
   thumbnails.
3. **UI** (`ScanSessionOverlays`). An inline flip card shows the face read, the
   back tiles and the conditional actions. The receipt shows
   `Merfolk // Doombot · Double-sided token`. "Same card" is a quiet hint, with
   +1 routed to the existing held-card offer.
4. **Persistence.** Add an optional pair key and basis to `CollectedCard` and
   `CollectionActivity` (lightweight migration, like `magicContentKindRaw`). The
   ownership key becomes the physical key plus the finish. CSV and CloudKit
   round-trip need explicit tests.
5. **Finish.** A pair's possible finishes are the intersection of its faces'
   finishes. After that, the existing `VariantResolver` and Finish Lock apply
   unchanged.
6. **Pricing.** Price comes from the card's TCGplayer listing. A Scryfall face
   price may be used only when that face record's TCGplayer id equals the
   listing. When there are several listing ids with no finish/packaging
   mapping, the price is unavailable. Uncatalogued pairs read "Price
   unavailable".

## Open evidence gates and risks

The engine emits acquisition intent only. Scanner/storage integration must
acknowledge successful and failed ownership writes before finalizing a receipt
or suppression state, and route undo back through that state. Those adapters,
pricing and UI integration remain deferred. Valid legacy token keys retain their
spelling; colon/pipe-bearing identity components are rejected, not migrated.

- [x] 2026-11-02: Xcode 27.1 / iOS 27 unsigned simulator executed both suites:
      26 model and 22 engine tests passed. CI selection now includes both;
      this does not validate the deferred integration or physical flips.
- [ ] Physical samples: emblem and helper footers, letter-prefixed numbers,
      pre-2023 token footer grammar (current parser behaviour on these is a
      safe miss, not verified support).
- [ ] Child routing: `ScryfallService.childSet` prefers `T<parent>` when a
      parent has several token children (e.g. `TFIN`/`WFIN`). A promo token
      carrying the same printed code and number could resolve to the main set.
      If that number exists in more than one child, it should become a choice.
- [ ] A per-set coverage review procedure and the first reviewed `complete` sets.
- [ ] Device acceptance: flip timing against latch release, and how
      discoverable the prompt is.
