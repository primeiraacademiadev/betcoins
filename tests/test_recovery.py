"""Connection guards: verify rejection happens before any PostgreSQL client runs."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('recovery', Path(__file__).parent / 'db/recovery.py')
recovery = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(recovery)


class RecoveryGuards(unittest.TestCase):
    def test_remote_implicit_and_connection_string_targets_are_rejected(self):
        for host, database in [('db.example.com', 'betcoins'), ('', 'betcoins'),
                               ('localhost', 'postgresql://remote/prod'), ('localhost', 'production')]:
            with self.subTest(host=host, database=database), patch.object(recovery.subprocess, 'run') as client:
                with patch.dict(recovery.os.environ, {'PGHOST': host, 'PGDATABASE': database}, clear=True):
                    with self.assertRaises(ValueError):
                        recovery.main()
                client.assert_not_called()

    def test_libpq_redirects_and_invalid_ports_are_rejected(self):
        for key, value in [('PGHOSTADDR', '203.0.113.1'), ('PGSERVICE', 'production'),
                           ('PGSERVICEFILE', '/secrets/services'), ('PGOPTIONS', '-c role=admin'),
                           ('PGPORT', 'host=remote'), ('PGPORT', '0'), ('PGPORT', '65536')]:
            with self.subTest(key=key, value=value):
                with self.assertRaises(ValueError):
                    recovery.local_environment({'PGHOST': 'localhost', 'PGDATABASE': 'betcoins', key: value})

    def test_local_settings_strip_other_pg_defaults(self):
        env = recovery.local_environment({'PGHOST': '127.0.0.1', 'PGDATABASE': 'betcoins',
                                           'PGUSER': 'unexpected', 'PGSSLMODE': 'require', 'PATH': 'clients'})
        self.assertEqual(env['PGUSER'], 'postgres')
        self.assertEqual(env['PATH'], 'clients')
        self.assertNotIn('PGSSLMODE', env)

    def test_existing_destination_stops_before_dump_or_create(self):
        with patch.dict(recovery.os.environ, {'PGHOST': 'localhost', 'PGDATABASE': 'betcoins'}, clear=True):
            with patch.object(recovery, 'query', return_value='1'), patch.object(recovery, 'run') as client:
                with self.assertRaisesRegex(RuntimeError, 'already exists'):
                    recovery.main()
                client.assert_not_called()

    def test_failed_client_does_not_log_private_output(self):
        failure = type('Result', (), {'returncode': 1, 'stdout': 'private rows', 'stderr': 'secret password'})()
        with patch.object(recovery.subprocess, 'run', return_value=failure):
            with self.assertRaisesRegex(RuntimeError, r'^psql failed \(exit 1\); rehearsal stopped$'):
                recovery.run(['psql'], {})


if __name__ == '__main__':
    unittest.main()
