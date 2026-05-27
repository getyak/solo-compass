/**
 * Compares extracted TS and Swift struct fields for schema parity.
 *
 * Type compatibility rules (TS → Swift):
 *   string / ExperienceId / branded string  →  String
 *   number / ConfidenceLevel                →  Double | Int | Float
 *   boolean                                 →  Bool
 *   readonly [number, number] / Coordinates →  [Double] | [Double, Double]
 *   readonly T[] / T[]                      →  [T]
 *   T | undefined (optional)                →  T?
 *   string literal union "a"|"b"            →  Swift enum (same name or known alias)
 *   string (ISO 8601 date)                  →  Date (Swift decodes from string)
 *   nested interface (same name)            →  Same struct name
 *
 * See scripts/parity/README.md for the full mapping table.
 */

import type { TSStruct, TSField } from "./ts-extractor.js";
import type { SwiftStruct, SwiftField } from "./swift-extractor.js";

export interface FieldMismatch {
  structName: string;
  fieldName: string;
  tsType: string;
  tsOptional: boolean;
  swiftType?: string;
  swiftOptional?: boolean;
  issue: "missing_in_swift" | "missing_in_ts" | "type_mismatch" | "optionality_mismatch";
}

export interface ParityResult {
  missingSwiftStructs: string[];
  fieldMismatches: FieldMismatch[];
  ok: boolean;
}

// ---------------------------------------------------------------------------
// Type compatibility
// ---------------------------------------------------------------------------

/**
 * Normalise a raw TS type string.
 * - Strips `readonly` modifier
 * - Unwraps `ReadonlyArray<T>` → `T[]`
 * - Resolves branded string types
 */
function normaliseTSType(raw: string): string {
  let t = raw.trim();
  // Branded type: `string & { readonly __brand: "..." }` → "string"
  t = t.replace(/string\s*&\s*\{[^}]*\}/, "string");
  // ReadonlyArray<T> → T[]
  t = t.replace(/ReadonlyArray<(.+)>/, "$1[]");
  // readonly T[] → T[]
  t = t.replace(/^readonly\s+(.+\[\])$/, "$1");
  // readonly [A, B] → [A, B]
  t = t.replace(/^readonly\s+(\[.+\])$/, "$1");
  // Collapse multi-line union formatting: leading `|` from ts-morph
  t = t.replace(/^\|\s*/, "");
  return t.trim().replace(/\s+/g, " ");
}

/** Strip Swift optionality marker. */
function normaliseSwiftType(raw: string): string {
  return raw.trim().replace(/\?$/, "");
}

/** True if the TS type is a string-literal union: `"a" | "b" | ...` */
function isStringLiteralUnion(t: string): boolean {
  return /^"[^"]+"(\s*\|\s*"[^"]+")+$/.test(t.trim());
}

/**
 * True when a TS string-literal union is satisfied by a Swift enum or String.
 * We accept any single-word Swift identifier (enum name) as compatible,
 * because Swift enums have raw-value Codable that maps to the string literals.
 */
function stringUnionCompatible(swiftType: string): boolean {
  // Swift enum: a single CamelCase identifier (not a primitive, not an array)
  return /^[A-Z][A-Za-z0-9]*$/.test(swiftType) || swiftType === "String";
}

/**
 * Known direct TS→Swift type aliases (ts normalised → swift normalised).
 */
const DIRECT: Record<string, string[]> = {
  string: ["String", "URL", "Date"], // Date: Swift decodes ISO 8601 strings
  number: ["Double", "Int", "Float"],
  boolean: ["Bool"],
  "[number, number]": ["[Double]", "[Double, Double]"],
  Date: ["Date", "String"],
};

/**
 * Known named-type aliases from TS → Swift.
 */
const NAMED_ALIASES: Record<string, string> = {
  ExperienceId: "String",
  UserId: "String",
  ItineraryId: "String",
  CompanionPostId: "String",
  CompanionRequestId: "String",
  ConversationId: "String",
  ChatMessageId: "String",
  CompanionReportId: "String",
  Coordinates: "[Double]",
  ConfidenceLevel: "Int",
  HealthStatus: "HealthStatus",
  ExperienceCategory: "ExperienceCategory",
  ExperienceLocation: "ExperienceLocation",
  TimeWindow: "TimeWindow",
  HowToStep: "HowToStep",
  RealInconvenience: "RealInconvenience",
  InformationSource: "InformationSource",
  SoloScore: "SoloScore",
  Confidence: "Confidence",
};

function typesCompatible(tsType: string, swiftType: string): boolean {
  const normTS = normaliseTSType(tsType);
  const normSW = normaliseSwiftType(swiftType);

  // String literal union → Swift enum or String
  if (isStringLiteralUnion(normTS)) {
    return stringUnionCompatible(normSW);
  }

  // Direct primitive mappings
  for (const [ts, swifts] of Object.entries(DIRECT)) {
    if (normTS === ts && swifts.includes(normSW)) return true;
  }

  // Named aliases
  if (NAMED_ALIASES[normTS] === normSW) return true;

  // Same name (struct references another struct with same name)
  if (normTS === normSW) return true;

  // Arrays: T[] ↔ [T] — check element type compatibility
  const tsArr = /^(.+)\[\]$/.exec(normTS);
  const swArr = /^\[(.+)\]$/.exec(normSW);
  if (tsArr && swArr) {
    return typesCompatible(tsArr[1]!, swArr[1]!);
  }

  // Inline object shape `{ ... }` → accept if Swift has any struct name
  // (we check these shapes via nested struct comparison, not field-by-field here)
  if (normTS.startsWith("{")) return true;

  return false;
}

// ---------------------------------------------------------------------------
// Fields to skip when checking Swift side
// ---------------------------------------------------------------------------

/**
 * Swift-only computed/UI properties that have no TS counterpart.
 * These are not schema fields — they're view helpers or Identifiable conformance.
 */
const IGNORED_SWIFT_FIELDS = new Set([
  "id",
  "coordinate",
  "clCoordinate",
  "scoreColor",
  "health",
  "symbol",
  "color",
  "localizedTitle",
  "localizedDescription",
  "accessibilitySymbol",
  "totalCount",
  // copy() method — not a stored property but just in case parser catches it
  "copy",
]);

// ---------------------------------------------------------------------------
// Main comparator
// ---------------------------------------------------------------------------

export function compareStructs(
  tsStructs: TSStruct[],
  swiftStructs: SwiftStruct[],
  watchedNames: Set<string>,
): ParityResult {
  const swiftByName = new Map(swiftStructs.map((s) => [s.name, s]));
  const tsByName = new Map(tsStructs.map((s) => [s.name, s]));

  const missingSwiftStructs: string[] = [];
  const fieldMismatches: FieldMismatch[] = [];

  for (const structName of watchedNames) {
    const ts = tsByName.get(structName);
    const sw = swiftByName.get(structName);

    if (!ts) continue;

    if (!sw) {
      missingSwiftStructs.push(structName);
      continue;
    }

    const swiftFieldMap = new Map(sw.fields.map((f) => [f.name, f]));
    const tsFieldMap = new Map(ts.fields.map((f) => [f.name, f]));

    // TS → Swift: every TS field must be present and type-compatible
    for (const tsField of ts.fields) {
      const swField = swiftFieldMap.get(tsField.name);

      if (!swField) {
        fieldMismatches.push({
          structName,
          fieldName: tsField.name,
          tsType: tsField.type,
          tsOptional: tsField.optional,
          issue: "missing_in_swift",
        });
        continue;
      }

      if (!typesCompatible(tsField.type, swField.type)) {
        fieldMismatches.push({
          structName,
          fieldName: tsField.name,
          tsType: tsField.type,
          tsOptional: tsField.optional,
          swiftType: swField.type,
          swiftOptional: swField.optional,
          issue: "type_mismatch",
        });
        continue;
      }

      // Optionality: TS required → Swift must not be MORE restrictive (non-optional is fine).
      // TS optional → Swift must be optional too (non-optional = crash risk).
      if (tsField.optional && !swField.optional) {
        fieldMismatches.push({
          structName,
          fieldName: tsField.name,
          tsType: tsField.type,
          tsOptional: true,
          swiftType: swField.type,
          swiftOptional: false,
          issue: "optionality_mismatch",
        });
      }
    }

    // Swift → TS: Swift stored fields not in TS are suspicious (unless ignored)
    for (const swField of sw.fields) {
      if (IGNORED_SWIFT_FIELDS.has(swField.name)) continue;
      if (!tsFieldMap.has(swField.name)) {
        fieldMismatches.push({
          structName,
          fieldName: swField.name,
          tsType: "(absent)",
          tsOptional: false,
          swiftType: swField.type,
          swiftOptional: swField.optional,
          issue: "missing_in_ts",
        });
      }
    }
  }

  return {
    missingSwiftStructs,
    fieldMismatches,
    ok: missingSwiftStructs.length === 0 && fieldMismatches.length === 0,
  };
}

export function formatReport(result: ParityResult): string {
  if (result.ok) return "✅  TS↔Swift schema parity: all fields match.\n";

  const lines: string[] = ["❌  TS↔Swift schema parity FAILED\n"];

  if (result.missingSwiftStructs.length > 0) {
    lines.push("Missing Swift structs:");
    for (const name of result.missingSwiftStructs) {
      lines.push(`  • ${name}`);
    }
    lines.push("");
  }

  if (result.fieldMismatches.length > 0) {
    lines.push("Field mismatches:");
    for (const m of result.fieldMismatches) {
      const prefix = `  ${m.structName}.${m.fieldName}`;
      switch (m.issue) {
        case "missing_in_swift":
          lines.push(`${prefix}  [missing in Swift]   TS: ${m.tsType}${m.tsOptional ? "?" : ""}`);
          break;
        case "missing_in_ts":
          lines.push(
            `${prefix}  [missing in TS]      Swift: ${m.swiftType}${m.swiftOptional ? "?" : ""}`,
          );
          break;
        case "type_mismatch":
          lines.push(
            `${prefix}  [type mismatch]      TS: ${m.tsType}  ↔  Swift: ${m.swiftType}${m.swiftOptional ? "?" : ""}`,
          );
          break;
        case "optionality_mismatch":
          lines.push(
            `${prefix}  [optionality]        TS: ${m.tsType}?  but Swift: ${m.swiftType} (non-optional)`,
          );
          break;
      }
    }
    lines.push("");
  }

  lines.push("Run `pnpm parity:check` locally to reproduce.");
  return lines.join("\n");
}
