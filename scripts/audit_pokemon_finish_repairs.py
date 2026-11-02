#!/usr/bin/env python3
"""Audit exact Git blobs and generate the bounded, additive finish evidence table.

No network, prices, range inference, or collection access. The original UTF-8 BOM
ledger is retained byte-for-byte. --write-table only updates its runtime projection.
"""
import argparse
import collections
import csv
import hashlib
import io
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASELINE = '4a9d70b12d941877e2752fe9cfb5fd1508ce0520'
SHA256 = '51e71a2a68815bd4170f4cb2ae432b577d1a456d175becfdb7a2cf3e7292672c'
LEDGER = ROOT / 'TestFixtures/TradingCards/PokemonFinishEvidence/confirmed_repairs.csv'
TABLE = ROOT / 'TradingCardScanner/PokemonChecklistSnapshot/finish-minimums.json'


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])


def ledger():
    raw = LEDGER.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == SHA256, 'Repair ledger hash changed'
    rows = list(csv.DictReader(io.StringIO(raw.decode('utf-8-sig'))))
    assert len(rows) == len({r['provider_id'] for r in rows}) == 277
    pairs = [(r['provider_id'], f.strip()) for r in rows for f in r['missing_finishes'].split(';')]
    assert len(pairs) == len(set(pairs)) == 302
    assert all(f in {'holo', 'reverse'} for _, f in pairs)
    assert sum(bool(r['extra_observed_finishes_requiring_review']) for r in rows) == 115
    return rows


def audit(ref, rows):
    totals = collections.defaultdict(lambda: dict(identities=0, missing=0, present=0, slots=0))
    for set_id in dict.fromkeys(r['set_id'] for r in rows):
        subset = [r for r in rows if r['set_id'] == set_id]
        path = subset[0]['repository_url'].split('/' + BASELINE + '/')[1]
        raw = (ROOT / path).read_bytes() if ref == 'WORKTREE' else git('show', ref + ':' + path)
        blob = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
        if ref == BASELINE:
            assert {r['git_blob_sha1'] for r in subset} == {blob}
        cards = json.loads(raw)
        slots = [(c['providerID'], c.get('masterSetVariant', {}).get('id')) for c in cards]
        assert len(slots) == len(set(slots)), f'{ref}: duplicate slots in {set_id}'
        for row in subset:
            group = [c for c in cards if c['providerID'] == row['provider_id']]
            assert group, f"Missing identity: {row['provider_id']}"
            assert all(c['collectorNumber'] == row['collector_number'] and c['name'] == row['card_name']
                       and c['setID']['providerID'] == set_id for c in group)
            finishes = {c.get('masterSetVariant', {}).get('id') for c in group}
            missing = {f.strip() for f in row['missing_finishes'].split(';')}
            if ref == BASELINE:
                assert finishes == {'normal'}
                assert len(missing) == int(row['missing_finish_count'])
            totals[set_id]['identities'] += 1
            totals[set_id]['missing'] += len(missing - finishes)
            totals[set_id]['present'] += len(missing & finishes)
        totals[set_id]['slots'] = len(cards)
    return dict(totals)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ref', action='append', default=[])
    parser.add_argument('--write-table', action='store_true')
    parser.add_argument('--check-table', action='store_true')
    args = parser.parse_args()
    rows = ledger()
    table = {r['provider_id']: dict(setID=r['set_id'], number=r['collector_number'],
             minimum=[f.strip() for f in r['required_minimum_finishes'].split(';')],
             normalNeedsReview=bool(r['extra_observed_finishes_requiring_review'])) for r in rows}
    if args.write_table:
        TABLE.write_text(json.dumps(table, indent=2, ensure_ascii=False) + '\n')
    if args.check_table:
        assert json.loads(TABLE.read_text()) == table
    print(json.dumps({ref: audit(ref, rows) for ref in args.ref or [BASELINE, 'HEAD', 'WORKTREE']}, indent=2))


if __name__ == '__main__':
    main()
