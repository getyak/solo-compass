import { describe, it, expect, vi } from "vitest";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { OsmAdapter } from "./adapter.js";
import type { BBox } from "@solo-compass/sources-core";
import type { OverpassResponse } from "./types.js";
import { DEFAULT_AMENITY_TYPES, DEFAULT_TOURISM_TYPES } from "./types.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURE: OverpassResponse = JSON.parse(
  readFileSync(join(__dirname, "__fixtures__/lisbon-overpass.json"), "utf8"),
) as OverpassResponse;

const LISBON_BBOX: BBox = {
  minLon: -9.23,
  minLat: 38.69,
  maxLon: -9.09,
  maxLat: 38.73,
};

function makeFetch(response: OverpassResponse) {
  return vi.fn(async (_url: string, _body: string) => response);
}

describe("OsmAdapter — shape contract", () => {
  it("satisfies SourceAdapter contract shape", () => {
    const adapter = new OsmAdapter();
    expect(adapter.name).toBe("osm");
    expect(adapter.weight).toBeGreaterThan(0);
    expect(typeof adapter.fetch).toBe("function");
    expect(typeof adapter.healthCheck).toBe("function");
  });

  it("exposes fetchPOIs", () => {
    const adapter = new OsmAdapter();
    expect(typeof adapter.fetchPOIs).toBe("function");
  });
});

describe("OsmAdapter.fetchPOIs — fixture", () => {
  it("returns Candidate[] from recorded fixture", async () => {
    const adapter = new OsmAdapter({ fetchFn: makeFetch(FIXTURE) });
    const candidates = await adapter.fetchPOIs(LISBON_BBOX);
    expect(candidates.length).toBeGreaterThan(0);
  });

  it("excludes elements with no name tag", async () => {
    const adapter = new OsmAdapter({ fetchFn: makeFetch(FIXTURE) });
    const candidates = await adapter.fetchPOIs(LISBON_BBOX);
    for (const c of candidates) {
      expect(c.title.length).toBeGreaterThan(0);
    }
  });

  it("sets sourceName to OpenStreetMap", async () => {
    const adapter = new OsmAdapter({ fetchFn: makeFetch(FIXTURE) });
    const candidates = await adapter.fetchPOIs(LISBON_BBOX);
    for (const c of candidates) {
      expect(c.sourceName).toBe("OpenStreetMap");
    }
  });

  it("builds sourceId as osm:<type>:<id>", async () => {
    const adapter = new OsmAdapter({ fetchFn: makeFetch(FIXTURE) });
    const candidates = await adapter.fetchPOIs(LISBON_BBOX);
    for (const c of candidates) {
      expect(c.sourceId).toMatch(/^osm:(node|way|relation):\d+$/);
    }
  });

  it("generates unique sourceIds", async () => {
    const adapter = new OsmAdapter({ fetchFn: makeFetch(FIXTURE) });
    const candidates = await adapter.fetchPOIs(LISBON_BBOX);
    const ids = candidates.map((c) => c.sourceId);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("sets coordinates as [lon, lat] for node elements", async () => {
    const adapter = new OsmAdapter({ fetchFn: makeFetch(FIXTURE) });
    const candidates = await adapter.fetchPOIs(LISBON_BBOX);
    const brasileira = candidates.find((c) => c.title === "A Brasileira");
    expect(brasileira).toBeDefined();
    expect(brasileira?.coordinates?.[0]).toBeCloseTo(-9.1369, 3); // lon
    expect(brasileira?.coordinates?.[1]).toBeCloseTo(38.7108, 3); // lat
  });

  it("sets coordinates from center for way elements", async () => {
    const adapter = new OsmAdapter({ fetchFn: makeFetch(FIXTURE) });
    const candidates = await adapter.fetchPOIs(LISBON_BBOX);
    const museum = candidates.find((c) => c.title === "National Museum of Ancient Art");
    expect(museum).toBeDefined();
    expect(museum?.coordinates?.[0]).toBeCloseTo(-9.1359, 3); // lon
    expect(museum?.coordinates?.[1]).toBeCloseTo(38.7057, 3); // lat
  });

  it("sets OSM url on each candidate", async () => {
    const adapter = new OsmAdapter({ fetchFn: makeFetch(FIXTURE) });
    const candidates = await adapter.fetchPOIs(LISBON_BBOX);
    const castle = candidates.find((c) => c.title === "São Jorge Castle");
    expect(castle?.url).toBe("https://www.openstreetmap.org/node/502834712");
  });

  it("includes description, hours, and address in rawText when available", async () => {
    const adapter = new OsmAdapter({ fetchFn: makeFetch(FIXTURE) });
    const candidates = await adapter.fetchPOIs(LISBON_BBOX);
    const taberna = candidates.find((c) => c.title === "Taberna da Rua das Flores");
    expect(taberna?.rawText).toContain("petiscos");
    expect(taberna?.rawText).toContain("Hours:");
    expect(taberna?.rawText).toContain("Address:");
  });

  it("sets fetchedAt to a valid ISO timestamp", async () => {
    const adapter = new OsmAdapter({ fetchFn: makeFetch(FIXTURE) });
    const candidates = await adapter.fetchPOIs(LISBON_BBOX);
    for (const c of candidates) {
      expect(c.fetchedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    }
  });
});

describe("OsmAdapter — caching", () => {
  it("caches results — HTTP called only once for same bbox+types", async () => {
    const fetchFn = makeFetch(FIXTURE);
    const adapter = new OsmAdapter({ fetchFn });

    await adapter.fetchPOIs(LISBON_BBOX);
    await adapter.fetchPOIs(LISBON_BBOX);
    expect(fetchFn).toHaveBeenCalledTimes(1);
  });

  it("makes a new request for different bbox", async () => {
    const fetchFn = makeFetch(FIXTURE);
    const adapter = new OsmAdapter({ fetchFn });

    const otherBbox: BBox = { minLon: -9.1, minLat: 38.7, maxLon: -9.0, maxLat: 38.8 };
    await adapter.fetchPOIs(LISBON_BBOX);
    await adapter.fetchPOIs(otherBbox);
    expect(fetchFn).toHaveBeenCalledTimes(2);
  });
});

describe("OsmAdapter.fetch — SourceAdapter contract", () => {
  it("delegates to fetchPOIs when bbox is provided", async () => {
    const fetchFn = makeFetch(FIXTURE);
    const adapter = new OsmAdapter({ fetchFn });

    const candidates = await adapter.fetch({ bbox: LISBON_BBOX });
    expect(candidates.length).toBeGreaterThan(0);
  });

  it("returns [] when no bbox is provided", async () => {
    const fetchFn = makeFetch(FIXTURE);
    const adapter = new OsmAdapter({ fetchFn });

    const candidates = await adapter.fetch({ cityCode: "Lisbon" });
    expect(candidates).toEqual([]);
  });
});

describe("OsmAdapter — default types", () => {
  it("default amenity types include required values", () => {
    expect(DEFAULT_AMENITY_TYPES).toContain("cafe");
    expect(DEFAULT_AMENITY_TYPES).toContain("restaurant");
    expect(DEFAULT_AMENITY_TYPES).toContain("bar");
    expect(DEFAULT_AMENITY_TYPES).toContain("place_of_worship");
    expect(DEFAULT_AMENITY_TYPES).toContain("library");
    expect(DEFAULT_AMENITY_TYPES).toContain("bookshop");
  });

  it("default tourism types include required values", () => {
    expect(DEFAULT_TOURISM_TYPES).toContain("attraction");
    expect(DEFAULT_TOURISM_TYPES).toContain("viewpoint");
    expect(DEFAULT_TOURISM_TYPES).toContain("museum");
  });
});

describe("OsmAdapter.healthCheck", () => {
  it("returns true when fetch succeeds", async () => {
    const fetchFn = vi.fn(async () => ({ elements: [] } as OverpassResponse));
    const adapter = new OsmAdapter({ fetchFn });
    expect(await adapter.healthCheck()).toBe(true);
  });

  it("returns false when fetch throws", async () => {
    const fetchFn = vi.fn(async () => {
      throw new Error("network error");
    });
    const adapter = new OsmAdapter({ fetchFn });
    expect(await adapter.healthCheck()).toBe(false);
  });
});
