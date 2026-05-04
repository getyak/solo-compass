# @solo-compass/ai

Prompts, recommendation engine, Claude wrappers.

## Responsibilities
- System prompts for **experience generation** (raw sources → structured Experience)
- System prompts for **recommendation** (user context + candidate pool → ranked picks with reasons)
- Voice intent parser (30s audio → structured query)
- User-shared experience structuring (voice memo → CandidateExperience)

## What does NOT live here
- Direct UI rendering of recommendations (apps do that)
- Persistence (that's `packages/data`)
- Domain types (those are `packages/core`)

## Status
🚧 Skeleton only. Prompts under design — see [`docs/AI_PROMPTS.md`](../../docs/AI_PROMPTS.md).
