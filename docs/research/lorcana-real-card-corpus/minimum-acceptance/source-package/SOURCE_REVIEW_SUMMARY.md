# First 12 specimen targets — source research decisions

**Date:** 2026-10-12. **Research decision ≠ physical signoff.** Every row has `physical_approval=false`; every physical finish, size, footer and candidate-universe field still requires specimen evidence. 'Documented' indicates a verifiable public claim only, not measurements.

| Target | Source-documented footer | Published distinction | Evidence decision | Physical action required |
|---|---|---|---|---|
| MIN-01 Hades ordinary | `5/204 EN 1` | Standard nonfoil, throne art | Documented; unapproved | Front/back, literal footer, ruler size, normal finish |
| MIN-02 Hades foil | `5/204 EN 1` | Same standard card, playable Gift Set foil | Publisher-supported; unapproved | Compare directly to MIN-01, angled finish, stamps |
| MIN-03 Hades jumbo | `5/204 EN 1` | Oversized Gift Set foil; same footer | Publisher-supported; unapproved | Photo with MIN-02 and ruler, measure dimensions |
| MIN-04 Stitch original | `23/204 EN 1` | The First Chapter printing | Publisher-supported; unapproved | Literal footer/artwork scan, compare against reprint |
| MIN-05 Stitch reprint | `3/204 EN 9` | Fabled printing, same gameplay | Publisher-supported; unapproved | Distinct printing evidence; ensure different ownership key |
| MIN-06 Elsa Enchanted | `207/204 EN 1` | Alternate illustration, premium-numbered | Publisher-supported; unapproved | Approved front/back and moving-light foil image; never use as 42/204 finish |
| MIN-07 Dalmatian 4a | `4a/204 EN 3` | One of five lettered pictures | Collector-documented; unapproved | Card photo, footer and art; parser must not reduce to `4` |
| MIN-08 Dalmatian 4c | `4c/204 EN 3` | Different art; third-party photo of held card | Collector/photo-documented; unapproved | Permissioned front/back and angled foil image; literal footer |
| MIN-09 Motunui Location | `170/204 EN 3` | Landscape layout on standard stock | Catalog-documented; unapproved | Physical horizontal orientation and camera ROI under rotation |
| MIN-10 2022 D23 Mickey | `1TFC EN 1/P1` | D23/1st stamps, reversed early footer order, nonfoil | Photo + collector-documented; **grammar held** | Permissioned true front/back, macro for marks/footer, actual finish |
| MIN-11 Ursula's Contract | `30/31 EN Q1` | Gold-backed Quest scenario deck / official Item type | Publisher-supported; **item-kind held** | Front/back with actual gold back, raw kind and finish review |
| MIN-12 Vine Entrance | `207/207 EN 13` | Landscape Location, denominator 207 | Publisher-supported; unapproved | Actual printed footer, standard size, live camera ROI |

All measurements are **unfilled** in the evidence packets. The listed expected standard size is approximately **63.5 × 88.9 mm** (orientation swaps for landscape), and a reported gift-set jumbo size is **87.9 × 125.9 mm**, as relayed by [Wargamer](https://www.wargamer.com/disney-lorcana/card-size) based on contact with Ravensburger. These are approximate targets, not 12 new readings. The page's standard-size inch conversion is internally inconsistent, so do not accept it as specimen measurement.

## Additional, deliberate holds outside the first 12

- `LRC-017`: **Cinderella 2024 D23**. [Official gallery](https://cards.disneylorcana.com/en-US/?cardId=1192) prints `2/D23 EN 2` in metadata; [collector record](https://lorcanaplayer.com/card/cinderella-stouthearted-d23-collection/) uses `02/D23`. Both claims retained pending literal photographic review. No leading-zero repair.
- `LRC-016`: Cinderella Challenge `3/C1`, foil versus nonfoil distribution; finish/stamp physical identity unresolved.
- `LRC-023`: unnumbered oversized Ursula. Must never manufacture a collector footer.
- `LRC-003/LRC-004`: Mulan standard/oversized same-footer second check is deferred; the source package retains them. If Hades passes, test Mulan as a second independently reviewed size case before broad production.
- `LRC-013b/d/e`: other three puppy arts retained in the 29-record inventory; do not declare artwork completeness from just a and c.

## Stage boundary and required operator actions

The available material does **not** include a real card, its original photographic captures, physical scale measurements, human signoff, the uncommitted macOS checkout or iOS simulator. Therefore original iOS cases `LRC-AC-01`–`LRC-AC-25` are **NOT RUN**. Their exact action/expected outputs are faithfully carried into `scenario_execution_matrix.json` for execution once verified.

1. Obtain originals or permissioned, independently documented physical photos for these twelve targets. Close *each packet* separately; two different finish specimens require two separate packets.
2. Record the literal glyphs, widths/heights, orientation, foil behavior, artwork/stamps/back, image hashes and chain of custody. For Hades jumbo, include a standard card in the same frame with ruler.
3. Get **two independent people** to review hashed evidence for printing identity, finish, same-footer candidate-universe completeness and any correction history; do not auto-approve on a successful script run.
4. Construct only approved schema-2 physical records in the existing codebase; assign durable app-owned UUIDs; create a signed ephemeral **isolated local** debug seed, preserving the original legacy read-only recovery and unsupported class cases.
5. Run the 25 mapped actual runtime scenarios, including scanner encounter independence, explicit size choice, per-printing finish, write/undo/relaunch, Browse and CSV. Use physical device for ROI accuracy; phone/tablet/large-text for rendering. Record xcresult + recorded photos/frames and close cases individually. Production defaults and shared sync remain off.
