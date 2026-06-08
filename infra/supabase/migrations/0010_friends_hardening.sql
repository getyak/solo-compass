-- Solo Compass — Friend operations backend hardening (US-025 / FRD-025).
--
-- Anti-abuse + data hygiene on friend requests, enforced server-side so a
-- malicious client cannot bypass it (the iOS client INSERTs friend_requests
-- directly through RLS — see 0008_friends.sql — so every guard below lives in
-- the DB where the client cannot reach around it).
--
-- Four invariants:
--   1. Per-user daily friend-request cap (DAILY_FRIEND_REQUEST_CAP = 50).
--      Over-limit INSERTs are rejected via `raise sqlstate 'PGRST'` with
--      detail.status = 429 so PostgREST surfaces HTTP 429 directly to the
--      client (which INSERTs through PostgREST/RLS — there is no Edge Function
--      in front of friend_requests). message.code = 'SC429' is a stable marker
--      the client and tests key off.
--   2. `discover`-source requests are re-gated by the requester's reporter_weight
--      server-side (>= REPORTER_WEIGHT_THRESHOLD = 0.3). The client claims a
--      source; we never trust it — we re-check the gate here.
--   3. Pending requests past expires_at are swept to `expired` by a scheduled
--      job calling sc_cleanup_stale_friend_requests() (the cleanupStaleRequests
--      pattern).
--   4. Blocked pairs cannot send requests or see each other: an INSERT where the
--      requester/recipient are a blocked pair (in either direction, via
--      companion_blocks) is silently dropped (no row, no error) — matching
--      FR-7 "发请求时静默成功不泄露拉黑状态".
--
-- Idempotent: re-running is safe (guards use CREATE OR REPLACE / IF NOT EXISTS).

begin;

-- ──────────────────────────────────────────────────────────────────────────────
-- Tunables (kept as SQL constants inside the function bodies; documented here).
--   DAILY_FRIEND_REQUEST_CAP   = 50
--   REPORTER_WEIGHT_THRESHOLD  = 0.3   (mirrors companion-discover Edge Function)
-- ──────────────────────────────────────────────────────────────────────────────

-- BEFORE INSERT guard on friend_requests. SECURITY DEFINER so it can read
-- companion_blocks / companion_profiles regardless of the caller's RLS scope.
create or replace function sc_guard_friend_request()
  returns trigger
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  daily_cap        constant int     := 50;
  weight_threshold constant numeric := 0.3;
  sent_today       int;
  is_blocked       boolean;
  requester_weight numeric;
begin
  -- (4) Block dependency: if requester/recipient are a blocked pair in EITHER
  --     direction, drop the insert silently (return NULL → row not written).
  --     No error is raised so the sender cannot detect the block (FR-7).
  select exists (
    select 1 from public.companion_blocks
    where (blocker_id = NEW.requester_id and blocked_id = NEW.recipient_id)
       or (blocker_id = NEW.recipient_id and blocked_id = NEW.requester_id)
  ) into is_blocked;
  if is_blocked then
    return null;
  end if;

  -- (2) discover-source reporter_weight gate (server-side, do not trust client).
  --     A requester whose companion_profile reporter_weight is below the
  --     threshold may not originate `discover` requests. Absence of a profile
  --     means default trust (1.0), which passes.
  if NEW.source = 'discover' then
    select reporter_weight into requester_weight
    from public.companion_profiles
    where user_id = NEW.requester_id;
    if requester_weight is not null and requester_weight < weight_threshold then
      -- PostgREST → HTTP 403. message.code = 'SC403' is the stable client marker.
      raise sqlstate 'PGRST'
        using message = json_build_object(
                'code',    'SC403',
                'message', 'discover requests blocked',
                'details', 'reporter_weight below threshold')::text,
              detail = json_build_object('status', 403)::text;
    end if;
  end if;

  -- (1) Per-user daily cap. Count this requester's friend_requests created in
  --     the trailing 24h. At/over the cap, reject so PostgREST returns HTTP 429.
  select count(*) into sent_today
  from public.friend_requests
  where requester_id = NEW.requester_id
    and created_at >= now() - interval '24 hours';
  if sent_today >= daily_cap then
    -- PostgREST → HTTP 429 (detail.status). retry-after hints the client to
    -- back off until the trailing-24h window clears. message.code = 'SC429'.
    raise sqlstate 'PGRST'
      using message = json_build_object(
              'code',    'SC429',
              'message', 'daily friend-request cap reached',
              'details', format('%s/%s in the last 24h', sent_today, daily_cap))::text,
            detail = json_build_object(
              'status',  429,
              'headers', json_build_object('Retry-After', '3600'))::text;
  end if;

  return NEW;
end;
$$;

drop trigger if exists friend_requests_guard on public.friend_requests;

create trigger friend_requests_guard
  before insert on public.friend_requests
  for each row execute function sc_guard_friend_request();

-- ──────────────────────────────────────────────────────────────────────────────
-- (3) Expiry sweep — cleanupStaleRequests pattern.
--
-- Pending requests whose expires_at is in the past become `expired`. Returns the
-- number of rows swept (useful for scheduled-job logging). SECURITY DEFINER so a
-- scheduled invocation under a restricted role can still update across users.
--
-- Schedule via pg_cron (hourly), e.g.:
--   select cron.schedule('friend-requests-expire', '0 * * * *',
--                        'select sc_cleanup_stale_friend_requests()');
-- ──────────────────────────────────────────────────────────────────────────────

create or replace function sc_cleanup_stale_friend_requests()
  returns int
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  swept int;
begin
  with expired as (
    update public.friend_requests
    set status = 'expired'
    where status = 'pending'
      and expires_at < now()
    returning 1
  )
  select count(*) into swept from expired;
  return swept;
end;
$$;

-- If pg_cron is available, register the hourly sweep idempotently. Skipped
-- silently where the extension is absent (e.g. bare local Postgres).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'friend-requests-expire',
      '0 * * * *',
      'select public.sc_cleanup_stale_friend_requests()'
    );
  end if;
exception
  when undefined_function or undefined_table or insufficient_privilege then
    -- pg_cron present but not usable here; the function can still be called
    -- by an external scheduler. Nothing to do.
    null;
end$$;

commit;
