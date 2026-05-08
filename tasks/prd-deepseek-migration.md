# Migration Design: Anthropic Claude → DeepSeek

**Type:** Architecture Decision Record (ADR) / Technical Migration Design
**Status:** Proposed (awaiting implementation)
**Date:** 2026-05-08
**Author:** Xinwei Xiong
**Decision Reference:** Conversation thread 2026-05-08, branch `feat/ios-settings-survey-checkin`

---

## 1. Context

Solo Compass currently uses **Anthropic Claude (`claude-opus-4-7`)** as its sole AI provider across three integration points:

| Integration         | File                                              | Purpose                                                                            |
| ------------------- | ------------------------------------------------- | ---------------------------------------------------------------------------------- |
| iOS recommendations | `apps/ios/SoloCompass/Services/AIService.swift`   | Voice intent → ranked experience IDs; one-sentence "why this matters" explanations |
| TS ranking          | `packages/ai/src/prompts/rank-experiences.ts`     | Bot + Web → top-3 experiences for a user intent                                    |
| TS structuring      | `packages/ai/src/prompts/structure-experience.ts` | Source-text (Wikivoyage / Reddit / blog) → structured `Experience` record          |

The decision to migrate was driven by two converging forces:

1. **Cost.** `claude-opus-4-7` lists at ~$15/M input + $75/M output tokens. Solo Compass intends to run continuous source-compilation pipelines (Data Engine v2 — see `tasks/prd-data-engine-v2.md`); at current Claude pricing, a single-city compile run is in the dollars-per-run range. DeepSeek's `deepseek-v4-pro` is approximately **two orders of magnitude cheaper** ($0.27/M input + $1.10/M output, ~50× cheaper input, ~70× cheaper output).
2. **Toolchain alignment with sibling project.** The author's other production iOS app (`daypage`, also in `~/data/mine/cubxxw/personal/`) already runs on DeepSeek via a mature `.env` → `generate_secrets.sh` → `GeneratedSecrets.swift` pipeline, with runtime UserDefaults override for user-supplied keys. Reusing that pattern reduces cognitive overhead across the author's projects and lets both apps share secret-management mental models.

DeepSeek is **OpenAI protocol-compatible** (`POST /v1/chat/completions`, `Authorization: Bearer …`, identical request/response schema), which means the migration is mechanically tractable: drop in the `openai` SDK pointed at `https://api.deepseek.com/v1`. No new transport code is required.

The trade-off is **prompt portability**. Anthropic's tool-use API is a structured JSON-output mechanism distinct from OpenAI function calling. The current Solo Compass prompts (`structure-experience.ts`, `rank-experiences.ts`) lean on Claude's tool-use to enforce schema. DeepSeek supports OpenAI function calling but, per community reports and `daypage`'s own implementation choice, JSON mode (`response_format: { type: "json_object" }`) + a strict system prompt is the more rugged path. We follow `daypage`.

---

## 2. Decision

### 2.1 Provider & Model

- **Provider:** DeepSeek (https://platform.deepseek.com)
- **Protocol:** OpenAI-compatible chat completions (`/v1/chat/completions`)
- **Model identifier:** `deepseek-v4-pro` (matches `daypage`; pass through verbatim — if unrecognized, swap to `deepseek-chat` per DeepSeek's then-current model catalog)
- **Output mode:** JSON mode via `response_format: { type: "json_object" }`, paired with a system prompt that explicitly forbids markdown fences and prose outside the JSON object
- **Defensive parsing:** every consumer must strip ` ```json … ``` ` fences before `JSON.parse` — DeepSeek occasionally emits them despite `response_format`, observed in `daypage` production

### 2.2 Secret Management (iOS)

Adopt **the `daypage` model verbatim**:

```
.env (gitignored, project root)
  ↓ scripts/generate_secrets.sh  (Xcode "Pre-build" Run Script Phase)
  ↓
apps/ios/SoloCompass/Config/GeneratedSecrets.swift  (gitignored)
  enum Secrets {
    static let deepSeekApiKey: String = "..."
    static let deepSeekBaseURL: String = "..."
    static let deepSeekModel: String = "..."
  }
  ↑
SecretsRuntime.swift  (committed; runtime override layer)
  extension Secrets {
    static var resolvedDeepSeekApiKey: String {
      UserDefaults.standard.string(forKey: ...) ?? deepSeekApiKey
    }
  }
```

- **No `Secrets.plist` fallback retained.** The legacy plist path in `AIService.swift:174-199` is removed. Single source of truth, less code to reason about. (Q1 = A.)
- **User-supplied API key in Settings.** Following `daypage`, the iOS Settings page exposes a "DeepSeek API Key" text field. Stored in `UserDefaults` under a stable key (e.g. `runtimeDeepSeekKey`). `SecretsRuntime.resolvedDeepSeekApiKey` resolves UserDefaults > GeneratedSecrets, so user-supplied keys win. (Q2 = A.)
  - Rationale: enables open-source distribution and TestFlight users to supply their own keys without shipping the author's key in the binary.

### 2.3 Secret Management (Node — bot/web)

bot and web read `process.env.DEEPSEEK_API_KEY` / `DEEPSEEK_BASE_URL` / `DEEPSEEK_MODEL` directly. No code generation. Local dev: `.env` at repo root (loaded by Next.js automatically; `apps/bot` should `import "dotenv/config"` at startup if it doesn't already).

### 2.4 Test Strategy

- Existing unit tests (`__tests__/rank-experiences.test.ts`, `structure-experience.test.ts`) are **rewritten** to mock the OpenAI SDK shape (`choices[0].message.content` JSON string) instead of Anthropic's `content[].type === "tool_use"` shape.
- Existing `__golden__/*.json` files are **deleted**. They captured Claude's tool-use output and are now schema-incompatible.
- Replacement golden files will be generated **after this PR** by running `LIVE_API=true pnpm --filter @solo-compass/ai test:live` against real DeepSeek with a valid `.env`. Tracked as a follow-up task, not a blocker for the migration PR.
- Mock-based unit tests (anti-hallucination, score clamping, refusal handling) continue to provide protection in the meantime.

### 2.5 CI Strategy

- `.github/workflows/ios-ci.yml` injects an **empty placeholder `.env`** before the build step:
  ```yaml
  - run: |
      cat > .env <<EOF
      DEEPSEEK_API_KEY=
      DEEPSEEK_BASE_URL=https://api.deepseek.com/v1
      DEEPSEEK_MODEL=deepseek-v4-pro
      DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM
      EOF
  ```
- `generate_secrets.sh` runs successfully against an empty key → `GeneratedSecrets.deepSeekApiKey = ""` → `AIService` raises `missingAPIKey` at first AI call → callers fall back to local Solo-Score ranking. Build, type-check, and unit tests all pass.
- **No real keys in CI.** The author's real DeepSeek key never enters GitHub Actions. (Q3 = A.)

### 2.6 Multi-Provider Abstraction — _Explicitly Rejected_

We do **not** introduce an `AIProvider` interface or pluggable backend layer. Reasons:

1. YAGNI — there is no current second consumer of an abstraction
2. The migration to DeepSeek is intended as a permanent replacement, not a feature flag
3. An abstraction layer would lock in the lowest common denominator of Anthropic + OpenAI-compatible APIs, costing capability without buying anything Solo Compass needs today
4. If a future need arises (e.g., on-device inference, fallback to Claude during outage), revisit then

Anthropic-specific code (`@anthropic-ai/sdk` import, `claude-opus-4-7` model strings, tool-use schemas, `Anthropic.Usage` types) is **fully removed**, not commented out or feature-flagged.

---

## 3. Trade-offs & Risks

| Risk                                                                     | Likelihood                  | Impact     | Mitigation                                                                                                                                                                                                                                                                |
| ------------------------------------------------------------------------ | --------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| DeepSeek output quality drops vs. Claude on edge prompts                 | Medium                      | Medium     | Anti-hallucination unit tests still enforce ID validity, score clamping, refusal handling. Live golden replay test (post-migration) catches regressions on real fixtures.                                                                                                 |
| `deepseek-v4-pro` model name is unrecognized at API call time            | Low-Medium                  | Low        | `.env` is the single source — swap to `deepseek-chat` and rebuild. No code change required.                                                                                                                                                                               |
| DeepSeek wraps JSON in markdown fences despite `response_format`         | Medium                      | Low        | Defensive fence-stripping in `parseRankedJSON` / `parseStructureJSON` before `JSON.parse`. Pattern proven in `daypage`.                                                                                                                                                   |
| Sibling-project `.env` was leaked in this conversation thread            | **High (already happened)** | **High**   | **Author must rotate** the four leaked keys post-merge. **Solo Compass repo never receives those keys** — only placeholders in `.env.example`.                                                                                                                            |
| First-run users on iOS without API key see no AI features                | High                        | Low        | Existing Solo-Score local-fallback ranking already handles `missingAPIKey`. Onboarding will be updated (Phase 2 of follow-up work) to invite users to supply their own DeepSeek key in Settings.                                                                          |
| Breaking change for any external consumers of `@solo-compass/ai`         | Low                         | Low        | The published exports (`rankExperiences`, `structureExperience`, `parseIntent`) keep their input/output signatures. Only the optional `client?` parameter changes type from `Anthropic` to `OpenAI`. No external consumer exists outside this monorepo (`grep` confirms). |
| Existing `__golden__` test suite fails between deletion and regeneration | Certain                     | Low        | Acknowledged. The structure-experience test file is rewritten to mock OpenAI's response shape; mock-based tests still pass. Live-replay tests are explicitly opt-in via `LIVE_API=true`.                                                                                  |
| `cost-tracker.ts` warning threshold ($5/call) is no longer meaningful    | Certain                     | Negligible | At DeepSeek prices, $5 implies ~18M input or ~4.5M output tokens — astronomical for a single ranking call. Threshold left at $5 as a sanity guard against runaway loops.                                                                                                  |

---

## 4. Migration Plan

Five sequential commits on `feat/ios-settings-survey-checkin` (or a new `feat/deepseek-migration` branch — author's choice).

### Commit 1 — `chore: env template + gitignore generated secrets`

| Action  | File                                                                                                                       |
| ------- | -------------------------------------------------------------------------------------------------------------------------- |
| Rewrite | `.env.example` — replace Anthropic block with DeepSeek; keep Mapbox/Supabase/Telegram intact                               |
| Append  | `.gitignore` — add `apps/ios/SoloCompass/Config/GeneratedSecrets.swift` and `apps/ios/SoloCompass/Resources/Secrets.plist` |

### Commit 2 — `feat(ai): switch packages/ai from Anthropic to DeepSeek (JSON mode)`

| Action  | File                                                                                                                       |
| ------- | -------------------------------------------------------------------------------------------------------------------------- |
| Edit    | `packages/ai/package.json` — remove `@anthropic-ai/sdk`, add `openai ^4.73.0`                                              |
| Create  | `packages/ai/src/client.ts` — DeepSeek client factory (`createDeepseekClient`, `deepseekModel`, `deepseekBaseURL`)         |
| Rewrite | `packages/ai/src/cost-tracker.ts` — DeepSeek pricing, `OpenAI.CompletionUsage` types, drop cache token fields              |
| Rewrite | `packages/ai/src/prompts/rank-experiences.ts` — JSON-mode prompt, defensive parser, `client?: OpenAI`                      |
| Rewrite | `packages/ai/src/prompts/structure-experience.ts` — JSON-mode prompt, defensive parser, refuse-via-JSON, `client?: OpenAI` |
| Edit    | `packages/ai/src/index.ts` — export `createDeepseekClient`, `deepseekModel`                                                |
| Rewrite | `packages/ai/src/__tests__/rank-experiences.test.ts` — mock OpenAI client shape                                            |
| Rewrite | `packages/ai/src/structure-experience.test.ts` — mock OpenAI client shape                                                  |
| Delete  | `packages/ai/src/__golden__/*.json` (3 files)                                                                              |
| Add     | `packages/ai/src/__golden__/.gitkeep` + comment file noting regeneration via `LIVE_API=true`                               |

### Commit 3 — `feat(ios): wire DeepSeek via .env-generated Secrets.swift`

| Action  | File                                                                                                                                                                                                                                                                                                                                                                                         |
| ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Create  | `scripts/generate_secrets.sh` — adapted from `daypage`, reads `DEEPSEEK_*` + `DEVELOPMENT_TEAM`                                                                                                                                                                                                                                                                                              |
| Create  | `apps/ios/SoloCompass/Config/GeneratedSecrets.swift` (committed initially with empty values to bootstrap; gitignored thereafter — same pattern as `daypage`'s first-time bootstrap)                                                                                                                                                                                                          |
| Create  | `apps/ios/SoloCompass/Config/SecretsRuntime.swift` — `resolvedDeepSeekApiKey` UserDefaults override                                                                                                                                                                                                                                                                                          |
| Edit    | `apps/ios/SoloCompass/project.yml` — add Pre-build Run Script Phase invoking `${SRCROOT}/../../scripts/generate_secrets.sh`                                                                                                                                                                                                                                                                  |
| Rewrite | `apps/ios/SoloCompass/Services/AIService.swift` — switch to `URLSession` POST against `Secrets.deepSeekBaseURL + "/chat/completions"`, `Authorization: Bearer …`, response shape `choices[0].message.content`. Remove all `Secrets.plist` reading code. Keep three public methods (`recommendExperiences`, `explainRecommendation`, `processVoiceIntent`) and their fallback paths verbatim. |
| Edit    | `apps/ios/SoloCompass/Resources/en.lproj/Localizable.strings` — add `ai.error.missingDeepseekKey` if needed (existing `ai.error.missingKey` may suffice)                                                                                                                                                                                                                                     |
| Add     | New Settings section — "AI Provider" with DeepSeek API key text field (write to UserDefaults under `runtimeDeepSeekKey`)                                                                                                                                                                                                                                                                     |

### Commit 4 — `chore(ci): inject placeholder .env for iOS build`

| Action | File                                                                                                  |
| ------ | ----------------------------------------------------------------------------------------------------- |
| Edit   | `.github/workflows/ios-ci.yml` — add step that writes a placeholder `.env` before `xcodegen`          |
| Edit   | `.github/workflows/testflight.yml` — same, but uses `${{ secrets.DEEPSEEK_API_KEY }}` for real builds |

### Commit 5 — `chore: regenerate pnpm-lock.yaml`

| Action     | File                                          |
| ---------- | --------------------------------------------- |
| Regenerate | `pnpm-lock.yaml` after running `pnpm install` |

---

## 5. Rollback Strategy

If post-merge testing reveals DeepSeek output is unusable (catastrophic quality drop, sustained API outage, model deprecation), rollback steps:

1. `git revert` Commits 2 + 3 (Commit 1, 4, 5 are non-functional infra)
2. Restore `@anthropic-ai/sdk` in `packages/ai/package.json`
3. Restore `Secrets.plist` reading in `AIService.swift` if iOS team had been using it
4. Restore `__golden__/*.json` from `git show <pre-revert-commit>:packages/ai/src/__golden__/...`
5. Re-run `pnpm install` and `xcodegen`

Estimated rollback time: **< 30 minutes** for an experienced engineer with the original commits' diffs available.

The five-commit structure is intentional: each commit is independently revertable, so partial rollback (e.g., revert iOS only, keep TS on DeepSeek) is possible.

---

## 6. Acceptance Criteria

The migration is **done** when all of the following hold:

- [ ] `grep -r "@anthropic-ai/sdk" packages apps` returns **zero** matches
- [ ] `grep -r "claude-opus" packages apps` returns **zero** matches
- [ ] `grep -r "Secrets.plist" apps/ios` returns **zero** matches
- [ ] `pnpm install && pnpm typecheck` passes for the entire monorepo
- [ ] `pnpm --filter @solo-compass/ai test` passes (golden-replay tests skipped or stubbed; mock-based tests green)
- [ ] `cd apps/ios && xcodegen && xcodebuild build -project SoloCompass.xcodeproj -scheme SoloCompass -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest'` completes
- [ ] `xcodebuild test` for `SoloCompassTests` passes
- [ ] iOS app launched in Simulator with empty `DEEPSEEK_API_KEY`: opens to map, recommendations fall back to Solo-Score (no crash, no spinner-of-death)
- [ ] iOS Settings page shows new "DeepSeek API Key" field; entering a value persists across app restart
- [ ] Manual smoke test (with real key in `.env`): rebuild, voice intent "find me coffee" returns ≥1 ranked experience with a non-empty reason string
- [ ] `.github/workflows/ios-ci.yml` green on push (using placeholder `.env`)
- [ ] `.env.example` documents all three `DEEPSEEK_*` vars with helpful comments
- [ ] No real API keys committed anywhere in the repo (`gitleaks` scan or equivalent)

---

## 7. Non-Goals (Out of Scope)

The following are **explicitly not** part of this migration:

1. **Multi-provider abstraction layer** — see §2.6
2. **Local / on-device inference** — Solo Compass continues to require an internet connection for AI features
3. **Streaming responses** — current usage is request/response only; streaming is a possible future addition for `explainRecommendation`
4. **Prompt re-engineering for DeepSeek's strengths** — system prompts are migrated near-verbatim. Quality tuning is a follow-up after observing real DeepSeek outputs
5. **Rate limiting / retry logic** — existing one-shot calls are retained. Retry/backoff is `daypage` territory but not yet justified here (`rankExperiences` is called per user gesture, not in batch)
6. **Cost dashboard / spend alerting** — `cost-tracker.ts` keeps emitting structured logs to stdout; aggregation is a deploy-time concern (Vercel / Railway log drain), not application code
7. **Re-running the Data Engine v2 compilation pipeline against DeepSeek** — that's a separate project (see `tasks/prd-data-engine-v2.md`); this PR only migrates the runtime calls
8. **Updating any web app UI** — `apps/web` only consumes `rankExperiences` server-side; no UI text change needed
9. **i18n for the new Settings section** — the existing `Localizable.strings` workflow is followed, but translation to non-English locales is a separate task

---

## 8. Technical Considerations

### 8.1 OpenAI SDK Version Pinning

`apps/bot/package.json` already pins `openai ^4.73.0`. `packages/ai` aligns to the same major to avoid duplicate copies in `node_modules`. Web does not import `openai` directly — it goes through `@solo-compass/ai`.

### 8.2 DeepSeek Quirks to Watch

Documented in the `daypage` codebase and to be ported to Solo Compass:

- `response_format: { type: "json_object" }` is **necessary but not sufficient** — system prompt must also forbid fences explicitly
- DeepSeek may return `"finish_reason": "length"` if `max_tokens` is too low for a JSON schema with many fields. `structure-experience` keeps the existing `max_tokens: 2048`; `rank-experiences` keeps `1024`. Increase if real-world testing shows truncation.
- DeepSeek's `usage.prompt_tokens` is reliable; `completion_tokens` matches OpenAI semantics; no `cache_*` fields exist (unlike Anthropic prompt caching, which `cost-tracker.ts` was tracking).

### 8.3 GeoJSON Convention Preserved

All coordinate handling stays `[longitude, latitude]` per `CLAUDE.md` and `packages/core/src/geo.ts`. The migration touches only the LLM layer; no geo conversions are introduced or removed.

### 8.4 iOS `@Observable` Concurrency Boundaries

`AIService` remains an `@Observable final class` with `@MainActor`-isolated `isProcessing` / `lastError`. The DeepSeek call site in `sendMessage` is unchanged structurally — only the URL, headers, body shape, and response parsing change. `SWIFT_STRICT_CONCURRENCY: complete` continues to compile.

### 8.5 Error Surface

| iOS error                       | Source                                       | User-visible                                                                   |
| ------------------------------- | -------------------------------------------- | ------------------------------------------------------------------------------ |
| `AIError.missingAPIKey`         | `Secrets.resolvedDeepSeekApiKey.isEmpty`     | Localized `ai.error.missingKey` shown, recommendation falls back to Solo-Score |
| `AIError.requestFailed(401, …)` | DeepSeek auth rejected                       | Localized `ai.error.request %d`                                                |
| `AIError.requestFailed(429, …)` | DeepSeek rate limit                          | Same as above; future retry/backoff is a non-goal                              |
| `AIError.decodingFailed(…)`     | JSON parse failed even after fence-stripping | Logged; recommendation falls back to Solo-Score                                |

---

## 9. Success Metrics

Quantifiable post-migration targets to validate over the **first 30 days** after merge:

| Metric                                                       | Target                                                         | Measurement                                             |
| ------------------------------------------------------------ | -------------------------------------------------------------- | ------------------------------------------------------- |
| Per-call cost (rank-experiences, p50)                        | **≥ 50× cheaper** than Claude baseline                         | `cost-tracker.ts` stdout logs aggregated by route       |
| `rankExperiences` latency p50 (TS, server-side)              | ≤ 1.5× the Claude baseline                                     | Same logs, `duration_ms` field                          |
| `structureExperience` accept rate (model returns valid JSON) | ≥ 95% over a 100-source sample                                 | Live-API test run after PR                              |
| iOS `AIService.processVoiceIntent` success rate              | ≥ 90% (returns non-empty `recommendedIds` for relevant intent) | Manual TestFlight smoke testing across 20 voice intents |
| Build time impact (iOS)                                      | ≤ +2 seconds for `generate_secrets.sh` step                    | `xcodebuild` log timestamps                             |
| `pnpm install` time impact                                   | ≤ +5 seconds (openai SDK is already in bot's deps)             | `time pnpm install` before/after                        |
| Zero hardcoded secrets in repo                               | 100%                                                           | `gitleaks detect` clean                                 |

If any of the first three metrics misses target, treat as a quality regression and investigate prompt tuning before declaring the migration successful.

---

## 10. Open Questions

Items to resolve **during implementation** or **immediately after first deploy**:

1. **`deepseek-v4-pro` vs `deepseek-chat`** — Author's `daypage` `.env` says `v4-pro`. If DeepSeek's API rejects this name on first real call, switch to `deepseek-chat`. Verify within 1 hour of merging.
2. **Should the iOS Settings page show estimated cost per call?** `cost-tracker.ts` knows; we could surface it. Decision deferred until post-migration.
3. **Anthropic prompt-cache hit rate was being tracked.** Whether DeepSeek offers an equivalent prompt-cache mechanism is unclear from public docs (as of 2026-05-08). Cost projection assumes no caching.
4. **Rotation of leaked sibling-project secrets** — separate from this migration but **must happen** before any code derived from the sibling project ships publicly. Tracked outside the Solo Compass repo.
5. **Onboarding flow update** — should new users be prompted on first launch to enter a DeepSeek key, or do we rely on the build-time injected key for the author's own TestFlight builds and only show the Settings field for self-distributed builds? Defer until iOS Settings task is closed (#61).
6. **`apps/bot` `import "dotenv/config"`** — verify whether telegraf bot already loads `.env` on startup. If not, add it as a one-line fix in Commit 2 or a follow-up.
7. **Live-API golden file regeneration** — when does it happen, and who runs it? Suggested: author runs locally with real key after PR merges, commits new `__golden__/*.json` separately. Tracked as a follow-up issue.

---

## 11. References

- `daypage` `.env.example` — `~/data/mine/cubxxw/personal/daypage/.env.example`
- `daypage` `scripts/generate_secrets.sh` — `~/data/mine/cubxxw/personal/daypage/scripts/generate_secrets.sh`
- `daypage` `CompilationService.swift` (DeepSeek integration reference) — `~/data/mine/cubxxw/personal/daypage/DayPage/Services/CompilationService.swift`
- `daypage` `SecretsRuntime.swift` (UserDefaults override pattern) — `~/data/mine/cubxxw/personal/daypage/DayPage/Config/SecretsRuntime.swift`
- DeepSeek pricing — https://platform.deepseek.com (current as of 2026-05-08)
- OpenAI SDK (compatible client) — https://github.com/openai/openai-node
- Solo Compass `CLAUDE.md` — root of this repo
- Solo Compass conversation thread that produced this decision — 2026-05-08

---

## 12. Implementation Status

**Pre-flight (already done in this session before the PRD was written):**

- ✅ `.env.example` rewritten (Commit 1, partial)
- ✅ `.gitignore` updated (Commit 1, partial)
- ✅ `packages/ai/package.json` dependency switched (Commit 2, partial)
- ✅ `packages/ai/src/cost-tracker.ts` rewritten (Commit 2, partial)
- ✅ `packages/ai/src/client.ts` created (Commit 2, partial)

**Awaiting implementation** (per `/prd` skill rules, no further code changes are made until the PRD is reviewed):

- ⏸️ Commit 2 remainder: rewrite `prompts/*.ts`, rewrite test files, delete `__golden__/*`, update `index.ts`
- ⏸️ Commit 3: iOS — `generate_secrets.sh`, `Config/`, `project.yml`, `AIService.swift` rewrite, Settings DeepSeek-key field
- ⏸️ Commit 4: CI workflows
- ⏸️ Commit 5: pnpm-lock regeneration

The 5 already-modified files **leave the workspace in a broken intermediate state** (`packages/ai` typecheck will fail because `prompts/*.ts` still imports `@anthropic-ai/sdk`). Resolution: either continue to Commit 2 immediately after PRD review, or **do not run `pnpm typecheck`** until then.
