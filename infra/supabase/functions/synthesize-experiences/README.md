# synthesize-experiences

Server-side AI synthesis. Removes the DeepSeek API key from the iOS bundle
(PRD US-030 / FR-19). Calls DeepSeek's OpenAI-compatible
`/chat/completions` endpoint with thinking disabled.

## Deploy

```bash
supabase functions deploy synthesize-experiences

supabase secrets set DEEPSEEK_API_KEY=sk-...
# optional overrides — defaults shown:
supabase secrets set DEEPSEEK_BASE_URL=https://api.deepseek.com/v1
supabase secrets set DEEPSEEK_MODEL=deepseek-flash
# SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are auto-injected.
```

## Test

```bash
JWT=<paste a real Supabase user access token from the iOS app>
PROJECT=<your-project-ref>

cd infra/supabase/functions/synthesize-experiences
JWT="$JWT" PROJECT="$PROJECT" ./test.sh
```

Expected response on cache hit / miss:

```json
{
  "experiences": [...],
  "cached": true
}
```

Quota / entitlement errors:

| Status | Meaning                                                       |
| ------ | ------------------------------------------------------------- |
| 401    | Bearer token missing / invalid                                |
| 402    | Caller's profiles.entitlement_tier is `free` or `pro_expired` |
| 429    | Caller has used today's 30-call quota                         |
| 502    | DeepSeek upstream failure or invalid JSON                     |

## Environment

- `DEEPSEEK_API_KEY` — required, set via `supabase secrets set`
- `DEEPSEEK_BASE_URL` — optional; defaults to `https://api.deepseek.com/v1`
- `DEEPSEEK_MODEL` — optional; defaults to `deepseek-flash` (legacy ids are
  normalized forward)
- `SUPABASE_URL` — auto-injected at runtime
- `SUPABASE_SERVICE_ROLE_KEY` — auto-injected; used to read profiles + write
  synthesized_experiences (bypasses RLS)

## Wire protocol

- `Authorization: Bearer <DEEPSEEK_API_KEY>`
- Request body: OpenAI-compatible `{ model, max_tokens, messages, thinking }`,
  with a top-level `thinking: {"type":"disabled"}`. Thinking must not be
  nested under `extra_body`.
- Response parsing: `choices[0].message.content`, then the first `[…]` JSON
  array is extracted and every item is schema-checked before caching. Empty
  arrays and `null` / non-object items are rejected with a controlled `502`
  **before** any cache write.
- Cache lookup is qualified by `source_cache_key` **and** `model_name`, so a
  payload synthesized by an older model can never be served for a
  `deepseek-flash` request.

## Cost guardrails

- Daily quota 30 / Pro user, enforced via `sc_function_calls`
- Cache hits do NOT increment the quota counter
- DeepSeek platform spend limits are the final safety net
