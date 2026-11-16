-- #1: explicit snapshot value / delta from the previous period's END snapshot.
-- Versioned only. Requires 01--10. Does not install anything remotely.
begin;
alter table public.markets
 add column mode text check(mode in ('snapshot_value','snapshot_delta_previous')),
 add column previous_championship_id uuid references public.championships(id),
 add column previous_sprint_id uuid references public.sprints(id),
 add column previous_closes_at timestamptz,
 add constraint market_mode_reference check(case
  when mode is null then previous_championship_id is null and previous_sprint_id is null and previous_closes_at is null
  when mode='snapshot_value' then championship_id is not null and previous_championship_id is null and previous_sprint_id is null and previous_closes_at is null
  else championship_id is not null and previous_championship_id is not null
   and previous_closes_at is not null and previous_closes_at<closes_at and ((sprint_id is null)=(previous_sprint_id is null)) end);

create table public.market_classifications(
 id uuid primary key default gen_random_uuid(),
 market_id uuid not null unique references public.markets(id),
 mode text not null check(mode in ('snapshot_value','snapshot_delta_previous')),
 current_capture_id uuid not null references public.competition_captures(id),
 previous_capture_id uuid references public.competition_captures(id),
 rows jsonb not null check(jsonb_typeof(rows)='array'),
 validated_by uuid not null references public.profiles(id),
 validated_at timestamptz not null default clock_timestamp(),
 note text not null check(length(btrim(note)) between 10 and 2000),
 check((mode='snapshot_value' and previous_capture_id is null) or
       (mode='snapshot_delta_previous' and previous_capture_id is not null)),
 unique(market_id,id)
);
alter table public.market_classifications enable row level security;
revoke all on public.market_classifications from public,anon,authenticated;
grant select on public.market_classifications to authenticated;
create policy market_classification_read on public.market_classifications for select to authenticated using(true);
create trigger market_classification_immutable before update or delete on public.market_classifications
 for each row execute function public.reject_competition_rewrite();
alter table public.market_resolutions alter column validation_id drop not null;
alter table public.market_resolutions add column classification_id uuid,
 add foreign key(market_id,classification_id) references public.market_classifications(market_id,id),
 add check((validation_id is null)<>(classification_id is null));

create function public.reject_market_redefinition() returns trigger
language plpgsql set search_path='' as $$
begin
 if old.mode is not null and row(new.mode,new.championship_id,new.sprint_id,new.closes_at,
  new.previous_championship_id,new.previous_sprint_id,new.previous_closes_at,new.category)
  is distinct from row(old.mode,old.championship_id,old.sprint_id,old.closes_at,
  old.previous_championship_id,old.previous_sprint_id,old.previous_closes_at,old.category) then
  raise exception using errcode='BP001',message='Critério e referências do mercado são imutáveis';
 end if;
 return new;
end $$;
create trigger market_definition_immutable before update on public.markets
 for each row execute function public.reject_market_redefinition();

-- Select the immediate registered predecessor once, when creating the market.
-- No previous snapshot is substituted by a start snapshot or by today's YTD.
create function public.get_previous_market_period(p_championship uuid,p_sprint uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_start timestamptz;v_kind text;v_at timestamptz;v_count integer;v_result jsonb;
begin
 if auth.uid() is null then raise exception using errcode='42501',message='Não autenticado';end if;
 if p_sprint is null then
  select starts_at into v_start from public.championships where id=p_championship;
  select max(ends_at) into v_at from public.championships where id<>p_championship and ends_at<=v_start;
  select count(*),min(jsonb_build_object('championship_id',id,'sprint_id',null,'ends_at',ends_at,'name',name)::text)::jsonb
   into v_count,v_result from public.championships where id<>p_championship and ends_at=v_at;
 else
  select starts_at,kind into v_start,v_kind from public.sprints where id=p_sprint and championship_id=p_championship;
  select max(ends_at) into v_at from public.sprints where championship_id=p_championship and kind=v_kind and id<>p_sprint and ends_at<=v_start;
  select count(*),min(jsonb_build_object('championship_id',championship_id,'sprint_id',id,'ends_at',ends_at,'name',name)::text)::jsonb
   into v_count,v_result from public.sprints where championship_id=p_championship and kind=v_kind and ends_at=v_at and id<>p_sprint;
 end if;
 return case when v_count=1 then v_result else jsonb_build_object('unavailable',true,'ambiguous',v_count>1) end;
end $$;

create function public.create_competition_market(p_title text,p_championship uuid,p_sprint uuid,p_category text,p_mode text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_market uuid;v_previous jsonb;
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 if p_mode is null or p_mode not in ('snapshot_value','snapshot_delta_previous') then
  raise exception using errcode='BP002',message='Seleciona a modalidade de aposta';end if;
 perform pg_advisory_xact_lock(941001);
 if p_mode='snapshot_delta_previous' then
  v_previous:=public.get_previous_market_period(p_championship,p_sprint);
  if v_previous->>'championship_id' is null then
   raise exception using errcode='BP003',message='Período anterior inexistente ou ambíguo';end if;
 end if;
 v_market:=public.create_competition_market(p_title,p_championship,p_sprint,p_category);
 update public.markets set mode=p_mode,
  previous_championship_id=(v_previous->>'championship_id')::uuid,
  previous_sprint_id=(v_previous->>'sprint_id')::uuid,
  previous_closes_at=(v_previous->>'ends_at')::timestamptz where id=v_market;
 return v_market;
end $$;

create function public.get_market_classification(p_market uuid) returns jsonb
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
    select e.competitor_id,e.nickname,e.ytd as end_ytd,a.ytd as previous_ytd,
     e.source_history_id as current_history_id,a.source_history_id as previous_history_id,
     case when e.ytd is null then 'missing_end'
      when m.mode='snapshot_delta_previous' and a.ytd is null then 'missing_previous' else 'complete' end as status,
     case when m.mode='snapshot_value' then e.ytd else round(e.ytd-a.ytd,4) end as value
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

create function public.validate_market_classification(p_market uuid,p_note text) returns uuid
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
 insert into public.market_classifications(market_id,mode,current_capture_id,previous_capture_id,rows,validated_by,note)
  values(p_market,r->>'mode',(r#>>'{current_capture,id}')::uuid,(r#>>'{previous_capture,id}')::uuid,r->'rows',auth.uid(),btrim(p_note)) returning id into v_id;
 return v_id;
end $$;

alter function public.get_market_resolution(uuid) rename to get_legacy_market_resolution;
revoke all on function public.get_legacy_market_resolution(uuid) from public,anon,authenticated;
create function public.get_market_resolution(p_market uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare m public.markets%rowtype;r jsonb;v_rows jsonb;v_target numeric;v_winner uuid;v_count integer;v_status text;
begin
 if auth.uid() is null then raise exception using errcode='42501',message='Não autenticado';end if;
 select * into m from public.markets where id=p_market;
 if not found or m.mode is null then return public.get_legacy_market_resolution(p_market);end if;
 r:=public.get_market_classification(p_market);
 if m.state='settled' then v_status:='settled';v_winner:=m.winner_outcome_id;
 elsif r->>'status'<>'validated' then v_status:=case when r->>'status'='ready_for_validation' then 'awaiting_validation' else r->>'status' end;
 else
  v_rows:=r->'rows';
  if m.category='last' then select min((x->>'value')::numeric) into v_target from jsonb_array_elements(v_rows) x;
  else select (x->>'value')::numeric into v_target from jsonb_array_elements(v_rows) x
   where (x->>'place')::integer=case when m.category='winner' then 1 else 2 end limit 1;end if;
  select count(*),min(o.id::text)::uuid into v_count,v_winner from jsonb_array_elements(v_rows) x
   join public.outcomes o on o.market_id=p_market and o.competitor_id=(x->>'competitor_id')::uuid where (x->>'value')::numeric=v_target;
  v_status:=case when v_count=1 then 'ready' else 'tie_unsupported' end;
 end if;
 return jsonb_build_object('status',v_status,'criterion',m.mode,'classification_id',r->'classification_id',
  'winner_outcome_id',case when v_status in ('ready','settled') then v_winner end);
end $$;

alter function public.settle_market(uuid,uuid) rename to settle_legacy_validated_market;
revoke all on function public.settle_legacy_validated_market(uuid,uuid) from public,anon,authenticated;
create function public.settle_market(p_market uuid,p_winner uuid) returns void
language plpgsql security definer set search_path='' as $$
declare m public.markets%rowtype;r jsonb;
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 perform pg_advisory_xact_lock(941003);
 select * into m from public.markets where id=p_market for update;
 if not found or m.mode is null then perform public.settle_legacy_validated_market(p_market,p_winner);return;end if;
 if m.state='settled' then
  if p_winner is not null and p_winner=m.winner_outcome_id and exists(select 1 from public.market_resolutions where market_id=p_market and classification_id is not null) then return;end if;
  raise exception using errcode='BM004',message='Resultado imutável';end if;
 if m.state<>'open' or clock_timestamp()<m.closes_at then raise exception using errcode='BM001',message='Mercado ainda não pode liquidar';end if;
 r:=public.get_market_resolution(p_market);
 if r->>'status'<>'ready' or p_winner is null or p_winner<>(r->>'winner_outcome_id')::uuid then
  raise exception using errcode='BM004',message='Liquidação exige resultado validado sem empate relevante';end if;
 perform public.settle_market_p2p_core(p_market,p_winner);
 insert into public.market_resolutions(market_id,classification_id,winner_outcome_id,resolved_by)
  values(p_market,(r->>'classification_id')::uuid,p_winner,auth.uid());
end $$;

revoke all on function public.reject_market_redefinition(),public.get_previous_market_period(uuid,uuid),
 public.create_competition_market(text,uuid,uuid,text,text),public.get_market_classification(uuid),
 public.validate_market_classification(uuid,text),public.get_market_resolution(uuid),public.settle_market(uuid,uuid) from public,anon,authenticated;
grant execute on function public.get_previous_market_period(uuid,uuid),public.create_competition_market(text,uuid,uuid,text,text),
 public.get_market_classification(uuid),public.validate_market_classification(uuid,text),
 public.get_market_resolution(uuid),public.settle_market(uuid,uuid) to authenticated;
commit;
