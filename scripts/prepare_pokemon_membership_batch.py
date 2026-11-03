#!/usr/bin/env python3
"""Corroborate recorded English tables against a live provider, unsigned only.

The independent input is a reviewed factual transcription from the web tool.
This utility never signs, publishes, changes finishes, or edits production input.
"""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import time
import urllib.request

from prepare_pokemon_pop_membership import canonical


def fetch(path):
    url = 'https://api.tcgdex.net/v2/en/' + path
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=30) as response:
                raw = response.read()
            return json.loads(raw), hashlib.sha256(raw).hexdigest()
        except Exception:
            if attempt == 2:
                raise
            time.sleep(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fetch', action='store_true', required=True)
    parser.add_argument('--checklists', type=Path, required=True)
    parser.add_argument('--output-directory', type=Path, required=True)
    parser.add_argument('--fixture-directory', type=Path, required=True)
    args = parser.parse_args()
    tables = json.loads(args.checklists.read_text())['sets']
    directory, directory_hash = fetch('sets')
    descriptors, receipts, sets = [], [], []
    for table in tables:
        if table.get('hold'):
            continue
        title = table.get('providerSetID') or f"McDonald's Collection {table['year']}"
        matches = [row for row in directory if
                   row['id'] == table['providerSetID']] if table.get('providerSetID') else [
                       row for row in directory if row['name'] == title]
        assert len(matches) == 1, title
        identity = matches[0]['id']
        source, digest = fetch('sets/' + identity)
        denominator = source['cardCount']['official']
        independent = {row['number']: row for row in table['cards']}
        assert len(independent) == len(table['cards']) == len(source['cards']) == denominator
        assert set(independent) == set(range(1, denominator + 1))
        members, facts = [], []
        for card in source['cards']:
            row = independent[int(card['localId'])]
            assert row['denominator'] == denominator
            assert canonical(row['name']) == canonical(card['name']), (identity, row, card)
            assert card['id'] == identity + '-' + card['localId']
            printed_denominator = row.get('printedDenominator', denominator)
            if printed_denominator != denominator:
                # Explicit reviewed physical-footer evidence, never inferred
                # from a provider's normalized set count.
                assert len(set(row.get('physicalSources', []))) >= 2
                assert all(url.startswith('https://') for url in row['physicalSources'])
            members.append(dict(providerCardID=card['id'], canonicalName=canonical(card['name']),
                printedLocalID=str(row['number']), printedDenominator=printed_denominator))
            facts.append(dict(providerCardID=card['id'], providerName=card['name'],
                corroboratingName=row['name'], printedNumber=f"{row['number']}/{printed_denominator}",
                physicalSources=row.get('physicalSources', [])))
        descriptors.append(dict(providerSetID=identity, recognitionKind='notScannable',
            scanEnabled=False, rulesVersion=1, membershipRecognition=dict(members=members)))
        receipts.append(dict(providerSetID=identity, sourceURL='https://api.tcgdex.net/v2/en/sets/' + identity,
            sourceSHA256=digest, corroboratingURL=table['sourceURL'], cards=facts))
        sets.append(source)
    # Native validation consumes complete provider details, not invented cards.
    ids = [card['id'] for source in sets for card in source['cards']]
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        detailed = list(pool.map(fetch, ['cards/' + identity for identity in ids]))
    inputs = dict(sets=descriptors)
    args.output_directory.mkdir(parents=True, exist_ok=True)
    args.fixture_directory.mkdir(parents=True, exist_ok=True)
    outputs = {
        args.output_directory / 'membership-input.json': inputs,
        args.output_directory / 'evidence.json': dict(schemaVersion=1, date='2026-11-02',
            independentInputSHA256=hashlib.sha256(args.checklists.read_bytes()).hexdigest(),
            directorySHA256=directory_hash, sets=receipts,
            heldSets=[dict(providerSetID=t.get('providerSetID'), reason=t['hold']) for t in tables if t.get('hold')],
            detailedCardSHA256=dict(zip(ids, [row[1] for row in detailed]))),
        args.fixture_directory / 'catalog-input.json': inputs,
        args.fixture_directory / 'recorded-provider.json': dict(
            directory=[row for row in directory if row['id'] in {s['id'] for s in sets}],
            sets=sets, cards=[row[0] for row in detailed])
    }
    for path, data in outputs.items():
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
    print(f'Corroborated {len(ids)} numbered English identities in {len(sets)} sets; complete native fixture prepared.')


if __name__ == '__main__':
    main()
