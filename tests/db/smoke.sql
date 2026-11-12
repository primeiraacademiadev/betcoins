-- End-to-end economic smoke test with three isolated simulated JWT identities.
\set ON_ERROR_STOP on
insert into auth.users(id) values
 ('11111111-1111-4111-8111-111111111111'),
 ('22222222-2222-4222-8222-222222222222'),
 ('33333333-3333-4333-8333-333333333333');
-- Keep tests independent of the real 2026 championship expiry date.
update public.championships set starts_at=now()-interval '30 days',ends_at=now()+interval '30 days';
insert into public.admins(id) values('11111111-1111-4111-8111-111111111111');
insert into public.competitors(id) values('11111111-1111-4111-8111-111111111111');
set role authenticated;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select public.update_nickname('Investidor B');
select public.apply_competitor();
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.vote_application((select id from public.applications limit 1),true);
do $$begin
 if not exists(select 1 from public.competitors where id='22222222-2222-4222-8222-222222222222') then raise exception 'Admissão falhou';end if;
end $$;
select public.update_nickname('Investidor A');
select public.set_my_score(12.5);
select public.create_market('Vencedor teste','annual','winner',now()+interval '10 min',
 array['11111111-1111-4111-8111-111111111111'::uuid,'22222222-2222-4222-8222-222222222222'::uuid]);
-- Sprint snapshots: calculate period return from boundary YTDs.
select public.create_sprint('Semana de teste','weekly',now()-interval '1 hour',now()+interval '1 hour');
select public.capture_sprint((select id from public.sprints limit 1),'start');
select public.set_my_score(24);
reset role;
update public.sprints set ends_at=now()-interval '1 sec';
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.capture_sprint((select id from public.sprints limit 1),'end');
do $$declare v_result numeric;begin
 select return_pct into v_result from public.get_sprint_rankings((select id from public.sprints limit 1))
 where competitor_id='11111111-1111-4111-8111-111111111111';
 if abs(v_result-10.2222)>0.001 then raise exception 'Retorno sprint incorrecto: %',v_result;end if;
end $$;
-- A spectator can only receive weekly grants once.
select public.grant_weekly();
select public.grant_weekly();
do $$begin
 if (select total_issued from public.wallets where owner_id='33333333-3333-4333-8333-333333333333')<>2000 then
  raise exception 'Grant semanal duplicado';
 end if;
end $$;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select public.place_offer(
 (select id from public.outcomes where competitor_id='11111111-1111-4111-8111-111111111111' limit 1),
 'back',1.20,10);
do $$begin
 if (select reserved from public.wallets where owner_id='22222222-2222-4222-8222-222222222222')<>10 then raise exception 'Stake não reservada';end if;
end $$;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select public.accept_offer((select id from public.offers limit 1),10);
do $$begin
 if (select reserved from public.wallets where owner_id='33333333-3333-4333-8333-333333333333')<>2 then raise exception 'Responsabilidade LAY inválida';end if;
end $$;
-- Back position is sold by B to A for 5, releasing exactly the existing collateral.
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select public.list_position((select id from public.positions where side='back' limit 1),5);
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.buy_position((select id from public.listings limit 1));
do $$declare v_supply numeric;v_issued numeric;begin
 select sum(available+reserved),sum(total_issued) into v_supply,v_issued from public.wallets;
 if v_supply<>v_issued then raise exception 'A revenda criou ou destruiu BetCoins: % vs %',v_supply,v_issued;end if;
 if (select owner_id from public.positions where side='back' limit 1)<>'11111111-1111-4111-8111-111111111111' then raise exception 'Titularidade não transferida';end if;
end $$;
-- Simulate the cut-off by administrator-side time travel on disposable DB only.
reset role;
update public.markets set closes_at=now()-interval '1 sec';
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.settle_market(
 (select id from public.markets limit 1),
 (select id from public.outcomes where competitor_id='11111111-1111-4111-8111-111111111111' limit 1));
do $$declare v_supply numeric;v_issued numeric;begin
 select sum(available+reserved),sum(total_issued) into v_supply,v_issued from public.wallets;
 if v_supply<>v_issued then raise exception 'Liquidação criou ou destruiu BetCoins';end if;
 if (select count(*) from public.trades where settled_at is not null)<>1 then raise exception 'Trade por liquidar';end if;
 if (select state from public.markets limit 1)<>'settled' then raise exception 'Mercado não liquidado';end if;
end $$;
-- Permission check: authenticated role must not write wallets directly.
do $$begin
 begin
  update public.wallets set available=999999;
  raise exception 'SECURITY: direct wallet UPDATE unexpectedly allowed';
 exception when insufficient_privilege then null;
 end;
end $$;
