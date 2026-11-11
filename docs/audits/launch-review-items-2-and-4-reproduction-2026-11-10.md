# Reproducible findings: production content and Pokémon finish certainty

**Date:** 2026-11-10. **Scope:** items 2 and 4 in the independent review's chat summary, meaning LR02/LR04 and LR06 in the [full audit](launch-review-2026-11-10.md).
**Baseline:** main at 2527c9b4163a4b9694e509ca245b9ca96d8ba38c plus the existing dirty working tree.
**Purpose:** detailed reproduction supplement. The full audit and [launch contract](../release/launch-contract.md) retain status/product authority; this document makes these findings independently testable.

No app/test/catalog/project code was changed. A fresh comparison with the original 2,353 tracked-file fingerprints found only the review's documentation updates. Relevant existing user changes remain in place. Builds, earlier test receipts and fresh HTTP captures are retained outside the repository:

    /Volumes/T7/CodexBuilds/LaunchReview-20261110-Codex/

## Finding inventory

| ID | Finding | Type and confidence | User impact |
| --- | --- | --- | --- |
| 2A / LR02 | Release disables One Piece and provides no production catalog origin or pins | Demonstrated configuration gap; high | The contracted fifth game's ordinary acquisition journey is unavailable in this configuration. Local owner availability can conceal the gap during development. |
| 2B / LR04 | Configured Pokémon catalog pointer returns HTTP 404 | Demonstrated deployment gap at the recorded time; high | New signed catalog generations cannot be obtained from that endpoint. Bundled/persisted catalogs remain available. |
| 4A / LR06 | Incomplete Pokémon singleton membership can become catalogCertain / “Only variant printed” | Demonstrated resolution/confidence policy; high. Incorrect assignment of a particular physical card is not demonstrated. | A supported finish can acquire stronger certainty than the coverage evidence warrants, potentially hiding a missing alternative. |

All three remain P1/Major under the launch contract. That prioritizes work; it does not equate a missing deployment, a confidence mismatch and a proven physical misidentification.

## Reproduction setup and evidence rules

Use this repository root, Xcode and its selected developer directory. Record the actual source/configuration before comparison; the commit alone does not identify this dirty candidate:

    git rev-parse HEAD
    git status --short
    git diff -- Config/OnePieceCatalogProduction.xcconfig Config/PokemonCatalogProduction.xcconfig TradingCardScanner/Services/VariantResolver.swift TradingCardScanner/Models/CardVariant.swift TradingCardScanner/Games/Core/LegacyResolvedCard.swift
    xcodebuild -version
    xcrun simctl list devices available

Keep generated material on an available external SSD. The examples below use the review machine's T7; substitute another mounted SSD if needed. Use a dedicated disposable simulator/store for tests and any manual acquisition. Do not uninstall the owner's installed app, reset a simulator or import into their collection.

Create one new output directory and retain its path for all subsequent blocks:

    REVIEW_RUN="$(mktemp -d /Volumes/T7/CodexBuilds/Findings-2-4.XXXXXX)"
    export REVIEW_RUN

The build/test commands below are reproduction instructions. This follow-up did not execute another build or app test run; it re-read the retained results and confirmed unchanged app source. HTTP checks were freshly repeated at approximately 2026-11-10 21:51–21:52 UTC. A changed endpoint or later source can legitimately produce a different result; retain that evidence rather than forcing the old outcome.

## 2A — One Piece is deliberately disabled in the Release candidate

### Expected and observed behavior

The contract's launch boundary includes five games, with ordinary supported scanning, Browse and collection acquisition. In contrast, the actual Release settings are:

| Built Info.plist key | Observed value |
| --- | --- |
| ONE_PIECE_CATALOG_ROLLOUT_MODE | disabled |
| ONE_PIECE_CATALOG_BASE_URL | empty string |
| ONE_PIECE_CATALOG_PINNED_KEYS | empty string |
| ONE_PIECE_COLLECTION_WRITES | NO |

These are intentional safety gates awaiting reviewed data, trust configuration and production approval. The defect relative to launch is the unfinished integration/configuration, not a failure of the gate itself.

### Cause and execution path

1. [OnePieceCatalogProduction.xcconfig](../../Config/OnePieceCatalogProduction.xcconfig) supplies these values and is included by [PokemonCatalogProduction.xcconfig](../../Config/PokemonCatalogProduction.xcconfig).
2. [Info.plist](../../TradingCardScanner/Info.plist) expands them into the installed bundle.
3. [OnePieceCatalogBootstrapConfiguration.configured](../../TradingCardScanner/Services/OnePieceCatalogBootstrap.swift#L37) reads them. Collection writes require both remoteAuthority mode and an explicit YES.
4. [configuredRuntime](../../TradingCardScanner/Services/OnePieceCatalogBootstrap.swift#L225) returns nil immediately for disabled mode. An enabled production path instead requires the one-piece-catalog-release.json seed, dedicated acceptable keys and safe origin.
5. [CardGameRuntimeContainer.appDefaults](../../TradingCardScanner/Games/Core/CardGameRuntime.swift#L359) therefore adds no One Piece module through the configured production path.
6. The separate ownerRuntime path is compiled under LOCAL_ONLY_SIGNING; local review additionally uses DEBUG. These explain a functioning local One Piece experience. The prior Release build's compiler conditions contained NO_CLOUDKIT and excluded those local flags and owner resources.

Changing only the mode cannot complete this work: missing pins/origin/seed should fail closed. Enabling writes alone cannot register a disabled game.

### Steps to reproduce

**Fast source check:**

    cat Config/OnePieceCatalogProduction.xcconfig
    rg -n 'OnePieceCatalogProduction|baseConfigurationReference|SWIFT_ACTIVE_COMPILATION_CONDITIONS' Config/PokemonCatalogProduction.xcconfig TradingCardScanner.xcodeproj/project.pbxproj

**Independent compiled readback:** build the ordinary Release configuration, with no testing/local flag overrides:

    xcodebuild build \
      -project TradingCardScanner.xcodeproj \
      -scheme TradingCardScanner \
      -configuration Release \
      -sdk iphonesimulator \
      -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath "$REVIEW_RUN/ReleaseDerivedData" \
      CODE_SIGNING_ALLOWED=NO \
      > "$REVIEW_RUN/release-build.log" 2>&1

Proceed only after the build exits successfully. Read the processed plist rather than assuming source settings won:

    python3 - "$REVIEW_RUN/ReleaseDerivedData/Build/Products/Release-iphonesimulator/TradingCardScanner.app/Info.plist" <<'PY'
    import plistlib, sys
    with open(sys.argv[1], "rb") as stream:
        info = plistlib.load(stream)
    for key in (
        "ONE_PIECE_CATALOG_ROLLOUT_MODE",
        "ONE_PIECE_CATALOG_BASE_URL",
        "ONE_PIECE_CATALOG_PINNED_KEYS",
        "ONE_PIECE_COLLECTION_WRITES",
    ):
        print(key, repr(info.get(key)))
    PY

The expected reproduction is the four values above. This unsigned simulator build is a configuration probe, not archive or distribution acceptance.

**Behavior controls:** run the selected tests in the shared command below. The disabled-bootstrap test should pass by returning nil without loading invalid seed bytes. The production-write test should pass by producing no CollectedCard or InventoryEvent and zero successful acquisitions. Passing proves safe refusal; it does not fulfill the five-game product promise.

For native confirmation, install the newly built Release app on a dedicated simulator with no debug/owner launch arguments. Inspect the game selector/Browse and attempt ordinary One Piece acquisition. Record the available capabilities and recovery outcome. This exact Release UI pass was not newly performed in this follow-up; the configuration, compiled readback and runtime trace establish the gap.

### Closure criteria

Follow [the production setup](../release/one-piece-production-setup-2026-10-23.md). Approve the supported catalog scope, seed, dedicated public pins and hosted signed release; then enable the intended capabilities. Accept normal Release recognition → exact printing/finish choice → save → relaunch → price → removal/Undo → CSV on a disposable collection. Test stale/withdrawn choices and malformed/signature/rollback failures. Preserve existing UUIDs/ownership keys and the refusal of unsupported identities. Never promote local owner bypasses as the production fix.

## 2B — Pokémon's configured signed-update endpoint is missing

### Evidence and cause

[Production configuration](../../Config/PokemonCatalogProduction.xcconfig) and the retained Release plist specify remote-authority with base URL https://catalog.scan-stash.com. [PokemonCatalogUpdateClient](../../TradingCardScanner/Services/PokemonCatalogUpdateClient.swift#L77) appends v1/current.json, producing:

    https://catalog.scan-stash.com/v1/current.json

At **2026-11-10T21:51:37Z**, a fresh direct HTTPS GET returned **404**, with curl exit 0. Exit 0 means the HTTP exchange completed; it does not mean HTTP success. Headers/body/status/timestamp are retained in Items2And4/pokemon-pointer.headers.txt, pokemon-pointer.body and endpoint-checks.json.

The same check returned **200** for both of these independently scoped market-feed endpoints:

    https://catalog.scan-stash.com/market-prices/v1/tcgplayer/3/24722/products
    https://catalog.scan-stash.com/market-prices/v1/tcgplayer/3/24722/prices

Their metadata matched: sourceBuild 2026-11-09T20:06:00+0000; sourceFetchedAt 2026-11-10T15:50:42+00:00. This rules out declaring the whole host or sampled price feed unavailable.

The [revision 22 follow-up](launch-review-2026-11-10.md#revision-22-recovery-follow-up--2026-11-10) records the intervening CI history, repeated GET results and owner recovery steps. Firebase Hosting release history is needed to identify the release that dropped the namespace and its actor.

### Steps to reproduce

Run a GET without following redirects, retaining errors and response bytes:

    date -u
    curl --silent --show-error --proto '=https' --max-time 30 \
      --dump-header "$REVIEW_RUN/pokemon-pointer.headers.txt" \
      --output "$REVIEW_RUN/pokemon-pointer.body" \
      --write-out 'HTTP %{http_code}\n' \
      https://catalog.scan-stash.com/v1/current.json

Repeat the same command for the two exact market-feed URLs above, using different output names. Do not infer availability from HEAD, an unrelated group, an assumed market current.json path, cached fixture bytes or a portal landing page. If curl reports 000/nonzero exit, record a transport/access failure; that is not a reproduced HTTP 404.

### User-visible boundary and safety controls

[PokemonCatalogCoordinator](../../TradingCardScanner/Services/PokemonCatalogCoordinator.swift#L90) loads a valid saved release or bundled seed. A rejected fetch does not itself replace that registry. Therefore this finding does **not** demonstrate a startup crash, inability to scan all Pokémon, lost ownership or a universal pricing outage.

The client rejects non-2xx/304 responses. The coordinator shares automatic refreshes and applies a five-minute failure cooldown; explicit retry remains possible. Existing coverage includes PokemonCatalogSliceBTests/testClientError4xxDoesNotRetry, testLoadPersistedOrBundledFallsToBundledSeed and testBadSignatureRejectedLeavesCurrentUnchanged; PokemonCatalogSliceFTests/testAutomaticRefreshCooldownPreservesCurrentReleaseAndAllowsExplicitRetry covers retry retention. These local tests do not certify the hosted endpoint.

### Closure criteria

Publish the approved signed baseline through established publication controls and verify exact hosted bytes using the candidate's real pins/schema. HTTP 200 alone is insufficient. Accept revision N → N+1 activation and coherent recognition/Browse/write/price authority; offline cold restart must use the last accepted generation. Bad signatures, incompatible schema, revision rollback and same-revision collisions must retain that generation. Preserve other catalog namespaces and shared prices when deploying. Disabling update mode does not fulfill the current delivery requirement.

## 4A — Membership-only singleton becomes exhaustive certainty

### Exact deterministic reproduction

No camera, live provider or real card is needed. The existing [test](../../TradingCardScannerTests/VariantResolverTests.swift#L1070), testUnverifiedPokemonSingletonAutoResolvesWithoutBypassingAcquisitionGates, constructs this input for each of Normal, Holo and Reverse:

    VariantEvidence(
        game: .pokemon,
        setID: "fixture",
        cardNumber: "1",
        catalogVariants: [variant],
        physicalCoverageVerified: false,
        explicitMembershipSupported: true
    )

It calls:

    VariantResolver.resolveAcquisition(evidence, printedEdition: .absent)

**Observed and currently asserted result:**

    .resolved(.init(variant: variant, resolution: .uniqueInCatalog))

The test **passes** in the retained broad run. It is a reproduction of the current policy, not a regression test expecting the contract's desired outcome.

That enum then maps in [CardVariant.swift](../../TradingCardScanner/Models/CardVariant.swift#L349) to:

| Property | Value |
| --- | --- |
| label | Only variant printed |
| certainty | catalogCertain |
| receiptProminence | quiet |
| isAutomatic | true |

The demonstrated semantic mismatch is **explicitly unverified coverage → exhaustive-sounding certainty**. Knowing that Holo exists does not establish that Normal, a stamp or another supported object cannot exist.

### Cause and reachability

1. [VariantEvidence](../../TradingCardScanner/Services/VariantResolver.swift#L138) separates membership from coverage. Bounded finish-minimum entries expressly provide additive membership, force coverage false and permit explicit membership.
2. [LegacyResolvedCard.variantEvidence](../../TradingCardScanner/Games/Core/LegacyResolvedCard.swift#L181) can construct that combination for Pokémon; it is not an impossible fixture-only state.
3. resolveAcquisition's gate permits Pokémon membership without verified coverage when there is no observed printed edition.
4. [resolve](../../TradingCardScanner/Services/VariantResolver.swift#L240) repeats that Pokémon exception. After set rules/stamps, a single possible variant returns uniqueInCatalog (or deterministicSetRule when narrowed) before the later finish-lock/printed-finish branches.
5. [ScannerViewModel](../../TradingCardScanner/Views/ScannerViewModel.swift#L4473) routes a resolved result onward rather than presenting pendingChoice. This step alone is not proof of an incorrect durable write for a real card; the policy is on the acquisition path.
6. [VariantProvenancePresentation](../../TradingCardScanner/Views/ScanSessionOverlays.swift#L205) can render the resolution label alongside a finish; quiet prominence reduces routine receipt attention. This is source-level presentation reachability, not a newly captured screenshot showing that label for a real misidentified card.

The stated reason in the resolver comment is preserving no-tap acquisition for a sole supported Pokémon finish while background reconciliation handles coverage. That is deliberate existing behavior. It conflicts with the contract's S03.01 prohibition on incomplete singleton catalogs manufacturing certainty. Background maintenance does not itself validate the current physical object.

### Controls that must remain intact

The same existing test demonstrates the bounds of the exception:

| Input change | Current expected result |
| --- | --- |
| Two supported Pokémon variants, coverage false | needsChoice with the two options |
| Singleton Pokémon, coverage false, no explicit membership | needsChoice with no authorized options |
| Observed Normal contradicts the sole supported Holo | needsChoice with no authorized options |
| Conflicting observed editions | needsChoice with no authorized options |
| Magic singleton, coverage false, explicit membership true | needsChoice; no Pokémon exception |

Do not describe the implementation as blindly bypassing every acquisition gate. It retains these controls.

### Shared automated reproduction

Choose an available dedicated simulator UUID from the setup inventory, then run:

    REVIEW_SIMULATOR_UDID='replace-with-dedicated-simulator-UUID'
    xcodebuild test \
      -project TradingCardScanner.xcodeproj \
      -scheme TradingCardScanner \
      -configuration Debug \
      -destination "platform=iOS Simulator,id=$REVIEW_SIMULATOR_UDID" \
      -derivedDataPath "$REVIEW_RUN/TestDerivedData" \
      -resultBundlePath "$REVIEW_RUN/Findings.xcresult" \
      -parallel-testing-enabled NO \
      -collect-test-diagnostics never \
      -only-testing:TradingCardScannerTests/VariantResolverTests/testUnverifiedPokemonSingletonAutoResolvesWithoutBypassingAcquisitionGates \
      -only-testing:TradingCardScannerTests/OnePieceIntegrationTests/testDisabledBootstrapDoesNotRequireSeedOrRegisterOnePiece \
      -only-testing:TradingCardScannerTests/OnePieceIntegrationTests/testBootstrapRequiresDedicatedKeysSafeOriginAndVerifiedSeed \
      -only-testing:TradingCardScannerTests/OnePieceIntegrationTests/testValidationOnlyBootstrapKeepsGameHiddenAndWritesDisabled \
      -only-testing:TradingCardScannerTests/OnePieceIntegrationTests/testProductionOnePieceRuntimeCannotWriteToSharedCollection \
      > "$REVIEW_RUN/selected-tests.log" 2>&1

All five methods are expected to pass on this reviewed baseline. Their retained executed status is Passed in broad-method-statuses.json and BroadReview.xcresult. Use the project's ordinary signed Debug host; do not copy CODE_SIGNING_ALLOWED=NO from the Release compilation probe into this test command. If signing/environment setup blocks execution, report that separately.

Inspect the named singleton test's assertions, or break immediately after its resolveAcquisition call to inspect the actual enum. Inspect the enum's label/certainty mapping separately. A passing result does not independently prove physical catalog completeness.

### What remains unproven, and a correction to the earlier audit

No independently documented real physical printing with an omitted alternative was demonstrated here. Such a case would be needed to promote the risk into a proven wrong physical assignment, wrong price or wrong marketplace destination.

**Withdrawn comparison:** the earlier audit compared the correction editor for a saved Tropius with the 30th-005 price lane. The retained phone-collection-standard.png instead shows **Pitch Black 001**. Those are different printings. That comparison cannot establish a finish conflict and has been removed from the audit/handoff.

The separate fresh public-data check for **30th-005** found:

- TCGdex GET https://api.tcgdex.net/v2/en/cards/30th-005 returned 200 with Normal true, Holo false and Reverse false.
- The mapped product 716439 / group 24722 returned a Holofoil market lane.
- [TCGdexCard.catalogVariants](../../TradingCardScanner/Models/TCGdexCard.swift#L125) already explicitly supplies Holo for the reviewed 30th mappings before consulting those upstream booleans.

Therefore this example is not evidence that the app missed that correction. No new Holo option, existing-holding rekey or data rewrite is justified by it. The exact-response capture is retained in Items2And4/tcgdex-30th-005.json; it is not independent exhaustive physical truth.

### Closure criteria and recommended decision

First establish the evidence required to assert exhaustive coverage in the frozen supported scope. Then distinguish automatic selection, evidence strength and physical completeness consistently:

- A verified complete singleton should retain ordinary fast acquisition.
- Incomplete membership must not become “Only variant printed”/catalogCertain solely because the published list has one element.
- If validated family-specific evidence establishes the physical finish, record that evidence and test its boundary.
- Otherwise use the existing choice/recovery path as appropriate, or obtain an explicit contract/product decision for a narrower supported-membership claim. A copy-only change cannot resolve an unsupported physical assignment if one is demonstrated.
- Keep conflicting printed evidence, unsupported options, other-game boundaries, user choices, imported values, price identity and history/ledger invariants intact.

Independently sample known-risk physical families with exact game/set/number/printing/finish identity. Follow each accepted case through acquisition, stored provenance, correction, CSV, current price/history and exact TCGplayer product. Record an actual failure before changing a data family. Add regressions for honest certainty and bounded authority, with controls for ordinary verified singleton speed. Do not globally add a tap or weaken tests merely to make the finding disappear.
