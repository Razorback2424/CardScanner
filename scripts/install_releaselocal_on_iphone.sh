#!/bin/zsh
# Installs the ProfileLocal (ReleaseLocal) device build on a connected iPhone,
# but only after a successful backup of the installed app's data container.
#
#   DEVICE_ID=<udid> APP=<path to TradingCardScanner.app> BACKUP_DIR=<ssd dir> \
#     scripts/install_releaselocal_on_iphone.sh
#
# Steps: wait for the device; record the installed app; copy Library and
# Documents from the app's data container; refuse to install if the copy
# failed or holds no collection store; install; launch; after 90 s copy the
# container again so the active catalog revisions can be inspected.
# Never uninstalls the app or touches collection storage on the device.
set -u
: ${DEVICE_ID:?} ${APP:?} ${BACKUP_DIR:?}
BUNDLE=com.seankeller.CardScanner
STAMP=$(date +%Y%m%d-%H%M%S)
OUT="$BACKUP_DIR/$STAMP"
mkdir -p "$OUT"

[ -f "$APP/_CodeSignature/CodeResources" ] || { echo "App is not signed yet: $APP"; exit 2; }
codesign --verify --strict "$APP" || { echo "Signature check failed"; exit 2; }

echo "Waiting for $DEVICE_ID to be available…"
until xcrun devicectl list devices 2>/dev/null | grep "$DEVICE_ID" | grep -qE 'available|connected'; do sleep 10; done
echo "Device available."

xcrun devicectl device info apps --device "$DEVICE_ID" --bundle-id "$BUNDLE" > "$OUT/installed-app-before.txt" 2>&1
cat "$OUT/installed-app-before.txt"

backup_ok=0
for src in "Library" "Documents"; do
  if xcrun devicectl device copy from --device "$DEVICE_ID" --domain-type appDataContainer \
       --domain-identifier "$BUNDLE" --source "$src" --destination "$OUT/before/$src" > "$OUT/copy-$src.log" 2>&1; then
    echo "Copied $src"
  else
    echo "Could not copy $src (see $OUT/copy-$src.log)"
  fi
done
if find "$OUT/before/Library" -name 'default.store' -size +0 2>/dev/null | grep -q .; then
  backup_ok=1
fi
if [ $backup_ok -ne 1 ]; then
  if grep -qi 'no.*app\|not installed\|0 apps' "$OUT/installed-app-before.txt"; then
    echo "No existing app installed; nothing to back up."
  else
    echo "STOP: no collection store in the backup. The installed app may be a TestFlight build,"
    echo "which doesn't allow container copies. Export a CSV from the app, then rerun with FORCE_INSTALL=1."
    [ "${FORCE_INSTALL:-0}" = 1 ] || exit 3
  fi
fi
find "$OUT/before" -type f 2>/dev/null | sed "s#$OUT/before/##" > "$OUT/backup-manifest.txt"
echo "Backup: $OUT/before ($(wc -l < "$OUT/backup-manifest.txt") files)"

xcrun devicectl device install app --device "$DEVICE_ID" "$APP" 2>&1 | tee "$OUT/install.log"
xcrun devicectl device info apps --device "$DEVICE_ID" --bundle-id "$BUNDLE" > "$OUT/installed-app-after.txt" 2>&1
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE" 2>&1 | tee "$OUT/launch.log"
echo "Launched. Waiting 90 s for catalog activation…"
sleep 90
xcrun devicectl device copy from --device "$DEVICE_ID" --domain-type appDataContainer \
  --domain-identifier "$BUNDLE" --source "Library" --destination "$OUT/after/Library" > "$OUT/copy-after.log" 2>&1 \
  && echo "After-launch container: $OUT/after"
