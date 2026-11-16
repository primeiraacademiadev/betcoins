-- E4 regression tests, disposable PostgreSQL only. Rolled back in every CI path.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values
 ('e0000000-0000-4000-8000-000000000001'),
 ('e0000000-0000-4000-8000-000000000002'),
 ('e0000000-0000-4000-8000-000000000003');
insert into public.admins(id) values('e0000000-0000-4000-8000-000000000001');
insert into public.competitors(id) select id from auth.users where id::text like 'e0000000%';
select set_config('request.jwt.claim.sub','e0000000-0000-4000-8000-000000000001',false);

-- Create actual market/outcomes, plus an immutable E2 fixture for its exact period.
-- E2's own suite tests temporal capture/validation; this suite tests its consumer.
create function pg_temp.market_fixture(p_kind text,p_category text,p_tie boolean default false,p_missing boolean default false,p_tie_last boolean default false)
returns uuid language plpgsql as $$
declare c uuid;s uuid;m uuid;a uuid;b uuid;v_cutoff timestamptz:=transaction_timestamp()-interval '1 second';
 o record;h bigint;v_value numeric;v_initial numeric;v_index integer:=0;
begin
 insert into public.championships(name,starts_at,ends_at) values('E4 fixture',now()-interval '3 days',now()+interval '1 hour') returning id into c;
 if p_kind<>'annual' then
  insert into public.sprints(championship_id,name,kind,starts_at,ends_at)
   values(c,'E4 sprint',p_kind,now()-interval '1 day',now()+interval '1 hour') returning id into s;
 end if;
 m:=public.create_competition_market('Mercado E4',c,s,p_category);
 update public.markets set closes_at=v_cutoff where id=m;
 update public.championships set ends_at=v_cutoff where id=c;
 if s is not null then
  update public.sprints set ends_at=v_cutoff,state='closed' where id=s;
  insert into public.competition_captures(championship_id,sprint_id,phase,cutoff_at,captured_by)
   values(c,s,'start',now()-interval '1 day',auth.uid()) returning id into a;
 end if;
 insert into public.competition_captures(championship_id,sprint_id,phase,cutoff_at,captured_by)
  values(c,s,'end',v_cutoff,auth.uid()) returning id into b;
 for o in select * from public.outcomes where market_id=m order by competitor_id loop
  v_index:=v_index+1;
  v_value:=case o.competitor_id
   when 'e0000000-0000-4000-8000-000000000001' then 50
   when 'e0000000-0000-4000-8000-000000000002' then case when p_tie then 50 else 20 end
   when 'e0000000-0000-4000-8000-000000000003' then 10 else -v_index end;
  if p_tie_last then v_value:=0;end if;
  insert into public.score_history(competitor_id,ytd,created_at)
   values(o.competitor_id,v_value,v_cutoff-interval '1 second') returning id into h;
  if p_missing and o.competitor_id='e0000000-0000-4000-8000-000000000001' then
   insert into public.competition_capture_scores(capture_id,competitor_id,nickname) values(b,o.competitor_id,o.label);
  else
   insert into public.competition_capture_scores(capture_id,competitor_id,nickname,source_history_id,declared_at,ytd)
    values(b,o.competitor_id,o.label,h,v_cutoff-interval '1 second',v_value);
  end if;
  if a is not null then
   v_initial:=case when o.competitor_id='e0000000-0000-4000-8000-000000000001' and not p_tie then 45 else 0 end;
   insert into public.score_history(competitor_id,ytd,created_at)
    values(o.competitor_id,v_initial,now()-interval '2 days') returning id into h;
   insert into public.competition_capture_scores(capture_id,competitor_id,nickname,source_history_id,declared_at,ytd)
    values(a,o.competitor_id,o.label,h,now()-interval '2 days',v_initial);
  end if;
 end loop;
 perform public.validate_competition(c,s,'Fixture E4: revisão completa dos resultados');
 return m;
end $$;

create function pg_temp.must_fail(p_sql text,p_code text default null) returns void language plpgsql as $$
begin
 begin execute p_sql;
 exception when others then
  if p_code is not null and sqlstate<>p_code then raise exception 'Expected %, got %: %',p_code,sqlstate,sqlerrm;end if;
  return;
 end;
 raise exception 'Expected rejection: %',p_sql;
end $$;

-- Market creation rejects old/unbound API, missing period and non-admin calls.
select pg_temp.must_fail($q$select public.create_market('No binding','annual','winner',now()+interval '1 hour',array[]::uuid[])$q$,'BM003');
select pg_temp.must_fail($q$select public.create_competition_market('No period',null,null,'winner')$q$,'BM003');
select set_config('request.jwt.claim.sub','e0000000-0000-4000-8000-000000000002',false);
select pg_temp.must_fail($q$select public.create_competition_market('Unauthorized',null,null,'winner')$q$,'42501');
select set_config('request.jwt.claim.sub','e0000000-0000-4000-8000-000000000001',false);

do $$declare m uuid;r jsonb;k text;cat text;expected uuid;begin
 foreach k in array array['annual','weekly','monthly'] loop
  foreach cat in array array['winner','second','last'] loop
   m:=pg_temp.market_fixture(k,cat);r:=public.get_market_resolution(m);
   if r->>'status'<>'ready' then raise exception 'Expected ready %/%: %',k,cat,r;end if;
   select o.competitor_id into expected from public.outcomes o where o.id=(r->>'winner_outcome_id')::uuid;
   if cat='winner' and expected<>(case when k='annual' then 'e0000000-0000-4000-8000-000000000001' else 'e0000000-0000-4000-8000-000000000002' end)::uuid then raise exception 'Wrong winner';end if;
   if cat='second' and expected<>(case when k='annual' then 'e0000000-0000-4000-8000-000000000002' else 'e0000000-0000-4000-8000-000000000003' end)::uuid then raise exception 'Wrong second';end if;
   if cat='last' and expected::text like 'e0000000%' then raise exception 'Wrong last';end if;
   perform public.settle_market(m,(r->>'winner_outcome_id')::uuid);
  end loop;
 end loop;
 -- Relevant ties block, including the missing second place in ranking 1,1,3.
 foreach cat in array array['winner','second'] loop
  m:=pg_temp.market_fixture('weekly',cat,true);
  if public.get_market_resolution(m)->>'status'<>'tie_unsupported' then raise exception 'Tie not blocked';end if;
  perform pg_temp.must_fail(format('select public.settle_market(%L,%L)',m,(select id from public.outcomes where market_id=m limit 1)),'BM004');
 end loop;
 m:=pg_temp.market_fixture('monthly','last',true);
 if public.get_market_resolution(m)->>'status'<>'ready' then raise exception 'Irrelevant top tie should not select a false last';end if;
 m:=pg_temp.market_fixture('annual','winner',false,true);
 if public.get_market_resolution(m)->>'status'<>'incomplete' then raise exception 'Missing scores not blocked';end if;
 perform pg_temp.must_fail(format('select public.settle_market(%L,null)',m),'BM004');
 m:=pg_temp.market_fixture('annual','last',false,false,true);
 if public.get_market_resolution(m)->>'status'<>'tie_unsupported' then raise exception 'Last-place tie not blocked';end if;
 m:=pg_temp.market_fixture('annual','winner');
 update public.markets set closes_at=closes_at-interval '1 minute' where id=m;
 if public.get_market_resolution(m)->>'status'<>'period_mismatch' then raise exception 'Mismatched period not blocked';end if;
 m:=pg_temp.market_fixture('annual','winner');
 delete from public.outcomes where market_id=m and competitor_id='e0000000-0000-4000-8000-000000000003';
 if public.get_market_resolution(m)->>'status'<>'universe_changed' then raise exception 'Outcome subset not blocked';end if;
end $$;

do $$declare c uuid;m uuid;begin
 insert into public.championships(name,starts_at,ends_at) values('Awaiting result',now()-interval '1 day',now()+interval '1 day') returning id into c;
 m:=public.create_competition_market('Awaiting validation',c,null,'winner');
 update public.markets set closes_at=now()-interval '1 second' where id=m;
 if public.get_market_resolution(m)->>'status'<>'awaiting_validation' then raise exception 'Unvalidated result accepted';end if;
 perform pg_temp.must_fail(format('select public.settle_market(%L,null)',m),'BM004');
 insert into public.markets(title,kind,category,closes_at) values('Legacy market','annual','winner',now()-interval '1 second') returning id into m;
 if public.get_market_resolution(m)->>'status'<>'unlinked' then raise exception 'Legacy market automatically bound';end if;
 perform pg_temp.must_fail(format('select public.settle_market(%L,null)',m),'BM004');
end $$;

-- Economic regression: partial BACK and LAY, cancellation, full secondary sale,
-- current owner payoff, unmatched release, conservation and immutable retries.
select pg_temp.market_fixture('weekly','winner') as economic_market \gset
select public.get_market_resolution(:'economic_market')->>'winner_outcome_id' as economic_winner \gset
update public.markets set closes_at=clock_timestamp()+interval '1 hour' where id=:'economic_market';
set role authenticated;
select public.place_offer(:'economic_winner','back',1.25,20) as offer_back \gset
select public.place_offer(:'economic_winner','lay',1.20,20) as offer_lay \gset
select pg_temp.must_fail(format('select public.settle_market(%L,%L)',:'economic_market',:'economic_winner'),'BM001');
select pg_temp.must_fail(format('select public.place_offer(%L,null,2,10)',:'economic_winner'),'BM002');
select pg_temp.must_fail(format('select public.place_offer(%L,''back'',''NaN''::numeric,10)',:'economic_winner'),'BM002');
select pg_temp.must_fail(format('select public.accept_offer(%L,null)',:'offer_back'),'BM002');
select pg_temp.must_fail(format('select public.accept_offer(%L,1)',:'offer_back'));
select set_config('request.jwt.claim.sub','e0000000-0000-4000-8000-000000000002',false);
select public.accept_offer(:'offer_back',8) as trade_back \gset
select public.accept_offer(:'offer_lay',10) as trade_lay \gset
select pg_temp.must_fail(format('select public.accept_offer(%L,13)',:'offer_back'));
select pg_temp.must_fail(format('select public.cancel_offer(%L)',:'offer_back'),'42501');
select id as resale_position from public.positions where trade_id=:'trade_back' and side='lay' \gset
select public.list_position(:'resale_position',3) as resale_listing \gset
select set_config('request.jwt.claim.sub','e0000000-0000-4000-8000-000000000003',false);
select public.buy_position(:'resale_listing');
select pg_temp.must_fail(format('select public.buy_position(%L)',:'resale_listing'));
select set_config('request.jwt.claim.sub','e0000000-0000-4000-8000-000000000001',false);
select public.cancel_offer(:'offer_back');
select public.cancel_offer(:'offer_back');
reset role;
-- Restore the exact already validated cutoff; immutable E2 fixture is unchanged.
update public.markets m set closes_at=c.cutoff_at from public.competition_validations v
 join public.competition_captures c on c.id=v.end_capture_id
 where m.id=:'economic_market' and v.sprint_id=m.sprint_id;
set role authenticated;
select pg_temp.must_fail(format('select public.place_offer(%L,''back'',2,1)',:'economic_winner'),'BM001');
select pg_temp.must_fail(format('select public.accept_offer(%L,1)',:'offer_lay'),'BM001');
select pg_temp.must_fail(format('select public.settle_market(%L,%L)',:'economic_market',
 (select id from public.outcomes where market_id=:'economic_market' and id<>:'economic_winner' limit 1)),'BM004');
select set_config('request.jwt.claim.sub','e0000000-0000-4000-8000-000000000002',false);
select pg_temp.must_fail(format('select public.settle_market(%L,%L)',:'economic_market',:'economic_winner'),'42501');
select set_config('request.jwt.claim.sub','e0000000-0000-4000-8000-000000000001',false);
select public.settle_market(:'economic_market',:'economic_winner');
reset role;
select count(*) as ledger_count from public.ledger \gset
set role authenticated;
select public.settle_market(:'economic_market',:'economic_winner');
select pg_temp.must_fail(format('select public.settle_market(%L,null)',:'economic_market'),'BM004');
reset role;
select 1/(case when count(*)=:'ledger_count'::integer then 1 else 0 end) from public.ledger;
do $$begin
 if exists(select 1 from public.reconcile_wallets() where not balanced) then raise exception 'Ledger divergence';end if;
 if (select sum(available+reserved-total_issued) from public.wallets)<>0 then raise exception 'Currency not conserved';end if;
 if exists(select 1 from public.wallets where owner_id::text like 'e0000000%' and reserved<>0) then raise exception 'Collateral not released';end if;
 if not exists(select 1 from public.position_settlements where owner_id='e0000000-0000-4000-8000-000000000003' and payoff=0 and final_cost_basis=3 and realized_pnl=-3) then raise exception 'Resold LAY final P&L incorrect';end if;
 if not exists(select 1 from public.position_sales where seller_id='e0000000-0000-4000-8000-000000000002' and realized_pnl=1) then raise exception 'Previous resale P&L changed';end if;
 if exists(select 1 from public.market_resolutions r join public.markets m on m.id=r.market_id where r.winner_outcome_id<>m.winner_outcome_id) then raise exception 'Resolution mismatch';end if;
end $$;
-- Internal cores and direct writes are never callable by clients.
set role authenticated;
select pg_temp.must_fail($q$select public.settle_market_p2p_core(null,null)$q$,'42501');
select pg_temp.must_fail($q$select public.settle_market_economic_core(null,null)$q$,'42501');
select pg_temp.must_fail($q$select public.place_offer_p2p_core(null,'back',2,1)$q$,'42501');
select pg_temp.must_fail($q$select public.lock_trading_market(null)$q$,'42501');
select pg_temp.must_fail($q$update public.markets set winner_outcome_id=null$q$,'42501');
select pg_temp.must_fail($q$delete from public.market_resolutions$q$,'42501');
reset role;
select pg_temp.must_fail($q$update public.market_resolutions set resolved_at=clock_timestamp()$q$,'BC001');
rollback;
