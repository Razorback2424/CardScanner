# Next slice: One Piece camera acquisition and relaunch

**Status:** signed ordinary device build/install completed; physical-camera
acceptance pending an unlocked phone and owner physical sample.
**Execution checkpoint:** 2026-10-06, clean `3fe972a` before evidence-document
updates; [device record](one_piece_device_review.md) holds the results and blocker.
**Reviewed:** 2026-10-06, `merge/one-piece-integration` at `230a55f` plus the
existing seven modified files. This planning pass preserves those changes.
**Execution authority:** [One Piece implementation ledger](one_piece_code_implementation.md).
**Parent gates:** [release acceptance](one_piece_release_acceptance.md) and
[normal installed app](one_piece_device_review.md).

## Selection and intended outcome

The next slice is a bounded physical-camera acceptance pass in the owner's
ordinary app and existing collection: present an English One Piece card, resolve
only the distinctions that need a choice, acquire exactly one intended copy, and
retain the exact printing/finish after process relaunch and offline launch.

This follows the latest existing-save checkpoint rather than the older
supersession queue. The ordinary catalog, compact printing choice, exact pricing,
Browse/CSV integration and local recovery already exist. The latest recorded
affected simulator selection passes 380/380, including five disk-backed
failure/retry tests; those results are recorded evidence, not tests rerun during
this planning pass. The retained registry has no corrections. Building speculative
supersession is explicitly owner-deferred until an actual owned correction exists.

| Other candidate | Why it follows this slice |
| --- | --- |
| More One Piece physical coverage | Important, but first establish that the existing reviewed records work through a real camera and survive reopening. Expand held/special records in separately reviewed batches. |
| Lorcana Slice 2 | Its real corpus and exact physical resolution remain unfinished. It is a separate expansion; the current One Piece execution authority prioritizes acceptance of the owner's existing flow. |
| Legacy Browse/import extraction | Remaining architecture work, without a reproduced blocker for this bounded flow. Preserve the existing behavior and adapter seams. |
| Production signing/hosting, live pricing, CloudKit | Separate gates with their own rights, key, provider and multi-device prerequisites. |
| General historical Magic | General recognition/printing choice is implemented; device acceptance remains separate. Its old per-card pilot queue is historical. |
| Centering and broad performance work | Governed by their own active evidence plans; unrelated to proving One Piece acquisition durability. |

This choice is a recommendation for the current branch, not a claim that the
repository has one complete, globally ordered backlog. Protect accuracy by
stopping on wrong identity or quantity; establish speed by recording observed
timings; evaluate usability through the real printing distinctions.

## Scope and limits

- Start on one available owner iPhone, normal `TradingCardScanner` scheme,
  `Debug` configuration, `com.seankeller.CardScanner`, ordinary storage and Home
  Screen launch. Use Raw cards and Collection purpose, with finish locks on Auto.
- Begin with one physically owned, exactly matched starter or booster. Expand
  only after that acquisition survives relaunch.
- Exercise mapped/unmapped finishes, ST11/ST16 same-number choice, continuous
  visibility, skip/retry, one held-number recovery and offline reopening.
- Use at most six selected physical printings. Repeated presentations are logged
  separately from unique printings. Substitutions require a reviewed UUID,
  physical release/treatment match and expected finish/price policy before use.
- No app uninstall, storage reset, separate review identity, collection export,
  automatic cleanup, production rollout or new catalog promotion is part of this
  slice. Intended acquisitions remain in the owner's collection.
- Hardware availability and physical samples are execution dependencies. An
  unavailable case stays pending; a simulator substitute does not close it.
- Do not introduce instrumentation, a new harness or a persistence layer before
  evidence identifies a need. No application code change is planned initially.

The current source and bundled catalog both contain 2,490 verified, 224
provisional and 31 conflicted printings. **None of the verified printings has
multiple supported finishes.** A physical test therefore checks automatic sole
finish assignment. The shared multi-finish picker remains covered by
`testSolePrintingStillAsksForMultipleFinishes`; do not alter catalog evidence to
manufacture a hardware test. Held artwork with a number that also has a verified
printing is not the no-acquisition control: the owner-approved sole-candidate
policy does not establish coverage of every physical treatment or OCR language.

## Preparation and candidate identity

1. Recheck `git status --short` and relevant diffs. Record branch, HEAD, build
   configuration and a digest of the actual reviewed diff. Do not identify this
   working tree as the clean `230a55f` candidate or commit changes without a request.
2. Confirm the existing app opens its existing collection and that One Piece is
   available. Record aggregate collection count and each selected row's starting
   quantity, including absent rows as zero. Keep unrelated row details private.
3. Use the existing installed build if its candidate identity is known and
   appropriate. Otherwise build/install an in-place ordinary Debug update after
   confirming bundle identity, signing and storage selection. Do not use
   `-one_piece_local_review` or `-ui_debug_route OnePieceAcceptance` for hardware
   acceptance: they select developer storage, and the latter never starts the camera.
4. Put builds, derived data, caches and private evidence on the available external
   SSD. Inspect available capacity before building; use internal temporary storage
   only if no external SSD is available. Choose a new task directory rather than
   overwriting prior evidence. Prefer Xcode's device destination to putting device
   IDs in docs.
5. Record device model/OS, app version/build, launch arguments, signed envelope
   revision/hash and sample manifest. The current bundled owner envelope is
   revision 1, generated `2026-10-05T18:22:16Z`, SHA-256
   `6d81d20019d97269c32738bf941b87f27edf1978f3293ada7166bc629624efce`.
   Recompute at execution time. Its registry equals the retained source after
   UUID-case and array-order normalization; their raw JSON hashes differ.
6. Reuse `scripts/prepare_one_piece_acceptance_samples.py` if a wider candidate
   manifest is useful. It refuses an existing output path. Its 50-card selection
   is preparation for the parent release gate, not a requirement to acquire 50
   cards in this slice. Select only actually available physical matches.
7. Verify sample release/artwork/stamp/size/language against the physical card.
   Record any pre-existing quantities before scanning. Use the physical card,
   not a screenshot of a provider image, as camera acceptance evidence.

## Exact sample contract

These UUIDs and finish/mapping expectations were checked in both the retained
registry and bundled owner seed. A mapping permits an exact provider lookup; it
does not promise a fresh quote, amount or successful network response.

| Case | Physical match | Exact printing UUID | Finish / expected price authority |
| --- | --- | --- | --- |
| A | ST01-003 Karoo, ST-01 standard artwork | `dc3de4bd-5f24-4992-95a6-abb4844ef162` | Normal; exact mapping |
| B | OP01-120 Shanks, OP-01 standard artwork | `c629ad2f-7610-4449-87fc-20adc24ac228` | Foil; exact mapping; parallels/Manga are different samples |
| C | ST11-003 Backlight, original ST-11 release | `8d438939-46d2-497f-b4fa-8ba6c273232f` | Normal; exact mapping |
| D | ST11-003 Backlight, later ST-16 release | `3bc7c76c-baca-4b1b-bd31-7d4e7c2fc618` | Normal; no mapping; never borrow C's quote |
| E | ST01-012 Monkey.D.Luffy, ST-01 standard artwork | `3c334c55-6f0d-4e39-8b87-acb9b9f60334` | Foil; no mapping |
| F | ST01-005 Jinbe, held starter number | No eligible printing; retained provisional record | Needs attention; zero acquisitions |

Choose A or B for the first checkpoint. C and D require the corresponding
physical releases, not two copies of the same release. If E is unavailable,
P-001's verified English Super Pre-Release **winner** is an alternative unmapped
foil (`348ad90a-43d8-49b5-a384-4d9cc2a1fe27`); other P-001 treatments are not
substitutes. `OP01-999` remains a synthetic simulator control, not a real card.

## Execution sequence and acceptance

### 1. One-card vertical checkpoint

Present A or B in even light with the full raw card inside the guide. Record
time from stable presentation to recognized result, then to successful receipt.
Expect the sole verified printing and sole finish to acquire automatically;
there is no redundant printing confirmation or separate Save tap. Check the
receipt, collection detail and selected row's quantity delta of exactly +1.

Keep the same card continuously visible for ten seconds after success. Its
quantity must not increase again. Close the process only after the receipt and
collection update complete, reopen from the Home Screen and verify the same
printing, finish and quantity. An incorrect identity, finish, duplicate or lost
acquisition stops the run and becomes a reproducible defect. Record slow/missed
recognition separately; do not force a wrong match to obtain a success.

### 2. Physical printing distinction and skipped choice

Present C. Expect the ST-11/ST-16 choice before any mutation. Open Details and
verify that visible release/distinction labels let the collector match the card;
missing artwork alone must not force a guess. Skip once: quantity stays at the
baseline and one encounter is retained in Needs attention. Reopen the process,
retry that encounter, select ST-11 and verify exactly one acquisition of C.

Remove the card fully before presenting D. Select ST-16 and verify acquisition
of D only. If the existing duplicate protection offers **Add another**, verify
the selected printing first and authorize just the intended physical copy; an
extra prompt does not permit an automatic second acquisition. Reopen again:
C and D must retain independent UUID/finish rows and
their respective +1 deltas. A finish lock must not choose their printing. If
the releases cannot be distinguished reliably from the offered details, leave
the encounter unresolved and record a usability/physical-evidence blocker.

### 3. Unmapped pricing and offline durability

Present E (or the exactly matched alternate above). Verify sole Foil assignment
and +1 quantity without a fabricated price. Refresh the mapped and unmapped
samples: record each observed source/state/timestamp. D/E must not receive a
managed quote from another printing. Preserve any pre-existing manual/imported
prices; an unmapped row with a manual price is not proof of a provider fallback.

Disconnect networking and reopen from the Home Screen. One Piece availability,
the selected saved rows, quantities and local catalog should survive. Scan an
available reviewed sample offline only if another intended acquisition is
desired; record that additional +1. Price unavailability must not block an exact
local acquisition. Restore networking after the check. This closes a local
offline case, not new-release freshness or a provider outage/withdrawal matrix.

### 4. Held-number recovery and cancellation

Present F. Expect recognition to retain incomplete evidence in Needs attention,
with no eligible choice, successful acquisition or quantity change. Reopen and
check that this encounter remains. Retry while the same catalog is installed:
it must remain incomplete and must not borrow a neighboring printing. Explicitly
dismiss only the test encounter if cleanup is desired, reopen, and verify it
does not resurrect. Never dismiss unrelated recovery records.

If F is unavailable, keep this physical case pending and rely only on the
separately labeled deterministic incomplete-number tests for code behavior.

### 5. Bounded usability and regression controls

Repeat stable presentation under diffuse room light and one angled/glare
condition. Use Price Check for extra recognition attempts where another owned
copy is not intended; log purpose because it changes the acquisition expectation.
Check one raw Pokémon and one modern Magic control through Price Check, with
zero ownership changes. Confirm tab return/background foreground restores the
camera without duplicate acquisition.

Run VoiceOver through the printing choice, Details, Skip and recovery/retry;
check one large Dynamic Type setting for legible actions and no clipping.
Capture read/receipt times per attempt and classify any confusion or failed
recognition. Do not claim sustained 8 Hz tracking, thermal performance, older
device support or statistically representative accuracy from this small pass.

## If a defect is found

Change only the boundary supported by the reproduction:

| Observed failure | Inspect first | Narrow verification |
| --- | --- | --- |
| Missed/foreign/incorrect footer | `Games/OnePiece/OnePieceScanProfile.swift`, `OnePieceRecognitionAdapter.swift`, `Services/CardScanner.swift` | `OnePieceIntegrationTests`, geometry/cross-game recognition selectors |
| Wrong or unclear printing/finish | `OnePieceCatalogAdapter.swift`, `Views/ScanSessionOverlays.swift`, `Services/VariantResolver.swift` | Exact-choice and finish-lock cases, `VariantResolverTests`, rendered affected state |
| Duplicate or pending choice replaced | `Services/CardLatch.swift`, `Views/ScannerViewModel.swift` | `CardLatchTests`, `ScanSubjectSuppressionTests`, scanner lifecycle selectors |
| Lost/failed save or recovery | `ScannerCollectionWriter` in `Services/CollectionStore.swift`, `Services/UnresolvedScanStore.swift` | Disk-backed failure/retry and persistent real-catalog integration cases |
| Wrong mapped/unmapped quote | `OnePiecePriceAdapter.swift`, collection price authority | Exact UUID/finish pricing and withdrawal cases; preserve manual/imported prices |
| Ordinary/offline catalog missing | `Services/OnePieceCatalogBootstrap.swift`, `Games/Core/CardGameRuntime.swift` | Owner bootstrap, ordinary storage and unavailable-runtime cases |

Capture a sanitized reproduction before fixing. Use `apply_patch`, preserve
existing local work and run the narrowest relevant `xcodebuild` tests with external
derived data/result bundles. Expand to the affected integration selection when
shared recognition, persistence, catalog authority or prices change. Rebuild and
repeat the failing physical case on the exact corrected candidate. Simulator
results do not replace that hardware recheck. If the defect requires speculative
migration or production configuration, split it into a separately justified slice.

## Evidence, completion and next boundary

Keep private photos, screen recordings and logs outside the repository. The
durable summary records candidate/configuration, device model/OS, seed hash,
sample UUID/release/finish, purpose, lighting, baseline/delta/reopened quantity,
recognized result, choices, timings, quote state, recovery state, outcome and
private artifact reference. Label unavailable cases **Pending**, reproduced
defects **Failed**, and observations **Passed** only with direct evidence.

The first one-card checkpoint is independently reportable. The bounded slice is
complete only when the available exact samples establish acquisition/relaunch,
same-number separation, no repeated continuous acquisition, unmapped-price
behavior, offline availability and held/skip recovery, with the usability checks
recorded and blocking defects corrected/rechecked. A missing required physical
sample means partial evidence; it must not be silently waived.

Update [installed-app evidence](one_piece_device_review.md), the relevant rows
in [release acceptance](one_piece_release_acceptance.md), the
[implementation ledger](one_piece_code_implementation.md), then append verified
execution evidence to [`progress.md`](../../progress.md). Reconcile changed
priorities in [the documentation audit](documentation_audit.md). Validate local
Markdown links and run `git diff --check` after documentation edits.

Even a passing bounded slice leaves the parent 50-card ST/OP/EB/P coverage gate,
oldest/current-device matrix, live 50-mapping provider sampling, sustained
performance, physical special-printing coverage, CloudKit/mixed-client policy,
source rights, production keys/hosting/rollback and release archive open. Next,
expand the existing camera sample manifest to that representative matrix and
review held physical distinctions in declared batches. Fix any confirmed
blocking defect before expanding to Lorcana or production delivery.
