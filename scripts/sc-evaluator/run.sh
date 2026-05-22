#!/usr/bin/env bash
# sc-evaluator/run.sh — Solo Compass evaluator runtime.
#
# Boots an iOS simulator (iPhone 17 Pro / iOS 26.4 preferred), installs the
# freshly built SoloCompass.app, launches it, and walks through a named
# journey. Writes an append-only findings file under findings/<run_id>.md.
#
# Usage:
#   scripts/sc-evaluator/run.sh <journey-name> [--no-build]
#
# Exit codes:
#   0  all journey steps passed
#   1  one or more findings raised
#   2  setup error (no journey, no simulator, build failed)

set -u
set -o pipefail

# ---------- locate repo ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IOS_DIR="$REPO_ROOT/apps/ios"
JOURNEYS_DIR="$SCRIPT_DIR/journeys"
FINDINGS_DIR="$SCRIPT_DIR/findings"
SCREENSHOTS_DIR="$SCRIPT_DIR/screenshots"
BUNDLE_ID="com.solocompass.app"
PREFERRED_DEVICE="iPhone 17 Pro"
PREFERRED_OS="iOS 26.4"
SKIP_BUILD=0

mkdir -p "$FINDINGS_DIR"

# ---------- args ----------
JOURNEY="${1:-}"
if [[ -z "$JOURNEY" ]]; then
  echo "error: journey name required" >&2
  echo "usage: $0 <journey-name> [--no-build]" >&2
  echo "available journeys:" >&2
  ls "$JOURNEYS_DIR" 2>/dev/null | sed -E 's/\.(sh|yml)$//' | sort -u | sed 's/^/  - /' >&2 || true
  exit 2
fi
shift || true
for arg in "$@"; do
  case "$arg" in
    --no-build) SKIP_BUILD=1 ;;
    *) echo "warning: ignoring unknown arg: $arg" >&2 ;;
  esac
done

JOURNEY_YML="$JOURNEYS_DIR/${JOURNEY}.yml"
JOURNEY_SCRIPT="$JOURNEYS_DIR/${JOURNEY}.sh"
JOURNEY_MODE=""
if [[ -f "$JOURNEY_YML" ]]; then
  JOURNEY_MODE="yml"
elif [[ -f "$JOURNEY_SCRIPT" ]]; then
  JOURNEY_MODE="sh"
else
  echo "error: journey '$JOURNEY' not found (looked for $JOURNEY_YML and $JOURNEY_SCRIPT)" >&2
  exit 2
fi

# ---------- YAML pre-validation ----------
# When the journey is YAML, validate (and parse) it BEFORE we boot the
# simulator or build the app. Validation failures exit 2 so callers can
# distinguish setup errors from real findings.
DSL_HELPER="$SCRIPT_DIR/_dsl.py"
PARSED_STEPS=""
if [[ "$JOURNEY_MODE" == "yml" ]]; then
  if [[ ! -f "$DSL_HELPER" ]]; then
    echo "error: DSL helper missing at $DSL_HELPER" >&2
    exit 2
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "error: python3 is required to load YAML journeys" >&2
    exit 2
  fi
  TMP_STDOUT="$(mktemp)"
  TMP_STDERR="$(mktemp)"
  if python3 "$DSL_HELPER" "$JOURNEY_YML" >"$TMP_STDOUT" 2>"$TMP_STDERR"; then
    PARSED_STEPS="$(cat "$TMP_STDOUT")"
    rm -f "$TMP_STDOUT" "$TMP_STDERR"
  else
    echo "error: journey '$JOURNEY' failed DSL validation" >&2
    cat "$TMP_STDERR" >&2
    rm -f "$TMP_STDOUT" "$TMP_STDERR"
    exit 2
  fi
fi

# ---------- run id + findings file ----------
RUN_ID="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
# ISO-8601 UTC timestamp with colons. RUN_ID is filesystem-safe (hyphens),
# while RUN_TIMESTAMP_ISO is the canonical machine-readable form emitted in
# the frontmatter and JSON shadow.
RUN_TIMESTAMP_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
FINDINGS_FILE="$FINDINGS_DIR/${RUN_ID}.md"
FINDINGS_JSON="$FINDINGS_DIR/${RUN_ID}.json"
ARTIFACTS_DIR="$FINDINGS_DIR/${RUN_ID}_artifacts"
RUN_SCREENSHOTS_DIR="$SCREENSHOTS_DIR/${RUN_ID}"
mkdir -p "$ARTIFACTS_DIR" "$RUN_SCREENSHOTS_DIR"

# Append-only safety: never overwrite existing outputs.
if [[ -e "$FINDINGS_FILE" ]]; then
  echo "error: findings file already exists (would overwrite): $FINDINGS_FILE" >&2
  exit 2
fi
if [[ -e "$FINDINGS_JSON" ]]; then
  echo "error: findings JSON shadow already exists (would overwrite): $FINDINGS_JSON" >&2
  exit 2
fi

# Short commit SHA for the frontmatter / JSON shadow; falls back to "unknown"
# outside a git checkout.
COMMIT_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
# Populated after simulator resolution; emitted into frontmatter at flush time.
SIMULATOR_NAME=""
IOS_VERSION=""

# ---------- findings helpers ----------
FINDINGS_COUNT=0
STEP_RESULTS=()

# Sidecar JSON-Lines streams: each helper appends one record per line. At end
# of run, a small python pass synthesizes findings/<run_id>.json from these
# streams so we never string-concatenate JSON in bash.
STEPS_JSONL="$ARTIFACTS_DIR/.steps.jsonl"
FINDINGS_JSONL="$ARTIFACTS_DIR/.findings.jsonl"
FIXES_JSONL="$ARTIFACTS_DIR/.fixes.jsonl"
SCREENSHOTS_JSONL="$ARTIFACTS_DIR/.screenshots.jsonl"
: > "$STEPS_JSONL"
: > "$FINDINGS_JSONL"
: > "$FIXES_JSONL"
: > "$SCREENSHOTS_JSONL"

# Markdown bodies for the four content sections. Buffered separately so the
# final file can emit them in the order required by SCHEMA.md
# (Steps → Findings → Suggested Fixes → Screenshots → Summary) regardless of
# the chronological order in which they were produced during the run.
STEPS_BUFFER="$ARTIFACTS_DIR/.steps-buffer.md"
FINDINGS_BUFFER="$ARTIFACTS_DIR/.findings-buffer.md"
FIXES_BUFFER="$ARTIFACTS_DIR/.fixes-buffer.md"
: > "$STEPS_BUFFER"
: > "$FINDINGS_BUFFER"
: > "$FIXES_BUFFER"

# Screenshot links are buffered to a sidecar file during the run and flushed
# into a `## Screenshots` section right before the `## Summary` block. This
# keeps `## Steps` contiguous in the findings file even though screenshot
# steps and other steps interleave chronologically.
SCREENSHOTS_BUFFER="$ARTIFACTS_DIR/.screenshots-buffer.md"
: > "$SCREENSHOTS_BUFFER"

# JSONL append helper — minimal python so we get correct quoting / escaping
# for arbitrary detail strings (which may contain quotes, newlines, etc.).
_sc_jsonl_append() {
  # _sc_jsonl_append <jsonl-file> <k1> <v1> [<k2> <v2> ...]
  local file="$1"
  shift
  python3 - "$file" "$@" <<'PY'
import json, sys
file = sys.argv[1]
kvs = sys.argv[2:]
record = {}
for i in range(0, len(kvs), 2):
    record[kvs[i]] = kvs[i + 1]
with open(file, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(record, sort_keys=True))
    fh.write("\n")
PY
}

emit_step() {
  # emit_step <status:PASS|FAIL> <step-name> <detail...>
  #
  # Records a step into both the markdown `## Steps` buffer and the JSON-Lines
  # stream consumed at end-of-run when synthesizing the JSON shadow.
  local status="$1"
  local name="$2"
  shift 2
  local detail="$*"
  STEP_RESULTS+=("$status|$name|$detail")
  printf -- "- [%s] **%s** — %s\n" "$status" "$name" "$detail" >> "$STEPS_BUFFER"
  _sc_jsonl_append "$STEPS_JSONL" status "$status" name "$name" detail "$detail"
  if [[ "$status" == "FAIL" ]]; then
    FINDINGS_COUNT=$((FINDINGS_COUNT + 1))
    # Each FAIL becomes a `## Findings` entry. Anchors emitted via
    # emit_fix_anchor between now and the next emit_step are attached to this
    # finding by recording the latest finding name in $LAST_FINDING_NAME so
    # emit_fix_anchor can include it in its JSONL record.
    LAST_FINDING_NAME="$name"
    printf -- "- **%s** — %s\n" "$name" "$detail" >> "$FINDINGS_BUFFER"
    _sc_jsonl_append "$FINDINGS_JSONL" name "$name" detail "$detail"
  fi
}

emit_screenshot() {
  # emit_screenshot <label> <relative-path-from-findings-file>
  #
  # Buffers a Markdown image link for the eventual `## Screenshots` section
  # and records the (label, path) pair for the JSON shadow.
  local label="$1"
  local rel="$2"
  printf -- "![%s](%s)\n" "$label" "$rel" >> "$SCREENSHOTS_BUFFER"
  _sc_jsonl_append "$SCREENSHOTS_JSONL" label "$label" path "$rel"
}

# Tracks the most recent failing step so emit_fix_anchor can associate a fix
# with its parent finding. Empty when no finding is currently open.
LAST_FINDING_NAME=""

emit_fix_anchor() {
  # emit_fix_anchor <file:line> <hint>
  #
  # Each fix anchor is attached to the most recent FAIL step (the "current"
  # finding) when one exists. Anchors emitted before any failure — e.g. setup
  # hints — are still captured in the JSON shadow with an empty finding name.
  local anchor="$1"
  local hint="$2"
  printf -- "  - suggested fix: \`%s\` — %s\n" "$anchor" "$hint" >> "$FIXES_BUFFER"
  _sc_jsonl_append "$FIXES_JSONL" finding "$LAST_FINDING_NAME" anchor "$anchor" hint "$hint"
}

# ---------- final flush: assemble frontmatter + ordered sections + JSON ----------
#
# Centralized writer used by every exit path. Always overwrites
# $FINDINGS_FILE with the canonical layout (frontmatter → Steps → Findings →
# Suggested Fixes → Screenshots → Summary) and writes the JSON shadow at
# $FINDINGS_JSON. Safe to call multiple times.
#
# Args:
#   $1 — final result label: "PASS" | "FAIL"
#   $2 — optional summary suffix (e.g. "(setup)", "(build)") for the markdown
#        result line; the JSON shadow stores it as `summary.failure_reason`.
flush_findings_file() {
  local result="$1" reason="${2:-}"

  local total_steps=${#STEP_RESULTS[@]}
  local pass_steps=0
  local entry
  for entry in "${STEP_RESULTS[@]}"; do
    [[ "${entry%%|*}" == "PASS" ]] && pass_steps=$((pass_steps + 1))
  done

  # Build the markdown file.
  {
    printf -- '---\n'
    printf -- 'run_id: "%s"\n' "$RUN_TIMESTAMP_ISO"
    printf -- 'journey: "%s"\n' "$JOURNEY"
    printf -- 'timestamp: "%s"\n' "$RUN_TIMESTAMP_ISO"
    printf -- 'commit_sha: "%s"\n' "$COMMIT_SHA"
    printf -- 'simulator: "%s"\n' "$SIMULATOR_NAME"
    printf -- 'ios_version: "%s"\n' "$IOS_VERSION"
    printf -- '---\n\n'
    printf -- '# sc-evaluator finding — %s\n\n' "$RUN_ID"
    printf -- '- Journey: `%s`\n' "$JOURNEY"
    printf -- '- Started: %s\n' "$RUN_TIMESTAMP_ISO"
    printf -- '- Repo: %s\n\n' "$REPO_ROOT"

    printf -- '## Steps\n'
    if [[ -s "$STEPS_BUFFER" ]]; then
      cat "$STEPS_BUFFER"
    fi

    printf -- '\n## Findings\n'
    if [[ -s "$FINDINGS_BUFFER" ]]; then
      cat "$FINDINGS_BUFFER"
    else
      printf -- '_no findings_\n'
    fi

    printf -- '\n## Suggested Fixes\n'
    if [[ -s "$FIXES_BUFFER" ]]; then
      cat "$FIXES_BUFFER"
    else
      printf -- '_no suggested fixes_\n'
    fi

    printf -- '\n## Screenshots\n'
    if [[ -s "$SCREENSHOTS_BUFFER" ]]; then
      cat "$SCREENSHOTS_BUFFER"
    else
      printf -- '_no screenshots_\n'
    fi

    printf -- '\n## Summary\n'
    printf -- '- steps: %d/%d passed\n' "$pass_steps" "$total_steps"
    printf -- '- findings: %d\n' "$FINDINGS_COUNT"
    printf -- '- artifacts: ./%s_artifacts/\n' "$RUN_ID"
    if [[ -n "$reason" ]]; then
      printf -- '- result: **%s** %s\n' "$result" "$reason"
    else
      printf -- '- result: **%s**\n' "$result"
    fi
  } > "$FINDINGS_FILE"

  # JSON shadow — synthesized from the JSON-Lines sidecar streams.
  python3 - \
      "$FINDINGS_JSON" \
      "$RUN_TIMESTAMP_ISO" \
      "$JOURNEY" \
      "$COMMIT_SHA" \
      "$SIMULATOR_NAME" \
      "$IOS_VERSION" \
      "$STEPS_JSONL" \
      "$FINDINGS_JSONL" \
      "$FIXES_JSONL" \
      "$SCREENSHOTS_JSONL" \
      "$pass_steps" "$total_steps" "$FINDINGS_COUNT" \
      "$result" "$reason" <<'PY' || true
import json, sys
from pathlib import Path

(out, run_id, journey, commit_sha, simulator, ios_version,
 steps_p, findings_p, fixes_p, screenshots_p,
 pass_steps, total_steps, findings_count,
 result, reason) = sys.argv[1:16]

def load(p):
    path = Path(p)
    if not path.is_file():
        return []
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out

doc = {
    "run_id": run_id,
    "journey": journey,
    "timestamp": run_id,
    "commit_sha": commit_sha,
    "simulator": simulator,
    "ios_version": ios_version,
    "steps": load(steps_p),
    "findings": load(findings_p),
    "suggested_fixes": load(fixes_p),
    "screenshots": load(screenshots_p),
    "summary": {
        "steps_passed": int(pass_steps),
        "steps_total": int(total_steps),
        "findings_count": int(findings_count),
        "result": result,
        "failure_reason": reason or None,
    },
}
Path(out).write_text(
    json.dumps(doc, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY
}

# ---------- simulator detection / boot ----------
echo "→ resolving simulator…"
UDID=""

# Already-booted simulator wins.
UDID="$(xcrun simctl list devices booted 2>/dev/null \
  | grep -Eo '\([A-F0-9-]{36}\)' | head -1 | tr -d '()' || true)"

if [[ -z "$UDID" ]]; then
  # Prefer the configured device name in any available runtime.
  UDID="$(xcrun simctl list devices available 2>/dev/null \
    | awk -v dev="$PREFERRED_DEVICE" '
        $0 ~ dev {
          match($0, /\([A-F0-9-]{36}\)/);
          if (RSTART) print substr($0, RSTART+1, 36);
        }' | head -1 || true)"

  if [[ -z "$UDID" ]]; then
    # Fallback: any iPhone simulator.
    UDID="$(xcrun simctl list devices available 2>/dev/null \
      | grep -Eo 'iPhone[^(]*\([A-F0-9-]{36}\)' \
      | grep -Eo '\([A-F0-9-]{36}\)' | head -1 | tr -d '()' || true)"
  fi

  if [[ -z "$UDID" ]]; then
    emit_step FAIL "simulator.resolve" "no available iPhone simulator (need ${PREFERRED_DEVICE} on ${PREFERRED_OS})"
    echo "FAILED: no simulator" >&2
    # Defaults populate frontmatter when simulator detection never ran.
    SIMULATOR_NAME="$PREFERRED_DEVICE"
    IOS_VERSION="${PREFERRED_OS#iOS }"
    flush_findings_file FAIL "(setup)"
    exit 2
  fi

  echo "  booting $UDID…"
  xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
fi

# Open Simulator.app so the runner is visible (best-effort, never blocks).
open -gja Simulator >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
emit_step PASS "simulator.resolve" "udid=$UDID"

# Resolve the human-readable device name and iOS version for the UDID we
# locked onto. `simctl list devices --json` is the most reliable source.
# Falls back to the configured defaults if the lookup fails so frontmatter
# is always populated with non-empty values.
SIM_LOOKUP="$(xcrun simctl list devices --json 2>/dev/null \
  | python3 - "$UDID" <<'PY' 2>/dev/null || true
import json, sys
udid = sys.argv[1]
data = json.load(sys.stdin)
for runtime, devs in (data.get("devices") or {}).items():
    for d in devs:
        if d.get("udid") == udid:
            # runtime looks like "com.apple.CoreSimulator.SimRuntime.iOS-26-4"
            ios = runtime.rsplit(".", 1)[-1]
            if ios.lower().startswith("ios-"):
                ios = ios[4:].replace("-", ".")
            print(f"{d.get('name','')}\t{ios}")
            sys.exit(0)
PY
)"
if [[ -n "$SIM_LOOKUP" ]]; then
  SIMULATOR_NAME="${SIM_LOOKUP%%	*}"
  IOS_VERSION="${SIM_LOOKUP##*	}"
fi
[[ -z "$SIMULATOR_NAME" ]] && SIMULATOR_NAME="$PREFERRED_DEVICE"
[[ -z "$IOS_VERSION" ]] && IOS_VERSION="${PREFERRED_OS#iOS }"

# ---------- build (optional) ----------
APP_PATH=""
if [[ "$SKIP_BUILD" -eq 0 ]]; then
  echo "→ building SoloCompass.app…"
  BUILD_LOG="$ARTIFACTS_DIR/xcodebuild.log"
  if ( cd "$IOS_DIR" && xcodebuild \
        -project SoloCompass.xcodeproj \
        -scheme SoloCompass \
        -destination "id=$UDID" \
        -configuration Debug \
        build ) >"$BUILD_LOG" 2>&1; then
    emit_step PASS "build" "Debug build OK"
  else
    emit_step FAIL "build" "xcodebuild failed — see ${RUN_ID}_artifacts/xcodebuild.log"
    emit_fix_anchor "apps/ios/SoloCompass" "inspect xcodebuild.log tail for first error"
    # Echo a short tail into the findings buffer so the file is self-contained.
    tail -5 "$BUILD_LOG" 2>/dev/null | sed 's/^/    /' >> "$FINDINGS_BUFFER" || true
    flush_findings_file FAIL "(build)"
    exit 1
  fi
fi

APP_PATH="$(find ~/Library/Developer/Xcode/DerivedData -name SoloCompass.app \
  -path '*/Debug-iphonesimulator/*' -type d 2>/dev/null \
  | xargs -I{} stat -f '%m %N' {} 2>/dev/null \
  | sort -rn | head -1 | awk '{print $2}')"

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  emit_step FAIL "app.locate" "SoloCompass.app not found in DerivedData"
  emit_fix_anchor "scripts/sc-evaluator/run.sh" "run without --no-build, or build manually in Xcode"
  flush_findings_file FAIL "(setup)"
  exit 2
fi
emit_step PASS "app.locate" "$APP_PATH"

# ---------- install + launch ----------
if xcrun simctl install "$UDID" "$APP_PATH" >/dev/null 2>&1; then
  emit_step PASS "app.install" "$BUNDLE_ID"
else
  emit_step FAIL "app.install" "simctl install failed"
  flush_findings_file FAIL "(install)"
  exit 1
fi

# Terminate any prior instance for a clean cold start.
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

# ---------- run journey ----------
echo "→ running journey: $JOURNEY"
export SC_UDID="$UDID"
export SC_BUNDLE_ID="$BUNDLE_ID"
export SC_ARTIFACTS_DIR="$ARTIFACTS_DIR"
export SC_RUN_ID="$RUN_ID"
export SC_FINDINGS_FILE="$FINDINGS_FILE"
export SC_RUN_SCREENSHOTS_DIR="$RUN_SCREENSHOTS_DIR"
export SCREENSHOTS_BUFFER

# Helper exported for journey scripts.
#
# Captures a PNG to scripts/sc-evaluator/screenshots/<run_id>/<NN>-<label>.png
# via `xcrun simctl io`. Echoes the path relative to the active findings file
# on success (suitable for emit_screenshot), empty string on failure.
#
# Args:
#   $1 — 2-digit zero-padded step ordinal (NN)
#   $2 — label (used verbatim in filename; callers sanitize if needed)
sc_screenshot() {
  local nn="$1" label="$2"
  local filename="${nn}-${label}.png"
  local path="$RUN_SCREENSHOTS_DIR/${filename}"
  xcrun simctl io "$UDID" screenshot "$path" >/dev/null 2>&1 || return 1
  # Path relative to FINDINGS_FILE (which lives in findings/) so markdown
  # links resolve when the findings file is viewed in place.
  echo "../screenshots/${RUN_ID}/${filename}"
}
export -f sc_screenshot
export -f emit_step
export -f emit_screenshot
export -f emit_fix_anchor

# Journey script may call: emit_step / emit_screenshot / emit_fix_anchor / sc_screenshot.
# A non-zero exit from the journey indicates one or more failed steps.
JOURNEY_EXIT=0

# Extract a JSON field from a step's json-args via python3 (already required
# for yml mode). Echoes empty string when the key is absent.
sc_json_field() {
  local json="$1" key="$2"
  python3 -c "import json,sys; d=json.loads(sys.argv[1]); v=d.get(sys.argv[2]); print('' if v is None else v)" "$json" "$key"
}

run_yml_journey() {
  # Iterate the validated step stream. Each line: <idx>\t<kind>\t<json-args>
  local line idx kind args
  while IFS=$'\t' read -r idx kind args; do
    [[ -z "$kind" ]] && continue
    case "$kind" in
      launch)
        local out rc
        out="$(xcrun simctl launch "$SC_UDID" "$SC_BUNDLE_ID" 2>&1)"
        rc=$?
        if [[ "$rc" -eq 0 ]]; then
          emit_step PASS "step${idx}.launch" "${out}"
        else
          emit_step FAIL "step${idx}.launch" "simctl launch failed: ${out}"
          emit_fix_anchor "apps/ios/SoloCompass/App/SoloCompassApp.swift:1" "verify @main entry and bundle id"
          return 1
        fi
        ;;
      wait)
        local secs
        secs="$(sc_json_field "$args" seconds)"
        sleep "$secs"
        emit_step PASS "step${idx}.wait" "slept ${secs}s"
        ;;
      screenshot)
        local label nn rel
        label="$(sc_json_field "$args" label)"
        # NN is the 2-digit zero-padded step ordinal so files sort in journey order.
        nn="$(printf '%02d' "$idx")"
        rel="$(sc_screenshot "$nn" "$label")"
        if [[ -n "$rel" ]]; then
          emit_step PASS "step${idx}.screenshot" "captured $label"
          emit_screenshot "$label" "$rel"
        else
          emit_step FAIL "step${idx}.screenshot" "simctl screenshot failed for $label"
          emit_fix_anchor "scripts/sc-evaluator/run.sh:sc_screenshot" "check simulator boot state and disk space"
        fi
        ;;
      tap|longPress|assertVisible|assertText)
        # The XCUITest backend that performs these gestures is not yet wired
        # up (US-018+). We still emit a step record so the journey trace is
        # complete and downstream tooling can detect the unfulfilled action.
        emit_step PASS "step${idx}.${kind}" "queued (no XCUITest backend) — args=${args}"
        ;;
      *)
        emit_step FAIL "step${idx}.${kind}" "unhandled step kind"
        emit_fix_anchor "scripts/sc-evaluator/run.sh" "add a case for '${kind}'"
        return 1
        ;;
    esac
  done <<< "$PARSED_STEPS"
  return 0
}

if [[ "$JOURNEY_MODE" == "yml" ]]; then
  run_yml_journey || JOURNEY_EXIT=$?
else
  # shellcheck disable=SC1090
  source "$JOURNEY_SCRIPT" || JOURNEY_EXIT=$?
fi

# ---------- final flush (markdown + JSON shadow) ----------
if [[ "$FINDINGS_COUNT" -eq 0 && "$JOURNEY_EXIT" -eq 0 ]]; then
  flush_findings_file PASS ""
else
  flush_findings_file FAIL ""
fi

# Sidecar buffers are no longer needed once the canonical outputs exist.
rm -f "$SCREENSHOTS_BUFFER" "$STEPS_BUFFER" "$FINDINGS_BUFFER" "$FIXES_BUFFER"

echo "→ findings: $FINDINGS_FILE"
echo "→ findings json: $FINDINGS_JSON"

# Screenshot retention: scripts/sc-evaluator/screenshots/ is git-ignored by
# default (see .gitignore). When the developer wants to commit a run's
# screenshots — e.g. to attach visual evidence to a PR — they set
# SC_EVALUATOR_KEEP_SCREENSHOTS=1, and we force-add only this run's directory
# to the index. We never touch capture behaviour: PNGs are written either way.
if [[ "${SC_EVALUATOR_KEEP_SCREENSHOTS:-0}" == "1" ]]; then
  if command -v git >/dev/null 2>&1 && [[ -d "$RUN_SCREENSHOTS_DIR" ]]; then
    if git -C "$REPO_ROOT" add -f "$RUN_SCREENSHOTS_DIR" >/dev/null 2>&1; then
      echo "→ screenshots staged (SC_EVALUATOR_KEEP_SCREENSHOTS=1): $RUN_SCREENSHOTS_DIR"
    fi
  fi
fi

if [[ "$FINDINGS_COUNT" -eq 0 && "$JOURNEY_EXIT" -eq 0 ]]; then
  exit 0
else
  exit 1
fi
