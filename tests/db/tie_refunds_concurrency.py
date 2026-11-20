"""Real local calendar, resale chains and overlapping whole-market tie refunds."""
import json
import time
from db_sessions import race, sql, user, value

actors = [f'f5000000-0000-4000-8000-00000000000{i}' for i in range(1, 5)]
admin, lay, buyer, last_buyer = actors
sql('insert into auth.users(id) values' + ','.join(f"('{x}')" for x in actors) + ';')
sql(f"insert into public.admins values('{admin}'); insert into public.competitors(id) values('{admin}'),('{lay}'),('{buyer}');")


def call(who, command):
    return value(user(who, command))


def denied(who, command):
    assert sql(user(who, command), check=False).returncode != 0, command


def snapshot():
    return value("select md5(string_agg(to_jsonb(w)::text,',' order by owner_id)) from public.wallets w") + ':' + value('select count(*) from public.ledger')


def assert_clean():
    assert call(admin, 'select count(*) from public.reconcile_wallets() where not balanced;') == '0'
    assert value('select (sum(available+reserved)=sum(total_issued))::text from public.wallets') == 'true'


for group, scores in [('top', (20, 20, 3)), ('bottom', (20, 3, 3)), ('unique', (20, 15, 3))]:
    champ = value("insert into public.championships(name,starts_at,ends_at) values('Tie refund grid',clock_timestamp()-interval '1 day',clock_timestamp()+interval '14 seconds') returning id")
    for who in actors[:3]:
        call(who, f"select public.declare_initial_ytd('{champ}',0);")
    for mode in ('snapshot_value', 'snapshot_delta_previous'):
        call(admin, f"select public.configure_recurring_bet('{champ}','annual','{mode}',true);")
    markets = json.loads(value(f"select jsonb_agg(jsonb_build_object('id',id,'category',category,'mode',mode)) from public.markets where championship_id='{champ}'"))
    for m in markets:
        mid = m['id']
        outcome = value(f"select id from public.outcomes where market_id='{mid}' and competitor_id='{admin}'")
        offer = call(admin, f"select public.place_offer('{outcome}','back',1.20,15);")
        call(lay, f"select public.accept_offer('{offer}',10);")
        m['offer'] = offer
        # A contract on a competitor outside the top tie must also be refunded.
        other = value(f"select id from public.outcomes where market_id='{mid}' and competitor_id='{buyer}'")
        extra = call(admin, f"select public.place_offer('{other}','lay',2,5);")
        call(lay, f"select public.accept_offer('{extra}',5);")
        if group == 'top' and m['category'] == 'winner':
            position = value(f"select id from public.positions where market_id='{mid}' and outcome_id='{outcome}' and side='back'")
            listing = call(admin, f"select public.list_position('{position}',7,10);")
            call(buyer, f"select public.buy_position('{listing}');")
            listing = call(buyer, f"select public.list_position('{position}',4,5);")
            call(last_buyer, f"select public.buy_position('{listing}');")
            # Resell one complete LAY slice too; preserve its acquisition basis.
            lp = value(f"select id from public.positions where market_id='{mid}' and outcome_id='{outcome}' and side='lay' order by id limit 1")
            listing = call(lay, f"select public.list_position('{lp}',0.50,5);")
            call(admin, f"select public.buy_position('{listing}');")
            m['listing'] = call(admin, f"select public.list_position('{lp}',0.75,5);")
        before = snapshot()
        denied(admin, f"select public.refund_tied_market('{mid}');")
        assert snapshot() == before
    deadline = time.monotonic() + 30
    while value(f"select (clock_timestamp()>=ends_at)::text from public.championships where id='{champ}'") != 'true':
        if time.monotonic() > deadline:
            raise AssertionError('Real championship cutoff was not reached')
        time.sleep(.05)
    rid = call(admin, f"select x->>'id' from jsonb_array_elements(public.get_my_final_declarations()) x where x->>'championship_id'='{champ}';")
    for who, score in zip(actors[:3], scores):
        call(who, f"select public.declare_final_score('{rid}',{score});")
    call(admin, f"select public.finalize_final_round('{rid}','Frozen scores for whole-market tie refunds');")
    for m in markets:
        mid = m['id']
        before = snapshot()
        denied(admin, f"select public.refund_tied_market('{mid}');")  # not validated
        assert snapshot() == before
        call(admin, f"select public.validate_market_classification('{mid}','Reviewed tie refund classification and source snapshots');")
        resolution = json.loads(call(admin, f"select public.get_market_resolution('{mid}');"))
        tied = (group == 'top' and m['category'] in ('winner', 'second')) or (group == 'bottom' and m['category'] in ('second', 'last'))
        denied(lay, f"select public.refund_tied_market('{mid}');")
        if not tied:
            assert resolution['status'] == 'ready', resolution
            denied(admin, f"select public.refund_tied_market('{mid}');")
            assert snapshot() == before
            call(admin, f"select public.settle_market('{mid}','{resolution['winner_outcome_id']}');")
            denied(admin, f"select public.refund_tied_market('{mid}');")
            assert_clean()
            continue
        assert resolution['status'] == 'ready_refund' and resolution['winner_outcome_id'] is None
        sales = value('select coalesce(jsonb_agg(to_jsonb(s) order by listing_id),\'[]\'::jsonb) from public.position_sales s')
        wealth = value("select jsonb_agg(jsonb_build_array(owner_id,available+reserved) order by owner_id) from public.wallets")
        denied(admin, f"select public.settle_market('{mid}',null);")
        # Force a late financial failure in a rollback-only local transaction.
        result = sql(f"begin; update public.wallets set reserved=0 where owner_id='{lay}'; " + user(admin, f"select public.refund_tied_market('{mid}');"), check=False)
        assert result.returncode != 0
        assert snapshot() == before
        commands = [user(admin, f"select public.refund_tied_market('{mid}');")] * 3
        commands.append(user(admin, f"select public.cancel_offer('{m['offer']}');"))
        if 'listing' in m:
            commands.append(user(last_buyer, f"select public.buy_position('{m['listing']}');"))
        results = race(commands)
        assert all(r.returncode == 0 for r in results[:4]), results
        assert all(r.returncode != 0 for r in results[4:]), results
        assert value("select jsonb_agg(jsonb_build_array(owner_id,available+reserved) order by owner_id) from public.wallets") == wealth
        assert value('select coalesce(jsonb_agg(to_jsonb(s) order by listing_id),\'[]\'::jsonb) from public.position_sales s') == sales
        assert value(f"select count(*) from public.positions where market_id='{mid}' and status<>'settled'") == '0'
        assert value(f"select count(*) from public.listings l join public.positions p on p.id=l.position_id where p.market_id='{mid}' and l.state='open'") == '0'
        assert value(f"select count(*) from public.position_settlements s join public.positions p on p.id=s.position_id where p.market_id='{mid}' and (s.owner_id<>p.owner_id or s.settlement_kind<>'tie_refund' or s.payoff<>case when p.side='back' then p.stake else p.liability end or s.realized_pnl<>s.payoff-p.cost_basis)") == '0'
        assert value(f"select (count(*)=count(s.position_id))::text from public.positions p left join public.position_settlements s on s.position_id=p.id where p.market_id='{mid}'") == 'true'
        assert value(f"select sum(s.payoff) from public.position_settlements s join public.positions p on p.id=s.position_id where p.market_id='{mid}'") == '22.00'
        assert value(f"select available_delta||':'||reserved_delta from public.ledger where reason='expire_offer' and reference='{m['offer']}'") == '5.00:-5.00'
        if 'listing' in m:
            assert value(f"select seller_cost_basis||':'||sale_price||':'||realized_pnl from public.position_sales s join public.positions p on p.id=s.position_id where p.market_id='{mid}' and s.seller_id='{admin}'") == '10.00:7.00:-3.00'
            assert value(f"select payoff||':'||final_cost_basis||':'||realized_pnl from public.position_settlements s join public.positions p on p.id=s.position_id where p.market_id='{mid}' and s.owner_id='{buyer}'") == '5.00:3.50:1.50'
            assert value(f"select payoff||':'||final_cost_basis||':'||realized_pnl from public.position_settlements s join public.positions p on p.id=s.position_id where p.market_id='{mid}' and s.owner_id='{last_buyer}'") == '5.00:4.00:1.00'
        assert value(f"select resolution_kind||':'||(winner_outcome_id is null)::text from public.market_resolutions where market_id='{mid}'") == 'tie_refund:true'
        assert json.loads(call(admin, f"select public.get_market_activity('{mid}');"))['resolution']['status'] == 'refunded'
        assert json.loads(call(admin, f"select public.get_market_resolution('{mid}');"))['status'] == 'refunded'
        again = snapshot()
        call(admin, f"select public.refund_tied_market('{mid}');")
        assert snapshot() == again
        assert_clean()
    print(f'Tie refunds PASS: {group}, both modes, all places, real sources and reconciled wallets', flush=True)

assert value("select has_function_privilege('anon','public.refund_tied_market(uuid)','EXECUTE')::text") == 'false'
assert value("select has_function_privilege('authenticated','public.get_market_resolution_before_refunds(uuid)','EXECUTE')::text") == 'false'
print('Tie refunds PASS: current holders, BACK/LAY resale chains, partial/unmatched lots, rollback and overlapping retries')
