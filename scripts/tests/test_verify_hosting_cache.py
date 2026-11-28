"""Focused offline tests for static and live Cloudflare/Firebase cache verification."""
import base64
import copy
import hashlib
from io import BytesIO
import json
from pathlib import Path
import sys
import tempfile
import unittest
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import market_price_feeds as feeds
import market_price_v2 as v2
import r2_catalog_publish as r2
import verify_hosting_cache as verify


def _signed_envelope(revision, extra=None):
    payload = {"revision": revision}
    if extra:
        payload.update(extra)
    encoded = base64.urlsafe_b64encode(feeds.packed(payload)).decode().rstrip("=")
    return feeds.packed({"keyID": "fixture", "payload": encoded, "signature": "sig"})


class StaticHostingCacheVerificationTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)

    def test_repository_firebase_and_cloudflare_specs_pass_static_checks(self):
        summary = verify.verify_static(ROOT / "firebase.json", ROOT / "Config/Cloudflare/catalog-cache-rules.json")
        self.assertEqual(summary["firebase"], "valid")
        self.assertEqual(summary["cloudflareRules"], "valid")
        self.assertGreaterEqual(summary["verifiedPaths"], 20)

    def test_rejects_zero_second_error_ttl_reordered_bypass_or_premature_production_activation(self):
        spec = json.loads((ROOT / "Config/Cloudflare/catalog-cache-rules.json").read_text())

        # 1. Zero-second status_code_ttl (revalidation) instead of -1 (no-store) is rejected.
        bad_ttl = copy.deepcopy(spec)
        bad_ttl["staging"]["rules"][0]["action_parameters"]["edge_ttl"]["status_code_ttl"][0]["value"] = 0
        p1 = self.root / "bad-ttl.json"
        p1.write_text(json.dumps(bad_ttl))
        with self.assertRaisesRegex(ValueError, "must use -1"):
            verify.verify_static(ROOT / "firebase.json", p1)

        # 2. Putting verification nonce bypass BEFORE immutable rule violates precedence.
        reordered = copy.deepcopy(spec)
        reordered["staging"]["rules"].insert(0, reordered["staging"]["rules"].pop())
        p2 = self.root / "reordered.json"
        p2.write_text(json.dumps(reordered))
        with self.assertRaisesRegex(ValueError, "unexpected rule IDs or order"):
            verify.verify_static(ROOT / "firebase.json", p2)

        # 3. Activating production cutover template prematurely is rejected.
        prod_on = copy.deepcopy(spec)
        prod_on["production_cutover_template"]["activated"] = True
        p3 = self.root / "prod-on.json"
        p3.write_text(json.dumps(prod_on))
        with self.assertRaisesRegex(ValueError, "activated=false"):
            verify.verify_static(ROOT / "firebase.json", p3)

        # 4. Removing Firebase Functions or Firestore config is rejected.
        fb = json.loads((ROOT / "firebase.json").read_text())
        del fb["firestore"]
        p4 = self.root / "bad-fb.json"
        p4.write_text(json.dumps(fb))
        with self.assertRaisesRegex(ValueError, "Firestore"):
            verify.verify_static(p4, ROOT / "Config/Cloudflare/catalog-cache-rules.json")


class LiveHostingCacheVerificationTests(unittest.TestCase):
    def setUp(self):
        self.rules = r2.HostingRules.load(ROOT / "firebase.json")
        self.origin = feeds.R2_ORIGIN
        self.objects = {}
        self.counts = {}
        self._seed_fixture_site()

    def _put(self, key, body):
        ctype, ccontrol = self.rules.headers(key)
        self.objects[key] = {
            "body": body,
            "content_type": ctype,
            "cache_control": ccontrol,
            "etag": f'"{hashlib.sha256(body).hexdigest()[:16]}"',
        }

    def _seed_fixture_site(self):
        pk = _signed_envelope(26)
        op = _signed_envelope(7)
        self._put("v1/current.json", pk)
        self._put("v1/releases/26/catalog-release.json", pk)
        self._put("one-piece/v1/current.json", op)
        self._put("one-piece/v1/releases/7/catalog-release.json", op)
        for game, (_, ns) in feeds.CATALOG_NAMESPACES.items():
            scope = feeds.packed({
                "schemaVersion": 1, "game": game, "revision": 7 if game == "one-piece" else None,
                "catalogSHA256": "a" * 64, "pointerSHA256": hashlib.sha256(op).hexdigest() if game == "one-piece" else None,
                "groups": [[1, [[123, ["Normal" if game == "one-piece" else "Unlimited"]]]]],
            })
            self._put(f"{ns}/{feeds.SCOPE_FILE}", scope)

        marker = "2026-11-27T12:00:00+00:00"
        v1_files = {
            "last-updated.txt": (marker + "\n").encode(),
            "tcgplayer/3/1/products": feeds.packed({"success": True, "errors": [], "totalItems": 1,
                "results": [{"productId": 123, "categoryId": 3, "groupId": 1, "name": "Card", "extendedData": []}],
                "sourceBuild": marker, "sourceFetchedAt": marker}),
            "tcgplayer/3/1/prices": feeds.packed({"success": True, "errors": [], "totalItems": 1,
                "results": [{"productId": 123, "subTypeName": "Normal", "marketPrice": 5.0}],
                "sourceBuild": marker, "sourceFetchedAt": marker}),
        }
        v1_index = feeds.packed({"schemaVersion": 1, "sourceBuild": marker,
                                 "files": [v2.entry(p, raw) for p, raw in sorted(v1_files.items())]})
        self._put("market-prices/v1/index.json", v1_index)
        for p, raw in v1_files.items():
            self._put(f"market-prices/v1/{p}", raw)

        v2_files = {
            **v1_files,
            "index.json": v1_index,
            "scopes/one-piece.json": self.objects["one-piece/v1/market-price-scope.json"]["body"],
            "scopes/yugioh.json": self.objects["yugioh/v1/market-price-scope.json"]["body"],
        }
        pointer = v2.pointer_for(marker, [v2.entry(p, raw) for p, raw in v2_files.items()])
        raw_pointer = feeds.packed(pointer)
        build = pointer["build"]
        self._put(v2.LATEST, raw_pointer)
        self._put(f"{v2.V2}/verified-builds/{build}.json", raw_pointer)
        for p, raw in v2_files.items():
            self._put(f"{v2.V2}/builds/{build}/{p}", raw)

    def _fetch(self, url, *, extra_headers=None, force_cf=None):
        key = urlsplit(url).path.lstrip("/")
        self.counts[key] = self.counts.get(key, 0) + 1
        obj = self.objects.get(key)
        if obj is None:
            cf_status = (force_cf or {}).get(key, "DYNAMIC")
            return 404, {"cf-cache-status": cf_status, "cf-ray": "test-DEN"}, b""
        if extra_headers and extra_headers.get("If-None-Match") == obj["etag"]:
            return 304, {"cache-control": obj["cache_control"], "etag": obj["etag"],
                         "cf-cache-status": "BYPASS", "cf-ray": "test-DEN"}, b""
        if obj["cache_control"] == "no-cache" or key.startswith("market-prices/v1/"):
            cf_status = (force_cf or {}).get(key, "BYPASS")
        else:
            cf_status = (force_cf or {}).get(key, "MISS" if self.counts[key] == 1 else "HIT")
        headers = {
            "content-type": obj["content_type"],
            "cache-control": obj["cache_control"],
            "etag": obj["etag"],
            "cf-cache-status": cf_status,
            "cf-ray": "test-DEN",
        }
        if cf_status == "HIT":
            headers["age"] = "12"
        return 200, headers, obj["body"]

    def test_live_verification_succeeds_with_dynamic_discovery_and_missing_object_probe(self):
        uploaded_keys = []
        deleted_keys = []

        def put_obj(key, body, ctype, ccontrol, sha):
            uploaded_keys.append(key)
            self.objects[key] = {"body": body, "content_type": ctype, "cache_control": ccontrol, "etag": '"probe"'}

        def del_obj(key):
            deleted_keys.append(key)
            self.objects.pop(key, None)

        report = verify.verify_live(
            self.origin, fetch=self._fetch, probe_missing=True,
            put_object=put_obj, delete_object=del_obj, sleep=lambda _: None,
        )
        self.assertGreaterEqual(len(report["immutable"]), 5)
        self.assertGreaterEqual(len(report["mutable"]), 6)
        self.assertEqual(len(report["legacyV1"]), 2)
        self.assertTrue(report["negativeCacheProbe"]["cleanedUp"])
        self.assertEqual(uploaded_keys, deleted_keys)
        self.assertTrue(uploaded_keys[0].startswith(verify.PROBE_PREFIX))
        # Verify conditional 304 revalidation was exercised on mutable pointers.
        self.assertTrue(any(row["conditionalRevalidation"]["status"] == 304 for row in report["mutable"]))

    def test_live_verification_rejects_cached_mutable_pointer_legacy_v1_and_negative_cached_404(self):
        with self.assertRaisesRegex(ValueError, "not bypassed"):
            verify.verify_live(
                self.origin,
                fetch=lambda url, extra_headers=None: self._fetch(
                    url, extra_headers=extra_headers, force_cf={"v1/current.json": "HIT"}),
                sleep=lambda _: None,
            )

        with self.assertRaisesRegex(ValueError, "Legacy v1 resource was not bypassed"):
            verify.verify_live(
                self.origin,
                fetch=lambda url, extra_headers=None: self._fetch(
                    url, extra_headers=extra_headers, force_cf={"market-prices/v1/tcgplayer/3/1/prices": "HIT"}),
                sleep=lambda _: None,
            )

        # Negative caching before upload is detected and no upload occurs.
        with self.assertRaisesRegex(ValueError, "Negative caching detected"):
            verify.run_negative_cache_probe(
                self.origin,
                lambda *args: self.fail("Should not upload if 404 is already HIT"),
                lambda *args: None,
                fetch=lambda url: (404, {"cf-cache-status": "HIT", "cf-ray": "test-DEN"}, b""),
                sleep=lambda _: None,
            )

        # Negative cache masking newly uploaded object still cleans up the diagnostic key.
        cleaned = []
        calls = {"n": 0}

        def masked_fetch(url):
            calls["n"] += 1
            if calls["n"] <= 2:
                return 404, {"cf-cache-status": "DYNAMIC"}, b""
            return 404, {"cf-cache-status": "HIT"}, b""

        with self.assertRaisesRegex(ValueError, "Negative cache masked"):
            verify.run_negative_cache_probe(
                self.origin,
                lambda *args: None,
                cleaned.append,
                fetch=masked_fetch,
                retries=1,
                sleep=lambda _: None,
            )
        self.assertEqual(len(cleaned), 1)

        # Missing-object probe is refused on production hostname.
        with self.assertRaisesRegex(ValueError, "staging origin"):
            verify.run_negative_cache_probe("https://catalog.scan-stash.com", lambda *a: None, lambda *a: None)

    def test_read_only_cloudflare_rules_inspection_detects_drift_and_never_leaks_token(self):
        spec = json.loads((ROOT / "Config/Cloudflare/catalog-cache-rules.json").read_text())["staging"]["rules"]
        zone = "0123456789abcdef0123456789abcdef"
        read_token = "cf-readonly-canary-token"

        class Opener:
            def __init__(self, rules_payload):
                self.payload = rules_payload

            def open(self, req, timeout=30):
                self.assert_req = req
                resp = BytesIO(json.dumps({"success": True, "result": {"rules": self.payload}}).encode())
                resp.status = 200
                return resp

        result = verify.inspect_deployed_cloudflare_rules(zone, read_token, opener=Opener(spec))
        self.assertEqual(result["matchedRuleCount"], 4)

        drifted = copy.deepcopy(spec)
        drifted[0]["action_parameters"]["edge_ttl"]["status_code_ttl"][0]["value"] = 0
        with self.assertRaises(ValueError) as ctx:
            verify.inspect_deployed_cloudflare_rules(zone, read_token, opener=Opener(drifted))
        self.assertNotIn(read_token, str(ctx.exception))

        # A catch-all zone rule without http.host placed after our staging rules is rejected.
        with_catchall = copy.deepcopy(spec) + [{
            "id": "zone-catchall", "description": "Catch-all override", "action": "set_cache_settings",
            "enabled": True, "expression": 'starts_with(http.request.uri.path, "/")',
            "action_parameters": {"cache": True},
        }]
        with self.assertRaisesRegex(ValueError, "Overlapping zone Cache Rule"):
            verify.inspect_deployed_cloudflare_rules(zone, read_token, opener=Opener(with_catchall))


if __name__ == "__main__":
    unittest.main()
