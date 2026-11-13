-- Sprint snapshots are authoritative when captured, and never inferred from a
-- competitor's latest score retroactively. The operator must validate boundaries.
create table public.sprints(
 id uuid primary key default gen_random_uuid(),
 championship_id uuid not null references public.championships(id),
 name text not null,
 kind text not null check(kind in ('weekly','monthly')),
 starts_at timestamptz not null,
 ends_at timestamptz not null,
 state text not null default 'open' check(state in ('open','closed')),
 check(ends_at>starts_at),
 unique(championship_id,kind,starts_at)
);
create table public.sprint_scores(
 sprint_id uuid not null references public.sprints(id),
 competitor_id uuid not null references public.competitors(id),
 phase text not null check(phase in ('start','end')),
 ytd numeric(12,4) not null check(ytd>=-100),
 captured_at timestamptz not null default now(),
 primary key(sprint_id,competitor_id,phase)
);
alter table public.sprints enable row level security;
alter table public.sprint_scores enable row level security;
create policy sprint_read on public.sprints for select to authenticated using(true);
create policy sprint_score_read on public.sprint_scores for select to authenticated using(true);
grant select on public.sprints,public.sprint_scores to authenticated;
create or replace function public.create_sprint(p_name text,p_kind text,p_start timestamptz,p_end timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_champ uuid;
begin
 if not public.is_admin() then raise exception 'Sem permissão';end if;
 if length(btrim(p_name)) not between 3 and 120 or p_kind not in ('weekly','monthly') or p_start is null or p_end is null or p_end<=p_start then raise exception 'Sprint inválido';end if;
 select id into v_champ from public.championships where state='open' and p_start>=starts_at and p_end<=ends_at;
 if v_champ is null then raise exception 'Sprint fora do campeonato';end if;
 insert into public.sprints(championship_id,name,kind,starts_at,ends_at)
 values(v_champ,btrim(p_name),p_kind,p_start,p_end) returning id into v_id;
 return v_id;
end $$;
create or replace function public.capture_sprint(p_sprint uuid,p_phase text)
returns integer language plpgsql security definer set search_path='' as $$
declare v_sprint public.sprints%rowtype;v_total integer;
begin
 if not public.is_admin() then raise exception 'Sem permissão';end if;
 if p_phase not in ('start','end') then raise exception 'Fase inválida';end if;
 select * into v_sprint from public.sprints where id=p_sprint for update;
 if not found or v_sprint.state<>'open' then raise exception 'Sprint fechado';end if;
 -- Snapshots must be taken within their capture windows and never overwritten.
 if p_phase='start' and (now()<v_sprint.starts_at or now()>=v_sprint.ends_at) then raise exception 'Fora do período';end if;
 if p_phase='end' and now()<v_sprint.ends_at then raise exception 'Sprint ainda em curso';end if;
 if exists(select 1 from public.sprint_scores where sprint_id=p_sprint and phase=p_phase) then raise exception 'Snapshot já capturado';end if;
 insert into public.sprint_scores(sprint_id,competitor_id,phase,ytd)
 select p_sprint,c.id,p_phase,c.ytd from public.competitors c;
 get diagnostics v_total=row_count;
 if p_phase='end' then update public.sprints set state='closed' where id=p_sprint;end if;
 return v_total;
end $$;
create or replace function public.get_sprint_rankings(p_sprint uuid)
returns table(competitor_id uuid,nickname text,start_ytd numeric,end_ytd numeric,return_pct numeric)
language sql stable security definer set search_path='' as $$
 select c.id,p.nickname,a.ytd,b.ytd,
 round(((1+b.ytd/100)/nullif(1+a.ytd/100,0)-1)*100,4)
 from public.competitors c
 join public.profiles p on p.id=c.id
 join public.sprint_scores a on a.sprint_id=p_sprint and a.phase='start' and a.competitor_id=c.id
 join public.sprint_scores b on b.sprint_id=p_sprint and b.phase='end' and b.competitor_id=c.id
 where a.ytd>-100
 order by 5 desc,c.id
$$;
revoke all on function public.create_sprint(text,text,timestamptz,timestamptz),
 public.capture_sprint(uuid,text),public.get_sprint_rankings(uuid) from public,anon,authenticated;
grant execute on function public.create_sprint(text,text,timestamptz,timestamptz),
 public.capture_sprint(uuid,text),public.get_sprint_rankings(uuid) to authenticated;
