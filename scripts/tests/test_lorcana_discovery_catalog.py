import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'build_lorcana_discovery_catalog.py'
spec = importlib.util.spec_from_file_location('lorcana_builder', SCRIPT)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class LorcanaDiscoveryBuilderTests(unittest.TestCase):
    def test_real_footer_formats_keep_promo_order_and_artwork_suffixes(self):
        regular = builder.footer('4a/204 • EN • 3')
        self.assertEqual(regular['collectorNumber'], '4A')
        self.assertEqual(builder.footer('24B/P2 • EN • 7')['denominator'], 'P2')
        d23 = builder.footer('1 TFC • EN • 2/P1')
        self.assertEqual(d23, dict(collectorNumber='2', denominator='P1', language='en', printedSetMarker='1'))
        self.assertIsNone(builder.footer('EN • Q3'))
        with self.assertRaises(ValueError):
            builder.footer('1/204 • EN')
        with self.assertRaises(ValueError):
            builder.footer('1/204 • FR • 1')

    def build_fixture(self, mutate=None, evidence=None):
        source = dict(metadata=dict(language='en', formatVersion='2.4.0', generatedOn='2026-10-10T17:54:17'),
                      sets={'1': dict(name='The First Chapter', prereleaseDate='2023-08-18', releaseDate='2023-09-01',
                                      cardCounts=dict(total=1))}, cards=[dict(id=1, setCode='1', fullIdentifier='1/204 • EN • 1',
                                      fullName='Ariel - On Human Legs', number=1, foilTypes=['None', 'Silver'], rarity='Uncommon',
                                      type='Character', images=dict(full='https://example.com/ariel.jpg'), externalLinks={})])
        product = dict(productId=10, name='The First Chapter Booster Box', groupId=1, categoryId=71,
                       imageUrl='https://example.com/box.jpg', extendedData=[], presaleInfo=dict(releasedOn='2023-08-18'))
        groups = dict(success=True, errors=[], totalItems=1, results=[dict(groupId=1, name='The First Chapter')])
        products = dict(success=True, errors=[], totalItems=1, results=[product])
        if mutate:
            mutate(source, products)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / 'cards.json').write_text(json.dumps(source))
            (path / 'groups.json').write_text(json.dumps(groups))
            (path / '1.json').write_text(json.dumps(products))
            evidence_path = None
            if evidence:
                evidence_path = path / 'evidence.json'
                evidence_path.write_text(json.dumps(dict(schemaVersion=1, records=evidence)))
            return builder.build(path / 'cards.json', path / 'groups.json', path, evidence_path)

    def test_source_count_mismatch_and_duplicate_cards_fail(self):
        def mismatch(source, products):
            source['sets']['1']['cardCounts']['total'] = 2
        with self.assertRaises(AssertionError):
            self.build_fixture(mismatch)
        def duplicate(source, products):
            source['cards'].append(source['cards'][0])
        with self.assertRaises(AssertionError):
            self.build_fixture(duplicate)

    def test_product_count_mismatch_fails(self):
        with self.assertRaises(AssertionError):
            self.build_fixture(lambda source, products: products.update(totalItems=2))

    def test_puzzle_and_oversized_card_are_never_classified_as_sealed(self):
        def puzzle(source, products):
            product = products['results'][0]
            product['name'] = 'Ariel Puzzle Insert (Set of 4)'
            product['extendedData'] = [dict(name='Rarity', value='None')]
        self.assertFalse(self.build_fixture(puzzle)['sealed'])
        def oversized(source, products):
            product = products['results'][0]
            product['name'] = 'Ariel - On Human Legs (Oversized)'
            product['extendedData'] = [dict(name='Rarity', value='Uncommon'), dict(name='Number', value='1/204')]
        result = self.build_fixture(oversized)
        self.assertFalse(result['sealed'])
        supplemental = [card for card in result['cards'] if card['id'].startswith('tcgcsv:')]
        self.assertEqual(len(supplemental), 1)
        self.assertIsNone(supplemental[0]['footer'], 'A name/number match is not inspected footer evidence')
        self.assertEqual(supplemental[0]['foilTypes'], [])

    def test_unknown_products_and_source_schema_require_review(self):
        with self.assertRaises(AssertionError):
            self.build_fixture(lambda source, products: products['results'][0].update(name='Unclassified Product'))
        with self.assertRaises(AssertionError):
            self.build_fixture(lambda source, products: source['metadata'].update(formatVersion='3.0.0'))

    def test_prices_are_not_copied_into_discovery(self):
        result = self.build_fixture(lambda source, products: products['results'][0].update(marketPrice=1234))
        self.assertEqual(len(result['sealed']), 1)
        self.assertNotIn('marketPrice', result['sealed'][0])

    def test_accented_names_and_rarity_qualifiers_join_without_duplicate_cards(self):
        def epic(source, products):
            source['cards'][0].update(fullName='Héctor Rivera - Street Musician', rarity='Epic')
            products['results'][0].update(name='Hector Rivera - Street Musician (Epic)',
                extendedData=[dict(name='Rarity', value='Epic'), dict(name='Number', value='1/204')])
        result = self.build_fixture(epic)
        self.assertEqual(len(result['cards']), 1)
        self.assertEqual(result['coverage']['productJoins'][0]['sourceCardID'], 'lorcanajson:en:1')
        def wrong_set(source, products):
            epic(source, products)
            source['sets']['1']['name'] = 'Another Set'
        result = self.build_fixture(wrong_set)
        self.assertEqual(len(result['cards']), 2)
        self.assertIsNone(result['cards'][1]['footer'])

    def test_reviewed_footer_is_bound_to_exact_product_and_conflicts_fail(self):
        def autograph(source, products):
            products['results'][0].update(name='Ariel - On Human Legs (Autograph)',
                extendedData=[dict(name='Rarity', value='Promo'), dict(name='Number', value='1')])
        proof = dict(productID=10, expectedName='Ariel - On Human Legs (Autograph)',
            printedIdentifier='1/P2 • EN • 1', reference='https://example.com/card.jpg', bodySHA256='a'*64)
        result = self.build_fixture(autograph, [proof])
        self.assertEqual(result['cards'][1]['footer']['denominator'], 'P2')
        bad = dict(proof, printedIdentifier='2/P2 • EN • 1')
        with self.assertRaises(ValueError):
            self.build_fixture(autograph, [bad])
        with self.assertRaises(ValueError):
            self.build_fixture(autograph, [dict(proof, expectedName='Other card')])


if __name__ == '__main__':
    unittest.main()
