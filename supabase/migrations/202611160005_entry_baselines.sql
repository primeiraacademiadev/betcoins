-- #11: immutable first YTD and effective mid-period participation.
-- Versioned only. Requires 01--13; no remote installation.
begin;
create table public.entry_baselines(
 id uuid primary key default gen_random_uuid(),
 championship_id uuid not null references public.championships(id),
 competitor_id uuid not null references public.competitors(id),
 source_history_id bigint not null references public.score_history(id),
 ytd numeric(12,4) not null check(ytd>=-100 and ytd<=100000 and ytd::text not in ('NaN','Infinity','-Infinity')),
 admitted_at timestamptz not null,effective_at timestamptz not null,
 recorded_at timestamptz not null default clock_timestamp(),
 source_kind text not null check(source_kind in ('first_declaration','audited_history')),
 unique(championship_id,competitor_id),check(effective_at>=admitted_at)
);
alter table public.entry_baselines enable row level security;
revoke all on public.entry_baselines from public,anon,authenticated;
grant select on public.entry_baselines to authenticated;
create policy entry_baseline_read on public.entry_baselines for select to authenticated using(true);
create trigger entry_baseline_immutable before update or delete on public.entry_baselines for each row execute function public.reject_competition_rewrite();

-- Only genuinely audited declarations after admission and within the championship.
-- No reconstruction from competitors.ytd or closing snapshots, and no guessed zero.
insert into public.entry_baselines(championship_id,competitor_id,source_history_id,ytd,admitted_at,effective_at,source_kind)
select ch.id,c.id,h.id,h.ytd,c.joined_at,h.created_at,'audited_history'
from public.championships ch cross join public.competitors c
join lateral (
 select id,ytd,created_at from public.score_history sh where sh.competitor_id=c.id
  and sh.created_at>=greatest(c.joined_at,ch.starts_at) and sh.created_at<=ch.ends_at and sh.created_at<=clock_timestamp()
  and sh.ytd between -100 and 100000 and sh.ytd::text not in ('NaN','Infinity','-Infinity')
 order by sh.created_at,sh.id limit 1
) h on true;

alter table public.markets add column entry_reference_enabled boolean not null default false,
 add column entry_starts_at timestamptz,
 drop constraint market_mode_reference,
 add constraint market_mode_reference check(case
  when mode is null then previous_championship_id is null and previous_sprint_id is null and previous_closes_at is null
  when mode='snapshot_value' then championship_id is not null and previous_championship_id is null and previous_sprint_id is null and previous_closes_at is null
  else championship_id is not null and (
   (previous_championship_id is not null and previous_closes_at is not null and previous_closes_at<closes_at and ((sprint_id is null)=(previous_sprint_id is null)))
   or (entry_reference_enabled and previous_championship_id is null and previous_sprint_id is null and previous_closes_at is null)) end),
 add check((not entry_reference_enabled and entry_starts_at is null) or (entry_reference_enabled and mode is not null and entry_starts_at is not null and entry_starts_at<closes_at));
alter table public.final_members add column entry_baseline_id uuid references public.entry_baselines(id);
alter table public.market_classifications add column entry_references boolean not null default false,
 drop constraint market_classifications_check,
 add constraint classification_reference_sources check(
  (mode='snapshot_value' and previous_capture_id is null) or
  (mode='snapshot_delta_previous' and (previous_capture_id is not null or entry_references)));

-- Enable the new rule only for still-tradable, unvalidated explicit markets.
-- Captured/settled history and stored classification rows are never rewritten.
update public.markets m set entry_reference_enabled=true,
 entry_starts_at=case when m.sprint_id is null then c.starts_at else s.starts_at end
from public.championships c left join public.sprints s on s.championship_id=c.id
where m.championship_id=c.id and (m.sprint_id is null or m.sprint_id=s.id)
 and m.mode is not null and m.state='open' and m.closes_at>clock_timestamp()
 and not exists(select 1 from public.market_classifications v where v.market_id=m.id)
 and not exists(select 1 from public.competition_captures cap where cap.championship_id=m.championship_id and cap.sprint_id is not distinct from m.sprint_id and cap.phase='end');

create or replace function public.reject_market_redefinition() returns trigger language plpgsql set search_path='' as $$
begin
 if old.mode is not null and row(new.mode,new.championship_id,new.sprint_id,new.closes_at,new.previous_championship_id,new.previous_sprint_id,new.previous_closes_at,new.category,new.entry_reference_enabled,new.entry_starts_at)
  is distinct from row(old.mode,old.championship_id,old.sprint_id,old.closes_at,old.previous_championship_id,old.previous_sprint_id,old.previous_closes_at,old.category,old.entry_reference_enabled,old.entry_starts_at) then
  raise exception using errcode='BP001',message='Critério e referências do mercado são imutáveis';end if;
 return new;
end $$;

-- One shared reference rule for provisional and frozen classifications.
create function public.market_entry_reference(p_market uuid,p_competitor uuid,p_capture uuid)
returns table(reference_kind text,reference_ytd numeric,reference_at timestamptz,entry_baseline_id uuid,entry_effective_at timestamptz,admitted_at timestamptz,participation_status text)
language sql stable security definer set search_path='' as $$
 select case when m.mode='snapshot_value' then null
   when m.entry_reference_enabled and b.effective_at>=m.entry_starts_at and b.effective_at<=m.closes_at then 'entry_baseline' else 'previous_snapshot' end,
  case when m.entry_reference_enabled and b.effective_at>=m.entry_starts_at and b.effective_at<=m.closes_at then b.ytd else coalesce(s.declared_ytd,s.ytd) end,
  case when m.entry_reference_enabled and b.effective_at>=m.entry_starts_at and b.effective_at<=m.closes_at then b.effective_at else m.previous_closes_at end,
  b.id,b.effective_at,c.joined_at,
  case when not m.entry_reference_enabled then 'legacy' when b.id is null then 'awaiting_initial' when b.effective_at>m.closes_at then 'not_yet_entered' else 'active' end
 from public.markets m join public.competitors c on c.id=p_competitor
 left join public.entry_baselines b on b.championship_id=m.championship_id and b.competitor_id=c.id
 left join public.competition_capture_scores s on s.capture_id=p_capture and s.competitor_id=c.id
 where m.id=p_market
$$;


-- Activation also synchronizes new explicit individual markets using the same policy.
create function public.sync_effective_outcomes(p_championship uuid) returns integer
language plpgsql security definer set search_path='' as $$
declare m uuid;n integer;v_count integer:=0;
begin
 perform pg_advisory_xact_lock(941001);perform pg_advisory_xact_lock(941002);perform pg_advisory_xact_lock(941003);
 for m in select x.id from public.markets x left join public.bet_definitions d on d.id=x.definition_id
   where x.championship_id=p_championship and x.entry_reference_enabled and (x.definition_id is null or d.active) and x.state='open' and x.closes_at>clock_timestamp()
    and not exists(select 1 from public.market_classifications v where v.market_id=x.id)
   order by x.id for update of x loop
  if (select closes_at from public.markets where id=m)<=clock_timestamp() then continue;end if;
  insert into public.outcomes(market_id,competitor_id,label)
   select m,b.competitor_id,p.nickname from public.entry_baselines b join public.profiles p on p.id=b.competitor_id
   where b.championship_id=p_championship and b.effective_at<=clock_timestamp() on conflict(market_id,competitor_id) do nothing;
  get diagnostics n=row_count;v_count:=v_count+n;
 end loop;
 return v_count;
end $$;

-- Approval alone no longer publishes outcomes. First declaration drives activation.
drop trigger admitted_recurring_markets on public.competitors;
create function public.register_entry_from_history() returns trigger language plpgsql security definer set search_path='' as $$
declare ch record;source public.score_history%rowtype;v_entry uuid;v_admitted timestamptz;
begin
 perform pg_advisory_xact_lock(941001);perform pg_advisory_xact_lock(941002);perform pg_advisory_xact_lock(941003);
 select joined_at into v_admitted from public.competitors where id=new.competitor_id;
 for ch in select * from public.championships where state='open' and starts_at<=clock_timestamp() and ends_at>=clock_timestamp() order by id loop
  if exists(select 1 from public.entry_baselines where championship_id=ch.id and competitor_id=new.competitor_id) then continue;end if;
  select * into source from public.score_history h where h.competitor_id=new.competitor_id
   and h.created_at>=greatest(v_admitted,ch.starts_at) and h.created_at<=ch.ends_at and h.created_at<=clock_timestamp()
   and h.ytd between -100 and 100000 and h.ytd::text not in ('NaN','Infinity','-Infinity') order by h.created_at,h.id limit 1;
  if not found then continue;end if;
  insert into public.entry_baselines(championship_id,competitor_id,source_history_id,ytd,admitted_at,effective_at,source_kind)
   values(ch.id,new.competitor_id,source.id,source.ytd,v_admitted,source.created_at,case when source.id=new.id then 'first_declaration' else 'audited_history' end)
   on conflict(championship_id,competitor_id) do nothing returning id into v_entry;
  if v_entry is not null and exists(select 1 from public.bet_definitions where championship_id=ch.id and active) then
   perform public.generate_bet_markets(ch.id);
  elsif v_entry is not null then
   perform public.sync_effective_outcomes(ch.id);
  end if;
 end loop;
 return new;
end $$;
create trigger first_history_entry after insert on public.score_history for each row execute function public.register_entry_from_history();

create function public.get_my_entry_baselines() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null then raise exception using errcode='42501',message='Não autenticado';end if;
 select coalesce(jsonb_agg(to_jsonb(q) order by name,championship_id),'[]'::jsonb) into result from (
  select ch.id as championship_id,ch.name,c.joined_at as admitted_at,b.id as baseline_id,b.ytd,b.effective_at,b.source_kind,
   case when b.id is null then 'awaiting_initial' else 'active' end as status
  from public.championships ch join public.competitors c on c.id=auth.uid()
  left join public.entry_baselines b on b.championship_id=ch.id and b.competitor_id=c.id
  where ch.state='open' and ch.starts_at<=now() and ch.ends_at>=now()
 ) q;
 return result;
end $$;
create function public.declare_initial_ytd(p_championship uuid,p_ytd numeric) returns uuid language plpgsql security definer set search_path='' as $$
declare b public.entry_baselines%rowtype;
begin
 if not public.is_competitor() then raise exception using errcode='42501',message='Apenas concorrentes admitidos';end if;
 perform pg_advisory_xact_lock(941001);perform pg_advisory_xact_lock(941002);perform pg_advisory_xact_lock(941003);
 if p_ytd is null or p_ytd::text in ('NaN','Infinity','-Infinity') or p_ytd<-100 or p_ytd>100000 or p_ytd<>round(p_ytd,4) then
  raise exception using errcode='BF004',message='YTD inicial inválido';end if;
 select * into b from public.entry_baselines where championship_id=p_championship and competitor_id=auth.uid();
 if found then
  if b.ytd=p_ytd then return b.id;end if;
  raise exception using errcode='BE001',message='O primeiro YTD é imutável; usa a atualização corrente';end if;
 if not exists(select 1 from public.championships where id=p_championship and state='open' and starts_at<=clock_timestamp() and ends_at>=clock_timestamp()) then
  raise exception using errcode='BE002',message='Campeonato fora da janela de participação';end if;
 perform public.set_my_score(p_ytd);
 select * into b from public.entry_baselines where championship_id=p_championship and competitor_id=auth.uid();
 if not found then raise exception using errcode='BE002',message='Não foi possível registar a entrada';end if;
 return b.id;
end $$;

revoke all on function public.market_entry_reference(uuid,uuid,uuid),public.sync_effective_outcomes(uuid),public.register_entry_from_history(),public.get_my_entry_baselines(),public.declare_initial_ytd(uuid,numeric)
 from public,anon,authenticated;
grant execute on function public.get_my_entry_baselines(),public.declare_initial_ytd(uuid,numeric) to authenticated;
-- The generation/classification/capture entry points are replaced below.

create or replace function public.create_competition_market(p_title text,p_championship uuid,p_sprint uuid,p_category text,p_mode text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_market uuid;v_previous jsonb;v_kind text;v_start timestamptz;v_end timestamptz;v_competitors uuid[];
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 if p_mode is null or p_mode not in ('snapshot_value','snapshot_delta_previous') then raise exception using errcode='BP002',message='Seleciona a modalidade';end if;
 perform pg_advisory_xact_lock(941001);perform pg_advisory_xact_lock(941002);perform pg_advisory_xact_lock(941003);
 if p_sprint is null then
  select 'annual',starts_at,ends_at into v_kind,v_start,v_end from public.championships where id=p_championship and state='open';
 else
  select sp.kind,sp.starts_at,sp.ends_at into v_kind,v_start,v_end from public.sprints sp join public.championships ch on ch.id=sp.championship_id
   where sp.id=p_sprint and sp.championship_id=p_championship and sp.state='open' and ch.state='open';
 end if;
 if v_end is null or v_end<=clock_timestamp() or p_title is null or p_category is null then raise exception using errcode='BM003',message='Período inválido ou fechado';end if;
 if p_mode='snapshot_delta_previous' then
  v_previous:=public.get_previous_market_period(p_championship,p_sprint);
  if coalesce((v_previous->>'ambiguous')::boolean,false) then raise exception using errcode='BP003',message='Período anterior ambíguo';end if;
 end if;
 select array_agg(competitor_id order by competitor_id) into v_competitors from public.entry_baselines
  where championship_id=p_championship and effective_at<=clock_timestamp();
 if coalesce(array_length(v_competitors,1),0)<2 then raise exception using errcode='BE003',message='São necessárias duas participações com YTD inicial';end if;
 v_market:=public.create_market_p2p_core(p_title,v_kind,p_category,v_end,v_competitors);
 update public.markets set championship_id=p_championship,sprint_id=p_sprint,mode=p_mode,
  previous_championship_id=(v_previous->>'championship_id')::uuid,previous_sprint_id=(v_previous->>'sprint_id')::uuid,
  previous_closes_at=(v_previous->>'ends_at')::timestamptz,entry_reference_enabled=true,entry_starts_at=v_start where id=v_market;
 return v_market;
end $$;

create or replace function public.generate_bet_markets(p_championship uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_def record;v_occ record;v_previous public.bet_occurrences%rowtype;ref jsonb;cat text;m uuid;
 v_added integer:=0;v_outcomes integer:=0;v_blocked integer:=0;n integer;v_calendar integer;
begin
 v_calendar:=public.prepare_bet_occurrences(p_championship);
 for v_def in select * from public.bet_definitions where championship_id=p_championship and active order by id loop
  for v_occ in select * from public.bet_occurrences where championship_id=p_championship and kind=v_def.kind order by starts_at loop
   -- Historical periods remain calendar entries. Never manufacture past bets.
   if v_occ.ends_at<=clock_timestamp() then continue;end if;
   if (select count(*) from public.entry_baselines where championship_id=p_championship and effective_at<=clock_timestamp())<2 then v_blocked:=v_blocked+1;continue;end if;
   ref:=null;
   if v_def.mode='snapshot_delta_previous' then
    if v_occ.kind='annual' then
     -- Internal trigger paths may be invoked without a user JWT (SQL operator).
     select case when count(*)=1 then min(jsonb_build_object('championship_id',c.id,'sprint_id',null,'ends_at',c.ends_at)::text)::jsonb end into ref
      from public.championships c where c.id<>p_championship and c.ends_at=(
       select max(a.ends_at) from public.championships a where a.id<>p_championship
        and a.ends_at<=(select starts_at from public.championships where id=p_championship));
    else
     select * into v_previous from public.bet_occurrences where id=v_occ.previous_occurrence_id;
     if found then ref:=jsonb_build_object('championship_id',v_previous.championship_id,'sprint_id',v_previous.sprint_id,'ends_at',v_previous.ends_at);end if;
    end if;
    -- The first occurrence may use per-player entry references; older participants still need the previous END.
   end if;
   foreach cat in array array['winner','second','last'] loop
    if v_occ.ends_at<=clock_timestamp() then continue;end if;
    select id into m from public.markets where definition_id=v_def.id and occurrence_id=v_occ.id and category=cat;
    if m is null then
     -- No API fallback or inference of mode: period and previous END are explicit.
     insert into public.markets(title,kind,category,closes_at,championship_id,sprint_id,mode,
      previous_championship_id,previous_sprint_id,previous_closes_at,definition_id,occurrence_id,entry_reference_enabled,entry_starts_at)
     values(v_occ.name||' · '||case when v_def.mode='snapshot_value' then 'Valor no fecho' else 'Variação no período' end||' · '||case cat when 'winner' then '1.º' when 'second' then '2.º' else 'Último' end,v_occ.kind,cat,v_occ.ends_at,p_championship,v_occ.sprint_id,v_def.mode,
      (ref->>'championship_id')::uuid,(ref->>'sprint_id')::uuid,(ref->>'ends_at')::timestamptz,v_def.id,v_occ.id,true,v_occ.starts_at) returning id into m;
     v_added:=v_added+1;
    end if;
   end loop;
  end loop;
 end loop;
 v_outcomes:=public.sync_effective_outcomes(p_championship);
 return jsonb_build_object('new_occurrences',v_calendar,'new_markets',v_added,'new_outcomes',v_outcomes,'blocked_occurrences',v_blocked);
end $$;

create or replace function public.ensure_final_rounds() returns void language plpgsql security definer set search_path='' as $$
declare o record;r uuid;
begin
 perform pg_advisory_xact_lock(941001);perform pg_advisory_xact_lock(941002);perform pg_advisory_xact_lock(941003);
 for o in select b.* from public.bet_occurrences b where b.ends_at<=clock_timestamp()
  and exists(select 1 from public.markets m where m.occurrence_id=b.id and m.state='open')
  and not exists(select 1 from public.competition_captures c where c.championship_id=b.championship_id and c.sprint_id is not distinct from b.sprint_id and c.phase='end')
  order by b.ends_at,b.id loop
  insert into public.final_rounds(championship_id,cutoff_at) values(o.championship_id,o.ends_at) on conflict(championship_id,cutoff_at) do nothing;
  select id into r from public.final_rounds where championship_id=o.championship_id and cutoff_at=o.ends_at and state='collecting';
  if r is null then continue;end if;
  insert into public.final_round_occurrences(round_id,occurrence_id) values(r,o.id) on conflict do nothing;
  insert into public.final_members(round_id,occurrence_id,competitor_id,entry_baseline_id)
   select distinct r,o.id,x.competitor_id,b.id from public.outcomes x join public.markets m on m.id=x.market_id
   left join public.entry_baselines b on b.championship_id=o.championship_id and b.competitor_id=x.competitor_id and b.effective_at<=o.ends_at
   where m.occurrence_id=o.id and m.state='open'
    and (not exists(select 1 from public.markets em where em.occurrence_id=o.id and em.entry_reference_enabled) or b.id is not null) on conflict do nothing;
 end loop;
end $$;

create or replace function public.get_market_classification(p_market uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare m public.markets%rowtype;c public.competition_captures%rowtype;p public.competition_captures%rowtype;
 v public.market_classifications%rowtype;r jsonb;v_status text;
begin
 if auth.uid() is null then raise exception using errcode='42501',message='Não autenticado';end if;
 select * into m from public.markets where id=p_market;
 if not found then raise exception using errcode='BM003',message='Mercado inválido';end if;
 if m.mode is null then return jsonb_build_object('status','legacy','can_validate',false,'rows','[]'::jsonb);end if;
 select * into v from public.market_classifications where market_id=p_market;
 if v.id is not null then
  select * into c from public.competition_captures where id=v.current_capture_id;
  select * into p from public.competition_captures where id=v.previous_capture_id;
  r:=v.rows;v_status:='validated';
 else
  select * into c from public.competition_captures where championship_id=m.championship_id
   and sprint_id is not distinct from m.sprint_id and phase='end';
  if m.mode='snapshot_delta_previous' then
   select * into p from public.competition_captures where championship_id=m.previous_championship_id
    and sprint_id is not distinct from m.previous_sprint_id and phase='end';
  end if;
  if c.id is null then v_status:='waiting_current_snapshot';
  elsif c.cutoff_at<>m.closes_at or (m.mode='snapshot_delta_previous' and p.cutoff_at<>m.previous_closes_at) then v_status:='period_mismatch';
  else
   with source as (
    select e.competitor_id,e.nickname,e.ytd as end_ytd,
     case when m.mode='snapshot_delta_previous' then ref.reference_ytd end as previous_ytd,
     e.declared_ytd,e.penalty_pp,e.score_origin,e.declared_at as source_declared_at,e.source_cutoff_at,
     e.closing_declaration_id as current_closing_declaration_id,a.ytd as previous_effective_ytd,
     e.source_history_id as current_history_id,a.source_history_id as previous_history_id,
     ref.reference_kind,ref.reference_at,ref.entry_baseline_id,ref.entry_effective_at,ref.admitted_at,ref.participation_status,
     case when ref.participation_status in ('awaiting_initial','not_yet_entered') then 'not_participating'
      when e.ytd is null then 'missing_end'
      when m.mode='snapshot_delta_previous' and ref.reference_ytd is null then 'missing_previous' else 'complete' end as status,
     case when ref.participation_status in ('awaiting_initial','not_yet_entered') then null
      when m.mode='snapshot_value' then e.ytd else round(e.ytd-ref.reference_ytd,4) end as value
    from public.competition_capture_scores e left join public.competition_capture_scores a
     on a.capture_id=p.id and a.competitor_id=e.competitor_id
    cross join lateral public.market_entry_reference(p_market,e.competitor_id,p.id) ref where e.capture_id=c.id
   ), ranked as (
    select *,case when status='complete' then rank() over(order by value desc nulls last) end as place from source
   ) select coalesce(jsonb_agg(to_jsonb(ranked) order by value desc nulls last,competitor_id),'[]'::jsonb) into r from ranked;
   if exists(
    (select (x->>'competitor_id')::uuid from jsonb_array_elements(r) x except select competitor_id from public.outcomes where market_id=p_market)
    union all
    (select competitor_id from public.outcomes where market_id=p_market except select (x->>'competitor_id')::uuid from jsonb_array_elements(r) x)
   ) then v_status:='universe_changed';
   elsif jsonb_array_length(r)<2 or exists(select 1 from jsonb_array_elements(r) x where x->>'status'<>'complete') then
    v_status:=case when m.mode='snapshot_delta_previous' and p.id is null and exists(select 1 from jsonb_array_elements(r) x where x->>'status'='missing_previous') then 'waiting_previous_snapshot' else 'incomplete' end;
   else v_status:='ready_for_validation';end if;
  end if;
 end if;
 return jsonb_build_object('status',v_status,'mode',m.mode,'unit',case when m.mode='snapshot_value' then '%' else 'pp' end,
  'rows',coalesce(r,'[]'::jsonb),'classification_id',v.id,'entry_reference_enabled',m.entry_reference_enabled,'entry_starts_at',m.entry_starts_at,
  'current_capture',case when c.id is not null then to_jsonb(c) end,
  'previous_capture',case when p.id is not null then to_jsonb(p) end,
  'validation',case when v.id is not null then to_jsonb(v)-'rows' end,
  'can_validate',v_status='ready_for_validation' and m.state='open' and now()>=m.closes_at);
end $$;

create or replace function public.get_bet_provisional_rankings(p_market uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare m public.markets%rowtype;cap uuid;result jsonb;
begin
 if auth.uid() is null then raise exception using errcode='42501',message='Não autenticado';end if;
 select * into m from public.markets where id=p_market;
 if not found or m.definition_id is null or m.state<>'open' or m.closes_at<=clock_timestamp() then
  return jsonb_build_object('status','historical','rows','[]'::jsonb);end if;
 if m.mode='snapshot_delta_previous' then
  select id into cap from public.competition_captures where championship_id=m.previous_championship_id
   and sprint_id is not distinct from m.previous_sprint_id and phase='end' and cutoff_at=m.previous_closes_at;
 end if;
 with inputs as (
  select o.competitor_id,o.label as nickname,c.updated_at,c.ytd as end_ytd,ref.reference_ytd as previous_ytd,
   ref.reference_kind,ref.reference_at,ref.entry_baseline_id,ref.entry_effective_at,ref.admitted_at,ref.participation_status,
   case when ref.participation_status in ('awaiting_initial','not_yet_entered') then null
    when m.mode='snapshot_value' then c.ytd else round(c.ytd-ref.reference_ytd,4) end as value
  from public.outcomes o join public.competitors c on c.id=o.competitor_id
   cross join lateral public.market_entry_reference(p_market,o.competitor_id,cap) ref
  where o.market_id=p_market
 ), rows as (
  select *,case when value is not null then rank() over(order by value desc nulls last) end as place from inputs
 ) select coalesce(jsonb_agg(to_jsonb(rows) order by value desc nulls last,competitor_id),'[]'::jsonb) into result from rows;
 return jsonb_build_object('status','provisional','mode',m.mode,'unit',case when m.mode='snapshot_value' then '%' else 'pp' end,
  'previous_capture_id',cap,'rows',result);
end $$;

create or replace function public.validate_market_classification(p_market uuid,p_note text) returns uuid
language plpgsql security definer set search_path='' as $$
declare r jsonb;v_id uuid;
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 perform pg_advisory_xact_lock(941001);
 perform pg_advisory_xact_lock(941002);
 perform pg_advisory_xact_lock(941003);
 perform 1 from public.markets where id=p_market for update;
 select id into v_id from public.market_classifications where market_id=p_market;
 if v_id is not null then return v_id;end if;
 if p_note is null or length(btrim(p_note)) not between 10 and 2000 then
  raise exception using errcode='BC006',message='Nota de validação obrigatória';end if;
 r:=public.get_market_classification(p_market);
 if not coalesce((r->>'can_validate')::boolean,false) then
  raise exception using errcode='BP004',message='Snapshots completos e apuramento revisto são obrigatórios';end if;
 insert into public.market_classifications(market_id,mode,current_capture_id,previous_capture_id,rows,validated_by,note,entry_references)
  values(p_market,r->>'mode',(r#>>'{current_capture,id}')::uuid,(r#>>'{previous_capture,id}')::uuid,r->'rows',auth.uid(),btrim(p_note),coalesce((r->>'entry_reference_enabled')::boolean,false)) returning id into v_id;
 return v_id;
end $$;

commit;
