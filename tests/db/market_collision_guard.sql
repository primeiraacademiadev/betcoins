-- Migration 17 adds one nullable metadata field; all prior values stay exact.
\set ON_ERROR_STOP on
create view public.legacy_migration_payload as
select jsonb_object_agg(name,rows) as payload from (
 select 'markets' as name,coalesce(jsonb_agg(to_jsonb(x)-'replaced_by_market_id' order by id),'[]'::jsonb) as rows from public.markets x
 union all select 'outcomes',coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.outcomes x
 union all select 'captures',coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.competition_captures x
 union all select 'capture_scores',coalesce(jsonb_agg(to_jsonb(x) order by capture_id,competitor_id),'[]'::jsonb) from public.competition_capture_scores x
 union all select 'classifications',coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.market_classifications x
 union all select 'resolutions',coalesce(jsonb_agg(to_jsonb(x) order by market_id),'[]'::jsonb) from public.market_resolutions x
 union all select 'baselines',coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.entry_baselines x
 union all select 'members',coalesce(jsonb_agg(to_jsonb(x) order by round_id,occurrence_id,competitor_id),'[]'::jsonb) from public.final_members x
 union all select 'history',coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.score_history x
 union all select 'wallets',coalesce(jsonb_agg(to_jsonb(x) order by owner_id),'[]'::jsonb) from public.wallets x
 union all select 'ledger',coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.ledger x
 union all select 'offers',coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.offers x
 union all select 'trades',coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.trades x
 union all select 'positions',coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.positions x
 union all select 'listings',coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.listings x
) q;
create table public.legacy_migration_guard as select * from public.legacy_migration_payload;

create table public.collision_audit_guard as select jsonb_build_object(
 'reconciliations',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.market_reconciliations x),
 'associations',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.market_bet_associations x),
 'definitions',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.bet_definitions x),
 'occurrences',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.bet_occurrences x)
) as payload;
