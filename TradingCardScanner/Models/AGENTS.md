# Models Guide

**Scope:** `TradingCardScanner/Models/`. Also follow [`../AGENTS.md`](../AGENTS.md).

This directory mixes **persisted** SwiftData models (`@Model` types such as `CollectedCard`, `PriceRecord`, `ProductIdentity`, `CollectionActivity`, `InventoryEvent`, `PriceObservation`, `PriceCheckDay`, `PortfolioDailyClose`, `ReferenceQuote`) with plain value, measurement, and presentation types. The compatibility rules below apply to persisted types; ordinary value types can change normally.

## Persisted types are compatibility contracts

Existing collections on users' devices (and CloudKit records) must keep loading without a versioned-schema rewrite.

- Treat entity names, `@Attribute(originalName:)` mappings, key formats, stored raw values, and property defaults as contracts. Examples that look like cleanup targets but are not:
  - `CollectedCard` keeps its original entity name so existing stores migrate.
  - `collectionKey` maps to the original `tcgdexID` attribute.
  - `PriceRecord.unitMarketPriceUSD` is a legacy slot that may hold native-currency values; `currencyCode` qualifies it. Valuation must use `effectiveUnitMarketPriceUSD`.
- New persisted properties need defaults (CloudKit-compatible: optional or defaulted, no unique constraints). Uniqueness of `collectionKey` is enforced in code by `CollectionStore`, not by the store.
- Treatment, provenance, and game identifiers are stored as strings for forward compatibility. Preserve unfamiliar raw values; never coerce them into a known case.
- When adding a persisted type, decide which store it belongs in. The schema partition (synced ownership vs. local pricing/artwork) lives in `Services/CollectionStorageBootstrap.swift`; update it and the [CloudKit compatibility audit](../../docs/release/cloudkit-compatibility-audit.md) together.

## Identity

- Keep printing identity, finish, print run, treatment, graded identity, and sealed-product identity distinct. A Magic named foil treatment and ordinary foil must never collapse onto one price record.
- Build keys with the existing identity builders and accessors. Do not assume a provider ID alone identifies a physical printing.

## Money and time

- Use `Money` and `PortfolioPriceEligibility` for valuation. An unavailable or ineligible price must stay distinguishable from a real zero.
- Keep provider data time (`sourceUpdatedAt`), retrieval time, attempted-check time, and successful-check time as separate fields with separate meanings.

## Verification

`CollectionKeyTests`, `CardGameForwardCompatibilityTests`, `CloudKitSchemaCompatibilityTests` (and `scripts/audit_cloudkit_schema.sh` for schema changes), plus the persistence or portfolio suites for the field you touched (see [`../../TradingCardScannerTests/AGENTS.md`](../../TradingCardScannerTests/AGENTS.md)).
