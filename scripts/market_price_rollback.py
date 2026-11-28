"""Preserve, prune, and verify immutable pricing builds through full Firebase deploys."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
import json
import os
from pathlib import Path
import re
import secrets
import shutil
from urllib.error import HTTPError
from urllib.parse import urlencode

from market_price_feeds import (
    MAX_SCOPE_BYTES, NAMESPACE, ORIGIN, R2_ORIGIN as R2, instant, packed, read_http, validate_site,
)
import market_price_v2 as v2


HISTORY = f"{v2.V2}/history.json"
BUILDS = f"{v2.V2}/builds/"
VERIFIED = f"{v2.V2}/verified-builds/"
BUILD_ID = re.compile(r"[0-9a-f]{64}")
DEFAULT_FIREBASE_RETENTION_DAYS = 7
FIREBASE_HOSTING_READONLY_SCOPE = "https://www.googleapis.com/auth/firebase.readonly"
MAX_HOSTING_FILE_PAGES = 100


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


def retention_cutoff(active_source_build, retention_days=DEFAULT_FIREBASE_RETENTION_DAYS):
    """Return the oldest sourceBuild timestamp retained on Firebase, or None if unbounded."""
    if retention_days is None:
        return None
    if type(retention_days) is not int or retention_days < 0:
        raise ValueError(f"Invalid Firebase retention_days: {retention_days!r}")
    return instant(active_source_build) - timedelta(days=retention_days)


def build_source_timestamp(origin, build, fetch, *, site=None):
    """Read only index.json (locally if staged, else 1 small HTTP read) to get a build's sourceBuild."""
    if site is not None:
        local_index = Path(site) / BUILDS / build / "index.json"
        if local_index.is_file():
            raw = v2.bounded(local_index, v2.MAX_POINTER_BYTES)
            return instant(json.loads(raw)["sourceBuild"])
    raw = fetch_path(origin, f"{BUILDS}{build}/index.json", v2.MAX_POINTER_BYTES, fetch=fetch)
    return instant(json.loads(raw)["sourceBuild"])


def prune_expired_builds(site, builds, active_build, active_source_build, *,
                         retention_days=DEFAULT_FIREBASE_RETENTION_DAYS):
    """Keep the active build and builds within retention_days on Firebase; prune older staged builds.

    R2 retains all builds indefinitely; Firebase only needs the active build plus recent builds
    that in-flight clients may still reference during rollback.
    """
    cutoff = retention_cutoff(active_source_build, retention_days)
    kept = set()
    pruned = set()
    for build in sorted(builds):
        if build == active_build or cutoff is None:
            kept.add(build)
            continue
        index_path = Path(site) / BUILDS / build / "index.json"
        if not index_path.is_file():
            raise ValueError(f"Staged Firebase v2 build is missing index.json: {build}")
        source_time = instant(json.loads(v2.bounded(index_path, v2.MAX_POINTER_BYTES))["sourceBuild"])
        if source_time < cutoff:
            pruned.add(build)
            build_dir = Path(site) / BUILDS / build
            if build_dir.exists():
                shutil.rmtree(build_dir)
        else:
            kept.add(build)
    if pruned:
        print(f"Pruned {len(pruned)} expired Firebase v2 build(s) older than {retention_days}d (retained {len(kept)})",
              flush=True)
    return kept, pruned


def _write_state_file(state_file, *, previous_builds, retained_builds, active_build, pruned_builds):
    if state_file is None:
        return
    path = Path(state_file)
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schemaVersion": 1,
        "activeBuild": active_build,
        "previousBuilds": sorted(previous_builds),
        "newBuilds": sorted(retained_builds - previous_builds),
        "retainedBuilds": sorted(retained_builds),
        "prunedBuilds": sorted(pruned_builds),
    }
    path.write_bytes(packed(payload))


def _load_state_file(state_file):
    if state_file is None:
        return None
    path = Path(state_file)
    if not path.is_file():
        return None
    doc = json.loads(v2.bounded(path, v2.MAX_POINTER_BYTES))
    if not isinstance(doc, dict) or doc.get("schemaVersion") != 1:
        raise ValueError("Invalid Firebase v2 deploy state file")
    return {
        "activeBuild": doc["activeBuild"],
        "previousBuilds": build_ids(doc.get("previousBuilds", [])),
        "newBuilds": build_ids(doc.get("newBuilds", [])),
    }


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


def _recent_missing_builds(r2_builds, retained, active_build, cutoff, fetch):
    candidates = sorted(r2_builds - retained - {active_build})
    if not candidates or cutoff is None:
        return candidates
    if len(candidates) == 1:
        return [candidates[0]] if build_source_timestamp(R2, candidates[0], fetch) >= cutoff else []
    with ThreadPoolExecutor(max_workers=12) as pool:
        timestamps = list(pool.map(lambda b: build_source_timestamp(R2, b, fetch), candidates))
    return [b for b, ts in zip(candidates, timestamps) if ts >= cutoff]


def prepare(site, r2_builds, expected, fetch=read_http, *,
            retention_days=DEFAULT_FIREBASE_RETENTION_DAYS, state_file=None):
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
    cutoff = retention_cutoff(primary["sourceBuild"], retention_days)
    fetched = set()
    for build in _recent_missing_builds(r2_builds, retained, primary["build"], cutoff, fetch):
        _, files = read_build(R2, build, fetch)
        v2.write_build(site / BUILDS / build, files)
        fetched.add(build)
    confirm_preserved(site, fetch)
    candidate = v2.stage(site, retain_history=True)
    if packed(candidate) != expected:
        raise ValueError("Firebase backup input does not reproduce the verified R2 build")
    confirm_primary_pointer(expected, fetch)
    kept, pruned = prune_expired_builds(
        site, retained | fetched | {primary["build"]}, primary["build"], primary["sourceBuild"],
        retention_days=retention_days,
    )
    history_path.write_bytes(history_bytes(kept))
    _write_state_file(
        state_file, previous_builds=retained, retained_builds=kept,
        active_build=primary["build"], pruned_builds=pruned,
    )
    return candidate


def sync_r2(site, r2_builds, fetch=read_http, *,
            retention_days=DEFAULT_FIREBASE_RETENTION_DAYS, state_file=None):
    """Catch up Firebase v2 prices from R2 during a catalog backup deploy.

    Unlike prepare(), this does not re-stage v2 from mutable catalog scopes,
    because a freshly published R2 catalog can legitimately advance its scope
    before the next scheduled price capture runs.
    """
    expected = fetch_path(R2, v2.LATEST, v2.MAX_POINTER_BYTES, fetch=fetch, fresh=True)
    primary = v2.validate_pointer(expected)
    history_path = site / HISTORY
    retained = history(history_path.read_bytes()) if history_path.exists() else set()
    if primary["build"] not in (r2_builds | retained):
        raise ValueError("R2 inventory is missing its active price build")
    firebase_path = site / v2.LATEST
    if firebase_path.exists():
        previous = v2.validate_pointer(firebase_path.read_bytes())
        if instant(primary["sourceBuild"]) < instant(previous["sourceBuild"]):
            raise ValueError("Refusing to publish an older Firebase v2 price build")
    cutoff = retention_cutoff(primary["sourceBuild"], retention_days)
    to_fetch = _recent_missing_builds(r2_builds, retained, primary["build"], cutoff, fetch)
    if primary["build"] not in retained:
        to_fetch = sorted(set(to_fetch) | {primary["build"]})
    fetched = set()
    for build in to_fetch:
        raw, files = read_build(R2, build, fetch)
        if build == primary["build"] and raw != expected:
            raise ValueError("R2 active v2 build disagrees with its pointer")
        v2.write_build(site / BUILDS / build, files)
        fetched.add(build)
    active_index = v2.bounded(site / BUILDS / primary["build"] / "index.json", v2.MAX_POINTER_BYTES)
    legacy_index = v2.bounded(site / NAMESPACE / "index.json", v2.MAX_POINTER_BYTES)
    if legacy_index != active_index:
        raise ValueError("R2 legacy v1 prices do not match the active v2 build")
    confirm_preserved(site, fetch)
    confirm_primary_pointer(expected, fetch)
    kept, pruned = prune_expired_builds(
        site, retained | fetched | {primary["build"]}, primary["build"], primary["sourceBuild"],
        retention_days=retention_days,
    )
    (site / v2.LATEST).parent.mkdir(parents=True, exist_ok=True)
    (site / v2.LATEST).write_bytes(expected)
    history_path.write_bytes(history_bytes(kept))
    _write_state_file(
        state_file, previous_builds=retained, retained_builds=kept,
        active_build=primary["build"], pruned_builds=pruned,
    )
    return primary


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


def local_build_expected_paths(site, build):
    """Validate local staged build metadata against its build ID and return expected Hosting paths."""
    build_dir = Path(site) / BUILDS / build
    index_raw = v2.bounded(build_dir / "index.json", v2.MAX_POINTER_BYTES)
    index = json.loads(index_raw)
    scopes = {path: v2.bounded(build_dir / path, MAX_SCOPE_BYTES) for path in v2.SCOPES}
    metadata = {"index.json": index_raw, **scopes}
    pointer = v2.pointer_for(
        index["sourceBuild"],
        index["files"] + [v2.entry(path, raw) for path, raw in metadata.items()],
    )
    if pointer["build"] != build:
        raise ValueError(f"Local staged v2 build metadata does not match its address: {build}")
    v2.validate_scopes([row["path"] for row in index["files"]], scopes)
    rel_paths = sorted(set(metadata) | {row["path"] for row in index["files"]})
    return [f"/{BUILDS}{build}/{rel}" for rel in rel_paths]


def fetch_hosting_release_files(site_id, service_account, *, token_minter=None, api_get=None):
    """Fetch active file hashes for the latest two finalized Firebase Hosting versions (zero egress)."""
    from rollback_readiness import FIREBASE_HOSTING_API, google_api_get_json, mint_google_access_token

    minter = token_minter or mint_google_access_token
    getter = api_get or google_api_get_json
    access_token = minter(Path(service_account), scopes=FIREBASE_HOSTING_READONLY_SCOPE)

    releases_url = f"{FIREBASE_HOSTING_API}/sites/{site_id}/releases?pageSize=10"
    releases_doc = getter(releases_url, access_token)
    finalized_versions = []
    for release in releases_doc.get("releases") or []:
        version = release.get("version") or {}
        name = version.get("name")
        status = version.get("status")
        if isinstance(name, str) and name and status in ("FINALIZED", None):
            if name not in finalized_versions:
                finalized_versions.append(name)
        if len(finalized_versions) >= 2:
            break
    if not finalized_versions:
        raise ValueError(f"Firebase Hosting returned no finalized releases for site {site_id}")

    def list_files(version_name):
        files = {}
        page_token = None
        for _ in range(MAX_HOSTING_FILE_PAGES):
            query = {"pageSize": "1000"}
            if page_token:
                query["pageToken"] = page_token
            url = f"{FIREBASE_HOSTING_API}/{version_name}/files?{urlencode(query)}"
            doc = getter(url, access_token)
            for entry in doc.get("files") or []:
                path = entry.get("path")
                if isinstance(path, str):
                    files[path] = {
                        "hash": entry.get("hash"),
                        "status": entry.get("status"),
                    }
            page_token = doc.get("nextPageToken")
            if not page_token:
                break
        else:
            raise ValueError(f"Firebase Hosting file listing exceeded {MAX_HOSTING_FILE_PAGES} pages for {version_name}")
        return files

    current_version = finalized_versions[0]
    current_files = list_files(current_version)
    previous_version = finalized_versions[1] if len(finalized_versions) > 1 else None
    previous_files = list_files(previous_version) if previous_version else {}
    return current_version, current_files, previous_version, previous_files


def verify(site, fetch=read_http, *, state_file=None, firebase_site=None,
           service_account=None, hosting_files_fetcher=None):
    """Verify Firebase v2 builds after deploy.

    Always performs full HTTP readback for the active build and any newly deployed builds.
    Older retained builds are verified at zero Hosting egress via the Firebase Hosting API's
    version file hashes (falling back to full HTTP readback if a hash changed or the API is
    not configured).
    """
    confirm_preserved(site, fetch)
    raw_pointer = v2.bounded(site / v2.LATEST, v2.MAX_POINTER_BYTES)
    active = v2.validate_pointer(raw_pointer)["build"]
    builds = history(v2.bounded(site / HISTORY, v2.MAX_POINTER_BYTES))

    state = _load_state_file(state_file)
    http_required = {active}
    if state is not None:
        http_required |= (builds - state["previousBuilds"]) | (state["newBuilds"] & builds)

    older_candidates = sorted(builds - http_required)
    can_use_api = older_candidates and (
        hosting_files_fetcher is not None or (firebase_site and service_account)
    )
    if can_use_api:
        if hosting_files_fetcher is not None:
            current_version, current_files, _, previous_files = hosting_files_fetcher()
        else:
            current_version, current_files, _, previous_files = fetch_hosting_release_files(
                firebase_site, service_account,
            )
        for build in older_candidates:
            expected_paths = local_build_expected_paths(site, build)
            unchanged_from_previous = True
            for path in expected_paths:
                cur = current_files.get(path)
                if cur is None or cur.get("status") != "ACTIVE" or not cur.get("hash"):
                    raise ValueError(
                        f"Firebase Hosting release {current_version} is missing active file "
                        f"for retained build {build}: {path}"
                    )
                prev = previous_files.get(path)
                if prev is None or prev.get("status") != "ACTIVE" or prev.get("hash") != cur.get("hash"):
                    unchanged_from_previous = False
            if unchanged_from_previous:
                print(
                    f"Verified Firebase v2 retained build {build} via Hosting API "
                    f"({len(expected_paths)} files unchanged in {current_version})",
                    flush=True,
                )
            else:
                http_required.add(build)
    else:
        http_required |= set(older_candidates)

    for build in sorted(http_required):
        pointer, files = read_build(ORIGIN, build, fetch)
        if build == active and pointer != raw_pointer:
            raise ValueError("Firebase v2 active build differs from the verified capture")
        print(f"Verified Firebase v2 build {build}: {len(files)} files (HTTP readback)", flush=True)
    confirm_preserved(site, fetch)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("restore", "prepare", "sync-r2", "confirm-preserved", "verify", "confirm-primary"))
    parser.add_argument("--site-root", required=True, type=Path)
    parser.add_argument("--r2-inventory", type=Path)
    parser.add_argument("--primary-pointer", type=Path)
    parser.add_argument("--prefer-r2", action="store_true")
    parser.add_argument("--retention-days", type=int, default=DEFAULT_FIREBASE_RETENTION_DAYS)
    parser.add_argument("--state-file", type=Path)
    parser.add_argument("--firebase-site", default=os.environ.get("FIREBASE_HOSTING_SITE_ID"))
    parser.add_argument(
        "--service-account",
        type=Path,
        default=Path(os.environ["GOOGLE_APPLICATION_CREDENTIALS"])
        if os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
        else None,
    )
    args = parser.parse_args()
    if args.action == "prepare":
        if args.r2_inventory is None or args.primary_pointer is None:
            parser.error("prepare requires --r2-inventory and --primary-pointer")
        prepare(
            args.site_root,
            inventory_ids(args.r2_inventory),
            v2.bounded(args.primary_pointer, v2.MAX_POINTER_BYTES),
            retention_days=args.retention_days,
            state_file=args.state_file,
        )
    elif args.action == "sync-r2":
        if args.r2_inventory is None:
            parser.error("sync-r2 requires --r2-inventory")
        sync_r2(
            args.site_root,
            inventory_ids(args.r2_inventory),
            retention_days=args.retention_days,
            state_file=args.state_file,
        )
    elif args.action == "confirm-primary":
        confirm_primary_pointer(v2.bounded(args.site_root / v2.LATEST, v2.MAX_POINTER_BYTES))
    elif args.action == "restore":
        restore(args.site_root, prefer_r2=args.prefer_r2)
    elif args.action == "verify":
        verify(
            args.site_root,
            state_file=args.state_file,
            firebase_site=args.firebase_site,
            service_account=args.service_account,
        )
    else:
        confirm_preserved(args.site_root)


if __name__ == "__main__":
    main()
