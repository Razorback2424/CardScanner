#!/usr/bin/env python3
"""Backup-verified install of the ProfileLocal (ReleaseLocal) build on an iPhone.

Fails closed: the app is installed only after a complete, consistent and
restorable backup of the installed app's data container has been verified in
this same run. There is no override.

Subcommands
  backup         Back up and verify only. Never installs.
  install        backup, then install and launch the given .app, then report
                 the active catalogs from an after-launch container copy.
  catalog-report Report catalog sources/revisions from an existing container
                 copy and app bundle (offline).

Usage (all paths absolute; BACKUP_ROOT should be on the external SSD):
  scripts/iphone_releaselocal_install.py backup  --device UDID --backup-root DIR
  scripts/iphone_releaselocal_install.py install --device UDID --backup-root DIR --app PATH.app
  scripts/iphone_releaselocal_install.py catalog-report --container DIR --app PATH.app

What "verified" means (every check must pass, otherwise exit non-zero):
  1. The app is installed on the device and is not running (it is asked to
     quit with SIGTERM first, so SQLite files are not being written).
  2. Every top-level item of the data container except tmp/ is copied, and
     every copy command succeeds.
  3. The device's own file listing (paths and sizes) matches the copy
     exactly: nothing missing, nothing truncated.
  4. Library/Application Support/default.store exists; every *.store is
     copied together with its -wal/-shm, and passes PRAGMA integrity_check
     on a scratch copy, with the collection tables present.
  5. CollectionStorage/manifest.json, when present, parses as JSON.
  6. SHA256SUMS covers every file, is re-verified after writing, and the
     backup is made read-only.
  7. A restore set is prepared: each store checkpointed into a single file
     with empty -wal/-shm, so a restore cannot replay a newer WAL onto an
     older database. RESTORE.md gives the exact commands.
"""
from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import json
import os
import plistlib
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

BUNDLE_ID = "com.seankeller.CardScanner"
EXECUTABLE = "TradingCardScanner"
APP_SUPPORT = "Library/Application Support"
REQUIRED_STORE = f"{APP_SUPPORT}/default.store"
COLLECTION_TABLES = ("ZCOLLECTEDCARD", "ZCOLLECTIONACTIVITY")
SKIP_TOP_LEVEL = {"tmp"}


class Refused(Exception):
    """A check failed. Whether the app was already installed is tracked in
    INSTALLED so the final message never claims otherwise."""


INSTALLED = False


# ---------------------------------------------------------------- devicectl

def run(cmd: list[str], *, timeout: int = 900) -> subprocess.CompletedProcess:
    print("$ " + " ".join(cmd), flush=True)
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def devicectl_json(args: list[str], out: Path, *, timeout: int = 900) -> dict:
    """Runs a devicectl command with JSON output; raises Refused on failure."""
    result = run(["xcrun", "devicectl", *args, "--json-output", str(out), "--quiet"], timeout=timeout)
    if result.returncode != 0:
        raise Refused(f"devicectl {' '.join(args[:3])} failed ({result.returncode}): "
                      f"{(result.stderr or result.stdout).strip()[:800]}")
    try:
        return json.loads(out.read_text())
    except (OSError, ValueError) as error:
        raise Refused(f"devicectl wrote no readable JSON to {out}: {error}")


def _dicts(node):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from _dicts(value)
    elif isinstance(node, list):
        for value in node:
            yield from _dicts(value)


def installed_app(info: dict) -> dict | None:
    matches = [d for d in _dicts(info.get("result", info)) if d.get("bundleIdentifier") == BUNDLE_ID]
    if len(matches) > 1:
        raise Refused("Device reported more than one app entry for the bundle ID")
    return matches[0] if matches else None


def app_process_ids(processes: dict) -> list[int]:
    """PIDs whose executable lives inside a TradingCardScanner.app bundle."""
    pids = []
    entries = [d for d in _dicts(processes.get("result", processes))
               if isinstance(d.get("processIdentifier"), int)]
    if not entries:
        raise Refused("Could not read the device process list (no processIdentifier entries)")
    for entry in entries:
        executable = str(entry.get("executable") or entry.get("executableURL") or entry.get("name") or "")
        if f"{EXECUTABLE}.app/{EXECUTABLE}" in executable:
            pids.append(entry["processIdentifier"])
    return pids


PATH_KEYS = ("relativePath", "path", "name")
SIZE_KEYS = ("size", "fileSize", "byteCount")


def file_listing(listing: dict) -> dict[str, int]:
    """Maps container-relative file paths to sizes from `info files` JSON.

    Raises Refused when the format can't be read with certainty, rather
    than guessing which entries are files."""
    files: dict[str, int] = {}
    result = listing.get("result", listing)
    entries = result.get("files") if isinstance(result, dict) and isinstance(result.get("files"), list) else list(_dicts(result))
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        path = next((entry[k] for k in PATH_KEYS if isinstance(entry.get(k), str)), None)
        if path is None:
            continue
        kind = str(entry.get("type", entry.get("fileType", ""))).lower()
        # devicectl (Xcode 27): {"relativePath", "metadata": {"size"},
        # "resources": {"isDirectory", "isSymbolicLink"}}
        resources = entry.get("resources") if isinstance(entry.get("resources"), dict) else {}
        metadata = entry.get("metadata") if isinstance(entry.get("metadata"), dict) else {}
        if resources.get("isSymbolicLink") is True:
            raise Refused(f"Container holds a symbolic link the backup can't verify: {path!r}")
        if (entry.get("isDirectory") is True or resources.get("isDirectory") is True
                or "directory" in kind or "symlink" in kind or "link" == kind):
            continue
        size = next((d[k] for d in (entry, metadata) for k in SIZE_KEYS if isinstance(d.get(k), int)), None)
        if size is None:
            if kind in ("", "file", "regular", "regularfile"):
                raise Refused(f"File listing entry has no size: {path!r}. Inspect the JSON and extend file_listing.")
            continue
        path = path.lstrip("/")
        if path.startswith("./"):
            path = path[2:]
        if path in files and files[path] != size:
            raise Refused(f"File listing reports {path!r} twice with different sizes")
        files[path] = size
    if not files:
        raise Refused("Could not read any files from the device listing")
    return files


# ---------------------------------------------------------- backup checks

def local_files(root: Path) -> dict[str, int]:
    return {str(p.relative_to(root)): p.stat().st_size for p in root.rglob("*")
            if p.is_file() and not p.is_symlink()}


def compare_listing(device: dict[str, int], copied: dict[str, int]) -> None:
    device = {p: s for p, s in device.items() if p.split("/", 1)[0] not in SKIP_TOP_LEVEL}
    missing = sorted(set(device) - set(copied))
    resized = sorted(p for p in set(device) & set(copied) if device[p] != copied[p])
    if missing or resized:
        raise Refused("Backup does not match the device: "
                      f"{len(missing)} missing (e.g. {missing[:5]}), "
                      f"{len(resized)} with different sizes (e.g. {resized[:5]})")


def store_files(root: Path) -> list[Path]:
    return sorted(p for p in root.rglob("*.store") if p.is_file())


def check_store(store: Path, *, required_tables: tuple[str, ...] = ()) -> dict:
    """integrity_check on a scratch copy of the store with its -wal/-shm, so
    the backup itself is never opened (opening can checkpoint the WAL)."""
    with tempfile.TemporaryDirectory() as scratch:
        copy = Path(scratch) / store.name
        shutil.copy2(store, copy)
        for suffix in ("-wal", "-shm"):
            side = store.with_name(store.name + suffix)
            if side.exists():
                shutil.copy2(side, copy.with_name(copy.name + suffix))
        connection = sqlite3.connect(f"file:{copy}?mode=rw", uri=True)
        try:
            result = connection.execute("PRAGMA integrity_check").fetchall()
            if result != [("ok",)]:
                raise Refused(f"{store.name}: integrity_check reported {result[:5]}")
            tables = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            missing = [t for t in required_tables if t not in tables]
            if missing:
                raise Refused(f"{store.name}: missing tables {missing}")
            counts = {t: connection.execute(f'SELECT COUNT(*) FROM "{t}"').fetchone()[0]
                      for t in sorted(tables) if t.startswith("Z") and t not in ("Z_METADATA", "Z_MODELCACHE")}
        finally:
            connection.close()
    return {"file": store.name, "integrity": "ok", "rowCounts": counts}


def prepare_restore_store(store: Path, destination: Path) -> None:
    """Writes a checkpointed single-file copy with empty -wal/-shm."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(store, destination)
    for suffix in ("-wal", "-shm"):
        side = store.with_name(store.name + suffix)
        if side.exists():
            shutil.copy2(side, destination.with_name(destination.name + suffix))
    connection = sqlite3.connect(str(destination))
    try:
        busy, _, _ = connection.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
        if busy:
            raise Refused(f"{store.name}: checkpoint for the restore set did not complete")
        if connection.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
            raise Refused(f"{store.name}: restore copy failed integrity_check")
    finally:
        connection.close()
    for suffix in ("-wal", "-shm"):
        side = destination.with_name(destination.name + suffix)
        side.write_bytes(b"")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def write_checksums(root: Path) -> Path:
    sums = root / "SHA256SUMS"
    lines = [f"{sha256(p)}  {p.relative_to(root)}" for p in sorted(root.rglob("*"))
             if p.is_file() and p != sums]
    sums.write_text("\n".join(lines) + "\n")
    return sums


def verify_checksums(root: Path) -> int:
    sums = root / "SHA256SUMS"
    count = 0
    for line in sums.read_text().splitlines():
        digest, relative = line.split("  ", 1)
        if sha256(root / relative) != digest:
            raise Refused(f"Checksum mismatch after writing: {relative}")
        count += 1
    listed = {line.split("  ", 1)[1] for line in sums.read_text().splitlines()}
    present = {str(p.relative_to(root)) for p in root.rglob("*") if p.is_file() and p != sums}
    if listed != present:
        raise Refused("SHA256SUMS does not cover exactly the files in the backup")
    return count


def make_read_only(root: Path) -> None:
    for path in sorted(root.rglob("*"), reverse=True):
        mode = path.stat().st_mode
        path.chmod(mode & ~(stat.S_IWUSR | stat.S_IWGRP | stat.S_IWOTH))


def normalize_copy(destination: Path) -> None:
    """devicectl may place a copied directory inside the destination
    (destination/Library/Library). Flatten exactly that shape; any other
    layout is left for compare_listing to refuse."""
    nested = destination / destination.name
    if destination.is_dir() and nested.is_dir() and [p.name for p in destination.iterdir()] == [destination.name]:
        staging = destination.with_name(destination.name + ".nested")
        nested.rename(staging)
        destination.rmdir()
        staging.rename(destination)


def verify_backup_tree(container: Path, device_files: dict[str, int]) -> dict:
    """All offline checks over a copied container. Returns the summary."""
    compare_listing(device_files, local_files(container))
    if not (container / REQUIRED_STORE).is_file():
        raise Refused(f"No collection store at {REQUIRED_STORE} in the backup")
    stores = []
    for store in store_files(container / APP_SUPPORT):
        tables = COLLECTION_TABLES if store.name == "default.store" else ()
        stores.append(check_store(store, required_tables=tables))
    manifest = container / APP_SUPPORT / "CardScanner/CollectionStorage/manifest.json"
    if manifest.exists():
        try:
            json.loads(manifest.read_text())
        except ValueError as error:
            raise Refused(f"Collection manifest is not valid JSON: {error}")
    return {"stores": stores, "fileCount": len(device_files),
            "collectionManifest": manifest.exists()}


# ------------------------------------------------------------ app checks

def check_app(app: Path, device: str) -> dict:
    info = plistlib.loads((app / "Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != BUNDLE_ID:
        raise Refused(f"App bundle ID is {info.get('CFBundleIdentifier')!r}")
    verify = run(["codesign", "--verify", "--strict", "--deep", str(app)])
    if verify.returncode != 0:
        raise Refused(f"codesign verification failed: {verify.stderr.strip()[:400]}")
    entitlements = run(["codesign", "-d", "--entitlements", "-", "--xml", str(app)])
    if entitlements.returncode != 0:
        raise Refused("Could not read the app's signed entitlements")
    if "icloud" in entitlements.stdout.lower():
        raise Refused("App is signed with iCloud entitlements; this installer is for the local-only build")
    profile = run(["security", "cms", "-D", "-i", str(app / "embedded.mobileprovision")])
    if profile.returncode != 0:
        raise Refused("Could not read embedded.mobileprovision")
    provision = plistlib.loads(profile.stdout.encode())
    if device not in provision.get("ProvisionedDevices", []):
        raise Refused("The embedded provisioning profile does not include this device")
    expires = provision["ExpirationDate"]  # plistlib returns naive UTC
    now = dt.datetime.now(dt.timezone.utc)
    if expires.tzinfo is None:
        now = now.replace(tzinfo=None)
    if expires <= now:
        raise Refused(f"The provisioning profile expired on {expires}")
    return {"bundleID": BUNDLE_ID, "version": info.get("CFBundleShortVersionString"),
            "build": info.get("CFBundleVersion"), "profileExpires": str(expires),
            "executableSHA256": sha256(app / EXECUTABLE)}


# ------------------------------------------------------ catalog reporting

def _envelope_payload(path: Path) -> dict | None:
    try:
        envelope = json.loads(path.read_text())
        payload = envelope.get("payload")
        if isinstance(payload, str):
            payload = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
        return {"keyID": envelope.get("keyID"), **payload} if isinstance(payload, dict) else None
    except (OSError, ValueError):
        return None


def catalog_report(container: Path | None, app: Path) -> list[dict]:
    """Per game: packaged revision (from the app) and persisted active slot
    (from the container). The app reads the current slot at launch and only
    replaces it with a newer verified release, so the active revision is the
    higher of the two for Pokémon/Magic; One Piece, Yu-Gi-Oh and Lorcana load
    their bundled files in this build configuration."""
    support = container / APP_SUPPORT if container else None
    rows = []

    def slot(relative: str) -> dict | None:
        return _envelope_payload(support / relative) if support and (support / relative).exists() else None

    pokemon = _envelope_payload(app / "PokemonCatalogRelease/catalog-release.json") or {}
    stored = slot("BrowseCatalogCache/CatalogReleases/catalog-release-current.json")
    packaged = pokemon.get("revision")
    active = max(r for r in (packaged, (stored or {}).get("revision")) if r is not None) if packaged or stored else None
    rows.append({"game": "Pokémon", "packaged": packaged, "persistedCurrent": (stored or {}).get("revision"),
                 "active": active, "source": "persisted signed release" if stored and stored["revision"] >= (packaged or 0)
                 else "bundled signed release",
                 "counts": f"{len(pokemon.get('sets', []))} sets"})

    magic = json.loads((app / "MagicCatalogSeed/catalog.json").read_text())
    stored = slot("BrowseCatalogCache/MagicCatalogReleases/magic-catalog-release-current.json")
    rows.append({"game": "Magic", "packaged": magic.get("revision"),
                 "persistedCurrent": (stored or {}).get("revision"),
                 "active": max(r for r in (magic.get("revision"), (stored or {}).get("revision")) if r is not None),
                 "source": "persisted signed release" if stored else "bundled seed",
                 "counts": f"{len(magic.get('sets', []))} sets"})

    owner = _envelope_payload(app / "OnePieceOwnerCatalog/one-piece-owner-catalog.json") or {}
    registry = owner.get("registry", {})
    rows.append({"game": "One Piece", "packaged": owner.get("revision"), "persistedCurrent": None,
                 "active": owner.get("revision"), "source": f"bundled owner catalog ({owner.get('keyID')})",
                 "counts": f"{len(registry.get('canonicalCards', []))} cards, "
                           f"{len(registry.get('printings', []))} printings"})

    ygo = json.loads((app / "YuGiOhCatalogSeed/catalog.json").read_text())
    rows.append({"game": "Yu-Gi-Oh", "packaged": ygo.get("generation"), "persistedCurrent": None,
                 "active": ygo.get("generation"), "source": "bundled seed",
                 "counts": f"{len(ygo.get('cards', []))} cards, {len(ygo.get('printings', []))} printings"})

    lorcana = json.loads((app / "LorcanaCatalogSeed/discovery.json").read_text())
    rows.append({"game": "Lorcana", "packaged": lorcana.get("generatedOn"), "persistedCurrent": None,
                 "active": lorcana.get("generatedOn"), "source": "bundled seed",
                 "counts": f"{len(lorcana.get('cards', []))} cards, {len(lorcana.get('sealed', []))} sealed"})
    return rows


def print_catalog_report(rows: list[dict]) -> None:
    print(f"{'Game':<10} {'Source':<44} {'Packaged':<24} {'Persisted':<10} {'Active':<24} Counts")
    for r in rows:
        print(f"{r['game']:<10} {r['source']:<44} {str(r['packaged']):<24} {str(r['persistedCurrent']):<10} "
              f"{str(r['active']):<24} {r['counts']}")


# ------------------------------------------------------------- workflow

def backup(device: str, backup_root: Path) -> Path:
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = backup_root / stamp
    work = run_dir / "devicectl"
    container = run_dir / "container"
    work.mkdir(parents=True)

    apps = devicectl_json(["device", "info", "apps", "--device", device, "--bundle-id", BUNDLE_ID],
                          work / "apps-before.json")
    app = installed_app(apps)
    if app is None:
        raise Refused("CardScanner is not installed on the device; there is no collection to protect. "
                      "Install it manually only if that is really expected.")

    pids = app_process_ids(devicectl_json(["device", "info", "processes", "--device", device], work / "processes.json"))
    for pid in pids:
        result = run(["xcrun", "devicectl", "device", "process", "terminate", "--device", device, "--pid", str(pid)])
        if result.returncode != 0:
            raise Refused(f"Could not quit the running app (pid {pid}): {result.stderr.strip()[:400]}")
    if pids:
        time.sleep(3)
        if app_process_ids(devicectl_json(["device", "info", "processes", "--device", device],
                                          work / "processes-after-quit.json")):
            raise Refused("The app is still running after being asked to quit")

    listing = devicectl_json(["device", "info", "files", "--device", device, "--domain-type", "appDataContainer",
                              "--domain-identifier", BUNDLE_ID], work / "files.json")
    device_files = file_listing(listing)
    top_level = sorted({p.split("/", 1)[0] for p in device_files if "/" in p} - SKIP_TOP_LEVEL)
    if "Library" not in top_level:
        raise Refused(f"Container has no Library directory (top level: {top_level})")
    loose = sorted(p for p in device_files if "/" not in p)
    for item in top_level + loose:
        result = run(["xcrun", "devicectl", "device", "copy", "from", "--device", device,
                      "--domain-type", "appDataContainer", "--domain-identifier", BUNDLE_ID,
                      "--source", item, "--destination", str(container / item)], timeout=3600)
        (work / f"copy-{item.replace('/', '_')}.log").write_text(result.stdout + result.stderr)
        if result.returncode != 0:
            raise Refused(f"Copy of {item} failed ({result.returncode}); see {work}")
        normalize_copy(container / item)

    summary = verify_backup_tree(container, device_files)
    for store in store_files(container / APP_SUPPORT):
        relative = store.relative_to(container)
        prepare_restore_store(store, run_dir / "restore" / relative)
    summary.update({"device": device, "installedApp": {k: app.get(k) for k in
                    ("bundleIdentifier", "version", "bundleVersion", "name", "url") if k in app},
                    "createdAt": stamp})
    (run_dir / "backup-summary.json").write_text(json.dumps(summary, indent=2, default=str))
    (run_dir / "RESTORE.md").write_text(restore_instructions(device, run_dir))
    count = verify_checksums(run_dir) if write_checksums(run_dir) else 0
    make_read_only(run_dir)
    print(f"Backup verified: {run_dir} ({count} files checksummed; stores: "
          + ", ".join(f"{s['file']} {s['rowCounts'].get('ZCOLLECTEDCARD', '-')} cards" for s in summary["stores"]) + ")")
    return run_dir


def restore_instructions(device: str, run_dir: Path) -> str:
    return f"""# Restore this backup

1. Reinstall the previous app build first if the new build migrated the
   store (the new schema may not open in an older build). The build that was
   installed is recorded in backup-summary.json (installedApp).
2. Quit the app on the phone.
3. Copy the restore set back. It holds each store checkpointed into one file
   with empty -wal/-shm, so a newer WAL on the phone cannot be replayed onto
   the older database:

   for f in "{run_dir}/restore/Library/Application Support/"*.store*; do
     xcrun devicectl device copy to --device {device} --domain-type appDataContainer \\
       --domain-identifier {BUNDLE_ID} --source "$f" \\
       --destination "Library/Application Support/$(basename "$f")"
   done

   Then list the container (`xcrun devicectl device info files ...`) and
   confirm each store, -wal (0 bytes) and -shm (0 bytes) landed, before
   opening the app. This restore path has not been exercised on a device.

4. If anything else needs restoring, the untouched copy of the whole
   container is in container/ (verify with `shasum -a 256 -c SHA256SUMS`).
"""


def install(device: str, backup_root: Path, app_path: Path) -> None:
    app_summary = check_app(app_path, device)
    print("App checks passed:", json.dumps(app_summary))
    run_dir = backup(device, backup_root)
    work = Path(tempfile.mkdtemp(prefix="install-", dir=run_dir.parent))

    result = run(["xcrun", "devicectl", "device", "install", "app", "--device", device, str(app_path)], timeout=1800)
    (work / "install.log").write_text(result.stdout + result.stderr)
    if result.returncode != 0:
        raise Refused(f"Install failed ({result.returncode}); the device keeps the previous app. See {work}")
    global INSTALLED
    INSTALLED = True
    after = installed_app(devicectl_json(["device", "info", "apps", "--device", device, "--bundle-id", BUNDLE_ID],
                                         work / "apps-after.json"))
    if after is None:
        raise Refused("Install reported success but the app is not listed afterwards")

    result = run(["xcrun", "devicectl", "device", "process", "launch", "--device", device, BUNDLE_ID])
    (work / "launch.log").write_text(result.stdout + result.stderr)
    if result.returncode != 0:
        raise Refused(f"Launch failed ({result.returncode}): {result.stderr.strip()[:400]} "
                      "(an unlocked phone and a trusted developer certificate are required)")
    print("Launched; waiting 90 s for storage and catalog activation…", flush=True)
    time.sleep(90)
    after_copy = work / "after-launch"
    result = run(["xcrun", "devicectl", "device", "copy", "from", "--device", device,
                  "--domain-type", "appDataContainer", "--domain-identifier", BUNDLE_ID,
                  "--source", APP_SUPPORT, "--destination", str(after_copy / APP_SUPPORT)], timeout=3600)
    if result.returncode != 0:
        raise Refused(f"After-launch copy failed: {result.stderr.strip()[:400]}")
    if not (after_copy / REQUIRED_STORE).is_file():
        raise Refused("After launch the collection store is missing; restore from the backup")
    rows = catalog_report(after_copy, app_path)
    (work / "catalog-report.json").write_text(json.dumps(rows, indent=2))
    print_catalog_report(rows)
    print(f"Installed and launched. Backup: {run_dir}  Install logs: {work}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("backup", "install"):
        p = sub.add_parser(name)
        p.add_argument("--device", required=True)
        p.add_argument("--backup-root", required=True, type=Path)
        if name == "install":
            p.add_argument("--app", required=True, type=Path)
    p = sub.add_parser("catalog-report")
    p.add_argument("--container", type=Path)
    p.add_argument("--app", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == "backup":
            backup(args.device, args.backup_root)
        elif args.command == "install":
            install(args.device, args.backup_root, args.app)
        else:
            print_catalog_report(catalog_report(args.container, args.app))
    except (Refused, subprocess.TimeoutExpired) as refusal:
        state = ("The new build IS installed; the verified backup is listed above." if INSTALLED
                 else "Nothing was installed.")
        print(f"REFUSED: {refusal}\n{state}", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
