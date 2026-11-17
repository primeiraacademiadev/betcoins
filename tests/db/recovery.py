"""Backup/restore rehearsal for the disposable CI cluster, never for Supabase."""
import difflib
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = 'betcoins'
TARGET = 'betcoins_recovery'


def local_environment(environ):
    if environ.get('PGHOST') not in ('localhost', '127.0.0.1'):
        raise ValueError('Recovery rehearsal requires explicit localhost PGHOST')
    if environ.get('PGDATABASE') != SOURCE:
        raise ValueError('Recovery rehearsal requires the disposable betcoins database')
    for name in ('PGHOSTADDR', 'PGSERVICE', 'PGSERVICEFILE', 'PGOPTIONS'):
        if environ.get(name):
            raise ValueError('Alternate PostgreSQL connection settings are forbidden')
    port = environ.get('PGPORT', '5432')
    if not port.isdecimal() or not 1 <= int(port) <= 65535:
        raise ValueError('Invalid local PostgreSQL port')
    # Do not inherit libpq defaults capable of redirecting connections.
    result = {k: v for k, v in environ.items() if not k.startswith('PG')}
    result.update(PGHOST=environ['PGHOST'], PGPORT=port,
                  PGUSER='postgres', PGDATABASE=SOURCE, PGCONNECT_TIMEOUT='5',
                  PGPASSWORD=environ.get('PGPASSWORD', ''))
    return result


def run(args, env):
    result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=120)
    if result.returncode:
        # Logs must not contain SQL rows, connection strings or credentials.
        raise RuntimeError(f'{args[0]} failed (exit {result.returncode}); rehearsal stopped')
    return result.stdout


def query(database, command, env):
    return run(['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-d', database,
                '-c', command], env).strip()


def check_versions(env):
    server_major = int(query(SOURCE, 'show server_version_num', env)) // 10000
    for client in ('pg_dump', 'pg_restore'):
        version = run([client, '--version'], env)
        match = re.search(r'\(PostgreSQL\) (\d+)\.', version)
        if not match or int(match.group(1)) != server_major:
            raise RuntimeError(f'{client} must match PostgreSQL server major {server_major}')


def normalize_schema(schema):
    # Recent pg_dump versions generate a new psql restriction key per export.
    schema = re.sub(r'^\\(?:un)?restrict .*\n?', '', schema, flags=re.M)
    # PostgreSQL 16.16 assigns internal attribute versions independently on
    # restore. Older 16.x clients emit them as ignored ALTER COLUMN options.
    # Preserve the statement/object identity, replacing only that internal value.
    schema = re.sub(r'^(ALTER TABLE ONLY .+ ALTER COLUMN .+ SET \(pg_attver=)\d+(\);)$',
                    r'\g<1>INTERNAL\2', schema, flags=re.M)
    return schema


def schema_snapshot(database, env):
    return normalize_schema(run(['pg_dump', '--schema-only', '--no-owner', '-d', database], env))


def contents(database, env):
    tables = query(database, """select format('%I.%I',schemaname,tablename)
      from pg_tables where schemaname in ('public','auth') order by 1""", env).splitlines()
    result = {}
    for table in tables:
        # Canonical row ordering preserves duplicate rows and ignores physical order.
        result[table] = query(database, f"""select count(*)||':'||md5(coalesce(
          string_agg(row_text,E'\\n' order by row_text collate "C"),''))
          from (select to_jsonb(t)::text row_text from {table} t) rows""", env)
    return result


def main():
    env = local_environment(os.environ)
    if query('postgres', f"select count(*) from pg_database where datname='{TARGET}'", env) != '0':
        raise RuntimeError('Recovery target already exists; no database was overwritten')
    check_versions(env)
    before_schema = schema_snapshot(SOURCE, env)
    before_rows = contents(SOURCE, env)
    if not before_rows or not query(SOURCE, 'select count(*) from public.trades', env).isdigit():
        raise RuntimeError('Missing application fixtures')
    if query(SOURCE, 'select count(*) from public.trades', env) == '0':
        raise RuntimeError('Recovery requires populated trading fixtures')
    with tempfile.TemporaryDirectory(prefix='betcoins-recovery-') as directory:
        archive = str(Path(directory) / 'database.dump')
        run(['pg_dump', '--format=custom', '--no-owner', '-d', SOURCE, '-f', archive], env)
        run(['createdb', '--template=template0', TARGET], env)
        # Restore ACLs, policies, triggers and functions as well as all data.
        run(['pg_restore', '--exit-on-error', '--single-transaction', '--no-owner',
             '-d', TARGET, archive], env)
    after_schema = schema_snapshot(TARGET, env)
    after_rows = contents(TARGET, env)
    if before_schema != after_schema:
        # Schema definitions are repository code; never print table row contents.
        print(''.join(list(difflib.unified_diff(before_schema.splitlines(True),
                                              after_schema.splitlines(True)))[:100]), flush=True)
        raise RuntimeError('Restored schema differs from the original')
    if before_rows != after_rows:
        changed = sorted(k for k in before_rows.keys() | after_rows.keys()
                         if before_rows.get(k) != after_rows.get(k))
        raise RuntimeError('Restored table contents differ: ' + ', '.join(changed))
    run(['psql', '-X', '-q', '-v', 'ON_ERROR_STOP=1', '-d', TARGET,
         '-f', str(ROOT / 'tests/db/recovery_checks.sql')], env)
    # Re-run the real current-model authorization/market acceptance on the copy.
    run(['psql', '-X', '-q', '-v', 'ON_ERROR_STOP=1', '-d', TARGET,
         '-f', str(ROOT / 'tests/db/issue_11_acceptance.sql')], env)
    if before_rows != contents(TARGET, env) or before_rows != contents(SOURCE, env):
        raise RuntimeError('Read-only recovery checks changed application data')
    print(f'Recovery PASS: {len(before_rows)} tables identical; schema/ACL/RLS, ledger, '
          'reserves, immutable results and current-model acceptance verified')


if __name__ == '__main__':
    main()
