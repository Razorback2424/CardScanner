import base64
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import catalog_release_preflight as preflight

MIB = 1024 * 1024


class PreflightTests(unittest.TestCase):
    def test_budgets_come_from_the_swift_readers(self):
        self.assertEqual(preflight.budget("one-piece", "payload"), 40 * MIB)
        self.assertEqual(preflight.budget("one-piece", "envelope"), 64 * MIB)
        self.assertEqual(preflight.budget("pokemon", "payload"), 24 * MIB)
        self.assertEqual(preflight.budget("lorcana", "manifest"), 16 * MIB)
        self.assertEqual(preflight.budget("yugioh", "envelope"), 65 * MIB)
        with self.assertRaises(preflight.PreflightError):
            preflight.budget("pokemon", "envelope")

    def test_parses_underscored_and_unspaced_factors(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            relative, name = preflight.BUDGET_SOURCES["pokemon"]["payload"]
            (root / relative).parent.mkdir(parents=True)
            (root / relative).write_text(f"    public static let {name} = 3*1_024 * 1024\n")
            self.assertEqual(preflight.budget("pokemon", "payload", root), 3 * MIB)

    def test_status_is_ok_near_or_over(self):
        limit = preflight.budget("pokemon", "payload")
        self.assertEqual(preflight.check("pokemon", "payload", limit // 2, 0.05)["status"], "ok")
        self.assertEqual(preflight.check("pokemon", "payload", limit - 1, 0.05)["status"], "near")
        self.assertEqual(preflight.check("pokemon", "payload", limit + 1, 0.05)["status"], "over")
        self.assertEqual(preflight.check("pokemon", "payload", limit - 1, 0.0)["status"], "ok")

    def test_envelope_check_also_bounds_the_decoded_payload(self):
        with tempfile.TemporaryDirectory() as directory:
            envelope = Path(directory, "release-envelope.json")
            payload = b"x" * 1000
            encoded = base64.urlsafe_b64encode(payload).decode().rstrip("=")
            envelope.write_text(json.dumps({"keyID": "one-piece-test", "payload": encoded, "signature": "s"}))
            self.assertEqual(preflight.envelope_payload_bytes(envelope), 1000)
            self.assertEqual(preflight.main(["--game", "one-piece", "--envelope", str(envelope)]), 0)

    def test_cli_fails_an_over_budget_candidate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            relative, name = preflight.BUDGET_SOURCES["pokemon"]["payload"]
            (root / relative).parent.mkdir(parents=True)
            (root / relative).write_text(f"static let {name} = 1_000\n")
            small, large = root / "small.json", root / "large.json"
            small.write_bytes(b"{}" * 100)
            large.write_bytes(b"{}" * 600)
            self.assertEqual(preflight.main(["--game", "pokemon", "--payload", str(small), "--root", str(root)]), 0)
            self.assertEqual(preflight.main(["--game", "pokemon", "--payload", str(large), "--root", str(root)]), 1)
            self.assertEqual(preflight.main(["--game", "pokemon", "--envelope", str(small), "--root", str(root)]), 2)


if __name__ == "__main__":
    unittest.main()
