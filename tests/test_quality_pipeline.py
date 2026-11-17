"""Packaging/security invariants, with no database or network access."""
import copy
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('bundles', ROOT / 'scripts/build_sql_bundles.py')
bundles = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundles)


class SqlExports(unittest.TestCase):
    def test_frozen_exports_are_exact_and_deterministic(self):
        expected = {'baseline': 'aef57446fe29d3d4ce34581b37235c65f122e0b88945c1141a07496b6a09d36c',
                    'upgrade': '483582618fa535e97ca1293e09e96d59e7cc12e1ad6a39a34eb37c4a1633946f'}
        for name in expected:
            with self.subTest(name=name):
                relative, sql = bundles.render(name)
                manifest = json.loads((ROOT / 'supabase/bundles.json').read_text())
                self.assertEqual(bundles.digest(sql), expected[name])
                self.assertEqual(bundles.digest(sql), manifest[name]['sha256'])
                self.assertEqual((relative, sql), bundles.render(name))
                self.assertNotIn('{{source:', sql)

    def test_atomic_upgrade_keeps_one_transaction_and_guards(self):
        sql = bundles.render('upgrade')[1]
        self.assertEqual(len(re.findall(r'^BEGIN;$', sql, re.M)), 1)
        self.assertEqual(len(re.findall(r'^COMMIT;$', sql, re.M)), 1)
        self.assertLess(sql.index('$preflight$;'), sql.index('-- >>> MIGRATION 3'))
        self.assertGreater(sql.index('DO $postflight$'), sql.index('-- <<< END MIGRATION 8'))
        self.assertIn("round(b.ytd-a.ytd,4)", sql)

    def test_changed_source_order_or_body_fails_closed(self):
        base = {'template': 'supabase/template.tmpl', 'output': 'supabase/out.sql',
                'sha256': bundles.digest('select 1;'),
                'sources': [{'path': 'supabase/migrations/a.sql', 'sha256': bundles.digest('select 1;')}]}
        for mutation in ('body', 'order', 'traversal', 'output'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / 'supabase/migrations').mkdir(parents=True)
                (root / 'supabase/migrations/a.sql').write_text('select 1;')
                (root / 'supabase/template.tmpl').write_text('{{source:a.sql}}')
                item = copy.deepcopy(base)
                if mutation == 'body':
                    (root / 'supabase/migrations/a.sql').write_text('drop table wallets;')
                elif mutation == 'order':
                    (root / 'supabase/template.tmpl').write_text('{{source:b.sql}}')
                elif mutation == 'traversal':
                    item['sources'][0]['path'] = '../outside.sql'
                else:
                    item['output'] = '../outside.sql'
                (root / 'supabase/bundles.json').write_text(json.dumps({'baseline': item}))
                with self.assertRaises(ValueError):
                    bundles.build('baseline', root)


class AnalysisAndInstall(unittest.TestCase):
    def test_workflow_installs_are_locked_and_do_not_run_lifecycle_scripts(self):
        lock = json.loads((ROOT / 'package-lock.json').read_text(encoding='utf-8'))
        package = json.loads((ROOT / 'package.json').read_text(encoding='utf-8'))
        for group in ('dependencies', 'devDependencies'):
            self.assertEqual(package[group], lock['packages'][''][group])
        count = 0
        for path in (ROOT / '.github/workflows').glob('*.yml'):
            for command in re.findall(r'^\s+(?:-\s+)?run:\s*(.+)$', path.read_text(encoding='utf-8'), re.M):
                if re.match(r'npm (?:install|ci)\b', command):
                    self.assertTrue(command.startswith('npm ci '), path.name)
                    self.assertIn('--ignore-scripts', command, path.name)
                    count += 1
                self.assertNotRegex(command, r'\bnpx\b')
        self.assertGreaterEqual(count, 4)

    def test_only_immutable_migrations_are_exempt_from_copy_detection(self):
        properties = {}
        for line in (ROOT / '.sonarcloud.properties').read_text(encoding='utf-8').splitlines():
            if line.strip() and not line.startswith('#'):
                key, value = line.split('=', 1)
                properties[key] = value
        self.assertEqual(set(properties), {'sonar.cpd.exclusions'})
        paths = properties['sonar.cpd.exclusions'].split(',')
        self.assertEqual(len(paths), len(set(paths)))
        for path in paths:
            self.assertNotIn('*', path)
            self.assertEqual((ROOT / path).parent, ROOT / 'supabase/migrations')
            self.assertTrue((ROOT / path).is_file())
        self.assertNotIn('src/', ','.join(paths))


if __name__ == '__main__':
    unittest.main()
