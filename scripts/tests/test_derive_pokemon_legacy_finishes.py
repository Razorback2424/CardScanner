import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from derive_pokemon_legacy_finishes import ascended_reverse_aggregate, cosmos_holo_aggregate, match_cards


class PokemonFinishProjectionTests(unittest.TestCase):
    def test_matches_exact_number_name_and_independently_identified_trait(self):
        cards = {"xy5-9": {"name": "Sceptile", "number": "9"}}
        primary = {"xy5-9": {"name": "Sceptile", "localId": "9"}}
        secondary = {"xy5-9": {"name": "Sceptile", "number": "9", "ancientTrait": {"name": "Ω Barrier"}}}
        products = {"9": [
            {"productId": 41, "name": "Sceptile (Omega)", "number": "9/160", "subtypes": ["Holofoil"]},
            {"productId": 42, "name": "Sceptile (Alpha)", "number": "9/160", "subtypes": ["Normal"]},
            {"productId": 43, "name": "Sceptile (Omega)", "number": "8/160", "subtypes": ["Normal"]},
        ]}
        row = match_cards(cards, primary, secondary, products)["xy5-9"]
        self.assertEqual(row["minimum"], ["holo"])
        self.assertEqual(row["productIDs"], [41])
        self.assertEqual(row["otherProductsAtNumber"], [42, 43])

        secondary["xy5-9"]["number"] = "10"
        row = match_cards(cards, primary, secondary, products)["xy5-9"]
        self.assertEqual(row["minimum"], [])
        self.assertEqual(row["status"], "independent catalog identity unavailable or differs")

    def test_cosmos_aggregate_requires_existing_pattern_and_preserves_plain_holo(self):
        cosmos = {"type": "holo", "foil": "cosmos", "size": "standard"}
        card = {"variants": {"holo": True}, "variants_detailed": [cosmos]}
        self.assertEqual(cosmos_holo_aggregate(card, {"normal", "holo", "cosmos"}), ["cosmos"])
        self.assertEqual(cosmos_holo_aggregate(card, {"normal", "holo"}), [])

        card["variants_detailed"].append({"type": "holo", "languages": ["ja"]})
        self.assertEqual(cosmos_holo_aggregate(card, {"holo", "cosmos"}), ["cosmos"])
        card["variants_detailed"].append({"type": "holo", "languages": ["en"]})
        self.assertEqual(cosmos_holo_aggregate(card, {"holo", "cosmos"}), [])

        card["variants_detailed"] = [cosmos]
        card["pricing"] = {"tcgplayer": {"holofoil": {"productId": 12}}}
        self.assertEqual(cosmos_holo_aggregate(card, {"holo", "cosmos"}), [])

    def test_ascended_reverse_aggregate_needs_both_named_market_products(self):
        patterns = {"energy", "pokeBall"}
        slots = patterns | {"reverse", "normal"}
        card = {"set": {"id": "me02.5"}, "variants": {"reverse": True}, "variants_detailed": [
            {"type": "reverse", "foil": "energy"}, {"type": "reverse", "foil": "pokeball"},
        ]}
        self.assertEqual(ascended_reverse_aggregate(card, slots, patterns), ["energy", "pokeBall"])
        self.assertEqual(ascended_reverse_aggregate(card, slots, {"energy"}), [])
        self.assertEqual(ascended_reverse_aggregate(card, slots, patterns | {"reverse"}), [])
        card["variants_detailed"].append({"type": "reverse"})
        self.assertEqual(ascended_reverse_aggregate(card, slots, patterns), [])
