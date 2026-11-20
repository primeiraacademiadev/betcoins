-- #5: whole-market refunds to current collateral holders. Requires 01--17.
-- Repository/CI only. Never executes against a remote Supabase project.
begin;
alter table public.market_resolutions alter column winner_outcome_id drop not null;
alter table public.market_resolutions add column resolution_kind text not null default 'regular',
 add constraint market_resolution_kind check(
  (resolution_kind='regular' and winner_outcome_id is not null) or
  (resolution_kind='tie_refund' and winner_outcome_id is null and classification_id is not null));
alter table public.position_settlements add column settlement_kind text not null default 'regular'
 check(settlement_kind in ('regular','tie_refund'));

alter function public.get_market_resolution(uuid) rename to get_market_resolution_before_refunds;
revoke all on function public.get_market_resolution_before_refunds(uuid) from public,anon,authenticated;
create function public.get_market_resolution(p_market uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r jsonb;m public.markets%rowtype;c jsonb;
begin
 r:=public.get_market_resolution_before_refunds(p_market);
 select * into m from public.markets where id=p_market;
 if exists(select 1 from public.market_resolutions where market_id=p_market and resolution_kind='tie_refund') then
  return r||jsonb_build_object('status','refunded','resolution_kind','tie_refund','winner_outcome_id',null);
 end if;
 if r->>'status'='tie_unsupported' and m.mode is not null and m.definition_id is not null and m.occurrence_id is not null then
  c:=public.get_market_classification(p_market);
  if c->>'status'='validated' and jsonb_array_length(c->'rows')>=2 and not exists(
   select 1 from jsonb_array_elements(c->'rows') x where x->>'status' is distinct from 'complete' or x->>'value' is null
  ) then return r||jsonb_build_object('status','ready_refund','resolution_kind','tie_refund','winner_outcome_id',null);end if;
 end if;
 return r;
end $$;

create function public.refund_tied_market(p_market uuid) returns void
language plpgsql security definer set search_path='' as $$
declare m public.markets%rowtype;r jsonb;p public.positions%rowtype;f public.offers%rowtype;
 amount numeric;at_time timestamptz;
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 perform pg_advisory_xact_lock(941003);
 select * into m from public.markets where id=p_market for update;
 if not found or m.mode is null or m.definition_id is null or m.occurrence_id is null then
  raise exception using errcode='BM004',message='Devolução exige um mercado recorrente explícito';end if;
 if m.state='settled' and exists(select 1 from public.market_resolutions where market_id=p_market and resolution_kind='tie_refund') then return;end if;
 if m.state<>'open' or clock_timestamp()<m.closes_at then
  raise exception using errcode='BM001',message='Mercado ainda não pode devolver colateral';end if;
 r:=public.get_market_resolution(p_market);
 if r->>'status' is distinct from 'ready_refund' then
  raise exception using errcode='BM004',message='Devolução exige empate relevante na classificação validada';end if;
 -- Fail atomically on inconsistent trade slices, rather than minting a refund.
 if exists(select 1 from public.trades t where t.market_id=p_market and
  (t.settled_at is not null or (select count(*) from public.positions x where x.trade_id=t.id)<>2 or exists(
   select 1 from public.positions x where x.trade_id=t.id and
    (x.status<>'open' or x.market_id<>t.market_id or x.outcome_id<>t.outcome_id or x.stake<>t.stake or x.liability<>t.liability)))) then
  raise exception using errcode='BM004',message='Colateral do mercado inconsistente';end if;
 perform 1 from public.wallets where owner_id in (
  select owner_id from public.positions where market_id=p_market union
  select owner_id from public.offers where market_id=p_market and state='open'
 ) order by owner_id for update;
 at_time:=clock_timestamp();
 for f in select * from public.offers where market_id=p_market and state='open' order by id for update loop
  amount:=case when f.side='back' then f.stake_remaining else round(f.stake_remaining*(f.odds-1),2) end;
  update public.offers set state='cancelled',stake_remaining=0 where id=f.id;
  if amount>0 then perform public.transfer_coins(f.owner_id,amount,-amount,'expire_offer',f.id::text);end if;
 end loop;
 for p in select * from public.positions where market_id=p_market and status='open' order by id for update loop
  amount:=case when p.side='back' then p.stake else p.liability end;
  perform public.transfer_coins(p.owner_id,amount,-amount,'tie_refund',p.id::text);
  insert into public.position_settlements(position_id,owner_id,payoff,final_cost_basis,settled_at,settlement_kind)
   values(p.id,p.owner_id,amount,p.cost_basis,at_time,'tie_refund');
  update public.positions set status='settled' where id=p.id;
 end loop;
 update public.trades set settled_at=at_time where market_id=p_market and settled_at is null;
 update public.listings set state='cancelled' where state='open' and position_id in(select id from public.positions where market_id=p_market);
 update public.markets set state='settled',winner_outcome_id=null where id=p_market;
 insert into public.market_resolutions(market_id,classification_id,winner_outcome_id,resolved_by,resolved_at,resolution_kind)
  values(p_market,(r->>'classification_id')::uuid,null,auth.uid(),at_time,'tie_refund');
end $$;

alter function public.get_market_activity(uuid,timestamptz,text,integer) rename to get_market_activity_before_refunds;
revoke all on function public.get_market_activity_before_refunds(uuid,timestamptz,text,integer) from public,anon,authenticated;
create function public.get_market_activity(p_market uuid,p_before timestamptz default null,p_before_id text default null,p_limit integer default 50) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r jsonb;resolution jsonb;
begin
 r:=public.get_market_activity_before_refunds(p_market,p_before,p_before_id,p_limit);
 select jsonb_build_object('status','refunded','resolution_kind',resolution_kind,'resolved_at',resolved_at,'winner_outcome_id',null)
 into resolution from public.market_resolutions where market_id=p_market and resolution_kind='tie_refund';
 if resolution is not null then r:=r||jsonb_build_object('resolution',resolution);end if;
 return r;
end $$;
revoke all on function public.get_market_resolution(uuid),public.refund_tied_market(uuid),public.get_market_activity(uuid,timestamptz,text,integer) from public,anon,authenticated;
grant execute on function public.get_market_resolution(uuid),public.refund_tied_market(uuid),public.get_market_activity(uuid,timestamptz,text,integer) to authenticated;
commit;
