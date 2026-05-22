# shellcheck shell=bash
# Journey: home-screen-cold-start
#
# Placeholder journey for US-016: cold-launch SoloCompass.app and screenshot
# the home (map) screen. Later journeys may extend to filter taps, marker
# selection, voice button, etc.
#
# Available helpers (exported by run.sh):
#   emit_step <PASS|FAIL> <name> <detail>
#   emit_screenshot <relative-path>
#   emit_fix_anchor <file:line> <hint>
#   sc_screenshot <name>          -> echoes relative artifact path
#
# Available env vars:
#   SC_UDID, SC_BUNDLE_ID, SC_ARTIFACTS_DIR, SC_RUN_ID, SC_FINDINGS_FILE

set +e  # let individual steps fail without aborting the journey

# Step 1: launch app (cold start).
LAUNCH_OUT="$(xcrun simctl launch "$SC_UDID" "$SC_BUNDLE_ID" 2>&1)"
LAUNCH_RC=$?
if [[ "$LAUNCH_RC" -eq 0 ]]; then
  emit_step PASS "home.launch" "${LAUNCH_OUT}"
else
  emit_step FAIL "home.launch" "simctl launch failed: ${LAUNCH_OUT}"
  emit_fix_anchor "apps/ios/SoloCompass/App/SoloCompassApp.swift:1" "verify @main entry point and Info.plist bundle identifier"
  return 1
fi

# Give the map a moment to render.
sleep 4

# Step 2: home-screen screenshot.
REL="$(sc_screenshot "01_home_map")"
if [[ -n "$REL" ]]; then
  emit_step PASS "home.screenshot" "captured home map"
  emit_screenshot "$REL"
else
  emit_step FAIL "home.screenshot" "simctl screenshot failed"
  emit_fix_anchor "scripts/sc-evaluator/run.sh:sc_screenshot" "check simulator boot state and disk space"
fi

return 0
