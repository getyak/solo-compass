/**
 * Extracts struct/interface field definitions from TypeScript source files.
 * Uses ts-morph for AST-level accuracy — no regex hacks on TS syntax.
 */

import {
  Project,
  SyntaxKind,
  type InterfaceDeclaration,
  type TypeAliasDeclaration,
} from "ts-morph";
import path from "node:path";

export interface TSField {
  name: string;
  type: string;
  optional: boolean;
  readonly: boolean;
}

export interface TSStruct {
  name: string;
  fields: TSField[];
  /** Which file it came from (relative path) */
  file: string;
}

function resolveType(typeText: string): string {
  // Normalize whitespace and strip readonly array wrappers
  return typeText.replace(/\s+/g, " ").trim();
}

function extractFromInterface(decl: InterfaceDeclaration, file: string): TSStruct {
  const fields: TSField[] = [];

  for (const prop of decl.getProperties()) {
    const name = prop.getName();
    const optional = prop.hasQuestionToken();
    const readonly = prop.isReadonly();
    const type = resolveType(prop.getTypeNode()?.getText() ?? prop.getType().getText());
    fields.push({ name, type, optional, readonly });
  }

  return { name: decl.getName(), fields, file };
}

export function extractTSStructs(rootDir: string, globs: string[]): TSStruct[] {
  const project = new Project({
    tsConfigFilePath: path.join(rootDir, "packages/core/tsconfig.json"),
    skipAddingFilesFromTsConfig: true,
    addFilesFromTsConfig: false,
  });

  for (const glob of globs) {
    project.addSourceFilesAtPaths(path.join(rootDir, glob));
  }

  // Add referenced files so types resolve correctly
  project.resolveSourceFileDependencies();

  const structs: TSStruct[] = [];

  for (const sourceFile of project.getSourceFiles()) {
    const relFile = path.relative(rootDir, sourceFile.getFilePath());

    // Interfaces
    for (const decl of sourceFile.getInterfaces()) {
      structs.push(extractFromInterface(decl, relFile));
    }

    // Type aliases that are object types (not unions/primitives)
    for (const decl of sourceFile.getTypeAliases()) {
      const typeNode = decl.getTypeNode();
      if (!typeNode) continue;
      if (typeNode.getKind() === SyntaxKind.TypeLiteral) {
        // Inline object type — treat like an interface
        const fields: TSField[] = [];
        for (const member of typeNode.getChildrenOfKind(SyntaxKind.PropertySignature)) {
          const name = member.getName();
          const optional = member.hasQuestionToken();
          const readonly = member.isReadonly();
          const type = resolveType(member.getTypeNode()?.getText() ?? "unknown");
          fields.push({ name, type, optional, readonly });
        }
        structs.push({ name: decl.getName(), fields, file: relFile });
      }
    }
  }

  return structs;
}

/** Return only the structs that are part of the Experience schema (not utility types). */
export const SCHEMA_INTERFACES = new Set([
  "Experience",
  "ExperienceLocation",
  "TimeWindow",
  "HowToStep",
  "RealInconvenience",
  "InformationSource",
  "SoloScore",
  "Confidence",
  "Itinerary",
  "CompanionPost",
  "CompanionRequest",
  "CompanionProfile",
  "Conversation",
  "ChatMessage",
  "CompanionReport",
  "Route",
  "RouteVerification",
]);

/**
 * TS interfaces that mirror SwiftData @Model classes in Persistence/Models/.
 * These are checked by the SwiftData parity pass (not the struct pass above).
 */
export const SWIFTDATA_MODEL_INTERFACES = new Set(["DiscoveredCity"]);
