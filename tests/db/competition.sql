-- Runs only on disposable CI PostgreSQL after migration 09. Fixtures roll back.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'ASSERT: %',label;end if;end $$;
create function pg_temp.reject(command text,expected text) returns void language plpgsql as $$
begin
 begin execute command;
 exception when others then
  if sqlstate=expected then return;end if;
  raise exception 'Expected %, got %: %',expected,sqlstate,sqlerrm;
 end;
 raise exception 'Unexpected success: %',command;
end $$;
insert into auth.users(id) select ('a0000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,7) n;
insert into public.admins(id) values('a0000000-0000-4000-8000-000000000001');
insert into public.competitors(id,joined_at) select ('a0000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,now()-interval '60 days' from generate_series(1,3) n;
create temp table test_voters as select id,row_number() over(order by id) as n from public.competitors;
grant select on test_voters to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000004',true);
select public.apply_competitor();
select pg_temp.reject('select public.apply_competitor()','P0001');
select pg_temp.reject('select public.set_my_score(1)','P0001');
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000005',true);
select public.apply_competitor();
select pg_temp.reject($q$select public.vote_application((select id from public.applications where candidate_id='a0000000-0000-4000-8000-000000000005'),true)$q$,'P0001');
-- First yes is insufficient; duplicate vote must not count twice.
select set_config('request.jwt.claim.sub',(select id::text from test_voters where n=1),true);
select public.vote_application((select id from public.applications where candidate_id='a0000000-0000-4000-8000-000000000004'),true);
select pg_temp.check_true((select state='pending' from public.applications where candidate_id='a0000000-0000-4000-8000-000000000004'),'absolute majority, abstentions remain in denominator');
select pg_temp.reject($q$select public.vote_application((select id from public.applications where candidate_id='a0000000-0000-4000-8000-000000000004'),true)$q$,'23505');
do $$declare v record;v_app uuid;begin
 select id into v_app from public.applications where candidate_id='a0000000-0000-4000-8000-000000000004';
 for v in select id from test_voters where n>1 and n<=(select count(*)/2+1 from test_voters) loop
  perform set_config('request.jwt.claim.sub',v.id::text,true);
  perform public.vote_application(v_app,true);
 end loop;
end $$;
select pg_temp.check_true((select state='approved' and decided_at is not null from public.applications where candidate_id='a0000000-0000-4000-8000-000000000004'),'audited approval');
select pg_temp.check_true((select ytd is null and updated_at is null from public.competitors where id='a0000000-0000-4000-8000-000000000004'),'admission does not invent zero');
-- Newly admitted D cannot vote in E's older, frozen electorate.
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000004',true);
select pg_temp.reject($q$select public.vote_application((select id from public.applications where candidate_id='a0000000-0000-4000-8000-000000000005'),true)$q$,'P0001');
do $$declare v record;v_app uuid;begin
 select id into v_app from public.applications where candidate_id='a0000000-0000-4000-8000-000000000005';
 for v in select id from test_voters where n<=ceil((select count(*) from test_voters)/2.0) loop
  perform set_config('request.jwt.claim.sub',v.id::text,true);
  perform public.vote_application(v_app,false);
 end loop;
end $$;
select pg_temp.check_true((select state='rejected' and decided_at is not null from public.applications where candidate_id='a0000000-0000-4000-8000-000000000005'),'mathematically impossible majority rejected');
select pg_temp.check_true(not exists(select 1 from public.competitors where id='a0000000-0000-4000-8000-000000000005'),'rejection does not admit');
select pg_temp.reject($q$select public.vote_application((select id from public.applications where candidate_id='a0000000-0000-4000-8000-000000000005'),true)$q$,'P0001');
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000002',true);
-- Even electorate: half the yes votes is not approval; half the no votes rejects.
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000006',true);
select public.apply_competitor();
do $$declare v record;v_app uuid;v_n integer;begin
 select id,eligible_votes into v_app,v_n from public.applications where candidate_id='a0000000-0000-4000-8000-000000000006';
 perform pg_temp.check_true(v_n%2=0,'even electorate fixture');
 for v in select id,row_number() over(order by id) n from public.competitors loop
  perform set_config('request.jwt.claim.sub',v.id::text,true);
  perform public.vote_application(v_app,v.n<=v_n/2);
  if v.n=v_n/2 then
   perform pg_temp.check_true((select state='pending' from public.applications where id=v_app),'exactly half yes is not majority');
  end if;
 end loop;
 perform pg_temp.check_true((select state='rejected' from public.applications where id=v_app),'exactly half no makes majority impossible');
end $$;
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000002',true);
select public.set_my_score(0);
select pg_temp.check_true((select ytd=0 and updated_at is not null from public.competitors where id='a0000000-0000-4000-8000-000000000002'),'declared zero distinguished from missing');
select pg_temp.check_true(exists(select 1 from public.score_history where competitor_id='a0000000-0000-4000-8000-000000000002' and ytd=0),'declaration audit');
select pg_temp.reject('select public.set_my_score(''NaN''::numeric)','P0001');
select pg_temp.reject('select public.set_my_score(-100.0001)','P0001');
reset role;

-- Historical fixtures inserted once: never rewrite real declarations.
insert into public.championships(id,name,starts_at,ends_at) values
 ('b0000000-0000-4000-8000-000000000001','E2 historical',now()-interval '50 days',now()-interval '2 hours');
insert into public.sprints(id,championship_id,name,kind,starts_at,ends_at) values
 ('c0000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','E2 weekly','weekly',now()-interval '4 hours',now()-interval '2 hours'),
 ('c0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','E2 monthly','monthly',now()-interval '4 hours',now()-interval '2 hours');
insert into public.competitors(id,joined_at) values('a0000000-0000-4000-8000-000000000007',now()-interval '3 hours');
insert into public.score_history(competitor_id,ytd,created_at) values
 ('a0000000-0000-4000-8000-000000000001',12,now()-interval '4 hours'),
 ('a0000000-0000-4000-8000-000000000001',16,now()-interval '2 hours'),
 ('a0000000-0000-4000-8000-000000000001',16.5,now()-interval '2 hours'),
 ('a0000000-0000-4000-8000-000000000001',99,now()-interval '1 hour'),
 ('a0000000-0000-4000-8000-000000000002',-100,now()-interval '5 hours'),
 ('a0000000-0000-4000-8000-000000000002',-95.5,now()-interval '3 hours'),
 ('a0000000-0000-4000-8000-000000000007',40,now()-interval '150 minutes');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000006',true);
select pg_temp.reject($q$select public.capture_sprint('c0000000-0000-4000-8000-000000000001','start')$q$,'42501');
select pg_temp.reject($q$select public.validate_competition('b0000000-0000-4000-8000-000000000001',null,'Validado pelo teste')$q$,'42501');
select pg_temp.reject('update public.competitors set ytd=100','42501');
select pg_temp.reject('delete from public.score_history','42501');
select pg_temp.reject('delete from public.competition_captures','42501');
select pg_temp.reject('delete from public.competition_capture_scores','42501');
select pg_temp.reject('delete from public.competition_validations','42501');
select pg_temp.reject('delete from public.votes','42501');
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000001',true);
select pg_temp.reject($q$select public.capture_sprint('c0000000-0000-4000-8000-000000000001',null)$q$,'BC002');
select pg_temp.reject($q$select public.capture_sprint('c0000000-0000-4000-8000-000000000001','end')$q$,'BC005');
select pg_temp.reject($q$select public.validate_competition('b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001','Ainda sem capturas')$q$,'BC007');
select public.capture_sprint('c0000000-0000-4000-8000-000000000001','start');
select public.capture_sprint('c0000000-0000-4000-8000-000000000001','start');
select public.capture_sprint('c0000000-0000-4000-8000-000000000001','end');
select public.capture_sprint('c0000000-0000-4000-8000-000000000001','end');
select pg_temp.check_true((select count(*)=2 from public.competition_captures where sprint_id='c0000000-0000-4000-8000-000000000001'),'idempotent captures');
select pg_temp.check_true((select return_pct=4.5 and start_ytd=12 and end_ytd=16.5 from public.get_sprint_rankings('c0000000-0000-4000-8000-000000000001') where competitor_id='a0000000-0000-4000-8000-000000000001'),'cutoff inclusive and deterministic same-time history; no future 99');
select pg_temp.check_true((select count(*)=2 from public.get_sprint_rankings('c0000000-0000-4000-8000-000000000001')),'missing scores and mid-period entrants excluded without fabricated zero');
do $$declare review jsonb;begin
 review:=public.get_competition_review('b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001');
 perform pg_temp.check_true((select count(*)=2 from jsonb_array_elements(review->'rows') r where r->>'place'='1'),'ties share rank');
 perform pg_temp.check_true((select count(*)=1 from jsonb_array_elements(review->'rows') r where r->>'status'='missing_start'),'late admission explicitly unranked');
 perform pg_temp.check_true((select count(*)=1 from jsonb_array_elements(review->'rows') r where r->>'status'='missing_end'),'never declared explicitly unranked');
 perform pg_temp.check_true((review->'validation')='null'::jsonb,'closed is not validated');
end $$;
select pg_temp.reject($q$select public.validate_competition('b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001','curta')$q$,'BC006');
select public.validate_competition('b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001','Revistos os dados, empates e ausentes sem classificação; sem liquidação.');
select public.validate_competition('b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001','Repetição não altera nota');
select pg_temp.check_true((select count(*)=1 from public.competition_validations where sprint_id='c0000000-0000-4000-8000-000000000001'),'validation idempotent');
select public.set_my_score(77);
select public.update_nickname('Nome posterior');
select pg_temp.check_true((select end_ytd=16.5 from public.get_sprint_rankings('c0000000-0000-4000-8000-000000000001') where competitor_id='a0000000-0000-4000-8000-000000000001'),'later declarations cannot alter snapshots');
select pg_temp.check_true((select rows=public.get_competition_review(championship_id,sprint_id)->'rows' from public.competition_validations where sprint_id='c0000000-0000-4000-8000-000000000001'),'validated rows frozen, including nickname');
select public.capture_sprint('c0000000-0000-4000-8000-000000000002','start');
select public.capture_sprint('c0000000-0000-4000-8000-000000000002','end');
select public.validate_competition('b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000002','Mensal revisto com dados ausentes explícitos');
select public.capture_championship('b0000000-0000-4000-8000-000000000001');
select public.validate_competition('b0000000-0000-4000-8000-000000000001',null,'Anual revisto; classificação pelo YTD congelado');
select pg_temp.check_true((select r->>'competitor_id'='a0000000-0000-4000-8000-000000000007' from jsonb_array_elements(public.get_competition_review('b0000000-0000-4000-8000-000000000001',null)->'rows') r where r->>'place'='1'),'annual ranks absolute YTD, not sprint delta');
reset role;
select pg_temp.reject('update public.competition_validations set note=''reescrever passado''','BC001');
select pg_temp.reject('delete from public.competition_capture_scores','BC001');
select pg_temp.reject('update public.competition_captures set cutoff_at=now()','BC001');
select pg_temp.reject('update public.score_history set ytd=0','BC001');
select pg_temp.reject('delete from public.sprint_scores','BC001');
-- The pre-migration smoke fixture must stay byte-for-byte authoritative, uncertified.
set local role authenticated;
select pg_temp.reject($q$select public.capture_sprint((select id from public.sprints where name='Semana de teste'),'end')$q$,'BC004');
reset role;
-- Empty captures need durable markers too; early limits and invalid scopes fail closed.
insert into public.sprints(id,championship_id,name,kind,starts_at,ends_at) values
 ('c0000000-0000-4000-8000-000000000003','b0000000-0000-4000-8000-000000000001','Empty old sprint','weekly',now()-interval '90 days',now()-interval '89 days'),
 ('c0000000-0000-4000-8000-000000000004','b0000000-0000-4000-8000-000000000001','Future sprint','weekly',now()+interval '1 day',now()+interval '2 days');
set local role authenticated;
select public.capture_sprint('c0000000-0000-4000-8000-000000000003','start');
select public.capture_sprint('c0000000-0000-4000-8000-000000000003','start');
select public.capture_sprint('c0000000-0000-4000-8000-000000000003','end');
select pg_temp.check_true((select count(*)=2 from public.competition_captures where sprint_id='c0000000-0000-4000-8000-000000000003'),'empty snapshot cannot be repopulated');
select pg_temp.reject($q$select public.validate_competition('b0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000003','Sem dados apuráveis')$q$,'BC007');
select pg_temp.reject($q$select public.capture_sprint('c0000000-0000-4000-8000-000000000004','start')$q$,'BC003');
select pg_temp.reject($q$select public.get_competition_review('b0000000-0000-4000-8000-000000000009',null)$q$,'BC002');
reset role;
set local role anon;
select pg_temp.reject($q$select public.get_competition_review('b0000000-0000-4000-8000-000000000001',null)$q$,'42501');
select pg_temp.reject('select * from public.competition_validations','42501');
reset role;
rollback;
