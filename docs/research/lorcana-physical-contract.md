# Lorcana local physical-printing contract

**Status:** schema-2 contract and exact-resolution code implemented; 82 focused
simulator tests pass — 2026-10-12, `feat/lorcana-implementation` at
`9d7c780c` plus local changes. All physical review examples in tests are
synthetic. The [implementation plan](../plans/lorcana_code_implementation.md)
retains real-corpus and production acceptance authority.

The later [normal pricing rollout](lorcana-normal-pricing-rollout.md) adopts this
contract for public-source-reviewed ordinary printings in normal app registration.
The synthetic test checkpoint below remains dated evidence, not current coverage.

## Identity and evidence

[`LorcanaPhysicalCatalog`](../../TradingCardScanner/Games/Lorcana/LorcanaPhysicalCatalog.swift)
adds a versioned local manifest containing canonical-card UUIDs, permanent
physical-printing UUIDs, footer families, physical records, exact candidate
universes and correction history. Schema-1 families still cannot resolve owned
printings. Provider set codes, aliases, names and image URLs remain metadata;
they cannot allocate physical UUIDs or substitute for footer/finish evidence.

Each physical identity protects canonical membership, footer/language, artwork
UUID, distribution ID, stamp or explicit absence of a stamp, size and layout.
Presentation labels and URLs remain separate. A verified record needs explicit
footer, artwork, distribution, stamp and size references, nonempty finish evidence
and a finish-universe reference. This contract supports `normal` and `foil`
finish IDs; unknown future finish strings reject decoding rather than narrowing
the finish universe silently. A reference records a review claim; fixture labels
or an unsigned manifest do not prove physical authority.

Every declared footer universe lists all active records for that footer,
including provisional and conflicted records. An omitted candidate rejects the
manifest. An absent/incomplete universe, unverified record or conflicting
canonical membership leaves catalog lookup incomplete. The contract bounds
record counts, strings, references, candidate lists and correction graphs; JSON
entry points retain the existing 8 MiB limit.

## Exact lookup and choice

[`LorcanaCatalogAdapter`](../../TradingCardScanner/Games/Lorcana/LorcanaGameRuntime.swift)
uses the existing recognizer, neutral printing candidates, resolved-card type,
compact choice/Details comparison and finish resolver. It adds no central game
cases or new UI framework.

| Installed physical evidence | Result |
| --- | --- |
| Schema-1 family or unknown footer | Existing incomplete summary/recovery. |
| Complete universe with one verified standard-size record | Exact app-owned UUID; supported finishes then drive the existing finish resolver. |
| Standard/oversized, stamp, artwork or distribution alternatives | Explicit physical-printing choice with reviewed labels/artwork before finish choice. |
| One verified oversized record | Explicit size choice; footer OCR does not establish physical size. |
| Incomplete universe, unreviewed/conflicted candidate, missing finish evidence or conflicting canonical membership | Incomplete lookup or invalid manifest, never uniqueness derived by dropping records. |
| Indistinguishable alternatives without available artwork distinctions | Incomplete lookup; different hidden UUIDs cannot supply a visible distinction. |

Candidates retain their generation, exact metadata and visible size/stamp/layout
details. Resolution rejects cross-game, stale or tampered choices. The existing
artwork-selection guard handles loading and availability; label distinctions
remain usable without image downloads. Acquisition is revalidated against the
same current complete universe; automatic acquisition additionally requires a
single standard-size record. Choice resolution never becomes a cached default
for the footer or another encountered copy.

The variant menu is the union of verified printings' reviewed finishes. It is not authority
to change every printing: `validateVariantCorrection` requires an exact installed
printing and its supported finish, rejecting unknown/nil/case-altered values.
An already known verified UUID retains its finish authority when footer discovery
is incomplete; this does not establish uniqueness for acquiring another card.
Provisional, conflicted and superseded UUIDs remain ineligible for correction.
Physical size, artwork, stamps and distribution distinctions remain separate
UUIDs, not finish IDs. Collection keys use `lorcana:<physical-uuid>#<finish>`.
Stable set grouping uses footer language/marker/denominator independently from
the provider set code and distribution channel.

## Promotion and corrections

Schema-1 → schema-2 promotion preserves footer evidence and retained source
aliases. Explicit retry changes the generation while retaining the identifier
fields and suppression identity. Recovery encounter UUIDs and printing choices
continue through the generic unresolved store; missing-module recovery is
read-only. No family key is rewritten as an owned physical UUID.

Construction with `previous:` validates transitions. Permanent printing and
canonical IDs remain present, physical identity cannot mutate under an existing
UUID, source aliases and finish IDs remain retained, and existing identity,
finish and canonical relationship evidence/correction history cannot disappear.
Adding metadata, aliases or a
supported finish changes generation while preserving existing ownership keys.

A corrected identity requires a new printing UUID and a reviewed correction edge.
The old record remains superseded with its original identity/evidence. Cycles,
dangling corrections, missing history and resurrection of superseded rows are
rejected. Corrections do not automatically migrate collection rows or history.
The [signed activation contract](lorcana-signed-activation.md) now supplies the
actual durable predecessor for update validation and protects recovery against
the verified previous slot or seed. Standalone construction remains an explicit
local/bootstrap path.
Schema-2 → schema-1 downgrade with a previous registry is rejected.
This bounded contract retains alias and finish declarations; it does not silently
reassign aliases between footer families or withdraw a declared finish. Those
finish discrepancies require explicit supersession with retained evidence and
a new reviewed UUID. Cross-family alias reassignment still needs a separately
reviewed correction design. Neither silently reinterprets existing UUIDs.

Generation incorporates all normalized metadata and review semantics. Ordering
families, aliases, canonical cards, finishes, references, printings, universe
members and corrections does not change it. Metadata-only edits still reject
stale in-flight results and saved choices.

## Verification and remaining work

[`LorcanaPhysicalCatalogTests`](../../TradingCardScannerTests/LorcanaPhysicalCatalogTests.swift)
exercise real recognizer input → exact lookup/physical choice → supported finish,
size/stamp/artwork distinctions, incomplete/unreviewed universes, tampered/stale
choices, transitions/corrections, stable keys, cross-set grouping and relaunch
recovery with/without the module. These are synthetic contract tests. The final
app/test build and prepared-package simulator run pass all 82 selected cases:
22 physical-catalog, 13 Lorcana integration, 12 source-normalization, 31 forward
compatibility and four suppression tests, with zero failures/skips. Project
syntax, links and whitespace checks also pass.

The final external SSD artifacts are `physical-final.xctestproducts`,
`physical-final-build.log` and `physical-final.xcresult` under
`CodexBuilds/LorcanaImplementation-20261012/`. Verification initially encountered
internal disk exhaustion in the wrapper's test-package copy. Only this task's
generated packages were relocated to the SSD. Intermediate invocations were
interrupted while buffered output obscured progress; a prepared attempt had 52
passes and one canceled test. The next complete replay had one failing fixture
whose textual JSON edit left an escaped footer unchanged. Field-based mutation
fixed it, and the final 82/82 run verifies actual candidate tampering rejection.
One internal QoS warning remains in the result; no device performance claim is
made. No simulator data was erased and the main simulator was untouched.

The [provider source inventory](lorcana-source-corpus.md) still contains metadata
observations, not reviewed physical records. A permitted real-card corpus with
footer, finish, stamp, size and candidate-universe evidence remains required.
No real physical seed or production configuration is added. Signed activation,
Browse/import, local ownership acceptance, pricing, camera/device measurements,
rights, CloudKit policy and release gates remain open. Production defaults still
omit the Lorcana runtime; the explicit research runtime has only scan capability.
