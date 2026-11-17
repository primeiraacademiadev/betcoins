"""Disposable localhost fixtures; no Supabase credentials or remote database access."""
import json
import os
from pathlib import Path
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/db'))
from recovery import local_environment, query, run

ACTORS = [str(uuid.UUID(f'eb000000-0000-4000-8000-00000000000{i}')) for i in range(1, 5)]
MODES = ('snapshot_value', 'snapshot_delta_previous')


def environment():
    if os.environ.get('CI') != 'true':
        raise ValueError('Financial fixtures require an explicitly disposable CI job')
    return local_environment(os.environ)


def sql(command, env):
    return query('betcoins', command, env)


def as_user(who, command, env):
    return sql(f"set role authenticated; select set_config('request.jwt.claim.sub','{who}',false); {command}", env).splitlines()[-1]


def initialize(env):
    run(['psql', '-X', '-v', 'ON_ERROR_STOP=1', '-f', str(ROOT / 'tests/db/bootstrap.sql')], env)
    for path in sorted((ROOT / 'supabase/migrations').glob('*.sql')):
        run(['psql', '-X', '-v', 'ON_ERROR_STOP=1', '-f', str(path)], env)
    # Supabase auth.uid() reads PostgREST's signed JWT claims. Keep the historical
    # per-session setting too, for fixture setup through authenticated SQL RPCs.
    sql("""create or replace function auth.uid() returns uuid language sql stable as $$
      select coalesce(nullif(current_setting('request.jwt.claim.sub',true),''),
        nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid $$;""", env)
    password = os.environ['FINANCIAL_DB_PASSWORD']
    sql(f"create role browser_gateway login noinherit password '{password}'; grant anon,authenticated to browser_gateway;", env)


def seed(scenario, mode, env):
    if scenario not in ('trading', 'uncertain', 'settlement') or mode not in MODES:
        raise ValueError('Unknown financial fixture')
    # Data-only reset in this job's disposable database; no schema changes and
    # no test control endpoint is exposed to the application or browser.
    sql("""do $$declare tables text;begin
      select string_agg(format('%I.%I',schemaname,tablename),',') into tables
      from pg_tables where schemaname in ('public','auth') and tablename<>'bet_calendar_sessions';
      execute 'truncate table '||tables||' restart identity cascade';end $$;""", env)
    a, b, c, _ = ACTORS
    for who, nickname in zip(ACTORS, ('Ana', 'Bruno', 'Carla', 'Duarte')):
        sql(f"insert into auth.users(id) values('{who}');", env)
        as_user(who, f"select public.update_nickname('{nickname}');", env)
    sql(f"insert into public.admins values('{a}'); insert into public.competitors(id) values('{a}'),('{b}'),('{c}');", env)
    result = {'actors': ACTORS, 'mode': mode}
    groups = ('ready', 'tie') if scenario == 'settlement' else ('trading',)
    for group in groups:
        duration = '12 seconds' if scenario == 'settlement' else '1 day'
        champ = sql(f"insert into public.championships(name,starts_at,ends_at) values('Browser financial',clock_timestamp()-interval '1 day',clock_timestamp()+interval '{duration}') returning id", env)
        for who, score in zip(ACTORS[:3], (12, 15, 0)):
            as_user(who, f"select public.declare_initial_ytd('{champ}',{score});", env)
        as_user(a, f"select public.configure_recurring_bet('{champ}','annual','{mode}',true);", env)
        sql(f"update public.markets set title='Browser {group} '||category where championship_id='{champ}'", env)
        # Use winner explicitly, independent of UPDATE result ordering.
        market = json.loads(sql(f"select jsonb_build_object('id',id,'title',title,'definition',definition_id,'occurrence',occurrence_id) from public.markets where championship_id='{champ}' and category='winner'", env))
        market['outcome'] = sql(f"select id from public.outcomes where market_id='{market['id']}' and competitor_id='{a}'", env)
        result[group] = market
        if scenario == 'settlement':
            offer = as_user(a, f"select public.place_offer('{market['outcome']}','back',2,10);", env)
            as_user(b, f"select public.accept_offer('{offer}',10);", env)
            # Real short calendar, real server cutoff: no clock mocking, trigger
            # disabling, timestamp rewrites or fabricated frozen classifications.
            deadline = time.monotonic() + 20
            while sql(f"select (clock_timestamp()>=ends_at)::text from public.championships where id='{champ}'", env) != 'true':
                if time.monotonic() > deadline:
                    raise RuntimeError('Financial fixture did not reach its cutoff')
                time.sleep(.1)
            round_id = as_user(a, f"select x->>'id' from jsonb_array_elements(public.get_my_final_declarations()) x where x->>'championship_id'='{champ}';", env)
            finals = (16, 18, 3) if group == 'ready' else ((20, 20, 3) if mode == 'snapshot_value' else (20, 23, 3))
            for who, score in zip(ACTORS[:3], finals):
                as_user(who, f"select public.declare_final_score('{round_id}',{score});", env)
            as_user(a, f"select public.finalize_final_round('{round_id}','Fecho preparado para validar e liquidar no navegador');", env)
    return result


def main():
    env = environment()
    if sys.argv[1:] == ['init']:
        initialize(env)
    elif len(sys.argv) == 4 and sys.argv[1] == 'seed':
        print(json.dumps(seed(sys.argv[2], sys.argv[3], env)))
    else:
        raise ValueError('Expected init or seed SCENARIO MODE')


if __name__ == '__main__':
    main()
