# CloudKit Compatibility Audit

Status: local source gate passed; entitled construction and Development /
Production CloudKit inspection are blocked until the approved App ID and
container are enrolled.

The public 1.0 structured configuration is limited to five synced models:
`CollectedCard`, `PriceRecord`, `ProductIdentity`, `CollectionActivity`, and
`InventoryEvent`. Device-local quote, observation, close, and artwork models
are not related to those records and remain outside the CloudKit configuration.

| Model | Stable application identity | Unique constraint absent | Relationships optional | Explicit inverse | Delete rule | Cross-configuration relationship absent | Defaults/optionality | Duplicate reconciliation owner | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `CollectedCard` | `collectionKey` plus application identity rules | Yes; enforced by `CollectionStore` | Yes for `activityBackfillAnchor` | `activityBackfillAnchor` ↔ `backfillAnchorCard` | Optional relationship nullifies | Yes | Existing defaults; optional provider/grade/artwork fields | `CollectionStore` / catalog normalization | PASS — source review; runtime pending |
| `PriceRecord` | `key` | Yes; enforced by `PriceStore` | N/A | N/A | N/A | Yes | Existing defaults and optionals | `PriceStore` authoritative duplicate reconciliation | PASS — source review; runtime pending |
| `ProductIdentity` | `key` | Yes; enforced by `ProductIdentityStore` | N/A | N/A | N/A | Yes | Existing defaults and optionals | `ProductIdentityStore` | PASS — source review; runtime pending |
| `CollectionActivity` | UUID `id` | Yes; no CloudKit uniqueness constraint | Yes for `backfillAnchorCard` | Explicit inverse with `CollectedCard` | Optional relationship nullifies | Yes | Existing migration-safe defaults | Activity/ledger write boundaries | PASS — source review; runtime pending |
| `InventoryEvent` | `idempotencyKey` plus `eventID` | Yes; application dedupe | N/A | N/A | N/A | Yes | Existing defaults and optionals | `InventoryLedger` | PASS — source review; runtime pending |

## Relationship facts

- `CollectedCard.activityBackfillAnchor: CollectionActivity?` is optional.
- `CollectionActivity.backfillAnchorCard: CollectedCard?` is optional.
- The inverse is explicit on the `CollectedCard` side and must be verified by
  runtime behavior before schema promotion.
- The other three synced models currently have no relationships.
- No synced model relates to `ReferenceQuote`, `PriceObservation`,
  `PriceCheckDay`, `PortfolioDailyClose`, or `LocalArtworkOverride`.
- Raw-card condition is not persisted in the 1.0 schema. Provider listing/SKU
  condition text must not be represented as owned-copy condition.

## Required gates

- `scripts/audit_cloudkit_schema.sh`: source prohibition audit.
- `CloudKitSchemaCompatibilityTests`: local schema construction and
  application-identity checks.
- Entitled host construction: `BLOCKED — external enrollment`.
- Development private schema inspection and promotion: `BLOCKED — external
  enrollment`.

The absence of a uniqueness constraint is intentional. CloudKit does not
support SwiftData uniqueness constraints for this configuration, so duplicate
rows are reconciled by application code and unequal payload collisions fail
closed rather than selecting a winner silently.
