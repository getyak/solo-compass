-- Durable, user-scoped cache for deterministic route compiler output.
-- The service role is the only writer; users may read their own cached plans.

begin;

create type public.route_compilation_status as enum ('solved', 'unsatisfiable');

create table public.route_compilations (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users(id) on delete cascade,
  cache_key            text not null,
  request_fingerprint  text not null,
  input_fingerprint    text not null,
  status               public.route_compilation_status not null,
  plan_payload         jsonb not null,
  expires_at           timestamptz not null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  unique (user_id, cache_key)
);

create index route_compilations_expiry_idx on public.route_compilations(expires_at);
create index route_compilations_user_updated_idx
  on public.route_compilations(user_id, updated_at desc);

create table public.route_compile_quotas (
  user_id      uuid not null references auth.users(id) on delete cascade,
  bucket_start timestamptz not null,
  attempts     integer not null default 0 check (attempts >= 0),
  updated_at   timestamptz not null default now(),
  primary key (user_id, bucket_start)
);
create index route_compile_quotas_expiry_idx on public.route_compile_quotas(bucket_start);

create or replace function public.consume_route_compile_quota(
  p_user_id uuid,
  p_limit integer default 30
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  allowed boolean;
  current_bucket timestamptz := date_trunc('hour', now());
begin
  if p_limit < 1 then return false; end if;
  insert into public.route_compile_quotas (user_id, bucket_start, attempts, updated_at)
  values (p_user_id, current_bucket, 1, now())
  on conflict (user_id, bucket_start) do update
    set attempts = route_compile_quotas.attempts + 1,
        updated_at = now()
    where route_compile_quotas.attempts < p_limit
  returning true into allowed;
  return coalesce(allowed, false);
end;
$$;

alter table public.route_compilations enable row level security;
alter table public.route_compile_quotas enable row level security;
create policy "route compilations self-select" on public.route_compilations
  for select using (auth.uid() = user_id);
revoke all on table public.route_compilations, public.route_compile_quotas from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.route_compilations from authenticated;
revoke all on table public.route_compile_quotas from authenticated;

revoke all on function public.consume_route_compile_quota(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.consume_route_compile_quota(uuid, integer) to service_role;

commit;
