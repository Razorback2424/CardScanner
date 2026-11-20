import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_yugioh_catalog as builder  # noqa: E402
import catalog_exceptions  # noqa: E402
import reconcile_yugioh_release_names as reconcile  # noqa: E402


def ledger_row(code, products, sources, reason="unreviewedCorrespondence"):
    return catalog_exceptions.row("yugioh", code.split("-")[0], code, reason, "",
                                  {"products": products, "sourceRows": sources})


def product(pid, gid, group, card, rarity="Ultra Rare"):
    return {"productID": pid, "groupID": gid, "group": group, "rarity": rarity, "name": "x", "cardID": card}


def source(card, name, rarity="Ultra Rare"):
    return {"cardID": card, "setName": name, "rarity": rarity}


class ProposeTests(unittest.TestCase):
    def test_printed_code_and_card_agreement_names_the_release(self):
        rows = [ledger_row(f"SDBE-EN00{i}", [product(i, 1153, "Structure Deck: Saga of Blue-Eyes White Dragon", 10 + i)],
                           [source(10 + i, "Saga of Blue-Eyes White Dragon Structure Deck")]) for i in range(1, 4)]
        aliases, refusals = reconcile.propose(rows)
        self.assertEqual(refusals, [])
        self.assertEqual([(a["groupID"], a["setName"], a["codePrefixes"], a["evidence"]["products"]) for a in aliases],
                         [(1153, "Saga of Blue-Eyes White Dragon Structure Deck", ["SDBE-"], 3)])

    def test_sub_releases_in_one_group_get_exact_code_aliases(self):
        rows = [ledger_row("DT05-EN001", [product(1, 5, "Duel Terminal 5", 1)], [source(1, "Duel Terminal 5a")]),
                ledger_row("DT05-EN051", [product(2, 5, "Duel Terminal 5", 2)], [source(2, "Duel Terminal 5b")]),
                ledger_row("DT05-EN052", [product(3, 5, "Duel Terminal 5", 3)], [source(3, "Duel Terminal 5b")])]
        aliases, refusals = reconcile.propose(rows)
        self.assertEqual(refusals, [])
        self.assertEqual([(a["setName"], a["codePrefixes"], a["codes"], a["evidence"]["products"]) for a in aliases],
                         [("Duel Terminal 5a", [], ["DT05-EN001"], 1),
                          ("Duel Terminal 5b", [], ["DT05-EN051", "DT05-EN052"], 2)])
        self.assertEqual(len({a["id"] for a in aliases}), 2)

    def test_a_code_whose_products_disagree_stays_open(self):
        rows = [ledger_row("ABC-EN001", [product(1, 5, "Group", 1), product(2, 5, "Group", 9)],
                           [source(1, "Set A"), source(9, "Set B")]),
                ledger_row("ABC-EN002", [product(3, 5, "Group", 2)], [source(2, "Set B")])]
        aliases, refusals = reconcile.propose(rows)
        self.assertEqual([(a["setName"], a["codes"]) for a in aliases], [("Set B", ["ABC-EN002"])])
        self.assertEqual([(r["reason"], r["codes"], r["products"]) for r in refusals],
                         [("ambiguousSetName", ["ABC-EN001"], 2)])

    def test_two_names_for_every_product_are_ambiguous(self):
        rows = [ledger_row("ABC-EN001", [product(1, 5, "Group", 1)], [source(1, "Set A"), source(1, "Set B")])]
        aliases, refusals = reconcile.propose(rows)
        self.assertEqual(aliases, [])
        self.assertEqual(refusals[0]["reason"], "ambiguousSetName")

    def test_another_cards_source_row_is_not_evidence(self):
        rows = [ledger_row("ABC-EN001", [product(1, 5, "Group", 1)], [source(2, "Set A")])]
        aliases, refusals = reconcile.propose(rows)
        self.assertEqual(aliases, [])
        self.assertEqual(refusals[0]["reason"], "noSourceRow")

    def test_unresolved_cards_and_exactly_named_groups_are_ignored(self):
        rows = [ledger_row("ABC-EN001", [product(1, 5, "Set A", 1)], [source(1, "Set A", "Secret Rare")]),
                ledger_row("ABC-EN002", [product(2, 6, "Other", None)], [source(3, "Set A")]),
                ledger_row("ABC-EN003", [product(3, 6, "Other", 4)], [source(4, "Set A")], reason="rarityShortfall")]
        self.assertEqual(reconcile.propose(rows), ([], []))

    def test_prefixes_are_scoped_separately(self):
        rows = [ledger_row("AAA-EN001", [product(1, 5, "Promos", 1)], [source(1, "Promo A")]),
                ledger_row("BBB-EN001", [product(2, 5, "Promos", 2)], [source(2, "Promo B")])]
        aliases, _ = reconcile.propose(rows)
        self.assertEqual(sorted((a["setName"], tuple(a["codePrefixes"])) for a in aliases),
                         [("Promo A", ("AAA-",)), ("Promo B", ("BBB-",))])
        self.assertEqual(len({a["id"] for a in aliases}), 2)


class MergeTests(unittest.TestCase):
    def test_unchanged_aliases_keep_their_review_record(self):
        kept = {"id": "a", "setName": "A", "codePrefixes": ["A-"]}
        changed = {"id": "b", "setName": "B", "codePrefixes": ["B-"]}
        document = {"rules": [1], "setNameAliases": [dict(kept, reviewedAt="2026-01-01", ledger={"g": 1}),
                                                     dict(changed, codePrefixes=["C-"], reviewedAt="2026-01-01")]}
        merged = reconcile.merge(document, [kept, changed], "2026-02-02", {"g": 2})
        self.assertEqual(merged["rules"], [1])
        self.assertEqual(merged["setNameAliases"], [dict(kept, reviewedAt="2026-01-01", ledger={"g": 1}),
                                                    dict(changed, reviewedAt="2026-02-02", ledger={"g": 2})])


class BuilderAliasTests(unittest.TestCase):
    rules = {"setNameAliases": [{"groupID": 1153, "groupName": "Structure Deck: Saga of Blue-Eyes White Dragon",
                                 "setName": "Saga of Blue-Eyes White Dragon Structure Deck", "codePrefixes": ["SDBE-"]}]}

    def names(self, gid, group, code):
        return builder.release_names(gid, group, code, self.rules)

    def test_alias_applies_only_to_its_group_name_and_prefix(self):
        group = "Structure Deck: Saga of Blue-Eyes White Dragon"
        alias = builder.norm("Saga of Blue-Eyes White Dragon Structure Deck")
        self.assertIn(alias, self.names(1153, group, "SDBE-EN001"))
        self.assertNotIn(alias, self.names(1153, group, "LOB-EN001"))
        self.assertNotIn(alias, self.names(9999, group, "SDBE-EN001"))
        self.assertNotIn(alias, self.names(1153, "Renamed group", "SDBE-EN001"))
        self.assertEqual(self.names(9999, "Any", "X-1"), {builder.norm("Any")})

    def test_exact_code_alias_does_not_spread_to_its_prefix(self):
        rules = {"setNameAliases": [{"groupID": 5, "groupName": "Duel Terminal 5", "setName": "Duel Terminal 5a",
                                     "codePrefixes": [], "codes": ["DT05-EN001"]}]}
        alias = builder.norm("Duel Terminal 5a")
        self.assertIn(alias, builder.release_names(5, "Duel Terminal 5", "DT05-EN001", rules))
        self.assertNotIn(alias, builder.release_names(5, "Duel Terminal 5", "DT05-EN0011", rules))
        self.assertNotIn(alias, builder.release_names(5, "Duel Terminal 5", "DT05-EN051", rules))


class SourceRarityTests(unittest.TestCase):
    rules = {"sourceRarityAliases": [{"sourceRarities": ["Short Print", "Super Short Print"], "physicalRarity": "Common"}]}

    def test_pack_ratio_labels_name_the_physical_rarity_only(self):
        self.assertEqual(builder.source_physical_rarity("Short Print", self.rules), "Common")
        self.assertEqual(builder.source_physical_rarity("super short print", self.rules), "Common")
        self.assertEqual(builder.source_physical_rarity("Ultra Rare", self.rules), "Ultra Rare")
        self.assertEqual(builder.source_physical_rarity("Short Print", {}), "Short Print")


if __name__ == "__main__":
    unittest.main()
