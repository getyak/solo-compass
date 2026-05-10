#!/usr/bin/env tsx
/**
 * TS↔Swift schema parity guard.
 *
 * Usage:
 *   pnpm parity:check
 *   tsx scripts/check-swift-parity.ts [--verbose]
 *
 * Exits 0 when all watched interfaces match their Swift counterparts.
 * Exits 1 and prints a diff report on any mismatch.
 */

import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  extractTSStructs,
  SCHEMA_INTERFACES,
  SWIFTDATA_MODEL_INTERFACES,
} from "./parity/ts-extractor.js";
import { extractSwiftStructs } from "./parity/swift-extractor.js";
import { compareStructs, formatReport } from "./parity/comparator.js";
import { checkDbParity, formatDbParityReport } from "./parity/db-parity.js";
import { checkSqlSwiftParity } from "./parity/sql-swift-parity.js";
import { extractSwiftDataModels, checkSwiftDataParity } from "./parity/swiftdata-parity.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const VERBOSE = process.argv.includes("--verbose");

// ---------------------------------------------------------------------------
// TS source globs (relative to ROOT)
// ---------------------------------------------------------------------------
const TS_GLOBS = [
  "packages/core/src/experience.ts",
  "packages/core/src/confidence.ts",
  "packages/core/src/solo-score.ts",
  "packages/core/src/geo.ts",
];

// ---------------------------------------------------------------------------
// Swift source globs (relative to ROOT)
// ---------------------------------------------------------------------------
const SWIFT_GLOBS = ["apps/ios/SoloCompass/Models/*.swift"];

// ---------------------------------------------------------------------------
// SwiftData @Model source globs (relative to ROOT)
// ---------------------------------------------------------------------------
const SWIFTDATA_GLOBS = ["apps/ios/SoloCompass/Persistence/Models/*.swift"];

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function main(): void {
  // ── TS ↔ Swift parity ────────────────────────────────────────────────────

  if (VERBOSE) {
    console.log("🔍 Extracting TypeScript interfaces...");
  }

  let tsStructs;
  try {
    tsStructs = extractTSStructs(ROOT, TS_GLOBS);
  } catch (err) {
    console.error("❌ Failed to parse TypeScript sources:");
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }

  if (VERBOSE) {
    console.log(
      `   Found ${tsStructs.length} TS struct(s): ${tsStructs.map((s) => s.name).join(", ")}`,
    );
    console.log("🔍 Extracting Swift structs...");
  }

  let swiftStructs;
  try {
    swiftStructs = extractSwiftStructs(ROOT, SWIFT_GLOBS);
  } catch (err) {
    console.error("❌ Failed to parse Swift sources:");
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }

  if (VERBOSE) {
    console.log(
      `   Found ${swiftStructs.length} Swift struct(s): ${swiftStructs.map((s) => s.name).join(", ")}`,
    );
    for (const s of swiftStructs) {
      console.log(`\n   ${s.name} (${s.file}):`);
      for (const f of s.fields) {
        console.log(`     ${f.name}: ${f.type}${f.optional ? "?" : ""}`);
      }
    }
  }

  const swiftResult = compareStructs(tsStructs, swiftStructs, SCHEMA_INTERFACES);
  process.stdout.write(formatReport(swiftResult));

  // ── TS ↔ DB (Drizzle) parity ─────────────────────────────────────────────

  if (VERBOSE) {
    console.log("🔍 Checking TS↔DB (Drizzle) parity...");
  }

  let dbResult;
  try {
    dbResult = checkDbParity(ROOT, VERBOSE);
  } catch (err) {
    console.error("❌ Failed to run DB parity check:");
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }

  process.stdout.write(formatDbParityReport(dbResult));

  // ── Supabase SQL ↔ Swift sync-payload parity (Epic F US-035) ─────────────

  if (VERBOSE) {
    console.log("🔍 Checking Supabase SQL↔Swift sync-payload parity...");
  }

  let sqlSwiftResult;
  try {
    sqlSwiftResult = checkSqlSwiftParity(ROOT, VERBOSE);
  } catch (err) {
    console.error("❌ Failed to run SQL↔Swift parity check:");
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }

  process.stdout.write(sqlSwiftResult.report);

  // ── TS ↔ SwiftData @Model parity ─────────────────────────────────────────

  if (VERBOSE) {
    console.log("🔍 Checking TS↔SwiftData @Model parity...");
  }

  let swiftDataModels;
  try {
    swiftDataModels = extractSwiftDataModels(ROOT, SWIFTDATA_GLOBS);
  } catch (err) {
    console.error("❌ Failed to parse SwiftData @Model sources:");
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }

  if (VERBOSE) {
    console.log(
      `   Found ${swiftDataModels.length} @Model class(es): ${swiftDataModels.map((m) => m.name).join(", ")}`,
    );
  }

  // Re-use the already-extracted TS structs — we just need different watch-set
  const swiftDataResult = checkSwiftDataParity(
    tsStructs,
    swiftDataModels,
    SWIFTDATA_MODEL_INTERFACES,
  );
  process.stdout.write(swiftDataResult.report);

  // ── Exit ─────────────────────────────────────────────────────────────────

  if (!swiftResult.ok || !dbResult.ok || !sqlSwiftResult.passed || !swiftDataResult.ok) {
    process.exit(1);
  }
}

main();
