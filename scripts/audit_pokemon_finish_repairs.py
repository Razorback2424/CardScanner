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
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BASELINE = '4a9d70b12d941877e2752fe9cfb5fd1508ce0520'
SHA256 = '51e71a2a68815bd4170f4cb2ae432b577d1a456d175becfdb7a2cf3e7292672c'
LEDGER = ROOT / 'TestFixtures/TradingCards/PokemonFinishEvidence/confirmed_repairs.csv'
TABLE = ROOT / 'TradingCardScanner/PokemonChecklistSnapshot/finish-minimums.json'
COVERAGE = TABLE.with_name('finish-coverage.json')
WORKBOOK = LEDGER.with_name('pokemon_support_repairs_v2.xlsx')
V2_LEDGER = LEDGER.with_name('confirmed_repairs_v2.csv')
V2_SHA256 = 'd32090f2b276949cb77cdd263cd878cc95b7bc67b444897d7c1fe769226dd951'


def workbook_sheets():
    assert hashlib.sha256(WORKBOOK.read_bytes()).hexdigest() == V2_SHA256
    ns = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
    with zipfile.ZipFile(WORKBOOK) as z:
        rels = {r.attrib['Id']: r.attrib['Target'] for r in ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))}
        sheets = {}
        for sheet in ET.fromstring(z.read('xl/workbook.xml')).findall('s:sheets/s:sheet', ns):
            target = rels[sheet.attrib['{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id']]
            path = target.lstrip('/') if target.startswith('/') else 'xl/' + target
            rows = []
            for row in ET.fromstring(z.read(path)).findall('.//s:row', ns):
                values = []
                for cell in row:
                    # Formula cells use the recorded value, never concatenate
                    # formula text with its cached result. This is read-only.
                    value, inline = cell.find('s:v', ns), cell.find('s:is', ns)
                    values.append(value.text or '' if value is not None else ''.join(inline.itertext()) if inline is not None else '')
                rows.append(values)
            sheets[sheet.attrib['name']] = [dict(zip(rows[0], r)) for r in rows[1:]]
    assert {'Confirmed', 'New This Pass', 'Observed', 'Controls', 'Holds', 'Sources', 'Source Receipts'} <= sheets.keys()
    return sheets


def v2_rows(sheets):
    rows = []
    for row in sheets['Confirmed']:
        card_id = row['Provider ID']
        rows.append(dict(provider_id=card_id, set_id=card_id.rsplit('-', 1)[0], set_name=row['Set'],
            collector_number=row['Collector number'], card_name=row['Card name'],
            observed_finishes=row['Retained finishes'], required_minimum_finishes=row['Required minimum'],
            missing_finishes=row['Missing finishes'], missing_finish_count=row['Missing pair count'],
            extra_observed_finishes_requiring_review='normal' if 'normal' not in row['Required minimum'].split('; ') else '',
            source_ids=row['Source IDs'], evidence_urls=' | '.join(filter(None, [row['Evidence URL 1'], row['Evidence URL 2'], row['Additional evidence URLs']])),
            repository_url=row['Pinned repository URL'], git_blob_sha1=row['Git blob SHA-1'], commit=BASELINE))
    assert len(sheets['New This Pass']) == 180
    assert {r['Provider ID'] for r in sheets['New This Pass']} == {r['provider_id'] for r in rows[277:]}
    assert len(sheets['Observed']) == 504
    assert len(sheets['Holds']) == 14  # 13 Dragon Vault leads and Entei 10a/73.
    return rows


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])


def ledger(extract_v2=False):
    raw = LEDGER.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == SHA256, 'Repair ledger hash changed'
    rows = list(csv.DictReader(io.StringIO(raw.decode('utf-8-sig'))))
    assert len(rows) == len({r['provider_id'] for r in rows}) == 277
    pairs = [(r['provider_id'], f.strip()) for r in rows for f in r['missing_finishes'].split(';')]
    assert len(pairs) == len(set(pairs)) == 302
    assert all(f in {'holo', 'reverse'} for _, f in pairs)
    assert sum(bool(r['extra_observed_finishes_requiring_review']) for r in rows) == 115
    sheets = workbook_sheets()
    expanded = v2_rows(sheets)
    for original, updated in zip(rows, expanded[:277]):
        for key in ['provider_id', 'set_id', 'card_name', 'collector_number', 'observed_finishes',
                    'required_minimum_finishes', 'missing_finishes', 'missing_finish_count', 'git_blob_sha1']:
            assert original[key] == updated[key], (original['provider_id'], key)
    assert len(expanded) == len({r['provider_id'] for r in expanded}) == 457
    assert sum(int(r['missing_finish_count']) for r in expanded) == 510
    pairs = [(r['provider_id'], f.strip()) for r in expanded for f in r['missing_finishes'].split(';')]
    assert len(pairs) == len(set(pairs)) == 510
    assert all(f in {'holo', 'reverse'} for _, f in pairs)
    for receipt in sheets['Source Receipts']:
        raw = git('show', BASELINE + ':' + receipt['Repository path'])
        blob = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
        assert blob == receipt['Expected Git SHA-1']
        if receipt['Verification'] == 'Verified full blob':
            assert len(raw) == int(receipt['Raw bytes'])
            assert hashlib.sha256(raw).hexdigest() == receipt['Raw SHA-256']
    if extract_v2:
        with V2_LEDGER.open('w', encoding='utf-8-sig', newline='') as output:
            writer = csv.DictWriter(output, fieldnames=list(expanded[0]))
            writer.writeheader()
            writer.writerows(expanded)
    assert list(csv.DictReader(V2_LEDGER.open(encoding='utf-8-sig'))) == expanded
    return expanded


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
        baseline = json.loads(git('show', BASELINE + ':' + path))
        slots = [(c['providerID'], c.get('masterSetVariant', {}).get('id')) for c in cards]
        assert len(slots) == len(set(slots)), f'{ref}: duplicate slots in {set_id}'
        original_slots = {(c['providerID'], c.get('masterSetVariant', {}).get('id')) for c in baseline}
        assert {c['providerID'] for c in baseline} == {c['providerID'] for c in cards}, 'Identity set changed'
        assert original_slots <= set(slots), 'Retained membership removed'
        allowed = {(r['provider_id'], f.strip()) for r in subset for f in r['missing_finishes'].split(';')}
        assert set(slots) - original_slots <= allowed, 'Unassessed/held finish added'
        for original in baseline:
            new = next(c for c in cards if c['providerID'] == original['providerID']
                       and c.get('masterSetVariant') == original.get('masterSetVariant'))
            assert {k: v for k, v in original.items() if k != 'isSoleSlotForCard'} == {
                k: v for k, v in new.items() if k != 'isSoleSlotForCard'}, 'Unrelated metadata changed'
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


def install_generated(directory, rows):
    target = ROOT / 'TradingCardScanner/PokemonChecklistSnapshot'
    manifest = json.loads((target / 'manifest.json').read_text())
    generated = json.loads((directory / 'manifest.json').read_text())
    sets = {r['set_id'] for r in rows}
    for old in manifest['entries']:
        if old['providerID'] not in sets:
            continue
        new = next(e for e in generated['entries'] if e['set']['catalogID'] == old['set']['catalogID'])
        assert new['resource'] == old['resource']
        assert new.get('providerFingerprint') == (old.get('providerFingerprint') if 'providerProbeFingerprint' in old else None)
        raw = (directory / new['resource']).read_bytes()
        cards = json.loads(raw)
        assert len(cards) == new['expandedSlotCount'] == new['set']['cardCount']
        (target / new['resource']).write_bytes(raw)
        old.clear()
        old.update(new)
    # The normal Swift writer's fingerprint includes all decoded manifest entries.
    manifest['directoryFingerprint'] = generated['directoryFingerprint']
    (target / 'manifest.json').write_text(json.dumps(manifest, separators=(',', ':'), ensure_ascii=False) + '\n')
    report = audit('WORKTREE', rows)
    assert sum(v['missing'] for v in report.values()) == 0
    assert sum(v['slots'] for v in report.values()) == 1015


def minimum_table(rows, certified_ids):
    return {r['provider_id']: dict(setID=r['set_id'], number=r['collector_number'],
            minimum=[f.strip() for f in r['required_minimum_finishes'].split(';')],
            normalNeedsReview=bool(r['extra_observed_finishes_requiring_review'])) for r in rows
            if r['provider_id'] not in certified_ids}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ref', action='append', default=[])
    parser.add_argument('--extract-v2', action='store_true')
    parser.add_argument('--install-generated', type=Path)
    parser.add_argument('--write-table', action='store_true')
    parser.add_argument('--check-table', action='store_true')
    args = parser.parse_args()
    rows = ledger(args.extract_v2)
    if args.write_table or args.check_table:
        coverage = json.loads(COVERAGE.read_text())
        table = minimum_table(rows, {card_id for item in coverage['sets'].values() for card_id in item['cards']})
        if args.write_table:
            TABLE.write_text(json.dumps(table, indent=2, ensure_ascii=False) + '\n')
        if args.check_table:
            assert json.loads(TABLE.read_text()) == table
    if args.install_generated:
        install_generated(args.install_generated, rows)
    print(json.dumps({ref: audit(ref, rows) for ref in args.ref or [BASELINE, 'HEAD', 'WORKTREE']}, indent=2))


if __name__ == '__main__':
    main()
