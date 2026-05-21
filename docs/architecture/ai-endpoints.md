# Solo Compass AI endpoint topology snapshot

This document is a topology snapshot for the current iOS AI surfaces. It is intentionally descriptive: US-022 does not change runtime routing.

## Summary

Solo Compass currently has two separate LLM endpoint families:

| Surface        | Call sites                                                                                                                        | Provider / endpoint                                                                                  | Model                                                                | Auth source                                                          | Quota                                                              |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- | -------------------------------------------------------------------- | ------------------------------------------------------------------ |
| Agent layer    | `IntentAgent`, `QueryAgent`, `GuideAgent`                                                                                         | Anthropic Messages API, `https://api.anthropic.com/v1/messages`                                      | `claude-opus-4-7` by default                                         | `ANTHROPIC_API_KEY` environment variable or explicit initializer key | No in-app quota currently enforced                                 |
| App AI service | `AIService.synthesizeExperiences`, `explainRecommendation`, `processVoiceIntent`, `sendAgentMessage`, `sendAgentMessageStreaming` | DeepSeek/OpenAI-compatible chat completions, `Secrets.resolvedDeepSeekBaseURL + "/chat/completions"` | `Secrets.resolvedDeepSeekModel`, with per-kind environment overrides | `Secrets.resolvedDeepSeekApiKey` via `AIService.resolveAPIKey()`     | Pro: synthesis/voice 30 per day, explanation 60 per day; free: 0/0 |

## Anthropic Messages API surfaces

The lightweight agent classes under `Services/Agents/` call Anthropic directly when an Anthropic key is available. Each also accepts `session`, `apiKey`, `apiURL`, and `modelName` initializer overrides for tests and controlled routing.

### `IntentAgent`

- File: `apps/ios/SoloCompass/Services/Agents/IntentAgent.swift`
- Purpose: classify a user utterance into `FindExperience`, `ChangeSettings`, `GetRecommendation`, or `SmallTalk`.
- Endpoint: `https://api.anthropic.com/v1/messages` unless `apiURL` is injected.
- Model: `claude-opus-4-7` by default.
- Key resolution: explicit initializer `apiKey`, then `ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]`.
- Headers: `x-api-key` plus `anthropic-version: 2023-06-01`.
- Fallback: local keyword/small-talk classification when key is missing or the request fails.

### `QueryAgent`

- File: `apps/ios/SoloCompass/Services/Agents/QueryAgent.swift`
- Purpose: translate a natural-language place query into an `ExperienceFilter`.
- Endpoint/model/key: same Anthropic defaults as `IntentAgent`.
- Uses Anthropic tool-calling (`extract_experience_filter`) with `claude-opus-4-7` by default.
- Fallback: local keyword extraction when key is missing or the request fails.

### `GuideAgent`

- File: `apps/ios/SoloCompass/Services/Agents/GuideAgent.swift`
- Purpose: stream warm guide/recommendation replies using context and selected experiences.
- Endpoint/model/key: same Anthropic defaults as `IntentAgent`.
- Uses server-sent streaming from Anthropic Messages API with `stream: true`.
- Fallback: deterministic stub reply when key is missing.

### Quota status for Anthropic agents

The Anthropic agent layer has no daily quota in the current code. It is only gated by key availability and request failure fallback behavior.

## DeepSeek chat-completions surfaces

`AIService` is the app-level AI service. It talks to DeepSeek through an OpenAI-compatible `/chat/completions` endpoint.

### Endpoint and model resolution

- File: `apps/ios/SoloCompass/Services/AIService.swift`
- Endpoint: `Secrets.resolvedDeepSeekBaseURL`, with one trailing slash stripped, plus `/chat/completions`.
- Model: `Secrets.resolvedDeepSeekModel`.
- Per-kind model overrides:
  - `DEEPSEEK_MODEL_SYNTHESIS`
  - `DEEPSEEK_MODEL_EXPLANATION`
  - `DEEPSEEK_MODEL_VOICE`

### Key resolution

`AIService.resolveAPIKey()` resolves the DeepSeek key via `Secrets.resolvedDeepSeekApiKey`; if that returns a non-empty value it is used for all DeepSeek calls. `Secrets` resolves runtime/user defaults and generated/environment-backed configuration before exposing that value.

DeepSeek calls use an OpenAI-style bearer token header:

```text
Authorization: Bearer <DeepSeek key>
```

### `synthesizeExperiences`

- Kind: `.synthesis`.
- Endpoint: DeepSeek `/chat/completions`.
- Purpose: turn nearby POIs/context into generated `Experience` candidates.
- Quota bucket: synthesis.

### `explainRecommendation`

- Kind: `.explanation`.
- Endpoint: DeepSeek `/chat/completions`.
- Purpose: produce a concise explanation for a recommended experience.
- Quota bucket: explanation.

### `processVoiceIntent`

- Kind: `.voice`.
- Endpoint: DeepSeek `/chat/completions`.
- Purpose: parse a transcript plus nearby curated experiences into recommended IDs, explanation text, and an optional filter suggestion.
- Quota bucket: synthesis/voice.

### `sendAgentMessage`

- Kind: `.voice`.
- Endpoint: DeepSeek `/chat/completions`.
- Purpose: non-streaming voice-agent turn with OpenAI-compatible tool definitions and tool-call parsing.
- Quota bucket: synthesis/voice.

### `sendAgentMessageStreaming`

- Kind: `.voice`.
- Endpoint: DeepSeek `/chat/completions` with `stream: true`.
- Purpose: streaming voice-agent turn that emits content deltas and accumulated tool calls.
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

For free users, both quota buckets are zero; the paywall is still the primary gate, and the AIService quota is a second line of defense.

Anthropic `IntentAgent`, `QueryAgent`, and `GuideAgent` calls are not counted in this quota system today.

## Refactor notes

- Do not assume every AI call goes through `AIService`; the agent classes still call Anthropic directly.
- Do not replace `ANTHROPIC_API_KEY` with a DeepSeek key in `IntentAgent`, `QueryAgent`, or `GuideAgent` without a deliberate migration.
- Do not route `AIService` through Anthropic unless quota, model, headers, parser shape, and tests are updated together.
- This snapshot should be updated whenever a new call site, endpoint, key resolver, or quota bucket is added.
