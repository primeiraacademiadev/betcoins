-- #11: replace an untouched generated placeholder with a compatible legacy market.
-- Versioned only, requires 01--16. No installation-time data rewriting.
begin;
alter table public.markets add column replaced_by_market_id uuid references public.markets(id),
 add check(replaced_by_market_id is null or replaced_by_market_id<>id);
create table public.market_collision_resolutions(
 id uuid primary key default gen_random_uuid(),generated_market_id uuid not null unique references public.markets(id),
 legacy_market_id uuid not null unique references public.markets(id),definition_id uuid not null references public.bet_definitions(id),
 occurrence_id uuid not null references public.bet_occurrences(id),fingerprint text not null,
 reviewed_by uuid not null references public.profiles(id),reviewed_at timestamptz not null default clock_timestamp(),
 note text not null check(length(btrim(note)) between 10 and 2000),plan jsonb not null,
 before_generated jsonb not null,after_generated jsonb not null,before_legacy jsonb not null,after_legacy jsonb not null,
 check(generated_market_id<>legacy_market_id)
);
alter table public.market_collision_resolutions enable row level security;
revoke all on public.market_collision_resolutions from public,anon,authenticated;
grant select on public.market_collision_resolutions to authenticated;
create policy collision_resolution_read on public.market_collision_resolutions for select to authenticated using(true);
create trigger collision_resolution_immutable before update or delete on public.market_collision_resolutions for each row execute function public.reject_competition_rewrite();

create function public.market_bet_association_plan(p_market uuid,p_definition uuid,p_occurrence uuid,p_allow_occupied boolean) returns jsonb
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
  when m.replaced_by_market_id is not null then 'market_replaced'
  when m.definition_id=p_definition and m.occurrence_id=p_occurrence then 'already_associated'
  when m.definition_id is not null or m.occurrence_id is not null then 'association_immutable'
  when occupant is not null and not p_allow_occupied then 'slot_occupied'
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
revoke all on function public.market_bet_association_plan(uuid,uuid,uuid,boolean) from public,anon,authenticated;
create or replace function public.preview_market_bet_association(p_market uuid,p_definition uuid,p_occurrence uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select public.market_bet_association_plan(p_market,p_definition,p_occurrence,false)
$$;

create or replace function public.sync_effective_outcomes(p_championship uuid) returns integer
language plpgsql security definer set search_path='' as $$
declare m uuid;n integer;v_count integer:=0;
begin
 perform pg_advisory_xact_lock(941001);perform pg_advisory_xact_lock(941002);perform pg_advisory_xact_lock(941003);
 for m in select x.id from public.markets x left join public.bet_definitions d on d.id=x.definition_id
   where x.replaced_by_market_id is null and x.championship_id=p_championship and x.entry_reference_enabled and (x.definition_id is null or d.active) and x.state='open' and x.closes_at>clock_timestamp()
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

create function public.preview_market_collision(p_market uuid,p_definition uuid,p_occurrence uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare legacy public.markets%rowtype;generated public.markets%rowtype;l jsonb;g jsonb;plan jsonb;block text;
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 l:=public.market_bet_association_plan(p_market,p_definition,p_occurrence,true);
 select * into legacy from public.markets where id=p_market;
 select * into generated from public.markets where id=(l->>'occupied_by')::uuid;
 if generated.id is not null then g:=public.market_bet_association_plan(generated.id,p_definition,p_occurrence,false);end if;
 block:=case
  when not coalesce((l->>'can_apply')::boolean,false) then l->>'status'
  when generated.id is null then 'no_collision'
  when legacy.closes_at<=clock_timestamp() or legacy.state<>'open' or generated.closes_at<=clock_timestamp() or generated.state<>'open' then 'historical_preserved'
  when generated.replaced_by_market_id is not null or exists(select 1 from public.market_bet_associations where market_id=generated.id)
   or exists(select 1 from public.market_collision_resolutions where generated_market_id=generated.id or legacy_market_id=generated.id) then 'generated_identity_preserved'
  when exists(select 1 from public.offers where market_id=generated.id) or exists(select 1 from public.trades where market_id=generated.id)
   or exists(select 1 from public.positions where market_id=generated.id) then 'generated_contracts_preserved'
  when exists(select 1 from public.market_classifications where market_id=generated.id) or exists(select 1 from public.market_resolutions where market_id=generated.id) then 'generated_results_preserved'
  when row(legacy.mode,legacy.championship_id,legacy.sprint_id,legacy.kind,legacy.category,legacy.closes_at,legacy.previous_championship_id,legacy.previous_sprint_id,legacy.previous_closes_at,legacy.entry_reference_enabled,legacy.entry_starts_at)
   is distinct from row(generated.mode,generated.championship_id,generated.sprint_id,generated.kind,generated.category,generated.closes_at,generated.previous_championship_id,generated.previous_sprint_id,generated.previous_closes_at,generated.entry_reference_enabled,generated.entry_starts_at) then 'contract_mismatch'
  when exists(
   (select competitor_id from public.outcomes where market_id=p_market except select competitor_id from public.outcomes where market_id=generated.id)
   union all (select competitor_id from public.outcomes where market_id=generated.id except select competitor_id from public.outcomes where market_id=p_market)
  ) then 'participants_mismatch'
 end;
 plan:=jsonb_build_object('status',coalesce(block,'ready'),'can_apply',block is null,'legacy',l,'generated',g,
  'generated_market_id',generated.id,'legacy_market_id',p_market,'paused',l->'paused');
 return plan||jsonb_build_object('fingerprint',md5(plan::text));
end $$;

create or replace function public.reject_market_bet_reassignment() returns trigger language plpgsql set search_path='' as $$
begin
 if row(new.definition_id,new.occurrence_id) is distinct from row(old.definition_id,old.occurrence_id)
  and not exists(select 1 from public.market_bet_associations a where a.market_id=old.id and a.before_market=to_jsonb(old) and a.after_market=to_jsonb(new))
  and not exists(select 1 from public.market_collision_resolutions a where
   (a.generated_market_id=old.id and a.before_generated=to_jsonb(old) and a.after_generated=to_jsonb(new))
   or (a.legacy_market_id=old.id and a.before_legacy=to_jsonb(old) and a.after_legacy=to_jsonb(new))) then
  raise exception using errcode='BA003',message='Associação exige revisão e é imutável';end if;
 return new;
end $$;
create function public.protect_replaced_market() returns trigger language plpgsql set search_path='' as $$
begin
 if old.replaced_by_market_id is not null and (tg_op='DELETE' or to_jsonb(new) is distinct from to_jsonb(old)) then
  raise exception using errcode='BK003',message='Mercado substituído é um arquivo imutável';end if;
 if tg_op='UPDATE' and new.replaced_by_market_id is distinct from old.replaced_by_market_id
  and not exists(select 1 from public.market_collision_resolutions a where a.generated_market_id=old.id and a.before_generated=to_jsonb(old) and a.after_generated=to_jsonb(new)) then
  raise exception using errcode='BK003',message='Substituição exige revisão de colisão';end if;
 return case when tg_op='DELETE' then old else new end;
end $$;
create trigger market_replacement_immutable before update or delete on public.markets for each row execute function public.protect_replaced_market();
create function public.protect_replaced_outcomes() returns trigger language plpgsql set search_path='' as $$
begin
 if exists(select 1 from public.markets where id=case when tg_op='DELETE' then old.market_id else new.market_id end and replaced_by_market_id is not null)
  or (tg_op='UPDATE' and exists(select 1 from public.markets where id=old.market_id and replaced_by_market_id is not null)) then
  raise exception using errcode='BK003',message='Outcomes de arquivo substituído são imutáveis';end if;
 return case when tg_op='DELETE' then old else new end;
end $$;
create trigger replaced_outcomes_immutable before insert or update or delete on public.outcomes for each row execute function public.protect_replaced_outcomes();

create function public.resolve_market_collision(p_market uuid,p_definition uuid,p_occurrence uuid,p_fingerprint text,p_note text) returns uuid
language plpgsql security definer set search_path='' as $$
declare l public.markets%rowtype;g public.markets%rowtype;after_l public.markets%rowtype;after_g public.markets%rowtype;plan jsonb;prior public.market_collision_resolutions%rowtype;result uuid;
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 perform pg_advisory_xact_lock(941001);perform pg_advisory_xact_lock(941002);perform pg_advisory_xact_lock(941003);
 select * into prior from public.market_collision_resolutions where legacy_market_id=p_market;
 if found and prior.definition_id=p_definition and prior.occurrence_id=p_occurrence and prior.fingerprint=p_fingerprint then return prior.id;end if;
 if p_note is null or length(btrim(p_note)) not between 10 and 2000 then raise exception using errcode='BC006',message='Nota de revisão obrigatória';end if;
 perform 1 from public.markets where id=p_market or (definition_id=p_definition and occurrence_id=p_occurrence and category=(select category from public.markets where id=p_market)) order by id for update;
 plan:=public.preview_market_collision(p_market,p_definition,p_occurrence);
 if p_fingerprint is distinct from plan->>'fingerprint' then raise exception using errcode='BL001',message='A pré-visualização mudou; revê novamente';end if;
 if not (plan->>'can_apply')::boolean then raise exception using errcode='BK002',message='Colisão preservada; não é permitida fusão de contratos';end if;
 select * into l from public.markets where id=p_market;
 select * into g from public.markets where id=(plan->>'generated_market_id')::uuid;
 after_l:=l;after_l.definition_id:=p_definition;after_l.occurrence_id:=p_occurrence;
 after_g:=g;after_g.definition_id:=null;after_g.occurrence_id:=null;after_g.replaced_by_market_id:=l.id;
 insert into public.market_collision_resolutions(generated_market_id,legacy_market_id,definition_id,occurrence_id,fingerprint,reviewed_by,note,plan,before_generated,after_generated,before_legacy,after_legacy)
  values(g.id,l.id,p_definition,p_occurrence,p_fingerprint,auth.uid(),btrim(p_note),plan,to_jsonb(g),to_jsonb(after_g),to_jsonb(l),to_jsonb(after_l)) returning id into result;
 -- Both identities survive. No state=void and no deletion/refund/position movement.
 update public.markets set definition_id=null,occurrence_id=null,replaced_by_market_id=l.id where id=g.id;
 update public.markets set definition_id=p_definition,occurrence_id=p_occurrence where id=l.id;
 return result;
end $$;

alter function public.lock_trading_market(uuid) rename to lock_trading_market_before_collisions;
revoke all on function public.lock_trading_market_before_collisions(uuid) from public,anon,authenticated;
create function public.lock_trading_market(p_market uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform public.lock_trading_market_before_collisions(p_market);
 if exists(select 1 from public.markets where id=p_market and replaced_by_market_id is not null) then raise exception using errcode='BK003',message='Mercado substituído; consulta o contrato associado';end if;
end $$;
revoke all on function public.lock_trading_market(uuid) from public,anon,authenticated;

alter function public.get_market_classification(uuid) rename to get_market_classification_before_collisions;
revoke all on function public.get_market_classification_before_collisions(uuid) from public,anon,authenticated;
create function public.get_market_classification(p_market uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare replacement uuid;
begin
 if auth.uid() is null then raise exception using errcode='42501',message='Não autenticado';end if;
 select replaced_by_market_id into replacement from public.markets where id=p_market;
 if replacement is not null then return jsonb_build_object('status','replaced','can_validate',false,'rows','[]'::jsonb,'replaced_by_market_id',replacement);end if;
 return public.get_market_classification_before_collisions(p_market);
end $$;
alter function public.get_bet_provisional_rankings(uuid) rename to get_bet_provisional_before_collisions;
revoke all on function public.get_bet_provisional_before_collisions(uuid) from public,anon,authenticated;
create function public.get_bet_provisional_rankings(p_market uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare replacement uuid;
begin
 if auth.uid() is null then raise exception using errcode='42501',message='Não autenticado';end if;
 select replaced_by_market_id into replacement from public.markets where id=p_market;
 if replacement is not null then return jsonb_build_object('status','replaced','rows','[]'::jsonb,'replaced_by_market_id',replacement);end if;
 return public.get_bet_provisional_before_collisions(p_market);
end $$;
alter function public.validate_market_classification(uuid,text) rename to validate_market_before_collisions;
revoke all on function public.validate_market_before_collisions(uuid,text) from public,anon,authenticated;
create function public.validate_market_classification(p_market uuid,p_note text) returns uuid language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 perform pg_advisory_xact_lock(941001);perform pg_advisory_xact_lock(941002);perform pg_advisory_xact_lock(941003);
 if exists(select 1 from public.markets where id=p_market and replaced_by_market_id is not null) then raise exception using errcode='BK003',message='Arquivo substituído não pode ser validado';end if;
 return public.validate_market_before_collisions(p_market,p_note);
end $$;
alter function public.settle_market(uuid,uuid) rename to settle_market_before_collisions;
revoke all on function public.settle_market_before_collisions(uuid,uuid) from public,anon,authenticated;
create function public.settle_market(p_market uuid,p_winner uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 perform pg_advisory_xact_lock(941003);
 if exists(select 1 from public.markets where id=p_market and replaced_by_market_id is not null) then raise exception using errcode='BK003',message='Arquivo substituído não pode liquidar';end if;
 perform public.settle_market_before_collisions(p_market,p_winner);
end $$;
revoke all on function public.preview_market_collision(uuid,uuid,uuid),public.resolve_market_collision(uuid,uuid,uuid,text,text),public.protect_replaced_market(),public.protect_replaced_outcomes(),public.get_market_classification(uuid),public.get_bet_provisional_rankings(uuid),public.validate_market_classification(uuid,text),public.settle_market(uuid,uuid) from public,anon,authenticated;
grant execute on function public.preview_market_collision(uuid,uuid,uuid),public.resolve_market_collision(uuid,uuid,uuid,text,text),public.get_market_classification(uuid),public.get_bet_provisional_rankings(uuid),public.validate_market_classification(uuid,text),public.settle_market(uuid,uuid) to authenticated;
commit;
