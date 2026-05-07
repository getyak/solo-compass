/** OSM amenity types fetched by default. */
export const DEFAULT_AMENITY_TYPES = [
  "cafe",
  "restaurant",
  "bar",
  "place_of_worship",
  "library",
  "bookshop",
] as const;

/** OSM tourism types fetched by default. */
export const DEFAULT_TOURISM_TYPES = [
  "attraction",
  "viewpoint",
  "museum",
] as const;

export type AmenityType = (typeof DEFAULT_AMENITY_TYPES)[number];
export type TourismType = (typeof DEFAULT_TOURISM_TYPES)[number];

/** Overpass API element for a node, way, or relation. */
export interface OverpassElement {
  readonly type: "node" | "way" | "relation";
  readonly id: number;
  readonly lat?: number;
  readonly lon?: number;
  readonly center?: { readonly lat: number; readonly lon: number };
  readonly tags?: Record<string, string>;
}

/** Raw Overpass API response envelope. */
export interface OverpassResponse {
  readonly version?: number;
  readonly generator?: string;
  readonly elements: readonly OverpassElement[];
}

/** Options accepted by OsmAdapter. */
export interface OsmAdapterOptions {
  /** Override the Overpass API endpoint (useful for tests). */
  overpassUrl?: string;
  /** Amenity values to fetch. Defaults to DEFAULT_AMENITY_TYPES. */
  amenityTypes?: readonly string[];
  /** Tourism values to fetch. Defaults to DEFAULT_TOURISM_TYPES. */
  tourismTypes?: readonly string[];
  /** Cache TTL in seconds. Default: 86400 (24 h). */
  cacheTtlSeconds?: number;
  /** Inject a custom fetch function for testing. */
  fetchFn?: (url: string, body: string) => Promise<OverpassResponse>;
}
