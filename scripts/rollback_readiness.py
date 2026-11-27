#!/usr/bin/env python3
"""Continuous Firebase rollback readiness verification and reporting.

Verifies that Firebase Hosting (`scanstash-catalog-prod.web.app`) remains a
ready fallback target during the 30-day post-cutover rollback window:

  1. Continuous catalog and pricing parity against R2 (`catalog-staging.scan-stash.com`
     or the configured primary origin).
  2. HTTPS certificate validity and expiry headroom for both the Firebase origin
     and the custom rollback hostname (`catalog.scan-stash.com`) probed directly
     against Firebase via TLS SNI (so checks keep targeting Firebase even after
     public DNS switches to Cloudflare).
  3. Firebase Hosting storage and bandwidth headroom (staged site size plus
     Firebase Hosting API and Cloud Monitoring usage metrics).
  4. Explicit READY / NOT READY rollback readiness reporting in JSON and
     Markdown (`$GITHUB_STEP_SUMMARY`).

A failed check exits non-zero so the independent Firebase backup job fails
visibly without affecting or rolling back the verified R2 primary publication.
"""
from __future__ import annotations

import argparse
import base64
from datetime import datetime, timedelta, timezone
import gzip
import hashlib
from http.client import IncompleteRead
import json
import os
from pathlib import Path
import secrets
import socket
import ssl
import subprocess
import sys
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlparse
from urllib.request import Request, build_opener

from catalog_hosting_cache import MAX_POINTER_BYTES, NAMESPACES
from market_price_feeds import (
    CATALOG_NAMESPACES,
    MAX_SCOPE_BYTES,
    NAMESPACE as PRICE_V1_NAMESPACE,
    ORIGIN as FIREBASE_ORIGIN,
    R2_ORIGIN,
    SCOPE_FILE,
    NoRedirects,
)
import market_price_rollback as price_rollback
import market_price_v2 as price_v2

DEFAULT_ROLLBACK_HOSTNAME = "catalog.scan-stash.com"
REQUIRED_CATALOG_NAMESPACES = ("v1", "one-piece/v1")
DEFAULT_MIN_CERT_DAYS = 14
DEFAULT_STAGED_SITE_LIMIT_BYTES = 2 * 1024 * 1024 * 1024  # 2 GiB
DEFAULT_STORAGE_LIMIT_BYTES = 10 * 1024 * 1024 * 1024  # 10 GiB Hosting storage ceiling
DEFAULT_DAILY_BANDWIDTH_LIMIT_BYTES = 360 * 1024 * 1024  # 360 MiB/day free-tier baseline
DEFAULT_MONTHLY_BANDWIDTH_LIMIT_BYTES = 10 * 1024 * 1024 * 1024  # 10 GiB rolling 30d ceiling
DEFAULT_MIN_HEADROOM_RATIO = 0.20  # Require >= 20% headroom (<= 80% used)
MAX_API_RESPONSE_BYTES = 4 * 1024 * 1024
OAUTH_SCOPES = (
    "https://www.googleapis.com/auth/firebase.readonly "
    "https://www.googleapis.com/auth/monitoring.read"
)
ALLOWED_TOKEN_URIS = (
    "https://oauth2.googleapis.com/token",
    "https://accounts.google.com/o/oauth2/token",
)
FIREBASE_HOSTING_API = "https://firebasehosting.googleapis.com/v1beta1"
CLOUD_MONITORING_API = "https://monitoring.googleapis.com/v3"
STORAGE_METRIC = "firebasehosting.googleapis.com/storage/total_bytes"
BANDWIDTH_METRIC = "firebasehosting.googleapis.com/network/sent_bytes_count"
REQUIRED_MONITORING_ROLE = "roles/monitoring.viewer"


class ReadinessError(RuntimeError):
    """Raised when an internal readiness probe fails unexpectedly."""


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso_utc(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def format_bytes(num_bytes: int | float) -> str:
    value = float(num_bytes)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if abs(value) < 1024.0 or unit == "TiB":
            return f"{value:.2f} {unit}" if unit != "B" else f"{int(value)} B"
        value /= 1024.0
    return f"{value:.2f} TiB"


def normalize_origin(origin: str) -> str:
    cleaned = origin.strip().rstrip("/")
    parsed = urlparse(cleaned)
    if parsed.scheme != "https" or not parsed.netloc or parsed.path or parsed.query or parsed.fragment:
        raise ValueError(f"Expected an HTTPS origin without path or query: {origin!r}")
    return cleaned


def fetch_http_with_headers(url: str, maximum: int, *, absent_ok: bool = False) -> tuple[bytes | None, dict[str, str]]:
    """Bounded HTTPS readback with no redirects and transparent gzip decoding."""
    request = Request(
        url,
        headers={
            "User-Agent": "ScanStashRollbackReadiness/1.0",
            "Accept-Encoding": "gzip",
            "Cache-Control": "no-cache",
        },
    )
    try:
        with build_opener(NoRedirects()).open(request, timeout=60) as response:
            encoding = response.headers.get("Content-Encoding", "identity").strip().lower()
            if encoding == "gzip":
                with gzip.GzipFile(fileobj=response) as decoded:
                    data = decoded.read(maximum + 1)
            elif encoding == "identity":
                data = response.read(maximum + 1)
            else:
                raise ValueError(f"Unexpected Content-Encoding for {url}: {encoding}")
            if response.status != 200 or not 0 < len(data) <= maximum:
                raise ValueError(f"Unexpected HTTP {response.status} or byte count ({len(data)}) for {url}")
            return data, {k.lower(): v for k, v in response.headers.items()}
    except HTTPError as error:
        if absent_ok and error.code == 404:
            return None, {k.lower(): v for k, v in (error.headers.items() if error.headers else [])}
        raise


def fetch_with_retry(
    origin: str,
    rel_path: str,
    maximum: int,
    *,
    fetch=fetch_http_with_headers,
    absent_ok: bool = False,
    attempts: int | None = None,
    sleep=time.sleep,
) -> tuple[bytes | None, dict[str, str]]:
    max_attempts = (3 if fetch is fetch_http_with_headers else 1) if attempts is None else attempts
    last_error: Exception | None = None
    for attempt in range(max_attempts):
        nonce = secrets.token_hex(8)
        url = f"{origin}/{rel_path}?rbv={nonce}"
        try:
            return fetch(url, maximum, absent_ok=absent_ok)
        except (HTTPError, URLError, TimeoutError, ConnectionError, IncompleteRead, ssl.SSLEOFError, ValueError) as err:
            last_error = err
            retryable = not isinstance(err, HTTPError) or err.code in (429, 500, 502, 503, 504)
            if not retryable or attempt + 1 >= max_attempts:
                raise
            sleep(2 ** attempt)
    assert last_error is not None
    raise last_error


def extract_catalog_revision(pointer_bytes: bytes, namespace: str) -> int:
    """Decode the active revision number from a signed catalog envelope or payload."""
    document = json.loads(pointer_bytes)
    if not isinstance(document, dict):
        raise ValueError(f"Catalog pointer for {namespace} is not a JSON object")
    if isinstance(document.get("payload"), str):
        encoded = document["payload"]
        padded = encoded + "=" * (-len(encoded) % 4)
        payload = json.loads(base64.urlsafe_b64decode(padded))
    else:
        payload = document
    revision = payload.get("revision") if isinstance(payload, dict) else None
    if type(revision) is not int or revision < 1:
        raise ValueError(f"Catalog pointer for {namespace} lacks a valid integer revision")
    return revision


def _has_no_cache(headers: dict[str, str]) -> bool:
    return "no-cache" in headers.get("cache-control", "").lower()


def _has_immutable(headers: dict[str, str]) -> bool:
    cc = headers.get("cache-control", "").lower()
    return "max-age=31536000" in cc and "immutable" in cc


def check_parity(
    *,
    r2_origin: str = R2_ORIGIN,
    firebase_origin: str = FIREBASE_ORIGIN,
    required_namespaces: tuple[str, ...] = REQUIRED_CATALOG_NAMESPACES,
    fetch=fetch_http_with_headers,
    attempts: int | None = None,
    sleep=time.sleep,
) -> dict:
    """Verify live catalog pointers, immutable releases, scopes, and prices match."""
    r2_origin = normalize_origin(r2_origin)
    firebase_origin = normalize_origin(firebase_origin)
    failures: list[str] = []
    catalog_results: dict[str, dict] = {}
    observed_revisions: dict[str, int] = {}

    for _, namespace in NAMESPACES.items():
        required = namespace in required_namespaces
        pointer_path = f"{namespace}/current.json"
        try:
            r2_bytes, _ = fetch_with_retry(
                r2_origin, pointer_path, MAX_POINTER_BYTES, fetch=fetch, absent_ok=not required,
                attempts=attempts, sleep=sleep,
            )
            fb_bytes, fb_headers = fetch_with_retry(
                firebase_origin, pointer_path, MAX_POINTER_BYTES, fetch=fetch, absent_ok=not required,
                attempts=attempts, sleep=sleep,
            )
        except Exception as exc:
            failures.append(f"Failed to read {pointer_path}: {exc}")
            catalog_results[namespace] = {"status": "failed", "error": str(exc)}
            continue

        if r2_bytes is None and fb_bytes is None:
            catalog_results[namespace] = {"status": "absent"}
            continue
        if r2_bytes is None or fb_bytes is None:
            present = "R2" if r2_bytes is not None else "Firebase"
            missing = "Firebase" if r2_bytes is not None else "R2"
            msg = f"{pointer_path} is present on {present} but missing on {missing}"
            failures.append(msg)
            catalog_results[namespace] = {"status": "failed", "error": msg}
            continue

        r2_sha = sha256_bytes(r2_bytes)
        fb_sha = sha256_bytes(fb_bytes)
        if r2_sha != fb_sha:
            msg = f"{pointer_path} digest mismatch: R2={r2_sha[:12]} Firebase={fb_sha[:12]}"
            failures.append(msg)
            catalog_results[namespace] = {
                "status": "failed",
                "r2SHA256": r2_sha,
                "firebaseSHA256": fb_sha,
                "error": msg,
            }
            continue

        if not _has_no_cache(fb_headers):
            msg = f"Firebase {pointer_path} lacks no-cache header: {fb_headers.get('cache-control', '')!r}"
            failures.append(msg)
            catalog_results[namespace] = {"status": "failed", "pointerSHA256": r2_sha, "error": msg}
            continue

        try:
            revision = extract_catalog_revision(r2_bytes, namespace)
        except Exception as exc:
            failures.append(str(exc))
            catalog_results[namespace] = {"status": "failed", "pointerSHA256": r2_sha, "error": str(exc)}
            continue

        observed_revisions[namespace] = revision
        companion_files = ["catalog-release.json"]
        if namespace == "v1":
            companion_files.append("pokemon-catalog-snapshot.json")
        elif namespace == "yugioh/v1":
            companion_files.append("catalog.json")

        release_hashes: dict[str, str] = {}
        release_ok = True
        for filename in companion_files:
            release_path = f"{namespace}/releases/{revision}/{filename}"
            try:
                r2_rel, _ = fetch_with_retry(
                    r2_origin, release_path, MAX_POINTER_BYTES, fetch=fetch, absent_ok=False,
                    attempts=attempts, sleep=sleep,
                )
                fb_rel, fb_rel_headers = fetch_with_retry(
                    firebase_origin, release_path, MAX_POINTER_BYTES, fetch=fetch, absent_ok=False,
                    attempts=attempts, sleep=sleep,
                )
            except Exception as exc:
                msg = f"Failed to read immutable release {release_path}: {exc}"
                failures.append(msg)
                catalog_results[namespace] = {"status": "failed", "revision": revision, "error": msg}
                release_ok = False
                break

            assert r2_rel is not None and fb_rel is not None
            r2_rel_sha = sha256_bytes(r2_rel)
            fb_rel_sha = sha256_bytes(fb_rel)
            if r2_rel_sha != fb_rel_sha:
                msg = f"{release_path} digest mismatch: R2={r2_rel_sha[:12]} Firebase={fb_rel_sha[:12]}"
                failures.append(msg)
                catalog_results[namespace] = {"status": "failed", "revision": revision, "error": msg}
                release_ok = False
                break
            if not _has_immutable(fb_rel_headers):
                msg = f"Firebase {release_path} lacks immutable cache header: {fb_rel_headers.get('cache-control', '')!r}"
                failures.append(msg)
                catalog_results[namespace] = {"status": "failed", "revision": revision, "error": msg}
                release_ok = False
                break
            release_hashes[filename] = r2_rel_sha

        if not release_ok:
            continue

        catalog_results[namespace] = {
            "status": "passed",
            "revision": revision,
            "pointerSHA256": r2_sha,
            "releaseSHA256": release_hashes["catalog-release.json"],
            "immutableSHA256": release_hashes,
        }

    scope_results: dict[str, dict] = {}
    for game, (_, namespace) in CATALOG_NAMESPACES.items():
        scope_path = f"{namespace}/{SCOPE_FILE}"
        try:
            r2_scope, _ = fetch_with_retry(
                r2_origin, scope_path, MAX_SCOPE_BYTES, fetch=fetch, attempts=attempts, sleep=sleep
            )
            fb_scope, fb_scope_headers = fetch_with_retry(
                firebase_origin, scope_path, MAX_SCOPE_BYTES, fetch=fetch, attempts=attempts, sleep=sleep
            )
        except Exception as exc:
            msg = f"Failed to read {scope_path}: {exc}"
            failures.append(msg)
            scope_results[game] = {"status": "failed", "path": scope_path, "error": str(exc)}
            continue
        assert r2_scope is not None and fb_scope is not None
        r2_sha = sha256_bytes(r2_scope)
        fb_sha = sha256_bytes(fb_scope)
        if r2_sha != fb_sha:
            msg = f"{scope_path} digest mismatch: R2={r2_sha[:12]} Firebase={fb_sha[:12]}"
            failures.append(msg)
            scope_results[game] = {"status": "failed", "path": scope_path, "error": msg}
        elif not _has_no_cache(fb_scope_headers):
            msg = f"Firebase {scope_path} lacks no-cache header: {fb_scope_headers.get('cache-control', '')!r}"
            failures.append(msg)
            scope_results[game] = {"status": "failed", "path": scope_path, "error": msg}
        else:
            scope_results[game] = {"status": "passed", "path": scope_path, "sha256": r2_sha}

    pricing_result: dict = {"status": "passed"}
    observed_price_build: str | None = None
    observed_source_build: str | None = None
    retained_builds_count: int | None = None

    try:
        r2_latest, _ = fetch_with_retry(
            r2_origin, price_v2.LATEST, price_v2.MAX_POINTER_BYTES, fetch=fetch, attempts=attempts, sleep=sleep
        )
        fb_latest, fb_latest_headers = fetch_with_retry(
            firebase_origin, price_v2.LATEST, price_v2.MAX_POINTER_BYTES, fetch=fetch, attempts=attempts, sleep=sleep
        )
        assert r2_latest is not None and fb_latest is not None
        r2_pointer = price_v2.validate_pointer(r2_latest)
        observed_price_build = r2_pointer["build"]
        observed_source_build = r2_pointer["sourceBuild"]
        if r2_latest != fb_latest:
            failures.append(
                f"{price_v2.LATEST} digest mismatch: R2={sha256_bytes(r2_latest)[:12]} "
                f"Firebase={sha256_bytes(fb_latest)[:12]}"
            )
            pricing_result["status"] = "failed"
        elif not _has_no_cache(fb_latest_headers):
            failures.append(
                f"Firebase {price_v2.LATEST} lacks no-cache header: {fb_latest_headers.get('cache-control', '')!r}"
            )
            pricing_result["status"] = "failed"

        fb_history_raw, fb_history_headers = fetch_with_retry(
            firebase_origin, price_rollback.HISTORY, price_v2.MAX_POINTER_BYTES, fetch=fetch,
            attempts=attempts, sleep=sleep,
        )
        assert fb_history_raw is not None
        retained = price_rollback.history(fb_history_raw)
        retained_builds_count = len(retained)
        if observed_price_build not in retained:
            failures.append(
                f"Firebase {price_rollback.HISTORY} does not include active v2 build {observed_price_build}"
            )
            pricing_result["status"] = "failed"
        if not _has_no_cache(fb_history_headers):
            failures.append(
                f"Firebase {price_rollback.HISTORY} lacks no-cache header: "
                f"{fb_history_headers.get('cache-control', '')!r}"
            )
            pricing_result["status"] = "failed"

        active_index_path = f"{price_rollback.BUILDS}{observed_price_build}/index.json"
        r2_build_index, _ = fetch_with_retry(
            r2_origin, active_index_path, price_v2.MAX_POINTER_BYTES, fetch=fetch, attempts=attempts, sleep=sleep
        )
        fb_build_index, fb_build_headers = fetch_with_retry(
            firebase_origin, active_index_path, price_v2.MAX_POINTER_BYTES, fetch=fetch, attempts=attempts, sleep=sleep
        )
        assert r2_build_index is not None and fb_build_index is not None
        if r2_build_index != fb_build_index:
            failures.append(f"{active_index_path} digest mismatch between R2 and Firebase")
            pricing_result["status"] = "failed"
        elif not _has_immutable(fb_build_headers):
            failures.append(
                f"Firebase {active_index_path} lacks immutable cache header: "
                f"{fb_build_headers.get('cache-control', '')!r}"
            )
            pricing_result["status"] = "failed"

        for rel_path, require_no_cache in (
            (f"{PRICE_V1_NAMESPACE}/index.json", False),
            (f"{PRICE_V1_NAMESPACE}/last-updated.txt", True),
        ):
            r2_v1, _ = fetch_with_retry(
                r2_origin, rel_path, price_v2.MAX_POINTER_BYTES, fetch=fetch, attempts=attempts, sleep=sleep
            )
            fb_v1, fb_v1_headers = fetch_with_retry(
                firebase_origin, rel_path, price_v2.MAX_POINTER_BYTES, fetch=fetch, attempts=attempts, sleep=sleep
            )
            assert r2_v1 is not None and fb_v1 is not None
            if r2_v1 != fb_v1:
                failures.append(f"{rel_path} digest mismatch between R2 and Firebase")
                pricing_result["status"] = "failed"
            elif require_no_cache and not _has_no_cache(fb_v1_headers):
                failures.append(
                    f"Firebase {rel_path} lacks no-cache header: {fb_v1_headers.get('cache-control', '')!r}"
                )
                pricing_result["status"] = "failed"

        pricing_result.update({
            "activeBuild": observed_price_build,
            "sourceBuild": observed_source_build,
            "firebaseRetainedBuilds": retained_builds_count,
            "pointerSHA256": sha256_bytes(r2_latest),
        })
    except Exception as exc:
        failures.append(f"Pricing parity verification failed: {exc}")
        pricing_result["status"] = "failed"
        pricing_result["error"] = str(exc)

    return {
        "status": "passed" if not failures else "failed",
        "catalogs": catalog_results,
        "scopes": scope_results,
        "pricing": pricing_result,
        "observed": {
            "catalogRevisions": observed_revisions,
            "priceBuild": observed_price_build,
            "priceSourceBuild": observed_source_build,
            "firebaseRetainedBuilds": retained_builds_count,
        },
        "failures": failures,
    }


def hostname_matches_san(hostname: str, san: str) -> bool:
    host = hostname.strip().lower().rstrip(".")
    pattern = san.strip().lower().rstrip(".")
    if not host or not pattern:
        return False
    if pattern == host:
        return True
    if pattern.startswith("*.") and pattern.count("*") == 1:
        suffix = pattern[1:]  # ".example.com"
        if host.endswith(suffix):
            prefix = host[: -len(suffix)]
            return bool(prefix) and "." not in prefix
    return False


def _flatten_x509_name(tuples: tuple) -> str:
    parts = []
    for rdn in tuples:
        for key, value in rdn:
            parts.append(f"{key}={value}")
    return ", ".join(parts)


def fetch_peer_certificate(connect_host: str, server_hostname: str, *, port: int = 443, timeout: float = 15.0) -> dict:
    """Connect directly to `connect_host:port` with SNI `server_hostname` and verify TLS."""
    context = ssl.create_default_context()
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    with socket.create_connection((connect_host, port), timeout=timeout) as raw_sock:
        with context.wrap_socket(raw_sock, server_hostname=server_hostname) as tls_sock:
            cert = tls_sock.getpeercert()
            if not cert:
                raise ValueError(f"Empty TLS peer certificate for {server_hostname} via {connect_host}")
            return {
                "subject": _flatten_x509_name(cert.get("subject", ())),
                "issuer": _flatten_x509_name(cert.get("issuer", ())),
                "notBefore": cert.get("notBefore", ""),
                "notAfter": cert.get("notAfter", ""),
                "san": [value for kind, value in cert.get("subjectAltName", ()) if kind == "DNS"],
                "tlsVersion": tls_sock.version() or "",
            }


def evaluate_certificate_info(
    info: dict,
    *,
    server_hostname: str,
    connect_host: str,
    min_days: int = DEFAULT_MIN_CERT_DAYS,
    now: datetime | None = None,
) -> dict:
    current = now or utc_now()
    failures: list[str] = []
    san = list(info.get("san", []))
    not_before_raw = info.get("notBefore", "")
    not_after_raw = info.get("notAfter", "")
    try:
        not_before = datetime.fromtimestamp(ssl.cert_time_to_seconds(not_before_raw), tz=timezone.utc)
        not_after = datetime.fromtimestamp(ssl.cert_time_to_seconds(not_after_raw), tz=timezone.utc)
    except Exception as exc:
        return {
            "status": "failed",
            "serverHostname": server_hostname,
            "connectHost": connect_host,
            "failures": [f"Unable to parse certificate validity dates for {server_hostname}: {exc}"],
        }

    days_remaining = (not_after - current).total_seconds() / 86400.0
    if not any(hostname_matches_san(server_hostname, candidate) for candidate in san):
        failures.append(f"Certificate SANs {san!r} do not cover {server_hostname}")
    if current < not_before:
        failures.append(f"Certificate for {server_hostname} is not valid until {iso_utc(not_before)}")
    if current >= not_after:
        failures.append(f"Certificate for {server_hostname} expired at {iso_utc(not_after)}")
    elif days_remaining < min_days:
        failures.append(
            f"Certificate for {server_hostname} expires in {days_remaining:.1f} days "
            f"(minimum required headroom: {min_days} days)"
        )

    return {
        "status": "passed" if not failures else "failed",
        "serverHostname": server_hostname,
        "connectHost": connect_host,
        "subject": info.get("subject", ""),
        "issuer": info.get("issuer", ""),
        "san": san,
        "tlsVersion": info.get("tlsVersion", ""),
        "notBefore": iso_utc(not_before),
        "notAfter": iso_utc(not_after),
        "daysRemaining": round(days_remaining, 2),
        "minDaysRequired": min_days,
        "failures": failures,
    }


def check_certificates(
    *,
    firebase_origin: str = FIREBASE_ORIGIN,
    rollback_hostname: str = DEFAULT_ROLLBACK_HOSTNAME,
    custom_domain_connect_host: str | None = None,
    min_days: int = DEFAULT_MIN_CERT_DAYS,
    cert_fetcher=fetch_peer_certificate,
    now: datetime | None = None,
) -> dict:
    """Validate Firebase origin TLS and custom rollback hostname TLS directly on Firebase."""
    firebase_host = urlparse(normalize_origin(firebase_origin)).hostname
    assert firebase_host is not None
    connect_target = (custom_domain_connect_host or firebase_host).strip()
    targets = [(firebase_host, firebase_host)]
    if rollback_hostname and rollback_hostname.strip().lower() != firebase_host.lower():
        targets.append((connect_target, rollback_hostname.strip()))

    endpoints: list[dict] = []
    failures: list[str] = []
    for connect_host, server_hostname in targets:
        try:
            info = cert_fetcher(connect_host, server_hostname)
            evaluated = evaluate_certificate_info(
                info,
                server_hostname=server_hostname,
                connect_host=connect_host,
                min_days=min_days,
                now=now,
            )
        except Exception as exc:
            evaluated = {
                "status": "failed",
                "serverHostname": server_hostname,
                "connectHost": connect_host,
                "failures": [f"TLS probe failed for {server_hostname} via {connect_host}: {exc}"],
            }
        endpoints.append(evaluated)
        failures.extend(evaluated["failures"])

    return {
        "status": "passed" if not failures else "failed",
        "minDaysRequired": min_days,
        "endpoints": endpoints,
        "failures": failures,
    }


def measure_staged_site(site_root: Path) -> dict:
    """Measure local staged site bytes grouped by catalog, legacy v1, and immutable v2 builds."""
    root = Path(site_root)
    if not root.is_dir():
        raise ValueError(f"Staged site directory does not exist: {root}")
    total_bytes = 0
    file_count = 0
    catalog_bytes = 0
    price_v1_bytes = 0
    price_v2_bytes = 0
    v2_builds: set[str] = set()

    for entry in root.rglob("*"):
        if entry.is_symlink():
            raise ValueError(f"Unexpected symlink inside staged site: {entry}")
        if not entry.is_file():
            continue
        size = entry.stat().st_size
        rel = entry.relative_to(root).as_posix()
        total_bytes += size
        file_count += 1
        if rel.startswith("market-prices/v2/"):
            price_v2_bytes += size
            parts = rel.split("/")
            if len(parts) >= 4 and parts[2] == "builds":
                v2_builds.add(parts[3])
        elif rel.startswith("market-prices/v1/"):
            price_v1_bytes += size
        else:
            catalog_bytes += size

    return {
        "totalBytes": total_bytes,
        "fileCount": file_count,
        "catalogBytes": catalog_bytes,
        "priceV1Bytes": price_v1_bytes,
        "priceV2Bytes": price_v2_bytes,
        "v2BuildCount": len(v2_builds),
    }


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def mint_google_access_token(
    service_account_path: Path,
    *,
    scopes: str = OAUTH_SCOPES,
    now: datetime | None = None,
    opener=None,
) -> str:
    """Exchange a Google service account JSON key for a short-lived OAuth2 bearer token.

    Uses standard `openssl dgst -sha256 -sign` so no third-party Python packages are required.
    Never logs or includes private key material or tokens in exceptions.
    """
    account = json.loads(Path(service_account_path).read_bytes())
    client_email = account.get("client_email")
    private_key = account.get("private_key")
    token_uri = account.get("token_uri") or ALLOWED_TOKEN_URIS[0]
    if not isinstance(client_email, str) or not client_email.strip():
        raise ReadinessError("Service account JSON is missing client_email")
    if not isinstance(private_key, str) or "BEGIN" not in private_key:
        raise ReadinessError("Service account JSON is missing a valid private_key")
    if token_uri not in ALLOWED_TOKEN_URIS:
        raise ReadinessError(f"Refusing untrusted OAuth token URI: {token_uri!r}")

    issued = int((now or utc_now()).timestamp())
    header = _b64url(json.dumps({"alg": "RS256", "typ": "JWT"}, separators=(",", ":")).encode("utf-8"))
    claims = _b64url(
        json.dumps(
            {
                "iss": client_email,
                "scope": scopes,
                "aud": token_uri,
                "iat": issued,
                "exp": issued + 300,
            },
            separators=(",", ":"),
        ).encode("utf-8")
    )
    signing_input = f"{header}.{claims}".encode("ascii")

    fd, key_file = tempfile.mkstemp(prefix="gcp-sa-", suffix=".pem")
    try:
        os.chmod(key_file, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(private_key)
        signed = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", key_file],
            input=signing_input,
            capture_output=True,
            check=False,
        )
        if signed.returncode != 0 or not signed.stdout:
            raise ReadinessError("openssl failed to sign Google OAuth2 JWT assertion")
    finally:
        try:
            os.unlink(key_file)
        except OSError:
            pass

    assertion = f"{header}.{claims}.{_b64url(signed.stdout)}"
    body = urlencode(
        {
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": assertion,
        }
    ).encode("ascii")
    req = Request(
        token_uri,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": "ScanStashRollbackReadiness/1.0",
        },
    )
    http_open = opener or build_opener(NoRedirects()).open
    try:
        with http_open(req, timeout=30) as resp:
            payload = json.loads(resp.read(MAX_API_RESPONSE_BYTES))
    except HTTPError as error:
        raise ReadinessError(f"Google OAuth2 token exchange failed with HTTP {error.code}") from None
    except Exception as exc:
        raise ReadinessError(f"Google OAuth2 token exchange failed: {type(exc).__name__}") from None

    token = payload.get("access_token")
    if not isinstance(token, str) or not token:
        raise ReadinessError("Google OAuth2 token response did not contain an access_token")
    return token


def google_api_get_json(url: str, access_token: str, *, opener=None) -> dict:
    req = Request(
        url,
        headers={
            "Authorization": f"Bearer {access_token}",
            "Accept": "application/json",
            "User-Agent": "ScanStashRollbackReadiness/1.0",
        },
    )
    http_open = opener or build_opener(NoRedirects()).open
    with http_open(req, timeout=30) as resp:
        data = resp.read(MAX_API_RESPONSE_BYTES + 1)
        if len(data) > MAX_API_RESPONSE_BYTES:
            raise ReadinessError(f"Google API response exceeded {MAX_API_RESPONSE_BYTES} bytes")
        return json.loads(data)


def _point_number(point: dict) -> float:
    value = point.get("value", {})
    if "int64Value" in value:
        return float(int(value["int64Value"]))
    if "doubleValue" in value:
        return float(value["doubleValue"])
    return 0.0


def fetch_firebase_quota_metrics(
    *,
    project_id: str,
    site_id: str,
    access_token: str,
    now: datetime | None = None,
    api_get=google_api_get_json,
) -> dict:
    """Query Firebase Hosting latest release plus Cloud Monitoring storage & bandwidth metrics."""
    current = now or utc_now()
    hosting_info: dict = {}
    releases_url = f"{FIREBASE_HOSTING_API}/sites/{site_id}/releases?pageSize=1"
    releases_doc = api_get(releases_url, access_token)
    releases = releases_doc.get("releases") or []
    if releases:
        latest = releases[0]
        version = latest.get("version") or {}
        hosting_info = {
            "latestReleaseName": latest.get("name", ""),
            "latestReleaseTime": latest.get("releaseTime", ""),
            "latestVersionName": version.get("name", ""),
            "latestVersionStatus": version.get("status", ""),
            "latestVersionFileCount": int(version.get("fileCount") or 0),
        }

    def query_monitoring(
        metric_type: str,
        start: datetime,
        end: datetime,
        *,
        aligner: str,
        reducer: str | None = None,
        alignment_period: str = "3600s",
    ) -> list[dict]:
        def fetch_pages(filter_expr: str) -> list[dict]:
            collected: list[dict] = []
            page_token: str | None = None
            for _ in range(20):
                query: dict[str, str] = {
                    "filter": filter_expr,
                    "interval.startTime": iso_utc(start),
                    "interval.endTime": iso_utc(end),
                    "aggregation.alignmentPeriod": alignment_period,
                    "aggregation.perSeriesAligner": aligner,
                }
                if reducer:
                    query["aggregation.crossSeriesReducer"] = reducer
                if page_token:
                    query["pageToken"] = page_token
                url = f"{CLOUD_MONITORING_API}/projects/{project_id}/timeSeries?{urlencode(query)}"
                doc = api_get(url, access_token)
                collected.extend(doc.get("timeSeries") or [])
                page_token = doc.get("nextPageToken")
                if not page_token:
                    break
            return collected

        series = fetch_pages(f'metric.type="{metric_type}" AND resource.labels.site_name="{site_id}"')
        if not series:
            # Fall back to project-level filter if site_name label is not emitted on this metric.
            series = fetch_pages(f'metric.type="{metric_type}"')
        return series

    storage_series = query_monitoring(
        STORAGE_METRIC,
        current - timedelta(hours=48),
        current,
        aligner="ALIGN_MAX",
        alignment_period="3600s",
    )
    latest_storage_bytes: int | None = None
    latest_storage_ts = ""
    for series in storage_series:
        for point in series.get("points") or []:
            end_time = (point.get("interval") or {}).get("endTime", "")
            val = int(round(_point_number(point)))
            if latest_storage_bytes is None or end_time >= latest_storage_ts:
                latest_storage_bytes = val
                latest_storage_ts = end_time

    bw_30d_series = query_monitoring(
        BANDWIDTH_METRIC,
        current - timedelta(days=30),
        current,
        aligner="ALIGN_SUM",
        reducer="REDUCE_SUM",
        alignment_period="3600s",
    )
    cutoff_24h = current - timedelta(hours=24)
    sent_24h = 0.0
    sent_30d = 0.0
    point_count = 0
    for series in bw_30d_series:
        for point in series.get("points") or []:
            amount = _point_number(point)
            sent_30d += amount
            point_count += 1
            end_raw = (point.get("interval") or {}).get("endTime", "")
            if end_raw:
                try:
                    parsed = datetime.fromisoformat(end_raw.replace("Z", "+00:00"))
                    if parsed >= cutoff_24h:
                        sent_24h += amount
                except ValueError:
                    pass

    return {
        "hosting": hosting_info,
        "storageTotalBytes": latest_storage_bytes,
        "storageObservedAt": latest_storage_ts,
        "bandwidthSent24hBytes": int(round(sent_24h)),
        "bandwidthSent30dBytes": int(round(sent_30d)),
        "bandwidthPointCount": point_count,
    }


def evaluate_quota_headroom(
    *,
    site_root: Path | None = None,
    metrics: dict | None = None,
    metrics_error: str | None = None,
    quota_mode: str = "strict",
    staged_site_limit_bytes: int = DEFAULT_STAGED_SITE_LIMIT_BYTES,
    storage_limit_bytes: int = DEFAULT_STORAGE_LIMIT_BYTES,
    daily_bandwidth_limit_bytes: int = DEFAULT_DAILY_BANDWIDTH_LIMIT_BYTES,
    monthly_bandwidth_limit_bytes: int = DEFAULT_MONTHLY_BANDWIDTH_LIMIT_BYTES,
    min_headroom_ratio: float = DEFAULT_MIN_HEADROOM_RATIO,
) -> tuple[dict, dict]:
    """Evaluate storage and bandwidth headroom checks from staged site and Cloud Monitoring."""
    if quota_mode not in ("strict", "advisory"):
        raise ValueError(f"Unsupported quota_mode: {quota_mode!r}")

    storage_failures: list[str] = []
    storage_warnings: list[str] = []
    storage_report: dict = {
        "quotaMode": quota_mode,
        "stagedSiteLimitBytes": staged_site_limit_bytes,
        "storageLimitBytes": storage_limit_bytes,
        "minHeadroomRatio": min_headroom_ratio,
    }

    if site_root is not None:
        staged = measure_staged_site(site_root)
        storage_report["stagedSite"] = staged
        if staged["totalBytes"] > staged_site_limit_bytes:
            storage_failures.append(
                f"Staged Firebase site ({format_bytes(staged['totalBytes'])}) exceeds "
                f"limit ({format_bytes(staged_site_limit_bytes)})"
            )

    bandwidth_failures: list[str] = []
    bandwidth_warnings: list[str] = []
    bandwidth_report: dict = {
        "quotaMode": quota_mode,
        "dailyLimitBytes": daily_bandwidth_limit_bytes,
        "monthlyLimitBytes": monthly_bandwidth_limit_bytes,
        "minHeadroomRatio": min_headroom_ratio,
    }

    if metrics_error is not None:
        detail = f"Firebase quota monitoring API check failed: {metrics_error}"
        if quota_mode == "strict":
            storage_failures.append(detail)
            bandwidth_failures.append(detail)
        else:
            storage_warnings.append(detail)
            bandwidth_warnings.append(detail)
        storage_report["apiError"] = metrics_error
        bandwidth_report["apiError"] = metrics_error
    elif metrics is None:
        detail = "Firebase quota monitoring credentials were not provided"
        if quota_mode == "strict":
            storage_failures.append(detail)
            bandwidth_failures.append(detail)
        else:
            storage_warnings.append(detail)
            bandwidth_warnings.append(detail)
    else:
        storage_report["hosting"] = metrics.get("hosting", {})
        live_storage = metrics.get("storageTotalBytes")
        if live_storage is None:
            # No storage time-series point emitted; fall back to staged site only in advisory mode.
            if quota_mode == "strict":
                storage_failures.append(
                    f"Cloud Monitoring returned no data points for {STORAGE_METRIC}"
                )
            else:
                storage_warnings.append(
                    f"Cloud Monitoring returned no data points for {STORAGE_METRIC}"
                )
        else:
            used_ratio = live_storage / storage_limit_bytes if storage_limit_bytes > 0 else 1.0
            headroom_ratio = max(0.0, 1.0 - used_ratio)
            storage_report["liveStorageBytes"] = live_storage
            storage_report["storageObservedAt"] = metrics.get("storageObservedAt", "")
            storage_report["usedRatio"] = round(used_ratio, 4)
            storage_report["headroomRatio"] = round(headroom_ratio, 4)
            if live_storage > storage_limit_bytes or headroom_ratio < min_headroom_ratio:
                storage_failures.append(
                    f"Firebase Hosting storage ({format_bytes(live_storage)} of "
                    f"{format_bytes(storage_limit_bytes)}, {headroom_ratio:.1%} headroom) "
                    f"is below the {min_headroom_ratio:.0%} minimum headroom requirement"
                )

        sent_24h = int(metrics.get("bandwidthSent24hBytes", 0))
        sent_30d = int(metrics.get("bandwidthSent30dBytes", 0))
        daily_used = sent_24h / daily_bandwidth_limit_bytes if daily_bandwidth_limit_bytes > 0 else 1.0
        monthly_used = sent_30d / monthly_bandwidth_limit_bytes if monthly_bandwidth_limit_bytes > 0 else 1.0
        daily_headroom = max(0.0, 1.0 - daily_used)
        monthly_headroom = max(0.0, 1.0 - monthly_used)
        bandwidth_report.update(
            {
                "sent24hBytes": sent_24h,
                "sent30dBytes": sent_30d,
                "dailyUsedRatio": round(daily_used, 4),
                "dailyHeadroomRatio": round(daily_headroom, 4),
                "monthlyUsedRatio": round(monthly_used, 4),
                "monthlyHeadroomRatio": round(monthly_headroom, 4),
                "pointCount": int(metrics.get("bandwidthPointCount", 0)),
            }
        )
        if sent_24h > daily_bandwidth_limit_bytes or daily_headroom < min_headroom_ratio:
            bandwidth_failures.append(
                f"Firebase 24h transfer ({format_bytes(sent_24h)} of "
                f"{format_bytes(daily_bandwidth_limit_bytes)}, {daily_headroom:.1%} headroom) "
                f"is below the {min_headroom_ratio:.0%} minimum headroom requirement"
            )
        if sent_30d > monthly_bandwidth_limit_bytes or monthly_headroom < min_headroom_ratio:
            bandwidth_failures.append(
                f"Firebase 30d transfer ({format_bytes(sent_30d)} of "
                f"{format_bytes(monthly_bandwidth_limit_bytes)}, {monthly_headroom:.1%} headroom) "
                f"is below the {min_headroom_ratio:.0%} minimum headroom requirement"
            )

    storage_report["warnings"] = storage_warnings
    storage_report["failures"] = storage_failures
    storage_report["status"] = (
        "failed" if storage_failures else ("advisory_unavailable" if storage_warnings else "passed")
    )

    bandwidth_report["warnings"] = bandwidth_warnings
    bandwidth_report["failures"] = bandwidth_failures
    bandwidth_report["status"] = (
        "failed" if bandwidth_failures else ("advisory_unavailable" if bandwidth_warnings else "passed")
    )
    return storage_report, bandwidth_report


def run_readiness_check(
    *,
    r2_origin: str = R2_ORIGIN,
    firebase_origin: str = FIREBASE_ORIGIN,
    rollback_hostname: str = DEFAULT_ROLLBACK_HOSTNAME,
    custom_domain_connect_host: str | None = None,
    required_namespaces: tuple[str, ...] = REQUIRED_CATALOG_NAMESPACES,
    min_cert_days: int = DEFAULT_MIN_CERT_DAYS,
    site_root: Path | None = None,
    firebase_project: str | None = None,
    firebase_site: str | None = None,
    service_account: Path | None = None,
    quota_mode: str = "strict",
    staged_site_limit_bytes: int = DEFAULT_STAGED_SITE_LIMIT_BYTES,
    storage_limit_bytes: int = DEFAULT_STORAGE_LIMIT_BYTES,
    daily_bandwidth_limit_bytes: int = DEFAULT_DAILY_BANDWIDTH_LIMIT_BYTES,
    monthly_bandwidth_limit_bytes: int = DEFAULT_MONTHLY_BANDWIDTH_LIMIT_BYTES,
    min_headroom_ratio: float = DEFAULT_MIN_HEADROOM_RATIO,
    fetch=fetch_http_with_headers,
    cert_fetcher=fetch_peer_certificate,
    token_minter=mint_google_access_token,
    metrics_fetcher=fetch_firebase_quota_metrics,
    now: datetime | None = None,
) -> dict:
    checked_at = now or utc_now()
    parity = check_parity(
        r2_origin=r2_origin,
        firebase_origin=firebase_origin,
        required_namespaces=required_namespaces,
        fetch=fetch,
    )
    certificate = check_certificates(
        firebase_origin=firebase_origin,
        rollback_hostname=rollback_hostname,
        custom_domain_connect_host=custom_domain_connect_host,
        min_days=min_cert_days,
        cert_fetcher=cert_fetcher,
        now=checked_at,
    )

    metrics: dict | None = None
    metrics_error: str | None = None
    if service_account is not None and firebase_project and firebase_site:
        try:
            token = token_minter(service_account, now=checked_at)
            metrics = metrics_fetcher(
                project_id=firebase_project,
                site_id=firebase_site,
                access_token=token,
                now=checked_at,
            )
        except HTTPError as error:
            if error.code == 403:
                metrics_error = (
                    f"HTTP 403 Forbidden from Google API — ensure the Firebase service account has "
                    f"{REQUIRED_MONITORING_ROLE} and Firebase Hosting read access"
                )
            else:
                metrics_error = f"HTTP {error.code} from Google quota API"
        except Exception as exc:
            metrics_error = str(exc)

    storage, bandwidth = evaluate_quota_headroom(
        site_root=site_root,
        metrics=metrics,
        metrics_error=metrics_error,
        quota_mode=quota_mode,
        staged_site_limit_bytes=staged_site_limit_bytes,
        storage_limit_bytes=storage_limit_bytes,
        daily_bandwidth_limit_bytes=daily_bandwidth_limit_bytes,
        monthly_bandwidth_limit_bytes=monthly_bandwidth_limit_bytes,
        min_headroom_ratio=min_headroom_ratio,
    )

    checks = {
        "parity": parity,
        "certificate": certificate,
        "storageHeadroom": storage,
        "bandwidthHeadroom": bandwidth,
    }
    failures = [
        *parity["failures"],
        *certificate["failures"],
        *storage["failures"],
        *bandwidth["failures"],
    ]
    warnings = [
        *storage.get("warnings", []),
        *bandwidth.get("warnings", []),
    ]
    # Rollback target is ONLY marked READY when every check strictly passed
    # (never false-green when quota monitoring is unverified).
    all_passed = all(check["status"] == "passed" for check in checks.values())
    hard_failed = any(check["status"] == "failed" for check in checks.values())
    rollback_ready = all_passed and not failures

    return {
        "schemaVersion": 1,
        "checkedAt": iso_utc(checked_at),
        "r2Origin": normalize_origin(r2_origin),
        "firebaseOrigin": normalize_origin(firebase_origin),
        "rollbackHostname": rollback_hostname,
        "rollbackReady": rollback_ready,
        "status": "ready" if rollback_ready else ("not_ready" if hard_failed else "unverified"),
        "hardFailed": hard_failed,
        "checks": checks,
        "observed": parity["observed"],
        "failures": failures,
        "warnings": warnings,
    }


def format_markdown_summary(report: dict) -> str:
    status_label = "READY" if report["rollbackReady"] else (
        "NOT READY" if report["hardFailed"] else "NOT READY (QUOTA UNVERIFIED)"
    )
    lines = [
        f"### Firebase Rollback Readiness: {status_label}",
        "",
        f"- Checked at: `{report['checkedAt']}`",
        f"- Primary origin: `{report['r2Origin']}`",
        f"- Rollback origin: `{report['firebaseOrigin']}` (custom hostname `{report['rollbackHostname']}`)",
        "",
        "| Check | Status | Details |",
        "| --- | --- | --- |",
    ]
    checks = report["checks"]
    revs = report["observed"].get("catalogRevisions") or {}
    rev_text = ", ".join(f"`{ns}` rev {rev}" for ns, rev in sorted(revs.items())) or "none"
    build = report["observed"].get("priceBuild")
    build_text = f"`{build[:12]}` ({report['observed'].get('priceSourceBuild')})" if build else "unknown"
    lines.append(
        f"| Catalog & price parity | `{checks['parity']['status']}` | {rev_text}; price build {build_text} |"
    )

    cert_parts = []
    for ep in checks["certificate"].get("endpoints", []):
        if "daysRemaining" in ep:
            cert_parts.append(f"`{ep['serverHostname']}`: {ep['daysRemaining']:.1f}d left (until `{ep['notAfter']}`)")
        else:
            cert_parts.append(f"`{ep['serverHostname']}`: probe failed")
    lines.append(
        f"| HTTPS certificate | `{checks['certificate']['status']}` | {'; '.join(cert_parts) or 'none'} |"
    )

    storage = checks["storageHeadroom"]
    storage_parts = []
    if "stagedSite" in storage:
        st = storage["stagedSite"]
        storage_parts.append(f"staged {format_bytes(st['totalBytes'])} ({st['fileCount']} files, {st['v2BuildCount']} v2 builds)")
    if "liveStorageBytes" in storage:
        storage_parts.append(
            f"live {format_bytes(storage['liveStorageBytes'])} / {format_bytes(storage['storageLimitBytes'])} "
            f"({storage['headroomRatio']:.1%} headroom)"
        )
    elif storage.get("apiError"):
        storage_parts.append(storage["apiError"])
    lines.append(
        f"| Firebase storage headroom | `{storage['status']}` | {'; '.join(storage_parts) or 'not checked'} |"
    )

    bw = checks["bandwidthHeadroom"]
    if "sent24hBytes" in bw:
        bw_detail = (
            f"24h {format_bytes(bw['sent24hBytes'])} / {format_bytes(bw['dailyLimitBytes'])} "
            f"({bw['dailyHeadroomRatio']:.1%} headroom); "
            f"30d {format_bytes(bw['sent30dBytes'])} / {format_bytes(bw['monthlyLimitBytes'])} "
            f"({bw['monthlyHeadroomRatio']:.1%} headroom)"
        )
    elif bw.get("apiError"):
        bw_detail = bw["apiError"]
    else:
        bw_detail = "quota API not queried"
    lines.append(f"| Firebase bandwidth headroom | `{bw['status']}` | {bw_detail} |")

    if report["failures"]:
        lines.extend(["", "**Blocking failures:**"])
        for failure in report["failures"]:
            lines.append(f"- {failure}")
    if report["warnings"]:
        lines.extend(["", "**Warnings:**"])
        for warning in report["warnings"]:
            lines.append(f"- {warning}")
    if not report["rollbackReady"]:
        lines.extend(
            [
                "",
                "The verified R2 primary publication remains active. Firebase is marked **not ready** "
                "as a rollback target until a later publish passes all rollback readiness checks.",
            ]
        )
    lines.append("")
    return "\n".join(lines)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--r2-origin", default=R2_ORIGIN)
    parser.add_argument("--firebase-origin", default=FIREBASE_ORIGIN)
    parser.add_argument("--rollback-hostname", default=DEFAULT_ROLLBACK_HOSTNAME)
    parser.add_argument(
        "--custom-domain-connect-host",
        default=None,
        help="Host/IP to connect to when probing the custom rollback hostname via SNI (defaults to Firebase origin host).",
    )
    parser.add_argument("--min-cert-days", type=int, default=DEFAULT_MIN_CERT_DAYS)
    parser.add_argument("--site-root", type=Path, default=None)
    parser.add_argument("--firebase-project", default=os.environ.get("FIREBASE_PROJECT_ID"))
    parser.add_argument("--firebase-site", default=os.environ.get("FIREBASE_HOSTING_SITE_ID"))
    parser.add_argument(
        "--service-account",
        type=Path,
        default=Path(os.environ["GOOGLE_APPLICATION_CREDENTIALS"])
        if os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
        else None,
    )
    parser.add_argument("--quota-mode", choices=("strict", "advisory"), default="strict")
    parser.add_argument("--staged-site-limit-bytes", type=int, default=DEFAULT_STAGED_SITE_LIMIT_BYTES)
    parser.add_argument("--storage-limit-bytes", type=int, default=DEFAULT_STORAGE_LIMIT_BYTES)
    parser.add_argument("--daily-bandwidth-limit-bytes", type=int, default=DEFAULT_DAILY_BANDWIDTH_LIMIT_BYTES)
    parser.add_argument("--monthly-bandwidth-limit-bytes", type=int, default=DEFAULT_MONTHLY_BANDWIDTH_LIMIT_BYTES)
    parser.add_argument("--min-headroom-ratio", type=float, default=DEFAULT_MIN_HEADROOM_RATIO)
    parser.add_argument("--report", type=Path, default=None, help="Write JSON rollback readiness report to PATH.")
    parser.add_argument("--summary", type=Path, default=None, help="Append Markdown summary to PATH (e.g. $GITHUB_STEP_SUMMARY).")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    report = run_readiness_check(
        r2_origin=args.r2_origin,
        firebase_origin=args.firebase_origin,
        rollback_hostname=args.rollback_hostname,
        custom_domain_connect_host=args.custom_domain_connect_host,
        min_cert_days=args.min_cert_days,
        site_root=args.site_root,
        firebase_project=args.firebase_project,
        firebase_site=args.firebase_site,
        service_account=args.service_account,
        quota_mode=args.quota_mode,
        staged_site_limit_bytes=args.staged_site_limit_bytes,
        storage_limit_bytes=args.storage_limit_bytes,
        daily_bandwidth_limit_bytes=args.daily_bandwidth_limit_bytes,
        monthly_bandwidth_limit_bytes=args.monthly_bandwidth_limit_bytes,
        min_headroom_ratio=args.min_headroom_ratio,
    )
    if args.report is not None:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    summary = format_markdown_summary(report)
    print(summary, flush=True)
    if args.summary is not None:
        args.summary.parent.mkdir(parents=True, exist_ok=True)
        with args.summary.open("a", encoding="utf-8") as handle:
            handle.write("\n" + summary)

    if report["hardFailed"]:
        for failure in report["failures"]:
            print(f"::error title=Firebase rollback not ready::{failure}", file=sys.stderr)
        return 1
    if not report["rollbackReady"]:
        for warning in report["warnings"]:
            print(f"::warning title=Firebase rollback quota unverified::{warning}", file=sys.stderr)
        # In advisory mode, hard failures fail the job; unverified quota still prints NOT READY loudly.
        return 0 if args.quota_mode == "advisory" else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
