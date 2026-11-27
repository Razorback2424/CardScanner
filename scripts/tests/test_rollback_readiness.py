"""Offline regression tests for continuous Firebase rollback readiness checks."""
from __future__ import annotations

import base64
from datetime import datetime, timedelta, timezone
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from urllib.error import HTTPError

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import market_price_feeds as feeds  # noqa: E402
import market_price_rollback as rollback  # noqa: E402
import market_price_v2 as v2  # noqa: E402
import rollback_readiness as rr  # noqa: E402

WORKFLOWS = Path(__file__).resolve().parents[2] / ".github/workflows"


def _envelope(payload: dict) -> bytes:
    encoded = base64.urlsafe_b64encode(feeds.packed(payload)).rstrip(b"=").decode("ascii")
    return feeds.packed({"keyID": "prod-1", "payload": encoded, "signature": "sig"})


def _build_matching_origins(tmp: Path, *, include_optional: bool = False):
    r2_dir = tmp / "r2"
    fb_dir = tmp / "fb"
    r2_dir.mkdir()
    fb_dir.mkdir()

    def put(base: Path, rel: str, raw: bytes):
        path = base / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)

    poke_env = _envelope({"schemaVersion": 1, "catalogKind": "pokemon", "revision": 26})
    op_env = _envelope({"schemaVersion": 1, "catalogKind": "one-piece", "revision": 7})
    put(r2_dir, "v1/current.json", poke_env)
    put(r2_dir, "v1/releases/26/catalog-release.json", poke_env)
    put(r2_dir, "v1/releases/26/pokemon-catalog-snapshot.json", feeds.packed({"schemaVersion": 1, "entries": []}))
    put(r2_dir, "one-piece/v1/current.json", op_env)
    put(r2_dir, "one-piece/v1/releases/7/catalog-release.json", op_env)
    if include_optional:
        mtg_env = _envelope({"schemaVersion": 1, "catalogKind": "magic", "revision": 3})
        ygo_env = _envelope({"schemaVersion": 2, "revision": 2})
        put(r2_dir, "magic/v1/current.json", mtg_env)
        put(r2_dir, "magic/v1/releases/3/catalog-release.json", mtg_env)
        put(r2_dir, "yugioh/v1/current.json", ygo_env)
        put(r2_dir, "yugioh/v1/releases/2/catalog-release.json", ygo_env)
        put(r2_dir, "yugioh/v1/releases/2/catalog.json", feeds.packed({"schemaVersion": 1, "printings": []}))

    op_digest = hashlib.sha256(op_env).hexdigest()
    ygo_digest = hashlib.sha256(b"ygo-seed").hexdigest()
    op_scope = feeds.packed(
        {
            "schemaVersion": 1,
            "game": "one-piece",
            "revision": 7,
            "catalogSHA256": op_digest,
            "pointerSHA256": op_digest,
            "groups": [[2, [[2, ["Normal"]]]]],
        }
    )
    ygo_scope = feeds.packed(
        {
            "schemaVersion": 1,
            "game": "yugioh",
            "revision": 2 if include_optional else None,
            "catalogSHA256": ygo_digest,
            "pointerSHA256": ygo_digest if include_optional else None,
            "groups": [[3, [[3, ["1st Edition"]]]]],
        }
    )
    put(r2_dir, f"one-piece/v1/{feeds.SCOPE_FILE}", op_scope)
    put(r2_dir, f"yugioh/v1/{feeds.SCOPE_FILE}", ygo_scope)

    source_build = "2026-11-27T10:00:00+0000"

    def products_doc(category: int, group: int, pid: int, name: str) -> bytes:
        return feeds.packed(
            {
                "success": True,
                "errors": [],
                "sourceBuild": source_build,
                "sourceFetchedAt": source_build,
                "results": [
                    {
                        "productId": pid,
                        "categoryId": category,
                        "groupId": group,
                        "name": name,
                        "extendedData": [],
                    }
                ],
            }
        )

    def prices_doc(pid: int, lane: str, price: float) -> bytes:
        return feeds.packed(
            {
                "success": True,
                "errors": [],
                "sourceBuild": source_build,
                "sourceFetchedAt": source_build,
                "results": [{"productId": pid, "subTypeName": lane, "marketPrice": price}],
            }
        )

    v1_root = r2_dir / feeds.NAMESPACE
    for rel, raw in {
        "tcgplayer/3/1/products": products_doc(3, 1, 1, "Pikachu"),
        "tcgplayer/3/1/prices": prices_doc(1, "Normal", 5.0),
        "tcgplayer/68/2/products": products_doc(68, 2, 2, "Luffy"),
        "tcgplayer/68/2/prices": prices_doc(2, "Normal", 6.0),
        "tcgplayer/2/3/products": products_doc(2, 3, 3, "Blue-Eyes"),
        "tcgplayer/2/3/prices": prices_doc(3, "1st Edition", 7.0),
        "tcgplayer/71/4/products": products_doc(71, 4, 4, "Mickey"),
        "tcgplayer/71/4/prices": prices_doc(4, "Normal", 8.0),
    }.items():
        put(v1_root, rel, raw)
    put(v1_root, "last-updated.txt", (source_build + "\n").encode("utf-8"))
    manifest_files = []
    for p in sorted(v1_root.rglob("*")):
        if p.is_file():
            raw = p.read_bytes()
            manifest_files.append(
                {"path": p.relative_to(v1_root).as_posix(), "sha256": hashlib.sha256(raw).hexdigest(), "byteCount": len(raw)}
            )
    put(v1_root, "index.json", feeds.packed({"schemaVersion": 1, "sourceBuild": source_build, "files": manifest_files}))
    pointer = v2.stage(r2_dir, retain_history=True)
    build_id = pointer["build"]

    # Mirror R2 to Firebase and add Firebase v2 history.json.
    for src in r2_dir.rglob("*"):
        if src.is_file():
            put(fb_dir, src.relative_to(r2_dir).as_posix(), src.read_bytes())
    put(fb_dir, rollback.HISTORY, rollback.history_bytes({build_id}))
    return r2_dir, fb_dir, build_id


def _make_fetcher(r2_dir: Path, fb_dir: Path, *, header_overrides: dict[str, dict[str, str]] | None = None):
    overrides = header_overrides or {}

    def default_headers(rel: str) -> dict[str, str]:
        if "/releases/" in rel or rel.startswith("market-prices/v2/builds/"):
            return {"cache-control": "public, max-age=31536000, immutable"}
        if rel.endswith(("current.json", feeds.SCOPE_FILE, "latest.json", "history.json", "last-updated.txt")):
            return {"cache-control": "no-cache"}
        return {"cache-control": "public, max-age=300"}

    def fetch(url: str, maximum: int, *, absent_ok: bool = False):
        clean = url.split("?", 1)[0]
        if clean.startswith(feeds.R2_ORIGIN + "/"):
            rel = clean[len(feeds.R2_ORIGIN) + 1 :]
            target = r2_dir / rel
            headers = default_headers(rel)
        elif clean.startswith(feeds.ORIGIN + "/"):
            rel = clean[len(feeds.ORIGIN) + 1 :]
            target = fb_dir / rel
            headers = overrides.get(rel, default_headers(rel))
        else:
            raise AssertionError(f"Unexpected URL: {url}")
        if not target.is_file():
            if absent_ok:
                return None, {}
            raise HTTPError(url, 404, "Not Found", {}, io.BytesIO(b""))
        data = target.read_bytes()
        if len(data) > maximum:
            raise ValueError("oversized")
        return data, headers

    return fetch


class ParityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_parity_passes_when_catalogs_scopes_and_prices_match(self):
        r2_dir, fb_dir, build_id = _build_matching_origins(self.root)
        result = rr.check_parity(fetch=_make_fetcher(r2_dir, fb_dir))
        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["failures"], [])
        self.assertEqual(result["observed"]["catalogRevisions"], {"v1": 26, "one-piece/v1": 7})
        self.assertEqual(result["observed"]["priceBuild"], build_id)
        self.assertEqual(result["catalogs"]["magic/v1"]["status"], "absent")
        self.assertEqual(result["catalogs"]["yugioh/v1"]["status"], "absent")

    def test_parity_passes_with_optional_magic_and_yugioh_present(self):
        r2_dir, fb_dir, _ = _build_matching_origins(self.root, include_optional=True)
        result = rr.check_parity(fetch=_make_fetcher(r2_dir, fb_dir))
        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["observed"]["catalogRevisions"], {"v1": 26, "one-piece/v1": 7, "magic/v1": 3, "yugioh/v1": 2})

    def test_parity_fails_on_stale_firebase_pointer(self):
        r2_dir, fb_dir, _ = _build_matching_origins(self.root)
        (fb_dir / "v1/current.json").write_bytes(_envelope({"schemaVersion": 1, "catalogKind": "pokemon", "revision": 25}))
        result = rr.check_parity(fetch=_make_fetcher(r2_dir, fb_dir))
        self.assertEqual(result["status"], "failed")
        self.assertTrue(any("v1/current.json digest mismatch" in f for f in result["failures"]))

    def test_parity_fails_when_optional_namespace_only_on_one_origin(self):
        r2_dir, fb_dir, _ = _build_matching_origins(self.root, include_optional=True)
        (fb_dir / "magic/v1/current.json").unlink()
        result = rr.check_parity(fetch=_make_fetcher(r2_dir, fb_dir))
        self.assertEqual(result["status"], "failed")
        self.assertTrue(any("magic/v1/current.json is present on R2 but missing on Firebase" in f for f in result["failures"]))

    def test_parity_fails_on_missing_firebase_immutable_release_or_bad_cache_header(self):
        r2_dir, fb_dir, _ = _build_matching_origins(self.root)
        (fb_dir / "one-piece/v1/releases/7/catalog-release.json").unlink()
        (fb_dir / "v1/releases/26/pokemon-catalog-snapshot.json").unlink()
        result = rr.check_parity(
            fetch=_make_fetcher(r2_dir, fb_dir, header_overrides={"v1/current.json": {"cache-control": "public, max-age=60"}})
        )
        self.assertEqual(result["status"], "failed")
        self.assertTrue(any("v1/current.json lacks no-cache header" in f for f in result["failures"]))
        self.assertTrue(any("one-piece/v1/releases/7/catalog-release.json" in f for f in result["failures"]))

        # Also check missing companion snapshot when pointer header is valid.
        result_snap = rr.check_parity(fetch=_make_fetcher(r2_dir, fb_dir))
        self.assertEqual(result_snap["status"], "failed")
        self.assertTrue(any("v1/releases/26/pokemon-catalog-snapshot.json" in f for f in result_snap["failures"]))

    def test_parity_fails_on_scope_or_v2_history_or_v1_drift(self):
        r2_dir, fb_dir, build_id = _build_matching_origins(self.root)
        (fb_dir / "one-piece/v1" / feeds.SCOPE_FILE).write_bytes(b'{"stale":true}\n')
        other_build = "0" * 64
        (fb_dir / rollback.HISTORY).write_bytes(rollback.history_bytes({other_build}))
        (fb_dir / feeds.NAMESPACE / "last-updated.txt").write_bytes(b"2026-11-20T00:00:00+0000\n")
        result = rr.check_parity(fetch=_make_fetcher(r2_dir, fb_dir))
        self.assertEqual(result["status"], "failed")
        self.assertTrue(any("market-price-scope.json digest mismatch" in f for f in result["failures"]))
        self.assertTrue(any(f"does not include active v2 build {build_id}" in f for f in result["failures"]))
        self.assertTrue(any("last-updated.txt digest mismatch" in f for f in result["failures"]))


class CertificateTests(unittest.TestCase):
    NOW = datetime(2026, 11, 27, 12, 0, 0, tzinfo=timezone.utc)

    def _cert(self, san: list[str], *, days_left: int = 45, days_ago: int = 30) -> dict:
        return {
            "subject": f"CN={san[0]}",
            "issuer": "O=Google Trust Services, CN=WR3",
            "notBefore": (self.NOW - timedelta(days=days_ago)).strftime("%b %d %H:%M:%S %Y GMT"),
            "notAfter": (self.NOW + timedelta(days=days_left)).strftime("%b %d %H:%M:%S %Y GMT"),
            "san": san,
            "tlsVersion": "TLSv1.3",
        }

    def test_wildcard_san_matching(self):
        self.assertTrue(rr.hostname_matches_san("scanstash-catalog-prod.web.app", "*.web.app"))
        self.assertFalse(rr.hostname_matches_san("nested.scanstash-catalog-prod.web.app", "*.web.app"))
        self.assertTrue(rr.hostname_matches_san("catalog.scan-stash.com", "CATALOG.SCAN-STASH.COM"))

    def test_probes_custom_rollback_hostname_directly_against_firebase_origin_via_sni(self):
        seen: list[tuple[str, str]] = []

        def fake_cert(connect_host: str, server_hostname: str) -> dict:
            seen.append((connect_host, server_hostname))
            if server_hostname == "scanstash-catalog-prod.web.app":
                return self._cert(["*.web.app", "scanstash-catalog-prod.web.app"], days_left=60)
            return self._cert(["catalog.scan-stash.com"], days_left=55)

        result = rr.check_certificates(cert_fetcher=fake_cert, now=self.NOW)
        self.assertEqual(result["status"], "passed")
        self.assertEqual(
            seen,
            [
                ("scanstash-catalog-prod.web.app", "scanstash-catalog-prod.web.app"),
                ("scanstash-catalog-prod.web.app", "catalog.scan-stash.com"),
            ],
        )

    def test_rejects_expiring_soon_expired_and_mismatched_san_certificates(self):
        def expiring(connect_host: str, server_hostname: str) -> dict:
            return self._cert([server_hostname], days_left=10 if server_hostname == "catalog.scan-stash.com" else 60)

        res_exp = rr.check_certificates(cert_fetcher=expiring, min_days=14, now=self.NOW)
        self.assertEqual(res_exp["status"], "failed")
        self.assertTrue(any("expires in 10.0 days" in f for f in res_exp["failures"]))

        def expired(connect_host: str, server_hostname: str) -> dict:
            return self._cert([server_hostname], days_left=-1)

        res_dead = rr.check_certificates(cert_fetcher=expired, now=self.NOW)
        self.assertEqual(res_dead["status"], "failed")
        self.assertTrue(any("expired at" in f for f in res_dead["failures"]))

        def wrong_san(connect_host: str, server_hostname: str) -> dict:
            return self._cert(["other.example.com"], days_left=60)

        res_san = rr.check_certificates(cert_fetcher=wrong_san, now=self.NOW)
        self.assertEqual(res_san["status"], "failed")
        self.assertTrue(any("do not cover" in f for f in res_san["failures"]))


class QuotaAndOAuthTests(unittest.TestCase):
    NOW = datetime(2026, 11, 27, 12, 0, 0, tzinfo=timezone.utc)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_fetch_firebase_quota_metrics_parses_hosting_and_monitoring(self):
        calls: list[str] = []

        def fake_api_get(url: str, token: str) -> dict:
            self.assertEqual(token, "tok-123")
            calls.append(url)
            if "/releases?" in url:
                return {
                    "releases": [
                        {
                            "name": "sites/scanstash-catalog-prod/releases/123",
                            "releaseTime": "2026-11-27T11:00:00Z",
                            "version": {
                                "name": "sites/scanstash-catalog-prod/versions/abc",
                                "status": "FINALIZED",
                                "fileCount": "1499",
                            },
                        }
                    ]
                }
            if "storage%2Ftotal_bytes" in url:
                return {
                    "timeSeries": [
                        {
                            "points": [
                                {"interval": {"endTime": "2026-11-27T08:00:00Z"}, "value": {"int64Value": "350000000"}},
                                {"interval": {"endTime": "2026-11-27T11:30:00Z"}, "value": {"int64Value": "400000000"}},
                            ]
                        }
                    ]
                }
            if "sent_bytes_count" in url:
                self.assertIn("aggregation.alignmentPeriod=3600s", url)
                self.assertIn("aggregation.perSeriesAligner=ALIGN_SUM", url)
                if "pageToken=page2" in url:
                    return {
                        "timeSeries": [
                            {
                                "points": [
                                    {"interval": {"endTime": "2026-11-10T10:00:00Z"}, "value": {"int64Value": "90000000"}},
                                ]
                            }
                        ]
                    }
                return {
                    "nextPageToken": "page2",
                    "timeSeries": [
                        {
                            "points": [
                                {"interval": {"endTime": "2026-11-27T10:00:00Z"}, "value": {"int64Value": "10000000"}},
                            ]
                        }
                    ],
                }
            raise AssertionError(f"Unexpected API URL: {url}")

        metrics = rr.fetch_firebase_quota_metrics(
            project_id="scanstash-catalog-prod",
            site_id="scanstash-catalog-prod",
            access_token="tok-123",
            now=self.NOW,
            api_get=fake_api_get,
        )
        self.assertEqual(metrics["hosting"]["latestVersionFileCount"], 1499)
        self.assertEqual(metrics["storageTotalBytes"], 400_000_000)
        self.assertEqual(metrics["bandwidthSent24hBytes"], 10_000_000)
        self.assertEqual(metrics["bandwidthSent30dBytes"], 100_000_000)
        self.assertEqual(len(calls), 4)

    def test_strict_vs_advisory_quota_evaluation_and_thresholds(self):
        r2_dir, fb_dir, _ = _build_matching_origins(self.root)
        # Strict mode fails closed when monitoring API errors.
        storage, bw = rr.evaluate_quota_headroom(
            site_root=fb_dir,
            metrics=None,
            metrics_error="HTTP 403 Forbidden",
            quota_mode="strict",
        )
        self.assertEqual(storage["status"], "failed")
        self.assertEqual(bw["status"], "failed")

        # Advisory mode marks advisory_unavailable (still NOT READY overall), but fails hard on over-budget.
        storage_adv, bw_adv = rr.evaluate_quota_headroom(
            site_root=fb_dir,
            metrics=None,
            metrics_error="HTTP 403 Forbidden",
            quota_mode="advisory",
        )
        self.assertEqual(storage_adv["status"], "advisory_unavailable")
        self.assertEqual(bw_adv["status"], "advisory_unavailable")

        # Over-budget usage ALWAYS fails hard even in advisory mode.
        storage_over, bw_over = rr.evaluate_quota_headroom(
            site_root=fb_dir,
            metrics={
                "storageTotalBytes": int(9.0 * 1024**3),
                "bandwidthSent24hBytes": int(310 * 1024**2),
                "bandwidthSent30dBytes": int(9.5 * 1024**3),
                "bandwidthPointCount": 5,
            },
            quota_mode="advisory",
        )
        self.assertEqual(storage_over["status"], "failed")
        self.assertEqual(bw_over["status"], "failed")

        # Staged site limit check fails closed.
        storage_staged_over, _ = rr.evaluate_quota_headroom(
            site_root=fb_dir,
            metrics={
                "storageTotalBytes": 100,
                "bandwidthSent24hBytes": 0,
                "bandwidthSent30dBytes": 0,
                "bandwidthPointCount": 1,
            },
            staged_site_limit_bytes=10,
            quota_mode="strict",
        )
        self.assertEqual(storage_staged_over["status"], "failed")
        self.assertTrue(any("Staged Firebase site" in f for f in storage_staged_over["failures"]))

    def test_mint_google_access_token_signs_rs256_and_guards_token_uri(self):
        # Generate an ephemeral RSA test key with openssl to exercise real JWT signing.
        key_proc = subprocess.run(
            ["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048"],
            capture_output=True,
            text=True,
            check=True,
        )
        sa_path = self.root / "sa.json"
        sa_path.write_text(
            json.dumps(
                {
                    "client_email": "test@scanstash-catalog-prod.iam.gserviceaccount.com",
                    "private_key": key_proc.stdout,
                    "token_uri": "https://oauth2.googleapis.com/token",
                }
            ),
            encoding="utf-8",
        )

        captured_req = {}

        class FakeResp:
            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self, n=-1):
                return b'{"access_token":"ya29.fake-test-token","expires_in":3600}'

        def fake_open(req, timeout=30):
            captured_req["url"] = req.full_url
            captured_req["body"] = req.data.decode("ascii")
            return FakeResp()

        token = rr.mint_google_access_token(sa_path, now=self.NOW, opener=fake_open)
        self.assertEqual(token, "ya29.fake-test-token")
        self.assertEqual(captured_req["url"], "https://oauth2.googleapis.com/token")
        self.assertIn("assertion=", captured_req["body"])

        # Reject untrusted token URI.
        bad_sa = self.root / "bad-sa.json"
        bad_sa.write_text(
            json.dumps(
                {
                    "client_email": "test@example.com",
                    "private_key": key_proc.stdout,
                    "token_uri": "https://evil.example/token",
                }
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(rr.ReadinessError, "Refusing untrusted OAuth token URI"):
            rr.mint_google_access_token(bad_sa, now=self.NOW, opener=fake_open)


class ReadinessReportAndWorkflowTests(unittest.TestCase):
    NOW = datetime(2026, 11, 27, 12, 0, 0, tzinfo=timezone.utc)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_end_to_end_readiness_report_ready_and_not_ready_summary(self):
        r2_dir, fb_dir, build_id = _build_matching_origins(self.root)
        sa = self.root / "sa.json"
        sa.write_text("{}")

        def ok_cert(connect_host, server_hostname):
            return {
                "subject": f"CN={server_hostname}",
                "issuer": "O=Google Trust Services, CN=WR3",
                "notBefore": (self.NOW - timedelta(days=20)).strftime("%b %d %H:%M:%S %Y GMT"),
                "notAfter": (self.NOW + timedelta(days=50)).strftime("%b %d %H:%M:%S %Y GMT"),
                "san": [server_hostname],
                "tlsVersion": "TLSv1.3",
            }

        def ok_metrics(**kwargs):
            return {
                "hosting": {"latestVersionFileCount": 1499},
                "storageTotalBytes": 500 * 1024**2,
                "storageObservedAt": "2026-11-27T11:30:00Z",
                "bandwidthSent24hBytes": 20 * 1024**2,
                "bandwidthSent30dBytes": 200 * 1024**2,
                "bandwidthPointCount": 10,
            }

        report = rr.run_readiness_check(
            site_root=fb_dir,
            firebase_project="scanstash-catalog-prod",
            firebase_site="scanstash-catalog-prod",
            service_account=sa,
            quota_mode="strict",
            fetch=_make_fetcher(r2_dir, fb_dir),
            cert_fetcher=ok_cert,
            token_minter=lambda *a, **k: "tok",
            metrics_fetcher=ok_metrics,
            now=self.NOW,
        )
        self.assertTrue(report["rollbackReady"])
        self.assertEqual(report["status"], "ready")
        summary = rr.format_markdown_summary(report)
        self.assertIn("Firebase Rollback Readiness: READY", summary)
        self.assertIn(build_id[:12], summary)
        self.assertIn("catalog.scan-stash.com", summary)

        # In advisory mode with 403 Monitoring error, rollbackReady MUST stay False (never false-green).
        def forbidden_metrics(**kwargs):
            raise HTTPError("https://monitoring.googleapis.com/v3/test", 403, "Forbidden", {}, io.BytesIO(b""))

        unverified = rr.run_readiness_check(
            site_root=fb_dir,
            firebase_project="scanstash-catalog-prod",
            firebase_site="scanstash-catalog-prod",
            service_account=sa,
            quota_mode="advisory",
            fetch=_make_fetcher(r2_dir, fb_dir),
            cert_fetcher=ok_cert,
            token_minter=lambda *a, **k: "tok",
            metrics_fetcher=forbidden_metrics,
            now=self.NOW,
        )
        self.assertFalse(unverified["rollbackReady"])
        self.assertFalse(unverified["hardFailed"])
        self.assertEqual(unverified["status"], "unverified")
        unverified_summary = rr.format_markdown_summary(unverified)
        self.assertIn("NOT READY (QUOTA UNVERIFIED)", unverified_summary)
        self.assertIn("roles/monitoring.viewer", unverified_summary)

    def test_all_four_backup_workflows_report_rollback_readiness_and_preserve_r2_isolation(self):
        for name in (
            "pokemon-catalog.yml",
            "one-piece-catalog.yml",
            "magic-catalog.yml",
            "yugioh-catalog.yml",
        ):
            with self.subTest(workflow=name):
                text = (WORKFLOWS / name).read_text(encoding="utf-8")
                self.assertIn("scripts/rollback_readiness.py", text)
                self.assertIn("--rollback-hostname catalog.scan-stash.com", text)
                self.assertIn("--report \"$RUNNER_TEMP/rollback-readiness.json\"", text)
                self.assertIn("--summary \"$GITHUB_STEP_SUMMARY\"", text)
                self.assertIn("Upload rollback readiness report", text)
                self.assertIn("**Rollback readiness: NOT READY**", text)

        rehearsal_wf = (WORKFLOWS / "r2-rollback-readiness.yml").read_text(encoding="utf-8")
        self.assertIn("workflow_dispatch:", rehearsal_wf)
        self.assertIn("scripts/catalog_roll_forward.py rehearse-recovery", rehearsal_wf)
        self.assertIn("scripts/rollback_readiness.py", rehearsal_wf)
        # Read-only workflow must not claim the Firebase deploy lock.
        self.assertNotIn("scanstash-catalog-production-hosting", rehearsal_wf)
        self.assertNotIn("POKEMON_CATALOG_SIGNING_KEY", rehearsal_wf)


if __name__ == "__main__":
    unittest.main()
