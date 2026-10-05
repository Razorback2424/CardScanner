"""Exercise namespace preservation without a network or a production key.

Signature validation is covered by the publisher's actual cryptographic tests.
This harness verifies routing, failure propagation and immutable restoration.
"""
import base64
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class CatalogHostingRestoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        source = Path(__file__).resolve().parents[1]
        for name in ("restore_catalog_hosting_site.sh", "one_piece_pinned_keys.py"):
            shutil.copy(source / name, self.root / "scripts" / name)
        (self.root / "Config").mkdir()
        key = base64.b64encode(bytes(range(32))).decode()
        (self.root / "Config/OnePieceCatalogProduction.xcconfig").write_text(
            f"ONE_PIECE_CATALOG_PINNED_KEYS = one-piece-test:{key}\n")
        (self.root / "bin").mkdir()
        self.environment = os.environ | {"PATH": str(self.root / "bin") + os.pathsep + os.environ["PATH"],
                                         "RUNNER_TEMP": str(self.root), "POINTER_STATUS": "200"}
        self.tool("curl", """#!/usr/bin/env python3
import os, pathlib, sys
a=sys.argv[1:]; url=a[-1]; output=pathlib.Path(a[a.index('--output')+1])
status=os.environ.get('POINTER_STATUS','200') if url.endswith('current.json') else '200'
output.write_text('2' if url.endswith('current.json') or '/2/' in url else '1')
print(status,end='')
""")
        self.tool("swift", """#!/usr/bin/env python3
import os, pathlib, sys
a=sys.argv[1:]
assert 'one-piece-catalog-publisher' in a and 'verify-hosted-release' in a
assert '--trusted-keys' in a
if os.environ.get('VERIFY_FAIL'): sys.exit(1)
revision=pathlib.Path(a[a.index('--input')+1]).read_text()
if '--expected-revision' in a: assert a[a.index('--expected-revision')+1] == revision
print(revision)
""")

    def tearDown(self):
        self.temp.cleanup()

    def tool(self, name, body):
        path = self.root / "bin" / name
        path.write_text(body)
        path.chmod(0o755)

    def restore(self):
        return subprocess.run(["bash", "scripts/restore_catalog_hosting_site.sh", "", "", "publisher/site",
                               "https://scanstash-catalog-prod.web.app"], cwd=self.root,
                              env=self.environment, capture_output=True, text=True)

    def test_existing_callers_restore_one_piece_and_keep_other_namespaces(self):
        prior = self.root / "publisher/site/magic/v1/current.json"
        prior.parent.mkdir(parents=True)
        prior.write_text("existing magic")
        result = self.restore()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(prior.read_text(), "existing magic")
        for revision in (1, 2):
            self.assertEqual((self.root / f"publisher/site/one-piece/v1/releases/{revision}/catalog-release.json").read_text(), str(revision))
        self.assertEqual((self.root / "publisher/site/one-piece/v1/current.json").read_text(), "2")
        self.assertEqual(self.restore().returncode, 0, "Repeated restoration must be idempotent")

    def test_absent_one_piece_is_allowed_before_first_publication(self):
        self.environment["POINTER_STATUS"] = "404"
        self.assertEqual(self.restore().returncode, 0)
        self.assertFalse((self.root / "publisher/site/one-piece").exists())

    def test_network_or_signature_failure_stops_deployment_preparation(self):
        self.environment["POINTER_STATUS"] = "503"
        self.assertNotEqual(self.restore().returncode, 0)
        self.environment["POINTER_STATUS"] = "200"
        self.environment["VERIFY_FAIL"] = "1"
        self.assertNotEqual(self.restore().returncode, 0)
        self.assertFalse((self.root / "publisher/site/one-piece/v1/current.json").exists())

    def test_conflicting_immutable_artifact_is_never_overwritten(self):
        artifact = self.root / "publisher/site/one-piece/v1/releases/1/catalog-release.json"
        artifact.parent.mkdir(parents=True)
        artifact.write_text("retain this artifact")
        self.assertNotEqual(self.restore().returncode, 0)
        self.assertEqual(artifact.read_text(), "retain this artifact")


if __name__ == "__main__":
    unittest.main()
