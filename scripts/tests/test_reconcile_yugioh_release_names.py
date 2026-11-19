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

    def test_disagreeing_source_names_are_refused(self):
        rows = [ledger_row("ABC-EN001", [product(1, 5, "Group", 1)], [source(1, "Set A")]),
                ledger_row("ABC-EN002", [product(2, 5, "Group", 2)], [source(2, "Set B")])]
        aliases, refusals = reconcile.propose(rows)
        self.assertEqual(aliases, [])
        self.assertEqual(refusals[0]["reason"], "noCommonSetName")

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


if __name__ == "__main__":
    unittest.main()
