# Scanner recognition and Needs attention remediation

**Status:** implemented, with code-review corrections in the 2026-09-25 working
tree based on `main@6747859f5e8c`. The current focused iPhone 17 Pro / iOS 26.5
simulator selection passes 229/229 tests with 0 skipped. The 1,561-pass / 7
skipped full non-centering result belongs to the preceding source-review
snapshot and was not rerun after these corrections. Exact evidence is recorded
in [`progress.md`](../../progress.md). Physical-device and Instruments
acceptance remain open.

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
Historical rows without a set are scoped to the scanner session, since two
physical cards from different sets can share a number and denominator. A
failure that merges into a row from an earlier session still counts in the
current session summary. When a user retries a row, another failure updates
that source row by UUID even when its session scope differs; unrelated
historical scans remain separate.

The title evidence for a historical number expires with its bounded OCR
attempt. When that attempt renews for the same number, title OCR starts fresh;
reusing old title readings could attach the first physical card's name to a
second card with the same number. This adjusts the earlier B3 proposal to keep
title readings across TTL renewal, based on the code-review finding about stale
OCR inheritance. Choosing a Pokémon candidate preserves the row's slab evidence
and resolves the exact chosen printing from the offline checklist before
falling back to historical catalog resolution.

Rows support catalog retry, save retry when the pending candidate remains in
memory, Pokémon candidate selection, catalog browsing, and dismissal. A
successful collection commit clears its source row and other rows with the
same suppression key or an explicitly resolved provider identity. Set-known
Pokémon rows clear by canonical local number, denominator, and exact set. A
set-unknown row clears by number and denominator only when the active registry
and checklist show exactly one possible set owner; candidate suggestions alone
never authorize clearing a row.
A Retry save clears its source row when the writer confirms that exact printing
is already in the collection, and it suppresses the duplicate without
incrementing quantity. Candidate selection or catalog lookup alone never
clears the row.

## Verification boundary

Source and simulator tests can verify the recognition and persistence rules.
They do not verify camera framing, physical card behavior, provider availability,
or performance. The 25-row write chunks bound a single transaction, but do not
guarantee fair lock handoff; the effect on lock waits remains unproven until the
device signpost comparison. The ASC stack, forced failure/relaunch actions, and the
`oneCardScan`, `twoFrameConfirmation`, `titleOCR`, `labelOCR`, and
`collectionWriteLockWait` Instruments comparison require a physical iPhone and
remain open until performed.
