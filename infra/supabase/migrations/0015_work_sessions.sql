-- First-party work outcomes. Raw sessions remain visible only to their owner;
-- the service derives anonymous place observations after authenticated writes.

begin;

create type public.work_session_outcome as enum (
  'completed', 'partially_completed', 'abandoned'
);
create type public.work_session_failure_reason as enum (
  'place_closed', 'no_seat', 'wifi_unreliable', 'too_noisy', 'no_power',
  'video_call_not_allowed', 'long_stay_pressure', 'minimum_spend', 'other'
);

create table public.work_sessions (
  id                     uuid primary key default gen_random_uuid(),
  user_id                uuid not null references auth.users(id) on delete cascade,
  experience_id          text not null,
  place_id               uuid not null references public.places(id) on delete cascade,
  planned_task_kind      text not null,
  started_at             timestamptz not null,
  ended_at               timestamptz not null,
  outcome                public.work_session_outcome not null,
  failure_reason         public.work_session_failure_reason,
  place_was_open         boolean,
  wifi_reliability       smallint check (wifi_reliability between 1 and 5),
  noise_level            smallint check (noise_level between 1 and 5),
  power_available        boolean,
  video_call_worked      boolean,
  long_stay_accepted     boolean,
  minimum_spend_amount   double precision,
  minimum_spend_currency text,
  idempotency_key        text not null,
  created_at             timestamptz not null default now(),
  unique (user_id, idempotency_key),
  check (ended_at >= started_at and ended_at <= started_at + interval '24 hours'),
  check (
    (minimum_spend_amount is null and minimum_spend_currency is null)
    or (
      minimum_spend_amount >= 0
      and minimum_spend_currency ~ '^[A-Z]{3}$'
    )
  )
);

create index work_sessions_user_time_idx on public.work_sessions(user_id, ended_at desc);
create index work_sessions_place_time_idx on public.work_sessions(place_id, ended_at desc);
create index work_sessions_experience_time_idx on public.work_sessions(experience_id, ended_at desc);

alter table public.work_sessions enable row level security;
create policy "work sessions self-select" on public.work_sessions
  for select using (auth.uid() = user_id);
revoke all on table public.work_sessions from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.work_sessions from authenticated;

commit;
