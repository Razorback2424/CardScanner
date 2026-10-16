#!/usr/bin/env python3
"""Reconcile retained public inventories without granting physical identity authority.

Reports source records, physical printings, ownership and pricing separately.
No network requests, UUID allocation, signature changes or automatic promotion.
"""
import argparse
import base64
import collections
import csv
import hashlib
import json
from pathlib import Path


def read(path):
    return json.loads(path.read_bytes())


def source_receipt(path):
    return dict(sha256=hashlib.sha256(path.read_bytes()).hexdigest(), bytes=path.stat().st_size)


def write_csv(path, rows, fields):
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def audit(repo, magic_sets, one_piece_products, lorcana_cards, pokemon_sets, pokemon_pocket_series, output):
    output.mkdir(parents=True, exist_ok=True)
    summary = dict(schemaVersion=1, boundary='Public source records are discovery leads, not a complete physical-printing denominator.',
        sources={name: source_receipt(path) for name, path in [('magicSets', magic_sets), ('onePieceProducts', one_piece_products), ('lorcanaCards', lorcana_cards), ('pokemonSets', pokemon_sets), ('pokemonPocketSeries', pokemon_pocket_series)]})

    # The long-code CSV is deliberately not an optical-success assertion:
    # inspected PLG20 cards print PRM; inspected PTKDF cards print DTK.
    sets = read(magic_sets)['data']
    long_codes = [s for s in sets if not s['digital'] and s.get('released_at', '') >= '2014-07-18'
        and s['set_type'] not in {'token', 'memorabilia', 'minigame', 'art_series'} and not 3 <= len(s['code']) <= 4]
    write_csv(output/'magic-long-code-sets.csv', [dict(code=s['code'], name=s['name'], release=s.get('released_at'),
        source_record_count=s['card_count'], set_type=s['set_type'], source_url='https://api.scryfall.com/sets/'+s['code'],
        disposition='Reviewed printed-footer mappings' if s['code'] in {'plg20', 'ptkdf'} else 'Needs actual footer/layout reconciliation') for s in sorted(long_codes, key=lambda s:s['code'])],
        ['code', 'name', 'release', 'source_record_count', 'set_type', 'source_url', 'disposition'])
    summary['magic'] = dict(directorySets=len(sets), longCodeSets=len(long_codes),
        longCodeSourceRecords=sum(s['card_count'] for s in long_codes), reviewedFooterMappings=6,
        note='PT SNC contains token layouts despite promo set metadata. Long provider codes do not prove printed codes.')

    pokemon_root = repo/'TradingCardScanner/PokemonChecklistSnapshot'
    manifest = read(pokemon_root/'manifest.json')
    eligibility = repo/'docs/research/card-coverage-gap-data/2026-10-05/pokemon_parallel_slots.csv'
    expected = collections.defaultdict(set)
    with eligibility.open() as stream:
        for row in csv.DictReader(stream):
            expected[row['app_set_id']].add((int(row['collector_number']), {'pokeball':'pokeBall','masterball':'masterBall'}[row['foil_pattern']]))
    parallel_rows = []
    for sid, slots in sorted(expected.items()):
        entry = next(e for e in manifest['entries'] if e['providerID'] == sid)
        cards = read(pokemon_root/entry['resource'])
        observed = {(int(c['collectorNumber']), c.get('masterSetVariant',{}).get('id')) for c in cards
            if c.get('masterSetVariant',{}).get('id') in {'pokeBall','masterBall'}}
        parallel_rows.append(dict(set=sid, expectedSlots=len(slots), bundledSlots=len(observed),
            missingSlots=len(slots-observed), unexpectedSlots=len(observed-slots)))
    summary['pokemon'] = dict(snapshotGeneratedAt=manifest['generatedAt'], setEntries=len(manifest['entries']),
        distinctProviderSets=len({e['providerID'] for e in manifest['entries']}), parallelInventories=parallel_rows,
        note='All 471 retained ball slots already exist in bundled checklists. Resolver fallback was broader; tests now protect exact eligibility. Other stamp/edition distributions have no independent complete denominator.')
    provider_sets = read(pokemon_sets)
    pocket_series = read(pokemon_pocket_series)
    if pocket_series['id'] != 'tcgp':
        raise ValueError('Expected the provider Pocket series inventory')
    digital_sets = {s['id'] for s in pocket_series['sets']}
    bundled_sets = {e['providerID'] for e in manifest['entries']}
    absent_sets = [dict(set_id=s['id'], name=s['name'], provider_card_count=s['cardCount']['total'],
        source_url='https://api.tcgdex.net/v2/en/sets/'+s['id'],
        disposition='Digital Pocket; outside physical scope' if s['id'] in digital_sets else
            'Absent from offline checklist; live lookup may exist, release/scope must be reconciled') for s in provider_sets if s['id'] not in bundled_sets]
    write_csv(output/'pokemon-sets-absent-offline.csv', absent_sets, ['set_id','name','provider_card_count','source_url','disposition'])
    summary['pokemon'].update(currentProviderSets=len(provider_sets), setsAbsentOffline=len(absent_sets),
        digitalSetsAmongAbsent=sum(s['disposition'].startswith('Digital') for s in absent_sets))

    registry = read(repo/'OnePieceCatalogCore/ReviewCorpus/english-stress/registry.json')
    envelope = read(repo/'TradingCardScanner/OnePieceOwnerCatalog/one-piece-owner-catalog.json')
    payload = envelope['payload']
    installed = json.loads(base64.urlsafe_b64decode(payload+'='*(-len(payload)%4)))
    installed_market = {str(m['productID']) for p in installed['registry']['printings'] if p['status']=='verified' and p['language']=='en' for m in p['marketMappings']}
    reviewed = read(repo/'OnePieceCatalogCore/ReviewCorpus/english-stress/special-printings-review.json')
    pending = {str(p['comparisonProductID']) for p in reviewed['printings']}
    inventory = read(one_piece_products)
    gaps = []
    for row in inventory['cards']:
        if str(row['tcgplayer_product_id']) in installed_market:
            continue
        gaps.append(dict(product_id=row['tcgplayer_product_id'], number=row['printed_card_number'], name=row['product_name'],
            group=row['group_name'], variant_class=row['variant_class'], variant_labels=';'.join(row['variant_labels']),
            record_kind=row['catalog_status'], presale=row['is_presale'], source_url=row['tcgplayer_url'],
            disposition='Reviewed candidate; pending signed local activation' if str(row['tcgplayer_product_id']) in pending else 'Unmatched source product; needs physical identity/release/finish reconciliation'))
    write_csv(output/'one-piece-unmatched-products.csv', gaps,
        ['product_id','number','name','group','variant_class','variant_labels','record_kind','presale','source_url','disposition'])
    summary['onePiece'] = dict(upstreamBuild=inventory['meta']['upstream_build'], sourceRecords=len(inventory['cards']),
        installedRevision=installed['revision'], installedVerifiedEnglishPrintings=sum(p['status']=='verified' and p['language']=='en' for p in installed['registry']['printings']),
        reviewVerifiedEnglishPrintings=sum(p['status']=='verified' and p['language']=='en' for p in registry['printings']),
        unmatchedSourceProducts=len(gaps), unmatchedClasses=dict(sorted(collections.Counter(r['variant_class'] for r in gaps).items())),
        unmatchedPresales=sum(r['presale'] for r in gaps), pendingReviewedPrintings=len(pending),
        note='Unmatched means no exact installed market association. It does not prove a missing physical printing; duplicate listings, unpriced known cards, presales and other scope are retained for review.')

    discovery = read(repo/'TradingCardScanner/LorcanaCatalogSeed/discovery.json')
    physical = read(repo/'TradingCardScanner/LorcanaCatalogSeed/market.json')
    upstream = read(lorcana_cards)
    expected_ids = {'lorcanajson:en:'+str(c['id']) for c in upstream['cards']}
    discovery_ids = {c['id'] for c in discovery['cards']}
    physical_aliases = {a['id'] for p in physical['physicalPrintings'] if p['status']=='verified' for a in p['sourceAliases']}
    held = [dict(source_id=c['id'], name=c['name'], set=c['setCode'], number=c['number'], rarity=c['rarity'],
        foil_types=';'.join(c['foilTypes']), disposition='Discovery/recovery only; no reviewed physical ownership', source_url=c['imageURL'])
        for c in discovery['cards'] if c['id'] not in physical_aliases]
    write_csv(output/'lorcana-discovery-only.csv', held, ['source_id','name','set','number','rarity','foil_types','disposition','source_url'])
    summary['lorcana'] = dict(upstreamGeneratedOn=upstream['metadata']['generatedOn'], upstreamRecords=len(expected_ids),
        upstreamMissingFromDiscovery=sorted(expected_ids-discovery_ids), discoveryRecords=len(discovery_ids),
        physicalPrintings=len(physical['physicalPrintings']), exactFinishMappings=sum(len(p.get('marketMappings',[])) for p in physical['physicalPrintings']),
        enchantedPrintings=sum(p['identity']['distributionID'].startswith('enchanted-expansion-') for p in physical['physicalPrintings']),
        discoveryOnlyRecords=len(held), discoveryOnlyRarities=dict(sorted(collections.Counter(r['rarity'] for r in held).items())))
    (output/'summary.json').write_text(json.dumps(summary, indent=2, sort_keys=True)+'\n')
    return summary


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    for name in ['magic-sets', 'one-piece-products', 'lorcana-cards', 'pokemon-sets', 'pokemon-pocket-series', 'output']:
        parser.add_argument('--'+name, type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.repo, args.magic_sets, args.one_piece_products, args.lorcana_cards, args.pokemon_sets, args.pokemon_pocket_series, args.output)
    print(json.dumps({game:result[game] for game in ['magic','pokemon','onePiece','lorcana']}, indent=2))
