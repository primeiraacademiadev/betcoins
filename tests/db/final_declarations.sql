-- Closing declarations/penalties: disposable databases only; all fixtures rollback.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values
 ('d3000000-0000-4000-8000-000000000001'),('d3000000-0000-4000-8000-000000000002'),
 ('d3000000-0000-4000-8000-000000000003'),('d3000000-0000-4000-8000-000000000004'),('d3000000-0000-4000-8000-000000000005');
insert into public.admins(id) values('d3000000-0000-4000-8000-000000000001');
insert into public.competitors(id,joined_at) select id,now()-interval '30 days' from auth.users where id::text like 'd3000000%' and id<>'d3000000-0000-4000-8000-000000000005';
insert into public.score_history(competitor_id,ytd,created_at) select id,12,now()-interval '10 days' from public.competitors where id::text like 'd3000000%' and id<>'d3000000-0000-4000-8000-000000000004';
insert into public.championships(name,starts_at,ends_at) values('Current update scope',now()-interval '1 day',now()+interval '1 day');
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000001',false);
create function pg_temp.final_check(ok boolean,msg text) returns void language plpgsql as $$
begin if not coalesce(ok,false) then raise exception '%',msg;end if;end $$;
create function pg_temp.final_reject(command text,code text) returns void language plpgsql as $$
begin begin execute command;exception when others then
 if sqlstate<>code then raise exception 'Expected %, got %: %',code,sqlstate,sqlerrm;end if;return;
 end;raise exception 'Expected rejection: %',command;end $$;
create function pg_temp.final_occurrence(c uuid,k text,cut timestamptz,people uuid[],prev uuid default null)
returns uuid language plpgsql as $$
declare o uuid;s uuid;d uuid;m uuid;prior public.bet_occurrences%rowtype;
begin
 if k<>'annual' then insert into public.sprints(championship_id,name,kind,starts_at,ends_at) values(c,'Closing fixture',k,cut-interval '1 day',cut) returning id into s;end if;
 insert into public.bet_occurrences(championship_id,kind,period_key,name,starts_at,ends_at,sprint_id,previous_occurrence_id)
  values(c,k,cut::text,'Final '||k,cut-interval '1 day',cut,s,prev) returning id into o;
 insert into public.bet_definitions(championship_id,kind,mode,active) values(c,k,'snapshot_value',false) on conflict do nothing;
 select id into d from public.bet_definitions where championship_id=c and kind=k and mode='snapshot_value';
 insert into public.markets(title,kind,category,closes_at,championship_id,sprint_id,mode,definition_id,occurrence_id)
  values('Closing value',k,'winner',cut,c,s,'snapshot_value',d,o) returning id into m;
 insert into public.outcomes(market_id,competitor_id,label) select m,p.id,p.nickname from public.profiles p where p.id=any(people);
 if prev is not null then
  select * into prior from public.bet_occurrences where id=prev;
  insert into public.bet_definitions(championship_id,kind,mode,active) values(c,k,'snapshot_delta_previous',false) on conflict do nothing;
  select id into d from public.bet_definitions where championship_id=c and kind=k and mode='snapshot_delta_previous';
  insert into public.markets(title,kind,category,closes_at,championship_id,sprint_id,mode,definition_id,occurrence_id,previous_championship_id,previous_sprint_id,previous_closes_at)
   values('Closing delta',k,'winner',cut,c,s,'snapshot_delta_previous',d,o,c,prior.sprint_id,prior.ends_at) returning id into m;
  insert into public.outcomes(market_id,competitor_id,label) select m,p.id,p.nickname from public.profiles p where p.id=any(people);
 end if;
 return o;
end $$;
insert into public.championships(name,starts_at,ends_at) values('Coincident finals',now()-interval '30 days',now()-interval '3 days') returning id as champ \gset
select pg_temp.final_occurrence(:'champ',k,now()-interval '3 days',array['d3000000-0000-4000-8000-000000000001','d3000000-0000-4000-8000-000000000002','d3000000-0000-4000-8000-000000000003','d3000000-0000-4000-8000-000000000004']::uuid[]) from unnest(array['weekly','monthly','annual']) k;
select public.get_final_rounds(:'champ');
select id as round from public.final_rounds where championship_id=:'champ' \gset
select pg_temp.final_check((select count(*)=3 from public.final_round_occurrences where round_id=:'round'),'Three coincident scopes share one round');
select pg_temp.final_reject(format('select public.capture_sprint(%L,''end'')',(select sprint_id from public.bet_occurrences where championship_id=:'champ' and kind='weekly')),'BF005');
select public.set_final_deadline(:'round',clock_timestamp()+interval '4 seconds','Prazo explícito escolhido pela gestão');
select deadline_at as promised_deadline from public.final_rounds where id=:'round' \gset
select pg_temp.final_reject(format('select public.finalize_final_round(%L,''Cannot shorten promised window'')',:'round'),'BF003');
set role authenticated;
select pg_temp.final_reject($q$select public.set_current_score_core(99)$q$,'42501');
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000005',false);
select pg_temp.final_reject(format('select public.declare_final_score(%L,1)',:'round'),'42501');
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000002',false);
select pg_temp.final_check(jsonb_array_length(public.get_my_final_declarations())=1,'One pending item, not three');
select pg_temp.final_reject('select public.set_my_score(99)','BF001');
select pg_temp.final_reject(format('select public.declare_final_score(%L,''NaN''::numeric)',:'round'),'BF004');
select pg_temp.final_reject(format('select public.declare_final_score(%L,1.12345)',:'round'),'BF004');
reset role;
select count(*) as history_before from public.score_history \gset
set role authenticated;
select public.declare_final_score(:'round',16.5) as declaration \gset
select pg_temp.final_check(public.declare_final_score(:'round',16.5)=:'declaration'::uuid,'Same declaration retry must be idempotent');
select pg_temp.final_reject(format('select public.declare_final_score(%L,17)',:'round'),'BC001');
reset role;
select pg_temp.final_check((select count(*)=:'history_before'::integer from public.score_history),'Final declaration must not enter current score history');
set role authenticated;
select public.set_my_score(99);
reset role;
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000001',false);
select pg_sleep(greatest(0,extract(epoch from(:'promised_deadline'::timestamptz-clock_timestamp())))+.02);
select public.finalize_final_round(:'round','Recolha concluída; apurar ausências explícitas');
select public.finalize_final_round(:'round','Repetir sem modificar snapshots ou pagamentos');
select pg_temp.final_check((select count(*)=3 from public.competition_captures where championship_id=:'champ' and phase='end'),'Exactly three frozen snapshots');
select pg_temp.final_check((select count(*)=3 from public.competition_capture_scores where closing_declaration_id=:'declaration' and ytd=16.5 and penalty_pp=0),'Single declaration used in every coincident scope');
select pg_temp.final_check((select count(*)=3 from public.competition_capture_scores s join public.competition_captures c on c.id=s.capture_id where c.championship_id=:'champ' and competitor_id='d3000000-0000-4000-8000-000000000003' and declared_ytd=12 and ytd=11 and penalty_pp=1 and score_origin='missing_final'),'Original 12, effective 11, local -1 pp');
select pg_temp.final_check((select count(*)=3 from public.competition_capture_scores s join public.competition_captures c on c.id=s.capture_id where c.championship_id=:'champ' and competitor_id='d3000000-0000-4000-8000-000000000004' and ytd is null and penalty_pp=0 and score_origin='missing_baseline'),'No baseline is not a fake zero or penalty');
select pg_temp.final_check((select ytd=99 from public.competitors where id='d3000000-0000-4000-8000-000000000002'),'Snapshot must not overwrite live YTD');
select pg_temp.final_check((select bool_and(ytd=12) from public.score_history where competitor_id='d3000000-0000-4000-8000-000000000003'),'Penalty must not rewrite source history');
select pg_temp.final_reject(format('select public.declare_final_score(%L,1)',:'round'),'BF002');
select pg_temp.final_reject(format('update public.final_rounds set state=''collecting'' where id=%L',:'round'),'BC001');

-- Two consecutive periods: previous penalty never becomes the next delta baseline.
insert into public.championships(name,starts_at,ends_at) values('Consecutive finals',now()-interval '30 days',now()+interval '1 day') returning id as next_champ \gset
select pg_temp.final_occurrence(:'next_champ','weekly',now()-interval '2 days',array['d3000000-0000-4000-8000-000000000002','d3000000-0000-4000-8000-000000000003']::uuid[]) as prev_occ \gset
select pg_temp.final_occurrence(:'next_champ','weekly',now()-interval '1 day',array['d3000000-0000-4000-8000-000000000002','d3000000-0000-4000-8000-000000000003']::uuid[],:'prev_occ') as current_occ \gset
select public.get_final_rounds(:'next_champ');
select id as prev_round from public.final_rounds where championship_id=:'next_champ' and cutoff_at=now()-interval '2 days' \gset
select id as current_round from public.final_rounds where championship_id=:'next_champ' and cutoff_at=now()-interval '1 day' \gset
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000003',false);
select pg_temp.final_reject(format('select public.declare_final_score(%L,14)',:'current_round'),'BF001');
reset role;
-- Historical source fixture: this original declaration was known BEFORE the next cutoff.
insert into public.closing_declarations(round_id,competitor_id,ytd,submitted_at) values(:'prev_round','d3000000-0000-4000-8000-000000000003',14,now()-interval '2 days'+interval '1 hour');
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000001',false);
select public.finalize_final_round(:'prev_round','Fechar referência anterior com omissão local');
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000002',false);
select public.declare_final_score(:'current_round',12);
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000001',false);
select public.finalize_final_round(:'current_round','Fechar atual sem acumular penalizações anteriores');
select id as value_market from public.markets where occurrence_id=:'current_occ' and mode='snapshot_value' \gset
select id as delta_market from public.markets where occurrence_id=:'current_occ' and mode='snapshot_delta_previous' \gset
select pg_temp.final_check((select (x->>'value')::numeric=0 and (x->>'previous_ytd')::numeric=12 from jsonb_array_elements(public.get_market_classification(:'delta_market')->'rows') x where x->>'competitor_id'='d3000000-0000-4000-8000-000000000002'),'Previous effective 11 must not replace original baseline 12');
select pg_temp.final_check((select (x->>'declared_ytd')::numeric=14 and (x->>'end_ytd')::numeric=13 and (x->>'penalty_pp')::integer=1 from jsonb_array_elements(public.get_market_classification(:'value_market')->'rows') x where x->>'competitor_id'='d3000000-0000-4000-8000-000000000003'),'Latest original final declaration is a known source, without accumulating prior penalties');
select public.validate_market_classification(:'value_market','Validar o valor efetivo no snapshot atual');
select public.validate_market_classification(:'delta_market','Validar delta com referência anterior original');
select pg_temp.final_check((select competitor_id='d3000000-0000-4000-8000-000000000003' from public.outcomes where id=(public.get_market_resolution(:'value_market')->>'winner_outcome_id')::uuid),'Value winner must be C=13');
select pg_temp.final_check((select competitor_id='d3000000-0000-4000-8000-000000000002' from public.outcomes where id=(public.get_market_resolution(:'delta_market')->>'winner_outcome_id')::uuid),'Delta winner must be B=0, C=-1');

set role authenticated;
select pg_temp.final_reject($q$select public.finalize_final_round(null,'Unauthorized finalize')$q$,'BF003');
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000002',false);
select pg_temp.final_reject($q$select public.set_final_deadline(null,now()+interval '1 day','Unauthorized deadline')$q$,'42501');
select pg_temp.final_reject($q$select public.finalize_final_round(null,'Unauthorized finalize')$q$,'42501');
select pg_temp.final_reject($q$select public.closing_score_source(null,now())$q$,'42501');
select pg_temp.final_reject($q$update public.closing_declarations set ytd=0$q$,'42501');
reset role;
select pg_temp.final_reject($q$update public.closing_declarations set ytd=0$q$,'BC001');
select pg_temp.final_check((select sum(available+reserved-total_issued)=0 from public.wallets),'No money changes from declarations/penalties');
rollback;
