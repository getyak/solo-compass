# CLAUDE.md

> Project memory for Claude Code and other AI coding agents working in this repo.

## What this project is

**Solo Compass** is a map-first, experience-as-unit, AI-curated companion app for solo travelers. The core unit is `Experience`, not `Place`. The map is the home screen, not a feature.

Read these first when picking up a task:

1. `docs/PRODUCT_BRIEF.md` — the *why*
2. `docs/PHASES.md` — what we're building *now*
3. `packages/core/src/experience.ts` — the schema everything orbits

## Repository conventions

### Monorepo
- `pnpm` workspaces + `turbo` for tasks.
- `packages/*` — platform-agnostic, no UI deps.
- `apps/*` — apps. Web (Next.js), iOS (Swift, Xcode-managed, NOT in pnpm workspaces), Bot (Telegraf).

### TypeScript
- `strict: true`, `noUncheckedIndexedAccess: true`. Don't disable.
- Prefer `interface` for object shapes, `type` for unions.
- All IDs are branded types (`UserId`, `ExperienceId`). Never `string`.

### Geo
- Coordinates are `[longitude, latitude]` (GeoJSON / Mapbox / PostGIS convention).
- **Never** mix with `[lat, lng]` (Google Maps convention). When integrating with Google APIs, convert at the boundary.

### Time
- Storage: ISO 8601 strings, UTC.
- Display: local to the user's current city.
- Best-time windows for experiences use 0–23 hour ints in *local time of the experience's city*.

### Commit messages
- Conventional Commits, lowercase scope.
- Examples in `CONTRIBUTING.md`.

## iOS App Conventions

### Architecture: `apps/ios/SoloCompass/`
- SwiftUI + MapKit, target iOS 17.0+, MVVM with `@Observable`
- Zero third-party deps — Swift native APIs only
- Structure: `App/`, `Views/{Map,Experience,Filter,Shared}`, `Models/`, `Services/`, `ViewModels/`, `Resources/`

### Code Standards (iOS/Swift)
- Use `guard let` and `throws`, NO force unwraps in production paths
- SwiftUI previews for every view
- Unit tests for ViewModels and Services
- Localization-ready: use `NSLocalizedString` from day 1
- All user-facing strings in `Resources/en.lproj/Localizable.strings`

### CI/CD (GitHub Actions)
- `.github/workflows/ios-ci.yml`: build + test + SwiftLint on push/PR
- `scripts/ralph/`: autonomous AI dev loop (`ralph.sh --tool claude`)
- Ralph uses `prd.json` (12 user stories) with `passes` gates

## How to think about changes

### The three-pillar test
Before suggesting any feature or change, ask:

1. **Does it respect Map-First?** The map is the home screen. Tabs, drawers, side menus, modal flows that take the user away from the map without a strong reason — get pushed back.
2. **Does it respect Experience-as-Unit?** We don't store "places". We store "things worth doing".
3. **Does it respect AI-doesn't-decide?** AI filters from many to few. AI explains. Never a single answer with no alternatives.

### The privacy posture
- No real names required. Background location is opt-in.
- "Other solo travelers nearby" surfaces *count* and *aggregated traces*, never identities.
- No photos required. Never asks for emergency contact, government ID, or social graph.

## When stuck or unsure

- Open a GitHub issue describing the question. Don't ship code that depends on an answer the team hasn't given.
- If you find yourself adding a field to `Experience`, post the proposal as a comment on a tracking issue first. The schema is the moat.

## Things I (Claude) should never do here

- Add a "social feed" of any kind. Add a points/leaderboard system.
- Add features that pressure the user to share, post, invite, or rate.
- Optimize for "engagement metrics." Optimize for week-1 retention.
- Generate seed experiences and commit them to the public repo. Seeds are curated and live in a private repo.

## Useful commands

```bash
pnpm install          # install TS workspace
pnpm typecheck        # type-check whole graph
pnpm format           # format

# Ralph autonomous dev
cd scripts/ralph && ./ralph.sh --tool claude 12
```
