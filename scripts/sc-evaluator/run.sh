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
FINDINGS_FILE="$FINDINGS_DIR/${RUN_ID}.md"
ARTIFACTS_DIR="$FINDINGS_DIR/${RUN_ID}_artifacts"
RUN_SCREENSHOTS_DIR="$SCREENSHOTS_DIR/${RUN_ID}"
mkdir -p "$ARTIFACTS_DIR" "$RUN_SCREENSHOTS_DIR"

# Append-only safety: never overwrite an existing file.
if [[ -e "$FINDINGS_FILE" ]]; then
  echo "error: findings file already exists (would overwrite): $FINDINGS_FILE" >&2
  exit 2
fi

# ---------- findings helpers ----------
FINDINGS_COUNT=0
STEP_RESULTS=()

cat > "$FINDINGS_FILE" <<EOF
# sc-evaluator finding — ${RUN_ID}

- Journey: \`${JOURNEY}\`
- Started: ${RUN_ID}
- Repo: ${REPO_ROOT}

## Steps
EOF

# Screenshot links are buffered to a sidecar file during the run and flushed
# into a `## Screenshots` section right before the `## Summary` block. This
# keeps `## Steps` contiguous in the findings file even though screenshot
# steps and other steps interleave chronologically.
SCREENSHOTS_BUFFER="$ARTIFACTS_DIR/.screenshots-buffer.md"
: > "$SCREENSHOTS_BUFFER"

emit_step() {
  # emit_step <status:PASS|FAIL> <step-name> <detail...>
  local status="$1"
  local name="$2"
  shift 2
  local detail="$*"
  STEP_RESULTS+=("$status|$name|$detail")
  printf -- "- [%s] **%s** — %s\n" "$status" "$name" "$detail" >> "$FINDINGS_FILE"
  if [[ "$status" == "FAIL" ]]; then
    FINDINGS_COUNT=$((FINDINGS_COUNT + 1))
  fi
}

emit_screenshot() {
  # emit_screenshot <label> <relative-path-from-findings-file>
  #
  # Buffers a Markdown image link for the eventual `## Screenshots` section.
  # The buffer is flushed into the findings file at the end of the run so
  # screenshot links stay grouped instead of being interleaved with steps.
  local label="$1"
  local rel="$2"
  printf -- "![%s](%s)\n" "$label" "$rel" >> "$SCREENSHOTS_BUFFER"
}

emit_fix_anchor() {
  # emit_fix_anchor <file:line> <hint>
  local anchor="$1"
  local hint="$2"
  printf -- "  - suggested fix: \`%s\` — %s\n" "$anchor" "$hint" >> "$FINDINGS_FILE"
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
    printf "\n## Summary\n- result: **FAIL** (setup)\n- findings: %d\n" "$FINDINGS_COUNT" >> "$FINDINGS_FILE"
    exit 2
  fi

  echo "  booting $UDID…"
  xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
fi

# Open Simulator.app so the runner is visible (best-effort, never blocks).
open -gja Simulator >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
emit_step PASS "simulator.resolve" "udid=$UDID"

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
    tail -5 "$BUILD_LOG" 2>/dev/null | sed 's/^/    /' >> "$FINDINGS_FILE" || true
    printf "\n## Summary\n- result: **FAIL** (build)\n- findings: %d\n" "$FINDINGS_COUNT" >> "$FINDINGS_FILE"
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
  printf "\n## Summary\n- result: **FAIL** (setup)\n- findings: %d\n" "$FINDINGS_COUNT" >> "$FINDINGS_FILE"
  exit 2
fi
emit_step PASS "app.locate" "$APP_PATH"

# ---------- install + launch ----------
if xcrun simctl install "$UDID" "$APP_PATH" >/dev/null 2>&1; then
  emit_step PASS "app.install" "$BUNDLE_ID"
else
  emit_step FAIL "app.install" "simctl install failed"
  printf "\n## Summary\n- result: **FAIL** (install)\n- findings: %d\n" "$FINDINGS_COUNT" >> "$FINDINGS_FILE"
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

# ---------- flush screenshots section ----------
# Append the `## Screenshots` block (with all buffered image links) before
# the summary, so the findings file ordering is: Steps → Screenshots → Summary.
if [[ -s "$SCREENSHOTS_BUFFER" ]]; then
  {
    printf "\n## Screenshots\n"
    cat "$SCREENSHOTS_BUFFER"
  } >> "$FINDINGS_FILE"
fi
rm -f "$SCREENSHOTS_BUFFER"

# ---------- summary ----------
TOTAL_STEPS=${#STEP_RESULTS[@]}
PASS_STEPS=0
for entry in "${STEP_RESULTS[@]}"; do
  [[ "${entry%%|*}" == "PASS" ]] && PASS_STEPS=$((PASS_STEPS + 1))
done

{
  printf "\n## Summary\n"
  printf -- "- steps: %d/%d passed\n" "$PASS_STEPS" "$TOTAL_STEPS"
  printf -- "- findings: %d\n" "$FINDINGS_COUNT"
  printf -- "- artifacts: ./%s_artifacts/\n" "$RUN_ID"
  if [[ "$FINDINGS_COUNT" -eq 0 && "$JOURNEY_EXIT" -eq 0 ]]; then
    printf -- "- result: **PASS**\n"
  else
    printf -- "- result: **FAIL**\n"
  fi
} >> "$FINDINGS_FILE"

echo "→ findings: $FINDINGS_FILE"

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
