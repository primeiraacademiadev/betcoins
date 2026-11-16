"""Recurring generation/admission races on the disposable CI database only."""
from db_sessions import race, sql, value, user

admin, voter, candidate, buyer = [f'c2000000-0000-4000-8000-00000000000{i}' for i in range(1,5)]
sql(f"insert into auth.users(id) values('{admin}'),('{voter}'),('{candidate}'),('{buyer}'); insert into public.admins(id) values('{admin}'); insert into public.competitors(id) values('{admin}'),('{voter}');")
champ = value("insert into public.championships(name,starts_at,ends_at) values('Recurring race','2026-01-01T00:00Z','2026-12-31T23:59:59Z') returning id")
configure = user(admin,f"select public.configure_recurring_bet('{champ}','weekly','snapshot_value',true);")
results = race([configure,configure])
assert all(r.returncode==0 for r in results), results
assert value(f"select count(*) from public.bet_definitions where championship_id='{champ}'")=='1'
assert value(f"select count(*) from public.bet_occurrences where championship_id='{champ}'")=='66'
market_count = value(f"select count(*) from public.markets where championship_id='{champ}'")
assert int(market_count)>0
generate = user(admin,f"select public.regenerate_bet_markets('{champ}');")
assert all(r.returncode==0 for r in race([generate,generate]))
assert value(f"select count(*) from public.markets where championship_id='{champ}'")==market_count
assert value(f"select count(*) from (select definition_id,occurrence_id,category from public.markets where championship_id='{champ}' group by 1,2,3 having count(*)>1) x")=='0'

# The same active period has both explicit modalities and references after activation.
sql(user(admin,f"select public.configure_recurring_bet('{champ}','weekly','snapshot_delta_previous',true);"))
market = value(f"select id from public.markets where championship_id='{champ}' and mode='snapshot_value' and category='winner' and closes_at>clock_timestamp() order by closes_at limit 1")
outcome = value(f"select id from public.outcomes where market_id='{market}' and competitor_id='{admin}'")
offer = value(user(admin,f"select public.place_offer('{outcome}','back',2,10);"))
protected_offer = value(f"select to_jsonb(o)::text from public.offers o where id='{offer}'")

# Real voting, including a non-admin decisive voter, drives the admission trigger.
sql(user(candidate,'select public.apply_competitor();'))
application = value(f"select id from public.applications where candidate_id='{candidate}' and state='pending'")
electors = sql(f"select voter_id from public.application_electorate where application_id='{application}' order by voter_id").stdout.strip().splitlines()
needed = len(electors)//2+1
for who in electors[:needed-1]:
    sql(user(who,f"select public.vote_application('{application}',true);"))
results = race([user(who,f"select public.vote_application('{application}',true);") for who in electors[needed-1:needed+1]])
assert sum(r.returncode==0 for r in results)==1, results
assert value(f"select count(*) from public.competitors where id='{candidate}' and ytd is null")=='1'
assert value(f"select count(*) from public.markets m join public.bet_definitions d on d.id=m.definition_id where d.championship_id='{champ}' and d.active and m.closes_at>clock_timestamp() and not exists(select 1 from public.outcomes o where o.market_id=m.id and o.competitor_id='{candidate}')")=='0'
assert value(f"select to_jsonb(o)::text from public.offers o where id='{offer}'")==protected_offer

# Reconciliation and acceptance serialize without destroying the existing contract.
results = race([generate,user(candidate,f"select public.accept_offer('{offer}',5);")])
assert all(r.returncode==0 for r in results), results
assert value(f"select count(*) from public.trades where offer_id='{offer}'")=='1'
assert value(f"select stake_remaining from public.offers where id='{offer}'")=='5'
assert value(f"select count(*) from public.positions where market_id='{market}'")=='2'

# Concurrent admissions append each outcome once, including all future periods.
more = ['c2000000-0000-4000-8000-000000000005','c2000000-0000-4000-8000-000000000006']
sql(f"insert into auth.users(id) values('{more[0]}'),('{more[1]}');")
results = race([f"insert into public.competitors(id) values('{who}');" for who in more])
assert all(r.returncode==0 for r in results), results
for who in more:
    assert value(f"select count(*) from public.markets m join public.bet_definitions d on d.id=m.definition_id where d.championship_id='{champ}' and d.active and m.closes_at>clock_timestamp() and not exists(select 1 from public.outcomes o where o.market_id=m.id and o.competitor_id='{who}')")=='0'

# Pause vs accept: either the match precedes pause, or it fails in full.
pause = user(admin,f"select public.configure_recurring_bet('{champ}','weekly','snapshot_value',false);")
results = race([pause,user(buyer,f"select public.accept_offer('{offer}',5);")])
assert results[0].returncode==0, results
assert results[1].returncode==0 or 'suspensa' in results[1].stderr, results
assert value(f"select active::text from public.bet_definitions where championship_id='{champ}' and mode='snapshot_value'")=='false'
sql(user(admin,f"select public.configure_recurring_bet('{champ}','weekly','snapshot_value',true);"))
assert value('select sum(available+reserved-total_issued) from public.wallets') in ('0','0.00')
assert value(user(admin,'select count(*) from public.reconcile_wallets() where not balanced;'))=='0'
print('Recurring bets: concurrent generation, real admissions, append-only outcomes, matching, pause/resume and conservation passed')
