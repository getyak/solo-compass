-- Solo Compass — Friend-code rotation + redeem hardening (US-026 / FRD-026).
--
-- A leaked friend code must be invalidatable. Rotation = revoke the current
-- live code AND activate a fresh one in ONE atomic step, server-side, so the
-- two halves can never drift apart (no window with two live codes or none).
--
-- The iOS client cannot be trusted to do this in two round-trips (revoke,
-- then insert): a crash between them, or two devices rotating at once, would
-- leave the account in a bad state. We collapse it to a single SECURITY DEFINER
-- RPC the owner calls; the `friend_codes_user_live_unique` partial index
-- (0008) is the hard backstop that one-live-code-per-user always holds.
--
-- Invariants enforced here:
--   1. Rotation revokes the old code and activates the new one atomically.
--      After rotation the old code is dead immediately (revoked_at set) so a
--      leaked code stops resolving the instant the owner rotates.
--   2. Concurrent rotation is safe: the owner's live row is locked FOR UPDATE,
--      so two simultaneous rotations serialize — the second sees the first's
--      result and rotates from it, never producing two live codes. The unique
--      index is the final guard if a race slips through.
--   3. Codes are not reverse-lookupable: generation uses crypto-random bytes
--      (gen_random_bytes) over an unambiguous alphabet — not a counter or
--      timestamp — so a code reveals nothing about the user and cannot be
--      guessed from a known one. The table has no public SELECT (0008); the
--      only resolve path is the redeem-friend-code Edge Function (service role).
--
-- Idempotent: CREATE OR REPLACE / IF NOT EXISTS throughout.

begin;

-- pgcrypto provides gen_random_bytes() for the unguessable code body. Supabase
-- ships it; CREATE EXTENSION IF NOT EXISTS is a no-op when already present.
create extension if not exists pgcrypto;

-- ──────────────────────────────────────────────────────────────────────────────
-- Code generator — SOLO-XXXX-XXXX over a Crockford-style ambiguity-free
-- alphabet (no I/O/0/1/L) so codes are easy to read aloud yet unguessable.
--
-- Crypto-random, NOT sequential/time-based: a known code leaks no information
-- about any other, satisfying "code not reverse-lookupable". Mirrors the
-- CODE_PATTERN /^SOLO-[A-Z0-9]{4}-[A-Z0-9]{4}$/ the Edge Function validates.
-- ──────────────────────────────────────────────────────────────────────────────

create or replace function sc_gen_friend_code()
  returns text
  language plpgsql
  volatile
  set search_path = public
as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; -- 30 chars, no I O 0 1 L
  body     text := '';
  i        int;
  bytes    bytea;
begin
  bytes := gen_random_bytes(8);
  for i in 0..7 loop
    -- map each random byte into the alphabet; modulo bias over 30 is negligible
    -- for a friend code's threat model (codes are also short-lived/rotatable).
    body := body || substr(alphabet, (get_byte(bytes, i) % length(alphabet)) + 1, 1);
  end loop;
  return 'SOLO-' || substr(body, 1, 4) || '-' || substr(body, 5, 4);
end;
$$;

-- ──────────────────────────────────────────────────────────────────────────────
-- Atomic rotate — revoke the caller's live code (if any) and activate a fresh
-- one, returning the new code. Owner-scoped via auth.uid(); SECURITY DEFINER so
-- it can write through RLS but only ever for the calling user's own rows.
--
-- Also serves first-issue: a user with no code yet gets one (old-revoke is a
-- no-op). Each call yields a new live code and kills the previous one.
-- ──────────────────────────────────────────────────────────────────────────────

create or replace function sc_rotate_friend_code()
  returns text
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  uid      uuid := auth.uid();
  new_code text;
  attempt  int := 0;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Lock the caller's live code row so concurrent rotations serialize: the
  -- second waiter blocks here until the first commits, then revokes the
  -- already-new code and rotates from it. No two-live-codes window.
  perform 1
  from public.friend_codes
  where user_id = uid and revoked_at is null
  for update;

  -- Revoke whatever is currently live for this user (no-op on first issue).
  update public.friend_codes
  set revoked_at = now()
  where user_id = uid and revoked_at is null;

  -- Insert a fresh live code, retrying on the (astronomically rare) primary-key
  -- collision. The partial unique index guarantees we never end up with two
  -- live rows; a violation there means a concurrent inserter beat us — retry.
  loop
    attempt := attempt + 1;
    new_code := sc_gen_friend_code();
    begin
      insert into public.friend_codes (code, user_id)
      values (new_code, uid);
      return new_code;
    exception
      when unique_violation then
        if attempt >= 5 then
          raise exception 'could not allocate a unique friend code' using errcode = 'P0001';
        end if;
        -- code PK collision → retry; live-index collision → a concurrent rotate
        -- won the race, so re-revoke and loop to rotate from the new live code.
        update public.friend_codes
        set revoked_at = now()
        where user_id = uid and revoked_at is null;
    end;
  end loop;
end;
$$;

-- The RPC is the ONLY write path the client should use for rotation. Grant
-- execute to authenticated users; the function self-scopes to auth.uid().
grant execute on function sc_rotate_friend_code() to authenticated;

-- sc_gen_friend_code is an internal helper — no client should call it directly
-- (it would let a caller fish for code shapes). Keep it server-internal.
revoke all on function sc_gen_friend_code() from public;

commit;
