# Gradual Rollout Playbook — v1.0 GA (#391)

Owner: release captain
Timeline: 3 weeks post Phase 3 beta exit

Every stage below has an exit criterion. Do NOT advance until met.

## Stage 0 — Prep

- [ ] `xcodebuild build + test` full suite green on `macos-latest` CI.
- [ ] `docs/BETA_TEST_CHECKLIST.md` marked PASS.
- [ ] App Store Connect: v1.0 build submitted for review, review passed.
- [ ] Phased release toggle ENABLED in App Store Connect.
- [ ] AnalyticsService dashboard connected to the 9 event names
  (`AnalyticsService.EventName`).

## Stage 1 — 10% (day 1–7)

- Rollout controls: App Store Connect "Phased Release for Automatic
  Updates" set to 10% (day 1). Users on prior versions still get the
  update at Apple's default schedule.
- Watch:
  - Crash-free session rate ≥ 99.5% (Sentry `SentryService`).
  - `paywall_shown` → `iap_success` conversion ≥ 60% of the beta
    baseline (see `docs/METRICS_VALIDATION.md`).
  - AI response time p95 ≤ 3.5s.
- Exit: 5 consecutive days with all three signals in band.
- Abort: crash-free < 99% OR conversion < 40% of baseline. Roll back
  via App Store Connect phased release control.

## Stage 2 — 50% (day 8–14)

- Advance the phased release slider to 50%.
- Watch (in addition to Stage 1):
  - `capsule_buried` events per DAU ≥ 0.05 (target 1 in 20 users
    buries at least one capsule this week).
  - `blindbox_started` events per DAU ≥ 0.02.
  - `agent_hint_accepted` events per DAU ≥ 0.15.
- Exit: 5 consecutive days.
- Abort: any of the three engagement floors missed for 3 consecutive
  days → hold at 50% and diagnose before advancing.

## Stage 3 — 100% (day 15+)

- Advance to 100%.
- Continue watching Stage 1 + 2 signals for 14 days.
- File `#393 GA sign-off` in `docs/V_NEXT_DESIGN.md` after 14 clean
  days.

## Rollback protocol

If a Stage 1 abort fires:
1. Immediate: phased release paused via App Store Connect.
2. Hotfix build submitted within 48h with the isolated fix.
3. Post-mortem written to `docs/incidents/YYYY-MM-DD-v1.0-abort.md`.
4. Restart Stage 1 with the hotfix build; the counters reset.

## Manual toggle backdoors

For emergency shutdown of a runaway new surface:
- Blindbox: no runtime kill switch — must ship hotfix removing
  `BlindboxLaunchView` entry point.
- Capsule: `CapsuleStore` writes are best-effort; UI kill = strip the
  long-press handler in `ExperienceDetailView`.
- Chat memory: `MemoryDigestService.setUseLLM(false)` disables the
  LLM enrichment path immediately (deterministic on-device path
  remains). Ships as a UserDefaults flag next hotfix if needed.
