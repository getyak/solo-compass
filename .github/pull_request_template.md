<!--
Thanks for the PR. Read CONTRIBUTING.md and CLAUDE.md if you haven't.
Skip sections that don't apply.
-->

## What

<!-- One sentence: what does this PR change? -->

## Why

<!-- One paragraph: what problem does this solve? Link the issue. -->

Closes #

## Three-pillar check

Before merging, confirm this change respects:

- [ ] **Map-First** — does not move users away from the map without strong reason
- [ ] **Experience-as-Unit** — does not introduce "place" / "POI" concepts at the domain level
- [ ] **AI doesn't decide** — recommendations remain options + reasons, not single answers

If any is violated, explain in **Why** above why an exception is justified.

## Schema impact

<!-- Did you add/remove/rename a field in packages/core? If yes, the iOS app must mirror. -->

- [ ] No schema change
- [ ] Schema changed — updated TS schema in `packages/core/` to match Swift changes (or vice-versa)
- [ ] Schema changed; iOS parity tracking issue: #

## Testing

<!-- How did you verify? -->

## Screenshots / video

<!-- If UI change. -->
