# Minimum physical acceptance batch integration

**Status:** supplied 2026-10-12 package retained; 0/12 completed physical packets,
0/12 approved local-seed targets and 0/25 executed iOS acceptance scenarios.

The [original guide](source-package/README.md),
[12 specimen targets](source-package/minimum_specimens.json),
[individual evidence packets](source-package/evidence_packets/), and
[25-scenario execution matrix](source-package/scenario_execution_matrix.json)
come from `lorcana_minimum_physical_acceptance_2026-10-12.zip`. All 26 supplied
files are preserved byte-for-byte with their original
[checksums](source-package/SHA256SUMS.txt). The three JSON snapshots match the
[previously imported reference corpus](../README.md) exactly. Supplied research
claims and historic run logs remain provenance; their websites were not revisited
for this import.

The first batch selects three Hades size/finish instances, two Stitch reprints,
Elsa Enchanted, Dalmatian 4a and 4c, Motunui, 2022 D23 Mickey, Ursula's Contract
and Vine Entrance. It narrows acquisition priority, not the candidate universe
required for exact lookup. Mulan, ordinary Elsa, other Dalmatian artworks,
language/Challenge cases and the Cinderella D23 footer conflict remain in the
broader inventory. Scenarios needing deferred specimens remain blocked.

Published photographs, dimension references and finish claims are clearly
separated from the unfilled specimen observations. No photographs, physical
measurements, human approvals, permanent UUIDs, authorized finishes or signed
manifest are supplied. Historical notes about unavailable Xcode and checkout
access describe the package's preparation environment, not this repository.

## Local verification

The import replay passes all 23 offline source/inventory checks and all 16
Python evidence-precheck tests. Every physical packet is rejected as unapproved.
These checks do not invoke Swift, exercise the scanner or execute the iOS matrix.

From the repository root, replay without overwriting the retained historical
`offline_gate_results.json`:

```sh
cd docs/research/lorcana-real-card-corpus/minimum-acceptance/source-package
python3 -B -c 'import gate_audit; checks, packets = gate_audit.checks(); assert all(c["passed"] for c in checks); assert all(not gate_audit.is_approved(p)[0] for p in packets); print("PASS 23 offline checks; 0/12 packets approved")'
python3 -B -m unittest -v test_gate_audit
```

Running `gate_audit.py` directly rewrites its historical result file. Work on
copies when collecting new evidence. Its `is_approved` helper checks declared
field readiness only: it does not read image files, verify their hashes, validate
human signatures or establish physical catalog correctness. A successful
precheck cannot authorize signing or replace independent review and Swift
registry/transition validation.

## Next gate

Complete permissioned specimen captures and two independent reviews for each
target and its explicitly bounded full footer universe. Keep actual evidence
private with provenance and file hashes. Preserve held grammar, item-kind and
footer conflicts until reviewed. Only then construct approved schema-2 records
and use the isolated `LorcanaLocalReviewKit`, followed by the appropriate runtime
and device scenarios. The [implementation plan](../../../plans/lorcana_code_implementation.md)
retains acceptance authority; production Lorcana remains disabled.
