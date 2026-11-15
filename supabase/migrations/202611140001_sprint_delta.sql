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
