-- #1 snapshot modalities: disposable database consumer tests, rolled back.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values
 ('b1000000-0000-4000-8000-000000000001'),
 ('b1000000-0000-4000-8000-000000000002'),
 ('b1000000-0000-4000-8000-000000000003');
insert into public.admins(id) values('b1000000-0000-4000-8000-000000000001');
insert into public.competitors(id,joined_at) select id,now()-interval '20 days' from auth.users where id::text like 'b1000000%';
select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000001',false);
create function pg_temp.mode_reject(p_sql text,p_code text) returns void language plpgsql as $$
begin
 begin execute p_sql;exception when others then
  if sqlstate<>p_code then raise exception 'Expected %, got %: %',p_code,sqlstate,sqlerrm;end if;return;
 end;raise exception 'Expected failure: %',p_sql;
end $$;

-- Source snapshots carry real score_history references. Capture provenance itself
-- is tested by competition.sql; here we test the modality-specific consumer.
create function pg_temp.mode_capture(c uuid,s uuid,ph text,at_time timestamptz,variant text,p_case text)
returns uuid language plpgsql as $$
declare cap uuid;x record;h bigint;val numeric;i integer:=0;
begin
 insert into public.competition_captures(championship_id,sprint_id,phase,cutoff_at,captured_by)
  values(c,s,ph,at_time,auth.uid()) returning id into cap;
 for x in select c.id,p.nickname from public.competitors c join public.profiles p on p.id=c.id order by c.id loop
  i:=i+1;
  if variant='previous' and p_case='missing_previous' and x.id='b1000000-0000-4000-8000-000000000002' then continue;end if;
  val:=case when variant='start' then 100 else case x.id
   when 'b1000000-0000-4000-8000-000000000001' then case when variant='previous' then 12 else 16.5 end
   when 'b1000000-0000-4000-8000-000000000002' then case when variant='previous' then case when p_case='tie' then 12 else -5 end else case when p_case='tie' then 16.5 else 2 end end
   when 'b1000000-0000-4000-8000-000000000003' then case when variant='previous' then -1 else 0 end
   else case when variant='previous' then 0 else -i end end end;
  if variant='current' and p_case='missing_end' and x.id='b1000000-0000-4000-8000-000000000002' then
   insert into public.competition_capture_scores(capture_id,competitor_id,nickname) values(cap,x.id,x.nickname);
  else
   insert into public.score_history(competitor_id,ytd,created_at) values(x.id,val,at_time-interval '1 second') returning id into h;
   insert into public.competition_capture_scores(capture_id,competitor_id,nickname,source_history_id,declared_at,ytd)
    values(cap,x.id,x.nickname,h,at_time-interval '1 second',val);
  end if;
 end loop;
 return cap;
end $$;

create function pg_temp.mode_fixture(k text,md text,cat text default 'winner',p_case text default 'complete')
returns uuid language plpgsql as $$
declare c uuid;pc uuid;s uuid;ps uuid;m uuid;prev_end timestamptz:=now()-interval '2 days';cur_end timestamptz:=now()-interval '1 hour';
begin
 insert into public.championships(name,starts_at,ends_at) values('Modes current',now()-interval '1 day',cur_end) returning id into c;
 if k='annual' then
  insert into public.championships(name,starts_at,ends_at) values('Modes previous',now()-interval '4 days',prev_end) returning id into pc;
 else
  pc:=c;
  insert into public.sprints(championship_id,name,kind,starts_at,ends_at)
   values(c,'Modes previous',k,now()-interval '4 days',prev_end) returning id into ps;
  insert into public.sprints(championship_id,name,kind,starts_at,ends_at)
   values(c,'Modes current',k,now()-interval '1 day',cur_end) returning id into s;
  -- Deliberately different from previous END: the new delta must never use it.
  perform pg_temp.mode_capture(c,s,'start',now()-interval '1 day','start',p_case);
 end if;
 if p_case not in ('waiting_previous','start_only') then
  perform pg_temp.mode_capture(pc,ps,'end',prev_end+case when p_case='wrong_cutoff' then interval '1 minute' else interval '0' end,'previous',p_case);
 end if;
 if p_case<>'waiting_current' then perform pg_temp.mode_capture(c,s,'end',cur_end,'current',p_case);end if;
 insert into public.markets(title,kind,category,closes_at,championship_id,sprint_id,mode,previous_championship_id,previous_sprint_id,previous_closes_at)
  values('Explicit mode',k,cat,cur_end,c,s,md,case when md='snapshot_delta_previous' then pc end,
   case when md='snapshot_delta_previous' then ps end,case when md='snapshot_delta_previous' then prev_end end) returning id into m;
 insert into public.outcomes(market_id,competitor_id,label) select m,c.id,p.nickname from public.competitors c join public.profiles p on p.id=c.id;
 return m;
end $$;

do $$declare k text;md text;cat text;m uuid;r jsonb;expected uuid;v uuid;before_count integer;begin
 foreach k in array array['annual','weekly','monthly'] loop
  foreach md in array array['snapshot_value','snapshot_delta_previous'] loop
   foreach cat in array array['winner','second','last'] loop
    m:=pg_temp.mode_fixture(k,md,cat);r:=public.get_market_classification(m);
    if r->>'status'<>'ready_for_validation' then raise exception 'Not ready: %',r;end if;
    if md='snapshot_delta_previous' then
     if (select (x->>'value')::numeric from jsonb_array_elements(r->'rows') x where x->>'competitor_id'='b1000000-0000-4000-8000-000000000001')<>4.5 then raise exception '12 -> 16.5 must be 4.5 pp, not compound/start delta';end if;
    else
     if (select (x->>'value')::numeric from jsonb_array_elements(r->'rows') x where x->>'competitor_id'='b1000000-0000-4000-8000-000000000001')<>16.5 then raise exception 'Snapshot value must be 16.5';end if;
    end if;
    perform pg_temp.mode_reject(format('select public.settle_market(%L,null)',m),'BM004');
    v:=public.validate_market_classification(m,'Revisão dos snapshots e do critério explícito');
    if public.validate_market_classification(m,'Repetição da mesma revisão')<>v then raise exception 'Validation not idempotent';end if;
    r:=public.get_market_resolution(m);
    if r->>'status'<>'ready' then raise exception 'Resolution not ready: %',r;end if;
    select competitor_id into expected from public.outcomes where id=(r->>'winner_outcome_id')::uuid;
    if cat='winner' and expected<>(case when md='snapshot_value' then 'b1000000-0000-4000-8000-000000000001' else 'b1000000-0000-4000-8000-000000000002' end)::uuid then raise exception 'Wrong mode winner';end if;
    if cat='second' and expected<>(case when md='snapshot_value' then 'b1000000-0000-4000-8000-000000000002' else 'b1000000-0000-4000-8000-000000000001' end)::uuid then raise exception 'Wrong mode second';end if;
    if cat='last' and expected::text like 'b1000000%' then raise exception 'Wrong mode last';end if;
    select count(*) into before_count from public.ledger;
    perform public.settle_market(m,(r->>'winner_outcome_id')::uuid);
    perform public.settle_market(m,(r->>'winner_outcome_id')::uuid);
    if (select count(*) from public.ledger)<>before_count then raise exception 'Empty settlement changed money';end if;
    if not exists(select 1 from public.market_resolutions where market_id=m and classification_id=v and validation_id is null) then raise exception 'Missing mode audit';end if;
   end loop;
  end loop;
 end loop;
end $$;

do $$declare m uuid;r jsonb;md text;cat text;v jsonb;begin
 -- A missing initial snapshot/previous score never blocks absolute END value.
 m:=pg_temp.mode_fixture('weekly','snapshot_value','winner','missing_previous');
 if public.get_market_classification(m)->>'status'<>'ready_for_validation' then raise exception 'Absolute value incorrectly requires previous score';end if;
 foreach md in array array['snapshot_value','snapshot_delta_previous'] loop
  m:=pg_temp.mode_fixture('monthly',md,'winner','missing_end');
  if public.get_market_classification(m)->>'status'<>'incomplete' then raise exception 'Missing END not blocked';end if;
  perform pg_temp.mode_reject(format('select public.validate_market_classification(%L,''Review missing source'')',m),'BP004');
  foreach cat in array array['winner','second'] loop
   m:=pg_temp.mode_fixture('weekly',md,cat,'tie');
   perform public.validate_market_classification(m,'Empate real nos snapshots congelados');
   if public.get_market_resolution(m)->>'status'<>'tie_unsupported' then raise exception 'Tie/absent second not blocked';end if;
   perform pg_temp.mode_reject(format('select public.settle_market(%L,null)',m),'BM004');
  end loop;
 end loop;
 m:=pg_temp.mode_fixture('weekly','snapshot_delta_previous','winner','missing_previous');
 if public.get_market_classification(m)->>'status'<>'incomplete' then raise exception 'Missing prior score replaced by zero';end if;
 m:=pg_temp.mode_fixture('monthly','snapshot_delta_previous','winner','start_only');
 if public.get_market_classification(m)->>'status'<>'waiting_previous_snapshot' then raise exception 'Own start used as previous END';end if;
 m:=pg_temp.mode_fixture('monthly','snapshot_delta_previous','winner','waiting_current');
 if public.get_market_classification(m)->>'status'<>'waiting_current_snapshot' then raise exception 'Current YTD used without snapshot';end if;
 m:=pg_temp.mode_fixture('annual','snapshot_delta_previous','winner','wrong_cutoff');
 if public.get_market_classification(m)->>'status'<>'period_mismatch' then raise exception 'Wrong reference timestamp accepted';end if;
 m:=pg_temp.mode_fixture('annual','snapshot_value');
 perform pg_temp.mode_reject(format('select public.validate_market_classification(%L,''short'')',m),'BC006');
 perform public.validate_market_classification(m,'Validar snapshot e preservar resultado');
 v:=public.get_market_classification(m);
 insert into public.score_history(competitor_id,ytd) values('b1000000-0000-4000-8000-000000000001',999);
 if public.get_market_classification(m)<>v then raise exception 'Live score rewrote frozen result';end if;
 perform pg_temp.mode_reject(format('update public.markets set mode=''snapshot_delta_previous'' where id=%L',m),'BP001');
 perform pg_temp.mode_reject(format('update public.markets set closes_at=closes_at+interval ''1 second'' where id=%L',m),'BP001');
 m:=pg_temp.mode_fixture('annual','snapshot_value');
 delete from public.outcomes where market_id=m and competitor_id='b1000000-0000-4000-8000-000000000003';
 if public.get_market_classification(m)->>'status'<>'universe_changed' then raise exception 'Outcome subset accepted';end if;
end $$;

-- Creation pins the actual immediate predecessor, not an arbitrary older period.
do $$declare c uuid;s uuid;ps uuid;older uuid;m uuid;r jsonb;begin
 insert into public.championships(name,starts_at,ends_at) values('Future modes',now()-interval '10 days',now()+interval '10 days') returning id into c;
 insert into public.sprints(championship_id,name,kind,starts_at,ends_at) values(c,'Older','weekly',now()-interval '8 days',now()-interval '6 days') returning id into older;
 insert into public.sprints(championship_id,name,kind,starts_at,ends_at) values(c,'Previous','weekly',now()-interval '5 days',now()-interval '3 days') returning id into ps;
 insert into public.sprints(championship_id,name,kind,starts_at,ends_at) values(c,'Current','weekly',now()-interval '2 days',now()+interval '2 days') returning id into s;
 m:=public.create_competition_market('Delta future',c,s,'winner','snapshot_delta_previous');
 if (select previous_sprint_id from public.markets where id=m)<>ps then raise exception 'Not the immediate predecessor';end if;
 if (select mode from public.markets where id=m)<>'snapshot_delta_previous' then raise exception 'Missing explicit mode';end if;
 perform pg_temp.mode_reject(format('select public.create_competition_market(''Bad mode'',%L,%L,''winner'',null)',c,s),'BP002');
 perform pg_temp.mode_reject(format('select public.create_competition_market(''First period'',%L,%L,''winner'',''snapshot_delta_previous'')',c,older),'BP003');
 insert into public.sprints(championship_id,name,kind,starts_at,ends_at) values(c,'Ambiguous previous','weekly',now()-interval '4 days',now()-interval '3 days');
 perform pg_temp.mode_reject(format('select public.create_competition_market(''Ambiguous'',%L,%L,''winner'',''snapshot_delta_previous'')',c,s),'BP003');
 -- The existing market reference is pinned despite later calendar changes.
 if (select previous_sprint_id from public.markets where id=m)<>ps then raise exception 'Reference silently changed';end if;
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000002',false);
select pg_temp.mode_reject($q$select public.validate_market_classification(null,'Unauthorized review')$q$,'42501');
select pg_temp.mode_reject($q$select public.create_competition_market('Unauthorized',null,null,'winner','snapshot_value')$q$,'42501');
select pg_temp.mode_reject($q$update public.market_classifications set note='Rewrite immutable result'$q$,'42501');
select pg_temp.mode_reject($q$select public.settle_legacy_validated_market(null,null)$q$,'42501');
select pg_temp.mode_reject($q$select public.get_legacy_market_resolution(null)$q$,'42501');
reset role;
select pg_temp.mode_reject($q$update public.market_classifications set note='Rewrite immutable result'$q$,'BC001');
set role anon;
select pg_temp.mode_reject($q$select public.get_market_classification(null)$q$,'42501');
reset role;
rollback;
