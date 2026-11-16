"""Offline checks for the local One Piece publication safeguards."""
import io
import re
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import publish_one_piece_local as local  # noqa: E402

DIGEST = 'a' * 64
WORKFLOW = Path(__file__).resolve().parents[2] / '.github/workflows'


class ArgumentTests(unittest.TestCase):
    def parse(self, *extra):
        base = ['--reviewed-sha256', DIGEST, '--envelope-sha256', DIGEST, '--manifest-sha256', DIGEST,
                '--work-dir', '/tmp/x']
        return local.parse_args(base + list(extra))

    def rejected(self, *argv):
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            local.parse_args(list(argv))

    def test_requires_exactly_one_artifact_source(self):
        self.rejected('--reviewed-sha256', DIGEST, '--envelope-sha256', DIGEST, '--manifest-sha256', DIGEST,
                      '--work-dir', '/tmp/x')
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            self.parse('--signed-run-id', '1', '--artifact-dir', '/tmp/a')
        self.assertEqual(self.parse('--signed-run-id', '43913438883').signed_run_id, '43913438883')

    def test_rejects_malformed_digests_and_run_ids(self):
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            self.parse('--signed-run-id', '12a')
        self.rejected('--signed-run-id', '1', '--reviewed-sha256', 'A' * 64, '--envelope-sha256', DIGEST,
                      '--manifest-sha256', DIGEST, '--work-dir', '/tmp/x')
        self.rejected('--signed-run-id', '1', '--reviewed-sha256', DIGEST, '--envelope-sha256', 'a' * 63,
                      '--manifest-sha256', DIGEST, '--work-dir', '/tmp/x')

    def test_deploy_requires_confirmation_unless_requested(self):
        self.assertFalse(self.parse('--signed-run-id', '1').yes)


class SafeguardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.site = Path(self.tmp.name)
        self.write('v1/current.json', b'pokemon')
        self.write('market-prices/v1/index.json', b'prices')
        self.write('one-piece/v1/current.json', b'rev6')
        self.write('one-piece/v1/releases/6/catalog-release.json', b'rev6')

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, relative, data):
        path = self.site / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def test_preservation_accepts_identical_live_namespaces(self):
        live = {'v1/current.json': b'pokemon', 'market-prices/v1/index.json': b'prices'}
        self.assertEqual(local.preservation_problems(self.site, live.get), [])

    def test_preservation_rejects_missing_or_changed_live_namespaces(self):
        live = {'v1/current.json': b'pokemon-newer', 'market-prices/v1/index.json': b'prices',
                'yugioh/v1/current.json': b'yugioh'}
        problems = local.preservation_problems(self.site, live.get)
        self.assertEqual(len(problems), 2)
        self.assertTrue(any('v1/current.json differs' in p for p in problems))
        self.assertTrue(any('yugioh/v1/current.json is live but missing' in p for p in problems))

    def readback(self, responses):
        def fetch(url):
            return responses(re.sub(r'\?.*', '', url))
        with redirect_stdout(io.StringIO()):
            return local.readback_problems(self.site, '6', fetch)

    def test_readback_accepts_matching_bytes_and_cache_headers(self):
        def responses(url):
            relative = url.split('/', 3)[3]
            cache = {'one-piece/v1/current.json': 'no-cache',
                     'one-piece/v1/releases/6/catalog-release.json': 'public, max-age=31536000, immutable'}
            return (self.site / relative).read_bytes(), {'cache-control': cache.get(relative, 'max-age=60')}
        self.assertEqual(self.readback(responses), [])

    def test_readback_reports_stale_bytes_and_wrong_cache_headers_on_each_origin(self):
        def responses(url):
            relative = url.split('/', 3)[3]
            if relative == 'one-piece/v1/current.json':
                return b'rev5', {'cache-control': 'no-cache'}
            return (self.site / relative).read_bytes(), {'cache-control': 'max-age=60'}
        problems = self.readback(responses)
        self.assertEqual(len(problems), 4)
        for origin in local.ORIGINS:
            self.assertIn(f'{origin}/one-piece/v1/current.json bytes differ', problems)
            self.assertIn(f'{origin}/one-piece/v1/releases/6/catalog-release.json is not cached as immutable',
                          problems)

    def test_busy_runs_ignore_pull_requests_and_finished_runs(self):
        runs = [{'event': 'pull_request', 'status': 'in_progress'},
                {'event': 'schedule', 'status': 'completed'},
                {'event': 'schedule', 'status': 'queued'},
                {'event': 'workflow_dispatch', 'status': 'waiting'}]
        self.assertEqual(local.busy_github_runs(runs), runs[2:])

    def test_run_check_covers_every_workflow_that_deploys_the_shared_site(self):
        deploying = {path.name for path in WORKFLOW.glob('*.yml')
                     if 'scanstash-catalog-production-hosting' in path.read_text()}
        self.assertEqual(deploying, set(local.SHARED_SITE_WORKFLOWS))


if __name__ == '__main__':
    unittest.main()
