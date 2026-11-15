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
 order by wealth desc,p.nickname,w.owner_id;
end $$;
revoke all on function public.get_spectator_rankings(timestamptz) from public,anon,authenticated;
grant execute on function public.get_spectator_rankings(timestamptz) to authenticated;
