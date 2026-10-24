#!/usr/bin/env python3
"""Prepare bounded English physical printings using explicit offline source joins.

No fuzzy/provider fallback or price-column finish inference. UUID assignments are
retained independently in a ledger; ambiguous families and market siblings stay
discovery-only. Existing reviewed Hades identities are retained exactly.
Sets 9–14 and their later rarities require the explicit isolated-review option.
"""
import argparse
import collections
import hashlib
import json
import math
from pathlib import Path
import re
import uuid

from build_lorcana_discovery_catalog import name_key

REVIEW = 'docs/research/lorcana-normal-pricing-rollout.md'
FINISH = 'https://disneyparksblog.com/products/getting-started-with-disney-lorcana-trading-card-game/'
ENCHANTED_FINISH = 'https://www.disneylorcana.com/en-US/news/enchanted-reveal'
# Inspected exact set/number/title spelling difference; never a global fuzzy join.
ENCHANTED_MARKET_NAMES = {('8', '219', 'The Sword of Shan-Yu'): 'The Sword of Shan Yu'}
LATER_REVIEW = 'docs/research/lorcana-expansion-candidate-review-2026-10-23.md'
LATER_RARITIES = 'https://www.disneylorcana.com/en-US/news/2025/08/2025-8-stunning-new-rarities'
LATER_GROUPS = {'9': 24348, '10': 24414, '11': 24500, '12': 24617, '13': 24666, '14': 24740}
DISNEY100_REFERENCE = 'https://www.disneylorcana.com/en-US/news/s2-announcement'
# source ID: (printed number, printed expansion, exact product, source title).
DISNEY100 = {
    'lorcanajson:en:676': ('18', '2', 516448, 'Mickey Mouse - Friendly Face'),
    'lorcanajson:en:677': ('19', '2', 516452, 'Elsa - Gloves Off'),
    'lorcanajson:en:678': ('20', '1', 516454, 'Genie - Powers Unleashed'),
    'lorcanajson:en:679': ('21', '1', 516456, 'Stitch - Abomination'),
    'lorcanajson:en:680': ('22', '1', 516459, 'Maleficent - Uninvited'),
    'lorcanajson:en:681': ('23', '1', 516460, 'Maui - Demigod'),
}
# Explicitly reviewed separate Normal/Foil listings. A generic qualified sibling
# still holds: the product pairs below do not authorize other alternates.
LATER_SPLIT_PRODUCTS = {
    ('11', '113'): (675499, 678861), ('11', '114'): (675500, 678862),
    ('11', '137'): (676217, 678863), ('11', '138'): (676218, 678864),
    ('12', '37'): (692014, 692015), ('12', '38'): (692016, 692017),
    ('12', '39'): (692018, 692019), ('12', '40'): (692020, 692021),
    ('12', '41'): (692022, 692023), ('12', '42'): (692024, 692025),
    ('12', '43'): (692026, 692027), ('12', '44'): (692028, 692029),
    ('12', '81'): (692040, 692041), ('12', '106'): (692050, 692093),
    ('12', '139'): (692179, 692180), ('12', '140'): (692060, 692061),
    ('12', '141'): (692062, 692063), ('12', '184'): (692081, 692082),
    ('12', '185'): (690212, 692097),
    ('13', '74'): (702684, 702683), ('13', '75'): (702686, 702685),
    ('13', '110'): (704619, 704618), ('13', '111'): (704621, 704620),
    ('13', '158'): (704656, 704655), ('13', '159'): (704658, 704657),
}


def reviewed_finishes(row, review_later_expansions=False, review_disney100=False):
    """Physical policy precedes market lookup; a price lane cannot create a finish."""
    f = row['footer']
    code = row['setCode']
    if review_disney100 and row['id'] in DISNEY100:
        number, marker, _, title = DISNEY100[row['id']]
        if (f == dict(collectorNumber=number, denominator='P1', language='en', printedSetMarker=marker)
                and code == 'P1' and row['sourceSetCode'] == marker and row['name'] == title
                and row.get('distribution') == "Disney 100 Collector's Set" and row['layout'] == 'normal'
                and row['foilTypes'] == ['Satin'] and row['rarity'] == 'Special'
                and row['imageURL'].startswith(f'https://api.lorcana.ravensburger.com/images/en/promo1/{number}_')):
            return [('foil', 'Holofoil')]
        return None
    if review_later_expansions and code in {str(i) for i in range(9, 15)}:
        denominator = '207' if code == '13' else '204'
        maximum = int(denominator)
        if (not f or f['language'] != 'en' or f['denominator'] != denominator
                or row['sourceSetCode'] != code or f['printedSetMarker'] != code
                or not re.fullmatch(r'[0-9]+', f['collectorNumber'])
                or row.get('distribution') is not None or row['layout'] not in {'normal', 'landscape'}
                or len(row['foilTypes']) != len(set(row['foilTypes']))
                or not row['imageURL'].startswith(f"https://api.lorcana.ravensburger.com/images/en/set{code}/{f['collectorNumber']}_")):
            return None
        number = int(f['collectorNumber'])
        ordinary_patterns = [{'None', 'Silver'}]
        if code == '10':
            ordinary_patterns.append({'None', 'FreeForm1'})
        minimum = 0 if code == '9' else 1  # Reviewed Bruno 0/204; never a global zero rule.
        if (minimum <= number <= maximum and set(row['foilTypes']) in ordinary_patterns
                and (number != 0 or (row['id'] == 'lorcanajson:en:1936' and row['name'] == 'Bruno Madrigal - Undetected Uncle'))
                and row['rarity'] in {'Common', 'Uncommon', 'Rare', 'Super Rare', 'Legendary'}):
            foil_lane = 'Holofoil' if set(row['foilTypes']) == {'None', 'FreeForm1'} else 'Cold Foil'
            return [('normal', 'Normal'), ('foil', foil_lane)]
        special = {
            'Epic': (maximum + 1, maximum + 18, 'Satin'),
            'Enchanted': (maximum + 19, maximum + 36, 'Tinsel' if code == '14' else 'Magma'),
            'Iconic': (maximum + 37, maximum + 38, 'Lore'),
        }.get(row['rarity'])
        if special and special[0] <= number <= special[1] and row['foilTypes'] == [special[2]]:
            return [('foil', 'Holofoil')]
        return None
    if not f or f['language'] != 'en' or f['denominator'] != '204' or not re.fullmatch(r'[0-9]+', f['collectorNumber']):
        return None
    number = int(f['collectorNumber'])
    if 1 <= number <= 204 and set(row['foilTypes']) == {'None', 'Silver'}:
        return [('normal', 'Normal'), ('foil', 'Cold Foil')]
    # Only the eight reconciled original Enchanted runs. Later Magma/Tinsel,
    # promos, multiple foil treatments and alternate distributions need their own policy.
    code = row['setCode']
    if code not in {str(i) for i in range(1, 9)} or row['sourceSetCode'] != code or f['printedSetMarker'] != code:
        return None
    maximum = 216 if code in {'1', '2'} else 222
    pattern = 'Lava' if code in {'1', '2', '3', '4'} else 'VerticalWave'
    if (205 <= number <= maximum and row['rarity'] == 'Enchanted' and row['layout'] in {'normal', 'landscape'}
            and row['foilTypes'] == [pattern] and row.get('distribution') is None
            and row['imageURL'].startswith(f'https://api.lorcana.ravensburger.com/images/en/set{code}/{number}_')):
        return [('foil', 'Holofoil')]
    return None


def build(discovery, sources, baseline, assignments, review_later_expansions=False, review_disney100=False):
    source_bytes = discovery.read_bytes()
    payload = json.loads(source_bytes)
    base = json.loads(baseline.read_bytes())
    ledger = dict(assignments)
    def allocate(key):
        if key not in ledger:
            ledger[key] = str(uuid.uuid4())
        return ledger[key]
    rows = payload['cards']
    by_footer = collections.defaultdict(list)
    def footer_key(f):
        return ':'.join(f[k] for k in ['language', 'printedSetMarker', 'collectorNumber', 'denominator'])
    for row in rows:
        if row['footer']:
            by_footer[footer_key(row['footer'])].append(row)
    catalogs = {}
    receipts = []
    for group in json.loads((sources / 'groups-selected.json').read_bytes()):
        if review_later_expansions and group['code'] in LATER_GROUPS and group['groupID'] != LATER_GROUPS[group['code']]:
            raise ValueError('Later expansion source group differs from reviewed identity')
        if review_disney100 and group['code'] == 'P1' and group['groupID'] != 23305:
            raise ValueError('Disney100 source group differs from reviewed identity')
        product_bytes = (sources / f"{group['groupID']}-products.json").read_bytes()
        price_bytes = (sources / f"{group['groupID']}-prices.json").read_bytes()
        products, prices = json.loads(product_bytes), json.loads(price_bytes)
        for batch in [products, prices]:
            if not batch['success'] or batch['errors'] or batch.get('totalItems', len(batch['results'])) != len(batch['results']):
                raise ValueError('Incomplete or failed feed')
        for p in products['results']:
            if p['categoryId'] != 71 or p['groupId'] != group['groupID']:
                raise ValueError('Cross-category/group product')
        catalogs[group['code']] = (group, products['results'], prices['results'], hashlib.sha256(product_bytes).hexdigest())
        receipts.append(dict(**group, productsSHA256=hashlib.sha256(product_bytes).hexdigest(), pricesSHA256=hashlib.sha256(price_bytes).hexdigest()))
    manifest = dict(base)
    manifest['discoverySHA256'] = hashlib.sha256(source_bytes).hexdigest()
    manifest['canonicalCards'] = list(base['canonicalCards'])
    manifest['physicalPrintings'] = list(base['physicalPrintings'])
    manifest['printFamilies'] = list(base['printFamilies'])
    manifest['universes'] = list(base['universes'])
    existing = {footer_key(f['footer']) for f in base['printFamilies']}
    decisions = []
    for row in sorted(rows, key=lambda r: r['id']):
        f = row['footer']
        if not f or row['setCode'] not in catalogs or not row['id'].startswith('lorcanajson:'):
            continue
        key = footer_key(f)
        if key in existing:
            continue
        finishes = reviewed_finishes(row, review_later_expansions, review_disney100)
        disney100 = review_disney100 and row['id'] in DISNEY100
        enchanted = row['rarity'] == 'Enchanted'
        special = row['rarity'] in {'Enchanted', 'Epic', 'Iconic'}
        review = LATER_REVIEW if disney100 or (review_later_expansions and row['setCode'] in LATER_GROUPS) else REVIEW
        reason = None
        if len(by_footer[key]) != 1:
            reason = 'Multiple source physical candidates'
        elif finishes is None:
            reason = 'Outside reviewed ordinary/Enchanted physical policy'
        group, products, prices, product_hash = catalogs[row['setCode']]
        numbers = {f['collectorNumber'], f['collectorNumber'] + '/' + f['denominator']}
        market_name = ENCHANTED_MARKET_NAMES.get((row['setCode'], f['collectorNumber'], row['name']), row['name']) if enchanted else row['name']
        matches = []
        siblings = []
        for p in products:
            fields = [field['value'] for field in p['extendedData'] if field['name'] == 'Number']
            if len(fields) != 1 or fields[0] not in numbers or re.search(r'\((?:JP|CS) Exclusive\)', p['name']):
                continue
            if name_key(re.sub(r' \([^)]*\)$', '', p['name'])) == name_key(market_name):
                siblings.append(p)
            expected_name = market_name + (' (Alternate Art)' if disney100 else f" ({row['rarity']})" if special else '')
            if name_key(p['name']) == name_key(expected_name):
                require_rarity = disney100 or special or (review_later_expansions and row['setCode'] in LATER_GROUPS)
                expected_rarity = 'Promo' if disney100 else row['rarity']
                if require_rarity and [x['value'] for x in p['extendedData'] if x['name'] == 'Rarity'] != [expected_rarity]:
                    continue
                if disney100 and p['productId'] != DISNEY100[row['id']][2]:
                    continue
                matches.append(p)
        split = LATER_SPLIT_PRODUCTS.get((row['setCode'], f['collectorNumber'])) if review_later_expansions and not special else None
        split_products = {p['productId']: p for p in siblings}
        split_valid = (split and len(matches) == 1 and set(split_products) == set(split)
            and matches[0]['productId'] == split[0]
            and split_products[split[1]]['name'] == market_name + ' (Foil)'
            and [x['value'] for x in split_products[split[1]]['extendedData'] if x['name'] == 'Rarity'] == [row['rarity']])
        if len(matches) != 1 or (len(siblings) != 1 and not split_valid):
            reason = reason or 'Missing/ambiguous exact title-number join or qualified sibling'
        if reason:
            decisions.append(dict(sourceID=row['id'], status='held', reason=reason));continue
        product = matches[0]
        products_by_finish = {k: split_products[split[0] if k == 'normal' else split[1]] if split_valid else product for k, _ in finishes}
        expected_by_product = collections.defaultdict(list)
        for k, lane in finishes:
            expected_by_product[products_by_finish[k]['productId']].append(lane)
        if any(sorted(p['subTypeName'] for p in prices if p['productId'] == pid) != sorted(lanes)
               for pid, lanes in expected_by_product.items()):
            decisions.append(dict(sourceID=row['id'], status='held', reason='Missing/duplicate/unexpected market lanes'));continue
        canonical, artwork, printing = [allocate(key + ':' + kind) for kind in ['canonical', 'artwork', 'printing']]
        aliases = [dict(provider='lorcanajson', id=row['id']), dict(provider='tcgcsv', id=f"tcgcsv:71:{product['productId']}")]
        if split_valid:
            aliases.append(dict(provider='tcgcsv', id=f'tcgcsv:71:{split[1]}'))
        image = row['imageURL']
        refs = [review, image]
        manifest['printFamilies'].append(dict(footer=f, providerSetCode=row['sourceSetCode'], name=row['name'], version=None,
            rarity=row['rarity'], layout=row['layout'], sourceAliases=aliases, footerEvidenceReference=image))
        manifest['canonicalCards'].append(dict(id=canonical, name=row['name'], version=None, relationshipEvidenceReferences=refs))
        manifest['physicalPrintings'].append(dict(id=printing, identity=dict(canonicalCardID=canonical, footer=f, artworkID=artwork,
            distributionID='disney100-collectors-set' if disney100 else (row['rarity'].lower() + '-expansion-' if special else 'ordinary-expansion-') + row['setCode'],
            size='standard', layout=row['layout'], **({'stamp': 'Disney100 printed animator signature'} if disney100 else {})),
            providerSetCode=row['sourceSetCode'], setName=row['setName'],
            artworkLabel='Disney100 alternate artwork' if disney100 else row['rarity'] + ' artwork' if special else 'Original artwork',
            distributionLabel="Disney100 Collector's Set" if disney100 else row['rarity'] + ' expansion' if special else 'Ordinary expansion', imageURL=image, status='verified',
            identityEvidence=[dict(kind=k, reference=image if k in ['printedFooter','artwork','stamp'] else review) for k in ['printedFooter','artwork','stamp','size','distribution']],
            finishes=[dict(finish=k, evidenceReferences=[review, DISNEY100_REFERENCE if disney100 else LATER_RARITIES if row['rarity'] in {'Epic', 'Iconic'} else ENCHANTED_FINISH if enchanted else FINISH]) for k, _ in finishes], finishUniverseEvidenceReference=review,
            sourceAliases=aliases, marketMappings=[dict(finish=k, groupID=group['groupID'], productID=products_by_finish[k]['productId'],
                productName=products_by_finish[k]['name'], productNumber=next(x['value'] for x in products_by_finish[k]['extendedData'] if x['name']=='Number'),
                providerVariantID=lane, market='us', currency='USD', condition='aggregate',
                evidenceReferences=[review, f"https://tcgcsv.com/tcgplayer/71/{group['groupID']}/products", 'sha256:'+product_hash])
                for k,lane in finishes]))
        manifest['universes'].append(dict(footer=f, printingIDs=[printing], isComplete=True, evidenceReference=review))
        decisions.append(dict(sourceID=row['id'], printingID=printing, productID=product['productId'], groupID=group['groupID'], status='mapped'))
    report = dict(schemaVersion=1, discoverySHA256=hashlib.sha256(source_bytes).hexdigest(), groups=receipts,
        mappedPrintingCount=sum(bool(p.get('marketMappings')) for p in manifest['physicalPrintings']),
        mappingCount=sum(len(p.get('marketMappings',[])) for p in manifest['physicalPrintings']), decisions=decisions)
    return manifest, ledger, report


def validate_previous(current, previous):
    old = {p['id']: p for p in previous['physicalPrintings']}
    new = {p['id']: p for p in current['physicalPrintings']}
    if not old.keys() <= new.keys():
        raise ValueError('Existing physical IDs cannot disappear; explicit withdrawal/held transition required')
    for key, p in old.items():
        if p['identity'] != new[key]['identity'] or p['imageURL'] != new[key]['imageURL']:
            raise ValueError('Physical identity/artwork changed; explicit supersession review required')
    if len(set(p['id'] for p in current['physicalPrintings'])) != len(new):
        raise ValueError('Duplicate allocated physical UUID')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['discovery','sources','baseline','assignments','output','report']:
        parser.add_argument('--'+name, required=True, type=Path)
    parser.add_argument('--reviewed-at', type=float, help='Review time as Foundation Date seconds since 2001-01-01 UTC')
    parser.add_argument('--review-later-expansions', action='store_true', help='Prepare isolated sets 9–14 review data; does not activate or publish')
    parser.add_argument('--review-disney100', action='store_true', help='Prepare the six exact Disney100 collector printings in isolated outputs')
    args=parser.parse_args()
    assignments=json.loads(args.assignments.read_bytes()) if args.assignments.exists() else {}
    manifest, ledger, report=build(args.discovery,args.sources,args.baseline,assignments,args.review_later_expansions,args.review_disney100)
    if args.reviewed_at is not None:
        if not math.isfinite(args.reviewed_at) or args.reviewed_at <= 0:
            raise ValueError('Invalid review timestamp')
        manifest['reviewedAt'] = args.reviewed_at
        report['reviewedAt'] = args.reviewed_at
    if args.output.exists():
        validate_previous(manifest, json.loads(args.output.read_bytes()))
    for path,value in [(args.output,manifest),(args.assignments,ledger),(args.report,report)]:
        path.write_text(json.dumps(value,sort_keys=True,separators=(',',':'))+'\n')
    print(report['mappedPrintingCount'], 'mapped printings;',report['mappingCount'],'finish mappings')


if __name__ == '__main__':
    main()
