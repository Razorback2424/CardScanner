#!/usr/bin/env python3
"""Prepare scoped daily price feeds, or preserve them during a catalog deploy.

This is a static snapshot publisher, not a query API. Only reviewed product IDs
and lanes from the app's bundled catalogs are exported. Captured bytes are reused
for an unchanged upstream build; a failed/mixed capture never replaces the site.
"""
from __future__ import annotations

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import time
from urllib.error import HTTPError
from urllib.request import HTTPRedirectHandler, Request, build_opener

NAMESPACE = "market-prices/v1"
MAX_FILE_BYTES = 8 * 1024 * 1024
MAX_SITE_BYTES = 128 * 1024 * 1024
ORIGIN = "https://scanstash-catalog-prod.web.app"
FEED_PATH = re.compile(r"tcgplayer/(2|3|68|71)/[1-9][0-9]*/(products|prices)\Z")


def packed(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n").encode()


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def instant(value):
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("A timezone is required")
    return parsed


def stamp():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def read_http(url, maximum=MAX_FILE_BYTES, absent_ok=False):
    request = Request(url, headers={"User-Agent": "ScanStashPricePublisher/1.0", "Accept": "application/json,text/plain"})
    try:
        with build_opener(NoRedirects()).open(request, timeout=45) as response:
            raw = response.read(maximum + 1)
    except HTTPError as error:
        if absent_ok and error.code == 404:
            return None
        raise
    if len(raw) > maximum:
        raise ValueError("Response exceeds the byte limit")
    return raw


def scope_from_repo(repo):
    """Price lookup scope cannot add physical identity or collection authority."""
    scope = {}

    def add(category, group, product, lane):
        if type(group) is not int or group < 1 or type(product) is not int or product < 1 or not lane:
            raise ValueError("Invalid reviewed market mapping")
        scope.setdefault((category, group), {}).setdefault(product, set()).add(lane)

    mapping = (repo / "TradingCardScanner/Services/PokemonTCGCSVMapping.swift").read_text()
    for group, product in re.findall(r"Entry\(cardID: [^\n]+?groupID: (\d+), productID: (\d+),", mapping):
        add(3, int(group), int(product), "Holofoil")
    lorcana = json.loads((repo / "TradingCardScanner/LorcanaCatalogSeed/market.json").read_bytes())
    for printing in lorcana["physicalPrintings"]:
        if printing["status"] != "verified":
            continue
        for market in printing.get("marketMappings") or []:
            add(71, market["groupID"], market["productID"], market["providerVariantID"])
    envelope = json.loads((repo / "TradingCardScanner/OnePieceOwnerCatalog/one-piece-owner-catalog.json").read_bytes())
    encoded = envelope["payload"]
    one_piece = json.loads(base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)))
    for printing in one_piece["registry"]["printings"]:
        if printing["status"] != "verified":
            continue
        for market in printing.get("marketMappings") or []:
            if market["status"] == "exact" and market["provider"] == "tcgplayer" and market["market"] == "us" and market["currency"] == "USD":
                add(68, int(market["qualifiers"]["groupID"]), int(market["productID"]), market["providerVariantID"])
    yugioh = json.loads((repo / "TradingCardScanner/YuGiOhCatalogSeed/catalog.json").read_bytes())
    lanes = {"yugioh1stEdition": "1st Edition", "yugiohUnlimited": "Unlimited", "yugiohLimited": "Limited"}
    for printing in yugioh["printings"]:
        for edition in printing["e"]:
            add(2, printing["g"], printing["p"], lanes[edition])
    if {category for category, _ in scope} != {2, 3, 68, 71} or len(scope) > 900:
        raise ValueError("Unexpected catalog pricing scope")
    return scope


def validate_response(raw, category, group, resource):
    doc = json.loads(raw)
    if doc.get("success") is not True or doc.get("errors") != [] or not isinstance(doc.get("results"), list):
        raise ValueError("Failed or malformed provider response")
    rows = doc["results"]
    if "totalItems" in doc and (type(doc["totalItems"]) is not int or doc["totalItems"] != len(rows)):
        raise ValueError("Incomplete provider response")
    if any(key in doc for key in ("next", "nextPage", "hasMore", "continuationToken")):
        raise ValueError("Unexpected pagination")
    seen = set()
    for row in rows:
        product = row.get("productId")
        if type(product) is not int or product < 1:
            raise ValueError("Invalid product ID")
        key = product if resource == "products" else (product, row.get("subTypeName"))
        if key in seen:
            raise ValueError("Duplicate provider product or price lane")
        seen.add(key)
        if resource == "products":
            if (type(row.get("categoryId")) is not int or type(row.get("groupId")) is not int
                    or row["categoryId"] != category or row["groupId"] != group
                    or not isinstance(row.get("name"), str) or not row["name"]
                    or not isinstance(row.get("extendedData"), list)):
                raise ValueError("Foreign or incomplete product")
            if any(not isinstance(field, dict) or not isinstance(field.get("name"), str)
                   or (field["name"] == "Number" and not isinstance(field.get("value"), str)) for field in row["extendedData"]):
                raise ValueError("Malformed product fields")
        else:
            value = row.get("marketPrice")
            if not isinstance(row.get("subTypeName"), str) or (value is not None and (type(value) not in (int, float) or not math.isfinite(value) or value < 0)):
                raise ValueError("Invalid market price")
    return rows


def prepare(scope, cache, site, fetch=read_http, now=stamp, pause=time.sleep, yugioh_source=None):
    # Only the marker is checked on every run. Group bodies are retained once
    # per daily build; repeated prepares reuse their original capture receipts.
    pause(0.1)
    marker = fetch("https://tcgcsv.com/last-updated.txt", 1024).decode().strip()
    if len(marker) > 100 or instant(marker) > instant(now()):
        raise ValueError("Invalid upstream daily build")
    if yugioh_source is not None:
        # The existing daily YGO builder already fetched these exact unfiltered
        # source files. Both surrounding markers must bind them to this build.
        for name in ("source-build-start.txt", "source-build-end.txt"):
            if (yugioh_source / name).read_text().strip() != marker:
                raise ValueError("Retained YGO source is not bound to this daily build")
    root = cache / digest(marker.encode())
    root.mkdir(parents=True, exist_ok=True)
    receipts_path = root / "captures.json"
    receipts = json.loads(receipts_path.read_bytes()) if receipts_path.exists() else {}
    output = {"last-updated.txt": (marker + "\n").encode()}
    missing = []
    for completed, ((category, group), products) in enumerate(sorted(scope.items()), 1):
        for resource in ("products", "prices"):
            path = f"tcgplayer/{category}/{group}/{resource}"
            raw_path = root / f"{category}-{group}-{resource}.json"
            receipt = receipts.get(path)
            if receipt:
                raw = raw_path.read_bytes()
                if digest(raw) != receipt["sha256"]:
                    raise ValueError("Retained source bytes changed")
            else:
                retained = yugioh_source / "tcgcsv" / f"{group}-{resource}.json" if category == 2 and yugioh_source is not None else None
                if retained is not None:
                    raw = retained.read_bytes()
                    captured_at = datetime.fromtimestamp(retained.stat().st_mtime, timezone.utc).replace(microsecond=0).isoformat()
                else:
                    pause(0.1)
                    raw = fetch("https://tcgcsv.com/" + path)
                    captured_at = now()
                validate_response(raw, category, group, resource)
                receipt = {"sha256": digest(raw), "capturedAt": captured_at}
                raw_path.write_bytes(raw)
                receipts[path] = receipt
                temporary = receipts_path.with_suffix(".tmp")
                temporary.write_bytes(packed(receipts))
                temporary.replace(receipts_path)
            if not 0 <= (instant(now()) - instant(receipt["capturedAt"])).total_seconds() < 86400:
                raise ValueError("A stale capture cannot be published as current")
            rows = validate_response(raw, category, group, resource)
            selected = []
            for row in rows:
                product = row["productId"]
                if product not in products:
                    continue
                if resource == "products":
                    selected.append({key: row[key] for key in ("productId", "categoryId", "groupId", "name")} | {
                        "extendedData": [field for field in row["extendedData"] if field["name"] == "Number"]})
                elif row["subTypeName"] in products[product]:
                    selected.append({"productId": product, "subTypeName": row["subTypeName"], "marketPrice": row.get("marketPrice")})
            if resource == "products":
                missing.extend([category, group, product] for product in sorted(set(products) - {row["productId"] for row in selected}))
            doc = {"success": True, "errors": [], "totalItems": len(selected), "results": selected,
                   "sourceBuild": marker, "sourceFetchedAt": receipt["capturedAt"]}
            output[path] = packed(doc)
        if completed % 25 == 0 or completed == len(scope):
            print(f"Prepared {completed}/{len(scope)} scoped groups; not published", flush=True)
    pause(0.1)
    if fetch("https://tcgcsv.com/last-updated.txt", 1024).decode().strip() != marker:
        raise ValueError("Upstream changed during capture; publication refused")
    index = {"schemaVersion": 1, "sourceBuild": marker, "files": [
        {"path": path, "sha256": digest(raw), "byteCount": len(raw)} for path, raw in sorted(output.items())]}
    # Validate the complete candidate before writing any hosting artifact.
    validate_site(index, output)
    namespace = site / NAMESPACE
    if namespace.exists() and any(namespace.iterdir()):
        raise ValueError("Prepare into an empty price namespace")
    for path, raw in output.items():
        destination = namespace / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(raw)
    (namespace / "index.json").write_bytes(packed(index))
    return {"sourceBuild": marker, "groups": len(scope), "products": sum(len(value) for value in scope.values()),
            "missingProducts": missing, "files": len(output), "bytes": sum(map(len, output.values())),
            "indexSHA256": digest(packed(index))}


def validate_site(index, files):
    if index.get("schemaVersion") != 1 or not isinstance(index.get("files"), list) or not 1 <= len(index["files"]) <= 1801:
        raise ValueError("Invalid price feed index")
    instant(index["sourceBuild"])
    paths = set()
    total = 0
    for entry in index["files"]:
        path = entry["path"]
        if path in paths or not (path == "last-updated.txt" or FEED_PATH.fullmatch(path)):
            raise ValueError("Unsafe or duplicate price feed path")
        paths.add(path)
        size = entry["byteCount"]
        if type(size) is not int or not 0 < size <= MAX_FILE_BYTES:
            raise ValueError("Invalid price feed size")
        total += size
        raw = files[path]
        if len(raw) != size or digest(raw) != entry["sha256"]:
            raise ValueError("Price feed hash/size mismatch")
        if path != "last-updated.txt":
            doc = json.loads(raw)
            category, group, resource = path.split("/")[1:]
            validate_response(raw, int(category), int(group), resource)
            captured = instant(doc["sourceFetchedAt"])
            if doc["sourceBuild"] != index["sourceBuild"] or instant(index["sourceBuild"]) > captured:
                raise ValueError("Mixed price build or invalid receipt")
    if total > MAX_SITE_BYTES or "last-updated.txt" not in paths or files["last-updated.txt"].decode().strip() != index["sourceBuild"]:
        raise ValueError("Invalid price site size/build marker")
    for path in paths - {"last-updated.txt"}:
        peer = path.rsplit("/", 1)[0] + ("/prices" if path.endswith("/products") else "/products")
        if peer not in paths:
            raise ValueError("Incomplete product/price pair")


def restore(site, origin=ORIGIN, fetch=read_http):
    if origin != ORIGIN:
        raise ValueError("Unexpected production origin")
    namespace = site / NAMESPACE
    local = namespace / "index.json"
    raw = local.read_bytes() if local.exists() else fetch(origin + "/" + NAMESPACE + "/index.json", 1024 * 1024, absent_ok=True)
    if raw is None:
        return False
    index = json.loads(raw)
    # Preflight paths and declared budgets before network/file reads.
    entries = index.get("files")
    if not isinstance(entries, list) or len(entries) > 1801:
        raise ValueError("Invalid price feed index")
    files = {}
    total = 0
    for entry in entries:
        path, size = entry["path"], entry["byteCount"]
        if not (path == "last-updated.txt" or FEED_PATH.fullmatch(path)) or type(size) is not int or not 0 < size <= MAX_FILE_BYTES:
            raise ValueError("Unsafe price feed path/size")
        total += size
        if total > MAX_SITE_BYTES or path in files:
            raise ValueError("Oversize or duplicate price feed index")
        files[path] = (namespace / path).read_bytes() if local.exists() else fetch(origin + "/" + NAMESPACE + "/" + path, size)
    validate_site(index, files)
    for path, body in files.items():
        destination = namespace / path
        if destination.exists() and destination.read_bytes() != body:
            raise ValueError("Conflicting prepared price feed")
    for path, body in files.items():
        destination = namespace / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(body)
    local.write_bytes(raw)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build = commands.add_parser("prepare")
    build.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    build.add_argument("--cache-dir", type=Path, required=True)
    build.add_argument("--site-root", type=Path, required=True)
    build.add_argument("--report", type=Path, required=True)
    build.add_argument("--yugioh-source", type=Path, help="Reuse the same job's build-bound YGO source without another upstream download")
    preserve = commands.add_parser("restore")
    preserve.add_argument("--site-root", type=Path, required=True)
    preserve.add_argument("--origin", default=ORIGIN)
    args = parser.parse_args()
    if args.command == "prepare":
        result = prepare(scope_from_repo(args.repo), args.cache_dir, args.site_root, yugioh_source=args.yugioh_source)
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_bytes(packed(result))
        print(json.dumps({key: value for key, value in result.items() if key != "missingProducts"}, sort_keys=True))
    else:
        print("Price namespace preserved" if restore(args.site_root, args.origin) else "No price namespace is published")


if __name__ == "__main__":
    main()
