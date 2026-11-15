#!/usr/bin/env python3
"""Export an offline, evidence-limited inventory of retained catalog records."""
import argparse
import base64
import collections
import csv
from datetime import date
import hashlib
import json
from pathlib import Path
import re

from audit_catalog_coverage import run, footer_key
from audit_set_pricing import validate_feed
from audit_one_piece_coverage import BROWSE_DISCOVERY
from discover_one_piece_products import prefixes

FIELDS = ('game source_scope record_type source_id set_name set_code product_set_code printed_set_marker card_number card_name rarity printing_id artwork_id finish '
          'verification_status price_status issue_codes issue_details recommended_action '
          'catalog_source_url market_provider market_product_id market_product_url market_group_id market_lane market_product_name market_product_number last_price_check '
          'catalog_revision market_snapshot_date possible_verified_match_id confidence review_notes assessment').split()
SUMMARY = ['game', 'source_scope', 'set_name', 'set_code', 'issue_code', 'severity', 'count']
CENSUS_FIELDS = ['game', 'code', 'identity', 'scope', 'disposition', 'detail', 'assessment']


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def make(**values):
    return {field: str(values.get(field) or '') for field in FIELDS}


def classify(row, issues):
    row['issue_codes'] = '|'.join(code for code, _, _ in issues)
    row['issue_details'] = ' | '.join(detail for _, detail, _ in issues)
    row['recommended_action'] = ' | '.join(dict.fromkeys(action for _, _, action in issues))
    row['assessment'] = assessment(row)
    return row


def assessment(row):
    codes = set(row['issue_codes'].split('|')) - {''}
    codes.discard('RAW_FINISH_COVERAGE_UNEVALUATED')
    if codes - {'PRICE_NOT_CHECKED'}:
        return 'actionable'
    return 'coverage_not_evaluated' if codes else 'no_known_exception'


def pricing(mapping, verified):
    if not verified:
        return 'unknown', []
    if mapping is None:
        return 'mapping_missing', [('PRICE_MAPPING_MISSING', 'No exact mapping is retained for this finish.', 'Review exact market mapping')]
    return 'not_checked', [('PRICE_NOT_CHECKED', 'No price observation was supplied to this offline audit.', 'Check a dated provider snapshot')]


def inventory(repo):
    root = repo / 'TradingCardScanner'
    rows = []
    manifest = read(root / 'PokemonChecklistSnapshot/manifest.json')
    for entry in manifest['entries']:
        for card in read(root / 'PokemonChecklistSnapshot' / entry['resource']):
            row = make(game='pokemon', source_scope='retained_raw', record_type='checklist_slot', source_id=card['providerID'], set_name=card.get('setName'), set_code=card.get('setCode'),
                       card_number=card.get('collectorNumber'), card_name=card.get('name'),
                       finish=(card.get('masterSetVariant') or {}).get('id'), verification_status='source_slot_unverified',
                       price_status='unknown', catalog_revision=manifest.get('generatedAt'),
                       catalog_source_url='https://api.tcgdex.net/v2/en/cards/' + card['providerID'],
                       review_notes='Raw checklist slot; read-time corrections and marketplace mapping are not evaluated.')
            rows.append(classify(row, [('RAW_FINISH_COVERAGE_UNEVALUATED', 'Raw checklist cannot establish resolved physical finishes or read-time corrections.', 'Evaluate native finish resolution')]))

    manifest = read(root / 'MagicTreatmentSnapshot/manifest.json')
    for entry in manifest['entries']:
        if not entry.get('resource'):
            continue
        for card in read(root / 'MagicTreatmentSnapshot' / entry['resource']):
            for finish in card.get('finishes') or ['']:
                row = make(game='magic', source_scope='test_only', record_type='treatment_snapshot', source_id=card.get('id'), set_name=card.get('setName'), set_code=card.get('setCode'),
                           card_number=card.get('collectorNumber'), card_name=card.get('name'), rarity=card.get('rarity'),
                           printing_id=card.get('id'), finish=finish, verification_status='source_record', price_status='unknown',
                           catalog_revision=manifest.get('generatedAt'),
                       catalog_source_url='https://api.scryfall.com/cards/' + card['id'],
                       review_notes='Test-only treatment subset; includes non-English and digital records; not the live catalog.')
                issues = [('PRICE_NOT_CHECKED', 'Live pricing and exact mappings were not evaluated.', 'Check live catalog and pricing')]
                row['price_status'] = 'not_checked'
                rows.append(classify(row, issues))

    envelope = read(root / 'OnePieceOwnerCatalog/one-piece-owner-catalog.json')
    encoded = envelope['payload']
    owner = json.loads(base64.urlsafe_b64decode(encoded + '=' * (-len(encoded) % 4)))
    registry = owner['registry']
    cards = {card['id']: card for card in registry['canonicalCards']}
    products = {product['id']: product for product in registry['products']}
    for printing in registry['printings']:
        if printing['status'] == 'superseded':
            continue
        card = cards[printing['canonicalCardID']]
        product = products.get(printing.get('releaseID'), {})
        for finish in printing.get('supportedVariantIDs') or ['']:
            mapping = next((m for m in printing.get('marketMappings', []) if m['variantID'] == finish and m['status'] == 'exact'), None)
            verified = printing['status'] == 'verified'
            status, issues = pricing(mapping, verified and bool(finish))
            if not verified:
                issues.append(('PRINTING_NEEDS_REVIEW', 'Printing status: ' + printing['status'], 'Review printing evidence'))
            if not finish:
                issues.append(('FINISH_UNVERIFIED', 'No supported finish is retained.', 'Review physical finish evidence'))
            product_codes = prefixes(product.get('label', ''))
            product_code = product_codes[0] if len(product_codes) == 1 else ''
            row = make(game='one-piece', source_scope='installed', record_type='physical_printing', source_id=printing['canonicalCardID'], set_name=product.get('label'), set_code=product_code, product_set_code=product_code, printed_set_marker=card.get('printedNumber', '').split('-')[0],
                       card_number=card.get('printedNumber'), card_name=card.get('name'), printing_id=printing['id'],
                       artwork_id=printing.get('artworkID'), finish=finish, verification_status=printing['status'],
                       price_status=status, catalog_revision=owner.get('revision'),
                       catalog_source_url=(printing.get('review') or {}).get('reference'),
                       market_provider=(mapping or {}).get('provider'), market_product_id=(mapping or {}).get('productID'),
                       market_group_id=((mapping or {}).get('qualifiers') or {}).get('groupID'),
                       market_lane=(mapping or {}).get('providerVariantID'),
                       market_product_name=((mapping or {}).get('qualifiers') or {}).get('productName'),
                       market_product_number=card.get('printedNumber') if mapping else '')
            rows.append(classify(row, issues))

    # Browse groups discoveries by product and printed number; aliases are evidence, not separate displayed cards.
    # Observations do not establish physical printing, artwork or finish IDs.
    discoveries = collections.defaultdict(list)
    cards_by_number = {c['printedNumber']: c for c in registry['canonicalCards'] if c['language'] == 'en'}
    for obs in owner['observations']:
        evidence = obs['printedEvidence']
        if evidence.get('sourceRole') == BROWSE_DISCOVERY and obs.get('productEvidence') and evidence.get('number') in cards_by_number:
            discoveries[(obs['productEvidence'][0], evidence['number'])].append(obs)
    for (product_id, number), observations in sorted(discoveries.items()):
        product = products.get(product_id, {})
        product_codes = prefixes(product.get('label', ''))
        product_code = product_codes[0] if len(product_codes) == 1 else ''
        card = cards_by_number[number]
        row = make(game='one-piece', source_scope='installed', record_type='browse_discovery', source_id='|'.join(sorted(o['id'] for o in observations)),
                   set_name=product.get('label'), set_code=product_code, product_set_code=product_code,
                   printed_set_marker=number.split('-')[0], card_number=number, card_name=card['name'],
                   verification_status='discovery', price_status='unknown', catalog_source_url=observations[0]['sourceURL'],
                   catalog_revision=owner.get('revision'), review_notes='Bandai artwork aliases: ' + '|'.join(sorted({o['printedEvidence'].get('sourceArtworkAlias', o['id']) for o in observations})) + '; product ID: ' + product_id)
        rows.append(classify(row, [('PRINTING_NEEDS_REVIEW', 'Browse discovery has no verified physical printing for this appearance.', 'Review Bandai appearance and physical printing')]))

    candidate_path = repo / 'publisher/one-piece/production/revision-4/candidate.json'
    candidate = read(candidate_path)
    candidate_products = {p['id']: p for p in candidate['registry']['products']}
    pending = collections.defaultdict(list)
    for obs in candidate['observations']:
        ev = obs['printedEvidence']
        if ev.get('sourceRole') == BROWSE_DISCOVERY and obs.get('productEvidence') and ev.get('number'):
            key = (obs['productEvidence'][0], ev['number'])
            if key not in discoveries:
                pending[key].append(obs)
    for (product_id, number), observations in sorted(pending.items()):
        label = candidate_products.get(product_id, {}).get('label', '')
        codes = prefixes(label)
        code = codes[0] if len(codes) == 1 else ''
        row = make(game='one-piece', source_scope='candidate', record_type='candidate_discovery', source_id='|'.join(sorted(o['id'] for o in observations)),
                   set_name=label, set_code=code, product_set_code=code, printed_set_marker=number.split('-')[0],
                   card_number=number, card_name=observations[0]['printedEvidence'].get('name'),
                   verification_status='candidate_discovery', price_status='unknown', catalog_source_url=observations[0]['sourceURL'],
                   catalog_revision=candidate.get('revision'), review_notes='Pending candidate; not installed. Bandai artwork aliases: ' + '|'.join(sorted({o['printedEvidence'].get('sourceArtworkAlias', o['id']) for o in observations})) + '; product ID: ' + product_id)
        rows.append(classify(row, [('PRINTING_NEEDS_REVIEW', 'Candidate discovery has no verified physical printing for this appearance.', 'Review candidate and physical printing')]))

    # A historical, explicitly incomplete unmatched-product report is useful as
    # discovery evidence, but is not a current catalog or physical authority.
    mapped = {str(m['productID']) for p in registry['printings'] if p['status'] == 'verified'
              for m in p.get('marketMappings', []) if m['status'] == 'exact' and m['provider'] == 'tcgplayer'}
    siblings = collections.defaultdict(list)
    for p in registry['printings']:
        if p['status'] == 'verified':
            siblings[cards[p['canonicalCardID']]['printedNumber']].append(p['id'])
    discovery_path = repo / 'docs/research/catalog-variant-coverage-2026-10-15/one-piece-unmatched-products.csv'
    with discovery_path.open(encoding='utf-8', newline='') as file:
        for item in csv.DictReader(file):
            if item['product_id'] in mapped:
                continue
            matches = sorted(set(siblings[item['number']]))
            issues = [('PRINTING_NEEDS_REVIEW', 'Historical unmatched marketplace product; physical identity is not established.', 'Reconcile product and physical evidence')]
            if matches:
                issues.append(('POSSIBLE_DUPLICATE', 'Verified printings share this printed number; this is not an identity match.', 'Compare artwork, release and finish'))
            row = make(game='one-piece', source_scope='historical', record_type='market_discovery', source_id='tcgplayer:' + item['product_id'],
                       set_name=item['group'], printed_set_marker=item['number'].split('-')[0] if '-' in item['number'] else '',
                       card_number=item['number'], card_name=item['name'], verification_status='discovery', price_status='unknown',
                       market_provider='tcgplayer', market_product_id=item['product_id'], market_product_url=item['source_url'],
                       market_snapshot_date='2026-10-14T20:05:55+0000', possible_verified_match_id='|'.join(matches),
                       confidence='number_only' if matches else '',
                       review_notes='Historical incomplete discovery; presale=' + item['presale'] + '; ' + item['variant_class'])
            rows.append(classify(row, issues))

    discovery = read(root / 'LorcanaCatalogSeed/discovery.json')
    market = read(root / 'LorcanaCatalogSeed/market.json')
    sources = {card['id']: card for card in discovery['cards']}
    universes = {footer_key(u['footer']): u for u in market['universes']}
    covered = set()
    for printing in market['physicalPrintings']:
        if printing['status'] == 'superseded':
            continue
        aliases = [sources[a['id']] for a in printing['sourceAliases'] if a['id'] in sources]
        card = aliases[0] if aliases else {}
        universe = universes.get(footer_key(printing['identity']['footer']), {})
        if printing['status'] == 'verified' and universe.get('isComplete'):
            covered.update(a['id'] for a in printing['sourceAliases'])
        for finish_obj in printing.get('finishes') or [{}]:
            finish = finish_obj.get('finish', '')
            mapping = next((m for m in printing.get('marketMappings', []) if m['finish'] == finish), None)
            verified = printing['status'] == 'verified'
            status, issues = pricing(mapping, verified and bool(finish))
            if not verified:
                issues.append(('PRINTING_NEEDS_REVIEW', 'Printing status: ' + printing['status'], 'Review printing evidence'))
            if not finish:
                issues.append(('FINISH_UNVERIFIED', 'No physical finish is recorded.', 'Review finish evidence'))
            if not universe.get('isComplete'):
                issues.append(('PHYSICAL_FAMILY_INCOMPLETE', 'The physical family has not been certified complete.', 'Review family-wide printing coverage'))
            row = make(game='lorcana', source_scope='retained_physical', record_type='physical_printing', source_id=card.get('id'), set_name=card.get('setName'), set_code=card.get('setCode'), card_number=card.get('number'),
                       card_name=card.get('name'), rarity=card.get('rarity'), printing_id=printing['id'],
                       artwork_id=printing['identity'].get('artworkID'), finish=finish, verification_status=printing['status'],
                       price_status=status, catalog_source_url=printing.get('imageURL'), catalog_revision=discovery.get('generatedOn'),
                       market_provider='tcgplayer' if mapping else '', market_product_id=(mapping or {}).get('productID'),
                       market_group_id=(mapping or {}).get('groupID'), market_lane=(mapping or {}).get('providerVariantID'),
                       market_product_name=(mapping or {}).get('productName'), market_product_number=(mapping or {}).get('productNumber'))
            rows.append(classify(row, issues))
    for identity, card in sources.items():
        if identity in covered:
            continue
        row = make(game='lorcana', source_scope='retained_discovery', record_type='discovery', source_id=identity, set_name=card.get('setName'), set_code=card.get('setCode'), card_number=card.get('number'),
                   card_name=card.get('name'), rarity=card.get('rarity'), verification_status='discovery', price_status='unknown',
                   catalog_source_url=card.get('imageURL'), catalog_revision=discovery.get('generatedOn'), review_notes=identity)
        rows.append(classify(row, [('PRINTING_NEEDS_REVIEW', 'Discovery record lacks a complete verified physical family.', 'Review physical printing evidence')]))

    seed = read(root / 'YuGiOhCatalogSeed/catalog.json')
    sets = {item['g']: item for item in seed['sets']}
    for printing in seed['printings'] + seed.get('referencePrintings', []):
        card = seed['cards'][printing['k']]
        group = sets[printing['g']]
        supported = printing.get('ir') is None and printing['e'] and (printing['ec'] or printing.get('m'))
        for edition in printing['e'] or ['']:
            membership = next((m for m in printing.get('m', []) if m['e'] == edition), None)
            row = make(game='yugioh', source_scope='retained_seed', record_type='physical_printing', source_id=card.get('sourceID'), set_name=group.get('n'), set_code=group.get('a'), card_number=printing.get('c'),
                       card_name=card.get('n'), rarity=printing.get('r'), printing_id=printing['id'], finish=edition,
                       verification_status='supported' if supported else 'held', price_status='unknown',
                       catalog_source_url=printing.get('img'), catalog_revision=seed.get('generation'),
                       market_provider='tcgplayer' if membership and printing.get('p') else '',
                       market_product_id=printing.get('p') if membership else '',
                       market_group_id=printing.get('pg', printing['g']) if membership else '',
                       market_lane={'yugioh1stEdition': '1st Edition', 'yugiohUnlimited': 'Unlimited', 'yugiohLimited': 'Limited'}.get(edition) if membership else '',
                       market_product_name=printing.get('pn') if membership else '', market_product_number=printing.get('c') if membership else '',
                       review_notes='Edition is recorded in finish; rarity is a separate printing attribute.')
            if supported and membership and printing.get('p'):
                issues = [('PRICE_NOT_CHECKED', 'Exact edition membership is retained; live quote was not evaluated.', 'Check exact edition pricing')]
                row['price_status'] = 'not_checked'
            elif supported and edition:
                issues = [('PRICE_MAPPING_MISSING', 'No exact product and edition membership is retained.', 'Review exact edition mapping')]
                row['price_status'] = 'mapping_missing'
            else:
                issues = []
            if not supported:
                issues.append(('PRINTING_NEEDS_REVIEW', printing.get('ir') or 'No supported edition membership.', 'Review printing and edition evidence'))
            if not edition:
                issues.append(('EDITION_UNVERIFIED', 'No supported physical edition is retained.', 'Review edition evidence'))
            if printing.get('canonicalLink') == 'unresolved':
                issues.append(('CANONICAL_LINK_UNRESOLVED', 'The physical printing has no resolved canonical-card link.', 'Review canonical identity'))
            if printing['c'] in seed.get('incompleteCodes', []):
                issues.append(('PRINTING_FAMILY_INCOMPLETE', 'The printed code is explicitly marked incomplete.', 'Review printing family and distinctions'))
            rows.append(classify(row, issues))
    return sorted(rows, key=lambda r: tuple(r[f] for f in ('game', 'set_code', 'card_number', 'card_name', 'printing_id', 'finish', 'review_notes')))


def write(path, fields, rows):
    with path.open('w', encoding='utf-8', newline='') as file:
        writer = csv.DictWriter(file, fieldnames=fields, lineterminator='\n')
        writer.writeheader()
        for row in rows:
            writer.writerow({key: spreadsheet_safe(value) for key, value in row.items()})


def spreadsheet_safe(value):
    value = str(value)
    return "'" + value if value and (value[0] in '\t\r\n' or value.lstrip().startswith(('=', '+', '-', '@'))) else value


def load_prices(directory):
    """Replay hash-bound, complete feed pairs from the existing capture format."""
    manifest = read(directory / 'capture.json')
    upstream = manifest['upstreamBuild']
    if manifest.get('mappedFeedsUpstreamBuild') != upstream:
        raise ValueError('Mapped feeds are incomplete or from another upstream build')
    snapshot_date = date.fromisoformat(upstream[:10])
    feeds = {}
    for name, receipt in manifest['captures'].items():
        parts = name.removesuffix('.json').split('-')
        if len(parts) != 3 or parts[2] not in ('products', 'prices') or not all(p.isdigit() for p in parts[:2]):
            continue
        category, group = map(int, parts[:2])
        expected = f'https://tcgcsv.com/tcgplayer/{category}/{group}/{parts[2]}'
        raw = (directory / name).read_bytes()
        if receipt.get('sourceURL') != expected or receipt.get('sha256') != hashlib.sha256(raw).hexdigest():
            raise ValueError('Changed or incorrectly scoped capture: ' + name)
        feeds.setdefault((category, group), {})[parts[2]] = validate_feed(raw, category, group, parts[2])
    return snapshot_date, feeds


def apply_prices(rows, snapshot_date, feeds, as_of, max_age_days):
    if as_of < snapshot_date:
        raise ValueError('Evaluation date precedes marketplace snapshot')
    indexes = {key: ({p['productId']: p for p in feed['products']},
                     {(p['productId'], p['subTypeName']): p.get('marketPrice') for p in feed['prices']})
               for key, feed in feeds.items() if {'products', 'prices'} <= feed.keys()}
    for row in rows:
        if row['record_type'] != 'physical_printing' or row['market_provider'] != 'tcgplayer' or not row['market_lane'] or not row['market_group_id'].isdigit():
            continue
        category = {'one-piece': 68, 'lorcana': 71, 'yugioh': 2}.get(row['game'])
        index = indexes.get((category, int(row['market_group_id'])))
        if not index:
            continue
        product = int(row['market_product_id'])
        products, prices = index
        observed = products.get(product)
        numbers = [v['value'] for v in observed.get('extendedData', []) if v['name'] == 'Number'] if observed else []
        if (not observed or not row['market_product_name'] or not row['market_product_number']
                or observed.get('name') != row['market_product_name'] or numbers != [row['market_product_number']]):
            continue  # Product identity drift is not proof of quote availability.
        quote = prices.get((product, row['market_lane']))
        codes = row['issue_codes'].split('|') if row['issue_codes'] else []
        details = row['issue_details'].split(' | ') if row['issue_details'] else []
        issues = [(code, detail, '') for code, detail in zip(codes, details) if code != 'PRICE_NOT_CHECKED']
        row['market_snapshot_date'] = snapshot_date.isoformat()
        if quote is None:
            row['price_status'] = 'no_quote'
            issues.append(('NO_MARKET_QUOTE', 'Captured feed has no usable market price for this product and lane.', 'Review provider availability'))
        elif (as_of - snapshot_date).days > max_age_days:
            row['price_status'] = 'stale'
            issues.append(('PRICE_STALE', f'Quote snapshot is older than {max_age_days} days as of {as_of}.', 'Refresh provider snapshot'))
        else:
            row['price_status'] = 'quoted'
        # Existing actions belong to other issues; drop the resolved lookup action.
        actions = [a for a in row['recommended_action'].split(' | ')
                   if a and a not in ('Check a dated provider snapshot', 'Check exact edition pricing')]
        actions.extend(action for _, _, action in issues if action)
        row['issue_codes'] = '|'.join(code for code, _, _ in issues)
        row['issue_details'] = ' | '.join(detail for _, detail, _ in issues)
        row['recommended_action'] = ' | '.join(dict.fromkeys(actions))
        row['assessment'] = assessment(row)


def export(repo, output, capture_dir=None, as_of=None, max_age_days=30):
    result, census_findings = run(repo)
    if result['structuralErrors']:
        raise ValueError('Catalog validation failed: ' + json.dumps(result['structuralErrors']))
    rows = inventory(repo)
    snapshot_date = None
    if capture_dir:
        if as_of is None:
            raise ValueError('--as-of is required with --capture-dir for reproducible freshness')
        snapshot_date, feeds = load_prices(capture_dir)
        apply_prices(rows, snapshot_date, feeds, as_of, max_age_days)
    output.mkdir(parents=True, exist_ok=True)
    write(output / 'catalog-inventory.csv', FIELDS, rows)
    write(output / 'catalog-exceptions.csv', FIELDS, (row for row in rows if row['assessment'] == 'actionable'))
    # These are source-/set-level findings, not invented physical printing rows.
    # Preserve the original audit's disposition: informational and risk cohorts are not defects.
    def census_assessment(item):
        if item['disposition'] in ('informational', 'source_risk_cohort', 'runtime_projection_required'):
            return 'coverage_not_evaluated'
        if item['disposition'] in ('intentionally_held', 'unsupported_placeholder'):
            return 'known_limitation'
        return 'actionable'
    write(output / 'catalog-census-findings.csv', CENSUS_FIELDS,
          ({**item, 'assessment': census_assessment(item)} for item in census_findings))
    severity = {'RAW_FINISH_COVERAGE_UNEVALUATED': 'unchecked', 'PHYSICAL_FAMILY_INCOMPLETE': 'review',
                'EDITION_UNVERIFIED': 'review', 'CANONICAL_LINK_UNRESOLVED': 'review', 'PRINTING_FAMILY_INCOMPLETE': 'review',
                'PRINTING_NEEDS_REVIEW': 'review', 'POSSIBLE_DUPLICATE': 'review',
                'FINISH_UNVERIFIED': 'review', 'PRICE_MAPPING_MISSING': 'review',
                'NO_MARKET_QUOTE': 'availability', 'PRICE_STALE': 'refresh',
                'PRICE_NOT_CHECKED': 'unchecked'}
    counts = collections.Counter((row['game'], row['source_scope'], row['set_name'], row['set_code'], code, severity.get(code, 'review'))
                                 for row in rows for code in row['issue_codes'].split('|') if code)
    write(output / 'catalog-summary.csv', SUMMARY,
          (dict(zip(SUMMARY, (*key, count))) for key, count in sorted(counts.items())))
    metadata = dict(schemaVersion=2, boundary=result['boundary'], sources=result['sources'],
                    marketCaptureSHA256=hashlib.sha256((capture_dir / 'capture.json').read_bytes()).hexdigest() if capture_dir else None,
                    marketSnapshotDate=snapshot_date.isoformat() if snapshot_date else None,
                    freshnessAsOf=as_of.isoformat() if as_of else None, maxAgeDays=max_age_days if capture_dir else None,
                    onePieceDiscoverySHA256=hashlib.sha256((repo / 'docs/research/catalog-variant-coverage-2026-10-15/one-piece-unmatched-products.csv').read_bytes()).hexdigest(),
                    onePieceCandidateSHA256=hashlib.sha256((repo / 'publisher/one-piece/production/revision-4/candidate.json').read_bytes()).hexdigest())
    (output / 'catalog-metadata.json').write_text(json.dumps(metadata, indent=2, sort_keys=True) + '\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--capture-dir', type=Path, help='Retained audit_set_pricing.py capture directory')
    parser.add_argument('--as-of', type=date.fromisoformat, help='Freshness evaluation date (YYYY-MM-DD)')
    parser.add_argument('--max-age-days', type=int, default=30, help='Maximum quote age in days (default: 30)')
    args = parser.parse_args()
    if args.max_age_days < 0 or (args.as_of and not args.capture_dir):
        parser.error('Use a nonnegative max age and supply --capture-dir with --as-of')
    export(args.repo.resolve(), args.output, args.capture_dir, args.as_of, args.max_age_days)


if __name__ == '__main__':
    main()
