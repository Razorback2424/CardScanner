#!/usr/bin/env python3
"""Reconcile Lorcana promo and event distributions into reviewed physical evidence.

Offline replay. Lorcana promos (Organized Play, Disney Parks & Stores, Disney
Cruise, prerelease packs, gift sets, events, Quest victory cards) carry their
own printed footer, such as ``26/P1 EN 3`` or ``4/DIS EN 13``, and the
publisher declares each one's finish. TCGplayer files every one as its own
product, usually in "Disney Lorcana Promo Cards". This pass turns each card a
reviewed rule covers into a ``physicalReleaseEvidence`` record in
``lorcana_product_evidence.json``. ``build_lorcana_discovery_catalog.py`` and
``build_lorcana_market_catalog.py`` then promote it through their existing
reviewed-product path; this script adds no builder path of its own.

Policy lives in ``lorcana_promo_distributions.json``. Each rule selects the
discovery rows of one distribution (promo scope, LorcanaJSON distribution and,
optionally, printed sets) and pins its TCGplayer group, card count, product
count, finish lanes, market rarities, stamp and release evidence. A card is
reconciled only when every gate passes:

* the rule selects exactly ``expectedCount`` rows, each with one finish pattern
  the rule lists;
* its printed number and title match exactly one product in the rule's group
  (a single trailing qualifier such as "(Store Championship)" is allowed), and
  LorcanaJSON's own TCGplayer link, when present, names the same product;
* no other card claims that product, and no existing evidence record
  contradicts the join;
* the product has at most one price lane, and that lane is one the rule allows
  for the card's finish (no lane means a real printing that is not yet priced);
* the rule matches exactly ``expectedProducts`` products in total.

Anything else stays held with a reason. The computed holds must equal the
rule file's reviewed ``holds``; a difference is drift that needs review, and
no evidence is written.
"""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import re
import sys

from build_lorcana_discovery_catalog import name_key
from build_lorcana_market_catalog import footer_key

SCRIPTS = Path(__file__).resolve().parent
RULES = SCRIPTS / 'lorcana_promo_distributions.json'
EVIDENCE = SCRIPTS / 'lorcana_product_evidence.json'
LANES = {'Normal', 'Cold Foil', 'Holofoil'}
FOREIGN = re.compile(r'\((?:JP|CS) Exclusive\)')
QUALIFIED = re.compile(r'(?P<name>.+) \((?P<qualifier>[^()]+)\)')
# Fields this pass adds to a record. A record carrying ``distributionRule`` is
# owned by this pass and is recomputed on every run.
PHYSICAL_FIELDS = ('distribution', 'distributionID', 'distributionRule', 'foilTypes', 'groupID', 'layout',
                   'marketLane', 'marketRarity', 'physicalReleaseEvidence', 'sourceName', 'stamp')


class RuleError(ValueError):
    pass


def load_rules(document):
    if document.get('schemaVersion') != 1:
        raise RuleError('Unsupported Lorcana promo distribution rule schema')
    rules, seen = document['rules'], set()
    for rule in rules:
        identity = rule['id']
        if identity in seen or not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', identity):
            raise RuleError(f'Duplicate or invalid rule id: {identity}')
        seen.add(identity)
        for field in ('label', 'setCode', 'distribution', 'kind'):
            if not isinstance(rule.get(field), str) or not rule[field]:
                raise RuleError(f'{identity}: {field} is required')
        if not isinstance(rule.get('groupID'), int) or not isinstance(rule.get('expectedCount'), int):
            raise RuleError(f'{identity}: groupID and expectedCount must be integers')
        if not rule['physicalReleaseEvidence'].startswith('https://'):
            raise RuleError(f'{identity}: release evidence must be a public https reference')
        if not rule['finishes'] or not rule.get('marketRarities'):
            raise RuleError(f'{identity}: finishes and marketRarities are required')
        for pattern, lanes in rule['finishes'].items():
            allowed = {'Normal'} if pattern == 'None' else {'Cold Foil', 'Holofoil'}
            if not lanes or not set(lanes) <= allowed or len(set(lanes)) != len(lanes):
                raise RuleError(f'{identity}: {pattern} lanes must be a subset of {sorted(allowed)}')
        if rule.get('stamp') is not None and not isinstance(rule['stamp'], str):
            raise RuleError(f'{identity}: stamp must be text or null')
    holds = {}
    for hold in document.get('holds', []):
        if hold['sourceCardID'] in holds or not re.fullmatch(r'[a-z][A-Za-z0-9]*', hold['reason']) or not hold['detail']:
            raise RuleError(f"Duplicate or invalid reviewed hold: {hold['sourceCardID']}")
        holds[hold['sourceCardID']] = hold
    return rules, holds


def selects(rule, row):
    return (row['id'].startswith('lorcanajson:en:') and row['setCode'] == rule['setCode']
            and row.get('distribution') == rule['distribution']
            and ('printedSets' not in rule or row['sourceSetCode'] in rule['printedSets']))


def fields(product):
    return collections.defaultdict(list, {k: [e['value'] for e in product['extendedData'] if e['name'] == k]
                                          for k in ('Number', 'Rarity')})


def title_matches(product_name, card_name):
    if name_key(product_name) == name_key(card_name):
        return True
    match = QUALIFIED.fullmatch(product_name)
    return bool(match) and name_key(match['name']) == name_key(card_name)


def number_matches(product, footer):
    numbers = fields(product)['Number']
    expected = {footer['collectorNumber'].upper(), f"{footer['collectorNumber']}/{footer['denominator']}".upper()}
    return len(numbers) == 1 and numbers[0].upper() in expected


def load_market(directory, group):
    product_bytes = (directory / f'{group}-products.json').read_bytes()
    products, prices = json.loads(product_bytes), json.loads((directory / f'{group}-prices.json').read_bytes())
    for batch in (products, prices):
        if not batch['success'] or batch['errors'] or batch.get('totalItems', len(batch['results'])) != len(batch['results']):
            raise ValueError(f'Incomplete or failed TCGCSV batch for group {group}')
    for product in products['results']:
        if product['categoryId'] != 71 or product['groupId'] != group:
            raise ValueError(f'Cross-category/group product in group {group}')
    lanes = collections.defaultdict(list)
    for price in prices['results']:
        lanes[price['productId']].append(price['subTypeName'])
    return dict(products=products['results'], lanes=lanes, sha256=hashlib.sha256(product_bytes).hexdigest())


def reconcile(rows, market, rules_document, evidence, source_links=None):
    """Return (evidence document, report). ``market`` maps group ID to load_market()."""
    rules, declared = load_rules(rules_document)
    source_links = source_links or {}
    records = [dict(r) for r in evidence['records']]
    for record in records:  # Recompute everything this pass owns.
        if 'distributionRule' in record:
            for name in PHYSICAL_FIELDS:
                record.pop(name, None)
            if record.pop('createdByDistributionRule', False):
                record['_drop'] = True
    records = [r for r in records if not r.pop('_drop', False)]
    by_product = {r['productID']: r for r in records}
    by_source = collections.defaultdict(list)
    for record in records:
        if record.get('sourceCardID'):
            by_source[record['sourceCardID']].append(record)
    owner = {}
    for rule in rules:
        for row in rows:
            if selects(rule, row):
                if row['id'] in owner:
                    raise RuleError(f"{row['id']} is selected by {owner[row['id']]} and {rule['id']}")
                owner[row['id']] = rule['id']
    footers = collections.Counter(footer_key(r['footer']) for r in rows if r['footer'])
    holds, accepted, summary = {}, [], {}
    def hold(row, reason, detail):
        holds[row['id']] = dict(sourceCardID=row['id'], printedIdentifier=row['printedIdentifier'],
                                reason=reason, detail=detail)
    for rule in rules:
        selected = sorted((r for r in rows if selects(rule, r)), key=lambda r: r['id'])
        group = market.get(rule['groupID'])
        candidates = []
        if len(selected) != rule['expectedCount'] or group is None:
            for row in selected:
                hold(row, 'ruleCountDrift', f"Rule {rule['id']} expects {rule['expectedCount']} cards"
                     f" in group {rule['groupID']}; found {len(selected)}")
            summary[rule['id']] = dict(selected=len(selected), reconciled=0, held=len(selected))
            continue
        for row in selected:
            footer, patterns = row['footer'], row['foilTypes']
            if not footer or len(patterns) != 1 or patterns[0] not in rule['finishes']:
                hold(row, 'finishOutsideRule', f"Finish {patterns} is not one the rule {rule['id']} lists")
                continue
            if footers[footer_key(footer)] > 1:
                hold(row, 'sharedFooter', f"{footers[footer_key(footer)]} discovery cards print {row['printedIdentifier']}")
                continue
            matches = [p for p in group['products'] if not FOREIGN.search(p['name'])
                       and number_matches(p, footer) and title_matches(p['name'], row['name'])]
            if len(matches) != 1:
                hold(row, 'noMarketProduct' if not matches else 'ambiguousMarketProduct',
                     f"{len(matches)} products in group {rule['groupID']} match number {footer['collectorNumber']} and title")
                continue
            product = matches[0]
            link = source_links.get(row['id'])
            if link is not None and link != product['productId']:
                hold(row, 'sourceLinkConflict', f"LorcanaJSON links product {link}; title and number match {product['productId']}")
                continue
            candidates.append((row, product))
        claims = collections.Counter(p['productId'] for _, p in candidates)
        products = set()
        for row, product in candidates:
            identity = product['productId']
            lanes = group['lanes'][identity]
            pattern = row['foilTypes'][0]
            rarity = fields(product)['Rarity']
            existing = by_product.get(identity)
            other = [r for r in by_source[row['id']] if r['productID'] != identity]
            if claims[identity] > 1:
                hold(row, 'sharedMarketProduct', f'{claims[identity]} cards in this distribution share product {identity}')
            elif len(lanes) > 1 or (lanes and lanes[0] not in rule['finishes'][pattern]):
                hold(row, 'finishLaneConflict', f'Product {identity} lanes {sorted(lanes)} disagree with {pattern}')
            elif rarity != [] and (len(rarity) != 1 or rarity[0] not in rule['marketRarities']):
                hold(row, 'marketRarityConflict', f'Product {identity} rarity {rarity}')
            elif other or (existing and (existing.get('sourceCardID') != row['id'] or existing['expectedName'] != product['name']
                                         or existing.get('printedIdentifier', row['printedIdentifier']) != row['printedIdentifier'])):
                hold(row, 'evidenceConflict', f'An existing evidence record contradicts product {identity}')
            else:
                products.add(identity)
                accepted.append((rule, row, product, lanes, rarity))
        expected_products = rule.get('expectedProducts', rule['expectedCount'])
        matched = {p['productId'] for _, p in candidates}
        if len(matched) != expected_products:
            for row in selected:
                if row['id'] not in holds:
                    hold(row, 'ruleCountDrift', f"Rule {rule['id']} expects {expected_products} products; matched {len(matched)}")
            accepted = [a for a in accepted if a[0] is not rule]
        summary[rule['id']] = dict(selected=len(selected),
                                   reconciled=sum(1 for a in accepted if a[0] is rule),
                                   held=sum(1 for r in selected if r['id'] in holds))
    for rule, row, product, lanes, rarity in accepted:
        identity = product['productId']
        group = market[rule['groupID']]
        record = by_product.get(identity)
        if record is not None and record.get('physicalReleaseEvidence'):
            continue  # Reviewed earlier by hand; this pass leaves curated records alone.
        if record is None:
            record = dict(productID=identity, expectedName=product['name'], sourceCardID=row['id'],
                          reference=f"https://tcgcsv.com/tcgplayer/71/{rule['groupID']}/products",
                          bodySHA256=group['sha256'], createdByDistributionRule=True)
            records.append(record)
            by_product[identity] = record
        pattern = row['foilTypes'][0]
        allowed = rule['finishes'][pattern]
        lane = None if pattern == 'None' else lanes[0] if lanes else allowed[0] if len(allowed) == 1 else None
        record.update(printedIdentifier=row['printedIdentifier'], groupID=rule['groupID'],
                      foilTypes=row['foilTypes'], layout=row['layout'], distribution=rule['label'],
                      distributionID='promo-' + rule['id'], distributionRule=rule['id'],
                      physicalReleaseEvidence=rule['physicalReleaseEvidence'], marketLane=lane)
        if rarity:
            record['marketRarity'] = rarity[0]
        if row['name'] != product['name']:
            record['sourceName'] = row['name']
        if rule.get('stamp'):
            record['stamp'] = rule['stamp']
    computed = {(h['sourceCardID'], h['reason']) for h in holds.values()}
    reviewed = {(h['sourceCardID'], h['reason']) for h in declared.values()}
    report = dict(schemaVersion=1, rules=summary,
                  reconciled=sorted(row['id'] for _, row, _, _, _ in accepted),
                  holds=sorted(holds.values(), key=lambda h: h['sourceCardID']),
                  unreviewedHolds=sorted(computed - reviewed), staleReviewedHolds=sorted(reviewed - computed),
                  marketSHA256={str(k): v['sha256'] for k, v in sorted(market.items())})
    output = dict(evidence)
    output['records'] = records  # Curated order is kept; new records follow it.
    return output, report


def source_links_from(cards_path):
    source = json.loads(Path(cards_path).read_bytes())
    return {f"lorcanajson:en:{card['id']}": card['externalLinks']['tcgPlayerId'] for card in source['cards']
            if card.get('externalLinks', {}).get('tcgPlayerId') is not None}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--discovery', required=True, type=Path, help='Built discovery.json')
    parser.add_argument('--market', required=True, type=Path, help='TCGCSV snapshot (<group>-products/prices.json)')
    parser.add_argument('--cards', type=Path, help='LorcanaJSON allCards.json for its TCGplayer links')
    parser.add_argument('--rules', type=Path, default=RULES)
    parser.add_argument('--evidence', type=Path, default=EVIDENCE)
    parser.add_argument('--output', required=True, type=Path, help='Evidence output (may equal --evidence)')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args(argv)
    rules_document = json.loads(args.rules.read_bytes())
    groups = {rule['groupID'] for rule in rules_document['rules']}
    market = {group: load_market(args.market, group) for group in sorted(groups)}
    rows = json.loads(args.discovery.read_bytes())['cards']
    links = source_links_from(args.cards) if args.cards else None
    evidence, report = reconcile(rows, market, rules_document, json.loads(args.evidence.read_bytes()), links)
    if args.report:
        args.report.write_text(json.dumps(report, indent=1, sort_keys=True, ensure_ascii=False) + '\n')
    print(f"{len(report['reconciled'])} reconciled; {len(report['holds'])} held "
          f"({collections.Counter(h['reason'] for h in report['holds']).most_common()})")
    if report['unreviewedHolds'] or report['staleReviewedHolds']:
        print('Holds differ from the reviewed rule file; nothing written.', file=sys.stderr)
        for key in report['unreviewedHolds']:
            print('  unreviewed hold:', *key, file=sys.stderr)
        for key in report['staleReviewedHolds']:
            print('  stale reviewed hold:', *key, file=sys.stderr)
        return 1
    args.output.write_text(json.dumps(evidence, indent=2, ensure_ascii=False) + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
