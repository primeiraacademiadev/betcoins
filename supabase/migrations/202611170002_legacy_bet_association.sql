-- #11: reviewed metadata-only association. Versioned only, requires 01--15.
begin;
create table public.market_bet_associations(
 id uuid primary key default gen_random_uuid(),market_id uuid not null unique references public.markets(id),
 definition_id uuid not null references public.bet_definitions(id),occurrence_id uuid not null references public.bet_occurrences(id),
 fingerprint text not null,reviewed_by uuid not null references public.profiles(id),reviewed_at timestamptz not null default clock_timestamp(),
 note text not null check(length(btrim(note)) between 10 and 2000),plan jsonb not null,before_market jsonb not null,after_market jsonb not null
);
alter table public.market_bet_associations enable row level security;
revoke all on public.market_bet_associations from public,anon,authenticated;
grant select on public.market_bet_associations to authenticated;
create policy market_bet_association_read on public.market_bet_associations for select to authenticated using(true);
create trigger market_bet_association_immutable before update or delete on public.market_bet_associations for each row execute function public.reject_competition_rewrite();

-- Preparing a destination must never suspend an already-active definition or
-- generate competing markets before the administrator has reviewed associations.
create function public.prepare_bet_for_association(p_championship uuid,p_kind text,p_mode text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d uuid;n integer;
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 perform pg_advisory_xact_lock(941001);perform pg_advisory_xact_lock(941002);perform pg_advisory_xact_lock(941003);
 if p_kind is null or p_kind not in ('annual','monthly','weekly') or p_mode is null or p_mode not in ('snapshot_value','snapshot_delta_previous')
  or not exists(select 1 from public.championships where id=p_championship and state='open') then raise exception using errcode='BR001',message='Definição inválida';end if;
 if exists(select 1 from public.bet_definitions where championship_id=p_championship and kind=p_kind and mode=p_mode and active) then
  raise exception using errcode='BA002',message='Bet já ativa; preparar não suspende nem substitui mercados';end if;
 n:=public.prepare_bet_occurrences(p_championship);
 insert into public.bet_definitions(championship_id,kind,mode,active) values(p_championship,p_kind,p_mode,false)
  on conflict(championship_id,kind,mode) do nothing;
 select id into d from public.bet_definitions where championship_id=p_championship and kind=p_kind and mode=p_mode;
 return jsonb_build_object('definition_id',d,'new_occurrences',n,'new_markets',0,'new_outcomes',0,'blocked_occurrences',0);
end $$;

create function public.preview_market_bet_association(p_market uuid,p_definition uuid,p_occurrence uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare m public.markets%rowtype;d public.bet_definitions%rowtype;o public.bet_occurrences%rowtype;previous public.bet_occurrences%rowtype;
 ref jsonb;eligible jsonb;outcomes jsonb;block text;occupant uuid;historical boolean;captured boolean;frozen boolean;plan jsonb;history_hash text;source_hash text;
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 select * into m from public.markets where id=p_market;
 if not found then raise exception using errcode='BM003',message='Mercado inválido';end if;
 select * into d from public.bet_definitions where id=p_definition;
 select * into o from public.bet_occurrences where id=p_occurrence;
 historical:=m.closes_at<=clock_timestamp() or m.state<>'open';
 select id into occupant from public.markets where definition_id=p_definition and occurrence_id=p_occurrence and category=m.category and id<>p_market;
 if d.mode='snapshot_delta_previous' and o.id is not null then
  if o.kind='annual' then ref:=public.get_previous_market_period(o.championship_id,null);
  else
   select * into previous from public.bet_occurrences where id=o.previous_occurrence_id;
   if found then ref:=jsonb_build_object('championship_id',previous.championship_id,'sprint_id',previous.sprint_id,'ends_at',previous.ends_at);end if;
  end if;
 end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) into outcomes from public.outcomes x where market_id=p_market;
 select coalesce(jsonb_agg(jsonb_build_object('baseline_id',b.id,'competitor_id',b.competitor_id,'effective_at',b.effective_at) order by b.competitor_id),'[]'::jsonb) into eligible
  from public.entry_baselines b where b.championship_id=m.championship_id and b.effective_at<=clock_timestamp() and b.effective_at<=m.closes_at;
 captured:=exists(select 1 from public.competition_captures c where c.championship_id=m.championship_id and c.sprint_id is not distinct from m.sprint_id and c.phase='end' and c.cutoff_at=m.closes_at);
 frozen:=exists(select 1 from public.market_classifications where market_id=p_market)
  or exists(select 1 from public.market_resolutions where market_id=p_market)
  or exists(select 1 from public.final_round_occurrences where occurrence_id=p_occurrence)
  or exists(select 1 from public.competition_captures c where c.championship_id=m.championship_id and c.sprint_id is not distinct from m.sprint_id and c.phase='end');
 -- Only opaque signatures of economic/source data enter the public audit.
 select md5(coalesce(jsonb_agg(to_jsonb(q) order by q.kind,q.id)::text,'')) into history_hash from (
  select 'offer' as kind,x.id,to_jsonb(x) as row from public.offers x where market_id=p_market
  union all select 'trade',x.id,to_jsonb(x) from public.trades x where market_id=p_market
  union all select 'position',x.id,to_jsonb(x) from public.positions x where market_id=p_market
  union all select 'listing',x.id,to_jsonb(x) from public.listings x join public.positions p on p.id=x.position_id where p.market_id=p_market
 ) q;
 select md5(coalesce(jsonb_agg(to_jsonb(q) order by q.kind,q.id)::text,'')) into source_hash from (
  select 'capture' as kind,c.id,to_jsonb(c) as row from public.competition_captures c where c.championship_id=m.championship_id and c.sprint_id is not distinct from m.sprint_id
  union all select 'classification',v.id,to_jsonb(v) from public.market_classifications v where market_id=p_market
  union all select 'resolution',r.market_id,to_jsonb(r) from public.market_resolutions r where market_id=p_market
 ) q;
 block:=case
  when d.id is null or o.id is null or d.championship_id<>o.championship_id or d.kind<>o.kind
   or (o.sprint_id is null and not exists(select 1 from public.championships c where c.id=o.championship_id and c.starts_at=o.starts_at and c.ends_at=o.ends_at))
   or (o.sprint_id is not null and not exists(select 1 from public.sprints s where s.id=o.sprint_id and s.championship_id=o.championship_id and s.kind=o.kind and s.starts_at=o.starts_at and s.ends_at=o.ends_at)) then 'invalid_target'
  when m.definition_id=p_definition and m.occurrence_id=p_occurrence then 'already_associated'
  when m.definition_id is not null or m.occurrence_id is not null then 'association_immutable'
  when occupant is not null then 'slot_occupied'
  when m.mode is null then 'explicit_mode_required'
  when m.championship_id is distinct from o.championship_id or m.sprint_id is distinct from o.sprint_id or m.kind<>o.kind or m.closes_at<>o.ends_at or m.mode<>d.mode then 'contract_mismatch'
  when m.entry_reference_enabled and m.entry_starts_at is distinct from o.starts_at then 'contract_mismatch'
  when d.mode='snapshot_delta_previous' and (coalesce((ref->>'ambiguous')::boolean,false) or row(m.previous_championship_id,m.previous_sprint_id,m.previous_closes_at) is distinct from row((ref->>'championship_id')::uuid,(ref->>'sprint_id')::uuid,(ref->>'ends_at')::timestamptz)) then 'previous_mismatch'
  when m.state not in ('open','settled') then 'unsupported_state'
  when not historical and (not exists(select 1 from public.championships c where c.id=o.championship_id and c.state='open')
   or (o.sprint_id is not null and not exists(select 1 from public.sprints s where s.id=o.sprint_id and s.state='open'))) then 'target_closed'
  when historical and m.state='open' and not captured then 'historical_without_snapshot'
  when not historical and frozen then 'frozen_live_period'
  when not historical and not m.entry_reference_enabled then 'entry_policy_required'
  when not historical and (jsonb_array_length(eligible)<2 or exists(
   (select x->>'competitor_id' from jsonb_array_elements(outcomes) x except select x->>'competitor_id' from jsonb_array_elements(eligible) x)
   union all (select x->>'competitor_id' from jsonb_array_elements(eligible) x except select x->>'competitor_id' from jsonb_array_elements(outcomes) x)
  )) then 'participants_mismatch'
 end;
 plan:=jsonb_build_object('market_id',m.id,'definition',to_jsonb(d),'occurrence',to_jsonb(o),'before_market',to_jsonb(m),
  'status',coalesce(block,'ready'),'can_apply',block is null,'historical',historical,'paused',not d.active,
  'occupied_by',occupant,'outcomes',outcomes,'eligible',case when not historical then eligible else '[]'::jsonb end,
  'history_hash',history_hash,'source_hash',source_hash,'previous_reference',ref);
 return plan||jsonb_build_object('fingerprint',md5(plan::text));
end $$;

create function public.reject_market_bet_reassignment() returns trigger language plpgsql set search_path='' as $$
begin
 if row(new.definition_id,new.occurrence_id) is distinct from row(old.definition_id,old.occurrence_id)
  and not exists(select 1 from public.market_bet_associations a where a.market_id=old.id and a.before_market=to_jsonb(old) and a.after_market=to_jsonb(new)) then
  raise exception using errcode='BA003',message='Associação exige revisão e é imutável';end if;
 return new;
end $$;
create trigger market_bet_identity_immutable before update of definition_id,occurrence_id on public.markets for each row execute function public.reject_market_bet_reassignment();

create function public.associate_legacy_market(p_market uuid,p_definition uuid,p_occurrence uuid,p_fingerprint text,p_note text) returns uuid
language plpgsql security definer set search_path='' as $$
declare m public.markets%rowtype;after_m public.markets%rowtype;plan jsonb;prior public.market_bet_associations%rowtype;result uuid;
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 perform pg_advisory_xact_lock(941001);perform pg_advisory_xact_lock(941002);perform pg_advisory_xact_lock(941003);
 select * into m from public.markets where id=p_market for update;
 select * into prior from public.market_bet_associations where market_id=p_market;
 if found and prior.definition_id=p_definition and prior.occurrence_id=p_occurrence and prior.fingerprint=p_fingerprint then return prior.id;end if;
 if p_note is null or length(btrim(p_note)) not between 10 and 2000 then raise exception using errcode='BC006',message='Nota de associação obrigatória';end if;
 plan:=public.preview_market_bet_association(p_market,p_definition,p_occurrence);
 if p_fingerprint is distinct from plan->>'fingerprint' then raise exception using errcode='BL001',message='A pré-visualização mudou; revê novamente';end if;
 if not (plan->>'can_apply')::boolean then raise exception using errcode='BA002',message='Associação bloqueada; contrato e calendário preservados';end if;
 after_m:=m;after_m.definition_id:=p_definition;after_m.occurrence_id:=p_occurrence;
 insert into public.market_bet_associations(market_id,definition_id,occurrence_id,fingerprint,reviewed_by,note,plan,before_market,after_market)
  values(p_market,p_definition,p_occurrence,p_fingerprint,auth.uid(),btrim(p_note),plan,to_jsonb(m),to_jsonb(after_m)) returning id into result;
 update public.markets set definition_id=p_definition,occurrence_id=p_occurrence where id=p_market;
 return result;
end $$;
revoke all on function public.prepare_bet_for_association(uuid,text,text),public.preview_market_bet_association(uuid,uuid,uuid),public.associate_legacy_market(uuid,uuid,uuid,text,text),public.reject_market_bet_reassignment() from public,anon,authenticated;
grant execute on function public.prepare_bet_for_association(uuid,text,text),public.preview_market_bet_association(uuid,uuid,uuid),public.associate_legacy_market(uuid,uuid,uuid,text,text) to authenticated;
commit;
