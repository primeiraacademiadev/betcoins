"""Prove financial fixture preparation cannot target a remote or ordinary local DB."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('financial_setup', Path(__file__).parent / 'browser/financial_setup.py')
fixture = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fixture)


class FinancialFixtureGuards(unittest.TestCase):
    def test_requires_explicit_disposable_ci_and_local_connection(self):
        base = {'CI': 'true', 'PGHOST': 'localhost', 'PGDATABASE': 'betcoins'}
        for changes in ({'CI': ''}, {'PGHOST': 'db.example.com'}, {'PGDATABASE': 'production'},
                        {'PGHOSTADDR': '203.0.113.1'}, {'PGSERVICE': 'production'},
                        {'PGOPTIONS': '-c role=admin'}):
            with self.subTest(changes=changes), patch.dict(fixture.os.environ, {**base, **changes}, clear=True):
                with patch.object(fixture, 'sql') as client:
                    with self.assertRaises(ValueError):
                        fixture.environment()
                    client.assert_not_called()

    def test_invalid_scenario_or_mode_is_rejected_before_reset(self):
        for scenario, mode in [('typo', 'snapshot_value'), ('trading', 'legacy')]:
            with self.subTest(scenario=scenario, mode=mode), patch.object(fixture, 'sql') as client:
                with self.assertRaises(ValueError):
                    fixture.seed(scenario, mode, {})
                client.assert_not_called()


if __name__ == '__main__':
    unittest.main()
