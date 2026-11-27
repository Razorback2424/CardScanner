import hashlib
from pathlib import Path
import sys
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import r2_catalog_publish as r2
import market_price_feeds as feeds
import market_price_v2 as v2

PUBLIC = "https://catalog-staging.example.test"


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

    def fixture(self, name, marker="2026-11-26T20:05:59+00:00", price=12.34):
        site = self.root / name
        old = site / feeds.NAMESPACE
        files = {"last-updated.txt": (marker + "\n").encode()}
        for category in (2, 3, 68, 71):
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
            scope.write_bytes(feeds.packed({"schemaVersion": 1, "game": game, "revision": None,
                "pointerSHA256": None, "catalogSHA256": "a" * 64, "groups": [[1, [[123, [lane]]]]]}))
        pointer = v2.stage(site)
        return site, pointer

    def publish(self, site, **kwargs):
        return r2.publish(r2.plan(site, self.rules), self.bucket, PUBLIC,
                          fetch=self.bucket.fetch, log=lambda _: None, **kwargs)

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
            self.publish(new)
        self.assertEqual(self.bucket.objects[v2.LATEST]["body"], feeds.packed(pointer))
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

    def test_headers(self):
        self.assertEqual(self.rules.headers(v2.LATEST), ("application/json; charset=utf-8", "no-cache"))
        self.assertEqual(self.rules.headers(v2.V2 + "/builds/a/tcgplayer/3/1/prices"),
                         ("application/json; charset=utf-8", "public,max-age=31536000,immutable"))
        self.assertEqual(self.rules.headers(v2.V2 + "/builds/a/last-updated.txt"),
                         ("text/plain; charset=utf-8", "public,max-age=31536000,immutable"))


if __name__ == "__main__":
    unittest.main()
