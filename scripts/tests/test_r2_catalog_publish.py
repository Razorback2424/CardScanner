import hashlib
from http.client import IncompleteRead
from io import BytesIO, StringIO
import json
from pathlib import Path
from ssl import SSLEOFError
import sys
import tempfile
import threading
import shutil
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import r2_catalog_publish as r2
import market_price_feeds as feeds
import market_price_v2 as v2

PUBLIC = "https://catalog-staging.example.test"


class PublicReadbackTests(unittest.TestCase):
    def test_retries_transient_http_and_transport_errors(self):
        transient_errors = (
            HTTPError(PUBLIC, 429, "Rate limited", {}, None),
            HTTPError(PUBLIC, 502, "Bad gateway", {}, None),
            URLError("Temporary name resolution failure"),
            TimeoutError(),
            ConnectionResetError(),
            IncompleteRead(b"partial"),
            SSLEOFError(8, "TLS connection closed during read"),
        )
        for error in transient_errors:
            with self.subTest(error=error), patch.object(r2, "build_opener") as make_opener, \
                    patch.object(r2.time, "sleep") as sleep, patch.object(r2.sys, "stderr", new_callable=StringIO):
                open_request = make_opener.return_value.open
                response = open_request.return_value.__enter__.return_value
                response.status = 200
                response.headers = {"Content-Type": "application/json"}
                if isinstance(error, (IncompleteRead, SSLEOFError)):
                    response.read.side_effect = [error, b"{}"]
                else:
                    open_request.side_effect = [error, open_request.return_value]
                    response.read.return_value = b"{}"

                self.assertEqual(r2.fetch_public(PUBLIC), (200, {"content-type": "application/json"}, b"{}"))
                self.assertEqual(open_request.call_count, 2)
                sleep.assert_called_once_with(1)

    def test_returns_404_without_retrying(self):
        with patch.object(r2, "build_opener") as make_opener, patch.object(r2.time, "sleep") as sleep:
            open_request = make_opener.return_value.open
            open_request.side_effect = HTTPError(PUBLIC, 404, "Not found", {}, None)

            self.assertEqual(r2.fetch_public(PUBLIC), (404, {}, b""))
            open_request.assert_called_once()
            sleep.assert_not_called()

    def test_stops_after_three_retries(self):
        with patch.object(r2, "build_opener") as make_opener, patch.object(r2.time, "sleep") as sleep, \
                patch.object(r2.sys, "stderr", new_callable=StringIO):
            open_request = make_opener.return_value.open
            open_request.side_effect = [HTTPError(PUBLIC, 503, "Unavailable", {}, None) for _ in range(4)]

            self.assertEqual(r2.fetch_public(PUBLIC), (503, {}, b""))
            self.assertEqual(open_request.call_count, 4)
            self.assertEqual([call.args for call in sleep.call_args_list], [(1,), (2,), (4,)])


class FakeBucket:
    """In-memory S3 bucket that serves its objects over a fake public host."""

    def __init__(self):
        self.objects = {}
        self.puts = []
        self.lock = threading.Lock()
        self.corrupt = set()

    def head(self, key):
        item = self.objects.get(key)
        if item is None:
            return None
        return {"sha256": item["sha256"], "content_type": item["content_type"],
                "cache_control": item["cache_control"]}

    def put(self, item):
        with self.lock:
            self.puts.append(item["key"])
            self.objects[item["key"]] = {"body": item["path"].read_bytes(), "sha256": item["sha256"],
                                         "content_type": item["content_type"],
                                         "cache_control": item["cache_control"]}

    def fetch(self, url):
        key = url[len(PUBLIC) + 1:].split("?", 1)[0]
        item = self.objects.get(key)
        if item is None:
            return 404, {}, b""
        body = b"corrupted" if key in self.corrupt else item["body"]
        return 200, {"content-type": item["content_type"], "cache-control": item["cache_control"]}, body


class R2CatalogPublishTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.site = Path(temp.name) / "site"
        self.rules = r2.HostingRules.load(ROOT / "firebase.json")
        files = {
            "v1/current.json": b'{"revision":2}',
            "v1/releases/1/catalog-release.json": b'{"revision":1}',
            "v1/releases/2/catalog-release.json": b'{"revision":2}',
            "one-piece/v1/current.json": b'{"revision":7}',
            "one-piece/v1/releases/7/catalog-release.json": b'{"revision":7}',
            "one-piece/v1/market-price-scope.json": b'{"groups":[1]}',
            "market-prices/v1/index.json": b'{"build":"b"}',
            "market-prices/v1/last-updated.txt": b"2026-11-26T20:05:59+0000\n",
            "market-prices/v1/tcgplayer/2/1110/prices": b'{"results":[]}',
            "market-prices/v1/tcgplayer/2/1110/products": b'{"results":[]}',
            ".DS_Store": b"ignored",
            "v1/.hidden/file.json": b"ignored",
        }
        for relative, body in files.items():
            path = self.site / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(body)
        self.bucket = FakeBucket()

    def run_publish(self, **options):
        objects = r2.plan(self.site, self.rules)
        return r2.publish(objects, self.bucket, PUBLIC, fetch=self.bucket.fetch, log=lambda _: None, **options)

    def test_headers_match_the_firebase_hosting_rules(self):
        expected = {
            "v1/current.json": ("application/json", "no-cache"),
            "v1/releases/2/catalog-release.json": ("application/json", "public,max-age=31536000,immutable"),
            "one-piece/v1/market-price-scope.json": ("application/json", "no-cache"),
            "market-prices/v1/index.json": ("application/json", "public,max-age=300"),
            "market-prices/v1/last-updated.txt": ("text/plain; charset=utf-8", "no-cache"),
            "market-prices/v1/tcgplayer/2/1110/prices": ("application/json; charset=utf-8", "public,max-age=300"),
        }
        for relative, headers in expected.items():
            self.assertEqual(self.rules.headers(relative), headers, relative)

    def test_ignored_and_reserved_paths_are_not_published(self):
        keys = {item["key"] for item in r2.plan(self.site, self.rules)}
        self.assertNotIn(".DS_Store", keys)
        self.assertNotIn("v1/.hidden/file.json", keys)
        self.assertTrue(self.rules.ignored("__/firebase/init.js"))
        self.assertTrue(self.rules.ignored("firebase.json"))

    def test_tiers_publish_in_order_with_the_marker_last(self):
        self.run_publish()
        order = [r2.tier(key, self.rules.headers(key)[1]) for key in self.bucket.puts]
        self.assertEqual(order, sorted(order))
        self.assertEqual(self.bucket.puts[-1], "market-prices/v1/last-updated.txt")
        pointer = self.bucket.puts.index("v1/current.json")
        self.assertLess(self.bucket.puts.index("v1/releases/2/catalog-release.json"), pointer)
        self.assertLess(self.bucket.puts.index("market-prices/v1/index.json"), pointer)

    def test_failed_readback_stops_before_pointers_and_marker(self):
        original_put = self.bucket.put

        def put_and_corrupt(item):
            original_put(item)
            if item["key"] == "market-prices/v1/tcgplayer/2/1110/prices":
                self.bucket.corrupt.add(item["key"])

        self.bucket.put = put_and_corrupt
        with self.assertRaisesRegex(r2.PublishError, "SHA-256 mismatch"):
            self.run_publish()
        self.assertNotIn("market-prices/v1/index.json", self.bucket.objects)
        self.assertNotIn("v1/current.json", self.bucket.objects)
        self.assertNotIn("market-prices/v1/last-updated.txt", self.bucket.objects)

    def test_rerun_is_a_no_op(self):
        first = self.run_publish()
        self.bucket.puts.clear()
        second = self.run_publish()
        self.assertEqual(self.bucket.puts, [])
        self.assertEqual(second["uploaded"], 0)
        self.assertEqual(second["unchanged"], first["uploaded"])

    def test_changed_header_is_republished_without_changing_bytes(self):
        self.run_publish()
        self.bucket.objects["v1/current.json"]["cache_control"] = "public,max-age=3600"
        self.bucket.puts.clear()
        self.run_publish()
        self.assertEqual(self.bucket.puts, ["v1/current.json"])

    def test_existing_immutable_object_with_different_bytes_is_refused(self):
        self.run_publish()
        key = "v1/releases/1/catalog-release.json"
        self.bucket.objects[key]["sha256"] = hashlib.sha256(b"other").hexdigest()
        self.bucket.puts.clear()
        with self.assertRaisesRegex(r2.PublishError, "Immutable object"):
            self.run_publish()
        self.assertEqual(self.bucket.puts, [])

    def test_dry_run_uploads_nothing(self):
        summary = self.run_publish(dry_run=True)
        self.assertEqual(self.bucket.puts, [])
        self.assertEqual(summary["uploaded"], len(r2.plan(self.site, self.rules)))

    def test_unclassified_mutable_path_is_refused(self):
        stray = self.site / "notes" / "readme.json"
        stray.parent.mkdir(parents=True)
        stray.write_bytes(b"{}")
        with self.assertRaises(r2.PublishError):
            r2.plan(self.site, self.rules)

    def test_readback_rejects_wrong_headers(self):
        self.run_publish()
        item = next(i for i in r2.plan(self.site, self.rules) if i["key"] == "v1/current.json")
        self.bucket.objects["v1/current.json"]["cache_control"] = "public,max-age=600"
        with self.assertRaisesRegex(r2.PublishError, "cache-control"):
            r2.verify_readback(item, PUBLIC, self.bucket.fetch, "n")


class AtomicPriceV2Tests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.rules = r2.HostingRules.load(ROOT / "firebase.json")
        self.bucket = FakeBucket()

    def fixture(self, name, marker="2026-11-26T20:05:59+00:00", price=12.34, *, omit=(), withdrawn=()):
        site = self.root / name
        old = site / feeds.NAMESPACE
        files = {"last-updated.txt": (marker + "\n").encode()}
        for category in (2, 3, 68, 71):
            if category in omit:
                continue
            for resource in ("products", "prices"):
                row = ({"productId": 123, "categoryId": category, "groupId": 1,
                        "name": "Fixture", "extendedData": []} if resource == "products" else
                       {"productId": 123, "subTypeName": "Normal", "marketPrice": price})
                files[f"tcgplayer/{category}/1/{resource}"] = feeds.packed(
                    {"success": True, "errors": [], "totalItems": 1, "results": [row],
                     "sourceBuild": marker, "sourceFetchedAt": marker})
        index = {"schemaVersion": 1, "sourceBuild": marker,
                 "files": [v2.entry(path, raw) for path, raw in sorted(files.items())]}
        files["index.json"] = feeds.packed(index)
        for path, raw in files.items():
            dest = old / path
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(raw)
        for game, (_, namespace) in feeds.CATALOG_NAMESPACES.items():
            scope = site / namespace / feeds.SCOPE_FILE
            scope.parent.mkdir(parents=True, exist_ok=True)
            lane = "Normal" if game == "one-piece" else "Unlimited"
            empty = game in withdrawn
            scope.write_bytes(feeds.packed({"schemaVersion": 1, "game": game,
                "revision": 7 if empty else None, "pointerSHA256": "b" * 64 if empty else None,
                "catalogSHA256": "a" * 64, "groups": [] if empty else [[1, [[123, [lane]]]]]}))
        pointer = v2.stage(site)
        return site, pointer

    def publish(self, site, **kwargs):
        return r2.publish(r2.plan(site, self.rules), self.bucket, PUBLIC,
                          fetch=self.bucket.fetch, log=lambda _: None, **kwargs)

    def test_primary_cli_publishes_with_only_r2_and_records_build_before_activation(self):
        site, pointer = self.fixture("primary", marker=feeds.stamp())
        shutil.rmtree(site / v2.V2)
        reads = []

        def scope_fetch(url, maximum, *, absent_ok=False):
            self.assertTrue(url.startswith(feeds.R2_ORIGIN + "/"), url)
            reads.append(url)
            if url.endswith("/current.json"):
                self.assertTrue(absent_ok)
                return None
            return (site / url.removeprefix(feeds.R2_ORIGIN + "/")).read_bytes()

        def publish(*args, **options):
            return real_publish(*args, **options, log=lambda _: None,
                                fetch=lambda url: self.bucket.fetch(PUBLIC + url.removeprefix(feeds.R2_ORIGIN)))

        real_publish = r2.publish
        with patch.object(r2, "AwsCliStore", return_value=self.bucket), patch.object(r2, "publish", side_effect=publish), \
                patch.object(r2, "confirm_r2_scopes", side_effect=lambda root: feeds.confirm_r2_scopes(root, scope_fetch)), \
                patch.object(feeds, "build_opener", side_effect=AssertionError("Unexpected network request")):
            self.assertEqual(r2.main(["--primary-prices", "--site", str(site), "--public-base", feeds.R2_ORIGIN,
                                     "--bucket", "fixture", "--account-id", "a" * 32]), 0)
        receipt = f"{r2.VERIFIED}{pointer['build']}.json"
        self.assertLess(self.bucket.puts.index(receipt), self.bucket.puts.index(v2.LATEST))
        self.assertEqual(self.bucket.objects[receipt]["body"], feeds.packed(pointer))
        self.assertEqual(self.bucket.objects[v2.LATEST]["body"], feeds.packed(pointer))
        self.assertEqual(self.bucket.puts[-1], feeds.NAMESPACE + "/last-updated.txt")
        self.assertTrue(all(key.startswith("market-prices/") for key in self.bucket.puts))
        self.assertEqual(len(reads), 2 * 2 * len(feeds.CATALOG_NAMESPACES))

    def test_interrupted_catalog_sync_can_reuse_the_scope_bound_to_active_catalog(self):
        site, pointer = self.fixture("prior")
        key = "one-piece/v1/market-price-scope.json"
        old = (site / key).read_bytes()
        newer = json.loads(old) | {"revision": 2, "pointerSHA256": "1" * 64}
        public = {
            key: feeds.packed(newer),
            v2.LATEST: feeds.packed(pointer),
            f"{v2.V2}/builds/{pointer['build']}/scopes/one-piece.json": old,
        }

        def fetch(url, maximum, *, absent_ok=False):
            self.assertTrue(url.startswith(feeds.R2_ORIGIN + "/"))
            key = url.removeprefix(feeds.R2_ORIGIN + "/")
            return public.get(key) if absent_ok else public[key]

        self.assertEqual(feeds.read_r2_scope("one-piece", "one-piece/v1", fetch), old)
        scope = f"{v2.V2}/builds/{pointer['build']}/scopes/one-piece.json"
        public[scope] = public[scope].replace(b'"Normal"', b'"Foil"')
        with self.assertRaisesRegex(ValueError, "failed its build checks"):
            feeds.read_r2_scope("one-piece", "one-piece/v1", fetch)

    def test_same_capture_same_build_and_coverage(self):
        first, a = self.fixture("a")
        second, b = self.fixture("b")
        self.assertEqual(a, b)
        for row in a["files"]:
            path = row["path"]
            self.assertEqual((first / v2.V2 / "builds" / a["build"] / path).read_bytes(),
                             (second / v2.V2 / "builds" / b["build"] / path).read_bytes())
        _, corrected = self.fixture("corrected", price=99)
        self.assertNotEqual(a["build"], corrected["build"])
        self.assertEqual(a["sourceBuild"], corrected["sourceBuild"])

    def test_activation_before_legacy_updates_and_idempotent_retry(self):
        site, pointer = self.fixture("a")
        self.publish(site)
        index = self.bucket.puts.index(v2.LATEST)
        self.assertTrue(all(key.startswith(v2.V2 + "/builds/") for key in self.bucket.puts[:index]))
        self.assertEqual(self.bucket.puts[-1], feeds.NAMESPACE + "/last-updated.txt")
        self.assertEqual(self.bucket.objects[v2.LATEST]["body"], feeds.packed(pointer))
        self.bucket.puts.clear()
        summary = self.publish(site)
        self.assertEqual(summary["uploaded"], 0)
        self.assertEqual(self.bucket.puts, [])

    def test_corrupt_immutable_readback_never_switches_pointer(self):
        old, pointer = self.fixture("old")
        self.publish(old)
        new, candidate = self.fixture("new", price=99)
        key = f"{v2.V2}/builds/{candidate['build']}/tcgplayer/3/1/prices"
        self.bucket.corrupt.add(key)
        with self.assertRaisesRegex(r2.PublishError, "SHA-256 mismatch"):
            self.publish(new, record_build=True)
        self.assertEqual(self.bucket.objects[v2.LATEST]["body"], feeds.packed(pointer))
        self.assertNotIn(f"{r2.VERIFIED}{candidate['build']}.json", self.bucket.objects)
        # Even if the failed attempt uploaded it, retry must reverify it.
        with self.assertRaisesRegex(r2.PublishError, "SHA-256 mismatch"):
            self.publish(new)
        self.bucket.corrupt.clear()
        self.publish(new)
        self.assertEqual(self.bucket.objects[v2.LATEST]["body"], feeds.packed(candidate))

    def test_v1_failure_does_not_break_v2_and_retry_repairs(self):
        old, _ = self.fixture("old")
        self.publish(old)
        new, pointer = self.fixture("new", price=99)
        key = feeds.NAMESPACE + "/tcgplayer/3/1/prices"
        self.bucket.corrupt.add(key)
        with self.assertRaisesRegex(r2.PublishError, "SHA-256 mismatch"):
            self.publish(new)
        self.assertEqual(self.bucket.objects[v2.LATEST]["body"], feeds.packed(pointer))
        self.bucket.corrupt.clear()
        self.publish(new, verify_all=True)
        self.assertEqual(self.bucket.objects[key]["body"], (new / key).read_bytes())

    def test_older_and_superseded_same_day_candidates_cannot_activate(self):
        new, pointer = self.fixture("new", marker="2026-11-27T20:05:59+00:00")
        self.publish(new)
        old, _ = self.fixture("old")
        with self.assertRaisesRegex(r2.PublishError, "older v2"):
            self.publish(old)
        same, _ = self.fixture("same", marker=pointer["sourceBuild"], price=99)
        def superseded():
            raise ValueError("Firebase changed")
        with self.assertRaisesRegex(ValueError, "Firebase changed"):
            self.publish(same, confirm_current=superseded)
        self.assertEqual(self.bucket.objects[v2.LATEST]["body"], feeds.packed(pointer))

    def test_missing_or_modified_staged_files_are_rejected(self):
        site, pointer = self.fixture("a")
        path = site / v2.V2 / "builds" / pointer["build"] / "tcgplayer/3/1/prices"
        raw = path.read_bytes()
        path.unlink()
        with self.assertRaisesRegex(r2.PublishError, "Incomplete"):
            self.publish(site)
        path.write_bytes(raw + b" ")
        with self.assertRaisesRegex(r2.PublishError, "hash/size mismatch"):
            self.publish(site)
        self.assertEqual(self.bucket.puts, [])

    def test_catalog_only_mirror_keeps_previous_v2_build(self):
        site, pointer = self.fixture("a")
        self.publish(site)
        catalog = self.root / "catalog" / "v1" / "current.json"
        catalog.parent.mkdir(parents=True)
        catalog.write_bytes(b"{}")
        self.publish(catalog.parents[1])
        self.assertEqual(self.bucket.objects[v2.LATEST]["body"], feeds.packed(pointer))
        self.assertTrue(all(f"{v2.V2}/builds/{pointer['build']}/{row['path']}" in self.bucket.objects
                            for row in pointer["files"]))

    def test_authorized_empty_scopes_can_publish_without_affecting_other_games(self):
        old, _ = self.fixture("old")
        self.publish(old)
        site, pointer = self.fixture("withdrawn", omit=(2, 68), withdrawn=("yugioh", "one-piece"))
        self.publish(site)
        self.assertEqual(self.bucket.objects[v2.LATEST]["body"], feeds.packed(pointer))
        paths = {row["path"] for row in pointer["files"]}
        self.assertIn("scopes/yugioh.json", paths)
        self.assertIn("scopes/one-piece.json", paths)
        self.assertTrue(any(path.startswith("tcgplayer/3/") for path in paths))
        self.assertTrue(any(path.startswith("tcgplayer/71/") for path in paths))
        self.assertFalse(any(path.startswith(("tcgplayer/2/", "tcgplayer/68/")) for path in paths))

    def test_missing_or_unexpected_scope_groups_are_refused(self):
        with self.assertRaisesRegex(ValueError, "authorized catalog scope: yugioh"):
            self.fixture("missing", omit=(2,))
        with self.assertRaisesRegex(ValueError, "authorized catalog scope: one-piece"):
            self.fixture("stray", withdrawn=("one-piece",))
        with self.assertRaisesRegex(ValueError, "no groups for category 3"):
            self.fixture("missing-pokemon", omit=(3,))

    def test_retry_repairs_corrupted_legacy_bytes_with_matching_metadata(self):
        site, pointer = self.fixture("old")
        self.publish(site)
        key = feeds.NAMESPACE + "/tcgplayer/3/1/prices"
        self.bucket.objects[key]["body"] = b"wrong bytes"
        self.bucket.puts.clear()
        result = self.publish(site)
        self.assertEqual(self.bucket.puts, [key])
        self.assertEqual(self.bucket.objects[key]["body"], (site / key).read_bytes())
        self.assertEqual(self.bucket.objects[v2.LATEST]["body"], feeds.packed(pointer))
        self.assertEqual(result["uploaded"], 1)
        self.assertEqual(result["unchanged"] + result["uploaded"], result["verified"])

    def test_retry_never_overwrites_corrupted_immutable_bytes(self):
        site, pointer = self.fixture("old")
        self.publish(site)
        key = f"{v2.V2}/builds/{pointer['build']}/tcgplayer/3/1/prices"
        self.bucket.objects[key]["body"] = b"wrong bytes"
        self.bucket.puts.clear()
        with self.assertRaisesRegex(r2.PublishError, "SHA-256 mismatch"):
            self.publish(site)
        self.assertEqual(self.bucket.puts, [])

    def test_pointer_preflight_and_readback_use_distinct_cache_keys(self):
        old, _ = self.fixture("old")
        self.publish(old)
        site, pointer = self.fixture("corrected", price=99)
        cache = {}
        pointer_urls = []

        def caching_fetch(url):
            if "/" + v2.LATEST + "?" in url:
                pointer_urls.append(url)
                if url not in cache:
                    cache[url] = self.bucket.fetch(url)
                return cache[url]
            return self.bucket.fetch(url)

        r2.publish(r2.plan(site, self.rules), self.bucket, PUBLIC, fetch=caching_fetch,
                   log=lambda _: None)
        self.assertEqual(len(pointer_urls), 2)
        self.assertNotEqual(*pointer_urls)
        self.assertEqual(self.bucket.objects[v2.LATEST]["body"], feeds.packed(pointer))

    def test_network_retries_and_confirmed_legacy_corruption_repair(self):
        site, _ = self.fixture("old")
        self.publish(site)
        key = feeds.NAMESPACE + "/tcgplayer/3/1/prices"
        self.bucket.puts.clear()
        self.bucket.objects[key]["body"] = b"wrong bytes"
        requests = []
        unavailable_reads = 5

        def open_request(request, timeout):
            nonlocal unavailable_reads
            url = request.full_url
            if "/" + key + "?" in url:
                requests.append(url)
                if unavailable_reads:
                    unavailable_reads -= 1
                    raise HTTPError(url, 503, "Unavailable", {}, None)
            status, headers, body = self.bucket.fetch(url)
            response = BytesIO(body)
            response.status = status
            response.headers = headers
            return response

        objects = r2.plan(site, self.rules)
        with patch.object(r2, "build_opener") as make_opener, patch.object(r2.time, "sleep") as sleep, \
                patch.object(r2.sys, "stderr", new_callable=StringIO):
            make_opener.return_value.open.side_effect = open_request
            with self.assertRaisesRegex(r2.PublishError, "HTTP 503"):
                r2.publish(objects, self.bucket, PUBLIC, log=lambda _: None)
            self.assertEqual(self.bucket.puts, [])
            self.assertEqual(len(requests), 4)

            requests.clear()
            r2.publish(objects, self.bucket, PUBLIC, log=lambda _: None)
            self.assertEqual(self.bucket.puts, [key])
            self.assertEqual(self.bucket.objects[key]["body"], (site / key).read_bytes())
            failed_url, retried_url, repaired_url = requests
            self.assertEqual(failed_url, retried_url)
            self.assertNotEqual(retried_url, repaired_url)
            self.assertEqual([call.args for call in sleep.call_args_list], [(1,), (2,), (4,), (1,)])

    def test_headers(self):
        self.assertEqual(self.rules.headers(v2.LATEST), ("application/json; charset=utf-8", "no-cache"))
        self.assertEqual(self.rules.headers(v2.V2 + "/builds/a/tcgplayer/3/1/prices"),
                         ("application/json; charset=utf-8", "public,max-age=31536000,immutable"))
        self.assertEqual(self.rules.headers(v2.V2 + "/builds/a/last-updated.txt"),
                         ("text/plain; charset=utf-8", "public,max-age=31536000,immutable"))

    def test_swift_v2_manifest_parity_fixture_matches_python_canonical_build_id(self):
        fixture_path = ROOT / "TradingCardScannerTests/Fixtures/TCGCSVPriceV2ManifestParity.json"
        raw = fixture_path.read_bytes()
        pointer = v2.validate_pointer(raw)
        recomputed = v2.pointer_for(pointer["sourceBuild"], pointer["files"])
        self.assertEqual(recomputed["build"], pointer["build"])
        self.assertEqual(feeds.packed(recomputed), raw)
        self.assertEqual(pointer["build"], "cc512246f9c9cc6ba430eb79dc898c7df19e0d5b9b233cdd785986c8ab7c0aee")


class PrimaryCatalogPublishTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.rules = r2.HostingRules.load(ROOT / "firebase.json")
        self.bucket = FakeBucket()

    def stage_catalog(self, name, namespace, revision, payload, *, previous_revision=None, previous_pointer=None,
                      extra_files=(), scope_groups=None):
        site = self.root / name / "site"
        release_dir = site / namespace / "releases" / str(revision)
        release_dir.mkdir(parents=True, exist_ok=True)
        (release_dir / "catalog-release.json").write_bytes(payload)
        for filename, body in extra_files:
            (release_dir / filename).write_bytes(body)
        (site / namespace / "current.json").write_bytes(payload)
        if namespace in r2.SCOPED_CATALOG_NAMESPACES:
            game = r2.SCOPED_CATALOG_NAMESPACES[namespace]
            lane = "Normal" if game == "one-piece" else "Unlimited"
            groups = [[1, [[123, [lane]]]]] if scope_groups is None else scope_groups
            scope_doc = {
                "schemaVersion": 1,
                "game": game,
                "revision": revision,
                "catalogSHA256": hashlib.sha256(payload).hexdigest(),
                "pointerSHA256": hashlib.sha256(payload).hexdigest(),
                "groups": groups,
            }
            (site / namespace / feeds.SCOPE_FILE).write_bytes(feeds.packed(scope_doc))
        metadata = r2.build_catalog_metadata(
            site, namespace, revision,
            previous_revision=previous_revision,
            previous_pointer_path=previous_pointer,
            rules=self.rules,
        )
        metadata_path = self.root / name / "catalog-publish-metadata.json"
        metadata_path.write_bytes(feeds.packed(metadata))
        return site, metadata, metadata_path

    def publish_catalog(self, site, metadata, **options):
        objects = r2.plan(site, self.rules)
        return r2.publish(objects, self.bucket, PUBLIC, fetch=self.bucket.fetch,
                          log=lambda _: None, catalog_metadata=metadata, **options)

    def test_primary_catalog_publishes_immutable_then_pointer_then_scope_and_keeps_history(self):
        rev1_site, rev1_meta, _ = self.stage_catalog("op-1", "one-piece/v1", 1, b'{"rev":1}')
        self.publish_catalog(rev1_site, rev1_meta)
        self.assertEqual(self.bucket.puts, [
            "one-piece/v1/releases/1/catalog-release.json",
            "one-piece/v1/current.json",
            "one-piece/v1/market-price-scope.json",
        ])

        rev2_site, rev2_meta, _ = self.stage_catalog(
            "op-2", "one-piece/v1", 2, b'{"rev":2}',
            previous_revision=1, previous_pointer=rev1_site / "one-piece/v1/current.json",
        )
        self.bucket.puts.clear()
        self.publish_catalog(rev2_site, rev2_meta)
        self.assertEqual(self.bucket.puts, [
            "one-piece/v1/releases/2/catalog-release.json",
            "one-piece/v1/current.json",
            "one-piece/v1/market-price-scope.json",
        ])
        # Historical revision 1 remains intact in R2.
        self.assertEqual(self.bucket.objects["one-piece/v1/releases/1/catalog-release.json"]["body"], b'{"rev":1}')
        self.assertEqual(self.bucket.objects["one-piece/v1/current.json"]["body"], b'{"rev":2}')

    def test_failed_pointer_upload_leaves_price_scope_untouched(self):
        rev1_site, rev1_meta, _ = self.stage_catalog("op-scope-1", "one-piece/v1", 1, b'{"rev":1}')
        self.publish_catalog(rev1_site, rev1_meta)
        original_scope = self.bucket.objects["one-piece/v1/market-price-scope.json"]["body"]
        rev2_site, rev2_meta, _ = self.stage_catalog(
            "op-scope-2", "one-piece/v1", 2, b'{"rev":2}',
            previous_revision=1, previous_pointer=rev1_site / "one-piece/v1/current.json",
        )
        real_put = self.bucket.put

        def fail_on_pointer_put(item):
            if item["key"] == "one-piece/v1/current.json":
                raise r2.PublishError("Simulated pointer upload failure")
            return real_put(item)

        self.bucket.puts.clear()
        with patch.object(self.bucket, "put", side_effect=fail_on_pointer_put):
            with self.assertRaisesRegex(r2.PublishError, "Simulated pointer upload failure"):
                self.publish_catalog(rev2_site, rev2_meta)
        # Immutable release uploaded, pointer failed, and scope was never written.
        self.assertEqual(self.bucket.puts, ["one-piece/v1/releases/2/catalog-release.json"])
        self.assertNotIn("one-piece/v1/market-price-scope.json", self.bucket.puts)
        self.assertEqual(self.bucket.objects["one-piece/v1/market-price-scope.json"]["body"], original_scope)
        self.assertEqual(self.bucket.objects["one-piece/v1/current.json"]["body"], b'{"rev":1}')

    def test_interrupted_immutable_upload_leaves_pointer_and_scope_untouched_and_retry_reverifies(self):
        rev1_site, rev1_meta, _ = self.stage_catalog("pk-1", "v1", 1, b'{"rev":1}',
                                                     extra_files=(("pokemon-catalog-snapshot.json", b'{"snap":1}'),))
        self.publish_catalog(rev1_site, rev1_meta)
        rev2_site, rev2_meta, _ = self.stage_catalog(
            "pk-2", "v1", 2, b'{"rev":2}',
            previous_revision=1, previous_pointer=rev1_site / "v1/current.json",
            extra_files=(("pokemon-catalog-snapshot.json", b'{"snap":2}'),),
        )
        self.bucket.corrupt.add("v1/releases/2/pokemon-catalog-snapshot.json")
        with self.assertRaisesRegex(r2.PublishError, "SHA-256 mismatch"):
            self.publish_catalog(rev2_site, rev2_meta)
        # Pointer must remain on rev 1.
        self.assertEqual(self.bucket.objects["v1/current.json"]["body"], b'{"rev":1}')
        # Retry must reverify immutable bytes even though metadata already matches, and never overwrite immutable.
        self.bucket.puts.clear()
        with self.assertRaisesRegex(r2.PublishError, "SHA-256 mismatch"):
            self.publish_catalog(rev2_site, rev2_meta)
        self.assertEqual(self.bucket.puts, [])
        self.assertEqual(self.bucket.objects["v1/current.json"]["body"], b'{"rev":1}')
        # Once readback returns intact bytes, retry activates rev 2 cleanly.
        self.bucket.corrupt.clear()
        self.publish_catalog(rev2_site, rev2_meta)
        self.assertEqual(self.bucket.objects["v1/current.json"]["body"], b'{"rev":2}')
        # Idempotent retry after pointer activation succeeds without re-uploading.
        self.bucket.puts.clear()
        summary = self.publish_catalog(rev2_site, rev2_meta)
        self.assertEqual(self.bucket.puts, [])
        self.assertEqual(summary["uploaded"], 0)
        self.assertEqual(summary["verified"], 3)

    def test_concurrent_catalog_advance_or_missing_predecessor_blocks_activation(self):
        rev1_site, rev1_meta, _ = self.stage_catalog("m-1", "magic/v1", 1, b'{"rev":1}')
        self.publish_catalog(rev1_site, rev1_meta)
        rev2a_site, rev2a_meta, _ = self.stage_catalog(
            "m-2a", "magic/v1", 2, b'{"rev":2,"a":1}',
            previous_revision=1, previous_pointer=rev1_site / "magic/v1/current.json",
        )
        rev2b_site, rev2b_meta, _ = self.stage_catalog(
            "m-2b", "magic/v1", 2, b'{"rev":2,"b":2}',
            previous_revision=1, previous_pointer=rev1_site / "magic/v1/current.json",
        )
        self.publish_catalog(rev2a_site, rev2a_meta)
        # Competing candidate built against rev 1 is refused before writing anything.
        self.bucket.puts.clear()
        with self.assertRaisesRegex(r2.PublishError, "changed before activation"):
            self.publish_catalog(rev2b_site, rev2b_meta)
        self.assertEqual(self.bucket.puts, [])
        self.assertEqual(self.bucket.objects["magic/v1/current.json"]["body"], b'{"rev":2,"a":1}')

        # Missing predecessor immutable release on R2 also blocks advancing to rev 3.
        rev3_site, rev3_meta, _ = self.stage_catalog(
            "m-3", "magic/v1", 3, b'{"rev":3}',
            previous_revision=2, previous_pointer=rev2a_site / "magic/v1/current.json",
        )
        del self.bucket.objects["magic/v1/releases/2/catalog-release.json"]
        with self.assertRaisesRegex(r2.PublishError, "Predecessor immutable release"):
            self.publish_catalog(rev3_site, rev3_meta)
        self.assertEqual(self.bucket.objects["magic/v1/current.json"]["body"], b'{"rev":2,"a":1}')

    def test_primary_catalog_rejects_foreign_namespaces_and_price_files(self):
        site, meta, meta_path = self.stage_catalog("pk-isolated", "v1", 1, b'{"rev":1}')
        # Stray file in another catalog namespace is rejected.
        foreign = site / "magic/v1/current.json"
        foreign.parent.mkdir(parents=True)
        foreign.write_bytes(b'{"rev":99}')
        with self.assertRaisesRegex(r2.PublishError, "staged files mismatch"):
            self.publish_catalog(site, meta)
        foreign.unlink()
        # Any market-prices file is refused at CLI level too.
        price = site / "market-prices/v1/last-updated.txt"
        price.parent.mkdir(parents=True)
        price.write_bytes(b"2026-11-27T00:00:00Z\n")
        with patch.object(r2.sys, "stderr", new_callable=StringIO) as stderr:
            code = r2.main(["--primary-catalog", "v1", "--catalog-metadata", str(meta_path),
                            "--site", str(site), "--public-base", feeds.R2_ORIGIN,
                            "--bucket", "fixture", "--account-id", "a" * 32])
        self.assertEqual(code, 1)
        self.assertIn("Only the primary price publisher", stderr.getvalue())

    def test_primary_catalog_cli_publishes_without_touching_firebase_or_prices(self):
        # Seed existing v2 prices in R2 bucket to confirm catalog publish leaves them untouched.
        price_helper = AtomicPriceV2Tests()
        price_helper.root = self.root
        price_helper.rules = self.rules
        price_helper.bucket = self.bucket
        price_site, price_pointer = price_helper.fixture("existing-prices")
        price_helper.publish(price_site)
        self.bucket.puts.clear()

        site, meta, meta_path = self.stage_catalog("pk-cli", "v1", 1, b'{"rev":1}')
        real_publish = r2.publish

        def publish_mock(*args, **options):
            return real_publish(*args, **options, log=lambda _: None,
                                fetch=lambda url: self.bucket.fetch(PUBLIC + url.removeprefix(feeds.R2_ORIGIN)))

        with patch.object(r2, "AwsCliStore", return_value=self.bucket), patch.object(r2, "publish", side_effect=publish_mock), \
                patch.object(feeds, "build_opener", side_effect=AssertionError("Unexpected Firebase or network call")):
            code = r2.main(["--primary-catalog", "v1", "--catalog-metadata", str(meta_path),
                            "--site", str(site), "--public-base", feeds.R2_ORIGIN,
                            "--bucket", "fixture", "--account-id", "a" * 32])
        self.assertEqual(code, 0)
        self.assertEqual(self.bucket.puts, ["v1/releases/1/catalog-release.json", "v1/current.json"])
        self.assertEqual(self.bucket.objects[v2.LATEST]["body"], feeds.packed(price_pointer))

    def test_write_catalog_metadata_cli_ignores_dotfiles_and_validates_scope_binding(self):
        site, _, _ = self.stage_catalog("magic-dot", "magic/v1", 1, b'{"rev":1}',
                                        extra_files=(("catalog-payload.json", b'{"rev":1}'), (".complete", b"complete\n")))
        out = self.root / "magic-dot" / "cli-meta.json"
        code = r2.main(["--site", str(site), "--write-catalog-metadata", str(out),
                        "--namespace", "magic/v1", "--revision", "1"])
        self.assertEqual(code, 0)
        doc = r2.validate_catalog_metadata(out.read_bytes(), expected_namespace="magic/v1")
        self.assertEqual(doc["immutableFiles"], [
            "magic/v1/releases/1/catalog-payload.json",
            "magic/v1/releases/1/catalog-release.json",
        ])


if __name__ == "__main__":
    unittest.main()
