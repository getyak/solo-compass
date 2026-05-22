#!/bin/bash
# Ralph - Autonomous AI agent loop for Solo Compass
# Each iteration: fresh Claude Code instance → implement single story → test → commit
# Usage: ./ralph.sh [--tool claude] [max_iterations]

set -e
set -o pipefail

TOOL="claude"
MAX_ITERATIONS=10

while [[ $# -gt 0 ]]; do
  case $1 in
    --tool) TOOL="$2"; shift 2 ;;
    --tool=*) TOOL="${1#*=}"; shift ;;
    *) [[ "$1" =~ ^[0-9]+$ ]] && MAX_ITERATIONS="$1"; shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="$SCRIPT_DIR/../../prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Init progress file
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Solo Compass — Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$PROGRESS_FILE"
  echo "Tool: $TOOL" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

echo "🚀 Ralph starting — Tool: $TOOL, Max iterations: $MAX_ITERATIONS"
echo "📋 PRD: $PRD_FILE"
echo ""

# Cache TARGET_BRANCH at start (NEVER re-read from PRD — Claude Code may overwrite it)
TARGET_BRANCH=$(python3 -c "import json; f=open('$PRD_FILE'); print(json.load(f).get('branchName','main'))")
echo "🎯 Target branch: $TARGET_BRANCH"

# Verify we're on the correct branch BEFORE first iteration
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "$TARGET_BRANCH" ]; then
  echo "   ⚠️ Not on target branch ($CURRENT_BRANCH ≠ $TARGET_BRANCH) — switching"
  git checkout "$TARGET_BRANCH"
fi

for i in $(seq 1 $MAX_ITERATIONS); do
  echo "═══════════════════════════════════════════════════════════"
  echo "  Iteration $i / $MAX_ITERATIONS"
  echo "═══════════════════════════════════════════════════════════"

  # Guard: ensure we're on the correct branch (Claude Code may have switched it)
  CURRENT_BRANCH=$(git branch --show-current)
  if [ "$CURRENT_BRANCH" != "$TARGET_BRANCH" ]; then
    echo "   ⚠️ Branch drift: on $CURRENT_BRANCH, expected $TARGET_BRANCH — switching back"
    git checkout "$TARGET_BRANCH"
  fi

  # Find next incomplete story
  STORY=$(python3 -c "
import json, sys
with open('$PRD_FILE') as f:
    prd = json.load(f)
items = prd.get('stories', prd.get('userStories', []))
incomplete = [s for s in items if not s['passes']]
if not incomplete:
    print('ALL_DONE')
    sys.exit(0)
story = incomplete[0]
print(json.dumps(story))
")

  if [ "$STORY" = "ALL_DONE" ]; then
    echo "✅ ALL STORIES COMPLETE!"
    echo "All stories pass: true" >> "$PROGRESS_FILE"
    exit 0
  fi

  STORY_ID=$(echo "$STORY" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  STORY_NAME=$(echo "$STORY" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('name', d.get('title','')))")
  STORY_DESC=$(echo "$STORY" | python3 -c "import json,sys; print(json.load(sys.stdin)['description'])")
  # acceptanceCriteria is an array — join with newlines for the prompt
  STORY_ACCEPT=$(echo "$STORY" | python3 -c "
import json,sys
d = json.load(sys.stdin)
ac = d.get('acceptance', d.get('acceptanceCriteria', []))
if isinstance(ac, list):
    print('\n'.join(f'- {a}' for a in ac))
else:
    print(ac)
")

  echo "📌 Story #$STORY_ID: $STORY_NAME"
  echo "   Acceptance: $STORY_ACCEPT"

  # Pull the most recent progress notes for THIS story so the next iteration
  # can resume instead of re-exploring. Falls back to empty string if none.
  PROGRESS_TAIL=$(grep -F "Story #$STORY_ID" "$PROGRESS_FILE" 2>/dev/null | tail -8 || true)
  if [ -z "$PROGRESS_TAIL" ]; then
    PROGRESS_TAIL="(no prior iterations on this story — fresh start)"
  fi

  # Build the Claude Code prompt
  PROMPT="You are implementing a SINGLE user story for the Solo Compass iOS UI/AI Deep Optimization PRD.

PROJECT: Solo Compass (独行罗盘) — map-first companion app for solo travelers.
Current PRD: static-analysis-driven cleanup of Solo Compass iOS, sourced from tasks/prd-ui-ai-deep-optimization.md.
Tech stack: pnpm monorepo; iOS app under apps/ios/SoloCompass (SwiftUI + MapKit, XcodeGen); web/bot/packages in TypeScript strict.
Skim CLAUDE.md only if you need a convention you don't already know. Choose the relevant target from the story acceptance criteria.

⚠️ CRITICAL: You are working on branch '$TARGET_BRANCH'. NEVER run git checkout, git switch, git branch, or any command that changes the current branch. NEVER push or pull. Only git add and git commit.

⚠️ TURN BUDGET: you have ~60 tool turns total for this story. Spend them on EDITING and BUILDING, not on broad exploration. If a previous iteration already touched files for this story (see progress notes below), CONTINUE from where it stopped — do not re-explore the whole codebase. Run \`git status\` and \`git diff --stat\` ONCE at the start to see what is already in the working tree.

PROGRESS NOTES (recent iterations on this same story; may include build/test errors and NEXT_STEPS hints to fix):
$PROGRESS_TAIL

STORY #$STORY_ID: $STORY_NAME
DESCRIPTION: $STORY_DESC
ACCEPTANCE CRITERIA:
$STORY_ACCEPT

Implement ONLY this story. Do NOT touch unrelated code. Keep changes focused and preserve existing behavior.
After implementing:
1. For iOS stories: cd apps/ios && xcodegen if project.yml changes, then xcodebuild build -project SoloCompass.xcodeproj -scheme SoloCompass -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' when practical
2. For TypeScript/scripts/docs stories: pnpm typecheck and relevant tests; run scripts/check-localization.ts when localization changes
3. Run formatting according to existing project scripts when practical
4. Print a summary of what you changed
5. The acceptance criteria must be satisfied

If you run out of turns before finishing, end your final assistant message with a single line:
NEXT_STEPS: <one short sentence describing exactly what the next iteration should do first>
so the next run can pick up immediately."

  echo "   🤖 Running Claude Code..."

  # Run Claude Code in the repo root
  cd "$REPO_ROOT"
  
  if claude -p "$PROMPT" \
    --allowedTools "Read,Write,Edit,Bash" \
    --max-turns 60 \
    --output-format json \
    --dangerously-skip-permissions 2>&1 | tee /tmp/ralph-output-$i.json; then
    
    echo "   ✅ Story #$STORY_ID implemented successfully"

    # Mark story as passes: true (BEFORE commit so it's included)
    python3 -c "
import json
with open('$PRD_FILE') as f:
    prd = json.load(f)
for s in prd.get('stories', prd.get('userStories', [])):
    if s['id'] == '$STORY_ID':
        s['passes'] = True
        break
with open('$PRD_FILE', 'w') as f:
    json.dump(prd, f, indent=2)
"
    echo "   ✔️ Story #$STORY_ID marked as passes: true"

    # Log progress
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Story #$STORY_ID: $STORY_NAME — PASSED" >> "$PROGRESS_FILE"

    # Git add + commit (includes PRD mark AND progress)
    cd "$REPO_ROOT"
    if git diff --quiet && git diff --cached --quiet; then
      echo "   ⚠️ No changes to commit"
    else
      git add -A
      git commit -m "feat(ai): story #$STORY_ID — $STORY_NAME

Implemented: $STORY_DESC
Acceptance: $STORY_ACCEPT"
      echo "   📝 Committed: story #$STORY_ID"
    fi

  else
    echo "   ❌ Story #$STORY_ID FAILED"
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Story #$STORY_ID: $STORY_NAME — FAILED (iteration $i)" >> "$PROGRESS_FILE"

    # Extract NEXT_STEPS hint (preferred) or fall back to terminal_reason + last
    # ~400 chars of result, so the next iteration's prompt can resume in context.
    NEXT_STEPS=$(python3 - <<'PYEOF' "/tmp/ralph-output-$i.json" 2>/dev/null || true
import json, sys, re
try:
    with open(sys.argv[1]) as f:
        # tee writes one JSON object on the last line (--output-format json),
        # but earlier lines may be progress text — grab the last { ... } block.
        text = f.read()
    m = list(re.finditer(r'\{"type":"result".*?\}\s*$', text, re.S))
    if not m:
        print(""); sys.exit(0)
    obj = json.loads(m[-1].group(0))
    # Look for NEXT_STEPS in the final result text if present.
    result = obj.get("result") or ""
    hint = ""
    for line in result.splitlines()[::-1]:
        if line.strip().startswith("NEXT_STEPS:"):
            hint = line.strip(); break
    if not hint:
        reason = obj.get("terminal_reason") or obj.get("subtype") or "unknown"
        errs = "; ".join(obj.get("errors", []))[:200]
        hint = f"NEXT_STEPS: (auto) prior run ended ({reason}) {errs}".strip()
    print(hint[:400])
except Exception:
    print("")
PYEOF
)
    if [ -n "$NEXT_STEPS" ]; then
      echo "    └─ $NEXT_STEPS" >> "$PROGRESS_FILE"
    fi

    # Don't exit — continue to next iteration (Claude may fix it in next pass)
  fi

  echo ""
done

echo "🏁 Ralph complete after $MAX_ITERATIONS iterations"
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Ralph complete after $MAX_ITERATIONS iterations" >> "$PROGRESS_FILE"

# Report remaining incomplete stories
REMAINING=$(python3 -c "
import json
with open('$PRD_FILE') as f:
    prd = json.load(f)
remaining = [s.get('name', s.get('title', '?')) for s in prd.get('stories', prd.get('userStories', [])) if not s['passes']]
if remaining:
    print('Remaining: ' + ', '.join(remaining))
else:
    print('All complete! 🎉')
")
echo "📊 $REMAINING"
