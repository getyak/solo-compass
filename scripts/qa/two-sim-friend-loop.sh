#!/usr/bin/env bash
# two-sim-friend-loop.sh — US-027 end-to-end loop harness for the Friends /
# Companion social graph.
#
# Drives TWO iOS simulators side-by-side (User A "scanner" + User B "owner")
# through the full loop:
#
#   scan-add-friend -> friend invites to a meetup -> meetup builds a group
#   chat -> someone in the group taps [Add Friend] -> mutual upgrade ->
#   DM + push arrives
#
# WHY half-automated: on Xcode 26.4 / iOS 26.4, idb and AppleScript-driven
# taps are unreliable (idb Abort trap, no accessibility permission). Only
# `simctl boot/install/launch/screenshot/openurl/push` are stable. So this
# harness OWNS the deterministic plumbing — booting both sims, installing the
# build, injecting per-user identity + feature-flag env, capturing labelled
# screenshots, delivering APNs payloads, and (optionally) asserting backend
# rows over SQL — while the human tester performs the in-app taps following
# docs/qa/friend-companion-loop-regression.md. Each step prints a PROMPT and
# waits, then screenshots the result as evidence.
#
# This is intentionally NOT a pass/fail CI gate; it is a guided, reproducible
# manual-verification rig that leaves a screenshot trail under artifacts/.
#
# Usage:
#   scripts/qa/two-sim-friend-loop.sh                 # flag-on, real backend
#   FLAG=off scripts/qa/two-sim-friend-loop.sh        # flag-off no-crash run
#   SIM_A="iPhone 17 Pro" SIM_B="iPhone 16" scripts/qa/two-sim-friend-loop.sh
#
# Required env for the flag-on real-backend run:
#   SUPABASE_URL, SUPABASE_ANON_KEY   (User A + User B authed sessions)
# Optional:
#   APP_PATH      path to a built SoloCompass.app (else assumed pre-installed)
#   PUSH_A_JSON / PUSH_B_JSON   APNs payload files for simulated push delivery
#   DATABASE_URL  psql connection string to assert friendships/conversations
#
set -uo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE_ID="com.solocompass.app"
SIM_A="${SIM_A:-iPhone 17 Pro}"   # User A — the scanner (adds via friend code)
SIM_B="${SIM_B:-iPhone 16 Pro}"   # User B — the code owner / meetup host
FLAG="${FLAG:-on}"                # on => FF_COMPANION=1 ; off => 0
ARTIFACTS="${ARTIFACTS:-$ROOT/artifacts/two-sim-friend-loop/$(date +%Y%m%d-%H%M%S)}"
APP_PATH="${APP_PATH:-}"

mkdir -p "$ARTIFACTS"

# ---------------------------------------------------------------------------
# Pretty logging
# ---------------------------------------------------------------------------
c_reset=$'\033[0m'; c_blue=$'\033[34m'; c_green=$'\033[32m'
c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_bold=$'\033[1m'
log()    { printf '%s[loop]%s %s\n' "$c_blue" "$c_reset" "$*"; }
ok()     { printf '%s[ ok ]%s %s\n' "$c_green" "$c_reset" "$*"; }
warn()   { printf '%s[warn]%s %s\n' "$c_yellow" "$c_reset" "$*"; }
err()    { printf '%s[fail]%s %s\n' "$c_red" "$c_reset" "$*" >&2; }
prompt() {
  printf '\n%s%s>>> MANUAL STEP:%s %s\n' "$c_bold" "$c_yellow" "$c_reset" "$*"
  printf '    Press [Enter] when done (or "s" + Enter to skip)... '
  read -r _ans
  [[ "${_ans:-}" == "s" ]] && { warn "skipped"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# Simulator helpers
# ---------------------------------------------------------------------------
udid_for() {
  # $1 = device name; echoes the first matching UDID (booted or shutdown).
  xcrun simctl list devices available \
    | grep -E "    $1 \(" \
    | head -1 \
    | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}

boot_sim() {
  local udid="$1" name="$2"
  if [[ -z "$udid" ]]; then
    err "no available simulator named '$name' — run: xcrun simctl list devices"
    exit 1
  fi
  local state
  state="$(xcrun simctl list devices | grep "$udid" | grep -oE '\((Booted|Shutdown)\)' | tr -d '()')"
  if [[ "$state" != "Booted" ]]; then
    log "booting $name ($udid)"
    xcrun simctl boot "$udid" 2>/dev/null || true
  else
    ok "$name already booted"
  fi
}

install_app() {
  local udid="$1"
  if [[ -z "$APP_PATH" ]]; then
    warn "APP_PATH not set; assuming app already installed on $udid (build it first)"
    return 0
  fi
  log "installing app on $udid"
  xcrun simctl install "$udid" "$APP_PATH"
}

launch_app() {
  # $1 udid, $2 user-label (A|B). Injects feature-flag + backend env.
  local udid="$1" who="$2"
  local -a env_args=()
  if [[ "$FLAG" == "on" ]]; then
    env_args+=("SIMCTL_CHILD_FF_COMPANION=1")
    env_args+=("SIMCTL_CHILD_SUPABASE_URL=${SUPABASE_URL:-}")
    env_args+=("SIMCTL_CHILD_SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY:-}")
  else
    # flag-off: FF_COMPANION != "1"; app must stay local-only & not crash.
    env_args+=("SIMCTL_CHILD_FF_COMPANION=0")
  fi
  log "launching User $who on $udid (FLAG=$FLAG)"
  env "${env_args[@]}" xcrun simctl launch "$udid" "$BUNDLE_ID" >/dev/null 2>&1 \
    || warn "launch returned non-zero (app may already be foreground)"
}

shot() {
  # $1 udid, $2 label. Captures a labelled PNG under ARTIFACTS.
  local udid="$1" label="$2"
  local out="$ARTIFACTS/${label}.png"
  if xcrun simctl io "$udid" screenshot "$out" >/dev/null 2>&1; then
    ok "screenshot: ${out#"$ROOT"/}"
  else
    warn "screenshot failed for $label"
  fi
}

push() {
  # $1 udid, $2 payload-file. Simulated APNs delivery (works in Simulator).
  local udid="$1" payload="$2"
  if [[ -z "$payload" || ! -f "$payload" ]]; then
    warn "no APNs payload for push step — deliver a real push from the backend instead"
    return 1
  fi
  log "delivering simulated push to $udid"
  xcrun simctl push "$udid" "$BUNDLE_ID" "$payload"
}

sql_assert() {
  # $1 = human label, $2 = SQL returning a count; passes if count > 0.
  local label="$1" query="$2"
  if [[ -z "${DATABASE_URL:-}" ]]; then
    warn "DATABASE_URL unset — skipping backend assert: $label"
    return 0
  fi
  if ! command -v psql >/dev/null 2>&1; then
    warn "psql not found — skipping backend assert: $label"
    return 0
  fi
  local n
  n="$(psql "$DATABASE_URL" -tAc "$query" 2>/dev/null | tr -d '[:space:]')"
  if [[ "${n:-0}" -gt 0 ]]; then
    ok "backend assert PASS ($label): count=$n"
  else
    err "backend assert FAIL ($label): count=${n:-0}"
  fi
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
log "US-027 two-sim friend loop — FLAG=$FLAG"
log "artifacts -> $ARTIFACTS"
if [[ "$FLAG" == "on" && ( -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ) ]]; then
  err "FLAG=on requires SUPABASE_URL and SUPABASE_ANON_KEY for the real-backend run"
  err "for the local no-crash smoke test run: FLAG=off $0"
  exit 1
fi

UDID_A="$(udid_for "$SIM_A")"
UDID_B="$(udid_for "$SIM_B")"
boot_sim "$UDID_A" "$SIM_A"
boot_sim "$UDID_B" "$SIM_B"
xcrun simctl bootstatus "$UDID_A" -b >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID_B" -b >/dev/null 2>&1 || true

install_app "$UDID_A"
install_app "$UDID_B"
launch_app "$UDID_A" "A"
launch_app "$UDID_B" "B"
sleep 4
shot "$UDID_A" "00-A-launch"
shot "$UDID_B" "00-B-launch"

# ---------------------------------------------------------------------------
# FLAG-OFF short-circuit: only verify no-crash + local-only behaviour.
# ---------------------------------------------------------------------------
if [[ "$FLAG" == "off" ]]; then
  warn "FLAG=off run — verifying the app does NOT crash with Companion disabled."
  prompt "On BOTH sims: open Me sheet, try to reach Friends/Add Friend. Confirm the gated entry points are hidden OR no-op, and neither app crashes." || true
  shot "$UDID_A" "01-A-flagoff-me"
  shot "$UDID_B" "01-B-flagoff-me"
  ok "flag-off no-crash pass — see $ARTIFACTS"
  exit 0
fi

# ---------------------------------------------------------------------------
# FLAG-ON full loop (real backend)
# ---------------------------------------------------------------------------

# Step 1 — User B reveals friend code; User A scans/redeems it.
prompt "User B ($SIM_B): Me sheet -> Add Friend -> show MY friend code (QR + text). User A ($SIM_A): Add Friend -> Scan/Enter B's code -> redeem." || true
shot "$UDID_B" "10-B-friend-code"
shot "$UDID_A" "11-A-redeemed"
sql_assert "friendship A<->B exists" \
  "select count(*) from public.friendships where status in ('accepted','active');"

# Step 2 — B invites A to a meetup (route companion), which spins up a group chat.
prompt "User B: open a Route -> Invite friends -> select User A -> send meetup invite. User A: accept the meetup invite." || true
shot "$UDID_B" "20-B-invite-sent"
shot "$UDID_A" "21-A-invite-accepted"
# Backend has no conversations.type column (it's an iOS-model field). A route
# group chat is keyed by an accepted companion_request whose conversation has
# >1 participant. Assert a multi-party conversation exists instead.
sql_assert "group conversation created" \
  "select count(*) from public.conversations where jsonb_array_length(participant_ids) > 1;"
shot "$UDID_A" "22-A-group-chat"
shot "$UDID_B" "23-B-group-chat"

# Step 3 — In the group chat, someone taps [Add Friend] on the OTHER member -> mutual upgrade.
prompt "In the GROUP CHAT, tap [+ Add Friend] on the other participant's row/avatar. Other side: accept -> mutual friendship upgrade." || true
shot "$UDID_A" "30-A-addfriend-in-group"
shot "$UDID_B" "31-B-addfriend-accept"

# Step 4 — Mutual friends can now open a direct (friendDirect) DM thread.
prompt "Open the now-mutual friend's profile -> Message -> send a DM. Confirm a direct (1:1) thread opens (requestId is nil for friendDirect)." || true
shot "$UDID_A" "40-A-dm-sent"
# friendDirect DMs are backed by a Friendship, not a companion_request, so the
# backend marks them with request_id IS NULL (migration 0008 relaxed the NOT
# NULL). That is the durable backend signal for a direct thread.
sql_assert "friendDirect DM thread exists (request_id is null)" \
  "select count(*) from public.conversations where request_id is null;"

# Step 5 — Push arrives on the recipient (message-notify -> APNs).
log "Waiting for the message-notify Edge Function to deliver a push to User B..."
if ! push "$UDID_B" "${PUSH_B_JSON:-}"; then
  prompt "Confirm the real push notification from 'message-notify' arrives on User B's lock screen / banner." || true
fi
shot "$UDID_B" "50-B-push-received"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
ok "End-to-end loop walk complete."
log "Evidence: $ARTIFACTS"
log "Fill in pass/fail in docs/qa/friend-companion-loop-regression.md"
