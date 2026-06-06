-- Solo Compass — User-created places (UGC, Phase 2)
--
-- Upload channel for experiences a user registers by hand (the `exp_user_*`
-- candidates created via long-press → form on the map). The local SwiftData
-- copy is the source of truth on-device; this table is the durable server
-- mirror that later feeds AI synthesis (soloScore/whyItMatters) and curator
-- review (candidate → active promotion).
--
-- Trust model: rows arrive as `status = 'candidate'`. The user supplies only
-- mechanical facts (name, category, coords, photos, description). The
-- trust-critical Solo Score is NOT stored here — it is computed by the
-- `synthesize-experiences` Edge Function after upload, never self-reported.
--
-- Columns mirror `SyncUserExperiencePayload` (iOS) 1:1 in snake_case so the
-- JSON body serializes directly. Server-owned columns (id/created_at/
-- updated_at) are excluded from the payload (see sql-swift-parity ignore list).
--
-- DEPLOYMENT: run via `supabase db push` or paste into the Supabase SQL editor.
-- Claude cannot deploy this — the user must.

create table if not exists public.user_experiences (
  id                    uuid          primary key default gen_random_uuid(),
  user_id               uuid          not null references auth.users(id) on delete cascade,
  experience_id         text          not null, -- exp_user_<uuid>, client-generated stable id
  title                 text          not null,
  one_liner             text          not null,
  category              text          not null,
  coordinates           jsonb         not null, -- [lon, lat] GeoJSON order
  city_code             text          not null,
  place_name_romanized  text,
  place_name_local      text,
  address_hint          text,
  description           text,                   -- maps to Experience.whyItMatters
  photo_urls            jsonb,                  -- JSON array of URL strings
  user_tags             jsonb,                  -- JSON array of strings
  status                text          not null default 'candidate'
                        check (status in ('candidate', 'active', 'stale', 'retired')),
  created_at            timestamptz   not null default now(),
  updated_at            timestamptz   not null default now(),
  -- One server row per (user, client-side experience id): re-uploads upsert.
  unique (user_id, experience_id)
);

create index if not exists user_experiences_user_idx on public.user_experiences(user_id);
create index if not exists user_experiences_exp_idx  on public.user_experiences(experience_id);
create index if not exists user_experiences_city_idx on public.user_experiences(city_code);

create trigger sc_user_experiences_touch
  before update on public.user_experiences
  for each row execute function public.sc_touch_updated_at();

-- RLS: a user can only read/write their own submitted places. Promotion to the
-- public pool happens by a curator/service role copying approved rows into the
-- shared `experiences` table — not by widening these policies.
alter table public.user_experiences enable row level security;

create policy "user_experiences self-select" on public.user_experiences
  for select using (auth.uid() = user_id);
create policy "user_experiences self-insert" on public.user_experiences
  for insert with check (auth.uid() = user_id);
create policy "user_experiences self-update" on public.user_experiences
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "user_experiences self-delete" on public.user_experiences
  for delete using (auth.uid() = user_id);
