-- Solo Compass — Platform roles & moderation (admin / moderator)
--
-- Adds a platform-level access role orthogonal to the P2P friend graph, plus
-- the server-side plumbing a moderation team needs:
--
--   • companion_profiles.role        — user | moderator | admin (default user)
--   • companion_profiles.is_banned   — soft ban flag (default false)
--   • sc_is_moderator() / sc_is_admin() helpers (SECURITY DEFINER)
--   • companion_reports moderator/admin select-all policy
--       (previously self-select only — nobody could read the queue)
--   • a guard trigger so clients CANNOT escalate their own role or ban flag
--       (only service_role / the moderate-action Edge Function may write them)
--   • banned users are blocked from inserting friend requests & chat messages
--   • admin seed: ADMIN_USER_IDS env (app.settings.admin_user_ids GUC) takes
--       precedence; falls back to the hardcoded default list below.
--
-- Mirrors `UserRole` in packages/core/src/companion.ts.

begin;

-- ──────────────────────────────────────────────────────────────────────────────
-- 1. Columns on companion_profiles
-- ──────────────────────────────────────────────────────────────────────────────

alter table public.companion_profiles
  add column if not exists role text not null default 'user'
    check (role in ('user','moderator','admin'));

alter table public.companion_profiles
  add column if not exists is_banned boolean not null default false;

create index if not exists companion_profiles_role_idx
  on public.companion_profiles(role)
  where role <> 'user';

-- ──────────────────────────────────────────────────────────────────────────────
-- 2. Role helpers (SECURITY DEFINER so RLS policies can call them without
--    recursing into companion_profiles' own row-level policies)
-- ──────────────────────────────────────────────────────────────────────────────

create or replace function public.sc_is_moderator(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.companion_profiles
    where user_id = uid
      and role in ('moderator','admin')
      and is_banned = false
  );
$$;

create or replace function public.sc_is_admin(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.companion_profiles
    where user_id = uid
      and role = 'admin'
      and is_banned = false
  );
$$;

-- ──────────────────────────────────────────────────────────────────────────────
-- 3. Guard: clients may NOT set their own role / is_banned.
--
--    companion_profiles already has a "self-update" policy (a user owns their
--    row), which would otherwise let anyone PATCH role='admin'. This trigger
--    rejects any change to role/is_banned unless the session is service_role
--    (the moderate-action Edge Function runs with the service key).
-- ──────────────────────────────────────────────────────────────────────────────

create or replace function public.sc_guard_profile_privilege()
returns trigger
language plpgsql
as $$
begin
  if (new.role is distinct from old.role)
     or (new.is_banned is distinct from old.is_banned) then
    if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role'
       and coalesce(auth.role(), '') <> 'service_role' then
      raise exception 'role/ban changes are service-role only'
        using errcode = '42501';  -- insufficient_privilege
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists companion_profiles_guard_privilege on public.companion_profiles;
create trigger companion_profiles_guard_privilege
  before update on public.companion_profiles
  for each row execute function public.sc_guard_profile_privilege();

-- ──────────────────────────────────────────────────────────────────────────────
-- 4. companion_reports: let moderators/admins read the full queue.
--    (Existing "self-select" stays so a reporter still sees their own report.)
-- ──────────────────────────────────────────────────────────────────────────────

drop policy if exists "companion_reports moderator-select" on public.companion_reports;
create policy "companion_reports moderator-select" on public.companion_reports
  for select using (public.sc_is_moderator(auth.uid()));

-- Resolution bookkeeping so the queue can hide handled reports.
alter table public.companion_reports
  add column if not exists resolved_at timestamptz;
alter table public.companion_reports
  add column if not exists resolved_by uuid references auth.users(id) on delete set null;

drop policy if exists "companion_reports moderator-update" on public.companion_reports;
create policy "companion_reports moderator-update" on public.companion_reports
  for update
  using (public.sc_is_moderator(auth.uid()))
  with check (public.sc_is_moderator(auth.uid()));

-- ──────────────────────────────────────────────────────────────────────────────
-- 5. Banned users can't act: block friend-request inserts & chat-message sends.
--    Layered on top of existing policies (RESTRICTIVE → must also pass).
-- ──────────────────────────────────────────────────────────────────────────────

create or replace function public.sc_is_banned(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.companion_profiles
    where user_id = uid and is_banned = true
  );
$$;

drop policy if exists "friend_requests not-banned" on public.friend_requests;
create policy "friend_requests not-banned" on public.friend_requests
  as restrictive
  for insert
  with check (not public.sc_is_banned(auth.uid()));

drop policy if exists "chat_messages not-banned" on public.chat_messages;
create policy "chat_messages not-banned" on public.chat_messages
  as restrictive
  for insert
  with check (not public.sc_is_banned(auth.uid()));

-- ──────────────────────────────────────────────────────────────────────────────
-- 6. Admin seed.
--
--    Precedence: the `app.settings.admin_user_ids` GUC (set from the
--    ADMIN_USER_IDS env at deploy time, comma-separated uuids) wins. When that
--    GUC is empty/unset, fall back to the hardcoded default list below.
--
--    A profile row may not exist yet for a seeded id (e.g. the account exists
--    in auth.users but never opened the companion sheet), so we upsert a
--    minimal profile and stamp role='admin'.
-- ──────────────────────────────────────────────────────────────────────────────

do $$
declare
  v_env   text := coalesce(current_setting('app.settings.admin_user_ids', true), '');
  -- Hardcoded fallback admins. Replace with real auth.users uuids before
  -- production; left empty here so a fresh DB doesn't grant admin to a
  -- placeholder. Format: array['00000000-0000-0000-0000-000000000000']::uuid[]
  v_default uuid[] := array[]::uuid[];
  v_ids   uuid[];
  v_id    uuid;
begin
  if length(trim(v_env)) > 0 then
    -- parse comma-separated uuids from the env-derived GUC
    select array_agg(trim(x)::uuid)
      into v_ids
      from unnest(string_to_array(v_env, ',')) as x
      where length(trim(x)) > 0;
  else
    v_ids := v_default;
  end if;

  if v_ids is null or array_length(v_ids, 1) is null then
    raise notice 'sc admin seed: no admin ids configured (set ADMIN_USER_IDS)';
    return;
  end if;

  foreach v_id in array v_ids loop
    -- only seed ids that exist in auth.users
    if exists (select 1 from auth.users where id = v_id) then
      insert into public.companion_profiles (id, user_id, role)
      values ('cprof_admin_' || replace(v_id::text, '-', ''), v_id, 'admin')
      on conflict (user_id)
      do update set role = 'admin', updated_at = now();
      raise notice 'sc admin seed: granted admin to %', v_id;
    else
      raise notice 'sc admin seed: skipped % (no auth.users row)', v_id;
    end if;
  end loop;
end;
$$;

commit;
