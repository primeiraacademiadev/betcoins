-- #11: reviewed reconciliation of untouched legacy contracts. Versioned only.
-- Requires 01--14. No remote installation or automatic historical rewriting.
begin;
create table public.market_reconciliations(
 id uuid primary key default gen_random_uuid(),market_id uuid not null references public.markets(id),
 fingerprint text not null,reviewed_by uuid not null references public.profiles(id),
 reviewed_at timestamptz not null default clock_timestamp(),note text not null check(length(btrim(note)) between 10 and 2000),
 plan jsonb not null,before_market jsonb not null,after_market jsonb not null,
 before_outcomes jsonb not null,after_outcomes jsonb not null,unique(market_id,fingerprint)
);
alter table public.market_reconciliations enable row level security;
revoke all on public.market_reconciliations from public,anon,authenticated;
grant select on public.market_reconciliations to authenticated;
create policy reconciliation_read on public.market_reconciliations for select to authenticated using(true);
create trigger reconciliation_immutable before update or delete on public.market_reconciliations for each row execute function public.reject_competition_rewrite();

-- Caller chooses the period and mode; titles and current YTD never infer either.
create function public.preview_legacy_market(p_market uuid,p_championship uuid,p_sprint uuid,p_mode text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare m public.markets%rowtype;target jsonb;prev jsonb;old_out jsonb;eligible jsonb;removed jsonb;added jsonb;
 start_at timestamptz;end_at timestamptz;kind text;blocked text;financial boolean;frozen boolean;plan jsonb;
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 select * into m from public.markets where id=p_market;
 if not found then raise exception using errcode='BM003',message='Mercado inválido';end if;
 if p_sprint is null then
  select c.starts_at,c.ends_at,'annual' into start_at,end_at,kind from public.championships c where c.id=p_championship and c.state='open';
 else
  select s.starts_at,s.ends_at,s.kind into start_at,end_at,kind from public.sprints s join public.championships c on c.id=s.championship_id
   where s.id=p_sprint and s.championship_id=p_championship and s.state='open' and c.state='open';
 end if;
 if p_mode='snapshot_delta_previous' then prev:=public.get_previous_market_period(p_championship,p_sprint);end if;
 select coalesce(jsonb_agg(to_jsonb(o) order by o.id),'[]'::jsonb) into old_out from public.outcomes o where market_id=p_market;
 select coalesce(jsonb_agg(jsonb_build_object('competitor_id',b.competitor_id,'baseline_id',b.id,'effective_at',b.effective_at,'label',p.nickname) order by b.competitor_id),'[]'::jsonb)
  into eligible from public.entry_baselines b join public.profiles p on p.id=b.competitor_id
  where b.championship_id=p_championship and b.effective_at<=clock_timestamp() and b.effective_at<=m.closes_at;
 select coalesce(jsonb_agg(x order by x->>'id'),'[]'::jsonb) into removed from jsonb_array_elements(old_out) x
  where not exists(select 1 from jsonb_array_elements(eligible) e where e->>'competitor_id'=x->>'competitor_id');
 select coalesce(jsonb_agg(e order by e->>'competitor_id'),'[]'::jsonb) into added from jsonb_array_elements(eligible) e
  where not exists(select 1 from jsonb_array_elements(old_out) x where e->>'competitor_id'=x->>'competitor_id');
 financial:=exists(select 1 from public.offers where market_id=p_market)
  or exists(select 1 from public.trades where market_id=p_market) or exists(select 1 from public.positions where market_id=p_market);
 frozen:=exists(select 1 from public.market_classifications where market_id=p_market)
  or exists(select 1 from public.market_resolutions where market_id=p_market)
  or exists(select 1 from public.competition_captures c where c.phase='end' and
   ((c.championship_id=m.championship_id and c.sprint_id is not distinct from m.sprint_id)
    or (c.championship_id=p_championship and c.sprint_id is not distinct from p_sprint)))
  or exists(select 1 from public.final_round_occurrences f join public.bet_occurrences o on o.id=f.occurrence_id
   where o.id=m.occurrence_id or (o.championship_id=p_championship and o.sprint_id is not distinct from p_sprint));
 blocked:=case
  when m.state<>'open' or m.closes_at<=clock_timestamp() then 'historical_preserved'
  when frozen then 'frozen_preserved'
  when financial then 'contracts_preserved'
  when start_at is null or end_at<>m.closes_at or kind<>m.kind or p_mode is null or p_mode not in ('snapshot_value','snapshot_delta_previous') then 'period_or_mode_required'
  when m.mode is not null and (m.mode<>p_mode or m.championship_id is distinct from p_championship or m.sprint_id is distinct from p_sprint) then 'contract_mismatch'
  when m.definition_id is not null and not exists(select 1 from public.bet_definitions d where d.id=m.definition_id and d.active) then 'definition_paused'
  when p_mode='snapshot_delta_previous' and coalesce((prev->>'ambiguous')::boolean,false) then 'ambiguous_previous'
  when m.mode='snapshot_delta_previous' and row(m.previous_championship_id,m.previous_sprint_id,m.previous_closes_at) is distinct from row((prev->>'championship_id')::uuid,(prev->>'sprint_id')::uuid,(prev->>'ends_at')::timestamptz) then 'contract_mismatch'
  when jsonb_array_length(eligible)<2 then 'awaiting_initial_scores'
 end;
 target:=jsonb_build_object('championship_id',p_championship,'sprint_id',p_sprint,'mode',p_mode,'entry_reference_enabled',true,'entry_starts_at',start_at,
  'previous_championship_id',(prev->>'championship_id')::uuid,'previous_sprint_id',(prev->>'sprint_id')::uuid,'previous_closes_at',(prev->>'ends_at')::timestamptz);
 if blocked is null and m.entry_reference_enabled and removed='[]'::jsonb and added='[]'::jsonb then blocked:='already_aligned';end if;
 plan:=jsonb_build_object('market_id',p_market,'status',coalesce(blocked,'ready'),'can_apply',blocked is null,'target',target,
  'before_market',to_jsonb(m),'before_outcomes',old_out,'eligible',eligible,'remove',removed,'add',added,'has_contracts',financial,'has_frozen_sources',frozen);
 return plan||jsonb_build_object('fingerprint',md5(plan::text));
end $$;

-- The only exception to immutability is the exact reviewed pristine transition.
create or replace function public.reject_market_redefinition() returns trigger language plpgsql set search_path='' as $$
begin
 if old.mode is not null and row(new.mode,new.championship_id,new.sprint_id,new.closes_at,new.previous_championship_id,new.previous_sprint_id,new.previous_closes_at,new.category,new.entry_reference_enabled,new.entry_starts_at)
  is distinct from row(old.mode,old.championship_id,old.sprint_id,old.closes_at,old.previous_championship_id,old.previous_sprint_id,old.previous_closes_at,old.category,old.entry_reference_enabled,old.entry_starts_at)
  and not exists(select 1 from public.market_reconciliations a where a.market_id=old.id and a.before_market=to_jsonb(old) and a.after_market=to_jsonb(new)) then
  raise exception using errcode='BP001',message='Critério e referências do mercado são imutáveis';end if;
 return new;
end $$;

create function public.reconcile_legacy_market(p_market uuid,p_championship uuid,p_sprint uuid,p_mode text,p_fingerprint text,p_note text) returns uuid
language plpgsql security definer set search_path='' as $$
declare plan jsonb;m public.markets%rowtype;after_m public.markets%rowtype;new_out jsonb;result uuid;prior public.market_reconciliations%rowtype;
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 perform pg_advisory_xact_lock(941001);perform pg_advisory_xact_lock(941002);perform pg_advisory_xact_lock(941003);
 select * into m from public.markets where id=p_market for update;
 select * into prior from public.market_reconciliations where market_id=p_market and fingerprint=p_fingerprint;
 if found and prior.plan#>>'{target,championship_id}'=p_championship::text and (prior.plan#>>'{target,sprint_id}') is not distinct from p_sprint::text and prior.plan#>>'{target,mode}'=p_mode then return prior.id;end if;
 if p_note is null or length(btrim(p_note)) not between 10 and 2000 then raise exception using errcode='BC006',message='Nota de revisão obrigatória';end if;
 plan:=public.preview_legacy_market(p_market,p_championship,p_sprint,p_mode);
 if p_fingerprint is distinct from plan->>'fingerprint' then raise exception using errcode='BL001',message='A pré-visualização mudou; revê novamente';end if;
 if not (plan->>'can_apply')::boolean then raise exception using errcode='BL002',message='Contrato preservado; reconciliação automática bloqueada';end if;
 after_m:=jsonb_populate_record(m,plan->'target');
 -- Build the exact post-state once, keeping all existing eligible outcome IDs/labels.
 select coalesce(jsonb_agg(x order by x->>'id'),'[]'::jsonb) into new_out from (
  select x from jsonb_array_elements(plan->'before_outcomes') x where not exists(select 1 from jsonb_array_elements(plan->'remove') r where r->>'id'=x->>'id')
  union all select jsonb_build_object('id',gen_random_uuid(),'market_id',p_market,'competitor_id',e->>'competitor_id','label',e->>'label') from jsonb_array_elements(plan->'add') e
 ) q;
 insert into public.market_reconciliations(market_id,fingerprint,reviewed_by,note,plan,before_market,after_market,before_outcomes,after_outcomes)
  values(p_market,p_fingerprint,auth.uid(),btrim(p_note),plan,to_jsonb(m),to_jsonb(after_m),plan->'before_outcomes',new_out) returning id into result;
 update public.markets set championship_id=after_m.championship_id,sprint_id=after_m.sprint_id,mode=after_m.mode,
  previous_championship_id=after_m.previous_championship_id,previous_sprint_id=after_m.previous_sprint_id,previous_closes_at=after_m.previous_closes_at,
  entry_reference_enabled=after_m.entry_reference_enabled,entry_starts_at=after_m.entry_starts_at where id=p_market;
 delete from public.outcomes where market_id=p_market and id in(select (x->>'id')::uuid from jsonb_array_elements(plan->'remove') x);
 insert into public.outcomes(id,market_id,competitor_id,label) select (x->>'id')::uuid,p_market,(x->>'competitor_id')::uuid,x->>'label' from jsonb_array_elements(new_out) x on conflict(market_id,competitor_id) do nothing;
 return result;
end $$;

-- Quarantine ambiguous or prematurely published universes, without touching money.
-- Cancellation and reviewed settlement retain their existing independent paths.
create or replace function public.lock_trading_market(p_market uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform public.lock_trading_market_core(p_market);
 if exists(select 1 from public.markets m join public.bet_definitions d on d.id=m.definition_id where m.id=p_market and not d.active) then
  raise exception using errcode='BR003',message='Bet recorrente suspensa';end if;
 if exists(select 1 from public.markets m where m.id=p_market and (m.mode is null or
  (m.entry_reference_enabled and exists(select 1 from public.outcomes o where o.market_id=m.id and not exists(
   select 1 from public.entry_baselines b where b.championship_id=m.championship_id and b.competitor_id=o.competitor_id and b.effective_at<=clock_timestamp() and b.effective_at<=m.closes_at))))) then
  raise exception using errcode='BL002',message='Mercado legado requer reconciliação antes de negociar';end if;
end $$;
revoke all on function public.preview_legacy_market(uuid,uuid,uuid,text),public.reconcile_legacy_market(uuid,uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.preview_legacy_market(uuid,uuid,uuid,text),public.reconcile_legacy_market(uuid,uuid,uuid,text,text,text) to authenticated;
commit;
