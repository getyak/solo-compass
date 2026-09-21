import { describe, expect, it } from "vitest";
import { matchCandidateToExperience, type ExperienceAnchor } from "./entity-resolution";

const anchors: ExperienceAnchor[] = [
  {
    experienceId: "exp_osm_123",
    placeName: "Graph Cafe",
    coordinates: [98.9853, 18.7883],
  },
  {
    experienceId: "exp_cmi_library_focus",
    placeName: "Chiang Mai City Library",
    coordinates: [98.986, 18.789],
  },
];

describe("matchCandidateToExperience", () => {
  it("uses a provider id bridge before fuzzy matching", () => {
    expect(
      matchCandidateToExperience(
        { sourceId: "osm:node:123", title: "Renamed Cafe", coordinates: [0, 0] },
        anchors,
      ),
    ).toEqual({ experienceId: "exp_osm_123", confidence: 0.99, method: "external_id" });
  });

  it("links a nearby normalized name", () => {
    expect(
      matchCandidateToExperience(
        {
          sourceId: "google_places:abc",
          title: "Chiang Mai City Library (Main)",
          coordinates: [98.9861, 18.7891],
        },
        anchors,
      )?.experienceId,
    ).toBe("exp_cmi_library_focus");
  });

  it("refuses a far-away name collision", () => {
    expect(
      matchCandidateToExperience(
        { sourceId: "google_places:far", title: "Graph Cafe", coordinates: [100, 20] },
        anchors,
      ),
    ).toBeNull();
  });

  it("refuses an ambiguous pair instead of guessing", () => {
    const ambiguous: ExperienceAnchor[] = [
      { experienceId: "a", placeName: "Blue Cafe", coordinates: [98, 18] },
      { experienceId: "b", placeName: "Blue Cafe", coordinates: [98.00001, 18.00001] },
    ];
    expect(
      matchCandidateToExperience(
        { sourceId: "web:x", title: "Blue Cafe", coordinates: [98, 18] },
        ambiguous,
      ),
    ).toBeNull();
  });
});
