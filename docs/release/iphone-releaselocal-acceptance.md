# iPhone acceptance: ProfileLocal (ReleaseLocal) build

**Status — 2026-11-13:** installed through the verified backup; data preserved after first launch; checklist not yet run. Build from `main` at
`4c4a2e6` or later, ProfileLocal scheme, `ReleaseLocal` configuration
(optimized, no DEBUG, `LOCAL_ONLY_SIGNING`, `NO_CLOUDKIT`,
`UNVERIFIED_REPORTS_LOCAL_BETA`). Local storage only. CloudKit sync and
two-device tests are separate release gates
([plan](../plans/unverified_pokemon_reports.md#release-gates)).

## Install

Install only through the backup-verified installer. It quits the app, copies
the whole data container, checks it against the device's own file listing,
runs SQLite `integrity_check` on every store with its WAL, checksums the
backup, prepares a restore set, and only then installs. There is no override.

```bash
DEVICE_ID=<udid> BACKUP_DIR="/Volumes/<ssd>/CardScannerDeviceBackups" \
APP="<DerivedData>/Build/Products/ReleaseLocal-iphoneos/TradingCardScanner.app" \
  scripts/install_releaselocal_on_iphone.sh
```

Prerequisites: the app is signed (the keychain must allow `codesign` to use
the development key), the phone is connected, unlocked, trusted and in
Developer Mode, and the installed app is a development build. A TestFlight or
App Store install refuses the container copy, so the installer stops. The
development profile expires one week after it was issued; the installer
refuses an expired profile.

## Confirm the active catalogs

The installer copies `Library/Application Support` 90 s after launch and
prints the catalog report. To rerun it against any container copy:

```bash
python3 -I scripts/iphone_releaselocal_install.py catalog-report --container <copy> --app <app>
```

Then confirm each game in the running app. The report's Pokémon "Persisted"
value is written by the running app when it activates a release; the other
games load bundled files, so the in-app marker is the observation.

| Game | Expected | Evidence |
| --- | --- | --- |
| Pokémon | Signed revision 24, 76 sets | Report: Persisted 24. Browse shows Delta Reign (DLR) and MEP Black Star Promos 111–117 |
| One Piece | Owner catalog revision 10: 2,850 cards, 4,383 printings | Browse lists Extra Booster: One Piece Heroines Edition Vol. 2 (EB05) and OP17 |
| Magic | Bundled seed revision 1, 910 sets | Report: Persisted None (no hosted release yet) |
| Yu-Gi-Oh | Bundled seed `yugioh-en-fe3eaff93a48` | Browse lists Magnificent Maestros (MAMS) |
| Lorcana | Bundled discovery from 2026-11-08 | Browse finds Beast – Snowfield Troublemaker (1/PD1) |

## Checklist

Write down the collection's card count and total value before installing.

1. **Data preserved** — [ ] Same card count and value after first launch.
   [ ] Settings shows no iCloud sync.
2. **Pokémon scans** — [ ] Three ordinary cards identify and save; quantity
   rises by one each. [ ] Rescanning one gives quantity 2, not a new row.
   [ ] Prices appear (network needed).
3. **Recent Pokémon** — [ ] A Delta Reign card scans and saves. [ ] A reverse
   holo keeps the right finish; fixing the finish from the receipt works.
4. **One Piece** — [ ] Browse a set and save a card. [ ] Scan a card; it
   identifies and saves. [ ] Open a sealed product.
5. **Unverified variant** — [ ] Receipt → "Report a different variant" →
   save: the row reads "Unverified", has no price and is left out of value.
   [ ] Collection → Unverified cards lists it. [ ] A failed scan of an
   unlisted card offers "Add unverified card" with set and number prefilled.
   [ ] In airplane mode a failed lookup does not offer it.
6. **Review and link** — [ ] "Link to verified card…" → choose card and
   finish: "From your report, now verified", priced, same quantity.
   [ ] History shows the add and the link, nothing duplicated.
   [ ] "Undo link" returns it to Unverified, same quantity, unpriced.
7. **Quantity and history** — [ ] Removing a copy lowers quantity and value
   and is logged; restoring it brings it back.
8. **Persistence** — [ ] Force-quit and reopen: everything above is
   unchanged. [ ] Launch in airplane mode: catalogs and collection open.

## If something goes wrong

Don't uninstall. The backup folder's `RESTORE.md` has the exact restore
commands. A restore also needs the previously installed build, because this
build migrates the store on first launch.
