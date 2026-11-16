-- #11: mandatory closing declarations and local -1 pp omission penalties.
-- Repository migration only; requires 01--12. Never executes against remote DB.
begin;
create table public.final_rounds(
 id uuid primary key default gen_random_uuid(),championship_id uuid not null references public.championships(id),
 cutoff_at timestamptz not null,state text not null default 'collecting' check(state in ('collecting','finalized')),
 created_at timestamptz not null default clock_timestamp(),deadline_at timestamptz,deadline_by uuid references public.profiles(id),deadline_note text,
 finalized_at timestamptz,finalized_by uuid references public.profiles(id),final_note text,
 unique(championship_id,cutoff_at),
 check(deadline_at is null or deadline_at>=cutoff_at),
 check((deadline_at is null and deadline_by is null and deadline_note is null) or
       (deadline_at is not null and deadline_by is not null and length(btrim(deadline_note)) between 10 and 2000)),
 check((state='collecting' and finalized_at is null and finalized_by is null) or
       (state='finalized' and finalized_at is not null and finalized_by is not null and deadline_at is not null and length(btrim(final_note)) between 10 and 2000))
);
create table public.final_round_occurrences(
 round_id uuid not null references public.final_rounds(id),occurrence_id uuid not null unique references public.bet_occurrences(id),
 primary key(round_id,occurrence_id)
);
create table public.final_members(
 round_id uuid not null,occurrence_id uuid not null,competitor_id uuid not null references public.competitors(id),
 primary key(round_id,occurrence_id,competitor_id),
 foreign key(round_id,occurrence_id) references public.final_round_occurrences(round_id,occurrence_id)
);
create table public.closing_declarations(
 id uuid primary key default gen_random_uuid(),round_id uuid not null references public.final_rounds(id),
 competitor_id uuid not null references public.competitors(id),ytd numeric(12,4) not null check(ytd>=-100 and ytd<=100000 and ytd::text not in ('NaN','Infinity','-Infinity')),
 submitted_at timestamptz not null default clock_timestamp(),unique(round_id,competitor_id)
);
alter table public.final_rounds enable row level security;
alter table public.final_round_occurrences enable row level security;
alter table public.final_members enable row level security;
alter table public.closing_declarations enable row level security;
revoke all on public.final_rounds,public.final_round_occurrences,public.final_members,public.closing_declarations from public,anon,authenticated;
grant select on public.final_rounds,public.final_round_occurrences,public.final_members,public.closing_declarations to authenticated;
create policy final_round_read on public.final_rounds for select to authenticated using(true);
create policy final_occurrence_read on public.final_round_occurrences for select to authenticated using(true);
create policy final_member_read on public.final_members for select to authenticated using(competitor_id=auth.uid());
create policy closing_declaration_owner_read on public.closing_declarations for select to authenticated using(competitor_id=auth.uid());
create trigger final_occurrence_immutable before update or delete on public.final_round_occurrences for each row execute function public.reject_competition_rewrite();
create trigger final_member_immutable before update or delete on public.final_members for each row execute function public.reject_competition_rewrite();
create trigger closing_declaration_immutable before update or delete on public.closing_declarations for each row execute function public.reject_competition_rewrite();
create function public.guard_final_round() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='DELETE' or old.state='finalized' then raise exception using errcode='BC001',message='Fecho imutável';end if;
 if row(new.championship_id,new.cutoff_at,new.created_at) is distinct from row(old.championship_id,old.cutoff_at,old.created_at)
  or (old.deadline_at is not null and row(new.deadline_at,new.deadline_by,new.deadline_note) is distinct from row(old.deadline_at,old.deadline_by,old.deadline_note)) then
  raise exception using errcode='BC001',message='Referência e prazo do fecho são imutáveis';end if;
 return new;
end $$;
create trigger final_round_monotonic before update or delete on public.final_rounds for each row execute function public.guard_final_round();

alter table public.competition_capture_scores
 add column closing_declaration_id uuid references public.closing_declarations(id),
 add column declared_ytd numeric(12,4),add column penalty_pp numeric(1,0) not null default 0 check(penalty_pp in (0,1)),
 add column source_cutoff_at timestamptz,add column score_origin text check(score_origin in ('final_declaration','missing_final','missing_baseline')),
 drop constraint competition_capture_scores_check,
 add constraint capture_score_provenance check(
  (ytd is null and source_history_id is null and closing_declaration_id is null and declared_at is null and declared_ytd is null and penalty_pp=0)
  or (ytd is not null and declared_at is not null and ((source_history_id is null)<>(closing_declaration_id is null)) and
   ((declared_ytd is null and penalty_pp=0 and closing_declaration_id is null and ytd>=-100)
    or (declared_ytd is not null and declared_ytd>=-100 and declared_ytd<=100000 and declared_ytd::text not in ('NaN','Infinity','-Infinity') and ytd=declared_ytd-penalty_pp and source_cutoff_at is not null)))
 );

-- Existing captured/validated history is excluded: it is never reopened or rewritten.
-- Only published recurring occurrences require declarations, not empty historical calendar entries.
create function public.ensure_final_rounds() returns void language plpgsql security definer set search_path='' as $$
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
  insert into public.final_members(round_id,occurrence_id,competitor_id)
   select distinct r,o.id,x.competitor_id from public.outcomes x join public.markets m on m.id=x.market_id
   where m.occurrence_id=o.id and m.state='open' on conflict do nothing;
 end loop;
end $$;
create function public.get_my_final_declarations() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null then raise exception using errcode='42501',message='Não autenticado';end if;
 perform public.ensure_final_rounds();
 select coalesce(jsonb_agg(to_jsonb(q) order by cutoff_at,id),'[]'::jsonb) into result from (
  select r.id,r.championship_id,r.cutoff_at,r.deadline_at,
   (select jsonb_agg(o.name order by o.kind) from public.final_round_occurrences a join public.bet_occurrences o on o.id=a.occurrence_id where a.round_id=r.id) as periods,
   r.deadline_at is not null and clock_timestamp()>=r.deadline_at as expired
  from public.final_rounds r where r.state='collecting'
   and exists(select 1 from public.final_members m where m.round_id=r.id and m.competitor_id=auth.uid())
   and not exists(select 1 from public.closing_declarations d where d.round_id=r.id and d.competitor_id=auth.uid())
 ) q;
 return result;
end $$;
create function public.declare_final_score(p_round uuid,p_ytd numeric) returns uuid language plpgsql security definer set search_path='' as $$
declare r public.final_rounds%rowtype;d public.closing_declarations%rowtype;first_round uuid;v_at timestamptz;
begin
 if auth.uid() is null then raise exception using errcode='42501',message='Não autenticado';end if;
 perform public.ensure_final_rounds();v_at:=clock_timestamp();
 if p_ytd is null or p_ytd::text in ('NaN','Infinity','-Infinity') or p_ytd<-100 or p_ytd>100000 or p_ytd<>round(p_ytd,4) then
  raise exception using errcode='BF004',message='YTD final inválido';end if;
 if not exists(select 1 from public.final_members where round_id=p_round and competitor_id=auth.uid()) then raise exception using errcode='42501',message='Não pertences a este fecho';end if;
 select * into d from public.closing_declarations where round_id=p_round and competitor_id=auth.uid();
 if found then
  if d.ytd=p_ytd then return d.id;end if;
  raise exception using errcode='BC001',message='Declaração final imutável';end if;
 select * into r from public.final_rounds where id=p_round for update;
 if r.state<>'collecting' or (r.deadline_at is not null and v_at>=r.deadline_at) then raise exception using errcode='BF002',message='Prazo de declaração encerrado';end if;
 select (x->>'id')::uuid into first_round from jsonb_array_elements(public.get_my_final_declarations()) x limit 1;
 if first_round is distinct from p_round then raise exception using errcode='BF001',message='Resolve primeiro o fecho mais antigo';end if;
 insert into public.closing_declarations(round_id,competitor_id,ytd,submitted_at) values(p_round,auth.uid(),p_ytd,v_at) returning id into d.id;
 return d.id;
end $$;

alter function public.set_my_score(numeric) rename to set_current_score_core;
revoke all on function public.set_current_score_core(numeric) from public,anon,authenticated;
create function public.set_my_score(p_ytd numeric) returns void language plpgsql security definer set search_path='' as $$
begin
 if jsonb_array_length(public.get_my_final_declarations())>0 then raise exception using errcode='BF001',message='Declara primeiro o YTD dos fechos pendentes';end if;
 perform public.set_current_score_core(p_ytd);
end $$;

create function public.get_final_rounds(p_championship uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 perform public.ensure_final_rounds();
 select coalesce(jsonb_agg(to_jsonb(q) order by cutoff_at,id),'[]'::jsonb) into result from (
  select r.*,r.deadline_at is not null and clock_timestamp()>=r.deadline_at as expired,(select count(distinct competitor_id) from public.final_members where round_id=r.id) as members,
   (select count(*) from public.closing_declarations where round_id=r.id) as declared,
   (select jsonb_agg(o.name order by o.kind) from public.final_round_occurrences a join public.bet_occurrences o on o.id=a.occurrence_id where a.round_id=r.id) as periods
  from public.final_rounds r where championship_id=p_championship
 ) q;
 return result;
end $$;
create function public.set_final_deadline(p_round uuid,p_deadline timestamptz,p_note text) returns void language plpgsql security definer set search_path='' as $$
declare r public.final_rounds%rowtype;
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 perform public.ensure_final_rounds();
 select * into r from public.final_rounds where id=p_round for update;
 if not found or r.state<>'collecting' then raise exception using errcode='BF003',message='Fecho indisponível';end if;
 if r.deadline_at is not null then
  if r.deadline_at=p_deadline then return;end if;
  raise exception using errcode='BC001',message='Prazo já fixado';end if;
 if p_deadline is null or p_deadline<=clock_timestamp() or p_note is null or length(btrim(p_note)) not between 10 and 2000 then
  raise exception using errcode='BF003',message='Prazo futuro e nota de revisão obrigatórios';end if;
 update public.final_rounds set deadline_at=p_deadline,deadline_by=auth.uid(),deadline_note=btrim(p_note) where id=p_round;
end $$;

-- Last known ORIGINAL value as of the cutoff. Previous penalties never accumulate.
create function public.closing_score_source(p_competitor uuid,p_cutoff timestamptz)
returns table(source_history_id bigint,closing_declaration_id uuid,declared_at timestamptz,source_cutoff_at timestamptz,declared_ytd numeric)
language sql stable security definer set search_path='' as $$
 select * from (
  select h.id,null::uuid,h.created_at,h.created_at,h.ytd from public.score_history h where h.competitor_id=p_competitor and h.created_at<=p_cutoff
  union all
  select null::bigint,d.id,d.submitted_at,r.cutoff_at,d.ytd from public.closing_declarations d join public.final_rounds r on r.id=d.round_id
   where d.competitor_id=p_competitor and r.cutoff_at<p_cutoff and d.submitted_at<=p_cutoff
 ) s order by 4 desc,3 desc,1 desc nulls last,2 desc nulls last limit 1
$$;
create function public.finalize_final_round(p_round uuid,p_note text) returns uuid language plpgsql security definer set search_path='' as $$
declare r public.final_rounds%rowtype;o record;cap uuid;v_at timestamptz;
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 perform public.ensure_final_rounds();v_at:=clock_timestamp();
 select * into r from public.final_rounds where id=p_round for update;
 if not found then raise exception using errcode='BF003',message='Fecho inválido';end if;
 if r.state='finalized' then return r.id;end if;
 if p_note is null or length(btrim(p_note)) not between 10 and 2000 then raise exception using errcode='BC006',message='Nota de apuramento obrigatória';end if;
 if r.deadline_at>v_at then raise exception using errcode='BF003',message='O prazo prometido ainda não terminou';end if;
 if r.deadline_at is null then
  update public.final_rounds set deadline_at=v_at,deadline_by=auth.uid(),deadline_note=btrim(p_note) where id=p_round;
 end if;
 for o in select b.* from public.final_round_occurrences a join public.bet_occurrences b on b.id=a.occurrence_id where a.round_id=p_round order by b.id loop
  if exists(select 1 from public.competition_captures where championship_id=o.championship_id and sprint_id is not distinct from o.sprint_id and phase='end') then
   raise exception using errcode='BF005',message='Snapshot existente; não reabrir nem substituir';end if;
  insert into public.competition_captures(championship_id,sprint_id,phase,cutoff_at,captured_by)
   values(o.championship_id,o.sprint_id,'end',r.cutoff_at,auth.uid()) returning id into cap;
  insert into public.competition_capture_scores(capture_id,competitor_id,nickname,source_history_id,closing_declaration_id,declared_at,declared_ytd,penalty_pp,source_cutoff_at,score_origin,ytd)
  select cap,m.competitor_id,p.nickname,
   case when d.id is null then s.source_history_id end,coalesce(d.id,s.closing_declaration_id),
   coalesce(d.submitted_at,s.declared_at),coalesce(d.ytd,s.declared_ytd),
   case when d.id is null and s.declared_ytd is not null then 1 else 0 end,
   case when d.id is not null then r.cutoff_at else s.source_cutoff_at end,
   case when d.id is not null then 'final_declaration' when s.declared_ytd is not null then 'missing_final' else 'missing_baseline' end,
   case when d.id is not null then d.ytd when s.declared_ytd is not null then s.declared_ytd-1 end
  from public.final_members m join public.profiles p on p.id=m.competitor_id
   left join public.closing_declarations d on d.round_id=p_round and d.competitor_id=m.competitor_id
   left join lateral public.closing_score_source(m.competitor_id,r.cutoff_at) s on true
  where m.round_id=p_round and m.occurrence_id=o.id;
  if o.sprint_id is not null then update public.sprints set state='closed' where id=o.sprint_id;
  else update public.championships set state='closed' where id=o.championship_id;end if;
 end loop;
 update public.final_rounds set state='finalized',finalized_at=v_at,finalized_by=auth.uid(),final_note=btrim(p_note) where id=p_round;
 return p_round;
end $$;

alter function public.capture_competition(uuid,uuid,text) rename to capture_competition_legacy;
revoke all on function public.capture_competition_legacy(uuid,uuid,text) from public,anon,authenticated;
create function public.capture_competition(p_championship uuid,p_sprint uuid,p_phase text) returns integer language plpgsql security definer set search_path='' as $$
declare cap uuid;
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 perform public.ensure_final_rounds();
 if p_phase='end' and exists(select 1 from public.markets where championship_id=p_championship and sprint_id is not distinct from p_sprint and occurrence_id is not null) then
  select id into cap from public.competition_captures where championship_id=p_championship and sprint_id is not distinct from p_sprint and phase='end';
  if cap is not null then return (select count(*)::integer from public.competition_capture_scores where capture_id=cap);end if;
  raise exception using errcode='BF005',message='Usa a recolha de declarações finais e o apuramento do fecho';
 end if;
 return public.capture_competition_legacy(p_championship,p_sprint,p_phase);
end $$;


-- Rebind both public capture entry points to the guarded dispatcher.
create or replace function public.capture_sprint(p_sprint uuid,p_phase text)
returns integer language plpgsql security definer set search_path='' as $$
begin
 return public.capture_competition((select championship_id from public.sprints where id=p_sprint),p_sprint,p_phase);
end $$;
create or replace function public.capture_championship(p_championship uuid)
returns integer language sql security definer set search_path='' as $$
 select public.capture_competition(p_championship,null,'end')
$$;

revoke all on function public.guard_final_round(),public.ensure_final_rounds(),public.closing_score_source(uuid,timestamptz),public.get_my_final_declarations(),
 public.declare_final_score(uuid,numeric),public.set_my_score(numeric),public.get_final_rounds(uuid),public.set_final_deadline(uuid,timestamptz,text),
 public.finalize_final_round(uuid,text),public.capture_competition(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.get_my_final_declarations(),public.declare_final_score(uuid,numeric),public.set_my_score(numeric),
 public.get_final_rounds(uuid),public.set_final_deadline(uuid,timestamptz,text),public.finalize_final_round(uuid,text) to authenticated;
-- Modality/provisional readers below expose declared, effective and local penalty.

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
  elsif m.mode='snapshot_delta_previous' and p.id is null then v_status:='waiting_previous_snapshot';
  elsif c.cutoff_at<>m.closes_at or (m.mode='snapshot_delta_previous' and p.cutoff_at<>m.previous_closes_at) then v_status:='period_mismatch';
  else
   with source as (
    select e.competitor_id,e.nickname,e.ytd as end_ytd,coalesce(a.declared_ytd,a.ytd) as previous_ytd,
     e.declared_ytd,e.penalty_pp,e.score_origin,e.declared_at as source_declared_at,e.source_cutoff_at,
     e.closing_declaration_id as current_closing_declaration_id,a.ytd as previous_effective_ytd,
     e.source_history_id as current_history_id,a.source_history_id as previous_history_id,
     case when e.ytd is null then 'missing_end'
      when m.mode='snapshot_delta_previous' and coalesce(a.declared_ytd,a.ytd) is null then 'missing_previous' else 'complete' end as status,
     case when m.mode='snapshot_value' then e.ytd else round(e.ytd-coalesce(a.declared_ytd,a.ytd),4) end as value
    from public.competition_capture_scores e left join public.competition_capture_scores a
     on a.capture_id=p.id and a.competitor_id=e.competitor_id where e.capture_id=c.id
   ), ranked as (
    select *,case when status='complete' then rank() over(order by value desc nulls last) end as place from source
   ) select coalesce(jsonb_agg(to_jsonb(ranked) order by value desc nulls last,competitor_id),'[]'::jsonb) into r from ranked;
   if exists(
    (select (x->>'competitor_id')::uuid from jsonb_array_elements(r) x except select competitor_id from public.outcomes where market_id=p_market)
    union all
    (select competitor_id from public.outcomes where market_id=p_market except select (x->>'competitor_id')::uuid from jsonb_array_elements(r) x)
   ) then v_status:='universe_changed';
   elsif jsonb_array_length(r)<2 or exists(select 1 from jsonb_array_elements(r) x where x->>'status'<>'complete') then v_status:='incomplete';
   else v_status:='ready_for_validation';end if;
  end if;
 end if;
 return jsonb_build_object('status',v_status,'mode',m.mode,'unit',case when m.mode='snapshot_value' then '%' else 'pp' end,
  'rows',coalesce(r,'[]'::jsonb),'classification_id',v.id,
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
  select o.competitor_id,o.label as nickname,c.updated_at,c.ytd as end_ytd,coalesce(p.declared_ytd,p.ytd) as previous_ytd,
   case when m.mode='snapshot_value' then c.ytd else round(c.ytd-coalesce(p.declared_ytd,p.ytd),4) end as value
  from public.outcomes o join public.competitors c on c.id=o.competitor_id
   left join public.competition_capture_scores p on p.capture_id=cap and p.competitor_id=o.competitor_id
  where o.market_id=p_market
 ), rows as (
  select *,case when value is not null then rank() over(order by value desc nulls last) end as place from inputs
 ) select coalesce(jsonb_agg(to_jsonb(rows) order by value desc nulls last,competitor_id),'[]'::jsonb) into result from rows;
 return jsonb_build_object('status','provisional','mode',m.mode,'unit',case when m.mode='snapshot_value' then '%' else 'pp' end,
  'previous_capture_id',cap,'rows',result);
end $$;

create or replace function public.competition_rows(p_end uuid,p_start uuid,p_is_sprint boolean)
returns jsonb language sql stable security definer set search_path='' as $$
 with source as (
  select e.competitor_id,e.nickname,a.ytd as start_ytd,e.ytd as end_ytd,
   e.declared_ytd,e.penalty_pp,e.score_origin,e.declared_at as source_declared_at,e.source_cutoff_at,
   a.declared_at as start_declared_at,e.declared_at as end_declared_at,
   a.source_history_id as start_source_id,e.source_history_id as end_source_id,
   case when e.ytd is null then 'missing_end'
        when p_is_sprint and a.ytd is null then 'missing_start' else 'complete' end as status,
   case when p_is_sprint then round(e.ytd-a.ytd,4) else e.ytd end as value
  from public.competition_capture_scores e
  left join public.competition_capture_scores a on a.capture_id=p_start and a.competitor_id=e.competitor_id
  where e.capture_id=p_end
 ), ranked as (
  select *,case when status='complete' then rank() over(order by value desc nulls last) end as place from source
 )
 select coalesce(jsonb_agg(to_jsonb(ranked) order by value desc nulls last,competitor_id),'[]'::jsonb) from ranked
$$;

commit;
