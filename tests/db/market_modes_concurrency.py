"""Disposable PostgreSQL concurrency regressions."""
import time
from db_sessions import race, sql, value, user

admin, maker, taker, buyer = [f'a1000000-0000-4000-8000-00000000000{i}' for i in range(1,5)]
sql(f"insert into auth.users(id) values('{admin}'),('{maker}'),('{taker}'),('{buyer}'); insert into public.admins(id) values('{admin}'); insert into public.competitors(id) values('{admin}'),('{maker}');")
champ = value("insert into public.championships(name,starts_at,ends_at) values('Modes race',clock_timestamp()-interval '4 days',clock_timestamp()+interval '1 day') returning id")
cutoff = value("select clock_timestamp()+interval '10 seconds'")
periods = {}
for kind in ('weekly', 'monthly'):
    previous = value(f"insert into public.sprints(championship_id,name,kind,starts_at,ends_at) values('{champ}','Previous {kind}','{kind}',clock_timestamp()-interval '3 days',clock_timestamp()-interval '2 days') returning id")
    current = value(f"insert into public.sprints(championship_id,name,kind,starts_at,ends_at) values('{champ}','Current {kind}','{kind}',clock_timestamp()-interval '1 day','{cutoff}') returning id")
    periods[kind] = previous, current

markets = []
for kind in ('weekly', 'monthly'):
    for mode in ('snapshot_value', 'snapshot_delta_previous'):
        m = value(user(admin, f"select public.create_competition_market('Mode {kind} {mode}','{champ}','{periods[kind][1]}','winner','{mode}');"))
        outcome = value(f"select id from public.outcomes where market_id='{m}' and competitor_id='{admin}'")
        offer_id = value(user(maker, f"select public.place_offer('{outcome}','back',2,10);"))
        value(user(taker, f"select public.accept_offer('{offer_id}',10);"))
        # Preserve a completed secondary sale, distinct from collateral/payout.
        position = value(f"select id from public.positions where market_id='{m}' and side='back'")
        listing = value(user(maker, f"select public.list_position('{position}',7);"))
        sql(user(buyer, f"select public.buy_position('{listing}');"))
        # Unmatched reserves are returned only by successful regular settlement.
        value(user(maker, f"select public.place_offer('{outcome}','back',2,3);"))
        markets.append((kind, mode, m, outcome))

deadline = time.monotonic()+20
while value(f"select (clock_timestamp()>='{cutoff}'::timestamptz)::text") != 'true':
    if time.monotonic()>deadline:
        raise AssertionError('Cutoff not reached')
    time.sleep(.05)

# Immutable source fixtures with exact boundary timestamps and history IDs.
# Weekly: absolute A=16.5 > B=2, delta A=4.5 < B=7. Monthly: both tied.
for kind in ('weekly', 'monthly'):
    prev, cur = periods[kind]
    for sprint, variant in ((prev, 'previous'), (cur, 'current')):
        sql(f"""
        do $$declare cap uuid;x record;h bigint;v numeric;i integer:=0;t timestamptz;begin
          select ends_at into t from public.sprints where id='{sprint}';
          insert into public.competition_captures(championship_id,sprint_id,phase,cutoff_at,captured_by)
           values('{champ}','{sprint}','end',t,'{admin}') returning id into cap;
          for x in select c.id,p.nickname from public.competitors c join public.profiles p on p.id=c.id order by c.id loop
           i:=i+1;
           v:=case x.id when '{admin}' then case when '{variant}'='previous' then 12 else 16.5 end
             when '{maker}' then case when '{variant}'='previous' then case when '{kind}'='monthly' then 12 else -5 end
               else case when '{kind}'='monthly' then 16.5 else 2 end end
             else case when '{variant}'='previous' then 0 else -i end end;
           insert into public.score_history(competitor_id,ytd,created_at) values(x.id,v,t-interval '1 second') returning id into h;
           insert into public.competition_capture_scores(capture_id,competitor_id,nickname,source_history_id,declared_at,ytd) values(cap,x.id,x.nickname,h,t-interval '1 second',v);
          end loop;
        end $$;
        """)

for kind, mode, m, outcome in markets:
    validate = user(admin, f"select public.validate_market_classification('{m}','Revisão concorrente dos fechos e modalidade');")
    results = race([validate, validate])
    assert all(r.returncode==0 for r in results), results
    assert results[0].stdout.splitlines()[-1] == results[1].stdout.splitlines()[-1]
    assert value(f"select count(*) from public.market_classifications where market_id='{m}'") == '1'
    if kind=='monthly':
        assert value(user(admin, f"select public.get_market_resolution('{m}')->>'status';")) == 'tie_unsupported'
        before = value('select count(*) from public.ledger')
        results = race([user(admin, f"select public.settle_market('{m}','{outcome}');")] * 2)
        assert all(r.returncode!=0 for r in results), results
        assert value('select count(*) from public.ledger') == before
        assert value(f"select count(*) from public.market_resolutions where market_id='{m}'") == '0'
        assert value(f"select count(*) from public.positions where market_id='{m}' and status='open'") == '2'
        continue
    winner = value(user(admin, f"select public.get_market_resolution('{m}')->>'winner_outcome_id';"))
    winner_competitor = value(f"select competitor_id from public.outcomes where id='{winner}'")
    assert winner_competitor == (admin if mode=='snapshot_value' else maker)
    wrong = value(f"select id from public.outcomes where market_id='{m}' and id<>'{winner}' limit 1")
    assert sql(user(admin, f"select public.settle_market('{m}','{wrong}');"), check=False).returncode!=0
    results = race([user(admin, f"select public.settle_market('{m}','{winner}');")] * 2)
    assert all(r.returncode==0 for r in results), results
    before = value('select count(*) from public.ledger')
    sql(user(admin, f"select public.settle_market('{m}','{winner}');"))
    assert value('select count(*) from public.ledger') == before
    assert value(f"select count(*) from public.market_resolutions where market_id='{m}' and classification_id is not null and validation_id is null") == '1'
    payoff = 20 if mode=='snapshot_value' else 0
    assert value(f"select count(*) from public.position_settlements s join public.positions p on p.id=s.position_id where p.market_id='{m}' and s.owner_id='{buyer}' and s.payoff={payoff} and s.final_cost_basis=7 and s.realized_pnl={payoff-7}") == '1'

assert value(f"select count(*) from public.position_sales where seller_id='{maker}' and realized_pnl=-3") == '4'
assert value('select sum(available+reserved-total_issued) from public.wallets') in ('0','0.00')
assert value(user(admin,'select count(*) from public.reconcile_wallets() where not balanced;')) == '0'
print('Snapshot modes: divergent winners, audited sources, validation/settlement races, final-holder P&L, conserved supply and blocked ties passed')


