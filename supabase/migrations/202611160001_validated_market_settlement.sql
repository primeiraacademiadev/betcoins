-- E4: guard existing P2P settlement with an immutable E2 result.
-- Repository only: no remote installation. Requires migrations 01--09.
begin;

alter table public.markets
 add column championship_id uuid references public.championships(id),
 add column sprint_id uuid references public.sprints(id);
create table public.market_resolutions(
 market_id uuid primary key references public.markets(id),
 validation_id uuid not null references public.competition_validations(id),
 winner_outcome_id uuid not null references public.outcomes(id),
 resolved_by uuid not null references public.profiles(id),
 resolved_at timestamptz not null default clock_timestamp()
);
alter table public.market_resolutions enable row level security;
revoke all on public.market_resolutions from public,anon,authenticated;
grant select on public.market_resolutions to authenticated;
create policy resolution_read on public.market_resolutions for select to authenticated using(true);
create trigger resolution_immutable before update or delete on public.market_resolutions
 for each row execute function public.reject_competition_rewrite();

-- A single MVP trading mutex prevents cross-market wallet lock inversions.
-- Check wall time AFTER waiting: now() is the start of the transaction.
create function public.lock_trading_market(p_market uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_market public.markets%rowtype;
begin
 if auth.uid() is null then raise exception using errcode='42501',message='Não autenticado';end if;
 perform pg_advisory_xact_lock(941003);
 select * into v_market from public.markets where id=p_market for update;
 if not found or v_market.state<>'open' or clock_timestamp()>=v_market.closes_at then
  raise exception using errcode='BM001',message='Mercado fechado';
 end if;
end $$;

alter function public.place_offer(uuid,text,numeric,integer) rename to place_offer_p2p_core;
alter function public.accept_offer(uuid,integer) rename to accept_offer_p2p_core;
alter function public.buy_position(uuid) rename to buy_position_p2p_core;
alter function public.list_position(uuid,numeric,integer) rename to list_position_p2p_core;
alter function public.create_market(text,text,text,timestamptz,uuid[]) rename to create_market_p2p_core;
alter function public.settle_market(uuid,uuid) rename to settle_market_p2p_core;
revoke all on function public.place_offer_p2p_core(uuid,text,numeric,integer),
 public.accept_offer_p2p_core(uuid,integer),public.buy_position_p2p_core(uuid),
 public.list_position_p2p_core(uuid,numeric,integer),
 public.create_market_p2p_core(text,text,text,timestamptz,uuid[]),
 public.settle_market_p2p_core(uuid,uuid) from public,anon,authenticated;

create function public.place_offer(p_outcome uuid,p_side text,p_odds numeric,p_stake integer)
returns uuid language plpgsql security definer set search_path='' as $$
begin
 if p_side is null or p_side not in ('back','lay') or p_odds is null or
 p_odds::text in ('NaN','Infinity','-Infinity') or p_odds<=1 or p_odds>1000 or
 p_odds<>round(p_odds,2) or p_stake is null or p_stake<1 or p_stake>1000000 then
  raise exception using errcode='BM002',message='Oferta inválida';end if;
 perform public.lock_trading_market((select market_id from public.outcomes where id=p_outcome));
 return public.place_offer_p2p_core(p_outcome,p_side,p_odds,p_stake);
end $$;
create function public.accept_offer(p_offer uuid,p_stake integer)
returns uuid language plpgsql security definer set search_path='' as $$
begin
 if p_stake is null or p_stake<1 or p_stake>1000000 then
  raise exception using errcode='BM002',message='Stake inválida';end if;
 perform public.lock_trading_market((select market_id from public.offers where id=p_offer));
 return public.accept_offer_p2p_core(p_offer,p_stake);
end $$;
create function public.buy_position(p_listing uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform public.lock_trading_market((select p.market_id from public.positions p
  join public.listings l on l.position_id=p.id where l.id=p_listing));
 perform public.buy_position_p2p_core(p_listing);
end $$;
create function public.list_position(p_position uuid,p_price numeric,p_stake integer)
returns uuid language plpgsql security definer set search_path='' as $$
begin
 if p_price is null or p_price::text in ('NaN','Infinity','-Infinity') then
  raise exception using errcode='BM002',message='Preço inválido';end if;
 perform public.lock_trading_market((select market_id from public.positions where id=p_position));
 return public.list_position_p2p_core(p_position,p_price,p_stake);
end $$;
-- Recompile the legacy overload against the guarded three-argument function.
create or replace function public.list_position(p_position uuid,p_price numeric)
returns uuid language sql security definer set search_path='' as $$
 select public.list_position(p_position,p_price,null::integer)
$$;
create or replace function public.cancel_offer(p_offer uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_offer public.offers%rowtype;v_release numeric;
begin
 if auth.uid() is null then raise exception using errcode='42501',message='Não autenticado';end if;
 perform pg_advisory_xact_lock(941003);
 -- Cancellation is also allowed after the cut-off, to return unmatched reserves.
 perform 1 from public.markets where id=(select market_id from public.offers where id=p_offer) for update;
 select * into v_offer from public.offers where id=p_offer for update;
 if not found or v_offer.owner_id<>auth.uid() then raise exception using errcode='42501',message='Não permitido';end if;
 if v_offer.state='cancelled' then return;end if;
 if v_offer.state<>'open' then raise exception 'Oferta indisponível';end if;
 v_release:=case when v_offer.side='back' then v_offer.stake_remaining else round(v_offer.stake_remaining*(v_offer.odds-1),2) end;
 update public.offers set state='cancelled',stake_remaining=0 where id=p_offer;
 perform public.transfer_coins(auth.uid(),v_release,-v_release,'cancel_offer',p_offer::text);
end $$;

-- New markets declare the period, instead of accepting an unrelated winner later.
-- No new snapshot modality or automatic recurrence is introduced here (#1/#11).
create function public.create_competition_market(p_title text,p_championship uuid,p_sprint uuid,p_category text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_kind text;v_cutoff timestamptz;v_market uuid;v_competitors uuid[];
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 perform pg_advisory_xact_lock(941001);
 if p_sprint is null then
  select 'annual',ends_at into v_kind,v_cutoff from public.championships where id=p_championship and state='open';
 else
  select s.kind,s.ends_at into v_kind,v_cutoff from public.sprints s
   join public.championships c on c.id=s.championship_id
   where s.id=p_sprint and s.championship_id=p_championship and s.state='open' and c.state='open';
 end if;
 if v_cutoff is null or v_cutoff<=clock_timestamp() or p_title is null or p_category is null then
  raise exception using errcode='BM003',message='Período inválido ou fechado';end if;
 select array_agg(id order by id) into v_competitors from public.competitors where joined_at<=clock_timestamp();
 v_market:=public.create_market_p2p_core(p_title,v_kind,p_category,v_cutoff,v_competitors);
 update public.markets set championship_id=p_championship,sprint_id=p_sprint where id=v_market;
 return v_market;
end $$;
-- Old clients cannot accidentally create more unbound markets.
create function public.create_market(p_title text,p_kind text,p_category text,p_closes_at timestamptz,p_competitors uuid[])
returns uuid language plpgsql security definer set search_path='' as $$
begin raise exception using errcode='BM003',message='Seleciona o período do campeonato na interface atualizada';end $$;

create function public.get_market_resolution(p_market uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_market public.markets%rowtype;v_validation public.competition_validations%rowtype;
 v_rows jsonb;v_winner uuid;v_count integer;v_target numeric;v_status text;
begin
 if auth.uid() is null then raise exception using errcode='42501',message='Não autenticado';end if;
 select * into v_market from public.markets where id=p_market;
 if not found then raise exception using errcode='BM003',message='Mercado inválido';end if;
 if v_market.state='settled' then
  return jsonb_build_object('status','settled','winner_outcome_id',v_market.winner_outcome_id);
 end if;
 if v_market.championship_id is null then v_status:='unlinked';
 else
  select * into v_validation from public.competition_validations where championship_id=v_market.championship_id
   and sprint_id is not distinct from v_market.sprint_id;
  if v_validation.id is null then v_status:='awaiting_validation';
  elsif not exists(select 1 from public.competition_captures
   where id=v_validation.end_capture_id and cutoff_at=v_market.closes_at) then v_status:='period_mismatch';
  else
   v_rows:=v_validation.rows;
   if exists(select 1 from jsonb_array_elements(v_rows) r where r->>'status'<>'complete' or r->>'value' is null) then
    v_status:='incomplete';
   elsif exists(
    (select (r->>'competitor_id')::uuid from jsonb_array_elements(v_rows) r
     except select competitor_id from public.outcomes where market_id=p_market)
    union all
    (select competitor_id from public.outcomes where market_id=p_market
     except select (r->>'competitor_id')::uuid from jsonb_array_elements(v_rows) r)
   ) then v_status:='universe_changed';
   else
    -- rank() preserves ties (1,1,3); an absent second place is not invented.
    if v_market.category='last' then
     select min((r->>'value')::numeric) into v_target from jsonb_array_elements(v_rows) r;
    else
     select (r->>'value')::numeric into v_target from jsonb_array_elements(v_rows) r
      where (r->>'place')::integer=case when v_market.category='winner' then 1 else 2 end limit 1;
    end if;
    select count(*),min(o.id::text)::uuid into v_count,v_winner
     from jsonb_array_elements(v_rows) r join public.outcomes o
      on o.market_id=p_market and o.competitor_id=(r->>'competitor_id')::uuid
     where (r->>'value')::numeric=v_target;
    v_status:=case when v_count=1 then 'ready' else 'tie_unsupported' end;
   end if;
  end if;
 end if;
 return jsonb_build_object('status',v_status,'validation_id',v_validation.id,
  'winner_outcome_id',case when v_status='ready' then v_winner end,
  'criterion',case when v_market.kind='annual' then 'annual_ytd' else 'sprint_delta_start_end' end);
end $$;

create function public.settle_market(p_market uuid,p_winner uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_market public.markets%rowtype;v_result jsonb;
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 perform pg_advisory_xact_lock(941003);
 select * into v_market from public.markets where id=p_market for update;
 if not found then raise exception using errcode='BM003',message='Mercado inválido';end if;
 -- Retrying a committed request is safe; a different winner is never accepted.
 if v_market.state='settled' then
  if p_winner is not null and p_winner=v_market.winner_outcome_id and
   exists(select 1 from public.market_resolutions where market_id=p_market and winner_outcome_id=p_winner) then return;end if;
  raise exception using errcode='BM004',message='Resultado imutável ou liquidação antiga';
 end if;
 if v_market.state<>'open' or clock_timestamp()<v_market.closes_at then
  raise exception using errcode='BM001',message='Mercado ainda não pode liquidar';end if;
 v_result:=public.get_market_resolution(p_market);
 if v_result->>'status'<>'ready' then
  raise exception using errcode='BM004',message='Liquidação bloqueada: '||(v_result->>'status');end if;
 if p_winner is null or p_winner<>(v_result->>'winner_outcome_id')::uuid then
  raise exception using errcode='BM004',message='O resultado tem de corresponder à classificação validada';end if;
 perform public.settle_market_p2p_core(p_market,p_winner);
 insert into public.market_resolutions(market_id,validation_id,winner_outcome_id,resolved_by)
  values(p_market,(v_result->>'validation_id')::uuid,p_winner,auth.uid());
end $$;

revoke all on function public.lock_trading_market(uuid),public.place_offer(uuid,text,numeric,integer),
 public.accept_offer(uuid,integer),public.buy_position(uuid),public.list_position(uuid,numeric,integer),
 public.create_market(text,text,text,timestamptz,uuid[]),public.create_competition_market(text,uuid,uuid,text),
 public.get_market_resolution(uuid),public.settle_market(uuid,uuid) from public,anon,authenticated;
grant execute on function public.place_offer(uuid,text,numeric,integer),public.accept_offer(uuid,integer),
 public.buy_position(uuid),public.list_position(uuid,numeric,integer),
 public.create_market(text,text,text,timestamptz,uuid[]),public.create_competition_market(text,uuid,uuid,text),
 public.get_market_resolution(uuid),public.settle_market(uuid,uuid) to authenticated;
commit;
