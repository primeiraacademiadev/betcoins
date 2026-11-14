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
