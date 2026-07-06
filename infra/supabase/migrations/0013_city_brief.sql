-- Solo City OS v2 — city-brief data pipeline (落地包 · 在地).
--
-- Apply with `supabase db push` after `supabase link --project-ref <ref>`.
--
-- Four tables backing the server-side city-brief pipeline:
--   1. sc_cities      — city registry; brief_enabled gates the compile pipeline.
--   2. city_kits      — the "landing kit" (4 sections: net/money/visa/safety),
--                       re-verified periodically; health decays as rows age.
--   3. city_events    — the "live/在地" module; time-bound local events with a
--                       solo-friendliness score. Expired rows swept to 'expired'.
--   4. city_brief_runs — compile-run accounting: cooldown + cost bookkeeping.
--
-- RLS mirrors synthesized_experiences from 0001: the first three tables are
-- read-public; NONE has a public write policy — the service-role key used by the
-- compile-city-brief Edge Function bypasses RLS, and that bypass IS the write
-- boundary. city_brief_runs is internal: no public policies at all.
--
-- cityCode convention: lowercase (e.g. 'vte'), matching synthesized_experiences.

begin;

-- ─── 1. City registry ───────────────────────────────────────────────────────

create table if not exists public.sc_cities (
  city_code       text          primary key, -- lowercase, e.g. 'vte'
  name_local      text          not null,    -- local-script name, e.g. 'ວຽງຈັນ'
  name_zh         text          not null,    -- '万象'
  name_en         text          not null,    -- 'Vientiane'
  country_code    text          not null,    -- ISO 3166-1 alpha-2, e.g. 'LA'
  lat             double precision not null,
  lon             double precision not null,
  timezone        text          not null,    -- IANA tz, e.g. 'Asia/Vientiane'
  brief_enabled   boolean       not null default false,
  created_at      timestamptz   not null default now(),
  updated_at      timestamptz   not null default now()
);

-- ─── 2. Landing kit (net / money / visa / safety) ───────────────────────────

create table if not exists public.city_kits (
  city_code       text          not null references public.sc_cities(city_code) on delete cascade,
  section         text          not null check (section in ('net', 'money', 'visa', 'safety')),
  name            text          not null,    -- section headline, e.g. 'Airalo 老挝 eSIM'
  body            text          not null,    -- main copy
  lens_line       text,                       -- 独行透镜 one-liner
  health          text          not null default 'gray' check (health in ('green', 'yellow', 'red', 'gray')),
  last_verified_at timestamptz,
  link_url        text,                       -- deep-link target (allowlisted host)
  link_label      text,
  action          jsonb,                      -- structured action, e.g. visa_reminder / emergency_numbers
  sources         jsonb         not null default '[]'::jsonb,
  model_name      text,                       -- null when human-curated
  created_at      timestamptz   not null default now(),
  updated_at      timestamptz   not null default now(),
  primary key (city_code, section)
);
create index if not exists city_kits_city_idx on public.city_kits(city_code);

-- ─── 3. Live events (在地) ──────────────────────────────────────────────────

create table if not exists public.city_events (
  id              text          primary key, -- deterministic: evt_{city}_{slug≤32}_{yyyymmdd}
  city_code       text          not null references public.sc_cities(city_code) on delete cascade,
  name            text          not null,
  category        text          not null check (category in ('culture', 'wellness', 'market', 'music', 'sports', 'food', 'notice')),
  when_label      text          not null,    -- human-facing, e.g. '本周五 傍晚'
  starts_at       timestamptz,                -- nullable (all-week / recurring)
  ends_at         timestamptz   not null,    -- expiry anchor
  solo_score      double precision check (solo_score is null or (solo_score >= 0 and solo_score <= 10)),
  solo_note       text,
  health          text          not null default 'gray' check (health in ('green', 'yellow', 'red', 'gray')),
  seen_label      text,                       -- provenance, e.g. '人工策展 · 7月5日'
  lat             double precision,
  lng             double precision,
  limited_label   text,                       -- 限时 chip text, e.g. '仅本周'
  source_url      text          not null,
  verified_at     timestamptz,
  model_name      text,                       -- null when human-curated
  status          text          not null default 'active' check (status in ('active', 'expired')),
  created_at      timestamptz   not null default now(),
  updated_at      timestamptz   not null default now()
);
create index if not exists city_events_city_ends_idx on public.city_events(city_code, ends_at desc);

-- ─── 4. Compile-run accounting ──────────────────────────────────────────────

create table if not exists public.city_brief_runs (
  id              uuid          primary key default gen_random_uuid(),
  city_code       text          not null,
  target          text          not null check (target in ('kit', 'events')),
  status          text          not null check (status in ('ok', 'partial', 'failed')),
  search_calls    integer       not null default 0,
  prompt_tokens   integer       not null default 0,
  output_tokens   integer       not null default 0,
  items_written   integer       not null default 0,
  error           text,
  started_at      timestamptz   not null default now(),
  finished_at     timestamptz
);
create index if not exists city_brief_runs_city_target_idx
  on public.city_brief_runs(city_code, target, started_at desc);

-- ─── RLS: read-public on the three content tables ───────────────────────────

alter table public.sc_cities        enable row level security;
alter table public.city_kits        enable row level security;
alter table public.city_events      enable row level security;
alter table public.city_brief_runs  enable row level security;

create policy "sc_cities public-read" on public.sc_cities
  for select using (true);

create policy "city_kits public-read" on public.city_kits
  for select using (true);

create policy "city_events public-read" on public.city_events
  for select using (true);

-- Note: writes to sc_cities / city_kits / city_events happen ONLY via the
-- service-role key inside the compile-city-brief Edge Function (and the seed
-- script). Service role bypasses RLS, so no public INSERT/UPDATE/DELETE
-- policies exist here on purpose — that's the security boundary.
--
-- city_brief_runs has RLS enabled but NO policies at all: it is internal
-- accounting, unreadable by anon/authenticated clients.

-- ─── updated_at touch triggers (reuse sc_touch_updated_at from 0001) ─────────

create trigger sc_cities_touch      before update on public.sc_cities   for each row execute function public.sc_touch_updated_at();
create trigger sc_city_kits_touch   before update on public.city_kits   for each row execute function public.sc_touch_updated_at();
create trigger sc_city_events_touch before update on public.city_events for each row execute function public.sc_touch_updated_at();

-- ─── Expiry sweep — mark past events 'expired'. ─────────────────────────────
--
-- Events whose ends_at is in the past become 'expired'. Returns the number of
-- rows swept (useful for scheduled-job logging). SECURITY DEFINER so a
-- scheduled invocation under a restricted role can still update across cities.
--
-- Schedule via pg_cron (hourly), e.g.:
--   select cron.schedule('city-events-expire', '0 * * * *',
--                        'select public.sc_expire_city_events()');

create or replace function public.sc_expire_city_events()
  returns int
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  swept int;
begin
  with expired as (
    update public.city_events
    set status = 'expired'
    where status = 'active'
      and ends_at < now()
    returning 1
  )
  select count(*) into swept from expired;
  return swept;
end;
$$;

-- If pg_cron is available, register the hourly sweep idempotently. Skipped
-- silently where the extension is absent (e.g. bare local Postgres). The
-- iOS client also filters on ends_at as a second line of defence.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'city-events-expire',
      '0 * * * *',
      'select public.sc_expire_city_events()'
    );
  end if;
exception
  when undefined_function or undefined_table or insufficient_privilege then
    -- pg_cron present but not usable here; the function can still be called
    -- by an external scheduler. Nothing to do.
    null;
end$$;

commit;
