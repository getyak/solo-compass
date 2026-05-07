import NodeCache from "node-cache";
import type { SourceAdapter, SourceQuery, Candidate, BBox } from "@solo-compass/sources-core";
import { RateLimiter } from "./rate-limiter.js";
import { buildOverpassQuery, fetchOverpass, OVERPASS_API } from "./overpass.js";
import {
  DEFAULT_AMENITY_TYPES,
  DEFAULT_TOURISM_TYPES,
  type OsmAdapterOptions,
  type OverpassElement,
  type OverpassResponse,
} from "./types.js";

const CACHE_TTL_SECONDS = 24 * 60 * 60; // 24 h

export class OsmAdapter implements SourceAdapter {
  readonly name = "osm";
  readonly weight = 0.7;

  private readonly overpassUrl: string;
  private readonly amenityTypes: readonly string[];
  private readonly tourismTypes: readonly string[];
  private readonly limiter: RateLimiter;
  private readonly cache: NodeCache;
  private readonly fetchFn: (url: string, body: string) => Promise<OverpassResponse>;

  constructor(options: OsmAdapterOptions = {}) {
    this.overpassUrl = options.overpassUrl ?? OVERPASS_API;
    this.amenityTypes = options.amenityTypes ?? DEFAULT_AMENITY_TYPES;
    this.tourismTypes = options.tourismTypes ?? DEFAULT_TOURISM_TYPES;
    this.limiter = new RateLimiter(1); // max 1 req/sec
    this.cache = new NodeCache({
      stdTTL: options.cacheTtlSeconds ?? CACHE_TTL_SECONDS,
      useClones: false,
    });
    this.fetchFn = options.fetchFn ?? fetchOverpass;
  }

  /**
   * Fetch POI candidates for a bounding box.
   * Results are cached 24 h; rate-limited to ≤1 req/sec.
   */
  async fetchPOIs(
    bbox: BBox,
    amenityTypes: readonly string[] = this.amenityTypes,
    tourismTypes: readonly string[] = this.tourismTypes,
  ): Promise<Candidate[]> {
    const cacheKey = bboxCacheKey(bbox, amenityTypes, tourismTypes);
    const cached = this.cache.get<Candidate[]>(cacheKey);
    if (cached !== undefined) return cached;

    const query = buildOverpassQuery(bbox, amenityTypes, tourismTypes);
    await this.limiter.acquire();
    const response = await this.fetchFn(this.overpassUrl, query);

    const candidates = elementsToCandidates(response.elements);
    this.cache.set(cacheKey, candidates);
    return candidates;
  }

  /** SourceAdapter contract. Requires `query.bbox`. */
  async fetch(query: SourceQuery): Promise<Candidate[]> {
    if (!query.bbox) return [];
    return this.fetchPOIs(query.bbox);
  }

  async healthCheck(): Promise<boolean> {
    try {
      // Minimal query: one node in a 0-size bbox at (0,0)
      const testQuery = "[out:json][timeout:5];\nnode(0,0,0,0);\nout;";
      await this.limiter.acquire();
      await this.fetchFn(this.overpassUrl, testQuery);
      return true;
    } catch {
      return false;
    }
  }
}

function bboxCacheKey(
  bbox: BBox,
  amenityTypes: readonly string[],
  tourismTypes: readonly string[],
): string {
  return [
    bbox.minLon,
    bbox.minLat,
    bbox.maxLon,
    bbox.maxLat,
    amenityTypes.join(","),
    tourismTypes.join(","),
  ].join("|");
}

function elementCoords(
  el: OverpassElement,
): readonly [number, number] | undefined {
  if (el.lat !== undefined && el.lon !== undefined) {
    return [el.lon, el.lat]; // GeoJSON: [longitude, latitude]
  }
  if (el.center !== undefined) {
    return [el.center.lon, el.center.lat];
  }
  return undefined;
}

function elementTitle(tags: Record<string, string>): string {
  return tags["name"] ?? tags["name:en"] ?? tags["ref"] ?? "";
}

function elementDescription(tags: Record<string, string>): string {
  const parts: string[] = [];
  const category =
    tags["amenity"] ?? tags["tourism"] ?? tags["leisure"] ?? tags["shop"];
  if (category) parts.push(`Type: ${category}`);
  if (tags["description"]) parts.push(tags["description"]);
  if (tags["opening_hours"]) parts.push(`Hours: ${tags["opening_hours"]}`);
  if (tags["website"]) parts.push(`Website: ${tags["website"]}`);
  if (tags["phone"]) parts.push(`Phone: ${tags["phone"]}`);
  if (tags["addr:street"]) {
    const addr = [
      tags["addr:housenumber"],
      tags["addr:street"],
      tags["addr:city"],
    ]
      .filter(Boolean)
      .join(" ");
    parts.push(`Address: ${addr}`);
  }
  return parts.join("\n");
}

function elementsToCandidates(
  elements: readonly OverpassElement[],
): Candidate[] {
  const fetchedAt = new Date().toISOString();

  return elements
    .filter((el) => {
      const tags = el.tags ?? {};
      const title = elementTitle(tags);
      return title.length > 0;
    })
    .map((el): Candidate => {
      const tags = el.tags ?? {};
      const title = elementTitle(tags);
      const description = elementDescription(tags);
      const coords = elementCoords(el);
      const osmUrl = `https://www.openstreetmap.org/${el.type}/${el.id}`;

      return {
        sourceId: `osm:${el.type}:${el.id}`,
        sourceName: "OpenStreetMap",
        title,
        rawText: description,
        url: osmUrl,
        coordinates: coords,
        fetchedAt,
      };
    });
}
