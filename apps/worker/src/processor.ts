import { createHash } from "node:crypto";
import {
  EvidenceRepo,
  FEATURE_KEYS,
  matchCandidateToExperience,
  parseSimpleOpeningHours,
  RefreshQueueRepo,
  type AppendObservationInput,
  type ExperienceAnchor,
  type FeatureKey,
  type JsonValue,
  type RefreshJobRow,
} from "@solo-compass/data";
import type { BBox, Candidate, SourceAdapter, SourceQuery } from "@solo-compass/sources-core";

interface EvidenceWriter {
  upsertPlaceIdentity: EvidenceRepo["upsertPlaceIdentity"];
  attachExternalRef: EvidenceRepo["attachExternalRef"];
  registerSourceArtifact: EvidenceRepo["registerSourceArtifact"];
  appendObservation: EvidenceRepo["appendObservation"];
  materializeFeature: EvidenceRepo["materializeFeature"];
  linkExperience: EvidenceRepo["linkExperience"];
}

interface RefreshQueue {
  claim: RefreshQueueRepo["claim"];
  succeed: RefreshQueueRepo["succeed"];
  fail: RefreshQueueRepo["fail"];
}

export interface RefreshWorkerDependencies {
  readonly evidence: EvidenceWriter;
  readonly queue: RefreshQueue;
  readonly adapters: readonly SourceAdapter[];
}

export interface RefreshBatchResult {
  readonly claimed: number;
  readonly succeeded: number;
  readonly failed: number;
}

export class RefreshWorker {
  constructor(private readonly dependencies: RefreshWorkerDependencies) {}

  async runBatch(workerId: string, batchSize = 10): Promise<RefreshBatchResult> {
    const jobs = await this.dependencies.queue.claim(workerId, batchSize, 180);
    let succeeded = 0;
    let failed = 0;
    for (const job of jobs) {
      try {
        const result = await this.processJob(job);
        await this.dependencies.queue.succeed(job.id, workerId, result);
        succeeded += 1;
      } catch (error) {
        await this.dependencies.queue.fail(job.id, workerId, error);
        failed += 1;
      }
    }
    return { claimed: jobs.length, succeeded, failed };
  }

  private async processJob(job: RefreshJobRow): Promise<JsonValue> {
    const context = parseQuery(job.query);
    const query = sourceQuery(context.center, context.radiusMeters);
    const adapters = this.adaptersFor(job);
    if (adapters.length === 0) throw new Error("no policy-eligible source adapter is configured");
    const fetched = await fetchCandidates(adapters, query);
    if (fetched.length === 0) throw new Error("source adapters returned no candidates");

    let selected = fetched;
    if (job.place_id) {
      const anchor = context.placeAnchor;
      if (!anchor) throw new Error("place refresh job requires a placeName and coordinates query");
      selected = fetched.filter(
        ({ candidate }) => matchCandidateToExperience(candidate, [anchor]) !== null,
      );
      if (selected.length === 0)
        throw new Error("no source candidate safely matched the requested place");
    }

    let observations = 0;
    let materialized = 0;
    let links = 0;
    const resolvedKeys = new Set<FeatureKey>();
    for (const item of selected.slice(0, 100)) {
      const result = await this.ingestCandidate(item, job.place_id ?? undefined, context.anchors);
      observations += result.observations;
      materialized += result.materialized;
      links += result.links;
      result.featureKeys.forEach((key) => resolvedKeys.add(key));
    }
    const unresolved = job.feature_keys.filter((key) => !resolvedKeys.has(key));
    return {
      candidateCount: fetched.length,
      selectedCount: selected.length,
      observations,
      materialized,
      experienceLinks: links,
      unresolvedFeatureKeys: unresolved,
    };
  }

  private adaptersFor(job: RefreshJobRow): readonly SourceAdapter[] {
    return this.dependencies.adapters.filter((adapter) => {
      if (job.provider_hint && adapter.name !== job.provider_hint) return false;
      // Restricted commercial Places content is intentionally not consumed by
      // this durable ledger. It belongs in a separate ephemeral verifier.
      if (adapter.name === "google_places") return false;
      return adapterCanAddress(adapter.name, job.feature_keys);
    });
  }

  private async ingestCandidate(
    item: FetchedCandidate,
    existingPlaceId: string | undefined,
    anchors: readonly ExperienceAnchor[],
  ): Promise<{
    observations: number;
    materialized: number;
    links: number;
    featureKeys: readonly FeatureKey[];
  }> {
    const { candidate, sourceWeight } = item;
    const coordinates = candidate.coordinates;
    if (!coordinates || (coordinates[0] === 0 && coordinates[1] === 0)) {
      return { observations: 0, materialized: 0, links: 0, featureKeys: [] };
    }
    const identity = splitSourceId(candidate.sourceId);
    const category = lineValue(candidate.rawText, "Type");
    const place = existingPlaceId
      ? { id: existingPlaceId }
      : await this.dependencies.evidence.upsertPlaceIdentity({
          provider: identity.provider,
          externalId: identity.externalId,
          canonicalName: candidate.title,
          coordinates,
          basicCategory: category,
          identityConfidence: 0.8,
        });
    if (existingPlaceId) {
      await this.dependencies.evidence.attachExternalRef({
        placeId: existingPlaceId,
        provider: identity.provider,
        externalId: identity.externalId,
        seenAt: candidate.fetchedAt,
      });
    }

    const policy = sourcePolicy(identity.provider);
    const artifact = await this.dependencies.evidence.registerSourceArtifact({
      provider: identity.provider,
      externalRef: candidate.sourceId,
      sourceUrl: candidate.url,
      contentHash: sha256(
        [candidate.sourceId, candidate.title, candidate.rawText, candidate.fetchedAt].join("\n"),
      ),
      licenseCode: policy.licenseCode,
      retentionPolicy: policy.retentionPolicy,
      retrievedAt: candidate.fetchedAt,
      sourceObservedAt: candidate.fetchedAt,
      metadata: { sourceName: candidate.sourceName },
    });

    const extracted = hardSignalObservations({
      placeId: place.id,
      artifactId: artifact.id,
      candidate,
      sourceWeight,
      provider: identity.provider,
      externalId: identity.externalId,
    });
    for (const observation of extracted) {
      await this.dependencies.evidence.appendObservation(observation);
    }
    const featureKeys = [...new Set(extracted.map((observation) => observation.featureKey))];
    for (const featureKey of featureKeys) {
      await this.dependencies.evidence.materializeFeature(place.id, featureKey);
    }

    let links = 0;
    const match = matchCandidateToExperience(candidate, anchors);
    if (match) {
      await this.dependencies.evidence.linkExperience({
        experienceId: match.experienceId,
        placeId: place.id,
        confidence: match.confidence,
        method: match.method,
      });
      links = 1;
    }
    return {
      observations: extracted.length,
      materialized: featureKeys.length,
      links,
      featureKeys,
    };
  }
}

function adapterCanAddress(adapterName: string, featureKeys: readonly string[]): boolean {
  if (featureKeys.length === 0) return true;
  if (adapterName !== "osm") return true;
  const osmCapabilities = new Set<string>([
    FEATURE_KEYS.canonicalName,
    FEATURE_KEYS.coordinates,
    FEATURE_KEYS.rawOpeningHours,
    FEATURE_KEYS.regularOpeningHours,
  ]);
  return featureKeys.some((featureKey) => osmCapabilities.has(featureKey));
}

interface FetchedCandidate {
  readonly candidate: Candidate;
  readonly sourceWeight: number;
}

interface QueryContext {
  readonly center: readonly [number, number];
  readonly radiusMeters: number;
  readonly anchors: readonly ExperienceAnchor[];
  readonly placeAnchor?: ExperienceAnchor;
}

async function fetchCandidates(
  adapters: readonly SourceAdapter[],
  query: SourceQuery,
): Promise<FetchedCandidate[]> {
  const results = await Promise.allSettled(
    adapters.map(async (adapter) => ({ adapter, candidates: await adapter.fetch(query) })),
  );
  const fetched: FetchedCandidate[] = [];
  const failures: string[] = [];
  for (const result of results) {
    if (result.status === "rejected") {
      failures.push(errorMessage(result.reason));
      continue;
    }
    fetched.push(
      ...result.value.candidates.map((candidate) => ({
        candidate,
        sourceWeight: result.value.adapter.weight,
      })),
    );
  }
  if (fetched.length === 0 && failures.length > 0) {
    throw new Error(`all source adapters failed: ${failures.join("; ")}`);
  }
  return fetched;
}

function hardSignalObservations(input: {
  readonly placeId: string;
  readonly artifactId: string;
  readonly candidate: Candidate;
  readonly sourceWeight: number;
  readonly provider: string;
  readonly externalId: string;
}): AppendObservationInput[] {
  const common = {
    placeId: input.placeId,
    artifactId: input.artifactId,
    state: "observed" as const,
    confidence: 0.9,
    sourceWeight: input.sourceWeight,
    independenceKey: `${input.provider}:${input.externalId}`,
    observedAt: input.candidate.fetchedAt,
    extractorVersion: "deterministic-hard-signals-v1",
  };
  const values: Array<{ featureKey: FeatureKey; value: JsonValue }> = [
    { featureKey: FEATURE_KEYS.canonicalName, value: input.candidate.title },
  ];
  if (input.candidate.coordinates) {
    values.push({
      featureKey: FEATURE_KEYS.coordinates,
      value: [...input.candidate.coordinates],
    });
  }
  const hours = lineValue(input.candidate.rawText, "Hours");
  if (hours) {
    values.push({ featureKey: FEATURE_KEYS.rawOpeningHours, value: hours });
    const parsedHours = parseSimpleOpeningHours(hours);
    if (parsedHours) {
      values.push({
        featureKey: FEATURE_KEYS.regularOpeningHours,
        value: parsedHours as unknown as JsonValue,
      });
    }
  }
  return values.map(({ featureKey, value }) => ({
    ...common,
    featureKey,
    value,
    dedupeKey: sha256(
      [input.artifactId, featureKey, JSON.stringify(value), common.extractorVersion].join(":"),
    ),
  }));
}

function parseQuery(query: JsonValue | null): QueryContext {
  if (!isRecord(query)) throw new Error("refresh job query must be an object");
  const center = coordinate(query["center"] ?? query["coordinates"]);
  if (!center) throw new Error("refresh job query requires GeoJSON-order center/coordinates");
  const radiusValue = query["radiusMeters"];
  const radiusMeters =
    typeof radiusValue === "number" && Number.isFinite(radiusValue)
      ? Math.max(50, Math.min(50_000, radiusValue))
      : 300;
  const anchors = parseAnchors(query["experienceAnchors"]);
  const experienceId = query["experienceId"];
  const placeName = query["placeName"];
  const placeAnchor =
    typeof experienceId === "string" && typeof placeName === "string"
      ? { experienceId, placeName, coordinates: center }
      : undefined;
  return { center, radiusMeters, anchors, ...(placeAnchor ? { placeAnchor } : {}) };
}

function parseAnchors(value: JsonValue | undefined): ExperienceAnchor[] {
  if (!Array.isArray(value)) return [];
  const anchors: ExperienceAnchor[] = [];
  for (const item of value) {
    if (!isRecord(item)) continue;
    const experienceId = item["experienceId"];
    const placeName = item["placeName"];
    const coordinates = coordinate(item["coordinates"]);
    if (typeof experienceId === "string" && typeof placeName === "string" && coordinates) {
      anchors.push({ experienceId, placeName, coordinates });
    }
  }
  return anchors;
}

function sourceQuery(center: readonly [number, number], radiusMeters: number): SourceQuery {
  return { bbox: bboxAround(center, radiusMeters), maxResults: 100 };
}

function bboxAround(center: readonly [number, number], radiusMeters: number): BBox {
  const [longitude, latitude] = center;
  const latDelta = radiusMeters / 111_000;
  const longitudeScale = Math.max(0.1, Math.cos((latitude * Math.PI) / 180));
  const lonDelta = radiusMeters / (111_000 * longitudeScale);
  return {
    minLon: Math.max(-180, longitude - lonDelta),
    minLat: Math.max(-90, latitude - latDelta),
    maxLon: Math.min(180, longitude + lonDelta),
    maxLat: Math.min(90, latitude + latDelta),
  };
}

function sourcePolicy(provider: string): {
  readonly licenseCode?: string;
  readonly retentionPolicy: "metadata_only" | "derived_only" | "cacheable_content";
} {
  if (provider === "osm") return { licenseCode: "ODbL-1.0", retentionPolicy: "cacheable_content" };
  return { retentionPolicy: "metadata_only" };
}

function splitSourceId(sourceId: string): { provider: string; externalId: string } {
  const separator = sourceId.indexOf(":");
  if (separator <= 0 || separator === sourceId.length - 1) {
    throw new Error(`invalid source id: ${sourceId}`);
  }
  return { provider: sourceId.slice(0, separator), externalId: sourceId.slice(separator + 1) };
}

function lineValue(rawText: string, label: string): string | undefined {
  const prefix = `${label}:`;
  const line = rawText.split(/\r?\n/).find((candidate) => candidate.startsWith(prefix));
  const value = line?.slice(prefix.length).trim();
  return value || undefined;
}

function coordinate(value: JsonValue | undefined): readonly [number, number] | undefined {
  if (
    !Array.isArray(value) ||
    value.length !== 2 ||
    typeof value[0] !== "number" ||
    typeof value[1] !== "number" ||
    value[0] < -180 ||
    value[0] > 180 ||
    value[1] < -90 ||
    value[1] > 90
  ) {
    return undefined;
  }
  return [value[0], value[1]];
}

function isRecord(
  value: JsonValue | null | undefined,
): value is { readonly [key: string]: JsonValue } {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
