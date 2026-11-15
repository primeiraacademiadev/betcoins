"""Real PostgreSQL sessions; CI disposable DB only, never a Supabase URL."""
import concurrent.futures
import os
import subprocess
import time

if os.environ.get('PGHOST') not in ('localhost', '127.0.0.1'):
    raise RuntimeError('Concurrency fixtures require the local CI PostgreSQL service')


def sql(command, app='e2-test', check=True):
    result = subprocess.run(['psql', '-X', '-At', '-v', 'ON_ERROR_STOP=1', '-c', command],
                            env={**os.environ, 'PGAPPNAME': app}, capture_output=True, text=True, timeout=30)
    if check and result.returncode:
        raise AssertionError(result.stderr)
    return result


def as_user(user, command):
    return f"set role authenticated; select set_config('request.jwt.claim.sub','{user}',false); {command}"


def race(commands, lock=941001):
    # Hold the same advisory lock as the RPC until BOTH contenders are waiting.
    holder = subprocess.Popen(['psql', '-X', '-At', '-v', 'ON_ERROR_STOP=1'],
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        holder.stdin.write(f'begin; select pg_advisory_xact_lock({lock});\n\\echo LOCKED\n')
        holder.stdin.flush()
        while holder.stdout.readline().strip() != 'LOCKED':
            if holder.poll() is not None:
                raise AssertionError('Lock holder exited')
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(sql, command, f'e2-racer-{i}', False) for i, command in enumerate(commands)]
            deadline = time.monotonic() + 10
            while True:
                waiting = sql("select count(*) from pg_stat_activity where application_name like 'e2-racer-%' and wait_event='advisory'").stdout.strip()
                if waiting == '2':
                    break
                if time.monotonic() > deadline:
                    raise AssertionError('Both sessions did not contend on the lock')
                time.sleep(.05)
            holder.stdin.write('commit;\n\\q\n')
            holder.stdin.flush()
            return [f.result(timeout=20) for f in futures]
    finally:
        if holder.poll() is None:
            holder.kill()
        holder.wait(timeout=5)


admin = 'd0000000-0000-4000-8000-000000000001'
candidate = 'd0000000-0000-4000-8000-000000000002'
sprint = 'd0000000-0000-4000-8000-000000000003'
champ = sql('select id from public.championships limit 1').stdout.strip()
sql(f"""
insert into auth.users(id) values('{admin}'),('{candidate}');
insert into public.admins(id) values('{admin}');
insert into public.competitors(id,joined_at) values('{admin}',clock_timestamp()-interval '1 day');
insert into public.score_history(competitor_id,ytd,created_at) values('{admin}',12,clock_timestamp()-interval '2 hours');
""")
sql(as_user(candidate, 'select public.apply_competitor();'))
application = sql(f"select id from public.applications where candidate_id='{candidate}'").stdout.strip()
vote = as_user(admin, f"select public.vote_application('{application}',true);")
results = race([vote, vote])
assert sum(r.returncode == 0 for r in results) == 1, results
assert sql(f"select count(*) from public.votes where application_id='{application}'").stdout.strip() == '1'
# The smoke fixture has two original voters; the next yes decides a 3-person electorate.
commands = [as_user(user, f"select public.vote_application('{application}',true);") for user in
            ['11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222']]
results = race(commands)
assert sum(r.returncode == 0 for r in results) == 1
assert sql(f"select state||':'||(select count(*) from public.votes where application_id='{application}') from public.applications where id='{application}'").stdout.strip() == 'approved:2'
assert sql(f"select count(*) from public.competitors where id='{candidate}' and ytd is null").stdout.strip() == '1'

sql(f"insert into public.sprints(id,championship_id,name,kind,starts_at,ends_at) values('{sprint}','{champ}','Concurrent E2','weekly',clock_timestamp()-interval '1 hour',clock_timestamp()-interval '1 minute')")
for phase in ['start', 'end']:
    capture = as_user(admin, f"select public.capture_sprint('{sprint}','{phase}');")
    assert all(r.returncode == 0 for r in race([capture, capture]))
assert sql(f"select count(*) from public.competition_captures where sprint_id='{sprint}'").stdout.strip() == '2'
validate = as_user(admin, f"select public.validate_competition('{champ}','{sprint}','Revisão concorrente dos dados congelados');")
results = race([validate, validate])
assert all(r.returncode == 0 for r in results)
assert results[0].stdout.splitlines()[-1] == results[1].stdout.splitlines()[-1]
assert sql(f"select count(*) from public.competition_validations where sprint_id='{sprint}'").stdout.strip() == '1'

# Start a score transaction BEFORE a boundary, keep it waiting until AFTER it.
late_sprint = 'd0000000-0000-4000-8000-000000000004'
sql(f"insert into public.sprints(id,championship_id,name,kind,starts_at,ends_at) values('{late_sprint}','{champ}','Boundary race E2','monthly',clock_timestamp()-interval '1 hour',clock_timestamp()+interval '5 seconds')")
sql(as_user(admin, f"select public.capture_sprint('{late_sprint}','start');"))
holder = subprocess.Popen(['psql', '-X', '-At', '-v', 'ON_ERROR_STOP=1'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
try:
    holder.stdin.write('begin; select pg_advisory_xact_lock(941002);\n\\echo LOCKED\n')
    holder.stdin.flush()
    while holder.stdout.readline().strip() != 'LOCKED':
        pass
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        future = pool.submit(sql, as_user(admin, 'begin; select public.set_my_score(99); commit;'), 'e2-late-score')
        deadline = time.monotonic()+10
        while sql("select count(*) from pg_stat_activity where application_name='e2-late-score' and wait_event='advisory'").stdout.strip() != '1':
            if time.monotonic()>deadline:
                raise AssertionError('Score did not wait')
            time.sleep(.05)
        assert sql(f"select xact_start<(select ends_at from public.sprints where id='{late_sprint}') from pg_stat_activity where application_name='e2-late-score'").stdout.strip() == 't'
        holder.stdin.write(f"select pg_sleep(greatest(0,extract(epoch from (select ends_at from public.sprints where id='{late_sprint}')-clock_timestamp())+.1)); commit;\n\\q\n")
        holder.stdin.flush()
        future.result(timeout=20)
finally:
    holder.wait(timeout=10)
sql(as_user(admin, f"select public.capture_sprint('{late_sprint}','end');"))
assert sql(f"select end_ytd from public.get_sprint_rankings('{late_sprint}') where competitor_id='{admin}'").stdout.strip() == '12.0000'
assert sql(f"select updated_at>(select ends_at from public.sprints where id='{late_sprint}') from public.competitors where id='{admin}'").stdout.strip() == 't'
print('E2 concurrent votes, capture, validation and boundary timestamps: PASS')
