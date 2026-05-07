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
import { extractTSStructs, SCHEMA_INTERFACES } from "./parity/ts-extractor.js";
import { extractSwiftStructs } from "./parity/swift-extractor.js";
import { compareStructs, formatReport } from "./parity/comparator.js";

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
// Main
// ---------------------------------------------------------------------------

function main(): void {
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
    console.log(`   Found ${tsStructs.length} TS struct(s): ${tsStructs.map((s) => s.name).join(", ")}`);
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
    console.log(`   Found ${swiftStructs.length} Swift struct(s): ${swiftStructs.map((s) => s.name).join(", ")}`);
    for (const s of swiftStructs) {
      console.log(`\n   ${s.name} (${s.file}):`);
      for (const f of s.fields) {
        console.log(`     ${f.name}: ${f.type}${f.optional ? "?" : ""}`);
      }
    }
  }

  const result = compareStructs(tsStructs, swiftStructs, SCHEMA_INTERFACES);
  const report = formatReport(result);

  process.stdout.write(report);

  if (!result.ok) {
    process.exit(1);
  }
}

main();
