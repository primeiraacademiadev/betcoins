-- #11: recurring definitions, audited 2026 calendar and idempotent generation.
-- Repository only. Requires migrations 01--11; never installs remotely.
begin;

-- NYSE cash-equity core sessions. Source checked 2026-11-16:
-- https://www.nyse.com/trade/hours-calendars
create table public.bet_calendar_sessions(
 session_date date primary key,closes_at timestamptz not null,
 source_url text not null default 'https://www.nyse.com/trade/hours-calendars'
);
insert into public.bet_calendar_sessions(session_date,closes_at)
select d::date,(d::date+case when d::date in ('2026-11-27','2026-12-24') then time '13:00' else time '16:00' end) at time zone 'America/New_York'
from generate_series(date '2026-01-01',date '2026-12-31',interval '1 day') d
where extract(isodow from d)<6 and d::date not in
 ('2026-01-01','2026-01-19','2026-02-16','2026-04-03','2026-05-25','2026-06-19','2026-07-03','2026-09-07','2026-11-26','2026-12-25');

create table public.bet_definitions(
 id uuid primary key default gen_random_uuid(),
 championship_id uuid not null references public.championships(id),
 kind text not null check(kind in ('annual','monthly','weekly')),
 mode text not null check(mode in ('snapshot_value','snapshot_delta_previous')),
 active boolean not null default true,created_at timestamptz not null default clock_timestamp(),
 unique(championship_id,kind,mode)
);
create table public.bet_occurrences(
 id uuid primary key default gen_random_uuid(),
 championship_id uuid not null references public.championships(id),
 kind text not null check(kind in ('annual','monthly','weekly')),
 period_key text not null,name text not null,starts_at timestamptz not null,ends_at timestamptz not null,
 sprint_id uuid unique references public.sprints(id),
 previous_occurrence_id uuid references public.bet_occurrences(id),
 check(ends_at>starts_at),check((kind='annual')=(sprint_id is null)),
 unique(championship_id,kind,period_key)
);
alter table public.markets add column definition_id uuid references public.bet_definitions(id),
 add column occurrence_id uuid references public.bet_occurrences(id),
 add check((definition_id is null)=(occurrence_id is null)),
 add unique(definition_id,occurrence_id,category);

alter table public.bet_calendar_sessions enable row level security;
alter table public.bet_definitions enable row level security;
alter table public.bet_occurrences enable row level security;
revoke all on public.bet_calendar_sessions,public.bet_definitions,public.bet_occurrences from public,anon,authenticated;
grant select on public.bet_calendar_sessions,public.bet_definitions,public.bet_occurrences to authenticated;
create policy calendar_session_read on public.bet_calendar_sessions for select to authenticated using(true);
create policy definition_read on public.bet_definitions for select to authenticated using(true);
create policy occurrence_read on public.bet_occurrences for select to authenticated using(true);
create trigger calendar_session_immutable before update or delete on public.bet_calendar_sessions for each row execute function public.reject_competition_rewrite();
create trigger occurrence_immutable before update or delete on public.bet_occurrences for each row execute function public.reject_competition_rewrite();

-- Pure calendar: no clock override is exposed by the generation RPC.
create function public.recurring_calendar(p_championship uuid,p_kind text)
returns table(period_key text,name text,starts_at timestamptz,ends_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare c public.championships%rowtype;
begin
 select * into c from public.championships where id=p_championship;
 if not found or c.starts_at<'2026-01-01T00:00:00Z' or c.ends_at>'2026-12-31T23:59:59Z' or c.ends_at<=c.starts_at
  or p_kind is null or p_kind not in ('annual','monthly','weekly') then
  raise exception using errcode='BR001',message='Calendário suportado apenas dentro do campeonato 2026';end if;
 if p_kind='annual' then
  return query select '2026'::text,'Anual 2026'::text,c.starts_at,c.ends_at;
 elsif p_kind='monthly' then
  return query with months as (
   select d,to_char(d,'YYYY-MM') as k,d at time zone 'Europe/Lisbon' as a,
    ((d+interval '1 month') at time zone 'Europe/Lisbon')-interval '1 microsecond' as b
   from generate_series(timestamp '2026-01-01',timestamp '2026-12-01',interval '1 month') d
  ) select k,'Mês '||k,greatest(a,c.starts_at),least(b,c.ends_at) from months
   where a<c.ends_at and b>c.starts_at order by d;
 else
  return query with weeks as (
   select date_trunc('week',session_date::timestamp) as w,max(closes_at) as b from public.bet_calendar_sessions group by 1
  ), boundaries as (
   select w,b,coalesce(lag(b) over(order by w)+interval '1 microsecond',c.starts_at) as a from weeks
  ) select to_char(w,'IYYY-"W"IW'),'Semana '||to_char(w,'IYYY-"W"IW'),greatest(a,c.starts_at),least(b,c.ends_at)
   from boundaries where a<c.ends_at and b>c.starts_at order by w;
 end if;
end $$;

create function public.prepare_bet_occurrences(p_championship uuid) returns integer
language plpgsql security definer set search_path='' as $$
declare k text;r record;s uuid;existing public.sprints%rowtype;prev uuid;added integer:=0;n integer;
begin
 foreach k in array array['annual','monthly','weekly'] loop
  prev:=null;
  for r in select * from public.recurring_calendar(p_championship,k) loop
   s:=null;
   if k<>'annual' then
    select * into existing from public.sprints where championship_id=p_championship and kind=k and starts_at=r.starts_at;
    if found then
     if existing.ends_at<>r.ends_at then raise exception using errcode='BR002',message='Sprint existente com calendário incompatível; revisão obrigatória';end if;
     s:=existing.id;
    else
     insert into public.sprints(championship_id,name,kind,starts_at,ends_at) values(p_championship,r.name,k,r.starts_at,r.ends_at) returning id into s;
    end if;
   end if;
   insert into public.bet_occurrences(championship_id,kind,period_key,name,starts_at,ends_at,sprint_id,previous_occurrence_id)
    values(p_championship,k,r.period_key,r.name,r.starts_at,r.ends_at,s,prev) on conflict(championship_id,kind,period_key) do nothing;
   get diagnostics n=row_count;added:=added+n;
   select id into prev from public.bet_occurrences where championship_id=p_championship and kind=k and period_key=r.period_key;
  end loop;
 end loop;
 return added;
end $$;

-- Internal only, also used by the admission trigger. The caller holds all locks.
create function public.generate_bet_markets(p_championship uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_def record;v_occ record;v_previous public.bet_occurrences%rowtype;ref jsonb;cat text;m uuid;
 v_added integer:=0;v_outcomes integer:=0;v_blocked integer:=0;n integer;v_calendar integer;
begin
 v_calendar:=public.prepare_bet_occurrences(p_championship);
 for v_def in select * from public.bet_definitions where championship_id=p_championship and active order by id loop
  for v_occ in select * from public.bet_occurrences where championship_id=p_championship and kind=v_def.kind order by starts_at loop
   -- Historical periods remain calendar entries. Never manufacture past bets.
   if v_occ.ends_at<=clock_timestamp() then continue;end if;
   if (select count(*) from public.competitors)<2 then v_blocked:=v_blocked+1;continue;end if;
   ref:=null;
   if v_def.mode='snapshot_delta_previous' then
    if v_occ.kind='annual' then ref:=public.get_previous_market_period(p_championship,null);
    else
     select * into v_previous from public.bet_occurrences where id=v_occ.previous_occurrence_id;
     if found then ref:=jsonb_build_object('championship_id',v_previous.championship_id,'sprint_id',v_previous.sprint_id,'ends_at',v_previous.ends_at);end if;
    end if;
    if ref->>'championship_id' is null then v_blocked:=v_blocked+1;continue;end if;
   end if;
   foreach cat in array array['winner','second','last'] loop
    if v_occ.ends_at<=clock_timestamp() then continue;end if;
    select id into m from public.markets where definition_id=v_def.id and occurrence_id=v_occ.id and category=cat;
    if m is null then
     -- No API fallback or inference of mode: period and previous END are explicit.
     insert into public.markets(title,kind,category,closes_at,championship_id,sprint_id,mode,
      previous_championship_id,previous_sprint_id,previous_closes_at,definition_id,occurrence_id)
     values(v_occ.name||' · '||case when v_def.mode='snapshot_value' then 'Valor no fecho' else 'Variação do fecho anterior' end||' · '||case cat when 'winner' then '1.º' when 'second' then '2.º' else 'Último' end,v_occ.kind,cat,v_occ.ends_at,p_championship,v_occ.sprint_id,v_def.mode,
      (ref->>'championship_id')::uuid,(ref->>'sprint_id')::uuid,(ref->>'ends_at')::timestamptz,v_def.id,v_occ.id) returning id into m;
     v_added:=v_added+1;
    end if;
   end loop;
  end loop;
 end loop;
 -- Append-only membership. Never touch offers/trades/positions or past universes.
 for m in select x.id from public.markets x join public.bet_definitions d on d.id=x.definition_id
   where d.championship_id=p_championship and d.active and x.state='open' and x.closes_at>clock_timestamp()
    and not exists(select 1 from public.market_classifications v where v.market_id=x.id)
   order by x.id for update of x loop
  if (select closes_at from public.markets where id=m)<=clock_timestamp() then continue;end if;
  insert into public.outcomes(market_id,competitor_id,label)
   select m,c.id,p.nickname from public.competitors c join public.profiles p on p.id=c.id
   where c.joined_at<=clock_timestamp() on conflict(market_id,competitor_id) do nothing;
  get diagnostics n=row_count;v_outcomes:=v_outcomes+n;
 end loop;
 return jsonb_build_object('new_occurrences',v_calendar,'new_markets',v_added,'new_outcomes',v_outcomes,'blocked_occurrences',v_blocked);
end $$;

create function public.get_bet_provisional_rankings(p_market uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare m public.markets%rowtype;cap uuid;result jsonb;
begin
 if auth.uid() is null then raise exception using errcode='42501',message='Não autenticado';end if;
 select * into m from public.markets where id=p_market;
 if not found or m.definition_id is null or m.state<>'open' or m.closes_at<=now() then
  return jsonb_build_object('status','historical','rows','[]'::jsonb);end if;
 if m.mode='snapshot_delta_previous' then
  select id into cap from public.competition_captures where championship_id=m.previous_championship_id
   and sprint_id is not distinct from m.previous_sprint_id and phase='end' and cutoff_at=m.previous_closes_at;
 end if;
 with inputs as (
  select o.competitor_id,o.label as nickname,c.updated_at,c.ytd as end_ytd,p.ytd as previous_ytd,
   case when m.mode='snapshot_value' then c.ytd else round(c.ytd-p.ytd,4) end as value
  from public.outcomes o join public.competitors c on c.id=o.competitor_id
   left join public.competition_capture_scores p on p.capture_id=cap and p.competitor_id=o.competitor_id
  where o.market_id=p_market
 ), rows as (
  select *,case when value is not null then rank() over(order by value desc nulls last) end as place from inputs
 ) select coalesce(jsonb_agg(to_jsonb(rows) order by value desc nulls last,competitor_id),'[]'::jsonb) into result from rows;
 return jsonb_build_object('status','provisional','mode',m.mode,'unit',case when m.mode='snapshot_value' then '%' else 'pp' end,
  'previous_capture_id',cap,'rows',result);
end $$;

create function public.configure_recurring_bet(p_championship uuid,p_kind text,p_mode text,p_active boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid;result jsonb;
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 if p_active is null or p_kind is null or p_kind not in ('annual','monthly','weekly') or p_mode is null or p_mode not in ('snapshot_value','snapshot_delta_previous') then
  raise exception using errcode='BR001',message='Definição inválida';end if;
 perform pg_advisory_xact_lock(941001);perform pg_advisory_xact_lock(941002);perform pg_advisory_xact_lock(941003);
 if not exists(select 1 from public.championships where id=p_championship and state='open') then raise exception using errcode='BR001',message='Campeonato fechado';end if;
 -- Validate supported dates even when pausing a new definition.
 perform 1 from public.recurring_calendar(p_championship,p_kind);
 insert into public.bet_definitions(championship_id,kind,mode,active) values(p_championship,p_kind,p_mode,p_active)
  on conflict(championship_id,kind,mode) do update set active=excluded.active returning id into v_id;
 result:=public.generate_bet_markets(p_championship);
 return result||jsonb_build_object('definition_id',v_id);
end $$;
create function public.regenerate_bet_markets(p_championship uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 perform pg_advisory_xact_lock(941001);perform pg_advisory_xact_lock(941002);perform pg_advisory_xact_lock(941003);
 if not exists(select 1 from public.championships where id=p_championship and state='open') then raise exception using errcode='BR001',message='Campeonato fechado';end if;
 return public.generate_bet_markets(p_championship);
end $$;

create function public.sync_admitted_bet_markets() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_champ uuid;
begin
 perform pg_advisory_xact_lock(941001);perform pg_advisory_xact_lock(941002);perform pg_advisory_xact_lock(941003);
 for v_champ in select distinct d.championship_id from public.bet_definitions d join public.championships c on c.id=d.championship_id
  where d.active and c.state='open' and c.ends_at>clock_timestamp() order by d.championship_id loop
  perform public.generate_bet_markets(v_champ);
 end loop;
 return new;
end $$;
create trigger admitted_recurring_markets after insert on public.competitors
 for each row execute function public.sync_admitted_bet_markets();

alter function public.lock_trading_market(uuid) rename to lock_trading_market_core;
revoke all on function public.lock_trading_market_core(uuid) from public,anon,authenticated;
create function public.lock_trading_market(p_market uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform public.lock_trading_market_core(p_market);
 if exists(select 1 from public.markets m join public.bet_definitions d on d.id=m.definition_id where m.id=p_market and not d.active) then
  raise exception using errcode='BR003',message='Bet recorrente suspensa';end if;
end $$;

revoke all on function public.recurring_calendar(uuid,text),public.prepare_bet_occurrences(uuid),public.generate_bet_markets(uuid),
 public.configure_recurring_bet(uuid,text,text,boolean),public.regenerate_bet_markets(uuid),public.sync_admitted_bet_markets(),public.lock_trading_market(uuid),public.get_bet_provisional_rankings(uuid)
 from public,anon,authenticated;
grant execute on function public.configure_recurring_bet(uuid,text,text,boolean),public.regenerate_bet_markets(uuid),public.get_bet_provisional_rankings(uuid) to authenticated;
commit;
