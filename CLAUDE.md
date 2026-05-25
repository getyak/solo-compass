# Solo Compass — Claude Code Project Guidelines

## Overview

Solo Compass: a map-first companion app for solo travelers. The core unit is `Experience` (not `Place`); the map is the home screen.

## Tech Stack

### Monorepo

| Layer           | Choice                                               | Notes                                                               |
| --------------- | ---------------------------------------------------- | ------------------------------------------------------------------- |
| Package manager | **pnpm 9.12.0** workspaces + **turbo**               | `engines.node >=20`. iOS app is **not** a workspace member          |
| TypeScript      | `strict: true`, `noUncheckedIndexedAccess: true`     | Don't relax. `interface` for object shapes, `type` for unions       |
| IDs             | **Branded types** (`UserId`, `ExperienceId`)         | Never plain `string`                                                |
| Geo coords      | `[longitude, latitude]` (GeoJSON / Mapbox / PostGIS) | Convert at the boundary when integrating Google APIs (`[lat, lng]`) |
| Time            | ISO 8601 UTC at storage; local at display            | `bestTimes` uses 0–23 hour ints in the **experience's** local time  |
| Commits         | Conventional Commits, lowercase scope                | See `CONTRIBUTING.md`                                               |

### Apps & Packages

```
apps/
  web/    Next.js (App Router)
  bot/    Telegraf (Telegram bot)
  ios/    SwiftUI + MapKit — Xcode-managed, NOT in pnpm workspaces
packages/
  core/   Schema (experience.ts, confidence.ts, solo-score.ts, geo.ts, user.ts) — no UI deps
  ai/     Recommendation + extraction prompts
  data/   Seed loaders, fixtures
```

### iOS App (`apps/ios/SoloCompass/`)

| Layer        | Choice                                                       | Notes                                                                                                                                                |
| ------------ | ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Platform     | **iOS 17.0+**, Swift 5.10                                    | Single Xcode target `SoloCompass.app`. SwiftPM deps kept minimal: `supabase-swift` (sync backend), `sentry-cocoa` (crash & error tracking)           |
| Project gen  | **xcodegen** from `apps/ios/project.yml`                     | Regenerate after editing the yml; don't hand-edit `.xcodeproj`                                                                                       |
| UI           | SwiftUI + **MapKit**                                         | `CompassMapView` is the root — no tabs, no drawer                                                                                                    |
| State        | `@Observable` + `@MainActor` services                        | `SWIFT_STRICT_CONCURRENCY: complete` is on                                                                                                           |
| Architecture | MVVM                                                         | `Views/{Map,Experience,Filter,Shared}` / `Models/` / `Services/` / `ViewModels/`                                                                     |
| Voice        | `SFSpeechRecognizer` + `AVAudioEngine`                       | `VoiceService.swift` streams partial transcripts via `AsyncThrowingStream`                                                                           |
| Location     | `CLLocationManager` + `CLCircularRegion` (200m, ≤20 regions) | `LocationService.shared`                                                                                                                             |
| AI           | Anthropic Messages API direct                                | `AIService.swift`, model `claude-opus-4-7`, key from `Secrets.plist` or `ANTHROPIC_API_KEY` env. Falls back to Solo-Score ranking when key is absent |
| Seed data    | `Resources/JSON/seed_experiences.json` (bundle)              | Falls back to `ExperienceService.hardcodedSeed` for previews/tests                                                                                   |
| Localization | `NSLocalizedString` from day 1                               | All user strings in `Resources/en.lproj/Localizable.strings`                                                                                         |
| Telemetry    | **sentry-cocoa** via SwiftPM                                 | `SentryService.bootstrap()` in `SoloCompassApp.init`; DSN from `Secrets.sentryDSN` (build-time inject); empty DSN → SDK never starts (no-op)         |

## Project Structure

```
solo-compass/
  apps/
    ios/SoloCompass/
      App/         SoloCompassApp (entry)
      Views/       Map, Experience, Filter, Shared
      ViewModels/  MapViewModel, ExperienceDetailViewModel
      Models/      Experience, UserPreferences
      Services/    Experience, AI, Location, Voice
      Resources/   Info.plist, Assets, JSON, en.lproj
      Tests/       SoloCompassTests (XCTest)
    web/           Next.js
    bot/           Telegraf
  packages/        core, ai, data
  scripts/
    ralph/         Autonomous AI dev loop (prd.json, ralph.sh)
    check-swift-parity.ts   TS↔Swift schema parity guard
    seed-load.ts            Seed loader
  docs/            PRODUCT_BRIEF, PHASES
```

## Coding Conventions

### TypeScript / Web / Bot

- Don't disable `strict` or `noUncheckedIndexedAccess`
- Branded types for all IDs
- Coords are `[lon, lat]` — never mix conventions inside one module

### Swift / iOS

- `@MainActor final class` for services and view models
- `guard let` / `throws` — no force-unwraps in production paths
- SwiftUI `#Preview` for every view
- ViewModels and Services should have unit tests (`apps/ios/SoloCompass/Tests/`)
- All user-facing strings via `NSLocalizedString`

## Useful Commands

```bash
# TS workspace
pnpm install
pnpm typecheck
pnpm test
pnpm format
pnpm parity:check        # verify TS↔Swift schema parity

# iOS
cd apps/ios
xcodegen                 # regenerate SoloCompass.xcodeproj from project.yml
xcodebuild build \
  -project SoloCompass.xcodeproj -scheme SoloCompass \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
xcodebuild test \
  -project SoloCompass.xcodeproj -scheme SoloCompass \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'

# Ralph autonomous dev
cd scripts/ralph && ./ralph.sh --tool claude 12
```

## CI

- `.github/workflows/ios-ci.yml` — schema parity → build → test on `macos-latest`
- `.github/workflows/ci.yml` — TS lint / typecheck / test
- `.github/workflows/testflight.yml` — TestFlight upload on tagged release
- `.github/workflows/update-changelog.yml` — auto changelog

## Testing

**iOS**: XCTest target `SoloCompassTests` (default sim: iPhone 17 Pro, iOS latest). Always start the Simulator in the background — never let it occupy the foreground terminal.

**TS**: per-package `pnpm test` via turbo.

Before marking a task complete:

1. Build affected target (`pnpm typecheck` for TS, `xcodebuild build` for iOS)
2. Run the relevant tests
3. For schema changes touching `packages/core/src/experience.ts`, run `pnpm parity:check`
4. For iOS UI changes, launch in Simulator and verify visually — `#Preview` alone is insufficient

## Skill Routing

When the user's request matches an available skill, invoke it via the Skill tool as your FIRST action.

| Trigger                                                | Skill                              |
| ------------------------------------------------------ | ---------------------------------- |
| Product ideas, brainstorming, "is this worth building" | `office-hours`                     |
| Bugs, errors, "why is this broken"                     | `investigate`                      |
| Ship, deploy, push, create PR                          | `ship`                             |
| QA, find bugs, test the site                           | `qa`                               |
| Code review, check my diff                             | `review`                           |
| Update docs after shipping                             | `document-release`                 |
| Architecture review                                    | `plan-eng-review`                  |
| Visual audit, design polish                            | `design-review`                    |
| Save / resume progress                                 | `context-save` / `context-restore` |
| Code quality, health check                             | `health`                           |
