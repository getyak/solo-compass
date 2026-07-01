# Visual Snapshot Plan (#X40)

Owner: iOS test infra

## Where we are

`ArchiveSnapshotTests` already lands two `ImageRenderer` snapshots
(populated + empty) to `/tmp/archive_snapshot_*.png`. Same pattern is
usable for every new v-next view, but ImageRenderer has known
limitations:

- Does not trigger `onAppear` — services that load in `.task { }` or
  `.onAppear { }` never fire.
- LazyVStack / ScrollView render only the viewport-visible children.
- Custom animations render at the initial keyframe only.

So the snapshot suite has to grow along two axes:

1. **Static composition snapshots** (ImageRenderer, cheap, deterministic).
2. **UIHostingController snapshots** (mounts the view into a real
   window, triggers appear + layout, expensive but faithful).

## Suites to add

Each maps to one new v-next view. Land as separate XCTest cases
under `SoloCompassTests/Tests/`.

### Static (ImageRenderer)

- `OmenCardSnapshotTests` — front + flipped back.
- `CityCodexSnapshotTests` — populated grid + Pro upsell shown.
- `OstShareCardSnapshotTests` — with all four style tags.
- `BragCardSnapshotTests` — with + without unlocked video.
- `InsightCardSnapshotTests` — populated + zero-visit month.
- `BlindboxLaunchViewSnapshotTests` — three duration selections.
- `BlindboxRecapCardSnapshotTests` — different anchor counts.
- `CapsuleComposeViewSnapshotTests` — empty + populated states.

### UIHostingController (real appear + layout)

- `CapsuleOpenViewSnapshotTests` — verify the 5-beat animation
  midpoint (needs animation clock override).
- `ArchiveViewSnapshotTests` — extend the existing suite to include
  the new capsule section + year-end banner when clock is Dec 15.
- `NotificationsSettingsViewSnapshotTests` — verify each toggle state.

## Delivery contract

- Every new snapshot file writes to `/tmp/snapshot_<viewname>_<state>.png`.
- Failing test attaches the rendered image to the XCTest attachment
  (`XCTAttachment(image:)`) so CI logs surface it directly.
- Baseline images live in `apps/ios/SoloCompass/Tests/__Snapshots__/`
  and are diffed via `PixelDiff` (introduce this helper as part of the
  first snapshot commit).

## Rollout

Land one suite per PR — small green diffs beat one giant unstable one.
Order by highest-visual-risk-first:

1. `CapsuleOpenViewSnapshotTests` (ceremonial)
2. `OmenCardSnapshotTests` (front↔back flip)
3. `BlindboxRecapCardSnapshotTests` (share-critical)
4. Everything else in bulk.
