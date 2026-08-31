import { describe, expect, it, vi } from "vitest";
import { FEATURE_KEYS } from "@solo-compass/data";
import type {
  ExperiencePlaceLinkRow,
  PlaceObservationRow,
  PlaceRow,
  RefreshJobRow,
  ResolvedPlaceFeature,
  SourceArtifactRow,
} from "@solo-compass/data";
import type { SourceAdapter } from "@solo-compass/sources-core";
import { RefreshWorker, type RefreshWorkerDependencies } from "./processor";

const NOW = "2026-08-31T12:00:00.000Z";
const PLACE_ID = "11111111-1111-4111-8111-111111111111";

function job(): RefreshJobRow {
  return {
    id: "job-1",
    place_id: null,
    feature_keys: [],
    query: {
      center: [98.9853, 18.7883],
      radiusMeters: 500,
      experienceAnchors: [
        {
          experienceId: "exp_osm_123",
          placeName: "Graph Cafe",
          coordinates: [98.9853, 18.7883],
        },
      ],
    },
    reason: "coverage_gap",
    urgency: "background",
    priority: 100,
    provider_hint: null,
    budget_class: "coverage_backfill",
    idempotency_key: "key",
    status: "running",
    demand_score: 1,
    decision_impact: 1,
    uncertainty: 1,
    staleness: 1,
    estimated_cost: 0.5,
    not_before: NOW,
    claimed_by: "worker",
    claimed_at: NOW,
    lease_expires_at: "2026-08-31T12:03:00.000Z",
    attempts: 1,
    max_attempts: 5,
    last_error: null,
    result: null,
    created_at: NOW,
    updated_at: NOW,
    completed_at: null,
  };
}

function dependencies(
  adapter: SourceAdapter,
  claimedJob: RefreshJobRow = job(),
): {
  readonly value: RefreshWorkerDependencies;
  readonly succeed: ReturnType<typeof vi.fn>;
  readonly fail: ReturnType<typeof vi.fn>;
  readonly appended: unknown[];
  readonly links: unknown[];
} {
  const appended: unknown[] = [];
  const links: unknown[] = [];
  const place: PlaceRow = {
    id: PLACE_ID,
    canonical_name: "Graph Cafe",
    basic_category: "cafe",
    location: { type: "Point", coordinates: [98.9853, 18.7883] },
    operating_status: "unknown",
    identity_confidence: 0.8,
    created_at: NOW,
    updated_at: NOW,
  };
  const artifact: SourceArtifactRow = {
    id: "artifact",
    provider: "osm",
    external_ref: "osm:node:123",
    source_url: null,
    content_hash: "hash",
    license_code: "ODbL-1.0",
    retention_policy: "cacheable_content",
    raw_storage_key: null,
    retrieved_at: NOW,
    source_observed_at: NOW,
    expires_at: null,
    metadata: null,
    created_at: NOW,
  };
  const succeed = vi.fn(async () => job());
  const fail = vi.fn(async () => job());
  const value: RefreshWorkerDependencies = {
    queue: {
      claim: vi.fn(async () => [claimedJob]),
      succeed,
      fail,
    },
    evidence: {
      upsertPlaceIdentity: vi.fn(async () => place),
      attachExternalRef: vi.fn(async () => undefined),
      registerSourceArtifact: vi.fn(async () => artifact),
      appendObservation: vi.fn(async (input): Promise<PlaceObservationRow> => {
        appended.push(input);
        return {
          id: `obs-${appended.length}`,
          place_id: input.placeId,
          artifact_id: input.artifactId ?? null,
          feature_key: input.featureKey,
          state: input.state,
          value: input.value ?? null,
          confidence: input.confidence,
          source_weight: input.sourceWeight,
          independence_key: input.independenceKey,
          time_scope: input.timeScope ?? null,
          observed_at: input.observedAt,
          expires_at: input.expiresAt ?? null,
          extractor_version: input.extractorVersion,
          dedupe_key: input.dedupeKey,
          created_at: NOW,
        };
      }),
      materializeFeature: vi.fn(
        async (_placeId, featureKey): Promise<ResolvedPlaceFeature> => ({
          placeId: PLACE_ID,
          featureKey,
          value: true,
          status: "resolved",
          confidence: 0.8,
          supportingObservationIds: ["obs"],
          conflictingObservationIds: [],
          resolverVersion: "test",
          resolutionFingerprint: "test",
          resolvedAt: NOW,
        }),
      ),
      linkExperience: vi.fn(async (input): Promise<ExperiencePlaceLinkRow> => {
        links.push(input);
        return { ...input, linked_at: NOW };
      }),
    },
    adapters: [adapter],
  };
  return { value, succeed, fail, appended, links };
}

describe("RefreshWorker", () => {
  it("ingests hard signals, materializes them, and links an existing Experience", async () => {
    const adapter: SourceAdapter = {
      name: "osm",
      weight: 0.8,
      healthCheck: async () => true,
      fetch: async () => [
        {
          sourceId: "osm:node:123",
          sourceName: "OpenStreetMap",
          title: "Graph Cafe",
          rawText: "Type: cafe\nHours: Mo-Fr 08:00-18:00",
          coordinates: [98.9853, 18.7883],
          fetchedAt: NOW,
        },
      ],
    };
    const deps = dependencies(adapter);
    const result = await new RefreshWorker(deps.value).runBatch("worker", 1);

    expect(result).toEqual({ claimed: 1, succeeded: 1, failed: 0 });
    expect(deps.appended).toHaveLength(4);
    expect(deps.appended).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          featureKey: FEATURE_KEYS.regularOpeningHours,
          value: expect.objectContaining({ kind: "weekly" }),
        }),
      ]),
    );
    expect(deps.links).toEqual([
      expect.objectContaining({ experienceId: "exp_osm_123", placeId: PLACE_ID }),
    ]);
    expect(deps.succeed).toHaveBeenCalledWith(
      "job-1",
      "worker",
      expect.objectContaining({ observations: 4, materialized: 4, experienceLinks: 1 }),
    );
    expect(deps.fail).not.toHaveBeenCalled();
  });

  it("returns a leased job to retry when every adapter fails", async () => {
    const adapter: SourceAdapter = {
      name: "osm",
      weight: 0.8,
      healthCheck: async () => false,
      fetch: async () => {
        throw new Error("overpass unavailable");
      },
    };
    const deps = dependencies(adapter);
    const result = await new RefreshWorker(deps.value).runBatch("worker", 1);

    expect(result).toEqual({ claimed: 1, succeeded: 0, failed: 1 });
    expect(deps.fail).toHaveBeenCalledWith("job-1", "worker", expect.any(Error));
    expect(deps.succeed).not.toHaveBeenCalled();
  });

  it("does not spend an OSM request on unsupported workability features", async () => {
    const fetch = vi.fn(async () => []);
    const adapter: SourceAdapter = {
      name: "osm",
      weight: 0.8,
      healthCheck: async () => true,
      fetch,
    };
    const unsupported: RefreshJobRow = {
      ...job(),
      place_id: PLACE_ID,
      feature_keys: [FEATURE_KEYS.wifiReliability],
    };
    const deps = dependencies(adapter, unsupported);
    const result = await new RefreshWorker(deps.value).runBatch("worker", 1);

    expect(result).toEqual({ claimed: 1, succeeded: 0, failed: 1 });
    expect(fetch).not.toHaveBeenCalled();
    expect(deps.fail).toHaveBeenCalledWith("job-1", "worker", expect.any(Error));
  });
});
