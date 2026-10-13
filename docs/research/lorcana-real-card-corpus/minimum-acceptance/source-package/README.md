# Lorcana — minimum real physical-card acceptance batch

Research dated **2026-10-12**. Prepared against the supplied 29-record / 25-scenario source package. The original three JSON inputs are reproduced byte-for-byte in `source_snapshot/` so no data is silently overwritten. Use as a **local research/evidence workspace** alongside `docs/research/lorcana-real-card-corpus/`.

## What was genuinely done

1. Selected **12 specimen-instance targets** spanning same-footer different sizes, nonfoil/cold foil, cross-set gameplay reprints, separate premium artwork, two lettered artworks, two Location layouts, a 2022 D23 stamped early-format promo, a gold-backed Q1 Quest card, and a /207 denominator.
2. Independently rechecked published card/footer/product claims against publisher documentation and specialist references. Each target has individual source URLs, research decision, expected size reference and artwork description in `minimum_specimens.json`.
3. Located useful **secondary publicly hosted photographs** for Mickey D23, Hades, and Dalmatian `4c`. Links and what those photographs appear to show are recorded. **Those photographs were not acquired with redistribution rights, not downloaded, and are not card-in-hand capture evidence.**
4. Created **12 prefilled, but intentionally unapproved physical evidence packets** with blank actual-photo, exact glyph, measured-size, finish and reviewer fields. No app-owned physical UUID was created. No permitted finish was asserted.
5. Prepared an execution matrix for **all 25 original acceptance scenarios**, including applicable target IDs and block reasons, and ran offline source/gate assertions. This is NOT an app runtime/scanner test.

## Critical findings

- Hades Gift Set foil exists in both standard and oversized physical formats. Same printed `5/204 EN 1` alone **cannot determine size**. Nonfoil and standard foil are candidate finishes for a standard physical printing; this relationship must be inspected before signing.
- Stitch `23/204 EN 1` and `3/204 EN 9` are a publisher-confirmed gameplay reprint pair but different physical printing targets.
- Elsa Enchanted `207/204 EN 1` is not the same physical printing as ordinary `42/204`; premium numbering does not become a finish selection.
- Dalmatian `4a/204` versus `4c/204` shows separate artworks/identities. The current supported OCR syntax was described as narrow numeric footer parsing; **do not assume alphanumeric numerator recognition** until tested/extended. Remain recoverably incomplete.
- Location card art is landscaped. Standard-card **physical stock** does not thereby become an oversized physical card; width and height swap according to orientation.
- D23 Mickey 2022 has the unusual `1TFC EN 1/P1` footer *order* and distinct D23 Expo and 1st marks; no silent conversion into a modern three-field marker. This remains a held parser grammar.
- Q1 Ursula's Contract is officially shown as `30/31 EN Q1` and listed as an *Item* in the publisher gallery, while sold inside a gold-backed scenario deck. The product's distinct distribution/back makes a simple ordinary-card write unsafe until raw item-kind review.
- Cinderella 2024 D23 (`2/D23` official vs `02/D23` collector) remains **quarantined separately**. Do not normalize away the zero, even if an indexed listing photograph appears to favor one variant.
- Third-party reported sizes for standard portrait are approximately 63.5 × 88.9 mm and Gift Set oversized 87.9 × 125.9 mm. These are **published dimensions, not measurements of the 12 specimens**. The referenced article has an internally inconsistent inch rendering for standard cards; measure physically.

## Which gates are still OPEN

**0/12 card-in-hand or permissioned specimen packets are complete. 0/12 independent two-reviewer decisions. 0/12 approved for any local seed. 0/25 runtime acceptance scenarios run.** The environment used to prepare this package cannot access the developer's `/Users/...` uncommitted source checkout, Xcode simulator, physical iOS devices or individual collector specimens. Source research and Python safety checks cannot stand in for them.

For an acceptance packet require, at minimum:

- Original front, back, footer macro, artwork/stamp macro and angled-light finish images, with capture provenance, rights/permission and SHA-256 of *actual* files. For the oversized case, a ruler or in-frame standard comparison is mandatory.
- Literal printed footer glyphs, spacing, order and orientation taken **from the physical image**, not copied from an API or this source list.
- Measured physical width and height and measurement method; documented finish under light; exact visible stamp/artwork, physical back/raw kind, and any conflicting evidence.
- A versioned definition of the candidate universe for that footer (including unsupported/held alternatives), reviewed distribution/art-size distinctions and stable physical UUID allocation/revision transitions.
- Two distinct independent human reviewers approving physical identity, finish and candidate-universe decision against referenced image hashes; otherwise leave the record held.
- An exact reviewed schema-2 registry and ephemeral signed seed that activate *only approved records* through the isolated local debug kit. Do **not** edit production defaults or CloudKit registration.

**Then** run the `scenario_execution_matrix.json` actions using `TradingCardScanner-ProfileLocal` / `DebugRemoteLocal`, a genuinely isolated local SwiftData store and, for the camera flows, actual recorded device capture. Record xcresult bundle paths and results. Do not call a scenario PASSED unless its correct surface and preconditions were actually exercised. Preserve missing/unreviewed classes as unresolved; do not fill gaps with fabricated IDs.

## Files

- `minimum_specimens.json` — concrete twelve-source-reviewed target slots.
- `evidence_packets/MIN-XX.json` — twelve individual evidence packets; no real photo/finish/size authority asserted.
- `scenario_execution_matrix.json` — all 25 cases and truthful execution status.
- `gate_audit.py`, `test_gate_audit.py` — executable *offline corpus/gate* checks (no Xcode and no simulation of a production authorization).
- `offline_gate_results.json` — exact offline assertion results from this session.
- `source_snapshot/` — original research inputs unchanged.
- `SHA256SUMS.txt` — integrity hashes.

No production registration, signed activation, collection mutations, pricing, publishing, simulator tests, commits or pushes were performed.
