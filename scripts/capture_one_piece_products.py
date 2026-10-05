#!/usr/bin/env python3
"""Capture reviewed product inputs; replay never fetches or rewrites retained bytes.

Raw responses stay in the private capture directory. captured-products.json is
the reconciler input with observed pagination files, not a physical catalog.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from datetime import datetime, timezone
import fcntl
import hashlib
import json
from pathlib import Path
import threading
import time
from urllib.parse import parse_qs, urljoin, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
from urllib.error import HTTPError, URLError

from normalize_one_piece_sources import Document, one
from reconcile_one_piece_launch_products import capture_index, checked_capture, load_products

MAX_BYTES = 5 * 1024 * 1024
ORIGINS = {"en.onepiece-cardgame.com", "coretcg.com"}


def checked_url(value, host=None):
    url = urlsplit(value)
    if url.scheme != "https" or url.netloc not in ORIGINS or url.fragment or (host and url.netloc != host):
        raise ValueError("unexpected product capture origin: " + value)
    return value


def safe_path(root, relative):
    path = Path(relative)
    if path.is_absolute() or not path.parts or ".." in path.parts:
        raise ValueError("unsafe capture path")
    for i in range(1, len(path.parts) + 1):
        if (root / Path(*path.parts[:i])).is_symlink():
            raise ValueError("symlink capture path")
    target = root / path
    target.resolve().relative_to(root.resolve())
    return target


def atomic_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    if temporary.exists():
        raise ValueError("unfinished manifest write requires repair: " + str(temporary))
    with temporary.open("x") as stream:
        stream.write(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(path)


class RejectRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        checked_url(newurl)
        raise ValueError("unexpected capture redirect")


class ProductCapture:
    def __init__(self, root, offline=False, official_manifest=None, transport=None,
                 user_agent="CardScannerOnePieceReview/1.0"):
        self.root, self.offline = Path(root), offline
        if not user_agent.strip() or "/" not in user_agent or "\n" in user_agent or "\r" in user_agent:
            raise ValueError("custom versioned User-Agent required")
        self.user_agent = user_agent
        self.root.mkdir(parents=True, exist_ok=True)
        self.path = safe_path(self.root, "capture-manifest.json")
        self.manifest = json.loads(self.path.read_text()) if self.path.exists() else {"schemaVersion": 1, "captures": []}
        if self.manifest.get("schemaVersion") != 1 or not isinstance(self.manifest.get("captures"), list):
            raise ValueError("unsupported capture manifest")
        capture_index(self.manifest["captures"], "rawFile")
        capture_index(self.manifest["captures"], "id")
        self.external = official_manifest or {"captures": []}
        capture_index(self.external["captures"], "id")
        self.transport = transport or self._download
        self.pacing, self.storage = threading.Lock(), threading.Lock()
        self.last_request, self.requests = 0.0, 0

    def _download(self, url):
        with self.pacing:
            if self.requests >= 2000:
                raise ValueError("product capture request budget exceeded")
            time.sleep(max(0, 0.150 - (time.monotonic() - self.last_request)))
            self.last_request = time.monotonic()
            self.requests += 1
        request = Request(url, headers={"User-Agent": self.user_agent})
        with build_opener(RejectRedirect()).open(request, timeout=40) as response:
            if response.geturl() != url:
                raise ValueError("capture response URL changed")
            raw = response.read(MAX_BYTES + 1)
        return raw

    def capture(self, url, filename, identity=None):
        checked_url(url)
        path = safe_path(self.root, filename)
        with self.storage:
            records = [c for c in self.manifest["captures"] if c["rawFile"] == filename]
            if records:
                record = records[0]
                if record["sourceURL"] != url or (identity is not None and record.get("id") != identity):
                    raise ValueError("retained capture identity changed")
                return record, checked_capture(self.root, record)
            external = [c for c in self.external["captures"] if c.get("id") == identity] if identity else []
            if external:
                record = one(external, "retained official capture")
                if record["sourceURL"] != url:
                    raise ValueError("retained official URL changed")
                return record, checked_capture(self.root.parent, record)
            if path.exists() or path.with_suffix(path.suffix + ".tmp").exists():
                raise ValueError("orphan capture requires explicit repair: " + filename)
            if self.offline:
                raise ValueError("offline capture missing: " + url)
        raw = self.transport(url)
        if not isinstance(raw, bytes) or len(raw) > MAX_BYTES:
            raise ValueError("capture exceeds response byte limit")
        record = {"rawFile": filename, "sourceURL": url, "payloadSHA256": hashlib.sha256(raw).hexdigest(),
                  "byteCount": len(raw), "observedAt": datetime.now(timezone.utc).isoformat()}
        if identity is not None:
            record["id"] = identity
        with self.storage:
            if path.exists():
                raise ValueError("capture path raced with another writer")
            if identity and any(c.get("id") == identity for c in self.manifest["captures"]):
                raise ValueError("duplicate capture identity")
            path.parent.mkdir(parents=True, exist_ok=True)
            temporary = path.with_suffix(path.suffix + ".tmp")
            with temporary.open("xb") as stream:
                stream.write(raw)
            temporary.replace(path)
            self.manifest["captures"].append(record)
            atomic_json(self.path, self.manifest)
        return record, raw


def next_retailer_page(document, current_url, group_id, page):
    forward, explicit = set(), set()
    for pagination in document.nodes(cls="pagination"):
        for link in pagination.nodes("a"):
            if "disabled" in link.attrs.get("class", "").split():
                continue
            href = link.attrs.get("href", "")
            if not href or href == "#":
                continue
            url = checked_url(urljoin(current_url, href), "coretcg.com")
            query = parse_qs(urlsplit(url).query)
            if urlsplit(url).path != "/Products/GetProducts" or query.get("mastergroupid") != [group_id] or query.get("mastercategoryid") != ["68"]:
                raise ValueError("pagination product scope changed")
            try:
                target_page = int(one(query.get("p", []), "pagination page"))
            except (ValueError, TypeError):
                raise ValueError("invalid pagination page") from None
            is_next = "next" in link.attrs.get("rel", "").split()
            if is_next and target_page <= page:
                raise ValueError("pagination cycle")
            if target_page > page:
                forward.add((target_page, url))
                if is_next:
                    explicit.add((target_page, url))
    if len(explicit) > 1:
        raise ValueError("ambiguous next page")
    if not forward:
        return None
    target = next(iter(explicit)) if explicit else min(forward)
    if target[0] != page + 1:
        raise ValueError("pagination inventory gap")
    return target


def capture_products(capture, manifest):
    result = deepcopy(manifest)
    completed = []
    for product in result["products"]:
        prefix = product["prefix"].lower()
        existing = [r for r in capture.manifest["captures"] + capture.external["captures"]
                    if r.get("id") == product["manufacturerCaptureID"]]
        filename = one(existing, "retained manufacturer identity")["rawFile"] if existing else "bandai-" + prefix + ".html"
        _, raw = capture.capture(product["manufacturerListURL"], filename, product["manufacturerCaptureID"])
        document = Document(raw).root
        images = []
        for card in product["cards"]:
            alias = card["artworkAlias"]
            modal = one((n for n in document.nodes("dl", "modalCol") if n.attrs.get("id") == alias), "reviewed artwork")
            image = one((n for n in modal.nodes("img") if n.attrs.get("data-src")), "artwork image")
            images.append((checked_url(urljoin(product["manufacturerListURL"], image.attrs["data-src"]), "en.onepiece-cardgame.com"), "images/" + alias + ".png"))
        finish = product.get("manufacturerFinish")
        if finish:
            _, raw = capture.capture(finish["sourceURL"], finish["captureFile"])
            if finish["exactText"] not in Document(raw).root.text(exclude={"script"}):
                raise ValueError("manufacturer finish specification changed")
        page, url, visited, files = 1, product["retailerStartURL"], set(), []
        while True:
            if url in visited or page > 100:
                raise ValueError("pagination cycle or page budget exceeded")
            visited.add(url)
            known = product["retailerCaptureFiles"]
            filename = known[page-1] if page <= len(known) else prefix + "-retailer-page" + str(page) + ".html"
            _, raw = capture.capture(checked_url(url, "coretcg.com"), filename)
            files.append(filename)
            retailer = Document(raw).root
            if not any(retailer.nodes("div", "productCard")):
                raise ValueError("retailer page has no product records; inventory remains incomplete")
            next_page = next_retailer_page(retailer, url, product["retailerGroupID"], page)
            if next_page is None:
                break
            page, url = next_page
        if files[:len(product["retailerCaptureFiles"])] != product["retailerCaptureFiles"]:
            raise ValueError("reviewed pagination scope disappeared")
        product["retailerCaptureFiles"] = files
        # Fetch each distinct reviewed alias once. The shared limiter applies to
        # all workers, and failures propagate before completion is recorded.
        with ThreadPoolExecutor(max_workers=4) as workers:
            list(workers.map(lambda pair: capture.capture(*pair), dict.fromkeys(images)))
        completed.append({"productID": product["productID"], "retailerCaptureFiles": files,
                          "scopedPaginationComplete": True, "physicalCoverageComplete": False})
    return result, completed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--products", required=True, type=Path)
    parser.add_argument("--capture-root", required=True, type=Path)
    parser.add_argument("--official-captures", type=Path)
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--user-agent", default="CardScannerOnePieceReview/1.0")
    parser.add_argument("--keep-going", action="store_true",
                        help="Capture the whole batch; retain source availability gaps for review")
    args = parser.parse_args()
    manifest = load_products(args.products)
    official_path = args.official_captures or args.products.parent / "captures.json"
    official = json.loads(official_path.read_text()) if official_path.exists() else None
    args.capture_root.mkdir(parents=True, exist_ok=True)
    # One process owns manifest movement; thread workers share its storage lock.
    with safe_path(args.capture_root, ".product-capture.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError("another product capture owns this directory") from None
        capture = ProductCapture(args.capture_root, args.offline, official, user_agent=args.user_agent)
        failures = []
        if args.keep_going:
            products, completed = deepcopy(manifest), []
            for index, product in enumerate(manifest["products"]):
                try:
                    result, records = capture_products(capture, {**manifest, "products": [product]})
                    products["products"][index] = result["products"][0]
                    completed.extend(records)
                    print("Captured product", index + 1, "/", len(manifest["products"]), product["prefix"], flush=True)
                except (HTTPError, URLError, TimeoutError) as error:
                    failures.append({"productID": product["productID"], "prefix": product["prefix"],
                                     "reason": str(error), "physicalCoverageComplete": False})
                    print("Source gap", product["prefix"], str(error), flush=True)
                except ValueError as error:
                    # Keep integrity/origin/schema errors fatal. An observed empty
                    # retailer result is a source gap, never completed pagination.
                    if str(error) != "retailer page has no product records; inventory remains incomplete":
                        raise
                    failures.append({"productID": product["productID"], "prefix": product["prefix"],
                                     "reason": str(error), "physicalCoverageComplete": False})
                    print("Source gap", product["prefix"], str(error), flush=True)
        else:
            products, completed = capture_products(capture, manifest)
        for filename, value in (("captured-products.json", products),
                                ("product-capture-review.json", {"schemaVersion": 1, "products": completed,
                                 **({"failedProducts": failures, "batchCaptureComplete": not failures} if args.keep_going else {})})):
            path = safe_path(capture.root, filename)
            if not path.exists() or json.loads(path.read_text()) != value:
                atomic_json(path, value)
    print(f"Captured/replayed {len(completed)} products; no physical completeness granted")


if __name__ == "__main__":
    main()
