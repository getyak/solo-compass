/**
 * Anti-pattern lint.
 *
 * Scans the diff against `main` for forbidden keywords that signal a drift
 * away from the three product pillars (Map-First, Experience-as-Unit, AI
 * doesn't decide) or the no-engagement-loop posture.
 *
 * Run locally:   pnpm tsx scripts/anti-pattern-lint.ts
 * In CI:         a workflow step compares HEAD against the merge-base of main.
 *
 * Exits non-zero on any match. Document narrowly-scoped exceptions inline
 * with the comment `anti-pattern-lint:allow <reason>` on the same line.
 */

import { execSync } from "node:child_process";

interface Rule {
  pattern: RegExp;
  reason: string;
}

const RULES: Rule[] = [
  { pattern: /\bsocial[_-]?feed\b/i, reason: "no social feed" },
  { pattern: /\bleaderboard\b/i, reason: "no leaderboards" },
  { pattern: /\bbadge[s]?\b/i, reason: "no gamification badges" },
  { pattern: /\bstreak[s]?\b/i, reason: "no engagement streaks" },
  { pattern: /\bfollow[_-]?user\b/i, reason: "no follow graph" },
  { pattern: /\bshare[_-]?to[_-]?social\b/i, reason: "no share-to-social pressure" },
  { pattern: /\blike[_-]?count\b/i, reason: "no like counts" },
  { pattern: /\bpoints?[_-]?earned\b/i, reason: "no points system" },
  { pattern: /\bdaily[_-]?streak\b/i, reason: "no daily streaks" },
  { pattern: /\bre[_-]?engagement[_-]?(push|notification)\b/i, reason: "no re-engagement nudges" },
  { pattern: /\bxp[_-]?points?\b/i, reason: "no XP" },
  { pattern: /\binvite[_-]?friend\b/i, reason: "no invite-friend prompts" },
  { pattern: /\bgovernment[_-]?id\b/i, reason: "no government ID collection" },
  { pattern: /\bemergency[_-]?contact\b/i, reason: "no emergency contact requirement" },
];

function getDiff(): string {
  // Compare against the merge-base of main. Falls back to HEAD vs main if
  // merge-base lookup fails (detached HEAD on a fresh checkout, etc.).
  try {
    const base = execSync("git merge-base HEAD origin/main", { encoding: "utf8" }).trim();
    return execSync(`git diff --unified=0 ${base} HEAD`, { encoding: "utf8" });
  } catch {
    try {
      return execSync("git diff --unified=0 origin/main HEAD", { encoding: "utf8" });
    } catch {
      return execSync("git diff --unified=0 main HEAD", { encoding: "utf8" });
    }
  }
}

interface Hit {
  file: string;
  line: string;
  rule: Rule;
}

function scan(diff: string): Hit[] {
  const hits: Hit[] = [];
  let currentFile = "";
  for (const raw of diff.split("\n")) {
    if (raw.startsWith("+++ b/")) {
      currentFile = raw.slice("+++ b/".length);
      continue;
    }
    if (!raw.startsWith("+") || raw.startsWith("+++")) continue;
    if (raw.includes("anti-pattern-lint:allow")) continue;

    // Skip the lint script itself — it legitimately mentions every keyword.
    // Skip archived Ralph runs — frozen historical artefacts, not shipped product.
    // Skip the live Ralph PRD — its acceptance criteria reference SwiftUI
    // component names (VerifiedBadge / SkeletonBadgeView / BestNowBadge) which
    // are existing UI affordances, not engagement-loop gamification; JSON has
    // no comment syntax so an inline `:allow` is impossible.
    if (
      currentFile === "scripts/anti-pattern-lint.ts" ||
      currentFile === "docs/PRIVACY.md" ||
      currentFile === "CLAUDE.md" ||
      currentFile === "prd.json" ||
      currentFile === "scripts/ralph/prd.json" ||
      currentFile.startsWith("scripts/ralph/archive/")
    ) {
      continue;
    }

    for (const rule of RULES) {
      if (rule.pattern.test(raw)) {
        hits.push({ file: currentFile, line: raw, rule });
      }
    }
  }
  return hits;
}

function main(): void {
  const diff = getDiff();
  const hits = scan(diff);
  if (hits.length === 0) {
    console.log("anti-pattern-lint: clean ✓");
    return;
  }
  console.error(`anti-pattern-lint: ${hits.length} forbidden pattern(s) introduced`);
  for (const h of hits) {
    console.error(`  ${h.file}: ${h.rule.reason}`);
    console.error(`    ${h.line.slice(0, 200)}`);
  }
  console.error("");
  console.error("If this is a false positive, append `// anti-pattern-lint:allow <reason>`.");
  process.exit(1);
}

main();
