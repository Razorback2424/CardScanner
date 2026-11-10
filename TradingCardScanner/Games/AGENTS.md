# Games Guide

**Scope:** `TradingCardScanner/Games/`. Also follow [`../AGENTS.md`](../AGENTS.md).

Each game (`Pokemon/`, `Magic/`, `OnePiece/`, `Lorcana/`, `YuGiOh/`) plugs into the app through adapters declared in `Core/`: recognition, catalog, Browse, import, pricing, variant policy, and catalog activation. Game-specific decisions belong behind those adapters, not in central services.

## Where to start

1. Read `Core/CardGameRuntime.swift` to see how runtimes register, which capabilities (`.scan`, `.browse`, `.collectionWrite`, …) gate which features, and how activation and price authority are bound to the storage container.
2. Open the affected game's `*GameRuntime.swift` to find the adapter that owns the behavior.
3. Change that adapter. If no adapter seam fits, extend the `Core/` protocol rather than adding a game branch to a central service.

## Contracts to preserve

- **Registration identity.** Registration rejects an adapter whose game does not match its runtime (`RegistrationError.*GameMismatch`). Keep each adapter's declared game correct.
- **Capabilities match implementations.** Declare a capability only when the adapter that serves it exists and works; features filter runtimes by capability.
- **Ambiguity is a result.** Recognition evaluates every participating recognizer; when more than one identifies a card, the outcome is `.ambiguous`. Registration order must never pick a winner.
- **Exact printing and variant identity** survives recognition, import, and pricing. Do not collapse a variant or treatment to a default to make a match succeed.
- **Imports validate.** A game outside the legacy set must supply an import adapter that validates the exact printing; otherwise import fails with `GameImportValidationError.missingAdapter`. Do not bypass that.
- **Activation, collection authority, and price authority stay coordinated.** A catalog activation that changes what can be owned must also be reflected in collection validation and pricing (see `CollectionAuthorizedActivationSource`, `installDeferredPriceAuthorities`).

## Boundary audit

`scripts/audit_game_boundaries.sh` lexically flags explicit game branches in central services. It currently **exits non-zero on existing legacy branches** awaiting extraction. Use it to confirm your change adds no new branches (compare against the output before your edit) and report the existing ones; do not turn a small game fix into an unrelated extraction.

## Verification

Run `CardGameForwardCompatibilityTests` plus the affected game's integration/activation suites, for example `OnePieceIntegrationTests`, `OnePieceCatalogActivationTests`, `LorcanaIntegrationTests`, `MagicCatalogActivationTests`, `MagicRecognitionProfileTests`, `YuGiOhRecognitionTests`/`YuGiOhWorkflowTests`, `PokemonCatalogRegistryTests`, and `GameRecognitionRegistrySupplementalTests` for cross-game recognition. Several of these classes live in files with other names; see [`../../TradingCardScannerTests/AGENTS.md`](../../TradingCardScannerTests/AGENTS.md).

Catalog package changes (`PokemonCatalogCore`, `MagicCatalogCore`, `OnePieceCatalogCore`) also need `swift test --package-path <Package>`.
