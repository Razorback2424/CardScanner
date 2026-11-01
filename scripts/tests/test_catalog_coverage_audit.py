import copy
import hashlib
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from audit_catalog_coverage import (
    Audit, CatalogIntegrityError, compare_magic_audit, one_piece_registry,
    validate_magic_treatments, validate_pokemon_slots, yugioh_summary,
)


PRINTING = 'aaaaaaaa-1111-4111-8111-111111111111'
ARTWORK = 'bbbbbbbb-2222-4222-8222-222222222222'
CARD = 'cccccccc-3333-4333-8333-333333333333'


class CatalogCoverageAuditTests(unittest.TestCase):
    def testReceiptsHashExactBytesAndRejectDuplicateObjectKeysOrOutsideResources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            raw = b'{"a": 1}\n'
            (root / 'fixture.json').write_bytes(raw)
            audit = Audit(root)
            self.assertEqual(audit.json('fixture.json'), {'a': 1})
            self.assertEqual(audit.sources['fixture.json'],
                {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()})
            (root / 'fixture.json').write_text('{"a": 1, "a": 2}')
            with self.assertRaisesRegex(CatalogIntegrityError, 'duplicate identity'):
                audit.json('fixture.json')
            with self.assertRaisesRegex(CatalogIntegrityError, 'escapes repository'):
                audit.text('../outside.json')

    def testPokemonFinishSlotsMayShareProviderCardButNotPhysicalSlotIdentity(self):
        set_id = dict(game='pokemon', providerID='fixture', pokemonPrintRun='unlimited')
        entry = dict(providerID='fixture', set=dict(catalogID=set_id), resource='fixture.json')
        standard = dict(game='pokemon', providerID='fixture-1', setID=set_id,
            masterSetVariant=dict(id='normal'), isExpandedMasterSetVariant=False)
        reverse = dict(standard, masterSetVariant=dict(id='reverse'), isExpandedMasterSetVariant=True)
        self.assertEqual(validate_pokemon_slots(entry, [standard, reverse]), dict(rows=2, standardSlots=1))
        with self.assertRaisesRegex(CatalogIntegrityError, 'duplicate identity'):
            validate_pokemon_slots(entry, [standard, copy.deepcopy(standard)])
        wrong_run = dict(standard, setID=dict(set_id, pokemonPrintRun='firstEdition'))
        with self.assertRaisesRegex(CatalogIntegrityError, 'another set'):
            validate_pokemon_slots(entry, [wrong_run])

    def testMagicTreatmentNormalizationMatchesRuntimeAndPreservesUnknownIDs(self):
        row = dict(id=PRINTING, treatments=[' NeonInk ', '', 'FutureTreatment'], qualifiers={'NEONINK ': ' red '})
        self.assertEqual(validate_magic_treatments(row), ['neonink', 'futuretreatment'])
        for changes in [
            dict(treatments=[' ', '']),
            dict(treatments=['neonink', ' NEONINK ']),
            dict(qualifiers={'unrelated': 'red'}),
            dict(qualifiers={'neonink': ' '}),
            dict(qualifiers={'neonink': 'red', 'NEONINK': 'red'}),
        ]:
            with self.subTest(changes=changes), self.assertRaises(CatalogIntegrityError):
                validate_magic_treatments(dict(row, **changes))

    def testMagicAuditDriftIsReportedWithoutBecomingACatalogPromotionGate(self):
        row = dict(id=PRINTING, setCode='NEO', collectorNumber='429')
        runtime = dict(sourceContentSHA256='a' * 64, sourceBulkDataID='bulk', sourceBulkDataType='default_cards',
            sourceAuditSchemaVersion=2, sourceAuditRulesVersion=2, entries=[row])
        snapshot = dict(source=dict(contentSHA256='a' * 64, bulkDataID='bulk', bulkDataType='default_cards'),
            schemaVersion=2, rulesVersion=2, auditedCardCount=1)
        with tempfile.TemporaryDirectory() as directory:
            audit = Audit(directory)
            compare_magic_audit(runtime, snapshot, {PRINTING: dict(row, setCode='neo')}, audit)
            self.assertEqual(audit.discrepancies, [])
            runtime['sourceContentSHA256'] = 'b' * 64
            snapshot['auditedCardCount'] = 2
            compare_magic_audit(runtime, snapshot, {PRINTING: dict(row, collectorNumber='430')}, audit)
            self.assertEqual({row['code'] for row in audit.discrepancies},
                {'runtimeAuditSourceDifference', 'declaredAuditTotalDifference', 'runtimeTreatmentIdentityDiffersFromAudit'})
            self.assertTrue(all(row['disposition'] == 'review_required' for row in audit.discrepancies))

    def one_piece(self):
        canonical = 'one-piece:en:OP01-001'
        return dict(canonicalCards=[dict(id=canonical, language='en', printingCoverageComplete=False)],
            artworks=[dict(id=ARTWORK)], products=[dict(id='OP01')],
            variants=[dict(id='normal'), dict(id='foil')], appearances=[],
            printings=[dict(id=PRINTING, canonicalCardID=canonical, artworkID=ARTWORK,
                language='en', releaseID='OP01', supportedVariantIDs=['normal'], status='verified',
                marketMappings=[dict(printingID=PRINTING, variantID='normal', provider='tcgplayer',
                    providerVariantID='Normal', productID='1', status='exact')])])

    def testOnePieceRejectsDanglingReferencesAndWrongExactFinish(self):
        for field, value, error in [
            ('canonicalCardID', 'one-piece:en:OP01-999', 'dangling canonical'),
            ('artworkID', CARD, 'dangling canonical/artwork'),
            ('releaseID', 'missing', 'dangling product'),
            ('supportedVariantIDs', ['future-finish'], 'unknown finish'),
        ]:
            with self.subTest(field=field):
                data = self.one_piece()
                data['printings'][0][field] = value
                with self.assertRaisesRegex(CatalogIntegrityError, error):
                    one_piece_registry(data)
        data = self.one_piece()
        data['printings'][0]['marketMappings'][0]['providerVariantID'] = 'Foil'
        with self.assertRaisesRegex(CatalogIntegrityError, 'invalid exact market finish'):
            one_piece_registry(data)

    def testOnePieceHeldIncompleteRecordsAreReportedAndUUIDCaseCannotHideDuplicates(self):
        data = self.one_piece()
        row = data['printings'][0]
        row.update(status='provisional', supportedVariantIDs=[], marketMappings=[])
        summary, _, _ = one_piece_registry(data)
        self.assertEqual(summary['heldOnlyCanonicalCards'], 1)
        self.assertEqual(summary['automaticSingletonFamilies'], 0)
        data['printings'].append(dict(row, id=PRINTING.upper()))
        with self.assertRaisesRegex(CatalogIntegrityError, 'duplicate identity'):
            one_piece_registry(data)

    def yugioh(self):
        return dict(capturedAt='fixture', generation='fixture', sets=[dict(g=1)],
            cards=[dict(id=CARD, n='Fixture')], incompleteCodes=[], autoEligibleCodes=[],
            printings=[dict(id=PRINTING, p=1, k=0, g=1, c='ABC-EN001', pn='Fixture',
                e=['yugiohUnlimited'], pe=[], ec=False, m=[dict(e='yugiohUnlimited')])])

    def testYugiohChoiceAndDiscoveryAreValidButDanglingReferencesAndUnsafeAutoAreNot(self):
        data = self.yugioh()
        summary = yugioh_summary(data)
        self.assertEqual(summary['explicitChoiceOnlyPrintings'], 1)
        data['printings'][0].update(e=[], m=[])
        self.assertEqual(yugioh_summary(data)['discoveryOnlyPrintings'], 1)
        data['autoEligibleCodes'] = ['ABC-EN001']
        with self.assertRaisesRegex(CatalogIntegrityError, 'unique reviewed family'):
            yugioh_summary(data)
        for field, value, error in [
            ('k', 1, 'dangling card/set'),
            ('g', 2, 'dangling card/set'),
            ('e', ['unknown-edition'], 'unsupported edition'),
            ('m', [dict(e='yugioh1stEdition')], 'dangling edition membership'),
        ]:
            with self.subTest(field=field):
                data = self.yugioh()
                data['printings'][0][field] = value
                with self.assertRaisesRegex(CatalogIntegrityError, error):
                    yugioh_summary(data)

    def testYugiohCodeCanonicalConflictsRemainReviewableAndCannotAutoSelect(self):
        data = self.yugioh()
        data['cards'].append(dict(id=ARTWORK, n='Different canonical'))
        data['printings'].append(dict(data['printings'][0], id=ARTWORK, p=2, k=1))
        with tempfile.TemporaryDirectory() as directory:
            audit = Audit(directory)
            summary = yugioh_summary(data, audit)
            self.assertEqual(summary['supportedCodeCanonicalConflicts'], ['ABC-EN001'])
            self.assertEqual(audit.discrepancies[0]['disposition'], 'review_required')
        data['autoEligibleCodes'] = ['ABC-EN001']
        with self.assertRaisesRegex(CatalogIntegrityError, 'unique reviewed family'):
            yugioh_summary(data)


if __name__ == '__main__':
    unittest.main()
