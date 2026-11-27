#!/usr/bin/env python3
"""Publish the shared catalog site tree to Cloudflare R2 without partial states.

The site tree is the same directory Firebase Hosting deploys
(`publisher/site`). Response headers come from the `firebase.json` hosting
rules, so both hosts serve each path with the same Cache-Control and
Content-Type.

Objects are published in tiers, and each tier is read back through the
public hostname and hash-verified before the next one starts:

  0. immutable releases (never overwritten once present)
  1. price group files
  2. price index and catalog price scopes
  3. catalog pointers (`current.json`)
  4. the price build marker (`last-updated.txt`)

A failure in any tier stops the run before later tiers, so clients never see
a pointer or marker that names objects missing from the public host. Objects
whose stored hash and headers already match are skipped, so a rerun is a
no-op. Nothing is ever deleted.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import fnmatch
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import secrets
import subprocess
import sys
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, build_opener

from market_price_feeds import NoRedirects

IMMUTABLE, PRICE_DATA, PRICE_INDEX, POINTER, MARKER = range(5)
TIER_NAMES = ("immutable releases", "price files", "price index and scopes", "catalog pointers", "build marker")
MARKER_PATHS = {"market-prices/v1/last-updated.txt"}
INDEX_PATHS = {"market-prices/v1/index.json"}
DEFAULT_TYPES = {".json": "application/json", ".txt": "text/plain; charset=utf-8"}
MAX_READBACK_BYTES = 128 * 1024 * 1024


class PublishError(RuntimeError):
    pass


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
    if "immutable" in cache_control:
        return IMMUTABLE
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
    """Return (status, headers, body) for an identity-encoded GET with no redirects."""
    request = Request(url, headers={"User-Agent": "ScanStashCatalogPublisher/1.0", "Accept-Encoding": "identity",
                                    "Cache-Control": "no-cache"})
    try:
        with build_opener(NoRedirects()).open(request, timeout=60) as response:
            body = response.read(MAX_READBACK_BYTES + 1)
            return response.status, {k.lower(): v for k, v in response.headers.items()}, body
    except HTTPError as error:
        return error.code, {k.lower(): v for k, v in error.headers.items()}, b""


def verify_readback(item, public_base, fetch, nonce):
    url = f"{public_base.rstrip('/')}/{quote(item['key'])}?r2v={nonce}"
    status, headers, body = fetch(url)
    problems = []
    if status != 200:
        problems.append(f"HTTP {status}")
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
        raise PublishError(f"Readback failed for {item['key']}: {', '.join(problems)}")


def publish(objects, store, public_base, *, fetch=fetch_public, dry_run=False, verify_all=False,
            workers=8, log=print):
    summary = {"uploaded": 0, "unchanged": 0, "verified": 0}
    nonce = secrets.token_hex(8)
    for current in range(len(TIER_NAMES)):
        items = [item for item in objects if item["tier"] == current]
        if not items:
            continue
        with ThreadPoolExecutor(max_workers=workers) as pool:
            states = list(pool.map(store.head, [item["key"] for item in items]))
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
        to_verify = items if verify_all else pending
        with ThreadPoolExecutor(max_workers=workers) as pool:
            list(pool.map(lambda item: verify_readback(item, public_base, fetch, nonce), to_verify))
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
    args = parser.parse_args(argv)
    if not args.public_base.startswith("https://"):
        parser.error("--public-base must be an https:// origin")
    if not args.bucket or not re.fullmatch(r"[0-9a-f]{32}", args.account_id or ""):
        parser.error("Set --bucket/R2_BUCKET_NAME and a 32-hex --account-id/R2_ACCOUNT_ID")
    try:
        objects = plan(args.site, HostingRules.load(args.firebase_config))
        store = AwsCliStore(args.bucket, f"https://{args.account_id}.r2.cloudflarestorage.com")
        summary = publish(objects, store, args.public_base, dry_run=args.dry_run, verify_all=args.verify_all)
    except PublishError as error:
        print(f"R2 publish stopped: {error}", file=sys.stderr)
        return 1
    print(f"R2 publish {'dry run ' if args.dry_run else ''}complete: {summary['uploaded']} uploaded, "
          f"{summary['unchanged']} unchanged, {summary['verified']} verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
