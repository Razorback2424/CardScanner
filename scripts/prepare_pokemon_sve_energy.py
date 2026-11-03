#!/usr/bin/env python3
"""Prepare SVE authority through the existing signed Energy descriptor.

Numbered identity evidence only; never alters finish or product mappings.
"""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
from prepare_pokemon_membership_batch import fetch
from prepare_pokemon_pop_membership import canonical


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--fetch', action='store_true', required=True)
parser.add_argument('--checklist', type=Path, required=True)
parser.add_argument('--output-directory', type=Path, required=True)
parser.add_argument('--fixture-directory', type=Path, required=True)
args = parser.parse_args()
independent = json.loads(args.checklist.read_text())
source, source_hash = fetch('sets/sve')
names = {row['number']: row['printedName'] for row in independent['cards']}
assert len(names) == len(independent['cards']) == len(source['cards']) == source['cardCount']['official'] == 24
assert set(names) == {f'{n:03d}' for n in range(1, 25)}
for card in source['cards']:
    assert card['id'] == 'sve-' + card['localId']
    assert canonical(card['name']) == canonical(names[card['localId']].removeprefix('Basic '))
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    detailed = list(pool.map(fetch, ['cards/' + card['id'] for card in source['cards']]))
descriptor = dict(providerSetID='sve', recognitionKind='energy', printedPrefix='SVE',
    catalogLocalIDPrefix='', localIDPadWidth=3, scanEnabled=True, rulesVersion=2)
inputs = dict(sets=[descriptor])
args.output_directory.mkdir(parents=True, exist_ok=True)
args.fixture_directory.mkdir(parents=True, exist_ok=True)
evidence = dict(schemaVersion=1, date='2026-11-02',
    providerURL='https://api.tcgdex.net/v2/en/sets/sve', providerSHA256=source_hash,
    corroboratingURL=independent['sourceURL'],
    independentInputSHA256=hashlib.sha256(args.checklist.read_bytes()).hexdigest(),
    cards=[dict(providerCardID=c['id'], providerName=c['name'],
                corroboratingPrintedName=names[c['localId']], printedFooter='SVE ' + c['localId'],
                detailedSHA256=digest) for c, (_, digest) in zip(source['cards'], detailed)])
outputs = {
    args.output_directory / 'energy-input.json': inputs,
    args.output_directory / 'evidence.json': evidence,
    args.fixture_directory / 'catalog-input.json': inputs,
    args.fixture_directory / 'recorded-provider.json': dict(
        directory=[dict(id='sve', name=source['name'], cardCount=source['cardCount'])],
        sets=[source], cards=[card for card, _ in detailed])
}
for path, data in outputs.items():
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
print('24 SVE identities corroborated; existing Energy descriptor prepared, without a denominator or finish override.')
