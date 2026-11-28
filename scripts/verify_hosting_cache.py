#!/usr/bin/env python3
"""Static and live verification of Firebase Hosting and Cloudflare Cache Rules.

Two modes:
  static  Offline CI check of firebase.json, r2_catalog_publish tiering, and
          Config/Cloudflare/catalog-cache-rules.json rule precedence & coverage.
  live    Authorized staging verification against https://catalog-staging.scan-stash.com
          covering immutable edge caching, mutable bypass & conditional revalidation,
          legacy v1 300s policy, optional negative-cache diagnostic probe, and
          optional read-only Cloudflare ruleset inspection.
"""
from __future__ import annotations

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import tempfile
import time
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import Request, build_opener

from cloudflare_cache import (
    BYPASS_CACHE_STATUSES,
    CLOUDFLARE_API_BASE,
    EDGE_HIT_CACHE_STATUSES,
    ZONE_ID_RE,
    fetch_canonical,
)
from market_price_feeds import CATALOG_NAMESPACES, NAMESPACE, R2_ORIGIN, SCOPE_FILE, NoRedirects
import market_price_v2 as v2
import r2_catalog_publish as r2

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_FIREBASE = ROOT / "firebase.json"
DEFAULT_RULES = ROOT / "Config/Cloudflare/catalog-cache-rules.json"
ALLOWED_STAGING_ORIGIN = R2_ORIGIN
PROBE_PREFIX = "v1/releases/_cache-probe/"


# ---------------------------------------------------------------------------
# Minimal deterministic evaluator for our Cloudflare Wirefilter rule grammar
# ---------------------------------------------------------------------------

_TOKEN_RE = re.compile(
    r'\s*(?:'
    r'(?P<LPAREN>\()|(?P<RPAREN>\))|(?P<LBRACE>\{)|(?P<RBRACE>\})|(?P<COMMA>,)|'
    r'(?P<STRING>"(?:\\.|[^"\\])*")|'
    r'(?P<IDENT>[A-Za-z_][A-Za-z0-9_.]*)'
    r')'
)


def _tokenize(expr):
    tokens = []
    pos = 0
    while pos < len(expr):
        if expr[pos].isspace():
            pos += 1
            continue
        match = _TOKEN_RE.match(expr, pos)
        if not match:
            raise ValueError(f"Unsupported Cloudflare expression syntax near: {expr[pos:pos + 30]!r}")
        kind = match.lastgroup
        value = match.group(kind)
        if kind == "STRING":
            value = json.loads(value)
        tokens.append((kind, value))
        pos = match.end()
    return tokens


class _ExprParser:
    def __init__(self, tokens, fields):
        self.tokens = tokens
        self.pos = 0
        self.fields = fields

    def peek(self):
        return self.tokens[self.pos] if self.pos < len(self.tokens) else (None, None)

    def consume(self, expected_kind=None, expected_val=None):
        kind, val = self.peek()
        if expected_kind and kind != expected_kind:
            raise ValueError(f"Expected {expected_kind}, got {kind} ({val!r})")
        if expected_val and val != expected_val:
            raise ValueError(f"Expected {expected_val!r}, got {val!r}")
        self.pos += 1
        return kind, val

    def parse(self):
        result = self.parse_or()
        if self.pos != len(self.tokens):
            raise ValueError(f"Unexpected trailing token: {self.tokens[self.pos]!r}")
        return result

    def parse_or(self):
        left = self.parse_and()
        while self.peek() == ("IDENT", "or"):
            self.consume()
            right = self.parse_and()
            left = left or right
        return left

    def parse_and(self):
        left = self.parse_primary()
        while self.peek() == ("IDENT", "and"):
            self.consume()
            right = self.parse_primary()
            left = left and right
        return left

    def parse_primary(self):
        kind, val = self.peek()
        if kind == "LPAREN":
            self.consume("LPAREN")
            inner = self.parse_or()
            self.consume("RPAREN")
            return inner
        if kind == "IDENT" and val == "contains":
            raise ValueError(
                'Cloudflare \'contains\' must be used as an infix operator (field contains "value"), not a function'
            )
        if kind == "IDENT" and val == "starts_with":
            self.consume("IDENT")
            self.consume("LPAREN")
            field_name = self.consume("IDENT")[1]
            self.consume("COMMA")
            needle = self.consume("STRING")[1]
            self.consume("RPAREN")
            return self._field(field_name).startswith(needle)
        if kind == "IDENT":
            field_name = self.consume("IDENT")[1]
            op = self.consume("IDENT")[1]
            haystack = self._field(field_name)
            if op == "eq":
                target = self.consume("STRING")[1]
                return haystack == target
            if op == "contains":
                target = self.consume("STRING")[1]
                return target in haystack
            if op == "in":
                self.consume("LBRACE")
                values = set()
                while self.peek()[0] != "RBRACE":
                    values.add(self.consume("STRING")[1])
                self.consume("RBRACE")
                return haystack in values
            raise ValueError(f"Unsupported operator: {op!r}")
        raise ValueError(f"Unexpected token in Cloudflare expression: {(kind, val)!r}")

    def _field(self, name):
        if name not in self.fields:
            raise ValueError(f"Unsupported Cloudflare expression field: {name!r}")
        return self.fields[name]


def eval_expression(expression, *, host, path, query=""):
    fields = {
        "http.host": host,
        "http.request.uri.path": path,
        "http.request.uri.query": query,
    }
    return _ExprParser(_tokenize(expression), fields).parse()


def evaluate_ruleset(rules, *, host, path, query=""):
    """Simulate Cloudflare Cache Rules last-match-wins evaluation."""
    matched = []
    effective = None
    for rule in rules:
        if not rule.get("enabled", True):
            continue
        if eval_expression(rule["expression"], host=host, path=path, query=query):
            matched.append(rule["id"])
            if effective is None:
                effective = dict(rule["action_parameters"])
            else:
                effective = {**effective, **rule["action_parameters"]}
                if rule["action_parameters"].get("cache") is False:
                    effective.pop("edge_ttl", None)
                    effective.pop("browser_ttl", None)
                    effective.pop("serve_stale", None)
    return matched, effective


# ---------------------------------------------------------------------------
# Static verification (offline CI)
# ---------------------------------------------------------------------------

def _assert_no_store_error_rules(params, label):
    edge_ttl = params.get("edge_ttl") or {}
    if edge_ttl.get("mode") != "respect_origin":
        raise ValueError(f"{label}: edge_ttl.mode must be 'respect_origin'")
    if (params.get("browser_ttl") or {}).get("mode") != "respect_origin":
        raise ValueError(f"{label}: browser_ttl.mode must be 'respect_origin'")
    if (params.get("serve_stale") or {}).get("disable_stale_while_updating") is not True:
        raise ValueError(f"{label}: serve_stale.disable_stale_while_updating must be true")
    status_rules = edge_ttl.get("status_code_ttl") or []
    covered_codes = set()
    for entry in status_rules:
        if entry.get("value") != -1:
            raise ValueError(f"{label}: error status_code_ttl must use -1 (no-store), not {entry.get('value')!r}")
        if "status_code" in entry:
            covered_codes.add(entry["status_code"])
        elif "status_code_range" in entry:
            rng = entry["status_code_range"]
            covered_codes.update(range(rng["from"], rng["to"] + 1))
    required_errors = {400, 403, 404, 410, 429, 500, 502, 503, 504}
    missing = sorted(required_errors - covered_codes)
    if missing:
        raise ValueError(f"{label}: missing no-store error status codes: {missing}")


def verify_static(firebase_path=DEFAULT_FIREBASE, rules_path=DEFAULT_RULES):
    """Run all offline static checks for firebase.json and Cloudflare Cache Rules."""
    firebase_doc = json.loads(Path(firebase_path).read_text())
    hosting_list = firebase_doc.get("hosting")
    if not isinstance(hosting_list, list) or len(hosting_list) != 1:
        raise ValueError("firebase.json must define exactly one hosting target")
    target = hosting_list[0]
    if target.get("target") != "production" or target.get("public") != "publisher/site":
        raise ValueError("firebase.json hosting target must be production -> publisher/site")
    if "**/.*" not in target.get("ignore", []):
        raise ValueError("firebase.json hosting ignore must exclude dotfiles (**/.*)")

    # Preserve Firebase Functions and Firestore rules untouched.
    functions = firebase_doc.get("functions")
    if not isinstance(functions, list) or not any(
            fn.get("source") == "pricing-proxy" and fn.get("codebase") == "pricing" for fn in functions):
        raise ValueError("firebase.json must preserve the pricing-proxy Functions configuration")
    if (firebase_doc.get("firestore") or {}).get("rules") != "pricing-proxy/firestore.rules":
        raise ValueError("firebase.json must preserve the pricing-proxy Firestore rules")

    hosting_rules = r2.HostingRules(firebase_doc)
    immutable = "public,max-age=31536000,immutable"
    json_utf8 = "application/json; charset=utf-8"
    text_utf8 = "text/plain; charset=utf-8"
    expected_paths = {
        # Immutable catalog releases across all 4 hosted catalog namespaces
        "v1/releases/26/catalog-release.json": ("application/json", immutable, r2.IMMUTABLE),
        "v1/releases/26/pokemon-catalog-snapshot.json": ("application/json", immutable, r2.IMMUTABLE),
        "magic/v1/releases/1/catalog-release.json": ("application/json", immutable, r2.IMMUTABLE),
        "one-piece/v1/releases/7/catalog-release.json": ("application/json", immutable, r2.IMMUTABLE),
        "yugioh/v1/releases/1/catalog-release.json": ("application/json", immutable, r2.IMMUTABLE),
        "yugioh/v1/releases/1/catalog.json": ("application/json", immutable, r2.IMMUTABLE),
        # Immutable v2 price builds (including extensionless files & verified-build receipts)
        "market-prices/v2/builds/abc123/index.json": (json_utf8, immutable, r2.IMMUTABLE),
        "market-prices/v2/builds/abc123/tcgplayer/3/1/products": (json_utf8, immutable, r2.IMMUTABLE),
        "market-prices/v2/builds/abc123/tcgplayer/3/1/prices": (json_utf8, immutable, r2.IMMUTABLE),
        "market-prices/v2/builds/abc123/scopes/one-piece.json": (json_utf8, immutable, r2.IMMUTABLE),
        "market-prices/v2/builds/abc123/scopes/yugioh.json": (json_utf8, immutable, r2.IMMUTABLE),
        "market-prices/v2/builds/abc123/last-updated.txt": (text_utf8, immutable, r2.IMMUTABLE),
        "market-prices/v2/verified-builds/abc123.json": (json_utf8, immutable, r2.IMMUTABLE),
        # Mutable catalog pointers & scopes
        "v1/current.json": ("application/json", "no-cache", r2.POINTER),
        "magic/v1/current.json": ("application/json", "no-cache", r2.POINTER),
        "one-piece/v1/current.json": ("application/json", "no-cache", r2.POINTER),
        "yugioh/v1/current.json": ("application/json", "no-cache", r2.POINTER),
        "one-piece/v1/market-price-scope.json": ("application/json", "no-cache", r2.CATALOG_SCOPE),
        "yugioh/v1/market-price-scope.json": ("application/json", "no-cache", r2.CATALOG_SCOPE),
        # Mutable pricing metadata
        "market-prices/v2/latest.json": (json_utf8, "no-cache", r2.V2_POINTER),
        "market-prices/v1/last-updated.txt": (text_utf8, "no-cache", r2.MARKER),
        # Legacy v1 price files (including extensionless)
        "market-prices/v1/index.json": ("application/json", "public,max-age=300", r2.PRICE_INDEX),
        "market-prices/v1/tcgplayer/2/1110/products": (json_utf8, "public,max-age=300", r2.PRICE_DATA),
        "market-prices/v1/tcgplayer/68/23232/prices": (json_utf8, "public,max-age=300", r2.PRICE_DATA),
    }
    for rel, (ctype, ccontrol, expected_tier) in expected_paths.items():
        actual_ctype, actual_ccontrol = hosting_rules.headers(rel)
        if (actual_ctype, actual_ccontrol) != (ctype, ccontrol):
            raise ValueError(f"firebase.json headers mismatch for {rel}: got {(actual_ctype, actual_ccontrol)}, "
                             f"expected {(ctype, ccontrol)}")
        actual_tier = r2.tier(rel, actual_ccontrol)
        if actual_tier != expected_tier:
            raise ValueError(f"Tier mismatch for {rel}: got {actual_tier}, expected {expected_tier}")

    # Firebase-specific v2 history file must keep its no-cache header for rollback deploys.
    if hosting_rules.headers("market-prices/v2/history.json") != (json_utf8, "no-cache"):
        raise ValueError("firebase.json must keep no-cache on market-prices/v2/history.json")

    # Validate Cloudflare Cache Rules specification
    cf_doc = json.loads(Path(rules_path).read_text())
    if (cf_doc.get("schemaVersion") != 1 or cf_doc.get("phase") != "http_request_cache_settings"
            or cf_doc.get("precedence") != "last_match_wins"):
        raise ValueError("Invalid Cloudflare cache rules header metadata")
    staging = cf_doc.get("staging") or {}
    prod = cf_doc.get("production_cutover_template") or {}
    if staging.get("hostname") != "catalog-staging.scan-stash.com" or staging.get("activated") is not True:
        raise ValueError("Staging Cloudflare ruleset must target catalog-staging.scan-stash.com and be active")
    if prod.get("hostname") != "catalog.scan-stash.com" or prod.get("activated") is not False:
        raise ValueError("Production Cloudflare ruleset template must target catalog.scan-stash.com with activated=false")

    for section_name, section in (("staging", staging), ("production_cutover_template", prod)):
        host = section["hostname"]
        rules = section.get("rules") or []
        ids = [rule["id"] for rule in rules]
        expected_ids = [
            "immutable-catalog-and-price-builds",
            "legacy-v1-market-prices",
            "mutable-pointers-scopes-and-markers",
            "publisher-verification-nonce-bypass",
        ]
        if ids != expected_ids:
            raise ValueError(f"{section_name}: unexpected rule IDs or order: {ids} != {expected_ids}")
        for rule in rules:
            if rule.get("action") != "set_cache_settings" or rule.get("enabled") is not True:
                raise ValueError(f"{section_name}/{rule['id']}: must use enabled set_cache_settings action")

        # Test immutable paths (including extensionless v2 and verified-builds)
        for path in (
            "/v1/releases/26/catalog-release.json",
            "/magic/v1/releases/1/catalog-release.json",
            "/one-piece/v1/releases/7/catalog-release.json",
            "/yugioh/v1/releases/1/catalog.json",
            "/market-prices/v2/builds/aabbcc/tcgplayer/3/1/prices",
            "/market-prices/v2/builds/aabbcc/index.json",
            "/market-prices/v2/builds/aabbcc/last-updated.txt",
            "/market-prices/v2/verified-builds/aabbcc.json",
            f"/{PROBE_PREFIX}probe-123.json",
        ):
            matched, eff = evaluate_ruleset(rules, host=host, path=path)
            if matched != ["immutable-catalog-and-price-builds"] or eff.get("cache") is not True:
                raise ValueError(f"{section_name}: immutable path {path} misclassified: {matched}, {eff}")
            _assert_no_store_error_rules(eff, f"{section_name}:{path}")

        # Test legacy v1 price paths (including extensionless): must bypass edge cache so
        # legacy v1 clients never receive stale group files paired with a new last-updated.txt.
        for path in ("/market-prices/v1/index.json", "/market-prices/v1/tcgplayer/68/23232/prices"):
            matched, eff = evaluate_ruleset(rules, host=host, path=path)
            if matched != ["legacy-v1-market-prices"] or eff.get("cache") is not False:
                raise ValueError(f"{section_name}: legacy v1 path {path} must bypass edge cache: {matched}, {eff}")

        # Test mutable pointers, scopes, and markers
        for path in (
            "/v1/current.json",
            "/magic/v1/current.json",
            "/one-piece/v1/current.json",
            "/yugioh/v1/current.json",
            "/one-piece/v1/market-price-scope.json",
            "/yugioh/v1/market-price-scope.json",
            "/market-prices/v2/latest.json",
            "/market-prices/v2/history.json",
            "/market-prices/v1/last-updated.txt",
        ):
            matched, eff = evaluate_ruleset(rules, host=host, path=path)
            if matched != ["mutable-pointers-scopes-and-markers"] or eff.get("cache") is not False:
                raise ValueError(f"{section_name}: mutable path {path} not bypassed: {matched}, {eff}")

        # Test verification nonce bypass precedence over immutable and legacy v1 rules
        for path in (
            "/v1/releases/26/catalog-release.json",
            "/market-prices/v2/builds/aabbcc/tcgplayer/3/1/prices",
            "/market-prices/v1/index.json",
            "/market-prices/v1/tcgplayer/3/1/products",
            "/v1/current.json",
        ):
            for query in (
                "r2v=deadbeef",
                "foo=1&r2v=deadbeef",
                "v2r=cafebabe",
                "foo=1&v2r=cafebabe",
                "publication_check=local-1",
                "foo=1&publication_check=local-1",
            ):
                matched, eff = evaluate_ruleset(rules, host=host, path=path, query=query)
                if "publisher-verification-nonce-bypass" not in matched or eff.get("cache") is not False:
                    raise ValueError(f"{section_name}: nonce query {path}?{query} did not bypass: {matched}, {eff}")
            # Unrelated query string on immutable resource must NOT trigger nonce bypass.
            matched, eff = evaluate_ruleset(rules, host=host, path="/v1/releases/26/catalog-release.json",
                                            query="unrelated=1")
            if matched != ["immutable-catalog-and-price-builds"] or eff.get("cache") is not True:
                raise ValueError(f"{section_name}: unrelated query unexpectedly bypassed cache")

        # Non-managed hosts and non-managed paths must never match any rule.
        for foreign_host in ("scan-stash.com", "www.scan-stash.com", "mail.scan-stash.com",
                             "catalog.scan-stash.com" if host == "catalog-staging.scan-stash.com" else "catalog-staging.scan-stash.com"):
            matched, eff = evaluate_ruleset(rules, host=foreign_host, path="/v1/current.json")
            if matched or eff is not None:
                raise ValueError(f"{section_name}: rule leaked onto foreign host {foreign_host}: {matched}")
        for foreign_path in ("/", "/privacy", "/support", "/index.html"):
            matched, eff = evaluate_ruleset(rules, host=host, path=foreign_path, query="r2v=1")
            if matched or eff is not None:
                raise ValueError(f"{section_name}: rule leaked onto non-catalog path {foreign_path}: {matched}")

    return {"firebase": "valid", "cloudflareRules": "valid", "verifiedPaths": len(expected_paths)}


# ---------------------------------------------------------------------------
# Live verification (staging only; explicit operator or authorized workflow)
# ---------------------------------------------------------------------------

def _decode_envelope_revision(raw):
    doc = json.loads(raw)
    encoded = doc["payload"]
    payload = json.loads(base64.b64decode(encoded + "=" * (-len(encoded) % 4), altchars=b"-_", validate=True))
    rev = payload.get("revision")
    if type(rev) is not int or rev < 1:
        raise ValueError("Unable to discover positive revision from signed pointer")
    return rev


def verify_live_immutable(origin, key, expected_sha, expected_content_type, *,
                          fetch=fetch_canonical, attempts=4, sleep=time.sleep):
    url = f"{origin}/{key}"
    observed_statuses = []
    last = None
    for index in range(attempts):
        status, headers, body = fetch(url)
        if status != 200:
            raise ValueError(f"Immutable check failed for {url}: HTTP {status}")
        actual_sha = hashlib.sha256(body).hexdigest()
        if expected_sha and actual_sha != expected_sha:
            raise ValueError(f"Immutable SHA-256 mismatch for {url}")
        cc = headers.get("cache-control", "")
        if cc != "public,max-age=31536000,immutable":
            raise ValueError(f"Unexpected Cache-Control for {url}: {cc!r}")
        ctype = headers.get("content-type", "")
        if ctype != expected_content_type:
            raise ValueError(f"Unexpected Content-Type for {url}: {ctype!r}")
        cf_status = headers.get("cf-cache-status", "").strip().upper()
        observed_statuses.append(cf_status or "MISSING")
        last = {
            "url": url,
            "pathClass": "immutable",
            "status": status,
            "expectedSHA256": expected_sha or actual_sha,
            "observedSHA256": actual_sha,
            "cacheControl": cc,
            "contentType": ctype,
            "cfCacheStatusHistory": list(observed_statuses),
            "age": headers.get("age"),
            "etag": headers.get("etag"),
            "cfRay": headers.get("cf-ray"),
        }
        if cf_status in EDGE_HIT_CACHE_STATUSES:
            return last
        if index + 1 < attempts:
            sleep(0.5)
    raise ValueError(f"Immutable resource did not demonstrate Cloudflare edge caching at {url}: "
                     f"observed cf-cache-status={observed_statuses}")


def verify_live_mutable(origin, key, expected_content_type, *, fetch=fetch_canonical, attempts=2):
    url = f"{origin}/{key}"
    statuses = []
    first_sha = None
    etag = None
    last = None
    for _ in range(attempts):
        status, headers, body = fetch(url)
        if status != 200:
            raise ValueError(f"Mutable check failed for {url}: HTTP {status}")
        sha = hashlib.sha256(body).hexdigest()
        if first_sha is None:
            first_sha = sha
        elif sha != first_sha:
            raise ValueError(f"Mutable bytes unexpectedly changed during check for {url}")
        cc = headers.get("cache-control", "")
        if cc != "no-cache":
            raise ValueError(f"Mutable resource lacks no-cache header at {url}: {cc!r}")
        ctype = headers.get("content-type", "")
        if ctype != expected_content_type:
            raise ValueError(f"Unexpected Content-Type for {url}: {ctype!r}")
        cf_status = headers.get("cf-cache-status", "").strip().upper()
        if cf_status not in BYPASS_CACHE_STATUSES:
            raise ValueError(f"Mutable resource was not bypassed at {url}: cf-cache-status={cf_status or 'missing'!r}")
        statuses.append(cf_status)
        etag = headers.get("etag") or etag
        last = {
            "url": url,
            "pathClass": "mutable",
            "status": status,
            "expectedSHA256": first_sha,
            "observedSHA256": sha,
            "cacheControl": cc,
            "contentType": ctype,
            "cfCacheStatusHistory": list(statuses),
            "etag": etag,
            "cfRay": headers.get("cf-ray"),
            "conditionalRevalidation": None,
        }
    if etag:
        cond_status, cond_headers, cond_body = fetch(url, extra_headers={"If-None-Match": etag})
        cond_cf = cond_headers.get("cf-cache-status", "").strip().upper()
        if cond_cf not in BYPASS_CACHE_STATUSES:
            raise ValueError(f"Conditional revalidation for {url} was not bypassed: {cond_cf or 'missing'!r}")
        if cond_status == 304:
            last["conditionalRevalidation"] = {"status": 304, "cfCacheStatus": cond_cf}
        elif cond_status == 200 and hashlib.sha256(cond_body).hexdigest() == first_sha:
            last["conditionalRevalidation"] = {"status": 200, "cfCacheStatus": cond_cf}
        else:
            raise ValueError(f"Unexpected conditional revalidation response for {url}: HTTP {cond_status}")
    return last, body


def verify_live_legacy_v1(origin, key, expected_sha, expected_content_type, *,
                          fetch=fetch_canonical, attempts=2, sleep=time.sleep):
    url = f"{origin}/{key}"
    statuses = []
    last = None
    for index in range(attempts):
        status, headers, body = fetch(url)
        if status != 200:
            raise ValueError(f"Legacy v1 check failed for {url}: HTTP {status}")
        actual_sha = hashlib.sha256(body).hexdigest()
        if expected_sha and actual_sha != expected_sha:
            raise ValueError(f"Legacy v1 SHA-256 mismatch for {url}")
        cc = headers.get("cache-control", "")
        if cc != "public,max-age=300":
            raise ValueError(f"Unexpected legacy v1 Cache-Control for {url}: {cc!r}")
        ctype = headers.get("content-type", "")
        if ctype != expected_content_type:
            raise ValueError(f"Unexpected legacy v1 Content-Type for {url}: {ctype!r}")
        cf_status = headers.get("cf-cache-status", "").strip().upper()
        if cf_status not in BYPASS_CACHE_STATUSES:
            raise ValueError(
                f"Legacy v1 resource was not bypassed at edge for {url}: "
                f"cf-cache-status={cf_status or 'missing'!r} (expected BYPASS or DYNAMIC)"
            )
        statuses.append(cf_status)
        last = {
            "url": url,
            "pathClass": "legacy-v1",
            "status": status,
            "expectedSHA256": expected_sha or actual_sha,
            "observedSHA256": actual_sha,
            "cacheControl": cc,
            "contentType": ctype,
            "cfCacheStatusHistory": list(statuses),
            "age": headers.get("age"),
            "etag": headers.get("etag"),
            "cfRay": headers.get("cf-ray"),
        }
        if index + 1 < attempts:
            sleep(0.2)
    return last, body


def run_negative_cache_probe(origin, put_object, delete_object, *, fetch=fetch_canonical,
                             retries=3, sleep=time.sleep):
    """Verify missing objects are not negatively cached under a dedicated staging probe path."""
    if origin.rstrip("/") != ALLOWED_STAGING_ORIGIN:
        raise ValueError("Missing-object diagnostic probe is only authorized on staging origin")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    nonce = secrets.token_hex(8)
    key = f"{PROBE_PREFIX}probe-{stamp}-{nonce}.json"
    url = f"{origin.rstrip('/')}/{key}"
    payload = json.dumps({"diagnostic": "negative-cache-probe", "nonce": nonce}, separators=(",", ":")).encode()
    expected_sha = hashlib.sha256(payload).hexdigest()

    missing_checks = []
    for _ in range(2):
        status, headers, _ = fetch(url)
        cf_status = headers.get("cf-cache-status", "").strip().upper()
        if status != 404:
            raise ValueError(f"Diagnostic probe path unexpectedly returned HTTP {status} before upload: {url}")
        if cf_status in {"HIT", "STALE", "REVALIDATED"}:
            raise ValueError(f"Negative caching detected on missing diagnostic object {url}: cf-cache-status={cf_status}")
        missing_checks.append({"status": status, "cfCacheStatus": cf_status or None, "cfRay": headers.get("cf-ray")})

    uploaded = False
    try:
        put_object(key, payload, "application/json", "public,max-age=31536000,immutable", expected_sha)
        uploaded = True
        found = None
        for attempt in range(retries + 1):
            status, headers, body = fetch(url)
            cf_status = headers.get("cf-cache-status", "").strip().upper()
            if status == 200 and hashlib.sha256(body).hexdigest() == expected_sha:
                found = {
                    "status": status,
                    "observedSHA256": expected_sha,
                    "cacheControl": headers.get("cache-control"),
                    "cfCacheStatus": cf_status or None,
                    "cfRay": headers.get("cf-ray"),
                }
                break
            if status == 404 and cf_status in {"HIT", "STALE"}:
                raise ValueError(f"Negative cache masked newly uploaded diagnostic object at {url} "
                                 f"(HTTP 404, cf-cache-status={cf_status})")
            if attempt == retries:
                raise ValueError(f"Newly uploaded diagnostic object was not readable at {url} "
                                 f"(HTTP {status}, cf-cache-status={cf_status or 'missing'})")
            sleep(2 ** attempt)
    finally:
        if uploaded:
            delete_object(key)

    return {
        "url": url,
        "key": key,
        "expectedSHA256": expected_sha,
        "beforeUpload": missing_checks,
        "afterUpload": found,
        "cleanedUp": True,
    }


def _params_match(deployed, expected):
    """Allow Cloudflare API default fields while requiring every spec key/value to match."""
    if isinstance(expected, dict):
        if not isinstance(deployed, dict):
            return False
        for key, exp_val in expected.items():
            if key not in deployed or not _params_match(deployed[key], exp_val):
                return False
        return True
    if isinstance(expected, list):
        return isinstance(deployed, list) and len(deployed) == len(expected) and all(
            _params_match(d, e) for d, e in zip(deployed, expected)
        )
    return deployed == expected


def inspect_deployed_cloudflare_rules(zone_id, read_token, expected_rules_path=DEFAULT_RULES, *, opener=None):
    """Read-only inspection of deployed Cloudflare Cache Rules against the repo spec."""
    if not zone_id or not ZONE_ID_RE.match(zone_id):
        raise ValueError("Invalid Cloudflare zone ID for rule inspection")
    if not read_token or any(ch.isspace() for ch in read_token):
        raise ValueError("Missing or malformed Cloudflare read-only rules token")
    spec = json.loads(Path(expected_rules_path).read_text())["staging"]
    expected_host = spec["hostname"]
    expected_rules = spec["rules"]
    endpoint = f"{CLOUDFLARE_API_BASE}/zones/{zone_id}/rulesets/phases/http_request_cache_settings/entrypoint"
    request = Request(
        endpoint,
        method="GET",
        headers={
            "Authorization": f"Bearer {read_token}",
            "User-Agent": "ScanStashCatalogPublisher/1.0",
        },
    )
    http = opener or build_opener(NoRedirects())
    try:
        with http.open(request, timeout=30) as response:
            body = response.read(2 * 1024 * 1024)
    except HTTPError as error:
        with error:
            raise ValueError(f"Cloudflare ruleset inspection failed with HTTP {error.code}") from None
    doc = json.loads(body)
    if not isinstance(doc, dict) or doc.get("success") is not True or not isinstance(doc.get("result"), dict):
        raise ValueError("Cloudflare ruleset inspection returned unsuccessful or malformed JSON")
    deployed = [rule for rule in (doc["result"].get("rules") or []) if rule.get("enabled", True)]
    staging_indices = [idx for idx, rule in enumerate(deployed) if expected_host in (rule.get("expression") or "")]
    staging_deployed = [deployed[idx] for idx in staging_indices]
    expected_tokens = [_tokenize(rule["expression"]) for rule in expected_rules]
    deployed_tokens = [_tokenize(rule.get("expression") or "") for rule in staging_deployed]
    if deployed_tokens != expected_tokens:
        raise ValueError(
            f"Deployed Cloudflare staging rules for {expected_host} do not match spec order/expressions "
            f"(deployed={len(staging_deployed)}, expected={len(expected_rules)})"
        )
    for dep, exp in zip(staging_deployed, expected_rules):
        if dep.get("action") != exp["action"] or not _params_match(dep.get("action_parameters"), exp["action_parameters"]):
            raise ValueError(f"Deployed Cloudflare rule action_parameters disagree with spec for {exp['id']}")
    # Detect overlapping catch-all zone rules positioned after our first staging rule.
    first_idx = staging_indices[0]
    staging_set = set(staging_indices)
    for idx in range(first_idx + 1, len(deployed)):
        if idx in staging_set:
            continue
        expr = deployed[idx].get("expression") or ""
        if "http.host" not in expr:
            raise ValueError(
                f"Overlapping zone Cache Rule without hostname scope appears after {expected_host} rules "
                f"(position {idx + 1}): {deployed[idx].get('description') or deployed[idx].get('id')}"
            )
    return {
        "hostname": expected_host,
        "matchedRuleCount": len(staging_deployed),
        "totalEnabledZoneRules": len(deployed),
    }


def _aws_r2_helpers(bucket, account_id):
    endpoint = f"https://{account_id}.r2.cloudflarestorage.com"
    env = {
        **os.environ,
        "AWS_DEFAULT_REGION": "auto",
        "AWS_REQUEST_CHECKSUM_CALCULATION": "when_required",
        "AWS_RESPONSE_CHECKSUM_VALIDATION": "when_required",
    }

    def put_object(key, body, content_type, cache_control, sha_hex):
        with tempfile.NamedTemporaryFile(delete=False) as tmp:
            tmp.write(body)
            tmp_path = tmp.name
        try:
            subprocess.run(
                ["aws", "--endpoint-url", endpoint, "--cli-connect-timeout", "10", "--cli-read-timeout", "30",
                 "--no-cli-pager", "s3api", "put-object", "--bucket", bucket, "--key", key,
                 "--body", tmp_path, "--content-type", content_type, "--cache-control", cache_control,
                 "--metadata", f"sha256={sha_hex}"],
                check=True, capture_output=True, text=True, env=env,
            )
        finally:
            Path(tmp_path).unlink(missing_ok=True)

    def delete_object(key):
        subprocess.run(
            ["aws", "--endpoint-url", endpoint, "--cli-connect-timeout", "10", "--cli-read-timeout", "30",
             "--no-cli-pager", "s3api", "delete-object", "--bucket", bucket, "--key", key],
            check=True, capture_output=True, text=True, env=env,
        )

    return put_object, delete_object


def verify_live(origin=ALLOWED_STAGING_ORIGIN, *, fetch=fetch_canonical,
                probe_missing=False, put_object=None, delete_object=None,
                inspect_rules=False, zone_id=None, read_token=None,
                firebase_path=DEFAULT_FIREBASE, rules_path=DEFAULT_RULES,
                sleep=time.sleep):
    origin = origin.rstrip("/")
    if origin != ALLOWED_STAGING_ORIGIN:
        raise ValueError(f"Live verification is restricted to staging origin {ALLOWED_STAGING_ORIGIN}")
    hosting_rules = r2.HostingRules.load(firebase_path)
    report = {
        "origin": origin,
        "checkedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "mutable": [],
        "immutable": [],
        "legacyV1": [],
        "negativeCacheProbe": None,
        "cloudflareRulesInspection": None,
    }

    if inspect_rules:
        report["cloudflareRulesInspection"] = inspect_deployed_cloudflare_rules(
            zone_id, read_token, expected_rules_path=rules_path)

    # 1. Discover active catalog pointers and their immutable release objects.
    catalog_specs = (
        ("v1", True),
        ("one-piece/v1", True),
        ("magic/v1", False),
        ("yugioh/v1", False),
    )
    for namespace, required in catalog_specs:
        pointer_key = f"{namespace}/current.json"
        status, _, _ = fetch(f"{origin}/{pointer_key}")
        if status == 404 and not required:
            continue
        expected_ctype, _ = hosting_rules.headers(pointer_key)
        mut_rec, pointer_body = verify_live_mutable(origin, pointer_key, expected_ctype, fetch=fetch)
        report["mutable"].append(mut_rec)
        revision = _decode_envelope_revision(pointer_body)
        release_key = f"{namespace}/releases/{revision}/catalog-release.json"
        rel_ctype, _ = hosting_rules.headers(release_key)
        report["immutable"].append(verify_live_immutable(
            origin, release_key, hashlib.sha256(pointer_body).hexdigest(), rel_ctype,
            fetch=fetch, sleep=sleep,
        ))

    # 2. Verify catalog price scopes.
    for _, namespace in CATALOG_NAMESPACES.values():
        scope_key = f"{namespace}/{SCOPE_FILE}"
        scope_ctype, _ = hosting_rules.headers(scope_key)
        mut_rec, _ = verify_live_mutable(origin, scope_key, scope_ctype, fetch=fetch)
        report["mutable"].append(mut_rec)

    # 3. Verify v2 pricing pointer and representative immutable v2 build files
    #    (extensionless product/price, JSON index, text marker, and verified-build receipt if present).
    latest_ctype, _ = hosting_rules.headers(v2.LATEST)
    mut_rec, latest_body = verify_live_mutable(origin, v2.LATEST, latest_ctype, fetch=fetch)
    report["mutable"].append(mut_rec)
    pointer = v2.validate_pointer(latest_body)
    build = pointer["build"]
    rows_by_path = {row["path"]: row for row in pointer["files"]}
    extensionless_row = next(row for row in pointer["files"] if row["path"].startswith("tcgplayer/"))
    for row in (rows_by_path["index.json"], rows_by_path["last-updated.txt"], extensionless_row):
        key = f"{v2.V2}/builds/{build}/{row['path']}"
        ctype, _ = hosting_rules.headers(key)
        report["immutable"].append(verify_live_immutable(
            origin, key, row["sha256"], ctype, fetch=fetch, sleep=sleep))
    receipt_key = f"{v2.V2}/verified-builds/{build}.json"
    receipt_status, _, _ = fetch(f"{origin}/{receipt_key}")
    if receipt_status == 200:
        receipt_ctype, _ = hosting_rules.headers(receipt_key)
        report["immutable"].append(verify_live_immutable(
            origin, receipt_key, hashlib.sha256(latest_body).hexdigest(), receipt_ctype,
            fetch=fetch, sleep=sleep))

    # 4. Verify legacy v1 marker (mutable) and v1 index + extensionless feed (300s cacheable).
    marker_key = f"{NAMESPACE}/last-updated.txt"
    marker_ctype, _ = hosting_rules.headers(marker_key)
    mut_rec, _ = verify_live_mutable(origin, marker_key, marker_ctype, fetch=fetch)
    report["mutable"].append(mut_rec)

    index_key = f"{NAMESPACE}/index.json"
    index_ctype, _ = hosting_rules.headers(index_key)
    idx_rec, index_body = verify_live_legacy_v1(origin, index_key, None, index_ctype, fetch=fetch, sleep=sleep)
    report["legacyV1"].append(idx_rec)
    v1_index = json.loads(index_body)
    v1_feed = next(row for row in v1_index["files"] if row["path"].startswith("tcgplayer/"))
    v1_feed_key = f"{NAMESPACE}/{v1_feed['path']}"
    v1_feed_ctype, _ = hosting_rules.headers(v1_feed_key)
    feed_rec, _ = verify_live_legacy_v1(origin, v1_feed_key, v1_feed["sha256"], v1_feed_ctype,
                                        fetch=fetch, sleep=sleep)
    report["legacyV1"].append(feed_rec)

    # 5. Optional missing-object negative-cache diagnostic probe.
    if probe_missing:
        if put_object is None or delete_object is None:
            raise ValueError("Missing-object probe requires R2 put/delete helpers")
        report["negativeCacheProbe"] = run_negative_cache_probe(
            origin, put_object, delete_object, fetch=fetch, sleep=sleep)

    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    static_cmd = commands.add_parser("static", help="Validate firebase.json and Cloudflare Cache Rules offline")
    static_cmd.add_argument("--firebase-config", type=Path, default=DEFAULT_FIREBASE)
    static_cmd.add_argument("--rules", type=Path, default=DEFAULT_RULES)

    live_cmd = commands.add_parser("live", help="Verify live staging cache behavior against R2 staging")
    live_cmd.add_argument("--origin", default=ALLOWED_STAGING_ORIGIN)
    live_cmd.add_argument("--firebase-config", type=Path, default=DEFAULT_FIREBASE)
    live_cmd.add_argument("--rules", type=Path, default=DEFAULT_RULES)
    live_cmd.add_argument("--probe-missing-object", action="store_true",
                          help="Run authorized staging missing-object negative-cache probe (requires R2 creds)")
    live_cmd.add_argument("--bucket", default=os.environ.get("R2_BUCKET_NAME"))
    live_cmd.add_argument("--account-id", default=os.environ.get("R2_ACCOUNT_ID"))
    live_cmd.add_argument("--inspect-cloudflare-rules", action="store_true",
                          help="Compare deployed staging Cache Rules via read-only CLOUDFLARE_RULES_READ_TOKEN")
    live_cmd.add_argument("--cloudflare-zone-id", default=os.environ.get("CLOUDFLARE_ZONE_ID"))
    live_cmd.add_argument("--cloudflare-rules-read-token", default=os.environ.get("CLOUDFLARE_RULES_READ_TOKEN"))
    live_cmd.add_argument("--report", type=Path, help="Write structured JSON evidence report")

    args = parser.parse_args(argv)
    try:
        if args.command == "static":
            summary = verify_static(args.firebase_config, args.rules)
            print(f"Static hosting and Cloudflare cache policy verified ({summary['verifiedPaths']} managed paths).")
            return 0
        put_object = delete_object = None
        if args.probe_missing_object:
            if not args.bucket or not re.fullmatch(r"[0-9a-f]{32}", args.account_id or ""):
                raise ValueError("--probe-missing-object requires R2_BUCKET_NAME and 32-hex R2_ACCOUNT_ID")
            put_object, delete_object = _aws_r2_helpers(args.bucket, args.account_id)
        report = verify_live(
            args.origin,
            probe_missing=args.probe_missing_object,
            put_object=put_object,
            delete_object=delete_object,
            inspect_rules=args.inspect_cloudflare_rules,
            zone_id=args.cloudflare_zone_id,
            read_token=args.cloudflare_rules_read_token,
            firebase_path=args.firebase_config,
            rules_path=args.rules,
        )
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        print(f"Live staging cache verification passed: {len(report['immutable'])} immutable, "
              f"{len(report['mutable'])} mutable, {len(report['legacyV1'])} legacy v1 checked.")
        return 0
    except (ValueError, RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(f"Hosting cache verification failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
