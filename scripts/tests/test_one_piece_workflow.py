"""Protect scheduling and verification boundaries in the release workflow."""
import re
import unittest
from pathlib import Path


WORKFLOW = Path(__file__).resolve().parents[2] / '.github/workflows/one-piece-catalog.yml'


def job(text, name):
    match = re.search(rf'^  {re.escape(name)}:\n(.*?)(?=^  [a-z][a-z0-9-]*:\n|\Z)', text, re.M | re.S)
    if not match:
        raise AssertionError(f'Missing workflow job: {name}')
    return match.group(1)


class OnePieceWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = WORKFLOW.read_text()

    def test_portable_checks_and_cryptographic_tests_run_separately(self):
        portable = job(self.text, 'validate')
        core = job(self.text, 'validate-catalog-core')
        self.assertIn('runs-on: ubuntu-latest', portable)
        self.assertIn('Reject a combined sign and publish request', portable)
        for check in ('test_catalog_hosting_restore.py', 'test_one_piece_hosting.py',
                      'test_one_piece_tcgcsv_catalog.py', 'test_one_piece_retail_printings.py',
                      'test_one_piece_base_market_mappings.py', 'test_one_piece_pinned_keys.py'):
            self.assertIn(check, portable)
        self.assertNotIn('swift test --package-path OnePieceCatalogCore', portable)
        self.assertIn('runs-on: ubuntu-24.04', core)
        self.assertIn('swift test --package-path OnePieceCatalogCore', core)
        for name in ('sign-reviewed-artifact', 'publish-reviewed-artifact'):
            self.assertIn('needs: [validate, validate-catalog-core]', job(self.text, name))

    def test_signing_and_publication_retain_protected_verification(self):
        signing = job(self.text, 'sign-reviewed-artifact')
        publishing = job(self.text, 'publish-reviewed-artifact')
        r2_publish = job(self.text, 'publish-r2-catalog')
        backup = job(self.text, 'backup-firebase-catalog')
        self.assertIn('runs-on: ubuntu-24.04', signing)
        self.assertIn('runs-on: ubuntu-24.04', publishing)
        self.assertIn('runs-on: ubuntu-latest', r2_publish)
        self.assertIn('runs-on: macos-15', backup)
        for content, environment in ((signing, 'one-piece-catalog-signing'),
                                     (publishing, 'one-piece-catalog-production')):
            self.assertIn(f'environment: {environment}', content)
            self.assertIn("github.ref == 'refs/heads/main'", content)
            self.assertIn('python3 scripts/one_piece_pinned_keys.py', content)
            self.assertIn('--reviewed-payload-sha256', content)
            self.assertIn('one-piece-catalog-publisher verify', content)
        self.assertIn('one-piece-catalog-publisher sign', signing)
        self.assertLess(signing.index('catalog_release_preflight.py --game one-piece --payload'),
                        signing.index('one-piece-catalog-publisher sign'))
        self.assertIn('catalog_release_preflight.py --game one-piece --envelope', signing)
        self.assertIn('cmp "$artifact_root/manifest.json" "$artifact_root/verified-manifest.json"', signing)
        self.assertIn('cmp "$RUNNER_TEMP/one-piece-verified-manifest.json" "$artifact/verified-manifest.json"', publishing)
        self.assertIn('--write-catalog-metadata', publishing)
        self.assertNotIn('FIREBASE_', publishing)
        self.assertNotIn('web.app', publishing)
        self.assertIn('environment: r2-catalog-production', r2_publish)
        self.assertIn('group: scanstash-catalog-r2-hosting', r2_publish)
        self.assertIn('cancel-in-progress: false', r2_publish)
        self.assertIn('--primary-catalog one-piece/v1', r2_publish)
        self.assertNotIn('FIREBASE_', r2_publish)
        self.assertIn('needs: [publish-reviewed-artifact, publish-r2-catalog]', backup)
        self.assertIn('group: scanstash-catalog-production-hosting', backup)
        self.assertIn('cancel-in-progress: false', backup)
        self.assertIn('scripts/restore_catalog_hosting_site.sh', backup)
        self.assertIn('Verify live catalog bytes and cache headers', backup)
        self.assertIn('The verified R2 catalog publication remains active.', backup)


if __name__ == '__main__':
    unittest.main()
