# Unverified Pokémon variants: synced in collection (beta)

**Status — 2026-11-13:** design revision 5, with the implementation decisions
below. Report creation is built and enabled in DEBUG builds only
(`UnverifiedReportsFeature`). It must stay off for beta users until the
release gates in [Release gates](#release-gates) pass. Simulator unit tests
only; no device, CloudKit or TestFlight evidence yet.

## Status

| Area | State |
| --- | --- |
| Report model, key markers, fail-closed protection | Implemented, unit-tested |
| Price isolation (unverified rows never priced) | Implemented, unit-tested |
| Guards: merge, canonicalization, normalizer, finish repair, refresh targets, finish correction | Implemented, unit-tested |
| `addUnverified`, `moveAcquisitionToReport` | Implemented, unit-tested |
| Evaluator and reconciler | Implemented, unit-tested; runs on catalog load and activation while the scanner is active |
| Link and undo (dated ledger corrections) | Implemented, unit-tested at ledger level |
| CSV export | Keeps the report in an `unverified_report` column (only when the export contains a report row) |
| CSV import | **Temporary:** report rows are refused as failed entries, never merged. Restore is not built |
| UI | Receipt "Report a different variant", failed-scan "Add unverified card", collection detail status and "Undo link". Not yet visually verified |
| Review screen for reports needing confirmation | Not built — required before beta |
| Reconciliation at launch and on synced-row arrival | Not built |
| Portfolio replay verification of link chronology | Not built (ledger inputs are tested) |
| Linked-row grouping, "+N unverified" note, 60-day flag | Not built (lower priority) |

## Context

Beta testers own Pokémon cards whose variant, or whole set, isn't in the
catalog yet. They need to record them in the synced collection. These cards
are marked **Unverified**, carry no price, and are protected from automatic
guesses. When the catalog catches up, each card links to its verified identity
without losing quantity or history, and without creating duplicates.

Decisions:
- Unverified cards are synced `CollectedCard` rows. `UnresolvedScanStore` keeps
  handling failed scans only.
- Unknown sets are entered by hand from the failed-scan screen. The parser is
  not changed.
- A card links automatically only on genuinely new, unambiguous catalog
  evidence. Anything else goes to review.
- Report holdings stay separate from ordinary verified holdings. A link never
  merges rows.

## Implementation decisions (2026-11-13)

These refine revision 5 and are what the code does.

1. **Ledger: dated corrections, never rewrites.** A link appends one two-leg
   `.correction` operation per acquisition claim, dated `linkedAt`, from the
   unverified key and price key to the linked key and the verified price key.
   Each correction's operation ID is appended to its claim's
   `ledgerOperationIDs`, so later removals and undo validate through the
   existing `preflightLineage`. Existing ledger events are never edited.
   Activities move with the row (as `recordVariantCorrection` already does).
2. **Undo writes the opposite corrections.** It does not reverse the link
   operations: a reversed operation fails lineage validation, which would block
   every later removal. The report records `unlinkedAt` and never links
   automatically again; it waits for review.
3. **Strict link eligibility (beta).** A report links or unlinks only when every
   acquisition claim is intact (`resolvedQuantity == 0`), each claim's lineage
   validates under the row's key, the claims sum exactly to the row's quantity,
   no other activity changed the quantity, and the ledger nets to that
   quantity. Otherwise the report stays unverified, with review state
   `linkUnavailable`. Consequences: a removed or undone copy, or a stepper
   adjustment (`quantityAdjusted` is not an acquisition claim), blocks the
   link. Removal snapshots therefore never need identity rewriting in beta.
4. **Creation evidence is stamped by the write, not the caller.**
   `catalogRevisionAtCreation` and `knownVariantIDsAtCreation` come from the
   catalog the serialized write validated against.
5. **Key markers** are `~unverified=<id>` and `~report=<id>`. `~` appears in no
   other collection-key grammar.
6. **CSV import refuses report rows** (`CollectionCSVError.unverifiedReportImport`)
   and excludes report rows from import alias indexing. This is a temporary
   safety measure; restore through `addUnverified` / `restoreLinkedReport` is
   still required.
7. **Finish correction refuses report rows** (`reportRowProtected`). Only the
   report flow changes a report row's identity or finish.

## Design (revision 5)

### State: a marker in the key, details in JSON
- Unverified rows use `<base>~unverified=<reportID>`; `isUnverified` is read
  from the key, so protection never depends on decoding. Every unverified row
  uses `providerID = "unverified:<reportID>"`.
- Linked rows use `<verifiedKey>~report=<reportID>`. `hasReport` is true for
  either marker.
- `CollectedCard.unverifiedReportJSON` decodes to `UnverifiedReport`: schema
  version, report ID, kind (`knownCard` / `unknownSet`), reported finish,
  stamps, subtype, note, the observed set/number/name for unknown sets,
  `createdAt`, `catalogRevisionAtCreation`, `knownVariantIDsAtCreation`,
  `lastEvaluatedCatalogRevision`, review state, `linkedAt`, `unlinkedAt`,
  `preLinkIdentity` (everything undo needs) and `linkOperationIDs`.
- The JSON stays on the row after linking. If it won't decode: an unverified
  row stays protected and unpriced; a linked row stays verified and priced and
  offers no undo.
- Provenance: unverified rows use `.userConfirmed`; automatic links use
  `.linkedFromReport` (not automatic) and always carry a finish; links with no
  finish happen only by user confirmation and use `.userConfirmed`.

### Unpriced while unverified
While `isUnverified`, `priceStorageID` is `unverified:<reportID>`, the alias
keys are empty and `PriceRefreshTargets` skips the row. After linking, price
identity comes from `providerID` and the variant; the key suffix does not
affect pricing.

### Automatic boundaries
- Any report row: never merged, rekeyed or stripped of its marker
  (`mergeCollectionRows`, canonicalization/identity repair, CSV merge).
- Unverified rows also: no automatic identity, finish, price or marketplace
  change (`CollectionCatalogNormalizer`, the `repair` caller, CSV enrich).

### Adding cards
`addUnverified` uses the serialized write, quantity limits, an acquisition
activity and an unpriced ledger acquisition. A known card passes
`validatePokemonAcquisition` with no finish. Entry points: receipt "Report a
different variant" (`moveAcquisitionToReport`, blocked for a partly consumed
acquisition), failed-scan "Add unverified card" (unknown set, prefilled from
the scan).

### Reconciling against the catalog
Evaluation is read-only and skips reports already evaluated at the current
revision. Auto-link requires: a newer revision than at creation; a known-card
report with no note; exactly one catalog variant matching the structured
fields; and that variant absent from `knownVariantIDsAtCreation`. Review is
needed for an ambiguous or missing match, "Other"/notes, unrecognized
subtypes, a match the catalog already had, a previously undone link, and any
unknown-set report whose set and number now resolve.

`linkUnverified` re-reads the row, stops if the report bytes or the active
revision changed, re-checks the evaluator's decision for automatic links, and
validates the target with `validatePokemonAcquisition`, all inside one
serialized write. Applying the same link twice is a no-op.

### Preservation
- Removal snapshots carry `unverifiedReportJSON`; restore keeps the key.
- CSV: see implementation decision 6.
- Round trips through pre-feature builds lose the report (documented, not
  supported).

## Release gates

All required before the feature is enabled for beta users:

1. Local migration test on an existing collection.
2. Initialize the new field in the CloudKit development container, then
   deploy the schema to CloudKit production.
3. Two-device TestFlight test of competing offline operations, then
   reconnect: both devices link the same report; one links while the other
   changes quantity; one links while the other removes a copy. Pass when both
   devices agree on report state, quantity, activity history and ledger
   totals, with nothing silently dropped.
4. A pre-feature build against the new build must not strip markers, set
   finishes or merge marked rows. Expire earlier TestFlight builds before
   enabling.
5. The review screen, CSV restore and portfolio replay verification are
   complete.

## Verification so far

`UnverifiedReportTests` (23 tests) covers the model, markers, price isolation,
acquisition, the automatic-processing guards, removal snapshots, link and undo
with dated chronology at the ledger level, link eligibility, stale reports,
unknown-set links, unreadable linked reports, CSV export and import refusal,
"Report a different variant", the evaluator and the reconciler. Run results are
recorded in [`progress.md`](../../progress.md).
