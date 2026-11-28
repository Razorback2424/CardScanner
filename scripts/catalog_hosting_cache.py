#!/usr/bin/env python3
"""Reuse verified immutable catalog objects and verify Firebase catalog backups."""
import argparse
import gzip
import hashlib
from http.client import IncompleteRead
import json
from pathlib import Path
import secrets
import shutil
from ssl import SSLEOFError
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, build_opener

from market_price_feeds import (
    CATALOG_NAMESPACES,
    MAX_SCOPE_BYTES,
    NoRedirects,
    ORIGIN,
    R2_ORIGIN,
    SCOPE_FILE,
    packed,
    read_http,
    read_r2_scope,
)

NAMESPACES = {"pokemon": "v1", "magic": "magic/v1", "one-piece": "one-piece/v1", "yugioh": "yugioh/v1"}
APPROVED_ORIGINS = (ORIGIN, R2_ORIGIN)
ROOT = Path(__file__).resolve().parents[1]
PINS = ("PokemonCatalogProduction.xcconfig", "MagicCatalogProduction.xcconfig",
        "OnePieceCatalogProduction.xcconfig", "YuGiOhCatalogProduction.keys.json")
MAX_POINTER_BYTES = 65 * 1024 * 1024


def validate_origin(origin):
    if origin not in APPROVED_ORIGINS:
        raise ValueError(f"Unexpected catalog restore origin: {origin}")
    return origin


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def trust_stamp():
    pins = {}
    for file in PINS:
        try:
            pins[file] = digest(ROOT / "Config" / file)
        except FileNotFoundError:
            if file != "YuGiOhCatalogProduction.keys.json":
                raise
            # A Yu-Gi-Oh namespace is optional before approval. If present,
            # the restore still requires its public key file for verification.
            pins[file] = None
    return pins


def inventory(directory):
    if directory.is_symlink():
        raise ValueError(f"Unexpected link in restored catalog: {directory}")
    result = {}
    for entry in directory.rglob("*"):
        if entry.is_symlink():
            raise ValueError(f"Unexpected link in restored catalog: {entry}")
        if entry.is_file():
            result[entry.relative_to(directory).as_posix()] = digest(entry)
    return result


def get_pointer(namespace, tag, *, optional, origin=ORIGIN, fresh=False):
    origin = validate_origin(origin)
    headers = {"User-Agent": "ScanStashCatalogPublisher/1.0", "Accept-Encoding": "gzip",
               "Cache-Control": "no-cache"}
    if tag:
        headers["If-None-Match"] = tag
    suffix = f"?r2v={secrets.token_hex(8)}" if fresh else ""
    request = Request(f"{origin}/{namespace}/current.json{suffix}", headers=headers)
    try:
        with build_opener(NoRedirects()).open(request, timeout=45) as response:
            encoding = response.headers.get("Content-Encoding", "identity").strip().lower()
            if encoding == "gzip":
                with gzip.GzipFile(fileobj=response) as decoded:
                    data = decoded.read(MAX_POINTER_BYTES + 1)
            elif encoding == "identity":
                data = response.read(MAX_POINTER_BYTES + 1)
            else:
                raise ValueError(f"Unexpected pointer encoding for {namespace}: {encoding}")
            if response.status != 200 or not 0 < len(data) <= MAX_POINTER_BYTES:
                raise ValueError(f"Invalid production pointer size or response for {namespace}")
            return response.status, data, response.headers.get("ETag")
    except HTTPError as error:
        if error.code == 304 and tag:
            return 304, None, tag
        if error.code == 404 and optional:
            return 404, None, None
        raise


def pointer_reader(get, origin, *, fresh=False):
    if get is not get_pointer:
        return get
    return lambda namespace, tag, *, optional: get_pointer(
        namespace, tag, optional=optional, origin=origin, fresh=fresh)


def prepare(cache, site, work, get=get_pointer, *, reconcile_history=False, origin=ORIGIN):
    validate_origin(origin)
    reader = pointer_reader(get, origin, fresh=(origin == R2_ORIGIN))
    try:
        cached = json.loads((cache / "catalogs.json").read_bytes())
        known = cached["catalogs"]
        if not isinstance(known, dict):
            known = {}
        previous = known if cached["pins"] == trust_stamp() else {}
    except (OSError, ValueError, KeyError, TypeError):
        known = {}
        previous = {}
    work.mkdir(parents=True, exist_ok=True)
    state = {}
    for name, namespace in NAMESPACES.items():
        local = cache / "site" / namespace
        progress = work / f"{name}-cached-through"
        progress.unlink(missing_ok=True)
        entry = previous.get(name)
        try:
            if (not entry or type(entry["revision"]) is not int or not 1 <= entry["revision"] <= 100_000
                    or not isinstance(entry["files"], dict) or "current.json" not in entry["files"]
                    or inventory(local) != entry["files"]):
                entry = None
        except (OSError, ValueError, KeyError, TypeError):
            entry = None
        # Explicit recovery rechecks history even when the pointer is unchanged.
        # Keep the prior inventory for confirm() to prevent losing known objects.
        if reconcile_history:
            entry = None
        status, body, tag = reader(namespace, entry.get("etag") if entry else None,
                                   optional=name != "pokemon" and name not in known)
        pointer = work / f"{name}-current.json"
        if status == 404:
            pointer.unlink(missing_ok=True)
            continue
        if entry:
            shutil.copytree(local, site / namespace)
            progress.write_text(str(entry["revision"]) + "\n")
        if status == 304:
            shutil.copyfile(local / "current.json", pointer)
        else:
            pointer.write_bytes(body)
        recorded = previous.get(name)
        old_files = recorded.get("files") if isinstance(recorded, dict) else None
        old_releases = {path: sha for path, sha in old_files.items() if path.startswith("releases/")} \
            if isinstance(old_files, dict) else {}
        state[name] = {"etag": tag, "pointerSHA256": digest(pointer), "priorReleases": old_releases}
    (work / "pointers.json").write_bytes(packed(state))


def confirm(work, site, get=get_pointer, *, origin=ORIGIN):
    validate_origin(origin)
    reader = pointer_reader(get, origin, fresh=True)
    state = json.loads((work / "pointers.json").read_bytes())
    for name, namespace in NAMESPACES.items():
        entry = state.get(name)
        if entry:
            staged = inventory(site / namespace)
            if (staged.get("current.json") != entry["pointerSHA256"]
                    or any(staged.get(path) != sha for path, sha in entry["priorReleases"].items())):
                raise ValueError(f"Restoration lost or changed a verified {namespace} object")
        status, body, _ = reader(namespace, entry["etag"] if entry else None, optional=entry is None)
        if entry is None and status == 404:
            continue
        if entry and (status == 304 or (status == 200 and hashlib.sha256(body).hexdigest() == entry["pointerSHA256"])):
            continue
        raise ValueError(f"Production {namespace} changed during restoration")


def confirm_r2_scopes_match(site, fetch=read_http):
    """Confirm staged catalog scopes match R2's active scopes before Firebase backup."""
    nonce = secrets.token_hex(8)

    def fresh_fetch(url, maximum, *, absent_ok=False):
        separator = "&" if "?" in url else "?"
        return fetch(f"{url}{separator}r2v={nonce}", maximum, absent_ok=absent_ok)

    for game, (_, namespace) in CATALOG_NAMESPACES.items():
        path = Path(namespace) / SCOPE_FILE
        expected = (site / path).read_bytes()
        if read_r2_scope(game, namespace, fresh_fetch) != expected:
            raise ValueError(f"R2 {path.as_posix()} no longer matches the staged catalog backup")


def confirm_catalog_mirror_candidate(work, site, fetch=read_http, get=get_pointer):
    """Confirm the Firebase catalog snapshot before the separate R2 catalog sync."""
    nonce = secrets.token_hex(8)
    for _, namespace in CATALOG_NAMESPACES.values():
        path = f"{namespace}/{SCOPE_FILE}"
        if fetch(f"{ORIGIN}/{path}?r2v={nonce}", MAX_SCOPE_BYTES) != (site / path).read_bytes():
            raise ValueError(f"Firebase {path} no longer matches this verified catalog")
    # Reuse captured ETags so unchanged signed pointers stay cheap to confirm.
    confirm(work, site, get=get)


def fetch_firebase_with_headers(url, maximum):
    request = Request(url, headers={"User-Agent": "ScanStashCatalogPublisher/1.0",
                                    "Accept-Encoding": "gzip", "Cache-Control": "no-cache"})
    with build_opener(NoRedirects()).open(request, timeout=60) as response:
        encoding = response.headers.get("Content-Encoding", "identity").strip().lower()
        if encoding == "gzip":
            with gzip.GzipFile(fileobj=response) as decoded:
                data = decoded.read(maximum + 1)
        elif encoding == "identity":
            data = response.read(maximum + 1)
        else:
            raise ValueError(f"Unexpected response encoding: {encoding}")
        if response.status != 200 or not 0 < len(data) <= maximum:
            raise ValueError(f"Invalid readback size or HTTP status for {url}")
        return data, {k.lower(): v for k, v in response.headers.items()}


def verify_firebase_catalogs(site, *, namespace=None, revision=None, fetch=fetch_firebase_with_headers,
                             attempts=None, sleep=time.sleep):
    """Verify live Firebase catalog pointers, scopes, and an optional new revision."""
    site = Path(site)
    max_attempts = (4 if fetch is fetch_firebase_with_headers else 1) if attempts is None else attempts
    paths = []
    for ns in NAMESPACES.values():
        pointer = f"{ns}/current.json"
        if (site / pointer).is_file():
            paths.append((pointer, MAX_POINTER_BYTES, "no-cache"))
    for _, ns in CATALOG_NAMESPACES.values():
        scope = f"{ns}/{SCOPE_FILE}"
        if (site / scope).is_file():
            paths.append((scope, MAX_SCOPE_BYTES, "no-cache"))
    if namespace is not None:
        if namespace not in NAMESPACES.values():
            raise ValueError(f"Unknown catalog namespace: {namespace}")
        if revision is None or type(revision) is not int or revision < 1:
            raise ValueError("A positive revision is required with --namespace")
        release_dir = site / namespace / "releases" / str(revision)
        if not release_dir.is_dir():
            raise ValueError(f"Missing staged release directory: {release_dir}")
        for entry in sorted(release_dir.iterdir()):
            if entry.is_file() and not entry.name.startswith("."):
                rel = entry.relative_to(site).as_posix()
                paths.append((rel, MAX_POINTER_BYTES, "immutable"))
    for rel, limit, cache_kind in paths:
        expected = (site / rel).read_bytes()
        for attempt in range(max_attempts):
            nonce = secrets.token_hex(8)
            try:
                body, headers = fetch(f"{ORIGIN}/{rel}?fbv={nonce}", limit)
                if body != expected:
                    raise ValueError(f"Firebase backup bytes differ for {rel}")
                cache_control = headers.get("cache-control", "").lower()
                if cache_kind == "no-cache" and "no-cache" not in cache_control:
                    raise ValueError(f"Firebase backup lacks no-cache header for {rel}: {cache_control!r}")
                if cache_kind == "immutable" and (
                        "max-age=31536000" not in cache_control or "immutable" not in cache_control):
                    raise ValueError(f"Firebase backup lacks immutable cache header for {rel}: {cache_control!r}")
                break
            except (HTTPError, URLError, TimeoutError, ConnectionError, IncompleteRead, SSLEOFError, ValueError) as err:
                retryable = (not isinstance(err, HTTPError)
                             or err.code in (404, 429) or 500 <= err.code < 600)
                if not retryable or attempt + 1 >= max_attempts:
                    raise
                print(f"Retrying Firebase backup verification ({attempt + 1}/{max_attempts - 1}): {rel}",
                      file=sys.stderr, flush=True)
                sleep(2 ** attempt)
        print(f"Verified Firebase backup {ORIGIN}/{rel}", flush=True)


def seal(cache, site, work):
    pointers = json.loads((work / "pointers.json").read_bytes())
    catalogs = {}
    for name, pointer in pointers.items():
        namespace = NAMESPACES[name]
        source = site / namespace
        revision = int((work / f"{name}-verified-through").read_text())
        objects = inventory(source)
        if objects.get("current.json") != pointer["pointerSHA256"]:
            raise ValueError(f"The restored pointer changed for {namespace}")
        catalogs[name] = {"etag": pointer["etag"], "revision": revision, "files": objects}
    raw = packed({"pins": trust_stamp(), "catalogs": catalogs})
    old = cache / "catalogs.json"
    try:
        if old.read_bytes() == raw and all(inventory(cache / "site" / NAMESPACES[name]) == entry["files"]
                                          for name, entry in catalogs.items()):
            return ""
    except (OSError, ValueError):
        pass
    for name in NAMESPACES:
        target = cache / "site" / NAMESPACES[name]
        if target.is_dir():
            shutil.rmtree(target)
        if name in catalogs:
            shutil.copytree(site / NAMESPACES[name], target)
    cache.mkdir(parents=True, exist_ok=True)
    old.write_bytes(raw)
    return hashlib.sha256(packed({name: entry["etag"] for name, entry in catalogs.items()})).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "confirm", "confirm-r2-scopes",
                                            "verify-firebase-catalogs", "seal"))
    parser.add_argument("--cache", type=Path)
    parser.add_argument("--site", type=Path, required=True)
    parser.add_argument("--work", type=Path)
    parser.add_argument("--origin", default=ORIGIN, choices=APPROVED_ORIGINS)
    parser.add_argument("--namespace", choices=tuple(NAMESPACES.values()))
    parser.add_argument("--revision", type=int)
    parser.add_argument("--reconcile-history", action="store_true",
                        help="Restore all revisions after historical origin recovery")
    args = parser.parse_args()
    if args.command == "prepare":
        if args.cache is None or args.work is None:
            parser.error("prepare requires --cache and --work")
        prepare(args.cache, args.site, args.work, reconcile_history=args.reconcile_history, origin=args.origin)
    elif args.command == "confirm":
        if args.work is None:
            parser.error("confirm requires --work")
        confirm(args.work, args.site, origin=args.origin)
    elif args.command == "confirm-r2-scopes":
        confirm_r2_scopes_match(args.site)
    elif args.command == "verify-firebase-catalogs":
        verify_firebase_catalogs(args.site, namespace=args.namespace, revision=args.revision)
    else:
        if args.cache is None or args.work is None:
            parser.error("seal requires --cache and --work")
        print(seal(args.cache, args.site, args.work))


if __name__ == "__main__":
    main()
