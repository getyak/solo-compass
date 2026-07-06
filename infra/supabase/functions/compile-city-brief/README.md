# compile-city-brief

Server-side curation of a city's **landing kit** (落地包: net / money / visa /
safety) and **live/在地 events**. Content is city-level and shared across all
users, so this function is NOT user-triggered — a user "refresh" in the app is
just a re-read of the `city_kits` / `city_events` tables. It is driven by the
`city-brief-refresh` GitHub Actions cron, or invoked with the service-role key.

Pipeline: Tavily search (advanced, ≤6 results/query) → normalize to candidates
(dedup by URL, cap 18 / ~15k chars) → DeepSeek curation (`json_object`, one
retry on invalid JSON) → quality gates in `../_shared/city-brief-core.ts` →
upsert. Every run is accounted in `city_brief_runs` (search calls, token usage,
items written, status `ok|partial|failed`).

## Secrets

```bash
# from infra/supabase
supabase link --project-ref <ref>
supabase secrets set TAVILY_API_KEY=<tvly-…>
supabase secrets set CITY_BRIEF_CRON_SECRET=<random-long-string>
# DEEPSEEK_API_KEY is already set (shared with chat-proxy);
# optional overrides — defaults shown:
supabase secrets set DEEPSEEK_BASE_URL=https://api.deepseek.com/v1
supabase secrets set DEEPSEEK_MODEL=deepseek-chat
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided automatically by the
Supabase runtime.

## Deploy

```bash
supabase functions deploy compile-city-brief
```

## Contract

`POST /functions/v1/compile-city-brief`

Auth (either one):

- `Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>`, or
- `x-cron-secret: <CITY_BRIEF_CRON_SECRET>` (what the GitHub cron uses — it does
  not hold the service-role key).

Request body:

```json
{ "city_code": "vte", "target": "both", "force": false }
```

- `city_code` — lowercase; the city must exist in `sc_cities` with
  `brief_enabled = true`.
- `target` — `"kit"`, `"events"`, or `"both"`.
- `force` — optional; bypasses the cooldown (events 72h, kit 240h).

| Status | Meaning                                             |
| ------ | --------------------------------------------------- |
| 200    | Compiled (see `outcomes[]` for per-target results)  |
| 400    | Bad input (missing city_code / invalid target)      |
| 401    | Missing / wrong service-role bearer AND cron secret |
| 404    | City not found                                      |
| 409    | `brief_enabled = false` for the city                |
| 500    | Missing TAVILY_API_KEY / DEEPSEEK_API_KEY           |

A `200` with `outcomes[].error = "cooldown"` means the target was skipped
because a successful run happened inside the cooldown window.

## Invoke examples

Service-role (local/admin):

```bash
curl -s -X POST \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"city_code":"vte","target":"both","force":true}' \
  https://<project-ref>.functions.supabase.co/compile-city-brief | python3 -m json.tool
```

Cron secret (what the workflow sends):

```bash
curl -s -X POST \
  -H "x-cron-secret: $CITY_BRIEF_CRON_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"city_code":"vte","target":"events"}' \
  https://<project-ref>.functions.supabase.co/compile-city-brief
```

## Local

```bash
supabase functions serve compile-city-brief --env-file infra/supabase/.env.local
# then run ./test.sh
```

See `test.sh` — it curls twice; the second call should hit the cooldown.
