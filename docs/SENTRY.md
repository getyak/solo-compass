# Sentry — error tracking & auto-issue intake

## What it does

- **iOS app** (`apps/ios/SoloCompass`) ships with `sentry-cocoa` via SwiftPM.
- `SentryService.bootstrap()` runs in `SoloCompassApp.init` with DSN baked in
  from `Secrets.sentryDSN` (generated from `.env` → `GeneratedSecrets.swift`).
- Empty DSN → `SentrySDK.start` is skipped (no crash, no-op).

### Automatic capture

- Unhandled NSExceptions / Swift fatal errors
- Mach signals (SIGSEGV / SIGABRT / …)
- App hangs / ANR (>2s main-thread block)
- Network breadcrumbs (NSURLSession)
- UIKit lifecycle breadcrumbs
- Low-memory warnings
- 20% traces sample (perf transactions) — tune in `SentryService.swift`

### Manual capture

```swift
do {
    try riskyThing()
} catch {
    SentryService.capture(error: error, context: ["where": "ChatSheet.send"])
}

SentryService.capture(
    message: "Outbox grew past 100 items",
    level: .warning,
    context: ["count": outbox.count]
)
```

PII is off (`sendDefaultPii = false`); location / voice / chat content stays local.

---

## Setup

1. Get the DSN from Sentry → **Settings → Projects → solo-compass → Client Keys (DSN)**.
2. Paste into your local `.env` (root of repo):
   ```
   SENTRY_DSN=https://<public_key>@o<org>.ingest.us.sentry.io/<project_id>
   ```
3. Build the iOS app — `scripts/generate_secrets.sh` injects the DSN into
   `GeneratedSecrets.swift` at build time.
4. For CI / TestFlight builds, put `SENTRY_DSN` in the GitHub Actions secret
   used by the build job (same name).

---

## Auto-issue intake (Sentry → GitHub Issues)

There are two ways to land Sentry events as GitHub issues. We recommend
**Sentry's native GitHub integration** — it's the lowest-maintenance path.

### Option A — Sentry's native GitHub integration (recommended)

1. **Install integration** (one-time, per org)
   - Sentry → **Settings → Integrations → GitHub → Install**
   - Authorize for the `getyak` org (or whichever GitHub org owns this repo)
   - Pick the repos to enable; include `getyak/solo-compass`

2. **Link the project to the repo**
   - Sentry → **Settings → Projects → solo-compass → Integrations → GitHub**
   - Set default repo = `getyak/solo-compass`

3. **Auto-create issues via Alert Rules**
   - Sentry → **Alerts → Create Alert → Issues**
   - Trigger: e.g. `event.type:error AND environment:release`
     (skip `debug` — `SentryService` sets `environment = debug` for `#if DEBUG`)
   - Filter — pick whichever combo fits the noise floor:
     - `level:error OR level:fatal`
     - `is:unresolved`
     - `times_seen:>=3` (avoid one-off flukes)
   - Action: **Create a GitHub Issue**
     - Repo: `getyak/solo-compass`
     - Labels: `bug`, `from:sentry`
     - Title template: `[Sentry] {{ issue.title }}`
     - Body: Sentry fills in the event link, stack trace, and breadcrumbs

4. **Manual one-off** — on any Sentry issue page, the right-hand
   **Linked Issues** panel has a "Create GitHub Issue" button that bypasses
   the alert rule.

### Option B — Webhook + GitHub Actions (more control)

Use this if you want custom title formatting, deduping logic, or routing to
different repos based on tags. More moving parts; only worth it once Option A
shows real limitations.

Sketch:

1. Sentry → **Settings → Projects → solo-compass → Alerts → Send a
   notification → Webhook**
2. Webhook URL → `https://api.github.com/repos/getyak/solo-compass/dispatches`
   with a `repository_dispatch` event type like `sentry_event`.
3. `.github/workflows/sentry-to-issue.yml` listens for
   `repository_dispatch: types: [sentry_event]` and runs
   `gh issue create --title ... --body ...` with the payload from the webhook.

Skipping the YAML stub on purpose — write it when you actually need Option B.

---

## Deduping

Sentry already groups events into **Issues** by stack-trace fingerprint, so a
crash that fires 1000 times in a day creates **one** Sentry issue → **one**
GitHub issue. Reopened (regression) events post a comment back to the same
GitHub issue instead of opening a new one — provided the GitHub integration
is the linked source.

If duplicates ever appear, check that the alert rule filter is `is:unresolved`
(not `is:new`), and that the GitHub integration is installed at the org level,
not just the user level.

---

## Sample rate

`SentryService.tracesSampleRate = 0.2` (20%) — change in `SentryService.swift`.
At ≥5K MAU consider 0.05 to stay inside the free tier's transaction quota.
Error events are not sampled; every crash is sent.

---

## Verifying the integration

After setup:

```swift
// Temporarily add to any view's onTapGesture and tap once in a release build:
SentryService.capture(message: "smoke test", level: .error)
```

Within ~30s you should see:

1. A new event in Sentry (Issues view)
2. A new GitHub issue in `getyak/solo-compass` with label `from:sentry`

Remove the test line before merging.
