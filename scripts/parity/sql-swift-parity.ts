/**
 * Supabase SQL ↔ Swift sync-payload parity guard (Epic F US-035).
 *
 * iOS struct fields that get serialized into a Supabase upsert MUST line
 * up with the column names in `infra/supabase/migrations/0001_init.sql`,
 * otherwise the network call returns 400 with no helpful error in the
 * mobile log. This module catches those drifts at CI time.
 *
 * Approach: shallow regex extraction. Both source-of-truth files are
 * tiny and stable, so a full SQL parser would be overkill. We only
 * need: table name → column-name set on the SQL side, and Swift
 * payload struct → field-name set on the Swift side.
 */

import fs from "node:fs";
import path from "node:path";

interface ParityRule {
  /** Swift struct name we're checking */
  swiftStruct: string;
  /** Supabase table name the struct serializes into */
  supabaseTable: string;
  /** Columns we don't expect Swift to send (server defaults / generated) */
  ignoreColumns?: string[];
}

const RULES: ParityRule[] = [
  {
    swiftStruct: "SyncCompletionPayload",
    supabaseTable: "user_completions",
    ignoreColumns: ["id", "updated_at"],
  },
  {
    swiftStruct: "SyncFavoritePayload",
    supabaseTable: "user_favorites",
    ignoreColumns: ["updated_at"],
  },
  {
    swiftStruct: "SubscriptionEventPayload",
    supabaseTable: "subscription_events",
    ignoreColumns: ["id", "created_at", "updated_at"],
  },
  {
    swiftStruct: "SyncUserExperiencePayload",
    supabaseTable: "user_experiences",
    ignoreColumns: ["id", "created_at", "updated_at"],
  },
];

const SWIFT_FILES = [
  "apps/ios/SoloCompass/Persistence/ExperienceRepository.swift",
  "apps/ios/SoloCompass/Services/SubscriptionService.swift",
];

// All migrations whose CREATE TABLE statements back a sync payload. Concatenated
// before column extraction so tables added in later migrations (e.g.
// user_experiences in 0006) are found alongside the originals in 0001.
const SQL_FILES = [
  "infra/supabase/migrations/0001_init.sql",
  "infra/supabase/migrations/0006_user_experiences.sql",
];

function loadFile(rootDir: string, rel: string): string {
  return fs.readFileSync(path.join(rootDir, rel), "utf-8");
}

function extractSqlColumns(sql: string, table: string): string[] | null {
  const re = new RegExp(
    `create\\s+table\\s+if\\s+not\\s+exists\\s+public\\.${table}\\s*\\(([^;]+)\\);`,
    "i",
  );
  const match = sql.match(re);
  if (!match) return null;

  const body = match[1] ?? "";
  const cols: string[] = [];
  for (const rawLine of body.split("\n")) {
    const line = rawLine.trim().replace(/,$/, "");
    if (!line) continue;
    const lower = line.toLowerCase();
    if (
      lower.startsWith("primary key") ||
      lower.startsWith("foreign key") ||
      lower.startsWith("unique") ||
      lower.startsWith("check") ||
      lower.startsWith("constraint")
    ) {
      continue;
    }
    const colMatch = line.match(/^([a-z_][a-z0-9_]*)\s/i);
    if (colMatch) cols.push(colMatch[1]!);
  }
  return cols;
}

function extractSwiftStructFields(source: string, structName: string): string[] | null {
  const re = new RegExp(`struct\\s+${structName}\\s*:\\s*Encodable\\s*\\{([^}]+)\\}`, "m");
  const match = source.match(re);
  if (!match) return null;

  const body = match[1] ?? "";
  const fields: string[] = [];
  for (const rawLine of body.split("\n")) {
    const line = rawLine.trim();
    const m = line.match(/^let\s+([a-z_][a-z0-9_]*)\s*:/i);
    if (m) fields.push(m[1]!);
  }
  return fields;
}

export interface SqlSwiftParityResult {
  passed: boolean;
  report: string;
}

export function checkSqlSwiftParity(rootDir: string, verbose = false): SqlSwiftParityResult {
  const sql = SQL_FILES.map((rel) => loadFile(rootDir, rel)).join("\n\n");
  const swiftSources = SWIFT_FILES.map((rel) => loadFile(rootDir, rel)).join("\n\n");

  const failures: string[] = [];
  const lines: string[] = [];

  for (const rule of RULES) {
    const sqlCols = extractSqlColumns(sql, rule.supabaseTable);
    if (!sqlCols) {
      failures.push(`Could not find table ${rule.supabaseTable} in ${SQL_FILES.join(", ")}`);
      continue;
    }
    const swiftFields = extractSwiftStructFields(swiftSources, rule.swiftStruct);
    if (!swiftFields) {
      failures.push(`Could not find Swift struct ${rule.swiftStruct}`);
      continue;
    }
    const ignored = new Set(rule.ignoreColumns ?? []);
    const missingInSql = swiftFields.filter((f) => !sqlCols.includes(f));
    const missingInSwift = sqlCols.filter((c) => !ignored.has(c) && !swiftFields.includes(c));

    if (missingInSql.length === 0 && missingInSwift.length === 0) {
      lines.push(`  ✓ ${rule.swiftStruct} ↔ ${rule.supabaseTable}`);
    } else {
      const detail: string[] = [];
      if (missingInSql.length) detail.push(`Swift fields not in SQL: ${missingInSql.join(", ")}`);
      if (missingInSwift.length)
        detail.push(`SQL columns not in Swift: ${missingInSwift.join(", ")}`);
      failures.push(`${rule.swiftStruct} ↔ ${rule.supabaseTable}: ${detail.join("; ")}`);
    }
  }

  const passed = failures.length === 0;
  const header = passed
    ? "✅  Supabase SQL↔Swift sync-payload parity: all payloads match table columns."
    : "❌  Supabase SQL↔Swift sync-payload parity: drift detected.";

  let report = `${header}\n`;
  if (verbose && passed) report += lines.join("\n") + "\n";
  if (!passed) {
    for (const f of failures) report += `  - ${f}\n`;
  }
  return { passed, report };
}
