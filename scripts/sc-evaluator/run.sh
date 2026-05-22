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
  ls "$JOURNEYS_DIR" 2>/dev/null | sed 's/\.sh$//' | sed 's/^/  - /' >&2 || true
  exit 2
fi
shift || true
for arg in "$@"; do
  case "$arg" in
    --no-build) SKIP_BUILD=1 ;;
    *) echo "warning: ignoring unknown arg: $arg" >&2 ;;
  esac
done

JOURNEY_SCRIPT="$JOURNEYS_DIR/${JOURNEY}.sh"
if [[ ! -f "$JOURNEY_SCRIPT" ]]; then
  echo "error: journey '$JOURNEY' not found at $JOURNEY_SCRIPT" >&2
  exit 2
fi

# ---------- run id + findings file ----------
RUN_ID="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
FINDINGS_FILE="$FINDINGS_DIR/${RUN_ID}.md"
ARTIFACTS_DIR="$FINDINGS_DIR/${RUN_ID}_artifacts"
mkdir -p "$ARTIFACTS_DIR"

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
  # emit_screenshot <relative-path-from-findings-dir>
  local rel="$1"
  printf -- "  - screenshot: [%s](./%s)\n" "$rel" "$rel" >> "$FINDINGS_FILE"
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

# Helper exported for journey scripts.
sc_screenshot() {
  local name="$1"
  local path="$ARTIFACTS_DIR/${name}.png"
  xcrun simctl io "$UDID" screenshot "$path" >/dev/null 2>&1 || return 1
  # path relative to FINDINGS_DIR for markdown links
  echo "${RUN_ID}_artifacts/${name}.png"
}
export -f sc_screenshot
export -f emit_step
export -f emit_screenshot
export -f emit_fix_anchor

# Journey script may call: emit_step / emit_screenshot / emit_fix_anchor / sc_screenshot.
# A non-zero exit from the journey indicates one or more failed steps.
JOURNEY_EXIT=0
# shellcheck disable=SC1090
source "$JOURNEY_SCRIPT" || JOURNEY_EXIT=$?

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
if [[ "$FINDINGS_COUNT" -eq 0 && "$JOURNEY_EXIT" -eq 0 ]]; then
  exit 0
else
  exit 1
fi
