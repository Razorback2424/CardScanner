# Scripts Guide

**Scope:** `scripts/` (including `scripts/tests/` and `scripts/fixtures/`). Also follow the root [`AGENTS.md`](../AGENTS.md).

This directory mixes offline audits, retained-source replay, live provider capture, catalog generators that write into the app bundle, UI capture, and hosting/publication tools. Know which kind you are about to run.

## Before running anything

Read the script's arguments, environment variables, and **every output path**. Classify it:

| Kind | Examples | Side effects |
| --- | --- | --- |
| Offline audit / replay | `audit_*.py`, `reconcile_*.py`, `verify_*.py` | Reads retained inputs; may write reports |
| Live capture | `capture_*.py`, `discover_one_piece_products.py`, `one_piece_tcgcsv_capture.py`, `generate_magic_treatment_snapshot.sh` | Contacts providers; results change over time |
| Generator into app resources | `build_*_catalog.py`, `generate_*.sh`, `update_mee_snapshot.py` | Rewrites bundled resources under `TradingCardScanner/` |
| Simulator / Xcode | `ui_build_and_shoot.sh`, `centering_ui_build_and_shoot.sh`, `generate_pokemon_snapshot.sh` | Builds the app; may uninstall the simulator app |
| Hosting / publication | `restore_catalog_hosting_site.sh`, `restore_pokemon_catalog_releases.sh`, `verify_*_publication_*`, `verify_*_hosting_*` | Shapes what the shared site publishes |

Do not run live capture or regenerate committed resources just to verify a code change; replay retained inputs instead.

## Known surprises

- `generate_magic_treatment_snapshot.sh` downloads live Scryfall bulk data, writes the audit snapshot (`MAGIC_TREATMENT_SNAPSHOT_OUTPUT`), **and always** rewrites `TradingCardScanner/MagicTreatmentCatalog/` via `generate_magic_treatment_catalog.sh`. Redirecting the snapshot does not redirect the catalog.
- `generate_pokemon_snapshot.sh` runs an app-hosted `xcodebuild test` (one `BrowseFeatureTests` method) and requires `POKEMON_SNAPSHOT_DERIVED_DATA_PATH` on the external SSD.
- `ui_build_and_shoot.sh` uninstalls the app (deleting simulator data) unless `UI_PRESERVE_APP_DATA=1`, and defaults `DERIVED_DATA` to `/tmp`. See [`../TradingCardScanner/Views/AGENTS.md`](../TradingCardScanner/Views/AGENTS.md).
- `audit_game_boundaries.sh` currently fails on existing legacy branches; compare before/after rather than treating failure as new.

## Data contracts

- Preserve retained source bytes, receipt hashes, capture dates, and identity-assignment ledgers. Never rewrite a retained input to make a test pass.
- Keep discovery data, physical-printing authority, finish evidence, and market observations separate. For example, One Piece normalization explicitly grants no physical UUID, finish, or completeness authority.
- Preserve stable physical identities (UUIDs, pinned keys) when rebuilding; validate against the previous release.
- Change generated artifacts only through their producer, and review companion outputs (catalog + vocabulary + manifest) together.
- Not all JSON is generated. `publisher/catalog-input.json` and `publisher/discovery-policy.json` are owner-controlled policy inputs; `scripts/yugioh_*.json` and `lorcana_product_evidence.json` are curated inputs. Their `fixtures/` counterparts are recorded test inputs. Edit the one whose role matches the task.
- Hosting changes must keep the shared-site preservation contract: restoring other catalog namespaces before deploy (see `restore_catalog_hosting_site.sh` and `test_catalog_hosting_restore.py`).

## Verification

Start with the focused offline test, which is usually named after the script (`scripts/tests/test_<script or area>.py`):

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -p test_one_piece_product_pipeline.py -v
```

The `.github/workflows/*.yml` files list the exact tests each area runs. Yu-Gi-Oh! fixture tests run with `PYTHONPATH=scripts python3 -m unittest discover -s scripts/fixtures/yugioh -v`. When a script's output feeds a catalog package or the app, also run that side (`swift test --package-path <Package>` or the matching app test class).
