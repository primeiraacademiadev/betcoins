\set ON_ERROR_STOP on
do $$begin
 if (select payload from public.legacy_migration_guard) is distinct from (select payload from public.legacy_migration_payload) then raise exception 'Migration 15 rewrote existing data';end if;
end $$;
drop table public.legacy_migration_guard;
drop view public.legacy_migration_payload;
begin;
create function pg_temp.ck(ok boolean,msg text) returns void language plpgsql as $$begin if not coalesce(ok,false) then raise exception '%',msg;end if;end $$;
create function pg_temp.reject(command text,code text) returns void language plpgsql as $$begin
 begin execute command;exception when others then if sqlstate<>code then raise exception 'Expected %, got %: %',code,sqlstate,sqlerrm;end if;return;end;
 raise exception 'Unexpected acceptance: %',command;end $$;
insert into auth.users(id) values('e7000000-0000-4000-8000-000000000001'),('e7000000-0000-4000-8000-000000000002'),('e7000000-0000-4000-8000-000000000003');
insert into public.admins values('e7000000-0000-4000-8000-000000000001');
insert into public.competitors(id,joined_at) select id,now()-interval '3 days' from auth.users where id::text like 'e7000000%';
insert into public.championships(name,starts_at,ends_at) values('Legacy review tests',now()-interval '4 days',now()+interval '4 days') returning id as champ \gset
insert into public.sprints(championship_id,name,kind,starts_at,ends_at) values(:'champ','Legacy period','weekly',now()-interval '2 days',now()+interval '2 days') returning id as sprint \gset
insert into public.score_history(competitor_id,ytd,created_at) values('e7000000-0000-4000-8000-000000000001',12,now()-interval '1 day'),('e7000000-0000-4000-8000-000000000002',10,now()-interval '1 day');
select set_config('request.jwt.claim.sub','e7000000-0000-4000-8000-000000000001',false);
create function pg_temp.legacy(c uuid,s uuid,md text default null) returns uuid language plpgsql as $$declare m uuid;begin
 insert into public.markets(title,kind,category,closes_at,championship_id,sprint_id,mode)
 select 'Legacy without inferred criterion','weekly','winner',ends_at,case when md is not null then c end,case when md is not null then s end,md from public.sprints where id=s returning id into m;
 insert into public.outcomes(market_id,competitor_id,label) select m,id,nickname from public.profiles where id in('e7000000-0000-4000-8000-000000000001','e7000000-0000-4000-8000-000000000003');return m;end $$;
select pg_temp.legacy(:'champ',:'sprint') as legacy \gset
select public.preview_legacy_market(:'legacy',:'champ',:'sprint','snapshot_value') as plan \gset
select pg_temp.ck((:'plan'::jsonb->>'can_apply')::boolean,'Pristine mode-null market can be explicitly mapped');
select pg_temp.ck(jsonb_array_length(:'plan'::jsonb->'remove')=1 and jsonb_array_length(:'plan'::jsonb->'add')=1,'Exact safe universe diff');
select pg_temp.ck((select mode is null from public.markets where id=:'legacy'),'Preview must not write');
select pg_temp.reject(format('select public.reconcile_legacy_market(%L,%L,%L,%L,%L,%L)',:'legacy',:'champ',:'sprint','snapshot_value','stale','Nota de revisão obrigatória'),'BL001');
select pg_temp.reject(format('select public.reconcile_legacy_market(%L,%L,%L,%L,%L,%L)',:'legacy',:'champ',:'sprint','snapshot_value',:'plan'::jsonb->>'fingerprint','curta'),'BC006');
select id as old_outcome from public.outcomes where market_id=:'legacy' and competitor_id=auth.uid() \gset
select public.reconcile_legacy_market(:'legacy',:'champ',:'sprint','snapshot_value',:'plan'::jsonb->>'fingerprint','Selecionar período e modalidade após revisão explícita') as audit \gset
select pg_temp.ck(public.reconcile_legacy_market(:'legacy',:'champ',:'sprint','snapshot_value',:'plan'::jsonb->>'fingerprint','Pedido repetido')=:'audit'::uuid,'Idempotent retry');
select pg_temp.ck((select entry_reference_enabled and mode='snapshot_value' and definition_id is null and occurrence_id is null from public.markets where id=:'legacy'),'Explicit mapping without silently binding recurring definition');
select pg_temp.ck(exists(select 1 from public.outcomes where id=:'old_outcome'),'Retain eligible outcome identity');
select pg_temp.ck(not exists(select 1 from public.outcomes where market_id=:'legacy' and competitor_id='e7000000-0000-4000-8000-000000000003'),'Remove only premature outcome on pristine market');
select pg_temp.ck((select after_market=to_jsonb(m) from public.market_reconciliations a join public.markets m on m.id=a.market_id where a.id=:'audit'),'Exact persisted after-state');
select pg_temp.ck(public.preview_legacy_market(:'legacy',:'champ',:'sprint','snapshot_value')->>'status'='already_aligned','No duplicate reconciliation');
select pg_temp.reject(format('update public.markets set mode=%L where id=%L','snapshot_delta_previous',:'legacy'),'BP001');
select pg_temp.reject(format('delete from public.market_reconciliations where id=%L',:'audit'),'BC001');

-- Explicit pre-14 market: preserve its chosen mode while activating effective entry.
select pg_temp.legacy(:'champ',:'sprint','snapshot_value') as explicit \gset
select pg_temp.ck(public.preview_legacy_market(:'explicit',:'champ',:'sprint','snapshot_delta_previous')->>'status'='contract_mismatch','No criterion replacement');
select public.preview_legacy_market(:'explicit',:'champ',:'sprint','snapshot_value')->>'fingerprint' as token \gset
select public.reconcile_legacy_market(:'explicit',:'champ',:'sprint','snapshot_value',:'token','Manter modalidade explícita e rever participantes efetivos');
select pg_temp.legacy(:'champ',:'sprint') as delta \gset
select public.preview_legacy_market(:'delta',:'champ',:'sprint','snapshot_delta_previous')->>'fingerprint' as token \gset
select public.reconcile_legacy_market(:'delta',:'champ',:'sprint','snapshot_delta_previous',:'token','Escolha explícita de variação com referências de entrada');
select pg_temp.ck((select mode='snapshot_delta_previous' and entry_reference_enabled from public.markets where id=:'delta'),'Both modes supported');

-- Any financial history (including cancelled offers) forbids semantic rewrites.
select public.place_offer(:'old_outcome','back',2,5) as offer \gset
select public.cancel_offer(:'offer');
select pg_temp.ck(public.preview_legacy_market(:'legacy',:'champ',:'sprint','snapshot_value')->>'status'='contracts_preserved','Cancelled offers still count as contracts');
select pg_temp.legacy(:'champ',:'sprint') as quarantined \gset
select id as bad_outcome from public.outcomes where market_id=:'quarantined' limit 1 \gset
select pg_temp.reject(format('select public.place_offer(%L,%L,2,5)',:'bad_outcome','back'),'BL002');
select pg_temp.ck(not exists(select 1 from public.offers where market_id=:'quarantined'),'Quarantine cannot reserve coins');
-- A later first declaration changes the reviewed plan and invalidates the token.
select public.preview_legacy_market(:'quarantined',:'champ',:'sprint','snapshot_value')->>'fingerprint' as stale_token \gset
insert into public.score_history(competitor_id,ytd) values('e7000000-0000-4000-8000-000000000003',0);
select pg_temp.reject(format('select public.reconcile_legacy_market(%L,%L,%L,%L,%L,%L)',:'quarantined',:'champ',:'sprint','snapshot_value',:'stale_token','Revisão anterior à nova entrada efetiva'),'BL001');
select pg_temp.ck((select count(*) from public.outcomes where market_id=:'quarantined')=2,'Stale reconciliation is atomic');

-- Frozen target periods are preserved even on an otherwise pristine market.
insert into public.competition_captures(championship_id,sprint_id,phase,cutoff_at,captured_by) select :'champ',:'sprint','end',ends_at,auth.uid() from public.sprints where id=:'sprint';
select pg_temp.ck(public.preview_legacy_market(:'quarantined',:'champ',:'sprint','snapshot_value')->>'status'='frozen_preserved','No rewriting a frozen period');
-- Real client roles cannot access private helpers, write audit, or reconcile as a spectator.
set local role authenticated;
select set_config('request.jwt.claim.sub','e7000000-0000-4000-8000-000000000003',false);
select pg_temp.reject(format('select public.preview_legacy_market(%L,%L,%L,%L)',:'quarantined',:'champ',:'sprint','snapshot_value'),'42501');
select pg_temp.reject(format('select public.reconcile_legacy_market(%L,%L,%L,%L,%L,%L)',:'quarantined',:'champ',:'sprint','snapshot_value',:'stale_token','Revisão não autorizada'),'42501');
select pg_temp.reject('delete from public.market_reconciliations','42501');
reset role;
select pg_temp.ck((select sum(available+reserved-total_issued)=0 from public.wallets),'Currency conserved');
rollback;
