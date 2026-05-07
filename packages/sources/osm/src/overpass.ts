import type { BBox } from "@solo-compass/sources-core";
import type { OverpassResponse } from "./types.js";

const OVERPASS_API = "https://overpass-api.de/api/interpreter";

/**
 * Builds an Overpass QL query for the given bbox and tag filters.
 * Returns nodes, ways, and relations; ways/relations get `out center` for coords.
 */
export function buildOverpassQuery(
  bbox: BBox,
  amenityTypes: readonly string[],
  tourismTypes: readonly string[],
): string {
  // Overpass bbox order: south,west,north,east (lat/lon)
  const bb = `${bbox.minLat},${bbox.minLon},${bbox.maxLat},${bbox.maxLon}`;

  const lines: string[] = ["[out:json][timeout:25];", "("];

  for (const v of amenityTypes) {
    lines.push(`  node["amenity"="${v}"](${bb});`);
    lines.push(`  way["amenity"="${v}"](${bb});`);
    lines.push(`  relation["amenity"="${v}"](${bb});`);
  }

  for (const v of tourismTypes) {
    lines.push(`  node["tourism"="${v}"](${bb});`);
    lines.push(`  way["tourism"="${v}"](${bb});`);
    lines.push(`  relation["tourism"="${v}"](${bb});`);
  }

  lines.push(");");
  lines.push("out body;");
  lines.push(">;");
  lines.push("out skel qt;");

  return lines.join("\n");
}

/** Default fetch implementation — POST to Overpass interpreter. */
export async function fetchOverpass(
  url: string,
  body: string,
): Promise<OverpassResponse> {
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "User-Agent": "SoloCompassBot/1.0 (data engine; contact: solo-compass@example.com)",
    },
    body: `data=${encodeURIComponent(body)}`,
  });

  if (!response.ok) {
    throw new Error(
      `Overpass request failed: ${response.status} ${response.statusText}`,
    );
  }

  return response.json() as Promise<OverpassResponse>;
}

export { OVERPASS_API };
