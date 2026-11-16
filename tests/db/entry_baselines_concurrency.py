"""Initial declaration, admission, market cutoff and financial regression races."""
from db_sessions import race,sql,value,user

admin, voter, candidate, late = [f'e6000000-0000-4000-8000-00000000000{i}' for i in range(1,5)]
sql(f"insert into auth.users(id) values('{admin}'),('{voter}'),('{candidate}'),('{late}'); insert into public.admins(id) values('{admin}'); insert into public.competitors(id) values('{admin}'),('{voter}'),('{late}');")
champ=value("insert into public.championships(name,starts_at,ends_at) values('Entry races','2026-01-01T00:00Z','2026-12-31T23:59:59Z') returning id")
for mode in ('snapshot_value','snapshot_delta_previous'):
    sql(user(admin,f"select public.configure_recurring_bet('{champ}','weekly','{mode}',true);"))
assert value(f"select count(*) from public.markets where championship_id='{champ}'")=='0'
value(user(admin,f"select public.declare_initial_ytd('{champ}',12);"))
assert value(f"select count(*) from public.markets where championship_id='{champ}'")=='0'
value(user(voter,f"select public.declare_initial_ytd('{champ}',15);"))
assert int(value(f"select count(*) from public.markets where championship_id='{champ}'"))>0

# A real decisive vote approves a candidate but does not activate market participation.
sql(user(candidate,'select public.apply_competitor();'))
application=value(f"select id from public.applications where candidate_id='{candidate}' and state='pending'")
electors=sql(f"select voter_id from public.application_electorate where application_id='{application}' order by voter_id").stdout.strip().splitlines()
needed=len(electors)//2+1
for who in electors[:needed]:
    sql(user(who,f"select public.vote_application('{application}',true);"))
assert value(f"select count(*) from public.competitors where id='{candidate}' and ytd is null")=='1'
assert value(f"select count(*) from public.entry_baselines where championship_id='{champ}' and competitor_id='{candidate}'")=='0'
assert value(f"select count(*) from public.outcomes o join public.markets m on m.id=o.market_id where m.championship_id='{champ}' and o.competitor_id='{candidate}'")=='0'

market=value(f"select id from public.markets where championship_id='{champ}' and mode='snapshot_value' order by closes_at limit 1")
outcome=value(f"select id from public.outcomes where market_id='{market}' and competitor_id='{admin}'")
offer=value(user(admin,f"select public.place_offer('{outcome}','back',2,10);"))
initial=user(candidate,f"select public.declare_initial_ytd('{champ}',12);")
results=race([initial,user(voter,f"select public.accept_offer('{offer}',5);")])
assert all(r.returncode==0 for r in results),results
assert value(f"select count(*) from public.entry_baselines where championship_id='{champ}' and competitor_id='{candidate}'")=='1'
assert value(f"select count(*) from public.trades where offer_id='{offer}'")=='1'
assert value(f"select stake_remaining from public.offers where id='{offer}'")=='5'
assert value(f"select count(*) from public.markets m where championship_id='{champ}' and closes_at>clock_timestamp() and not exists(select 1 from public.outcomes o where o.market_id=m.id and o.competitor_id='{candidate}')")=='0'
results=race([initial,initial])
assert all(r.returncode==0 for r in results),results
assert results[0].stdout.splitlines()[-1]==results[1].stdout.splitlines()[-1]
results=race([user(candidate,'select public.set_my_score(13);'),user(candidate,'select public.set_my_score(17);')])
assert all(r.returncode==0 for r in results),results
assert value(f"select b.ytd=h.ytd and b.ytd=12 and b.effective_at=h.created_at from public.entry_baselines b join public.score_history h on h.id=b.source_history_id where b.championship_id='{champ}' and b.competitor_id='{candidate}'")=='t'

# Real cutoff: initial declaration waits until AFTER a published period closes.
cutoff=value("select clock_timestamp()+interval '8 seconds'")
sprint=value(f"insert into public.sprints(championship_id,name,kind,starts_at,ends_at) values('{champ}','Partial entry race','weekly',clock_timestamp()-interval '1 hour','{cutoff}') returning id")
occ=value(f"insert into public.bet_occurrences(championship_id,kind,period_key,name,starts_at,ends_at,sprint_id) select '{champ}','weekly','entry-race','Entry race',starts_at,ends_at,id from public.sprints where id='{sprint}' returning id")
markets={}
for mode,category in [('snapshot_value','winner'),('snapshot_delta_previous','winner'),('snapshot_delta_previous','second')]:
    m=value(user(admin,f"select public.create_competition_market('Entry race {mode} {category}','{champ}','{sprint}','{category}','{mode}');"))
    definition=value(f"select id from public.bet_definitions where championship_id='{champ}' and kind='weekly' and mode='{mode}'")
    sql(f"update public.markets set definition_id='{definition}',occurrence_id='{occ}' where id='{m}'")
    markets[(mode,category)]=m
delta=markets[('snapshot_delta_previous','winner')]
back_outcome=value(f"select id from public.outcomes where market_id='{delta}' and competitor_id='{admin}'")
matched=value(user(admin,f"select public.place_offer('{back_outcome}','back',2,10);"))
value(user(voter,f"select public.accept_offer('{matched}',10);"))
second=markets[('snapshot_delta_previous','second')]
second_outcome=value(f"select id from public.outcomes where market_id='{second}' and competitor_id='{voter}'")
second_offer=value(user(admin,f"select public.place_offer('{second_outcome}','back',2,5);"))
value(user(candidate,f"select public.accept_offer('{second_offer}',5);"))
results=race([user(late,f"select public.declare_initial_ytd('{champ}',77);")],cross_cutoff=delta)
assert results[0].returncode==0,results
assert value(f"select (effective_at>'{cutoff}'::timestamptz)::text from public.entry_baselines where championship_id='{champ}' and competitor_id='{late}'")=='true'
assert value(f"select count(*) from public.outcomes o join public.markets m on m.id=o.market_id where m.occurrence_id='{occ}' and o.competitor_id='{late}'")=='0'
assert value(user(late,"select jsonb_array_length(public.get_my_final_declarations());"))=='0'
round_id=value(user(admin,"select public.get_my_final_declarations()->0->>'id';"))
assert value(f"select count(*) from public.final_members where round_id='{round_id}' and entry_baseline_id is not null")=='3'
assert sql(user(late,f"select public.declare_final_score('{round_id}',77);"),check=False).returncode!=0
for who,score in [(admin,16),(voter,18),(candidate,15)]:
    value(user(who,f"select public.declare_final_score('{round_id}',{score});"))
value(user(admin,f"select public.finalize_final_round('{round_id}','Apurar apenas participações efetivas antes do corte');"))
for m in markets.values():
    value(user(admin,f"select public.validate_market_classification('{m}','Validar referências de entrada e janelas parciais');"))
value_market=markets[('snapshot_value','winner')]
assert value(user(admin,f"select public.get_market_resolution('{value_market}')->>'status';"))=='ready'
value_winner=value(user(admin,f"select public.get_market_resolution('{value_market}')->>'winner_outcome_id';"))
assert value(f"select competitor_id from public.outcomes where id='{value_winner}'")==voter
assert value(user(admin,f"select public.get_market_resolution('{delta}')->>'winner_outcome_id';"))==back_outcome
assert value(f"select previous_capture_id is null and entry_references from public.market_classifications where market_id='{delta}'")=='t'
results=race([user(admin,f"select public.settle_market('{delta}','{back_outcome}');")]*2)
assert all(r.returncode==0 for r in results),results
assert value(f"select count(*) from public.market_resolutions where market_id='{delta}'")=='1'
assert value(user(admin,f"select public.get_market_resolution('{second}')->>'status';"))=='tie_unsupported'
before=value('select count(*) from public.ledger')
results=race([user(admin,f"select public.settle_market('{second}','{second_outcome}');")]*2)
assert all(r.returncode!=0 for r in results),results
assert value('select count(*) from public.ledger')==before
assert value(f"select count(*) from public.positions where market_id='{second}' and status='open'")=='2'
assert value('select sum(available+reserved-total_issued) from public.wallets') in ('0','0.00')
assert value(user(admin,'select count(*) from public.reconcile_wallets() where not balanced;'))=='0'
print('Entry baselines: real approval, first-score activation, immutable races, cutoff exclusion, both modalities, settlement conservation and blocked partial-window ties passed')
