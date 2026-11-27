import gzip
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import catalog_hosting_cache as hosting


class CatalogHostingCacheTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.site = self.root / "site"
        self.cache = self.root / "cache"
        self.work = self.root / "work"
        self.origin = {"v1": (b"pokemon-2", '"pokemon-2"'),
                       "one-piece/v1": (b"one-piece-2", '"one-piece-2"')}
        self.requests = []

    def fetch(self, namespace, tag, *, optional):
        self.requests.append((namespace, tag))
        if namespace not in self.origin:
            if optional:
                return 404, None, None
            raise HTTPError(namespace, 404, "Missing", {}, None)
        body, latest_tag = self.origin[namespace]
        return (304, None, tag) if tag == latest_tag else (200, body, latest_tag)

    def seal_verified_fixture(self):
        hosting.prepare(self.cache, self.site, self.work, get=self.fetch)
        for name, namespace in hosting.NAMESPACES.items():
            if namespace not in self.origin:
                continue
            root = self.site / namespace
            for revision in (1, 2):
                release = root / "releases" / str(revision) / "catalog-release.json"
                release.parent.mkdir(parents=True)
                release.write_bytes(f"{name}-{revision}".encode())
            (root / "current.json").write_bytes(self.origin[namespace][0])
            (self.work / f"{name}-verified-through").write_text("2\n")
        self.assertTrue(hosting.seal(self.cache, self.site, self.work))
        self.requests.clear()
        self.site = self.root / "redeploy-site"
        self.work = self.root / "redeploy-work"

    def test_unchanged_namespace_uses_conditional_get_and_reuses_every_revision(self):
        self.seal_verified_fixture()
        hosting.prepare(self.cache, self.site, self.work, get=self.fetch)
        self.assertIn(("v1", '"pokemon-2"'), self.requests)
        self.assertEqual((self.work / "pokemon-cached-through").read_text(), "2\n")
        self.assertEqual((self.work / "pokemon-current.json").read_bytes(), b"pokemon-2")
        self.assertEqual((self.site / "v1/releases/1/catalog-release.json").read_bytes(), b"pokemon-1")
        self.assertEqual((self.site / "v1/releases/2/catalog-release.json").read_bytes(), b"pokemon-2")
        for name in ("pokemon", "one-piece"):
            (self.work / f"{name}-verified-through").write_text("2\n")
        self.assertEqual(hosting.seal(self.cache, self.site, self.work), "")

    def test_explicit_reconciliation_rechecks_history_even_with_unchanged_pointer(self):
        self.seal_verified_fixture()
        hosting.prepare(self.cache, self.site, self.work, get=self.fetch, reconcile_history=True)
        self.assertIn(("v1", None), self.requests)
        self.assertFalse((self.work / "pokemon-cached-through").exists())
        for name, namespace in hosting.NAMESPACES.items():
            if namespace not in self.origin:
                continue
            root = self.site / namespace
            for revision in (1, 2):
                release = root / "releases" / str(revision) / "catalog-release.json"
                release.parent.mkdir(parents=True)
                release.write_bytes(f"{name}-{revision}".encode())
            (root / "current.json").write_bytes(self.origin[namespace][0])
        hosting.confirm(self.work, self.site, get=self.fetch)
        (self.site / "v1/releases/1/catalog-release.json").unlink()
        with self.assertRaisesRegex(ValueError, "lost or changed"):
            hosting.confirm(self.work, self.site, get=self.fetch)

    def test_changed_namespace_reuses_old_files_while_other_pointer_returns_304(self):
        self.seal_verified_fixture()
        self.origin["one-piece/v1"] = (b"one-piece-3", '"one-piece-3"')
        hosting.prepare(self.cache, self.site, self.work, get=self.fetch)
        self.assertIn(("one-piece/v1", '"one-piece-2"'), self.requests)
        self.assertEqual((self.work / "one-piece-current.json").read_bytes(), b"one-piece-3")
        self.assertEqual((self.work / "one-piece-cached-through").read_text(), "2\n")
        self.assertEqual((self.site / "one-piece/v1/releases/1/catalog-release.json").read_bytes(), b"one-piece-1")
        self.assertEqual((self.work / "pokemon-current.json").read_bytes(), b"pokemon-2")

    def test_missing_or_corrupt_cache_files_require_an_unconditional_restore(self):
        self.seal_verified_fixture()
        (self.cache / "site/v1/releases/1/catalog-release.json").unlink()
        (self.cache / "site/one-piece/v1/current.json").write_bytes(b"corrupt")
        hosting.prepare(self.cache, self.site, self.work, get=self.fetch)
        self.assertIn(("v1", None), self.requests)
        self.assertIn(("one-piece/v1", None), self.requests)
        self.assertFalse((self.work / "pokemon-cached-through").exists())
        self.assertFalse((self.work / "one-piece-cached-through").exists())
        self.assertFalse(self.site.exists())

    def test_recheck_rejects_a_pointer_change_during_restoration(self):
        self.seal_verified_fixture()
        hosting.prepare(self.cache, self.site, self.work, get=self.fetch)
        hosting.confirm(self.work, self.site, get=self.fetch)
        self.origin["v1"] = (b"pokemon-3", '"pokemon-3"')
        with self.assertRaisesRegex(ValueError, "changed during restoration"):
            hosting.confirm(self.work, self.site, get=self.fetch)

    def test_r2_catalog_sync_requires_current_scopes_and_catalog_pointers(self):
        self.seal_verified_fixture()
        hosting.prepare(self.cache, self.site, self.work, get=self.fetch)
        controls = {
            "/one-piece/v1/market-price-scope.json": b"One Piece scope",
            "/yugioh/v1/market-price-scope.json": b"Yu-Gi-Oh scope",
        }
        for relative, value in controls.items():
            path = self.site / relative.lstrip("/")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(value)

        def fetch(url, limit):
            parsed = urlsplit(url)
            self.assertEqual(f"{parsed.scheme}://{parsed.netloc}", hosting.ORIGIN)
            self.assertTrue(parsed.query.startswith("r2v="))
            self.assertLessEqual(len(controls[parsed.path]), limit)
            return controls[parsed.path]

        self.requests.clear()
        hosting.confirm_catalog_mirror_candidate(self.work, self.site, fetch=fetch, get=self.fetch)
        self.assertIn(("one-piece/v1", '"one-piece-2"'), self.requests)
        for path, original in controls.copy().items():
            with self.subTest(path=path):
                controls[path] = b"new publication"
                with self.assertRaisesRegex(ValueError, "no longer matches"):
                    hosting.confirm_catalog_mirror_candidate(self.work, self.site, fetch=fetch, get=self.fetch)
                controls[path] = original

        # Catalog publication must observe the same approved pointer.
        self.origin["v1"] = (b"pokemon-3", '"pokemon-3"')
        with self.assertRaisesRegex(ValueError, "Production v1 changed"):
            hosting.confirm_catalog_mirror_candidate(self.work, self.site, fetch=fetch, get=self.fetch)

    def test_recheck_refuses_to_deploy_a_previously_verified_but_now_missing_revision(self):
        self.seal_verified_fixture()
        hosting.prepare(self.cache, self.site, self.work, get=self.fetch)
        (self.site / "v1/releases/1/catalog-release.json").unlink()
        with self.assertRaisesRegex(ValueError, "lost or changed"):
            hosting.confirm(self.work, self.site, get=self.fetch)

    def test_previous_namespace_disappearance_does_not_drop_history(self):
        self.seal_verified_fixture()
        del self.origin["one-piece/v1"]
        with self.assertRaises(HTTPError):
            hosting.prepare(self.cache, self.site, self.work, get=self.fetch)

    def test_http_sends_the_etag_and_reads_compressed_pointers(self):
        response = io.BytesIO(gzip.compress(b"validated signed pointer fixture"))
        response.status = 200
        response.headers = {"Content-Encoding": "gzip", "ETag": '"fresh"'}
        with patch("catalog_hosting_cache.build_opener") as opener:
            opener.return_value.open.return_value = response
            self.assertEqual(hosting.get_pointer("v1", '"old"', optional=False),
                             (200, b"validated signed pointer fixture", '"fresh"'))
            request = opener.return_value.open.call_args.args[0]
            self.assertEqual(request.get_header("If-none-match"), '"old"')
            self.assertEqual(request.get_header("Cache-control"), "no-cache")

    def test_get_pointer_supports_r2_origin_with_cache_busting_and_rejects_unknown_origin(self):
        response = io.BytesIO(b"r2 pointer")
        response.status = 200
        response.headers = {"Content-Encoding": "identity", "ETag": '"r2-etag"'}
        with patch("catalog_hosting_cache.build_opener") as opener:
            opener.return_value.open.return_value = response
            self.assertEqual(
                hosting.get_pointer("v1", '"old"', optional=False, origin=hosting.R2_ORIGIN, fresh=True),
                (200, b"r2 pointer", '"r2-etag"'),
            )
            request = opener.return_value.open.call_args.args[0]
            self.assertTrue(request.full_url.startswith(f"{hosting.R2_ORIGIN}/v1/current.json?r2v="))
        with self.assertRaisesRegex(ValueError, "Unexpected catalog restore origin"):
            hosting.get_pointer("v1", None, optional=False, origin="https://unapproved.example.test")

    def test_verify_firebase_catalogs_checks_pointers_scopes_and_immutable_headers(self):
        files = {
            "v1/current.json": (b'{"rev":2}', {"cache-control": "no-cache"}),
            "v1/releases/2/catalog-release.json": (b'{"rev":2}', {"cache-control": "public,max-age=31536000,immutable"}),
            "v1/releases/2/pokemon-catalog-snapshot.json": (b'{"snap":2}', {"cache-control": "public,max-age=31536000,immutable"}),
            "one-piece/v1/market-price-scope.json": (b'{"scope":"op"}', {"cache-control": "no-cache"}),
            "yugioh/v1/market-price-scope.json": (b'{"scope":"ygo"}', {"cache-control": "no-cache"}),
        }
        for rel, (body, _) in files.items():
            path = self.site / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(body)

        def fetch(url, limit):
            parsed = urlsplit(url)
            self.assertEqual(f"{parsed.scheme}://{parsed.netloc}", hosting.ORIGIN)
            self.assertTrue(parsed.query.startswith("fbv="))
            return files[parsed.path.lstrip("/")]

        hosting.verify_firebase_catalogs(self.site, namespace="v1", revision=2, fetch=fetch)
        files["v1/releases/2/catalog-release.json"] = (b'{"rev":2}', {"cache-control": "no-cache"})
        with self.assertRaisesRegex(ValueError, "lacks immutable cache header"):
            hosting.verify_firebase_catalogs(self.site, namespace="v1", revision=2, fetch=fetch)
        files["v1/releases/2/catalog-release.json"] = (b'{"rev":1}', {"cache-control": "public,max-age=31536000,immutable"})
        with self.assertRaisesRegex(ValueError, "bytes differ"):
            hosting.verify_firebase_catalogs(self.site, namespace="v1", revision=2, fetch=fetch)

        # Transient post-deploy propagation lag retries with distinct cache-busting nonces.
        attempts_seen = []
        files["v1/releases/2/catalog-release.json"] = (b'{"rev":2}', {"cache-control": "public,max-age=31536000,immutable"})

        def flaky_fetch(url, limit):
            parsed = urlsplit(url)
            rel = parsed.path.lstrip("/")
            if rel == "v1/current.json":
                attempts_seen.append(parsed.query)
                if len(attempts_seen) == 1:
                    return b'{"rev":1}', {"cache-control": "no-cache"}
            return files[rel]

        sleeps = []
        with patch.object(hosting.sys, "stderr", new_callable=io.StringIO):
            hosting.verify_firebase_catalogs(self.site, namespace="v1", revision=2,
                                             fetch=flaky_fetch, attempts=3, sleep=sleeps.append)
        self.assertEqual(len(attempts_seen), 2)
        self.assertNotEqual(attempts_seen[0], attempts_seen[1])
        self.assertEqual(sleeps, [1])


if __name__ == "__main__":
    unittest.main()
