import hashlib
import importlib.util
import json
import subprocess
import sys
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("sources", Path(__file__).parents[1] / "normalize_one_piece_sources.py")
sources = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sources)


def capture(payload, provider="bandai", **updates):
    item = {"id": "capture", "provider": provider, "numbers": ["OP01-120"],
            "sourceURL": "https://en.onepiece-cardgame.com/cardlist/?series=569101" if provider == "bandai"
                else "https://onepiece.limitlesstcg.com/cards/en/OP01-120",
            "observedAt": "2026-10-04T00:00:00Z", "rawFile": "page.html",
            "payloadSHA256": hashlib.sha256(payload).hexdigest()}
    return dict(item, **updates)


def bandai(alias="OP01-120"):
    # Authored minimal schema fixture; no copied card rules text or assets.
    return f'''<dl class="modalCol" id="{alias}">
      <div class="infoCol"><span>OP01-120</span><span>SEC</span></div>
      <div class="cardName">Shanks</div>
      <div class="frontCol"><img data-src="../images/cardlist/card/{alias}.png?version=1"></div>
      <div class="getInfo"><h3>Card Set(s)</h3>Product A</div>
      <div class="getInfo"><h3>Notes</h3>Errata</div>
      <div class="block"><h3>Block<br>icon</h3>1</div>
    </dl>'''.encode()


def limitless(rows=2):
    table_rows = ''.join(f'''<tr><td><a {('href=/cards/en/OP01-120?v='+str(i)) if i else ''}>
      Product {i}<span class="prints-table-card-number">{'manga' if i else ''}</span></a></td>
      <td><a href="https://market.invalid/product/{i}">$999</a></td><td>EUR</td></tr>''' for i in range(rows))
    return f'''<span class="card-text-name"><a href="/cards/en/OP01-120">Shanks</a></span>
      <table class="card-prints-versions"><tr><th>Print</th><th>USD</th><th>EUR</th></tr>{table_rows}</table>
      <div class="card-prints-reprints"><a href="/cards/prb01-example">Reprint product</a></div>'''.encode()


class SourceNormalizationTests(unittest.TestCase):
    def test_bandai_uses_product_heading_not_errata_and_preserves_artwork_aliases(self):
        payload = bandai() + bandai("OP01-120_p1")
        records, inventory = sources.normalize_page(capture(payload), payload)
        self.assertEqual(len(records), 2)
        self.assertEqual({r['alias']['sourceID'] for r in records}, {'OP01-120', 'OP01-120_p1'})
        self.assertEqual(records[0]['printedEvidence']['sourceLabel'], 'Product A')
        self.assertEqual(records[0]['printedEvidence']['blockText'], '1')
        self.assertNotIn('imageSHA256', records[0])
        self.assertFalse(inventory['paginationComplete'])

    def test_limitless_keeps_all_rows_and_separate_reprint_appearance_without_prices(self):
        payload = limitless(61)
        records, inventory = sources.normalize_page(capture(payload, "limitless"), payload)
        self.assertEqual(len(records), 62)
        self.assertIn('manga', {r['printedEvidence'].get('sourceMarker') for r in records})
        self.assertTrue(any('|appearance:' in r['alias']['sourceID'] for r in records))
        self.assertNotIn('$999', json.dumps(records))
        self.assertNotIn('market.invalid', json.dumps(records))
        self.assertFalse(inventory['paginationComplete'])
        self.assertTrue(all(r['productEvidence'] == [] for r in records))

    def test_changed_bytes_missing_targets_foreign_origins_and_duplicate_aliases_fail(self):
        payload = bandai()
        for item, body in [(capture(payload), payload+b'changed'),
                           (capture(payload, numbers=['ST01-007']), payload),
                           (capture(payload, sourceURL='https://foreign.invalid/cardlist/'), payload),
                           (capture(payload+payload), payload+payload)]:
            with self.subTest(item=item):
                with self.assertRaises(ValueError):
                    sources.normalize_page(item, body)

    def test_market_or_japanese_links_cannot_become_english_print_aliases(self):
        for target in [b'/cards/jp/OP01-120?v=1', b'https://foreign.invalid/cards/en/OP01-120?v=1']:
            payload = limitless().replace(b'/cards/en/OP01-120?v=1', target)
            with self.assertRaises(ValueError):
                sources.normalize_page(capture(payload, 'limitless'), payload)
        payload = limitless().replace(b'class="card-prints-versions"', b'class="unknown-table"')
        with self.assertRaises(ValueError):
            sources.normalize_page(capture(payload, 'limitless'), payload)

    def test_current_variant_page_retains_its_query_instead_of_becoming_base_print(self):
        payload = limitless(1)
        item = capture(payload, 'limitless', sourceURL='https://onepiece.limitlesstcg.com/cards/en/OP01-120?v=2')
        records, _ = sources.normalize_page(item, payload)
        self.assertEqual(records[0]['alias']['sourceID'], 'en/OP01-120?v=2')

    def test_capture_bounds_and_paths_fail_without_reading_other_files(self):
        with self.assertRaises(ValueError):
            sources.Document(b' ' * (sources.MAX_BYTES + 1))
        payload = bandai()
        with tempfile.TemporaryDirectory() as directory:
            for filename in ['../page.html', '/private/page.html']:
                with self.assertRaises(ValueError):
                    sources.normalize_manifest({'schemaVersion': 1, 'captures': [capture(payload, rawFile=filename)]}, Path(directory))

    def test_same_artwork_alias_on_different_product_captures_stays_separate(self):
        first = bandai()
        second = first.replace(b'Product A', b'Product B')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'first.html').write_bytes(first)
            (root/'second.html').write_bytes(second)
            manifest = {'schemaVersion': 1, 'captures': [capture(first, id='first', rawFile='first.html'),
                capture(second, id='second', rawFile='second.html')]}
            records, inventories = sources.normalize_manifest(manifest, root)
            self.assertEqual(len(records), 2)
            self.assertEqual(records[0]['alias'], records[1]['alias'])
            self.assertNotEqual(records[0]['id'], records[1]['id'])
            self.assertEqual(len(inventories), 2)

    def test_cli_retains_identical_outputs_and_refuses_different_existing_review(self):
        payload = bandai()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'page.html').write_bytes(payload)
            manifest = root/'captures.json'
            manifest.write_text(json.dumps({'schemaVersion': 1, 'captures': [capture(payload)]}))
            output = root/'output'
            command = [sys.executable, '-B', SPEC.origin, '--manifest', str(manifest),
                       '--capture-dir', str(root), '--output-dir', str(output)]
            first = subprocess.run(command, capture_output=True)
            self.assertEqual(first.returncode, 0, first.stderr.decode())
            records = output/'observations.json'
            original = records.read_bytes()
            mtime = records.stat().st_mtime_ns
            second = subprocess.run(command, capture_output=True)
            self.assertEqual(second.returncode, 0, second.stderr.decode())
            self.assertEqual(records.stat().st_mtime_ns, mtime)
            (output/'inventories.json').write_text('preserved conflicting review')
            failed = subprocess.run(command, capture_output=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertEqual(records.read_bytes(), original)
            self.assertEqual((output/'inventories.json').read_text(), 'preserved conflicting review')


if __name__ == '__main__':
    unittest.main()
