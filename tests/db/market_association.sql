\set ON_ERROR_STOP on
do $$begin
 if (select payload from public.legacy_migration_guard) is distinct from (select payload from public.legacy_migration_payload) then raise exception 'Association migration rewrote existing data';end if;
 if (select payload from public.market_association_source_guard) is distinct from jsonb_build_object(
  'reconciliations',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.market_reconciliations x),
  'definitions',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.bet_definitions x),
  'occurrences',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.bet_occurrences x)) then raise exception 'Association migration changed calendar/audit';end if;
end $$;
drop table public.market_association_source_guard;
drop table public.legacy_migration_guard;
drop view public.legacy_migration_payload;
begin;
create function pg_temp.ck(ok boolean,msg text) returns void language plpgsql as $$begin if not coalesce(ok,false) then raise exception '%',msg;end if;end $$;
create function pg_temp.reject(command text,code text) returns void language plpgsql as $$begin
 begin execute command;exception when others then if sqlstate<>code then raise exception 'Expected %, got %: %',code,sqlstate,sqlerrm;end if;return;end;
 raise exception 'Unexpected acceptance: %',command;end $$;
insert into auth.users(id) values('e9000000-0000-4000-8000-000000000001'),('e9000000-0000-4000-8000-000000000002'),('e9000000-0000-4000-8000-000000000003');
insert into public.admins values('e9000000-0000-4000-8000-000000000001');
insert into public.competitors(id,joined_at) select id,now()-interval '1 hour' from auth.users where id::text like 'e9000000%';
insert into public.championships(name,starts_at,ends_at) values('Association SQL','2026-01-01T00:00Z','2026-12-31T23:59:59Z') returning id as champ \gset
insert into public.score_history(competitor_id,ytd,created_at) values('e9000000-0000-4000-8000-000000000001',12,now()-interval '30 minutes'),('e9000000-0000-4000-8000-000000000002',15,now()-interval '30 minutes');
select set_config('request.jwt.claim.sub','e9000000-0000-4000-8000-000000000001',false);
select public.prepare_bet_for_association(:'champ','weekly','snapshot_value')->>'definition_id' as value_def \gset
select public.prepare_bet_for_association(:'champ','weekly','snapshot_delta_previous')->>'definition_id' as delta_def \gset
select id as occ,sprint_id as sprint,previous_occurrence_id as prev from public.bet_occurrences where championship_id=:'champ' and kind='weekly' and starts_at<=now() and ends_at>now() \gset
select public.create_competition_market('Existing value contract',:'champ',:'sprint','winner','snapshot_value') as value_market \gset
select public.create_competition_market('Existing delta contract',:'champ',:'sprint','winner','snapshot_delta_previous') as delta_market \gset
select id as outcome from public.outcomes where market_id=:'value_market' and competitor_id=auth.uid() \gset
select public.place_offer(:'outcome','back',2,10) as offer \gset
select set_config('request.jwt.claim.sub','e9000000-0000-4000-8000-000000000002',false);
select public.accept_offer(:'offer',5);
select set_config('request.jwt.claim.sub','e9000000-0000-4000-8000-000000000001',false);
create temp table contract_before as select to_jsonb(m)-'definition_id'-'occurrence_id' as payload from public.markets m where id=:'value_market';
create temp table financial_before as select jsonb_build_object(
 'wallets',(select jsonb_agg(to_jsonb(x) order by owner_id) from public.wallets x),
 'offers',(select jsonb_agg(to_jsonb(x) order by id) from public.offers x),
 'trades',(select jsonb_agg(to_jsonb(x) order by id) from public.trades x),
 'positions',(select jsonb_agg(to_jsonb(x) order by id) from public.positions x),
 'ledger',(select jsonb_agg(to_jsonb(x) order by id) from public.ledger x),
 'outcomes',(select jsonb_agg(to_jsonb(x) order by id) from public.outcomes x)
) as payload;
select public.preview_market_bet_association(:'value_market',:'value_def',:'occ') as plan \gset
select pg_temp.ck((:'plan'::jsonb->>'can_apply')::boolean and (:'plan'::jsonb->>'paused')::boolean,'Metadata-only association supports existing exposure and previews suspension');
select pg_temp.ck((select definition_id is null from public.markets where id=:'value_market'),'Preview has no write');
select pg_temp.reject(format('select public.associate_legacy_market(%L,%L,%L,%L,%L)',:'value_market',:'value_def',:'occ','wrong','Nota de associação revista'),'BL001');
select pg_temp.reject(format('select public.associate_legacy_market(%L,%L,%L,%L,%L)',:'value_market',:'value_def',:'occ',:'plan'::jsonb->>'fingerprint','curta'),'BC006');
select public.associate_legacy_market(:'value_market',:'value_def',:'occ',:'plan'::jsonb->>'fingerprint','Associar contrato e rever efeito da suspensão da bet') as audit \gset
select pg_temp.ck(public.associate_legacy_market(:'value_market',:'value_def',:'occ',:'plan'::jsonb->>'fingerprint','Pedido repetido')=:'audit'::uuid,'Idempotent repeated review');
select pg_temp.ck((select to_jsonb(m)-'definition_id'-'occurrence_id'=(select payload from contract_before) from public.markets m where id=:'value_market'),'Only the two association fields changed');
select pg_temp.ck((select payload from financial_before)=jsonb_build_object(
 'wallets',(select jsonb_agg(to_jsonb(x) order by owner_id) from public.wallets x),
 'offers',(select jsonb_agg(to_jsonb(x) order by id) from public.offers x),
 'trades',(select jsonb_agg(to_jsonb(x) order by id) from public.trades x),
 'positions',(select jsonb_agg(to_jsonb(x) order by id) from public.positions x),
 'ledger',(select jsonb_agg(to_jsonb(x) order by id) from public.ledger x),
 'outcomes',(select jsonb_agg(to_jsonb(x) order by id) from public.outcomes x)),'Association preserves every financial row and outcome');
select pg_temp.reject(format('select public.accept_offer(%L,1)',:'offer'),'BR003');
select pg_temp.ck(public.preview_market_bet_association(:'delta_market',:'value_def',:'occ')->>'status'='slot_occupied','No implicit replacement of generated/associated market');
select public.preview_market_bet_association(:'delta_market',:'delta_def',:'occ')->>'fingerprint' as token \gset
select public.associate_legacy_market(:'delta_market',:'delta_def',:'occ',:'token','Associar modalidade delta sem alterar as referências');
select pg_temp.reject(format('update public.markets set definition_id=null,occurrence_id=null where id=%L',:'value_market'),'BA003');
select pg_temp.reject(format('delete from public.market_bet_associations where id=%L',:'audit'),'BC001');
select public.configure_recurring_bet(:'champ','weekly','snapshot_value',true);
select pg_temp.ck((select id=:'value_market'::uuid from public.markets where definition_id=:'value_def' and occurrence_id=:'occ' and category='winner'),'Generator reuses legacy identity');
select pg_temp.ck((select count(*)=1 from public.markets where definition_id=:'value_def' and occurrence_id=:'occ' and category='winner'),'No duplicate after repeated generation');
select pg_temp.reject(format('select public.prepare_bet_for_association(%L,%L,%L)',:'champ','weekly','snapshot_value'),'BA002');
select public.regenerate_bet_markets(:'champ');
select pg_temp.ck(public.preview_market_bet_association(:'value_market',:'value_def',:'occ')->>'status'='already_associated','Association is visible in recurring navigation');

-- Absent policy, wrong mode, wrong period and missing participants are never repaired implicitly.
select public.create_competition_market('Wrong period',:'champ',:'sprint','last','snapshot_value') as wrong \gset
select pg_temp.ck(public.preview_market_bet_association(:'wrong',:'delta_def',:'occ')->>'status'='contract_mismatch','No mode inference');
insert into public.outcomes(market_id,competitor_id,label) values(:'wrong','e9000000-0000-4000-8000-000000000003','No initial YTD');
-- Free second place under the inactive delta definition; a value market still cannot change mode.
select public.create_competition_market('Ineligible universe',:'champ',:'sprint','second','snapshot_delta_previous') as bad_universe \gset
insert into public.outcomes(market_id,competitor_id,label) values(:'bad_universe','e9000000-0000-4000-8000-000000000003','No initial YTD');
select pg_temp.ck(public.preview_market_bet_association(:'bad_universe',:'delta_def',:'occ')->>'status'='participants_mismatch','Requires reconciliation before metadata association');
select id as future_occ from public.bet_occurrences where championship_id=:'champ' and kind='weekly' and starts_at>now() order by starts_at limit 1 \gset
select pg_temp.ck(public.preview_market_bet_association(:'bad_universe',:'delta_def',:'future_occ')->>'status'='contract_mismatch','Cutoff and exact sprint must match');

insert into public.markets(title,kind,category,closes_at,championship_id,sprint_id,mode,entry_reference_enabled,entry_starts_at)
 select 'Mismatched previous close','weekly','last',ends_at,championship_id,sprint_id,'snapshot_delta_previous',true,starts_at from public.bet_occurrences where id=:'occ' returning id as bad_reference \gset
select pg_temp.ck(public.preview_market_bet_association(:'bad_reference',:'delta_def',:'occ')->>'status'='previous_mismatch','Association cannot rewrite the previous reference');
select public.prepare_bet_for_association(:'champ','annual','snapshot_value')->>'definition_id' as annual_def \gset
select id as annual_occ from public.bet_occurrences where championship_id=:'champ' and kind='annual' \gset
insert into public.markets(title,kind,category,closes_at,championship_id,mode)
 select 'Old entry policy','annual','winner',ends_at,id,'snapshot_value' from public.championships where id=:'champ' returning id as old_policy \gset
select pg_temp.ck(public.preview_market_bet_association(:'old_policy',:'annual_def',:'annual_occ')->>'status'='entry_policy_required','No silent adoption of the new entry policy on exposed legacy');
insert into public.markets(title,kind,category,closes_at) select 'No inferred mode','annual','last',ends_at from public.championships where id=:'champ' returning id as untyped \gset
select pg_temp.ck(public.preview_market_bet_association(:'untyped',:'annual_def',:'annual_occ')->>'status'='explicit_mode_required','No title-based mode inference');

-- Historical association needs frozen evidence; it creates no retrospective obligations.
select id as past_occ,sprint_id as past_sprint from public.bet_occurrences where championship_id=:'champ' and kind='weekly' and ends_at<now() order by ends_at desc limit 1 \gset
insert into public.markets(title,kind,category,closes_at,championship_id,sprint_id,mode)
 select 'Archived explicit market','weekly','winner',ends_at,championship_id,sprint_id,'snapshot_value' from public.bet_occurrences where id=:'past_occ' returning id as past_market \gset
select pg_temp.ck(public.preview_market_bet_association(:'past_market',:'value_def',:'past_occ')->>'status'='historical_without_snapshot','No retroactive mandatory finals');
insert into public.competition_captures(championship_id,sprint_id,phase,cutoff_at,captured_by)
 select championship_id,sprint_id,'end',ends_at,auth.uid() from public.bet_occurrences where id=:'past_occ';
select public.preview_market_bet_association(:'past_market',:'value_def',:'past_occ') as past_plan \gset
select pg_temp.ck((:'past_plan'::jsonb->>'can_apply')::boolean and (:'past_plan'::jsonb->>'historical')::boolean,'Frozen archive can be organized without reinterpreting policy');
select public.associate_legacy_market(:'past_market',:'value_def',:'past_occ',:'past_plan'::jsonb->>'fingerprint','Associação histórica sem reapuramento ou alteração de política');
select public.ensure_final_rounds();
select pg_temp.ck(not exists(select 1 from public.final_round_occurrences where occurrence_id=:'past_occ'),'No retrospective final collection');
-- Audit writes and admin RPCs are protected under actual client roles.
set local role authenticated;
select set_config('request.jwt.claim.sub','e9000000-0000-4000-8000-000000000003',false);
select pg_temp.reject(format('select public.preview_market_bet_association(%L,%L,%L)',:'value_market',:'value_def',:'occ'),'42501');
select pg_temp.reject(format('select public.associate_legacy_market(%L,%L,%L,%L,%L)',:'value_market',:'value_def',:'occ',:'plan'::jsonb->>'fingerprint','Revisão não autorizada'),'42501');
select pg_temp.reject('delete from public.market_bet_associations','42501');
select pg_temp.ck(not has_function_privilege('authenticated','public.reject_market_bet_reassignment()','execute'),'Private trigger cannot be invoked by clients');
reset role;
select pg_temp.ck((select sum(available+reserved-total_issued)=0 from public.wallets),'Currency conservation');
rollback;
