# PRD: Post-Pro-Chat Rebuild — Solo Compass

**Status:** Draft  v1
**Author:** Xinwei Xiong (with Claude Code)
**Created:** 2026-05-21
**Scope window:** All open work identified in the 2026-05-21 dual-agent diagnosis session, no time-boxing.
**Predecessor PR:** [#125 — fix(ios): unblock pro chat + free map controls from status bar](https://github.com/getyak/solo-compass/pull/125)

---

## 1. Introduction / Overview

After landing the Pro-tier chat-proxy Edge function (commit `5b40c5b`), real-device testing surfaced a cluster of issues:

1. A regression that left Pro users unable to chat at all (fixed in PR #125).
2. Map controls colliding with the iPhone status bar (fixed in PR #125).
3. Multiple still-open product gaps: weak data coverage, hard-coded categories with no user control, no AI follow-up entry point on the experience card, broken "expand to 25 km" fallback path.
4. A research/QA tooling gap: the "dual-agent" workflow (an evaluator that drives the app + an executor that fixes code) is referenced in `~/.claude/skills` but has **no actual implementation** in the repo today.

This PRD captures **everything that came out of that session that has not yet shipped**, so we can sequence the work clearly across product (the iOS app) and tooling (the dual-agent harness). It deliberately covers a large surface and is **not time-boxed** — items are grouped by area, not by sprint.

---

## 2. Goals

### Product goals (Solo Compass iOS)
- Pro chat must be **functionally complete**, not just unblocked: text + voice + per-card AI follow-up.
- The map must **always have something to show** in seeded cities — no dead-end "no experiences nearby" with a button that takes the user nowhere.
- Categories must be **user-controllable** without a new app build.
- Visual polish: zero overlap with system chrome on the iPhone 17 family.

### Tooling goals (dual-agent QA harness)
- Land a real, runnable `sc-evaluator` + `sc-executor` + `sc-loop` trio in the repo.
- Evaluator must be able to **boot a simulator, drive the app, and produce screenshots** so visual regressions (e.g. control-vs-status-bar overlap) are detectable, not just behavioral failures.
- Executor must consume the evaluator's findings file and produce patches that pass tests before the next iteration.
- Termination is **automatic**, based on a per-story acceptance script — no manual loop control.

### Non-goals
- See §6.

---

## 3. User Stories

User stories are grouped by epic. Each story is **small enough to implement in one focused session** (1–4 h of human work). Acceptance criteria are verifiable; UI stories must end with a simulator screenshot check.

### Epic A — Chat completeness (Pro)

#### US-A01: Per-experience AI follow-up button on `ExperienceDetailView`
**Description:** As a Pro user, I want to ask Solo follow-up questions about the experience I'm looking at, so that I can dig into operating hours, solo-friendliness, what to pair it with — without re-typing the place name.

**Acceptance criteria:**
- [ ] `ExperienceDetailView` shows an "Ask Solo about this" button below the hero card, above the "Mark done" CTA.
- [ ] Tapping it opens the existing `ChatSheet` with **the experience JSON injected as `<experience_context>` in the system prompt** (see FR-A1).
- [ ] The first assistant turn for that sheet must be able to reference the experience by name without the user typing it.
- [ ] Closing the sheet via the X icon does **not** persist the experience-scoped context to the next non-scoped chat.
- [ ] `xcodebuild build` passes.
- [ ] XCUITest case `testExperienceAskAIInjectsContext` asserts the system prompt contains `<experience_context>` with the experience's title.
- [ ] Screenshot via `simctl io screenshot` shows the button rendered on the detail sheet at iPhone 17 Pro / iOS 26.4.

#### US-A02: Reusing one orchestrator across scoped + unscoped chats
**Description:** As a developer, I want to reuse `VoiceAgentOrchestrator` instead of creating one per experience, so that memory stays bounded when a user opens 10 cards in a row.

**Acceptance criteria:**
- [ ] `CompassMapView.ensureOrchestrator` accepts an optional `experienceContext: Experience?`.
- [ ] When `experienceContext` changes, the orchestrator resets its session and re-seeds the system prompt — no new instance allocated.
- [ ] `XCTest` asserts that opening 5 different experience cards in sequence results in **exactly 1** `VoiceAgentOrchestrator` instance (use weak-ref counting helper).
- [ ] No regression in the unscoped `+` button flow.

#### US-A03: Fix `testMissingKeyYieldsUnconfiguredState` on dev machines
**Description:** As a developer, I want the unconfigured-state test to pass locally even when `GeneratedSecrets.deepSeekApiKey` is non-empty (dev `.env` baked in), so that CI parity is restored.

**Acceptance criteria:**
- [ ] Test stubs `Secrets.resolveAPIKey` (or uses a protocol-injected resolver) so that the compile-time key value is irrelevant.
- [ ] Same applies to `testRepeatedStartWhileUnconfiguredStaysUnconfigured`.
- [ ] Both tests pass on a machine with a real DeepSeek key in `.env`.

### Epic B — Map data freshness

#### US-B01: Auto-explore on empty category filter
**Description:** As a user, when I tap a category and the visible list goes to zero, I expect the app to fetch more data rather than show a static empty card.

**Acceptance criteria:**
- [ ] When `MapViewModel.applyFilters` returns 0 results **and** the user is in a seeded city, automatically call `exploreNearby(at: viewModel.exploreAnchorCoordinate)` once (debounced to ≤ 1 call / 10 s per category).
- [ ] Free-tier users see a single-ring Overpass POI fetch; Pro users get the existing multi-ring schedule.
- [ ] If `exploreNearby` itself returns empty, the current `EmptyStateOverlay` is shown (existing behavior).
- [ ] Unit test asserts the debounce window is respected.
- [ ] Screenshot test confirms a typical "Computer" category tap in Chiang Mai surfaces ≥ 1 marker within 8 s.

#### US-B02: "Expand to 25 km" → actually broaden, then offer Explore
**Description:** As a user, when 5 km has no results, the "expand to 25 km" button should *try harder*, and if 25 km is still empty, offer the obvious next step instead of looping.

**Acceptance criteria:**
- [ ] Tapping "Expand to 25 km" sets `preferences.maxDistanceKm = 25` **and** triggers `exploreNearby` at the current anchor.
- [ ] If after expand+explore the result set is still empty, the empty card's CTA flips to **"Explore farther"** which runs `exploreNearby(radiusMeters: 12000)`.
- [ ] After three consecutive empty cycles, the CTA flips to the existing "Browse nearest city" button (no infinite loop).
- [ ] Screenshot test from a remote coordinate (e.g. 0,0) confirms the CTA sequence.

#### US-B03: Overpass POI category mapping completeness audit
**Description:** As a user, when I tap "Coffee" I want only coffee-shop POIs, and when I tap "Computer" I want only co-working / laptop-friendly spots — not a generic mix.

**Acceptance criteria:**
- [ ] `OverpassService.fetchPOIs` accepts a `category: ExperienceCategory?` filter and builds the Overpass query accordingly (e.g. `amenity=cafe` for `.coffee`, `amenity=coworking_space` for `.work`).
- [ ] Unit test asserts the generated Overpass QL string for each of the 8 categories.
- [ ] Integration test (network-stubbed) confirms category-tagged results round-trip into `Experience.category` correctly.

#### US-B04: Foursquare Places integration (optional secondary source)
**Description:** As a product owner, I want a second data source so that thin-OSM cities (e.g. small Asian towns) still surface usable results.

**Acceptance criteria:**
- [ ] New `FoursquareService` mirrors the `OverpassService` interface (`fetchPOIs(near:radiusMeters:category:)`).
- [ ] API key read from `Secrets.resolvedFoursquareKey` (UserDefaults override → GeneratedSecrets, mirrors the DeepSeek pattern).
- [ ] `MapViewModel.exploreNearby` calls Overpass first; if results < 5 *and* Foursquare key present, it falls back to Foursquare and merges (de-duped by coord rounded to 4 decimals).
- [ ] Cost guard: at most 1 Foursquare call per `exploreNearby` invocation.
- [ ] Unit tests cover the merge / dedupe logic.

### Epic C — User-configurable categories

#### US-C01: Schema extension — built-in + custom tags
**Description:** As a developer, I want `Experience.category` to keep its enum strength but allow `Experience.userTags: [String]` so users can layer their own labels.

**Acceptance criteria:**
- [ ] Add `userTags: [String]` (default `[]`) to `Experience` in `Models/Experience.swift` **and** `packages/core/src/experience.ts`.
- [ ] Add a SwiftData migration for the new field.
- [ ] `pnpm parity:check` passes.
- [ ] Existing JSON seed still loads (the field is optional).

#### US-C02: Settings → "Visible categories" multi-select
**Description:** As a user, I want to hide categories I don't care about (e.g. "Nightlife") so the filter bar is shorter.

**Acceptance criteria:**
- [ ] New row in `SettingsView`: "Visible categories" → opens a checkbox list of the 8 built-ins.
- [ ] Selection persisted in `UserPreferences.visibleCategories: [ExperienceCategory]`.
- [ ] `FilterBarView.visibleCategories` reads from preferences (no longer the hard-coded constant at `FilterBarView.swift:30`).
- [ ] Screenshot test confirms unselected categories disappear from the filter bar.

#### US-C03: Custom-tag chip on the filter bar (v1 — manual)
**Description:** As a user, I want to type a custom tag once and see all experiences tagged with it.

**Acceptance criteria:**
- [ ] Settings → "Custom tags" → list with add / delete.
- [ ] Each custom tag renders as an extra pill on the filter bar after the 8 built-ins.
- [ ] Tapping it filters `visibleExperiences` to those with the tag in `userTags`.
- [ ] Custom tags persist via `UserPreferences.customTags`.
- [ ] **Non-goal for v1:** AI-suggested tags. See §6.

### Epic D — Visual polish

#### US-D01: Audit safe-area handling across all overlays
**Description:** As a user on iPhone 17 Pro / Pro Max / Air, no app control should sit under the Dynamic Island or status-bar text.

**Acceptance criteria:**
- [ ] Screenshot evidence on **3** simulators: iPhone 17 Pro, iPhone 17 Pro Max, iPhone Air (latest iOS).
- [ ] Each screenshot shows: city pill, filter bar, MapCompass, MapUserLocationButton, the `+` button, the explore button — all inside safe areas.
- [ ] Bottom info bar's text is not clipped by the home indicator.

#### US-D02: City pill — minimum tap target
**Description:** As a user, I want the city pill to be at least 44×44 pt (Apple HIG).

**Acceptance criteria:**
- [ ] Pill's tappable frame ≥ 44×44 (use `.contentShape(Rectangle().inset(by: -8))` if visual size is smaller).
- [ ] XCUITest hit-tests at the corners of the visual pill.

### Epic E — Dual-agent QA harness

#### US-E01: `sc-evaluator` skill — bootable
**Description:** As a developer, I want a `sc-evaluator` command that boots a simulator, installs the latest build, exercises a named user journey, and writes a findings file.

**Acceptance criteria:**
- [ ] New skill at `~/.claude/skills/sc-evaluator/SKILL.md` plus runtime script `scripts/sc-evaluator/run.sh`.
- [ ] Usage: `sc-evaluator <journey-name>` → exits 0 if journey passes, 1 if any finding raised.
- [ ] Each run writes `scripts/sc-evaluator/findings/<timestamp>.md` with: journey name, pass/fail per step, screenshot links, suggested fix anchors.
- [ ] Findings file is **append-only** — never overwrites prior runs.

#### US-E02: Evaluator screenshot pipeline
**Description:** As a developer, I need the evaluator to take screenshots at every interesting step so visual issues (control overlap, layout regression) are detectable.

**Acceptance criteria:**
- [ ] Every step in a journey can call `screenshot(label)` which:
   1. Saves PNG to `scripts/sc-evaluator/screenshots/<run-id>/<label>.png` via `simctl io screenshot`.
   2. Appends `![label](path)` to the findings file.
- [ ] At least one journey ("home-screen-cold-start") has ≥ 3 screenshot steps.
- [ ] Screenshots are gitignored by default; opt-in via `SC_EVALUATOR_KEEP_SCREENSHOTS=1`.

#### US-E03: Journey DSL
**Description:** As a developer, I want a tiny DSL to declare user journeys so authoring new tests doesn't require reading the harness code.

**Acceptance criteria:**
- [ ] Journeys live at `scripts/sc-evaluator/journeys/<name>.yml`.
- [ ] DSL supports steps: `launch`, `tap`, `longPress`, `screenshot`, `assertVisible`, `assertText`, `wait`.
- [ ] `tap` accepts either coordinates **or** an accessibility identifier.
- [ ] First two journeys shipped: `home-screen-cold-start.yml`, `pro-chat-roundtrip.yml`.

#### US-E04: `sc-executor` skill — consume findings, propose patch
**Description:** As a developer, I want an executor that reads the latest findings file and proposes (or commits, depending on mode) targeted patches.

**Acceptance criteria:**
- [ ] New skill at `~/.claude/skills/sc-executor/SKILL.md`.
- [ ] Usage: `sc-executor [--apply]` → reads the most recent `findings/*.md`, plans, edits, then either prints the diff (default) or commits to a branch `agent/<run-id>` (with `--apply`).
- [ ] Refuses to act if findings file is older than 1 h (stale-input guard).
- [ ] Always runs `xcodebuild build` before declaring success.

#### US-E05: `sc-loop` — wire evaluator ↔ executor with termination
**Description:** As a developer, I want a single command that runs evaluator → executor → evaluator until either all journeys pass or the iteration cap is hit.

**Acceptance criteria:**
- [ ] New skill at `~/.claude/skills/sc-loop/SKILL.md`.
- [ ] Usage: `sc-loop <journey-name> [--max-iterations 5]`.
- [ ] Each iteration logs to `scripts/sc-loop/runs/<run-id>/iteration-<n>.md`.
- [ ] Terminates on: ① all assertions pass, ② iteration cap, ③ executor refuses to act (e.g. stale findings, build broken).
- [ ] Final run summary printed at end with iteration count and exit reason.

#### US-E06: Feedback channel format
**Description:** As a developer, I want a stable schema for the findings file so future tools can parse it.

**Acceptance criteria:**
- [ ] Findings file uses a documented front-matter block: `run_id`, `journey`, `timestamp`, `commit_sha`, `simulator`, `ios_version`.
- [ ] Body sections are: `## Steps`, `## Findings`, `## Suggested Fixes` (each finding includes file:line anchors).
- [ ] JSON-shadow file `findings/<timestamp>.json` written alongside the markdown for machine consumers.
- [ ] Schema documented in `scripts/sc-evaluator/SCHEMA.md`.

---

## 4. Functional Requirements

Numbered for cross-reference. Maps to user stories in parentheses.

### Product

- **FR-A1** *(US-A01)*: When the experience-scoped chat opens, the system prompt sent to the model must include a `<experience_context>` block with `title`, `category`, `cityCode`, `bestTimes`, `confidenceLevel`, `soloScore`. No coordinates leak.
- **FR-A2** *(US-A01)*: The "Ask Solo about this" button is hidden if `aiService.isProTier == false && Secrets.resolvedDeepSeekApiKey.isEmpty` — i.e. the same gate the `+` button uses.
- **FR-A3** *(US-A02)*: `VoiceAgentOrchestrator` exposes `func rebindContext(_ experience: Experience?)` that clears the session and reseeds the system prompt without re-allocating dependencies.
- **FR-B1** *(US-B01)*: `MapViewModel.applyFilters` returns its result via a publisher that triggers `exploreNearby` after a 600 ms idle when the result count is 0. The trigger is gated on a per-category timestamp.
- **FR-B2** *(US-B02)*: `EmptyStateOverlay`'s primary button text + action are derived from a `EmptyStateStage` enum: `.tryExpand → .tryExplore → .browseCity`.
- **FR-B3** *(US-B03)*: `OverpassService` exposes a static `categoryToOverpassFilter` mapping table; the table is the single source of truth and is asserted in tests.
- **FR-B4** *(US-B04)*: When `FoursquareService` is enabled (key present), it is called **only after** Overpass returns < 5 results, and merged via `(latRounded4, lonRounded4)` dedupe.
- **FR-C1** *(US-C01)*: `Experience` adds `userTags: [String]?` (nullable for schema compatibility). TS schema mirror lives in `packages/core/src/experience.ts`.
- **FR-C2** *(US-C02)*: `UserPreferences.visibleCategories: Set<ExperienceCategory>` (default = all 8). `FilterBarView` reads from this set.
- **FR-C3** *(US-C03)*: `UserPreferences.customTags: [String]` (default `[]`). A pill is rendered for each tag, scroll-horizontal alongside the 8 built-ins.
- **FR-D1** *(US-D01)*: No SwiftUI overlay may use `.ignoresSafeArea()` for the top edge without an explicit safe-area inset replacement. A lint rule (string match in the CI script) flags violations.

### Tooling

- **FR-E1** *(US-E01)*: Evaluator runtime is a bash + Python (no extra Swift) script so it can run in any CI image with Xcode CLT.
- **FR-E2** *(US-E02)*: Screenshot capture goes through `xcrun simctl io <udid> screenshot` — no third-party deps.
- **FR-E3** *(US-E03)*: Journey YAML schema is validated on load; unknown step names fail fast.
- **FR-E4** *(US-E04)*: Executor commits to a per-run branch only when `--apply` is set. Default = dry-run diff print.
- **FR-E5** *(US-E05)*: Loop iteration cap default = 5, max = 20. Cap is a hard limit, not just a default.
- **FR-E6** *(US-E06)*: All findings files share a JSON-Schema-validated frontmatter (see `scripts/sc-evaluator/SCHEMA.md`).

---

## 5. Open issues from session, not yet user-storied

These are observations from the dual-agent diagnosis that need a follow-up but aren't ready for implementation yet. Park them here so they're not lost.

- **`MapViewModel.swift:993..1066` — Swift 6 sending warnings.** Pre-existing data-race warnings around `service` / `self.overpassService` / `self.aiService`. Will become hard errors when the project flips to Swift 6 mode. Needs a small refactor to mark those closures `@Sendable` or capture isolated copies. **Not blocking** any user-visible work today.
- **Build-time DeepSeek key resolution.** `GeneratedSecrets.deepSeekApiKey` is a `static let` baked at compile time and can't be overridden at runtime by tests. US-A03 deals with the test surface, but the broader question — should the build-time fallback even exist once chat-proxy is universal? — needs a product call.
- **Onboarding flow for empty-permission users.** If location permission is denied entirely, the map currently shows the user's last-known city or `defaultCenterForSelectedCity`. The 25-km expand chain (US-B02) needs to behave sanely in that state — confirm in QA before closing the epic.
- **TS↔Swift parity check coverage.** `pnpm parity:check` currently only audits `experience.ts` ↔ `Experience.swift`. After US-C01 lands, also audit `UserPreferences` fields that map to a server payload.

---

## 6. Non-Goals (Out of Scope)

The following are explicitly **excluded** from this PRD. Anything here that's eventually wanted should get its own PRD.

- **Cross-device sync of user-defined categories or tags.** v1 stores them locally only.
- **AI-suggested categories or tags.** US-C03 ships manual entry; auto-suggestion is a future epic.
- **Google Places API integration.** Costs $$ per call; we cover the data gap with OSM + Foursquare for now.
- **Android / web parity for any new field in `Experience`.** The TS package mirrors the schema, but no web or Android consumer is being added.
- **Auto-translation of OSM tags.** OSM names appear in their local language; we don't transliterate.
- **Evaluator running in production CI.** US-E01–E06 land the harness locally; wiring it into GitHub Actions is a follow-up PRD.
- **Speech-to-speech (voice-out) responses.** AVSpeechSynthesizer already exists for accessibility, but expanding voice-out is not in scope.
- **A new chat-proxy quota policy.** Quotas stay as they ship in commit `5b40c5b`.
- **Migration from DeepSeek to Anthropic / OpenAI.** Provider choice is independent of this PRD.
- **TestFlight release management.** v1 release readiness will be its own checklist.

---

## 7. Design Considerations

- **"Ask Solo about this" button.** Reuses the existing `MessageBubble` glassmorphism style for visual coherence with the `+` chat. Place it directly below the hero image, full-width minus 16 pt horizontal padding, vertical padding 12 pt. Icon: `bubble.left.and.text.bubble.right`. Localized labels in `Resources/{en,zh-Hans}.lproj/Localizable.strings` under `experience.askSolo.cta`.
- **Settings → Visible categories.** Reuse the existing toggle row style from `SettingsView.swift`. Group header: "Filter bar". Single localized string `settings.filter.visible_categories`.
- **Custom tag pill.** Same `iconPill` shape as the 8 built-ins; icon: `tag.fill`; color: `Color.accentColor` so they read as user-defined rather than brand.
- **Empty state stages.** Three distinct sentences for `.tryExpand`, `.tryExplore`, `.browseCity` — no shared "no results" string.
- **Evaluator screenshot directory layout.**
  ```
  scripts/sc-evaluator/
    SKILL.md
    SCHEMA.md
    run.sh
    journeys/
      home-screen-cold-start.yml
      pro-chat-roundtrip.yml
    findings/
      2026-05-21T19-45-00Z.md
      2026-05-21T19-45-00Z.json
    screenshots/
      2026-05-21T19-45-00Z/
        01-cold-launch.png
        02-permission-granted.png
        03-map-loaded.png
  ```
- **Findings file front-matter (yaml).**
  ```yaml
  ---
  run_id: 2026-05-21T19-45-00Z
  journey: home-screen-cold-start
  timestamp: 2026-05-21T19:45:00Z
  commit_sha: c62faddXX
  simulator: iPhone 17 Pro
  ios_version: "26.4"
  ---
  ```

---

## 8. Technical Considerations

- **Dependencies between epics.**
  - Epic A US-A01 depends on US-A02 (one orchestrator across sheets) for clean state, but US-A01 can ship first and let US-A02 follow.
  - Epic C US-C03 depends on US-C01 (the `userTags` field).
  - Epic E US-E04/E05 depend on US-E01–E03.
- **Persistence migration risk.** US-C01 adds a SwiftData field. Existing user databases must migrate without data loss. Use a `VersionedSchema` migration (we already have one for `subscription_to_profile.sql` on the backend side; mirror the pattern on-device).
- **Cost guards.** Foursquare free tier is 1000 calls / day. US-B04 hard-caps to 1 call per `exploreNearby` and adds a daily counter in `UserPreferences` for visibility (no enforcement in v1).
- **Test resource cost.** Adding XCUITest journeys roughly doubles iOS CI time per PR. Mitigate by tagging journeys `@critical` (run on every PR) vs `@nightly` (run on `main` only).
- **Skill discovery.** `sc-evaluator` / `sc-executor` / `sc-loop` are loaded by Claude Code from `~/.claude/skills/<name>/SKILL.md`. We keep them out of the repo (so different machines can have different evaluators) **but** check in the runtime scripts at `scripts/sc-evaluator/` etc. The SKILL.md files delegate to those scripts.
- **Existing chat-proxy contract.** All new AI calls (US-A01 follow-up chats) must go through the same `chat-proxy` Edge function for Pro users — do not introduce a second AI route.

---

## 9. Success Metrics

### Product
- **Chat send success rate ≥ 99 %** for Pro users over a 7-day window (telemetry: `chat.send.success` / `chat.send.attempt`).
- **Empty-state → action conversion ≥ 60 %** — when the EmptyStateOverlay shows, ≥ 60 % of users tap a CTA (not just dismiss the sheet).
- **Category usage entropy** — daily-active categories per user goes from ~2.1 (current; only 6 built-ins, no custom) to ≥ 3.0 after US-C02 + US-C03.
- **Visual regression count = 0** for the iPhone 17 family in the next two releases (measured by US-D01 screenshot diff).

### Tooling
- **One-command run from clean state.** `sc-loop home-screen-cold-start` on a fresh checkout produces a green run within 10 min.
- **First catch.** Dual-agent harness independently re-discovers the "MapCompass under status bar" issue within its first 3 runs against an artificially regressed branch.
- **Iteration time.** Mean wall-clock per evaluator+executor cycle ≤ 4 min on M-series hardware.

---

## 10. Open Questions

1. Should the per-experience AI follow-up chat persist its session to the experience's detail page so re-opening the card resumes the conversation, or always start fresh? *(US-A01 default: fresh.)*
2. For empty-category auto-explore (US-B01), do we charge the Pro user's daily quota or piggyback on the free single-ring budget?
3. For user custom tags (US-C03), do we sort the tag pills alphabetically, by recency-of-use, or by user-defined order?
4. For the evaluator (US-E02), do we keep screenshots forever (compressed) or expire after N days? Storage isn't free even locally.
5. Should `sc-loop` (US-E05) ever be allowed to push directly to a remote branch, or always stay local? *(Default proposal: always local; humans push.)*
6. Should the dual-agent harness include a **third** "reviewer" agent (security / style review of the executor's diff), or is two-agent + human review enough? *(Default: two-agent for v1; revisit if executor output quality drops.)*

---

## Appendix A — Mapping to the session diagnosis

| Original session finding | Covered by |
|---|---|
| #1 Category tap → "expand 25 km" no-op | US-B01, US-B02 |
| #1b Data sources too sparse | US-B03, US-B04 |
| #2 Categories hard-coded | US-C01, US-C02, US-C03 |
| #3 Right-top controls overlap status bar | **Shipped in PR #125**; ongoing audit in US-D01 |
| #4 "+" tap → no message echo, no AI reply | **Shipped in PR #125** |
| #5 Long-press voice → released, nothing happens | **Shipped in PR #125** |
| #6 Experience card has no AI follow-up entry | US-A01, US-A02 |
| Dual-agent skill files don't exist | US-E01–E06 |
| `testMissingKeyYieldsUnconfiguredState` pre-existing failure on dev | US-A03 |
| Swift 6 sending warnings in `MapViewModel` | §5 (parked) |

## Appendix B — File index (read these first when implementing)

- `apps/ios/SoloCompass/Services/VoiceAgentOrchestrator.swift` — chat lifecycle, Pro bypass
- `apps/ios/SoloCompass/Services/AIService.swift` — `isProTier`, `buildChatRequest`, chat-proxy
- `apps/ios/SoloCompass/Services/OverpassService.swift` — POI fetch, the obvious extension point for US-B03/B04
- `apps/ios/SoloCompass/Views/Map/CompassMapView.swift` — root view; safe-area, controls, sheet hosting
- `apps/ios/SoloCompass/Views/Filter/FilterBarView.swift` — hard-coded `visibleCategories` (US-C02)
- `apps/ios/SoloCompass/Views/Experience/ExperienceDetailView.swift` — host for the "Ask Solo" button (US-A01)
- `apps/ios/SoloCompass/Models/Experience.swift` + `packages/core/src/experience.ts` — schema parity (US-C01)
- `apps/ios/SoloCompass/Models/UserPreferences.swift` — visible/custom categories storage (US-C02/C03)
- `scripts/ralph/` — existing autonomous loop; reference, **not** to be replaced (US-E01–E06 build a separate harness)
