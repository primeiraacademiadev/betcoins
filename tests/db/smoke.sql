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
-- Sprint snapshots: calculate arithmetic YTD difference in percentage points.
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
 if abs(v_result-11.5)>0.001 then raise exception 'Retorno sprint incorrecto: %',v_result;end if;
end $$;
-- A spectator can only receive weekly grants once.
select public.grant_weekly();
select public.grant_weekly();
reset role;
do $$begin
 if (select total_issued from public.wallets where owner_id='33333333-3333-4333-8333-333333333333')<>2000 then
  raise exception 'Grant semanal duplicado';
 end if;
end $$;
set role authenticated;
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
-- Cost basis must pass to the new owner at the actual secondary-market purchase price.
reset role;
do $$declare v_basis numeric;v_pnl numeric;begin
 select cost_basis into v_basis from public.positions where side='back' limit 1;
 select realized_pnl into v_pnl from public.position_sales limit 1;
 if v_basis<>5 then raise exception 'Buyer cost basis invalid: %',v_basis;end if;
 if v_pnl<>-5 then raise exception 'Seller realized P&L invalid: %',v_pnl;end if;
 if (select count(*) from public.position_sales)<>1 then raise exception 'Sale history missing';end if;
end $$;
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);

reset role;
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
reset role;
do $$declare v_supply numeric;v_issued numeric;begin
 select sum(available+reserved),sum(total_issued) into v_supply,v_issued from public.wallets;
 if v_supply<>v_issued then raise exception 'Liquidação criou ou destruiu BetCoins';end if;
 if (select count(*) from public.trades where settled_at is not null)<>1 then raise exception 'Trade por liquidar';end if;
 if (select state from public.markets limit 1)<>'settled' then raise exception 'Mercado não liquidado';end if;
end $$;
-- Recover missed spectator weeks, without retroactive grants before signup.
reset role;
update public.profiles
 set created_at=now()-interval '15 days'
 where id='33333333-3333-4333-8333-333333333333';
-- Read private grant records as the privileged smoke-test session.
create temp table _grant_before as
 select count(*)::int as n from public.weekly_grants
 where owner_id='33333333-3333-4333-8333-333333333333';
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.grant_weekly();
do $$begin
 if public.grant_weekly()<>0 then raise exception 'Recarga não idempotente'; end if;
 if exists(select 1 from public.reconcile_wallets() r where not r.balanced) then
  raise exception 'Reconciliação falhou depois das recargas e da liquidação';
 end if;
end $$;
reset role;
do $$declare v_after integer;v_expected integer;begin
 select count(*) into v_after from public.weekly_grants
  where owner_id='33333333-3333-4333-8333-333333333333';
 select count(*) into v_expected from generate_series(
  date_trunc('week',(now()-interval '15 days') at time zone 'UTC'),
  date_trunc('week',now() at time zone 'UTC'),interval '7 days'
 ) g;
 if v_after<>v_expected or v_after<=(select n from _grant_before) then
  raise exception 'Recuperação semanal incorreta: % / %',v_after,v_expected;
 end if;
end $$;
drop table _grant_before;
-- Reconciliation must be able to report a discrepancy, without repairing balances.
reset role;
begin;
update public.wallets set available=available+1
 where owner_id='33333333-3333-4333-8333-333333333333';
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
do $$begin
 if not exists(select 1 from public.reconcile_wallets() r
  where r.owner_id='33333333-3333-4333-8333-333333333333'
   and not r.balanced and r.available_difference=1) then
  raise exception 'Reconciliação não detetou divergência';
 end if;
end $$;
rollback;
-- Permission check: authenticated role must not write wallets directly.
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
do $$begin
 begin
  update public.wallets set available=999999;
  raise exception 'SECURITY: direct wallet UPDATE unexpectedly allowed';
 exception when insufficient_privilege then null;
 end;
end $$;

-- Rank as-of must be reproducible from immutable ledger entries, with no invented mark-to-market.
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
do $$declare r record;begin
 select * into r from public.get_spectator_rankings(null)
 where owner_id='33333333-3333-4333-8333-333333333333';
 if not found or r.issued<=0 or r.wealth<>r.available+r.reserved
  or r.valuation_status<>'contabilistico_sem_cotacao'
  or r.open_positions<>0 then
  raise exception 'Classificação atual incorreta';
 end if;
 if r.relative_pct<>round(100*(r.wealth-r.issued)/r.issued,2) then
  raise exception 'Rentabilidade relativa inconsistente';
 end if;
 if exists(select 1 from public.get_spectator_rankings(
   (select created_at-interval '1 second' from public.profiles
    where id='33333333-3333-4333-8333-333333333333')
  ) where owner_id='33333333-3333-4333-8333-333333333333') then
  raise exception 'Histórico inclui utilizador antes da inscrição';
 end if;
end $$;

-- The partial resale is a split of BOTH sides, not a split of collateral only.
-- Match BACK 10 / LAY 30 (odd 4), list 3 / 9 and retain 7 / 21.
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.create_market('Revenda parcial teste','weekly','winner',now()+interval '10 minutes',
 array['11111111-1111-4111-8111-111111111111'::uuid,'22222222-2222-4222-8222-222222222222'::uuid]);
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select public.place_offer(
 (select o.id from public.outcomes o
  join public.markets m on m.id=o.market_id
  where m.title='Revenda parcial teste'
    and o.competitor_id='11111111-1111-4111-8111-111111111111'),
 'back',4.00,10);
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select public.accept_offer(
 (select f.id from public.offers f join public.markets m on m.id=f.market_id
  where m.title='Revenda parcial teste'),10);
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
-- A partial listing cannot invent a non-exact stake, cost or collateral proportion.
select public.list_position(
 (select p.id from public.positions p join public.markets m on m.id=p.market_id
  where m.title='Revenda parcial teste' and p.side='back'),4,3);
do $$declare x record;begin
 select * into x from public.get_active_listings()
  where market_title='Revenda parcial teste';
 if not found or x.stake<>3 or x.liability<>9 then
  raise exception 'Marketplace não mostra o lote exato';
 end if;
end $$;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.buy_position(
 (select id from public.get_active_listings() where market_title='Revenda parcial teste'));
-- Check exact remaining slice, buyer ownership, seller P&L, both sides and conserved supply.
reset role;
do $$declare t numeric;issued numeric;begin
 select sum(available+reserved),sum(total_issued) into t,issued from public.wallets;
 if t<>issued then raise exception 'Partial resale minted/burned coins'; end if;
 if (select count(*) from public.trades t join public.markets m on m.id=t.market_id
    where m.title='Revenda parcial teste')<>2 then raise exception 'Split missing child trade'; end if;
 if (select count(*) from public.positions p join public.markets m on m.id=p.market_id
    where m.title='Revenda parcial teste')<>4 then raise exception 'Missing matched BACK/LAY legs'; end if;
 if (select sum(stake) from public.positions p join public.markets m on m.id=p.market_id
    where m.title='Revenda parcial teste' and side='back')<>10 then raise exception 'Stake not conserved'; end if;
 if (select sum(liability) from public.positions p join public.markets m on m.id=p.market_id
    where m.title='Revenda parcial teste' and side='lay')<>30 then raise exception 'Liability not conserved'; end if;
 if not exists(select 1 from public.positions p join public.markets m on m.id=p.market_id
    where m.title='Revenda parcial teste' and p.side='back'
     and p.owner_id='11111111-1111-4111-8111-111111111111'
     and p.stake=3 and p.liability=9 and p.cost_basis=4) then
   raise exception 'Buyer lot incorrect';
 end if;
 if not exists(select 1 from public.positions p join public.markets m on m.id=p.market_id
    where m.title='Revenda parcial teste' and p.side='back'
     and p.owner_id='22222222-2222-4222-8222-222222222222'
     and p.stake=7 and p.liability=21 and p.cost_basis=7) then
   raise exception 'Seller residual lot incorrect';
 end if;
 if not exists(select 1 from public.position_sales ps
    where ps.sale_price=4 and ps.seller_cost_basis=3 and ps.realized_pnl=1) then
  raise exception 'Sale P&L incorrect';
 end if;
end $$;
-- Neither the buyer nor the seller can execute the consumed listing twice.
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
do $$begin
 begin
  perform public.buy_position((select ps.listing_id from public.position_sales ps
   where ps.buyer_id='11111111-1111-4111-8111-111111111111'
    and ps.sale_price=4));
  raise exception 'DOUBLE_PURCHASE_SUCCEEDED';
 exception when others then
  if sqlerrm='DOUBLE_PURCHASE_SUCCEEDED' then raise; end if;
 end;
end $$;
-- Settlement pays out BOTH split trades; original loser keeps no collateral.
reset role;
update public.markets set closes_at=now()-interval '1 second'
 where title='Revenda parcial teste';
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.settle_market(
 (select id from public.markets where title='Revenda parcial teste'),
 (select o.id from public.outcomes o join public.markets m on m.id=o.market_id
  where m.title='Revenda parcial teste'
   and o.competitor_id='11111111-1111-4111-8111-111111111111'));
reset role;
do $$declare t numeric;issued numeric;begin
 select sum(available+reserved),sum(total_issued) into t,issued from public.wallets;
 if t<>issued then raise exception 'Settlement of partial lots changed total supply'; end if;
 if (select count(*) from public.trades t join public.markets m on m.id=t.market_id
  where m.title='Revenda parcial teste' and t.settled_at is not null)<>2 then
  raise exception 'Split trades not settled';
 end if;
end $$;

-- Final results must reconcile against the last holder's actual purchase basis.
reset role;
do $$declare v_pnl numeric; v_payoff numeric;begin
 select ps.realized_pnl,ps.payoff into v_pnl,v_payoff
 from public.position_settlements ps
 join public.positions p on p.id=ps.position_id
 join public.markets m on m.id=p.market_id
 where m.title='Revenda parcial teste' and p.side='back'
 and p.stake=3;
 if v_payoff<>12 or v_pnl<>8 then
  raise exception 'Final buyer BACK result incorrect: % / %',v_payoff,v_pnl;
 end if;
 if (select count(*) from public.position_settlements ps
   join public.positions p on p.id=ps.position_id
   join public.markets m on m.id=p.market_id
   where m.title='Revenda parcial teste')<>4 then
   raise exception 'Missing split settlements';
 end if;
end $$;
