#!/usr/bin/env python3
"""Targeted Cloudflare single-file cache purge and canonical readback checks.

Never uses purge-everything, never accepts arbitrary purge URLs, and never logs
or embeds Cloudflare credentials in outputs or exception messages.
"""
from __future__ import annotations

import hashlib
from http.client import IncompleteRead
import json
from pathlib import PurePosixPath
import re
from ssl import SSLEOFError
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlsplit
from urllib.request import Request, build_opener

from market_price_feeds import CATALOG_NAMESPACES, NAMESPACE, SCOPE_FILE, NoRedirects
import market_price_v2 as v2

APPROVED_HOSTS = frozenset({"catalog-staging.scan-stash.com", "catalog.scan-stash.com"})
PRIMARY_CATALOG_NAMESPACES = ("v1", "magic/v1", "one-piece/v1", "yugioh/v1")
SCOPED_CATALOG_NAMESPACES = {namespace: game for game, (_, namespace) in CATALOG_NAMESPACES.items()}

MUTABLE_CATALOG_PATHS = {
    namespace: tuple(
        [f"{namespace}/current.json"]
        + ([f"{namespace}/{SCOPE_FILE}"] if namespace in SCOPED_CATALOG_NAMESPACES else [])
    )
    for namespace in PRIMARY_CATALOG_NAMESPACES
}
MUTABLE_PRICE_PATHS = (
    v2.LATEST,
    f"{NAMESPACE}/last-updated.txt",
    f"{NAMESPACE}/index.json",
)
BYPASS_REQUIRED_PATHS = frozenset(
    {v2.LATEST, f"{v2.V2}/history.json", f"{NAMESPACE}/last-updated.txt", f"{NAMESPACE}/index.json"}
    | {path for paths in MUTABLE_CATALOG_PATHS.values() for path in paths}
)
SHORT_TTL_MUTABLE_PATHS = frozenset()
ALLOWED_PURGE_PATHS = frozenset(
    set(MUTABLE_PRICE_PATHS)
    | {path for paths in MUTABLE_CATALOG_PATHS.values() for path in paths}
)

BYPASS_CACHE_STATUSES = frozenset({"BYPASS", "DYNAMIC"})
FORBIDDEN_MUTABLE_CACHE_STATUSES = frozenset({"HIT", "STALE", "EXPIRED", "REVALIDATED", "UPDATING"})
EDGE_HIT_CACHE_STATUSES = frozenset({"HIT", "REVALIDATED"})

ZONE_ID_RE = re.compile(r"[0-9a-f]{32}\Z")
MAX_PURGE_BATCH = 30
MAX_PURGE_RETRIES = 3
MAX_CANONICAL_RETRIES = 3
MAX_RETRY_AFTER_SECONDS = 30
MAX_READBACK_BYTES = 128 * 1024 * 1024
CLOUDFLARE_API_BASE = "https://api.cloudflare.com/client/v4"


class CacheVerificationError(RuntimeError):
    """Post-activation Cloudflare purge or canonical readback failure."""

    def __init__(self, message, *, stage="cache", affected_urls=(), details=None):
        super().__init__(message)
        self.stage = stage
        self.affected_urls = list(affected_urls)
        self.details = details or []


def validate_public_base(public_base):
    parsed = urlsplit(public_base.rstrip("/"))
    if (parsed.scheme != "https" or parsed.netloc not in APPROVED_HOSTS
            or parsed.path or parsed.query or parsed.fragment or "@" in parsed.netloc):
        raise ValueError(f"Unapproved Cloudflare public origin: {public_base}")
    return f"https://{parsed.netloc}"


def canonical_url(public_base, key):
    origin = validate_public_base(public_base)
    if key not in ALLOWED_PURGE_PATHS or ".." in PurePosixPath(key).parts:
        raise ValueError(f"Refusing to purge non-allowlisted path: {key}")
    return f"{origin}/{quote(key, safe='/')}"


def validate_purge_url(url):
    parsed = urlsplit(url)
    if (parsed.scheme != "https" or parsed.netloc not in APPROVED_HOSTS
            or parsed.query or parsed.fragment or "@" in parsed.netloc):
        raise ValueError(f"Unapproved Cloudflare purge URL: {url}")
    key = parsed.path.lstrip("/")
    if key not in ALLOWED_PURGE_PATHS or ".." in PurePosixPath(key).parts:
        raise ValueError(f"Refusing to purge non-allowlisted URL path: {key}")
    return url


def purge_items_for_plan(objects, public_base, *, primary_catalog=None, primary_prices=False):
    """Derive exact mutable objects to purge and verify from a verified publication plan."""
    validate_public_base(public_base)
    if primary_catalog and primary_prices:
        raise ValueError("Cannot derive purge targets for catalog and prices simultaneously")
    if primary_catalog:
        if primary_catalog not in MUTABLE_CATALOG_PATHS:
            raise ValueError(f"Unknown primary catalog namespace: {primary_catalog}")
        allowed = set(MUTABLE_CATALOG_PATHS[primary_catalog])
    elif primary_prices:
        allowed = set(MUTABLE_PRICE_PATHS)
    else:
        return []
    by_key = {item["key"]: item for item in objects}
    ordered = (MUTABLE_CATALOG_PATHS[primary_catalog] if primary_catalog else MUTABLE_PRICE_PATHS)
    selected = []
    for key in ordered:
        if key in by_key and key in allowed:
            selected.append(by_key[key])
    return selected


def parse_retry_after(headers):
    value = headers.get("retry-after")
    if not value:
        return None
    text = value.strip()
    if text.isdigit():
        seconds = int(text)
        return max(1, min(seconds, MAX_RETRY_AFTER_SECONDS))
    return None


def _sanitize_error_messages(body_bytes):
    try:
        doc = json.loads(body_bytes)
        errors = doc.get("errors")
        if isinstance(errors, list) and errors:
            parts = []
            for entry in errors[:3]:
                if isinstance(entry, dict):
                    code = entry.get("code")
                    msg = entry.get("message")
                    parts.append(f"{code}: {msg}" if code is not None else str(msg))
            if parts:
                return "; ".join(parts)
    except Exception:
        pass
    return None


def purge_urls(urls, zone_id, api_token, *, opener=None, sleep=time.sleep, max_retries=MAX_PURGE_RETRIES):
    """Purge exact canonical URLs via Cloudflare's single-file purge API."""
    if not zone_id or not ZONE_ID_RE.match(zone_id):
        raise CacheVerificationError("Invalid Cloudflare zone ID (expected 32 lowercase hex characters)",
                                     stage="purge", affected_urls=urls)
    if not api_token or any(ch.isspace() for ch in api_token):
        raise CacheVerificationError("Missing or malformed Cloudflare cache purge token",
                                     stage="purge", affected_urls=urls)
    validated = []
    seen = set()
    for url in urls:
        clean = validate_purge_url(url)
        if clean not in seen:
            seen.add(clean)
            validated.append(clean)
    if not validated:
        return []

    endpoint = f"{CLOUDFLARE_API_BASE}/zones/{zone_id}/purge_cache"
    http = opener or build_opener(NoRedirects())
    receipts = []
    for index in range(0, len(validated), MAX_PURGE_BATCH):
        batch = validated[index:index + MAX_PURGE_BATCH]
        payload = json.dumps({"files": batch}, separators=(",", ":")).encode("utf-8")
        for attempt in range(max_retries + 1):
            request = Request(
                endpoint,
                data=payload,
                method="POST",
                headers={
                    "Authorization": f"Bearer {api_token}",
                    "Content-Type": "application/json",
                    "User-Agent": "ScanStashCatalogPublisher/1.0",
                },
            )
            delay = 2 ** attempt
            try:
                with http.open(request, timeout=30) as response:
                    status = response.status
                    body = response.read(1024 * 1024)
                    headers = {k.lower(): v for k, v in response.headers.items()}
                if status != 200:
                    raise CacheVerificationError(
                        f"Cloudflare purge returned unexpected HTTP {status}",
                        stage="purge", affected_urls=batch,
                    )
                try:
                    doc = json.loads(body)
                except ValueError as error:
                    raise CacheVerificationError(
                        "Cloudflare purge returned malformed JSON response",
                        stage="purge", affected_urls=batch,
                    ) from error
                if not isinstance(doc, dict) or doc.get("success") is not True or not isinstance(doc.get("result"), dict):
                    detail = _sanitize_error_messages(body) or "success=false or missing result"
                    raise CacheVerificationError(
                        f"Cloudflare purge API rejected request ({detail})",
                        stage="purge", affected_urls=batch,
                    )
                receipts.append({"files": batch, "id": doc["result"].get("id")})
                break
            except HTTPError as error:
                with error:
                    code = error.code
                    headers = {k.lower(): v for k, v in (error.headers.items() if error.headers else ())}
                    err_body = error.read(64 * 1024) if hasattr(error, "read") else b""
                retryable = code == 429 or 500 <= code < 600
                if not retryable or attempt == max_retries:
                    detail = _sanitize_error_messages(err_body)
                    suffix = f" ({detail})" if detail else ""
                    raise CacheVerificationError(
                        f"Cloudflare purge failed with HTTP {code}{suffix}",
                        stage="purge", affected_urls=batch,
                    ) from None
                retry_after = parse_retry_after(headers) if code == 429 else None
                delay = retry_after if retry_after is not None else delay
            except (URLError, TimeoutError, ConnectionError, IncompleteRead, SSLEOFError) as error:
                if attempt == max_retries:
                    raise CacheVerificationError(
                        f"Cloudflare purge transport error: {type(error).__name__}",
                        stage="purge", affected_urls=batch,
                    ) from None
            print(f"Retrying Cloudflare cache purge ({attempt + 1}/{max_retries}) in {delay}s for {len(batch)} URL(s)",
                  file=sys.stderr, flush=True)
            sleep(delay)
    return receipts


def fetch_canonical(url, *, extra_headers=None):
    """Fetch a canonical public URL like an ordinary client (no bypass headers or nonce)."""
    parsed = urlsplit(url)
    if parsed.query:
        raise ValueError(f"Canonical client verification URL must not include a query string: {url}")
    headers = {"User-Agent": "ScanStashCatalogClientCheck/1.0", "Accept-Encoding": "identity"}
    if extra_headers:
        headers.update(extra_headers)
    request = Request(url, headers=headers)
    opener = build_opener(NoRedirects())
    try:
        with opener.open(request, timeout=60) as response:
            body = response.read(MAX_READBACK_BYTES + 1)
            return response.status, {k.lower(): v for k, v in response.headers.items()}, body
    except HTTPError as error:
        with error:
            return error.code, {k.lower(): v for k, v in (error.headers.items() if error.headers else ())}, b""


def check_canonical_response(key, expected_sha256, expected_content_type, expected_cache_control,
                             status, headers, body):
    """Validate an ordinary client response against expected bytes, headers, and cache status."""
    problems = []
    if status != 200:
        problems.append(f"HTTP {status}")
    elif len(body) > MAX_READBACK_BYTES:
        problems.append("body exceeds readback limit")
    else:
        encoding = headers.get("content-encoding", "identity").strip().lower()
        if encoding not in ("", "identity"):
            problems.append(f"unexpected content-encoding {encoding!r}")
        else:
            actual_sha = hashlib.sha256(body).hexdigest()
            if actual_sha != expected_sha256:
                problems.append("SHA-256 mismatch")
        if headers.get("content-type") != expected_content_type:
            problems.append(f"content-type {headers.get('content-type')!r}")
        if headers.get("cache-control") != expected_cache_control:
            problems.append(f"cache-control {headers.get('cache-control')!r}")

    cache_status = headers.get("cf-cache-status", "").strip().upper()
    if key in BYPASS_REQUIRED_PATHS:
        if cache_status not in BYPASS_CACHE_STATUSES:
            problems.append(f"cf-cache-status {cache_status or 'missing'!r} (expected BYPASS or DYNAMIC)")
    elif key in SHORT_TTL_MUTABLE_PATHS:
        if not cache_status:
            problems.append("cf-cache-status missing")
        elif cache_status == "STALE":
            problems.append("cf-cache-status 'STALE'")

    return problems, cache_status


def verify_canonical_objects(items, public_base, *, fetch=fetch_canonical,
                             retries=MAX_CANONICAL_RETRIES, sleep=time.sleep):
    """Verify affected mutable objects through their canonical URLs as an ordinary client."""
    origin = validate_public_base(public_base)
    results = []
    failures = []
    for item in items:
        key = item["key"]
        url = canonical_url(origin, key)
        last_problems = []
        last_record = None
        for attempt in range(retries + 1):
            try:
                status, headers, body = fetch(url)
                problems, cache_status = check_canonical_response(
                    key, item["sha256"], item["content_type"], item["cache_control"],
                    status, headers, body,
                )
                actual_sha = hashlib.sha256(body).hexdigest() if status == 200 and len(body) <= MAX_READBACK_BYTES else None
                last_record = {
                    "url": url,
                    "key": key,
                    "status": status,
                    "expectedSHA256": item["sha256"],
                    "observedSHA256": actual_sha,
                    "contentType": headers.get("content-type"),
                    "cacheControl": headers.get("cache-control"),
                    "cfCacheStatus": cache_status or None,
                    "cfRay": headers.get("cf-ray"),
                    "age": headers.get("age"),
                    "etag": headers.get("etag"),
                }
                if not problems:
                    results.append(last_record)
                    break
                last_problems = problems
                retryable = (
                    status in (404, 429) or 500 <= status < 600
                    or "SHA-256 mismatch" in problems
                    or any("cf-cache-status" in p for p in problems)
                )
                if not retryable or attempt == retries:
                    failures.append({"url": url, "problems": problems, "observed": last_record})
                    break
            except (URLError, TimeoutError, ConnectionError, IncompleteRead, SSLEOFError) as error:
                last_problems = [f"transport error: {type(error).__name__}"]
                if attempt == retries:
                    failures.append({"url": url, "problems": last_problems})
                    break
            delay = 2 ** attempt
            print(f"Retrying canonical readback ({attempt + 1}/{retries}) for {url}: {', '.join(last_problems)}",
                  file=sys.stderr, flush=True)
            sleep(delay)
    if failures:
        summary = "; ".join(f"{entry['url']} ({', '.join(entry['problems'])})" for entry in failures)
        raise CacheVerificationError(
            f"Canonical client-visible verification failed: {summary}",
            stage="canonical-readback",
            affected_urls=[entry["url"] for entry in failures],
            details=failures,
        )
    return results


def purge_and_verify(objects, public_base, *, primary_catalog=None, primary_prices=False,
                     zone_id=None, api_token=None, enforce=False, dry_run=False,
                     opener=None, fetch=fetch_canonical, sleep=time.sleep, log=print):
    """Purge derived mutable URLs for a verified publication and run canonical readback."""
    items = purge_items_for_plan(objects, public_base, primary_catalog=primary_catalog,
                                 primary_prices=primary_prices)
    urls = [canonical_url(public_base, item["key"]) for item in items]
    if dry_run:
        return {"status": "skipped", "reason": "dry-run", "affectedUrls": urls, "purged": [], "canonical": []}
    if not items:
        return {"status": "skipped", "reason": "no_mutable_targets", "affectedUrls": [], "purged": [], "canonical": []}
    if bool(zone_id) != bool(api_token):
        raise CacheVerificationError(
            "Partial Cloudflare cache configuration: set both CLOUDFLARE_ZONE_ID and CLOUDFLARE_CACHE_PURGE_TOKEN",
            stage="credentials",
            affected_urls=urls,
        )
    if not zone_id and not api_token:
        if enforce:
            raise CacheVerificationError(
                "Cloudflare cache verification is enforced, but CLOUDFLARE_ZONE_ID or "
                "CLOUDFLARE_CACHE_PURGE_TOKEN is not configured",
                stage="credentials",
                affected_urls=urls,
            )
        log("Client-visible Cloudflare purge and canonical verification skipped: "
            "CLOUDFLARE_ZONE_ID / CLOUDFLARE_CACHE_PURGE_TOKEN not configured "
            "(not eligible for Stage 2 cache readiness).")
        return {
            "status": "skipped",
            "reason": "credentials_not_configured",
            "affectedUrls": urls,
            "purged": [],
            "canonical": [],
        }

    receipts = purge_urls(urls, zone_id, api_token, opener=opener, sleep=sleep)
    log(f"Cloudflare targeted purge succeeded for {len(urls)} canonical URL(s): {', '.join(urls)}")
    canonical = verify_canonical_objects(items, public_base, fetch=fetch, sleep=sleep)
    for row in canonical:
        log(f"Client-visible canonical verification passed: {row['url']} "
            f"(HTTP {row['status']}, cf-cache-status={row['cfCacheStatus']}, "
            f"cache-control={row['cacheControl']})")
    return {
        "status": "passed",
        "affectedUrls": urls,
        "purged": receipts,
        "canonical": canonical,
    }
