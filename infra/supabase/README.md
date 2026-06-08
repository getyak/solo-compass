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

## Friend-operations hardening test

`0010_friends_hardening.sql` enforces anti-abuse + data hygiene on
`friend_requests` server-side (US-025): a 50/day per-user request cap
(over-limit → HTTP 429), a server-side `reporter_weight` re-gate on
`discover`-source requests (→ HTTP 403), silent dropping of requests between
blocked pairs, and the `sc_cleanup_stale_friend_requests()` expiry sweep
(`pending` past `expires_at` → `expired`, schedulable via pg_cron).

Run against a DB that has migrations `0001`–`0010` applied:

```bash
cd infra/supabase
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f test_friends_hardening.sql
```

It runs inside a rolled-back transaction (leaves no rows) and asserts the
cap boundary (50 ok, 51st rejected), the block-pair silent drop, the
discover gate, and the expiry sweep (past-due flips, future-dated stays).
`ON_ERROR_STOP=1` makes the first failed ASSERT abort with a clear message.

## Friend-code rotation test

`0011_friend_code_rotation.sql` makes a leaked friend code invalidatable
(US-026). It adds `sc_rotate_friend_code()` — a `SECURITY DEFINER` RPC that
**atomically** revokes the caller's current live code and activates a fresh,
crypto-random one (`sc_gen_friend_code()`, `SOLO-XXXX-XXXX` over an
ambiguity-free alphabet, so codes are unguessable and not reverse-lookupable).
The owner's live row is locked `FOR UPDATE`, so concurrent rotations serialize
and the `friend_codes_user_live_unique` index (0008) guarantees exactly one
live code per user — never two, never zero. A rotated-away code is `revoked_at`
immediately, and `redeem-friend-code` only resolves codes with
`revoked_at IS NULL`, so a leaked code stops redeeming the instant the owner
rotates.

Clients call it via PostgREST: `supabase.rpc("sc_rotate_friend_code")`.

Run against a DB that has migrations `0001`–`0011` applied:

```bash
cd infra/supabase
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f test_friend_code_rotation.sql
```

It asserts the code format, that rotation invalidates old + activates new
immediately, that a revoked code no longer matches the redeem predicate,
per-user isolation, and the one-live-code index backstop — all inside a
rolled-back transaction. Concurrent idempotency is verifiable by driving
`sc_rotate_friend_code()` from two sessions against the same user: the lock
serializes them and exactly one live code remains.

To verify a revoked code fails to redeem end-to-end after deploy: rotate
(`supabase.rpc("sc_rotate_friend_code")`), then POST the _old_ code to
`redeem-friend-code` — it must return `404 {"error":"not found"}` (same as an
unknown code, by anti-enumeration design).

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

# Friends (US-023 / FRD-022): APNs push to the recipient of a friend request.
# Called by FriendService.sendRequest after a pending row is created. Uses the
# service role to read the recipient's device_push_tokens (self-only SELECT under
# RLS) and sends token-based APNs (.p8 ES256 provider JWT).
supabase functions deploy friend-request-notify

# Friends (US-024 / FRD-023): APNs push to the OTHER party of a chat message.
# Called by ChatService.send after a chat_messages row is inserted. Derives the
# recipients server-side (conversation participants − sender) so it NEVER pushes
# self, reads their device_push_tokens via the service role, and sends a banner
# with a truncated preview. The tapped push deep-links to the matching ChatView.
# Reuses the same APNS_* secrets as friend-request-notify (set once, below).
supabase functions deploy message-notify
# Token-based APNs secrets (one-time; .p8 downloaded from the Apple Developer
# portal → Keys). APNS_HOST is the sandbox host for dev builds, the prod host
# for App Store / TestFlight builds.
supabase secrets set APNS_KEY_P8="$(cat AuthKey_XXXXXXXXXX.p8)"
supabase secrets set APNS_KEY_ID=XXXXXXXXXX
supabase secrets set APNS_TEAM_ID=YYYYYYYYYY
supabase secrets set APNS_TOPIC=com.solocompass.app
supabase secrets set APNS_HOST=api.sandbox.push.apple.com   # prod: api.push.apple.com
```

See each function's header comment for request/response shape and required secrets.
