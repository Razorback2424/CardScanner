import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from audit_catalog_coverage import lorcana_hold_reason
from build_lorcana_market_catalog import build
import reconcile_lorcana_promo_distributions as promo

GROUP = 23234


def card(identity, number, name, foil='Silver', printed='5', distribution='Organized Play', code='P2'):
    return dict(id=f'lorcanajson:en:{identity}', name=name, number=number, setCode=code, sourceSetCode=printed,
                setName='Promo Set 2', printedIdentifier=f'{number}/{code} • EN • {printed}', rarity='Special',
                layout='normal', foilTypes=[foil], distribution=distribution,
                imageURL=f'https://example.com/{identity}.jpg',
                footer=dict(collectorNumber=number, denominator=code, language='en', printedSetMarker=printed))


def product(identity, number, name, rarity='Promo'):
    return dict(productId=identity, categoryId=71, groupId=GROUP, name=name,
                extendedData=[dict(name='Rarity', value=rarity), dict(name='Number', value=number)])


class PromoDistributionTests(unittest.TestCase):
    def setUp(self):
        self.rows = [card(1, '3', 'Nala - Mischievous Cub'), card(2, '7', 'Mirabel Madrigal - Family Gatherer', 'VerticalWave'),
                     card(3, '24A', 'Hiro Hamada - Armor Designer', 'None', printed='7')]
        self.products = [product(561996, '3', 'Nala - Mischievous Cub'),
                         product(561210, '7', 'Mirabel Madrigal - Family Gatherer (Store Championship)'),
                         product(620277, '24A', 'Hiro Hamada - Armor Designer (Store Championship Participant)'),
                         product(561998, '3', 'Chicha - Dedicated Mother')]  # Same number, another promo set.
        self.lanes = {561996: ['Cold Foil'], 561210: ['Holofoil'], 620277: ['Normal']}
        self.rules = dict(schemaVersion=1, rules=[dict(
            id='p2-organized-play', kind='organizedPlay', label='Organized Play', setCode='P2',
            distribution='Organized Play', groupID=GROUP, expectedCount=3,
            finishes={'Silver': ['Cold Foil'], 'VerticalWave': ['Holofoil'], 'None': ['Normal']},
            marketRarities=['Promo'], stamp=None, physicalReleaseEvidence='https://example.com/gallery')], holds=[])
        self.evidence = dict(schemaVersion=1, records=[])

    def market(self):
        return {GROUP: dict(products=self.products, sha256='b' * 64,
                            lanes={k: list(v) for k, v in self.lanes.items()} | {})}

    def run_pass(self, links=None, evidence=None):
        market = self.market()
        market[GROUP]['lanes'] = __import__('collections').defaultdict(list, market[GROUP]['lanes'])
        return promo.reconcile(self.rows, market, self.rules, evidence or self.evidence, links)

    def held(self, report):
        return {h['sourceCardID']: h['reason'] for h in report['holds']}

    def test_exact_number_and_title_create_physical_evidence(self):
        evidence, report = self.run_pass()
        self.assertEqual(self.held(report), {})
        records = {r['sourceCardID']: r for r in evidence['records']}
        self.assertEqual(records['lorcanajson:en:1']['productID'], 561996)
        self.assertEqual(records['lorcanajson:en:1']['marketLane'], 'Cold Foil')
        self.assertEqual(records['lorcanajson:en:1']['marketRarity'], 'Promo')
        self.assertEqual(records['lorcanajson:en:1']['reference'], f'https://tcgcsv.com/tcgplayer/71/{GROUP}/products')
        self.assertEqual(records['lorcanajson:en:2']['sourceName'], 'Mirabel Madrigal - Family Gatherer')
        self.assertEqual(records['lorcanajson:en:2']['expectedName'], 'Mirabel Madrigal - Family Gatherer (Store Championship)')
        self.assertIsNone(records['lorcanajson:en:3']['marketLane'])
        self.assertEqual(records['lorcanajson:en:3']['distributionID'], 'promo-p2-organized-play')
        self.assertTrue(all(r['physicalReleaseEvidence'] == 'https://example.com/gallery' for r in records.values()))

    def test_replay_is_idempotent(self):
        first, _ = self.run_pass()
        second, _ = self.run_pass(evidence=copy.deepcopy(first))
        self.assertEqual(first, second)

    def test_count_drift_holds_the_whole_rule(self):
        self.rules['rules'][0]['expectedCount'] = 4
        evidence, report = self.run_pass()
        self.assertEqual(set(self.held(report).values()), {'ruleCountDrift'})
        self.assertEqual(evidence['records'], [])
        self.rules['rules'][0]['expectedCount'] = 3
        self.rules['rules'][0]['expectedProducts'] = 2
        _, report = self.run_pass()
        self.assertEqual(set(self.held(report).values()), {'ruleCountDrift'})

    def test_missing_ambiguous_and_conflicting_products_are_held(self):
        self.products = self.products[1:]
        self.rules['rules'][0]['expectedProducts'] = 2
        self.assertEqual(self.held(self.run_pass()[1]), {'lorcanajson:en:1': 'noMarketProduct'})
        self.products.append(product(9, '3', 'Nala - Mischievous Cub (Foil)'))
        self.products.append(product(10, '3', 'Nala - Mischievous Cub'))
        self.assertEqual(self.held(self.run_pass()[1]), {'lorcanajson:en:1': 'ambiguousMarketProduct'})

    def test_source_link_must_agree(self):
        report = self.run_pass(links={'lorcanajson:en:1': 561998})[1]
        self.assertEqual(self.held(report)['lorcanajson:en:1'], 'sourceLinkConflict')

    def test_finish_and_lane_gates(self):
        self.lanes[561996] = ['Normal']
        self.assertEqual(self.held(self.run_pass()[1])['lorcanajson:en:1'], 'finishLaneConflict')
        self.lanes[561996] = ['Cold Foil', 'Holofoil']
        self.assertEqual(self.held(self.run_pass()[1])['lorcanajson:en:1'], 'finishLaneConflict')
        self.lanes[561996] = []
        evidence, report = self.run_pass()
        self.assertEqual(self.held(report), {})  # Not yet priced is a known gap, not a hold.
        self.assertEqual(next(r for r in evidence['records'] if r['productID'] == 561996)['marketLane'], 'Cold Foil')
        self.rows[0]['foilTypes'] = ['Glitter']
        self.assertEqual(self.held(self.run_pass()[1])['lorcanajson:en:1'], 'finishOutsideRule')

    def test_shared_footer_needs_an_owner_decision(self):
        self.rows.append(dict(card(4, '3', 'Vaiana - Mischievous Cub'), distribution='Other'))
        self.assertEqual(self.held(self.run_pass()[1])['lorcanajson:en:1'], 'sharedFooter')

    def test_existing_records_are_upgraded_or_block_on_conflict(self):
        alias = dict(productID=561996, expectedName='Nala - Mischievous Cub', sourceCardID='lorcanajson:en:1',
                     reference='https://example.com/scan.jpg', bodySHA256='a' * 64)
        evidence, report = self.run_pass(evidence=dict(schemaVersion=1, records=[alias]))
        upgraded = next(r for r in evidence['records'] if r['productID'] == 561996)
        self.assertEqual(upgraded['reference'], 'https://example.com/scan.jpg')
        self.assertNotIn('createdByDistributionRule', upgraded)
        self.assertEqual(upgraded['printedIdentifier'], '3/P2 • EN • 5')
        replay, _ = self.run_pass(evidence=copy.deepcopy(evidence))
        self.assertEqual(replay, evidence)
        conflict = dict(alias, sourceCardID='lorcanajson:en:99')
        report = self.run_pass(evidence=dict(schemaVersion=1, records=[conflict]))[1]
        self.assertEqual(self.held(report)['lorcanajson:en:1'], 'evidenceConflict')

    def test_rules_select_each_card_once_and_validate_lanes(self):
        duplicate = copy.deepcopy(self.rules['rules'][0]) | {'id': 'again'}
        self.rules['rules'].append(duplicate)
        with self.assertRaises(promo.RuleError):
            self.run_pass()
        self.rules['rules'].pop()
        self.rules['rules'][0]['finishes']['None'] = ['Holofoil']
        with self.assertRaises(promo.RuleError):
            self.run_pass()

    def test_cli_refuses_to_write_when_holds_differ_from_review(self):
        self.products = self.products[1:]
        self.rules['rules'][0]['expectedProducts'] = 2
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / f'{GROUP}-products.json').write_text(json.dumps(dict(success=True, errors=[], results=self.products)))
            prices = [dict(productId=k, subTypeName=lane) for k, v in self.lanes.items() for lane in v]
            (root / f'{GROUP}-prices.json').write_text(json.dumps(dict(success=True, errors=[], results=prices)))
            (root / 'discovery.json').write_text(json.dumps(dict(cards=self.rows)))
            (root / 'rules.json').write_text(json.dumps(self.rules))
            (root / 'evidence.json').write_text(json.dumps(self.evidence))
            args = ['--discovery', str(root / 'discovery.json'), '--market', str(root), '--rules', str(root / 'rules.json'),
                    '--evidence', str(root / 'evidence.json'), '--output', str(root / 'out.json')]
            self.assertEqual(promo.main(args), 1)
            self.assertFalse((root / 'out.json').exists())
            self.rules['holds'] = [dict(sourceCardID='lorcanajson:en:1', printedIdentifier='3/P2 • EN • 5',
                                        reason='noMarketProduct', detail='Reviewed: no product yet')]
            (root / 'rules.json').write_text(json.dumps(self.rules))
            self.assertEqual(promo.main(args), 0)
            self.assertEqual(len(json.loads((root / 'out.json').read_text())['records']), 2)


class PromoPromotionThroughBuilderTests(unittest.TestCase):
    """The reconciler's records go through the market builder's existing reviewed-product path."""

    def test_promo_evidence_promotes_with_market_rarity(self):
        row = card(1, '3', 'Nala - Mischievous Cub')
        rows, rules = [row], dict(schemaVersion=1, rules=[dict(
            id='p2-organized-play', kind='organizedPlay', label='Organized Play', setCode='P2', distribution='Organized Play',
            groupID=GROUP, expectedCount=1, finishes={'Silver': ['Cold Foil']}, marketRarities=['Promo'], stamp=None,
            physicalReleaseEvidence='https://example.com/gallery')], holds=[])
        products = [product(561996, '3', 'Nala - Mischievous Cub')]
        market = {GROUP: dict(products=products, sha256='b' * 64,
                              lanes=__import__('collections').defaultdict(list, {561996: ['Cold Foil']}))}
        evidence, _ = promo.reconcile(rows, market, rules, dict(schemaVersion=1, records=[]))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'discovery.json').write_text(json.dumps(dict(cards=rows, coverage=dict(productEvidence=evidence['records']))))
            (root / 'base.json').write_text(json.dumps(dict(schemaVersion=2, reviewedAt=1, canonicalCards=[],
                physicalPrintings=[], printFamilies=[], universes=[], corrections=[])))
            (root / 'groups-selected.json').write_text(json.dumps([dict(code='CC2', groupID=GROUP)]))
            (root / f'{GROUP}-products.json').write_text(json.dumps(dict(success=True, errors=[], results=products)))
            (root / f'{GROUP}-prices.json').write_text(json.dumps(dict(success=True, errors=[],
                results=[dict(productId=561996, subTypeName='Cold Foil')])))
            manifest, _, report = build(root / 'discovery.json', root, root / 'base.json', {})
            printing = manifest['physicalPrintings'][0]
            self.assertEqual(printing['identity']['distributionID'], 'promo-p2-organized-play')
            self.assertEqual([(m['finish'], m['providerVariantID']) for m in printing['marketMappings']], [('foil', 'Cold Foil')])
            self.assertEqual(report['mappedPrintingCount'], 1)
            evidence['records'][0]['marketRarity'] = 'Special'
            (root / 'discovery.json').write_text(json.dumps(dict(cards=rows, coverage=dict(productEvidence=evidence['records']))))
            _, _, report = build(root / 'discovery.json', root, root / 'base.json', {})
            self.assertEqual(report['decisions'][0]['status'], 'held')


class LedgerReasonTests(unittest.TestCase):
    def test_reasons_are_stable_and_reviewed_holds_win(self):
        row = card(1, '3', 'Nala - Mischievous Cub')
        self.assertEqual(lorcana_hold_reason(row, {}, {})[0], 'promoDistribution')
        reviewed = {row['id']: dict(reason='sharedFooter', detail='Owner decision')}
        self.assertEqual(lorcana_hold_reason(row, {}, reviewed), ('sharedFooter', 'Owner decision'))
        self.assertEqual(lorcana_hold_reason(dict(row, name='Mickey (Serial Numbered)'), {}, {})[0], 'heldSerialized')
        self.assertEqual(lorcana_hold_reason(row, {'en:5:3:P2': {}}, {})[0], 'incompleteFamily')
        self.assertEqual(lorcana_hold_reason(dict(row, footer=None), {}, {})[0], 'noFooter')
        market = dict(row, id='tcgcsv:71:5', footer=None, printedIdentifier='5', name='Baymax - Lab Assistant')
        self.assertEqual(lorcana_hold_reason(market, {}, {})[0], 'marketOnly')
        oversized = dict(market, printedIdentifier='EN • Q1', name='Ursula - Ruler of Lorcana (Oversized)')
        self.assertEqual(lorcana_hold_reason(oversized, {}, {})[0], 'noFooter')
        self.assertEqual(lorcana_hold_reason(dict(row, setCode='5'), {}, {})[0], 'expansionReview')


if __name__ == '__main__':
    unittest.main()
