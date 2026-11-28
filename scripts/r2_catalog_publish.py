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
  3. v1 price index
  4. catalog pointers (`current.json`)
  5. catalog price scopes (`market-price-scope.json`)
  6. the v1 price build marker (`last-updated.txt`)

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

from cloudflare_cache import CacheVerificationError, purge_and_verify
from market_price_feeds import (
    CATALOG_NAMESPACES,
    MAX_SCOPE_BYTES,
    NAMESPACE,
    R2_ORIGIN,
    SCOPE_FILE,
    NoRedirects,
    confirm_r2_scopes,
    instant,
    packed,
    restore,
    validate_catalog_scope,
)
import market_price_v2 as v2
from market_price_rollback import VERIFIED

IMMUTABLE, V2_POINTER, PRICE_DATA, PRICE_INDEX, POINTER, CATALOG_SCOPE, MARKER = range(7)
TIER_NAMES = (
    "immutable releases and price builds",
    "v2 price pointer",
    "price files",
    "price index",
    "catalog pointers",
    "catalog price scopes",
    "build marker",
)
MARKER_PATHS = {"market-prices/v1/last-updated.txt"}
INDEX_PATHS = {"market-prices/v1/index.json"}
PRIMARY_CATALOG_NAMESPACES = ("v1", "magic/v1", "one-piece/v1", "yugioh/v1")
SCOPED_CATALOG_NAMESPACES = {namespace: game for game, (_, namespace) in CATALOG_NAMESPACES.items()}
DEFAULT_TYPES = {".json": "application/json", ".txt": "text/plain; charset=utf-8"}
MAX_READBACK_BYTES = 128 * 1024 * 1024
MAX_READBACK_RETRIES = 3
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
CACHE_VERIFICATION_FAILED_EXIT = 2


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
    if name == "market-price-scope.json":
        return CATALOG_SCOPE
    if relative in INDEX_PATHS:
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


def build_catalog_metadata(site, namespace, revision, *, previous_revision=None, previous_pointer_path=None, rules=None):
    """Build canonical metadata binding a staged primary catalog release to its predecessor."""
    site = Path(site)
    if namespace not in PRIMARY_CATALOG_NAMESPACES:
        raise PublishError(f"Unsupported primary catalog namespace: {namespace}")
    if type(revision) is not int or not 1 <= revision <= 100_000:
        raise PublishError(f"Invalid catalog revision: {revision}")
    if (previous_revision is None) != (previous_pointer_path is None):
        raise PublishError("Predecessor revision and pointer path must either both be set or both be omitted")
    previous_sha = None
    if previous_revision is not None:
        if type(previous_revision) is not int or not 1 <= previous_revision < revision:
            raise PublishError(f"Catalog revision {revision} must be greater than predecessor {previous_revision}")
        previous_path = Path(previous_pointer_path)
        if not previous_path.is_file():
            raise PublishError(f"Missing predecessor pointer file: {previous_path}")
        previous_sha = sha256(previous_path)

    pointer_path = site / namespace / "current.json"
    release_dir = site / namespace / "releases" / str(revision)
    release_envelope = release_dir / "catalog-release.json"
    if not pointer_path.is_file() or not release_envelope.is_file():
        raise PublishError(f"Missing staged {namespace} pointer or immutable release {revision}")
    pointer_sha = sha256(pointer_path)
    if sha256(release_envelope) != pointer_sha:
        raise PublishError(f"Staged {namespace}/current.json disagrees with immutable revision {revision}")

    immutable_files = []
    for entry in sorted(release_dir.rglob("*")):
        if entry.is_symlink():
            raise PublishError(f"Refusing to publish a link: {entry}")
        if not entry.is_file():
            continue
        rel = entry.relative_to(site).as_posix()
        if rules is not None and rules.ignored(rel):
            continue
        if any(part.startswith(".") for part in PurePosixPath(rel).parts):
            continue
        immutable_files.append(rel)

    scope_sha = None
    if namespace in SCOPED_CATALOG_NAMESPACES:
        game = SCOPED_CATALOG_NAMESPACES[namespace]
        scope_path = site / namespace / SCOPE_FILE
        if not scope_path.is_file():
            raise PublishError(f"Missing staged {namespace}/{SCOPE_FILE}")
        raw_scope = scope_path.read_bytes()
        validate_catalog_scope(raw_scope, game)
        scope_doc = json.loads(raw_scope)
        if scope_doc["pointerSHA256"] != pointer_sha or scope_doc["revision"] != revision:
            raise PublishError(f"Staged {namespace}/{SCOPE_FILE} is not bound to revision {revision}")
        scope_sha = sha256(scope_path)

    metadata = {
        "schemaVersion": 1,
        "namespace": namespace,
        "revision": revision,
        "previousRevision": previous_revision,
        "previousPointerSHA256": previous_sha,
        "pointerSHA256": pointer_sha,
        "immutableFiles": immutable_files,
        "scopeSHA256": scope_sha,
    }
    return validate_catalog_metadata(packed(metadata), expected_namespace=namespace)


def validate_catalog_metadata(raw, expected_namespace=None):
    if len(raw) > 1024 * 1024:
        raise PublishError("Catalog publish metadata exceeds byte limit")
    doc = json.loads(raw)
    expected_keys = {
        "schemaVersion", "namespace", "revision", "previousRevision",
        "previousPointerSHA256", "pointerSHA256", "immutableFiles", "scopeSHA256",
    }
    if not isinstance(doc, dict) or set(doc) != expected_keys or doc["schemaVersion"] != 1:
        raise PublishError("Invalid catalog publish metadata")
    namespace = doc["namespace"]
    if namespace not in PRIMARY_CATALOG_NAMESPACES:
        raise PublishError(f"Unsupported primary catalog namespace: {namespace}")
    if expected_namespace is not None and namespace != expected_namespace:
        raise PublishError(f"Catalog metadata namespace {namespace} does not match {expected_namespace}")
    revision = doc["revision"]
    previous_revision = doc["previousRevision"]
    previous_sha = doc["previousPointerSHA256"]
    pointer_sha = doc["pointerSHA256"]
    if type(revision) is not int or not 1 <= revision <= 100_000:
        raise PublishError("Invalid catalog metadata revision")
    if (previous_revision is None) != (previous_sha is None):
        raise PublishError("Incomplete catalog metadata predecessor")
    if previous_revision is not None:
        if type(previous_revision) is not int or not 1 <= previous_revision < revision:
            raise PublishError("Catalog metadata revision is not greater than predecessor")
        if not isinstance(previous_sha, str) or not SHA256_RE.match(previous_sha):
            raise PublishError("Invalid catalog metadata predecessor SHA-256")
    if not isinstance(pointer_sha, str) or not SHA256_RE.match(pointer_sha):
        raise PublishError("Invalid catalog metadata pointer SHA-256")
    immutable_files = doc["immutableFiles"]
    prefix = f"{namespace}/releases/{revision}/"
    envelope_key = f"{prefix}catalog-release.json"
    if (not isinstance(immutable_files, list) or not immutable_files
            or len(set(immutable_files)) != len(immutable_files)
            or immutable_files != sorted(immutable_files)
            or envelope_key not in immutable_files
            or any(not isinstance(path, str) or not path.startswith(prefix)
                   or ".." in PurePosixPath(path).parts for path in immutable_files)):
        raise PublishError("Invalid catalog metadata immutable file list")
    scope_sha = doc["scopeSHA256"]
    if namespace in SCOPED_CATALOG_NAMESPACES:
        if not isinstance(scope_sha, str) or not SHA256_RE.match(scope_sha):
            raise PublishError(f"Primary catalog {namespace} requires a bound scope SHA-256")
    elif scope_sha is not None:
        raise PublishError(f"Unexpected scope SHA-256 for {namespace}")
    return doc


def validate_primary_catalog_plan(objects, metadata):
    """Ensure a primary catalog publication contains only its exact verified namespace objects."""
    namespace = metadata["namespace"]
    pointer_key = f"{namespace}/current.json"
    envelope_key = f"{namespace}/releases/{metadata['revision']}/catalog-release.json"
    scope_key = f"{namespace}/{SCOPE_FILE}" if metadata["scopeSHA256"] is not None else None
    expected_keys = set(metadata["immutableFiles"]) | {pointer_key}
    if scope_key is not None:
        expected_keys.add(scope_key)
    by_key = {item["key"]: item for item in objects}
    if set(by_key) != expected_keys:
        extra = sorted(set(by_key) - expected_keys)
        missing = sorted(expected_keys - set(by_key))
        raise PublishError(f"Primary catalog staged files mismatch (extra={extra}, missing={missing})")
    for key in metadata["immutableFiles"]:
        if by_key[key]["tier"] != IMMUTABLE:
            raise PublishError(f"Expected immutable cache rule for {key}")
    if by_key[pointer_key]["tier"] != POINTER:
        raise PublishError(f"Expected pointer tier for {pointer_key}")
    if by_key[pointer_key]["sha256"] != metadata["pointerSHA256"]:
        raise PublishError(f"Staged {pointer_key} SHA-256 differs from catalog metadata")
    if by_key[envelope_key]["sha256"] != metadata["pointerSHA256"]:
        raise PublishError(f"Staged {envelope_key} SHA-256 differs from {pointer_key}")
    if scope_key is not None:
        scope_item = by_key[scope_key]
        if scope_item["tier"] != CATALOG_SCOPE:
            raise PublishError(f"Expected scope tier for {scope_key}")
        if scope_item["sha256"] != metadata["scopeSHA256"]:
            raise PublishError(f"Staged {scope_key} SHA-256 differs from catalog metadata")
        raw_scope = scope_item["path"].read_bytes()
        if len(raw_scope) > MAX_SCOPE_BYTES:
            raise PublishError(f"Staged {scope_key} exceeds byte limit")
        validate_catalog_scope(raw_scope, SCOPED_CATALOG_NAMESPACES[namespace])
        scope_doc = json.loads(raw_scope)
        if scope_doc["pointerSHA256"] != metadata["pointerSHA256"] or scope_doc["revision"] != metadata["revision"]:
            raise PublishError(f"Staged {scope_key} is not bound to active revision {metadata['revision']}")


def check_catalog_activation(metadata, store, public_base, fetch):
    """Confirm R2's active catalog pointer and predecessor immutable object before mutating."""
    namespace = metadata["namespace"]
    pointer_key = f"{namespace}/current.json"
    state = store.head(pointer_key)
    url = f"{public_base.rstrip('/')}/{quote(pointer_key)}?r2v={secrets.token_hex(8)}"
    status, _, body = fetch(url)
    if state is None:
        if status != 404:
            raise PublishError(f"Cannot establish current {pointer_key} from public readback")
        if metadata["previousPointerSHA256"] is not None:
            raise PublishError(f"Active R2 {pointer_key} is missing; refusing implicit re-baseline")
        return
    if status != 200:
        raise PublishError(f"Cannot establish current {pointer_key} from public readback")
    live_sha = hashlib.sha256(body).hexdigest()
    if state["sha256"] and live_sha != state["sha256"]:
        raise PublishError(f"Cannot establish current {pointer_key} from public readback")
    if live_sha not in (metadata["previousPointerSHA256"], metadata["pointerSHA256"]):
        raise PublishError(f"Active R2 {pointer_key} changed before activation")
    if metadata["previousRevision"] is not None:
        prev_key = f"{namespace}/releases/{metadata['previousRevision']}/catalog-release.json"
        prev_url = f"{public_base.rstrip('/')}/{quote(prev_key)}?r2v={secrets.token_hex(8)}"
        prev_status, _, prev_body = fetch(prev_url)
        if prev_status != 200 or hashlib.sha256(prev_body).hexdigest() != metadata["previousPointerSHA256"]:
            raise PublishError(f"Predecessor immutable release {prev_key} is missing or mismatched on R2")


def publish(objects, store, public_base, *, fetch=fetch_public, dry_run=False, verify_all=False,
            workers=8, log=print, confirm_current=None, record_build=False, catalog_metadata=None):
    summary = {"uploaded": 0, "unchanged": 0, "verified": 0}
    nonce = secrets.token_hex(8)
    has_v2 = any(item["key"] == v2.LATEST for item in objects)
    if catalog_metadata is not None:
        validate_primary_catalog_plan(objects, catalog_metadata)
        if not dry_run:
            check_catalog_activation(catalog_metadata, store, public_base, fetch)
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
            # Recheck the source scopes after the potentially long immutable upload.
            if confirm_current is not None:
                confirm_current()
            if record_build:
                record_verified_build(items[0], store, public_base, fetch)
        if catalog_metadata is not None and current in (POINTER, CATALOG_SCOPE) and not dry_run:
            # Recheck active catalog pointer and predecessor after immutable upload/readback.
            check_catalog_activation(catalog_metadata, store, public_base, fetch)
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
        # Never activate a v2 or catalog pointer based solely on object metadata,
        # even on a retry. Read back every referenced immutable object.
        to_verify = items if verify_all or has_v2 or catalog_metadata is not None else pending
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


def record_verified_build(pointer, store, public_base, fetch):
    """Register verified bytes before any client can see the active pointer."""
    build = v2.validate_pointer(pointer["path"].read_bytes())["build"]
    item = {**pointer, "key": f"{VERIFIED}{build}.json", "cache_control": "public,max-age=31536000,immutable"}
    state = store.head(item["key"])
    if state is None:
        store.put(item)
    elif state["sha256"] != item["sha256"]:
        raise PublishError(f"Conflicting verified v2 build receipt: {build}")
    elif state["cache_control"] != item["cache_control"] or state["content_type"] != item["content_type"]:
        store.put(item)
    verify_readback(item, public_base, fetch, secrets.token_hex(8))


def verify_existing_origin(objects, public_base, *, fetch=fetch_public, workers=8):
    """Idempotent origin-only readback check used by --recover-cache-only (never uploads)."""
    nonce = secrets.token_hex(8)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        list(pool.map(lambda item: verify_readback(item, public_base, fetch, nonce), objects))
    return {"uploaded": 0, "unchanged": len(objects), "verified": len(objects)}


def _publication_label(args, site, catalog_metadata):
    if args.primary_catalog is not None and catalog_metadata is not None:
        return f"catalog:{args.primary_catalog}@rev-{catalog_metadata['revision']}"
    if args.primary_prices:
        pointer_path = site / v2.LATEST
        if pointer_path.is_file():
            build = v2.validate_pointer(pointer_path.read_bytes())["build"]
            return f"prices:v2@{build[:12]}"
        return "prices:v2"
    return "site"


def _write_cache_report(path, payload):
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--site", required=True, help="Site tree to publish (the Firebase public directory)")
    parser.add_argument("--firebase-config", default=str(Path(__file__).resolve().parents[1] / "firebase.json"))
    parser.add_argument("--bucket", default=os.environ.get("R2_BUCKET_NAME"))
    parser.add_argument("--account-id", default=os.environ.get("R2_ACCOUNT_ID"))
    parser.add_argument("--public-base", help="HTTPS origin used for readback")
    parser.add_argument("--dry-run", action="store_true", help="Compare with the bucket without uploading")
    parser.add_argument("--verify-all", action="store_true", help="Read back every object, not only uploads")
    parser.add_argument("--recover-cache-only", action="store_true",
                        help="Verify active origin objects without uploading, then rerun purge and canonical readback")
    parser.add_argument("--cloudflare-zone-id", default=os.environ.get("CLOUDFLARE_ZONE_ID"),
                        help="32-hex Cloudflare zone ID for targeted single-file cache purge")
    parser.add_argument("--cloudflare-purge-token", default=os.environ.get("CLOUDFLARE_CACHE_PURGE_TOKEN"),
                        help="Least-privilege Cloudflare API token with Cache Purge permission")
    parser.add_argument("--require-cache-verification", action="store_true",
                        help="Fail cache verification if Cloudflare purge credentials are not configured")
    parser.add_argument("--cache-report", type=Path,
                        help="Write structured JSON origin and client-visible cache verification report")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--primary-prices", action="store_true", help="Publish prices bound to the active R2 scopes")
    mode.add_argument("--primary-catalog", choices=PRIMARY_CATALOG_NAMESPACES,
                      help="Publish a single verified catalog namespace directly to R2")
    mode.add_argument("--write-catalog-metadata", type=Path,
                      help="Write canonical primary-catalog publish metadata and exit")
    parser.add_argument("--catalog-metadata", type=Path, help="Metadata file for --primary-catalog")
    parser.add_argument("--namespace", choices=PRIMARY_CATALOG_NAMESPACES, help="Namespace for --write-catalog-metadata")
    parser.add_argument("--revision", type=int, help="Revision for --write-catalog-metadata")
    parser.add_argument("--previous-revision", type=int, help="Predecessor revision for --write-catalog-metadata")
    parser.add_argument("--previous-pointer", type=Path, help="Predecessor pointer path for --write-catalog-metadata")
    args = parser.parse_args(argv)
    if args.write_catalog_metadata is not None:
        if not args.namespace or args.revision is None:
            parser.error("--write-catalog-metadata requires --namespace and --revision")
        try:
            rules = HostingRules.load(args.firebase_config)
            metadata = build_catalog_metadata(
                args.site, args.namespace, args.revision,
                previous_revision=args.previous_revision,
                previous_pointer_path=args.previous_pointer,
                rules=rules,
            )
            args.write_catalog_metadata.parent.mkdir(parents=True, exist_ok=True)
            args.write_catalog_metadata.write_bytes(packed(metadata))
        except (PublishError, ValueError, OSError) as error:
            print(f"R2 metadata preparation stopped: {error}", file=sys.stderr)
            return 1
        return 0
    if not args.public_base or not args.public_base.startswith("https://"):
        parser.error("--public-base must be an https:// origin")
    if not args.recover_cache_only and (not args.bucket or not re.fullmatch(r"[0-9a-f]{32}", args.account_id or "")):
        parser.error("Set --bucket/R2_BUCKET_NAME and a 32-hex --account-id/R2_ACCOUNT_ID")
    try:
        confirm_current = None
        catalog_metadata = None
        site = Path(args.site)
        if args.primary_prices:
            if args.public_base.rstrip("/") != R2_ORIGIN:
                raise PublishError("Primary prices must use the approved R2 origin")
            def confirm_current():
                confirm_r2_scopes(site)

            confirm_current()
            if not (site / NAMESPACE / "index.json").is_file():
                raise PublishError("Missing local primary price capture")
            restore(site, origin=R2_ORIGIN, require_fresh=True, require_present=True)
            if not (args.recover_cache_only and (site / v2.LATEST).is_file()):
                v2.stage(site)
        elif args.primary_catalog is not None:
            if args.public_base.rstrip("/") != R2_ORIGIN:
                raise PublishError("Primary catalogs must use the approved R2 origin")
            if args.catalog_metadata is None:
                raise PublishError("--primary-catalog requires --catalog-metadata")
            if (site / "market-prices").exists():
                raise PublishError("Only the primary price publisher can change prices on R2")
            catalog_metadata = validate_catalog_metadata(
                args.catalog_metadata.read_bytes(), expected_namespace=args.primary_catalog)
        elif (site / "market-prices").exists():
            raise PublishError("Only the primary price publisher can change prices on R2")
        objects = plan(site, HostingRules.load(args.firebase_config))
        if args.primary_prices:
            # Scope files are authoritative catalog inputs on R2. This job only reads them.
            objects = [item for item in objects if item["key"].startswith("market-prices/")]
        if args.recover_cache_only:
            if catalog_metadata is not None:
                validate_primary_catalog_plan(objects, catalog_metadata)
            summary = verify_existing_origin(objects, args.public_base)
        else:
            store = AwsCliStore(args.bucket, f"https://{args.account_id}.r2.cloudflarestorage.com")
            summary = publish(objects, store, args.public_base, dry_run=args.dry_run,
                              verify_all=args.verify_all, confirm_current=confirm_current,
                              record_build=args.primary_prices, catalog_metadata=catalog_metadata)
    except (PublishError, ValueError, OSError) as error:
        print(f"R2 publish stopped: {error}", file=sys.stderr)
        return 1

    publication = _publication_label(args, site, catalog_metadata)
    print(f"Origin verification (nonce-based) {'dry run ' if args.dry_run else ''}complete for {publication}: "
          f"{summary['uploaded']} uploaded, {summary['unchanged']} unchanged, {summary['verified']} verified")

    if args.primary_catalog is None and not args.primary_prices:
        print(f"R2 publish {'dry run ' if args.dry_run else ''}complete: {summary['uploaded']} uploaded, "
              f"{summary['unchanged']} unchanged, {summary['verified']} verified")
        return 0

    enforce_cache = args.require_cache_verification or os.environ.get("CLOUDFLARE_CACHE_ENFORCE") == "true"
    try:
        cache_result = purge_and_verify(
            objects,
            args.public_base,
            primary_catalog=args.primary_catalog,
            primary_prices=args.primary_prices,
            zone_id=args.cloudflare_zone_id,
            api_token=args.cloudflare_purge_token,
            enforce=enforce_cache,
            dry_run=args.dry_run,
        )
    except (CacheVerificationError, ValueError) as error:
        affected = getattr(error, "affected_urls", [])
        stage = getattr(error, "stage", "cache")
        report = {
            "publication": publication,
            "originVerified": True,
            "cacheStatus": "failed",
            "stage": stage,
            "affectedUrls": affected,
            "error": str(error),
        }
        _write_cache_report(args.cache_report, report)
        print(
            f"Client-visible cache verification FAILED after verified R2 activation for {publication} "
            f"(stage={stage}, affected={', '.join(affected) or 'none'}): {error}\n"
            "R2 immutable objects and active pointer remain intact; publication is NOT Stage 2 cache-ready. "
            "Re-run with --recover-cache-only (or rerun the publish job) to retry invalidation and canonical readback.",
            file=sys.stderr,
        )
        return CACHE_VERIFICATION_FAILED_EXIT

    report = {
        "publication": publication,
        "originVerified": True,
        "cacheStatus": cache_result["status"],
        "reason": cache_result.get("reason"),
        "affectedUrls": cache_result["affectedUrls"],
        "purged": cache_result["purged"],
        "canonical": cache_result["canonical"],
    }
    _write_cache_report(args.cache_report, report)
    print(f"R2 publish {'dry run ' if args.dry_run else ''}complete: {summary['uploaded']} uploaded, "
          f"{summary['unchanged']} unchanged, {summary['verified']} verified "
          f"(client-visible cache verification: {cache_result['status']})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
