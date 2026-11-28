"""Focused offline tests for Cloudflare targeted purge and canonical readback."""
from contextlib import redirect_stderr, redirect_stdout
import hashlib
from io import BytesIO, StringIO
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import cloudflare_cache as cf
import market_price_feeds as feeds
import market_price_v2 as v2
import r2_catalog_publish as r2
import test_r2_catalog_publish as publisher_tests

ZONE_ID = "0123456789abcdef0123456789abcdef"
SECRET_TOKEN = "cf-secret-canary-token-never-log"


class FakeOpener:
    def __init__(self, responses):
        self.responses = list(responses)
        self.requests = []

    def open(self, request, timeout=30):
        self.requests.append(request)
        nxt = self.responses.pop(0)
        if isinstance(nxt, Exception):
            raise nxt
        status, headers, body = nxt
        resp = BytesIO(body)
        resp.status = status
        resp.headers = headers
        return resp


class CloudflarePurgeTests(unittest.TestCase):
    def setUp(self):
        self.rules = r2.HostingRules.load(ROOT / "firebase.json")
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)

    def _plan_from(self, files):
        site = self.root / f"site-{len(list(self.root.iterdir()))}"
        for rel, body in files.items():
            path = site / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(body)
        return site, r2.plan(site, self.rules)

    def test_exact_purge_targets_for_every_catalog_and_price_publication(self):
        cases = (
            ("v1", {"v1/releases/2/catalog-release.json": b"{}", "v1/current.json": b"{}"},
             ["https://catalog-staging.scan-stash.com/v1/current.json"]),
            ("magic/v1", {"magic/v1/releases/1/catalog-release.json": b"{}", "magic/v1/current.json": b"{}"},
             ["https://catalog-staging.scan-stash.com/magic/v1/current.json"]),
            ("one-piece/v1", {
                "one-piece/v1/releases/7/catalog-release.json": b"{}",
                "one-piece/v1/market-price-scope.json": b"{}",
                "one-piece/v1/current.json": b"{}",
            }, [
                "https://catalog-staging.scan-stash.com/one-piece/v1/current.json",
                "https://catalog-staging.scan-stash.com/one-piece/v1/market-price-scope.json",
            ]),
            ("yugioh/v1", {
                "yugioh/v1/releases/1/catalog-release.json": b"{}",
                "yugioh/v1/releases/1/catalog.json": b"{}",
                "yugioh/v1/market-price-scope.json": b"{}",
                "yugioh/v1/current.json": b"{}",
            }, [
                "https://catalog-staging.scan-stash.com/yugioh/v1/current.json",
                "https://catalog-staging.scan-stash.com/yugioh/v1/market-price-scope.json",
            ]),
        )
        for ns, files, expected_urls in cases:
            with self.subTest(namespace=ns):
                _, objects = self._plan_from(files)
                items = cf.purge_items_for_plan(objects, feeds.R2_ORIGIN, primary_catalog=ns)
                urls = [cf.canonical_url(feeds.R2_ORIGIN, item["key"]) for item in items]
                self.assertEqual(urls, expected_urls)
                self.assertFalse(any("/releases/" in u for u in urls))

        # Primary prices purges only v2/latest.json, v1/last-updated.txt, v1/index.json.
        helper = publisher_tests.AtomicPriceV2Tests()
        helper.root = self.root
        helper.rules = self.rules
        helper.bucket = publisher_tests.FakeBucket()
        price_site, _ = helper.fixture("prices-plan")
        price_objects = [item for item in r2.plan(price_site, self.rules) if item["key"].startswith("market-prices/")]
        items = cf.purge_items_for_plan(price_objects, feeds.R2_ORIGIN, primary_prices=True)
        urls = [cf.canonical_url(feeds.R2_ORIGIN, item["key"]) for item in items]
        self.assertEqual(urls, [
            "https://catalog-staging.scan-stash.com/market-prices/v2/latest.json",
            "https://catalog-staging.scan-stash.com/market-prices/v1/last-updated.txt",
            "https://catalog-staging.scan-stash.com/market-prices/v1/index.json",
        ])

    def test_rejects_arbitrary_foreign_immutable_and_query_purge_urls(self):
        bad_urls = (
            "https://scan-stash.com/v1/current.json",
            "https://evil.example/v1/current.json",
            "http://catalog-staging.scan-stash.com/v1/current.json",
            "https://catalog-staging.scan-stash.com/v1/releases/1/catalog-release.json",
            "https://catalog-staging.scan-stash.com/market-prices/v2/builds/abc/index.json",
            "https://catalog-staging.scan-stash.com/v1/current.json?r2v=1",
            "https://catalog-staging.scan-stash.com/market-prices/v1/tcgplayer/3/1/prices",
        )
        for bad in bad_urls:
            with self.subTest(url=bad):
                with self.assertRaises(ValueError):
                    cf.validate_purge_url(bad)

    def test_purge_retries_429_with_clamped_retry_after_and_5xx_and_never_uses_purge_everything(self):
        url = "https://catalog-staging.scan-stash.com/v1/current.json"
        err_429 = HTTPError(url, 429, "Too Many Requests", {"Retry-After": "999"}, BytesIO(b"{}"))
        err_503 = HTTPError(url, 503, "Unavailable", {}, BytesIO(b"{}"))
        ok = (200, {"Content-Type": "application/json"}, json.dumps({"success": True, "result": {"id": ZONE_ID}}).encode())
        opener = FakeOpener([err_429, err_503, URLError("reset"), ok])
        sleeps = []
        with redirect_stderr(StringIO()):
            receipts = cf.purge_urls([url], ZONE_ID, SECRET_TOKEN, opener=opener, sleep=sleeps.append)
        self.assertEqual(len(receipts), 1)
        self.assertEqual(sleeps, [30, 2, 4])
        for req in opener.requests:
            body = json.loads(req.data.decode())
            self.assertEqual(body, {"files": [url]})
            self.assertNotIn("purge_everything", body)

    def test_purge_fails_immediately_on_permanent_auth_error_and_never_discloses_token(self):
        url = "https://catalog-staging.scan-stash.com/v1/current.json"
        err_403 = HTTPError(url, 403, "Forbidden", {},
                            BytesIO(json.dumps({"success": False, "errors": [{"code": 10000, "message": "Authentication error"}]}).encode()))
        opener = FakeOpener([err_403])
        sleeps = []
        stderr = StringIO()
        with redirect_stderr(stderr), self.assertRaises(cf.CacheVerificationError) as ctx:
            cf.purge_urls([url], ZONE_ID, SECRET_TOKEN, opener=opener, sleep=sleeps.append)
        self.assertEqual(sleeps, [])
        self.assertEqual(len(opener.requests), 1)
        self.assertNotIn(SECRET_TOKEN, str(ctx.exception))
        self.assertNotIn(SECRET_TOKEN, stderr.getvalue())

    def test_purge_rejects_malformed_json_and_success_false_and_exhausted_retries(self):
        url = "https://catalog-staging.scan-stash.com/v1/current.json"
        for body in (b"not-json", json.dumps({"success": False, "errors": [{"code": 99, "message": "bad"}]}).encode()):
            with self.subTest(body=body):
                opener = FakeOpener([(200, {}, body)])
                with self.assertRaises(cf.CacheVerificationError):
                    cf.purge_urls([url], ZONE_ID, SECRET_TOKEN, opener=opener, sleep=lambda _: None)
        opener = FakeOpener([HTTPError(url, 502, "Bad Gateway", {}, BytesIO(b"")) for _ in range(4)])
        with redirect_stderr(StringIO()), self.assertRaises(cf.CacheVerificationError):
            cf.purge_urls([url], ZONE_ID, SECRET_TOKEN, opener=opener, sleep=lambda _: None)


class CanonicalReadbackAndOrderingTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.rules = r2.HostingRules.load(ROOT / "firebase.json")
        self.bucket = publisher_tests.FakeBucket()

    def _stage_pokemon(self, name, rev, body):
        helper = publisher_tests.PrimaryCatalogPublishTests()
        helper.root = self.root
        helper.rules = self.rules
        helper.bucket = self.bucket
        return helper.stage_catalog(name, "v1", rev, body)

    def test_canonical_verification_rejects_cached_or_stale_mutable_pointers_and_bad_headers(self):
        site, _, _ = self._stage_pokemon("pk", 1, b'{"rev":1}')
        item = next(o for o in r2.plan(site, self.rules) if o["key"] == "v1/current.json")

        for good_status in ("BYPASS", "DYNAMIC"):
            with self.subTest(cf_status=good_status):
                results = cf.verify_canonical_objects(
                    [item], feeds.R2_ORIGIN,
                    fetch=lambda url: (200, {
                        "content-type": "application/json", "cache-control": "no-cache",
                        "cf-cache-status": good_status, "cf-ray": "abc-DEN",
                    }, b'{"rev":1}'),
                    retries=0,
                )
                self.assertEqual(results[0]["cfCacheStatus"], good_status)

        for bad_status in ("HIT", "STALE", "EXPIRED", "REVALIDATED", "UPDATING", ""):
            with self.subTest(bad_cf_status=bad_status):
                headers = {"content-type": "application/json", "cache-control": "no-cache"}
                if bad_status:
                    headers["cf-cache-status"] = bad_status
                with self.assertRaisesRegex(cf.CacheVerificationError, "cf-cache-status"):
                    cf.verify_canonical_objects(
                        [item], feeds.R2_ORIGIN,
                        fetch=lambda url, h=headers: (200, h, b'{"rev":1}'),
                        retries=0,
                    )

        # Legacy v1 index.json must also bypass edge cache so it never mixes builds with last-updated.txt.
        index_problems, _ = cf.check_canonical_response(
            "market-prices/v1/index.json",
            hashlib.sha256(b'{"schemaVersion":1}').hexdigest(),
            "application/json",
            "public,max-age=300",
            200,
            {"content-type": "application/json", "cache-control": "public,max-age=300", "cf-cache-status": "HIT"},
            b'{"schemaVersion":1}',
        )
        self.assertTrue(any("cf-cache-status" in p for p in index_problems))

        # Wrong bytes, wrong cache-control, wrong content-type are rejected.
        with self.assertRaisesRegex(cf.CacheVerificationError, "SHA-256 mismatch"):
            cf.verify_canonical_objects(
                [item], feeds.R2_ORIGIN,
                fetch=lambda url: (200, {"content-type": "application/json", "cache-control": "no-cache",
                                         "cf-cache-status": "BYPASS"}, b'{"rev":0}'),
                retries=0,
            )
        with self.assertRaisesRegex(cf.CacheVerificationError, "cache-control"):
            cf.verify_canonical_objects(
                [item], feeds.R2_ORIGIN,
                fetch=lambda url: (200, {"content-type": "application/json", "cache-control": "public,max-age=60",
                                         "cf-cache-status": "BYPASS"}, b'{"rev":1}'),
                retries=0,
            )
        with self.assertRaisesRegex(cf.CacheVerificationError, "content-type"):
            cf.verify_canonical_objects(
                [item], feeds.R2_ORIGIN,
                fetch=lambda url: (200, {"content-type": "text/plain", "cache-control": "no-cache",
                                         "cf-cache-status": "BYPASS"}, b'{"rev":1}'),
                retries=0,
            )

    def test_end_to_end_ordering_post_activation_failure_recovery_and_dry_run_safety(self):
        site, _, meta_path = self._stage_pokemon("pk-e2e", 1, b'{"rev":1}')
        report_path = self.root / "cache-report.json"
        events = []

        real_publish = r2.publish

        def tracked_publish(*args, **options):
            events.append("origin-publish")
            return real_publish(
                *args, **options, log=lambda _: None,
                fetch=lambda url: self.bucket.fetch(publisher_tests.PUBLIC + url.removeprefix(feeds.R2_ORIGIN)),
            )

        def tracked_purge(urls, zone_id, api_token, **kwargs):
            events.append(("purge", list(urls)))
            return [{"files": list(urls), "id": zone_id}]

        def tracked_canonical(items, public_base, **kwargs):
            events.append(("canonical", [i["key"] for i in items]))
            return [{"url": cf.canonical_url(public_base, i["key"]), "key": i["key"], "status": 200,
                     "cfCacheStatus": "BYPASS", "cacheControl": i["cache_control"]} for i in items]

        # 1. Dry-run never purges or mutates Cloudflare.
        with patch.object(r2, "AwsCliStore", return_value=self.bucket), \
                patch.object(r2, "publish", side_effect=tracked_publish), \
                patch.object(cf, "purge_urls", side_effect=AssertionError("Dry run must not purge")), \
                redirect_stdout(StringIO()):
            code = r2.main([
                "--primary-catalog", "v1", "--catalog-metadata", str(meta_path), "--site", str(site),
                "--public-base", feeds.R2_ORIGIN, "--bucket", "fixture", "--account-id", "a" * 32,
                "--cloudflare-zone-id", ZONE_ID, "--cloudflare-purge-token", SECRET_TOKEN,
                "--dry-run", "--cache-report", str(report_path),
            ])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(report_path.read_text())["cacheStatus"], "skipped")
        events.clear()

        # 2. Failed immutable upload prevents activation AND never purges.
        self.bucket.corrupt.add("v1/releases/1/catalog-release.json")
        with patch.object(r2, "AwsCliStore", return_value=self.bucket), \
                patch.object(r2, "publish", side_effect=tracked_publish), \
                patch.object(cf, "purge_urls", side_effect=AssertionError("Failed immutable must not purge")), \
                redirect_stderr(StringIO()):
            code = r2.main([
                "--primary-catalog", "v1", "--catalog-metadata", str(meta_path), "--site", str(site),
                "--public-base", feeds.R2_ORIGIN, "--bucket", "fixture", "--account-id", "a" * 32,
                "--cloudflare-zone-id", ZONE_ID, "--cloudflare-purge-token", SECRET_TOKEN,
            ])
        self.assertEqual(code, 1)
        self.assertNotIn("v1/current.json", self.bucket.objects)
        self.bucket.corrupt.clear()
        events.clear()

        # 3. Post-activation purge failure returns exit code 2, preserves active R2 pointer,
        #    records exact affected URLs, and never leaks token.
        stderr = StringIO()
        with patch.object(r2, "AwsCliStore", return_value=self.bucket), \
                patch.object(r2, "publish", side_effect=tracked_publish), \
                patch.object(cf, "purge_urls", side_effect=cf.CacheVerificationError(
                    "purge failed", stage="purge",
                    affected_urls=["https://catalog-staging.scan-stash.com/v1/current.json"])), \
                redirect_stdout(StringIO()), redirect_stderr(stderr):
            code = r2.main([
                "--primary-catalog", "v1", "--catalog-metadata", str(meta_path), "--site", str(site),
                "--public-base", feeds.R2_ORIGIN, "--bucket", "fixture", "--account-id", "a" * 32,
                "--cloudflare-zone-id", ZONE_ID, "--cloudflare-purge-token", SECRET_TOKEN,
                "--cache-report", str(report_path),
            ])
        self.assertEqual(code, r2.CACHE_VERIFICATION_FAILED_EXIT)
        self.assertEqual(self.bucket.objects["v1/current.json"]["body"], b'{"rev":1}')
        report = json.loads(report_path.read_text())
        self.assertTrue(report["originVerified"])
        self.assertEqual(report["cacheStatus"], "failed")
        self.assertEqual(report["affectedUrls"], ["https://catalog-staging.scan-stash.com/v1/current.json"])
        self.assertNotIn(SECRET_TOKEN, report_path.read_text())
        self.assertNotIn(SECRET_TOKEN, stderr.getvalue())

        # 4. Safe idempotent recovery (--recover-cache-only) uploads nothing, reverifies origin,
        #    purges, and passes canonical verification.
        self.bucket.puts.clear()
        events.clear()
        with patch.object(r2, "verify_existing_origin", side_effect=lambda objs, base: (
                events.append("origin-verify"),
                {"uploaded": 0, "unchanged": len(objs), "verified": len(objs)},
            )[1]), \
                patch.object(cf, "purge_urls", side_effect=tracked_purge), \
                patch.object(cf, "verify_canonical_objects", side_effect=tracked_canonical), \
                redirect_stdout(StringIO()):
            code = r2.main([
                "--primary-catalog", "v1", "--catalog-metadata", str(meta_path), "--site", str(site),
                "--public-base", feeds.R2_ORIGIN, "--recover-cache-only",
                "--cloudflare-zone-id", ZONE_ID, "--cloudflare-purge-token", SECRET_TOKEN,
                "--cache-report", str(report_path),
            ])
        self.assertEqual(code, 0)
        self.assertEqual(self.bucket.puts, [])
        self.assertEqual(events, [
            "origin-verify",
            ("purge", ["https://catalog-staging.scan-stash.com/v1/current.json"]),
            ("canonical", ["v1/current.json"]),
        ])
        self.assertEqual(json.loads(report_path.read_text())["cacheStatus"], "passed")

        # 5. Enforced mode without credentials fails with exit 2 (never false success).
        with patch.object(r2, "AwsCliStore", return_value=self.bucket), \
                patch.object(r2, "publish", side_effect=tracked_publish), \
                redirect_stdout(StringIO()), redirect_stderr(StringIO()):
            code = r2.main([
                "--primary-catalog", "v1", "--catalog-metadata", str(meta_path), "--site", str(site),
                "--public-base", feeds.R2_ORIGIN, "--bucket", "fixture", "--account-id", "a" * 32,
                "--cloudflare-zone-id", "", "--cloudflare-purge-token", "",
                "--require-cache-verification", "--cache-report", str(report_path),
            ])
        self.assertEqual(code, r2.CACHE_VERIFICATION_FAILED_EXIT)
        self.assertEqual(json.loads(report_path.read_text())["cacheStatus"], "failed")

        # 6. Partial credential configuration (zone ID set, token missing) fails closed even without --require.
        with patch.object(r2, "AwsCliStore", return_value=self.bucket), \
                patch.object(r2, "publish", side_effect=tracked_publish), \
                redirect_stdout(StringIO()), redirect_stderr(StringIO()):
            code = r2.main([
                "--primary-catalog", "v1", "--catalog-metadata", str(meta_path), "--site", str(site),
                "--public-base", feeds.R2_ORIGIN, "--bucket", "fixture", "--account-id", "a" * 32,
                "--cloudflare-zone-id", ZONE_ID, "--cloudflare-purge-token", "",
                "--cache-report", str(report_path),
            ])
        self.assertEqual(code, r2.CACHE_VERIFICATION_FAILED_EXIT)
        self.assertIn("Partial Cloudflare cache configuration", json.loads(report_path.read_text())["error"])


if __name__ == "__main__":
    unittest.main()
