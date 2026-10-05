# Lorcana implementation plan

**Status:** recalibrated first slice implemented; 44 focused tests pass — 2026-10-04.
Workspace: existing `one-piece-integration` worktree, base `69c714f`, including
uncommitted One Piece infrastructure. The owner requested using this worktree;
the unused extra checkout was archived. No commit or production rollout is implied.

This is the current implementation authority. The [imported Lorcana research](../audits/lorcana-data-variant-scanner-architecture-audit.md)
remains source/background research, with nonportable original citations and
unverified release timelines. Current code and new evidence outrank that snapshot.

## Recalibration against the current code

| Earlier proposal | Current code / decision |
| --- | --- |
| Add Lorcana to closed game/scanner switches | `CardGame` is string-backed; recognition and catalog adapters already dispatch by game. Add a module under `Games/Lorcana`; no new scanner/catalog/UI switch cases. |
| Import every released set before a first usable checkpoint | Start with a validated local print-family snapshot and footer-to-incomplete-lookup path. Full provider ingestion and physical reconciliation are separate deliverables; fixtures cannot establish completeness. |
| Build another persistence or candidate picker | Reuse `ScanIdentifierSnapshot`, generic unresolved storage, physical-printing choices, `ResolvedCatalogCard`, and the compact Pokémon/Magic-style finish picker when exact printing evidence becomes available. |
| Treat a provider set code as a printed marker | Store provider set code independently. Require an explicit footer mapping with an evidence reference; API set metadata alone cannot establish a denominator or the physical footer. |
| Put stamps/artwork/oversized identity into finish variants | Follow the existing physical-printing boundary: distinct artwork, distribution, stamps and size normally require separate physical UUIDs. Finish varies beneath that exact printing only. |
| Optical foil classification in the early path | Preserve explicit finish selection. Optical classification is deferred until measured deterministic evidence can justify it; no foil inference from price fields or rarity. |
| Generic ingestion/signing/image embedding infrastructure | Reuse existing adapter and signed-storage mechanics later. No additional package, coordinator extraction, backend, embeddings, serial fields or generalized publisher is necessary in slice 1. |

[Lorcast's card API](https://lorcast.com/docs/api/cards) documents string collector
numbers, language, layout, set identifiers and `unique=prints`; its default
search grouping removes gameplay duplicates. Those provider fields are separate
from reviewed printed-footer evidence. Its normal/foil price fields do not prove
the complete set of supported physical finishes. The [set API](https://lorcast.com/docs/api/sets)
documents set codes and release metadata, and warns that pagination may be added.
These documents were read on 2026-10-04; no live corpus or release completeness
was validated for this slice.

## Slice 1: local print-family identity and recovery

Implement one bounded research path:

```text
explicit normalized local manifest
  → validated immutable Lorcana registry
  → complete footer evidence in one OCR observation
  → generic ScanIdentifier (printed-footer)
  → local print-family summary or unknown
  → catalogIncomplete
  → existing unresolved snapshot/recovery
```

`Games/Lorcana/LorcanaCatalogRegistry.swift` owns schema-1 manifests, validated
printed identities, source aliases and provisional family metadata. Numerator,
denominator/token, language and printed marker are separate strings. Premium
numerators may exceed the denominator; denominators and release tokens have no
hard-coded `/204` or set-number horizon. Rarity and layout remain open strings.
Family evidence keys are reproducible lookup keys, **never ownership keys or
physical UUIDs**, and do not imply gameplay equivalence across reprints.

Reject unsupported schema versions, invalid fields, duplicate footer identities,
reused provider aliases and oversized inputs. Require a footer mapping reference;
its presence records a review claim, not verified physical authority. Derive the
generation from normalized manifest content so metadata changes invalidate stale
lookups; ordering of families and aliases does not change that generation.
Lookup and vocabulary-scope validation use immutable dictionaries.

`LorcanaRecognitionAdapter` accepts the narrowly supported contiguous format
`number/denominator LANGUAGE marker` within one valid ROI-relative observation.
It does not combine fragments from unrelated lines, infer English, use names to
repair numbers or globally rewrite OCR text. Numeric `O/I/L` repair requires a
known language/marker scope; denominator repair additionally requires a matching
catalog numeric denominator and never rewrites an existing literal promo token.
Two distinct footer identities, including unknown numbers/markers/languages,
produce ambiguity; repeated identical evidence deduplicates. A complete unknown
footer remains recoverable evidence, without a closest-match fallback.

`LorcanaCatalogAdapter` validates the full payload, display and suppression key.
Lookup is pinned to the content generation. Explicit retry can rebase the same
printed evidence; unexpected fields or tampered evidence are rejected. All
families remain provisional physical evidence, so lookup returns
`catalogIncomplete(summary)` or `catalogIncomplete(nil)`. It never manufactures
an exact card or physical choice from a provider family ID.

`LorcanaGameRuntime` plugs into existing registration with research scan
capability only and an empty variant policy. Production `appDefaults` does not
register it. The standard descriptor supplies a display name only. Browse,
pricing, import enrichment, sealed products and collection writes stay disabled.
No schema changes to collection or unresolved records, provider requests, signed
seed, production configuration, keys, image redistribution or UI framework are
part of this slice.

### Slice 1 acceptance

- [x] Local manifest and content-derived generation; duplicate mappings fail closed.
- [x] Set code / marker separation, numerators above denominator, alternate denominators and promo tokens.
- [x] Generic runtime and catalog integration without central game switches.
- [x] Conservative complete-footer parser, ambiguity, unknown evidence, literal promo tokens and invalid geometry handling.
- [x] Generic recovery with installed module and read-only recovery without it; stale lookup and retry validation.
- [x] Production defaults, write capability, finish lock and pricing remain unavailable.
- [x] Focused app/test target checkpoint: 44/44 tests pass, including 13 Lorcana cases.
- [x] New plan links and whitespace checks; pre-existing missing audit/artifact links remain outside this slice.

These are fixture contracts. They do not prove real card accuracy, orientation,
ROI coverage, split-line OCR, printed separators, physical-size detection,
source completeness, device performance, rights or CloudKit compatibility.

## Subsequent slices

1. **Real source normalization and review corpus.** Bounded Lorcast DTO/import
   using all-print results; explicit pagination/continuation checks, retained
   source provenance and footer-to-provider mappings backed by permitted evidence.
   Ordinary/premium/reprint/promo/landscape/Quest/oversized stress records must be
   labeled accurately. Do not promote a source family to physical authority or
   freeze the research document's set/release list into code.
2. **Durable physical registry and exact local resolution.** App-owned UUIDs,
   retained aliases/corrections, artwork/distribution/stamp/size separation,
   evidence-backed finish lists and completeness review. Multiple physical
   candidates use the existing compact printing choice, followed by finish
   selection. Same-number oversized/standard cards cannot auto-resolve from the
   footer alone. No provider or artwork URL is an ownership identity.
3. **Signed local activation and measured camera support.** Reuse shared signed
   storage/transport and generation updates; dedicated Lorcana key namespace and
   disabled rollout until validated seed and delivery exist. Establish actual
   footer ROI/orientation, split-token association and typography support with
   real reference and device observations, retaining cross-game safety.
4. **Browse, import/export and ownership.** Use existing adapters and stable UUID
   keys. Enable writes only after unknown-game/mixed-client policy and direct
   collection-write boundaries are independently verified; inherit no readiness
   from fixture tests or the incomplete One Piece rollout.
5. **Exact pricing and optional optical assistance.** Reviewed exact mappings,
   finish/condition qualifiers and separate rights/provider gates. Withhold
   uncertain prices. Add candidate ranking or foil detection only if measured
   benefit and deterministic evidence justify the extra complexity.

## Verification evidence

`/private/tmp/lorcana-first-slice-checkpoint.log` records 44 passing cases:
13 `LorcanaIntegrationTests`, 27 `CardGameForwardCompatibilityTests`, and four
`ScanSubjectSuppressionTests`. The `TradingCardScanner-ProfileLocal` scheme with
`DebugRemoteLocal` built and tested against the existing iPhone simulator, using
the external SSD derived-data cache. The initial attempt stopped before
compilation because newly added project object IDs collided with existing
transport references; unique Lorcana IDs corrected that integration error. The
successful checkpoint includes the literal-promo-token normalization safeguard.
No unchanged tests were repeated after this successful checkpoint.

No full suite or physical-device, real-camera, provider, CloudKit, archive or
release certification was performed. No production default registration, keys,
catalog seed or sync enablement was added.
