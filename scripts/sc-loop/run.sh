#!/usr/bin/env bash
# sc-loop/run.sh — Solo Compass dual-agent optimization loop.
#
# Drives one evaluator → executor → evaluator cycle until either:
#   (a) the evaluator exits 0 — all journey steps pass (success);
#   (b) the iteration cap is reached (exhausted); or
#   (c) the executor refuses to act — stale findings, dirty tree, or build
#       broken (stopped).
#
# Each iteration is logged to:
#   scripts/sc-loop/runs/<run_id>/iteration-<N>.md
# with timestamp, evaluator exit code, executor action.
#
# Usage:
#   scripts/sc-loop/run.sh <journey-name> [--max-iterations N]
#
# --max-iterations defaults to 5 and is capped at 20. Values above 20 are
# clamped with a warning so a runaway argument can't lock the simulator for
# an unbounded number of cycles.
#
# Exit codes:
#   0  success — evaluator passed at least one iteration
#   1  exhausted — iteration cap hit without success
#   2  bad arguments
#   3  stopped — executor refused or evaluator hit a setup error

set -u
set -o pipefail

# ---------- locate repo ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EVALUATOR="$REPO_ROOT/scripts/sc-evaluator/run.sh"
EXECUTOR="$REPO_ROOT/scripts/sc-executor/run.sh"
RUNS_DIR="$SCRIPT_DIR/runs"
DEFAULT_MAX=5
HARD_CAP=20

mkdir -p "$RUNS_DIR"

# ---------- args ----------
JOURNEY=""
MAX_ITERATIONS="$DEFAULT_MAX"

usage() {
  cat >&2 <<EOF
usage: $0 <journey-name> [--max-iterations N]

  <journey-name>            name of a journey under scripts/sc-evaluator/journeys/
  --max-iterations N        cap the loop at N iterations (default ${DEFAULT_MAX}, max ${HARD_CAP})

exit codes:
  0  success            evaluator exited 0 on some iteration
  1  exhausted          ran the full N iterations without success
  2  bad arguments
  3  stopped            executor refused (stale findings / dirty tree / build broken)
                        or evaluator hit a setup error
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --max-iterations)
      shift
      if [[ "$#" -eq 0 || ! "$1" =~ ^[0-9]+$ ]]; then
        echo "error: --max-iterations requires a positive integer" >&2
        usage
        exit 2
      fi
      MAX_ITERATIONS="$1"
      shift
      ;;
    --max-iterations=*)
      MAX_ITERATIONS="${1#--max-iterations=}"
      if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
        echo "error: --max-iterations requires a positive integer" >&2
        usage
        exit 2
      fi
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "error: unknown flag: $1" >&2
      usage
      exit 2
      ;;
    *)
      if [[ -z "$JOURNEY" ]]; then
        JOURNEY="$1"
      else
        echo "error: unexpected positional arg: $1" >&2
        usage
        exit 2
      fi
      shift
      ;;
  esac
done

if [[ -z "$JOURNEY" ]]; then
  echo "error: journey name required" >&2
  usage
  exit 2
fi

if (( MAX_ITERATIONS < 1 )); then
  echo "error: --max-iterations must be ≥ 1" >&2
  exit 2
fi

if (( MAX_ITERATIONS > HARD_CAP )); then
  echo "warning: --max-iterations ${MAX_ITERATIONS} exceeds hard cap; clamping to ${HARD_CAP}" >&2
  MAX_ITERATIONS="$HARD_CAP"
fi

# ---------- preflight ----------
for tool in "$EVALUATOR" "$EXECUTOR"; do
  if [[ ! -x "$tool" ]]; then
    echo "error: missing or non-executable: $tool" >&2
    exit 2
  fi
done

# ---------- run id ----------
RUN_ID="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
RUN_TIMESTAMP_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RUN_DIR="$RUNS_DIR/${RUN_ID}"
mkdir -p "$RUN_DIR"

echo "→ sc-loop run ${RUN_ID}"
echo "→ journey:        ${JOURNEY}"
echo "→ max iterations: ${MAX_ITERATIONS}"
echo "→ run dir:        ${RUN_DIR}"
echo

# ---------- helpers ----------
log_iteration() {
  # log_iteration <N> <evaluator_exit> <executor_action>
  local n="$1" eval_exit="$2" exec_action="$3"
  local file="$RUN_DIR/iteration-${n}.md"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cat > "$file" <<EOF
# sc-loop iteration ${n}

- timestamp: ${ts}
- journey: \`${JOURNEY}\`
- evaluator exit code: ${eval_exit}
- executor action: ${exec_action}
EOF
}

# ---------- loop ----------
ITERATION=0
EXIT_REASON=""
LOOP_RC=1

while (( ITERATION < MAX_ITERATIONS )); do
  ITERATION=$((ITERATION + 1))
  echo "── iteration ${ITERATION}/${MAX_ITERATIONS} ──────────────────────────"

  EVAL_LOG="$RUN_DIR/iteration-${ITERATION}.evaluator.log"
  echo "→ running evaluator (${JOURNEY})…"
  set +e
  "$EVALUATOR" "$JOURNEY" >"$EVAL_LOG" 2>&1
  EVAL_RC=$?
  set -e

  case "$EVAL_RC" in
    0)
      echo "→ evaluator: PASS (exit 0) — journey passed"
      log_iteration "$ITERATION" "$EVAL_RC" "skipped — evaluator passed"
      EXIT_REASON="success"
      LOOP_RC=0
      break
      ;;
    1)
      echo "→ evaluator: findings (exit 1) — invoking executor (dry-run)…"
      ;;
    2)
      echo "→ evaluator: setup error (exit 2) — stopping"
      log_iteration "$ITERATION" "$EVAL_RC" "skipped — evaluator setup error"
      EXIT_REASON="stopped (evaluator setup error)"
      LOOP_RC=3
      break
      ;;
    *)
      echo "→ evaluator: unexpected exit ${EVAL_RC} — stopping"
      log_iteration "$ITERATION" "$EVAL_RC" "skipped — evaluator unexpected exit"
      EXIT_REASON="stopped (evaluator exit ${EVAL_RC})"
      LOOP_RC=3
      break
      ;;
  esac

  # Evaluator produced findings → invoke executor in dry-run mode. We
  # deliberately avoid --apply: that path creates and switches branches,
  # and the loop is expected to run inside an already-checked-out feature
  # branch where unattended branch changes would be disruptive.
  EXEC_LOG="$RUN_DIR/iteration-${ITERATION}.executor.log"
  set +e
  "$EXECUTOR" >"$EXEC_LOG" 2>&1
  EXEC_RC=$?
  set -e

  case "$EXEC_RC" in
    0)
      echo "→ executor: produced patch (dry-run)"
      log_iteration "$ITERATION" "$EVAL_RC" "patch produced (dry-run, exit 0)"
      ;;
    1)
      echo "→ executor: refused to act (exit 1) — stopping"
      log_iteration "$ITERATION" "$EVAL_RC" "refused (exit 1) — stale findings or build broken"
      EXIT_REASON="stopped (executor refused)"
      LOOP_RC=3
      break
      ;;
    *)
      echo "→ executor: unexpected exit ${EXEC_RC} — stopping"
      log_iteration "$ITERATION" "$EVAL_RC" "unexpected exit ${EXEC_RC}"
      EXIT_REASON="stopped (executor exit ${EXEC_RC})"
      LOOP_RC=3
      break
      ;;
  esac
done

if [[ -z "$EXIT_REASON" ]]; then
  EXIT_REASON="exhausted (max ${MAX_ITERATIONS} iterations)"
  LOOP_RC=1
fi

# ---------- summary ----------
SUMMARY_FILE="$RUN_DIR/summary.md"
{
  printf -- '# sc-loop run %s\n\n' "$RUN_ID"
  printf -- '- journey: `%s`\n' "$JOURNEY"
  printf -- '- started: %s\n' "$RUN_TIMESTAMP_ISO"
  printf -- '- iterations: %d / %d\n' "$ITERATION" "$MAX_ITERATIONS"
  printf -- '- exit reason: **%s**\n' "$EXIT_REASON"
  printf -- '- exit code: %d\n' "$LOOP_RC"
} > "$SUMMARY_FILE"

echo
echo "── sc-loop done ────────────────────────────────────────"
echo "→ iterations:  ${ITERATION} / ${MAX_ITERATIONS}"
echo "→ exit reason: ${EXIT_REASON}"
echo "→ run dir:     ${RUN_DIR}"
echo "→ summary:     ${SUMMARY_FILE}"

exit "$LOOP_RC"
