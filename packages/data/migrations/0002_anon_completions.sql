-- 0002_anon_completions.sql
-- Phase 2 web check-in flow uses opaque cookie IDs, not Supabase auth.
-- The web API routes call this with the service-role client, which bypasses
-- RLS — but the existing policies are auth.uid()-based and would block any
-- direct anon-key writes. Add an index on the synthetic handle to make
-- per-cookie upserts fast, and document the boundary with a comment.

-- ─── Anonymous user lookups by handle ──────────────────────────────────────────
-- handle is already UNIQUE (see 0001), but explicit index makes lookups
-- by `handle = 'anon_xxx'` an obvious O(1) plan.
create index if not exists users_handle_idx on users (handle);

-- ─── Completion freshness index ────────────────────────────────────────────────
-- Used by /api confidence-lift queries: "how many completions in the last 30d
-- for this experience?"
create index if not exists completions_experience_completed_at_idx
  on completions (experience_id, completed_at desc);

-- ─── Documentation ─────────────────────────────────────────────────────────────
comment on table completions is
  'One row per (user, experience). Anonymous web users carry an opaque cookie id — the user row is created on first checkin with handle = ''anon_<short>''. Completions inserts from the web are performed by the service-role client; RLS therefore does not block them. Telegram/auth flows continue to use auth.uid()-bound policies.';
