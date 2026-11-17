-- #11 acceptance: current recurring model, immutable occurrence results and public
-- market activity. Versioned only; requires 01--16. No legacy import or remote SQL.
begin;
create table public.occurrence_classifications(
 id uuid primary key default gen_random_uuid(),occurrence_id uuid not null references public.bet_occurrences(id),
 mode text not null check(mode in ('snapshot_value','snapshot_delta_previous')),
 current_capture_id uuid not null references public.competition_captures(id),
 previous_capture_id uuid references public.competition_captures(id),source_market_id uuid not null references public.markets(id),
 rows jsonb not null check(jsonb_typeof(rows)='array'),recorded_at timestamptz not null default clock_timestamp(),
 unique(occurrence_id,mode)
);
alter table public.occurrence_classifications enable row level security;
revoke all on public.occurrence_classifications from public,anon,authenticated;
grant select on public.occurrence_classifications to authenticated;
create policy occurrence_classification_read on public.occurrence_classifications for select to authenticated using(true);
create trigger occurrence_classification_immutable before update or delete on public.occurrence_classifications for each row execute function public.reject_competition_rewrite();

create function public.persist_occurrence_classification(p_market uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare m public.markets%rowtype;r jsonb;result public.occurrence_classifications%rowtype;
begin
 perform pg_advisory_xact_lock(941001);perform pg_advisory_xact_lock(941002);perform pg_advisory_xact_lock(941003);
 select * into m from public.markets where id=p_market;
 if m.occurrence_id is null or m.definition_id is null or m.mode is null then return null;end if;
 r:=public.get_market_classification(p_market);
 if r->>'status' not in ('ready_for_validation','validated') then return null;end if;
 insert into public.occurrence_classifications(occurrence_id,mode,current_capture_id,previous_capture_id,source_market_id,rows)
  values(m.occurrence_id,m.mode,(r#>>'{current_capture,id}')::uuid,(r#>>'{previous_capture,id}')::uuid,m.id,r->'rows')
  on conflict(occurrence_id,mode) do nothing;
 select * into result from public.occurrence_classifications where occurrence_id=m.occurrence_id and mode=m.mode;
 if result.rows is distinct from r->'rows' or result.current_capture_id is distinct from (r#>>'{current_capture,id}')::uuid
  or result.previous_capture_id is distinct from (r#>>'{previous_capture,id}')::uuid then
  raise exception using errcode='BC001',message='A ocorrência já tem estatísticas finais imutáveis';end if;
 return result.id;
end $$;

alter function public.finalize_final_round(uuid,text) rename to finalize_final_round_sources;
revoke all on function public.finalize_final_round_sources(uuid,text) from public,anon,authenticated;
create function public.finalize_final_round(p_round uuid,p_note text) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid;m record;
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 result:=public.finalize_final_round_sources(p_round,p_note);
 for m in select x.id from public.markets x join public.final_round_occurrences a on a.occurrence_id=x.occurrence_id
  where a.round_id=p_round and x.mode is not null order by x.id loop
  perform public.persist_occurrence_classification(m.id);
 end loop;
 return result;
end $$;
alter function public.validate_market_classification(uuid,text) rename to validate_market_classification_sources;
revoke all on function public.validate_market_classification_sources(uuid,text) from public,anon,authenticated;
create function public.validate_market_classification(p_market uuid,p_note text) returns uuid
language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception using errcode='42501',message='Sem permissão';end if;
 perform public.persist_occurrence_classification(p_market);
 return public.validate_market_classification_sources(p_market,p_note);
end $$;

create function public.get_occurrence_results(p_occurrence uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null then raise exception using errcode='42501',message='Não autenticado';end if;
 if not exists(select 1 from public.bet_occurrences where id=p_occurrence) then raise exception using errcode='BM003',message='Ocorrência inválida';end if;
 select jsonb_agg(jsonb_build_object('mode',md,'unit',case when md='snapshot_value' then '%' else 'pp' end,
  'status',case when c.id is null then 'waiting_final_results' else 'frozen' end,'rows',coalesce(c.rows,'[]'::jsonb),
  'id',c.id,'recorded_at',c.recorded_at,'current_capture_id',c.current_capture_id,'previous_capture_id',c.previous_capture_id) order by ord)
 into result from unnest(array['snapshot_value','snapshot_delta_previous']) with ordinality as modes(md,ord)
 left join public.occurrence_classifications c on c.occurrence_id=p_occurrence and c.mode=md;
 return result;
end $$;

-- Creation events and executions, paginated by (timestamp, event ID), including
-- cancelled/filled offers. Offer state/remaining quantity are explicitly current.
-- Counterparty identities, private positions and wallet balances are never exposed.
create function public.get_market_activity(p_market uuid,p_before timestamptz default null,p_before_id text default null,p_limit integer default 50) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare events jsonb;more boolean;m public.markets%rowtype;resolution jsonb;
begin
 if auth.uid() is null then raise exception using errcode='42501',message='Não autenticado';end if;
 select * into m from public.markets where id=p_market;
 if not found or m.mode is null or m.occurrence_id is null then raise exception using errcode='BM003',message='Mercado recorrente inválido';end if;
 if p_limit is null or p_limit not between 1 and 100 or ((p_before is null)<>(p_before_id is null)) then
  raise exception using errcode='BM002',message='Paginação inválida';end if;
 with history as (
  select 'offer:'||f.id as id,f.created_at as at,'offer' as kind,o.label,f.side,f.odds,
   null::integer as stake,null::numeric as liability,f.state,f.stake_remaining
  from public.offers f join public.outcomes o on o.id=f.outcome_id where f.market_id=p_market
  union all
  select 'trade:'||t.id,t.created_at,'trade',o.label,null,t.odds,t.stake,t.liability,null,null
  from public.trades t join public.outcomes o on o.id=t.outcome_id where t.market_id=p_market
 ), page as (
  select *,row_number() over(order by at desc,id collate "C" desc) as rn from history
  where p_before is null or at<p_before or (at=p_before and id collate "C"<p_before_id collate "C")
  order by at desc,id collate "C" desc limit p_limit+1
 ) select coalesce(jsonb_agg(to_jsonb(page)-'rn' order by at desc,id collate "C" desc) filter(where rn<=p_limit),'[]'::jsonb),
  coalesce(bool_or(rn>p_limit),false) into events,more from page;
 select jsonb_build_object('status','settled','winner',o.label,'resolved_at',r.resolved_at,'winner_outcome_id',r.winner_outcome_id)
  into resolution from public.market_resolutions r join public.outcomes o on o.id=r.winner_outcome_id where r.market_id=p_market;
 return jsonb_build_object('events',events,'has_more',more,'next_cursor',case when more then jsonb_build_object('at',events->-1->>'at','id',events->-1->>'id') end,
  'market_state',m.state,'closes_at',m.closes_at,'resolution',resolution);
end $$;
revoke all on function public.persist_occurrence_classification(uuid),public.finalize_final_round(uuid,text),public.validate_market_classification(uuid,text),public.get_occurrence_results(uuid),public.get_market_activity(uuid,timestamptz,text,integer) from public,anon,authenticated;
grant execute on function public.finalize_final_round(uuid,text),public.validate_market_classification(uuid,text),public.get_occurrence_results(uuid),public.get_market_activity(uuid,timestamptz,text,integer) to authenticated;
commit;
