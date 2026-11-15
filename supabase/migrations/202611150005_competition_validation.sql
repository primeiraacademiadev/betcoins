-- E2: audited boundary snapshots and explicit official validation.
-- Repository migration only. Never run automatically against a remote database.
begin;

-- NULL means never declared; a declared zero remains a real score.
alter table public.competitors alter column ytd drop not null;
alter table public.competitors alter column ytd drop default;
update public.competitors set ytd=null where updated_at is null;
create index if not exists score_history_boundary on public.score_history(competitor_id,created_at desc,id desc);

create table public.competition_captures(
 id uuid primary key default gen_random_uuid(),
 championship_id uuid not null references public.championships(id),
 sprint_id uuid references public.sprints(id),
 phase text not null check(phase in ('start','end')),
 cutoff_at timestamptz not null,
 captured_at timestamptz not null default clock_timestamp(),
 captured_by uuid not null references public.profiles(id),
 check(sprint_id is not null or phase='end')
);
create unique index competition_sprint_phase on public.competition_captures(sprint_id,phase) where sprint_id is not null;
create unique index competition_annual_phase on public.competition_captures(championship_id,phase) where sprint_id is null;
create table public.competition_capture_scores(
 capture_id uuid not null references public.competition_captures(id),
 competitor_id uuid not null references public.competitors(id),
 nickname text not null,
 source_history_id bigint references public.score_history(id),
 declared_at timestamptz,
 ytd numeric(12,4),
 primary key(capture_id,competitor_id),
 check((source_history_id is null and declared_at is null and ytd is null) or
       (source_history_id is not null and declared_at is not null and ytd is not null and ytd>=-100))
);
create table public.competition_validations(
 id uuid primary key default gen_random_uuid(),
 championship_id uuid not null references public.championships(id),
 sprint_id uuid references public.sprints(id),
 start_capture_id uuid references public.competition_captures(id),
 end_capture_id uuid not null unique references public.competition_captures(id),
 validated_at timestamptz not null default clock_timestamp(),
 validated_by uuid not null references public.profiles(id),
 note text not null check(length(btrim(note)) between 10 and 2000),
 rows jsonb not null check(jsonb_typeof(rows)='array')
);
create unique index competition_sprint_validation on public.competition_validations(sprint_id) where sprint_id is not null;
create unique index competition_annual_validation on public.competition_validations(championship_id) where sprint_id is null;

alter table public.competition_captures enable row level security;
alter table public.competition_capture_scores enable row level security;
alter table public.competition_validations enable row level security;
revoke all on public.competition_captures,public.competition_capture_scores,public.competition_validations from public,anon,authenticated;
grant select on public.competition_captures,public.competition_capture_scores,public.competition_validations to authenticated;
create policy capture_read on public.competition_captures for select to authenticated using(true);
create policy capture_scores_read on public.competition_capture_scores for select to authenticated using(true);
create policy validation_read on public.competition_validations for select to authenticated using(true);

create function public.reject_competition_rewrite() returns trigger
language plpgsql set search_path='' as $$
begin raise exception using errcode='BC001',message='Registo de competição imutável'; end $$;
create trigger capture_immutable before update or delete on public.competition_captures
 for each row execute function public.reject_competition_rewrite();
create trigger capture_score_immutable before update or delete on public.competition_capture_scores
 for each row execute function public.reject_competition_rewrite();
create trigger validation_immutable before update or delete on public.competition_validations
 for each row execute function public.reject_competition_rewrite();
create trigger declaration_immutable before update or delete on public.score_history
 for each row execute function public.reject_competition_rewrite();
create trigger legacy_sprint_score_immutable before update or delete on public.sprint_scores
 for each row execute function public.reject_competition_rewrite();

-- Timestamp after acquiring the lock: a long-running transaction cannot backdate
-- a new declaration across a boundary. Capture and declaration share this lock.
create or replace function public.set_my_score(p_ytd numeric)
returns void language plpgsql security definer set search_path='' as $$
declare v_at timestamptz;
begin
 perform pg_advisory_xact_lock(941002);
 v_at=clock_timestamp();
 if p_ytd is null or p_ytd::text in ('NaN','Infinity','-Infinity') or p_ytd < -100 or p_ytd > 100000 then raise exception 'YTD inválido';end if;
 if not exists(select 1 from public.championships where state='open' and v_at between starts_at and ends_at) then raise exception 'Campeonato fechado';end if;
 update public.competitors set ytd=p_ytd,updated_at=v_at where id=auth.uid();
 if not found then raise exception 'Não és concorrente';end if;
 insert into public.score_history(competitor_id,ytd,created_at) values(auth.uid(),p_ytd,v_at);
end $$;

create or replace function public.vote_application(p_application uuid,p_approve boolean)
returns void language plpgsql security definer set search_path='' as $$
declare v_app public.applications%rowtype;v_yes integer;v_no integer;v_at timestamptz;
begin
 perform pg_advisory_xact_lock(941001);
 if not public.is_competitor() then raise exception 'Apenas concorrentes votam';end if;
 if p_approve is null then raise exception 'Voto inválido';end if;
 select * into v_app from public.applications where id=p_application for update;
 if not found or v_app.state<>'pending' then raise exception 'Candidatura indisponível';end if;
 if v_app.candidate_id=auth.uid() then raise exception 'Não podes votar na própria candidatura';end if;
 if not exists(select 1 from public.application_electorate where application_id=p_application and voter_id=auth.uid()) then raise exception 'Não pertences ao eleitorado desta votação';end if;
 v_at=clock_timestamp();
 insert into public.votes(application_id,voter_id,approve,created_at) values(p_application,auth.uid(),p_approve,v_at);
 select count(*) filter(where approve),count(*) filter(where not approve) into v_yes,v_no from public.votes where application_id=p_application;
 if v_yes > v_app.eligible_votes/2 then
  update public.applications set state='approved',decided_at=v_at where id=p_application;
  insert into public.competitors(id,joined_at) values(v_app.candidate_id,v_at);
 elsif v_no >= v_app.eligible_votes/2.0 then
  update public.applications set state='rejected',decided_at=v_at where id=p_application;
 end if;
end $$;

create or replace function public.get_competitors() returns table(id uuid,nickname text,ytd numeric,updated_at timestamptz)
language sql stable security definer set search_path='' as $$
 select c.id,p.nickname,c.ytd,c.updated_at from public.competitors c join public.profiles p on p.id=c.id
 order by c.ytd desc nulls last,c.id
$$;

-- Internal implementation; entry points below check admin and scope again.
create function public.capture_competition(p_championship uuid,p_sprint uuid,p_phase text)
returns integer language plpgsql security definer set search_path='' as $$
declare v_cutoff timestamptz;v_capture uuid;v_total integer;v_champ uuid;
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 if p_phase is null or p_phase not in ('start','end') or (p_sprint is null and p_phase<>'end') then raise exception using errcode='BC002',message='Fase inválida';end if;
 -- Same lock order for all admission/capture/validation operations.
 perform pg_advisory_xact_lock(941001);
 perform pg_advisory_xact_lock(941002);
 if p_sprint is null then
  select id,ends_at into v_champ,v_cutoff from public.championships where id=p_championship;
 else
  select championship_id,case when p_phase='start' then starts_at else ends_at end
   into v_champ,v_cutoff from public.sprints where id=p_sprint and championship_id=p_championship;
 end if;
 if v_champ is null then raise exception using errcode='BC002',message='Período inválido';end if;
 if clock_timestamp()<v_cutoff then raise exception using errcode='BC003',message='Limite ainda não atingido';end if;
 select id into v_capture from public.competition_captures where championship_id=v_champ
  and sprint_id is not distinct from p_sprint and phase=p_phase;
 if v_capture is not null then
  return (select count(*)::integer from public.competition_capture_scores where capture_id=v_capture);
 end if;
 if p_sprint is not null then
  if not exists(select 1 from public.competition_captures where sprint_id=p_sprint) and
     (exists(select 1 from public.sprint_scores where sprint_id=p_sprint) or
      exists(select 1 from public.sprints where id=p_sprint and state='closed')) then
   raise exception using errcode='BC004',message='Snapshots antigos sem proveniência; apenas consulta';
  end if;
  if p_phase='end' and not exists(select 1 from public.competition_captures where sprint_id=p_sprint and phase='start') then
   raise exception using errcode='BC005',message='Capturar primeiro o snapshot inicial';
  end if;
 end if;
 insert into public.competition_captures(championship_id,sprint_id,phase,cutoff_at,captured_by)
  values(v_champ,p_sprint,p_phase,v_cutoff,auth.uid()) returning id into v_capture;
 insert into public.competition_capture_scores(capture_id,competitor_id,nickname,source_history_id,declared_at,ytd)
 select v_capture,c.id,p.nickname,h.id,h.created_at,h.ytd
 from public.competitors c join public.profiles p on p.id=c.id
 left join lateral (
  select sh.id,sh.created_at,sh.ytd from public.score_history sh
  where sh.competitor_id=c.id and sh.created_at<=v_cutoff
  order by sh.created_at desc,sh.id desc limit 1
 ) h on true
 where c.joined_at<=v_cutoff;
 get diagnostics v_total=row_count;
 if p_sprint is not null then
  -- Preserve the legacy read-only RPC contract, but never synthesize missing YTD.
  insert into public.sprint_scores(sprint_id,competitor_id,phase,ytd)
   select p_sprint,competitor_id,p_phase,ytd from public.competition_capture_scores
   where capture_id=v_capture and ytd is not null;
  if p_phase='end' then update public.sprints set state='closed' where id=p_sprint;end if;
 else
  update public.championships set state='closed' where id=v_champ;
 end if;
 return v_total;
end $$;

create or replace function public.capture_sprint(p_sprint uuid,p_phase text)
returns integer language plpgsql security definer set search_path='' as $$
begin
 return public.capture_competition((select championship_id from public.sprints where id=p_sprint),p_sprint,p_phase);
end $$;
create function public.capture_championship(p_championship uuid)
returns integer language sql security definer set search_path='' as $$
 select public.capture_competition(p_championship,null,'end')
$$;

create function public.competition_rows(p_end uuid,p_start uuid,p_is_sprint boolean)
returns jsonb language sql stable security definer set search_path='' as $$
 with source as (
  select e.competitor_id,e.nickname,a.ytd as start_ytd,e.ytd as end_ytd,
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

create function public.get_competition_review(p_championship uuid,p_sprint uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_start public.competition_captures%rowtype;v_end public.competition_captures%rowtype;
 v_validation public.competition_validations%rowtype;v_from timestamptz;v_to timestamptz;v_legacy boolean:=false;v_rows jsonb;
begin
 if auth.uid() is null then raise exception using errcode='42501',message='Não autenticado';end if;
 if p_sprint is null then
  select starts_at,ends_at into v_from,v_to from public.championships where id=p_championship;
 else
  select starts_at,ends_at into v_from,v_to from public.sprints where id=p_sprint and championship_id=p_championship;
 end if;
 if not found then raise exception using errcode='BC002',message='Período inválido';end if;
 select * into v_start from public.competition_captures where championship_id=p_championship and sprint_id=p_sprint and phase='start';
 select * into v_end from public.competition_captures where championship_id=p_championship and sprint_id is not distinct from p_sprint and phase='end';
 select * into v_validation from public.competition_validations where championship_id=p_championship and sprint_id is not distinct from p_sprint;
 if p_sprint is not null and v_start.id is null and v_end.id is null then
  v_legacy:=exists(select 1 from public.sprint_scores where sprint_id=p_sprint) or exists(select 1 from public.sprints where id=p_sprint and state='closed');
 end if;
 v_rows:=coalesce(v_validation.rows,public.competition_rows(v_end.id,v_start.id,p_sprint is not null));
 return jsonb_build_object('starts_at',v_from,'ends_at',v_to,'legacy',v_legacy,
  'start_capture',case when v_start.id is not null then to_jsonb(v_start) end,
  'end_capture',case when v_end.id is not null then to_jsonb(v_end) end,
  'validation',case when v_validation.id is not null then to_jsonb(v_validation)-'rows' end,
  'rows',v_rows,
  'can_capture_start',not v_legacy and p_sprint is not null and v_start.id is null and now()>=v_from,
  'can_capture_end',not v_legacy and v_end.id is null and now()>=v_to and (p_sprint is null or v_start.id is not null),
  'can_validate',not v_legacy and v_validation.id is null and v_end.id is not null and exists(select 1 from jsonb_array_elements(v_rows) r where r->>'status'='complete'));
end $$;

create function public.validate_competition(p_championship uuid,p_sprint uuid,p_note text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_review jsonb;v_id uuid;
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 perform pg_advisory_xact_lock(941001);
 perform pg_advisory_xact_lock(941002);
 select id into v_id from public.competition_validations where championship_id=p_championship and sprint_id is not distinct from p_sprint;
 if v_id is not null then return v_id;end if;
 if p_note is null or length(btrim(p_note)) not between 10 and 2000 then raise exception using errcode='BC006',message='Nota de validação obrigatória';end if;
 v_review:=public.get_competition_review(p_championship,p_sprint);
 if not (v_review->>'can_validate')::boolean then raise exception using errcode='BC007',message='Classificação ainda não validável';end if;
 insert into public.competition_validations(championship_id,sprint_id,start_capture_id,end_capture_id,validated_by,note,rows)
 values(p_championship,p_sprint,(v_review#>>'{start_capture,id}')::uuid,(v_review#>>'{end_capture,id}')::uuid,auth.uid(),btrim(p_note),v_review->'rows') returning id into v_id;
 return v_id;
end $$;

revoke all on function public.reject_competition_rewrite(),public.capture_competition(uuid,uuid,text),public.competition_rows(uuid,uuid,boolean),
 public.capture_championship(uuid),public.get_competition_review(uuid,uuid),public.validate_competition(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.capture_championship(uuid),public.get_competition_review(uuid,uuid),public.validate_competition(uuid,uuid,text) to authenticated;
-- Existing RPC ACLs are preserved by CREATE OR REPLACE.
commit;
