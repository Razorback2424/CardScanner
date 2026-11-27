import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import prepare_one_piece_hosting as hosting
from prepare_one_piece_hosting import publication_inputs


class OnePieceHostingTests(unittest.TestCase):
    current = "one-piece/v1/current.json"
    first = "one-piece/v1/releases/1/catalog-release.json"
    second = "one-piece/v1/releases/2/catalog-release.json"
    baseline = b"signed revision 1"
    approved = b"signed revision 2"

    def fetch(self, responses):
        def read(path, *, absent_ok):
            if path not in responses and not absent_ok:
                raise FileNotFoundError(path)
            return responses.get(path)
        return read

    @property
    def continuation(self):
        return {"revision": 2, "previousRevision": 1,
                "previousEnvelopeSHA256": hashlib.sha256(self.baseline).hexdigest()}

    def test_bootstrap_requires_empty_or_identical_head(self):
        manifest = {"revision": 1}
        self.assertEqual(publication_inputs(self.baseline, manifest, True, self.fetch({})), (1, None, None))
        already_published = self.fetch({self.current: self.baseline, self.first: self.baseline})
        self.assertEqual(publication_inputs(self.baseline, manifest, True, already_published), (1, self.baseline, None))
        with self.assertRaisesRegex(ValueError, "different production pointer"):
            publication_inputs(self.baseline, manifest, True, self.fetch({self.current: b"different"}))

    def test_continuation_requires_exact_reviewed_predecessor(self):
        read = self.fetch({self.current: self.baseline})
        self.assertEqual(publication_inputs(self.approved, self.continuation, False, read),
                         (2, self.baseline, self.baseline))
        for responses in [{}, {self.current: b"different signed revision 1"}]:
            with self.assertRaisesRegex(ValueError, "differs from the reviewed predecessor"):
                publication_inputs(self.approved, self.continuation, False, self.fetch(responses))

    def test_retry_uses_the_reviewed_immutable_predecessor(self):
        read = self.fetch({self.current: self.approved, self.first: self.baseline, self.second: self.approved})
        self.assertEqual(publication_inputs(self.approved, self.continuation, False, read),
                         (2, self.approved, self.baseline))
        read = self.fetch({self.current: self.approved, self.first: b"different", self.second: self.approved})
        with self.assertRaisesRegex(ValueError, "differs from the reviewed predecessor"):
            publication_inputs(self.approved, self.continuation, False, read)

    def test_conflicting_immutable_bytes_are_rejected(self):
        read = self.fetch({self.current: self.baseline, self.second: b"different"})
        with self.assertRaisesRegex(ValueError, "Existing immutable"):
            publication_inputs(self.approved, self.continuation, False, read)
        read = self.fetch({self.current: self.approved, self.first: self.baseline})
        with self.assertRaisesRegex(ValueError, "no matching immutable"):
            publication_inputs(self.approved, self.continuation, False, read)

    def test_cli_supports_r2_origin_and_one_piece_only_without_reading_firebase_or_other_games(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            artifact = root / "artifact"
            artifact.mkdir()
            (artifact / "release-envelope.json").write_bytes(self.approved)
            (artifact / "verified-manifest.json").write_text(json.dumps(self.continuation))
            out = root / "inputs"
            seen_urls = []

            def fake_read_http(url, maximum, *, absent_ok=False):
                seen_urls.append(url)
                self.assertTrue(url.startswith(hosting.R2_ORIGIN + "/"), url)
                self.assertIn("?r2v=", url)
                path = url.removeprefix(hosting.R2_ORIGIN + "/").split("?", 1)[0]
                if path == self.current:
                    return self.baseline
                return None

            stdout = io.StringIO()
            with patch.object(hosting, "read_http", side_effect=fake_read_http), redirect_stdout(stdout):
                hosting.main(["--artifact", str(artifact), "--output-dir", str(out),
                              "--bootstrap", "false", "--origin", hosting.R2_ORIGIN, "--one-piece-only"])
            self.assertEqual(stdout.getvalue().strip(), "2")
            self.assertEqual((out / "one-piece-current.json").read_bytes(), self.baseline)
            self.assertEqual((out / "one-piece-predecessor.json").read_bytes(), self.baseline)
            self.assertFalse((out / "pokemon-current.json").exists())
            self.assertFalse(any("/v1/current.json" in url and "/one-piece/" not in url for url in seen_urls))
