-- No repair, re-issuance, migration, settlement or production connection.
\set ON_ERROR_STOP on
begin;
do $$declare admin_id uuid;begin
 if exists(select 1 from public.wallets where available<0 or reserved<0) then
  raise exception 'Negative recovered balance';end if;
 if (select sum(available+reserved-total_issued) from public.wallets)<>0 then
  raise exception 'Recovered coin supply differs from issuance';end if;
 select id into strict admin_id from public.admins order by id limit 1;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 if exists(select 1 from public.reconcile_wallets() where not balanced) then
  raise exception 'Recovered ledger does not reconcile';end if;
 if not exists(select 1 from public.occurrence_classifications) then
  raise exception 'Missing frozen classifications in recovery fixture';end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
do $$begin
 if exists(select 1 from public.wallets where owner_id<>auth.uid()) then
  raise exception 'Recovered RLS exposes another wallet';end if;
 begin
  update public.wallets set available=available+1;
  raise exception 'Recovered wallet writes are exposed';
 exception when insufficient_privilege then null;end;
 begin
  delete from public.ledger;
  raise exception 'Recovered ledger writes are exposed';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;
