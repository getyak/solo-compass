# Living Data Agent Tools

Status: implemented foundation, with provider expansion points called out below.

Solo Compass serves `Experience` objects. A `Place` is only the internal anchor
that lets evidence from multiple sources converge without turning the product
into a generic POI directory.

## Runtime contract

The request path follows stale-while-revalidate:

1. Read the persisted Experience and `resolved_place_features` snapshot.
2. Return usable data immediately when it does not violate a hard constraint.
3. Enqueue missing or stale fields in `refresh_jobs`; do not call providers from
   the page request.
4. Let the leased worker append observations, materialize affected features,
   and relink the Experience.
5. Hash the normalized intent and exact materialized candidate input. Reuse the
   user-scoped `route_compilations` entry while it is fresh; newly resolved
   evidence changes the fingerprint and causes a deterministic recompile.

Unknown, negative, stale, and conflicted are separate states. A route may show a
stale soft preference with a warning. It may not reinterpret unknown hours as
closed, or a missing budget observation as zero cost.

## Agent-facing tools

### `get_experience_snapshot`

Backed by `EvidenceRepo.getSnapshotsForExperiences`.

```json
{
  "experience_ids": ["exp_cmi_nimman_coffee"],
  "feature_keys": ["opening_hours.regular", "work.wifi_reliability"]
}
```

Returns the current materialized values, evidence state, confidence,
`fresh_until`, and place anchor. It performs no provider calls.

### `request_evidence_refresh`

Backed by `RefreshQueueRepo.enqueue` and the priority policy in
`packages/data/src/refresh-policy.ts`.

```json
{
  "place_id": "uuid",
  "feature_keys": ["opening_hours.regular"],
  "reason": "hard_constraint",
  "urgency": "interactive",
  "decision_factors": {
    "demand": 1,
    "impact": 1,
    "uncertainty": 1,
    "staleness": 1,
    "estimated_cost": 0.2
  }
}
```

The idempotency bucket prevents a chat loop or repeated page render from buying
the same information repeatedly.

### `compile_workday_route`

Implemented as `POST /api/routes/compile` and
`@solo-compass/routing.planWorkdayRoute`.

The endpoint requires a Supabase bearer token. Its output is persisted by
`RouteCompilationRepo` with separate request and evidence fingerprints. Fresh
walking/cycling results live for six hours, auto matrices for ten minutes, and
partial or unsatisfiable results for five minutes. A cache outage only removes
the optimization; route compilation still proceeds.

Cache misses consume an atomic database quota (30 new compilations per user per
hour) before Valhalla is called. Cache hits do not consume quota. This bounds
matrix cost across multiple Web instances rather than relying on process-local
rate limiting.

The caller supplies local-day minutes and ordered tasks. Candidate discovery,
evidence projection, a Valhalla time-distance matrix, constraint solving, and
fallback selection happen outside the LLM. A missing matrix edge remains
unreachable; there is no straight-line substitution.

```json
{
  "origin": [98.9932, 18.7883],
  "radiusMeters": 3000,
  "localDate": "2026-08-31",
  "mode": "pedestrian",
  "intent": {
    "startMinute": 540,
    "endMinute": 1020,
    "maxTravelMinutes": 90,
    "budget": { "maxAmount": 700, "currency": "THB" },
    "tasks": [
      {
        "id": "focus",
        "kind": "deep_work",
        "durationMinutes": 150,
        "latestEndMinute": 750,
        "constraints": [
          {
            "featureKey": "work.wifi_reliability",
            "operator": "gte",
            "expected": 4,
            "hard": true
          }
        ]
      },
      {
        "id": "call",
        "kind": "video_call",
        "durationMinutes": 60,
        "earliestStartMinute": 840,
        "latestEndMinute": 960,
        "constraints": [
          {
            "featureKey": "work.video_call_fit",
            "operator": "eq",
            "expected": true,
            "hard": true
          }
        ]
      }
    ]
  }
}
```

An unsatisfiable result names the first failed task and aggregates rejection
reasons. If evidence is the reason, the API schedules interactive refresh jobs
and returns that state rather than asking an LLM to improvise.

This server cache prevents repeat matrix and solver work. Long-term user display
is a separate lifecycle. The iOS agent exposes `compile_workday_route` as a
distinct tool from the unconstrained `build_route` walk. It authenticates with
the traveler's Supabase bearer token, pins every task to the current visible
Experience IDs, and renders the exact server schedule, evidence coverage, and
per-task fallback. The proposal is not saved until the user adopts it; after
adoption, `RouteStore` persists `CompiledWorkdayPlan` in the optional
`RouteRecord.compiledPlanBlob` column so the timeline remains available across
launches. The LLM may explain the card but cannot edit its times or silently
relax a hard constraint.

Release/TestFlight builds resolve the API root from `SOLO_API_BASE_URL` through
the generated `Secrets` layer (environment or bundled `Secrets.plist` are also
supported). There is deliberately no production localhost fallback.

### `record_work_session`

Implemented as authenticated `POST /api/work-sessions` and
`WorkSessionRepo.record`.

The request accepts bounded structured outcomes only: completion state,
structured failure reason, 1–5 Wi-Fi/noise reports, boolean power/video-call/
long-stay results, and a currency-qualified minimum spend. It deliberately does
not accept a transcript, route trace, or arbitrary review body.

The private session remains user-scoped. Derived observations omit the user id,
are append-only, and are rematerialized through the same conflict-aware resolver
as provider evidence.

Authenticated clients have read-only access to their own raw sessions. Inserts
must pass through the API/service role so recency, quota, idempotency, and
anonymous evidence derivation cannot be bypassed with direct PostgREST writes.

Abuse resistance is part of the data model rather than an LLM prompt: reports
must fall within a seven-day window, each account is capped at 12 new sessions
per rolling day, repeated sessions from one traveler share one pseudonymous
independence key, and a single report has insufficient confidence for the Web
compiler's default hard-constraint threshold (`0.6`). Idempotency is scoped to
`(user_id, idempotency_key)` so one user cannot collide with another user's
submission.

## Worker tools

The worker owns three narrow operations:

- `claim_refresh_jobs`: lease a bounded batch using `FOR UPDATE SKIP LOCKED`.
- source adapter `fetch`: acquire candidates without deciding truth.
- evidence writer: register retention metadata, append observations, and
  materialize only the touched feature keys.

Provider policy is enforced before persistence. Google Places is excluded from
the durable ledger; it belongs in a separate ephemeral verifier. OSM content is
stored under its declared policy. First-party work sessions are retained as
private user data and emit anonymous derived facts.

The executable worker requires `OVERPASS_URL`. It deliberately has no implicit
public-Overpass default, so batch traffic must go to an explicitly approved or
self-hosted endpoint. The same process prunes expired `route_compilations`
hourly; cache failures are logged but never stop evidence refresh.

Adapters are capability-filtered before acquisition. For example, an OSM
adapter may satisfy identity, coordinates, or regular-hours work, but a Wi-Fi
refresh fails into the retry/dead-letter path without spending an Overpass
request. A licensed workability connector can later claim that capability.

## TikHub / Xiaohongshu connector boundary

TikHub is not wired by default because a reachable API is not the same as a
license to retain and republish its payload. A future adapter must meet all of
these conditions:

- explicit configured provider and endpoint; no hidden scraper fallback;
- source-policy allowlist before any request;
- `metadata_only` or `derived_only` retention unless the applicable terms allow
  more;
- no note text or image copied into the public place record;
- extracted claims carry source reference, observation time, confidence, and an
  independence key so reposts cannot manufacture consensus;
- marketing language receives a lower source weight than direct work sessions;
- deletion/retirement can remove the artifact reference without rewriting the
  append-only observation history incorrectly.

The connector should implement the existing `SourceAdapter` boundary, followed
by a provider-specific extractor. It must not bypass `source_artifacts`,
`place_observations`, or the resolver.

## Remaining deployment work

- Run Supabase migrations `0014`–`0016` in the target environment.
- Deploy a Valhalla endpoint and set `VALHALLA_URL` for the Web/API service.
- Configure an approved/self-hosted Overpass endpoint as `OVERPASS_URL` for the
  evidence worker.
- Add licensed non-OSM extractors for Wi-Fi, noise, seats, and long-stay facts.
- Add a background scheduler for monthly open-POI releases, promote matched
  places into the Experience candidate index, and add dead-letter alerting for
  refresh workers.
