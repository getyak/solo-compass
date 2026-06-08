# Friend → Companion → Chat → Upgrade — End-to-End Regression Checklist

**Story:** US-027 (Friends Social Graph PRD, `tasks/prd-friends-social-graph.md`)
**Scope:** the full social loop —
`scan-add-friend → friend invites to meetup → meetup builds group chat → someone in group [Add Friend] → mutual upgrade → DM + push`.
**Harness:** `scripts/qa/two-sim-friend-loop.sh` (two-simulator, half-automated).

> **Why half-automated.** On Xcode 26.4 / iOS 26.4 the UI-driving tools
> (`idb`, AppleScript taps) are broken on this machine. Only `simctl
boot/install/launch/screenshot/openurl/push` are reliable. The harness owns
> the deterministic plumbing (boot both sims, inject `FF_COMPANION` +
> Supabase env, capture labelled screenshots, deliver APNs, assert backend
> rows); the tester performs the in-app taps and ticks the boxes below.

---

## 0. Environment matrix

| Var                                       | flag-on (real backend)                                                                           | flag-off (local no-crash) |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------ | ------------------------- |
| `FF_COMPANION` (`FeatureFlags.companion`) | `1`                                                                                              | `0`                       |
| `SUPABASE_URL` / `SUPABASE_ANON_KEY`      | **required**, two authed sessions (User A, User B)                                               | unset                     |
| Migrations deployed                       | `0008`–`0011` (`friend_requests`, `friendships`, `friend_codes`, `device_push_tokens`, rotation) | n/a                       |
| Edge Functions live                       | `redeem-friend-code`, `friend-request-notify`, `message-notify`                                  | n/a                       |
| Sims                                      | `SIM_A` = User A (scanner), `SIM_B` = User B (owner/host)                                        | both                      |

Run:

```bash
# flag-on full loop (real backend)
SUPABASE_URL=... SUPABASE_ANON_KEY=... \
  DATABASE_URL='postgres://...'  \
  PUSH_B_JSON=scripts/qa/fixtures/push-message.apns.json \
  scripts/qa/two-sim-friend-loop.sh

# flag-off local no-crash smoke
FLAG=off scripts/qa/two-sim-friend-loop.sh
```

Each step leaves PNG evidence under
`artifacts/two-sim-friend-loop/<timestamp>/`.

---

## 1. Severity rubric

| Sev    | Meaning                                                           | Gate                  |
| ------ | ----------------------------------------------------------------- | --------------------- |
| **P0** | Loop blocked / crash / data loss / push never arrives             | must be **0** to ship |
| **P1** | Step works but wrong state, security/privacy leak, silent failure | must be **0** to ship |
| P2     | Cosmetic / copy / non-blocking UX                                 | track, don't block    |

A loop step that fails **must** be filed against the row's _Critical path?_
column. **No P0/P1 on any critical-path row is the acceptance gate.**

---

## 2. flag-ON critical-path loop (real backend)

| #   | Step                                                                | Expected                                                                                     | Backend assert                                                                                                                                                                                                  | Critical? | Result |
| --- | ------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- | ------ |
| 2.1 | User B: Me → Add Friend → reveal friend code (QR + text)            | A 6-char code + QR render; rotating revokes the old one (`FriendService.rotateFriendCode`)   | `friend_codes` has 1 active row for B (`revoked_at is null`)                                                                                                                                                    | ✅        | ☐      |
| 2.2 | User A: Add Friend → scan / type B's code → redeem                  | `redeem-friend-code` returns B's profile; A sees B as friend                                 | `select count(*) from friendships where status in ('accepted','active')` > 0                                                                                                                                    | ✅        | ☐      |
| 2.3 | B receives friend-added push/notice                                 | `friend-request-notify` → APNs banner on B                                                   | `device_push_tokens` has a row for B                                                                                                                                                                            | ✅        | ☐      |
| 2.4 | User B: open Route → Invite friends → select A → send meetup invite | A gets a companion/meetup invite                                                             | `companion_requests` row pending                                                                                                                                                                                | ✅        | ☐      |
| 2.5 | User A: accept the meetup invite → group chat opens                 | Both land in the SAME thread; iOS shows `type == groupRoute`, `routeId` set                  | `select count(*) from conversations where jsonb_array_length(participant_ids) > 1` > 0 (backend has no `type` col — it's an iOS-model field; route-group persistence lives in the `0005_route_companion` draft) | ✅        | ☐      |
| 2.6 | In group chat, tap **[+ Add Friend]** on the OTHER member           | `AddFriendButton.send()` fires; pending request created (`source = .groupChat` / companion)  | `friend_requests` row pending between the two                                                                                                                                                                   | ✅        | ☐      |
| 2.7 | Other side accepts → mutual upgrade                                 | Both now mutual friends; button flips to "Friends"                                           | `friendships` row `accepted/active` for the pair                                                                                                                                                                | ✅        | ☐      |
| 2.8 | Open mutual friend's profile → Message → send DM                    | A direct thread opens; iOS `type == friendDirect`, `requestId == nil`, `isReadOnly == false` | `select count(*) from conversations where request_id is null` > 0 (migration `0008` relaxed `request_id` to NULL for friendDirect DMs)                                                                          | ✅        | ☐      |
| 2.9 | DM delivers a push to the recipient                                 | `message-notify` → APNs banner; tapping deep-links into the DM thread                        | message row persisted; push delivered                                                                                                                                                                           | ✅        | ☐      |

> Backend asserts 2.2 / 2.5 / 2.8 are run automatically by the harness when
> `DATABASE_URL` is set (`sql_assert`). 2.1 / 2.3 / 2.4 / 2.6 / 2.7 / 2.9 are
> verified visually + by the queries listed (run them by hand if needed).

---

## 3. flag-OFF local no-crash (local-first invariant, PRD G7)

With `FF_COMPANION=0`, every gated `FriendService` / sync path early-returns
`featureDisabled` and no outbox rows are created. The app must stay usable
local-only and **must not crash**.

| #   | Step                                                           | Expected                                                                               | Result |
| --- | -------------------------------------------------------------- | -------------------------------------------------------------------------------------- | ------ |
| 3.1 | Launch with `FF_COMPANION=0`                                   | App boots to the map; no crash                                                         | ☐      |
| 3.2 | Reach Me → Friends / Add Friend entry points                   | Gated entries hidden OR no-op (no spinner-forever, no crash)                           | ☐      |
| 3.3 | Trigger any `FriendService` action that could fire (defensive) | Returns `FriendServiceError.featureDisabled`; UI shows a graceful empty/disabled state | ☐      |
| 3.4 | Background / foreground / cold relaunch                        | No SwiftData migration crash; local data intact                                        | ☐      |
| 3.5 | Existing solo flows (map, filters, voice, routes)              | Fully functional — friends being off changes nothing else                              | ☐      |

---

## 4. Regression guard rows (don't re-break neighbours)

| #   | Area                         | Check                                                                                                                             | Result |
| --- | ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ------ |
| 4.1 | Conversation decode          | Legacy payloads with no `type` default to `oneOnOne`; `friendDirect` decodes with `requestId == nil` (`Conversation.init(from:)`) | ☐      |
| 4.2 | Friend-code rotation         | Redeeming a **revoked** code fails cleanly (not a crash); only the newest code works (migration `0011`)                           | ☐      |
| 4.3 | Self-friend guard            | Redeeming your OWN code → `cannotFriendSelf`, no row written                                                                      | ☐      |
| 4.4 | Rate limit / expiry (US-025) | Spammed requests are throttled; expired requests can't be accepted                                                                | ☐      |
| 4.5 | Push token absence           | If `device_push_tokens` has no row, message send still succeeds locally; no crash, just no banner                                 | ☐      |
| 4.6 | Parity                       | `pnpm parity:check` green if `packages/core` friend/conversation schema touched                                                   | ☐      |

---

## 5. Sign-off

- [ ] flag-ON: all §2 critical rows pass against the real backend.
- [ ] flag-OFF: all §3 rows pass; **no crash**.
- [ ] §4 regression rows pass.
- [ ] Screenshot evidence archived under `artifacts/two-sim-friend-loop/<ts>/`.
- [ ] **P0 count = 0, P1 count = 0 on every critical-path row.**

| Field              | Value       |
| ------------------ | ----------- |
| Tester             |             |
| Build (commit)     |             |
| Date               |             |
| Sims (A / B)       |             |
| P0 / P1 / P2 found | / /         |
| Verdict            | PASS / FAIL |

---

## Appendix — defect log template

```
ID:        US027-NNN
Severity:  P0 | P1 | P2
Step:      2.x / 3.x / 4.x
Title:     <one line>
Repro:     <numbered steps>
Expected:  <…>
Actual:    <…>
Evidence:  artifacts/two-sim-friend-loop/<ts>/<png>
Owner:     <…>
```
