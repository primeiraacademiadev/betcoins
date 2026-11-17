"""Localhost-only association races and the complete recurring close/settlement path."""
import json
from db_sessions import race, sql, user, value

admin, backer, entrant = [f'ea000000-0000-4000-8000-00000000000{i}' for i in range(1, 4)]
sql(f"insert into auth.users(id) values('{admin}'),('{backer}'),('{entrant}'); insert into public.admins values('{admin}'); insert into public.competitors(id) values('{admin}'),('{backer}');")
champ = value("insert into public.championships(name,starts_at,ends_at) values('Association races','2026-01-01T00:00Z','2026-12-31T23:59:59Z') returning id")
for who, score in [(admin, 12), (backer, 15)]:
    value(user(who, f"select public.declare_initial_ytd('{champ}',{score});"))
definitions = {}
for mode in ('snapshot_value', 'snapshot_delta_previous'):
    definitions[mode] = value(user(admin, f"select public.prepare_bet_for_association('{champ}','weekly','{mode}')->>'definition_id';"))
occ = value(f"select id from public.bet_occurrences where championship_id='{champ}' and kind='weekly' and starts_at<=clock_timestamp() and ends_at>clock_timestamp()")
sprint = value(f"select sprint_id from public.bet_occurrences where id='{occ}'")


def market(title, category='winner', mode='snapshot_value', ch=champ, sp=sprint):
    return value(user(admin, f"select public.create_competition_market('{title}','{ch}','{sp}','{category}','{mode}');"))


def preview(m, d, o=occ):
    return json.loads(value(user(admin, f"select public.preview_market_bet_association('{m}','{d}','{o}');")))


def apply(m, d, p, o=occ):
    return user(admin, f"select public.associate_legacy_market('{m}','{d}','{o}','{p['fingerprint']}','Associar após revisão do calendário, contratos e suspensão');")


# Same review twice commits exactly one audit, preserving the contract identity.
first = market('Duplicate association')
d = definitions['snapshot_value']
p = preview(first, d)
before = value(f"select to_jsonb(m)-'definition_id'-'occurrence_id' from public.markets m where id='{first}'")
results = race([apply(first, d, p)] * 2)
assert all(r.returncode == 0 for r in results), results
assert results[0].stdout.splitlines()[-1] == results[1].stdout.splitlines()[-1]
assert value(f"select count(*) from public.market_bet_associations where market_id='{first}'") == '1'
assert value(f"select to_jsonb(m)-'definition_id'-'occurrence_id' from public.markets m where id='{first}'") == before

# Two compatible legacy contracts compete for one vacant slot; one stays individual.
left, right = market('Competing left', 'second'), market('Competing right', 'second')
plans = [preview(m, d) for m in (left, right)]
results = race([apply(m, d, p) for m, p in zip((left, right), plans)])
assert sum(r.returncode == 0 for r in results) == 1, results
assert value(f"select count(*) from public.markets where definition_id='{d}' and occurrence_id='{occ}' and category='second'") == '1'
assert value(f"select count(*) from public.markets where id in ('{left}','{right}')") == '2'
assert value(f"select count(*) from public.markets where id in ('{left}','{right}') and definition_id is null") == '1'

# A partial match changes the economic signature; association never discards that trade.
exposed = market('Match versus association', 'last')
outcome = value(f"select id from public.outcomes where market_id='{exposed}' and competitor_id='{admin}'")
offer = value(user(admin, f"select public.place_offer('{outcome}','back',2,10);"))
p = preview(exposed, d)
results = race([apply(exposed, d, p), user(backer, f"select public.accept_offer('{offer}',5);")])
assert sum(r.returncode == 0 for r in results) == 1, results
if results[0].returncode:
    assert 'visualiza' in results[0].stderr.lower(), results
    assert value(f"select count(*) from public.trades where offer_id='{offer}'") == '1'
    value(apply(exposed, d, preview(exposed, d)))
else:
    assert 'suspensa' in results[1].stderr.lower(), results
    assert value(f"select stake_remaining from public.offers where id='{offer}'") == '10'
ledger = value('select count(*) from public.ledger')
value(apply(exposed, d, p)) if results[0].returncode == 0 else None
assert value('select count(*) from public.ledger') == ledger
value(user(admin, f"select public.cancel_offer('{offer}');"))

# First score versus association: a stale participant universe never gets published.
candidate = market('Entry versus association', mode='snapshot_delta_previous')
delta_def = definitions['snapshot_delta_previous']
p = preview(candidate, delta_def)
sql(f"insert into public.competitors(id) values('{entrant}');")
results = race([apply(candidate, delta_def, p), user(entrant, f"select public.declare_initial_ytd('{champ}',0);")])
assert results[1].returncode == 0, results
if results[0].returncode:
    assert 'visualiza' in results[0].stderr.lower(), results
    # The suspended bet has not activated the individual market? Individual entry policy sync does.
    value(apply(candidate, delta_def, preview(candidate, delta_def)))
assert value(f"select count(*) from public.outcomes where market_id='{candidate}'") in ('2', '3')
# Resume reconciles all new effective participants, preserving existing identities.
value(user(admin, f"select public.configure_recurring_bet('{champ}','weekly','snapshot_delta_previous',true);"))
assert value(f"select count(*) from public.outcomes where market_id='{candidate}'") == '3'

# Generation versus association has one canonical slot and no silent replacement.
generated_race = market('Generator versus association', 'last', 'snapshot_delta_previous')
# That slot was generated on resume, and is now an explicit collision.
p = preview(generated_race, delta_def)
assert p['status'] == 'slot_occupied'
assert sql(apply(generated_race, delta_def, p), check=False).returncode != 0
# Use a separate paused monthly definition for an actually vacant racing slot.
monthly = value(user(admin, f"select public.prepare_bet_for_association('{champ}','monthly','snapshot_value')->>'definition_id';"))
monthly_occ = value(f"select id from public.bet_occurrences where championship_id='{champ}' and kind='monthly' and starts_at<=clock_timestamp() and ends_at>clock_timestamp()")
monthly_sp = value(f"select sprint_id from public.bet_occurrences where id='{monthly_occ}'")
m = market('Generator racing vacant slot', sp=monthly_sp)
p = preview(m, monthly, monthly_occ)
results = race([apply(m, monthly, p, monthly_occ), user(admin, f"select public.configure_recurring_bet('{champ}','monthly','snapshot_value',true);")])
assert results[1].returncode == 0, results
assert value(f"select count(*) from public.markets where definition_id='{monthly}' and occurrence_id='{monthly_occ}' and category='winner'") == '1'
assert value(f"select count(*) from public.markets where id='{m}'") == '1'

# A real cutoff cannot turn a reviewed live association into retroactive finals.
cut_champ = value("insert into public.championships(name,starts_at,ends_at) values('Association cutoff',clock_timestamp()-interval '1 day',clock_timestamp()+interval '2 days') returning id")
# First current history is genuinely audited for this new championship.
for who, score in [(admin, 12), (backer, 15), (entrant, 0)]:
    value(user(who, f"select public.declare_initial_ytd('{cut_champ}',{score});"))
cut_sprint = value(f"insert into public.sprints(championship_id,name,kind,starts_at,ends_at) values('{cut_champ}','Cutoff review','weekly',clock_timestamp()-interval '1 hour',clock_timestamp()+interval '7 seconds') returning id")
cut_occ = value(f"insert into public.bet_occurrences(championship_id,kind,period_key,name,starts_at,ends_at,sprint_id) select '{cut_champ}','weekly','cut-review','Cutoff',starts_at,ends_at,id from public.sprints where id='{cut_sprint}' returning id")
cut_def = value(f"insert into public.bet_definitions(championship_id,kind,mode,active) values('{cut_champ}','weekly','snapshot_value',false) returning id")
cut_market = market('Cutoff association', ch=cut_champ, sp=cut_sprint)
p = preview(cut_market, cut_def, cut_occ)
results = race([apply(cut_market, cut_def, p, cut_occ)], cross_cutoff=cut_market)
assert results[0].returncode != 0, results
assert value(f"select count(*) from public.market_bet_associations where market_id='{cut_market}'") == '0'
assert value(f"select definition_id is null from public.markets where id='{cut_market}'") == 't'

# Associated legacy markets now use one actual recurring collection, immutable entry
# references, distinct mode winners, and blocked second-place ties with reserved positions.
end_sprint = value(f"insert into public.sprints(championship_id,name,kind,starts_at,ends_at) values('{cut_champ}','Associated final','weekly',clock_timestamp()-interval '59 minutes',clock_timestamp()+interval '8 seconds') returning id")
end_occ = value(f"insert into public.bet_occurrences(championship_id,kind,period_key,name,starts_at,ends_at,sprint_id) select '{cut_champ}','weekly','associated-final','Final',starts_at,ends_at,id from public.sprints where id='{end_sprint}' returning id")
end_delta = value(f"insert into public.bet_definitions(championship_id,kind,mode,active) values('{cut_champ}','weekly','snapshot_delta_previous',false) returning id")
finals = {}
for mode, category, target in [('snapshot_value', 'winner', cut_def), ('snapshot_delta_previous', 'winner', end_delta), ('snapshot_delta_previous', 'second', end_delta)]:
    m = market(f'Associated {mode} {category}', category, mode, cut_champ, end_sprint)
    # No previous period ended before this overlapping fixture's start; entry references apply.
    outcome = value(f"select id from public.outcomes where market_id='{m}' and competitor_id='{admin}'")
    offer = value(user(admin, f"select public.place_offer('{outcome}','back',2,5);"))
    value(user(backer, f"select public.accept_offer('{offer}',5);"))
    value(apply(m, target, preview(m, target, end_occ), end_occ))
    finals[(mode, category)] = m
race([user(admin, 'select pg_advisory_xact_lock(941003);')], cross_cutoff=finals[('snapshot_value', 'winner')])
round_id = value(user(admin, f"select x->>'id' from jsonb_array_elements(public.get_my_final_declarations()) x where (x->>'championship_id')::uuid='{cut_champ}';"))
assert value(f"select count(*) from public.final_members where round_id='{round_id}' and occurrence_id='{end_occ}' and entry_baseline_id is not null") == '3'
for who, score in [(admin, 16), (backer, 18), (entrant, 3)]:
    value(user(who, f"select public.declare_final_score('{round_id}',{score});"))
value(user(admin, f"select public.finalize_final_round('{round_id}','Apurar fecho comum dos contratos legados associados');"))
for (mode, category), m in finals.items():
    value(user(admin, f"select public.validate_market_classification('{m}','Validar fontes congeladas sem reinterpretar o contrato');"))
    if category == 'second':
        assert value(user(admin, f"select public.get_market_resolution('{m}')->>'status';")) == 'tie_unsupported'
        before = value('select count(*) from public.ledger')
        assert sql(user(admin, f"select public.settle_market('{m}',null);"), check=False).returncode != 0
        assert value('select count(*) from public.ledger') == before
        assert value(f"select count(*) from public.positions where market_id='{m}' and status='open'") == '2'
    else:
        winner = value(user(admin, f"select public.get_market_resolution('{m}')->>'winner_outcome_id';"))
        assert value(f"select competitor_id from public.outcomes where id='{winner}'") == (backer if mode == 'snapshot_value' else admin)
        results = race([user(admin, f"select public.settle_market('{m}','{winner}');")] * 2)
        assert all(r.returncode == 0 for r in results), results
        assert value(f"select count(*) from public.market_resolutions where market_id='{m}'") == '1'
assert value('select sum(available+reserved-total_issued) from public.wallets') in ('0', '0.00')
assert value(user(admin, 'select count(*) from public.reconcile_wallets() where not balanced;')) == '0'
print('Market association: duplicate/conflicting reviews, matching, entry, generation, cutoff, recurring finals, both settlements and blocked ties passed')
