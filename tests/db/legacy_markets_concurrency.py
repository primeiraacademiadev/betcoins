"""Real localhost sessions: review races, cutoff, settlement and conserved money."""
import json
from db_sessions import race, sql, value, user

admin, other, pending = [f'e8000000-0000-4000-8000-00000000000{i}' for i in range(1, 4)]
sql(f"insert into auth.users(id) values('{admin}'),('{other}'),('{pending}'); insert into public.admins values('{admin}'); insert into public.competitors(id) values('{admin}'),('{other}'),('{pending}');")
champ = value("insert into public.championships(name,starts_at,ends_at) values('Legacy races',clock_timestamp()-interval '1 day',clock_timestamp()+interval '3 days') returning id")
for who, score in [(admin, 12), (other, 15)]:
    value(user(who, f"select public.declare_initial_ytd('{champ}',{score});"))


def fixture(label, seconds=120, category='winner'):
    sprint = value(f"insert into public.sprints(championship_id,name,kind,starts_at,ends_at) values('{champ}','{label}','weekly',clock_timestamp()-interval '1 hour',clock_timestamp()+interval '{seconds} seconds') returning id")
    market = value(f"insert into public.markets(title,kind,category,closes_at) select '{label}','weekly','{category}',ends_at from public.sprints where id='{sprint}' returning id")
    sql(f"insert into public.outcomes(market_id,competitor_id,label) select '{market}',id,nickname from public.profiles where id in ('{admin}','{other}');")
    return market, sprint


def preview(market, sprint, mode='snapshot_value'):
    return json.loads(value(user(admin, f"select public.preview_legacy_market('{market}','{champ}','{sprint}','{mode}');")))


def apply(market, sprint, plan, mode='snapshot_value'):
    return user(admin, f"select public.reconcile_legacy_market('{market}','{champ}','{sprint}','{mode}','{plan['fingerprint']}','Revisão explícita do contrato legado e participação efetiva');")


# Two reviewers publish exactly one immutable audit and preserve outcome identities.
market, sprint = fixture('Duplicate review')
plan = preview(market, sprint)
ids = value(f"select string_agg(id::text,',' order by id) from public.outcomes where market_id='{market}'")
results = race([apply(market, sprint, plan)] * 2)
assert all(r.returncode == 0 for r in results), results
assert results[0].stdout.splitlines()[-1] == results[1].stdout.splitlines()[-1]
assert value(f"select count(*) from public.market_reconciliations where market_id='{market}'") == '1'
assert value(f"select string_agg(id::text,',' order by id) from public.outcomes where market_id='{market}'") == ids

# First offer and reconciliation serialize. No offer can precede an explicit criterion.
market, sprint = fixture('Offer versus review')
plan = preview(market, sprint)
outcome = value(f"select id from public.outcomes where market_id='{market}' and competitor_id='{admin}'")
results = race([apply(market, sprint, plan), user(admin, f"select public.place_offer('{outcome}','back',2,5);")])
assert results[0].returncode == 0, results
if results[1].returncode:
    assert 'reconcilia' in results[1].stderr.lower(), results
    value(user(admin, f"select public.place_offer('{outcome}','back',2,5);"))
offer = value(f"select id from public.offers where market_id='{market}'")
value(user(other, f"select public.accept_offer('{offer}',5);"))
before = value(f"select jsonb_build_object('offers',(select jsonb_agg(to_jsonb(x)) from public.offers x where market_id='{market}'),'positions',(select jsonb_agg(to_jsonb(x)) from public.positions x where market_id='{market}'),'wallets',(select jsonb_agg(to_jsonb(x) order by owner_id) from public.wallets x),'ledger',(select count(*) from public.ledger))")
blocked = preview(market, sprint)
assert blocked['status'] == 'contracts_preserved'
assert sql(apply(market, sprint, blocked), check=False).returncode != 0
assert value(f"select jsonb_build_object('offers',(select jsonb_agg(to_jsonb(x)) from public.offers x where market_id='{market}'),'positions',(select jsonb_agg(to_jsonb(x)) from public.positions x where market_id='{market}'),'wallets',(select jsonb_agg(to_jsonb(x) order by owner_id) from public.wallets x),'ledger',(select count(*) from public.ledger))") == before
# Cancellation remains usable under quarantine, with no manufactured refunds.
sql(f"insert into public.outcomes(market_id,competitor_id,label) values('{market}','{pending}','Awaiting initial');")
assert sql(user(other, f"select public.list_position((select id from public.positions where market_id='{market}' and owner_id='{other}'),5);"), check=False).returncode != 0

# A new audited entry makes an old preview stale; the review cannot omit that participant.
stale_market, stale_sprint = fixture('Entry versus review')
stale_plan = preview(stale_market, stale_sprint)
results = race([user(pending, f"select public.declare_initial_ytd('{champ}',0);"), apply(stale_market, stale_sprint, stale_plan)])
assert results[0].returncode == 0, results
if results[1].returncode:
    assert 'visualiza' in results[1].stderr.lower(), results
    value(apply(stale_market, stale_sprint, preview(stale_market, stale_sprint)))
assert value(f"select count(*) from public.outcomes where market_id='{stale_market}'") == '3'

# Review waits beyond a real cutoff: no contract mutation or audit is committed.
expired, expired_sprint = fixture('Cutoff review', seconds=7)
expired_plan = preview(expired, expired_sprint)
results = race([apply(expired, expired_sprint, expired_plan)], cross_cutoff=expired)
assert results[0].returncode != 0, results
assert value(f"select count(*) from public.market_reconciliations where market_id='{expired}'") == '0'
assert value(f"select mode is null from public.markets where id='{expired}'") == 't'

# Actual validated settlement after reconciliation, both modes and a blocked delta tie.
value_market, end_sprint = fixture('Reconciled final', seconds=4)
cutoff = value(f"select closes_at from public.markets where id='{value_market}'")
markets = {'snapshot_value': value_market}
for mode in ('snapshot_delta_previous',):
    markets[mode] = value(f"insert into public.markets(title,kind,category,closes_at) values('Reconciled delta','weekly','winner','{cutoff}') returning id")
    sql(f"insert into public.outcomes(market_id,competitor_id,label) select '{markets[mode]}',id,nickname from public.profiles where id in ('{admin}','{other}');")
for mode, m in markets.items():
    value(apply(m, end_sprint, preview(m, end_sprint, mode), mode))
    outcome = value(f"select id from public.outcomes where market_id='{m}' and competitor_id='{admin}'")
    offer = value(user(admin, f"select public.place_offer('{outcome}','back',2,5);"))
    value(user(other, f"select public.accept_offer('{offer}',5);"))
race([user(admin, 'select pg_advisory_xact_lock(941003);')], cross_cutoff=value_market)
cap = value(f"insert into public.competition_captures(championship_id,sprint_id,phase,cutoff_at,captured_by) values('{champ}','{end_sprint}','end','{cutoff}','{admin}') returning id")
for who, score in [(admin, 16), (other, 18), (pending, 3)]:
    # Audited fixture sources; not a production backdated-declaration path.
    history = value(f"insert into public.score_history(competitor_id,ytd,created_at) values('{who}',{score},'{cutoff}'::timestamptz-interval '1 millisecond') returning id")
    sql(f"insert into public.competition_capture_scores(capture_id,competitor_id,nickname,source_history_id,declared_at,ytd) values('{cap}','{who}','Fixture','{history}','{cutoff}'::timestamptz-interval '1 millisecond',{score});")
for mode, m in markets.items():
    value(user(admin, f"select public.validate_market_classification('{m}','Validar as referências explícitas e os scores auditados');"))
    winner = value(user(admin, f"select public.get_market_resolution('{m}')->>'winner_outcome_id';"))
    assert value(f"select competitor_id from public.outcomes where id='{winner}'") == (other if mode == 'snapshot_value' else admin)
    results = race([user(admin, f"select public.settle_market('{m}','{winner}');")] * 2)
    assert all(r.returncode == 0 for r in results), results
    assert value(f"select count(*) from public.market_resolutions where market_id='{m}'") == '1'
# second delta: B=3, C=3, both with genuine independent entry references.
second = value(f"insert into public.markets(title,kind,category,closes_at,championship_id,sprint_id,mode,entry_reference_enabled,entry_starts_at) select 'Frozen delta tie','weekly','second','{cutoff}','{champ}','{end_sprint}','snapshot_delta_previous',true,starts_at from public.sprints where id='{end_sprint}' returning id")
sql(f"insert into public.outcomes(market_id,competitor_id,label) select '{second}',id,nickname from public.profiles where id in ('{admin}','{other}','{pending}');")
value(user(admin, f"select public.validate_market_classification('{second}','Confirmar empate relevante sem desempate arbitrário');"))
assert value(user(admin, f"select public.get_market_resolution('{second}')->>'status';")) == 'tie_unsupported'
ledger = value('select count(*) from public.ledger')
results = race([user(admin, f"select public.settle_market('{second}',null);")] * 2)
assert all(r.returncode != 0 for r in results), results
assert value('select count(*) from public.ledger') == ledger
assert value('select sum(available+reserved-total_issued) from public.wallets') in ('0', '0.00')
assert value(user(admin, 'select count(*) from public.reconcile_wallets() where not balanced;')) == '0'
print('Legacy reconciliation: duplicate reviews, concurrent trading/entry, cutoff, immutable contracts, both settlements, ties and conserved supply passed')
