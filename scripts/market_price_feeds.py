#!/usr/bin/env python3
"""Prepare scoped daily price feeds, or preserve them during a catalog deploy.

This is a static snapshot publisher, not a query API. Only reviewed product IDs
and lanes from the app's bundled catalogs are exported. Recent captures are
reused for an unchanged upstream build; a failed/mixed capture never replaces the site.
"""
from __future__ import annotations

import argparse
import base64
from datetime import datetime, timezone
import gzip
import hashlib
from http.client import IncompleteRead
import json
import math
from pathlib import Path
import re
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, Request, build_opener

NAMESPACE = "market-prices/v1"
MAX_FILE_BYTES = 8 * 1024 * 1024
MAX_SITE_BYTES = 128 * 1024 * 1024
# Leave two scheduled six-hour opportunities before clients reject a capture.
# Renewing a receipt always requires an actual upstream product/price fetch.
CAPTURE_REUSE_SECONDS = 12 * 60 * 60
MAX_PUBLISH_AGE_SECONDS = 18 * 60 * 60
ORIGIN = "https://scanstash-catalog-prod.web.app"
R2_ORIGIN = "https://catalog-staging.scan-stash.com"
FEED_PATH = re.compile(r"tcgplayer/(2|3|68|71)/[1-9][0-9]*/(products|prices)\Z")
CATALOG_NAMESPACES = {"one-piece": (68, "one-piece/v1"), "yugioh": (2, "yugioh/v1")}
SCOPE_FILE = "market-price-scope.json"
MAX_SCOPE_BYTES = 4 * 1024 * 1024
YUGIOH_LANES = {"yugioh1stEdition": "1st Edition", "yugiohUnlimited": "Unlimited", "yugiohLimited": "Limited"}


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
    request = Request(url, headers={"User-Agent": "ScanStashPricePublisher/1.0",
                                    "Accept": "application/json,text/plain", "Accept-Encoding": "gzip"})
    for attempt in range(3):
        try:
            with build_opener(NoRedirects()).open(request, timeout=45) as response:
                encoding = response.headers.get("Content-Encoding", "identity").strip().lower()
                if encoding == "gzip":
                    with gzip.GzipFile(fileobj=response) as decoded:
                        raw = decoded.read(maximum + 1)
                elif encoding == "identity":
                    raw = response.read(maximum + 1)
                else:
                    raise ValueError(f"Unsupported feed content encoding: {encoding}")
            if len(raw) > maximum:
                raise ValueError("Response exceeds the byte limit")
            return raw
        except HTTPError as error:
            if absent_ok and error.code == 404:
                return None
            if error.code not in (429, 500, 502, 503, 504) or attempt == 2:
                raise
        except (URLError, TimeoutError, ConnectionError, IncompleteRead):
            if attempt == 2:
                raise
        print(f"Retrying price feed read ({attempt + 1}/2): {url}", file=sys.stderr, flush=True)
        time.sleep(2 ** attempt)


def envelope_payload(envelope):
    encoded = envelope["payload"]
    return json.loads(base64.b64decode(encoded + "=" * (-len(encoded) % 4), altchars=b"-_", validate=True))


def one_piece_rows(release):
    for printing in release["registry"]["printings"]:
        if printing["status"] != "verified" or printing["language"] != "en":
            continue
        for market in printing.get("marketMappings") or []:
            if (market["status"] == "exact" and market["provider"] == "tcgplayer"
                    and market["market"] == "us" and market["currency"] == "USD"
                    and market["condition"] == "aggregate"):
                yield int(market["qualifiers"]["groupID"]), int(market["productID"]), market["providerVariantID"]


def yugioh_rows(catalog):
    for printing in catalog["printings"] + catalog.get("referencePrintings", []):
        if "p" in printing:
            for edition in printing["e"]:
                yield printing.get("pg", printing["g"]), printing["p"], YUGIOH_LANES[edition]


def catalog_scope(repo, site, game):
    """Project an already verified staged catalog, or its bundled baseline."""
    _, namespace = CATALOG_NAMESPACES[game]
    pointer = site / namespace / "current.json"
    if pointer.is_file():
        pointer_bytes = pointer.read_bytes()
        envelope = json.loads(pointer_bytes)
        manifest = envelope_payload(envelope)
        revision = manifest["revision"]
        if type(revision) is not int or revision < 1:
            raise ValueError("Invalid price scope catalog revision")
    else:
        pointer_bytes, revision = None, None
    if game == "one-piece":
        catalog_bytes = pointer_bytes if pointer_bytes is not None else (
            repo / "TradingCardScanner/OnePieceCatalogSeed/one-piece-catalog-release.json").read_bytes()
        catalog = manifest if pointer_bytes is not None else envelope_payload(json.loads(catalog_bytes))
        if catalog["catalogKind"] != "one-piece":
            raise ValueError("Invalid One Piece scope catalog")
        rows = one_piece_rows(catalog)
    else:
        if pointer_bytes is not None:
            if manifest["status"] != "approved":
                raise ValueError("Yu-Gi-Oh price scope requires an approved release")
            catalog_bytes = base64.b64decode(envelope["catalog"], validate=True)
            if digest(catalog_bytes) != manifest["sha256"]:
                raise ValueError("Yu-Gi-Oh price scope catalog digest mismatch")
        else:
            catalog_bytes = (repo / "TradingCardScanner/YuGiOhCatalogSeed/catalog.json").read_bytes()
        rows = yugioh_rows(json.loads(catalog_bytes))
    groups = {}
    for group, product, lane in rows:
        groups.setdefault(group, {}).setdefault(product, set()).add(lane)
    document = {"schemaVersion": 1, "game": game, "revision": revision, "catalogSHA256": digest(catalog_bytes),
                "pointerSHA256": digest(pointer_bytes) if pointer_bytes is not None else None,
                "groups": [[group, [[product, sorted(lanes)] for product, lanes in sorted(products.items())]]
                           for group, products in sorted(groups.items())]}
    return packed(document)


def validate_catalog_scope(raw, game):
    if len(raw) > MAX_SCOPE_BYTES:
        raise ValueError("Market price scope exceeds its byte limit")
    document = json.loads(raw)
    if document["schemaVersion"] != 1 or document["game"] != game:
        raise ValueError("Unsupported market price scope")
    revision, pointer_hash = document["revision"], document["pointerSHA256"]
    if revision is not None and (type(revision) is not int or revision < 1):
        raise ValueError("Invalid price scope catalog revision")
    if (revision is None) != (pointer_hash is None):
        raise ValueError("Incomplete price scope catalog pointer")
    for value in (document["catalogSHA256"], pointer_hash):
        if value is not None and not re.fullmatch(r"[0-9a-f]{64}", value):
            raise ValueError("Invalid market price scope digest")
    if document["catalogSHA256"] is None:
        raise ValueError("Missing market price scope catalog digest")
    allowed = {"Normal", "Foil"} if game == "one-piece" else set(YUGIOH_LANES.values())
    scope = {}
    for group, products in document["groups"]:
        if type(group) is not int or group < 1 or group in scope or not products:
            raise ValueError("Invalid market price scope group")
        scope[group] = {}
        for product, lanes in products:
            if (type(product) is not int or product < 1 or product in scope[group]
                    or not isinstance(lanes, list) or not lanes or len(set(lanes)) != len(lanes)
                    or not set(lanes) <= allowed):
                raise ValueError("Invalid market price scope product or lane")
            scope[group][product] = set(lanes)
    if len(scope) > 900 or (not scope and revision is None):
        raise ValueError("Invalid market price scope group count")
    return scope


def scope_from_repo(repo, one_piece_envelope=None, *, scopes=None):
    """Price lookup scope cannot add physical identity or collection authority."""
    scope = {}

    def add(category, group, product, lane):
        if type(group) is not int or group < 1 or type(product) is not int or product < 1 or not lane:
            raise ValueError("Invalid reviewed market mapping")
        scope.setdefault((category, group), {}).setdefault(product, set()).add(lane)

    mapping = (repo / "TradingCardScanner/Services/PokemonTCGCSVMapping.swift").read_text()
    for group, product in re.findall(r"Entry\(cardID: [^\n]+?groupID: (\d+), productID: (\d+),", mapping):
        add(3, int(group), int(product), "Holofoil")
    battle_decks = json.loads((repo / "publisher/pokemon-battle-deck-finishes.json").read_bytes())
    if battle_decks["schemaVersion"] != 1:
        raise ValueError("Unsupported Pokémon Battle Deck finish catalog")
    for printing in battle_decks["entries"]:
        if (printing["groupID"], printing["printing"]) not in {(1840, "Reverse Holofoil"), (24461, "Holofoil")}:
            raise ValueError("Invalid Pokémon Battle Deck market lane")
        add(3, printing["groupID"], printing["productID"], printing["printing"])
    deck_normals = json.loads((repo / "publisher/pokemon-deck-exclusive-normals.json").read_bytes())
    if deck_normals["schemaVersion"] != 1:
        raise ValueError("Unsupported Pokémon Deck Exclusives catalog")
    for printing in deck_normals["entries"]:
        if ((printing["groupID"], printing["printing"]) != (1840, "Normal")
                or printing["productID"] in scope.get((3, 1840), {})):
            raise ValueError("Invalid Pokémon Deck Exclusives market lane")
        add(3, 1840, printing["productID"], "Normal")
    m26 = json.loads((repo / "publisher/pokemon-mcdonalds-2026.json").read_bytes())
    cards = m26["cards"]
    if (m26["schemaVersion"] != 1 or m26["groupID"] != 24938 or m26["setCode"] != "M26"
            or len(cards) != 15 or {card["number"] for card in cards} != {f"{n:03d}/015" for n in range(1, 16)}
            or len({card["productID"] for card in cards}) != len(cards)):
        raise ValueError("Invalid Pokémon M26 catalog")
    for card in cards:
        if card["printing"] not in {"Normal", "Holofoil"}:
            raise ValueError("Invalid Pokémon M26 market lane")
        add(3, m26["groupID"], card["productID"], card["printing"])
    delta_reign = json.loads((repo / "publisher/pokemon-delta-reign-printings.json").read_bytes())
    if delta_reign["schemaVersion"] != 1:
        raise ValueError("Invalid Delta Reign printing catalog")
    for card in delta_reign["cards"]:
        set_id, _ = card["cardID"].rsplit("-", 1)
        for printing in card["printings"]:
            finish = printing["finish"]
            if set_id == "me06" and finish == "normal":
                group, lane = 1840, "Normal"
            elif set_id == "mep" and finish in {"prerelease", "staff", "cosmos", "holo", "pokemonCenter"}:
                group, lane = 24451, "Holofoil"
            else:
                raise ValueError("Invalid Delta Reign market lane")
            product = printing.get("productID")
            if product is None and card["cardID"] == "mep-114" and finish == "staff":
                continue
            add(3, group, product, lane)
    prize_packs = json.loads((repo / "publisher/pokemon-prize-pack-printings.json").read_bytes())
    if prize_packs["schemaVersion"] != 1 or prize_packs["groupID"] != 22880:
        raise ValueError("Invalid Pokémon Prize Pack printing catalog")
    for entry in prize_packs["entries"]:
        if not entry["variantID"].startswith("pokemonStamp|") or entry["printing"] not in {"Normal", "Holofoil"}:
            raise ValueError("Invalid Pokémon Prize Pack market lane")
        add(3, prize_packs["groupID"], entry["productID"], entry["printing"])
    lorcana = json.loads((repo / "TradingCardScanner/LorcanaCatalogSeed/market.json").read_bytes())
    for printing in lorcana["physicalPrintings"]:
        if printing["status"] != "verified":
            continue
        for market in printing.get("marketMappings") or []:
            add(71, market["groupID"], market["productID"], market["providerVariantID"])
    if scopes is None:
        production_seed = repo / "TradingCardScanner/OnePieceCatalogSeed/one-piece-catalog-release.json"
        for group, product, lane in one_piece_rows(envelope_payload(json.loads((one_piece_envelope or production_seed).read_bytes()))):
            add(68, group, product, lane)
        yugioh = json.loads((repo / "TradingCardScanner/YuGiOhCatalogSeed/catalog.json").read_bytes())
        for group, product, lane in yugioh_rows(yugioh):
            add(2, group, product, lane)
    else:
        for game, (category, _) in CATALOG_NAMESPACES.items():
            for group, products in validate_catalog_scope(scopes[game], game).items():
                scope[(category, group)] = products
    required_categories = {2, 3, 68, 71} if scopes is None else {3, 71}
    if not required_categories <= {category for category, _ in scope} or len(scope) > 900:
        raise ValueError("Unexpected catalog pricing scope")
    return scope


def validate_response(raw, category, group, resource, *, upstream=False):
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
            fields = row.get("extendedData", [] if upstream else None)
            if (type(row.get("categoryId")) is not int or type(row.get("groupId")) is not int
                    or row["categoryId"] != category or row["groupId"] != group
                    or not isinstance(row.get("name"), str) or not row["name"]
                    or not isinstance(fields, list)):
                raise ValueError("Foreign or incomplete product")
            if any(not isinstance(field, dict) or not isinstance(field.get("name"), str)
                   or (field["name"] == "Number" and not isinstance(field.get("value"), str)) for field in fields):
                raise ValueError("Malformed product fields")
        else:
            value = row.get("marketPrice")
            if not isinstance(row.get("subTypeName"), str) or (value is not None and (type(value) not in (int, float) or not math.isfinite(value) or value < 0)):
                raise ValueError("Invalid market price")
    return rows


def prepare(scope, cache, site, fetch=read_http, now=stamp, pause=time.sleep, yugioh_source=None):
    # Reuse recent bodies with their original receipts. Aging captures are
    # fetched again, including when upstream has not published a new build.
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
                age = (instant(now()) - instant(receipt["capturedAt"])).total_seconds()
                if age < 0:
                    raise ValueError("Capture receipt is in the future")
                if age >= CAPTURE_REUSE_SECONDS:
                    receipt = None
            if not receipt:
                retained = yugioh_source / "tcgcsv" / f"{group}-{resource}.json" if category == 2 and yugioh_source is not None else None
                if retained is not None and not retained.is_file():
                    retained = None
                if retained is not None:
                    age = (instant(now()) - datetime.fromtimestamp(retained.stat().st_mtime, timezone.utc)).total_seconds()
                    if not 0 <= age < CAPTURE_REUSE_SECONDS:
                        retained = None
                if retained is not None:
                    raw = retained.read_bytes()
                    captured_at = datetime.fromtimestamp(retained.stat().st_mtime, timezone.utc).replace(microsecond=0).isoformat()
                else:
                    pause(0.1)
                    raw = fetch("https://tcgcsv.com/" + path)
                    captured_at = now()
                validate_response(raw, category, group, resource, upstream=True)
                receipt = {"sha256": digest(raw), "capturedAt": captured_at}
                raw_path.write_bytes(raw)
                receipts[path] = receipt
                temporary = receipts_path.with_suffix(".tmp")
                temporary.write_bytes(packed(receipts))
                temporary.replace(receipts_path)
            if not 0 <= (instant(now()) - instant(receipt["capturedAt"])).total_seconds() < 86400:
                raise ValueError("A stale capture cannot be published as current")
            rows = validate_response(raw, category, group, resource, upstream=True)
            selected = []
            for row in rows:
                product = row["productId"]
                if product not in products:
                    continue
                if resource == "products":
                    selected.append({key: row[key] for key in ("productId", "categoryId", "groupId", "name")} | {
                        "extendedData": [field for field in row.get("extendedData", []) if field["name"] == "Number"]})
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
    feed_paths = paths - {"last-updated.txt"}
    if not feed_paths:
        raise ValueError("Price feed must contain at least one product/price pair")
    for path in feed_paths:
        peer = path.rsplit("/", 1)[0] + ("/prices" if path.endswith("/products") else "/products")
        if peer not in paths:
            raise ValueError("Incomplete product/price pair")


def read_site(raw, read_file):
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
        files[path] = read_file(path, size)
    validate_site(index, files)
    return files


def restore(site, origin=ORIGIN, fetch=read_http, require_fresh=False, now=stamp, require_present=False):
    if origin not in (ORIGIN, R2_ORIGIN):
        raise ValueError("Unexpected production origin")
    namespace = site / NAMESPACE
    local = namespace / "index.json"
    raw = local.read_bytes() if local.exists() else fetch(origin + "/" + NAMESPACE + "/index.json", 1024 * 1024, absent_ok=True)
    if raw is None:
        if require_present:
            raise ValueError("Published market-prices/v1/index.json is missing; restore the last feed or stage a validated replacement.")
        return False
    def read_file(path, size):
        if local.exists():
            return (namespace / path).read_bytes()
        return fetch(origin + "/" + NAMESPACE + "/" + path, size)
    files = read_site(raw, read_file)
    if require_fresh:
        for path, body in files.items():
            if path == "last-updated.txt":
                continue
            captured = instant(json.loads(body)["sourceFetchedAt"])
            if not 0 <= (instant(now()) - captured).total_seconds() < MAX_PUBLISH_AGE_SECONDS:
                raise ValueError("Price publication requires recent upstream captures")
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


def check_publication_build(site, fetch=read_http):
    """Reject a prepared job that lost the production slot to a newer build."""
    marker = "last-updated.txt"
    candidate = instant((site / NAMESPACE / marker).read_text().strip())
    active = fetch(f"{ORIGIN}/{NAMESPACE}/{marker}", 1024, absent_ok=True)
    if active is not None and candidate < instant(active.decode().strip()):
        raise ValueError("The prepared price feed is older than the active production build")


def write_catalog_scopes(repo, site, game=None):
    for selected in ([game] if game else CATALOG_NAMESPACES):
        raw = catalog_scope(repo, site, selected)
        validate_catalog_scope(raw, selected)
        target = site / CATALOG_NAMESPACES[selected][1] / SCOPE_FILE
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)


def check_catalog_scopes(site, prepared):
    for game, (_, namespace) in CATALOG_NAMESPACES.items():
        expected = (site / namespace / SCOPE_FILE).read_bytes()
        candidate = (prepared / namespace / SCOPE_FILE).read_bytes()
        if expected != candidate:
            raise ValueError(f"The {game} price scope changed during preparation. Prepare prices again.")


def read_r2_scope(game, namespace, fetch):
    pointer = fetch(f"{R2_ORIGIN}/{namespace}/current.json", 65 * 1024 * 1024, absent_ok=True)
    expected = digest(pointer) if pointer is not None else None
    raw = fetch(f"{R2_ORIGIN}/{namespace}/{SCOPE_FILE}", MAX_SCOPE_BYTES, absent_ok=True)
    if raw is not None:
        validate_catalog_scope(raw, game)
        if json.loads(raw)["pointerSHA256"] == expected:
            return raw

    # A catalog sync can be interrupted between its mutable scope and pointer.
    # Reuse an authenticated scope from the current price build only if it
    # still describes the active catalog revision.
    import market_price_v2 as v2
    active = v2.validate_pointer(fetch(f"{R2_ORIGIN}/{v2.LATEST}", v2.MAX_POINTER_BYTES))
    relative = f"scopes/{game}.json"
    row = next(item for item in active["files"] if item["path"] == relative)
    raw = fetch(f"{R2_ORIGIN}/{v2.V2}/builds/{active['build']}/{relative}", row["byteCount"])
    if v2.entry(relative, raw) != row:
        raise ValueError(f"The immutable R2 {game} scope failed its build checks")
    validate_catalog_scope(raw, game)
    if json.loads(raw)["pointerSHA256"] != expected:
        raise ValueError(f"The R2 {game} scope does not match its active catalog")
    return raw


def capture_r2_scopes(site, fetch=read_http):
    """Use the scopes bound to R2's own active catalogs for primary prices."""
    for game, (_, namespace) in CATALOG_NAMESPACES.items():
        relative = Path(namespace) / SCOPE_FILE
        raw = read_r2_scope(game, namespace, fetch)
        path = site / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)


def confirm_r2_scopes(site, fetch=read_http):
    for game, (_, namespace) in CATALOG_NAMESPACES.items():
        relative = Path(namespace) / SCOPE_FILE
        if read_r2_scope(game, namespace, fetch) != (site / relative).read_bytes():
            raise ValueError(f"The R2 {game} scope changed during price preparation")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build = commands.add_parser("prepare")
    build.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    build.add_argument("--cache-dir", type=Path, required=True)
    build.add_argument("--site-root", type=Path, required=True)
    build.add_argument("--report", type=Path, required=True)
    build.add_argument("--yugioh-source", type=Path, help="Reuse the same job's build-bound YGO source without another upstream download")
    scopes = build.add_mutually_exclusive_group()
    scopes.add_argument("--verified-one-piece-envelope", type=Path,
                        help="Production envelope already verified with the app-pinned keys")
    scopes.add_argument("--catalog-scopes", type=Path, help="Directory of captured catalog price scopes")
    preserve = commands.add_parser("restore")
    preserve.add_argument("--site-root", type=Path, required=True)
    preserve.add_argument("--origin", default=ORIGIN)
    preserve.add_argument("--require-fresh", action="store_true")
    preserve.add_argument("--require-present", action="store_true")
    check = commands.add_parser("check-publication-build")
    check.add_argument("--site-root", type=Path, required=True)
    write_scopes = commands.add_parser("write-catalog-scopes")
    write_scopes.add_argument("--site-root", type=Path, required=True)
    write_scopes.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    write_scopes.add_argument("--game", choices=CATALOG_NAMESPACES)
    check_scopes = commands.add_parser("check-catalog-scopes")
    check_scopes.add_argument("--site-root", type=Path, required=True)
    check_scopes.add_argument("--prepared", type=Path, required=True)
    capture = commands.add_parser("capture-r2-scopes")
    capture.add_argument("--site-root", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "prepare":
        captures = ({game: (args.catalog_scopes / namespace / SCOPE_FILE).read_bytes()
                     for game, (_, namespace) in CATALOG_NAMESPACES.items()} if args.catalog_scopes else None)
        result = prepare(scope_from_repo(args.repo, args.verified_one_piece_envelope, scopes=captures),
                         args.cache_dir, args.site_root, yugioh_source=args.yugioh_source)
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_bytes(packed(result))
        print(json.dumps({key: value for key, value in result.items() if key != "missingProducts"}, sort_keys=True))
    elif args.command == "restore":
        restored = restore(args.site_root, args.origin, require_fresh=args.require_fresh,
                           require_present=args.require_present)
        print("Price namespace preserved" if restored else "No price namespace is published")
    elif args.command == "check-publication-build":
        check_publication_build(args.site_root)
    elif args.command == "write-catalog-scopes":
        write_catalog_scopes(args.repo, args.site_root, args.game)
    elif args.command == "capture-r2-scopes":
        capture_r2_scopes(args.site_root)
    else:
        check_catalog_scopes(args.site_root, args.prepared)


if __name__ == "__main__":
    main()
