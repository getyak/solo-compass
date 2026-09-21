-- Living data engine: append-only evidence, materialized place features, and
-- a durable refresh queue. `places` is an internal evidence anchor; the
-- user-facing unit remains `Experience`.

begin;

create extension if not exists postgis;

create type public.place_operating_status as enum (
  'unknown', 'active', 'temporarily_closed', 'permanently_closed'
);
create type public.artifact_retention_policy as enum (
  'metadata_only', 'derived_only', 'cacheable_content', 'first_party'
);
create type public.observation_state as enum (
  'observed', 'reported_unknown', 'not_applicable'
);
create type public.resolved_feature_status as enum (
  'resolved', 'unknown', 'conflicted', 'stale'
);
create type public.refresh_job_status as enum (
  'queued', 'running', 'succeeded', 'failed', 'dead_letter', 'cancelled'
);
create type public.refresh_reason as enum (
  'coverage_gap', 'soft_stale', 'hard_constraint', 'user_report', 'source_release', 'manual'
);
create type public.refresh_urgency as enum ('background', 'interactive');

create table public.places (
  id                  uuid primary key default gen_random_uuid(),
  canonical_name      text not null,
  basic_category      text,
  location            geography(Point, 4326) not null,
  operating_status    public.place_operating_status not null default 'unknown',
  identity_confidence double precision not null default 0.5
                      check (identity_confidence between 0 and 1),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index places_location_gist on public.places using gist (location);
create index places_operating_status_idx on public.places (operating_status);

create table public.place_external_refs (
  id            uuid primary key default gen_random_uuid(),
  place_id      uuid not null references public.places(id) on delete cascade,
  provider      text not null,
  external_id   text not null,
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  retired_at    timestamptz,
  metadata      jsonb,
  unique (provider, external_id)
);
create index place_external_refs_place_provider_idx
  on public.place_external_refs (place_id, provider);

create table public.source_artifacts (
  id                 uuid primary key default gen_random_uuid(),
  provider           text not null,
  external_ref       text not null,
  source_url         text,
  content_hash       text not null,
  license_code       text,
  retention_policy   public.artifact_retention_policy not null,
  raw_storage_key    text,
  retrieved_at       timestamptz not null,
  source_observed_at timestamptz,
  expires_at         timestamptz,
  metadata           jsonb,
  created_at         timestamptz not null default now(),
  unique (provider, external_ref, content_hash),
  check (
    retention_policy in ('cacheable_content', 'first_party')
    or raw_storage_key is null
  )
);
create index source_artifacts_expiry_idx
  on public.source_artifacts (provider, expires_at);

create table public.place_observations (
  id               uuid primary key default gen_random_uuid(),
  place_id         uuid not null references public.places(id) on delete cascade,
  artifact_id      uuid references public.source_artifacts(id) on delete set null,
  feature_key      text not null,
  state            public.observation_state not null default 'observed',
  value            jsonb,
  confidence       double precision not null check (confidence between 0 and 1),
  source_weight    double precision not null default 1 check (source_weight between 0 and 1),
  independence_key text not null,
  time_scope       jsonb,
  observed_at      timestamptz not null,
  expires_at       timestamptz,
  extractor_version text not null,
  dedupe_key       text not null unique,
  created_at       timestamptz not null default now(),
  check ((state = 'observed' and value is not null) or state <> 'observed')
);
create index place_observations_feature_time_idx
  on public.place_observations (place_id, feature_key, observed_at desc);
create index place_observations_artifact_idx
  on public.place_observations (artifact_id);

create table public.resolved_place_features (
  place_id                    uuid not null references public.places(id) on delete cascade,
  feature_key                 text not null,
  value                       jsonb,
  status                      public.resolved_feature_status not null,
  confidence                  double precision not null check (confidence between 0 and 1),
  latest_observed_at          timestamptz,
  fresh_until                 timestamptz,
  supporting_observation_ids uuid[] not null default '{}',
  conflicting_observation_ids uuid[] not null default '{}',
  conflict_details            jsonb,
  resolver_version            text not null,
  resolution_fingerprint      text not null,
  resolved_at                 timestamptz not null,
  primary key (place_id, feature_key),
  check (status = 'unknown' or value is not null)
);
create index resolved_place_features_status_freshness_idx
  on public.resolved_place_features (status, fresh_until);

-- Intentionally no FK to a single Experience table during migration: the
-- current backend contains seed, synthesized, and user-created experience
-- stores. The stable text id remains the cross-store contract.
create table public.experience_place_links (
  experience_id text primary key,
  place_id      uuid not null references public.places(id) on delete cascade,
  confidence    double precision not null default 1 check (confidence between 0 and 1),
  method        text not null,
  linked_at     timestamptz not null default now()
);
create index experience_place_links_place_idx
  on public.experience_place_links (place_id);

create table public.refresh_jobs (
  id              uuid primary key default gen_random_uuid(),
  place_id        uuid references public.places(id) on delete cascade,
  feature_keys    text[] not null default '{}',
  query           jsonb,
  reason          public.refresh_reason not null,
  urgency         public.refresh_urgency not null default 'background',
  priority        integer not null,
  provider_hint   text,
  budget_class    text not null,
  idempotency_key text not null unique,
  status          public.refresh_job_status not null default 'queued',
  demand_score    double precision not null check (demand_score between 0 and 1),
  decision_impact double precision not null check (decision_impact between 0 and 1),
  uncertainty     double precision not null check (uncertainty between 0 and 1),
  staleness       double precision not null check (staleness between 0 and 1),
  estimated_cost  double precision not null check (estimated_cost > 0),
  not_before      timestamptz not null default now(),
  claimed_by      text,
  claimed_at      timestamptz,
  lease_expires_at timestamptz,
  attempts        integer not null default 0 check (attempts >= 0),
  max_attempts    integer not null default 5 check (max_attempts > 0),
  last_error      text,
  result          jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  completed_at    timestamptz
);
create index refresh_jobs_claim_idx
  on public.refresh_jobs (status, not_before, priority desc);
create index refresh_jobs_place_status_idx
  on public.refresh_jobs (place_id, status);

create or replace function public.sc_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger places_set_updated_at
  before update on public.places
  for each row execute function public.sc_set_updated_at();
create trigger refresh_jobs_set_updated_at
  before update on public.refresh_jobs
  for each row execute function public.sc_set_updated_at();

create or replace function public.upsert_place_identity(
  p_provider text,
  p_external_id text,
  p_canonical_name text,
  p_longitude double precision,
  p_latitude double precision,
  p_basic_category text default null,
  p_identity_confidence double precision default 0.5,
  p_metadata jsonb default null
)
returns public.places
language plpgsql
security definer
set search_path = public
as $$
declare
  place_row public.places%rowtype;
  existing_place_id uuid;
begin
  if p_longitude < -180 or p_longitude > 180 or p_latitude < -90 or p_latitude > 90 then
    raise exception 'invalid WGS-84 coordinate';
  end if;
  if p_identity_confidence < 0 or p_identity_confidence > 1 then
    raise exception 'identity confidence must be between 0 and 1';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_provider || ':' || p_external_id, 0));
  select place_id into existing_place_id
  from public.place_external_refs
  where provider = p_provider and external_id = p_external_id
  for update;

  if existing_place_id is null then
    insert into public.places (canonical_name, basic_category, location, identity_confidence)
    values (
      p_canonical_name,
      p_basic_category,
      st_setsrid(st_makepoint(p_longitude, p_latitude), 4326)::geography,
      p_identity_confidence
    )
    returning * into place_row;

    insert into public.place_external_refs (place_id, provider, external_id, metadata)
    values (place_row.id, p_provider, p_external_id, p_metadata);
  else
    update public.places
    set canonical_name = p_canonical_name,
        basic_category = coalesce(p_basic_category, basic_category),
        location = st_setsrid(st_makepoint(p_longitude, p_latitude), 4326)::geography,
        identity_confidence = greatest(identity_confidence, p_identity_confidence)
    where id = existing_place_id
    returning * into place_row;

    update public.place_external_refs
    set last_seen_at = now(), retired_at = null, metadata = coalesce(p_metadata, metadata)
    where provider = p_provider and external_id = p_external_id;
  end if;

  return place_row;
end;
$$;

create or replace function public.claim_refresh_jobs(
  p_worker text,
  p_batch_size integer default 10,
  p_lease_seconds integer default 120
)
returns setof public.refresh_jobs
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with candidates as (
    select id
    from public.refresh_jobs
    where (
      (status = 'queued' and not_before <= now())
      or (status = 'running' and lease_expires_at < now())
    )
    and attempts < max_attempts
    order by urgency desc, priority desc, created_at asc
    for update skip locked
    limit greatest(1, least(p_batch_size, 100))
  )
  update public.refresh_jobs as jobs
  set status = 'running',
      claimed_by = p_worker,
      claimed_at = now(),
      lease_expires_at = now() + make_interval(secs => greatest(30, p_lease_seconds)),
      attempts = jobs.attempts + 1,
      last_error = null,
      updated_at = now()
  from candidates
  where jobs.id = candidates.id
  returning jobs.*;
end;
$$;

-- Raw evidence and queue internals are service-role only. User-facing data is
-- served through Experience APIs after policy-aware resolution.
alter table public.places enable row level security;
alter table public.place_external_refs enable row level security;
alter table public.source_artifacts enable row level security;
alter table public.place_observations enable row level security;
alter table public.resolved_place_features enable row level security;
alter table public.experience_place_links enable row level security;
alter table public.refresh_jobs enable row level security;

revoke all on function public.claim_refresh_jobs(text, integer, integer)
  from public, anon, authenticated;
revoke all on function public.upsert_place_identity(text, text, text, double precision, double precision, text, double precision, jsonb)
  from public, anon, authenticated;
grant execute on function public.claim_refresh_jobs(text, integer, integer) to service_role;
grant execute on function public.upsert_place_identity(text, text, text, double precision, double precision, text, double precision, jsonb) to service_role;

commit;
