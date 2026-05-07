/**
 * Extracts struct/class field definitions from Swift source files using regex.
 * No Swift compiler required — parses `let`/`var` property declarations inside
 * `struct` and `class` blocks, without descending into nested types.
 */

import fs from "node:fs";
import path from "node:path";
import { glob } from "glob";

export interface SwiftField {
  name: string;
  type: string;
  optional: boolean;
}

export interface SwiftStruct {
  name: string;
  fields: SwiftField[];
  file: string;
}

// Matches a stored property (let/var) at the top level of a struct body.
// Group 1: name, Group 2: type (may end with ?)
const STORED_PROP_RE =
  /^[ \t]+(?:(?:public|private|internal|fileprivate)\s+)?(?:let|var)\s+(\w+)\s*:\s*([^\n{/=]+?)(?:\s*=\s*[^\n]+)?[ \t]*(?:\/\/[^\n]*)?\n/gm;

function parseSwiftType(raw: string): { type: string; optional: boolean } {
  const trimmed = raw.trim();
  if (trimmed.endsWith("?")) {
    return { type: trimmed.slice(0, -1).trim(), optional: true };
  }
  const optMatch = /^Optional<(.+)>$/.exec(trimmed);
  if (optMatch) {
    return { type: optMatch[1]!.trim(), optional: true };
  }
  return { type: trimmed, optional: false };
}

/** Find the index of the matching closing brace. `openIdx` must point at `{`. */
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

interface StructRange {
  name: string;
  bodyStart: number; // index after the opening `{`
  bodyEnd: number;   // index of the closing `}`
}

/**
 * Scan `src` for all top-level struct/class declarations and return their
 * body ranges.  Nested structs are NOT included (they are their own entries
 * but we only add them once from the outer scan).
 */
function findAllStructRanges(src: string): StructRange[] {
  const STRUCT_OPEN_RE =
    /(?:^|\n)[ \t]*(?:(?:public|private|internal|fileprivate)\s+)?(?:struct|class)\s+(\w+)[^{]*\{/g;

  const ranges: StructRange[] = [];
  let m: RegExpExecArray | null;

  while ((m = STRUCT_OPEN_RE.exec(src)) !== null) {
    const name = m[1]!;
    // The `{` is the last char of the match
    const openBraceIdx = m.index + m[0].length - 1;
    const closeBraceIdx = findClosingBrace(src, openBraceIdx);
    ranges.push({ name, bodyStart: openBraceIdx + 1, bodyEnd: closeBraceIdx });
  }

  return ranges;
}

/**
 * Given a struct body (between `{` and `}`), strip out any nested struct/class/
 * enum/extension bodies so that STORED_PROP_RE only sees the direct members.
 */
function stripNestedBodies(body: string): string {
  // Replace any nested `struct Foo { ... }` / `class Foo { ... }` / `enum Foo { ... }`
  // with just the declaration line, removing the body.
  // We iterate until no more replacements are needed (handles deeply nested).
  const NESTED_RE =
    /(?:(?:public|private|internal|fileprivate)\s+)?(?:struct|class|enum|extension)\s+\w+[^{]*\{/g;

  let result = body;
  let safety = 0;

  while (safety++ < 20) {
    NESTED_RE.lastIndex = 0;
    const m = NESTED_RE.exec(result);
    if (!m) break;

    const openIdx = m.index + m[0].length - 1;
    const closeIdx = findClosingBrace(result, openIdx);
    // Replace the entire nested block (opening keyword → closing `}`) with a placeholder
    result = result.slice(0, m.index) + "/* nested */" + result.slice(closeIdx + 1);
  }

  return result;
}

function parseDirectFields(body: string): SwiftField[] {
  const clean = stripNestedBodies(body);
  const fields: SwiftField[] = [];

  STORED_PROP_RE.lastIndex = 0;
  let m: RegExpExecArray | null;

  while ((m = STORED_PROP_RE.exec(clean)) !== null) {
    const rawName = m[1]!;
    const rawType = m[2]!.trim();

    // Skip if the "type" looks like a block expression (computed var)
    if (rawType.includes("{")) continue;

    const { type, optional } = parseSwiftType(rawType);
    fields.push({ name: rawName, type, optional });
  }

  return fields;
}

export function extractSwiftStructs(rootDir: string, swiftGlobs: string[]): SwiftStruct[] {
  const structs: SwiftStruct[] = [];

  for (const pattern of swiftGlobs) {
    const files = glob.sync(pattern, { cwd: rootDir, absolute: true });

    for (const filePath of files) {
      const src = fs.readFileSync(filePath, "utf8");
      const relFile = path.relative(rootDir, filePath);

      const ranges = findAllStructRanges(src);

      for (const range of ranges) {
        const body = src.slice(range.bodyStart, range.bodyEnd);
        const fields = parseDirectFields(body);

        if (fields.length > 0) {
          structs.push({ name: range.name, fields, file: relFile });
        }
      }
    }
  }

  return structs;
}
