"""Disposable localhost sessions: collision replacement, races and real recurring settlement."""
import json
from db_sessions import race, sql, user, value

admin, taker, entrant = [f'ec000000-0000-4000-8000-00000000000{i}' for i in range(1, 4)]
sql(f"insert into auth.users(id) values('{admin}'),('{taker}'),('{entrant}'); insert into public.admins values('{admin}'); insert into public.competitors(id) values('{admin}'),('{taker}'),('{entrant}');")
champ = value("insert into public.championships(name,starts_at,ends_at) values('Collision races','2026-01-01T00:00Z','2026-12-31T23:59:59Z') returning id")
for who, score in [(admin, 12), (taker, 15)]:
    value(user(who, f"select public.declare_initial_ytd('{champ}',{score});"))
defs = {mode: value(user(admin, f"select public.configure_recurring_bet('{champ}','weekly','{mode}',true)->>'definition_id';")) for mode in ('snapshot_value', 'snapshot_delta_previous')}
occ = value(f"select id from public.bet_occurrences where championship_id='{champ}' and kind='weekly' and starts_at<=clock_timestamp() and ends_at>clock_timestamp()")
sprint = value(f"select sprint_id from public.bet_occurrences where id='{occ}'")


def legacy(label, category='winner', mode='snapshot_value', ch=champ, sp=sprint):
    return value(user(admin, f"select public.create_competition_market('{label}','{ch}','{sp}','{category}','{mode}');"))


def preview(m, d, o=occ):
    return json.loads(value(user(admin, f"select public.preview_market_collision('{m}','{d}','{o}');")))


def resolve(m, d, p, o=occ):
    return user(admin, f"select public.resolve_market_collision('{m}','{d}','{o}','{p['fingerprint']}','Preservar legado e arquivar gerado sem histórico de negociação');")


def generated(d, category='winner', o=occ):
    return value(f"select id from public.markets where definition_id='{d}' and occurrence_id='{o}' and category='{category}'")


# Duplicate review commits one immutable resolution, leaving both rows present.
d = defs['snapshot_value']
m = legacy('Duplicate collision')
g = generated(d)
p = preview(m, d)
results = race([resolve(m, d, p)] * 2)
assert all(r.returncode == 0 for r in results), results
assert results[0].stdout.splitlines()[-1] == results[1].stdout.splitlines()[-1]
assert value(f"select count(*) from public.market_collision_resolutions where generated_market_id='{g}'") == '1'
assert value(f"select count(*) from public.markets where id in ('{m}','{g}')") == '2'

# Two legacy candidates cannot consume the same generated placeholder twice.
left, right = legacy('Collision left', 'second'), legacy('Collision right', 'second')
plans = [preview(m, d) for m in (left, right)]
results = race([resolve(m, d, p) for m, p in zip((left, right), plans)])
assert sum(r.returncode == 0 for r in results) == 1, results
assert value(f"select count(*) from public.market_collision_resolutions where legacy_market_id in ('{left}','{right}')") == '1'
assert value(f"select count(*) from public.markets where id in ('{left}','{right}') and definition_id is null") == '1'

# First offer on the generated market versus replacement: either the offer is
# preserved and replacement fails, or the archive rejects the offer before reserving.
m = legacy('First generated offer race', 'last')
g = generated(d, 'last')
p = preview(m, d)
outcome = value(f"select id from public.outcomes where market_id='{g}' and competitor_id='{admin}'")
results = race([resolve(m, d, p), user(admin, f"select public.place_offer('{outcome}','back',2,5);")])
assert sum(r.returncode == 0 for r in results) == 1, results
if results[0].returncode:
    assert 'visualiza' in results[0].stderr.lower(), results
    assert value(f"select replaced_by_market_id is null from public.markets where id='{g}'") == 't'
    offer = value(f"select id from public.offers where market_id='{g}'")
    value(user(admin, f"select public.cancel_offer('{offer}');"))
    assert preview(m, d)['status'] == 'generated_contracts_preserved'
else:
    assert 'substitu' in results[1].stderr.lower(), results
    assert value(f"select count(*) from public.offers where market_id='{g}'") == '0'

# Matching on the preserved legacy serializes with review and keeps the exact trade.
delta = defs['snapshot_delta_previous']
m = legacy('Legacy matching race', mode='snapshot_delta_previous')
outcome = value(f"select id from public.outcomes where market_id='{m}' and competitor_id='{admin}'")
offer = value(user(admin, f"select public.place_offer('{outcome}','back',2,10);"))
p = preview(m, delta)
results = race([resolve(m, delta, p), user(taker, f"select public.accept_offer('{offer}',5);")])
assert results[1].returncode == 0, results
if results[0].returncode:
    assert 'visualiza' in results[0].stderr.lower(), results
    value(resolve(m, delta, preview(m, delta)))
assert value(f"select count(*) from public.trades where offer_id='{offer}'") == '1'
assert value(f"select count(*) from public.positions where market_id='{m}' and status='open'") == '2'
assert value(f"select stake_remaining from public.offers where id='{offer}'") == '5'

# A genuine entry races with replacement. Both universes update before a fresh
# review, or only the survivor updates after replacement; the archive stays frozen.
m = legacy('Entry collision race', 'second', 'snapshot_delta_previous')
g = generated(delta, 'second')
p = preview(m, delta)
results = race([resolve(m, delta, p), user(entrant, f"select public.declare_initial_ytd('{champ}',0);")])
assert results[1].returncode == 0, results
if results[0].returncode:
    assert 'visualiza' in results[0].stderr.lower(), results
    value(resolve(m, delta, preview(m, delta)))
assert value(f"select count(*) from public.outcomes where market_id='{m}'") == '3'
archived_count = value(f"select count(*) from public.outcomes where market_id='{g}'")
results = race([user(admin, f"select public.regenerate_bet_markets('{champ}');")] * 2)
assert all(r.returncode == 0 for r in results), results
assert generated(delta, 'second') == m
assert value(f"select count(*) from public.outcomes where market_id='{g}'") == archived_count

# Regeneration and replacement serialize without introducing a second canonical ID.
m = legacy('Generation collision race', 'last', 'snapshot_delta_previous')
g = generated(delta, 'last')
p = preview(m, delta)
results = race([resolve(m, delta, p), user(admin, f"select public.regenerate_bet_markets('{champ}');")])
assert all(r.returncode == 0 for r in results), results
assert generated(delta, 'last') == m
assert value(f"select replaced_by_market_id='{m}' from public.markets where id='{g}'") == 't'


def short_champ(label):
    ch = value(f"insert into public.championships(name,starts_at,ends_at) values('{label}',clock_timestamp()-interval '1 day',clock_timestamp()+interval '2 days') returning id")
    for who, score in [(admin, 12), (taker, 15), (entrant, 0)]:
        value(user(who, f"select public.declare_initial_ytd('{ch}',{score});"))
    return ch


def short_occ(ch, label, seconds):
    sp = value(f"insert into public.sprints(championship_id,name,kind,starts_at,ends_at) values('{ch}','{label}','weekly',clock_timestamp()-interval '1 hour',clock_timestamp()+interval '{seconds} seconds') returning id")
    o = value(f"insert into public.bet_occurrences(championship_id,kind,period_key,name,starts_at,ends_at,sprint_id) select '{ch}','weekly','{label}','{label}',starts_at,ends_at,id from public.sprints where id='{sp}' returning id")
    return sp, o


# Waiting beyond the cutoff cannot detach a generated market or create a resolution.
cut_ch = short_champ('Collision cutoff')
cut_sp, cut_occ = short_occ(cut_ch, 'collision-cutoff', 8)
cut_def = value(user(admin, f"select public.configure_recurring_bet('{cut_ch}','weekly','snapshot_value',true)->>'definition_id';"))
m = legacy('Cutoff collision', ch=cut_ch, sp=cut_sp)
g = generated(cut_def, o=cut_occ)
p = preview(m, cut_def, cut_occ)
results = race([resolve(m, cut_def, p, cut_occ)], cross_cutoff=g)
assert results[0].returncode != 0, results
assert value(f"select count(*) from public.market_collision_resolutions where generated_market_id='{g}'") == '0'
assert value(f"select replaced_by_market_id is null and definition_id='{cut_def}' from public.markets where id='{g}'") == 't'
# Resolve the genuine earlier final obligation before declaring another period.
round_id = value(user(admin, f"select x->>'id' from jsonb_array_elements(public.get_my_final_declarations()) x where x->>'championship_id'='{cut_ch}';"))
for who, score in [(admin, 12), (taker, 15), (entrant, 0)]:
    value(user(who, f"select public.declare_final_score('{round_id}',{score});"))
value(user(admin, f"select public.finalize_final_round('{round_id}','Preservar os contratos fechados sem substituir identidades');"))

# Real final collection and settlement after replacing three pristine generated
# markets: different mode winners and a blocked second-place delta tie.
final_ch = short_champ('Collision final settlement')
final_sp, final_occ = short_occ(final_ch, 'collision-final', 9)
final_defs = {mode: value(user(admin, f"select public.configure_recurring_bet('{final_ch}','weekly','{mode}',true)->>'definition_id';")) for mode in ('snapshot_value', 'snapshot_delta_previous')}
finals, archives = {}, []
for mode, category in [('snapshot_value', 'winner'), ('snapshot_delta_previous', 'winner'), ('snapshot_delta_previous', 'second')]:
    m = legacy(f'Collision final {mode} {category}', category, mode, final_ch, final_sp)
    g = generated(final_defs[mode], category, final_occ)
    outcome = value(f"select id from public.outcomes where market_id='{m}' and competitor_id='{admin}'")
    offer = value(user(admin, f"select public.place_offer('{outcome}','back',2,5);"))
    value(user(taker, f"select public.accept_offer('{offer}',5);"))
    value(resolve(m, final_defs[mode], preview(m, final_defs[mode], final_occ), final_occ))
    finals[(mode, category)] = m
    archives.append(g)
race([user(admin, 'select pg_advisory_xact_lock(941003);')], cross_cutoff=finals[('snapshot_value', 'winner')])
round_id = value(user(admin, f"select x->>'id' from jsonb_array_elements(public.get_my_final_declarations()) x where x->>'championship_id'='{final_ch}';"))
assert value(f"select count(*) from public.final_members where round_id='{round_id}' and occurrence_id='{final_occ}'") == '3'
for who, score in [(admin, 16), (taker, 18), (entrant, 3)]:
    value(user(who, f"select public.declare_final_score('{round_id}',{score});"))
value(user(admin, f"select public.finalize_final_round('{round_id}','Apurar os mercados legados mantidos na ocorrência comum');"))
for (mode, category), m in finals.items():
    value(user(admin, f"select public.validate_market_classification('{m}','Validar fecho e referências preservadas após colisão');"))
    if category == 'second':
        assert value(user(admin, f"select public.get_market_resolution('{m}')->>'status';")) == 'tie_unsupported'
        before = value('select count(*) from public.ledger')
        assert sql(user(admin, f"select public.settle_market('{m}',null);"), check=False).returncode != 0
        assert value('select count(*) from public.ledger') == before
        assert value(f"select count(*) from public.positions where market_id='{m}' and status='open'") == '2'
    else:
        winner = value(user(admin, f"select public.get_market_resolution('{m}')->>'winner_outcome_id';"))
        assert value(f"select competitor_id from public.outcomes where id='{winner}'") == (taker if mode == 'snapshot_value' else admin)
        results = race([user(admin, f"select public.settle_market('{m}','{winner}');")] * 2)
        assert all(r.returncode == 0 for r in results), results
        assert value(f"select count(*) from public.market_resolutions where market_id='{m}'") == '1'
for g in archives:
    assert value(user(admin, f"select public.get_market_classification('{g}')->>'status';")) == 'replaced'
    assert value(f"select count(*) from public.market_classifications where market_id='{g}'") == '0'
    assert sql(user(admin, f"select public.settle_market('{g}',null);"), check=False).returncode != 0
    assert value(f"select count(*) from public.market_resolutions where market_id='{g}'") == '0'
assert value('select sum(available+reserved-total_issued) from public.wallets') in ('0', '0.00')
assert value(user(admin, 'select count(*) from public.reconcile_wallets() where not balanced;')) == '0'
print('Market collisions: duplicate/competing reviews, offers, matching, entries, generation, cutoff, recurring finals, both settlements, immutable archives and blocked ties passed')
