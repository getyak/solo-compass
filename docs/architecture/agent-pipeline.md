# Agent Pipeline — Architecture Decision

**Status:** DECIDED — Delete AgentRouter now (`delete-now`)
**Date:** 2026-05-21
**Scope:** `apps/ios/SoloCompass/Services/Agents/AgentRouter.swift` and `Services/FeatureFlags.agentRouterEnabled`

---

## Current State

### What exists

The codebase contains a three-stage intent pipeline:

```
User text
  └─ IntentAgent   → Intent enum (FindExperience | GetRecommendation | ChangeSettings | SmallTalk)
       └─ QueryAgent   → ExperienceFilter (for discovery intents only)
            └─ GuideAgent  → streamed reply tokens
```

`AgentRouter.swift` (183 lines) orchestrates these three agents, maintains conversation history as `[AgentTurn]`, emits UI state via `@Observable`, and synthesises responses to text-to-speech.

`FeatureFlags.agentRouterEnabled` is defined as a Bool that reads from the environment variable `FF_AGENT_ROUTER_ENABLED`, a `FeatureFlags.plist` entry, or defaults to `true`.

### What is actually wired up

**`FeatureFlags.agentRouterEnabled` has NO production effect.**

The flag is declared but never read in any production code path. There is no conditional branch anywhere in the codebase that checks this flag and routes traffic to `AgentRouter`. The flag comment even documents the intended switch ("When true, AgentRouter is used in place of the legacy VoiceAgentOrchestrator") but the switch was never implemented.

`AgentRouter` itself is:

- Never instantiated in production code.
- Not referenced from any `View`, `ViewModel`, or `Service` outside of tests.
- Covered by `AgentRouterTests` (6 cases) and `PerformanceTests` (P95 latency benchmark) — both of which exercise the class directly without going through the feature flag.

### Active production pathways

| User action             | Pathway                                                                              |
| ----------------------- | ------------------------------------------------------------------------------------ |
| Voice input / ChatSheet | `VoiceAgentOrchestrator` → `AIService.sendAgentMessage()` tool-use loop              |
| Explore Here (map)      | `MapViewModel.exploreHere()` → `AIService.synthesizeExperiences()`                   |
| Synthesis routing       | `FeatureFlags.routeAIThroughEdge && .backendSync` → Supabase Edge or direct DeepSeek |

`AgentRouter`, `IntentAgent`, `QueryAgent`, and `GuideAgent` are **dead code** relative to every active production code path.

---

## Decision: `delete-now`

**Remove `AgentRouter` and the three pipeline agents in the next cleanup story.**

### Rationale

1. **The flag defaulting to `true` is misleading.** A reader encounters `FeatureFlags.agentRouterEnabled = true` and reasonably concludes the router is active. It is not. This is a silent correctness hazard.

2. **VoiceAgentOrchestrator already covers the same intent space.** The orchestrator drives a `think → tool_execute → repeat` loop over `AIService`, handles all four user-intent categories via tool routing (`VoiceAgentToolRouter`), and is the battle-tested path wired to the actual UI. There is no functionality gap to fill by also shipping AgentRouter.

3. **The pipeline agents duplicate logic already in AIService.** `QueryAgent` does filter extraction; `AIService.processVoiceIntent` already returns a `filterSuggestion`. `GuideAgent` streams recommendations; the orchestrator already streams via `sendAgentMessageStreaming`. Maintaining two parallel stacks multiplies future change cost.

4. **No active rollout plan.** `FF_AGENT_ROUTER_ENABLED` has no associated story, milestone, or product spec calling for its activation. Keeping it is not a strategic hedge — it is accumulating technical debt with no exit date.

5. **Tests are unit-isolated and do not validate real integration.** The existing `AgentRouterTests` stub all three agents. Passing tests do not prove the router would work when wired into the UI, so their presence is not a reason to preserve the code.

### What to delete in the follow-up story

| File                                     | Action                                |
| ---------------------------------------- | ------------------------------------- |
| `Services/Agents/AgentRouter.swift`      | Delete                                |
| `Services/Agents/IntentAgent.swift`      | Delete (no non-router callers)        |
| `Services/Agents/QueryAgent.swift`       | Delete (no non-router callers)        |
| `Services/Agents/GuideAgent.swift`       | Delete (no non-router callers)        |
| `Services/Agents/AgentMessage.swift`     | Delete (types only used by the above) |
| `Services/FeatureFlags.swift`            | Remove `agentRouterEnabled` property  |
| `Tests/AgentTests.swift`                 | Remove `AgentRouterTests` class       |
| `Tests/PerformanceTests.swift`           | Remove AgentRouter benchmark          |
| `Resources/en.lproj/Localizable.strings` | Remove `agent.router.*` fallback keys |

### What to keep

`VoiceAgentOrchestrator`, `AIService`, and the existing `FeatureFlags` properties that do have production effect (`backendSync`, `routeAIThroughEdge`, `localAIFallback`) are unaffected.

---

## Migration steps (for the follow-up story)

1. Open `Services/FeatureFlags.swift`; delete the `agentRouterEnabled` computed property.
2. Delete `Services/Agents/AgentRouter.swift`, `IntentAgent.swift`, `QueryAgent.swift`, `GuideAgent.swift`, `AgentMessage.swift`.
3. Delete `AgentRouterTests` class from `Tests/AgentTests.swift`; delete AgentRouter benchmark from `Tests/PerformanceTests.swift`.
4. Remove the `agent.router.*` localisation keys from `Localizable.strings`.
5. Run `xcodegen` to regenerate the project file (the deleted Swift files must be absent from `project.yml` sources first).
6. Build and test: `xcodebuild build` then `xcodebuild test`. Confirm zero references remain via `grep -r "AgentRouter\|agentRouterEnabled\|IntentAgent\|QueryAgent\|GuideAgent\|AgentMessage" apps/ios`.

No runtime behavior changes — these files are unreachable from production code today.

---

## Alternatives considered

### `integrate-later` — wire AgentRouter into ChatSheet behind the flag

**Rejected.** This would require: implementing the `if FeatureFlags.agentRouterEnabled` branch in the UI layer, ensuring `AgentRouter` has access to `LocationService` and `ExperienceService` (currently absent from its constructor), resolving the duplicated filter-extraction logic between `QueryAgent` and `AIService.processVoiceIntent`, and running a real A/B comparison against `VoiceAgentOrchestrator`. That is a substantial new feature, not a cleanup. If product decides a simpler non-tool-use pipeline is valuable, it should be scoped as a new story from a clean starting point, not revived from this stale implementation.
