import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_lorcana_market_catalog import ORIGINAL_GROUPS, build, validate_previous, reviewed_finishes


class MarketCatalogTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.row = dict(id='lorcanajson:en:1', name='Ariel - On Human Legs', setCode='1', sourceSetCode='1',
            setName='The First Chapter', foilTypes=['None','Silver'], rarity='Uncommon', layout='normal',
            imageURL='https://api.lorcana.ravensburger.com/images/en/set1/1_fixture.jpg',
            footer=dict(collectorNumber='1',denominator='204',language='en',printedSetMarker='1'))
        self.product = dict(productId=494102,categoryId=71,groupId=22937,name=self.row['name'],extendedData=[dict(name='Number',value='1/204')])
        self.products=[self.product]
        self.prices=[dict(productId=494102,subTypeName=x,marketPrice=None) for x in ['Normal','Cold Foil']]
        self.rows=[self.row]
        self.groupID = 22937
    def tearDown(self):
        self.tmp.cleanup()
    def run_build(self, ledger=None, review_later=False, review_disney100=False):
        def write(name,obj):
            p=self.root/name;p.write_text(json.dumps(obj));return p
        discovery=write('discovery.json',dict(cards=self.rows))
        baseline=write('base.json',dict(schemaVersion=2,reviewedAt=1,canonicalCards=[],physicalPrintings=[],printFamilies=[],universes=[],corrections=[]))
        write('groups-selected.json',[dict(code=self.row['setCode'],name='Fixture',groupID=self.groupID)])
        write(f'{self.groupID}-products.json',dict(success=True,errors=[],results=self.products,totalItems=len(self.products)))
        write(f'{self.groupID}-prices.json',dict(success=True,errors=[],results=self.prices))
        return build(discovery,self.root,baseline,ledger or {},review_later_expansions=review_later,review_disney100=review_disney100)
    def testExactJoinAllocatesStableIDsWithoutInferringFinishFromPrice(self):
        m,ledger,r=self.run_build()
        self.assertEqual(r['mappingCount'],2)
        p=m['physicalPrintings'][0]
        self.assertEqual([x['providerVariantID'] for x in p['marketMappings']],['Normal','Cold Foil'])
        self.assertEqual(m,self.run_build(ledger)[0])
        self.row['foilTypes']=['Lava']
        self.assertEqual(self.run_build(ledger)[2]['mappingCount'],0)
    def testAmbiguousFooterQualifiedSiblingAndDuplicateLanesAreHeld(self):
        self.rows.append(dict(self.row,id='tcgcsv:71:2'))
        self.assertEqual(self.run_build()[2]['mappingCount'],0)
        self.rows=self.rows[:1]
        self.products.append(dict(self.product,productId=2,name=self.row['name']+' (Alternate Art)'))
        self.assertEqual(self.run_build()[2]['mappingCount'],0)
        self.products=self.products[:1]
        self.prices.append(self.prices[1])
        self.assertEqual(self.run_build()[2]['mappingCount'],0)
    def testWrongGroupAndWrongNumberCannotAuthorizeMapping(self):
        self.product['groupId']=3
        with self.assertRaises(ValueError): self.run_build()
        self.product['groupId']=22937
        self.product['extendedData'][0]['value']='2/204'
        self.assertEqual(self.run_build()[2]['mappingCount'],0)

    def testOrdinaryPhysicalPolicyRejectsOtherScopesAndTreatments(self):
        baseline = copy.deepcopy(self.row)
        for changes in [
            {'setCode': '99', 'sourceSetCode': '99'},
            {'sourceSetCode': '2'},
            {'distribution': 'D23'},
            {'layout': 'token'},
            {'rarity': 'Iconic'},
            {'foilTypes': ['None', 'Silver', 'Silver']},
            {'imageURL': 'https://api.lorcana.ravensburger.com/images/en/set2/1_fixture.jpg'},
        ]:
            with self.subTest(changes=changes):
                self.row.clear(); self.row.update(copy.deepcopy(baseline)); self.row.update(changes)
                self.assertIsNone(reviewed_finishes(self.row))
                self.assertEqual(self.run_build()[2]['mappingCount'], 0)
        self.row.clear(); self.row.update(copy.deepcopy(baseline))
        self.row['footer']['printedSetMarker'] = '2'
        self.assertIsNone(reviewed_finishes(self.row))
        self.assertEqual(self.run_build()[2]['mappingCount'], 0)

    def testOriginalExpansionCannotBorrowAnotherSelectedMarketGroup(self):
        self.groupID = self.product['groupId'] = 23303
        with self.assertRaises(ValueError): self.run_build()

    def testAdoptedOriginalPrintingsRetainTheirExactFinishAndGroupMappings(self):
        seed = Path(__file__).resolve().parents[2] / 'TradingCardScanner/LorcanaCatalogSeed'
        sources = {row['id']: row for row in json.loads((seed / 'discovery.json').read_bytes())['cards']}
        market = json.loads((seed / 'market.json').read_bytes())
        checked = 0
        for printing in market['physicalPrintings']:
            mappings = printing.get('marketMappings') or []
            if not mappings or printing['providerSetCode'] not in ORIGINAL_GROUPS:
                continue
            with self.subTest(printing=printing['id']):
                rows = [sources[alias['id']] for alias in printing['sourceAliases'] if alias['id'] in sources]
                self.assertEqual(len(rows), 1)
                row = rows[0]
                self.assertEqual(sorted(reviewed_finishes(row)),
                    sorted((mapping['finish'], mapping['providerVariantID']) for mapping in mappings))
                self.assertEqual({mapping['groupID'] for mapping in mappings}, {ORIGINAL_GROUPS[row['setCode']]})
                checked += 1
        self.assertGreater(checked, 0)
    def testPreviouslyAllocatedIdentityCannotBeRemovedOrChanged(self):
        m,_,_=self.run_build();changed=copy.deepcopy(m)
        changed['physicalPrintings'][0]['identity']['size']='oversized'
        with self.assertRaises(ValueError): validate_previous(changed,m)
        changed=copy.deepcopy(m);changed['physicalPrintings']=[]
        with self.assertRaises(ValueError): validate_previous(changed,m)

    def enchanted(self):
        self.row.update(name='Hades - King of Olympus', rarity='Enchanted', number='205', foilTypes=['Lava'],
            imageURL='https://api.lorcana.ravensburger.com/images/en/set1/205_example.jpg')
        self.row['footer']['collectorNumber'] = '205'
        self.product.update(name=self.row['name']+' (Enchanted)')
        self.product['extendedData']=[dict(name='Number',value='205/204'),dict(name='Rarity',value='Enchanted')]
        self.prices=[dict(productId=494102,subTypeName='Holofoil',marketPrice=None)]

    def testEnchantedIsAnExactSeparateFoilPrintingWithStableIdentity(self):
        self.enchanted()
        manifest,ledger,report=self.run_build()
        self.assertEqual(report['mappingCount'],1)
        printing=manifest['physicalPrintings'][0]
        self.assertEqual(printing['identity']['distributionID'],'enchanted-expansion-1')
        self.assertEqual([x['finish'] for x in printing['finishes']],['foil'])
        self.assertEqual(printing['marketMappings'][0]['providerVariantID'],'Holofoil')
        self.assertEqual(manifest,self.run_build(ledger)[0])

    def testEnchantedCannotBorrowOrdinaryFinishOrUnreviewedPattern(self):
        self.enchanted()
        self.prices.append(dict(productId=494102,subTypeName='Normal'))
        self.assertEqual(self.run_build()[2]['mappingCount'],0)
        self.prices=self.prices[:1]
        for patterns in [['Silver'],['Lava','None'],['Magma']]:
            self.row['foilTypes']=patterns
            self.assertEqual(self.run_build()[2]['mappingCount'],0)
        self.row['foilTypes']=['Lava']
        self.product['extendedData'][1]['value']='Legendary'
        self.assertEqual(self.run_build()[2]['mappingCount'],0)

    def disney100(self):
        self.groupID=23305
        self.row.update(id='lorcanajson:en:676',name='Mickey Mouse - Friendly Face',setCode='P1',sourceSetCode='2',
            distribution="Disney 100 Collector's Set",rarity='Special',foilTypes=['Satin'],
            imageURL='https://api.lorcana.ravensburger.com/images/en/promo1/18_fixture.jpg')
        self.row['footer'].update(collectorNumber='18',denominator='P1',printedSetMarker='2')
        self.product.update(productId=516448,groupId=23305,name=self.row['name']+' (Alternate Art)',
            extendedData=[dict(name='Number',value='18'),dict(name='Rarity',value='Promo')])
        self.prices=[dict(productId=516448,subTypeName='Holofoil')]

    def testDisney100RequiresOptInAndPreservesPrintedSignatureIdentity(self):
        self.disney100()
        self.assertEqual(self.run_build()[2]['mappingCount'],0)
        manifest,ledger,report=self.run_build(review_disney100=True)
        self.assertEqual(report['mappingCount'],1)
        printing=manifest['physicalPrintings'][0]
        self.assertEqual(printing['identity']['distributionID'],'disney100-collectors-set')
        self.assertEqual(printing['identity']['stamp'],'Disney100 printed animator signature')
        self.assertEqual([x['finish'] for x in printing['finishes']],['foil'])
        self.assertEqual(manifest,self.run_build(ledger,review_disney100=True)[0])

    def testDisney100CannotBorrowDifferentDistributionSizePatternOrProduct(self):
        self.disney100()
        for key,value in [('distribution','D23'),('layout','landscape'),('foilTypes',['None','Satin']),
                          ('sourceSetCode','1'),('id','lorcanajson:en:999')]:
            old=self.row[key];self.row[key]=value
            self.assertEqual(self.run_build(review_disney100=True)[2]['mappingCount'],0)
            self.row[key]=old
        self.product['productId']=999
        self.assertEqual(self.run_build(review_disney100=True)[2]['mappingCount'],0)
        self.product['productId']=516448;self.product['extendedData'][1]['value']='Legendary'
        self.assertEqual(self.run_build(review_disney100=True)[2]['mappingCount'],0)

    def testDisney100RejectsUnexpectedSiblingLaneAndMarketGroup(self):
        self.disney100()
        self.products.append(dict(self.product,productId=999,name=self.row['name']+' (Oversized)'))
        self.assertEqual(self.run_build(review_disney100=True)[2]['mappingCount'],0)
        self.products=self.products[:1];self.prices.append(dict(productId=516448,subTypeName='Normal'))
        self.assertEqual(self.run_build(review_disney100=True)[2]['mappingCount'],0)
        self.groupID=self.product['groupId']=23528
        with self.assertRaises(ValueError):self.run_build(review_disney100=True)

    def later(self, code='13', number='207', denominator='207'):
        self.groupID={'9':24348,'10':24414,'11':24500,'12':24617,'13':24666,'14':24740}[code]
        self.product['groupId']=self.groupID
        self.row.update(setCode=code, sourceSetCode=code, distribution=None,
            imageURL=f'https://api.lorcana.ravensburger.com/images/en/set{code}/{number}_fixture.jpg')
        self.row['footer'].update(printedSetMarker=code, collectorNumber=number, denominator=denominator)
        self.product['extendedData'][0]['value']=number+'/'+denominator
        rarity_fields=[f for f in self.product['extendedData'] if f['name']=='Rarity']
        if rarity_fields: rarity_fields[0]['value']=self.row['rarity']
        else: self.product['extendedData'].append(dict(name='Rarity',value=self.row['rarity']))

    def testDenominator207IsScopedAndRequiresExplicitReviewMode(self):
        self.later()
        self.assertEqual(self.run_build()[2]['mappingCount'],0)
        manifest,ledger,report=self.run_build(review_later=True)
        self.assertEqual(report['mappingCount'],2)
        self.assertEqual(manifest['physicalPrintings'][0]['identity']['footer']['denominator'],'207')
        self.assertEqual(self.run_build(ledger,review_later=True)[0],manifest)
        self.row['setCode']=self.row['sourceSetCode']=self.row['footer']['printedSetMarker']='12'
        self.assertIsNone(reviewed_finishes(self.row,True))

    def testEveryLaterOrdinaryExpansionRequiresExplicitReviewMode(self):
        for code in map(str, range(9, 15)):
            with self.subTest(code=code):
                self.later(code=code, number='1', denominator='207' if code == '13' else '204')
                self.assertEqual(self.run_build()[2]['mappingCount'], 0)
                self.assertEqual(self.run_build(review_later=True)[2]['mappingCount'], 2)

    def testLaterPolicyRejectsCrossScopeDistributionAndAdditionalFoilPatterns(self):
        self.later()
        for key,value in [('sourceSetCode','12'),('distribution','promo'),('imageURL','https://example.com/207.jpg'),('layout','token')]:
            original=self.row.get(key);self.row[key]=value
            self.assertIsNone(reviewed_finishes(self.row,True));self.row[key]=original
        self.row['foilTypes']=['None','Silver','RainbowPillars']
        self.assertIsNone(reviewed_finishes(self.row,True))
        self.row['foilTypes']=['None','Silver','Silver']
        self.assertIsNone(reviewed_finishes(self.row,True))
        self.row['foilTypes']=['None','Silver'];self.row['rarity']='Epic'
        self.assertIsNone(reviewed_finishes(self.row,True))

    def testLaterSelectedMarketGroupCannotBorrowAnotherExpansion(self):
        self.later()
        self.groupID=self.product['groupId']=24500
        with self.assertRaises(ValueError): self.run_build(review_later=True)

    def testWhisperSingleFoilAndFabledZeroAreScopedWithoutCollapsingMixedPatterns(self):
        self.later(code='10',number='2',denominator='204')
        self.row['foilTypes']=['None','FreeForm1']
        self.assertEqual(reviewed_finishes(self.row,True),[('normal','Normal'),('foil','Holofoil')])
        self.row['foilTypes'].reverse()
        self.assertEqual(reviewed_finishes(self.row,True),[('normal','Normal'),('foil','Holofoil')])
        self.row['foilTypes'].append('RainbowPillars')
        self.assertIsNone(reviewed_finishes(self.row,True))
        self.later(code='9',number='0',denominator='204');self.row['foilTypes']=['None','Silver']
        self.assertIsNone(reviewed_finishes(self.row,True))
        self.row.update(id='lorcanajson:en:1936',name='Bruno Madrigal - Undetected Uncle')
        self.assertEqual(reviewed_finishes(self.row,True),[('normal','Normal'),('foil','Cold Foil')])
        self.later(code='11',number='0',denominator='204')
        self.assertIsNone(reviewed_finishes(self.row,True))
        self.row['foilTypes']=['None','Silver'];self.row['rarity']='Epic'
        self.assertIsNone(reviewed_finishes(self.row,True))

    def testLaterSpecialRaritiesHaveDistinctPhysicalIdentityAndOneFoil(self):
        for rarity,number,pattern in [('Epic','208','Satin'),('Enchanted','226','Magma'),('Iconic','244','Lore')]:
            self.later(number=number)
            self.row.update(rarity=rarity,foilTypes=[pattern])
            self.product.update(name=self.row['name']+f' ({rarity})')
            self.product['extendedData']=[dict(name='Number',value=number+'/207'),dict(name='Rarity',value=rarity)]
            self.prices=[dict(productId=self.product['productId'],subTypeName='Holofoil')]
            manifest,_,report=self.run_build(review_later=True)
            self.assertEqual(report['mappingCount'],1)
            printing=manifest['physicalPrintings'][0]
            self.assertEqual(printing['identity']['distributionID'],rarity.lower()+'-expansion-13')
            self.assertEqual([x['finish'] for x in printing['finishes']],['foil'])
            self.product['extendedData'][1]['value']='Legendary'
            self.assertEqual(self.run_build(review_later=True)[2]['mappingCount'],0)

    def testReviewedSplitProductsBindNormalAndFoilWithoutAdmittingOtherSiblings(self):
        self.later(code='11',number='113',denominator='204')
        self.product.update(productId=675499)
        foil=copy.deepcopy(self.product);foil.update(productId=678861,name=self.row['name']+' (Foil)')
        self.products=[self.product,foil]
        self.prices=[dict(productId=675499,subTypeName='Normal'),dict(productId=678861,subTypeName='Cold Foil')]
        self.assertEqual(self.run_build()[2]['mappingCount'],0)
        manifest,_,report=self.run_build(review_later=True)
        self.assertEqual(report['mappingCount'],2)
        self.assertEqual([(x['finish'],x['productID']) for x in manifest['physicalPrintings'][0]['marketMappings']],
            [('normal',675499),('foil',678861)])
        self.products.append(dict(foil,productId=999,name=self.row['name']+' (Alternate Art)'))
        self.assertEqual(self.run_build(review_later=True)[2]['mappingCount'],0)
        self.products=self.products[:2];self.prices.append(self.prices[-1])
        self.assertEqual(self.run_build(review_later=True)[2]['mappingCount'],0)
        self.prices=self.prices[:2]
        foil['extendedData'].append(dict(name='Rarity',value='Legendary'))
        self.assertEqual(self.run_build(review_later=True)[2]['mappingCount'],0)


if __name__=='__main__': unittest.main()
