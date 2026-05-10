/**
 * SwiftData @Model ↔ TypeScript interface parity guard.
 *
 * Walks every `*.swift` file under a given glob, finds classes annotated with
 * `@Model`, extracts their stored properties, and compares them against the
 * corresponding TS interface in packages/core.
 *
 * Rules:
 *   - Only `@Model`-annotated classes are checked (plain structs/classes are
 *     the job of the existing swift-extractor + comparator pass).
 *   - Fields decorated with `@Attribute` or `@Relationship` are included.
 *   - Computed properties (those followed by `{`) are excluded.
 *   - Swift-only housekeeping fields listed in IGNORED_SWIFT_MODEL_FIELDS are
 *     skipped on the Swift side.
 *
 * Type mapping follows the same conventions as comparator.ts.
 */

import fs from "node:fs";
import path from "node:path";
import { glob } from "glob";
import type { TSStruct } from "./ts-extractor.js";

export interface SwiftDataField {
  name: string;
  type: string;
  optional: boolean;
}

export interface SwiftDataModel {
  name: string;
  fields: SwiftDataField[];
  file: string;
}

export interface SwiftDataParityMismatch {
  modelName: string;
  fieldName: string;
  tsType?: string;
  swiftType?: string;
  issue: "missing_in_swift" | "missing_in_ts" | "type_mismatch" | "optionality_mismatch";
}

export interface SwiftDataParityResult {
  missingSwiftModels: string[];
  mismatches: SwiftDataParityMismatch[];
  ok: boolean;
  report: string;
}

// ---------------------------------------------------------------------------
// Swift-only fields with no TS counterpart (framework / housekeeping)
// ---------------------------------------------------------------------------
const IGNORED_SWIFT_MODEL_FIELDS = new Set([
  // SwiftData implicit primary key
  "persistentModelID",
]);

// ---------------------------------------------------------------------------
// TS→Swift type compatibility (mirrors comparator.ts rules)
// ---------------------------------------------------------------------------
const DIRECT: Record<string, string[]> = {
  string: ["String", "URL", "Date"],
  number: ["Double", "Int", "Float"],
  boolean: ["Bool"],
};

function normaliseTSType(raw: string): string {
  let t = raw.trim();
  t = t.replace(/string\s*&\s*\{[^}]*\}/, "string");
  t = t.replace(/ReadonlyArray<(.+)>/, "$1[]");
  t = t.replace(/^readonly\s+(.+\[\])$/, "$1");
  t = t.replace(/^readonly\s+(\[.+\])$/, "$1");
  t = t.replace(/^\|\s*/, "");
  return t.trim().replace(/\s+/g, " ");
}

function normaliseSwiftType(raw: string): string {
  return raw.trim().replace(/\?$/, "");
}

function isStringLiteralUnion(t: string): boolean {
  return /^"[^"]+"(\s*\|\s*"[^"]+")+$/.test(t.trim());
}

function typesCompatible(tsType: string, swiftType: string): boolean {
  const normTS = normaliseTSType(tsType);
  const normSW = normaliseSwiftType(swiftType);

  if (isStringLiteralUnion(normTS)) {
    return /^[A-Z][A-Za-z0-9]*$/.test(normSW) || normSW === "String";
  }

  for (const [ts, swifts] of Object.entries(DIRECT)) {
    if (normTS === ts && swifts.includes(normSW)) return true;
  }

  if (normTS === normSW) return true;

  const tsArr = /^(.+)\[\]$/.exec(normTS);
  const swArr = /^\[(.+)\]$/.exec(normSW);
  if (tsArr && swArr) return typesCompatible(tsArr[1]!, swArr[1]!);

  if (normTS.startsWith("{")) return true;

  return false;
}

// ---------------------------------------------------------------------------
// @Model class extractor
// ---------------------------------------------------------------------------

// Matches stored properties inside a @Model class body.
const STORED_PROP_RE =
  /^[ \t]+(?:@Attribute[^\n]*)?\n?[ \t]*(?:(?:public|private|internal|fileprivate)\s+)?(?:let|var)\s+(\w+)\s*:\s*([^\n{/=]+?)(?:\s*=\s*[^\n]+)?[ \t]*(?:\/\/[^\n]*)?\n/gm;

function parseSwiftType(raw: string): { type: string; optional: boolean } {
  const trimmed = raw.trim();
  if (trimmed.endsWith("?")) return { type: trimmed.slice(0, -1).trim(), optional: true };
  const m = /^Optional<(.+)>$/.exec(trimmed);
  if (m) return { type: m[1]!.trim(), optional: true };
  return { type: trimmed, optional: false };
}

function findClosingBrace(src: string, openIdx: number): number {
  let depth = 0;
  for (let i = openIdx; i < src.length; i++) {
    if (src[i] === "{") depth++;
    else if (src[i] === "}") {
      depth--;
      if (depth === 0) return i;
    }
  }
  return src.length - 1;
}

export function extractSwiftDataModels(rootDir: string, swiftGlobs: string[]): SwiftDataModel[] {
  const models: SwiftDataModel[] = [];

  for (const pattern of swiftGlobs) {
    const files = glob.sync(pattern, { cwd: rootDir, absolute: true });

    for (const filePath of files) {
      const src = fs.readFileSync(filePath, "utf8");
      const relFile = path.relative(rootDir, filePath);

      // Find all @Model-annotated class declarations
      const MODEL_RE =
        /@Model\s+(?:(?:public|private|internal|fileprivate)\s+)?final\s+class\s+(\w+)[^{]*\{/g;
      let m: RegExpExecArray | null;

      while ((m = MODEL_RE.exec(src)) !== null) {
        const name = m[1]!;
        const openBraceIdx = m.index + m[0].length - 1;
        const closeBraceIdx = findClosingBrace(src, openBraceIdx);
        const body = src.slice(openBraceIdx + 1, closeBraceIdx);

        // Strip nested struct/class/enum/init/func bodies so regex only sees stored props
        let clean = body;
        const NESTED_RE =
          /(?:(?:public|private|internal|fileprivate)\s+)?(?:struct|class|enum|extension|func|init)\s*[\w(][^{]*\{/g;
        let safety = 0;
        while (safety++ < 20) {
          NESTED_RE.lastIndex = 0;
          const nm = NESTED_RE.exec(clean);
          if (!nm) break;
          const oi = nm.index + nm[0].length - 1;
          const ci = findClosingBrace(clean, oi);
          clean = clean.slice(0, nm.index) + "/* nested */" + clean.slice(ci + 1);
        }

        // Strip @Attribute(...) wrappers so inline attributes like
        // "@Attribute(.unique) public var cityCode: String" are parsed correctly
        clean = clean.replace(/@Attribute\([^)]*\) /g, "");

        const fields: SwiftDataField[] = [];
        STORED_PROP_RE.lastIndex = 0;
        let fm: RegExpExecArray | null;
        while ((fm = STORED_PROP_RE.exec(clean + "\n")) !== null) {
          const rawName = fm[1]!;
          const rawType = fm[2]!.trim();
          if (rawType.includes("{")) continue;
          if (IGNORED_SWIFT_MODEL_FIELDS.has(rawName)) continue;
          const { type, optional } = parseSwiftType(rawType);
          fields.push({ name: rawName, type, optional });
        }

        if (fields.length > 0) {
          models.push({ name, fields, file: relFile });
        }
      }
    }
  }

  return models;
}

// ---------------------------------------------------------------------------
// TS interface name → expected @Model class name
// ---------------------------------------------------------------------------
const TS_TO_MODEL_NAME: Record<string, string> = {
  DiscoveredCity: "DiscoveredCityRecord",
};

// ---------------------------------------------------------------------------
// Comparator
// ---------------------------------------------------------------------------

export function checkSwiftDataParity(
  tsStructs: TSStruct[],
  swiftModels: SwiftDataModel[],
  watchedNames: Set<string>,
): SwiftDataParityResult {
  const modelByName = new Map(swiftModels.map((m) => [m.name, m]));
  const tsByName = new Map(tsStructs.map((s) => [s.name, s]));

  const missingSwiftModels: string[] = [];
  const mismatches: SwiftDataParityMismatch[] = [];

  for (const tsName of watchedNames) {
    const ts = tsByName.get(tsName);
    if (!ts) continue;

    const modelName = TS_TO_MODEL_NAME[tsName] ?? tsName;
    const model = modelByName.get(modelName);

    if (!model) {
      missingSwiftModels.push(`${tsName} (expected @Model class: ${modelName})`);
      continue;
    }

    const swiftFieldMap = new Map(model.fields.map((f) => [f.name, f]));
    const tsFieldMap = new Map(ts.fields.map((f) => [f.name, f]));

    // TS → Swift
    for (const tsField of ts.fields) {
      const swField = swiftFieldMap.get(tsField.name);
      if (!swField) {
        mismatches.push({
          modelName: modelName,
          fieldName: tsField.name,
          tsType: tsField.type,
          issue: "missing_in_swift",
        });
        continue;
      }
      if (!typesCompatible(tsField.type, swField.type)) {
        mismatches.push({
          modelName: modelName,
          fieldName: tsField.name,
          tsType: tsField.type,
          swiftType: swField.type,
          issue: "type_mismatch",
        });
        continue;
      }
      if (tsField.optional && !swField.optional) {
        mismatches.push({
          modelName: modelName,
          fieldName: tsField.name,
          tsType: tsField.type,
          swiftType: swField.type,
          issue: "optionality_mismatch",
        });
      }
    }

    // Swift → TS: extra fields in @Model are suspicious
    for (const swField of model.fields) {
      if (IGNORED_SWIFT_MODEL_FIELDS.has(swField.name)) continue;
      if (!tsFieldMap.has(swField.name)) {
        mismatches.push({
          modelName: modelName,
          fieldName: swField.name,
          swiftType: swField.type,
          issue: "missing_in_ts",
        });
      }
    }
  }

  const ok = missingSwiftModels.length === 0 && mismatches.length === 0;

  let report: string;
  if (ok) {
    report = "✅  TS↔SwiftData @Model parity: all fields match.\n";
  } else {
    const lines: string[] = ["❌  TS↔SwiftData @Model parity FAILED\n"];
    if (missingSwiftModels.length > 0) {
      lines.push("Missing @Model classes:");
      for (const n of missingSwiftModels) lines.push(`  • ${n}`);
      lines.push("");
    }
    if (mismatches.length > 0) {
      lines.push("Field mismatches:");
      for (const mm of mismatches) {
        const prefix = `  ${mm.modelName}.${mm.fieldName}`;
        switch (mm.issue) {
          case "missing_in_swift":
            lines.push(`${prefix}  [missing in @Model]   TS: ${mm.tsType}`);
            break;
          case "missing_in_ts":
            lines.push(`${prefix}  [missing in TS]       Swift: ${mm.swiftType}`);
            break;
          case "type_mismatch":
            lines.push(
              `${prefix}  [type mismatch]       TS: ${mm.tsType}  ↔  Swift: ${mm.swiftType}`,
            );
            break;
          case "optionality_mismatch":
            lines.push(
              `${prefix}  [optionality]         TS: ${mm.tsType}?  but Swift: ${mm.swiftType} (non-optional)`,
            );
            break;
        }
      }
      lines.push("");
    }
    lines.push("Run `pnpm parity:check` locally to reproduce.");
    report = lines.join("\n");
  }

  return { missingSwiftModels, mismatches, ok, report };
}
