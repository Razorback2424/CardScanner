# Historical printing-family search verification

**Date:** 2026-10-06. Target: native Printing details for large families.
Routes: `PrintingChoice`, `many-details`, `many-filtered-details`,
`many-accessibility-filtered-details`. Expected: iPhone 17 Pro iOS 26.5 simulator.
Evidence remains on the external SSD under `CodexBuilds/MagicHistorical/UI/General/`.

- [x] Native set/collector search is visible with readable placeholder.
- [x] Filtering the 61-row fixture to `Block: 10` renders one matching row with its selection action.
- [x] Accessibility-size labels wrap; the filtered row and selection action remain fully visible.
- [x] Done, search and clear controls render as native controls with readable labels.
- [x] Source review confirms filtering changes display only; English and complete-family selection evidence remain authoritative.

HIG gate: native NavigationStack/List/search, local state, Dynamic Type and
44-point existing actions. Source/render HIG gate: PASS. Inspected all three
captures: unfiltered, filtered and accessibility3 filtered. Captures use a synthetic
61-row fixture and the exact Details view; they do not prove VoiceOver behavior,
keyboard interaction, row taps or dismissal from the production sheet. Device
interaction acceptance remains open.
