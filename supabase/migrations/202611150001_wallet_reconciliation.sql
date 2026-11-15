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
