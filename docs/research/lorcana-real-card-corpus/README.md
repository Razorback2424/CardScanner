# Lorcana real-card reference corpus integration

**Status:** supplied research package imported on 2026-10-12 at base `1e368b3`;
physical specimen review and Slice 2 acceptance remain open.

The [original review guide](source-package/README.md),
[29 reference records](source-package/lorcana_real_card_corpus.json),
[25 specified acceptance scenarios](source-package/acceptance_scenarios.json) and
[blank specimen evidence template](source-package/physical_review_evidence_template.json)
are retained from the user-supplied
`lorcana_representative_real_card_corpus_2026-10-12.zip`. All eight package files
are preserved byte-for-byte, including the supplied
[checksums](source-package/SHA256SUMS.txt). The 35 source references are supplied
research claims; this import did not independently revisit their websites.

All 29 candidates lack physical UUIDs, authorized finish IDs, specimen photos
and reviewer signoff. None permits activation. The research JSON is a separate
schema, not input to `LorcanaCatalogRegistry`, and is not bundled into app or test
resources. No provider alias joins, signing keys or catalog records were created.

The selection covers same-footer standard/oversized Hades and Mulan, cross-set
Stitch, five lettered Dalmatian artwork numbers, Quest `30/31 · EN · Q1`, and
the `207/207 · EN · 13` landscape case. The Cinderella D23 `2` versus `02`
discrepancy remains held until a printed specimen resolves it. These are review
targets, not certified physical observations or a complete printing inventory.

## Offline verification

Run from the repository root:

```sh
python3 docs/research/lorcana-real-card-corpus/source-package/validate_corpus.py
```

The structural validator checks references, expected identity boundaries and
inactive authority fields. It does not execute the 25 acceptance scenarios,
validate live source contents or approve physical evidence. The imported guide
lists 23 scenarios in its contents summary; the JSON contains 25. The original
`build.py` and `make_acceptance.py` use `/mnt/data/lorcana_real_corpus` and are
retained as provenance, not repository regeneration commands. Do not run them
against this retained checkpoint. The offline validator resolves its own folder
and needs no network access.

## Next physical acceptance gate

The follow-up [minimum acceptance batch](minimum-acceptance/README.md) now supplies
12 unapproved specimen targets, prefilled evidence packets and a mapping of all
25 scenarios. Its 23 offline checks and 16 Python tests pass locally; no physical
packet or iOS scenario is complete. Start with that narrower acquisition batch,
while retaining the full candidate-universe and deferred-case requirements below.

Follow the supplied guide's priority order, beginning with standard/oversized
Hades and Mulan and their separate finish specimens. Create one evidence packet
per specimen. Retain permissioned photographs privately, with exact hashes and
provenance; record literal footer, size, artwork/stamp, distribution and observed
finish. Two independent reviewers must approve the evidence and explicit
candidate-universe scope before permanent physical UUIDs and eligible finishes
are assigned. Keep unsupported item kinds and incomplete footer universes held.

Promote only an approved subset through the existing isolated debug
`LorcanaLocalReviewKit`, protecting predecessor identity and transition history.
The [implementation plan](../../plans/lorcana_code_implementation.md),
[physical contract](../lorcana-physical-contract.md) and
[signed activation contract](../lorcana-signed-activation.md) retain implementation
authority. The [provider checkpoint](../lorcana-source-corpus.md) remains separate.
Production registration, pricing, shared sync and device acceptance remain open.
