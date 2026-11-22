import copy
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_yugioh_catalog as builder  # noqa: E402


class OfficialRarityPlaceholderTests(unittest.TestCase):
    def setUp(self):
        self.code = "L5DD-ENA01"
        self.gid = 24396
        self.groups = [{"groupId": self.gid, "name": "Legendary 5D's Decks"}]
        self.source = {"set_code": self.code, "set_rarity": "3", "set_name": "Legendary 5D&apos;s Decks"}
        self.cards = [{"id": 48686504, "name": "Lonefire Blossom",
                       "card_images": [{"id": 48686504}], "card_sets": [self.source]}]
        self.market = {"productId": 661299, "groupId": self.gid, "categoryId": 2, "name": "Lonefire Blossom",
                       "extendedData": [{"name": "Number", "value": self.code}, {"name": "Rarity", "value": "Common"}]}
        self.products = {self.gid: [self.market]}
        self.rules = {"groups": [next(scope for scope in builder.PLACEHOLDER_RULES["groups"]
                                     if scope["groupID"] == self.gid)]}
        self.hashes = {self.gid: self.rules["groups"][0]["expectedProductsSHA256"]}

    def match(self):
        return builder.reviewed_placeholder_rarities(self.groups, self.products, self.cards, self.hashes, self.rules)

    def test_exact_publisher_rarity_closes_correspondence_without_auto_eligibility(self):
        self.assertEqual(self.match(), {self.code: (48686504, "Legendary 5D's Decks", "Common")})
        with patch.object(builder, "PLACEHOLDER_RULES", self.rules):
            editions = {"661299": {"editions": ["yugioh1stEdition"], "complete": True, "evidence": "Fixture receipt"}}
            args = (self.groups, self.products, {self.gid: []}, self.cards, {}, editions, "2026-11-21T00:00:00Z")
            baseline, _, _, _ = builder.build(*args, floor=1)
            resolved, _, _, _ = builder.build(*args, floor=1, product_hashes=self.hashes)
            self.source.update(set_rarity="Common", set_name="Legendary 5D's Decks")
            genuine, _, _, _ = builder.build(*args, floor=1, product_hashes=self.hashes)
        self.assertEqual(baseline["incompleteCodes"], [self.code])
        self.assertEqual(resolved["incompleteCodes"], [])
        self.assertEqual(resolved["autoEligibleCodes"], baseline["autoEligibleCodes"])
        self.assertEqual(genuine["autoEligibleCodes"], [self.code])
        self.assertEqual(resolved["printings"], [
            dict(baseline["printings"][0], correspondence="exactOrScopedTaxonomy")])

    def test_marketplace_drift_or_competing_product_refuses_the_rule(self):
        self.hashes[self.gid] = "changed"
        self.assertEqual(self.match(), {})
        self.hashes[self.gid] = self.rules["groups"][0]["expectedProductsSHA256"]
        self.products[self.gid].append(dict(self.market, productId=900000))
        self.assertEqual(self.match(), {})
        self.products[self.gid].pop()
        self.groups.append({"groupId": 99, "name": "Another group"})
        self.products[99] = [dict(self.market, groupId=99, productId=900001)]
        self.assertEqual(self.match(), {})

    def test_exact_names_code_group_and_placeholder_are_required(self):
        changes = ((self.source, "set_code", "L5DD-ENA02"), (self.source, "set_code", "L5DD-JPA01"),
                   (self.source, "set_rarity", "New"), (self.source, "set_name", "Another release"),
                   (self.cards[0], "id", 1), (self.cards[0], "name", "Different card"),
                   (self.groups[0], "name", "Renamed release"), (self.market, "categoryId", 3),
                   (self.market, "groupId", 99), (self.market, "productId", 1),
                   (self.market, "name", "Lonefire Blossom (Alternate Art)"),
                   (self.market["extendedData"][1], "value", "Ultra Rare"))
        for target, key, changed in changes:
            with self.subTest(key=key, changed=changed):
                original = target[key]
                target[key] = changed
                self.assertEqual(self.match(), {})
                target[key] = original

    def test_ambiguous_raw_source_or_product_fields_are_refused(self):
        self.cards[0]["card_sets"].append(dict(self.source, set_rarity="Ultra Rare"))
        self.assertEqual(self.match(), {})
        self.cards[0]["card_sets"].pop()
        self.cards.append(dict(copy.deepcopy(self.cards[0]), id=1))
        self.assertEqual(self.match(), {})
        self.cards.pop()
        self.market["extendedData"].append({"name": "Number", "value": "L5DD-ENA02"})
        self.assertEqual(self.match(), {})
