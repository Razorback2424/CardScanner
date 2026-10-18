import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_lorcana_market_catalog import build, validate_previous


class MarketCatalogTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.row = dict(id='lorcanajson:en:1', name='Ariel - On Human Legs', setCode='1', sourceSetCode='1',
            setName='The First Chapter', foilTypes=['None','Silver'], rarity='Uncommon', layout='normal',
            imageURL='https://example.com/ariel.jpg', footer=dict(collectorNumber='1',denominator='204',language='en',printedSetMarker='1'))
        self.product = dict(productId=494102,categoryId=71,groupId=22937,name=self.row['name'],extendedData=[dict(name='Number',value='1/204')])
        self.products=[self.product]
        self.prices=[dict(productId=494102,subTypeName=x,marketPrice=None) for x in ['Normal','Cold Foil']]
        self.rows=[self.row]
    def tearDown(self):
        self.tmp.cleanup()
    def run_build(self, ledger=None):
        def write(name,obj):
            p=self.root/name;p.write_text(json.dumps(obj));return p
        discovery=write('discovery.json',dict(cards=self.rows))
        baseline=write('base.json',dict(schemaVersion=2,reviewedAt=1,canonicalCards=[],physicalPrintings=[],printFamilies=[],universes=[],corrections=[]))
        write('groups-selected.json',[dict(code='1',name='The First Chapter',groupID=22937)])
        write('22937-products.json',dict(success=True,errors=[],results=self.products,totalItems=len(self.products)))
        write('22937-prices.json',dict(success=True,errors=[],results=self.prices))
        return build(discovery,self.root,baseline,ledger or {})
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


if __name__=='__main__': unittest.main()
