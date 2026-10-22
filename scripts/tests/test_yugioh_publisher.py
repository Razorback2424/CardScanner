"""Local signed delivery rehearsal. Set YUGIOH_CATALOG_PUBLISHER to the built CLI.

RFC 8032 test vector only; these bytes must never become production pins.
"""
import base64
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class YuGiOhPublisherTests(unittest.TestCase):
    def setUp(self):
        self.publisher = os.environ.get("YUGIOH_CATALOG_PUBLISHER")
        if not self.publisher:
            self.skipTest("Build the shared Swift publisher and set YUGIOH_CATALOG_PUBLISHER")
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.keys = self.root / "fixture-keys.json"
        public = bytes.fromhex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
        self.keys.write_text(json.dumps({"yugioh-fixture": base64.b64encode(public).decode()}))
        self.private = self.root / "fixture-key"
        self.private.write_bytes(bytes.fromhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"))
        scripts = Path(__file__).resolve().parents[1]
        spec = importlib.util.spec_from_file_location("builder", scripts / "build_yugioh_catalog.py")
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        f = json.loads((scripts / "fixtures/yugioh/catalog.json").read_text())
        self.seed = builder.build(f["groups"], {1: f["products"]}, {1: f["prices"]}, f["cards"],
            {"12206212": ["Harpie's Brother"]}, {}, "2026-10-20T00:00:00Z", floor=1,
            price_provenance={1: {"h": "a" * 64, "s": "2026-10-20T00:00:00Z", "st": "capturedAt"}})[0]
        self.bundle = self.root / "bundle.json"
        self.bundle.write_text(json.dumps(self.seed))
        self.site = self.root / "site"

    def run_tool(self, command, **options):
        args = [self.publisher, command, "--keys", str(self.keys)]
        for key, value in options.items():
            args += ["--" + key.replace("_", "-"), str(value)]
        return subprocess.run(args, capture_output=True, text=True)

    def approve(self, revision, parent=None, seed=None):
        seed = copy.deepcopy(seed or self.seed)
        seed["generation"] = f"yugioh-en-rehearsal-{revision}"
        path = self.root / f"catalog-{revision}.json"
        path.write_text(json.dumps(seed))
        output = self.root / f"release-{revision}.json"
        options = dict(catalog=path, revision=revision, key_id="yugioh-fixture", private_key_file=self.private,
                       review_id=f"fixture-review-{revision}", output=output)
        options.update(dict(parent_release=parent) if parent else dict(bundle=self.bundle))
        result = self.run_tool("approve", **options)
        self.assertEqual(result.returncode, 0, result.stderr)
        return output

    def promote(self, release):
        return self.run_tool("promote", input=release, bundle=self.bundle, site_root=self.site)

    def test_multi_generation_approval_same_snapshot_parent_export_and_namespace_preservation(self):
        unrelated = self.site / "magic/v1/current.json"
        unrelated.parent.mkdir(parents=True)
        unrelated.write_bytes(b"unchanged magic")
        parent = None
        for revision in range(1, 4):
            parent = self.approve(revision, parent)
            self.assertEqual(self.promote(parent).returncode, 0)
            exported = self.root / "approved-parent.json"
            result = self.run_tool("export-parent", input=parent, output=exported)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(exported.read_text())["capturedAt"], self.seed["capturedAt"])
            self.assertEqual(unrelated.read_bytes(), b"unchanged magic")
        self.assertEqual(self.promote(parent).returncode, 0)
        pointer = self.site / "yugioh/v1/current.json"
        self.assertEqual(pointer.read_bytes(), parent.read_bytes())
        previous = self.site / "yugioh/v1/previous.json"
        self.assertEqual(previous.read_bytes(), (self.root / "release-2.json").read_bytes())
        self.assertNotEqual(self.promote(self.root / "release-1.json").returncode, 0, "No rollback")
        self.assertEqual(pointer.read_bytes(), parent.read_bytes())

    def test_app_wire_fixture_matches_builder_and_actual_publisher_bytes(self):
        release = self.approve(1)
        fixture = Path(__file__).resolve().parents[2] / "TestFixtures/YuGiOhDelivery/approved-wire.json"
        expected = json.loads(fixture.read_bytes())
        actual = json.loads(release.read_bytes())
        # CryptoKit may hedge Ed25519 signing with fresh randomness. Require
        # byte-identical signed payload and catalog, then verify both signatures.
        expected.pop("signature")
        actual.pop("signature")
        self.assertEqual(expected, actual)
        self.assertEqual(self.run_tool("verify", input=fixture).returncode, 0)
        self.assertEqual(self.run_tool("verify", input=release).returncode, 0)

    def test_interrupted_upload_and_wrong_parent_do_not_advance_approved_pointer(self):
        first = self.approve(1)
        self.assertEqual(self.promote(first).returncode, 0)
        second = self.approve(2, first)
        collision = self.site / "yugioh/v1/releases/2/catalog-release.json"
        collision.parent.mkdir(parents=True)
        collision.write_bytes(b"interrupted/corrupt upload")
        self.assertNotEqual(self.promote(second).returncode, 0)
        self.assertEqual((self.site / "yugioh/v1/current.json").read_bytes(), first.read_bytes())
        wrong_parent = self.approve(3)
        self.assertNotEqual(self.promote(wrong_parent).returncode, 0)
        self.assertEqual((self.site / "yugioh/v1/current.json").read_bytes(), first.read_bytes())

    def test_signature_content_state_and_identity_tampering_fail_closed(self):
        first = self.approve(1)
        original = json.loads(first.read_text())
        for field, value in [("keyID", "yugioh-unknown"), ("signature", "A" * 86), ("catalog", "e30=")]:
            changed = dict(original)
            changed[field] = value
            path = self.root / f"tampered-{field}.json"
            path.write_text(json.dumps(changed))
            self.assertNotEqual(self.run_tool("verify", input=path).returncode, 0)
        self.assertNotEqual(self.run_tool("verify", input=first, expected_revision=2).returncode, 0)
        changed = copy.deepcopy(self.seed)
        changed["generation"] = "yugioh-en-invalid"
        changed["printings"][0]["pn"] = "Changed physical identity"
        path = self.root / "changed.json"
        path.write_text(json.dumps(changed))
        result = self.run_tool("approve", catalog=path, revision=2, key_id="yugioh-fixture",
            private_key_file=self.private, review_id="fixture", output=self.root / "invalid.json", parent_release=first)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "invalid.json").exists())


if __name__ == "__main__":
    unittest.main()
