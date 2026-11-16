"""E4 real-session races. Only the disposable localhost PostgreSQL CI service."""
import concurrent.futures
import os
import subprocess
import time

if os.environ.get('PGHOST') not in ('localhost', '127.0.0.1'):
    raise RuntimeError('E4 concurrency tests require a disposable local database')


def sql(command, app='e4-test', check=True):
    result = subprocess.run(['psql', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-c', command],
                            env={**os.environ, 'PGAPPNAME': app}, capture_output=True, text=True, timeout=30)
    if check and result.returncode:
        raise AssertionError(result.stderr)
    return result


def value(command):
    return sql(command).stdout.strip().splitlines()[-1]


def user(who, command):
    return f"set role authenticated; select set_config('request.jwt.claim.sub','{who}',false); {command}"


def race(commands, cross_cutoff=None):
    holder = subprocess.Popen(['psql', '-X', '-At', '-v', 'ON_ERROR_STOP=1'],
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        holder.stdin.write('begin; select pg_advisory_xact_lock(941003);\n\\echo LOCKED\n')
        holder.stdin.flush()
        while holder.stdout.readline().strip() != 'LOCKED':
            if holder.poll() is not None:
                raise AssertionError('Lock holder exited')
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(commands)) as pool:
            futures = [pool.submit(sql, command, f'e4-racer-{i}', False) for i, command in enumerate(commands)]
            deadline = time.monotonic() + 10
            while value("select count(*) from pg_stat_activity where application_name like 'e4-racer-%' and wait_event='advisory'") != str(len(commands)):
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


admin, back, lay, buyer = [f'f0000000-0000-4000-8000-00000000000{i}' for i in range(1, 5)]
sql(f"insert into auth.users(id) values('{admin}'),('{back}'),('{lay}'),('{buyer}'); insert into public.admins(id) values('{admin}'); insert into public.competitors(id) values('{admin}'),('{back}');")


def market():
    # A precise, validated two-participant E2 fixture, independent of E2 tests.
    champ = value("insert into public.championships(name,starts_at,ends_at) values('E4 race',clock_timestamp()-interval '1 day',clock_timestamp()+interval '1 day') returning id")
    m = value(f"insert into public.markets(title,kind,category,closes_at,championship_id) values('E4 race','annual','winner',clock_timestamp()+interval '1 hour','{champ}') returning id")
    sql(f"insert into public.outcomes(market_id,competitor_id,label) values('{m}','{admin}','A'),('{m}','{back}','B')")
    return m, value(f"select id from public.outcomes where market_id='{m}' and competitor_id='{admin}'")


def offer(outcome, amount=10):
    return value(user(back, f"select public.place_offer('{outcome}','back',2,{amount});"))


def close_validate(m):
    sql(f"""
    update public.markets set closes_at=clock_timestamp()-interval '1 second' where id='{m}';
    insert into public.competition_captures(championship_id,phase,cutoff_at,captured_by)
      select championship_id,'end',closes_at,'{admin}' from public.markets where id='{m}';
    insert into public.competition_validations(championship_id,end_capture_id,validated_by,note,rows)
      select m.championship_id,c.id,'{admin}','E4 validated race fixture',
        (select jsonb_agg(jsonb_build_object('competitor_id',o.competitor_id,'status','complete',
          'value',case when o.competitor_id='{admin}' then 20 else 10 end,
          'place',case when o.competitor_id='{admin}' then 1 else 2 end)) from public.outcomes o where o.market_id=m.id)
      from public.markets m join public.competition_captures c on c.championship_id=m.championship_id where m.id='{m}';
    """)


# One remaining offer cannot be consumed twice.
m, outcome = market()
o = offer(outcome)
results = race([user(lay, f"select public.accept_offer('{o}',10);"), user(buyer, f"select public.accept_offer('{o}',10);")])
assert sum(r.returncode == 0 for r in results) == 1, results
assert value(f"select count(*) from public.trades where offer_id='{o}'") == '1'

# Double sale: only one buyer acquires the current position/collateral.
position = value(f"select id from public.positions where market_id='{m}' and side='back'")
listing = value(user(back, f"select public.list_position('{position}',5);"))
results = race([user(lay, f"select public.buy_position('{listing}');"), user(buyer, f"select public.buy_position('{listing}');")])
assert sum(r.returncode == 0 for r in results) == 1, results
assert value(f"select count(*) from public.position_sales where listing_id='{listing}'") == '1'

# Settlement/cancellation contend in the same order; repeated settlement pays once.
unmatched = offer(outcome, 7)
close_validate(m)
results = race([user(admin, f"select public.settle_market('{m}','{outcome}');"), user(back, f"select public.cancel_offer('{unmatched}');")])
assert all(r.returncode == 0 for r in results), results
before = value('select count(*) from public.ledger')
results = race([user(admin, f"select public.settle_market('{m}','{outcome}');")] * 2)
assert all(r.returncode == 0 for r in results), results
assert value('select count(*) from public.ledger') == before
assert value(f"select count(*) from public.market_resolutions where market_id='{m}'") == '1'

# Spend on different markets still shares the same finite wallet.
m1, out1 = market()
m2, out2 = market()
o1, o2 = offer(out1, 600), None
# The maker cannot reserve 1200 either; use a different maker for the second offer.
o2 = value(user(admin, f"select public.place_offer('{out2}','back',2,600);"))
results = race([user(buyer, f"select public.accept_offer('{o1}',600);"), user(buyer, f"select public.accept_offer('{o2}',600);")])
assert sum(r.returncode == 0 for r in results) == 1, results

# Cancel vs accept cannot release collateral already committed to a trade.
m3, out3 = market()
o3 = value(user(lay, f"select public.place_offer('{out3}','back',2,5);"))
results = race([user(lay, f"select public.cancel_offer('{o3}');"), user(admin, f"select public.accept_offer('{o3}',5);")])
assert any(r.returncode == 0 for r in results), results
assert value(f"select count(*) from public.trades where offer_id='{o3}'") in ('0', '1')

# Transactions begin before cutoff and wait beyond it: every new economic action fails.
m4, out4 = market()
o4 = value(user(lay, f"select public.place_offer('{out4}','back',2,10);"))
value(user(admin, f"select public.accept_offer('{o4}',5);"))
p4 = value(f"select id from public.positions where market_id='{m4}' and owner_id='{lay}'")
l4 = value(user(lay, f"select public.list_position('{p4}',2);"))
sql(f"update public.markets set closes_at=clock_timestamp()+interval '5 seconds' where id='{m4}'")
before = value('select count(*) from public.ledger')
commands = [user(admin, f"begin; select public.place_offer('{out4}','back',2,1); commit;"),
            user(admin, f"begin; select public.accept_offer('{o4}',1); commit;"),
            user(admin, f"begin; select public.buy_position('{l4}'); commit;"),
            user(lay, f"begin; select public.list_position('{p4}',3); commit;")]
results = race(commands, cross_cutoff=m4)
assert all(r.returncode != 0 and 'Mercado fechado' in r.stderr for r in results), results
assert value('select count(*) from public.ledger') == before
assert value('select sum(available+reserved-total_issued) from public.wallets') in ('0', '0.00')
assert value(user(admin, 'select count(*) from public.reconcile_wallets() where not balanced;')) == '0'
print('E4 concurrency: matching, double sale/spend, cancellation, settlement and cutoff passed')
