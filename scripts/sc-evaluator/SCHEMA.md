# sc-evaluator schemas

Two related schemas live in this file:

1. The **journey DSL** — how authors describe a user flow in YAML.
2. The **findings format** — the markdown report and JSON shadow that the
   runtime emits after running a journey. Tooling that consumes evaluator
   output should validate against the JSON shadow (`findings.schema.json`)
   rather than scraping the markdown.

---

# Journey DSL

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

---

# Findings format

Each evaluator run produces a pair of files under
`scripts/sc-evaluator/findings/`:

| File                      | Purpose                                     |
| ------------------------- | ------------------------------------------- |
| `<run_id>.md`             | Human-readable markdown report (canonical). |
| `<run_id>.json`           | Machine-readable shadow of the same data.   |

The JSON shadow is validated by [`findings.schema.json`](./findings.schema.json)
(JSON Schema draft 2020-12). The markdown file leads with a YAML frontmatter
block that carries the same identifying metadata so static tooling (e.g.
`grep`, search indexers) can find the report by run, journey, commit, or
device without parsing the body.

`<run_id>` in the filename uses a filesystem-safe shape with hyphens instead
of colons (e.g. `2026-05-22T12-29-25Z.md`); the frontmatter `run_id` and the
JSON shadow's `run_id` use the canonical colon-bearing ISO-8601 form
(`2026-05-22T12:29:25Z`).

## Markdown layout

```markdown
---
run_id: "2026-05-22T12:29:25Z"
journey: "home-screen-cold-start"
timestamp: "2026-05-22T12:29:25Z"
commit_sha: "acc3a5c"
simulator: "iPhone 17 Pro"
ios_version: "26.4"
---

# sc-evaluator finding — 2026-05-22T12-29-25Z

- Journey: `home-screen-cold-start`
- Started: 2026-05-22T12:29:25Z
- Repo: /Users/me/solo-compass

## Steps
- [PASS] **simulator.resolve** — udid=…
- [PASS] **home.launch** — com.solocompass.app: 14872

## Findings
- **home.launch** — simctl launch failed: …

## Suggested Fixes
  - suggested fix: `apps/ios/SoloCompass/App/SoloCompassApp.swift:1` — verify @main entry and bundle id

## Screenshots
![home-map](../screenshots/2026-05-22T12-29-25Z/02-home-map.png)

## Summary
- steps: 5/5 passed
- findings: 0
- artifacts: ./2026-05-22T12-29-25Z_artifacts/
- result: **PASS**
```

### Required frontmatter fields

| Field         | Type   | Source                                                | Example                  |
| ------------- | ------ | ----------------------------------------------------- | ------------------------ |
| `run_id`      | string | `date -u +%Y-%m-%dT%H:%M:%SZ` at run start            | `2026-05-22T12:29:25Z`   |
| `journey`     | string | Bare name passed to `run.sh`                          | `home-screen-cold-start` |
| `timestamp`   | string | Same value as `run_id` (kept separate by convention)  | `2026-05-22T12:29:25Z`   |
| `commit_sha`  | string | `git rev-parse --short HEAD` (or `unknown`)           | `acc3a5c`                |
| `simulator`   | string | Resolved from `simctl list devices --json`            | `iPhone 17 Pro`          |
| `ios_version` | string | Parsed from the device's CoreSimulator runtime id     | `26.4`                   |

### Required body sections (in order)

1. **`## Steps`** — every step the runtime emitted, as
   `- [PASS|FAIL] **<step-name>** — <detail>`. Includes setup steps
   (`simulator.resolve`, `build`, `app.install`, …) and journey steps.
2. **`## Findings`** — one entry per FAIL step, as
   `- **<step-name>** — <detail>`. Each finding includes a `file:line`
   anchor where applicable (emitted into the next section as a fix).
   When there are no findings the section reads `_no findings_`.
3. **`## Suggested Fixes`** — one bullet per `emit_fix_anchor` call,
   `  - suggested fix: \`<file:line>\` — <hint>`. Reads
   `_no suggested fixes_` when none were emitted.
4. **`## Screenshots`** — `![<label>](<path>)` image references, ordered
   by capture time. Reads `_no screenshots_` when none were captured.

A `## Summary` block follows the four required sections; it is not part of
the schema contract but is always present.

## JSON shadow

The JSON shadow at `findings/<run_id>.json` carries the same information in
a strict, machine-parseable shape. Schema:
[`findings.schema.json`](./findings.schema.json).

```json
{
  "run_id": "2026-05-22T12:29:25Z",
  "journey": "home-screen-cold-start",
  "timestamp": "2026-05-22T12:29:25Z",
  "commit_sha": "acc3a5c",
  "simulator": "iPhone 17 Pro",
  "ios_version": "26.4",
  "steps": [
    { "status": "PASS", "name": "simulator.resolve", "detail": "udid=…" }
  ],
  "findings": [
    { "name": "home.launch", "detail": "simctl launch failed: …" }
  ],
  "suggested_fixes": [
    {
      "finding": "home.launch",
      "anchor": "apps/ios/SoloCompass/App/SoloCompassApp.swift:1",
      "hint": "verify @main entry and bundle id"
    }
  ],
  "screenshots": [
    { "label": "home-map", "path": "../screenshots/2026-05-22T12-29-25Z/02-home-map.png" }
  ],
  "summary": {
    "steps_passed": 5,
    "steps_total": 5,
    "findings_count": 0,
    "result": "PASS",
    "failure_reason": null
  }
}
```

`suggested_fixes[].finding` is the name of the most recent FAIL step at the
moment the fix was emitted (or `""` when the fix was emitted before any
failure occurred — e.g. a generic setup hint). Tooling can use this to
group fixes under their parent finding.

## Validating the JSON shadow

```bash
# any JSON Schema validator works; example with `ajv-cli`:
ajv validate \
  -s scripts/sc-evaluator/findings.schema.json \
  -d 'scripts/sc-evaluator/findings/*.json' \
  --spec=draft2020
```

## Authoring conventions for findings

- The runtime is the only writer of these files. Authors should not
  hand-edit findings markdown or JSON.
- The JSON shadow is the source of truth for tooling; the markdown is
  the source of truth for humans. Both must always be present and
  consistent — if you change one shape, change the other.
- `<file:line>` anchors in `## Suggested Fixes` should point at concrete
  source locations whenever possible. Use a bare file path only when no
  single line can be identified.
