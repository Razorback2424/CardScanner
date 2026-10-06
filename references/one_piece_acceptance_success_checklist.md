# One Piece integrated simulator acceptance

**Target screen:** real scanner, printing picker, recovery and Collection.
**Route:** `OnePieceAcceptance`; verified bundled full catalog.
**Device:** iPhone 17 Pro / iOS 26.5.
**Evidence:** external `CardScannerBuild/OnePieceAcceptance-2026-10-05`.
**Status:** integrated local simulator slice verified, 2026-10-05 at `f40e704`
plus local changes. Hardware/provider/CloudKit/release acceptance remains open.

## Visual checklist

- [x] ST11-003 shows Backlight and distinct ST11/ST16 release choices, with legible buttons.
- [x] No clipping or overlap between test controls, scanner chrome and picker.
- [x] Details and skip remain available; injection is disabled while choosing.
- [x] Starter/booster sole-printing samples show receipts without extra pickers.
- [x] Unknown number shows Needs attention and keeps navigation available.
- [x] Collection shows distinct ST11/ST16 owned rows and exact finishes.
- [x] Relaunch preserves owned rows in the separate acceptance collection.

## Behavior checklist

- [x] Real printing selection saves the chosen UUID, sole finish and quantity one.
- [x] Skip creates recovery without ownership; retry presents the current choices.
- [x] Two printings with one number/finish remain separate after persistent-store reopening and CSV import.
- [x] Exact mapped price survives reopening/refresh; an unmapped printing stays unpriced.
- [x] Ordinary launches and local-review launches keep their established storage directories.

`UI/ready-same-number`, `ready-starter` and `ready-booster` contain inspected
settled captures. Karoo shows Normal and Shanks Foil, each with a receipt and
no choice stage. These displayed prices are app-lane answers; no fresh-provider
claim is made. Earlier native interaction verified both Backlight selections,
Details, skip and retry; `UI/recovery-detail.png` records recovery controls.
An already-owned printing retried within the same session is correctly denied
as a duplicate; the skip-first/relaunch/retry regression verifies a successful
new save. The full-corpus tests also verify exact overdue refresh, Browse add
merging only the selected printing, and CSV into a fresh persistent store.

The nine-class regression passed 315/316; its one monitor fixture was corrected
and all five monitor cases passed on recheck. All 70 One Piece and 96 scanner
tests passed. Startup recovery now defers writes until serial disk reloads merge;
gated tests retain earlier/new encounters and prevent dismissed-row resurrection.
Real write failure remains covered by the existing scanner regression.

Final `UI/ready-unknown-final/ui-latest.png` shows OP01-999 not added and two
Needs attention records, with no false disk-save warning. The affected sample
regression passes against the full recognizer; the first OP99 sample was outside
its supported series and was corrected. `UI/collection-final.png` and its native
tree show four durable rows after process relaunch: ST11/ST16 Backlight each
Normal/quantity one, Karoo Normal/one and Shanks Foil/one. ST16 remains unpriced
(Not checked yet), while the mapped rows display their retained quotes.
`UI/collection-later-printing-final.png` shows the later Backlight Normal row
with Price not checked and the footer's four items / one unpriced copy.

Simulator number injection does not establish physical-camera OCR, device
performance, VoiceOver, live-provider coverage, CloudKit or release readiness.
