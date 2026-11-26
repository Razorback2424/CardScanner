#!/usr/bin/env python3
"""Reuse verified immutable Firebase catalog objects during price publication."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import shutil
from urllib.error import HTTPError
from urllib.request import Request, build_opener

from market_price_feeds import NoRedirects, ORIGIN, packed

NAMESPACES = {"pokemon": "v1", "magic": "magic/v1", "one-piece": "one-piece/v1", "yugioh": "yugioh/v1"}
ROOT = Path(__file__).resolve().parents[1]
PINS = ("PokemonCatalogProduction.xcconfig", "MagicCatalogProduction.xcconfig",
        "OnePieceCatalogProduction.xcconfig", "YuGiOhCatalogProduction.keys.json")
MAX_POINTER_BYTES = 65 * 1024 * 1024


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


def get_pointer(namespace, tag, *, optional):
    headers = {"User-Agent": "ScanStashCatalogPublisher/1.0", "Accept-Encoding": "gzip"}
    if tag:
        headers["If-None-Match"] = tag
    request = Request(f"{ORIGIN}/{namespace}/current.json", headers=headers)
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


def prepare(cache, site, work, get=get_pointer):
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
        status, body, tag = get(namespace, entry.get("etag") if entry else None,
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


def confirm(work, site, get=get_pointer):
    state = json.loads((work / "pointers.json").read_bytes())
    for name, namespace in NAMESPACES.items():
        entry = state.get(name)
        if entry:
            staged = inventory(site / namespace)
            if (staged.get("current.json") != entry["pointerSHA256"]
                    or any(staged.get(path) != sha for path, sha in entry["priorReleases"].items())):
                raise ValueError(f"Restoration lost or changed a verified {namespace} object")
        status, body, _ = get(namespace, entry["etag"] if entry else None, optional=entry is None)
        if entry is None and status == 404:
            continue
        if entry and (status == 304 or (status == 200 and hashlib.sha256(body).hexdigest() == entry["pointerSHA256"])):
            continue
        raise ValueError(f"Production {namespace} changed during restoration")


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
    parser.add_argument("command", choices=("prepare", "confirm", "seal"))
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--site", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "prepare":
        prepare(args.cache, args.site, args.work)
    elif args.command == "confirm":
        confirm(args.work, args.site)
    else:
        print(seal(args.cache, args.site, args.work))


if __name__ == "__main__":
    main()
