-- #11: deterministic 2026 calendar and generation/eligibility regressions.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values
 ('c1000000-0000-4000-8000-000000000001'),
 ('c1000000-0000-4000-8000-000000000002'),
 ('c1000000-0000-4000-8000-000000000003');
insert into public.admins(id) values('c1000000-0000-4000-8000-000000000001');
insert into public.competitors(id) values('c1000000-0000-4000-8000-000000000001'),('c1000000-0000-4000-8000-000000000002');
select set_config('request.jwt.claim.sub','c1000000-0000-4000-8000-000000000001',false);
insert into public.championships(name,starts_at,ends_at,state) values('Previous annual reference','2025-01-01T00:00Z','2025-12-31T23:59:59Z','closed');
insert into public.championships(name,starts_at,ends_at) values('Recurring tests','2026-01-01T00:00Z','2026-12-31T23:59:59Z') returning id as champ \gset
create function pg_temp.recurrence_reject(command text,code text) returns void language plpgsql as $$
begin
 begin execute command;exception when others then
  if sqlstate<>code then raise exception 'Expected %, got %: %',code,sqlstate,sqlerrm;end if;return;
 end;raise exception 'Expected rejection: %',command;
end $$;
create function pg_temp.calendar_check(ok boolean,message text) returns void language plpgsql as $$
begin if not coalesce(ok,false) then raise exception '%',message;end if;end $$;
select pg_temp.calendar_check((select count(*)=251 from public.bet_calendar_sessions),'Wrong NYSE session count');
select pg_temp.calendar_check((select ends_at='2026-04-02T20:00:00Z' from public.recurring_calendar(:'champ','weekly') where period_key='2026-W14'),'Good Friday week must close Thursday');
select pg_temp.calendar_check((select ends_at='2026-11-27T18:00:00Z' from public.recurring_calendar(:'champ','weekly') where period_key='2026-W48'),'Thanksgiving early close');
select pg_temp.calendar_check((select ends_at='2026-12-24T18:00:00Z' from public.recurring_calendar(:'champ','weekly') where period_key='2026-W52'),'Christmas early close and holiday');
select pg_temp.calendar_check((select ends_at='2026-07-02T20:00:00Z' from public.recurring_calendar(:'champ','weekly') where period_key='2026-W27'),'July 3 holiday');
select pg_temp.calendar_check((select ends_at='2026-03-06T21:00:00Z' from public.recurring_calendar(:'champ','weekly') where period_key='2026-W10'),'NYSE pre-DST close');
select pg_temp.calendar_check((select ends_at='2026-03-13T20:00:00Z' from public.recurring_calendar(:'champ','weekly') where period_key='2026-W11'),'NYSE post-DST close');
select pg_temp.calendar_check((select ends_at='2026-03-31T22:59:59.999999Z' from public.recurring_calendar(:'champ','monthly') where period_key='2026-03'),'Lisbon month DST');
select pg_temp.calendar_check((select count(*)=53 from public.recurring_calendar(:'champ','weekly')),'All 53 ISO trading weeks');
insert into public.championships(name,starts_at,ends_at) values('Clipped','2026-03-10T12:00Z','2026-11-19T12:00Z') returning id as clipped \gset
select pg_temp.calendar_check((select bool_and(starts_at>='2026-03-10T12:00Z' and ends_at<='2026-11-19T12:00Z') from public.recurring_calendar(:'clipped','weekly')),'Boundaries must be clipped');
insert into public.championships(name,starts_at,ends_at) values('Unsupported','2027-01-01T00:00Z','2027-12-31T23:59:59Z') returning id as unsupported \gset
select pg_temp.recurrence_reject(format('select public.configure_recurring_bet(%L,''weekly'',''snapshot_value'',true)',:'unsupported'),'BR001');

select public.configure_recurring_bet(:'champ',k,md,true) from unnest(array['annual','monthly','weekly']) k cross join unnest(array['snapshot_value','snapshot_delta_previous']) md;
select pg_temp.calendar_check((select count(*)=6 from public.bet_definitions where championship_id=:'champ'),'Six definitions');
select pg_temp.calendar_check((select count(*)=66 from public.bet_occurrences where championship_id=:'champ'),'One shared calendar for both modes');
select count(*) as market_count from public.markets where championship_id=:'champ' \gset
select public.regenerate_bet_markets(:'champ');
select pg_temp.calendar_check((select count(*)=:'market_count'::integer from public.markets where championship_id=:'champ'),'Generation must be idempotent');
select pg_temp.calendar_check(not exists(select 1 from public.markets m join public.bet_occurrences o on o.id=m.occurrence_id where o.championship_id=:'champ' and o.ends_at<=transaction_timestamp()),'No historical markets manufactured');
select pg_temp.calendar_check(not exists(select 1 from public.markets m join public.bet_occurrences o on o.id=m.occurrence_id join public.bet_definitions d on d.id=m.definition_id where m.championship_id=:'champ' and (m.mode<>d.mode or m.closes_at<>o.ends_at or m.sprint_id is distinct from o.sprint_id)),'Modes/scopes must remain explicit');
select pg_temp.calendar_check(not exists(select 1 from public.markets m join public.bet_occurrences o on o.id=m.occurrence_id join public.bet_occurrences p on p.id=o.previous_occurrence_id where m.championship_id=:'champ' and m.mode='snapshot_delta_previous' and (m.previous_sprint_id is distinct from p.sprint_id or m.previous_closes_at<>p.ends_at)),'Delta pins previous END');
select pg_temp.calendar_check(not exists(select 1 from public.competition_captures where championship_id=:'champ'),'Generation does not invent snapshots');

-- A historical published market is a protected fixture, not newly generated.
select id as historical_occurrence,sprint_id as historical_sprint,ends_at as historical_end from public.bet_occurrences where championship_id=:'champ' and kind='weekly' order by starts_at limit 1 \gset
select id as definition from public.bet_definitions where championship_id=:'champ' and kind='weekly' and mode='snapshot_value' \gset
insert into public.markets(title,kind,category,closes_at,championship_id,sprint_id,mode,definition_id,occurrence_id)
 values('Protected historic market','weekly','winner',:'historical_end',:'champ',:'historical_sprint','snapshot_value',:'definition',:'historical_occurrence') returning id as history_market \gset
insert into public.outcomes(market_id,competitor_id,label) values(:'history_market','c1000000-0000-4000-8000-000000000001','A');
-- Place an offer in a future generated market before admitting a new competitor.
select id as future_market from public.markets where definition_id=:'definition' and closes_at>clock_timestamp() order by closes_at limit 1 \gset
select id as future_outcome from public.outcomes where market_id=:'future_market' and competitor_id='c1000000-0000-4000-8000-000000000001' \gset
set role authenticated;
select public.place_offer(:'future_outcome','back',2,10) as offer \gset
reset role;
create temporary table protected_offer as select * from public.offers where id=:'offer';
insert into public.competitors(id) values('c1000000-0000-4000-8000-000000000003');
select pg_temp.calendar_check(not exists(select 1 from public.markets m join public.bet_definitions d on d.id=m.definition_id where d.championship_id=:'champ' and d.active and m.closes_at>clock_timestamp() and not exists(select 1 from public.outcomes o where o.market_id=m.id and o.competitor_id='c1000000-0000-4000-8000-000000000003')),'Admission must reach every tradable occurrence');
select pg_temp.calendar_check(not exists(select 1 from public.outcomes where market_id=:'history_market' and competitor_id='c1000000-0000-4000-8000-000000000003'),'Admission changed closed universe');
select pg_temp.calendar_check((select to_jsonb(o)=to_jsonb(p) from public.offers o join protected_offer p using(id)),'Admission changed offer/odds/collateral');
select pg_temp.calendar_check((select ytd is null from public.competitors where id='c1000000-0000-4000-8000-000000000003'),'Admission manufactured YTD zero');
select pg_temp.calendar_check(public.get_bet_provisional_rankings(:'history_market')->>'status'='historical','Live scores must not leak into history');
select pg_temp.calendar_check(public.get_bet_provisional_rankings(:'future_market')->>'status'='provisional','Live preview must be labelled provisional');
select public.configure_recurring_bet(:'champ','weekly','snapshot_value',false);
set role authenticated;
select pg_temp.recurrence_reject(format('select public.place_offer(%L,''back'',2,1)',:'future_outcome'),'BR003');
select pg_temp.recurrence_reject(format('select public.accept_offer(%L,1)',:'offer'),'BR003');
select public.cancel_offer(:'offer');
reset role;
select public.configure_recurring_bet(:'champ','weekly','snapshot_value',true);
select pg_temp.calendar_check(not exists(select 1 from public.reconcile_wallets() where not balanced),'Wallet reconciliation changed');
select pg_temp.calendar_check((select sum(available+reserved-total_issued)=0 from public.wallets),'Currency conservation');
set role authenticated;
select set_config('request.jwt.claim.sub','c1000000-0000-4000-8000-000000000002',false);
select pg_temp.recurrence_reject(format('select public.regenerate_bet_markets(%L)',:'champ'),'42501');
select pg_temp.recurrence_reject($q$select public.generate_bet_markets(null)$q$,'42501');
select pg_temp.recurrence_reject($q$select public.prepare_bet_occurrences(null)$q$,'42501');
select pg_temp.recurrence_reject($q$update public.bet_definitions set active=false$q$,'42501');
select pg_temp.recurrence_reject($q$delete from public.bet_occurrences$q$,'42501');
reset role;
select pg_temp.recurrence_reject($q$update public.bet_calendar_sessions set closes_at=closes_at+interval '1 hour'$q$,'BC001');
select pg_temp.recurrence_reject($q$delete from public.bet_occurrences$q$,'BC001');
rollback;
