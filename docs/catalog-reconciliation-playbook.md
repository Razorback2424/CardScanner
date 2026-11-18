# Catalog reconciliation playbook

**Status:** current method for every game's catalog backlog. Adopted 2026-11-18,
after One Piece revision 7.

The One Piece pass took the catalog from 684 "Printing needs review" rows and
no certified cards to 2,670 of 2,969 cards certified, with 173 true exceptions
left. That is now live as revision 7. It worked because the work was grouped
**by root cause, not by card**. This playbook records that method so Lorcana,
Pokémon and Yu-Gi-Oh can follow it.

## Principles

1. **Capture once, replay offline.** Take one complete, hash-pinned snapshot of
   each source: the TCGCSV category plus the publisher's card list. Every later
   pass runs offline against those bytes, so a batch can be rerun in seconds
   and reviewed exactly. A TCGCSV snapshot cannot be extended after 24 hours,
   so capture right before a pass and keep it on the external SSD.
2. **Measure with a reason-coded ledger every pass.** Each open row gets one
   reason code ([`scripts/catalog_exceptions.py`](../scripts/catalog_exceptions.py)).
   The next batch targets the largest reason. `diff` shows what a batch closed
   and whether it reopened anything.
3. **One reconciler per root cause, with strict gates.** A reconciler closes
   rows only when every gate passes:
   - the identity and number match;
   - the publisher's count agrees;
   - the title match is unique within the expected group;
   - the price lanes agree;
   - the photo matches, where art could differ.

   Anything ambiguous stays open with a reason.
4. **Policy lives in reviewed rule files, not per-card code.** Example:
   [`event-stamp-products.json`](../publisher/one-piece/event-stamp-products.json)
   pins each event's group, page, expected count and stamp. Adding a release
   means adding a reviewed rule entry.
5. **Follow collector conventions, written down once.** File printings the way
   the marketplace collectors use does. For One Piece that meant:
   - reprints are separate printings under the reprinting product;
   - stamped tiers are separate printings;
   - errata cards stay one printing.

   Record each such decision in the rule data and the game's guide.
6. **Known gaps are honest, not blocking.** A real printing with no price
   anywhere, or no photo, carries an evidence marker and a row label ("Not yet
   priced", "Art not yet confirmed"). It does not mark its set partial, and it
   does not stop the card family from being certified.
7. **Certify in batch; badges describe the set's own contents.** A certifier
   marks complete every card whose gates pass. A set is "Partial catalog" only
   when something the publisher lists for that set is missing, or one of its
   own printings is unresolved.
8. **Preflight every release.** Before signing:
   - run [`scripts/catalog_release_preflight.py`](../scripts/catalog_release_preflight.py),
     which reads each game's size caps from the Swift readers and fails within
     5% of them;
   - build on the live revision rather than an older candidate;
   - keep the local publish fallback ready (`scripts/publish_one_piece_local.py`
     for One Piece).

## The pass loop

1. Capture fresh sources (live capture scripts only).
2. Rebuild the catalog offline and write a ledger with `catalog_exceptions`.
3. Run `python3 scripts/catalog_exceptions.py summarize <ledger>` and pick the
   largest reason with a mechanical rule.
4. Write or extend that reason's reconciler and its reviewed rule file, with
   tests.
5. Rebuild, then write the next ledger. Run `diff` against the previous one,
   and spot-check the closed rows (photos for art-sensitive rules).
6. Repeat until the remaining reasons each need a person: an ambiguous photo,
   a publisher listing with no product, or an owner decision. Record those as
   the true exceptions.
7. Certify, run the preflight, then sign and publish, or ship with the app
   build for bundled catalogs.

## Where each game stands

| Game | Sources | Tools | Delivery |
| --- | --- | --- | --- |
| One Piece | Bandai card list, TCGCSV category 68 | `reconcile_one_piece_*`, `audit_one_piece_coverage.py`, `certify_one_piece_coverage.py` ([publisher guide](../OnePieceCatalogCore/README.md)) | Signed remote catalog |
| Lorcana | LorcanaJSON, TCGCSV category 71 | `build_lorcana_discovery_catalog.py`, `build_lorcana_market_catalog.py`, `audit_catalog_coverage.py` | Bundled seed |
| Pokémon | TCGdex checklist, TCGCSV category 3 | `capture_pokemon_tcgcsv.py`, `audit_pokemon_tcgcsv.py`, `certify_pokemon_finish_coverage.py` | Signed set directory; finish coverage bundled |
| Yu-Gi-Oh | YGOPRODeck, TCGCSV category 2, Konami inventories | `build_yugioh_catalog.py` and helpers | Bundled seed |
| Magic | Scryfall (live) | Treatment and printing-family builders | Live; no reconciliation backlog |

Game-specific plans and audits stay authoritative for each game's current
counts. This page records the method, not status.
