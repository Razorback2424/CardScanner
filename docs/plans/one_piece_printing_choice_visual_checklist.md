# One Piece printing-choice visual evidence

## Current owner correction — 2026-10-05

Target: One Piece scanner printing picker; deterministic route `PrintingChoice`.
Phone states: `long-title`, `few`, `many`, `accessibility`, `missing-artwork`.
The owner now requires no picker for one available verified printing. This
supersedes the older single-candidate confirmation policy. The remaining picker
uses a smaller headline, stacked identifier/set subtitle, compact rounded options,
and two columns for three or more choices. The full set title can wrap.

Current verification checklist:

- [x] Long set title is readable; title, identifier and set have clear hierarchy.
- [x] Choice buttons and skip/details actions remain reachable without oversized pills.
- [x] Many-candidate list remains bounded and scrollable; candidate 61 selected successfully.
- [x] Accessibility text wraps; no overlap or clipping at accessibility3 on the phone fixture.
- [x] Artwork-only options stay visibly disabled; runtime snapshot offers only Details and skip.
- [x] Shiki OP17-047 saves directly; multiple printings/finishes still ask in regression tests.

Verification: 97 One Piece/shared variant cases passed; the final recovery/scanner
follow-up passed 56 cases (118 distinct passing cases across both runs). This
includes the bundled Shiki card, supported finish choice, persisted singleton
revalidation, tampered-evidence rejection, and unresolved-store compatibility.
Native fixture checks opened/closed Details without selecting, selected candidate
2 and candidate 61, and skipped without selecting. Captures and logs are retained
under the external drive's `CardScannerBuild/one-piece-scan-ui/` directory.
The first capture caught catalog preparation; settled captures use the helper's
new optional `UI_CAPTURE_DELAY_SECONDS=12` and preserve existing simulator data.

HIG gate **Verdict: PASS for the scoped phone fixture changes**.

| Category | Result | Evidence |
| --- | --- | --- |
| Platform patterns | PASS | Existing scanner overlay and native Details sheet retained |
| Clarity | PASS | Single primary choice, subordinate set subtitle, readable options |
| Typography | PASS | Semantic fonts, full set wrapping, accessibility3 capture |
| Accessibility baseline | PASS | 44-point skip/Details targets, minimum 48-point choices, spoken action labels |
| Interaction cost | PASS | No sole-option prompt; one tap selects when a distinction remains |
| App Review design | PASS | Unavailable artwork choices remain disabled with a visible explanation |

Top issues addressed: sole-option confirmation, competing title/set hierarchy,
oversized pill actions. Minimal fixes are confined to the One Piece lookup,
persisted-choice compatibility and printing-picker presentation. Actual phone
camera, loaded real artwork, VoiceOver and tablet acceptance remain separate
from these simulator fixture checks.

The dated 2026-10-04 evidence below describes the prior layout.

**Status:** compact fixture layout/interaction verified; real-corpus/device acceptance open — 2026-10-04, uncommitted
`one-piece-integration` worktree at base `69c714f`.
This is a fixture rendering/interaction checklist, not real-corpus, device or
production support certification. The [implementation ledger](one_piece_code_implementation.md)
remains the execution authority.

Target screen: live printing choice and matching recovery rows.
Route: `PrintingChoice`; states `few`, `many`, `accessibility`, `footer`, `missing-artwork`.
Devices: existing iPhone simulator and iPad simulator; existing tested app reused.
Captures are retained on the external artifact drive, not committed to the repo.
Earlier fixture captures do not approve this design. The current rows expose too
much metadata; the owner requires a concise picker. The compact design requirements
in [ledger finding 2](one_piece_code_implementation.md#audit-findings-and-required-follow-up--2026-10-04)
supersede the earlier instruction to show complete metadata in every row.

## HIG gate

Based on the [Apple design tips](https://developer.apple.com/design/tips/), with
the repository's existing scanner overlay pattern retained.

| Category | Initial result | Minimal change / required evidence |
| --- | --- | --- |
| Platform patterns | PASS | Keep the existing overlay and recovery list; no new navigation step |
| Clarity / growth | FAIL | Bound a lazy vertical list; retain every candidate and show physical distinctions |
| Typography | FAIL | Remove one-line scaling and fixed row height; wrap metadata at Dynamic Type sizes |
| Accessibility | RISK | 44-point dismiss/choice targets, complete spoken labels, source image failure handling |
| Interaction cost | PASS | One tap chooses; skip remains available; optical comparison does not choose a card |
| App Review design | RISK | Do not offer indistinguishable candidates as exact physical choices |

Top issues: unbounded candidate grid, hidden distinction text, small dismiss target.
The earlier verbose layout was rejected. Owner clarification: match the existing Pokémon/Magic `VariantChoiceBar`
format, with shared header/glass styling and short option buttons. Up to three
choices use one row; more use two columns with bounded scrolling for long lists.
Do not use the verbose thumbnail/metadata list as the default. Put full metadata
behind a separate details control when required to disambiguate. Keep physical
evidence and unavailable-choice safety intact; do not hide an essential distinction.
The revised source follows that layout, selects short distinguishing labels,
and moves full metadata/artwork into a shared Details sheet. Compact artwork-only
choices are disabled; the image must load in Details before that choice is enabled.
Minimal files: `ScanSessionOverlays.swift`, shared candidate projection and
`UnresolvedScanDetailView.swift`. Source/client compatibility is checked alongside
rendering. Live artwork-only choices require the distinct reviewed image to load;
identical labels/artwork without another visible distinction need more catalog
detail and remain unresolved.

## Visual checklist

- [x] Two-choice phone state: same compact header and option-button format as Pokémon/Magic; skip and choices remain reachable.
- [x] Large phone history: bounded grid, visible count, no overflow, all 61 candidates retained.
- [x] Accessibility text: essential distinctions wrap without shrinking; full metadata remains in Details.
- [x] Tablet: sensible content width and the same candidate information/controls.
- [x] Text does not overlap; essential footer distinctions remain available without dumping all footer text into every row.
- [x] Missing artwork has a visible fallback; image-only choices cannot be guessed.
- [ ] Controlled loading and successfully loaded distinguishing artwork: render/selection checks with permitted real assets still required.
- [x] Safe areas and dismiss control remain visible.
- [x] Identical-art footer state retains the necessary block distinction in compact buttons.

## Behavior checklist

- [x] Scroll to the final candidate and select it; exact fixture ID appears.
- [x] Dismiss retains the skip action without selecting a physical printing.
- [x] Details open without selecting; necessary distinctions and the separate details action have clear accessible labels in runtime snapshots.
- [x] Older candidate JSON decodes and a same-generation legacy choice still resolves.
- [x] Region/footer distinctions and missing-artwork collisions are covered by focused tests.

## Evidence

Existing `/private/tmp/one-piece-printing-presentation-followup.log` records 52
passing selected tests (33 One Piece integration, three scanner printing-choice
cases, 16 unresolved-store cases). This plan-only audit inspected that log and
the current source; it ran no build/test or simulator interaction. Older JSON,
footer distinctions and collision tests are implementation evidence, not compact
UX acceptance. New captures and interaction checks are required after redesign.

Compact checkpoint: `/private/tmp/one-piece-compact-picker-checkpoint.log` passes
37 selected cases (34 One Piece integration and three scanner choice cases).
The additional shortest-label/large-text follow-up ran only its affected test and
passed; logs are at `/private/tmp/one-piece-compact-picker-accessibility-followup.log`.
Rendered header sizing and tablet contrast then received build-only checks in
`/private/tmp/one-piece-compact-picker-final-build.log` and
`/private/tmp/one-piece-compact-picker-contrast-build.log`, both successful.
Unchanged tests were not rerun for these last presentation fixes.

Final captures inspected under the external artifact directory
`/Volumes/Keller Family Photos 1/CodexBuilds/OnePieceIntegration/CompactPrintingChoice`:
`few-phone`, `many-phone`, `accessibility-phone`, `footer-phone`,
`missing-artwork-phone` and `many-tablet` each contain `ui-latest.png`.
Additional evidence: `many-phone/final-selected.png`,
`missing-artwork-phone/details.png` and the earlier `few-phone/details.png`.
After-install captures that caught launch UI were replaced only after observing
the settled fixture. Metadata launch timestamps remain the route-launch timestamps.

Native interaction reached choice 61, selected `fixture-61`, and exercised skip
with `Skipped to Needs attention`. Opening/closing Details retained `No printing
selected`; ordinary selection returned `fixture-2`. Missing-artwork candidates
exposed no selectable runtime targets in either compact or detail presentation,
and Details displayed the failure explanation. These debug actions update a
fixture result label; they do not write collection/recovery data. Actual recovery
and ownership mechanics are covered by the selected scanner cases, not screenshots.

**HIG verdict: RISK for full acceptance; fixture layout checks pass.** A/platform,
B/clarity, C/typography and E/interaction have scoped simulator evidence. D/accessibility
still needs actual VoiceOver/focus, increased contrast/transparency and device
checks; runtime snapshots include underlying debug-host content and do not prove
modal focus isolation. F/identity clarity still needs the real reviewed corpus,
successfully loaded artwork comparison and owner review. The rejected metadata
dump, clipping at large text and light-tablet material contrast were corrected.
Next minimal work is real-corpus distinguishability and these acceptance checks,
not another picker framework or optical selection logic.
