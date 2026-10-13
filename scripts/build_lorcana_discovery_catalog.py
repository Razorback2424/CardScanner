#!/usr/bin/env python3
"""Build offline English discovery data, never a reviewed physical catalog.

Inputs are public LorcanaJSON allCards and TCGCSV category 71 products. No
prices, images, signatures, physical UUIDs or ownership authority are generated.
Unknown footer formats and changed source counts fail instead of disappearing.
"""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import re
import unicodedata


def name_key(value):
    # Marketplace names often omit accents (Hector/Héctor, Mama/Mamá). Match
    # exact normalized words, never fuzzy titles or a nearest collector number.
    return ' '.join(''.join(c for c in unicodedata.normalize('NFKD', value).casefold()
                           if not unicodedata.combining(c)).split())


def footer(identifier):
    match = re.fullmatch(r"(\d+[A-Za-z]?)/([A-Z0-9-]+) • EN • ([A-Z0-9-]+)", identifier)
    if match:
        number, denominator, marker = match.groups()
        return dict(collectorNumber=number.upper(), denominator=denominator,
                    language="en", printedSetMarker=marker)
    match = re.fullmatch(r"(\d+) TFC • EN • (\d+)/P1", identifier)
    if match:
        marker, number = match.groups()
        return dict(collectorNumber=number, denominator="P1", language="en", printedSetMarker=marker)
    # This Quest token has no number on the card. Keep it browsable, and never
    # allocate an invented number for OCR to find.
    if identifier == "EN • Q3":
        return None
    raise ValueError(f"Unreviewed footer format: {identifier!r}")


def build(cards_path, groups_path, products_directory, evidence_path=None):
    raw = cards_path.read_bytes()
    source = json.loads(raw)
    assert source['metadata']['language'] == 'en'
    assert source['metadata']['formatVersion'] == '2.4.0'
    cards = []
    evidence = json.loads(evidence_path.read_bytes()) if evidence_path else dict(schemaVersion=1, records=[])
    if evidence['schemaVersion'] != 1:
        raise ValueError('Unsupported product evidence schema')
    evidence_by_id = {}
    for row in evidence['records']:
        if row['productID'] in evidence_by_id or not re.fullmatch('[0-9a-f]{64}', row['bodySHA256']):
            raise ValueError('Duplicate or invalid product evidence')
        if not row['reference'].startswith('https://') or not row.get('expectedName'):
            raise ValueError('Product evidence requires a public reference and exact name')
        evidence_by_id[row['productID']] = row
    used_evidence = set()
    tcg_ids = {str(c['externalLinks'].get('tcgPlayerId')) for c in source['cards']}
    ids = set()
    for card in source['cards']:
        assert card['id'] not in ids
        ids.add(card['id'])
        group = card.get('promoGrouping') or card['setCode']
        set_data = source['sets'][card['setCode']]
        group_name = set_data['name'] if group == card['setCode'] else {
            'P1': 'Promo Set 1', 'P2': 'Promo Set 2', 'P3': 'Promo Set 3', 'P4': 'Promo Set 4',
            'PD1': 'Disney Lorcana Day', 'D23': 'D23 Collection', 'C1': 'Challenge Year 1',
            'C2': 'Challenge Year 2', 'DIS': 'Disney Parks Promos', 'RPH': 'Ravensburger Play Hub',
            'CC1': "Curator’s Collection: Heroines Edition",
        }[group]
        assert card['foilTypes'] and len(set(card['foilTypes'])) == len(card['foilTypes'])
        cards.append(dict(id=f"lorcanajson:en:{card['id']}", name=card['fullName'],
                          number='Unnumbered' if card['fullIdentifier'].startswith('EN • Q') else str(card['number']) + card.get('variant', ''),
                          printedIdentifier=card['fullIdentifier'], footer=footer(card['fullIdentifier']),
                          setCode=group, setName=group_name,
                          releaseDate=(set_data['prereleaseDate'] or set_data['releaseDate']) if group == card['setCode'] else None,
                          rarity=card['rarity'], layout='landscape' if card['type'] == 'Location' else 'normal',
                          imageURL=card['images'].get('full'), thumbnailURL=card['images'].get('thumbnail'),
                          foilTypes=card['foilTypes'], distribution=card.get('promoSource') or card.get('promoSourceCategory'),
                          unnumberedSetMarker='Q3' if card['fullIdentifier'] == 'EN • Q3' else None,
                          recognitionTitles=['Vine Tendril'] if card['fullIdentifier'] == 'EN • Q3' else [],
                          sourceSetCode=card['setCode']))
    # Count every source row, including promos and artwork suffixes. The source
    # explicitly marks Q3 incomplete; retain that fact in the coverage receipt.
    counts = collections.Counter(c['setCode'] for c in source['cards'])
    for code, data in source['sets'].items():
        assert counts[code] == data['cardCounts'].get('total', 0), (code, counts[code])

    groups = json.loads(groups_path.read_bytes())
    assert groups['success'] and not groups['errors'] and groups['totalItems'] == len(groups['results'])
    sealed = []
    product_receipts = []
    excluded = []
    supplemental = []
    joined_products = []
    product_joins = []
    excluded_products = []
    for group in groups['results']:
        path = products_directory / f"{group['groupId']}.json"
        body = path.read_bytes()
        batch = json.loads(body)
        assert batch['success'] and not batch['errors']
        assert set(batch) in ({'success', 'errors', 'results'}, {'totalItems', 'success', 'errors', 'results'})
        assert batch.get('totalItems', 0) == len(batch['results'])
        product_receipts.append(dict(groupID=group['groupId'], sha256=hashlib.sha256(body).hexdigest(), count=len(batch['results'])))
        for product in batch['results']:
            assert product['categoryId'] == 71 and product['groupId'] == group['groupId']
            # A missing collector number alone is insufficient: puzzle inserts,
            # oversized Quest components and accessories must not become sealed.
            if product['extendedData']:
                if str(product['productId']) in tcg_ids:
                    continue
                fields = {field['name']: field['value'] for field in product['extendedData']}
                if fields.get('Rarity') in (None, 'None'):
                    continue  # Puzzle, rules, lore and case-file inserts are not playable cards.
                if re.search(r'\((?:JP|CS) Exclusive\)', product['name']):
                    continue  # Foreign-language observations are outside this English catalog.
                number = fields.get('Number', '')
                name = re.sub(r' \([^)]*\)$', '', product['name'])
                matches = [c for c in cards if name_key(c['name']) == name_key(name)
                           and (name_key(c['setName']) == name_key(group['name']) or
                                (c['setName'] == 'The Reign of Jafar' and group['name'] == 'Reign of Jafar'))
                           and (c['footer'] and number in (c['footer']['collectorNumber'],
                               c['footer']['collectorNumber'] + '/' + c['footer']['denominator']))]
                reviewed = evidence_by_id.get(product['productId'])
                if reviewed:
                    if reviewed['expectedName'] != product['name']:
                        raise ValueError(f"Product evidence name changed: {product['productId']}")
                    used_evidence.add(product['productId'])
                if product['productId'] == 652646:
                    excluded_products.append(dict(productID=652646, reason='Five-card marketplace bundle, not an individual card'))
                    continue
                explicit = reviewed.get('sourceCardID') if reviewed else None
                if explicit:
                    matches = [c for c in cards if c['id'] == explicit]
                    if len(matches) != 1:
                        raise ValueError('Evidence refers to an absent source card')
                    if reviewed.get('printedIdentifier') and reviewed['printedIdentifier'] != matches[0]['printedIdentifier']:
                        raise ValueError('Inspected alias footer contradicts source card')
                qualifier = re.search(r' \((Foil|Epic|Enchanted|Iconic)\)$', product['name'])
                same_rarity = qualifier is None or qualifier[1] == 'Foil' or (
                    len(matches) == 1 and name_key(matches[0]['rarity']) == name_key(qualifier[1]))
                if len(matches) == 1 and same_rarity and (explicit or product['name'] == name or qualifier):
                    joined_products.append(product['productId'])
                    product_joins.append(dict(productID=product['productId'], sourceCardID=matches[0]['id'],
                                             basis='reviewed image' if explicit else 'exact normalized name and collector number'))
                    continue
                # Market-only / errata / oversized observations remain searchable
                # without inventing a printed set marker, finish or ownership UUID.
                # A unique full name + number join may retain the source footer;
                # all other products require manual catalog recovery.
                observed_identifier = reviewed.get('printedIdentifier') if reviewed else None
                observed_footer = footer(observed_identifier) if observed_identifier and not observed_identifier.startswith('EN • Q') else None
                if observed_footer and number and number not in (observed_footer['collectorNumber'],
                        observed_footer['collectorNumber'] + '/' + observed_footer['denominator']):
                    raise ValueError('Product number contradicts inspected footer')
                promo_group = observed_footer['denominator'] if observed_footer and not observed_footer['denominator'].isdigit() else None
                promo_name = {'P1':'Promo Set 1','P2':'Promo Set 2','C1':'Challenge Year 1',
                              'C2':'Challenge Year 2','C3':'Challenge Year 3'}.get(promo_group)
                printed_set = source['sets'].get(observed_footer['printedSetMarker']) if observed_footer and not promo_group else None
                browse_code = promo_group if promo_name else observed_footer['printedSetMarker'] if printed_set else f"market-{group['groupId']}"
                browse_name = promo_name or (printed_set['name'] if printed_set else group['name'] + ' · Additional products')
                supplemental.append(dict(id=f"tcgcsv:71:{product['productId']}", name=product['name'],
                    number=number or 'Unnumbered', printedIdentifier=observed_identifier or number or 'Unnumbered',
                    footer=observed_footer,
                    setCode=browse_code, setName=browse_name,
                    releaseDate=None if promo_name else (printed_set['prereleaseDate'] or printed_set['releaseDate'])
                        if printed_set else (product['presaleInfo'].get('releasedOn') or '')[:10] or None,
                    rarity=fields['Rarity'], layout='unknown', sourceSetCode=observed_footer['printedSetMarker'] if observed_footer else
                        reviewed.get('unnumberedSetMarker', '') if reviewed else '',
                    unnumberedSetMarker=reviewed.get('unnumberedSetMarker') if reviewed else None,
                    recognitionTitles=reviewed.get('recognitionTitles', []) if reviewed else [],
                    imageURL=product['imageUrl'], thumbnailURL=product['imageUrl'], foilTypes=[],
                    distribution='TCGplayer product record; physical review pending'))
                continue
            if not re.search(r"booster|deck|trove|gift|bundle|collection|collector|quest|starter|pack|case|box|display|gateway|promo set", product['name'], re.I):
                excluded.append(dict(id=product['productId'], name=product['name']))
                continue
            sealed.append(dict(id=f"tcgcsv:71:{product['productId']}", name=product['name'],
                               setID=f"tcgcsv:71:{group['groupId']}", setName=group['name'],
                               releaseDate=product['presaleInfo'].get('releasedOn'),
                               imageURL=product['imageUrl'], tcgplayerProductID=str(product['productId'])))
    assert not excluded, f"Review unclassified products: {excluded}"
    assert len({p['id'] for p in sealed}) == len(sealed)
    if set(evidence_by_id) != used_evidence:
        raise ValueError('Product evidence is no longer represented by captured products')
    return dict(schemaVersion=1, generatedOn=source['metadata']['generatedOn'],
                cards=sorted(cards + supplemental, key=lambda c: c['id']), sealed=sorted(sealed, key=lambda p: p['id']),
                coverage=dict(cardSource='https://lorcanajson.org/files/current/en/allCards.json',
                              cardSourceSHA256=hashlib.sha256(raw).hexdigest(),
                              sourceFormat=source['metadata']['formatVersion'], sourceCardCount=len(cards),
                              sets=source['sets'], productGroups=product_receipts,
                              supplementalCardCount=len(supplemental), joinedProductIDs=joined_products,
                              productJoins=product_joins, excludedProducts=excluded_products, productEvidence=evidence['records'],
                              sealedCount=len(sealed)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cards', required=True, type=Path)
    parser.add_argument('--groups', required=True, type=Path)
    parser.add_argument('--products', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--evidence', type=Path, default=Path(__file__).with_name('lorcana_product_evidence.json'))
    args = parser.parse_args()
    result = build(args.cards, args.groups, args.products, args.evidence)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(',', ':')) + '\n')
    print(f"{len(result['cards'])} cards; {len(result['sealed'])} sealed products")


if __name__ == '__main__':
    main()
