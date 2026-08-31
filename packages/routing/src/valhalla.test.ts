import { describe, expect, it, vi } from "vitest";
import { ValhallaMatrixClient } from "./valhalla";

describe("ValhallaMatrixClient", () => {
  it("converts GeoJSON coordinates to Valhalla lat/lon and parses concise matrices", async () => {
    const fetchMock = vi.fn(async (_url: string | URL | Request, init?: RequestInit) => {
      const request = JSON.parse(String(init?.body)) as {
        sources: Array<{ lat: number; lon: number }>;
        verbose: boolean;
      };
      expect(request.sources).toEqual([
        { lat: 18.7883, lon: 98.9932 },
        { lat: 18.79, lon: 98.995 },
      ]);
      expect(request.verbose).toBe(false);
      return new Response(
        JSON.stringify({
          sources_to_targets: {
            durations: [
              [0, 180],
              [240, 0],
            ],
            distances: [
              [0, 0.8],
              [0.9, 0],
            ],
          },
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    });
    const client = new ValhallaMatrixClient({
      endpoint: "http://valhalla.test/",
      fetch: fetchMock as typeof fetch,
    });
    const result = await client.buildMatrix(
      [
        { id: "a", coordinates: [98.9932, 18.7883] },
        { id: "b", coordinates: [98.995, 18.79] },
      ],
      "pedestrian",
    );
    expect(result.cells["a"]?.["b"]).toEqual({ durationMinutes: 3, distanceMeters: 800 });
    expect(result.cells["b"]?.["a"]).toEqual({ durationMinutes: 4, distanceMeters: 900 });
  });

  it("preserves unreachable pairs as null instead of estimating them", async () => {
    const client = new ValhallaMatrixClient({
      endpoint: "http://valhalla.test",
      fetch: (async () =>
        new Response(
          JSON.stringify({
            sources_to_targets: {
              durations: [
                [0, null],
                [null, 0],
              ],
              distances: [
                [0, null],
                [null, 0],
              ],
            },
          }),
        )) as typeof fetch,
    });
    const result = await client.buildMatrix(
      [
        { id: "a", coordinates: [0, 0] },
        { id: "b", coordinates: [1, 1] },
      ],
      "pedestrian",
    );
    expect(result.cells["a"]?.["b"]?.durationMinutes).toBeNull();
  });
});
