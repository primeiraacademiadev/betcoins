-- BETCOINS fresh-install schema bundle, snapshot 2026-11-15.
-- The seven source migrations below are embedded unchanged and in their original order.
-- USE ONLY on an EMPTY, NEW database. NEVER apply to an existing Supabase project.
-- DO NOT apply both this baseline and the seven source migrations.
-- This is a reproducible deployment bundle, not a rewrite of migration history.
-- Existing databases: apply only missing migrations using the recorded migration history.

-- =============================================================================
-- BEGIN 202611120001_init.sql [source blob: 45e9a301d589ef49d25c6510ecdecf04abd8c7a2]
-- =============================================================================
-- BetCoins MVP: execute as project owner through Supabase SQL editor or CLI.
-- Requires PostgreSQL 15+ and Supabase auth schema.
create extension if not exists pgcrypto;
create table public.profiles(
 id uuid primary key references auth.users(id) on delete cascade,
 nickname text not null check(length(btrim(nickname)) between 2 and 40),
 created_at timestamptz not null default now()
);
create table public.admins(id uuid primary key references public.profiles(id));
create table public.championships(
 id uuid primary key default gen_random_uuid(),
 name text not null,
 starts_at timestamptz not null,
 ends_at timestamptz not null,
 state text not null default 'open' check (state in ('open','closed'))
);
create table public.applications(
 id uuid primary key default gen_random_uuid(),
 candidate_id uuid not null references public.profiles(id),
 state text not null default 'pending' check(state in ('pending','approved','rejected')),
 eligible_votes integer not null,
 created_at timestamptz not null default now(),
 decided_at timestamptz
);
create unique index applications_one_pending on public.applications(candidate_id) where state='pending';
create table public.competitors(
 id uuid primary key references public.profiles(id),
 joined_at timestamptz not null default now(),
 ytd numeric(12,4) not null default 0 check(ytd >= -100),
 updated_at timestamptz
);
create table public.application_electorate(
 application_id uuid not null references public.applications(id),
 voter_id uuid not null references public.competitors(id),
 primary key(application_id,voter_id)
);
create table public.votes(
 application_id uuid not null references public.applications(id),
 voter_id uuid not null references public.competitors(id),
 approve boolean not null,
 created_at timestamptz not null default now(),
 primary key(application_id,voter_id)
);
create table public.score_history(
 id bigint generated always as identity primary key,
 competitor_id uuid not null references public.competitors(id),
 ytd numeric(12,4) not null,
 created_at timestamptz not null default now(),
 check(ytd >= -100)
);
create table public.wallets(
 owner_id uuid primary key references public.profiles(id),
 available numeric(18,2) not null default 0 check(available>=0),
 reserved numeric(18,2) not null default 0 check(reserved>=0),
 total_issued numeric(18,2) not null default 0 check(total_issued>=0)
);
create table public.ledger(
 id bigint generated always as identity primary key,
 owner_id uuid not null references public.wallets(owner_id),
 available_delta numeric(18,2) not null,
 reserved_delta numeric(18,2) not null,
 reason text not null,
 reference text not null,
 created_at timestamptz not null default now(),
 unique(owner_id,reason,reference)
);
create table public.weekly_grants(
 owner_id uuid not null references public.wallets(owner_id),
 week_start date not null,
 created_at timestamptz not null default now(),
 primary key(owner_id,week_start)
);
create table public.markets(
 id uuid primary key default gen_random_uuid(),
 title text not null,
 kind text not null check(kind in ('annual','weekly','monthly')),
 category text not null check(category in ('winner','second','last')),
 closes_at timestamptz not null,
 state text not null default 'open' check(state in ('open','settled','void')),
 winner_outcome_id uuid,
 created_at timestamptz not null default now()
);
create table public.outcomes(
 id uuid primary key default gen_random_uuid(),
 market_id uuid not null references public.markets(id),
 competitor_id uuid not null references public.competitors(id),
 label text not null,
 unique(market_id,competitor_id),
 unique(market_id,id)
);
alter table public.markets add constraint market_winner_same_market
 foreign key(id,winner_outcome_id) references public.outcomes(market_id,id);
create table public.offers(
 id uuid primary key default gen_random_uuid(),
 market_id uuid not null,
 outcome_id uuid not null,
 owner_id uuid not null references public.wallets(owner_id),
 side text not null check(side in ('back','lay')),
 odds numeric(10,2) not null check(odds > 1 and odds <= 1000),
 stake_remaining integer not null check(stake_remaining >= 0),
 state text not null default 'open' check(state in ('open','cancelled','filled')),
 created_at timestamptz not null default now(),
 foreign key(market_id,outcome_id) references public.outcomes(market_id,id)
);
create table public.trades(
 id uuid primary key default gen_random_uuid(),
 market_id uuid not null references public.markets(id),
 outcome_id uuid not null references public.outcomes(id),
 offer_id uuid not null references public.offers(id),
 odds numeric(10,2) not null,
 stake integer not null check(stake>0),
 liability numeric(18,2) not null check(liability>=0),
 created_at timestamptz not null default now(),
 settled_at timestamptz,
 unique(id,outcome_id)
);
create table public.positions(
 id uuid primary key default gen_random_uuid(),
 trade_id uuid not null references public.trades(id),
 owner_id uuid not null references public.wallets(owner_id),
 side text not null check(side in ('back','lay')),
 market_id uuid not null references public.markets(id),
 outcome_id uuid not null references public.outcomes(id),
 stake integer not null check(stake>0),
 liability numeric(18,2) not null check(liability>=0),
 status text not null default 'open' check(status in ('open','settled','void')),
 unique(trade_id,side)
);
create table public.listings(
 id uuid primary key default gen_random_uuid(),
 position_id uuid not null references public.positions(id),
 seller_id uuid not null references public.wallets(owner_id),
 price numeric(18,2) not null check(price>0),
 state text not null default 'open' check(state in ('open','sold','cancelled')),
 created_at timestamptz not null default now(),
 sold_to uuid references public.wallets(owner_id),
 sold_at timestamptz
);
create unique index listings_one_open on public.listings(position_id) where state='open';
create index offers_market_active on public.offers(market_id,state);
create index positions_owner on public.positions(owner_id,status);
create index ledger_owner on public.ledger(owner_id,created_at);

-- Prevent clients from modifying data directly. All writes go through validated RPCs.
revoke all on all tables in schema public from anon,authenticated;
grant usage on schema public to authenticated;
grant select on public.profiles,public.championships,public.competitors,public.markets,public.outcomes,public.offers,public.listings to authenticated;
grant select on public.wallets,public.ledger,public.positions,public.trades,public.applications,public.votes,public.score_history to authenticated;
alter table public.profiles enable row level security;
alter table public.admins enable row level security;
alter table public.championships enable row level security;
alter table public.applications enable row level security;
alter table public.competitors enable row level security;
alter table public.application_electorate enable row level security;
alter table public.votes enable row level security;
alter table public.score_history enable row level security;
alter table public.wallets enable row level security;
alter table public.ledger enable row level security;
alter table public.weekly_grants enable row level security;
alter table public.markets enable row level security;
alter table public.outcomes enable row level security;
alter table public.offers enable row level security;
alter table public.trades enable row level security;
alter table public.positions enable row level security;
alter table public.listings enable row level security;
create policy profiles_read on public.profiles for select to authenticated using(true);
create policy championships_read on public.championships for select to authenticated using(true);
create policy competitors_read on public.competitors for select to authenticated using(true);
create policy markets_read on public.markets for select to authenticated using(true);
create policy outcomes_read on public.outcomes for select to authenticated using(true);
create policy offers_read on public.offers for select to authenticated using(true);
create policy listings_read on public.listings for select to authenticated using(true);
create policy wallets_own on public.wallets for select to authenticated using(owner_id=auth.uid());
create policy ledger_own on public.ledger for select to authenticated using(owner_id=auth.uid());
create policy positions_own on public.positions for select to authenticated using(owner_id=auth.uid());
create policy applications_read on public.applications for select to authenticated using(true);
create policy votes_own on public.votes for select to authenticated using(voter_id=auth.uid());
create policy score_read on public.score_history for select to authenticated using(true);

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.admins where id=auth.uid())
$$;
create or replace function public.is_competitor() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.competitors where id=auth.uid())
$$;
create or replace function public.my_roles() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('is_admin',public.is_admin(),'is_competitor',public.is_competitor())
$$;
create or replace function public.transfer_coins(
 p_owner uuid,p_avail numeric,p_reserve numeric,p_reason text,p_ref text
) returns void language plpgsql security definer set search_path='' as $$
begin
 update public.wallets set available=available+p_avail,reserved=reserved+p_reserve where owner_id=p_owner;
 if not found then raise exception 'Wallet não encontrada'; end if;
 insert into public.ledger(owner_id,available_delta,reserved_delta,reason,reference)
 values(p_owner,p_avail,p_reserve,p_reason,p_ref);
end $$;

-- Profile creation is server-side, including the single initial grant.
create or replace function public.register_player()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,nickname) values(new.id,'Jogador-'||substr(new.id::text,1,8));
 insert into public.wallets(owner_id,available,total_issued) values(new.id,1000,1000);
 insert into public.ledger(owner_id,available_delta,reserved_delta,reason,reference)
 values(new.id,1000,0,'initial_grant',new.id::text);
 return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.register_player();

create or replace function public.update_nickname(p_nickname text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if length(btrim(p_nickname)) not between 2 and 40 then raise exception 'Nickname inválido'; end if;
 update public.profiles set nickname=btrim(p_nickname) where id=auth.uid();
 if not found then raise exception 'Não autenticado'; end if;
end $$;
create or replace function public.apply_competitor() returns void
language plpgsql security definer set search_path='' as $$
declare v_count integer;
begin
 if auth.uid() is null then raise exception 'Não autenticado'; end if;
 perform pg_advisory_xact_lock(941001);
 if exists(select 1 from public.competitors where id=auth.uid()) then raise exception 'Já és concorrente'; end if;
 if exists(select 1 from public.applications where candidate_id=auth.uid() and state='pending') then raise exception 'Candidatura já aberta'; end if;
 select count(*) into v_count from public.competitors;
 if v_count=0 then
   -- Bootstrap first competitor only by an explicit administrator, never first signup.
   raise exception 'A primeira admissão requer um administrador';
 end if;
 with created as (insert into public.applications(candidate_id,eligible_votes) values(auth.uid(),v_count) returning id)
 insert into public.application_electorate(application_id,voter_id)
 select created.id,c.id from created cross join public.competitors c;
end $$;
create or replace function public.vote_application(p_application uuid,p_approve boolean)
returns void language plpgsql security definer set search_path='' as $$
declare v_app public.applications%rowtype;v_yes integer;v_no integer;
begin
 perform pg_advisory_xact_lock(941001);
 if not public.is_competitor() then raise exception 'Apenas concorrentes votam';end if;
 select * into v_app from public.applications where id=p_application for update;
 if not found or v_app.state<>'pending' then raise exception 'Candidatura indisponível'; end if;
 if v_app.candidate_id=auth.uid() then raise exception 'Não podes votar na própria candidatura'; end if;
 if not exists(select 1 from public.application_electorate where application_id=p_application and voter_id=auth.uid()) then raise exception 'Não pertences ao eleitorado desta votação';end if;
 insert into public.votes(application_id,voter_id,approve) values(p_application,auth.uid(),p_approve);
 select count(*) filter(where approve),count(*) filter(where not approve) into v_yes,v_no from public.votes where application_id=p_application;
 if v_yes > v_app.eligible_votes/2 then
  update public.applications set state='approved',decided_at=now() where id=p_application;
  insert into public.competitors(id) values(v_app.candidate_id);
 elsif v_no >= v_app.eligible_votes/2.0 then
  update public.applications set state='rejected',decided_at=now() where id=p_application;
 end if;
end $$;
create or replace function public.set_my_score(p_ytd numeric)
returns void language plpgsql security definer set search_path='' as $$
begin
 if p_ytd is null or p_ytd < -100 or p_ytd > 100000 then raise exception 'YTD inválido';end if;
 if not exists(select 1 from public.championships where state='open' and now()<=ends_at) then raise exception 'Campeonato fechado';end if;
 update public.competitors set ytd=p_ytd,updated_at=now() where id=auth.uid();
 if not found then raise exception 'Não és concorrente';end if;
 insert into public.score_history(competitor_id,ytd) values(auth.uid(),p_ytd);
end $$;
create or replace function public.get_competitors() returns table(id uuid,nickname text,ytd numeric,updated_at timestamptz)
language sql stable security definer set search_path='' as $$
 select c.id,p.nickname,c.ytd,c.updated_at from public.competitors c join public.profiles p on p.id=c.id order by c.ytd desc,c.joined_at asc
$$;
create or replace function public.get_applications()
returns table(id uuid,candidate_id uuid,nickname text,state text,yes_votes bigint,eligible_votes integer)
language sql stable security definer set search_path='' as $$
 select a.id,a.candidate_id,p.nickname,a.state,
 (select count(*) from public.votes v where v.application_id=a.id and v.approve),a.eligible_votes
 from public.applications a join public.profiles p on p.id=a.candidate_id where a.state='pending' order by a.created_at desc
$$;
create or replace function public.get_wallet() returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce((select jsonb_build_object('available',available,'reserved',reserved,'total_issued',total_issued)
 from public.wallets where owner_id=auth.uid()),'null'::jsonb)
$$;
create or replace function public.get_rankings()
returns table(nickname text,available numeric,reserved numeric,issued numeric)
language sql stable security definer set search_path='' as $$
 select p.nickname,w.available,w.reserved,w.total_issued from public.wallets w join public.profiles p on p.id=w.owner_id
 where not exists(select 1 from public.competitors c where c.id=w.owner_id)
 order by w.available+w.reserved desc,p.nickname
$$;
-- Public order-book detail through a narrow, authenticated, read-only RPC.
-- Positions are private on direct SELECT, but open listing metadata is market data.
create or replace function public.get_active_listings()
returns table(id uuid,position_id uuid,seller_id uuid,price numeric,state text,created_at timestamptz,
 side text,market_id uuid,outcome_id uuid,stake integer,liability numeric,outcome_label text,market_title text)
language sql stable security definer set search_path='' as $$
 select l.id,l.position_id,l.seller_id,l.price,l.state,l.created_at,
 p.side,p.market_id,p.outcome_id,p.stake,p.liability,o.label,m.title
 from public.listings l
 join public.positions p on p.id=l.position_id
 join public.outcomes o on o.id=p.outcome_id
 join public.markets m on m.id=p.market_id
 where l.state='open' and p.status='open' and m.state='open' and m.closes_at>now()
 order by l.created_at desc
$$;
-- Grant only after checking membership. The client never supplies user or period.
create or replace function public.grant_weekly(p_week date default null) returns integer
language plpgsql security definer set search_path='' as $$
declare v_week date;v_count integer:=0;v_owner uuid;
begin
 if not public.is_admin() then raise exception 'Sem permissão';end if;
 v_week:=date_trunc('week',current_timestamp at time zone 'UTC')::date;
 if p_week is not null and p_week<>v_week then raise exception 'Só é permitida a semana atual';end if;
 for v_owner in select w.owner_id from public.wallets w
 where not exists(select 1 from public.competitors c where c.id=w.owner_id)
 order by w.owner_id
 loop
  if not exists(select 1 from public.weekly_grants where owner_id=v_owner and week_start=v_week) then
   insert into public.weekly_grants(owner_id,week_start) values(v_owner,v_week) on conflict do nothing;
   if found then
    perform public.transfer_coins(v_owner,1000,0,'weekly_grant',v_week::text);
    update public.wallets set total_issued=total_issued+1000 where owner_id=v_owner;
    v_count:=v_count+1;
   end if;
  end if;
 end loop;
 return v_count;
end $$;
create or replace function public.create_market(p_title text,p_kind text,p_category text,p_closes_at timestamptz,p_competitors uuid[])
returns uuid language plpgsql security definer set search_path='' as $$
declare v_market uuid;v_id uuid;
begin
 if not public.is_admin() then raise exception 'Sem permissão';end if;
 if length(btrim(p_title)) not between 3 and 120 or p_kind not in ('annual','weekly','monthly') or p_category not in ('winner','second','last') then raise exception 'Mercado inválido';end if;
 if p_closes_at<=now() or coalesce(array_length(p_competitors,1),0)<2 then raise exception 'Prazo/concorrentes inválidos';end if;
 if not exists(select 1 from public.championships where state='open' and starts_at<=now() and ends_at>now() and p_closes_at<=ends_at) then raise exception 'Mercado fora do campeonato';end if;
 if (select count(distinct id) from public.competitors where id=any(p_competitors))<>array_length(p_competitors,1) then raise exception 'Concorrentes inválidos ou repetidos';end if;
 insert into public.markets(title,kind,category,closes_at) values(btrim(p_title),p_kind,p_category,p_closes_at) returning id into v_market;
 foreach v_id in array p_competitors loop
  insert into public.outcomes(market_id,competitor_id,label)
  select v_market,v_id,nickname from public.profiles where id=v_id;
 end loop;
 return v_market;
end $$;
create or replace function public.place_offer(p_outcome uuid,p_side text,p_odds numeric,p_stake integer)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_market public.markets%rowtype;v_offer uuid;v_reserve numeric;
begin
 if auth.uid() is null then raise exception 'Não autenticado';end if;
 if p_side not in ('back','lay') or p_odds<=1 or p_odds>1000 or p_odds<>round(p_odds,2) or p_stake<1 or p_stake>1000000 then raise exception 'Oferta inválida';end if;
 select m.* into v_market from public.markets m join public.outcomes o on o.market_id=m.id where o.id=p_outcome for update of m;
 if not found or v_market.state<>'open' or now()>=v_market.closes_at then raise exception 'Mercado fechado';end if;
 v_reserve:=case when p_side='back' then p_stake else round(p_stake*(p_odds-1),2) end;
 perform public.transfer_coins(auth.uid(),-v_reserve,v_reserve,'reserve_offer',gen_random_uuid()::text);
 insert into public.offers(market_id,outcome_id,owner_id,side,odds,stake_remaining)
 values(v_market.id,p_outcome,auth.uid(),p_side,p_odds,p_stake) returning id into v_offer;
 return v_offer;
end $$;
create or replace function public.accept_offer(p_offer uuid,p_stake integer)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_offer public.offers%rowtype;v_trade uuid;v_liability numeric;v_taker_reserve numeric;v_market_id uuid;
begin
 if auth.uid() is null or p_stake<1 then raise exception 'Pedido inválido';end if;
 select market_id into v_market_id from public.offers where id=p_offer;
 if v_market_id is null then raise exception 'Oferta indisponível';end if;
 perform 1 from public.markets where id=v_market_id and state='open' and closes_at>now() for update;
 if not found then raise exception 'Mercado fechado';end if;
 select * into v_offer from public.offers where id=p_offer for update;
 if not found or v_offer.state<>'open' or v_offer.stake_remaining<p_stake then raise exception 'Oferta indisponível';end if;
 if v_offer.owner_id=auth.uid() then raise exception 'Não podes aceitar a própria oferta';end if;
 if not exists(select 1 from public.markets where id=v_offer.market_id and state='open' and closes_at>now()) then raise exception 'Mercado fechado';end if;
 v_liability:=round(p_stake*(v_offer.odds-1),2);
 v_taker_reserve:=case when v_offer.side='back' then v_liability else p_stake end;
 perform public.transfer_coins(auth.uid(),-v_taker_reserve,v_taker_reserve,'reserve_trade',gen_random_uuid()::text);
 update public.offers set stake_remaining=stake_remaining-p_stake,
 state=case when stake_remaining=p_stake then 'filled' else 'open' end where id=p_offer;
 insert into public.trades(market_id,outcome_id,offer_id,odds,stake,liability)
 values(v_offer.market_id,v_offer.outcome_id,p_offer,v_offer.odds,p_stake,v_liability) returning id into v_trade;
 insert into public.positions(trade_id,owner_id,side,market_id,outcome_id,stake,liability)
 values(v_trade,v_offer.owner_id,v_offer.side,v_offer.market_id,v_offer.outcome_id,p_stake,v_liability),
 (v_trade,auth.uid(),case when v_offer.side='back' then 'lay' else 'back' end,v_offer.market_id,v_offer.outcome_id,p_stake,v_liability);
 return v_trade;
end $$;
create or replace function public.cancel_offer(p_offer uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_offer public.offers%rowtype;v_release numeric;
begin
 select * into v_offer from public.offers where id=p_offer for update;
 if not found or v_offer.owner_id<>auth.uid() or v_offer.state<>'open' then raise exception 'Não permitido';end if;
 v_release:=case when v_offer.side='back' then v_offer.stake_remaining else round(v_offer.stake_remaining*(v_offer.odds-1),2) end;
 update public.offers set state='cancelled',stake_remaining=0 where id=p_offer;
 perform public.transfer_coins(auth.uid(),v_release,-v_release,'cancel_offer',p_offer::text);
end $$;
create or replace function public.list_position(p_position uuid,p_price numeric)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_position public.positions%rowtype;v_listing uuid;
begin
 if p_price is null or p_price<=0 or p_price>100000000 then raise exception 'Preço inválido';end if;
 perform 1 from public.markets where id=(select market_id from public.positions where id=p_position) and state='open' and closes_at>now() for update;
 if not found then raise exception 'Mercado fechado';end if;
 select * into v_position from public.positions where id=p_position for update;
 if not found or v_position.owner_id<>auth.uid() or v_position.status<>'open' then raise exception 'Posição indisponível';end if;
 if not exists(select 1 from public.markets where id=v_position.market_id and state='open' and closes_at>now()) then raise exception 'Mercado encerrado';end if;
 insert into public.listings(position_id,seller_id,price) values(p_position,auth.uid(),round(p_price,2)) returning id into v_listing;
 return v_listing;
end $$;
create or replace function public.buy_position(p_listing uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_listing public.listings%rowtype;v_position public.positions%rowtype;v_collateral numeric;
begin
 if auth.uid() is null then raise exception 'Não autenticado';end if;
 perform 1 from public.markets where id=(select p.market_id from public.positions p join public.listings l on l.position_id=p.id where l.id=p_listing) and state='open' and closes_at>now() for update;
 if not found then raise exception 'Mercado fechado';end if;
 select * into v_listing from public.listings where id=p_listing for update;
 if not found or v_listing.state<>'open' or v_listing.seller_id=auth.uid() then raise exception 'Oferta indisponível';end if;
 select * into v_position from public.positions where id=v_listing.position_id for update;
 if v_position.status<>'open' or v_position.owner_id<>v_listing.seller_id then raise exception 'Posição indisponível';end if;
 if not exists(select 1 from public.markets where id=v_position.market_id and state='open' and closes_at>now()) then raise exception 'Mercado fechado';end if;
 v_collateral:=case when v_position.side='back' then v_position.stake else v_position.liability end;
 -- Seller transfers the already-reserved collateral to buyer; buyer pays only the listing price.
 -- No collateral is minted or destroyed; the aggregate wallet balance stays unchanged.
 perform public.transfer_coins(auth.uid(),-v_listing.price,v_collateral,'buy_position',p_listing::text);
 perform public.transfer_coins(v_listing.seller_id,v_listing.price,-v_collateral,'sell_position',p_listing::text);
 update public.positions set owner_id=auth.uid() where id=v_position.id;
 update public.listings set state='sold',sold_to=auth.uid(),sold_at=now() where id=p_listing;
end $$;
create or replace function public.cancel_listing(p_listing uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_listing public.listings%rowtype;
begin
 select * into v_listing from public.listings where id=p_listing for update;
 if not found or v_listing.seller_id<>auth.uid() or v_listing.state<>'open' then
  raise exception 'Anúncio indisponível';
 end if;
 update public.listings set state='cancelled' where id=p_listing;
end $$;
create or replace function public.settle_market(p_market uuid,p_winner uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_market public.markets%rowtype;v_trade public.trades%rowtype;v_back uuid;v_lay uuid;v_offer public.offers%rowtype;v_release numeric;
begin
 if not public.is_admin() then raise exception 'Sem permissão';end if;
 select * into v_market from public.markets where id=p_market for update;
 if not found or v_market.state<>'open' or v_market.closes_at>now() then raise exception 'Ainda não pode liquidar';end if;
 if not exists(select 1 from public.outcomes where id=p_winner and market_id=p_market) then raise exception 'Resultado inválido';end if;
 -- Closing open offers releases unfilled collateral.
 for v_offer in select * from public.offers where market_id=p_market and state='open' for update loop
  v_release:=case when v_offer.side='back' then v_offer.stake_remaining else round(v_offer.stake_remaining*(v_offer.odds-1),2) end;
  update public.offers set state='cancelled',stake_remaining=0 where id=v_offer.id;
  perform public.transfer_coins(v_offer.owner_id,v_release,-v_release,'expire_offer',v_offer.id::text);
 end loop;
 for v_trade in select * from public.trades where market_id=p_market and settled_at is null order by id loop
  select owner_id into v_back from public.positions where trade_id=v_trade.id and side='back' for update;
  select owner_id into v_lay from public.positions where trade_id=v_trade.id and side='lay' for update;
  if v_trade.outcome_id=p_winner then
   perform public.transfer_coins(v_back,v_trade.stake+v_trade.liability,-v_trade.stake,'back_wins',v_trade.id::text);
   perform public.transfer_coins(v_lay,0,-v_trade.liability,'lay_loses',v_trade.id::text);
  else
   perform public.transfer_coins(v_lay,v_trade.stake+v_trade.liability,-v_trade.liability,'lay_wins',v_trade.id::text);
   perform public.transfer_coins(v_back,0,-v_trade.stake,'back_loses',v_trade.id::text);
  end if;
  update public.positions set status='settled' where trade_id=v_trade.id;
  update public.trades set settled_at=now() where id=v_trade.id;
 end loop;
 update public.listings set state='cancelled' where state='open' and position_id in(select id from public.positions where market_id=p_market);
 update public.markets set state='settled',winner_outcome_id=p_winner where id=p_market;
end $$;
-- Views exposed to the frontend, use invoker checks on the underlying rows.
create view public.my_positions with(security_invoker=true) as
 select * from public.positions where owner_id=(select auth.uid());
create view public.active_listings with(security_invoker=true) as
 select * from public.listings where state='open';
grant select on public.my_positions,public.active_listings to authenticated;

-- API is read-only for anyone not authenticated; grant execute only to authenticated.
-- Financial invariants: total available+reserved changes only for initial/weekly grant.
-- Each trade carries exactly two sides. Reselling moves its full colateral intact.
-- Block automatic execution of helper functions by users.
revoke all on function public.transfer_coins(uuid,numeric,numeric,text,text) from public,anon,authenticated;
revoke all on function public.register_player() from public,anon,authenticated;
-- Explicit executable RPC allowlist; postgres grants PUBLIC EXECUTE by default.
do $$
declare f record;
begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f' loop
  execute format('revoke all on function %s from public, anon, authenticated',f.signature);
 end loop;
end $$;
grant execute on function public.my_roles(),public.get_competitors(),public.get_applications(),
 public.get_wallet(),public.get_rankings(),public.get_active_listings(),public.is_admin(),public.is_competitor() to authenticated;
grant execute on function public.update_nickname(text),public.apply_competitor(),
 public.vote_application(uuid,boolean),public.set_my_score(numeric),
 public.place_offer(uuid,text,numeric,integer),public.accept_offer(uuid,integer),
 public.cancel_offer(uuid),public.list_position(uuid,numeric),public.cancel_listing(uuid),public.buy_position(uuid) to authenticated;
grant execute on function public.create_market(text,text,text,timestamptz,uuid[]),
 public.settle_market(uuid,uuid),public.grant_weekly(date) to authenticated;

-- The administrator and the initial competitor are bootstrapped manually during setup,
-- using explicit auth UUIDs, never from user-controlled profile data.
insert into public.championships(name,starts_at,ends_at)
values('Campeonato 2026','2026-01-01T00:00:00Z','2026-12-31T23:59:59Z');
-- END 202611120001_init.sql


-- =============================================================================
-- BEGIN 202611120002_sprints.sql [source blob: 0332bb7490e2d85f860715e9e34fe4ef61e99063]
-- =============================================================================
-- Sprint snapshots are authoritative when captured, and never inferred from a
-- competitor's latest score retroactively. The operator must validate boundaries.
create table public.sprints(
 id uuid primary key default gen_random_uuid(),
 championship_id uuid not null references public.championships(id),
 name text not null,
 kind text not null check(kind in ('weekly','monthly')),
 starts_at timestamptz not null,
 ends_at timestamptz not null,
 state text not null default 'open' check(state in ('open','closed')),
 check(ends_at>starts_at),
 unique(championship_id,kind,starts_at)
);
create table public.sprint_scores(
 sprint_id uuid not null references public.sprints(id),
 competitor_id uuid not null references public.competitors(id),
 phase text not null check(phase in ('start','end')),
 ytd numeric(12,4) not null check(ytd>=-100),
 captured_at timestamptz not null default now(),
 primary key(sprint_id,competitor_id,phase)
);
alter table public.sprints enable row level security;
alter table public.sprint_scores enable row level security;
create policy sprint_read on public.sprints for select to authenticated using(true);
create policy sprint_score_read on public.sprint_scores for select to authenticated using(true);
grant select on public.sprints,public.sprint_scores to authenticated;
create or replace function public.create_sprint(p_name text,p_kind text,p_start timestamptz,p_end timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_champ uuid;
begin
 if not public.is_admin() then raise exception 'Sem permissão';end if;
 if length(btrim(p_name)) not between 3 and 120 or p_kind not in ('weekly','monthly') or p_start is null or p_end is null or p_end<=p_start then raise exception 'Sprint inválido';end if;
 select id into v_champ from public.championships where state='open' and p_start>=starts_at and p_end<=ends_at;
 if v_champ is null then raise exception 'Sprint fora do campeonato';end if;
 insert into public.sprints(championship_id,name,kind,starts_at,ends_at)
 values(v_champ,btrim(p_name),p_kind,p_start,p_end) returning id into v_id;
 return v_id;
end $$;
create or replace function public.capture_sprint(p_sprint uuid,p_phase text)
returns integer language plpgsql security definer set search_path='' as $$
declare v_sprint public.sprints%rowtype;v_total integer;
begin
 if not public.is_admin() then raise exception 'Sem permissão';end if;
 if p_phase not in ('start','end') then raise exception 'Fase inválida';end if;
 select * into v_sprint from public.sprints where id=p_sprint for update;
 if not found or v_sprint.state<>'open' then raise exception 'Sprint fechado';end if;
 -- Snapshots must be taken within their capture windows and never overwritten.
 if p_phase='start' and (now()<v_sprint.starts_at or now()>=v_sprint.ends_at) then raise exception 'Fora do período';end if;
 if p_phase='end' and now()<v_sprint.ends_at then raise exception 'Sprint ainda em curso';end if;
 if exists(select 1 from public.sprint_scores where sprint_id=p_sprint and phase=p_phase) then raise exception 'Snapshot já capturado';end if;
 insert into public.sprint_scores(sprint_id,competitor_id,phase,ytd)
 select p_sprint,c.id,p_phase,c.ytd from public.competitors c;
 get diagnostics v_total=row_count;
 if p_phase='end' then update public.sprints set state='closed' where id=p_sprint;end if;
 return v_total;
end $$;
create or replace function public.get_sprint_rankings(p_sprint uuid)
returns table(competitor_id uuid,nickname text,start_ytd numeric,end_ytd numeric,return_pct numeric)
language sql stable security definer set search_path='' as $$
 select c.id,p.nickname,a.ytd,b.ytd,
 round(((1+b.ytd/100)/nullif(1+a.ytd/100,0)-1)*100,4)
 from public.competitors c
 join public.profiles p on p.id=c.id
 join public.sprint_scores a on a.sprint_id=p_sprint and a.phase='start' and a.competitor_id=c.id
 join public.sprint_scores b on b.sprint_id=p_sprint and b.phase='end' and b.competitor_id=c.id
 where a.ytd>-100
 order by 5 desc,c.id
$$;
revoke all on function public.create_sprint(text,text,timestamptz,timestamptz),
 public.capture_sprint(uuid,text),public.get_sprint_rankings(uuid) from public,anon,authenticated;
grant execute on function public.create_sprint(text,text,timestamptz,timestamptz),
 public.capture_sprint(uuid,text),public.get_sprint_rankings(uuid) to authenticated;
-- END 202611120002_sprints.sql


-- =============================================================================
-- BEGIN 202611140001_sprint_delta.sql [source blob: 49dd2ee3a07935544edf257a937483986f48023a]
-- =============================================================================
-- Follow-up migration: existing sprint rankings used compounded returns.
-- BetCoins period-gain bets measure the arithmetic YTD difference in percentage points.
-- Idempotent replace; no historical data or snapshots are rewritten.
create or replace function public.get_sprint_rankings(p_sprint uuid)
returns table(competitor_id uuid,nickname text,start_ytd numeric,end_ytd numeric,return_pct numeric)
language sql stable security definer set search_path='' as $$
 select c.id,p.nickname,a.ytd,b.ytd,round(b.ytd-a.ytd,4)
 from public.competitors c
 join public.profiles p on p.id=c.id
 join public.sprint_scores a on a.sprint_id=p_sprint and a.phase='start' and a.competitor_id=c.id
 join public.sprint_scores b on b.sprint_id=p_sprint and b.phase='end' and b.competitor_id=c.id
 order by 5 desc,c.id
$$;
revoke all on function public.get_sprint_rankings(uuid) from public,anon,authenticated;
grant execute on function public.get_sprint_rankings(uuid) to authenticated;
-- END 202611140001_sprint_delta.sql


-- =============================================================================
-- BEGIN 202611140002_position_cost_basis.sql [source blob: e9311aefa92213f8acb0ac22d6319b1c722bae42]
-- =============================================================================
-- Position secondary-market accounting. Additive migration; review before remote application.
-- Economic acquisition cost is distinct from the collateral already reserved in wallets.

alter table public.positions add column cost_basis numeric(18,2);
-- Existing positions are originally matched trades, unless already resold in the MVP.
-- Reconstruct the current holder's basis using their most recent completed listing purchase
-- whenever possible; otherwise use the original stake (BACK) or liability (LAY).
update public.positions p
set cost_basis = coalesce(
 (select l.price from public.listings l
  where l.position_id=p.id and l.state='sold' and l.sold_to=p.owner_id
  order by l.sold_at desc nulls last,l.created_at desc limit 1),
 case when p.side='back' then p.stake else p.liability end
);
alter table public.positions alter column cost_basis set not null;
alter table public.positions add constraint positions_cost_basis_nonnegative check(cost_basis>=0);

-- Legacy matching RPCs insert positions without explicitly supplying cost_basis.
-- Capture the original exposure automatically for new matched BACK/LAY positions.
create or replace function public.initialize_position_cost_basis()
returns trigger language plpgsql set search_path='' as $$
begin
 if new.cost_basis is null then
  new.cost_basis := case when new.side='back' then new.stake else new.liability end;
 end if;
 return new;
end $$;
create trigger positions_initial_cost_basis
before insert on public.positions
for each row execute function public.initialize_position_cost_basis();


-- Completed sales are immutable records of price, owner and the seller's economic result.
create table public.position_sales (
 listing_id uuid primary key references public.listings(id),
 position_id uuid not null references public.positions(id),
 seller_id uuid not null references public.wallets(owner_id),
 buyer_id uuid not null references public.wallets(owner_id),
 seller_cost_basis numeric(18,2) not null check(seller_cost_basis>=0),
 sale_price numeric(18,2) not null check(sale_price>0),
 realized_pnl numeric(18,2) generated always as (sale_price-seller_cost_basis) stored,
 traded_at timestamptz not null default now(),
 check(seller_id<>buyer_id)
);
create index position_sales_seller_idx on public.position_sales(seller_id,traded_at desc);
create index position_sales_buyer_idx on public.position_sales(buyer_id,traded_at desc);
alter table public.position_sales enable row level security;
create policy position_sales_participants_read on public.position_sales
 for select to authenticated
 using(seller_id=(select auth.uid()) or buyer_id=(select auth.uid()));
revoke all on public.position_sales from public,anon,authenticated;
grant select on public.position_sales to authenticated;

-- Historical resales completed before this migration have no immutable cost-basis record.
-- Preserve their actual prices and order but do not fabricate prior cost bases or P&L.
-- The listing history remains available; new sales are recorded prospectively.

create or replace function public.buy_position(p_listing uuid)
returns void language plpgsql security definer set search_path='' as $$
declare
 v_listing public.listings%rowtype;
 v_position public.positions%rowtype;
 v_collateral numeric;
begin
 if auth.uid() is null then raise exception 'Não autenticado'; end if;
 perform 1 from public.markets
  where id=(select p.market_id from public.positions p
    join public.listings l on l.position_id=p.id where l.id=p_listing)
  and state='open' and closes_at>now() for update;
 if not found then raise exception 'Mercado fechado'; end if;
 select * into v_listing from public.listings where id=p_listing for update;
 if not found or v_listing.state<>'open' or v_listing.seller_id=auth.uid() then
  raise exception 'Oferta indisponível';
 end if;
 select * into v_position from public.positions where id=v_listing.position_id for update;
 if not found or v_position.status<>'open' or v_position.owner_id<>v_listing.seller_id then
  raise exception 'Posição indisponível';
 end if;
 if not exists(select 1 from public.markets
  where id=v_position.market_id and state='open' and closes_at>now()) then
  raise exception 'Mercado fechado';
 end if;
 v_collateral:=case when v_position.side='back' then v_position.stake else v_position.liability end;
 -- The existing collateral moves to the buyer; the listing price is consideration,
 -- not a replacement for collateral or a new mint.
 perform public.transfer_coins(auth.uid(),-v_listing.price,v_collateral,'buy_position',p_listing::text);
 perform public.transfer_coins(v_listing.seller_id,v_listing.price,-v_collateral,'sell_position',p_listing::text);
 insert into public.position_sales(
  listing_id,position_id,seller_id,buyer_id,seller_cost_basis,sale_price
 ) values (
  p_listing,v_position.id,v_listing.seller_id,auth.uid(),v_position.cost_basis,v_listing.price
 );
 update public.positions
  set owner_id=auth.uid(),cost_basis=v_listing.price
  where id=v_position.id;
 update public.listings
  set state='sold',sold_to=auth.uid(),sold_at=now()
  where id=p_listing;
end $$;
revoke all on function public.buy_position(uuid) from public,anon,authenticated;
grant execute on function public.buy_position(uuid) to authenticated;
-- END 202611140002_position_cost_basis.sql


-- =============================================================================
-- BEGIN 202611150001_wallet_reconciliation.sql [source blob: d10c75a76a4354ad4c03cf0e1a7ee7a86962444f]
-- =============================================================================
-- Issue #4: recover missed weekly grants and reconcile wallet balances with the ledger.
-- Additive migration: does not issue grants or change existing balances on application.
-- Dates are UTC, with ISO weeks starting on Monday.
create or replace function public.grant_weekly(p_week date default null)
returns integer language plpgsql security definer set search_path='' as $$
declare
 v_start date;
 v_last date;
 v_owner uuid;
 v_week date;
 v_count integer := 0;
 v_registered date;
begin
 if not public.is_admin() then raise exception 'Sem permissão'; end if;
 select min(starts_at) at time zone 'UTC'
 into v_start
 from public.championships
 where state='open' and starts_at<=now() and ends_at>=now();
 if v_start is null then raise exception 'Não existe campeonato ativo'; end if;
 v_start := date_trunc('week',v_start::timestamp)::date;
 v_last := date_trunc('week',now() at time zone 'UTC')::date;
 if p_week is not null and (p_week<>date_trunc('week',p_week::timestamp)::date or p_week<v_start or p_week>v_last) then
  raise exception 'Semana fora do campeonato ou no futuro';
 end if;

 -- Grant only to users who are spectators now. Registration date is the
 -- earliest eligible week; no credits for weeks before account creation.
 for v_owner,v_registered in
  select w.owner_id,date_trunc('week',p.created_at at time zone 'UTC')::date
  from public.wallets w
  join public.profiles p on p.id=w.owner_id
  where not exists(select 1 from public.competitors c where c.id=w.owner_id)
  order by w.owner_id
 loop
  for v_week in
   select gs::date
   from generate_series(
    greatest(v_start,v_registered)::timestamp,
    (case when p_week is null then v_last else p_week end)::timestamp,
    interval '7 days'
   ) as gs
   where p_week is null or gs::date=p_week
  loop
   insert into public.weekly_grants(owner_id,week_start)
   values(v_owner,v_week) on conflict do nothing;
   if found then
    perform public.transfer_coins(v_owner,1000,0,'weekly_grant',v_week::text);
    update public.wallets set total_issued=total_issued+1000 where owner_id=v_owner;
    v_count:=v_count+1;
   end if;
  end loop;
 end loop;
 return v_count;
end $$;
revoke all on function public.grant_weekly(date) from public,anon,authenticated;
grant execute on function public.grant_weekly(date) to authenticated;

-- Read-only reconciliation: no automatic adjustment of economic balances.
-- Each owner is checked independently; total issued must match issuance entries.
create or replace function public.reconcile_wallets()
returns table(
 owner_id uuid,
 nickname text,
 actual_available numeric,
 ledger_available numeric,
 available_difference numeric,
 actual_reserved numeric,
 ledger_reserved numeric,
 reserved_difference numeric,
 actual_issued numeric,
 ledger_issued numeric,
 issued_difference numeric,
 balanced boolean
)
language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Sem permissão'; end if;
 return query
 select w.owner_id,p.nickname,
  w.available,coalesce(l.available_total,0),
  w.available-coalesce(l.available_total,0),
  w.reserved,coalesce(l.reserved_total,0),
  w.reserved-coalesce(l.reserved_total,0),
  w.total_issued,coalesce(l.issued_total,0),
  w.total_issued-coalesce(l.issued_total,0),
  w.available=coalesce(l.available_total,0)
  and w.reserved=coalesce(l.reserved_total,0)
  and w.total_issued=coalesce(l.issued_total,0)
 from public.wallets w
 join public.profiles p on p.id=w.owner_id
 left join lateral (
  select sum(e.available_delta) as available_total,
   sum(e.reserved_delta) as reserved_total,
   sum(case when e.reason in ('initial_grant','weekly_grant')
    then e.available_delta else 0 end) as issued_total
  from public.ledger e where e.owner_id=w.owner_id
 ) l on true
 order by p.nickname,w.owner_id;
end $$;
revoke all on function public.reconcile_wallets() from public,anon,authenticated;
grant execute on function public.reconcile_wallets() to authenticated;
-- END 202611150001_wallet_reconciliation.sql


-- =============================================================================
-- BEGIN 202611150002_spectator_rankings.sql [source blob: 1460a69d55ddb90f5753be109f7702a310ce3a75]
-- =============================================================================
-- #7: reproducible, ledger-based spectator rankings (book value, not market value).
-- Public results expose aggregate spectator metrics, never private order/trade details.
-- No direct balance writes or marks at a guessed price.
create or replace function public.get_spectator_rankings(p_as_of timestamptz default null)
returns table(
 owner_id uuid, nickname text, available numeric, reserved numeric,
 issued numeric, wealth numeric, relative_pct numeric,
 realized_resale_pnl numeric, open_positions bigint, exposure numeric,
 valuation_status text
)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Não autenticado'; end if;
 if p_as_of is not null and p_as_of>now() then
  raise exception 'A data da classificação não pode estar no futuro';
 end if;
 return query
 select w.owner_id,p.nickname,
   case when p_as_of is null then w.available else coalesce(h.available,0) end,
   case when p_as_of is null then w.reserved else coalesce(h.reserved,0) end,
   case when p_as_of is null then w.total_issued else coalesce(h.issued,0) end,
   (case when p_as_of is null then w.available+w.reserved
     else coalesce(h.available,0)+coalesce(h.reserved,0) end) as wealth,
   case when (case when p_as_of is null then w.total_issued else coalesce(h.issued,0) end)>0
    then round(
      100*((case when p_as_of is null then w.available+w.reserved
        else coalesce(h.available,0)+coalesce(h.reserved,0) end)
       -(case when p_as_of is null then w.total_issued else coalesce(h.issued,0) end))
      / (case when p_as_of is null then w.total_issued else coalesce(h.issued,0) end),2)
    else null end,
   coalesce(s.realized_pnl,0),
   case when p_as_of is null then coalesce(pos.position_count,0) else null end,
   case when p_as_of is null then coalesce(pos.collateral,0) else null end,
   'contabilistico_sem_cotacao'::text
 from public.wallets w
 join public.profiles p on p.id=w.owner_id
 left join lateral (
  select sum(e.available_delta) as available,
         sum(e.reserved_delta) as reserved,
         sum(case when e.reason in ('initial_grant','weekly_grant')
              then e.available_delta else 0 end) as issued
  from public.ledger e
  where e.owner_id=w.owner_id and e.created_at<=p_as_of
 ) h on p_as_of is not null
 left join lateral (
  select sum(ps.realized_pnl) as realized_pnl
  from public.position_sales ps
  where ps.seller_id=w.owner_id
    and (p_as_of is null or ps.traded_at<=p_as_of)
 ) s on true
 left join lateral (
  select count(*) as position_count,
         sum(case when op.side='back' then op.stake else op.liability end) as collateral
  from public.positions op
  where op.owner_id=w.owner_id and op.status='open'
 ) pos on p_as_of is null
 where (p_as_of is null or p.created_at<=p_as_of)
   and not exists(
    select 1 from public.competitors c
    where c.id=w.owner_id and (p_as_of is null or c.joined_at<=p_as_of)
   )
 order by 6 desc,p.nickname,w.owner_id;
end $$;
revoke all on function public.get_spectator_rankings(timestamptz) from public,anon,authenticated;
grant execute on function public.get_spectator_rankings(timestamptz) to authenticated;
-- END 202611150002_spectator_rankings.sql


-- =============================================================================
-- BEGIN 202611150003_partial_resale.sql [source blob: b8c17d8dc6f47574bc3a1abf4a78120837a21905]
-- =============================================================================
-- #6: exact partial resale through indivisible BACK/LAY trade slices.
-- No currency is issued or removed. Split happens inside the atomic purchase transaction.
-- A listing may represent the whole position or an exact stake/liability slice.

alter table public.listings
 add column requested_stake integer check(requested_stake>0);

alter table public.positions
 add column parent_position_id uuid references public.positions(id);

-- A price is exact to cents, never silently rounded.
create or replace function public.list_position(
 p_position uuid, p_price numeric, p_stake integer
) returns uuid language plpgsql security definer set search_path='' as $$
declare
 v_position public.positions%rowtype;
 v_opposite public.positions%rowtype;
 v_listing uuid;
 v_slice_liability numeric;
begin
 if auth.uid() is null then raise exception 'Não autenticado'; end if;
 if p_price is null or p_price<=0 or p_price>100000000 or round(p_price,2)<>p_price then
  raise exception 'Preço inválido: usa no máximo duas casas decimais';
 end if;
 perform 1 from public.markets
  where id=(select market_id from public.positions where id=p_position)
    and state='open' and closes_at>now()
  for update;
 if not found then raise exception 'Mercado fechado'; end if;
 select * into v_position from public.positions where id=p_position for update;
 if not found or v_position.owner_id<>auth.uid() or v_position.status<>'open' then
  raise exception 'Posição indisponível';
 end if;
 if p_stake is null or p_stake=v_position.stake then
  insert into public.listings(position_id,seller_id,price,requested_stake)
  values(p_position,auth.uid(),p_price,v_position.stake) returning id into v_listing;
  return v_listing;
 end if;
 if p_stake<=0 or p_stake>=v_position.stake then raise exception 'Lote inválido'; end if;
 select * into v_opposite from public.positions
  where trade_id=v_position.trade_id and side<>v_position.side
  for update;
 if not found or v_opposite.status<>'open' then raise exception 'Contraparte indisponível'; end if;
 if exists(select 1 from public.listings
  where position_id=v_opposite.id and state='open') then
  raise exception 'A contraparte já está anunciada';
 end if;
 v_slice_liability := v_position.liability*p_stake/v_position.stake;
 if round(v_slice_liability,2)<>v_slice_liability
  or trunc(v_slice_liability)<>v_slice_liability
  or round(v_position.cost_basis*p_stake/v_position.stake,2)<>(v_position.cost_basis*p_stake/v_position.stake)
  or round(v_opposite.cost_basis*p_stake/v_position.stake,2)<>(v_opposite.cost_basis*p_stake/v_position.stake) then
  raise exception 'Lote não divisível: stake, responsabilidade e custo precisam de cêntimos exatos';
 end if;
 insert into public.listings(position_id,seller_id,price,requested_stake)
 values(p_position,auth.uid(),p_price,p_stake) returning id into v_listing;
 return v_listing;
end $$;

-- Keep the two-argument API for existing clients (full resale only).
create or replace function public.list_position(p_position uuid,p_price numeric)
returns uuid language sql security definer set search_path='' as $$
 select public.list_position(p_position,p_price,null::integer)
$$;

create or replace function public.buy_position(p_listing uuid)
returns void language plpgsql security definer set search_path='' as $$
declare
 v_listing public.listings%rowtype;
 v_position public.positions%rowtype;
 v_opposite public.positions%rowtype;
 v_trade public.trades%rowtype;
 v_piece_trade uuid;
 v_bought_position uuid;
 v_piece_stake integer;
 v_piece_liability numeric;
 v_seller_basis numeric;
 v_opposite_basis numeric;
 v_collateral numeric;
begin
 if auth.uid() is null then raise exception 'Não autenticado'; end if;
 perform 1 from public.markets
  where id=(select p.market_id from public.positions p
    join public.listings l on l.position_id=p.id where l.id=p_listing)
   and state='open' and closes_at>now()
  for update;
 if not found then raise exception 'Mercado fechado'; end if;
 select * into v_listing from public.listings where id=p_listing for update;
 if not found or v_listing.state<>'open' or v_listing.seller_id=auth.uid() then
  raise exception 'Anúncio indisponível';
 end if;
 select * into v_position from public.positions where id=v_listing.position_id for update;
 if not found or v_position.status<>'open' or v_position.owner_id<>v_listing.seller_id then
  raise exception 'Posição indisponível';
 end if;
 v_piece_stake:=coalesce(v_listing.requested_stake,v_position.stake);
 if v_piece_stake<=0 or v_piece_stake>v_position.stake then
  raise exception 'Lote já não disponível';
 end if;
 v_piece_liability:=v_position.liability*v_piece_stake/v_position.stake;
 if round(v_piece_liability,2)<>v_piece_liability or
    (v_piece_stake<v_position.stake and trunc(v_piece_liability)<>v_piece_liability) then
  raise exception 'Responsabilidade não divisível em moedas inteiras';
 end if;
 v_seller_basis:=v_position.cost_basis*v_piece_stake/v_position.stake;
 if round(v_seller_basis,2)<>v_seller_basis then raise exception 'Custo não divisível'; end if;
 v_bought_position:=v_position.id;

 if v_piece_stake<v_position.stake then
  -- Both sides of one trade must split identically for settlement to remain valid.
  select * into v_opposite from public.positions
   where trade_id=v_position.trade_id and side<>v_position.side for update;
  if not found or v_opposite.status<>'open' then raise exception 'Contraparte indisponível'; end if;
  if exists(select 1 from public.listings
   where position_id=v_opposite.id and state='open') then
   raise exception 'Contraparte anunciada: não é possível dividir';
  end if;
  v_opposite_basis:=v_opposite.cost_basis*v_piece_stake/v_position.stake;
  if round(v_opposite_basis,2)<>v_opposite_basis then
   raise exception 'Custo da contraparte não divisível';
  end if;
  select * into v_trade from public.trades where id=v_position.trade_id for update;
  if v_trade.settled_at is not null or v_trade.stake<>v_position.stake
    or v_trade.liability<>v_position.liability then
    raise exception 'Trade indisponível para divisão';
  end if;
  insert into public.trades(market_id,outcome_id,offer_id,odds,stake,liability,created_at)
   values(v_trade.market_id,v_trade.outcome_id,v_trade.offer_id,v_trade.odds,
          v_piece_stake,v_piece_liability,v_trade.created_at)
   returning id into v_piece_trade;
  -- Keep the original trade/positions as the residual lot.
  update public.trades
   set stake=v_trade.stake-v_piece_stake,liability=v_trade.liability-v_piece_liability
   where id=v_trade.id;
  update public.positions set
   stake=v_position.stake-v_piece_stake,
   liability=v_position.liability-v_piece_liability,
   cost_basis=v_position.cost_basis-v_seller_basis
   where id=v_position.id;
  update public.positions set
   stake=v_opposite.stake-v_piece_stake,
   liability=v_opposite.liability-v_piece_liability,
   cost_basis=v_opposite.cost_basis-v_opposite_basis
   where id=v_opposite.id;
  insert into public.positions(trade_id,owner_id,side,market_id,outcome_id,stake,liability,cost_basis,parent_position_id)
   values(v_piece_trade,v_listing.seller_id,v_position.side,v_position.market_id,
          v_position.outcome_id,v_piece_stake,v_piece_liability,v_seller_basis,v_position.id)
   returning id into v_bought_position;
  insert into public.positions(trade_id,owner_id,side,market_id,outcome_id,stake,liability,cost_basis,parent_position_id)
   values(v_piece_trade,v_opposite.owner_id,v_opposite.side,v_opposite.market_id,
          v_opposite.outcome_id,v_piece_stake,v_piece_liability,v_opposite_basis,v_opposite.id);
 end if;

 v_collateral:=case when v_position.side='back' then v_piece_stake else v_piece_liability end;
 -- A buyer must have liquid balance for the ask. Reserved collateral moves unchanged.
 perform public.transfer_coins(auth.uid(),-v_listing.price,v_collateral,'buy_position',p_listing::text);
 perform public.transfer_coins(v_listing.seller_id,v_listing.price,-v_collateral,'sell_position',p_listing::text);
 insert into public.position_sales(
   listing_id,position_id,seller_id,buyer_id,seller_cost_basis,sale_price
 ) values(
   p_listing,v_bought_position,v_listing.seller_id,auth.uid(),v_seller_basis,v_listing.price
 );
 update public.positions set owner_id=auth.uid(),cost_basis=v_listing.price
  where id=v_bought_position;
 update public.listings set state='sold',sold_to=auth.uid(),sold_at=now()
  where id=p_listing;
end $$;

-- The published marketplace must display the slice, not the entire source position.
create or replace function public.get_active_listings()
returns table(id uuid,position_id uuid,seller_id uuid,price numeric,state text,created_at timestamptz,
 side text,market_id uuid,outcome_id uuid,stake integer,liability numeric,outcome_label text,market_title text)
language sql stable security definer set search_path='' as $$
 select l.id,l.position_id,l.seller_id,l.price,l.state,l.created_at,
  p.side,p.market_id,p.outcome_id,coalesce(l.requested_stake,p.stake),
  round(p.liability*coalesce(l.requested_stake,p.stake)/p.stake,2),
  o.label,m.title
 from public.listings l
 join public.positions p on p.id=l.position_id
 join public.outcomes o on o.id=p.outcome_id
 join public.markets m on m.id=p.market_id
 where l.state='open' and p.status='open' and m.state='open' and m.closes_at>now()
 order by l.created_at desc
$$;

revoke all on function public.list_position(uuid,numeric,integer) from public,anon,authenticated;
grant execute on function public.list_position(uuid,numeric,integer) to authenticated;
revoke all on function public.list_position(uuid,numeric) from public,anon,authenticated;
grant execute on function public.list_position(uuid,numeric) to authenticated;
revoke all on function public.buy_position(uuid) from public,anon,authenticated;
grant execute on function public.buy_position(uuid) to authenticated;
revoke all on function public.get_active_listings() from public,anon,authenticated;
grant execute on function public.get_active_listings() to authenticated;
-- END 202611150003_partial_resale.sql
