"""Issue 8: overlapping weekly issuance, not just sequential retries."""
from db_sessions import race, sql, user, value

admin, spectator, competitor = [f'ec000000-0000-4000-8000-00000000000{i}' for i in range(1, 4)]
sql(f"""insert into auth.users(id) values('{admin}'),('{spectator}'),('{competitor}');
 insert into public.admins values('{admin}');
 insert into public.competitors(id) values('{admin}'),('{competitor}');
 insert into public.championships(name,starts_at,ends_at)
 values('Operations recovery fixture',now()-interval '1 day',now()+interval '1 day');""")
assert sql(user(spectator, 'select public.grant_weekly();'), check=False).returncode != 0
before = value(f"select total_issued from public.wallets where owner_id='{competitor}'")
# All requests must reach a database lock before release. One blocks on the
# wallet, the others on conflicting grant inserts, so the RPCs really overlap.
results = race([user(admin, 'select public.grant_weekly();')] * 4,
               hold_sql='select owner_id from public.wallets order by owner_id for update;')
assert all(r.returncode == 0 for r in results), results
assert value(f"select count(*) from public.weekly_grants where owner_id='{spectator}'") == '1'
assert value(f"select count(*) from public.ledger where owner_id='{spectator}' and reason='weekly_grant'") == '1'
assert value(f"select available||':'||reserved||':'||total_issued from public.wallets where owner_id='{spectator}'") == '2000.00:0.00:2000.00'
assert value(f"select total_issued from public.wallets where owner_id='{competitor}'") == before
assert value(f"select count(*) from public.weekly_grants where owner_id='{competitor}'") == '0'
ledger_before = value('select count(*) from public.ledger')
value(user(admin, 'select public.grant_weekly();'))
assert value('select count(*) from public.ledger') == ledger_before
assert value(user(admin, 'select count(*) from public.reconcile_wallets() where not balanced;')) == '0'
print('Operations PASS: four overlapping grants issue once, spectator-only, replay-safe and reconciled')
