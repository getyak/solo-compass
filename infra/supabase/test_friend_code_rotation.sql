-- Friend-code rotation + redeem-hardening tests (US-026 / FRD-026).
--
-- Exercises the rotation invariants from 0011_friend_code_rotation.sql against a
-- real Postgres instance with migrations 0001–0011 applied. Pure SQL — no
-- Supabase Auth/Realtime needed. We drive sc_rotate_friend_code() by setting the
-- JWT-sub GUC that auth.uid() reads, exactly as PostgREST does per request.
--
-- Run (against a DB with the migrations applied):
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f test_friend_code_rotation.sql
--
-- ASSERT-driven; first failure aborts. Everything is inside a transaction that
-- is ROLLED BACK at the end — no rows left behind. Synthetic UUIDs only.

\set ON_ERROR_STOP on

begin;

do $$
declare
  u_alice constant uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  u_bob   constant uuid := 'bbbbbbbb-0000-0000-0000-000000000002';
  code1   text;
  code2   text;
  code3   text;
  live_n  int;
  ok      boolean;
begin
  insert into auth.users (id, email)
  values (u_alice, 'alice@test.local'),
         (u_bob,   'bob@test.local')
  on conflict (id) do nothing;

  -- auth.uid() reads request.jwt.claim.sub. Set it to Alice for the session.
  perform set_config('request.jwt.claim.sub', u_alice::text, true);

  -- ── (1) Format: generator emits SOLO-XXXX-XXXX over the safe alphabet ─────
  code1 := sc_gen_friend_code();
  assert code1 ~ '^SOLO-[A-Z0-9]{4}-[A-Z0-9]{4}$',
    format('generated code must match SOLO-XXXX-XXXX, got %s', code1);
  -- No ambiguous chars leaked into the body (I O 0 1 L excluded by design).
  assert substr(code1, 6) !~ '[IO01L]',
    format('code body must avoid ambiguous chars I/O/0/1/L, got %s', code1);

  -- ── (2) First rotate issues a live code for a user with none ──────────────
  code1 := sc_rotate_friend_code();
  select count(*) into live_n
  from public.friend_codes where user_id = u_alice and revoked_at is null;
  assert live_n = 1, format('after first rotate exactly one live code, got %s', live_n);

  -- ── (3) Rotation invalidates old + activates new immediately ──────────────
  code2 := sc_rotate_friend_code();
  assert code2 <> code1, 'rotate must produce a different code';

  -- old code now revoked (dead immediately) ...
  select (revoked_at is not null) into ok
  from public.friend_codes where code = code1;
  assert ok, 'rotated-away code must be revoked immediately';

  -- ... and the new one is the sole live code.
  select count(*) into live_n
  from public.friend_codes where user_id = u_alice and revoked_at is null;
  assert live_n = 1, format('after rotate still exactly one live code, got %s', live_n);
  select (revoked_at is null) into ok
  from public.friend_codes where code = code2;
  assert ok, 'new code must be live after rotate';

  -- ── (4) Redeem semantics: a revoked code does not resolve ─────────────────
  -- The redeem-friend-code Edge Function resolves a code only when
  -- revoked_at IS NULL (see index.ts). Assert that predicate directly: the
  -- old code yields no live row, the new one does.
  select count(*) into live_n
  from public.friend_codes where code = code1 and revoked_at is null;
  assert live_n = 0, 'a revoked code must not match the redeem predicate (revoked_at IS NULL)';

  select count(*) into live_n
  from public.friend_codes where code = code2 and revoked_at is null;
  assert live_n = 1, 'the current code must match the redeem predicate';

  -- ── (5) Per-user isolation + one-live-code invariant across users ─────────
  perform set_config('request.jwt.claim.sub', u_bob::text, true);
  code3 := sc_rotate_friend_code();
  assert code3 <> code2, 'distinct users must not collide on the live code';

  -- Bob's rotate must not touch Alice's live code.
  select count(*) into live_n
  from public.friend_codes where user_id = u_alice and revoked_at is null;
  assert live_n = 1, 'rotating Bob must not affect Alice''s live code';

  -- ── (6) Hard backstop: the partial unique index forbids 2 live codes ──────
  -- Directly attempting to insert a second live row for Alice must fail, proving
  -- the one-live-code invariant the rotation RPC relies on is DB-enforced.
  ok := false;
  begin
    insert into public.friend_codes (code, user_id) values ('SOLO-TEST-DUPE', u_alice);
  exception
    when unique_violation then ok := true;
  end;
  assert ok, 'a second live code for a user must violate friend_codes_user_live_unique';

  raise notice 'ALL friend-code rotation checks passed (format, atomic rotate, revoke-on-rotate, redeem predicate, isolation, one-live-index)';
end$$;

rollback;
