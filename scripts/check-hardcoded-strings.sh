#!/usr/bin/env bash
#
# US-015: Hardcoded English string auditor for the iOS SwiftUI layer.
#
# Greps apps/ios/SoloCompass/Views for `Text("X…")` literals that begin with an
# uppercase ASCII letter — a strong signal the copy is a hardcoded English
# string rather than an `NSLocalizedString(...)` lookup. Two classes of match
# are intentionally NOT offenders:
#
#   1. Lines inside a `#Preview { … }` block. Preview-only copy is developer
#      scaffolding, never shipped, and need not be localized.
#   2. Acceptable proper nouns / fixed glyph prefixes (see ALLOWLIST below),
#      e.g. the brand name "Solo Compass" or the "L\(level)" confidence badge.
#
# Every other match is printed as `path:line: <code>` and the script exits 1,
# so it can gate CI and back a LocalizationCoverageTest assertion.
#
# Usage:  scripts/check-hardcoded-strings.sh
# Exit:   0 = no offenders, 1 = offenders printed to stdout.

set -euo pipefail

# Resolve repo root from this script's location so it runs from anywhere
# (CI, an Xcode test host, a developer shell).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIEWS_DIR="${SCRIPT_DIR}/../apps/ios/SoloCompass/Views"

if [ ! -d "$VIEWS_DIR" ]; then
  echo "error: Views directory not found at $VIEWS_DIR" >&2
  exit 2
fi

# Substrings that, when present on a matched line, make it acceptable.
# Keep this list tight and documented — every entry is a deliberate exception.
ALLOWLIST=(
  'Text("Solo Compass")'   # app brand name (proper noun) in ShareCard footer
  'Text("L\('               # confidence-level badge prefix, e.g. "L1" / "L2 · 3 signals"
)

is_allowlisted() {
  local line="$1"
  local entry
  for entry in "${ALLOWLIST[@]}"; do
    case "$line" in
      *"$entry"*) return 0 ;;
    esac
  done
  return 1
}

offenders=0

# Walk every .swift file under Views/. For each, use awk to mark which lines
# fall inside a `#Preview { … }` block (tracked by brace depth) and emit only
# the candidate offender lines that are OUTSIDE preview blocks.
while IFS= read -r -d '' file; do
  while IFS=$'\t' read -r lineno code; do
    [ -z "$lineno" ] && continue
    if is_allowlisted "$code"; then
      continue
    fi
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
      # Outside previews: report Text("X…") where X is an uppercase ASCII letter.
      /Text\("[A-Z]/ {
        printf "%d\t%s\n", NR, $0
      }
    ' "$file"
  )
done < <(find "$VIEWS_DIR" -name '*.swift' -print0 | sort -z)

if [ "$offenders" -gt 0 ]; then
  echo ""
  echo "✗ ${offenders} hardcoded English string(s) found in Views/. Replace each with NSLocalizedString(...)."
  exit 1
fi

echo "✓ No hardcoded English strings in Views/."
exit 0
