# Solo Compass AI endpoint topology snapshot

This document is a topology snapshot for the current AI surfaces. It is
intentionally descriptive: it records where model calls originate, which
provider/model they use, and how they are gated.

## Summary

All built-in AI **text/chat** routes now speak the DeepSeek OpenAI-compatible
`chat/completions` protocol. The built-in default model is **`deepseek-flash`**
(DeepSeek V4.1 Flash). Legacy model ids (`deepseek-chat`, `deepseek-reasoner`,
`deepseek-v4-pro`, `deepseek-v4-flash`) are normalized to `deepseek-flash` at
every entry point so a saved selection or stale secret cannot silently keep a
route on an old model.

The service-paid `chat-proxy` Edge Function owns model + thinking mode: it
**forces** `model=deepseek-flash` and a top-level `thinking: {"type":"disabled"}`
even if an older or malicious client sends a different model (for example
`claude-sonnet-4-6`) or `thinking.type=enabled`.

Audio transcription is a separate modality: the Telegram bot still calls
OpenAI `whisper-1` for voice notes (`apps/bot/src/index.ts`). That path is
intentionally unchanged by this migration.

DeepSeek V4.1 enables `thinking` at "high" by default. Every built-in route
explicitly disables it with a **top-level** `thinking: {"type":"disabled"}`
wire field (never nested under `extra_body`) because the app's tool loops do
not retain `reasoning_content` and its `max_tokens` budget is capped at
256–4096. See <https://api-docs.deepseek.com/guides/thinking_mode/>.

| Surface                    | Call sites                                                                                                                        | Provider / endpoint                                                                                  | Model                                                   | Auth source                                                      | Quota                                                                  |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------- | ---------------------------------------------------------------- | ---------------------------------------------------------------------- |
| App AI service             | `AIService.synthesizeExperiences`, `explainRecommendation`, `processVoiceIntent`, `sendAgentMessage`, `sendAgentMessageStreaming` | DeepSeek/OpenAI-compatible chat completions, `Secrets.resolvedDeepSeekBaseURL + "/chat/completions"` | `deepseek-flash`; per-kind `DEEPSEEK_MODEL_*` overrides | `Secrets.resolvedDeepSeekApiKey` via `AIService.resolveAPIKey()` | Pro: synthesis/voice 30 per day, explanation 60 per day; free: 0/0     |
| Supabase Edge (Pro proxy)  | `chat-proxy` function — forwards voice/explanation/synthesis bodies                                                               | DeepSeek/OpenAI-compatible, `DEEPSEEK_BASE_URL + "/chat/completions"`                                | `deepseek-flash` — server-forced, client model ignored  | Supabase JWT + service-role `DEEPSEEK_API_KEY`                   | Pro only (402 for free/expired); per-kind daily caps mirror the device |
| Supabase Edge (synthesis)  | `synthesize-experiences` function — batch OSM POI → Experience JSON                                                               | DeepSeek/OpenAI-compatible                                                                           | `deepseek-flash` (or `DEEPSEEK_MODEL`)                  | Supabase JWT + service-role `DEEPSEEK_API_KEY`                   | Pro only; 30 calls/day; cache hits do not count                        |
| Supabase Edge (UGC enrich) | `enrich-user-experience` function                                                                                                 | DeepSeek/OpenAI-compatible                                                                           | `deepseek-flash` (or `DEEPSEEK_MODEL`)                  | Supabase JWT + service-role `DEEPSEEK_API_KEY`                   | Pro only; 30 calls/day                                                 |
| Supabase Edge (city brief) | `compile-city-brief` function — Tavily + curation                                                                                 | DeepSeek/OpenAI-compatible                                                                           | `deepseek-flash` (or `DEEPSEEK_MODEL`)                  | service-role bearer or `x-cron-secret` + `DEEPSEEK_API_KEY`      | none (cron-driven, cooldown-gated)                                     |
| Web API                    | `apps/web` `/api/experiences/nearby`                                                                                              | `@solo-compass/ai` `rankExperiences` → DeepSeek                                                      | `deepseek-flash` (or `DEEPSEEK_MODEL`)                  | `DEEPSEEK_API_KEY` process env                                   | none (falls back to soloScore ranking)                                 |
| Go API                     | `apps/api/internal/reviews.Extractor`                                                                                             | DeepSeek/OpenAI-compatible `DEEPSEEK_BASE_URL + "/chat/completions"`                                 | `deepseek-flash` (or `DEEPSEEK_MODEL`)                  | `DEEPSEEK_API_KEY` process env                                   | none                                                                   |

## DeepSeek chat-completions surfaces

### Endpoint and model resolution

- File: `apps/ios/SoloCompass/Services/AIService.swift`
- Endpoint: `Secrets.resolvedDeepSeekBaseURL`, with trailing slashes stripped,
  plus `/chat/completions`.
- Model: `Secrets.resolvedDeepSeekModel`, which maps legacy DeepSeek ids
  forward to `deepseek-flash` for the built-in provider. Explicit
  OpenAI/custom provider models are preserved verbatim.
- Per-kind model overrides:
  - `DEEPSEEK_MODEL_SYNTHESIS`
  - `DEEPSEEK_MODEL_EXPLANATION`
  - `DEEPSEEK_MODEL_VOICE`

### Key resolution

`AIService.resolveAPIKey()` resolves the DeepSeek key via
`Secrets.resolvedDeepSeekApiKey`; if that returns a non-empty value it is used
for all DeepSeek calls. `Secrets` resolves in-app settings, UserDefaults
overrides, then generated/environment-backed configuration.

DeepSeek calls use an OpenAI-style bearer token header:

```text
Authorization: Bearer <DeepSeek key>
```

When Pro routing is enabled, requests go through the `chat-proxy` Edge
Function instead; the server holds `DEEPSEEK_API_KEY`, enforces the same
per-kind quota, and owns model/thinking (it forces `deepseek-flash` +
`thinking:disabled` regardless of the client body).

### `synthesizeExperiences`

- Kind: `.synthesis`.
- Endpoint: DeepSeek `/chat/completions` (direct) or `chat-proxy` Edge.
- Purpose: turn nearby POIs/context into generated `Experience` candidates.
- Quota bucket: synthesis.

### `explainRecommendation`

- Kind: `.explanation`.
- Endpoint: DeepSeek `/chat/completions` (direct) or `chat-proxy` Edge.
- Purpose: produce a concise explanation for a recommended experience.
- Quota bucket: explanation.

### `processVoiceIntent`

- Kind: `.voice`.
- Endpoint: DeepSeek `/chat/completions` (direct) or `chat-proxy` Edge.
- Purpose: parse a transcript plus nearby curated experiences into recommended
  IDs, explanation text, and an optional filter suggestion.
- Quota bucket: synthesis/voice.

### `sendAgentMessage`

- Kind: `.voice`.
- Endpoint: DeepSeek `/chat/completions`.
- Purpose: non-streaming voice-agent turn with OpenAI-compatible tool
  definitions and tool-call parsing.
- Quota bucket: synthesis/voice.

### `sendAgentMessageStreaming`

- Kind: `.voice`.
- Endpoint: DeepSeek `/chat/completions` with `stream: true`.
- Purpose: streaming voice-agent turn that emits content deltas and
  accumulated tool calls.
- Quota bucket: synthesis/voice.

## Quota system

`AIService` enforces the app AI quota locally:

- `AIService.dailySynthesisQuota = 30`
- `AIService.dailyExplanationQuota = 60`
- `AIService.dailySynthesisQuotaFree = 0`
- `AIService.dailyExplanationQuotaFree = 0`

For Pro users:

- `.synthesis` and `.voice` use the synthesis quota: 30 calls/day.
- `.explanation` uses the explanation quota: 60 calls/day.

For free users, both quota buckets are zero; the paywall is still the primary
gate, and the AIService quota is a second line of defense.

Edge Functions enforce the same daily caps server-side via
`sc_function_calls`, keyed per user and quota bucket.

## Refactor notes

- All built-in AI **text/chat** routes are DeepSeek OpenAI-compatible; there
  is no separate Anthropic Messages API surface in the app today. OpenAI
  `whisper-1` audio transcription in the Telegram bot is a separate modality
  and is intentionally unchanged.
- DeepSeek-only wire fields (for example `thinking`) are gated on the resolved
  endpoint being DeepSeek for direct client paths, so an explicitly configured
  OpenAI/custom provider never receives them. Service-paid Edge paths
  (`_shared/deepseek.ts`, `chat-proxy`) always force them.
- Apply the same legacy-id normalization and top-level thinking control in
  every new server-side path; see
  `infra/supabase/functions/_shared/deepseek.ts`.
- This snapshot should be updated whenever a new call site, endpoint, key
  resolver, or quota bucket is added.
