"""End-to-end current-model acceptance on disposable localhost PostgreSQL."""
import json
from db_sessions import race, sql, user, value

admin, other, omitted = [f'ee000000-0000-4000-8000-00000000000{i}' for i in range(1, 4)]
sql(f"insert into auth.users(id) values('{admin}'),('{other}'),('{omitted}'); insert into public.admins values('{admin}'); insert into public.competitors(id) values('{admin}'),('{other}'),('{omitted}');")
# A short championship uses the real calendar generator. Weekly, monthly and annual
# boundaries are legitimately truncated to the same championship end, not imported.
champ = value("insert into public.championships(name,starts_at,ends_at) values('Current acceptance final',clock_timestamp()-interval '1 day',clock_timestamp()+interval '9 seconds') returning id")
for who, score in [(admin, 12), (other, 15), (omitted, 0)]:
    value(user(who, f"select public.declare_initial_ytd('{champ}',{score});"))
for kind in ('annual', 'monthly', 'weekly'):
    for mode in ('snapshot_value', 'snapshot_delta_previous'):
        value(user(admin, f"select public.configure_recurring_bet('{champ}','{kind}','{mode}',true);"))
assert value(f"select count(*) from public.bet_occurrences where championship_id='{champ}'") == '3'
assert value(f"select count(*) from public.markets where championship_id='{champ}'") == '18'
value(user(admin, 'select public.set_my_score(13); select public.set_my_score(14);'))
value(user(other, 'select public.set_my_score(17);'))
value(user(omitted, 'select public.set_my_score(4);'))
markets = json.loads(value(f"select jsonb_agg(jsonb_build_object('id',id,'mode',mode,'category',category,'occurrence',occurrence_id,'kind',kind)) from public.markets where championship_id='{champ}'"))
for m in markets:
    outcome = value(f"select id from public.outcomes where market_id='{m['id']}' and competitor_id='{admin}'")
    offer = value(user(admin, f"select public.place_offer('{outcome}','back',2,2);"))
    value(user(other, f"select public.accept_offer('{offer}',2);"))
    m['offer'] = offer
first = markets[0]['id']
race([user(admin, 'select pg_advisory_xact_lock(941003);')], cross_cutoff=first)
round_id = value(user(admin, f"select x->>'id' from jsonb_array_elements(public.get_my_final_declarations()) x where x->>'championship_id'='{champ}';"))
assert value(f"select count(*) from public.final_round_occurrences where round_id='{round_id}'") == '3'
assert value(f"select count(distinct competitor_id) from public.final_members where round_id='{round_id}'") == '3'
# Cutoff blocks new offers/secondary listings; final declarations are mandatory first.
assert sql(user(admin, 'select public.set_my_score(99);'), check=False).returncode != 0
for who, score in [(admin, 16), (other, 18)]:
    value(user(who, f"select public.declare_final_score('{round_id}',{score});"))
results = race([user(admin, f"select public.finalize_final_round('{round_id}','Apurar uma declaração por fechos coincidentes e omissão local');")] * 2)
assert all(r.returncode == 0 for r in results), results
# One frozen statistical classification per occurrence/mode, before validation or money.
assert value(f"select count(*) from public.occurrence_classifications c join public.bet_occurrences o on o.id=c.occurrence_id where o.championship_id='{champ}'") == '6'
stats_before = value(f"select jsonb_agg(to_jsonb(c) order by c.id) from public.occurrence_classifications c join public.bet_occurrences o on o.id=c.occurrence_id where o.championship_id='{champ}'")
for m in markets:
    mid = m['id']
    assert sql(user(other, f"select public.accept_offer('{m['offer']}',1);"), check=False).returncode != 0
    result = json.loads(value(user(admin, f"select public.get_market_classification('{mid}');")))
    rows = {r['competitor_id']: r for r in result['rows']}
    assert float(rows[omitted]['declared_ytd']) == 4 and float(rows[omitted]['penalty_pp']) == 1
    assert float(rows[omitted]['end_ytd']) == 3 and rows[omitted]['score_origin'] == 'missing_final'
    assert float(rows[admin]['previous_ytd']) == 12 if m['mode'] == 'snapshot_delta_previous' else rows[admin]['previous_ytd'] is None
    if m['mode'] == 'snapshot_delta_previous':
        assert float(rows[admin]['value']) == 4 and float(rows[other]['value']) == 3
    # Competing validation of different position markets reuses the same frozen rows.
    results = race([user(admin, f"select public.validate_market_classification('{mid}','Validar fontes e estatísticas partilhadas da ocorrência');")] * 2)
    assert all(r.returncode == 0 for r in results), results
    stored = value(f"select (v.rows=c.rows)::text from public.market_classifications v join public.occurrence_classifications c on c.occurrence_id='{m['occurrence']}' and c.mode=v.mode where v.market_id='{mid}'")
    assert stored == 'true'
    resolution = json.loads(value(user(admin, f"select public.get_market_resolution('{mid}');")))
    if m['mode'] == 'snapshot_delta_previous' and m['category'] in ('second', 'last'):
        assert resolution['status'] == 'tie_unsupported'
        before = value('select count(*) from public.ledger')
        results = race([user(admin, f"select public.settle_market('{mid}',null);")] * 2)
        assert all(r.returncode != 0 for r in results), results
        assert value('select count(*) from public.ledger') == before
        assert value(f"select count(*) from public.positions where market_id='{mid}' and status='open'") == '2'
    else:
        expected = admin if m['mode'] == 'snapshot_delta_previous' or m['category'] == 'second' else other if m['category'] == 'winner' else omitted
        winner = resolution['winner_outcome_id']
        assert value(f"select competitor_id from public.outcomes where id='{winner}'") == expected
        results = race([user(admin, f"select public.settle_market('{mid}','{winner}');")] * 2)
        assert all(r.returncode == 0 for r in results), results
        activity = json.loads(value(user(other, f"select public.get_market_activity('{mid}');")))
        assert activity['resolution']['status'] == 'settled' and activity['resolution']['resolved_at']
        assert len(activity['events']) == 2
# Later current declarations cannot change earlier occurrence ranks or penalties.
value(user(omitted, 'select public.set_my_score(99);'))
value(user(admin, 'select public.set_my_score(100);'))
assert value(f"select jsonb_agg(to_jsonb(c) order by c.id) from public.occurrence_classifications c join public.bet_occurrences o on o.id=c.occurrence_id where o.championship_id='{champ}'") == stats_before
assert sql(f"update public.occurrence_classifications set rows='[]' where occurrence_id='{markets[0]['occurrence']}';", check=False).returncode != 0
assert value('select sum(available+reserved-total_issued) from public.wallets') in ('0', '0.00')
assert value(user(admin, 'select count(*) from public.reconcile_wallets() where not balanced;')) == '0'
print('Issue 11 acceptance: real six-definition generation, coincident finals, local omission penalty, six immutable statistical rankings, all position markets, distinct mode winners, concurrent validation/settlement, historical activity and blocked ties passed')
