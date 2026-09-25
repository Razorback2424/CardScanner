# Scanner recognition and Needs attention remediation

**Status:** implemented in the 2026-09-24 working tree and reviewed against the
plan on 2026-09-25. The focused simulator selection passes 227 tests and the
full non-centering suite passes 1,561 tests with 7 skipped; exact evidence and
result bundles are recorded in [`progress.md`](../../progress.md). Physical
device and Instruments acceptance remain open.

## Recognition rules

When the scanner reads a Pokémon collector number but misses its set code, it
may infer a modern expansion only when the official denominator has exactly one
owner in the active checklist/registry and that owner is a scan-enabled
expansion with a printed code. The inference produces the same set-code
identifier as a direct footer read. The bundled seed has no manifest counts, so
it cannot infer a set before the checklist is loaded. The current unique owners
include PAL, OBF, PAF, TWM, SCR, SSP, ASC, POR, and PBL; shared denominators stay
on historical resolution.

An inferred card is committed only when its resolved Pokémon name agrees with
the title OCR. Name comparison uses catalog identity normalization first,
accepts an exact match or the same name with spaces/punctuation removed, and
otherwise uses Damerau–Levenshtein distance at most 1 for 5–7 character names
or at most 2 for names of 8 or more characters. Names shorter than five
characters never use fuzzy matching. Catalog resolution still requires one
unique provider identity.

## Needs attention storage

Every collection scan failure is filed immediately. Rows live in the local-only
`Application Support/Scanner/unresolved-scans.json` file, which is excluded
from iCloud backup and capped at the newest 50 rows. The saved record contains
identity and OCR evidence plus candidate provider IDs and names; it does not
contain collection or pricing data. Graded-scan records also preserve the slab
label identity evidence needed to retry without downgrading a graded card into a
raw card. A row remains available across Scan-tab departures and app relaunches
until it is resolved or dismissed. If its saved identifier cannot be
reconstructed from the active catalog definitions, it is read-only and can be
dismissed.

Rows with the same suppression key merge their title evidence and candidate
identities, while the latest failure reason controls which recovery action is
shown. A direct set-code read remains authoritative when merged with an
inferred read, so that row does not acquire the inferred-only name gate.

Rows support catalog retry, save retry when the pending candidate remains in
memory, Pokémon candidate selection, catalog browsing, and dismissal. A
successful collection commit clears rows for the same provider identity or a
matching Pokémon local number and denominator when its set is unknown or equal.

## Verification boundary

Source and simulator tests can verify the recognition and persistence rules.
They do not verify camera framing, physical card behavior, provider availability,
or performance. The ASC stack, forced failure/relaunch actions, and the
`oneCardScan`, `twoFrameConfirmation`, `titleOCR`, `labelOCR`, and
`collectionWriteLockWait` Instruments comparison require a physical iPhone and
remain open until performed.
