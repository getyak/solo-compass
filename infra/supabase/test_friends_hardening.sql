-- Friend-operations hardening tests (US-025 / FRD-025).
--
-- Exercises the server-side guards from 0010_friends_hardening.sql against a
-- real Postgres instance that has migrations 0001–0010 applied. Pure SQL so it
-- runs without the Supabase Realtime/Auth stack — it drives the trigger and
-- sweep function directly, which is exactly the "do not trust the client" layer
-- US-025 hardens.
--
-- Run (against a DB with the migrations applied):
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f test_friends_hardening.sql
--
-- All checks use plpgsql ASSERT; the first failure aborts with a clear message.
-- Everything happens inside a transaction that is ROLLED BACK at the end, so the
-- test leaves no rows behind. Synthetic UUIDs only — no production data.

\set ON_ERROR_STOP on

begin;

-- ── Fixtures: synthetic users + companion profiles ──────────────────────────
-- We insert directly into auth.users (the FK target). reporter_weight defaults
-- to 1.0; we override one user below to test the discover gate.

do $$
declare
  u_requester constant uuid := '11111111-1111-1111-1111-111111111111';
  u_recipient constant uuid := '22222222-2222-2222-2222-222222222222';
  u_blocked   constant uuid := '33333333-3333-3333-3333-333333333333';
  u_lowtrust  constant uuid := '44444444-4444-4444-4444-444444444444';
  i           int;
  cnt         int;
  ok          boolean;
  swept       int;
  msg         text;
begin
  insert into auth.users (id, email)
  values (u_requester, 'req@test.local'),
         (u_recipient, 'rcp@test.local'),
         (u_blocked,   'blk@test.local'),
         (u_lowtrust,  'low@test.local')
  on conflict (id) do nothing;

  insert into public.companion_profiles (user_id, reporter_weight)
  values (u_requester, 1.0),
         (u_lowtrust,  0.2)   -- below the 0.3 discover gate
  on conflict (user_id) do nothing;

  -- ── (1) Daily cap boundary: 50 succeed, the 51st raises SC429 ─────────────
  -- friend_requests has a partial unique index on (requester_id, recipient_id)
  -- WHERE pending, so each request must target a distinct recipient.
  for i in 1..49 loop
    insert into auth.users (id, email)
    values (('5'||lpad(i::text, 31, '0'))::uuid, 'r'||i||'@test.local')
    on conflict (id) do nothing;
  end loop;

  insert into public.friend_requests (id, requester_id, recipient_id, status, source, expires_at)
  values ('freq_cap_0', u_requester, u_recipient, 'pending', 'companion_chat', now() + interval '14 days');
  for i in 1..49 loop
    insert into public.friend_requests (id, requester_id, recipient_id, status, source, expires_at)
    values ('freq_cap_'||i, u_requester, ('5'||lpad(i::text, 31, '0'))::uuid,
            'pending', 'companion_chat', now() + interval '14 days');
  end loop;

  select count(*) into cnt from public.friend_requests where requester_id = u_requester;
  assert cnt = 50, format('expected 50 requests under the cap, got %s', cnt);

  -- The 51st must be rejected. The guard raises sqlstate 'PGRST' (PostgREST
  -- HTTP-status convention) with message.code = 'SC429'.
  ok := false;
  begin
    insert into auth.users (id, email)
    values ('60000000-0000-0000-0000-000000000051', 'r51@test.local')
    on conflict (id) do nothing;
    insert into public.friend_requests (id, requester_id, recipient_id, status, source, expires_at)
    values ('freq_cap_51', u_requester, '60000000-0000-0000-0000-000000000051',
            'pending', 'companion_chat', now() + interval '14 days');
  exception
    when sqlstate 'PGRST' then
      get stacked diagnostics msg = message_text;
      ok := (msg like '%SC429%');
  end;
  assert ok, '51st request should be rejected with PGRST/SC429 (daily cap)';

  select count(*) into cnt from public.friend_requests where requester_id = u_requester;
  assert cnt = 50, format('over-cap insert must not persist; still expected 50, got %s', cnt);

  -- ── (4) Block dependency: blocked pair → insert silently dropped ──────────
  insert into public.companion_blocks (blocker_id, blocked_id)
  values (u_recipient, u_blocked)   -- recipient blocked u_blocked
  on conflict do nothing;

  -- u_blocked tries to friend u_recipient (blocked in the reverse direction).
  insert into public.friend_requests (id, requester_id, recipient_id, status, source, expires_at)
  values ('freq_blocked', u_blocked, u_recipient, 'pending', 'companion_chat', now() + interval '14 days');
  -- BEFORE trigger returns NULL → no row, no error.
  select count(*) into cnt from public.friend_requests where id = 'freq_blocked';
  assert cnt = 0, 'blocked-pair request must be silently dropped (0 rows)';

  -- ── (2) discover reporter_weight gate: low-trust requester is rejected ─────
  ok := false;
  begin
    insert into public.friend_requests (id, requester_id, recipient_id, status, source, expires_at)
    values ('freq_lowtrust', u_lowtrust, u_recipient, 'pending', 'discover', now() + interval '14 days');
  exception
    when sqlstate 'PGRST' then
      get stacked diagnostics msg = message_text;
      ok := (msg like '%SC403%');
  end;
  assert ok, 'discover request from reporter_weight < 0.3 should be rejected (PGRST/SC403)';

  -- A non-discover source from the same low-trust user is allowed (gate is
  -- discover-only). Distinct recipient to satisfy the pending-unique index.
  insert into public.friend_requests (id, requester_id, recipient_id, status, source, expires_at)
  values ('freq_lowtrust_ok', u_lowtrust, u_blocked, 'pending', 'friend_code', now() + interval '14 days');
  select count(*) into cnt from public.friend_requests where id = 'freq_lowtrust_ok';
  assert cnt = 1, 'non-discover request from low-trust user should be allowed';

  -- ── (3) Expiry boundary: only past-due pending rows flip to expired ───────
  update public.friend_requests set expires_at = now() - interval '1 hour'
  where id = 'freq_cap_0';
  update public.friend_requests set expires_at = now() + interval '1 hour'
  where id = 'freq_cap_1';

  select sc_cleanup_stale_friend_requests() into swept;
  assert swept >= 1, format('cleanup should sweep at least the past-due row, swept %s', swept);

  select (status = 'expired') into ok from public.friend_requests where id = 'freq_cap_0';
  assert ok, 'past-due pending request must become expired';

  select (status = 'pending') into ok from public.friend_requests where id = 'freq_cap_1';
  assert ok, 'future-dated pending request must stay pending';

  raise notice 'ALL friend-hardening checks passed (cap=50/429, block-drop, discover-gate, expiry sweep)';
end$$;

rollback;
