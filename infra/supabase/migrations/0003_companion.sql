-- Solo Compass — Companion Mode Phase 1 (US-007)
--
-- Adds the `itineraries` table for device-to-cloud sync.
-- Only applied when FF_COMPANION is on. The iOS client enqueues rows
-- via the SyncService outbox and reads them back with last-write-wins
-- merge (updated_at desc, device_id lex for ties).
--
-- Phase 1 scope:
--   - Owner-scoped itineraries (no sharing/discovery between users yet)
--   - experience_ids stored as JSONB array (mirrors the iOS blob)
--   - device_id for deterministic LWW tie-breaking
--   - is_deleted tombstone flag (soft-delete, hard-purge is post-launch)

begin;

create table if not exists public.itineraries (
  id                  text          primary key,            -- ItineraryId.rawValue (UUID string)
  user_id             uuid          not null references auth.users(id) on delete cascade,
  owner_id            text          not null,               -- "local" until linked to auth.uid()
  title               text          not null,
  city_code           text          not null,
  start_date          text          not null,               -- ISO 8601 date (YYYY-MM-DD)
  end_date            text          not null,               -- ISO 8601 date (YYYY-MM-DD)
  experience_ids      jsonb         not null default '[]'::jsonb,
  note                text,
  open_to_companions  boolean       not null default false,
  is_deleted          boolean       not null default false,
  device_id           text,
  created_at          timestamptz   not null default now(),
  updated_at          timestamptz   not null default now()
);

create index if not exists itineraries_user_idx      on public.itineraries(user_id);
create index if not exists itineraries_updated_idx   on public.itineraries(user_id, updated_at desc);

-- Automatic updated_at stamp (reuses the trigger function from 0001_init.sql).
-- sc_touch_updated_at() is defined in 0001_init.sql; it sets NEW.updated_at = now().
create trigger itineraries_touch_updated_at
  before update on public.itineraries
  for each row execute function sc_touch_updated_at();

-- RLS: each user sees and mutates only their own itineraries.
alter table public.itineraries enable row level security;

create policy "itineraries self-select" on public.itineraries
  for select using (auth.uid() = user_id);

create policy "itineraries self-insert" on public.itineraries
  for insert with check (auth.uid() = user_id);

create policy "itineraries self-update" on public.itineraries
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "itineraries self-delete" on public.itineraries
  for delete using (auth.uid() = user_id);

commit;
