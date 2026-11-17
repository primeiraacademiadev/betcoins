-- Current-model acceptance, no legacy import or compatibility fixtures.
\set ON_ERROR_STOP on
begin;
create function pg_temp.ck(ok boolean,msg text) returns void language plpgsql as $$begin if not coalesce(ok,false) then raise exception '%',msg;end if;end $$;
create function pg_temp.reject(command text,code text) returns void language plpgsql as $$begin
 begin execute command;exception when others then if sqlstate<>code then raise exception 'Expected %, got %: %',code,sqlstate,sqlerrm;end if;return;end;
 raise exception 'Unexpected acceptance: %',command;end $$;
insert into auth.users(id) values('ed000000-0000-4000-8000-000000000001'),('ed000000-0000-4000-8000-000000000002'),('ed000000-0000-4000-8000-000000000003');
insert into public.admins values('ed000000-0000-4000-8000-000000000001');
insert into public.competitors(id) values('ed000000-0000-4000-8000-000000000001'),('ed000000-0000-4000-8000-000000000002');
insert into public.championships(name,starts_at,ends_at) values('Acceptance current model','2026-01-01T00:00Z','2026-12-31T23:59:59Z') returning id as champ \gset
select set_config('request.jwt.claim.sub','ed000000-0000-4000-8000-000000000001',false);
select public.declare_initial_ytd(:'champ',12);
select set_config('request.jwt.claim.sub','ed000000-0000-4000-8000-000000000002',false);
select public.declare_initial_ytd(:'champ',15);
select set_config('request.jwt.claim.sub','ed000000-0000-4000-8000-000000000001',false);
select public.configure_recurring_bet(:'champ',kind,mode,true) from unnest(array['annual','monthly','weekly']) kind cross join unnest(array['snapshot_value','snapshot_delta_previous']) mode;
select id as market,occurrence_id as occ from public.markets where championship_id=:'champ' and kind='weekly' and mode='snapshot_value' and category='winner' order by closes_at limit 1 \gset
select pg_temp.ck(not exists(select 1 from public.markets where championship_id=:'champ' and (mode is null or definition_id is null or occurrence_id is null)),'Current generated model has explicit scope/mode');
select pg_temp.ck((select bool_and(x->>'status'='waiting_final_results' and jsonb_array_length(x->'rows')=0) from jsonb_array_elements(public.get_occurrence_results(:'occ')) x),'No current-score fallback for missing frozen results');
select id as outcome from public.outcomes where market_id=:'market' and competitor_id=auth.uid() \gset
select public.place_offer(:'outcome','back',2,5) as first_offer \gset
select public.place_offer(:'outcome','back',3,5);
select public.place_offer(:'outcome','lay',2,5);
select set_config('request.jwt.claim.sub','ed000000-0000-4000-8000-000000000002',false);
select public.accept_offer(:'first_offer',2);
select set_config('request.jwt.claim.sub','ed000000-0000-4000-8000-000000000001',false);
select public.cancel_offer(:'first_offer');
-- Tied timestamps exercise the stable event-ID cursor, using disposable fixtures.
update public.offers set created_at=transaction_timestamp() where market_id=:'market';
update public.trades set created_at=transaction_timestamp() where market_id=:'market';
select count(*) as ledger_count from public.ledger \gset
select public.get_market_activity(:'market',null,null,100) as activity \gset
select pg_temp.ck(jsonb_array_length(:'activity'::jsonb->'events')=4,'Cancelled/filled creation events and executions are retained');
select pg_temp.ck(exists(select 1 from jsonb_array_elements(:'activity'::jsonb->'events') e where e->>'kind'='offer' and e->>'state'='cancelled' and (e->>'stake_remaining')::integer=0),'Cancelled offer is visible with current remaining quantity');
select pg_temp.ck(exists(select 1 from jsonb_array_elements(:'activity'::jsonb->'events') e where e->>'kind'='trade' and (e->>'stake')::integer=2 and (e->>'liability')::numeric=2),'Executed stake and liability are visible');
select pg_temp.ck(:'activity' not like '%owner_id%' and :'activity' not like '%cost_basis%' and :'activity' not like '%wallet%','Activity does not publish private identities/costs/balances');
create temp table activity_target(id uuid);insert into activity_target values(:'market');
do $$declare p jsonb;before_at timestamptz;before_id text;seen text[]:='{}';event text;iterations integer:=0;begin
 loop
  p:=public.get_market_activity((select id from activity_target),before_at,before_id,1);
  if jsonb_array_length(p->'events')=0 then exit;end if;
  event:=p#>>'{events,0,id}';if event=any(seen) then raise exception 'Duplicate pagination event';end if;
  seen:=array_append(seen,event);iterations:=iterations+1;
  if not (p->>'has_more')::boolean then exit;end if;
  before_at:=(p#>>'{next_cursor,at}')::timestamptz;before_id:=p#>>'{next_cursor,id}';
  if iterations>10 then raise exception 'Cursor did not terminate';end if;
 end loop;
 if cardinality(seen)<>4 then raise exception 'Tied timestamps lost activity events';end if;
end $$;
select pg_temp.reject(format('select public.get_market_activity(%L,null,null,0)',:'market'),'BM002');
select pg_temp.reject(format('select public.get_market_activity(%L,now(),null,1)',:'market'),'BM002');
select pg_temp.reject('select public.get_market_activity(''ffffffff-ffff-4fff-8fff-ffffffffffff'')','BM003');
select pg_temp.ck((select count(*)=:'ledger_count'::integer from public.ledger),'Read-only history/statistics do not touch money');
set local role authenticated;
select set_config('request.jwt.claim.sub','ed000000-0000-4000-8000-000000000003',false);
select pg_temp.ck(jsonb_array_length(public.get_market_activity(:'market')->'events')=4,'Spectator can consult market executions');
select pg_temp.reject('delete from public.occurrence_classifications','42501');
select pg_temp.ck(not has_function_privilege('authenticated','public.persist_occurrence_classification(uuid)','execute'),'Materialization is private');
select pg_temp.ck(not has_function_privilege('authenticated','public.finalize_final_round_sources(uuid,text)','execute'),'Source-only finalization is private');
select pg_temp.ck(not has_function_privilege('authenticated','public.create_competition_market(text,uuid,uuid,text)','execute'),'Ambiguous individual creation is retired');
select pg_temp.ck(not has_function_privilege('authenticated','public.create_competition_market(text,uuid,uuid,text,text)','execute'),'Individual creation is outside the current recurring flow');
select pg_temp.ck(not has_function_privilege('authenticated','public.associate_legacy_market(uuid,uuid,uuid,text,text)','execute'),'No legacy association endpoint is exposed');
select pg_temp.ck(not has_function_privilege('authenticated','public.settle_recurring_market_core(uuid,uuid)','execute'),'Settlement cannot bypass the recurring scope guard');
select set_config('request.jwt.claim.sub','',false);
select pg_temp.reject(format('select public.get_market_activity(%L)',:'market'),'42501');
select pg_temp.reject(format('select public.get_occurrence_results(%L)',:'occ'),'42501');
reset role;
select pg_temp.ck((select sum(available+reserved-total_issued)=0 from public.wallets),'Currency conserved');
rollback;
