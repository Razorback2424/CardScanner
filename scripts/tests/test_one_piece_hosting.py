import hashlib
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
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
