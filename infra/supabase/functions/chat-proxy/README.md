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
  "model": "deepseek-chat",
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
