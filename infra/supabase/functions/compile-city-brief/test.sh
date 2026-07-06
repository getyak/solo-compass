#!/usr/bin/env bash
# Curl-based integration smoke test for compile-city-brief.
#
# Requires the project ref and ONE credential in env:
#   PROJECT           — Supabase project ref
#   CRON_SECRET       — value of CITY_BRIEF_CRON_SECRET, OR
#   SERVICE_ROLE_KEY  — the service-role key
# Optional:
#   CITY              — city_code (default: vte)
#   TARGET            — kit|events|both (default: events)
#
# It curls twice. The first call compiles; the second call (WITHOUT force)
# should be skipped by the cooldown — look for outcomes[].error == "cooldown".

set -euo pipefail

: "${PROJECT:?Set PROJECT to your Supabase project ref}"

CITY="${CITY:-vte}"
TARGET="${TARGET:-events}"
URL="https://${PROJECT}.functions.supabase.co/compile-city-brief"

# Pick the auth header from whichever credential is provided.
if [[ -n "${CRON_SECRET:-}" ]]; then
  AUTH_HEADER=(-H "x-cron-secret: ${CRON_SECRET}")
elif [[ -n "${SERVICE_ROLE_KEY:-}" ]]; then
  AUTH_HEADER=(-H "Authorization: Bearer ${SERVICE_ROLE_KEY}")
else
  echo "Set CRON_SECRET or SERVICE_ROLE_KEY" >&2
  exit 1
fi

echo "→ [1/2] POST $URL  (force=true — actually compiles)"
curl -fsSL "$URL" \
  "${AUTH_HEADER[@]}" \
  -H "Content-Type: application/json" \
  --data "{\"city_code\":\"${CITY}\",\"target\":\"${TARGET}\",\"force\":true}" \
  | python3 -m json.tool

echo
echo "→ [2/2] POST $URL  (no force — expect cooldown skip)"
curl -fsSL "$URL" \
  "${AUTH_HEADER[@]}" \
  -H "Content-Type: application/json" \
  --data "{\"city_code\":\"${CITY}\",\"target\":\"${TARGET}\"}" \
  | python3 -m json.tool
