import unittest

from derive_pokemon_unnumbered_energy import ENERGY_NAMES, exact_products, require_skus, require_stable_identities


class ReviewedUnnumberedEnergyTests(unittest.TestCase):
    def products(self):
        return [
            {"name": name, "productId": index, "extendedData": [
                {"name": "Card Type", "value": "Basic Energy"},
                {"name": "CardText", "value": "©2020 Unnumbered"},
            ]}
            for index, name in enumerate(ENERGY_NAMES, 1)
        ]

    def test_number_and_copyright_must_match_the_reviewed_family(self):
        products = self.products()
        self.assertEqual(set(exact_products(products, 2020, "")), set(ENERGY_NAMES))
        products[0]["extendedData"].append({"name": "Number", "value": "123/202"})
        with self.assertRaisesRegex(ValueError, "Unproven unnumbered product"):
            exact_products(products, 2020, "")
        products[0]["extendedData"].pop()
        products[0]["extendedData"][1]["value"] = "©2019 Unnumbered"
        with self.assertRaisesRegex(ValueError, "Unproven unnumbered product"):
            exact_products(products, 2020, "")

    def test_incomplete_or_duplicate_family_needs_review(self):
        products = self.products()
        with self.assertRaisesRegex(ValueError, "Incomplete reviewed Energy group"):
            exact_products(products[:-1], 2020, "")
        with self.assertRaisesRegex(ValueError, "Unproven unnumbered product"):
            exact_products([*products, products[0]], 2020, "")

    def test_brilliant_stars_requires_eight_named_energy_types(self):
        names = ENERGY_NAMES[:8]
        products = [
            {"name": name + " (2022 Unnumbered)", "productId": index,
             "extendedData": [{"name": "Card Type", "value": f"Basic {name}"}]}
            for index, name in enumerate(names, 1)
        ]
        self.assertEqual(set(exact_products(products, 2022, " (2022 Unnumbered)", names)), set(names))
        with self.assertRaisesRegex(ValueError, "Incomplete reviewed Energy group"):
            exact_products(products, 2022, " (2022 Unnumbered)")

    def test_skus_must_belong_to_the_exact_english_product_and_finish(self):
        product = self.products()[0]
        detail = {"productId": 1, "setId": 2585, "productName": product["name"], "sealed": False,
                  "productTypeName": "Cards", "customAttributes": {"number": ""},
                  "skus": [{"language": "English", "variant": "Normal"},
                           {"language": "English", "variant": "Reverse Holofoil"}]}
        require_skus(detail, product, 2585, {"Normal", "Reverse Holofoil"})
        with self.assertRaisesRegex(ValueError, "SKU identity or finish differs"):
            require_skus(detail, product, 1840, {"Normal", "Reverse Holofoil"})
        detail["skus"][1]["variant"] = "Holofoil"
        with self.assertRaisesRegex(ValueError, "SKU identity or finish differs"):
            require_skus(detail, product, 2585, {"Normal", "Reverse Holofoil"})

    def test_replay_cannot_replace_existing_ownership_identity(self):
        def table(product):
            return {"families": [{"providerSetID": "swsh1", "cards": [
                {"providerID": f"tcgplayer:{product}", "localID": str(product), "name": "Grass Energy"}
            ]}]}

        require_stable_identities(table(123), table(123))
        with self.assertRaisesRegex(ValueError, "Review the existing Energy ownership identities"):
            require_stable_identities(table(123), table(124))
        with self.assertRaisesRegex(ValueError, "Review the existing Energy ownership identities"):
            require_stable_identities(table(123), {"families": []})
