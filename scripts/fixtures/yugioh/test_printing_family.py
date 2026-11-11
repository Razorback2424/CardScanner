import copy
import json
import pathlib
import tempfile
import unittest
import build_yugioh_catalog as builder


class PrintingFamilyTests(unittest.TestCase):
    def setUp(self):
        self.fixture = json.loads(pathlib.Path(__file__).with_name('mp24.json').read_text())
        self.inventory = json.loads((builder.ROOT / 'yugioh_mp24_inventory.json').read_text())

    def build(self, inventory=True):
        f = self.fixture
        return builder.build(f['groups'], {23481: f['products']}, {23481: f['prices']}, f['cards'], {}, {},
            '2026-10-23T03:52:28Z', floor=1,
            price_provenance={23481: dict(h='ee875ec0b149d879140680d8cae89a6a960fcee3c80c901c208921e719b8fd72', s='2026-10-20T20:05:18+0000', st='providerSnapshot')},
            printing_inventory=self.inventory if inventory else None)[0]

    def test_source_backed_unique_common_preserves_unknown_editions(self):
        seed = self.build()
        self.assertEqual(seed['autoEligibleCodes'], ['MP24-EN372'])
        p = seed['printings'][0]
        self.assertFalse(p['ec'])
        self.assertEqual(p['e'], ['yugioh1stEdition'])
        self.assertEqual(p['pf']['sha256'], self.inventory['sha256'])
        self.assertEqual(self.build(False)['autoEligibleCodes'], [])

    def test_competing_rarity_artwork_unmatched_and_conflicting_crosswalk_excluded(self):
        original = copy.deepcopy(self.inventory)
        for change in ['rarity', 'artwork', 'name', 'duplicate']:
            self.inventory = copy.deepcopy(original)
            row = next(r for r in self.inventory['rows'] if r['cid'] == 18838)
            if change == 'rarity': row['rarities'].append('Ultra Rare')
            elif change == 'artwork': row['artwork'] = 2
            elif change == 'name': row['name'] = 'Different Card'
            else: self.inventory['rows'][0] = copy.deepcopy(row)
            self.assertEqual(self.build()['autoEligibleCodes'], [], change)

    def test_competing_product_and_quarantine_do_not_gain_authority(self):
        p = copy.deepcopy(self.fixture['products'][0])
        p['productId'] = 999999
        p['extendedData'].append(dict(name='Rarity', value='Ultra Rare'))
        self.fixture['products'].append(p)
        self.assertEqual(self.build()['autoEligibleCodes'], [])

    def test_missing_membership_does_not_invent_edition(self):
        self.fixture['prices'] = []
        seed = self.build()
        self.assertEqual(seed['autoEligibleCodes'], [])
        self.assertEqual(seed['printings'][0]['e'], [])

    def test_konami_inventory_keeps_embedded_apostrophe_in_exact_name(self):
        html = b"""<meta content="en"> ULTIMATE TOURNAMENT PACK 2 Total of 1 Card(s)
        <div class="t_row c_normal">
        <input type="hidden" class="cnm" value='Gravekeeper's Watcher'>
        <input class="cid" value="5514">
        <div class="lr_icon rid rid_1"><span>Common</span></div>
        <img id="card_image_5514_1">
        </div><!-- .t_row c_normal -->"""
        profile = {"releaseName": "ULTIMATE TOURNAMENT PACK 2", "count": 1, "url": "https://example.com"}
        self.assertEqual(builder.extract_inventory(html, profile)["rows"][0]["name"], "Gravekeeper's Watcher")

    def test_disjoint_market_receipts_keep_each_groups_source_date(self):
        with tempfile.TemporaryDirectory() as folder:
            first = pathlib.Path(folder) / "first.json"
            second = pathlib.Path(folder) / "second.json"
            for path, group, stamp in [(first, 1, "2026-10-20T20:00:00Z"), (second, 2, "2026-11-10T20:00:00Z")]:
                path.write_text(json.dumps({"snapshot_start": stamp, "snapshot_end": stamp, "snapshot_stable": True,
                    "groups": [{"group": group, "sha256": str(group)}]}))
            self.assertEqual(builder.read_price_receipts([first, second]), {
                1: ("2026-10-20T20:00:00Z", "1"), 2: ("2026-11-10T20:00:00Z", "2"),
            })
            with self.assertRaisesRegex(AssertionError, "multiple price receipts"):
                builder.read_price_receipts([first, first])

    def test_detects_newly_populated_released_group_without_flagging_another_editions_release(self):
        seed = {"capturedAt": "2026-11-10T18:00:00Z",
                "sets": [{"g": 1, "a": "UP02", "d": "", "created": "2026-11-04T00:00:00"},
                         {"g": 2, "a": "MAMS", "d": "", "created": "2026-11-13T00:00:00"},
                         {"g": 3, "a": "UP01", "d": "2026-07-08", "created": None}],
                "printings": [{"g": 1}, {"g": 1}, {"g": 2}, {"g": 3}]}
        self.assertEqual(builder.populated_released_groups(seed, {"printings": [{"g": 3}]}), [
            {"groupID": 1, "code": "UP02", "providerDate": "2026-11-04", "candidatePrintings": 2},
        ])
