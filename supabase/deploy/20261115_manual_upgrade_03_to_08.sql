-- BetCoins - manual upgrade, existing Supabase project, 2026-11-15
-- Applies migrations 03 through 08 ONLY. Never use on a fresh/empty database.
-- Intended for Supabase SQL Editor; paste and run the ENTIRE file once.
-- Do NOT run the 20261115 baseline or migrations 01/02 here.
-- All statements execute in ONE PostgreSQL transaction.
-- If an error occurs, nothing from this script is committed.
-- Source files are copied verbatim from the repository's main branch.

BEGIN;

DO $preflight$
BEGIN
 IF to_regclass('public.wallets') IS NULL
   OR to_regclass('public.ledger') IS NULL
   OR to_regclass('public.positions') IS NULL
   OR to_regclass('public.sprints') IS NULL
   OR to_regclass('public.sprint_scores') IS NULL
   OR to_regprocedure('public.get_sprint_rankings(uuid)') IS NULL
 THEN
  RAISE EXCEPTION 'Preflight: schema base ou sprints em falta; não aplicar upgrade incremental';
 END IF;
 IF EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='positions' AND column_name='cost_basis')
  OR to_regclass('public.position_sales') IS NOT NULL
  OR to_regprocedure('public.reconcile_wallets()') IS NOT NULL
  OR to_regprocedure('public.get_spectator_rankings(timestamptz)') IS NOT NULL
  OR to_regprocedure('public.list_position(uuid,numeric,integer)') IS NOT NULL
  OR to_regclass('public.position_settlements') IS NOT NULL
 THEN
  RAISE EXCEPTION 'Preflight: atualização já iniciada/aplicada; rever estado antes de repetir';
 END IF;
END
$preflight$;

-- >>> MIGRATION 3: 202611140001_sprint_delta.sql
-- Follow-up migration: existing sprint rankings used compounded returns.
-- BetCoins period-gain bets measure the arithmetic YTD difference in percentage points.
-- Idempotent replace; no historical data or snapshots are rewritten.
create or replace function public.get_sprint_rankings(p_sprint uuid)
returns table(competitor_id uuid,nickname text,start_ytd numeric,end_ytd numeric,return_pct numeric)
language sql stable security definer set search_path='' as $$
 select c.id,p.nickname,a.ytd,b.ytd,round(b.ytd-a.ytd,4)
 from public.competitors c
 join public.profiles p on p.id=c.id
 join public.sprint_scores a on a.sprint_id=p_sprint and a.phase='start' and a.competitor_id=c.id
 join public.sprint_scores b on b.sprint_id=p_sprint and b.phase='end' and b.competitor_id=c.id
 order by 5 desc,c.id
$$;
revoke all on function public.get_sprint_rankings(uuid) from public,anon,authenticated;
grant execute on function public.get_sprint_rankings(uuid) to authenticated;
-- <<< END MIGRATION 3

-- >>> MIGRATION 4: 202611140002_position_cost_basis.sql
-- Position secondary-market accounting. Additive migration; review before remote application.
-- Economic acquisition cost is distinct from the collateral already reserved in wallets.

alter table public.positions add column cost_basis numeric(18,2);
-- Existing positions are originally matched trades, unless already resold in the MVP.
-- Reconstruct the current holder's basis using their most recent completed listing purchase
-- whenever possible; otherwise use the original stake (BACK) or liability (LAY).
update public.positions p
set cost_basis = coalesce(
 (select l.price from public.listings l
  where l.position_id=p.id and l.state='sold' and l.sold_to=p.owner_id
  order by l.sold_at desc nulls last,l.created_at desc limit 1),
 case when p.side='back' then p.stake else p.liability end
);
alter table public.positions alter column cost_basis set not null;
alter table public.positions add constraint positions_cost_basis_nonnegative check(cost_basis>=0);

-- Legacy matching RPCs insert positions without explicitly supplying cost_basis.
-- Capture the original exposure automatically for new matched BACK/LAY positions.
create or replace function public.initialize_position_cost_basis()
returns trigger language plpgsql set search_path='' as $$
begin
 if new.cost_basis is null then
  new.cost_basis := case when new.side='back' then new.stake else new.liability end;
 end if;
 return new;
end $$;
create trigger positions_initial_cost_basis
before insert on public.positions
for each row execute function public.initialize_position_cost_basis();


-- Completed sales are immutable records of price, owner and the seller's economic result.
create table public.position_sales (
 listing_id uuid primary key references public.listings(id),
 position_id uuid not null references public.positions(id),
 seller_id uuid not null references public.wallets(owner_id),
 buyer_id uuid not null references public.wallets(owner_id),
 seller_cost_basis numeric(18,2) not null check(seller_cost_basis>=0),
 sale_price numeric(18,2) not null check(sale_price>0),
 realized_pnl numeric(18,2) generated always as (sale_price-seller_cost_basis) stored,
 traded_at timestamptz not null default now(),
 check(seller_id<>buyer_id)
);
create index position_sales_seller_idx on public.position_sales(seller_id,traded_at desc);
create index position_sales_buyer_idx on public.position_sales(buyer_id,traded_at desc);
alter table public.position_sales enable row level security;
create policy position_sales_participants_read on public.position_sales
 for select to authenticated
 using(seller_id=(select auth.uid()) or buyer_id=(select auth.uid()));
revoke all on public.position_sales from public,anon,authenticated;
grant select on public.position_sales to authenticated;

-- Historical resales completed before this migration have no immutable cost-basis record.
-- Preserve their actual prices and order but do not fabricate prior cost bases or P&L.
-- The listing history remains available; new sales are recorded prospectively.

create or replace function public.buy_position(p_listing uuid)
returns void language plpgsql security definer set search_path='' as $$
declare
 v_listing public.listings%rowtype;
 v_position public.positions%rowtype;
 v_collateral numeric;
begin
 if auth.uid() is null then raise exception 'Não autenticado'; end if;
 perform 1 from public.markets
  where id=(select p.market_id from public.positions p
    join public.listings l on l.position_id=p.id where l.id=p_listing)
  and state='open' and closes_at>now() for update;
 if not found then raise exception 'Mercado fechado'; end if;
 select * into v_listing from public.listings where id=p_listing for update;
 if not found or v_listing.state<>'open' or v_listing.seller_id=auth.uid() then
  raise exception 'Oferta indisponível';
 end if;
 select * into v_position from public.positions where id=v_listing.position_id for update;
 if not found or v_position.status<>'open' or v_position.owner_id<>v_listing.seller_id then
  raise exception 'Posição indisponível';
 end if;
 if not exists(select 1 from public.markets
  where id=v_position.market_id and state='open' and closes_at>now()) then
  raise exception 'Mercado fechado';
 end if;
 v_collateral:=case when v_position.side='back' then v_position.stake else v_position.liability end;
 -- The existing collateral moves to the buyer; the listing price is consideration,
 -- not a replacement for collateral or a new mint.
 perform public.transfer_coins(auth.uid(),-v_listing.price,v_collateral,'buy_position',p_listing::text);
 perform public.transfer_coins(v_listing.seller_id,v_listing.price,-v_collateral,'sell_position',p_listing::text);
 insert into public.position_sales(
  listing_id,position_id,seller_id,buyer_id,seller_cost_basis,sale_price
 ) values (
  p_listing,v_position.id,v_listing.seller_id,auth.uid(),v_position.cost_basis,v_listing.price
 );
 update public.positions
  set owner_id=auth.uid(),cost_basis=v_listing.price
  where id=v_position.id;
 update public.listings
  set state='sold',sold_to=auth.uid(),sold_at=now()
  where id=p_listing;
end $$;
revoke all on function public.buy_position(uuid) from public,anon,authenticated;
grant execute on function public.buy_position(uuid) to authenticated;
-- <<< END MIGRATION 4

-- >>> MIGRATION 5: 202611150001_wallet_reconciliation.sql
-- Issue #4: recover missed weekly grants and reconcile wallet balances with the ledger.
-- Additive migration: does not issue grants or change existing balances on application.
-- Dates are UTC, with ISO weeks starting on Monday.
create or replace function public.grant_weekly(p_week date default null)
returns integer language plpgsql security definer set search_path='' as $$
declare
 v_start date;
 v_last date;
 v_owner uuid;
 v_week date;
 v_count integer := 0;
 v_registered date;
begin
 if not public.is_admin() then raise exception 'Sem permissão'; end if;
 select min(starts_at) at time zone 'UTC'
 into v_start
 from public.championships
 where state='open' and starts_at<=now() and ends_at>=now();
 if v_start is null then raise exception 'Não existe campeonato ativo'; end if;
 v_start := date_trunc('week',v_start::timestamp)::date;
 v_last := date_trunc('week',now() at time zone 'UTC')::date;
 if p_week is not null and (p_week<>date_trunc('week',p_week::timestamp)::date or p_week<v_start or p_week>v_last) then
  raise exception 'Semana fora do campeonato ou no futuro';
 end if;

 -- Grant only to users who are spectators now. Registration date is the
 -- earliest eligible week; no credits for weeks before account creation.
 for v_owner,v_registered in
  select w.owner_id,date_trunc('week',p.created_at at time zone 'UTC')::date
  from public.wallets w
  join public.profiles p on p.id=w.owner_id
  where not exists(select 1 from public.competitors c where c.id=w.owner_id)
  order by w.owner_id
 loop
  for v_week in
   select gs::date
   from generate_series(
    greatest(v_start,v_registered)::timestamp,
    (case when p_week is null then v_last else p_week end)::timestamp,
    interval '7 days'
   ) as gs
   where p_week is null or gs::date=p_week
  loop
   insert into public.weekly_grants(owner_id,week_start)
   values(v_owner,v_week) on conflict do nothing;
   if found then
    perform public.transfer_coins(v_owner,1000,0,'weekly_grant',v_week::text);
    update public.wallets set total_issued=total_issued+1000 where owner_id=v_owner;
    v_count:=v_count+1;
   end if;
  end loop;
 end loop;
 return v_count;
end $$;
revoke all on function public.grant_weekly(date) from public,anon,authenticated;
grant execute on function public.grant_weekly(date) to authenticated;

-- Read-only reconciliation: no automatic adjustment of economic balances.
-- Each owner is checked independently; total issued must match issuance entries.
create or replace function public.reconcile_wallets()
returns table(
 owner_id uuid,
 nickname text,
 actual_available numeric,
 ledger_available numeric,
 available_difference numeric,
 actual_reserved numeric,
 ledger_reserved numeric,
 reserved_difference numeric,
 actual_issued numeric,
 ledger_issued numeric,
 issued_difference numeric,
 balanced boolean
)
language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Sem permissão'; end if;
 return query
 select w.owner_id,p.nickname,
  w.available,coalesce(l.available_total,0),
  w.available-coalesce(l.available_total,0),
  w.reserved,coalesce(l.reserved_total,0),
  w.reserved-coalesce(l.reserved_total,0),
  w.total_issued,coalesce(l.issued_total,0),
  w.total_issued-coalesce(l.issued_total,0),
  w.available=coalesce(l.available_total,0)
  and w.reserved=coalesce(l.reserved_total,0)
  and w.total_issued=coalesce(l.issued_total,0)
 from public.wallets w
 join public.profiles p on p.id=w.owner_id
 left join lateral (
  select sum(e.available_delta) as available_total,
   sum(e.reserved_delta) as reserved_total,
   sum(case when e.reason in ('initial_grant','weekly_grant')
    then e.available_delta else 0 end) as issued_total
  from public.ledger e where e.owner_id=w.owner_id
 ) l on true
 order by p.nickname,w.owner_id;
end $$;
revoke all on function public.reconcile_wallets() from public,anon,authenticated;
grant execute on function public.reconcile_wallets() to authenticated;
-- <<< END MIGRATION 5

-- >>> MIGRATION 6: 202611150002_spectator_rankings.sql
-- #7: reproducible, ledger-based spectator rankings (book value, not market value).
-- Public results expose aggregate spectator metrics, never private order/trade details.
-- No direct balance writes or marks at a guessed price.
create or replace function public.get_spectator_rankings(p_as_of timestamptz default null)
returns table(
 owner_id uuid, nickname text, available numeric, reserved numeric,
 issued numeric, wealth numeric, relative_pct numeric,
 realized_resale_pnl numeric, open_positions bigint, exposure numeric,
 valuation_status text
)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Não autenticado'; end if;
 if p_as_of is not null and p_as_of>now() then
  raise exception 'A data da classificação não pode estar no futuro';
 end if;
 return query
 select w.owner_id,p.nickname,
   case when p_as_of is null then w.available else coalesce(h.available,0) end,
   case when p_as_of is null then w.reserved else coalesce(h.reserved,0) end,
   case when p_as_of is null then w.total_issued else coalesce(h.issued,0) end,
   (case when p_as_of is null then w.available+w.reserved
     else coalesce(h.available,0)+coalesce(h.reserved,0) end) as wealth,
   case when (case when p_as_of is null then w.total_issued else coalesce(h.issued,0) end)>0
    then round(
      100*((case when p_as_of is null then w.available+w.reserved
        else coalesce(h.available,0)+coalesce(h.reserved,0) end)
       -(case when p_as_of is null then w.total_issued else coalesce(h.issued,0) end))
      / (case when p_as_of is null then w.total_issued else coalesce(h.issued,0) end),2)
    else null end,
   coalesce(s.realized_pnl,0),
   case when p_as_of is null then coalesce(pos.position_count,0) else null end,
   case when p_as_of is null then coalesce(pos.collateral,0) else null end,
   'contabilistico_sem_cotacao'::text
 from public.wallets w
 join public.profiles p on p.id=w.owner_id
 left join lateral (
  select sum(e.available_delta) as available,
         sum(e.reserved_delta) as reserved,
         sum(case when e.reason in ('initial_grant','weekly_grant')
              then e.available_delta else 0 end) as issued
  from public.ledger e
  where e.owner_id=w.owner_id and e.created_at<=p_as_of
 ) h on p_as_of is not null
 left join lateral (
  select sum(ps.realized_pnl) as realized_pnl
  from public.position_sales ps
  where ps.seller_id=w.owner_id
    and (p_as_of is null or ps.traded_at<=p_as_of)
 ) s on true
 left join lateral (
  select count(*) as position_count,
         sum(case when op.side='back' then op.stake else op.liability end) as collateral
  from public.positions op
  where op.owner_id=w.owner_id and op.status='open'
 ) pos on p_as_of is null
 where (p_as_of is null or p.created_at<=p_as_of)
   and not exists(
    select 1 from public.competitors c
    where c.id=w.owner_id and (p_as_of is null or c.joined_at<=p_as_of)
   )
 order by 6 desc,p.nickname,w.owner_id;
end $$;
revoke all on function public.get_spectator_rankings(timestamptz) from public,anon,authenticated;
grant execute on function public.get_spectator_rankings(timestamptz) to authenticated;
-- <<< END MIGRATION 6

-- >>> MIGRATION 7: 202611150003_partial_resale.sql
-- #6: exact partial resale through indivisible BACK/LAY trade slices.
-- No currency is issued or removed. Split happens inside the atomic purchase transaction.
-- A listing may represent the whole position or an exact stake/liability slice.

alter table public.listings
 add column requested_stake integer check(requested_stake>0);

alter table public.positions
 add column parent_position_id uuid references public.positions(id);

-- A price is exact to cents, never silently rounded.
create or replace function public.list_position(
 p_position uuid, p_price numeric, p_stake integer
) returns uuid language plpgsql security definer set search_path='' as $$
declare
 v_position public.positions%rowtype;
 v_opposite public.positions%rowtype;
 v_listing uuid;
 v_slice_liability numeric;
begin
 if auth.uid() is null then raise exception 'Não autenticado'; end if;
 if p_price is null or p_price<=0 or p_price>100000000 or round(p_price,2)<>p_price then
  raise exception 'Preço inválido: usa no máximo duas casas decimais';
 end if;
 perform 1 from public.markets
  where id=(select market_id from public.positions where id=p_position)
    and state='open' and closes_at>now()
  for update;
 if not found then raise exception 'Mercado fechado'; end if;
 select * into v_position from public.positions where id=p_position for update;
 if not found or v_position.owner_id<>auth.uid() or v_position.status<>'open' then
  raise exception 'Posição indisponível';
 end if;
 if p_stake is null or p_stake=v_position.stake then
  insert into public.listings(position_id,seller_id,price,requested_stake)
  values(p_position,auth.uid(),p_price,v_position.stake) returning id into v_listing;
  return v_listing;
 end if;
 if p_stake<=0 or p_stake>=v_position.stake then raise exception 'Lote inválido'; end if;
 select * into v_opposite from public.positions
  where trade_id=v_position.trade_id and side<>v_position.side
  for update;
 if not found or v_opposite.status<>'open' then raise exception 'Contraparte indisponível'; end if;
 if exists(select 1 from public.listings
  where position_id=v_opposite.id and state='open') then
  raise exception 'A contraparte já está anunciada';
 end if;
 v_slice_liability := v_position.liability*p_stake/v_position.stake;
 if round(v_slice_liability,2)<>v_slice_liability
  or trunc(v_slice_liability)<>v_slice_liability
  or round(v_position.cost_basis*p_stake/v_position.stake,2)<>(v_position.cost_basis*p_stake/v_position.stake)
  or round(v_opposite.cost_basis*p_stake/v_position.stake,2)<>(v_opposite.cost_basis*p_stake/v_position.stake) then
  raise exception 'Lote não divisível: stake, responsabilidade e custo precisam de cêntimos exatos';
 end if;
 insert into public.listings(position_id,seller_id,price,requested_stake)
 values(p_position,auth.uid(),p_price,p_stake) returning id into v_listing;
 return v_listing;
end $$;

-- Keep the two-argument API for existing clients (full resale only).
create or replace function public.list_position(p_position uuid,p_price numeric)
returns uuid language sql security definer set search_path='' as $$
 select public.list_position(p_position,p_price,null::integer)
$$;

create or replace function public.buy_position(p_listing uuid)
returns void language plpgsql security definer set search_path='' as $$
declare
 v_listing public.listings%rowtype;
 v_position public.positions%rowtype;
 v_opposite public.positions%rowtype;
 v_trade public.trades%rowtype;
 v_piece_trade uuid;
 v_bought_position uuid;
 v_piece_stake integer;
 v_piece_liability numeric;
 v_seller_basis numeric;
 v_opposite_basis numeric;
 v_collateral numeric;
begin
 if auth.uid() is null then raise exception 'Não autenticado'; end if;
 perform 1 from public.markets
  where id=(select p.market_id from public.positions p
    join public.listings l on l.position_id=p.id where l.id=p_listing)
   and state='open' and closes_at>now()
  for update;
 if not found then raise exception 'Mercado fechado'; end if;
 select * into v_listing from public.listings where id=p_listing for update;
 if not found or v_listing.state<>'open' or v_listing.seller_id=auth.uid() then
  raise exception 'Anúncio indisponível';
 end if;
 select * into v_position from public.positions where id=v_listing.position_id for update;
 if not found or v_position.status<>'open' or v_position.owner_id<>v_listing.seller_id then
  raise exception 'Posição indisponível';
 end if;
 v_piece_stake:=coalesce(v_listing.requested_stake,v_position.stake);
 if v_piece_stake<=0 or v_piece_stake>v_position.stake then
  raise exception 'Lote já não disponível';
 end if;
 v_piece_liability:=v_position.liability*v_piece_stake/v_position.stake;
 if round(v_piece_liability,2)<>v_piece_liability or
    (v_piece_stake<v_position.stake and trunc(v_piece_liability)<>v_piece_liability) then
  raise exception 'Responsabilidade não divisível em moedas inteiras';
 end if;
 v_seller_basis:=v_position.cost_basis*v_piece_stake/v_position.stake;
 if round(v_seller_basis,2)<>v_seller_basis then raise exception 'Custo não divisível'; end if;
 v_bought_position:=v_position.id;

 if v_piece_stake<v_position.stake then
  -- Both sides of one trade must split identically for settlement to remain valid.
  select * into v_opposite from public.positions
   where trade_id=v_position.trade_id and side<>v_position.side for update;
  if not found or v_opposite.status<>'open' then raise exception 'Contraparte indisponível'; end if;
  if exists(select 1 from public.listings
   where position_id=v_opposite.id and state='open') then
   raise exception 'Contraparte anunciada: não é possível dividir';
  end if;
  v_opposite_basis:=v_opposite.cost_basis*v_piece_stake/v_position.stake;
  if round(v_opposite_basis,2)<>v_opposite_basis then
   raise exception 'Custo da contraparte não divisível';
  end if;
  select * into v_trade from public.trades where id=v_position.trade_id for update;
  if v_trade.settled_at is not null or v_trade.stake<>v_position.stake
    or v_trade.liability<>v_position.liability then
    raise exception 'Trade indisponível para divisão';
  end if;
  insert into public.trades(market_id,outcome_id,offer_id,odds,stake,liability,created_at)
   values(v_trade.market_id,v_trade.outcome_id,v_trade.offer_id,v_trade.odds,
          v_piece_stake,v_piece_liability,v_trade.created_at)
   returning id into v_piece_trade;
  -- Keep the original trade/positions as the residual lot.
  update public.trades
   set stake=v_trade.stake-v_piece_stake,liability=v_trade.liability-v_piece_liability
   where id=v_trade.id;
  update public.positions set
   stake=v_position.stake-v_piece_stake,
   liability=v_position.liability-v_piece_liability,
   cost_basis=v_position.cost_basis-v_seller_basis
   where id=v_position.id;
  update public.positions set
   stake=v_opposite.stake-v_piece_stake,
   liability=v_opposite.liability-v_piece_liability,
   cost_basis=v_opposite.cost_basis-v_opposite_basis
   where id=v_opposite.id;
  insert into public.positions(trade_id,owner_id,side,market_id,outcome_id,stake,liability,cost_basis,parent_position_id)
   values(v_piece_trade,v_listing.seller_id,v_position.side,v_position.market_id,
          v_position.outcome_id,v_piece_stake,v_piece_liability,v_seller_basis,v_position.id)
   returning id into v_bought_position;
  insert into public.positions(trade_id,owner_id,side,market_id,outcome_id,stake,liability,cost_basis,parent_position_id)
   values(v_piece_trade,v_opposite.owner_id,v_opposite.side,v_opposite.market_id,
          v_opposite.outcome_id,v_piece_stake,v_piece_liability,v_opposite_basis,v_opposite.id);
 end if;

 v_collateral:=case when v_position.side='back' then v_piece_stake else v_piece_liability end;
 -- A buyer must have liquid balance for the ask. Reserved collateral moves unchanged.
 perform public.transfer_coins(auth.uid(),-v_listing.price,v_collateral,'buy_position',p_listing::text);
 perform public.transfer_coins(v_listing.seller_id,v_listing.price,-v_collateral,'sell_position',p_listing::text);
 insert into public.position_sales(
   listing_id,position_id,seller_id,buyer_id,seller_cost_basis,sale_price
 ) values(
   p_listing,v_bought_position,v_listing.seller_id,auth.uid(),v_seller_basis,v_listing.price
 );
 update public.positions set owner_id=auth.uid(),cost_basis=v_listing.price
  where id=v_bought_position;
 update public.listings set state='sold',sold_to=auth.uid(),sold_at=now()
  where id=p_listing;
end $$;

-- The published marketplace must display the slice, not the entire source position.
create or replace function public.get_active_listings()
returns table(id uuid,position_id uuid,seller_id uuid,price numeric,state text,created_at timestamptz,
 side text,market_id uuid,outcome_id uuid,stake integer,liability numeric,outcome_label text,market_title text)
language sql stable security definer set search_path='' as $$
 select l.id,l.position_id,l.seller_id,l.price,l.state,l.created_at,
  p.side,p.market_id,p.outcome_id,coalesce(l.requested_stake,p.stake),
  round(p.liability*coalesce(l.requested_stake,p.stake)/p.stake,2),
  o.label,m.title
 from public.listings l
 join public.positions p on p.id=l.position_id
 join public.outcomes o on o.id=p.outcome_id
 join public.markets m on m.id=p.market_id
 where l.state='open' and p.status='open' and m.state='open' and m.closes_at>now()
 order by l.created_at desc
$$;

revoke all on function public.list_position(uuid,numeric,integer) from public,anon,authenticated;
grant execute on function public.list_position(uuid,numeric,integer) to authenticated;
revoke all on function public.list_position(uuid,numeric) from public,anon,authenticated;
grant execute on function public.list_position(uuid,numeric) to authenticated;
revoke all on function public.buy_position(uuid) from public,anon,authenticated;
grant execute on function public.buy_position(uuid) to authenticated;
revoke all on function public.get_active_listings() from public,anon,authenticated;
grant execute on function public.get_active_listings() to authenticated;
-- <<< END MIGRATION 7

-- >>> MIGRATION 8: 202611150004_position_settlement_pnl.sql
-- Issue #15: immutable economic result of final settlement (no wallet writes).
-- This migration must run after 202611150003_partial_resale.sql.
create table public.position_settlements (
 position_id uuid primary key references public.positions(id),
 owner_id uuid not null references public.wallets(owner_id),
 payoff numeric(18,2) not null check(payoff>=0),
 final_cost_basis numeric(18,2) not null check(final_cost_basis>=0),
 realized_pnl numeric(18,2) generated always as (payoff-final_cost_basis) stored,
 settled_at timestamptz not null
);
create index position_settlements_owner_idx
 on public.position_settlements(owner_id,settled_at desc);
alter table public.position_settlements enable row level security;
create policy position_settlements_owner_read on public.position_settlements
 for select to authenticated using(owner_id=(select auth.uid()));
revoke all on public.position_settlements from public,anon,authenticated;
grant select on public.position_settlements to authenticated;

-- Backfill already-settled positions without changing any balance.
-- Older positions may have an inferred acquisition basis from migration #18.
insert into public.position_settlements(position_id,owner_id,payoff,final_cost_basis,settled_at)
select p.id,p.owner_id,
 case when
   (p.side='back' and t.outcome_id=m.winner_outcome_id)
   or (p.side='lay' and t.outcome_id<>m.winner_outcome_id)
   then p.stake+p.liability else 0 end,
 p.cost_basis,t.settled_at
from public.positions p
join public.trades t on t.id=p.trade_id
join public.markets m on m.id=p.market_id
where p.status='settled' and t.settled_at is not null
 and m.state='settled' and m.winner_outcome_id is not null
on conflict(position_id) do nothing;

-- Preserve the battle-tested, atomic existing settlement logic.
-- Wrap it to record both economic legs in the same transaction.
alter function public.settle_market(uuid,uuid) rename to settle_market_economic_core;
revoke all on function public.settle_market_economic_core(uuid,uuid)
 from public,anon,authenticated;

create function public.settle_market(p_market uuid,p_winner uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Sem permissão'; end if;
 perform public.settle_market_economic_core(p_market,p_winner);
 insert into public.position_settlements(
   position_id,owner_id,payoff,final_cost_basis,settled_at
 )
 select p.id,p.owner_id,
   case when
     (p.side='back' and t.outcome_id=p_winner)
     or (p.side='lay' and t.outcome_id<>p_winner)
     then p.stake+p.liability else 0 end,
   p.cost_basis,t.settled_at
 from public.positions p
 join public.trades t on t.id=p.trade_id
 where p.market_id=p_market and p.status='settled'
   and t.settled_at is not null
 on conflict(position_id) do nothing;
end $$;
revoke all on function public.settle_market(uuid,uuid)
 from public,anon,authenticated;
grant execute on function public.settle_market(uuid,uuid) to authenticated;
-- <<< END MIGRATION 8

DO $postflight$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM information_schema.columns
  WHERE table_schema='public' AND table_name='positions' AND column_name='cost_basis')
 OR to_regclass('public.position_sales') IS NULL
 OR to_regprocedure('public.reconcile_wallets()') IS NULL
 OR to_regprocedure('public.get_spectator_rankings(timestamptz)') IS NULL
 OR to_regprocedure('public.list_position(uuid,numeric,integer)') IS NULL
 OR to_regclass('public.position_settlements') IS NULL
 THEN RAISE EXCEPTION 'Postflight: um dos objetos das migrações 04-08 está ausente'; END IF;
 IF position('round(b.ytd-a.ytd,4)' IN
    pg_get_functiondef('public.get_sprint_rankings(uuid)'::regprocedure))=0
 THEN RAISE EXCEPTION 'Postflight: cálculo ΔYTD ainda não está corrigido'; END IF;
END
$postflight$;

COMMIT;

SELECT 'OK - BetCoins 03..08 aplicadas' AS resultado;
