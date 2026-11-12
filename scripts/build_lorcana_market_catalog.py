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
MARKET_NAMES = {
    ('3', '94', 'Has Set My Heaaaaaaart...'): 'Has Set My Heaaaaaaart . . .',
    ('8', '18', 'Chief Bogo - Commanding Officer'): 'Chief Bogo- Commanding Officer',
    ('8', '118', 'Walk the Plank!'): 'Walk the Plank',
    ('8', '152', 'The Sword of Shan-Yu'): 'The Sword of Shan Yu',
    ('8', '219', 'The Sword of Shan-Yu'): 'The Sword of Shan Yu',
    ('CC1', '6', 'Tinker Bell - Giant Fairy'): 'Tinker Bell - Giant Fairy (6/CC1)',
    ('D23', '1', 'Mickey Mouse - Brave Little Tailor'): 'Mickey Mouse - Brave Little Tailor (Extended Art)',
    ('C1', '1', 'Dragon Fire'): 'Dragon Fire (1/C1)',
    ('C1', '2', 'Let It Go'): 'Let It Go (Disney Lorcana Challenge Top 128)',
    ('C2', '1', 'Pegasus - Gift for Hercules'): 'Pegasus - Gift for Hercules (1)',
    ('C2', '2', 'Elsa - Ice Maker'): 'Elsa - Ice Maker (Foil)',
    ('C2', '3', 'Mulan - Charging Ahead'): 'Mulan - Charging Ahead (Foil)',
    ('C2', '4', 'Simba - Pride Protector'): 'Simba - Pride Protector (Foil)',
    ('C2', '5', 'Pegasus - Gift for Hercules'): 'Pegasus - Gift for Hercules (5)',
    ('C2', '9', 'Dragon Fire'): 'Dragon Fire (9/C2)',
    ('C2', '10', 'Let it Go'): 'Let It Go (Disney Lorcana Challenge)',
    ('PD1', '5', 'Buzz Lightyear - Providing Cover'): 'Buzz Lightyear - Providing Cover (Prerelease Promo)',
}
LATER_REVIEW = 'docs/research/lorcana-expansion-candidate-review-2026-10-23.md'
VARIANT_REVIEW = 'docs/audits/lorcana-coverage-2026-11-11.md'
LATER_RARITIES = 'https://www.disneylorcana.com/en-US/news/2025/08/2025-8-stunning-new-rarities'
# Exact groups retained by the adopted sets 1–8 mapping review. Selecting a
# source file cannot authorize a different expansion's title/number matches.
ORIGINAL_GROUPS = {'1': 22937, '2': 23303, '3': 23367, '4': 23474,
                   '5': 23536, '6': 23746, '7': 24011, '8': 24258}
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
ORIGINAL_SPLIT_PRODUCTS = {
    ('8', '1'): (631349, 633427), ('8', '2'): (631350, 633428),
    ('8', '3'): (631351, 633429), ('8', '65'): (631394, 633430),
    ('8', '125'): (631431, 633431),
}

DALMATIAN_PRODUCTS = {'4A': 532867, '4B': 532868, '4C': 532869, '4D': 532870, '4E': 532871}

SOURCE_FINISH_PATTERNS = {
    'normal': 'None',
    'lorcanaSilverFoil': 'Silver',
    'lorcanaFreeForm1Foil': 'FreeForm1',
    'lorcanaRainbowPillarsFoil': 'RainbowPillars',
}
MARKET_LANES_BY_FINISH = {
    'normal': {'Normal'},
    'foil': {'Cold Foil', 'Holofoil'},
    'lorcanaSilverFoil': {'Cold Foil'},
    'lorcanaFreeForm1Foil': {'Cold Foil', 'Holofoil'},
    'lorcanaRainbowPillarsFoil': {'Holofoil'},
}


def footer_key(footer):
    return ':'.join(footer[k] for k in ('language', 'printedSetMarker', 'collectorNumber', 'denominator'))


def validate_source_universes(rows, manifest):
    """A complete family must account for every observed sibling and finish."""
    complete = {footer_key(u['footer']) for u in manifest['universes'] if u['isComplete']}
    sources = {r['id']: r for r in rows}
    represented = collections.defaultdict(set)
    for printing in manifest['physicalPrintings']:
        key = footer_key(printing['identity']['footer'])
        if key not in complete or printing['status'] == 'superseded':
            continue
        observed = [sources[a['id']] for a in printing['sourceAliases'] if a['id'] in sources]
        if len(observed) != 1 or not observed[0]['footer'] or footer_key(observed[0]['footer']) != key:
            raise ValueError(f"Lorcana complete printing must bind exactly one matching discovery row: {printing['id']}")
        represented[observed[0]['id']].update(f['finish'] for f in printing['finishes'])
    for row in rows:
        if not row['footer'] or footer_key(row['footer']) not in complete:
            continue
        finishes = represented[row['id']]
        if not finishes:
            raise ValueError(f"Lorcana complete family omits discovery sibling: {row['id']}")
        if not row['foilTypes']:
            continue
        observed = set(row['foilTypes'])
        named = {SOURCE_FINISH_PATTERNS[f] for f in finishes if f in SOURCE_FINISH_PATTERNS}
        remaining = observed - named
        if not named <= observed or (
            (len(remaining) != 1 or 'None' in remaining) if 'foil' in finishes else bool(remaining)
        ):
            raise ValueError(f"Lorcana complete family disagrees with discovery finishes: {row['id']}")


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
        if (1 <= number <= maximum and row['rarity'] in {'Rare', 'Super Rare', 'Legendary'}
                and code in {'9', '10', '12', '14'}):
            if set(row['foilTypes']) == {'None', 'Silver', 'RainbowPillars'}:
                return [('normal', 'Normal'), ('lorcanaSilverFoil', 'Cold Foil'), ('lorcanaRainbowPillarsFoil', 'Holofoil')]
            if code == '10' and set(row['foilTypes']) == {'None', 'FreeForm1', 'RainbowPillars'}:
                # The marketplace lists two foil lanes, but the observed metadata
                # does not resolve the lane-to-pattern assignment for this group.
                return [('normal', 'Normal'), ('lorcanaFreeForm1Foil', None), ('lorcanaRainbowPillarsFoil', None)]
        special = {
            'Epic': (maximum + 1, maximum + 18, 'Satin'),
            'Enchanted': (maximum + 19, maximum + 36, 'Tinsel' if code == '14' else 'Magma'),
            'Iconic': (maximum + 37, maximum + 38, 'Lore'),
        }.get(row['rarity'])
        if special and special[0] <= number <= special[1] and row['foilTypes'] == [special[2]]:
            return [('foil', 'Holofoil')]
        return None
    # Ordinary 204-card numbering alone does not establish a reviewed expansion
    # or physical treatment. In particular, later sets must not reach this path
    # when their separate review option is off.
    if (not f or f['language'] != 'en' or f['denominator'] != '204'
            or code not in ORIGINAL_GROUPS or row['sourceSetCode'] != code or f['printedSetMarker'] != code
            or row.get('distribution') is not None or row['layout'] not in {'normal', 'landscape'}
            or len(row['foilTypes']) != len(set(row['foilTypes']))
            or not row['imageURL'].startswith(f"https://api.lorcana.ravensburger.com/images/en/set{code}/{f['collectorNumber'].lower()}_")):
        return None
    if (code == '3' and f['collectorNumber'] in DALMATIAN_PRODUCTS
            and row['name'] == 'Dalmatian Puppy - Tail Wagger' and row['rarity'] == 'Common'
            and set(row['foilTypes']) == {'None', 'Silver'}):
        return [('normal', 'Normal'), ('foil', 'Cold Foil')]
    if not re.fullmatch(r'[0-9]+', f['collectorNumber']):
        return None
    number = int(f['collectorNumber'])
    if (1 <= number <= 204 and set(row['foilTypes']) == {'None', 'Silver'}
            and row['rarity'] in {'Common', 'Uncommon', 'Rare', 'Super Rare', 'Legendary'}):
        return [('normal', 'Normal'), ('foil', 'Cold Foil')]
    # Only the eight reconciled original Enchanted runs. Later Magma/Tinsel,
    # promos, multiple foil treatments and alternate distributions need their own policy.
    maximum = 216 if code in {'1', '2'} else 222
    pattern = 'Lava' if code in {'1', '2', '3', '4'} else 'VerticalWave'
    if 205 <= number <= maximum and row['rarity'] == 'Enchanted' and row['foilTypes'] == [pattern]:
        return [('foil', 'Holofoil')]
    return None


def reviewed_fixed_product(row, scopes):
    """Match a bounded published deck or collector product before joining prices."""
    scope = scopes.get(row['setCode'])
    footer = row['footer']
    if (not scope or not footer or not row['id'].startswith('lorcanajson:en:')
            or footer['denominator'] != scope['denominator'] or footer['language'] != 'en'
            or footer['printedSetMarker'] != row['sourceSetCode']
            or footer['printedSetMarker'] != scope.get('printedSetMarker', row['sourceSetCode'])
            or not re.fullmatch(r'[0-9]+', footer['collectorNumber'])
            or row['rarity'] != 'Special' or row['layout'] not in {'normal', 'landscape'}):
        return None, None
    number = int(footer['collectorNumber'])
    for product in scope['fixedProducts']:
        first = product.get('first', scope['first'])
        last = product.get('last', scope['last'])
        image_prefix = f"https://api.lorcana.ravensburger.com/images/en/{product['sourceImagePath']}/{number}_"
        if (first <= number <= last and row.get('distribution') == product['sourceDistribution']
                and row.get('sourceFoilTypes', row['foilTypes']) == [product['foilPattern']]
                and row['imageURL'].startswith(image_prefix)):
            product_ids = product.get('marketProductIDs')
            return product, product_ids[number - first] if product_ids else None
    return None, None


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
    release_inventory = json.loads(Path(__file__).with_name('lorcana_release_inventory.json').read_bytes())
    fixed_scopes = {scope['code']: scope for scope in release_inventory['scopes'] if scope.get('fixedProducts')}
    reviewed_products = {r.get('sourceCardID', f"tcgcsv:71:{r['productID']}"): r
                         for r in payload.get('coverage', {}).get('productEvidence', [])
                         if r.get('physicalReleaseEvidence')}
    reviewed_products.update({r['sourceID']: r for r in payload.get('coverage', {}).get('publishedCards', [])})
    by_footer = collections.defaultdict(list)
    for row in rows:
        if row['footer']:
            by_footer[footer_key(row['footer'])].append(row)
    catalogs = {}
    catalogs_by_id = {}
    receipts = []
    for group in json.loads((sources / 'groups-selected.json').read_bytes()):
        if group['code'] in ORIGINAL_GROUPS and group['groupID'] != ORIGINAL_GROUPS[group['code']]:
            raise ValueError('Original expansion source group differs from reviewed identity')
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
        catalogs_by_id[group['groupID']] = catalogs[group['code']]
        receipts.append(dict(**group, productsSHA256=hashlib.sha256(product_bytes).hexdigest(), pricesSHA256=hashlib.sha256(price_bytes).hexdigest()))
    manifest = dict(base)
    manifest['discoverySHA256'] = hashlib.sha256(source_bytes).hexdigest()
    manifest['canonicalCards'] = list(base['canonicalCards'])
    manifest['physicalPrintings'] = list(base['physicalPrintings'])
    manifest['printFamilies'] = list(base['printFamilies'])
    manifest['universes'] = list(base['universes'])
    existing = {footer_key(f['footer']) for f in base['printFamilies']}
    decisions = []
    prepared = collections.defaultdict(list)
    for row in sorted(rows, key=lambda r: r['id']):
        f = row['footer']
        product_review = reviewed_products.get(row['id'])
        fixed_product, fixed_market_id = reviewed_fixed_product(row, fixed_scopes)
        product_policy = product_review or fixed_product
        catalog = catalogs_by_id.get(product_policy['groupID']) if product_policy else catalogs.get(row['setCode'])
        if not f or not catalog or not (row['id'].startswith('lorcanajson:') or product_review):
            continue
        key = footer_key(f)
        if key in existing:
            continue
        finishes = reviewed_finishes(row, review_later_expansions, review_disney100)
        if product_review:
            if (row['printedIdentifier'] != product_review['printedIdentifier']
                    or row['name'] != product_review.get('sourceName', product_review['expectedName'])
                    or row['foilTypes'] != product_review['foilTypes']
                    or row['layout'] != product_review['layout']
                    or ('sourceCardID' not in product_review
                        and (row['distribution'] != product_review['distribution'] or row['imageURL'] != product_review['reference']))):
                raise ValueError(f"Reviewed physical product differs from discovery: {row['id']}")
            patterns = row['foilTypes']
            foils = [pattern for pattern in patterns if pattern != 'None']
            if not patterns or len(foils) > 1:
                raise ValueError(f"Reviewed physical product needs exact finish evidence: {row['id']}")
            finishes = [('normal', 'Normal')] if 'None' in patterns else []
            if foils:
                finishes.append(('foil', product_review['marketLane']))
        elif fixed_product:
            finish = 'normal' if fixed_product['foilPattern'] == 'None' else 'foil'
            finishes = [(finish, fixed_product['marketLane'])]
            if row.get('nonfoilEvidence'):
                finishes.insert(0, ('normal', 'Normal'))
        disney100 = review_disney100 and row['id'] in DISNEY100
        enchanted = row['rarity'] == 'Enchanted'
        special = row['rarity'] in {'Enchanted', 'Epic', 'Iconic'}
        dalmatian = DALMATIAN_PRODUCTS.get(f['collectorNumber']) if row['setCode'] == '3' else None
        multiple_foils = finishes is not None and len(finishes) > 2
        approved_without_market = row['id'] == 'lorcanajson:en:1467' and key == 'en:7:34:204' and row['name'] == 'Koda - Smallish Bear'
        if product_review:
            review = product_review['physicalReleaseEvidence']
        elif fixed_product:
            review = fixed_product['reference']
        elif multiple_foils or approved_without_market or dalmatian:
            review = VARIANT_REVIEW
        elif disney100 or (review_later_expansions and row['setCode'] in LATER_GROUPS):
            review = LATER_REVIEW
        else:
            review = REVIEW
        members = by_footer[key]
        oversized = [reviewed_products[r['id']] for r in members
                     if reviewed_products.get(r['id'], {}).get('size') == 'oversized']
        standard = [r for r in members if r['id'].startswith('lorcanajson:')]
        gift_pair = len(members) == 2 and len(oversized) == 1 and len(standard) == 1
        printing_variants = {reviewed_products.get(r['id'], {}).get('printingVariant') for r in members}
        corrected_pair = len(members) == 2 and printing_variants == {'original', 'corrected'}
        reason = None
        if product_review and product_review.get('printingVariant') and not corrected_pair:
            reason = 'Corrected printing evidence requires both original and corrected records'
        elif len(members) != 1 and not (gift_pair or corrected_pair):
            reason = 'Multiple source physical candidates'
        elif finishes is None:
            reason = 'Outside reviewed ordinary/Enchanted physical policy'
        group, products, prices, product_hash = catalog
        if product_review and group['groupID'] != product_review['groupID']:
            raise ValueError(f"Wrong group for reviewed physical product: {row['id']}")
        numbers = {f['collectorNumber'], f['collectorNumber'] + '/' + f['denominator']}
        market_name = product_review['expectedName'] if product_review else MARKET_NAMES.get(
            (row['setCode'], f['collectorNumber'], row['name']), row['name'])
        expected_name = market_name
        if disney100:
            expected_name += ' (Alternate Art)'
        elif not product_review and special:
            expected_name += f" ({row['rarity']})"
        elif dalmatian:
            expected_name += f" ({f['collectorNumber'].lower()}/{f['denominator']})"
        require_rarity = (product_policy or disney100 or special or dalmatian
                          or (review_later_expansions and row['setCode'] in LATER_GROUPS))
        expected_rarity = 'Promo' if disney100 else row['rarity']
        if fixed_product:
            expected_rarity = fixed_product.get('marketRarityOverrides', {}).get(f['collectorNumber'], fixed_product['marketRarity'])
        matches = []
        siblings = []
        for p in products:
            fields = [field['value'] for field in p['extendedData'] if field['name'] == 'Number']
            if len(fields) != 1 or fields[0].upper() not in numbers or re.search(r'\((?:JP|CS) Exclusive\)', p['name']):
                continue
            if product_review and p['productId'] != product_review.get('productID'):
                continue
            if fixed_market_id is not None and p['productId'] != fixed_market_id:
                continue
            if not product_review and gift_pair and p['productId'] == oversized[0]['productID']:
                continue
            sibling_name = p['name'] if product_review or fixed_market_id is not None else re.sub(r' \([^)]*\)$', '', p['name'])
            if name_key(sibling_name) == name_key(market_name):
                siblings.append(p)
            if name_key(p['name']) == name_key(expected_name):
                if require_rarity and [x['value'] for x in p['extendedData'] if x['name'] == 'Rarity'] != [expected_rarity]:
                    continue
                if disney100 and p['productId'] != DISNEY100[row['id']][2]:
                    continue
                if dalmatian and p['productId'] != dalmatian:
                    continue
                matches.append(p)
        split_key = (row['setCode'], f['collectorNumber'])
        split = ORIGINAL_SPLIT_PRODUCTS.get(split_key)
        if review_later_expansions and not special:
            split = split or LATER_SPLIT_PRODUCTS.get(split_key)
        split_products = {p['productId']: p for p in siblings}
        split_valid = (split and len(matches) == 1 and set(split_products) == set(split)
            and matches[0]['productId'] == split[0]
            and split_products[split[1]]['name'] == market_name + ' (Foil)'
            and [x['value'] for x in split_products[split[1]]['extendedData'] if x['name'] == 'Rarity'] == [row['rarity']])
        published_without_market = product_review and 'sourceID' in product_review and 'productID' not in product_review
        physical_only = (approved_without_market or fixed_product or published_without_market) and not matches and not siblings
        if not physical_only and (len(matches) != 1 or (len(siblings) != 1 and not split_valid)):
            reason = reason or 'Missing/ambiguous exact title-number join or qualified sibling'
        if reason:
            decisions.append(dict(sourceID=row['id'], status='held', reason=reason));continue
        product = None if physical_only else matches[0]
        products_by_finish = {k: split_products[split[0] if k == 'normal' else split[1]] if split_valid else product
                              for k, _ in finishes} if product else {}
        expected_by_product = collections.defaultdict(list)
        for k, lane in finishes:
            if lane is not None and k in products_by_finish:
                expected_by_product[products_by_finish[k]['productId']].append(lane)
        price_lanes = {pid: collections.Counter(p['subTypeName'] for p in prices if p['productId'] == pid)
                       for pid in expected_by_product}
        usable_price_products = {pid for pid, lanes in expected_by_product.items()
                                 if not (price_lanes[pid] - collections.Counter(
                                     ('Normal', 'Cold Foil', 'Holofoil') if multiple_foils else lanes))}
        if split_valid and len(usable_price_products) != len(expected_by_product):
            usable_price_products.clear()
        size = product_review.get('size', 'standard') if product_review else 'standard'
        canonical = allocate(key + ':canonical')
        member_key = key
        if gift_pair:
            member_key += ':' + size
        elif corrected_pair:
            member_key += ':' + product_review['printingVariant']
        artwork, printing = [allocate(member_key + ':' + kind) for kind in ('artwork', 'printing')]
        aliases = [dict(provider=row['id'].split(':', 1)[0], id=row['id'])]
        if product and row['id'] != f"tcgcsv:71:{product['productId']}":
            aliases.append(dict(provider='tcgcsv', id=f"tcgcsv:71:{product['productId']}"))
        if split_valid:
            aliases.append(dict(provider='tcgcsv', id=f'tcgcsv:71:{split[1]}'))
        image = product_review['reference'] if corrected_pair else row['imageURL']
        refs = [review, image]
        distribution_id = (product_policy['distributionID'] if product_policy else 'disney100-collectors-set' if disney100
                           else (row['rarity'].lower() + '-expansion-' if special else 'ordinary-expansion-') + row['setCode'])
        distribution_label = (product_review['distribution'] if product_review else fixed_product['distributionLabel'] if fixed_product
                              else "Disney100 Collector's Set" if disney100 else row['rarity'] + ' expansion' if special else 'Ordinary expansion')
        stamp = product_policy.get('stamp') if product_policy else 'Disney100 printed animator signature' if disney100 else None
        artwork_label = 'Oversized artwork' if size == 'oversized' else 'Special product artwork' if product_policy else (
            'Disney100 alternate artwork' if disney100 else row['rarity'] + ' artwork' if special else 'Original artwork')
        if product_review and product_review.get('artworkLabel'):
            artwork_label = product_review['artworkLabel']
        printing_row = dict(id=printing, identity=dict(canonicalCardID=canonical, footer=f, artworkID=artwork,
            distributionID=distribution_id, size=size, layout=row['layout'], **({'stamp': stamp} if stamp else {})),
            providerSetCode=row['sourceSetCode'], setName=row['setName'],
            artworkLabel=artwork_label,
            distributionLabel=distribution_label, imageURL=image, status='verified',
            identityEvidence=[dict(kind=k, reference=image if k in ['printedFooter','artwork','stamp'] else review) for k in ['printedFooter','artwork','stamp','size','distribution']],
            finishes=[dict(finish=k, evidenceReferences=[row.get('nonfoilEvidence', review) if k == 'normal' else review,
                image if product_policy or multiple_foils else
                DISNEY100_REFERENCE if disney100 else LATER_RARITIES if row['rarity'] in {'Epic', 'Iconic'} else
                ENCHANTED_FINISH if enchanted else FINISH]) for k, _ in finishes], finishUniverseEvidenceReference=review,
            sourceAliases=aliases, marketMappings=[dict(finish=k, groupID=group['groupID'], productID=products_by_finish[k]['productId'],
                productName=products_by_finish[k]['name'], productNumber=next(x['value'] for x in products_by_finish[k]['extendedData'] if x['name']=='Number'),
                providerVariantID=lane, market='us', currency='USD', condition='aggregate',
                evidenceReferences=[review, f"https://tcgcsv.com/tcgplayer/71/{group['groupID']}/products", 'sha256:'+product_hash])
                for k,lane in finishes if lane is not None and k in products_by_finish
                and products_by_finish[k]['productId'] in usable_price_products
                and price_lanes[products_by_finish[k]['productId']][lane] == 1])
        prepared[key].append((row, printing_row, refs, dict(sourceID=row['id'], printingID=printing,
            productID=product['productId'] if product else None, groupID=group['groupID'],
            status='mapped' if printing_row['marketMappings'] else 'verifiedUnpriced')))
    for key, members in prepared.items():
        if len(members) != len(by_footer[key]):
            decisions.extend(dict(sourceID=row['id'], status='held', reason='Incomplete reviewed sibling group')
                             for row, _, _, _ in members)
            continue
        row, printing, refs, _ = next((m for m in members if m[1]['identity']['size'] == 'standard'
                                      and reviewed_products.get(m[0]['id'], {}).get('printingVariant') != 'corrected'), members[0])
        f = row['footer']
        aliases = [alias for _, p, _, _ in members for alias in p['sourceAliases']]
        manifest['printFamilies'].append(dict(footer=f, providerSetCode=row['sourceSetCode'], name=row['name'], version=None,
            rarity=row['rarity'], layout=row['layout'], sourceAliases=aliases, footerEvidenceReference=printing['imageURL']))
        manifest['canonicalCards'].append(dict(id=printing['identity']['canonicalCardID'], name=row['name'], version=None,
            relationshipEvidenceReferences=refs))
        manifest['physicalPrintings'].extend(p for _, p, _, _ in members)
        manifest['universes'].append(dict(footer=f, printingIDs=[p['id'] for _, p, _, _ in members], isComplete=True,
            evidenceReference=next((r[0] for _, p, r, _ in members if p['identity']['size'] == 'oversized'), refs[0])))
        decisions.extend(decision for _, _, _, decision in members)
    validate_source_universes(rows, manifest)
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
        old_finishes = {f['finish'] for f in p['finishes']}
        new_finishes = {f['finish'] for f in new[key]['finishes']}
        old_aliases = {(a['provider'], a['id']) for a in p['sourceAliases']}
        new_aliases = {(a['provider'], a['id']) for a in new[key]['sourceAliases']}
        if not old_finishes <= new_finishes or not old_aliases <= new_aliases:
            raise ValueError(f'Existing physical printing lost a supported finish or source alias: {key}')
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
