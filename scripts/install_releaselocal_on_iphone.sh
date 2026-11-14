#!/bin/zsh
# Backup-verified install of the ProfileLocal (ReleaseLocal) build on an iPhone.
# All logic and checks live in iphone_releaselocal_install.py; this wrapper
# only supplies the paths. Installation happens only after a complete,
# consistent, restorable backup of the app's data container is verified in
# the same run. There is no override.
#
#   DEVICE_ID=<udid> APP=<path to TradingCardScanner.app> BACKUP_DIR=<ssd dir> \
#     scripts/install_releaselocal_on_iphone.sh            # backup + install
#   DEVICE_ID=<udid> BACKUP_DIR=<ssd dir> \
#     scripts/install_releaselocal_on_iphone.sh backup     # backup only
set -euo pipefail
: ${DEVICE_ID:?set DEVICE_ID} ${BACKUP_DIR:?set BACKUP_DIR}
here=${0:A:h}
if [[ ${1:-install} == backup ]]; then
  exec python3 -I "$here/iphone_releaselocal_install.py" backup --device "$DEVICE_ID" --backup-root "$BACKUP_DIR"
fi
: ${APP:?set APP}
exec python3 -I "$here/iphone_releaselocal_install.py" install --device "$DEVICE_ID" --backup-root "$BACKUP_DIR" --app "$APP"
