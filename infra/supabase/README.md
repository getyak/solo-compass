# Supabase infrastructure

> Source of truth for the Solo Compass backend schema. Apply migrations
> to a fresh project via the Supabase CLI; each migration is forward-only.

## Required env

Copy from `.env.example` at the repo root and fill in real values:

```
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_ANON_KEY=eyJ...           # public, ships with iOS / web bundles
SUPABASE_SERVICE_ROLE_KEY=eyJ...   # server-only, NEVER ships to clients
ANTHROPIC_API_KEY=sk-ant-...       # used only by Edge Functions (Epic E US-030)
```

The anon key is what iOS sends as the `apikey` header. The service role
key bypasses RLS and is used by Edge Functions only — never by the
client.

## Apply migrations

Once the founder has provisioned the production project (PRD US-I2):

```bash
brew install supabase/tap/supabase
supabase login
supabase link --project-ref <project-ref>

cd infra/supabase
supabase db push
```

For a fresh remote project, `0001_init.sql` runs first and creates every
table and RLS policy.

## Schema overview

Three groups of tables:

1. **User-scoped data** (RLS = `auth.uid() = user_id`):
   - `profiles` — entitlement tier, anonymous flag
   - `user_completions` — append-only per visit
   - `user_favorites` — toggle (composite PK)
   - `micro_surveys` — 1–5 ratings + recommend
   - `subscription_events` — StoreKit lifecycle telemetry
   - `recent_explore_regions` — last N explored regions for offline mode

2. **Shared community cache** (read-public, write-service-role):
   - `osm_pois` — canonical OSM POI metadata
   - `synthesized_experiences` — AI-enriched Experience JSON, dedupable
     by `source_cache_key`. Stores `aggregated_solo_score` (refreshed
     nightly) so all users benefit from one paying user's exploration.
   - `solo_score_signals` — raw signal rows; aggregated nightly into
     `synthesized_experiences.aggregated_solo_score`. RLS lets users
     read their own only (privacy).

3. **Internal accounting** (service-role only writes):
   - `sc_function_calls` — Edge Function rate-limit accounting

## RLS smoke test

After applying migrations:

```bash
cd infra/supabase
deno run --allow-net --allow-env test_rls.ts
```

The test connects with both anon and service-role keys, creates two
synthetic users, then asserts:

- anon CANNOT read `user_completions` belonging to either user
- user A authenticated CANNOT read user B's `user_completions`
- anon CAN read `synthesized_experiences` (public-read)
- service-role CAN write to `synthesized_experiences` (write boundary)

A non-zero exit means the RLS posture has regressed; do not deploy.

## Edge Functions

Live in `infra/supabase/functions/<name>/index.ts`. Deploy with:

```bash
supabase functions deploy <name>
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
```

Deployed functions:

```bash
supabase functions deploy chat-proxy
supabase functions deploy companion-discover
supabase functions deploy enrich-user-experience
supabase functions deploy synthesize-experiences
# Friends (FRD-026): resolve a typed/scanned friend code → profile preview.
# Needs SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (service role bypasses RLS
# for the redeem path only; friend_codes has no public SELECT — anti-enum).
supabase functions deploy redeem-friend-code
```

See each function's header comment for request/response shape and required secrets.
