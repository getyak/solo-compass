# CI Test Matrix — Phase 2 + Phase 3 (#290 / #390)

Owner: infra
Target CI: `.github/workflows/ios-ci.yml` (`macos-latest`)

## Suites CI must run

Every landed test file in `apps/ios/SoloCompass/Tests/` runs by
default under the SoloCompassTests target. This document freezes the
critical subset that MUST stay green — CI blocks a merge if any of
them regresses.

### Phase 1 baseline (must stay 70+/70+)

- `V1_9SchemaRecordsTests` — SwiftData schema V1_9 CRUD + coord codec
- `VisitTrackingServiceTests` — 7 cases
- `TasteUpdateServiceTests` — 10 cases
- `GenerateTasteProfileTests` — 14 cases
- `ArchiveViewModelTests` — 8 cases
- `ArchiveSnapshotTests` — 2 cases
- `VisitedMarkerStateTests` — 6 cases
- `LiveActivityServiceTests` — 6 cases

### Phase 2 P2.0 (must stay green)

- `MemoryDigestServiceTests` — 15 cases

### V-next skeleton (Phase 2/3 code-scope)

- `V_NEXT_ServiceSkeletonTests` — 10 cases covering:
  - Omen determinism per day + differs across days
  - Music playlist determinism
  - Brag counts + headline determinism
  - Monthly insight month bucketing
  - Book weekly chapter aggregation
  - Analytics buffer opt-out
  - Capsule bury / ripe / markOpened
  - Nudge daily budget limit

## Local pre-push check

Because Phase 2 was landed without a local `xcodebuild test` run,
the first CI cycle after this branch merges is expected to surface
any type/API drift. Playbook if red:

1. Read the CI log for the exact file:line diagnostic.
2. Fix the symbol reference. `SourceKit` "cannot find type" errors
   in the branch's editor context are index-freshness, not compile
   errors — but real compile errors from CI use a different message
   ("cannot find in scope of module").
3. Re-run `xcodegen` only if the fix required a file rename or
   move; simple edits do not need it.

## Coverage floor

Phase 2 + Phase 3 code-scope files should hit ≥ 60% line coverage
via the tests above. Below floor blocks the PR — file a coverage
follow-up before merging.

## Non-covered by design

- Real StoreKit purchase flow (unit tests can't hit
  `Product.purchase()`).
- Real MusicKit playlist creation.
- Real UNUserNotificationCenter delivery (only scheduling assertions).
- Live Activity `Activity.request()` — needs the widget extension
  entitlement, tested manually via `docs/BETA_TEST_CHECKLIST.md`.
