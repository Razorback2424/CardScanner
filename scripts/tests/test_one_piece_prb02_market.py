import base64
import copy
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from prepare_one_piece_prb02_market import prepare, reviewed_title_matches


class PRB02MappingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        payload = json.loads((ROOT / 'publisher/one-piece/production/revision-3/release-envelope.json').read_bytes())['payload']
        cls.baseline = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))
        capture = ROOT / 'publisher/one-piece/prb02-mapping-candidate/capture'
        cls.products = (capture / '68-24305-products.json').read_bytes()
        cls.prices = (capture / '68-24305-prices.json').read_bytes()

    def run_prepare(self, release, products=None, prices=None):
        return prepare(release, products or self.products, prices or self.prices, '2026-11-16T11:50:00+00:00')

    def test_retained_capture_preserves_identity_and_existing_authority(self):
        release = copy.deepcopy(self.baseline)
        report = self.run_prepare(release)
        decisions = report['verifiedPrintingFinishes']
        self.assertEqual(sum(d['status'] == 'exact' for d in decisions), 265)
        self.assertEqual(sum(d['status'] == 'held' for d in decisions), 24)
        old = self.baseline['registry']
        new = release['registry']
        self.assertEqual({k: v for k, v in old.items() if k != 'printings'},
                         {k: v for k, v in new.items() if k != 'printings'})
        for before, after in zip(old['printings'], new['printings']):
            self.assertEqual({k: v for k, v in before.items() if k != 'marketMappings'},
                             {k: v for k, v in after.items() if k != 'marketMappings'})
            if before['marketMappings']:
                self.assertEqual(before['marketMappings'], after['marketMappings'])

    def test_conflicting_title_and_missing_lane_are_held(self):
        self.assertFalse(reviewed_title_matches('Limejuice (Pirate Foil)', 'Limejuice (Reprint)',
                                                'Limejuice', 'OP09-014', 'Standard artwork'))
        prices = json.loads(self.prices)
        prices['results'] = [p for p in prices['results'] if p['productId'] != 656037]
        report = self.run_prepare(copy.deepcopy(self.baseline), prices=json.dumps(prices).encode())
        decision = next(d for d in report['verifiedPrintingFinishes'] if d['number'] == 'OP09-014'
                        and d['treatment'] == 'Standard artwork')
        self.assertEqual(decision['reason'], 'marketplace has no unique exact finish lane')

    def test_duplicate_lane_is_rejected(self):
        prices = json.loads(self.prices)
        prices['results'].append(copy.deepcopy(prices['results'][0]))
        with self.assertRaises(ValueError):
            self.run_prepare(copy.deepcopy(self.baseline), prices=json.dumps(prices).encode())

    def test_revision_five_preserves_the_signed_revision_four_registry(self):
        path = ROOT / 'publisher/one-piece/prb02-revision-5/previous-envelope.json'
        payload = json.loads(path.read_bytes())['payload']
        baseline = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))
        candidate = json.loads((path.parent / 'candidate.json').read_bytes())
        self.assertEqual((baseline['revision'], candidate['revision']), (4, 5))
        self.assertEqual({k: v for k, v in baseline['registry'].items() if k != 'printings'},
                         {k: v for k, v in candidate['registry'].items() if k != 'printings'})
        before = {p['id']: p for p in baseline['registry']['printings']}
        after = {p['id']: p for p in candidate['registry']['printings']}
        self.assertEqual(before.keys(), after.keys())
        additions = 0
        for key, old in before.items():
            new = after[key]
            self.assertEqual({k: v for k, v in old.items() if k != 'marketMappings'},
                             {k: v for k, v in new.items() if k != 'marketMappings'})
            if old['marketMappings']:
                self.assertEqual(old['marketMappings'], new['marketMappings'])
            elif new['marketMappings']:
                self.assertEqual(old.get('releaseID'), 'product:prb02-premium-booster-the-best-vol-2-2025')
                additions += 1
        self.assertEqual(additions, 265)


if __name__ == '__main__':
    unittest.main()
