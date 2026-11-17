-- No existing contract, source, financial row, calendar or audit may change on install.
\ir legacy_market_guard.sql
create table public.market_association_source_guard as select jsonb_build_object(
 'reconciliations',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.market_reconciliations x),
 'definitions',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.bet_definitions x),
 'occurrences',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) from public.bet_occurrences x)
) as payload;
