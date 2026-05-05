#!/usr/bin/env python3
# Update a TestFlight build's "What to Test" (changelog) via the App Store
# Connect API. Designed to run from CI as the second half of a two-step deploy:
# the deploy workflow uploads the IPA fast (no changelog), and this script runs
# afterwards once ASC has finished processing the build, restoring the
# changelog without blocking the upload step on Apple's processing queue.
#
# Required env:
#   APP_STORE_CONNECT_API_KEY_ID       — ASC API key id (10-char string)
#   APP_STORE_CONNECT_ISSUER_ID        — ASC API issuer id (UUID)
#   APP_STORE_CONNECT_API_KEY_CONTENT  — ES256 PEM-encoded private key (multi-line)
#   ASC_APP_ID                         — App Store Connect app id (numeric, e.g. 6762390618)
#   BUILD_NUMBER                       — CURRENT_PROJECT_VERSION used in the build (e.g. "446")
#   MARKETING_VERSION                  — CFBundleShortVersionString (e.g. "0.1.66")
#   CHANGELOG_FILE                     — path to plaintext changelog
# Optional:
#   LOCALE                             — beta-build-localization locale (default "en-US")
#   MAX_WAIT_SECONDS                   — total seconds to wait for build to reach processingState=VALID (default 1800)
#   POLL_INTERVAL_SECONDS              — seconds between polls (default 30)
#
# Strategy:
#   1. Poll for the EXACT build (by build_number + marketing_version) for
#      up to 1800s (30 min). This catches the fast path where Apple processes
#      the build within minutes.
#   2. If the exact build never appears, FALL BACK to the most recent build
#      visible in ASC. This handles slow/incomplete Apple processing — we
#      still set the changelog on whatever the newest build is, which is
#      virtually always the one we just uploaded.
#
# Exits 0 on success, non-zero with diagnostic on failure.
#
# Required env:
#   APP_STORE_CONNECT_API_KEY_ID       — ASC API key id (10-char string)
#   APP_STORE_CONNECT_ISSUER_ID        — ASC API issuer id (UUID)
#   APP_STORE_CONNECT_API_KEY_CONTENT  — ES256 PEM-encoded private key (multi-line)
#   ASC_APP_ID                         — App Store Connect app id (numeric, e.g. 6762390618)
#   BUILD_NUMBER                       — CURRENT_PROJECT_VERSION used in the build (e.g. "446")
#   MARKETING_VERSION                  — CFBundleShortVersionString (e.g. "0.1.66")
#   CHANGELOG_FILE                     — path to plaintext changelog
# Optional:
#   LOCALE                             — beta-build-localization locale (default "en-US")
#   MAX_WAIT_SECONDS                   — total seconds to wait for build to reach processingState=VALID (default 1800)
#   POLL_INTERVAL_SECONDS              — seconds between polls (default 30)
#
# Exits 0 on success, non-zero with diagnostic on failure.

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

try:
    import jwt  # PyJWT
except ImportError:
    print("ERROR: PyJWT not installed. Run: pip install pyjwt cryptography", file=sys.stderr)
    sys.exit(2)

ASC_BASE = "https://api.appstoreconnect.apple.com"


def env(name: str, default: str | None = None, *, required: bool = True) -> str:
    value = os.environ.get(name, default)
    if required and not value:
        print(f"ERROR: env var {name} is required", file=sys.stderr)
        sys.exit(2)
    return value or ""


def make_jwt(key_id: str, issuer_id: str, private_key_pem: str) -> str:
    # ASC tokens have a max lifetime of 20 minutes; we re-mint each polling
    # round to stay safe across long waits.
    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 19 * 60,
        "aud": "appstoreconnect-v1",
    }
    headers = {"kid": key_id, "typ": "JWT"}
    return jwt.encode(payload, private_key_pem, algorithm="ES256", headers=headers)


def asc_request(method: str, path: str, token: str, *, body: dict | None = None,
                query: dict | None = None) -> tuple[int, dict]:
    url = ASC_BASE + path
    if query:
        url += "?" + urllib.parse.urlencode(query, doseq=True)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, method=method, data=data)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/json")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            payload = resp.read().decode()
            return resp.status, (json.loads(payload) if payload else {})
    except urllib.error.HTTPError as e:
        body_text = e.read().decode(errors="replace")
        try:
            return e.code, json.loads(body_text)
        except json.JSONDecodeError:
            return e.code, {"raw": body_text}


def find_build(token: str, app_id: str, build_number: str,
               marketing_version: str) -> dict | None:
    # Query by build number only; preReleaseVersion association may not exist
    # yet when the build first appears in ASC, so the combined filter would
    # return empty even though the build is visible.
    status, payload = asc_request(
        "GET",
        "/v1/builds",
        token,
        query={
            "filter[app]": app_id,
            "filter[version]": build_number,
            "limit": 10,
            "include": "preReleaseVersion",
        },
    )
    if status != 200:
        print(f"GET /v1/builds failed: HTTP {status} {json.dumps(payload)[:500]}", file=sys.stderr)
        return None
    items = payload.get("data") or []
    if not items:
        # Diagnostic: query without version filter to see if any builds exist
        status2, payload2 = asc_request(
            "GET", "/v1/builds", token,
            query={"filter[app]": app_id, "limit": 5},
        )
        total = payload2.get("meta", {}).get("paging", {}).get("total", "?")
        sample = [b.get("attributes", {}).get("version") for b in (payload2.get("data") or [])[:5]]
        print(f"  [diag] app has {total} total builds visible to this API key; "
              f"latest versions: {sample}")
        return None
    # Prefer the build whose included preReleaseVersion matches marketing_version.
    included = payload.get("included") or []
    for item in items:
        prv_id = (item.get("relationships", {})
                  .get("preReleaseVersion", {})
                  .get("data") or {}).get("id")
        if prv_id:
            for inc in included:
                if inc.get("id") == prv_id:
                    if inc.get("attributes", {}).get("version") == marketing_version:
                        return item
    # Fallback: return first result with matching build number regardless of version
    return items[0]


def find_most_recent_build(token: str, app_id: str) -> dict | None:
    """Find the most recent build visible in ASC, regardless of version.

    Used as fallback when the exact build_number + marketing_version
    combo never appears (e.g. Apple takes >2h to process). The most recent
    build is virtually always the one we just uploaded.
    """
    status, payload = asc_request(
        "GET",
        "/v1/builds",
        token,
        query={
            "filter[app]": app_id,
            "sort": "-uploadedDate",
            "limit": 5,
            "include": "preReleaseVersion",
        },
    )
    if status != 200:
        print(f"GET /v1/builds (fallback) failed: HTTP {status}", file=sys.stderr)
        return None
    items = payload.get("data") or []
    if not items:
        return None
    # Return newest build that is VALID (or first one if none VALID yet)
    for item in items:
        if item.get("attributes", {}).get("processingState") == "VALID":
            return item
    return items[0]


def wait_for_processed_build(token_factory, app_id: str, build_number: str,
                             marketing_version: str, max_wait: int,
                             poll_interval: int) -> dict:
    deadline = time.time() + max_wait
    last_state: str | None = None
    fell_back = False
    fallback_deadline = None  # set when fallback activates

    while True:
        token = token_factory()
        build = find_build(token, app_id, build_number, marketing_version)
        if build is None:
            state_msg = "build not yet visible in ASC"
        else:
            state = build.get("attributes", {}).get("processingState")
            last_state = state
            if state == "VALID":
                return build
            if state in {"INVALID", "FAILED"}:
                raise RuntimeError(
                    f"Build {marketing_version}({build_number}) processing ended in {state}"
                )
            state_msg = f"processingState={state}"
        remaining = int(deadline - time.time())
        if remaining <= 0:
            if not fell_back:
                print(f"  Exact build {marketing_version}({build_number}) not found after "
                      f"{max_wait}s. Falling back to most-recent-build strategy...")
                fell_back = True
                fallback_deadline = time.time() + max_wait  # give fallback same window

            if fell_back:
                # Fallback loop: try to find the most recent build
                token2 = token_factory()
                fallback = find_most_recent_build(token2, app_id)
                if fallback is not None:
                    fb_state = fallback.get("attributes", {}).get("processingState", "?")
                    if fb_state == "VALID":
                        print(f"  Fallback succeeded: build processingState=VALID")
                        return fallback
                    fb_remaining = int(fallback_deadline - time.time())
                    if fb_remaining > 0:
                        print(f"  Fallback build processingState={fb_state}; "
                              f"sleeping {poll_interval}s ({fb_remaining}s left)")
                    else:
                        raise TimeoutError(
                            f"Fallback timed out after {max_wait * 2}s total. "
                            f"Build {marketing_version}({build_number}) never appeared. "
                            f"This is usually transient — Apple processing > {max_wait * 2}s. "
                            f"Next deploy will retry."
                        )
                else:
                    fb_remaining = int(fallback_deadline - time.time())
                    if fb_remaining > 0:
                        print(f"  Fallback build not yet visible; "
                              f"sleeping {poll_interval}s ({fb_remaining}s left)")
                    else:
                        raise TimeoutError(
                            f"No builds visible in ASC after {max_wait * 2}s. "
                            f"Possible ASC API key permission issue."
                        )
                time.sleep(poll_interval)
                continue

            raise TimeoutError(
                f"Timed out after {max_wait}s waiting for build "
                f"{marketing_version}({build_number}) to reach VALID "
                f"(last seen: {last_state or 'not found'})"
            )
        print(f"  {state_msg}; sleeping {poll_interval}s ({remaining}s left)")
        time.sleep(poll_interval)


def upsert_localization(token: str, build_id: str, locale: str,
                        whats_new: str) -> None:
    status, payload = asc_request(
        "GET",
        f"/v1/builds/{build_id}/betaBuildLocalizations",
        token,
        query={"limit": 50},
    )
    if status != 200:
        raise RuntimeError(f"GET betaBuildLocalizations failed: HTTP {status} {payload}")

    existing = None
    for item in payload.get("data") or []:
        if item.get("attributes", {}).get("locale") == locale:
            existing = item
            break

    if existing:
        loc_id = existing["id"]
        body = {
            "data": {
                "type": "betaBuildLocalizations",
                "id": loc_id,
                "attributes": {"whatsNew": whats_new},
            }
        }
        status, payload = asc_request("PATCH",
                                      f"/v1/betaBuildLocalizations/{loc_id}",
                                      token, body=body)
        if status not in (200, 204):
            raise RuntimeError(
                f"PATCH betaBuildLocalization failed: HTTP {status} {payload}"
            )
        print(f"Updated existing betaBuildLocalization {loc_id} (locale={locale})")
    else:
        body = {
            "data": {
                "type": "betaBuildLocalizations",
                "attributes": {"locale": locale, "whatsNew": whats_new},
                "relationships": {
                    "build": {"data": {"type": "builds", "id": build_id}}
                },
            }
        }
        status, payload = asc_request("POST", "/v1/betaBuildLocalizations",
                                      token, body=body)
        if status not in (200, 201):
            raise RuntimeError(
                f"POST betaBuildLocalizations failed: HTTP {status} {payload}"
            )
        print(f"Created betaBuildLocalization (locale={locale})")


def main() -> int:
    key_id = env("APP_STORE_CONNECT_API_KEY_ID")
    issuer_id = env("APP_STORE_CONNECT_ISSUER_ID")
    key_pem = env("APP_STORE_CONNECT_API_KEY_CONTENT")
    app_id = env("ASC_APP_ID")
    build_number = env("BUILD_NUMBER")
    marketing_version = env("MARKETING_VERSION")
    changelog_path = env("CHANGELOG_FILE")
    locale = env("LOCALE", "en-US", required=False)
    max_wait = int(env("MAX_WAIT_SECONDS", "1800", required=False))
    poll_interval = int(env("POLL_INTERVAL_SECONDS", "30", required=False))

    changelog_text = Path(changelog_path).read_text(encoding="utf-8").strip()
    if not changelog_text:
        print("ERROR: changelog file is empty", file=sys.stderr)
        return 2

    # ASC caps "What to Test" at 4000 chars; deploy step already trims to 3800
    # but be defensive in case this script is invoked with a different source.
    if len(changelog_text) > 4000:
        changelog_text = changelog_text[:4000]

    print(f"Updating changelog for build {marketing_version} ({build_number}), locale={locale}")
    print(f"  app_id={app_id}, max_wait={max_wait}s, poll_interval={poll_interval}s")
    print(f"  changelog ({len(changelog_text)} chars):")
    for line in changelog_text.splitlines()[:20]:
        print(f"    {line}")
    if len(changelog_text.splitlines()) > 20:
        print("    ...")

    def token_factory() -> str:
        return make_jwt(key_id, issuer_id, key_pem)

    print("Waiting for build to reach processingState=VALID...")
    build = wait_for_processed_build(
        token_factory, app_id, build_number, marketing_version,
        max_wait, poll_interval,
    )
    build_id = build["id"]
    print(f"Build is VALID: id={build_id}")

    upsert_localization(token_factory(), build_id, locale, changelog_text)
    print("Changelog updated successfully.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, TimeoutError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
