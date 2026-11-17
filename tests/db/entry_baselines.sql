-- #11 initial reference and mid-period entry tests. Fixtures rollback.
\set ON_ERROR_STOP on
do $$begin
 if (select payload from public.entry_migration_payload) is distinct from (select payload from public.entry_migration_guard) then raise exception 'Migration rewrote history, contracts or financial data';end if;
 if not exists(select 1 from public.entry_baselines b join public.championships c on c.id=b.championship_id
  where c.name='Audited entry migration fixture' and b.competitor_id='e3000000-0000-4000-8000-000000000001' and b.ytd=12 and b.source_kind='audited_history') then raise exception 'Did not preserve the FIRST audited YTD';end if;
 if exists(select 1 from public.entry_baselines where competitor_id='e3000000-0000-4000-8000-000000000002') then raise exception 'Guessed baseline zero from current competitor row';end if;
end $$;
drop view public.entry_migration_payload;
drop table public.entry_migration_guard;
begin;
create function pg_temp.entry_check(ok boolean,msg text) returns void language plpgsql as $$
begin if not coalesce(ok,false) then raise exception '%',msg;end if;end $$;
create function pg_temp.entry_reject(command text,code text) returns void language plpgsql as $$
begin begin execute command;exception when others then
 if sqlstate<>code then raise exception 'Expected %, got %: %',code,sqlstate,sqlerrm;end if;return;
 end;raise exception 'Expected rejection: %',command;end $$;
insert into auth.users(id) values('e4000000-0000-4000-8000-000000000001'),('e4000000-0000-4000-8000-000000000002'),('e4000000-0000-4000-8000-000000000003');
insert into public.admins(id) values('e4000000-0000-4000-8000-000000000001');
insert into public.competitors(id) values('e4000000-0000-4000-8000-000000000001'),('e4000000-0000-4000-8000-000000000002');
insert into public.championships(name,starts_at,ends_at) values('Baseline activation','2026-01-01T00:00Z','2026-12-31T23:59:59Z') returning id as activation_champ \gset
select set_config('request.jwt.claim.sub','e4000000-0000-4000-8000-000000000001',false);
select public.configure_recurring_bet(:'activation_champ','weekly','snapshot_value',true);
select public.configure_recurring_bet(:'activation_champ','weekly','snapshot_delta_previous',true);
select pg_temp.entry_check(not exists(select 1 from public.markets where championship_id=:'activation_champ'),'Approval without initial scores must not create operative participants');
select pg_temp.entry_check((select x->>'status'='awaiting_initial' and x->>'baseline_id' is null from jsonb_array_elements(public.get_my_entry_baselines()) x where x->>'championship_id'=:'activation_champ'),'Explicit awaiting-initial state');
select public.declare_initial_ytd(:'activation_champ',12) as initial_id \gset
select pg_temp.entry_check(not exists(select 1 from public.markets where championship_id=:'activation_champ'),'One effective entry is not two participants');
select set_config('request.jwt.claim.sub','e4000000-0000-4000-8000-000000000002',false);
select public.declare_initial_ytd(:'activation_champ',0);
select pg_temp.entry_check(exists(select 1 from public.markets where championship_id=:'activation_champ'),'Second real baseline activates generation');
select pg_temp.entry_check((select ytd=0 from public.entry_baselines where championship_id=:'activation_champ' and competitor_id=auth.uid()),'Declared zero is valid');
select pg_temp.entry_check(not exists(select 1 from public.outcomes o join public.markets m on m.id=o.market_id where m.championship_id=:'activation_champ' and o.competitor_id not in ('e4000000-0000-4000-8000-000000000001','e4000000-0000-4000-8000-000000000002')),'No admitted-only outsiders in generated outcomes');
select set_config('request.jwt.claim.sub','e4000000-0000-4000-8000-000000000001',false);
select public.set_my_score(99);
select pg_temp.entry_check(public.declare_initial_ytd(:'activation_champ',12)=:'initial_id'::uuid,'Same initial request is idempotent');
select pg_temp.entry_check((select ytd=99 from public.competitors where id=auth.uid()),'Initial retry must not overwrite current YTD');
select pg_temp.entry_check((select ytd=12 from public.entry_baselines where id=:'initial_id'),'Later score must not overwrite baseline');
select pg_temp.entry_reject(format('select public.declare_initial_ytd(%L,13)',:'activation_champ'),'BE001');
select set_config('request.jwt.claim.sub','e4000000-0000-4000-8000-000000000003',false);
select pg_temp.entry_reject(format('select public.declare_initial_ytd(%L,1)',:'activation_champ'),'42501');

-- Audited chronological sources: A enters during period one; B participated earlier.
insert into auth.users(id) values('e5000000-0000-4000-8000-000000000001'),('e5000000-0000-4000-8000-000000000002'),('e5000000-0000-4000-8000-000000000003');
insert into public.competitors(id,joined_at) select id,now()-interval '12 days' from auth.users where id::text like 'e5000000%';
insert into public.championships(name,starts_at,ends_at) values('Partial-window reader fixture',now()-interval '20 days',now()+interval '2 days') returning id as champ \gset
insert into public.score_history(competitor_id,ytd,created_at) values
 ('e5000000-0000-4000-8000-000000000001',12,now()-interval '6 days'),
 ('e5000000-0000-4000-8000-000000000002',0,now()-interval '10 days');
select set_config('request.jwt.claim.sub','e4000000-0000-4000-8000-000000000001',false);
create function pg_temp.entry_market(c uuid,starts timestamptz,cut timestamptz,md text,prev_s uuid default null,prev_cut timestamptz default null)
returns uuid language plpgsql as $$
declare s uuid;m uuid;
begin
 select id into s from public.sprints where championship_id=c and kind='weekly' and starts_at=starts;
 if s is null then insert into public.sprints(championship_id,name,kind,starts_at,ends_at) values(c,'Entry fixture','weekly',starts,cut) returning id into s;end if;
 insert into public.markets(title,kind,category,closes_at,championship_id,sprint_id,mode,previous_championship_id,previous_sprint_id,previous_closes_at,entry_reference_enabled,entry_starts_at)
  values('Entry criterion','weekly','winner',cut,c,s,md,case when prev_s is not null then c end,prev_s,prev_cut,true,starts) returning id into m;
 insert into public.outcomes(market_id,competitor_id,label) select m,id,nickname from public.profiles where id in ('e5000000-0000-4000-8000-000000000001','e5000000-0000-4000-8000-000000000002');
 return m;
end $$;
create function pg_temp.entry_capture(c uuid,s uuid,cut timestamptz,a numeric,b numeric,b_penalty integer default 0)
returns uuid language plpgsql as $$
declare cap uuid;h bigint;
begin
 insert into public.competition_captures(championship_id,sprint_id,phase,cutoff_at,captured_by) values(c,s,'end',cut,auth.uid()) returning id into cap;
 if a is not null then
  insert into public.score_history(competitor_id,ytd,created_at) values('e5000000-0000-4000-8000-000000000001',a,cut-interval '1 hour') returning id into h;
  insert into public.competition_capture_scores(capture_id,competitor_id,nickname,source_history_id,declared_at,ytd) values(cap,'e5000000-0000-4000-8000-000000000001','A',h,cut-interval '1 hour',a);
 end if;
 insert into public.score_history(competitor_id,ytd,created_at) values('e5000000-0000-4000-8000-000000000002',b,cut-interval '1 hour') returning id into h;
 insert into public.competition_capture_scores(capture_id,competitor_id,nickname,source_history_id,declared_at,ytd,declared_ytd,penalty_pp,source_cutoff_at)
  values(cap,'e5000000-0000-4000-8000-000000000002','B',h,cut-interval '1 hour',b-b_penalty,b,b_penalty,cut-interval '1 hour');
 return cap;
end $$;
insert into public.sprints(championship_id,name,kind,starts_at,ends_at) values(:'champ','Previous','weekly',now()-interval '10 days',now()-interval '8 days') returning id as previous_sprint \gset
select pg_temp.entry_capture(:'champ',:'previous_sprint',now()-interval '8 days',null,10);
select pg_temp.entry_market(:'champ',now()-interval '7 days',now()-interval '5 days','snapshot_delta_previous',:'previous_sprint',now()-interval '8 days') as first_delta \gset
select sprint_id as first_sprint from public.markets where id=:'first_delta' \gset
select pg_temp.entry_capture(:'champ',:'first_sprint',now()-interval '5 days',15,12,1);
select pg_temp.entry_check((select (x->>'value')::numeric=3 and x->>'reference_kind'='entry_baseline' and (x->>'previous_ytd')::numeric=12 from jsonb_array_elements(public.get_market_classification(:'first_delta')->'rows') x where x->>'competitor_id'='e5000000-0000-4000-8000-000000000001'),'Entry 12 -> 15 must be +3 pp, with entry provenance');
select pg_temp.entry_check((select (x->>'value')::numeric=1 and x->>'reference_kind'='previous_snapshot' from jsonb_array_elements(public.get_market_classification(:'first_delta')->'rows') x where x->>'competitor_id'='e5000000-0000-4000-8000-000000000002'),'Earlier participant uses previous close, including local current penalty');
select public.validate_market_classification(:'first_delta','Validar janelas parciais e referências visíveis');
select pg_temp.entry_market(:'champ',now()-interval '4 days',now()-interval '2 days','snapshot_delta_previous',:'first_sprint',now()-interval '5 days') as next_delta \gset
select pg_temp.entry_market(:'champ',now()-interval '4 days',now()-interval '2 days','snapshot_value') as next_value \gset
select sprint_id as next_sprint from public.markets where id=:'next_delta' \gset
select pg_temp.entry_capture(:'champ',:'next_sprint',now()-interval '2 days',17,15);
select pg_temp.entry_check((select (x->>'value')::numeric=2 and (x->>'previous_ytd')::numeric=15 and x->>'reference_kind'='previous_snapshot' from jsonb_array_elements(public.get_market_classification(:'next_delta')->'rows') x where x->>'competitor_id'='e5000000-0000-4000-8000-000000000001'),'Next period is 15 -> 17 = 2, not baseline 12 reused forever');
select pg_temp.entry_check((select (x->>'value')::numeric=3 and (x->>'previous_ytd')::numeric=12 from jsonb_array_elements(public.get_market_classification(:'next_delta')->'rows') x where x->>'competitor_id'='e5000000-0000-4000-8000-000000000002'),'Previous penalty 12 -> 11 must not propagate');
select public.validate_market_classification(:'next_delta','Validar delta do período seguinte sem baseline permanente');
select public.validate_market_classification(:'next_value','Validar modalidade independente do valor absoluto');
select pg_temp.entry_check((select competitor_id='e5000000-0000-4000-8000-000000000001' from public.outcomes where id=(public.get_market_resolution(:'next_value')->>'winner_outcome_id')::uuid),'Absolute value winner A=17');
select pg_temp.entry_check((select competitor_id='e5000000-0000-4000-8000-000000000002' from public.outcomes where id=(public.get_market_resolution(:'next_delta')->>'winner_outcome_id')::uuid),'Delta winner B=3 versus A=2');
-- A later entry cannot join or alter the two already frozen periods.
select public.get_market_classification(:'first_delta')->'rows' as frozen_rows \gset
insert into public.score_history(competitor_id,ytd,created_at) values('e5000000-0000-4000-8000-000000000003',77,now()-interval '1 day');
select pg_temp.entry_check(public.get_market_classification(:'first_delta')->'rows'=:'frozen_rows'::jsonb,'Late baseline must not rewrite validated results');
select pg_temp.entry_check(not exists(select 1 from public.outcomes where market_id in (:'first_delta',:'next_delta',:'next_value') and competitor_id='e5000000-0000-4000-8000-000000000003'),'No historical outcome added');
select pg_temp.entry_check((select participation_status='not_yet_entered' from public.market_entry_reference(:'first_delta','e5000000-0000-4000-8000-000000000003',null)),'Late entry cannot be applied retroactively');

-- A first occurrence may be classified entirely from genuine entry baselines.
select pg_temp.entry_market(:'champ',now()-interval '7 days',now()-interval '5 days','snapshot_delta_previous') as no_previous \gset
-- Same first sprint already has an immutable end capture; B is older and must not fall back to entry.
select pg_temp.entry_check(public.get_market_classification(:'no_previous')->>'status'='waiting_previous_snapshot','Do not reuse older baselines when the previous snapshot is missing');
select pg_temp.entry_market(:'champ',now()-interval '11 days',now()-interval '5 days','snapshot_delta_previous') as first_occurrence \gset
select sprint_id as first_occurrence_sprint from public.markets where id=:'first_occurrence' \gset
select pg_temp.entry_capture(:'champ',:'first_occurrence_sprint',now()-interval '5 days',15,12);
select public.validate_market_classification(:'first_occurrence','Todos os participantes têm referência inicial genuína');
select pg_temp.entry_check((select previous_capture_id is null and entry_references from public.market_classifications where market_id=:'first_occurrence'),'A first occurrence can use genuine entry references without a fictional previous snapshot');
set role authenticated;
select pg_temp.entry_reject($q$update public.entry_baselines set ytd=0$q$,'42501');
select pg_temp.entry_reject($q$select public.market_entry_reference(null,null,null)$q$,'42501');
reset role;
select pg_temp.entry_reject($q$update public.entry_baselines set ytd=0$q$,'BC001');
select pg_temp.entry_check((select sum(available+reserved-total_issued)=0 from public.wallets),'No currency issued by baseline registration');
rollback;
