#!/usr/bin/env bash
#
# US-040: Production `print(...)` auditor for the iOS app.
#
# Counts `print(` calls in shipped Swift source so we can keep migrating them to
# `os.Logger`, which can be filtered in Console.app and stripped from release
# builds. Two classes of `print(` are intentionally NOT counted:
#
#   1. Lines inside a `#Preview { … }` block. Preview-only logging is developer
#      scaffolding, never shipped.
#   2. Anything under a `Tests/` directory. Test diagnostics are not production
#      code.
#
# The script prints every offending `path:line: <code>` it finds, then the total
# count. It exits 1 when the count EXCEEDS the documented baseline below — a
# ratchet that prevents regressions while batches of migration land. After each
# migration batch, lower BASELINE by the number removed.
#
# Usage:  scripts/check-no-production-print.sh
# Exit:   0 = count <= BASELINE, 1 = count > BASELINE (regression).

set -euo pipefail

# Baseline production print() count, post US-040 batch 1 (AgentRouter +
# MapViewModel + SubscriptionService migrated to os.Logger; dropped by 3).
BASELINE=16

# Resolve repo root from this script's location so it runs from anywhere
# (CI, an Xcode test host, a developer shell).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="${SCRIPT_DIR}/../apps/ios/SoloCompass"

if [ ! -d "$IOS_DIR" ]; then
  echo "error: iOS source directory not found at $IOS_DIR" >&2
  exit 2
fi

offenders=0

# Walk every .swift file outside Tests/. For each, use awk to mark which lines
# fall inside a `#Preview { … }` block (tracked by brace depth) and emit only
# the `print(` lines that are OUTSIDE preview blocks.
while IFS= read -r -d '' file; do
  while IFS=$'\t' read -r lineno code; do
    [ -z "$lineno" ] && continue
    echo "${file}:${lineno}: ${code}"
    offenders=$((offenders + 1))
  done < <(
    awk '
      # Track whether we are inside a #Preview { ... } block via brace depth.
      {
        line = $0
      }
      # Enter preview region when we see a #Preview directive.
      /#Preview/ { in_preview = 1 }
      in_preview {
        # Count braces on this line to know when the block closes.
        n = gsub(/{/, "{", line); depth += n
        m = gsub(/}/, "}", line); depth -= m
        if (started && depth <= 0) { in_preview = 0; started = 0; depth = 0 }
        else if (n > 0) { started = 1 }
        next
      }
      # Outside previews: report any print( call.
      /print\(/ {
        printf "%d\t%s\n", NR, $0
      }
    ' "$file"
  )
done < <(find "$IOS_DIR" -name '*.swift' -not -path '*/Tests/*' -print0 | sort -z)

echo ""
echo "production print() count: ${offenders} (baseline ${BASELINE})"

if [ "$offenders" -gt "$BASELINE" ]; then
  echo "✗ Production print() count regressed above baseline. Migrate new print() calls to os.Logger."
  exit 1
fi

echo "✓ Production print() count within baseline."
exit 0
