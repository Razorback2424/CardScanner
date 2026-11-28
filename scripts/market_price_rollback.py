"""Preserve and verify immutable pricing builds through full Firebase deploys."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import re
import secrets
from urllib.error import HTTPError

from market_price_feeds import MAX_SCOPE_BYTES, ORIGIN, R2_ORIGIN as R2, instant, packed, read_http, validate_site
import market_price_v2 as v2


HISTORY = f"{v2.V2}/history.json"
BUILDS = f"{v2.V2}/builds/"
VERIFIED = f"{v2.V2}/verified-builds/"
BUILD_ID = re.compile(r"[0-9a-f]{64}")


def build_ids(values):
    if not isinstance(values, list) or any(not isinstance(value, str) or not BUILD_ID.fullmatch(value)
                                           for value in values) or len(set(values)) != len(values):
        raise ValueError("Invalid v2 build inventory")
    return set(values)


def history_bytes(builds):
    raw = packed({"schemaVersion": 1, "builds": sorted(builds)})
    if len(raw) > v2.MAX_POINTER_BYTES:
        raise ValueError("V2 history exceeds its byte limit")
    return raw


def history(raw):
    value = json.loads(raw)
    if not isinstance(value, dict) or value.get("schemaVersion") != 1:
        raise ValueError("Invalid Firebase v2 history")
    builds = build_ids(value.get("builds"))
    if not builds or raw != history_bytes(builds):
        raise ValueError("Invalid Firebase v2 history")
    return builds


def fetch_path(origin, path, limit, *, fetch, absent_ok=False, fresh=False):
    suffix = f"?v2r={secrets.token_hex(8)}" if fresh else ""
    return fetch(f"{origin}/{path}{suffix}", limit, absent_ok=absent_ok)


def hosted_state(origin, fetch):
    pointer = fetch_path(origin, v2.LATEST, v2.MAX_POINTER_BYTES, fetch=fetch, absent_ok=True, fresh=True)
    inventory = fetch_path(origin, HISTORY, v2.MAX_POINTER_BYTES, fetch=fetch, absent_ok=True, fresh=True)
    if pointer is None and inventory is None:
        return None, None
    if pointer is None or inventory is None or v2.validate_pointer(pointer)["build"] not in history(inventory):
        raise ValueError("Firebase v2 pointer and history are incomplete")
    return pointer, inventory


def read_build(origin, build, fetch):
    prefix = f"{BUILDS}{build}/"

    def read(path, maximum):
        return fetch_path(origin, prefix + path, maximum, fetch=fetch)

    index_raw = read("index.json", v2.MAX_POINTER_BYTES)
    index = json.loads(index_raw)
    scopes = {path: read(path, MAX_SCOPE_BYTES) for path in v2.SCOPES}
    metadata = {"index.json": index_raw, **scopes}
    pointer = v2.pointer_for(index["sourceBuild"],
                             index["files"] + [v2.entry(path, raw) for path, raw in metadata.items()])
    if pointer["build"] != build:
        raise ValueError(f"V2 build metadata does not match its address: {build}")
    v2.validate_scopes([row["path"] for row in index["files"]], scopes)

    def download(row):
        path = row["path"]
        return path, read(path, row["byteCount"])

    with ThreadPoolExecutor(max_workers=12) as pool:
        rows = dict(pool.map(download, index["files"]))
    validate_site(index, rows)
    return packed(pointer), metadata | rows


def restore(site, fetch=read_http, *, prefer_r2=False):
    pointer, inventory = hosted_state(ORIGIN, fetch)
    if pointer is None:
        return
    current = v2.validate_pointer(pointer)["build"]
    for build in sorted(history(inventory)):
        try:
            raw, files = read_build(R2 if prefer_r2 else ORIGIN, build, fetch)
        except HTTPError as error:
            if not prefer_r2 or error.code != 404:
                raise
            # A retained Firebase-first build may never have reached R2.
            raw, files = read_build(ORIGIN, build, fetch)
        if build == current and raw != pointer:
            raise ValueError("Firebase v2 pointer does not match its build")
        v2.write_build(site / BUILDS / build, files)
    if hosted_state(ORIGIN, fetch) != (pointer, inventory):
        raise ValueError("Firebase v2 publication changed during history restore")
    (site / v2.LATEST).write_bytes(pointer)
    (site / HISTORY).write_bytes(inventory)


def inventory_ids(path):
    prefixes = json.loads(v2.bounded(path, v2.MAX_POINTER_BYTES))
    if prefixes is None:  # AWS CLI emits null when the bucket has no matching keys.
        return set()
    if not isinstance(prefixes, list):
        raise ValueError("Invalid R2 build prefixes")
    builds = []
    for prefix in prefixes:
        if isinstance(prefix, str) and prefix.startswith(BUILDS) and prefix.endswith("/"):
            builds.append(prefix[len(BUILDS):-1])
        elif isinstance(prefix, str) and prefix.startswith(VERIFIED) and prefix.endswith(".json"):
            builds.append(prefix[len(VERIFIED):-5])
        else:
            raise ValueError("Invalid R2 build inventory entry")
    return build_ids(builds)


def prepare(site, r2_builds, expected, fetch=read_http):
    primary = v2.validate_pointer(expected)
    confirm_primary_pointer(expected, fetch)
    history_path = site / HISTORY
    retained = history(history_path.read_bytes()) if history_path.exists() else set()
    firebase_path = site / v2.LATEST
    if firebase_path.exists():
        previous = v2.validate_pointer(firebase_path.read_bytes())
        if instant(primary["sourceBuild"]) < instant(previous["sourceBuild"]):
            raise ValueError("Refusing to publish an older Firebase v2 price build")
    if primary["build"] not in r2_builds:
        raise ValueError("R2 inventory is missing its active price build")
    for build in sorted(r2_builds - retained - {primary["build"]}):
        _, files = read_build(R2, build, fetch)
        v2.write_build(site / BUILDS / build, files)
    confirm_preserved(site, fetch)
    candidate = v2.stage(site, retain_history=True)
    if packed(candidate) != expected:
        raise ValueError("Firebase backup input does not reproduce the verified R2 build")
    confirm_primary_pointer(expected, fetch)
    history_path.write_bytes(history_bytes(retained | r2_builds))
    return candidate


def confirm_primary_pointer(expected, fetch=read_http):
    actual = fetch_path(R2, v2.LATEST, v2.MAX_POINTER_BYTES, fetch=fetch, fresh=True)
    if actual != expected:
        raise ValueError("R2 v2 pointer differs from the Firebase backup candidate")


def confirm_preserved(site, fetch=read_http):
    """Check that a catalog-only publisher still holds the last Firebase state."""
    local = tuple((site / path).read_bytes() if (site / path).is_file() else None
                  for path in (v2.LATEST, HISTORY))
    if hosted_state(ORIGIN, fetch) != local:
        raise ValueError("Firebase v2 publication changed before the catalog deploy")


def verify(site, fetch=read_http):
    confirm_preserved(site, fetch)
    raw_pointer = v2.bounded(site / v2.LATEST, v2.MAX_POINTER_BYTES)
    active = v2.validate_pointer(raw_pointer)["build"]
    builds = history(v2.bounded(site / HISTORY, v2.MAX_POINTER_BYTES))
    for build in sorted(builds):
        pointer, files = read_build(ORIGIN, build, fetch)
        if build == active and pointer != raw_pointer:
            raise ValueError("Firebase v2 active build differs from the verified capture")
        print(f"Verified Firebase v2 build {build}: {len(files)} files", flush=True)
    confirm_preserved(site, fetch)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("restore", "prepare", "confirm-preserved", "verify", "confirm-primary"))
    parser.add_argument("--site-root", required=True, type=Path)
    parser.add_argument("--r2-inventory", type=Path)
    parser.add_argument("--primary-pointer", type=Path)
    parser.add_argument("--prefer-r2", action="store_true")
    args = parser.parse_args()
    if args.action == "prepare":
        if args.r2_inventory is None or args.primary_pointer is None:
            parser.error("prepare requires --r2-inventory and --primary-pointer")
        prepare(args.site_root, inventory_ids(args.r2_inventory), v2.bounded(args.primary_pointer, v2.MAX_POINTER_BYTES))
    elif args.action == "confirm-primary":
        confirm_primary_pointer(v2.bounded(args.site_root / v2.LATEST, v2.MAX_POINTER_BYTES))
    elif args.action == "restore":
        restore(args.site_root, prefer_r2=args.prefer_r2)
    else:
        actions = {"confirm-preserved": confirm_preserved, "verify": verify}
        actions[args.action](args.site_root)


if __name__ == "__main__":
    main()
