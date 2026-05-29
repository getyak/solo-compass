#!/usr/bin/env bash
#
# US-052: zh-Hans half-width punctuation auditor.
#
# Chinese typography convention uses full-width punctuation (，！？：；（）)
# in CJK text, not the ASCII half-width forms (,!?:;()). This script greps
# apps/ios/SoloCompass/Resources/zh-Hans.lproj/Localizable.strings for
# half-width punctuation that appears in a *Chinese context* — i.e. directly
# adjacent to a CJK character — and reports each offending line.
#
# It deliberately does NOT flag half-width punctuation that is part of a
# technical value rather than Chinese prose, because those must stay ASCII:
#
#   * URLs (https://api.example.com/v1)
#   * format specifiers (%d, %@, %1$@, %.1f) and their "$" / "(" pieces
#   * email / host placeholders (you@example.com)
#   * pure-ASCII English values (e.g. "English")
#
# The CJK-adjacency rule is what isolates "Chinese context": a half-width
# comma is only an offender when a CJK character sits immediately before or
# after it. A comma between two ASCII tokens (a URL, a version range) is left
# alone.
#
# Usage:  scripts/check-zh-punctuation.sh
# Exit:   0 = no offenders, 1 = offenders printed to stdout, 2 = file missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STRINGS_FILE="${SCRIPT_DIR}/../apps/ios/SoloCompass/Resources/zh-Hans.lproj/Localizable.strings"

if [ ! -f "$STRINGS_FILE" ]; then
  echo "error: zh-Hans Localizable.strings not found at $STRINGS_FILE" >&2
  exit 2
fi

# Half-width punctuation that has a full-width CJK equivalent. The audit only
# fires when one of these sits immediately next to a CJK codepoint.
#
#   ,  ->  ，      !  ->  ！      ?  ->  ？
#   :  ->  ：      ;  ->  ；      (  ->  （      )  ->  ）
#
# Implemented in Perl for reliable Unicode property support (\p{Han} plus the
# common CJK punctuation/symbol blocks). The regex matches a half-width mark
# that is adjacent (either side) to a CJK character, anywhere in the line's
# value. We scan only the quoted value of each `"key" = "value";` line.

offenders="$(
  perl -CSD -ne '
    # Only consider the value side: "key" = "value";
    next unless /=\s*"(.*)"\s*;\s*$/;
    my $val = $1;

    # A "CJK character" for adjacency purposes: Han ideographs plus the
    # CJK symbol/punctuation ranges already used in the file (、。「」… etc).
    my $cjk = qr/[\p{Han}\x{3000}-\x{303F}\x{FF00}-\x{FFEF}\x{2018}\x{2019}\x{201C}\x{201D}\x{2026}]/;
    my $hw  = qr/[,!?:;()]/;

    if ($val =~ /(?:$cjk$hw|$hw$cjk)/) {
      print "$.: $_";
    }
  ' "$STRINGS_FILE"
)"

if [ -n "$offenders" ]; then
  echo "$offenders"
  count="$(printf '%s\n' "$offenders" | grep -c '' || true)"
  echo "---"
  echo "${count} line(s) with half-width punctuation in a Chinese context." >&2
  exit 1
fi

exit 0
