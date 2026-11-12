import gzip
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_magic_printing_families import family_index, printings


class MagicPrintingFamilyTests(unittest.TestCase):
    def test_bundled_families_keep_the_original_and_exact_alternatives(self):
        root = Path(__file__).resolve().parents[2]
        artifact = json.loads((root / "TradingCardScanner/MagicCatalogSeed/printing-families.json").read_bytes())
        self.assertEqual(artifact["schemaVersion"], 1)
        self.assertRegex(artifact["sourceSHA256"], r"^[0-9a-f]{64}$")
        families = artifact["families"]
        self.assertTrue(families)
        for key, family in families.items():
            self.assertEqual(str(uuid.UUID(family["oracleID"])), family["oracleID"])
            members = family["members"]
            self.assertTrue(2 <= len(members) <= 75)
            original = members[0]
            self.assertEqual(key, f'{original["setCode"]}/{original["collectorNumber"].lower()}')
            self.assertEqual(len(members), len({str(uuid.UUID(member["id"])) for member in members}))
        self.assertEqual({m["collectorNumber"] for m in families["2x2/208"]["members"]}, {"208", "2X2-208"})
        ebondeath = {m["collectorNumber"]: m["label"] for m in families["afr/100"]["members"]}
        self.assertEqual(set(ebondeath), {"100", "100a", "100p", "100s"})
        self.assertEqual(ebondeath["100a"], "D&D ampersand foil")
        self.assertEqual({m["collectorNumber"] for m in families["fin/544"]["members"]}, {"544", "544†"})
        for collector in ("232", "399", "497", "544"):
            kuja = {m["collectorNumber"]: m for m in families[f"fin/{collector}"]["members"] if m["setCode"] == "fin"}
            self.assertEqual(kuja[collector]["label"], "Back says Flare Star")
            self.assertEqual(kuja[collector + "†"]["label"], "Back says Flame Star")
            self.assertTrue(all(m["useReverse"] for m in kuja.values()))
        for key in ("acr/120", "ltc/386", "ltr/734", "mh3/383", "mkm/318", "mul/141", "who/564"):
            collector = key.split("/")[1]
            labels = {m["collectorNumber"]: m["label"] for m in families[key]["members"]}
            self.assertEqual(labels[collector + "z"], "Numbered serial stamp")

    def test_paper_footer_families_keep_exact_uuid_and_scope(self):
        oracle = "00000000-0000-4000-8000-000000000001"
        original = "00000000-0000-4000-8000-000000000002"
        stamp = "00000000-0000-4000-8000-000000000003"
        reprint = "00000000-0000-4000-8000-000000000004"
        variant = "00000000-0000-4000-8000-000000000005"
        base = {"object": "card", "id": original, "oracle_id": oracle, "set": "iko",
                "collector_number": "17", "lang": "en", "digital": False, "games": ["paper"],
                "oversized": False, "released_at": "2020-04-24", "layout": "normal", "finishes": ["nonfoil", "foil"],
                "frame": "2015", "border_color": "black", "illustration_id": "shared-art"}
        def printing(num, **changes):
            return {**base, "id": f"00000000-0000-4000-8000-{num:012}", **changes}
        directory = {
            "iko": {"set_type": "expansion", "released_at": "2020-04-24"},
            "piko": {"set_type": "promo", "parent_set_code": "iko"},
            "plst": {"set_type": "masters"},
        }
        rows = [base,
                printing(3, set="piko", collector_number="17s", promo_types=["prerelease", "datestamped"]),
                printing(4, set="plst", collector_number="IKO-17"),
                printing(5, collector_number="17†", variation_of=original),
                printing(6, collector_number="17b", variation_of=original),
                printing(7, set="piko", collector_number="17p", illustration_id="other-art", promo_types=["promopack", "stamped"]),
                printing(8, set="piko", collector_number="17a", promo_types=["boxtopper"]),
                printing(9, collector_number="17†a", variation_of=original, oracle_id="00000000-0000-4000-8000-000000000011"),
                printing(10, collector_number="17†b", variation_of=original, lang="fr"),
                printing(11, collector_number="17†c", variation_of=original, released_at="2026-11-12"),
                printing(12, collector_number="17†d", variation_of=original, oversized=True)]
        raw = "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows).encode()
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "bulk.jsonl.gz"
            path.write_bytes(gzip.compress(raw))
            cards, digest = printings(path, "2026-11-11")
        self.assertEqual(digest, hashlib.sha256(raw).hexdigest())
        families = family_index(cards, directory)
        self.assertEqual(list(families), ["iko/17"])
        self.assertEqual(families["iko/17"]["oracleID"], oracle)
        self.assertEqual([member["id"] for member in families["iko/17"]["members"]], [original, variant, stamp, reprint])
        self.assertEqual(families["iko/17"]["members"][-1]["collectorNumber"], "IKO-17")
        self.assertEqual(families, family_index(dict(reversed(list(cards.items()))), directory))


if __name__ == "__main__":
    unittest.main()
