import { describe, it, expect } from "vitest";
import { buildOverpassQuery } from "./overpass.js";
import type { BBox } from "@solo-compass/sources-core";

const BBOX: BBox = {
  minLon: -9.23,
  minLat: 38.69,
  maxLon: -9.09,
  maxLat: 38.73,
};

describe("buildOverpassQuery", () => {
  it("includes bbox in south,west,north,east order (lat/lon)", () => {
    const q = buildOverpassQuery(BBOX, ["cafe"], []);
    // Overpass bbox: minLat,minLon,maxLat,maxLon
    expect(q).toContain("38.69,-9.23,38.73,-9.09");
  });

  it("emits node/way/relation filters for each amenity type", () => {
    const q = buildOverpassQuery(BBOX, ["cafe", "restaurant"], []);
    expect(q).toContain('node["amenity"="cafe"]');
    expect(q).toContain('way["amenity"="cafe"]');
    expect(q).toContain('relation["amenity"="cafe"]');
    expect(q).toContain('node["amenity"="restaurant"]');
  });

  it("emits node/way/relation filters for each tourism type", () => {
    const q = buildOverpassQuery(BBOX, [], ["museum", "viewpoint"]);
    expect(q).toContain('node["tourism"="museum"]');
    expect(q).toContain('way["tourism"="museum"]');
    expect(q).toContain('relation["tourism"="museum"]');
    expect(q).toContain('node["tourism"="viewpoint"]');
  });

  it("requests json output", () => {
    const q = buildOverpassQuery(BBOX, [], []);
    expect(q).toContain("[out:json]");
  });

  it("handles empty type arrays without error", () => {
    const q = buildOverpassQuery(BBOX, [], []);
    expect(typeof q).toBe("string");
    expect(q.length).toBeGreaterThan(0);
  });
});
