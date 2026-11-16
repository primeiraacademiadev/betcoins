"""Final declaration/deadline/capture/settlement races on disposable PostgreSQL."""
import time
from db_sessions import race,sql,value,user

admin, other = ['d4000000-0000-4000-8000-000000000001','d4000000-0000-4000-8000-000000000002']
sql(f"insert into auth.users(id) values('{admin}'),('{other}'); insert into public.admins(id) values('{admin}'); insert into public.competitors(id) values('{admin}'),('{other}');")
champ=value("insert into public.championships(name,starts_at,ends_at) values('Final declaration races',clock_timestamp()-interval '30 days',clock_timestamp()+interval '1 day') returning id")
for who in (admin,other):
    sql(user(who,'select public.set_my_score(12);'))


def occurrence(kind,cutoff,label):
    sprint=value(f"insert into public.sprints(championship_id,name,kind,starts_at,ends_at) values('{champ}','{label}','{kind}','{cutoff}'::timestamptz-interval '1 hour','{cutoff}') returning id")
    definition=value(f"insert into public.bet_definitions(championship_id,kind,mode) values('{champ}','{kind}','snapshot_value') on conflict(championship_id,kind,mode) do update set active=true returning id")
    occ=value(f"insert into public.bet_occurrences(championship_id,kind,period_key,name,starts_at,ends_at,sprint_id) values('{champ}','{kind}','{label}','{label}','{cutoff}'::timestamptz-interval '1 hour','{cutoff}','{sprint}') returning id")
    market=value(f"insert into public.markets(title,kind,category,closes_at,championship_id,sprint_id,mode,definition_id,occurrence_id) values('{label}','{kind}','winner','{cutoff}','{champ}','{sprint}','snapshot_value','{definition}','{occ}') returning id")
    sql(f"insert into public.outcomes(market_id,competitor_id,label) values('{market}','{admin}','A'),('{market}','{other}','B')")
    outcome=value(f"select id from public.outcomes where market_id='{market}' and competitor_id='{admin}'")
    offer=value(user(admin,f"select public.place_offer('{outcome}','back',2,10);"))
    value(user(other,f"select public.accept_offer('{offer}',10);"))
    return sprint,market,outcome


def await_cutoff(cutoff):
    deadline=time.monotonic()+20
    while value(f"select (clock_timestamp()>='{cutoff}'::timestamptz)::text")!='true':
        if time.monotonic()>deadline:
            raise AssertionError('Cutoff not reached')
        time.sleep(.05)


cutoff=value("select clock_timestamp()+interval '5 seconds'")
weekly,market,outcome=occurrence('weekly',cutoff,'Coincident weekly')
monthly,month_market,month_outcome=occurrence('monthly',cutoff,'Coincident monthly')
await_cutoff(cutoff)
pending=value(user(admin,"select public.get_my_final_declarations()->0->>'id';"))
assert value(f"select count(*) from public.final_round_occurrences where round_id='{pending}'")=='2'
assert sql(user(admin,'select public.set_my_score(99);'),check=False).returncode!=0
assert sql(user(admin,f"select public.capture_sprint('{weekly}','end');"),check=False).returncode!=0

# Same declaration repeated concurrently freezes one record and does not update live YTD.
declare=user(admin,f"select public.declare_final_score('{pending}',13);")
results=race([declare,declare])
assert all(r.returncode==0 for r in results),results
assert results[0].stdout.splitlines()[-1]==results[1].stdout.splitlines()[-1]
declaration=results[0].stdout.splitlines()[-1]
assert value(f"select count(*) from public.closing_declarations where round_id='{pending}'")=='1'
assert value(f"select ytd from public.competitors where id='{admin}'") in ('12','12.0000')
sql(user(admin,'select public.set_my_score(99);'))
deadline=value("select clock_timestamp()+interval '2 seconds'")
sql(user(admin,f"select public.set_final_deadline('{pending}','{deadline}','Prazo administrativo explícito para teste');"))
assert sql(user(admin,f"select public.finalize_final_round('{pending}','Não encurtar prazo prometido');"),check=False).returncode!=0
await_cutoff(deadline)
before=value('select count(*) from public.ledger')

# The late declaration fails completely even when contending with finalization.
results=race([user(other,f"select public.declare_final_score('{pending}',100);"),user(admin,f"select public.finalize_final_round('{pending}','Apurar após o prazo administrativo');")])
assert results[0].returncode!=0 and results[1].returncode==0,results
assert value('select count(*) from public.ledger')==before
assert value(f"select count(*) from public.closing_declarations where round_id='{pending}'")=='1'
assert value(f"select count(*) from public.competition_capture_scores where closing_declaration_id='{declaration}' and declared_ytd=13 and penalty_pp=0")=='2'
assert value(f"select count(*) from public.competition_capture_scores s join public.competition_captures c on c.id=s.capture_id where c.championship_id='{champ}' and s.competitor_id='{other}' and s.declared_ytd=12 and s.ytd=11 and s.penalty_pp=1")=='2'
assert value(f"select ytd from public.competitors where id='{admin}'") in ('99','99.0000')
finalize=user(admin,f"select public.finalize_final_round('{pending}','Repetição segura do fecho congelado');")
assert all(r.returncode==0 for r in race([finalize,finalize]))
assert value(f"select count(*) from public.competition_captures where championship_id='{champ}' and phase='end'")=='2'

for current,expected in ((market,outcome),(month_market,month_outcome)):
    assert sql(user(admin,f"select public.settle_market('{current}','{expected}');"),check=False).returncode!=0
    validate=user(admin,f"select public.validate_market_classification('{current}','Validar classificação com penalização auditada');")
    assert all(r.returncode==0 for r in race([validate,validate]))
    results=race([user(admin,f"select public.settle_market('{current}','{expected}');")]*2)
    assert all(r.returncode==0 for r in results),results
    assert value(f"select count(*) from public.market_resolutions where market_id='{current}'")=='1'

# Omission penalty on both sides may create a tie: no payments/refunds are invented.
sql(user(admin,'select public.set_my_score(12);'))
next_cutoff=value("select clock_timestamp()+interval '3 seconds'")
_,tie_market,tie_outcome=occurrence('weekly',next_cutoff,'Penalized tie')
await_cutoff(next_cutoff)
tie_round=value(user(admin,"select public.get_my_final_declarations()->0->>'id';"))
sql(user(admin,f"select public.finalize_final_round('{tie_round}','Encerramento imediato explícito da recolha');"))
sql(user(admin,f"select public.validate_market_classification('{tie_market}','Ambas as omissões produzem empate real');"))
assert value(user(admin,f"select public.get_market_resolution('{tie_market}')->>'status';"))=='tie_unsupported'
before=value('select count(*) from public.ledger')
results=race([user(admin,f"select public.settle_market('{tie_market}','{tie_outcome}');")]*2)
assert all(r.returncode!=0 for r in results),results
assert value('select count(*) from public.ledger')==before
assert value(f"select count(*) from public.positions where market_id='{tie_market}' and status='open'")=='2'
assert value('select sum(available+reserved-total_issued) from public.wallets') in ('0','0.00')
assert value(user(admin,'select count(*) from public.reconcile_wallets() where not balanced;'))=='0'
print('Final declarations: coincident sources, mandatory sequence, deadline races, immutable penalties, idempotent settlement and blocked ties passed')
