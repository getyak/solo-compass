# TS ↔ Swift Schema Parity Guard

Automated check that TypeScript interfaces in `packages/core/src/` are mirrored by matching Swift structs in `apps/ios/SoloCompass/Models/`.

## How to run

```bash
pnpm parity:check          # exits 0 on match, 1 on mismatch
```

## Type mapping rules

| TypeScript | Swift | Notes |
|---|---|---|
| `string` | `String` | |
| `ExperienceId` (branded string) | `String` | Brand stripped at boundary |
| `number` | `Double` or `Int` | Both accepted |
| `boolean` | `Bool` | |
| `readonly [number, number]` / `Coordinates` | `[Double]` | GeoJSON lon/lat tuple |
| `T[]` / `readonly T[]` / `ReadonlyArray<T>` | `[T]` | Element type mapped recursively |
| `field?: T` (optional) | `field: T?` | TS optional → Swift optional |
| `string \| undefined` | `String?` | Same rule |
| `Date` (string in TS, ISO 8601) | `Date` or `String` | Swift decodes from ISO string |
| `ConfidenceLevel` (0\|1\|2\|3\|4\|5) | `Int` | Numeric union → Int |
| Inline `{ ... }` shapes | Nested Swift struct | Checked by struct name match |

## Optionality rules

- TS `field?: T` must have Swift `field: T?` — a non-optional Swift field for an optional TS field is a **decoding crash risk**.
- Swift `field: T?` for a required TS `field: T` is **allowed** (defensive decoding).

## Ignored Swift-only fields

Computed properties and UI helpers that exist only on the Swift side are skipped:

- `id` (Identifiable conformance, derived from other fields)
- `coordinate` / `clCoordinate` (computed from `location`)
- `scoreColor`, `health` (computed from score/confidence)
- `symbol`, `color`, `localizedTitle`, `localizedDescription` (UI layer)
- `accessibilitySymbol`, `totalCount` (UI/derived)

## Watched structs

The following interfaces are checked for full parity:

- `Experience`
- `ExperienceLocation`
- `TimeWindow`
- `HowToStep`
- `RealInconvenience`
- `InformationSource`
- `SoloScore`
- `Confidence`

## Adding a new field

1. Add the field to the TS interface in `packages/core/src/experience.ts` (or relevant file).
2. Add the corresponding Swift property to the matching struct in `apps/ios/SoloCompass/Models/Experience.swift`.
3. Run `pnpm parity:check` locally — it must pass before merging.

CI will block the PR if parity breaks.
