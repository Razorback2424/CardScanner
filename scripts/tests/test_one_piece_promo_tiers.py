import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from reconcile_one_piece_promo_tiers import binding_choice, parse_title


def product(qualifier, tier=None, pid=1):
    return {"qualifier": qualifier, "tier": tier, "id": pid}


class PromoTierTests(unittest.TestCase):
    def test_title_needs_the_card_name_one_event_and_a_known_tier(self):
        self.assertEqual(parse_title("OP07-091", "Monkey.D.Luffy",
                                     "Monkey.D.Luffy (091) (Online Regional 2024 Vol. 3) [Finalist]"),
                         ("Online Regional 2024 Vol. 3", "Finalist"))
        self.assertEqual(parse_title("OP02-008", "Jozu", "Jozu (Judge)"), ("Judge", None))
        self.assertEqual(parse_title("ST01-006", "Tony Tony.Chopper", "Tony Tony.Chopper - ST01-006 (Treasure Cup)"),
                         ("Treasure Cup", None))
        self.assertIsNone(parse_title("OP02-008", "Jozu", "Marco (Judge)"))
        self.assertIsNone(parse_title("OP02-008", "Jozu", "Jozu"))
        self.assertIsNone(parse_title("OP02-008", "Jozu", "Jozu (Judge) [Mystery]"))
        self.assertIsNone(parse_title("OP01-010", "Monkey.D.Luffy", "Monkey.D.Luffy (010)"))

    def test_binding_uses_venue_and_tier_words_and_refuses_ties(self):
        regional = [product("Online Regional 2023", t, i) for i, t in enumerate(["Participant", "Finalist", "Winner"])]
        regional += [product("Offline Regional 2023", t, 10 + i) for i, t in enumerate(["Participant", "Finalist", "Winner"])]
        self.assertEqual(binding_choice("Included in Online Regional Participation Pack Vol.1", regional)["id"], 0)
        self.assertEqual(binding_choice("Offline Regional Champion Card Set 2025 Vol.2", regional)["id"], 12)
        self.assertIsNone(binding_choice("Regional Participation Pack", regional))
        event = [product("OP14 Release Event", None, 1), product("OP14 Release Event Winner", None, 2)]
        self.assertEqual(binding_choice("OP14-EB04 Release Event", event)["id"], 1)
        self.assertEqual(binding_choice("3rd Anniversary Winner Prize", [product("3rd Anniversary Winner", None, 5)])["id"], 5)
        self.assertIsNone(binding_choice("Dreamhack Dallas 2024", [product("Convention Promo 2024", None, 1),
                                                                   product("2nd Anniversary Stamped Promo", None, 2)]))


if __name__ == "__main__":
    unittest.main()
