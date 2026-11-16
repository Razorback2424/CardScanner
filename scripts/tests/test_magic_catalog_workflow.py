"""Check the job-level Magic catalog publication boundary offline."""
import re
import unittest
from pathlib import Path


WORKFLOW = Path(__file__).resolve().parents[2] / '.github/workflows/magic-catalog.yml'


class MagicCatalogWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = WORKFLOW.read_text()
        cls.prepare = cls.text.split('  prepare-production:\n', 1)[1].split('  publish-production:\n', 1)[0]
        cls.publish = cls.text.split('  publish-production:\n', 1)[1]
        cls.condition = re.search(r'    if: >-\n((?:      .*\n)+)', cls.publish).group(1).strip()

    def eligible(self, event, publish, changes, approval, change_class):
        values = {
            'github.event_name': event,
            'inputs.publish': publish,
            'needs.prepare-production.outputs.has_changes': changes,
            'needs.prepare-production.outputs.requires_approval': approval,
            'needs.prepare-production.outputs.change_class': change_class,
        }
        expression = ' '.join(self.condition.split())
        expression = re.sub(r"(?<!')\btrue\b(?!')", 'True', expression)
        for name in sorted(values, key=len, reverse=True):
            expression = expression.replace(name, repr(values[name]))
        expression = expression.replace('&&', ' and ').replace('||', ' or ')
        self.assertRegex(expression, r"^[\s\w'()=]+$")
        return eval(expression, {'__builtins__': {}}, {})

    def test_scheduled_publication_requires_content_only_and_no_approval(self):
        for change_class in ('contentOnly', 'newSet', 'authority', 'unknown', 'none', ''):
            for changes in ('true', 'false', ''):
                for approval in ('true', 'false', ''):
                    with self.subTest(change_class=change_class, changes=changes, approval=approval):
                        self.assertEqual(
                            self.eligible('schedule', False, changes, approval, change_class),
                            change_class == 'contentOnly' and changes == 'true' and approval == 'false',
                        )

    def test_manual_publication_requires_explicit_request_and_changes(self):
        for change_class in ('contentOnly', 'newSet', 'authority', 'unknown'):
            self.assertTrue(self.eligible('workflow_dispatch', True, 'true', 'true', change_class))
            self.assertFalse(self.eligible('workflow_dispatch', False, 'true', 'true', change_class))
            self.assertFalse(self.eligible('workflow_dispatch', True, 'false', 'true', change_class))
            self.assertFalse(self.eligible('pull_request', True, 'true', 'false', change_class))

    def test_candidate_retention_and_publication_safeguards_remain(self):
        for expected in ('actions/upload-artifact@v4', 'Manual publication is required',
                         '::warning title=Magic catalog needs manual publication::',
                         'authority|newSet|unknown)', 'publish_environment="magic-catalog-production"'):
            self.assertIn(expected, self.prepare)
        for expected in ('group: scanstash-catalog-production-hosting', 'cancel-in-progress: false',
                         'name: ${{ needs.prepare-production.outputs.publish_environment }}',
                         'scripts/verify_magic_publication_environment.sh',
                         'candidate_manifest_sha256', 'shasum -a 256 -c',
                         'scripts/restore_catalog_hosting_site.sh', '--trusted-keys-file Config/MagicCatalogProduction.xcconfig'):
            self.assertIn(expected, self.publish)
        self.assertIn('test_magic_catalog_workflow.py', self.text)


if __name__ == '__main__':
    unittest.main()
