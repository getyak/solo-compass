# sc-evaluator journey DSL

A small YAML DSL for describing user journeys that sc-evaluator drives against
the iOS Simulator. The runtime in `run.sh` validates a journey on load via
`_dsl.py` and fails fast with a clear error message if a step name is unknown
or a required argument is missing.

Journeys live at `scripts/sc-evaluator/journeys/<name>.yml` and are selected by
their bare name: `scripts/sc-evaluator/run.sh <name>`.

## File shape

```yaml
name: home-screen-cold-start          # optional, informational
description: Cold launch and snapshot # optional, informational

steps:                                # required, non-empty list
  - <step>
  - <step>
```

The top-level document must be a mapping with a non-empty `steps` list. Each
step is a single-key mapping; the key is the step kind, the value is its args.
Steps that take no args may be written as `- launch:` (null body).

## Supported steps

| Step            | Required args                              | Optional args            | Notes |
| --------------- | ------------------------------------------ | ------------------------ | ----- |
| `launch`        | —                                          | —                        | Cold-launches `SC_BUNDLE_ID` on `SC_UDID`. |
| `tap`           | `x`+`y` **or** `accessibilityId`           | —                        | Exactly one of the two forms — never both. |
| `longPress`     | `x`+`y` **or** `accessibilityId`           | `duration` (default 1.0) | Same coordinate / id rule as `tap`. Duration is seconds. |
| `screenshot`    | `label` (string)                           | —                        | Written to `scripts/sc-evaluator/screenshots/<run_id>/<NN>-<label>.png` and linked from the findings file's `## Screenshots` section. `NN` is the 2-digit zero-padded step ordinal. Legacy `name` is still accepted as a synonym for `label`. |
| `assertVisible` | `accessibilityId` (string)                 | —                        | Fails the step if the element cannot be located. |
| `assertText`    | `text` (string)                            | `accessibilityId`        | If `accessibilityId` is given, only that element's text is checked. |
| `wait`          | `seconds` (number > 0)                     | —                        | Sleeps the journey for `seconds`. |

`x` and `y` are point coordinates in the simulator's screen space (top-left
origin). They can be integers or floats.

## Examples

### Tap by accessibility id

```yaml
- tap:
    accessibilityId: "chat.openButton"
```

### Tap by absolute coordinates

```yaml
- tap:
    x: 200
    y: 720
```

### Long press with a custom duration

```yaml
- longPress:
    accessibilityId: "marker.coffee_shop_42"
    duration: 1.5
```

### Assert visibility, then take a screenshot

```yaml
- assertVisible:
    accessibilityId: "compass.map"
- screenshot:
    label: "home-map"
```

### Wait between actions

```yaml
- wait:
    seconds: 3
```

## Validation guarantees

`run.sh` calls `_dsl.py <journey.yml>` before installing the app. The validator
exits non-zero (exit code 2 — setup error) if:

- the file does not exist
- the YAML cannot be parsed
- the top-level document is not a mapping with a `steps` list
- any step is not a single-key mapping (or explicit `{kind: ...}` form)
- a step name is not one of: `launch`, `tap`, `longPress`, `screenshot`,
  `assertVisible`, `assertText`, `wait`
- a required arg is missing or has the wrong type (in particular, `screenshot`
  requires a non-empty `label` — `name` is accepted as a legacy synonym)
- `tap` / `longPress` lack both `(x, y)` and `accessibilityId`, or provide both

Errors are written to stderr in the form:

```
error: unknown step 'taap' (allowed: ...) at step #3 (taap)
```

so the offending step index and name are always visible.

## Authoring conventions

- Prefer `accessibilityId` over absolute coordinates — coordinates break the
  moment we adjust layout, device size, or trait collection. Coordinates are
  only intended as an escape hatch when an element does not yet expose an
  accessibility identifier.
- Screenshot labels should be short, kebab-case state descriptions
  (e.g. `cold-launch`, `map-loaded`). The runtime prepends a 2-digit step
  ordinal (`NN-<label>.png`) so the screenshots directory sorts in journey
  order without callers having to repeat the index in the label.
- Keep a `wait` after any state transition that triggers animation or network
  activity; the runtime never auto-waits.
- Treat journeys as append-only documentation of a real user path. If a flow
  changes meaningfully, add a new journey instead of mutating an existing one.

## Running

```bash
scripts/sc-evaluator/run.sh home-screen-cold-start
scripts/sc-evaluator/run.sh pro-chat-roundtrip --no-build
```

Findings are written to `scripts/sc-evaluator/findings/<run-id>.md`. Build
logs and other run artifacts live under `findings/<run-id>_artifacts/`.
Screenshots are written to `scripts/sc-evaluator/screenshots/<run-id>/` —
this directory is git-ignored by default, but a run with
`SC_EVALUATOR_KEEP_SCREENSHOTS=1` force-stages that run's directory so the
PNGs can be committed alongside the findings file.
