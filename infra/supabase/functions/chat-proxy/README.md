# chat-proxy

Pro-tier proxy for the DeepSeek `/chat/completions` endpoint. Lets the iOS
app use voice agent / explanation / synthesis without bundling
`DEEPSEEK_API_KEY` in the IPA.

## Deploy

```bash
# from infra/supabase
supabase link --project-ref <ref>
supabase secrets set DEEPSEEK_API_KEY=<sk-…>
# optional — defaults to https://api.deepseek.com/v1
supabase secrets set DEEPSEEK_BASE_URL=https://api.deepseek.com/v1
supabase functions deploy chat-proxy
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided automatically
by the Supabase runtime.

## Contract

`POST /functions/v1/chat-proxy` — Authorization: `Bearer <user_jwt>`.

Request body is OpenAI-compatible (the iOS `AIService` already builds it):

```json
{
  "model": "deepseek-flash",
  "messages": [{ "role": "user", "content": "…" }],
  "tools": [
    /* function defs */
  ],
  "tool_choice": "auto",
  "stream": true,
  "max_tokens": 512,
  "temperature": 0.3,
  "kind": "voice"
}
```

`kind` is Solo-Compass-only metadata used to pick the daily quota bucket
(see `QUOTA` in `index.ts`). It is stripped before forwarding to DeepSeek.

The server owns routing: it **ignores the client `model`** and always
forwards `model=deepseek-flash`, and always sets a **top-level**
`thinking: {"type":"disabled"}` field (DeepSeek V4.1 defaults thinking to high;
the on-device tool loop does not retain `reasoning_content`). An older or
malicious client sending `model=claude-sonnet-4-6` or `thinking.type=enabled`
still reaches DeepSeek as Flash with thinking disabled. `extra_body` is never
used. Explicit OpenAI/custom provider support belongs to configured direct
client paths, not this service-paid proxy.

## Auth + Entitlement

| Status | Meaning                                                |
| ------ | ------------------------------------------------------ |
| 401    | Missing / invalid JWT                                  |
| 402    | `profiles.entitlement_tier` is `free` or `pro_expired` |
| 429    | Daily kind-quota exceeded for this user                |
| 502    | DeepSeek upstream error                                |

The entitlement tier is kept in sync with the StoreKit outbox by the
trigger in `0002_subscription_to_profile.sql`.

## Streaming

When `stream: true`, the upstream SSE body is piped through unchanged,
so the iOS `AsyncThrowingStream<StreamEvent>` parser in
`AIService.sendAgentMessageStreaming` consumes the same `data: …` lines
it would see from a direct DeepSeek call.

## Verify

```bash
curl -N \
  -H "Authorization: Bearer <user_jwt>" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"hi"}],"stream":true,"kind":"voice"}' \
  https://<project-ref>.supabase.co/functions/v1/chat-proxy
```
