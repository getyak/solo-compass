import type { TransportMode, TravelTimeMatrix } from "./types";

export interface MatrixNode {
  id: string;
  /** GeoJSON order: [longitude, latitude]. */
  coordinates: [longitude: number, latitude: number];
}

export interface ValhallaMatrixClientOptions {
  endpoint: string;
  fetch?: typeof globalThis.fetch;
  timeoutMs?: number;
}

interface ValhallaConciseResponse {
  sources_to_targets?: {
    durations?: Array<Array<number | null>>;
    distances?: Array<Array<number | null>>;
  };
}

export class ValhallaMatrixClient {
  private readonly endpoint: string;
  private readonly fetchImpl: typeof globalThis.fetch;
  private readonly timeoutMs: number;

  constructor(options: ValhallaMatrixClientOptions) {
    this.endpoint = options.endpoint.replace(/\/$/, "");
    this.fetchImpl = options.fetch ?? globalThis.fetch;
    this.timeoutMs = options.timeoutMs ?? 8_000;
  }

  async buildMatrix(
    nodes: MatrixNode[],
    mode: TransportMode,
    departureLocal?: string,
  ): Promise<TravelTimeMatrix> {
    validateNodes(nodes);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const locations = nodes.map(({ coordinates }) => ({
        lat: coordinates[1],
        lon: coordinates[0],
      }));
      const response = await this.fetchImpl(`${this.endpoint}/sources_to_targets`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          sources: locations,
          targets: locations,
          costing: mode,
          units: "kilometers",
          verbose: false,
          ...(departureLocal ? { date_time: { type: 1, value: departureLocal } } : {}),
        }),
        signal: controller.signal,
      });
      if (!response.ok) {
        throw new Error(`Valhalla matrix failed with HTTP ${response.status}`);
      }
      const payload = (await response.json()) as ValhallaConciseResponse;
      return parseConciseMatrix(payload, nodes, mode);
    } finally {
      clearTimeout(timeout);
    }
  }
}

function parseConciseMatrix(
  payload: ValhallaConciseResponse,
  nodes: MatrixNode[],
  mode: TransportMode,
): TravelTimeMatrix {
  const durations = payload.sources_to_targets?.durations;
  const distances = payload.sources_to_targets?.distances;
  if (!durations || durations.length !== nodes.length) {
    throw new Error("Valhalla returned an invalid duration matrix");
  }

  const cells: TravelTimeMatrix["cells"] = {};
  for (const [sourceIndex, source] of nodes.entries()) {
    const durationRow = durations[sourceIndex];
    const distanceRow = distances?.[sourceIndex];
    if (!durationRow || durationRow.length !== nodes.length) {
      throw new Error("Valhalla returned a non-square duration matrix");
    }
    const row: NonNullable<TravelTimeMatrix["cells"][string]> = {};
    for (const [targetIndex, target] of nodes.entries()) {
      const seconds = durationRow[targetIndex];
      const kilometers = distanceRow?.[targetIndex];
      row[target.id] = {
        durationMinutes:
          seconds === null || seconds === undefined ? null : Math.max(0, seconds / 60),
        ...(kilometers === null || kilometers === undefined
          ? {}
          : { distanceMeters: Math.max(0, kilometers * 1_000) }),
      };
    }
    cells[source.id] = row;
  }
  return { mode, generatedAt: new Date().toISOString(), cells };
}

function validateNodes(nodes: MatrixNode[]): void {
  if (nodes.length === 0) throw new Error("at least one matrix node is required");
  const ids = new Set<string>();
  for (const node of nodes) {
    if (!node.id || ids.has(node.id)) throw new Error(`matrix node ids must be unique: ${node.id}`);
    ids.add(node.id);
    const [longitude, latitude] = node.coordinates;
    if (longitude < -180 || longitude > 180 || latitude < -90 || latitude > 90) {
      throw new Error(`matrix node ${node.id} has invalid WGS-84 coordinates`);
    }
  }
}
