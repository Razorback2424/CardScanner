# Lorcana signed local activation

**Status:** implemented locally; the signed-activation checkpoint recorded 129
focused simulator tests passing — 2026-10-12,
`feat/lorcana-implementation` at `9d7c780c` plus local changes. Physical evidence
in tests is synthetic. The [implementation plan](../plans/lorcana_code_implementation.md)
retains real-corpus, device, rights and production acceptance authority.

## Signed contract and protected updates

[`LorcanaCatalogRelease`](../../TradingCardScanner/Games/Lorcana/LorcanaCatalogRelease.swift)
wraps the schema-2 physical manifest in release schema 1, with exact game ID,
positive revision and generation time. Ed25519 verifies the exact payload bytes
before decoding. Sorted JSON keys and normalized manifest arrays define canonical
bytes; verification rejects alternate encodings, unknown fields and noncanonical
payloads even when their signature is valid. Payloads are bounded to 8 MiB and
disk/transport envelopes to 12 MiB. Release time may be at most five minutes ahead
of verification time and cannot precede physical review time.

Trust pins must use the `lorcana-` namespace. Duplicate public material and
explicitly supplied keys belonging to other domains are rejected. There are no
committed private keys, production pins, hosted releases or automatic production
configuration. Signature validity authenticates a review claim; it cannot establish
whether a synthetic reference depicts a real physical card.

[`LorcanaCatalogReleaseStore`](../../TradingCardScanner/Games/Lorcana/LorcanaCatalogReleaseStore.swift)
wraps shared two-slot persistence using its own filenames/cache directory. Lower
revisions reject; equal revisions require the same pin ID and canonical payload
after independent signature verification. Re-signing identical content does not
collide; changing its content or signing pin does. Higher revisions
validate against the actual durable predecessor inside the shared actor transaction.
Prior printing/canonical UUIDs, physical identity, aliases, correction history,
identity references, canonical relationship references and finish evidence remain
protected. Metadata can change and supported finishes can be added with evidence.

Correcting physical identity or removing an erroneous finish requires explicit
supersession: retain the old UUID and its evidence, add a new reviewed UUID and a
correction edge, and replace the active universe membership. The old UUID loses
acquisition/finish-correction authority. This never migrates collection rows or
history. Alias reassignment between footer families remains unsupported pending
a separately reviewed correction design; it cannot be smuggled through metadata.

Lorcana opts into predecessor validation during disk recovery. Independently
verified previous/current slots must respect revision, collision and transition
rules relative to the prior valid slot or validated seed. A corrupt or rejected
current slot falls back to a valid previous slot, then the seed. Atomic-write
failures retain the old published head; a reported error after a committed write
is reconciled only through exact persisted bytes. Other games retain their existing
recovery policy.

## Coherent runtime publication

[`LorcanaCatalogCoordinator`](../../TradingCardScanner/Games/Lorcana/LorcanaCatalogCoordinator.swift)
implements the existing activation source and emits bounded latest-value streams.
Each snapshot creates catalog, recognition and variant adapters from one immutable
registry. Only a successfully persisted head is published, and concurrent callers
cannot reinstall a lower revision after an await. Metadata-only edits change the
content generation, preserving UUIDs while rejecting old choices/completions.

Explicit runtime injection binds through `CardGameRuntimeContainer.bound(to:isCurrent:)`.
Its collection-authorized wrapper installs validation authority before publication
and refuses retired storage sessions. Existing scanner consumers install recognition
between frames and rebase footer evidence only on explicit retry; a printing choice
must be made again. Slice 4 now includes local Browse and import adapters in the
same immutable snapshot; pricing remains a future slice.

The domain HTTPS client uses the existing bounded, redirect-refusing conditional
transport. Remote mode defaults to disabled. Validation-only mode never persists
or publishes a remote release; rejected responses clear conditional validators.
Launch refresh runs once, with concurrent refresh requests coalesced.

[`LorcanaLocalReviewKit`](../../TradingCardScanner/Games/Lorcana/LorcanaLocalReviewKit.swift)
is compiled only with `DEBUG && LOCAL_ONLY_SIGNING`. Its explicit factory requires
a supplied physical manifest and isolated cache root, generates an ephemeral key,
signs and verifies the seed, and returns a read-only scan/Browse runtime/coordinator.
It never fetches and is absent from production defaults. Slice 4 adds explicit
`allowCollectionWrites` opt-in: `bound(to:isCurrent:)` checks every actual model
configuration for writable in-memory storage or a store beneath the kit's isolated
review directory, without a CloudKit container identifier, before returning a
writable bound runtime. The public unbound runtime stays read-only. This remains
an injection API; a rendered review launch and real reviewed seed are still open.

## Verification and open gates

[`LorcanaCatalogActivationTests`](../../TradingCardScannerTests/LorcanaCatalogActivationTests.swift)
cover signatures/canonical bytes, trust, schema/time/bounds, revision rules,
protected updates/supersession, disk recovery/write faults, concurrency, immutable
publication, validation-only transport behavior, container rebinding/retirement,
stale in-flight completions and scanner/recovery activation.

The final app/test build and 129/129 cases pass with no failures/skips, including
23 new activation cases and Lorcana/shared-store/shared-transport/One Piece
regressions. `activation-final.xcresult`, full/selected prepared packages, logs,
derived data and dependency cache remain under the external SSD's
`CodexBuilds/LorcanaImplementation-20261012/`. Selected packaging retains all app
resources and tested fixtures/code, omitting only unused test assets. One internal
QoS warning remains in a write-fault test. The [plan's checkpoint](../plans/lorcana_code_implementation.md#signed-local-activation-checkpoint--2026-10-12)
records fixture corrections, failed installer attempts, preserved QA app data and
the restored runtime directory; no simulator was erased.

Real physical corpus acceptance, selected-corpus activation time/memory, rendered
UI/device/camera evidence, production key custody/hosting/rights, production
ownership/Browse/import, exact pricing, CloudKit and release acceptance remain open.
The implementation plan records Slice 4's separate local ownership checkpoint.
