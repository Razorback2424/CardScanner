# Executable coverage and honest boundaries

## Executed in this environment

- Original mounted corpus: `python /mnt/data/lorcana_real_corpus/validate_corpus.py` — **PASS**, 29 candidate records, 35 linked sources, 25 unexecuted original scenarios.
- `python gate_audit.py` — **PASS 23/23** independent source/inventory/negative-activation assertions on the twelve new targets and 25 scenario mappings.
- `python -m unittest -v test_gate_audit.py` — **PASS 16/16** Python offline review-gate tests. In particular, retailer finish claims, public in-hand photographs, a claimed UUID or a single reviewer cannot promote an unverified printing.

These do **not** call Lorcana Swift code. No scanner simulator acceptance was performed; no real physical specimen measurements/approvals were obtained. This is a genuine execution of source-review and safety gate checks, **not** the requested end-to-end app acceptance.

## Blocked in this environment

- `0/12` verified physical specimens and independent two-reviewer signoffs;
- `0/12` newly signed/activated schema-2 records;
- `0/25` original iOS acceptance scenarios executed;
- no macOS `/Users/...` checkout mounted, no Xcode/iOS simulators/device, no signed local seed.

This package is deliberately unsuitable for loading into the production runtime. `minimum_specimens.json` is a *research target selection*, not a Lorcana manifest or signed release. Do not directly transform its published finish candidate strings to authorized variant IDs or its temporary MIN-XX research slot IDs into permanent ownership keys.
