/**
 * Geospatial primitives.
 *
 * We use [longitude, latitude] tuples (GeoJSON convention) — NOT [lat, lng]
 * which Google Maps uses. Pick one and stick to it; mixing them is a leading
 * cause of "the pin is in the wrong ocean" bugs.
 */

/** [longitude, latitude] in WGS84. Matches GeoJSON, Mapbox, PostGIS. */
export type Coordinates = readonly [number, number];

export interface BoundingBox {
  readonly southWest: Coordinates;
  readonly northEast: Coordinates;
}

export interface GeofenceCircle {
  readonly center: Coordinates;
  readonly radiusMeters: number;
}

/** Haversine distance in meters. */
export function distanceMeters(a: Coordinates, b: Coordinates): number {
  const R = 6_371_000;
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const [lon1, lat1] = a;
  const [lon2, lat2] = b;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const sinDLat = Math.sin(dLat / 2);
  const sinDLon = Math.sin(dLon / 2);
  const h =
    sinDLat * sinDLat + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * sinDLon * sinDLon;
  return 2 * R * Math.asin(Math.sqrt(h));
}

/** Estimate walking time. Uses a flat 80m/min pace; refine with elevation later. */
export function walkingMinutes(meters: number): number {
  return Math.ceil(meters / 80);
}
