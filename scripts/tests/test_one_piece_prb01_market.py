import base64
import copy
import csv
import json
import sys
import unittest
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from prepare_one_piece_prb01_market import prepare


class PRB01MarketTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = ROOT / 'publisher/one-piece/prb01-revision-6'
        with (root / 'inventory.csv').open(newline='', encoding='utf-8-sig') as f:
            cls.rows = list(csv.DictReader(f))
        encoded = json.loads((root / 'previous-envelope.json').read_bytes())['payload']
        cls.baseline = json.loads(base64.urlsafe_b64decode(encoded + '=' * (-len(encoded) % 4)))
        cls.products = json.loads((root / 'capture/68-23496-products.json').read_bytes())
        cls.prices = json.loads((root / 'capture/68-23496-prices.json').read_bytes())
        cls.candidate = json.loads((root / 'candidate.json').read_bytes())

    def reconcile(self, rows, products=None, prices=None, release=None):
        release = release or copy.deepcopy(self.baseline)
        report = prepare(release, copy.deepcopy(rows), json.dumps(products or self.products).encode(),
                         json.dumps(prices or self.prices).encode(), '2026-11-16T12:00:00Z', 'a' * 64)
        return release, report['decisions']

    def test_inventory_and_candidate_preserve_baseline(self):
        self.assertEqual(len(self.rows), 252)
        self.assertEqual(len({r['printing_uuid'] for r in self.rows}), 252)
        self.assertEqual(len({r['tcgplayer_product_id'] for r in self.rows}), 252)
        self.assertEqual(Counter(r['price_lane'] for r in self.rows), {'Foil': 236, 'Normal': 16})
        generated, decisions = self.reconcile(self.rows)
        self.assertEqual(Counter(d['status'] for d in decisions), {'exact': 251, 'held': 1})
        held = next(d for d in decisions if d['status'] == 'held')
        self.assertEqual((held['productID'], held['reason']), ('586607', 'marketplace title differs from reviewed title'))
        old, new = self.baseline['registry'], self.candidate['registry']
        self.assertEqual({k: v for k, v in old.items() if k != 'printings'}, {k: v for k, v in new.items() if k != 'printings'})
        before = {p['id']: p for p in old['printings']}; after = {p['id']: p for p in new['printings']}
        self.assertEqual(before.keys(), after.keys())
        added = 0
        for key, a in before.items():
            b = after[key]
            self.assertEqual({k: v for k, v in a.items() if k != 'marketMappings'}, {k: v for k, v in b.items() if k != 'marketMappings'})
            if a['marketMappings']:
                self.assertEqual(a['marketMappings'], b['marketMappings'])
            elif b['marketMappings']:
                self.assertEqual(a['releaseID'], 'product:prb01-one-piece-card-the-best-2024')
                added += 1
        self.assertEqual(added, 251)
        self.assertEqual({p['id']: p['marketMappings'] for p in generated['registry']['printings']},
                         {p['id']: p['marketMappings'] for p in self.candidate['registry']['printings']})

    def test_title_treatment_and_artwork_conflicts_are_held(self):
        row = copy.deepcopy(next(r for r in self.rows if r['treatment'] == 'Alternate artwork'))
        for field, value in [('tcgplayer_product_name', 'Wrong title'), ('treatment', 'Standard artwork'),
                             ('artwork_id', '00000000-0000-0000-0000-000000000000'), ('artwork_alias', 'wrong-family')]:
            altered = dict(row, **{field: value})
            with self.subTest(field=field):
                self.assertEqual(self.reconcile([altered])[1][0]['status'], 'held')

    def test_missing_and_duplicate_product_or_lane_are_held(self):
        row = next(r for r in self.rows if r['treatment'] == 'Alternate artwork')
        pid = int(row['tcgplayer_product_id'])
        for resource, mode in [('products', 'missing'), ('products', 'duplicate'), ('prices', 'missing'), ('prices', 'duplicate')]:
            products, prices = copy.deepcopy(self.products), copy.deepcopy(self.prices)
            doc = products if resource == 'products' else prices
            target = next(x for x in doc['results'] if x['productId'] == pid and (resource == 'products' or x['subTypeName'] == row['price_lane']))
            if mode == 'missing': doc['results'].remove(target)
            else: doc['results'].append(copy.deepcopy(target))
            if 'totalItems' in doc: doc['totalItems'] = len(doc['results'])
            with self.subTest(resource=resource, mode=mode):
                self.assertEqual(self.reconcile([row], products, prices)[1][0]['status'], 'held')

    def test_normal_and_foil_cannot_be_interchanged(self):
        for lane in ('normal', 'foil'):
            row = next(r for r in self.rows if r['treatment'] == 'Standard artwork' and r['finish_variant'] == lane)
            self.assertEqual(self.reconcile([row])[1][0]['status'], 'exact')
            wrong = dict(row, price_lane='Foil' if lane == 'normal' else 'Normal')
            self.assertEqual(self.reconcile([wrong])[1][0]['status'], 'held')

    def test_nontextured_manga_requires_retained_specific_evidence(self):
        row = next(r for r in self.rows if r['treatment'] == 'Manga artwork (non-textured foil)')
        self.assertEqual(self.reconcile([row])[1][0]['status'], 'exact')
        release = copy.deepcopy(self.baseline)
        observation = next(o for o in release['observations'] if o['id'] == row['source_observation_id'])
        observation['printedEvidence'].pop('marketplacePrintingSpecification')
        self.assertEqual(self.reconcile([row], release=release)[1][0]['status'], 'held')

    def test_malformed_duplicate_and_incomplete_feed_are_rejected(self):
        products = copy.deepcopy(self.products)
        duplicate = copy.deepcopy(products['results'][0]); duplicate['groupId'] = 1
        products['results'].append(duplicate); products['totalItems'] = len(products['results'])
        with self.assertRaises(ValueError):
            self.reconcile([self.rows[0]], products=products)
        products = copy.deepcopy(self.products); products['totalItems'] += 1
        with self.assertRaises(ValueError):
            self.reconcile([self.rows[0]], products=products)

    def test_reused_product_id_is_never_mapped(self):
        row = self.rows[0]
        release = copy.deepcopy(self.baseline)
        other = next(p for p in release['registry']['printings'] if p['marketMappings'])
        other['marketMappings'][0]['productID'] = row['tcgplayer_product_id']
        self.assertEqual(self.reconcile([row], release=release)[1][0]['reason'], 'existing mapping or marketplace product collision')

    def test_unrelated_artwork_hash_cannot_borrow_a_printing(self):
        row = next(r for r in self.rows if r['treatment'] == 'Alternate artwork')
        release = copy.deepcopy(self.baseline)
        proof = next(o for o in release['observations'] if o['id'] == row['source_observation_id'])['printedEvidence']
        proof['matchedBandaiImageSHA256'] = 'a' * 64
        self.assertEqual(self.reconcile([row], release=release)[1][0]['status'], 'held')

    def test_sanji_exception_keeps_independent_evidence_without_invented_hash(self):
        row = dict(next(r for r in self.rows if r['tcgplayer_product_id'] == '586607'), tcgplayer_product_name='Sanji (PRB01-001)')
        release, decisions = self.reconcile([row])
        self.assertEqual(decisions[0]['status'], 'exact')
        proof = release['observations'][-1]['printedEvidence']
        self.assertIn('tcg.directory', proof['independentEvidenceURLs'])
        self.assertNotIn('retailerImageSHA256', proof)


if __name__ == '__main__':
    unittest.main()
