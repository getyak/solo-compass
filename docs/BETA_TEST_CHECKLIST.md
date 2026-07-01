# Beta Test Checklist — Phase 2 Exit (#291)

Owner: release captain
Duration: 1 week, TestFlight internal ring only

Do not push a build to external testers until every item in §1 passes on
real hardware. §2 items are informational — capture data, don't gate.

## §1 Must-pass on device

### Live Activity rate limits
- [ ] `soloAgentHint` fires at most 3× / calendar day (`UserDefaults` key
  `solo.liveactivity.count.soloAgentHint.<yyyy-MM-dd>` observable via
  Xcode → Devices → App Data).
- [ ] `dailyOmen` fires at most 1× / calendar day.
- [ ] `timeCapsule` is uncapped and always fires on region enter with a
  ripe capsule present.
- [ ] Cross-midnight reset: counters restart at 00:00 local.
- [ ] Reduce Motion respected: kill animation on capsule reveal +
  blindbox reveal + omen flip.

### Capsule accuracy
- [ ] Bury a text capsule scheduled for **3 months**. Manually rewind
  the device clock to that date (Settings → General → Date & Time,
  disable Automatic). Open app → capsule appears in Archive's "Ripe"
  band → open triggers CapsuleOpenView with the exact text.
- [ ] Bury at experience A, walk to experience B — B's region enter
  MUST NOT surface A's capsule.
- [ ] After "Forget me" (Settings → Data → Forget me), all buried
  capsules are gone from Archive and never re-surface on subsequent
  region enters.

### Blindbox safety
- [ ] Fresh-install user: blindbox picks only experiences with
  `soloScore ≥ 7.0` AND `confidence.level ≥ 3`. Verify by seeding a
  known low-confidence experience and confirming it's excluded.
- [ ] "Reshuffle" costs $0.00 — no paywall prompt, no consumable IAP
  charge.
- [ ] Blindbox running: closing the sheet ends the trip (in-memory
  orchestrator drops).

### Data hygiene
- [ ] "Forget me" clears AgentMemorySnapshot + TasteProfile in a
  single transaction. Chat opened afterwards has NO memory block in
  the system prompt (inspect `orch.currentSystemPrompt`).
- [ ] `AnalyticsService.pendingCount` after 5 minutes of active use
  is between 3 and 30. Opt-out flips it to 0 within one click.

## §2 Informational (capture, don't block)

- Baseline TTI (cold start → first frame of CompassMapView) on
  iPhone 15 Pro. Target ≤ 1.2s.
- LiveActivity throttle: watch for cases where 3+ hint triggers land
  in one hour and confirm only 3 make it to the island.
- Blindbox candidate pool size on a real-world seeded city (Chiang Mai
  seed). Should be ≥ 8 unique experiences.
- MusicKit status: `MusicService.permissionState` — expected
  `.unavailable` on internal ring pre-entitlement.

## §3 Regression must-not-happen

- [ ] Phase 1 baseline: Archive tab still populated, taste profile
  still updating after 5 visits, MeSheet segmented tab still swaps
  Archive / Me content.
- [ ] Chat still surfaces cards from `explore_nearby` /
  `filter_by_category` / `show_details` / `build_route` — the 4
  original tools MUST continue to work end-to-end.

## Sign-off

Beta lead marks this file `PASS` (add a line `pass 2026-xx-xx by …`)
before promoting to external testers. Any failed check blocks the
promotion until fixed OR explicitly waived here with rationale.
