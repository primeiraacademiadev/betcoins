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
