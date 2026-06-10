import {
  pgTable,
  pgEnum,
  uuid,
  text,
  integer,
  timestamp,
  doublePrecision,
  jsonb,
  customType,
} from "drizzle-orm/pg-core";

export const experienceStatusEnum = pgEnum("experience_status", [
  "candidate",
  "active",
  "stale",
  "retired",
]);

// PostGIS geography(Point,4326) stored as WKB hex; returned as WKB text from the DB.
const geography = customType<{ data: string }>({
  dataType() {
    return "geography(Point,4326)";
  },
});

export const experiences = pgTable("experiences", {
  id: uuid("id").primaryKey().defaultRandom(),
  title: text("title").notNull(),
  oneLiner: text("one_liner").notNull(),
  whyItMatters: text("why_it_matters").notNull(),
  category: text("category").notNull(),
  // geography(Point,4326) — [longitude, latitude] per GeoJSON convention
  location: geography("location").notNull(),
  confidenceLevel: integer("confidence_level").notNull().default(0),
  status: experienceStatusEnum("status").notNull().default("candidate"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  lastCompiledAt: timestamp("last_compiled_at", { withTimezone: true }),
  // Flattened sub-fields from Experience.durationMinutes
  durationMin: integer("duration_min"),
  durationMax: integer("duration_max"),
  // Flattened sub-fields from Experience.stats
  completionCount: integer("completion_count").notNull().default(0),
  averageRating: doublePrecision("average_rating"),
  // JSONB blobs for complex nested shapes
  bestTimes: jsonb("best_times"),
  howTo: jsonb("how_to"),
  realInconveniences: jsonb("real_inconveniences"),
  soloScore: jsonb("solo_score"),
  sources: jsonb("sources"),
  // User-defined free-form tags layered on top of the category enum (US-005).
  // Optional JSONB array of strings; absence is equivalent to an empty array.
  userTags: jsonb("user_tags"),
  // Category-specific scannable facts (Wi-Fi for cafés, signature dish for
  // food, best light for sights). Optional JSONB array of {kind,label,value};
  // absence is equivalent to an empty array. Mirrors Experience.categoryHighlights.
  categoryHighlights: jsonb("category_highlights"),
});
