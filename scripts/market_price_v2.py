"""Stage immutable price builds from a complete, validated v1 capture.

R2 staging only until the app and Firebase rollback path support v2.
No provider calls, price transformations, or deletions.
"""
import json
from pathlib import Path
import re

from market_price_feeds import (
    CATALOG_NAMESPACES, FEED_PATH, MAX_FILE_BYTES, MAX_SCOPE_BYTES,
    MAX_SITE_BYTES, NAMESPACE, SCOPE_FILE, digest, instant, packed,
    read_site, validate_catalog_scope,
)

V2 = "market-prices/v2"
LATEST = f"{V2}/latest.json"
MAX_POINTER_BYTES = 1024 * 1024
SCOPES = {f"scopes/{game}.json": namespace
          for game, (_, namespace) in CATALOG_NAMESPACES.items()}


def bounded(path, limit):
    if path.is_symlink():
        raise ValueError(f"Unexpected link: {path}")
    with path.open("rb") as stream:
        data = stream.read(limit + 1)
    if not 0 < len(data) <= limit:
        raise ValueError(f"Invalid price file size: {path}")
    return data


def entry(path, raw):
    return {"path": path, "sha256": digest(raw), "byteCount": len(raw)}


def validate_pointer(raw):
    if len(raw) > MAX_POINTER_BYTES:
        raise ValueError("Oversize v2 price pointer")
    pointer = json.loads(raw)
    if (not isinstance(pointer, dict) or set(pointer) != {"schemaVersion", "sourceBuild", "build", "files"}
            or pointer["schemaVersion"] != 2):
        raise ValueError("Invalid v2 price pointer")
    instant(pointer["sourceBuild"])
    rows = pointer["files"]
    if not isinstance(rows, list) or not 5 <= len(rows) <= 1804:
        raise ValueError("Invalid v2 price manifest")
    seen = set()
    total = 0
    for row in rows:
        path, size = row["path"], row["byteCount"]
        if (path in seen or not (path in {"index.json", "last-updated.txt"}
                or path in SCOPES or FEED_PATH.fullmatch(path))):
            raise ValueError("Unsafe or duplicate v2 price path")
        limit = MAX_SCOPE_BYTES if path in SCOPES else MAX_POINTER_BYTES if path == "index.json" else MAX_FILE_BYTES
        if (type(size) is not int or not 0 < size <= limit
                or not re.fullmatch(r"[0-9a-f]{64}", row["sha256"])):
            raise ValueError("Invalid v2 price file metadata")
        seen.add(path)
        total += size
    if not ({"index.json", "last-updated.txt"} | set(SCOPES)) <= seen:
        raise ValueError("Incomplete v2 price manifest")
    if total > MAX_SITE_BYTES + MAX_POINTER_BYTES + len(SCOPES) * MAX_SCOPE_BYTES:
        raise ValueError("Oversize v2 price manifest")
    if [row["path"] for row in rows] != sorted(seen):
        raise ValueError("Noncanonical v2 price manifest order")
    core = {key: value for key, value in pointer.items() if key != "build"}
    if pointer["build"] != digest(packed(core)):
        raise ValueError("Invalid v2 price build identity")
    return pointer


def stage(site):
    """Return the staged pointer; keep v1 and its capture receipts byte-identical."""
    from catalog_parity import MIRROR_CATEGORIES, mirror_priced_products

    site = Path(site)
    legacy = site / NAMESPACE
    target = site / V2
    if target.exists():
        raise ValueError("Stage v2 into a fresh verified artifact")
    index_raw = bounded(legacy / "index.json", MAX_POINTER_BYTES)
    files = read_site(index_raw, lambda path, size: bounded(legacy / path, size))
    files["index.json"] = index_raw
    # Bind the catalog scopes to this price build as well. The legacy scope
    # paths remain untouched for old clients and catalog publishing.
    scopes = {}
    for path, namespace in SCOPES.items():
        raw = bounded(site / namespace / SCOPE_FILE, MAX_SCOPE_BYTES)
        game = path.removeprefix("scopes/").removesuffix(".json")
        scopes[game] = validate_catalog_scope(raw, game)
        category = CATALOG_NAMESPACES[game][0]
        actual_groups = {int(name.split("/")[2]) for name in files
                         if name.startswith(f"tcgplayer/{category}/")}
        if actual_groups != set(scopes[game]):
            raise ValueError(f"v2 price groups do not match authorized catalog scope: {game}")
        files[path] = raw
    core = {"schemaVersion": 2, "sourceBuild": json.loads(index_raw)["sourceBuild"],
            "files": [entry(path, raw) for path, raw in sorted(files.items())]}
    pointer = {**core, "build": digest(packed(core))}
    raw_pointer = packed(pointer)
    validate_pointer(raw_pointer)
    build = target / "builds" / pointer["build"]
    for path, raw in files.items():
        destination = build / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(raw)
    # PR 65's priced-product coverage gate: compare both representations of
    # the *same* captured build, not two different days of provider prices.
    for game, category in MIRROR_CATEGORIES.items():
        # A verified catalog may explicitly withdraw its last eligible lane.
        # The group-set check above proves there are no stray feed files.
        if game in scopes and not scopes[game]:
            print(f"v2 parity {game}: 0 priced product/finish lanes (authorized empty scope)", flush=True)
            continue
        before = mirror_priced_products(legacy, category)
        after = mirror_priced_products(build, category)
        if before != after:
            raise ValueError(f"v2 priced-product coverage changed: {game}")
        print(f"v2 parity {game}: {len(before)} priced product/finish lanes", flush=True)
    (target / "latest.json").write_bytes(raw_pointer)
    return pointer


def check_plan(objects):
    """Refuse a pointer without its complete, exact staged build."""
    v2 = {item["key"]: item for item in objects if item["key"].startswith(V2 + "/")}
    if not v2:
        return
    if LATEST not in v2:
        raise ValueError("Missing v2 price pointer")
    pointer = validate_pointer(bounded(v2[LATEST]["path"], MAX_POINTER_BYTES))
    prefix = f"{V2}/builds/{pointer['build']}/"
    expected = {prefix + row["path"]: row for row in pointer["files"]}
    if set(v2) != set(expected) | {LATEST}:
        raise ValueError("Incomplete or unexpected staged v2 price files")
    for key, row in expected.items():
        item = v2[key]
        if item["sha256"] != row["sha256"] or item["size"] != row["byteCount"]:
            raise ValueError(f"Staged v2 price hash/size mismatch: {key}")
