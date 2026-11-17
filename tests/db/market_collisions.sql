\set ON_ERROR_STOP on
do $$begin
 if (select payload from public.legacy_migration_guard) is distinct from (select payload from public.legacy_migration_payload) then raise exception 'Collision migration rewrote history or contracts';end if;
 if (select payload from public.collision_audit_guard) is distinct from jsonb_build_object(
  'reconciliations',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.market_reconciliations x),
  'associations',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.market_bet_associations x),
  'definitions',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.bet_definitions x),
  'occurrences',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.bet_occurrences x)) then raise exception 'Collision migration changed calendar or prior audit';end if;
end $$;
drop table public.collision_audit_guard;
drop table public.legacy_migration_guard;
drop view public.legacy_migration_payload;
begin;
create function pg_temp.ck(ok boolean,msg text) returns void language plpgsql as $$begin if not coalesce(ok,false) then raise exception '%',msg;end if;end $$;
create function pg_temp.reject(command text,code text) returns void language plpgsql as $$begin
 begin execute command;exception when others then if sqlstate<>code then raise exception 'Expected %, got %: %',code,sqlstate,sqlerrm;end if;return;end;
 raise exception 'Unexpected acceptance: %',command;end $$;
insert into auth.users(id) values('eb000000-0000-4000-8000-000000000001'),('eb000000-0000-4000-8000-000000000002'),('eb000000-0000-4000-8000-000000000003');
insert into public.admins values('eb000000-0000-4000-8000-000000000001');
insert into public.competitors(id,joined_at) select id,now()-interval '1 hour' from auth.users where id::text like 'eb000000%';
insert into public.championships(name,starts_at,ends_at) values('Collision SQL','2026-01-01T00:00Z','2026-12-31T23:59:59Z') returning id as champ \gset
insert into public.score_history(competitor_id,ytd,created_at) values('eb000000-0000-4000-8000-000000000001',12,now()-interval '30 minutes'),('eb000000-0000-4000-8000-000000000002',15,now()-interval '30 minutes');
select set_config('request.jwt.claim.sub','eb000000-0000-4000-8000-000000000001',false);
select public.configure_recurring_bet(:'champ','weekly','snapshot_value',true)->>'definition_id' as value_def \gset
select public.configure_recurring_bet(:'champ','weekly','snapshot_delta_previous',true)->>'definition_id' as delta_def \gset
select id as occ,sprint_id as sprint from public.bet_occurrences where championship_id=:'champ' and kind='weekly' and starts_at<=now() and ends_at>now() \gset
select id as generated from public.markets where definition_id=:'value_def' and occurrence_id=:'occ' and category='winner' \gset
select public.create_competition_market('Legacy with resale',:'champ',:'sprint','winner','snapshot_value') as legacy \gset
select id as outcome from public.outcomes where market_id=:'legacy' and competitor_id=auth.uid() \gset
select public.place_offer(:'outcome','back',2,10) as offer \gset
select set_config('request.jwt.claim.sub','eb000000-0000-4000-8000-000000000002',false);
select public.accept_offer(:'offer',5);
select set_config('request.jwt.claim.sub','eb000000-0000-4000-8000-000000000001',false);
select id as position from public.positions where market_id=:'legacy' and owner_id=auth.uid() \gset
select public.list_position(:'position',7) as listing \gset
select set_config('request.jwt.claim.sub','eb000000-0000-4000-8000-000000000003',false);
select public.buy_position(:'listing');
select set_config('request.jwt.claim.sub','eb000000-0000-4000-8000-000000000001',false);
create temp view financial_payload as select jsonb_build_object(
 'wallets',(select jsonb_agg(to_jsonb(x) order by owner_id) from public.wallets x),
 'ledger',(select jsonb_agg(to_jsonb(x) order by id) from public.ledger x),
 'offers',(select jsonb_agg(to_jsonb(x) order by id) from public.offers x),
 'trades',(select jsonb_agg(to_jsonb(x) order by id) from public.trades x),
 'positions',(select jsonb_agg(to_jsonb(x) order by id) from public.positions x),
 'listings',(select jsonb_agg(to_jsonb(x) order by id) from public.listings x),
 'sales',(select jsonb_agg(to_jsonb(x) order by listing_id) from public.position_sales x),
 'outcomes',(select jsonb_agg(to_jsonb(x) order by id) from public.outcomes x)
) as payload;
create temp table financial_before as select * from financial_payload;
create temp table legacy_before as select to_jsonb(m)-'definition_id'-'occurrence_id' as payload from public.markets m where id=:'legacy';
create temp table generated_before as select to_jsonb(m)-'definition_id'-'occurrence_id'-'replaced_by_market_id' as payload from public.markets m where id=:'generated';
select public.preview_market_collision(:'legacy',:'value_def',:'occ') as plan \gset
select pg_temp.ck((:'plan'::jsonb->>'can_apply')::boolean,'Pristine generated can yield to an exposed compatible legacy');
select pg_temp.ck((select definition_id=:'value_def'::uuid from public.markets where id=:'generated'),'Preview does not detach');
select pg_temp.reject(format('select public.resolve_market_collision(%L,%L,%L,%L,%L)',:'legacy',:'value_def',:'occ','stale','Nota de revisão explícita'),'BL001');
select public.resolve_market_collision(:'legacy',:'value_def',:'occ',:'plan'::jsonb->>'fingerprint','Preservar o contrato legado e arquivar apenas o gerado intacto') as audit \gset
select pg_temp.ck(public.resolve_market_collision(:'legacy',:'value_def',:'occ',:'plan'::jsonb->>'fingerprint','Pedido repetido')=:'audit'::uuid,'Idempotent collision retry');
select pg_temp.ck((select payload from financial_before)=(select payload from financial_payload),'No financial/outcome mutation including resale cost/profit');
select pg_temp.ck((select to_jsonb(m)-'definition_id'-'occurrence_id'=(select payload from legacy_before) from public.markets m where id=:'legacy'),'Legacy contract unchanged');
select pg_temp.ck((select to_jsonb(m)-'definition_id'-'occurrence_id'-'replaced_by_market_id'=(select payload from generated_before) and state='open' and replaced_by_market_id=:'legacy'::uuid and definition_id is null and occurrence_id is null from public.markets m where id=:'generated'),'Generated identity preserved, not void/deleted');
select pg_temp.ck(public.get_market_classification(:'generated')->>'status'='replaced','Archive is not an invented classification');
select pg_temp.ck(public.get_bet_provisional_rankings(:'generated')->>'status'='replaced','No provisional ranking for retired identity');
select id as generated_outcome from public.outcomes where market_id=:'generated' limit 1 \gset
select pg_temp.reject(format('select public.place_offer(%L,%L,2,5)',:'generated_outcome','back'),'BK003');
select pg_temp.reject(format('select public.validate_market_classification(%L,%L)',:'generated','Tentativa de reapurar arquivo substituído'),'BK003');
select pg_temp.reject(format('select public.settle_market(%L,%L)',:'generated',:'generated_outcome'),'BK003');
select pg_temp.reject(format('update public.markets set replaced_by_market_id=null where id=%L',:'generated'),'BK003');
select pg_temp.reject(format('update public.markets set definition_id=null,occurrence_id=null where id=%L',:'legacy'),'BA003');
select pg_temp.reject(format('delete from public.outcomes where market_id=%L',:'generated'),'BK003');
select pg_temp.reject(format('delete from public.market_collision_resolutions where id=%L',:'audit'),'BC001');
select public.regenerate_bet_markets(:'champ');
select pg_temp.ck((select id=:'legacy'::uuid from public.markets where definition_id=:'value_def' and occurrence_id=:'occ' and category='winner'),'Regeneration retains the legacy identity');

-- A new genuine entry reaches the canonical market, never the archived placeholder.
insert into public.score_history(competitor_id,ytd) values('eb000000-0000-4000-8000-000000000003',0);
select pg_temp.ck(exists(select 1 from public.outcomes where market_id=:'legacy' and competitor_id='eb000000-0000-4000-8000-000000000003'),'New entry added to canonical market');
select pg_temp.ck(not exists(select 1 from public.outcomes where market_id=:'generated' and competitor_id='eb000000-0000-4000-8000-000000000003'),'Archived outcomes remain unchanged');
-- Second modality is preserved, without replacing its previous-END reference.
select public.create_competition_market('Legacy delta',:'champ',:'sprint','winner','snapshot_delta_previous') as delta \gset
select public.preview_market_collision(:'delta',:'delta_def',:'occ')->>'fingerprint' as token \gset
select public.resolve_market_collision(:'delta',:'delta_def',:'occ',:'token','Manter delta explícito e todas as referências de entrada');
select pg_temp.ck((select mode='snapshot_delta_previous' from public.markets where id=:'delta'),'No third modality or implicit criterion change');

-- Even a cancelled unmatched offer makes the generated contract non-pristine.
select id as contracted from public.markets where definition_id=:'value_def' and occurrence_id=:'occ' and category='second' \gset
select id as contracted_outcome from public.outcomes where market_id=:'contracted' limit 1 \gset
select public.place_offer(:'contracted_outcome','back',2,5) as cancelled \gset
select public.cancel_offer(:'cancelled');
select public.create_competition_market('Cannot merge these contracts',:'champ',:'sprint','second','snapshot_value') as blocked \gset
select public.preview_market_collision(:'blocked',:'value_def',:'occ') as blocked_plan \gset
select pg_temp.ck(:'blocked_plan'::jsonb->>'status'='generated_contracts_preserved','Cancelled offers block replacing generated');
select pg_temp.reject(format('select public.resolve_market_collision(%L,%L,%L,%L,%L)',:'blocked',:'value_def',:'occ',:'blocked_plan'::jsonb->>'fingerprint','Revisão de colisão com exposição preservada'),'BK002');
select pg_temp.ck((select definition_id=:'value_def'::uuid and replaced_by_market_id is null from public.markets where id=:'contracted'),'Blocked generated contract is untouched');
select pg_temp.ck((select definition_id is null from public.markets where id=:'blocked'),'Blocked legacy remains individual');
-- The bypass compatibility reader is never a public escape hatch.
set local role authenticated;
select set_config('request.jwt.claim.sub','eb000000-0000-4000-8000-000000000003',false);
select pg_temp.reject(format('select public.preview_market_collision(%L,%L,%L)',:'blocked',:'value_def',:'occ'),'42501');
select pg_temp.reject(format('select public.resolve_market_collision(%L,%L,%L,%L,%L)',:'blocked',:'value_def',:'occ',:'blocked_plan'::jsonb->>'fingerprint','Revisão não autorizada'),'42501');
select pg_temp.reject('delete from public.market_collision_resolutions','42501');
select pg_temp.ck(not has_function_privilege('authenticated','public.market_bet_association_plan(uuid,uuid,uuid,boolean)','execute'),'Compatibility bypass is private');
select pg_temp.ck(not has_function_privilege('authenticated','public.settle_market_before_collisions(uuid,uuid)','execute'),'Old settlement path stays private');
reset role;
select pg_temp.ck((select sum(available+reserved-total_issued)=0 from public.wallets),'Currency conserved');
rollback;
