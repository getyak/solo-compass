# Loop Findings — Round 1 (2026-06-22-r1)

## 1) TL;DR

- **37 raw findings → 35 after dedupe**, clustered into 6 themes: cold-start UX & deep-link router, onboarding/consent gating, chat orchestrator race + persistence gaps, `shortName` invariant violations, dark-mode/CT-token violations in detail view, and wiring fragility (stacked sheets, dead code). Breakdown: **4 P0 / 10 P1 / 20 P2 / 2 features**.
- **6/6 auto-implement picks landed in worktrees** — deep-link router wired, Terms+Onboarding collapsed into a single `fullScreenCover`, Decline path no longer leaks bootstrap, Chiang Mai seed route added, `RouteStore.nearby()` slug↔seed aliasing, and SwiftData schema v1.8 entities (`ChatCardRecord`, `ChatReasoningRecord`) for the chat-as-memory feature.
- **Verify gate**: `xcodebuild` succeeded (exit 0) on main; **none of the 6 worktree implementations have landed on main yet** (last commit is still `d4801d5` from round 17). TS typecheck and `parity:check` not run — no TS files touched this round. Next round must merge the worktree branches before treating these P0/P1 as resolved.

---

## 2) Implemented this round (6/6)

### P0-1 — Wire `experienceDetail` and `routePreview` deep links to UI router

- **Files**: `apps/ios/SoloCompass/Views/Map/CompassMapView.swift`
- **Commit msg**: `fix(ios): wire experienceDetail and routePreview deep links to UI router`
- Replaced `print()`-only branches with `experienceService.getExperience(id:) → viewModel.openExperienceDetail(_:)` and `routeStore.get(RouteId) → routeSheet = .detail(route)`. `pendingDeepLink` cleared unconditionally to prevent re-fire on rerender.

### P0-2 — Collapse Terms + Onboarding into single enum-driven `fullScreenCover`

- **Files**: `apps/ios/SoloCompass/App/SoloCompassApp.swift`, `apps/ios/SoloCompass/Views/Map/CompassMapView.swift`
- **Commit msg**: `fix(ios): collapse Terms + Onboarding into single enum-driven fullScreenCover`
- Replaced `@State showingTermsSheet: Bool` with `@State firstLaunchCover: FirstLaunchCover?` (`.terms` / `.onboarding`). Single `.fullScreenCover(item:)` switches over the enum; `TermsConsentSheet.onAccept` sets `firstLaunchCover = .onboarding` directly so no dismiss/re-present race. Added `onAppear` guard to promote to `.onboarding` when terms were accepted previously but onboarding was killed mid-flow. Removed the now-unreachable second cover from `CompassMapView`.

### P0-3 — Block bootstrap when Terms gate is declined (Apple 5.1.1 / PIPL / GDPR)

- **Files**: `apps/ios/SoloCompass/Views/Onboarding/TermsConsentSheet.swift`, `apps/ios/SoloCompass/App/SoloCompassApp.swift`, `Resources/en.lproj/Localizable.strings`, `Resources/zh-Hans.lproj/Localizable.strings`
- **Commit msg**: `fix(ios): block bootstrap when Terms gate is declined (5.1.1/PIPL/GDPR)`
- Decline now flips an in-cover `declined` state to a permanent "Consent required" screen with a "Review again" button — cover stays up, map never appears. Bootstrap (location request, push registration, Supabase, outbox, seed loaders, tips) extracted into `runBootstrapIfConsented()` gated on consent and re-triggered via `.onChange(of: showingTermsSheet)` after accept. `acceptedKey` UserDefaults bit only flips on accept, so refusal re-prompts next launch. Added `terms.declined.title / body / review` keys in en + zh-Hans parity.

### P1-1 — Add Chiang Mai seed route so cold-start Now section is populated

- **Files**: `apps/ios/SoloCompass/Resources/JSON/seed_routes.json`, `Tests/SeedRoutesParityTests.swift`, `Tests/RouteStoreTests.swift`
- **Commit msg**: `fix(ios): add Chiang Mai seed route so cold-start Now section is populated`
- Added `nimman-slow-morning` route (two Nimman stops: `exp_cmi_nimman_coffee` + `exp_cmi_bookstore_work`, relaxed 3h morning drift, lowercase `cmi` cityCode to match `routeStore.nearby(cityCode:)` exact predicate). Updated parity test (count 4→5, city allowlist `{VTE, cmi}`, id set ∪ `nimman-slow-morning`) and `RouteStoreTests` known-id set.

### P1-2 — Resolve cityCode slug↔seed aliases in `RouteStore.nearby()`

- **Files**: `apps/ios/SoloCompass/Persistence/RouteStore.swift`
- **Commit msg**: `fix(ios): resolve cityCode slug↔seed aliases in RouteStore.nearby()`
- Replaced literal `$0.cityCode == cityCode` SwiftData predicate with a fetch + Swift-side filter against a `cityCodeCandidates(for:)` set built from a private static `cityCodeAliases` table mirroring `MapViewModel.cityCodeAliases` exactly (chiang-mai↔cmi, vientiane↔VTE, shenzhen/szx↔cn-深圳市). Case-insensitive match preserves sort-by-title and limit semantics. Persistence layer doesn't import the view model.

### Feature-1 — Persist chat cards + reasoning summaries (SwiftData schema v1.8)

- **Files**: `apps/ios/SoloCompass/Persistence/Models/ChatCardRecord.swift` (new), `Persistence/Models/ChatReasoningRecord.swift` (new), `Persistence/SoloCompassModelContainer.swift`
- **Commit msg**: `feat(ios): persist chat cards + reasoning summaries (schema v1.8)`
- New `ChatCardRecord` (id, sessionId FK, messageId FK, orderIndex, kind discriminator, payloadBlob, createdAt) and `ChatReasoningRecord` (id, sessionId FK, messageId FK, summary headline, detailBlob, createdAt). Registered in `SoloCompassSchemaV1_8` as additive lightweight migration; both `ModelContainer(for:)` sites (shared on-disk + makeInMemory) updated. xcodegen re-run. **Next round must wire `ChatHistoryStore.saveSession` / `restoreConversation` to populate orchestrator's `cardsByMessageId` and `reasoningSummaryByMessageId` from these tables** — storage exists, callers don't write/read yet.

---

## 3) Open P0/P1 backlog (deferred — next round)

### P0-4 — Race in `VoiceAgentOrchestrator.start()` + `rebindContext()` can crash via `precondition`

- **File**: `apps/ios/SoloCompass/Services/VoiceAgentOrchestrator.swift:222`
- Ask Solo calls `ensureOrchestrator()` → `start()` → `seedSystem(prompt)` (which has `precondition(messages.isEmpty)`) and `rebindContext(experience)` → `reseedSystem(...)` back-to-back as unstructured Tasks. If reseed wins, the subsequent seedSystem traps. Unit test skips `start()` so race is invisible to CI.
- **Cheapest fix**: in `start()`, call `session.reseedSystem(prompt)` instead of `seedSystem(prompt)`. Better: shared serial seeding Task awaited+cancelled before re-enqueue.

### P1-3 — `bindToLocation` never reloads experiences on usable GPS outside seed cities

- **File**: `apps/ios/SoloCompass/ViewModels/MapViewModel.swift:260`
- User in Tokyo with no persisted city → stranded on default Chiang Mai forever because `isWithinKnownCity` gate vetoes auto-center.
- **Fix**: when `isWithinKnownCity == false` AND no persisted city, surface city-picker (`isShowingCityPicker = true`) and/or empty-state overlay variant.

### P1-4 — Ten sequential sheet/fullScreenCover modifiers on `CompassMapView`

- **File**: `apps/ios/SoloCompass/Views/Map/CompassMapView.swift:535-586`
- Documented silent-collapse pattern (memory `project_stacked_sheets_only_last_wins`). Round 1 P0-2 fix collapsed Terms+Onboarding but the other eight remain.
- **Fix**: migrate to single `ActiveSheet` enum (`.settings`, `.route(RouteSheet)`, `.favorites`, ...) and `.sheet(item:)`. See feature suggestion #2 below.

### P1-5 — `MapAvatarBubble` always renders `CompanionProfile.sample.avatarEmoji` (🧭)

- **File**: `apps/ios/SoloCompass/Views/Me/MeSheet.swift:506`
- Top-right avatar is always the preview-fixture compass regardless of user profile.
- **Fix**: resolve active user's `CompanionProfile` from store, inject `avatarEmoji` via `@Environment`. Fallback 🧭 only when no profile exists.

### P1-6 — Inline cards + reasoning chips dropped on chat restore

- **File**: `apps/ios/SoloCompass/Services/VoiceAgentOrchestrator.swift:169`
- **Status**: storage now exists (Feature-1 schema v1.8 landed) but `ChatHistoryStore.saveSession` / `restoreConversation` not yet wired to write/read `ChatCardRecord` / `ChatReasoningRecord`. This is the round-2 wiring task to close the loop.

### P1-7 — Closing chat mid-stream saves orphan user message with no assistant reply

- **File**: `apps/ios/SoloCompass/Services/VoiceAgentOrchestrator.swift:1499`
- **Fix**: in `stop()`/on dismiss, drop trailing user-role row with no following assistant turn, or inject synthetic cancellation row. Better: persist `turn_status` enum (completed | cancelled) on `ChatMessageRecord`.

### P1-8 — AI-built routes can land with `cityCode=osm` and never surface in Now

- **File**: `apps/ios/SoloCompass/Services/VoiceAgentToolRouter.swift:535`
- `build_route` falls back to `osm` when neither `vm.selectedCity` nor first candidate's cityCode resolves. `refreshNearbyRoutes` filters strictly → route orphaned forever.
- **Fix**: reject `osm` fallback; if cityCode resolves to neither, surface `InlineBanner` in chat and skip save. Alt: at adopt time in `CompassMapView`, override `proposal.route.cityCode` with `viewModel.selectedCity`.

### P1-9 — `shortName` invariant violated in 3 high-visibility surfaces

- **Files**: `Views/Chat/ChatSheet.swift:767` (a11y), `Views/Chat/ChatCardViews.swift:55` (visual + a11y), `Views/Experience/ExperienceDetailView.swift:433` (hero)
- VoiceOver hears full sentences; cards show truncated sentences with ellipsis; detail hero wraps a sentence at 27pt bold.
- **Fix**: replace `.title` with `shortName` at all three sites; extend `PeekCardShortNameTest` with `ImageRenderer` snapshots covering the three surfaces.

### P1-10 — Forced warm-light detail page mixes system-dynamic colors → dark-mode black blobs

- **File**: `apps/ios/SoloCompass/Views/Experience/ExperienceDetailView.swift:1276, 384, 1313, 1334, 1338, 1291`
- `soloScoreSection`, `highlightsSection`, `ratingRow`, `priceLevelRow`, `multiSourceIndicator` all use `Color(.secondarySystemBackground)` / `.tertiarySystemFill` / `.secondary` against fixed `CT.bgWarm` canvas. Violates `project_ct_fixed_white_cards` invariant.
- **Fix**: swap to `CT.surfaceSunken` fills, `CT.fgMuted` for labels, `CT.fgPrimary` for values.

---

## 4) P2 polish backlog (20 items)

| #   | Area              | Title                                                        | File:Line                                         |
| --- | ----------------- | ------------------------------------------------------------ | ------------------------------------------------- |
| 1   | Explore FAB       | Capsule width jumps mid-tap (label morphs)                   | `Views/Map/CompassMapView.swift:2562`             |
| 2   | Cold start        | `shouldShowRoutesSection` ignores `routes.isEmpty`           | `Views/Map/CompassMapView.swift:795`              |
| 3   | Active route      | Cold-start resume silently drops if experience missing       | `Views/Map/CompassMapView.swift:428`              |
| 4   | a11y              | `RecenterButton` tappable when `located == false`            | `Views/Map/CompassMapView.swift:2343`             |
| 5   | FilterBar         | `Now` pill pulse runs forever (battery + jank)               | `Views/Filter/FilterBarView.swift:415`            |
| 6   | ExperienceService | `hardcodedSeed` fallback masks repo failure silently         | `Services/ExperienceService.swift:27`             |
| 7   | Camera reload     | `bindToLocation` never re-fetches for walking user           | `ViewModels/MapViewModel.swift:232`               |
| 8   | Chat empty        | `placeEmptyState` rebuilds with no animation                 | `Views/Chat/ChatSheet.swift:686`                  |
| 9   | Chat reasoning    | `ReasoningSummaryChip` replays settle on scroll-back         | `Views/Chat/ChatCardStack.swift:281`              |
| 10  | i18n              | Smart-quote drift between en + code comments                 | `Resources/en.lproj/Localizable.strings:888`      |
| 11  | Chat config       | Unconfigured banner never reappears mid-session              | `Services/VoiceAgentOrchestrator.swift:241`       |
| 12  | Routes            | `skipStop` advances past `experienceIds.count`               | `Persistence/RouteStore.swift:209`                |
| 13  | Friends           | `FriendsListView` (698 LoC) is dead code                     | `Views/Friends/FriendsListView.swift:15`          |
| 14  | MeSheet           | `MeEmptyStateCard` renders even with explored places         | `Views/Me/MeSheet.swift:60`                       |
| 15  | MeSheet           | `ProfileHeader` ignores `colorScheme` (bright cream in dark) | `Views/Me/MeSheet.swift:304`                      |
| 16  | Friends           | `LanguageDisplay` flag map is culturally biased              | `Views/Friends/FriendProfileView.swift:347`       |
| 17  | ExperienceDetail  | `levelSignalText` double-counts user's own contribution      | `Views/Experience/ExperienceDetailView.swift:478` |
| 18  | Chat cards        | Fixed warm-white fill paired with system `.primary` text     | `Views/Chat/ChatCardViews.swift:57`               |
| 19  | Friends           | `FriendsHubView.searchBar` uppercase-on-keystroke breaks IME | `Views/Friends/FriendsHubView.swift:91`           |
| 20  | Strings           | en/zh-Hans key parity watchpoint (no defect today)           | `Resources/zh-Hans.lproj/Localizable.strings:1`   |

---

## 5) Feature suggestions backlog

### Feature-1 — Persist chat cards + reasoning summaries

- **Status**: storage schema landed this round (v1.8 entities); **wiring deferred to next round** (orchestrator save/restore + snapshot test round-tripping one place card + one route proposal + one reasoning summary).

### Feature-2 — Unified `ActiveSheet` enum for `CompassMapView` presentation stack

- One-time refactor collapsing the 10-modifier stack into a single `.sheet(item:)` driven by `ActiveSheet { case settings, route(RouteSheet), favorites, terms, ... }`. Simultaneously fixes the remaining wiring fragility (P1-4) and prevents the next silent-collapse regression. ~150 LoC, clear defensive win. Round 1's P0-2 fix already prototyped this pattern with `FirstLaunchCover`.

---

## 6) Build / test verification

- **Branch**: `main` (last commit `d4801d5 fix(ios): /loop round 17`)
- **iOS build**: `xcodebuild build -project SoloCompass.xcodeproj -scheme SoloCompass -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'` → **exit 0** (SUCCESS). Only pre-existing Swift 6 concurrency warnings (WeatherService KeyPath/Sendable) plus a benign `CFBundleVersion` mismatch between widget extension (`2`) and parent app (`1`).
- **TS typecheck**: not run — no TS files changed on `main` this round.
- **Parity check**: not run — `packages/core/src/experience.ts` not touched.
- **Worktree status**: 6/6 implementations live in `.claude/worktrees/wf_ea2096c5-fd-{5..0}`. **None merged to main yet** — the next-round orchestrator must land these before treating the P0/P1 list above as resolved.
- **Untracked on main**: `docs/AGENT_LOOP_REDESIGN.md`, `docs/AGENT_SYSTEM_ANALYSIS.md` (pre-existing, unrelated to this loop).
- **Per-worktree caveat**: each worktree needed `Resources/Secrets.plist` copied from main before building (gitignored; documented in memory `feedback_worktree_env`). All 6 builds succeeded after the copy.
