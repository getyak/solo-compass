#!/usr/bin/env bash
# sc-executor/run.sh — Solo Compass executor runtime.
#
# Reads the most recent sc-evaluator findings file from
# scripts/sc-evaluator/findings/*.md and either:
#   - default (dry-run): prints the proposed unified diff to stdout
#   - --apply:            writes the changes, commits to a per-run branch
#                         agent/<run_id>, then runs `xcodebuild build`. If the
#                         build fails the working tree is reset and the branch
#                         removed.
#
# The "patch" itself is the materialization of the evaluator's recommendation:
# a plan file at scripts/sc-executor/plans/<run_id>.md that mirrors the
# findings file's `## Findings` and `## Suggested Fixes` sections into a
# checked-in, machine-readable plan. This gives the loop an actual file diff
# to commit per run without yet attempting risky source-tree rewrites.
#
# Usage:
#   scripts/sc-executor/run.sh            # dry-run
#   scripts/sc-executor/run.sh --apply    # apply + commit + build
#
# Exit codes:
#   0  patch produced (and, in --apply mode, build passed)
#   1  setup error (no findings, stale findings, build failed after apply)
#   2  bad arguments

set -u
set -o pipefail

# ---------- locate repo ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IOS_DIR="$REPO_ROOT/apps/ios"
FINDINGS_DIR="$REPO_ROOT/scripts/sc-evaluator/findings"
PLANS_DIR="$SCRIPT_DIR/plans"
STALENESS_SECONDS=3600  # 1 hour

mkdir -p "$PLANS_DIR"

# ---------- args ----------
MODE="dry-run"
for arg in "$@"; do
  case "$arg" in
    --apply)   MODE="apply" ;;
    --dry-run) MODE="dry-run" ;;
    -h|--help)
      sed -n '1,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "error: unknown arg: $arg" >&2
      echo "usage: $0 [--apply]" >&2
      exit 2
      ;;
  esac
done

# ---------- find latest findings file ----------
if [[ ! -d "$FINDINGS_DIR" ]]; then
  echo "error: findings dir not found: $FINDINGS_DIR" >&2
  echo "       run scripts/sc-evaluator/run.sh first" >&2
  exit 1
fi

LATEST_FINDINGS="$(find "$FINDINGS_DIR" -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null \
  | xargs -0 stat -f '%m %N' 2>/dev/null \
  | sort -rn | head -1 | awk '{print $2}')"

if [[ -z "$LATEST_FINDINGS" || ! -f "$LATEST_FINDINGS" ]]; then
  echo "error: no findings files found in $FINDINGS_DIR" >&2
  echo "       run scripts/sc-evaluator/run.sh first" >&2
  exit 1
fi

# ---------- staleness check ----------
NOW_EPOCH="$(date +%s)"
FINDINGS_MTIME="$(stat -f '%m' "$LATEST_FINDINGS" 2>/dev/null || echo 0)"
AGE_SECONDS=$((NOW_EPOCH - FINDINGS_MTIME))

if (( AGE_SECONDS > STALENESS_SECONDS )); then
  age_min=$((AGE_SECONDS / 60))
  echo "error: latest findings file is stale (${age_min} minutes old, threshold: $((STALENESS_SECONDS / 60))m)" >&2
  echo "       file: $LATEST_FINDINGS" >&2
  echo "       re-run scripts/sc-evaluator/run.sh to refresh findings" >&2
  exit 1
fi

# ---------- derive run_id from findings filename ----------
RUN_ID="$(basename "$LATEST_FINDINGS" .md)"
PLAN_FILE="$PLANS_DIR/${RUN_ID}.md"
PLAN_REL="scripts/sc-executor/plans/${RUN_ID}.md"

# ---------- build the plan content from findings ----------
# Extract `## Findings`, `## Suggested Fixes`, and `## Summary` sections via
# python so we get reliable section-bounded slicing.
PLAN_CONTENT="$(python3 - "$LATEST_FINDINGS" "$RUN_ID" <<'PY'
import sys
from pathlib import Path

src = Path(sys.argv[1]).read_text(encoding="utf-8")
run_id = sys.argv[2]

def section(name: str) -> str:
    marker = f"## {name}"
    idx = src.find(marker)
    if idx == -1:
        return f"_no `{name}` section in findings_"
    rest = src[idx + len(marker):]
    end = rest.find("\n## ")
    body = rest if end == -1 else rest[:end]
    return body.strip() or f"_empty `{name}` section_"

print(f"# sc-executor plan — {run_id}")
print()
print(f"Generated from: `scripts/sc-evaluator/findings/{run_id}.md`")
print()
print("## Findings")
print()
print(section("Findings"))
print()
print("## Suggested Fixes")
print()
print(section("Suggested Fixes"))
print()
print("## Summary")
print()
print(section("Summary"))
PY
)"

# ---------- emit unified diff (always) ----------
# Construct a single unified diff that creates the plan file. Using
# `git diff --no-index` against /dev/null guarantees the diff is identical
# whether the plan exists or not.
TMP_PLAN="$(mktemp)"
printf '%s\n' "$PLAN_CONTENT" > "$TMP_PLAN"

# Note: `git diff --no-index` exits 1 when there are differences; that's
# expected here, so we don't propagate that exit code.
DIFF_OUT="$(git -C "$REPO_ROOT" diff --no-index --no-color \
  --src-prefix=a/ --dst-prefix=b/ \
  /dev/null "$TMP_PLAN" 2>/dev/null || true)"

# Rewrite the b/ path so the diff applies relative to the repo root.
# git diff --no-index emits the absolute temp path on both the
# `diff --git` header and the `+++ b/<path>` line; rewrite both so the
# diff is reviewable as if the file lived at its final location.
DIFF_OUT="$(printf '%s\n' "$DIFF_OUT" \
  | sed -E "s|${TMP_PLAN}|/${PLAN_REL}|g")"

if [[ "$MODE" == "dry-run" ]]; then
  echo "# sc-executor (dry-run)"
  echo "# latest findings: $LATEST_FINDINGS"
  echo "# would write:     $PLAN_FILE"
  echo "# run with --apply to commit on branch agent/${RUN_ID}"
  echo
  printf '%s\n' "$DIFF_OUT"
  rm -f "$TMP_PLAN"
  exit 0
fi

# ---------- --apply path ----------
rm -f "$TMP_PLAN"

# Refuse to operate on a dirty tree to keep the post-build reset safe.
if ! git -C "$REPO_ROOT" diff --quiet || ! git -C "$REPO_ROOT" diff --cached --quiet; then
  echo "error: working tree is dirty — commit or stash before --apply" >&2
  git -C "$REPO_ROOT" status --short >&2
  exit 1
fi

CURRENT_BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
TARGET_BRANCH="agent/${RUN_ID}"

# Reuse the branch if it already exists; otherwise create it from HEAD.
if git -C "$REPO_ROOT" rev-parse --verify --quiet "$TARGET_BRANCH" >/dev/null; then
  echo "→ branch $TARGET_BRANCH already exists — switching"
  git -C "$REPO_ROOT" checkout "$TARGET_BRANCH" >/dev/null
else
  echo "→ creating branch $TARGET_BRANCH from $CURRENT_BRANCH"
  git -C "$REPO_ROOT" checkout -b "$TARGET_BRANCH" >/dev/null
fi

# Write the plan file.
printf '%s\n' "$PLAN_CONTENT" > "$PLAN_FILE"
git -C "$REPO_ROOT" add -- "$PLAN_REL"

if git -C "$REPO_ROOT" diff --cached --quiet; then
  echo "→ plan file is identical to what is already committed; nothing to do"
  git -C "$REPO_ROOT" checkout "$CURRENT_BRANCH" >/dev/null
  exit 0
fi

git -C "$REPO_ROOT" commit -m "agent: sc-executor patch for ${RUN_ID}" >/dev/null
COMMIT_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
echo "→ committed ${COMMIT_SHA} on ${TARGET_BRANCH} (un-pushed)"

# ---------- post-apply build ----------
echo "→ verifying with xcodebuild build…"
BUILD_LOG="$PLANS_DIR/${RUN_ID}.build.log"
if ( cd "$IOS_DIR" && xcodebuild \
      -project SoloCompass.xcodeproj \
      -scheme SoloCompass \
      -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
      -configuration Debug \
      build ) >"$BUILD_LOG" 2>&1; then
  echo "→ build OK — branch ${TARGET_BRANCH} ready (un-pushed)"
  echo "→ build log: $BUILD_LOG"
  exit 0
else
  echo "error: xcodebuild build failed — reverting patch" >&2
  tail -20 "$BUILD_LOG" >&2 || true
  # Reset the working tree on the branch, then return to the original branch.
  git -C "$REPO_ROOT" reset --hard "HEAD~1" >/dev/null
  git -C "$REPO_ROOT" checkout "$CURRENT_BRANCH" >/dev/null
  # Drop the now-empty branch so the run is idempotent.
  git -C "$REPO_ROOT" branch -D "$TARGET_BRANCH" >/dev/null 2>&1 || true
  echo "→ reverted; restored to ${CURRENT_BRANCH}" >&2
  exit 1
fi
