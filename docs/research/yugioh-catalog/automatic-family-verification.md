# Automatic printing and edition resolution

**Status — 2026-10-22, base `1ac6750`:** game-wide decision code is implemented;
physical catalog coverage is incomplete. This is not a claim that every
Yu-Gi-Oh! printing can now be identified automatically. This record captures
the local implementation evidence before repository integration.

## Cause and policy

The bundled MP24-EN372 row is product 579846, Synchro World, Common, with
independently supported First Edition membership and unknown edition coverage.
The previous bundle had zero automatic codes. Both lookup and scanner save
validation required existing automatic authority; hiding the printing picker
alone would not have completed acquisition.

Printing-family certainty, exact product/edition membership, exhaustive edition
coverage, observed edition text, and prices remain independent. One shared
`VariantResolver.resolveAcquisition` policy runs during scanner resolution and
again against current authority at the collection writer. The actual capture
stays on the commit candidate. Generation, automatic printing authority, exact
edition support, contradictions and cancellation are checked before staging
and immediately before saving. Failed staging rolls back inventory, activity,
ownership and price writes together. Existing duplicate, quantity and Undo paths
remain in place; no automatic result is relabeled as a manual printing selection.

Verified unique printing plus supported positive First/Limited evidence can
continue without either picker. Without edition evidence, unknown edition
coverage still requires an explicit edition answer, even if only one supported
choice is known. A missing stamp never establishes Unlimited. Competing or
uncertified printings retain recovery; unsupported/conflicting editions cannot
be added. The edition picker discloses that supported choices may be incomplete.
Other games retain their finish wording.

Vision-supplied positive edition readings below 0.8 confidence, or with invalid
confidence, become unreadable evidence and require an answer. Existing unscored
recorded/injected fixtures retain their semantics. This conservative cutoff is
not a claim of physical-camera calibration.

## Game-wide implementation, bounded source evidence

`konami-release-family-v1` accepts reviewed release metadata; the Swift policy
has no MP24 code, rarity, group or source-hash exception. Each scope includes
release/group, English code prefix, admitted rarities, complete inventory count,
source URL/hash, capture time and exact product-snapshot hash. These fields are
inside the existing catalog bytes, generation, signature and transition checks.
Missing family authority in older catalogs grants no new automatic eligibility.
The standalone publisher executes the same loader. Its runtime-only pricing
helper was moved to the runtime adapter so that the Foundation-only CLI compiles.

The reproducible extractor checks the English locale, release title, reported
total, parsed row count, unique official card IDs, rarity lists and artwork IDs.
The requested `rp=99999` captures contain the entire reported result set; counts
are verified rather than assuming the request disabled pagination. Exact
normalized names crosswalk to the existing code/release/rarity correspondence.
Conflicting, skipped, unmatched, duplicate, multi-rarity, ambiguous artwork and
indistinguishable families remain excluded. Canonical image counts are used
only to exclude ambiguity, never to infer the edition of a physical copy.

| Release | Official card entries | Catalog products | Certified families | Excluded from automatic authority |
| --- | ---: | ---: | ---: | ---: |
| MP24 | 397 | 400 | 100 | 300 |
| Duelist Nexus | 100 | 125 | 73 | 52 |
| Pharaoh's Servant | 105 | 105 | 87 | 18 |
| Total reviewed | 602 | 630 | 260 | 370 |

MP24's official inventory is a card list, not a marketplace product count: one
entry has two rarity labels and the two marketplace token products are absent.
Only the 100 fully matched Common families are admitted there. Duelist Nexus
admits 49 Commons and 24 Super Rares; competing rarity families are excluded.
Pharaoh's Servant admits Commons, Rares, Super Rares, Ultra Rares and one Secret
Rare. These real modern and legacy inputs exercise the same rule, without
card-specific exceptions. None of the 46,542 products gains exhaustive edition
coverage. All 59,965 previously admitted product/edition pairs retain identity
and provenance. Quotes retain their original source dates.

The full catalog contains 37,869 codes. Of 46,542 products, 260 have automatic
family authority, 46,043 remain explicit-choice eligible, and 239 remain
discovery-only. These are source coverage counts, not camera accuracy.

**Remaining blocker to the user's all-printings goal:** trustworthy release
coverage and deterministic crosswalks are still missing outside these scopes.
The captured Konami index has 935 release entries; only 397 of the catalog's 659
release names have a unique exact normalized match. The other 262 need reviewed
release mappings; matching names alone also does not certify artwork/rarity
coverage. Further captures must pass the same count, correspondence and source
integrity checks. Broadly certifying all singleton marketplace rows would erase
this uncertainty. No mass manual per-product census or invented completeness
was used. The code can consume additional reviewed releases without an app
policy change, but this pass does not close catalog-wide evidence coverage.

Index capture: `card_list.action?wname=CardSearch&request_locale=en`, SHA-256
`0e81480e332d1d487614b316452d129b1b6b57c84a1832ef4b023ad4dd340c5b`.

## Provenance and replay

Source URLs, extracted identity rows, capture times and product hashes are in
the [MP24](../../../scripts/yugioh_mp24_inventory.json),
[Duelist Nexus](../../../scripts/yugioh_dune_inventory.json) and
[Pharaoh's Servant](../../../scripts/yugioh_psv_inventory.json) records.
Raw captures are preserved on the external SSD under
`YuGiOhSourceCache/2026-10-21/konami/`; card text and images were not copied into
the extracted inventories. Rule version and source hashes bind the replay.

The [official Synchro World entry](https://www.db.yugioh-card.com/yugiohdb/card_search.action?cid=18838&ope=2&request_locale=en)
corroborates MP24-EN372/Common. The
[official MP24 product page](https://www.yugioh-card.com/en/products/2024tin/)
states a 400-card set. Neither page alone certifies every edition.

Bundled generation: `yugioh-en-b8a4379840bc`.
Seed SHA-256: `b501e466c3b5e91b430e3bfdc69a58f559538f34a00c6ad010df0981f3091ac8`.
Final replay detected a patch-added terminal newline. The builder regenerated
the artifact with identical JSON and no extra newline; exact-byte comparison
then passed. The generation and catalog contents did not change.
The follow-up real-bundle signed-admission and partition selection passed both
tests (`automatic-exact-bytes.xcresult`); these overlap the 119-test selection.
The generic iOS build also passed with those exact final bytes
(`automatic-exact-bytes-ios.log`).

```bash
cache='/Volumes/<external-SSD>/YuGiOhSourceCache/2026-10-21'
python3 -I scripts/build_yugioh_catalog.py --offline --cache-dir "$cache" \
  --price-receipt docs/research/yugioh-catalog/price-census-receipt.json \
  --official-inventory-html "$cache/konami/mp24.html" \
  --official-inventory-html "$cache/konami/dune.html" \
  --official-inventory-html "$cache/konami/psv.html" \
  --out /tmp/yugioh-replay.json --report /tmp/yugioh-replay.md
cmp /tmp/yugioh-replay.json TradingCardScanner/YuGiOhCatalogSeed/catalog.json
python3 -I scripts/build_yugioh_catalog.py --self-test
```

## Verification

**Follow-up validation — 2026-10-23, local candidate based on `1ac6750`:** the
selected iOS 27.0 Simulator run passed 457 tests with zero failures. It includes
the catalog, resolution, workflow, scanner, recovery, import and neighboring-game
selectors. The result bundle is `CardBuilds/yugioh-integration-20261023/automatic-current-correct-destination.xcresult`
on the external SSD. The builder suite passed 33 tests, `--self-test` passed,
and changed-document link and whitespace checks passed. These results supplement
the earlier 119-test snapshot below; their overlapping counts are not summed.

Builder regressions: 33 passed. Local signed-publisher regressions: 5 passed.
Initial native selection: 50 passed. A subsequent broader selection executed
229 tests with one scanner lifecycle failure; the further game-wide run was
interrupted when the local tool/Simulator session restarted, leaving an
incomplete result bundle. Final native run `automatic-confidence-final.xcresult`
passed **119 tests with zero failures**, including the low-confidence OCR guard
and the lifecycle test that failed in the earlier broad run. The same lifecycle
test also passed on an untouched HEAD copy (`automatic-baseline-lifecycle.xcresult`,
one test); its earlier failure is retained as a transient result, not asserted
to be a confirmed pre-existing defect. Counts overlap and must not be summed.
The final Simulator UI build and generic iOS build after the confidence guard
both passed (`automatic-ui-final-build.log`, `automatic-generic-ios-final.log`).

Added native regressions exercise actual recognizer → scanner → writer → reopen
for MP24, DUNE and PSV, each with positive First evidence and absent edition
evidence; exact lineage; rejected contradictory/unsupported acquisition;
withdrawal/generation replacement without partial writes and a successful retry;
cancellation; malformed family authority; old-catalog decoding; and all supported
edition policy values. Existing Limited/manual recovery and neighboring-game
tests are retained. Fixtures and injected UI are separate from physical-camera
acceptance. No real capture of the user's card/stamp was supplied, so that gate
remains open. No owner collection data, production activation, physical-device
installation or deployment is claimed by this verification.

## Rendered scanner acceptance

The dedicated **YuGiOh Automatic UI QA** simulator uses separate edition-only
and positive-First debug stores. `scripts/ui_build_and_shoot.sh` launches the
actual app with `YuGiOhAcceptance` and states `MP24-EN372` / `MP24-EN372-first`;
it injects recorded recognition input, not a resolved card or save result.
The initial capture timed out at a first-launch system camera prompt. Camera
access was declined; the subsequent deterministic captures succeeded.

- Edition-only capture: `automatic-ui-edition/ui-latest.png`. Inspected the
  edition heading, Synchro World/code, supported-only disclosure, single First
  Edition button, readable wrapping and absence of a printing question. Pressing
  that button in Device Hub showed one recent scan, explicit confirmation
  provenance and Undo through the real UI.
- Positive First capture: `automatic-ui-first/ui-latest.png`. Inspected Auto
  mode, **1 added**, exact code/First Edition receipt, printed-label provenance,
  Undo and absence of either choice screen. The code-only and positive fixtures
  use different stores; the positive result did not inherit the earlier tap.

Artifacts and logs are on the external SSD under `CardScannerBuilds/yugioh/`;
screenshots are not repository artifacts. Native reopen/lineage checks, rather
than the screenshot alone, prove the exact persisted identity and count.

HIG gate: **PASS for the changed normal-size surfaces**. Platform patterns and
navigation are preserved; the one required answer is explicit, supported and
clearly worded; text wraps without clipping; button targets and accessibility
labels are retained. No UI issue requiring a further patch was found. Large
Dynamic Type, physical-camera behavior and full accessibility acceptance were
not newly certified by these captures.
