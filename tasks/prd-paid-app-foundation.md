# PRD: Paid-App Foundation — Persistence, Caching, Freemium & Cross-Device Sync

> **Status:** Draft
> **Owner:** @cubxxw
> **Target release:** v1.1.0 (iOS), feeds eventual web/bot parity
> **Branch convention:** `feat/<short-slug>` per user-story batch
> **Related:** `tasks/prd-data-engine-v2.md`, `tasks/prd-deepseek-migration.md`

---

## 1. Introduction / Overview

Solo Compass today is a SwiftUI map app with five Chiang Mai seed Experiences and a working "Explore here" flow that pulls real OpenStreetMap POIs and asks Claude to enrich them into solo-traveler entries. Everything beyond `UserPreferences` lives in memory — close the app and all generated content is gone. There is no caching layer, no cost control on AI calls, no monetization, and no way for the app to get smarter over time.

This PRD turns the current technical demo into a **shippable, paid iOS app** by adding four foundations:

1. **Local persistence** — every Experience (seed, OSM-generated, user-added) survives app restarts via SwiftData.
2. **Smart caching & cost control** — Explore-here results cached by region for 14 days; Claude calls deduplicated; cheaper model by default.
3. **Freemium monetization** — base map + filter + completed/favorites are free; AI-powered Explore Here, voice intent, and AI explanations require an active subscription via StoreKit 2.
4. **Supabase backend** — anonymous device identity, cross-device sync of user data and generated Experiences, telemetry on Solo-Score signals to power the "data flywheel."

The ultimate target: a v1.1 iOS build that can stand on its own in the App Store, generate revenue, and feed real usage data back into Experience quality.

---

## 2. Goals

- **G1 — No more data loss.** Generated Experiences and user state persist across app launches and device restarts (target: 100% retention of synthesized content for 90 days).
- **G2 — Cost-controlled AI.** Average cost per active user per day ≤ **$0.02** for free tier (zero AI calls) and ≤ **$0.30** for paid tier (cached, deduped, Sonnet-based).
- **G3 — Working free → paid funnel.** Subscribe screen reachable in ≤ 2 taps from any AI-gated action; 7-day free trial; restore-purchase flow works on fresh install.
- **G4 — Cross-device continuity.** A signed-in user opening the app on a second device sees the same favorites, completed list, generated Experiences, and Solo-Score history within 5 seconds.
- **G5 — Trust-preserving AI.** Generated Experiences visually distinguish themselves from curated content and never invent specific facts the model could not verify (no fake menu items, hours, or interior details).
- **G6 — App Store ready.** Privacy manifest, ATT prompt, refund-of-trial flow, IAP receipts, ITP/Family Sharing all configured. Pass App Store review on first submission.
- **G7 — Local-first.** Every UI read comes from SwiftData; Supabase is sync + shared cache only. App stays fully usable when offline or when the backend is down.

---

## 3. User Stories

> Stories are grouped into 6 epics totaling 31 user stories. Each story is sized to ~1–2 focused implementation sessions and references existing files where possible. Order follows recommended build sequence.

### Epic A: Local Persistence (SwiftData)

#### US-A1: Define SwiftData schema mirroring current Codable models
**Description:** As a developer, I want a SwiftData store that mirrors `Experience`, `Confidence`, `SoloScore`, `ExperienceLocation`, `TimeWindow`, `HowToStep`, `RealInconvenience`, `InformationSource`, and `Stats` so the app has a single source of truth on disk.

**Acceptance Criteria:**
- [ ] New file `apps/ios/SoloCompass/Persistence/SoloCompassModelContainer.swift` exposes a `ModelContainer` configured with all `@Model` types.
- [ ] New `@Model` classes in `apps/ios/SoloCompass/Persistence/Models/`: `ExperienceRecord`, `ConfidenceRecord`, `SoloScoreRecord`, `LocationRecord`, `TimeWindowRecord`, `HowToStepRecord`, `RealInconvenienceRecord`, `SourceRecord`, `StatsRecord`, `UserCompletionRecord`, `UserFavoriteRecord`, `MicroSurveyRecord`, `ExploreCacheRecord`.
- [ ] Two-way mapping: `ExperienceRecord(from: Experience)` initializer + `var asValue: Experience` computed property. Round-trip is lossless.
- [ ] Model versioning: schema is wrapped in a `VersionedSchema` named `SoloCompassSchemaV1` for future migration.
- [ ] Unit test: round-trip a hardcoded `Experience` through `ExperienceRecord` → fetch → `asValue` and assert equality.
- [ ] `xcodebuild test` passes.

#### US-A2: Replace ExperienceService in-memory store with SwiftData-backed repository
**Description:** As a user, I want every Experience I see on the map to come from local storage, so closing and reopening the app does not lose any of my discovered places.

**Acceptance Criteria:**
- [ ] New `ExperienceRepository` (in `Persistence/`) owns CRUD against the `ModelContainer`. `ExperienceService` becomes a thin facade that delegates to the repo and exposes the existing `@Observable` API for views.
- [ ] On first launch with empty store: bundle seed (`Resources/JSON/seed_experiences.json`) is imported once. A boolean flag `seedImported` is stored in `UserPreferences` so re-imports skip.
- [ ] `appendGenerated([Experience])` writes through to SwiftData and is **idempotent by id**.
- [ ] `markCompleted(id)` writes a `UserCompletionRecord` (separate table; never mutates the Experience) and the existing `Stats.completionCount` derives from a query.
- [ ] Acceptance test: launch app, run "Explore here" in Hanoi, force-quit, relaunch — all generated pins are still on the map.
- [ ] Unit test: write 30 generated Experiences, query nearby with radius 5 km, assert correct subset returned in correct order.
- [ ] `xcodebuild test` passes.

#### US-A3: Migrate UserPreferences mutable state into SwiftData
**Description:** As a user, I want my favorites, completed list, micro-survey responses, and pending check-ins to persist reliably across app reinstalls when I'm signed in.

**Acceptance Criteria:**
- [ ] `UserPreferences` retains `UserDefaults` for **scalar settings only** (style, max distance, disliked categories, last selected city).
- [ ] Lists move to SwiftData: `UserCompletionRecord`, `UserFavoriteRecord`, `MicroSurveyRecord`, `PendingCheckInRecord`.
- [ ] `isCompleted(id)` / `isFavorited(id)` become repository queries; existing call sites in `MapViewModel`, `ExperienceDetailViewModel`, settings/favorites views unchanged.
- [ ] Migration: on first launch of v1.1, read existing `UserDefaults` arrays for completed/favorites and seed the SwiftData tables, then clear the old keys.
- [ ] Unit test: pre-populate `UserDefaults` with legacy completed array → boot the app → assert SwiftData has matching `UserCompletionRecord` rows and old keys are gone.

#### US-A4: Persist offline map regions for last-explored area
**Description:** As a traveler with flaky data, I want the last region I explored to be browsable offline (markers + detail data, not basemap tiles).

**Acceptance Criteria:**
- [ ] Last 3 explored regions (lat/lon center + radius) recorded in a `RecentExploreRegion` SwiftData table.
- [ ] When `Explore here` is offline, the app still shows pins from the last region matching the current map center within 10 km — using only SwiftData reads.
- [ ] A small banner ("Showing offline data from <date>") appears when the data is older than 7 days.
- [ ] Unit test: simulate `URLSession` failure → `exploreNearby` returns cached region's pins, sets banner state.

---

### Epic B: Smart Caching & Cost Control

#### US-B1: Region-keyed cache for Overpass queries
**Description:** As a product owner, I don't want users repeatedly burning Overpass quota by tapping "Explore here" in the same area.

**Acceptance Criteria:**
- [ ] New `ExploreCacheRecord` in SwiftData: `regionKey: String` (e.g. `"21.03_105.85_3000"`), `osmJSON: Data`, `fetchedAt: Date`, `poiCount: Int`.
- [ ] `OverpassService.fetchPOIs` consults cache first; cache hit if `now - fetchedAt < 14 days` and `regionKey` matches at 0.01° rounding (~1.1 km grid).
- [ ] Cache miss → real fetch → write through.
- [ ] Cache hit count surfaced in settings → "Storage" row ("Cached 12 regions, 248 POIs"). User-visible **Clear cache** button purges `ExploreCacheRecord` and `ExperienceRecord` rows where `id LIKE 'exp_osm_%'`.
- [ ] Unit test (`URLProtocol` stub): two consecutive `fetchPOIs` calls in same region trigger only one HTTP request.

#### US-B2: Region-keyed cache for AI synthesis results
**Description:** As a product owner, I want Claude calls deduplicated so the same OSM batch never gets re-synthesized.

**Acceptance Criteria:**
- [ ] Cache key = SHA256 of sorted `osmId` list + cityCode + locale + model name. Stored in `AISynthesisCacheRecord`.
- [ ] `AIService.synthesizeExperiences` checks the cache before calling the network. Hit → decode persisted `[Experience]` JSON. Miss → call → write through.
- [ ] TTL **30 days**.
- [ ] Cache stats exposed alongside Overpass cache in settings.
- [ ] Unit test: same input batch hits the network once, returns identical Experiences twice.

#### US-B3: Switch default synthesis model to Sonnet 4.6 with Haiku fallback
**Description:** As a product owner, I want AI generation cost to drop ~80% without a noticeable quality regression.

**Acceptance Criteria:**
- [ ] `AIService` gains `model` config: `synthesisModel = "claude-sonnet-4-6"`, `explanationModel = "claude-haiku-4-5-20251001"`, `voiceIntentModel = "claude-sonnet-4-6"`.
- [ ] `recommendExperiences` and `synthesizeExperiences` use synthesis model; `explainRecommendation` uses Haiku.
- [ ] All three are read from `Secrets.plist` keys with defaults so QA can override per-build.
- [ ] A debug flag `AI_FORCE_OPUS=1` env var still routes everything to Opus for golden-set comparison.
- [ ] Snapshot test: synthesizing 5 fixed POIs with each model produces parseable JSON of the expected shape.

#### US-B4: Hallucination-resistant synthesis prompt
**Description:** As a user, I need to trust generated content not to invent facts the model can't actually know.

**Acceptance Criteria:**
- [ ] Updated prompt explicitly instructs: "Use ONLY the provided OSM tags. Do NOT invent menu items, interior details, hours, prices, owner backstories, or specific seating positions. If a field is not derivable from tags, write a generic safe value."
- [ ] `howTo` is constrained to navigation steps only (no "order the X").
- [ ] Prompt includes 2 few-shot examples showing **good** (tag-derived, generic) vs **bad** (hallucinated specifics) outputs.
- [ ] New regression test: feed a POI with only `{amenity: cafe, name: "Quán A"}` and assert the model output's `whyItMatters` and `howTo` do **not** contain any of the banned phrase patterns (regex list of 20+ red flags).

#### US-B5: Per-user daily AI quota with graceful degradation
**Description:** As a product owner, I want a hard cap on Claude spend per user per day so a runaway loop never costs more than $1.

**Acceptance Criteria:**
- [ ] `UserPreferences` adds `aiCallsToday: Int` and `aiCallsResetDate: Date` (rolling UTC day).
- [ ] Free tier limit: 0 paid AI calls (Explore-Here disabled, see Epic D).
- [ ] Paid tier: 30 synthesis calls/day, 60 explanation calls/day. Counter increments on every Anthropic POST regardless of cache hits (cache hits don't count).
- [ ] When limit hit: feature falls back to skeleton mode + visible banner "Daily AI limit reached, resets in Xh".
- [ ] Counter persists in SwiftData (`AIUsageRecord`) — survives kills.

---

### Epic C: Trust & UX Polish for Generated Content

#### US-C1: Visual downgrade for `confidence.level == 1` Experiences
**Description:** As a user, I want to immediately tell which pins are AI-guessed vs curated.

**Acceptance Criteria:**
- [ ] `MarkerIconView` renders confidence-1 pins with: dashed stroke border, 70% opacity, no glow, smaller badge.
- [ ] Detail view: existing "AI-generated · OpenStreetMap" badge is upgraded with a tappable info icon that opens an info sheet explaining the source and recommending the user verify on-site.
- [ ] Sources section explicitly shows "© OpenStreetMap contributors" with a link to the OSM node URL.
- [ ] Verify in simulator using `xcrun simctl` and a manual screenshot review.

#### US-C2: Surface explore errors and skeleton-mode state to the user
**Description:** As a user, when AI synthesis silently fails I should know that what I'm looking at is OSM-only, and when Explore fails completely I should see why.

**Acceptance Criteria:**
- [ ] `MapViewModel.lastExploreError` is rendered as a dismissible banner (reuse existing `lastAIError` style in `CompassMapView`).
- [ ] When `synthesizeExperiences` falls back to skeleton mode, set `lastExploreInfo = "Showing real places without AI enrichment — subscribe for richer descriptions."` (free tier) or `"AI is offline."` (paid tier with API failure).
- [ ] Banner has a "Subscribe" CTA in free-tier copy linking to the paywall (Epic D).
- [ ] Unit test: force `synthesizeExperiences` to throw → assert info banner state set correctly per subscription tier.

#### US-C3: Reverse-geocode discovered regions into real city names
**Description:** As a user, I shouldn't see "osm_21.0_105.9" in my city picker — I should see "Hanoi".

**Acceptance Criteria:**
- [ ] New `ReverseGeocodeService` wraps `CLGeocoder.reverseGeocodeLocation`.
- [ ] On successful Explore: resolve coordinate → `city, countryCode`. Persist to `DiscoveredCityRecord` (cityCode = ISO-3166-2-region-or-locality-slug, name = localized).
- [ ] `MapViewModel.cityCode(for:)` consults `DiscoveredCityRecord` first; falls back to current `osm_<lat>_<lon>` only when geocoder fails or offline.
- [ ] Generated Experiences in that region get the resolved cityCode written into `ExperienceRecord.location.cityCode`.
- [ ] City picker shows real names; tapping a discovered city centers the map and loads cached pins.

#### US-C4: Auto-switch selected city after successful Explore
**Description:** As a user who lands in a new city and taps Explore, I should immediately see the new pins without manually changing the city filter.

**Acceptance Criteria:**
- [ ] After `exploreNearby` adds N > 0 generated Experiences, `MapViewModel` calls `selectCity(resolvedCityCode)` so the visible-experiences filter no longer hides them.
- [ ] If reverse-geocoding succeeded, the city name briefly toasts: "Now exploring Hanoi · 12 places added".
- [ ] If geocoding failed, fallback toast: "12 places added near you".
- [ ] Unit test: with `selectedCity = "cmi"`, run `exploreNearby` at Hanoi coords with mocked geocoder → assert `selectedCity` becomes the Hanoi cityCode.

#### US-C5b: Cold-start UX for Solo-Score (zero-signal regions)
**Description:** As a user discovering a new region, I should see a useful Solo Score on every pin — clearly marked as an AI estimate when no community data exists yet, transitioning naturally to community-backed numbers as signals arrive.

**Acceptance Criteria:**
- [ ] `SoloScore` view component takes a new `signalCount: Int` parameter and renders three visual states:
  - `signalCount == 0`: dimmed score color + "AI estimate" pill + tap-to-explain tooltip
  - `signalCount` in `1...2`: normal score + "Based on N early reports" subtext
  - `signalCount >= 3`: normal score + "Based on N solo travelers" subtext (current behavior)
- [ ] Pin marker color saturation scales with `signalCount` (dimmed when 0, full when >=3) so the map at a glance shows community-validated places more prominently than AI estimates.
- [ ] Detail view's solo-score section header reads "Solo Score (AI estimate)" / "Solo Score (early)" / "Solo Score" matching the three states.
- [ ] Unit test: render `SoloScoreView` with each of `0, 1, 2, 3, 12` signals — assert the right state markers appear.
- [ ] Snapshot test for each state in light + dark mode.

#### US-C5: MicroSurvey responses feed back into SoloScore
**Description:** As a user, my honest feedback on a place should improve its Solo Score for the next traveler — making the app smarter every week.

**Acceptance Criteria:**
- [ ] `MicroSurveySheet` writes a `MicroSurveyRecord` (rating fields + experienceId + timestamp + anonymizedDeviceId).
- [ ] `SoloScore.overall` becomes a derived computed property: `0.5 * seedOrAI + 0.5 * meanOfLocalSurveys` (weighted by `basedOnCount`). Cached on read for 60s to avoid recomputing on every render.
- [ ] `basedOnCount` reflects local survey count (cross-device count comes in Epic E).
- [ ] When a user submits a survey their immediate next view of the Experience shows the updated score.
- [ ] Unit test: submit two surveys with comfort=5, pressure=4, recommend=yes → assert resulting `overall` matches the formula.

---

### Epic D: Freemium & StoreKit 2

#### US-D1: Subscription product setup & local entitlement check
**Description:** As a developer, I need StoreKit 2 wired up with two subscription SKUs and an offline-tolerant entitlement source of truth.

**Acceptance Criteria:**
- [ ] New file `apps/ios/SoloCompass/Services/SubscriptionService.swift` (`@MainActor @Observable`). Manages `StoreKit.Product` fetch, purchase, restore, transaction listener.
- [ ] App Store Connect SKUs (created out-of-band, documented in `docs/APP_STORE.md`):
  - `com.solocompass.pro.monthly` — monthly subscription, 7-day free trial, intro offer once per Apple ID
  - `com.solocompass.pro.yearly` — yearly subscription, 7-day free trial, ~55% savings vs monthly
- [ ] `SubscriptionService.entitlement: Entitlement` is one of `.free | .proTrial | .pro | .proExpired`. Computed from `Transaction.currentEntitlements`.
- [ ] Entitlement is **cached in Keychain** so a brief offline launch still respects it.
- [ ] Listener auto-updates entitlement on renewal/cancellation.
- [ ] Unit test with `Testing` framework + `Transaction.testSession` covers: free → trial → paid → expired transitions.

#### US-D2: Paywall view
**Description:** As a free user tapping an AI-gated action, I land on a clear paywall where I can start a free trial.

**Acceptance Criteria:**
- [ ] New `apps/ios/SoloCompass/Views/Paywall/PaywallView.swift`. Shows: hero copy, two product cards (monthly / yearly with "Best value" badge), "Start 7-day free trial" CTA, fine-print, "Restore purchases" link, "Manage subscription" deep link to App Store Settings.
- [ ] Localized en + zh-Hans (`Resources/zh-Hans.lproj/Localizable.strings` created).
- [ ] Paywall reachable via `viewModel.isShowingPaywall = true` from any AI-gated CTA.
- [ ] On successful purchase: dismiss paywall, retry the original action automatically (e.g. resume `exploreNearby`).
- [ ] Verify in simulator using StoreKit testing config (`Configuration.storekit` file in `apps/ios/`).

#### US-D3: Gate AI features behind entitlement
**Description:** As the product owner, I want AI features (Explore Here synthesis, voice intent, AI explanations) to require a Pro subscription.

**Acceptance Criteria:**
- [ ] `MapViewModel.exploreNearby` and `handleVoiceTranscript` and `ExperienceDetailViewModel.requestAIExplanation` consult `SubscriptionService.entitlement`. If `.free` or `.proExpired`: route to paywall instead of network call.
- [ ] Free users still get: full map, filters, seed Experiences, completed/favorites, micro-survey, settings, **OSM-only Explore Here in skeleton mode** (no Claude call) — this is the "show, don't tell" funnel.
- [ ] The Explore button label changes to "Explore (Pro)" with a small lock icon when free.
- [ ] Detail view's "AI insight" section shows a paywall teaser instead of "Loading…" for free users.
- [ ] Unit test: as `.free`, calling `exploreNearby` sets `isShowingPaywall = true` and does not invoke `OverpassService` or `AIService`.

#### US-D4: Trial-to-paid conversion analytics
**Description:** As a founder, I need to know how many trials convert and where users drop off.

**Acceptance Criteria:**
- [ ] On every `Transaction` lifecycle event (`subscribed`, `expired`, `inGracePeriod`, `revoked`, `upgraded`), emit a Supabase `subscription_events` row (Epic E).
- [ ] Column: `device_id`, `event_type`, `product_id`, `original_purchase_date`, `expires_date`, `is_in_trial_period`.
- [ ] No PII (no email, no Apple ID).
- [ ] Local sanity log in Console for debug builds.

#### US-D5: Refund-of-trial & restore-on-fresh-install flow
**Description:** As a user reinstalling on a new phone, I shouldn't have to pay again.

**Acceptance Criteria:**
- [ ] App boot on new device with same Apple ID -> `Transaction.currentEntitlements` populates -> entitlement set to `.pro` automatically without user action.
- [ ] Settings -> "Restore purchases" button explicitly calls `AppStore.sync()` and surfaces success/failure as a toast.
- [ ] If a user cancels mid-trial inside Settings.app, app reflects `.free` within 1 minute via the transaction listener.

---

### Epic E: Supabase Backend & Cross-Device Sync

#### US-E1: Anonymous device identity via Supabase Auth
**Description:** As a user, I want my data synced without creating an account or giving an email.

**Acceptance Criteria:**
- [ ] Existing `DeviceIdentityService` extended to call `supabase.auth.signInAnonymously()` on first launch and store the resulting `userId` in Keychain.
- [ ] On subsequent launches, refresh-token flow keeps the session alive.
- [ ] On entitlement change (`.proTrial` -> `.pro`), update a `profiles` row with `entitlement_tier`.
- [ ] If the user later wants account portability, they can link Apple ID via "Sign in with Apple" — this upgrades the anonymous user to a permanent one (this US covers anon-only; Apple-link is a follow-up).
- [ ] Supabase project bootstrap script in `infra/supabase/` (SQL + RLS policies) checked in.

#### US-E2: Schema and RLS policies on Supabase
**Description:** As a developer, I need a backend schema that mirrors local SwiftData tables and enforces per-user data isolation.

**Acceptance Criteria:**
- [ ] Tables: `profiles`, `user_completions`, `user_favorites`, `micro_surveys`, `subscription_events`, `synthesized_experiences` (canonical AI output, dedupable across users), `osm_pois` (canonical OSM cache), `solo_score_signals`.
- [ ] Row-Level Security: every user-data table allows `select/insert/update/delete WHERE user_id = auth.uid()`. `synthesized_experiences` and `osm_pois` are **read-public, write-server-role**.
- [ ] Migration files in `infra/supabase/migrations/0001_*.sql`.
- [ ] Smoke test script: `infra/supabase/test_rls.ts` runs anon vs user role queries and asserts isolation.

#### US-E3: Outbox sync for user data
**Description:** As a user toggling between phone and iPad, I want my favorites and completed list to converge within seconds.

**Acceptance Criteria:**
- [ ] New `SyncService` (in `Services/`) implements outbox pattern: any local mutation to user-data tables also writes to a `PendingSyncRecord` queue.
- [ ] Background flush every 30s and on app foreground; uses Supabase's REST upsert with `If-Match` on `updated_at` for last-write-wins.
- [ ] Inbound: pull diff (`updated_at > lastPulledAt`) for each user-data table on foreground; merge into SwiftData by id.
- [ ] Conflicts resolved by `updated_at` desc (LWW); ties broken by `device_id` lex order.
- [ ] Unit test: simulate two devices mutating the same favorite — assert eventual consistency after one round-trip each.

#### US-E4: Server-side AI synthesis cache (sharing across users)
**Description:** As a product owner, when User A in Hanoi has paid for AI synthesis of a region, User B's nearby request should reuse it for free.

**Acceptance Criteria:**
- [ ] `AIService.synthesizeExperiences` consults Supabase `synthesized_experiences` table by region+POI hash before calling Claude.
- [ ] On cache miss + paid call: write the result back to `synthesized_experiences` (server-role via a Supabase Edge Function with service-role key — client never has it).
- [ ] Free users **read** the shared cache (so a paid user's exploration "lights up" the area for everyone) — this is the core flywheel and a marketing hook.
- [ ] Edge Function `synthesize-experiences` (Deno/TS) does the Anthropic call server-side, validates the response, dedup-writes to `synthesized_experiences`. Client just calls the function.
- [ ] **API key never ships in the iOS app after this milestone.** `Secrets.plist` `ANTHROPIC_API_KEY` is removed.
- [ ] Edge Function rate-limits per `auth.uid()`: 30 calls/day for Pro, 0 for free.

#### US-E6: Optional Sign-in-with-Apple to upgrade anonymous account
**Description:** As a user who wants Family Sharing eligibility or extra account-recovery safety, I want to link my anonymous Solo Compass account to my Apple ID without losing my data.

**Acceptance Criteria:**
- [ ] Settings has a new row under "My Data": **"Save with Apple"** (when anonymous) / **"Linked to Apple ID"** (when linked).
- [ ] Tapping "Save with Apple" presents the system Sign-in-with-Apple sheet. On success, calls `supabase.auth.linkIdentity(provider: .apple)` to merge the anonymous user into a permanent one.
- [ ] All existing local SwiftData rows keep their `anonUserId` linkage; the Supabase `profiles` table updates `is_anonymous = false` and stores the Apple email relay (private relay, not real email).
- [ ] No Apple ID data leaves the device beyond what Supabase Auth needs (sub claim + email relay). Documented in `docs/PRIVACY.md`.
- [ ] If link fails (network, user cancels): toast "Couldn't link account. Your data is still saved on this device." No data is lost or corrupted.
- [ ] Family Sharing: linked accounts that share a Family receive Pro entitlement automatically via StoreKit Family Sharing (already supported by `Transaction.currentEntitlements`); document the limit (one paying organizer + 5 family members).
- [ ] Unit test (`Transaction.testSession` + Supabase mocked): anonymous user with 3 favorites and 1 micro-survey links to Apple → assert all rows now belong to permanent userId, anon session is deleted server-side.

#### US-E5: Solo-Score signal aggregation
**Description:** As a user, I should see Solo Scores that reflect actual community use, not just AI guesses.

**Acceptance Criteria:**
- [ ] On every micro-survey submit, `SyncService` writes a `solo_score_signals` row (anon user_id, experienceId, comfort, pressure, recommend, timestamp).
- [ ] Nightly Supabase scheduled function recomputes `synthesized_experiences.aggregated_solo_score` (mean/median + sample size) for each experienceId.
- [ ] Client pulls the aggregate on app foreground and merges into `ExperienceRecord.soloScore` if `signal_count >= 3`.
- [ ] Detail view displays "Based on N solo travelers" using the real count.

---

### Epic F: App Store Readiness & Privacy

#### US-F1: Privacy manifest and ATT prompt
**Description:** As an App Store applicant, I need a privacy manifest declaring data use and ATT prompts where appropriate.

**Acceptance Criteria:**
- [ ] `apps/ios/SoloCompass/Resources/PrivacyInfo.xcprivacy` lists: precise location, coarse location, device ID (Supabase anon), purchases (StoreKit), diagnostics (Supabase events).
- [ ] No data is marked as used for tracking. ATT prompt skipped (not needed without tracking).
- [ ] Privacy policy at `https://solocompass.app/privacy` (placeholder OK; URL configured in `Info.plist`).
- [ ] First-run onboarding screen explains: location stays on device + sent to OSM/Anthropic during Explore Here; entitlement events sent to Supabase for sync; nothing else.

#### US-F2: First-run Explore-Here consent screen
**Description:** As a privacy-conscious user, I want a clear opt-in moment before my coordinates leave the device.

**Acceptance Criteria:**
- [ ] New view `Onboarding/ExploreConsentSheet.swift` shown the first time the user taps Explore Here.
- [ ] Explains: "Tapping Explore here sends your map center coordinate to OpenStreetMap (free, anonymous) and to our AI server. We never store who asked, only what was asked, for 30 days."
- [ ] Two buttons: "Continue" (proceeds + sets `userPreferences.exploreConsentGivenAt`) and "Not now".
- [ ] Subsequent taps skip the sheet.
- [ ] Settings has a "Revoke consent" row that clears the flag and disables Explore Here.

#### US-F3: Schema parity check across iOS and TypeScript
**Description:** As a developer, I need `pnpm parity:check` to cover the new fields so future changes don't drift.

**Acceptance Criteria:**
- [ ] `packages/core/src/experience.ts` adds the same prefixes (`exp_osm_`), confidence-level-1 semantics, and `discoveredCity` types as iOS.
- [ ] `scripts/check-swift-parity.ts` extended to check the new model classes vs TS types.
- [ ] CI job `.github/workflows/ci.yml` runs `pnpm parity:check` and fails on drift.
- [ ] PR template adds checkbox: "Updated TS schema if Swift schema changed."

#### US-F4: Localization for zh-Hans
**Description:** As a Chinese-language user, I want the app and paywall in Simplified Chinese.

**Acceptance Criteria:**
- [ ] `Resources/zh-Hans.lproj/Localizable.strings` covers every key in `en.lproj`. Translations done by hand for app-store-visible strings (paywall, onboarding, Explore button, errors).
- [ ] App Store description, keywords, screenshots have zh-Hans variants.
- [ ] Default fallback to English remains for missing keys.

#### US-F5: TestFlight beta and App Store metadata
**Description:** As a founder, I want a TestFlight build with 20 beta testers feeding usage data before public launch.

**Acceptance Criteria:**
- [ ] `.github/workflows/testflight.yml` already exists; verify it works on this branch and uploads on tag `v1.1.0-beta.N`.
- [ ] App Store Connect entry filled: name, subtitle, keywords (en + zh), 6 screenshots per locale (iPhone 17 Pro), category Travel, age 4+.
- [ ] In-app review prompt (`SKStoreReviewController.requestReview()`) triggered after the user marks 3rd Experience completed (not before).
- [ ] Beta tester invite list documented in `docs/BETA.md`.

---

## 4. Functional Requirements

### Persistence
- **FR-1:** All Experiences (seed, OSM-generated, user-added) stored in SwiftData; bundle seed imported once on first launch.
- **FR-2:** User completion, favorites, and micro-surveys stored in SwiftData; legacy `UserDefaults` arrays migrated automatically.
- **FR-3:** SwiftData schema is versioned; v1 schema declared explicitly to allow future migrations.

### Caching & Cost
- **FR-4:** Overpass results cached for 14 days, keyed by 0.01 degree rounded coordinate + radius.
- **FR-5:** Claude synthesis results cached for 30 days locally and indefinitely server-side via Supabase.
- **FR-6:** Default synthesis model is Sonnet 4.6; explanation model is Haiku 4.5; Opus is gated behind a debug flag only.
- **FR-7:** Per-user daily AI quota: free=0, Pro=30 syntheses + 60 explanations.

### Trust & UX
- **FR-8:** Pins with `confidence.level == 1` render with dashed border, 70% opacity, and an info disclosure in detail view.
- **FR-9:** OSM-derived Experiences must include `(c) OpenStreetMap contributors` in `sources` and link to the node URL.
- **FR-10:** Synthesis prompt forbids invented specifics (menu items, hours, prices, interior details, owner backstories).
- **FR-11:** Reverse geocoding resolves city names; falls back to `osm_<lat>_<lon>` only when geocoder fails.

### Freemium & Monetization
- **FR-12:** Two subscription products with **globally uniform Apple price tiers** (auto-converted per region by App Store):
  - Monthly: Apple price tier 2 (~$1.99 USD; ¥12 CNY; €1.99; ¥300 JPY).
  - Yearly: Apple price tier 11 (~$14.99 USD; ¥98 CNY; €14.99; ¥2200 JPY).
  - Both with 7-day intro free trial.
- **FR-13:** AI features (Explore Here synthesis, voice intent, AI explanations) require `entitlement` in `{.proTrial, .pro}`. Free users see paywall instead.
- **FR-14:** Free users still receive OSM skeleton mode for Explore Here so they see value before subscribing.
- **FR-15:** Restore purchases works without sign-in via Apple ID.
- **FR-16:** Entitlement cached in Keychain for offline boot.
- **FR-16b:** Sign-in-with-Apple linking is supported in v1.1 (US-E6) and unlocks Family Sharing eligibility; remains optional.

### Backend & Sync
- **FR-17:** Supabase anonymous auth on first launch; `userId` persisted in Keychain.
- **FR-18:** Outbox sync flushes every 30 s and on foreground; LWW conflict resolution.
- **FR-19:** All Anthropic calls go through a Supabase Edge Function after Epic E ships; the iOS app no longer holds the API key.
- **FR-20:** Solo-Score aggregates recomputed nightly server-side; clients pull on foreground.
- **FR-24 (Local-first invariant):** SwiftData is the source of truth for every UI read. The app must be fully usable with Supabase unreachable: full map, all generated Experiences, completed/favorites, micro-survey submission (queued for later), entitlement check (Keychain cache). Backend writes are best-effort; failure must never block a UI action or surface a blocking error.
- **FR-25:** Supabase region: Singapore (`ap-southeast-1`) for v1.1; Tokyo failover documented but not provisioned.

### Privacy & Compliance
- **FR-21:** `PrivacyInfo.xcprivacy` declares all collected data types accurately; nothing is used for tracking.
- **FR-22:** First-run consent sheet required before Explore Here ever sends coordinates off-device; revocable in Settings.
- **FR-23:** Privacy policy URL configured in `Info.plist` and reachable.

---

## 5. Non-Goals (Out of Scope)

- **No social graph.** No friends, no public profiles, no following, no likes from other users.
- **No web app or bot in this PRD.** Supabase schema is shared so they can land later, but `apps/web` and `apps/bot` are not built in v1.1.
- **No mandatory sign-in.** Sign-in-with-Apple is optional (US-E6) and only used to upgrade an anonymous account. The default flow stays anonymous.
- **No offline basemap tiles.** Offline mode shows pins and detail data on Apple's blank basemap; downloading MapKit tiles is post-v1.1.
- **No third-party POI sources** beyond OpenStreetMap (no Foursquare, Google Places, Yelp, TripAdvisor).
- **No human moderation queue** for AI content in v1.1; rely on prompt constraints + visual downgrade. Moderation is v1.2.
- **No analytics SDKs** (no Mixpanel/Amplitude/Sentry). All events go to our own Supabase tables.
- **No push notifications beyond the existing geofence check-in nudge.**
- **No iPad-optimized layout.** App runs on iPad but UI is the iPhone layout scaled.
- **No referral / promo-code system in v1.1.** Standard Apple promo codes via App Store Connect only.

---

## 6. Design Considerations

- **Reuse existing components:** `MarkerIconView`, `ConfidenceBadge`, `ExperienceCardView`, `BottomInfoBar`, `FilterBarView`. No design system overhaul.
- **Paywall visual style:** Match existing `.regularMaterial` / SF Symbols aesthetic; no animated gradients or stock illustration. One product hero + two cards.
- **Skeleton-mode pin:** dashed stroke outline + 70% opacity (already prototyped for the long-press candidate marker — reuse that path).
- **City picker:** discovered cities show a small sparkle icon next to the name to indicate AI-explored; curated cities (Chiang Mai today) show a star icon.
- **Toasts:** lightweight `Capsule()` over `BottomInfoBar`, auto-dismiss in 3 s. Reuse the AI-error banner pattern.
- **Free vs Pro affordance:** Lock icon on the Explore button when free; subscribe CTA in info banners. No nag screens or interstitials.

---

## 7. Technical Considerations

### Stack additions
- **SwiftData** — iOS 17+ (already deployment target).
- **StoreKit 2** — new dependency, no third-party.
- **Supabase Swift SDK** — `supabase-swift` via SPM (one of the few cases the project breaks its "zero deps" rule; documented in `CLAUDE.md`).
- **Supabase project** — single project, two schemas (`public`, `private`). Hosted on Supabase Cloud (free tier covers the first 50k MAU; budget upgrade documented).
- **Supabase Edge Functions** — Deno runtime; one function (`synthesize-experiences`) holds the Anthropic key.

### Migration path
1. Land Epic A (persistence) on `feat/persistence-swiftdata` — no behavior change for users.
2. Land Epic B (caching + Sonnet) on `feat/ai-cost-control`.
3. Land Epic C (UX polish) on `feat/explore-trust`.
4. Land Epic D (StoreKit) on `feat/freemium-paywall` — first user-visible paid moment.
5. Land Epic E (Supabase) on `feat/backend-sync` — removes API key from client; this is the highest-risk merge and gets staged behind a feature flag.
6. Land Epic F (privacy/store) on `feat/app-store-prep` — final polish.
7. Tag `v1.1.0-beta.1`, push to TestFlight, gather 2 weeks of feedback, then `v1.1.0`.

### Feature flags
- `FF_BACKEND_SYNC` — gates Supabase calls; off by default in beta.1, on by beta.3.
- `FF_PAYWALL_ENABLED` — lets us TestFlight without showing the paywall to early testers.
- Stored in `Resources/FeatureFlags.plist` and overridable via launch args.

### Performance budgets
- App cold-start time: <= 1.0 s on iPhone 14 (currently ~0.7 s; SwiftData container init must not regress).
- Map first-pin-render: <= 300 ms after location lock.
- Explore Here end-to-end (cache miss): <= 6 s on a good network; (cache hit): <= 200 ms.
- Sync round-trip: <= 1 s on 4G.
- SwiftData query for "experiences within 5 km, filtered by category": <= 50 ms with 1000 records.

### Risks
- **R1 — SwiftData migrations are fragile.** Mitigate by versioning the schema from day 1 and never modifying v1 in place.
- **R2 — Apple may reject "anonymous account auto-creation".** Mitigate by making the anonymous account explicit in onboarding ("Solo Compass uses an anonymous device ID to sync across your devices. No email needed.").
- **R3 — Supabase Edge Function cold start.** First call may take 2–3 s; warm pings every 5 min via cron. Document fallback (skeleton mode if Edge Function times out).
- **R4 — Sonnet output quality regression vs Opus.** Mitigate via golden-set snapshot tests in US-B3 and ability to toggle back.
- **R5 — Server-side cache "lights up regions for free users" creates a vector for Pro users to feel cheated.** Counter by making the value of Pro about *speed of fresh exploration* + *daily quota* + *future AI features*, not exclusivity of past cache hits. Document this in the paywall copy.

---

## 8. Success Metrics

### North-Star
- **Daily Active Paid Users (DAPU)** — target 200 by week 4 post-launch.

### Activation
- >= 60% of users who tap "Explore Here" on free tier reach the paywall.
- >= 15% of paywall views start the free trial.
- >= 40% of trials convert to paid (industry benchmark: 30-50% for utility apps).

### Retention
- Day-7 retention free: >= 25%.
- Day-7 retention paid: >= 60%.
- Day-30 retention paid: >= 40%.

### Cost
- Average AI cost per paid user per day <= $0.30.
- >= 50% of synthesis requests served from cache after week 4 (the flywheel).

### Trust / Quality
- < 5% of generated Experiences flagged via Report Issue ("factually incorrect").
- >= 60% of generated Experiences in a region get at least 1 micro-survey within 60 days.

### Engineering
- All 6 epics ship within a 6-week calendar window.
- `xcodebuild test` passes on every PR; coverage on new code >= 75%.
- Zero P0 crashes in production for 14 days post-launch (measured via Apple's Crashes & Energy logs).

---

## 9. Resolved Decisions & Remaining Open Questions

### Resolved (decided 2026-05-09 with @cubxxw)

1. **Pricing — globally uniform USD-anchored tiers (Apple auto-converts).**
   - Monthly: **Apple price tier 2** (~$1.99 USD; ¥12 CNY; ¥300 JPY; €1.99 EUR). Anchor product, lowers friction.
   - Yearly: **Apple price tier 11** (~$14.99 USD; ¥98 CNY; ¥2200 JPY; €14.99 EUR). ~37% savings, nudges to annual.
   - Both with **7-day free trial**. No per-region discounts; same Apple tier ID applied everywhere — App Store auto-converts to local currency at Apple's official tiers, removing the need to maintain a price matrix.
   - Documented in `docs/APP_STORE.md` for ASO localization.

2. **Sign-in-with-Apple linking — included in v1.1.**
   - Promoted from Epic E follow-up to **US-E6** (new). Anonymous users can optionally tap "Save my data with Apple" in Settings to link their session, enabling Family Sharing eligibility from day 1 and protecting against accidental anon-token loss.
   - Still optional — anonymous-only flow remains the default.

3. **Backend posture — local-first, cloud as cache & sync only.**
   - SwiftData remains the **source of truth** for every read in the UI. Supabase serves three purposes: (a) outbox sync target; (b) shared AI synthesis cache; (c) Edge Function host for the Anthropic key.
   - The app must be **fully usable with Supabase unreachable**. All sync writes are best-effort; all reads can be served entirely from local SwiftData.
   - Supabase region: **Singapore** (`ap-southeast-1`) — closest to expected APAC user base; Tokyo as failover region documented but not provisioned in v1.1.
   - This is a stronger constraint than the original draft; it adds explicit **FR-24** below and is reflected in updated US-E3 acceptance criteria.

4. **Solo-Score cold-start — show a clearly-marked AI estimate, not a hidden field.**
   - When `signal_count == 0`: render the score with a small "AI estimate" pill and dimmed color; tooltip on the score reads "Estimated by AI from venue tags. Solo travelers haven't reported in yet."
   - When `signal_count` between 1–2: render normally but show "Based on N early reports" instead of the usual basedOn copy.
   - When `signal_count >= 3`: full-strength score, "Based on N solo travelers".
   - This is the best UX trade-off — hiding the score makes the map feel empty for new regions, but unmarked AI estimates would erode trust over time. Documented as **US-C5b** below.

### Remaining open (defer)

- **OSM attribution placement.** Sources section is fine for ODbL legal minimum; consider a one-line credit at the bottom of the detail view in v1.2 if any contributor flags it. *Owner: @cubxxw, beta-stage decision.*
- **Skeleton-mode richness.** OSM name + tag-derived category is the v1.1 minimum. If beta users say "this looks empty," add one heuristic-driven sentence (template per category) in a hot-fix. *Owner: product, validate in beta.*
- **Refund policy for hitting daily AI quota.** Standard Apple refund process applies; we'll publish a one-line "no manual refunds for quota usage" policy in the paywall fine print. *Owner: @cubxxw, before App Store submission.*
- **Edge Function language.** Deno/TS confirmed by default to keep the team in one language. *Owner: @cubxxw.*

---

## 10. Sequencing Summary

| Week | Focus | Branches | Deliverable |
|---|---|---|---|
| 1 | Epic A: Persistence | `feat/persistence-swiftdata` | All data on disk; no UX change |
| 2 | Epic B: Cost control | `feat/ai-cost-control` | Sonnet default + caching live |
| 3 | Epic C: Trust UX | `feat/explore-trust` | Visual downgrade + reverse geocode + survey feedback |
| 4 | Epic D: StoreKit | `feat/freemium-paywall` | Paywall live behind FF |
| 5 | Epic E: Supabase | `feat/backend-sync` | Server cache + sync + key removed from client + optional Apple ID link (US-E6) |
| 6 | Epic F: Store prep | `feat/app-store-prep` | TestFlight beta.1 |
| 7-8 | Beta feedback | hot-fix branches | `v1.1.0` GA |

---

## 11. Appendix — Files Touched (estimated)

**New files (~25):**
- `Persistence/SoloCompassModelContainer.swift`
- `Persistence/Models/*.swift` (~13 `@Model` classes)
- `Persistence/ExperienceRepository.swift`
- `Persistence/SyncService.swift`
- `Services/SubscriptionService.swift`
- `Services/ReverseGeocodeService.swift`
- `Services/SupabaseClient.swift`
- `Views/Paywall/PaywallView.swift`
- `Views/Onboarding/ExploreConsentSheet.swift`
- `Resources/zh-Hans.lproj/Localizable.strings`
- `Resources/Configuration.storekit`
- `Resources/PrivacyInfo.xcprivacy`
- `infra/supabase/migrations/0001_init.sql`
- `infra/supabase/functions/synthesize-experiences/index.ts`
- `docs/APP_STORE.md`, `docs/BETA.md`, `docs/PRIVACY.md`
- `tests/persistence/`, `tests/subscription/`, `tests/sync/`

**Modified (~12):**
- `Services/AIService.swift` — model config + cache + Edge Function call
- `Services/OverpassService.swift` — cache integration
- `Services/ExperienceService.swift` — repo facade
- `ViewModels/MapViewModel.swift` — entitlement gates + auto city switch
- `ViewModels/ExperienceDetailViewModel.swift` — survey writeback
- `Views/Map/CompassMapView.swift` — paywall sheet, banner upgrades
- `Views/Map/MarkerIconView.swift` — confidence-1 visual downgrade
- `Views/Experience/ExperienceDetailView.swift` — paywall teaser, source link
- `Models/UserPreferences.swift` — quota fields, consent flags
- `App/SoloCompassApp.swift` — ModelContainer, SubscriptionService injection
- `project.yml` — capabilities (in-app purchase, Supabase URL config)
- `packages/core/src/experience.ts` — schema parity

---

*End of PRD. Implementation starts on `feat/persistence-swiftdata` after PRD approval.*
