#!/usr/bin/env python3
"""Publish the shared catalog site tree to Cloudflare R2 without partial states.

The site tree is the same directory Firebase Hosting deploys
(`publisher/site`). Response headers come from the `firebase.json` hosting
rules, so both hosts serve each path with the same Cache-Control and
Content-Type.

Objects are published in tiers, and each tier is read back through the
public hostname and hash-verified before the next one starts:

  0. immutable releases (never overwritten once present)
  1. v2 price pointer (after the immutable price build is verified)
  2. v1 price group files
  3. v1 price index and catalog price scopes
  4. catalog pointers (`current.json`)
  5. the v1 price build marker (`last-updated.txt`)

A failure in any tier stops the run before later tiers, so clients never see
a pointer or marker that names objects missing from the public host. Objects
whose stored hash and headers already match are skipped, so a rerun is a
no-op. Nothing is ever deleted.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import fnmatch
import hashlib
from http.client import IncompleteRead
import json
import os
from pathlib import Path, PurePosixPath
import re
import secrets
from ssl import SSLEOFError
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, build_opener

from market_price_feeds import NAMESPACE, SCOPE_FILE, NoRedirects, instant
import market_price_v2 as v2

IMMUTABLE, V2_POINTER, PRICE_DATA, PRICE_INDEX, POINTER, MARKER = range(6)
TIER_NAMES = ("immutable releases and price builds", "v2 price pointer", "price files", "price index and scopes", "catalog pointers", "build marker")
MARKER_PATHS = {"market-prices/v1/last-updated.txt"}
INDEX_PATHS = {"market-prices/v1/index.json"}
DEFAULT_TYPES = {".json": "application/json", ".txt": "text/plain; charset=utf-8"}
MAX_READBACK_BYTES = 128 * 1024 * 1024
MAX_READBACK_RETRIES = 3


class PublishError(RuntimeError):
    pass


class ReadbackMismatch(PublishError):
    """Public bytes, headers, or object presence disagree with the verified source."""


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def glob_regex(source):
    """Translate a Firebase Hosting glob (`**`, `*`, `?`) to a regex."""
    pattern, index = "", 0
    source = source.lstrip("/")
    while index < len(source):
        if source.startswith("**", index):
            pattern += ".*"
            index += 2
        elif source[index] == "*":
            pattern += "[^/]*"
            index += 1
        elif source[index] == "?":
            pattern += "[^/]"
            index += 1
        else:
            pattern += re.escape(source[index])
            index += 1
    return re.compile(f"^{pattern}$")


class HostingRules:
    def __init__(self, config):
        hosting = config["hosting"]
        if isinstance(hosting, list):
            if len(hosting) != 1:
                raise PublishError("Expected exactly one hosting target in firebase.json")
            hosting = hosting[0]
        self.ignore = list(hosting.get("ignore", []))
        self.rules = [(glob_regex(rule["source"]), {h["key"].lower(): h["value"] for h in rule["headers"]})
                      for rule in hosting.get("headers", [])]

    @classmethod
    def load(cls, path):
        return cls(json.loads(Path(path).read_text()))

    def ignored(self, relative):
        parts = PurePosixPath(relative).parts
        if parts and parts[0] == "__":
            return True  # Firebase-reserved namespace; not part of the site tree.
        for pattern in self.ignore:
            if pattern == "**/.*" and any(part.startswith(".") for part in parts):
                return True
            if pattern.startswith("**/") and pattern.endswith("/**"):
                if pattern[3:-3] in parts[:-1]:
                    return True
            elif fnmatch.fnmatchcase(relative, pattern):
                return True
        return False

    def headers(self, relative):
        merged = {}
        for regex, headers in self.rules:
            if regex.match(relative):
                merged.update(headers)
        cache_control = merged.get("cache-control")
        if not cache_control:
            raise PublishError(f"No Cache-Control rule in firebase.json covers {relative}")
        content_type = merged.get("content-type") or DEFAULT_TYPES.get(PurePosixPath(relative).suffix)
        if not content_type:
            raise PublishError(f"No Content-Type for {relative}; add a firebase.json header rule")
        return content_type, cache_control


def tier(relative, cache_control):
    name = PurePosixPath(relative).name
    if relative == v2.LATEST:
        if cache_control != "no-cache":
            raise PublishError("The v2 pointer must not be cached")
        return V2_POINTER
    if "immutable" in cache_control:
        return IMMUTABLE
    if relative.startswith(v2.V2 + "/"):
        raise PublishError(f"Nonimmutable v2 price build object: {relative}")
    if relative in MARKER_PATHS:
        return MARKER
    if name == "current.json":
        return POINTER
    if relative in INDEX_PATHS or name == "market-price-scope.json":
        return PRICE_INDEX
    if relative.startswith("market-prices/"):
        return PRICE_DATA
    raise PublishError(f"Unclassified mutable object {relative}; add it to a publication tier")


def plan(site, rules):
    site = Path(site)
    if not site.is_dir():
        raise PublishError(f"Site tree not found: {site}")
    objects = []
    for path in sorted(site.rglob("*")):
        if path.is_symlink():
            raise PublishError(f"Refusing to publish a link: {path}")
        if not path.is_file():
            continue
        relative = path.relative_to(site).as_posix()
        if rules.ignored(relative):
            continue
        content_type, cache_control = rules.headers(relative)
        objects.append({"key": relative, "path": path, "sha256": sha256(path), "size": path.stat().st_size,
                        "content_type": content_type, "cache_control": cache_control,
                        "tier": tier(relative, cache_control)})
    if not objects:
        raise PublishError("The site tree has nothing to publish")
    try:
        v2.check_plan(objects)
    except ValueError as error:
        raise PublishError(str(error)) from error
    return objects


class AwsCliStore:
    """R2 through the S3 API, using the AWS CLI as the connectivity check does."""

    def __init__(self, bucket, endpoint):
        self.bucket, self.endpoint = bucket, endpoint

    def _run(self, *args):
        command = ["aws", "--endpoint-url", self.endpoint, "--cli-connect-timeout", "10",
                   "--cli-read-timeout", "60", "--no-cli-pager", "--output", "json", "s3api", *args,
                   "--bucket", self.bucket]
        # Match the proven connectivity check: R2 rejects some automatic
        # checksum modes, and integrity is enforced by the public readback.
        env = {**os.environ, "AWS_DEFAULT_REGION": "auto", "AWS_REQUEST_CHECKSUM_CALCULATION": "when_required",
               "AWS_RESPONSE_CHECKSUM_VALIDATION": "when_required"}
        return subprocess.run(command, capture_output=True, text=True, env=env)

    def head(self, key):
        result = self._run("head-object", "--key", key)
        if result.returncode != 0:
            if "Not Found" in result.stderr or "(404)" in result.stderr:
                return None
            raise PublishError(f"head-object failed for {key}: {result.stderr.strip()}")
        data = json.loads(result.stdout)
        return {"sha256": data.get("Metadata", {}).get("sha256"), "content_type": data.get("ContentType"),
                "cache_control": data.get("CacheControl")}

    def put(self, item):
        result = self._run("put-object", "--key", item["key"], "--body", str(item["path"]),
                           "--content-type", item["content_type"], "--cache-control", item["cache_control"],
                           "--metadata", f"sha256={item['sha256']}")
        if result.returncode != 0:
            raise PublishError(f"put-object failed for {item['key']}: {result.stderr.strip()}")


def fetch_public(url):
    """Return (status, headers, body) for a bounded GET, retrying transient failures."""
    request = Request(url, headers={"User-Agent": "ScanStashCatalogPublisher/1.0", "Accept-Encoding": "identity",
                                    "Cache-Control": "no-cache"})
    opener = build_opener(NoRedirects())
    for attempt in range(MAX_READBACK_RETRIES + 1):
        try:
            with opener.open(request, timeout=60) as response:
                body = response.read(MAX_READBACK_BYTES + 1)
                return response.status, {k.lower(): v for k, v in response.headers.items()}, body
        except HTTPError as error:
            with error:
                retryable = error.code == 429 or 500 <= error.code < 600
                if not retryable or attempt == MAX_READBACK_RETRIES:
                    return error.code, {k.lower(): v for k, v in error.headers.items()}, b""
        except (URLError, TimeoutError, ConnectionError, IncompleteRead, SSLEOFError) as error:
            if attempt == MAX_READBACK_RETRIES:
                raise PublishError(f"Public readback failed for {url}: {error}") from error
        print(f"Retrying public readback ({attempt + 1}/{MAX_READBACK_RETRIES}): {url}",
              file=sys.stderr, flush=True)
        time.sleep(2 ** attempt)


def verify_readback(item, public_base, fetch, nonce):
    url = f"{public_base.rstrip('/')}/{quote(item['key'])}?r2v={nonce}"
    status, headers, body = fetch(url)
    problems = []
    if status not in (200, 404):
        # Transient HTTP errors are not evidence that the stored object is wrong.
        raise PublishError(f"Readback failed for {item['key']}: HTTP {status}")
    if status == 404:
        problems.append("HTTP 404")
    elif len(body) > MAX_READBACK_BYTES:
        problems.append("body exceeds the readback limit")
    else:
        if headers.get("content-encoding", "identity").lower() not in ("", "identity"):
            problems.append(f"unexpected content-encoding {headers['content-encoding']}")
        elif hashlib.sha256(body).hexdigest() != item["sha256"]:
            problems.append("SHA-256 mismatch")
        if headers.get("cache-control") != item["cache_control"]:
            problems.append(f"cache-control {headers.get('cache-control')!r}")
        if headers.get("content-type") != item["content_type"]:
            problems.append(f"content-type {headers.get('content-type')!r}")
    if problems:
        raise ReadbackMismatch(f"Readback failed for {item['key']}: {', '.join(problems)}")


def check_v2_activation(item, state, public_base, fetch, nonce):
    candidate = v2.validate_pointer(item["path"].read_bytes())
    if state is None:
        return
    # Read only an existing pointer, and ensure the public response actually
    # matches the current R2 object (not a stale CDN response).
    url = f"{public_base.rstrip('/')}/{v2.LATEST}?r2v={nonce}"
    status, _, body = fetch(url)
    if status != 200 or hashlib.sha256(body).hexdigest() != state["sha256"]:
        raise PublishError("Cannot establish current v2 pointer from public readback")
    active = v2.validate_pointer(body)
    if instant(candidate["sourceBuild"]) < instant(active["sourceBuild"]):
        raise PublishError("Refusing to activate an older v2 price build")


def publish(objects, store, public_base, *, fetch=fetch_public, dry_run=False, verify_all=False,
            workers=8, log=print, confirm_current=None):
    summary = {"uploaded": 0, "unchanged": 0, "verified": 0}
    nonce = secrets.token_hex(8)
    has_v2 = any(item["key"] == v2.LATEST for item in objects)
    for current in range(len(TIER_NAMES)):
        items = [item for item in objects if item["tier"] == current]
        if not items:
            continue
        with ThreadPoolExecutor(max_workers=workers) as pool:
            states = list(pool.map(store.head, [item["key"] for item in items]))
        if current == V2_POINTER and not dry_run:
            # A distinct URL prevents a cached pre-PUT pointer response from
            # being reused by the post-PUT public readback.
            check_v2_activation(items[0], states[0], public_base, fetch, secrets.token_hex(8))
            # Recheck Firebase after the potentially long immutable upload,
            # including same-day corrected artifacts. The workflow is serialized.
            if confirm_current is not None:
                confirm_current()
        pending = []
        for item, state in zip(items, states):
            matches = state is not None and state["sha256"] == item["sha256"] \
                and state["content_type"] == item["content_type"] and state["cache_control"] == item["cache_control"]
            if matches:
                summary["unchanged"] += 1
                continue
            if current == IMMUTABLE and state is not None and state["sha256"] != item["sha256"]:
                raise PublishError(f"Immutable object {item['key']} already exists with different bytes; "
                                   "publish known-good content under a new revision instead")
            pending.append(item)
        log(f"{TIER_NAMES[current]}: {len(pending)} to upload, {len(items) - len(pending)} unchanged")
        if dry_run:
            summary["uploaded"] += len(pending)
            continue
        with ThreadPoolExecutor(max_workers=workers) as pool:
            list(pool.map(store.put, pending))
        summary["uploaded"] += len(pending)
        # Never activate a v2 pointer based solely on object metadata, even
        # on a retry. Read back every referenced immutable price object.
        to_verify = items if verify_all or has_v2 else pending
        pending_keys = {item["key"] for item in pending}
        legacy_scopes = {f"{namespace}/{SCOPE_FILE}" for namespace in v2.SCOPES.values()}

        def verify_or_repair(item):
            key = item["key"]
            try:
                verify_readback(item, public_base, fetch, nonce)
            except ReadbackMismatch:
                # Metadata can match even when the actual object does not.
                # Repair only skipped, mutable legacy pricing objects from
                # the verified artifact; do not overwrite immutable builds
                # or retry an already-failed upload within this publication.
                if (key in pending_keys or item["tier"] == IMMUTABLE
                        or not (key.startswith(NAMESPACE + "/") or key in legacy_scopes)):
                    raise
                log(f"Repairing legacy price object after readback mismatch: {key}")
                store.put(item)
                verify_readback(item, public_base, fetch, secrets.token_hex(8))
                return 1
            return 0

        with ThreadPoolExecutor(max_workers=workers) as pool:
            repaired = sum(pool.map(verify_or_repair, to_verify))
        summary["uploaded"] += repaired
        summary["unchanged"] -= repaired
        summary["verified"] += len(to_verify)
    return summary


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--site", required=True, help="Site tree to publish (the Firebase public directory)")
    parser.add_argument("--firebase-config", default=str(Path(__file__).resolve().parents[1] / "firebase.json"))
    parser.add_argument("--bucket", default=os.environ.get("R2_BUCKET_NAME"))
    parser.add_argument("--account-id", default=os.environ.get("R2_ACCOUNT_ID"))
    parser.add_argument("--public-base", required=True, help="HTTPS origin used for readback")
    parser.add_argument("--dry-run", action="store_true", help="Compare with the bucket without uploading")
    parser.add_argument("--verify-all", action="store_true", help="Read back every object, not only uploads")
    parser.add_argument("--mirror-work", type=Path, help="Verified Firebase artifact directory; stage v2 and recheck before activation")
    args = parser.parse_args(argv)
    if not args.public_base.startswith("https://"):
        parser.error("--public-base must be an https:// origin")
    if not args.bucket or not re.fullmatch(r"[0-9a-f]{32}", args.account_id or ""):
        parser.error("Set --bucket/R2_BUCKET_NAME and a 32-hex --account-id/R2_ACCOUNT_ID")
    try:
        confirm_current = None
        if args.mirror_work is not None:
            from catalog_hosting_cache import confirm_mirror_candidate
            site = Path(args.site)
            def confirm_current():
                confirm_mirror_candidate(args.mirror_work, site)
            confirm_current()
            v2.stage(site)
        elif (Path(args.site) / v2.V2).exists():
            raise PublishError("v2 publication requires a verified Firebase mirror artifact")
        objects = plan(args.site, HostingRules.load(args.firebase_config))
        store = AwsCliStore(args.bucket, f"https://{args.account_id}.r2.cloudflarestorage.com")
        summary = publish(objects, store, args.public_base, dry_run=args.dry_run,
                          verify_all=args.verify_all, confirm_current=confirm_current)
    except (PublishError, ValueError, OSError) as error:
        print(f"R2 publish stopped: {error}", file=sys.stderr)
        return 1
    print(f"R2 publish {'dry run ' if args.dry_run else ''}complete: {summary['uploaded']} uploaded, "
          f"{summary['unchanged']} unchanged, {summary['verified']} verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
