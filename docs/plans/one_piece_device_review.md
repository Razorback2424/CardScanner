# One Piece in the owner's existing app

**Next-slice plan — 2026-10-06:** [camera acquisition and relaunch](one_piece_camera_acceptance_slice.md)
defines the bounded physical samples, exact identities, ordinary-app procedure,
failure handling and evidence criteria. This is planned hardware work; the
2026-10-05 installation record below is not camera acceptance.

**Status — 2026-10-05:** corrected update installed under the original
**TradingCardScanner** name and existing app identity. It selects the original
collection storage, with One Piece available alongside Pokémon and Magic. The
owner explicitly rejected the isolated review collection and renamed app.
No app was uninstalled and no collection backup/export was made. Collection
contents and camera behavior still require confirmation on the phone.
Remote launch was denied because the phone is locked; unlock and open the usual
app from the Home Screen.

Historical: a separate review install hit the developer-profile app limit. An
in-place review update then opened isolated storage and confused the owner. That
approach is superseded by the normal-app update described here.

## Prepared build

The existing `TradingCardScanner` scheme and normal `Debug` configuration retain
the original name, identifier and storage paths. An owner-only signed local
catalog enables One Piece collection writes without selecting review storage.
After signature verification, its public trust pin is retained in app preferences
so subsequent ordinary local builds keep One Piece. No private signing key is
stored in the app. Production catalog publication remains disabled.

**Ordinary Xcode rebuild correction:** relying on that saved preference failed
when the owner rebuilt before the configured app's first launch. The normal
project now bundles the existing signed catalog and public pin directly. The
ordinary local build registers One Piece without any prior launch, copied
Documents file or special build setting, using the normal collection storage.

Device compilation and in-place installation passed. The focused owner-catalog
and storage selection executed 32 tests, with zero failures and one expected
simulator data-protection skip. The kit contains the
full retained ordinary registry and exact base price mappings, signed with an
ephemeral key. Artifacts are on the external SSD under
`CardScannerBuild/OnePieceDeviceReview-2026-10-05/`; private device logs remain
outside the repository. No backup was authorized or performed.

## First check, after installation

1. Open the usual **TradingCardScanner** app and check the existing collection.
   Allow Camera access when prompted.
2. Choose **Scan** and Collection mode. Use one ordinary English starter/booster
   card. Send its printed number first so its expected catalog choices can be
   checked. Examples include ST01-003 or OP01-120; use a card you actually own.
3. Put the card on a plain surface in even light. Hold the camera steady with
   the full card visible. Avoid glare across the printed number.
4. Verify the recognized name/number. A sole verified printing and sole supported
   finish save automatically under the owner's current policy. When multiple
   printings are offered, choose the release matching your card; a finish choice
   is needed only if that exact printing has multiple finishes. Do not choose a
   different printing merely because it is the only available option; use Needs
   attention instead.
5. Check the successful receipt and Collection for the same card, printing, finish and
   quantity. Record whether the choice was clear and roughly how long it took.
6. Close the app and reopen it from the Home Screen. Check the saved row again.
   Refresh prices. Exact mapped finishes can price; held/unmapped printings must
   remain unavailable. A price here is aggregate market data, not a condition SKU.
7. Report the card number, printing/finish selected, anything incorrect or
   confusing, and whether the row survived reopening. Start with this one card
   before expanding the test matrix.

After the first success, test an uncatalogued number retaining scan evidence in
Needs attention and an offline relaunch. Then expand to different lighting,
printing distinctions, accessibility, provider sampling and the two-device sync
matrix in [release acceptance](one_piece_release_acceptance.md).

This normal local build uses the existing collection. It does not establish
CloudKit or multi-device acceptance.
