-- Solo Compass — Friends & Social Graph (FRD-006, FRD-012, FRD-022)
--
-- The persistent relationship layer on top of the ephemeral companion system.
-- A `friendship` promotes a one-off companion tie into a long-term connection
-- that unlocks direct companion invites, persistent DMs, and a full profile.
--
-- Mirrors `packages/core/src/friend.ts`. Gated by FF_COMPANION on the iOS
-- client (friends reuse the companion feature flag).
--
-- This migration also:
--   • relaxes conversations.request_id to NULL (friendDirect DMs have no
--     companion request backing them) — FRD-012.
--   • adds device_push_tokens for APNs delivery — FRD-022.

begin;

-- ──────────────────────────────────────────────────────────────────────────────
-- FRD-006: friend_requests
-- ──────────────────────────────────────────────────────────────────────────────

create table if not exists public.friend_requests (
  id            text        primary key,       -- FriendRequestId.rawValue (freq_*)
  requester_id  uuid        not null references auth.users(id) on delete cascade,
  recipient_id  uuid        not null references auth.users(id) on delete cascade,
  -- pending | accepted | declined | withdrawn | expired
  status        text        not null default 'pending'
                              check (status in ('pending','accepted','declined','withdrawn','expired')),
  -- companion_chat | route_group | friend_code | discover
  source        text        not null
                              check (source in ('companion_chat','route_group','friend_code','discover')),
  note          text        check (note is null or char_length(note) <= 120),
  expires_at    timestamptz not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  -- a user can't friend themselves
  constraint friend_requests_distinct check (requester_id <> recipient_id)
);

create index if not exists friend_requests_recipient_idx on public.friend_requests(recipient_id, status);
create index if not exists friend_requests_requester_idx on public.friend_requests(requester_id, status);
-- at most one live (pending) request per direction
create unique index if not exists friend_requests_pending_unique
  on public.friend_requests(requester_id, recipient_id)
  where status = 'pending';

create trigger friend_requests_touch_updated_at
  before update on public.friend_requests
  for each row execute function sc_touch_updated_at();

alter table public.friend_requests enable row level security;

create policy "friend_requests participant-select" on public.friend_requests
  for select using (auth.uid() = requester_id or auth.uid() = recipient_id);

create policy "friend_requests requester-insert" on public.friend_requests
  for insert with check (auth.uid() = requester_id);

create policy "friend_requests participant-update" on public.friend_requests
  for update
  using (auth.uid() = requester_id or auth.uid() = recipient_id)
  with check (auth.uid() = requester_id or auth.uid() = recipient_id);

-- ──────────────────────────────────────────────────────────────────────────────
-- FRD-006: friendships (ordered pair, one row per pair)
-- ──────────────────────────────────────────────────────────────────────────────

create table if not exists public.friendships (
  id              text        primary key,     -- FriendshipId.rawValue (fnd_*)
  user_low_id     uuid        not null references auth.users(id) on delete cascade,
  user_high_id    uuid        not null references auth.users(id) on delete cascade,
  initiated_by    uuid        not null references auth.users(id) on delete cascade,
  conversation_id text        references public.conversations(id) on delete set null,
  accepted_at     timestamptz not null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  -- canonical ordering: low < high, so A↔B is a single row
  constraint friendships_ordered check (user_low_id < user_high_id),
  -- exactly one row per pair
  constraint friendships_pair_unique unique (user_low_id, user_high_id)
);

create index if not exists friendships_low_idx  on public.friendships(user_low_id);
create index if not exists friendships_high_idx on public.friendships(user_high_id);

create trigger friendships_touch_updated_at
  before update on public.friendships
  for each row execute function sc_touch_updated_at();

alter table public.friendships enable row level security;

create policy "friendships participant-select" on public.friendships
  for select using (auth.uid() = user_low_id or auth.uid() = user_high_id);

create policy "friendships participant-insert" on public.friendships
  for insert with check (auth.uid() = user_low_id or auth.uid() = user_high_id);

create policy "friendships participant-update" on public.friendships
  for update
  using (auth.uid() = user_low_id or auth.uid() = user_high_id)
  with check (auth.uid() = user_low_id or auth.uid() = user_high_id);

create policy "friendships participant-delete" on public.friendships
  for delete using (auth.uid() = user_low_id or auth.uid() = user_high_id);

-- ──────────────────────────────────────────────────────────────────────────────
-- FRD-014/FRD-026: friend_codes (rotatable, single-direction redeem)
--
-- A code maps to a user. Anyone signed-in can REDEEM a code (resolve it to a
-- userId) via the redeem-friend-code Edge Function using service role — we do
-- NOT expose this table for arbitrary SELECT (prevents enumeration). Users can
-- only read/rotate their own codes.
-- ──────────────────────────────────────────────────────────────────────────────

create table if not exists public.friend_codes (
  code        text        primary key,         -- "SOLO-XXXX-XXXX"
  user_id     uuid        not null references auth.users(id) on delete cascade,
  revoked_at  timestamptz,
  created_at  timestamptz not null default now()
);

-- one live code per user
create unique index if not exists friend_codes_user_live_unique
  on public.friend_codes(user_id)
  where revoked_at is null;

alter table public.friend_codes enable row level security;

-- Owner may read their own codes (to display the current one).
create policy "friend_codes self-select" on public.friend_codes
  for select using (auth.uid() = user_id);

create policy "friend_codes self-insert" on public.friend_codes
  for insert with check (auth.uid() = user_id);

-- Owner may revoke (set revoked_at) their own code.
create policy "friend_codes self-update" on public.friend_codes
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Note: redeeming someone else's code is handled by the redeem-friend-code
-- Edge Function with the service role key, bypassing RLS. No public SELECT
-- policy exists, so codes cannot be enumerated by clients.

-- ──────────────────────────────────────────────────────────────────────────────
-- FRD-022: device_push_tokens (APNs)
-- ──────────────────────────────────────────────────────────────────────────────

create table if not exists public.device_push_tokens (
  user_id    uuid        not null references auth.users(id) on delete cascade,
  device_id  text        not null,
  token      text        not null,
  platform   text        not null default 'ios' check (platform in ('ios')),
  updated_at timestamptz not null default now(),
  primary key (user_id, device_id)
);

create index if not exists device_push_tokens_user_idx on public.device_push_tokens(user_id);

create trigger device_push_tokens_touch_updated_at
  before update on public.device_push_tokens
  for each row execute function sc_touch_updated_at();

alter table public.device_push_tokens enable row level security;

create policy "device_push_tokens self-select" on public.device_push_tokens
  for select using (auth.uid() = user_id);

create policy "device_push_tokens self-insert" on public.device_push_tokens
  for insert with check (auth.uid() = user_id);

create policy "device_push_tokens self-update" on public.device_push_tokens
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "device_push_tokens self-delete" on public.device_push_tokens
  for delete using (auth.uid() = user_id);

-- ──────────────────────────────────────────────────────────────────────────────
-- FRD-012: conversations — relax request_id to NULL for friendDirect DMs
--
-- friendDirect conversations are backed by a Friendship, not a companion
-- request. The original column was `not null unique references companion_requests`.
-- We drop NOT NULL; the UNIQUE remains valid (NULLs are distinct in a unique
-- index, so multiple friendDirect rows with NULL request_id coexist).
-- ──────────────────────────────────────────────────────────────────────────────

alter table public.conversations alter column request_id drop not null;

commit;
