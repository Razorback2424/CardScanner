import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import catalog_exceptions as ledger


def sample():
    return [
        ledger.row("lorcana", "P2", "lorcanajson:en:1", "promoDistribution", "Organized Play"),
        ledger.row("lorcana", "P2", "lorcanajson:en:2", "promoDistribution"),
        ledger.row("lorcana", "Q3", "lorcanajson:en:3", "noFooter"),
        ledger.row("pokemon", "sv03", "sv03-100", "finishConflict", evidence={"productID": 613974}),
    ]


class LedgerTests(unittest.TestCase):
    def test_summary_ranks_reasons_per_game(self):
        summary = ledger.summarize(sample())
        self.assertEqual(summary["total"], 4)
        self.assertEqual(summary["byGame"], {"lorcana": 3, "pokemon": 1})
        self.assertEqual(list(summary["byReason"]["lorcana"]), ["promoDistribution", "noFooter"])
        self.assertEqual(summary["bySet"]["lorcana"], {"P2": 2, "Q3": 1})

    def test_write_is_deterministic_and_round_trips(self):
        rows = sample()
        with tempfile.TemporaryDirectory() as directory:
            first, second = Path(directory, "a.json"), Path(directory, "b.json")
            ledger.write_ledger(first, rows, source={"tcgcsvBuild": "2026-11-17"})
            ledger.write_ledger(second, list(reversed(rows)), source={"tcgcsvBuild": "2026-11-17"})
            self.assertEqual(first.read_bytes(), second.read_bytes())
            self.assertEqual(ledger.read_ledger(first), sorted(rows, key=lambda r: (r["game"], r["set"], r["reason"], r["identity"])))
            self.assertEqual(json.loads(first.read_text())["source"], {"tcgcsvBuild": "2026-11-17"})

    def test_diff_reports_closed_opened_and_reason_deltas(self):
        before = sample()
        after = [before[2], before[3], ledger.row("lorcana", "P3", "lorcanajson:en:9", "marketOnly")]
        result = ledger.diff(before, after)
        self.assertEqual((result["before"], result["after"]), (4, 3))
        self.assertEqual({r["identity"] for r in result["closed"]}, {"lorcanajson:en:1", "lorcanajson:en:2"})
        self.assertEqual([r["identity"] for r in result["opened"]], ["lorcanajson:en:9"])
        self.assertEqual(result["reasonDelta"]["lorcana"]["promoDistribution"], {"before": 2, "after": 0})
        self.assertNotIn("pokemon", result["reasonDelta"])

    def test_rejects_malformed_rows(self):
        bad = [
            {"game": "lorcana", "set": "P1", "identity": "x", "reason": "PromoDistribution", "detail": "", "evidence": {}},
            {"game": "chess", "set": "P1", "identity": "x", "reason": "noFooter", "detail": "", "evidence": {}},
            {"game": "lorcana", "set": "P1", "identity": "", "reason": "noFooter", "detail": "", "evidence": {}},
            {"game": "lorcana", "set": "P1", "identity": "x", "reason": "noFooter", "detail": "", "evidence": []},
            {"game": "lorcana", "set": "P1", "identity": "x", "reason": "noFooter", "detail": ""},
        ]
        for entry in bad:
            with self.subTest(entry=entry), self.assertRaises(ledger.LedgerError):
                ledger.validate([entry])
        duplicate = ledger.row("lorcana", "P1", "x", "noFooter")
        with self.assertRaises(ledger.LedgerError):
            ledger.validate([duplicate, dict(duplicate)])

    def test_same_identity_may_carry_several_reasons(self):
        ledger.validate([ledger.row("yugioh", "LOB", "LOB-001", "nameMismatch"),
                         ledger.row("yugioh", "LOB", "LOB-001", "rarityShortfall")])

    def test_cli_summarize_and_diff(self):
        with tempfile.TemporaryDirectory() as directory:
            before, after = Path(directory, "before.json"), Path(directory, "after.json")
            ledger.write_ledger(before, sample())
            ledger.write_ledger(after, sample()[2:])
            self.assertEqual(ledger.main(["summarize", str(before)]), 0)
            self.assertEqual(ledger.main(["diff", str(before), str(after)]), 0)


if __name__ == "__main__":
    unittest.main()
