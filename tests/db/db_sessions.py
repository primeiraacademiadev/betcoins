"""Shared real PostgreSQL sessions for disposable localhost CI databases."""
import concurrent.futures
import os
import subprocess
import time

if os.environ.get('PGHOST') not in ('localhost', '127.0.0.1'):
    raise RuntimeError('E4 concurrency tests require a disposable local database')


def sql(command, app='db-test', check=True):
    result = subprocess.run(['psql', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-c', command],
                            env={**os.environ, 'PGAPPNAME': app}, capture_output=True, text=True, timeout=30)
    if check and result.returncode:
        raise AssertionError(result.stderr)
    return result


def value(command):
    return sql(command).stdout.strip().splitlines()[-1]


def user(who, command):
    return f"set role authenticated; select set_config('request.jwt.claim.sub','{who}',false); {command}"


def race(commands, cross_cutoff=None, lock=941003, hold_sql=None):
    holder = subprocess.Popen(['psql', '-X', '-At', '-v', 'ON_ERROR_STOP=1'],
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        wait_condition = "wait_event_type='Lock'" if hold_sql else "wait_event='advisory'"
        hold_sql = hold_sql or f'select pg_advisory_xact_lock({lock});'
        holder.stdin.write(f'begin; {hold_sql}\n\\echo LOCKED\n')
        holder.stdin.flush()
        while holder.stdout.readline().strip() != 'LOCKED':
            if holder.poll() is not None:
                raise AssertionError('Lock holder exited')
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(commands)) as pool:
            futures = [pool.submit(sql, command, f'db-racer-{i}', False) for i, command in enumerate(commands)]
            deadline = time.monotonic() + 10
            while value(f"select count(*) from pg_stat_activity where application_name like 'db-racer-%' and {wait_condition}") != str(len(commands)):
                if time.monotonic() > deadline:
                    raise AssertionError('Contenders did not all reach the trading mutex')
                time.sleep(.05)
            if cross_cutoff:
                while value(f"select (clock_timestamp()>=closes_at)::text from public.markets where id='{cross_cutoff}'") != 'true':
                    if time.monotonic() > deadline:
                        raise AssertionError('Cutoff was not crossed')
                    time.sleep(.05)
            holder.stdin.write('commit;\n\\q\n')
            holder.stdin.flush()
            return [f.result(timeout=20) for f in futures]
    finally:
        if holder.poll() is None:
            holder.kill()
        holder.wait(timeout=5)


