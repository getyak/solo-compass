# Privacy

> Last updated 2026-05-06. Ground truth lives here; the bot's `/privacy`
> command and the web app's privacy footer link to this file.

Solo Compass is built for solo travelers. People moving through unfamiliar
places under their own name carry asymmetric privacy risk — so we collect as
little as possible, hash what we have to keep, and surface the opt-out paths
in the same flow that creates the data.

## What we collect, datum by datum

| Datum                       | Where collected        | Stored as                                                                                                                               | Retention                                                                   | Purpose                                  | Opt-out path                              |
| --------------------------- | ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- | ---------------------------------------- | ----------------------------------------- |
| Telegram `user_id`          | Telegram bot           | **Hashed** with SHA-256 + server salt at the edge. Never persisted raw.                                                                 | Hash retained 30 days then rotated; salt rotation invalidates older hashes. | Distinguish sessions for retention math. | `/optout`                                 |
| Telegram `username`, name   | Telegram bot           | Not stored.                                                                                                                             | n/a                                                                         | n/a                                      | n/a                                       |
| Voice note bytes            | Telegram bot → Whisper | Held in memory only during transcription. Never written to disk, never sent to Sentry, never logged.                                    | Dropped immediately after Whisper returns.                                  | Voice → text intent.                     | Type instead of recording.                |
| Voice transcript            | Telegram bot → Claude  | Passed in-memory to ranking call.                                                                                                       | Not retained after the response is sent.                                    | Match intent to experiences.             | n/a                                       |
| Coordinates (drop pin)      | Telegram bot, web app  | In-memory session only.                                                                                                                 | Cleared on `/reset` or 24h idle.                                            | Walking-distance ranking.                | `/reset`, browser refresh.                |
| Coordinates (live location) | Web app, future iOS    | Same as drop pin. Background GPS is **opt-in**, off by default.                                                                         | n/a                                                                         | n/a                                      | OS-level location toggle.                 |
| Anonymous device id (web)   | Web app                | Random UUID in localStorage. No fingerprinting.                                                                                         | Until user clears site data.                                                | Retention math.                          | Clear site data.                          |
| Analytics events            | Bot + web              | Event name + `channel` ("bot" / "web") + hashed user id. **No raw text, no transcripts, no coordinates, no IP.**                        | 90 days.                                                                    | Retention dashboard.                     | `/optout` (bot), localStorage flag (web). |
| Error reports (Sentry)      | Bot + web              | Stack traces, file paths, code context. **PII scrubbed in `beforeSend`** — no transcripts, no message bodies, no Mapbox tokens, no IPs. | 30 days.                                                                    | Catch crashes.                           | n/a (errors are anonymized at source).    |

## What we never collect

- Real names, phone numbers, email addresses (no signup at all on the bot).
- Government ID, passport numbers.
- Emergency contact information.
- Social-graph data — no follower lists, no contact import, no friend invites.
- Photos of the user's face.
- Continuous background location without explicit opt-in.

## Anti-patterns we've ruled out by policy

These appear in `scripts/anti-pattern-lint.ts` and any PR introducing them
will fail CI:

- Social feeds, leaderboards, badges, streaks.
- "Follow another user." Like counts. Public profiles.
- Re-engagement push notifications, daily streak nudges.
- Sharing pressure ("invite a friend to unlock").

## Sentry posture

Both `apps/bot/src/lib/sentry.ts` and `apps/web/src/lib/sentry.ts` install a
`beforeSend` hook that strips:

- `event.user.email`, `event.user.username`, `event.user.ip_address`
- `event.request.cookies`, `event.request.data`, `event.request.headers`,
  `event.request.query_string`
- `event.extra.transcript`, `event.extra.intent`, `event.extra.message_text`,
  `event.extra.mapbox_token`, `event.extra.voice_url`

Stack traces, file paths, and code context are kept — those are necessary for
debugging and contain no user data.

## Analytics: same events, two channels

Bot and web emit the same event names so retention can be compared
side-by-side on one dashboard:

- `session_start`
- `intent_submitted`
- `recommendations_shown`
- `experience_opened`
- `experience_completed`
- `experience_skipped`
- `experience_reported`
- `opted_out`

Each event carries `channel: "bot" | "web"`. We deliberately do **not** emit
engagement events (no `streak_extended`, no `daily_open`, no
`re_engagement_push`).

## Opt-out

- **Bot**: `/optout` — stops all analytics from that chat. The hashed id is
  added to a no-track set; subsequent events from that chat are dropped at
  the edge.
- **Web**: a localStorage flag `solo_compass_optout=1` (set via the privacy
  footer) suppresses all events.
- **Sentry**: errors are already anonymized at source via `beforeSend`; no
  user-level Sentry opt-out is necessary.

## Data deletion requests

Email `privacy@solo-compass.app` from any address with a description of the
request. We rotate the analytics salt monthly, which already invalidates
older hashed ids — for a hard request, we'll rotate immediately.

## Changes to this document

This file is the source of truth. Material changes are committed and dated.
The bot's `/privacy` command links here.
