import { customType } from "drizzle-orm/pg-core";

/**
 * PostGIS geography(Point, 4326).
 *
 * Coordinates entering the database must be WGS-84 and use GeoJSON order at
 * application boundaries: [longitude, latitude]. Postgres drivers expose the
 * value as provider-specific text/GeoJSON, so the schema deliberately keeps
 * the transport representation opaque.
 */
export const geographyPoint = customType<{ data: string }>({
  dataType() {
    return "geography(Point,4326)";
  },
});
