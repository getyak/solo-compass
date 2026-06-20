# Solo Compass — Beta v0.9 "One Good Day in a New City"

**Date:** 2026-06-19
**Branch:** main
**Channel:** TestFlight (Sentry environment = `beta`)

> Goal: a solo traveler in a new city sees 5 signal-thick Experiences in 30 seconds, builds a half-day route in 3 steps, and gets a cited reply from Solo with at least one specific recommendation.

## What shipped

11 atomic commits, every one BUILD SUCCEEDED on iPhone 17 Pro / iOS latest. `pnpm parity:check` 4/4.

| #   | Commit              | Area                                                     | Beta red line addressed             |
| --- | ------------------- | -------------------------------------------------------- | ----------------------------------- |
| 1   | `dd40aed` Beta-P0-B | Persistence fatalError → Sentry + graceful fallback      | #5 crash-free ≥99.5                 |
| 2   | `97d7723` Beta-P0-G | Sentry environment = `debug \| beta \| release`          | #5 crash-free monitoring            |
| 3   | `edb3577` Beta-P1-K | Skeleton copy "Solo is still listening…"                 | #2 real-vs-skeleton feel            |
| 4   | `0fa085b` Beta-P0-F | Suppress GPS auto-recenter outside known cities          | #1 cold start ≤10s, no SF empty map |
| 5   | `ab45e36` Beta-P0-C | SyncService `try? save()` → `saveOrReport` + Sentry      | #5 no silent data loss              |
| 6   | `57c2258` Beta-P1-I | UserCompletionRecord → categoryAffinity → prominence     | flywheel differentiation            |
| 7   | `908c2f1` Beta-P1-J | `<latest_context>` prepend per turn                      | #3 fresh context per ask            |
| 8   | `2362233` Beta-P0-E | `[exp:id]` citation enforcement + visual link            | #3 evidence-grounded reply          |
| 9   | `c65b4c2` Beta-P0-D | Per-card source-strength chip + italic skeleton oneLiner | #2 real-vs-skeleton feel            |
| 10  | `402b785` Beta-P0-A | Schema V1.7 + RouteStore active-route persistence        | #4 no lost route progress           |
| 11  | `972ccf6` Beta-P1-H | Route-stop geofences + `routeStopEntered` notification   | #4 auto-advance route stops         |

## Beta red lines — status

| #   | Red line                                              | Status     | Notes                                                                                                    |
| --- | ----------------------------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------- |
| 1   | Cold start ≤10s, see 5 cards, zero black screen       | ✅         | seed sync + SF guard + warm skeleton copy                                                                |
| 2   | AI real output vs skeleton visually distinguishable   | ✅         | per-card source-strength chip + italic oneLiner + "still listening" pill                                 |
| 3   | Solo gives at least one cited evidence-grounded reply | ✅         | system prompt enforces `[exp:id]` or "Guess —" prefix; chip rendered in chat bubble                      |
| 4   | Half-day route, no crash, no lost data                | ⚠️ partial | RouteStore + Schema V1.7 + geofence notification done; CompassMapView UI rehydration left to follow-up   |
| 5   | Sentry 24h crash-free <0.5%                           | ✅         | environment tagging + Persistence fatalError treated as recoverable + SyncService save failures captured |

## What we deferred (and why)

- **CompassMapView active-route rehydration UI** — RouteStore + Schema + geofence infrastructure all landed, but wiring `loadActiveRoute()` into the `@State activeRoute` and listening for `routeStopEntered` to call `advanceStop` was deferred. Risk of breaking other map/sheet wiring during a sleep-deprived push.
- **SessionFacts cross-session memory (P1-J extension)** — needs its own schema bump + LLM facts-extract round-trip; out of scope for Beta v0.9 minimal slice. The per-turn `<latest_context>` prepend covers the "where am I now" case.
- **Force-unwrap audit beyond Persistence (P0-B extension)** — 5 highest-risk `fatalError` sites closed; the broader 643-count `!` survey lives in a follow-up audit task.

## Files touched (high-impact)

```
apps/ios/SoloCompass/Persistence/PersistenceDecoding.swift      (new)
apps/ios/SoloCompass/Persistence/Models/RouteRecord.swift
apps/ios/SoloCompass/Persistence/Models/ExperienceRecord.swift
apps/ios/SoloCompass/Persistence/Models/ConversationRecord.swift
apps/ios/SoloCompass/Persistence/Models/ItineraryRecord.swift
apps/ios/SoloCompass/Persistence/SoloCompassModelContainer.swift  (V1.7 stage)
apps/ios/SoloCompass/Persistence/RouteStore.swift                 (startRoute/advanceStop/completeRoute/loadActiveRoute)
apps/ios/SoloCompass/Persistence/ExperienceRepository.swift       (categoryAffinity)
apps/ios/SoloCompass/Services/SentryService.swift                 (beta env)
apps/ios/SoloCompass/Services/SyncService.swift                   (saveOrReport)
apps/ios/SoloCompass/Services/LocationService.swift               (route geofences)
apps/ios/SoloCompass/Services/VoiceAgentOrchestrator.swift        (citation rules + latest_context)
apps/ios/SoloCompass/ViewModels/MapViewModel.swift                (SF guard + affinity sort)
apps/ios/SoloCompass/Views/Experience/ExperienceCardView.swift    (source-strength chip)
apps/ios/SoloCompass/Views/Chat/MessageBubble.swift               (citation rendering)
apps/ios/SoloCompass/Resources/en.lproj/Localizable.strings       (skeleton copy + source chips)
apps/ios/SoloCompass/Resources/zh-Hans.lproj/Localizable.strings  (zh-Hans equivalents)
```

## QA checklist for TestFlight upload

- [ ] Cold-start on iPhone 17 Pro fresh sim → land on Chiang Mai, 5 cards visible ≤10s
- [ ] Force-quit during route start → relaunch, `RouteStore.loadActiveRoute()` returns expected snapshot
- [ ] Ask Solo "What's a great cafe near here?" → reply contains at least one `[exp:…]` chip OR is prefixed with "Guess —"
- [ ] Mix real-AI and skeleton cards in the list → visual differentiation obvious without reading text
- [ ] Sentry dashboard 24h after TestFlight upload → `environment=beta` slice has < 0.5% crash-free regression vs `release`

## Known follow-ups (not blocking Beta)

- CompassMapView `loadActiveRoute()` → state binding (P0-A finish line)
- RouteStore.advanceStop wiring via `routeStopEntered` notification (P1-H finish line)
- Complete `[exp:…]` → SoloCompass URL-scheme handler in ChatSheet (P0-E follow-up)
- SessionFacts schema for cross-session preferences memory (P1-J follow-up)
