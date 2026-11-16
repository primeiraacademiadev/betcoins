-- Run BEFORE migration 14, only in disposable CI databases.
insert into auth.users(id) values('e3000000-0000-4000-8000-000000000001'),('e3000000-0000-4000-8000-000000000002');
insert into public.competitors(id,joined_at,ytd,updated_at) values
 ('e3000000-0000-4000-8000-000000000001',clock_timestamp()-interval '2 days',17,clock_timestamp()-interval '1 hour'),
 ('e3000000-0000-4000-8000-000000000002',clock_timestamp()-interval '2 days',0,null);
insert into public.championships(name,starts_at,ends_at) values('Audited entry migration fixture','2026-01-01T00:00Z','2026-12-31T23:59:59Z');
insert into public.score_history(competitor_id,ytd,created_at) values
 ('e3000000-0000-4000-8000-000000000001',12,clock_timestamp()-interval '1 day'),
 ('e3000000-0000-4000-8000-000000000001',17,clock_timestamp()-interval '1 hour');
create view public.entry_migration_payload as select jsonb_build_object(
 'history',(select jsonb_agg(to_jsonb(x) order by id) from public.score_history x),
 'scores',(select jsonb_agg(to_jsonb(x) order by capture_id,competitor_id) from public.competition_capture_scores x),
 'classifications',(select jsonb_agg(to_jsonb(x)-'entry_references' order by id) from public.market_classifications x),
 'resolutions',(select jsonb_agg(to_jsonb(x) order by market_id) from public.market_resolutions x),
 'wallets',(select jsonb_agg(to_jsonb(x) order by owner_id) from public.wallets x),
 'ledger',(select jsonb_agg(to_jsonb(x) order by id) from public.ledger x),
 'positions',(select jsonb_agg(to_jsonb(x) order by id) from public.positions x),
 'market_contracts',(select jsonb_agg(jsonb_build_array(id,mode,state,winner_outcome_id,closes_at,previous_championship_id,previous_sprint_id,previous_closes_at) order by id) from public.markets),
 'members',(select jsonb_agg(jsonb_build_array(round_id,occurrence_id,competitor_id) order by round_id,occurrence_id,competitor_id) from public.final_members)
) as payload;
create table public.entry_migration_guard as select payload from public.entry_migration_payload;
