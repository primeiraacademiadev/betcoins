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
