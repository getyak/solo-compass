import {
  pgTable,
  pgEnum,
  text,
  integer,
  timestamp,
  doublePrecision,
  jsonb,
} from "drizzle-orm/pg-core";
import { geographyPoint } from "./geo.js";

export const experienceStatusEnum = pgEnum("experience_status", [
  "candidate",
  "active",
  "stale",
  "retired",
]);

export const experiences = pgTable("experiences", {
  // Stable branded domain id, e.g. exp_cmi_suan_dok_sunset. This used to be a
  // UUID in the disconnected Drizzle schema, which made it incompatible with
  // packages/core and the live Supabase tables.
  id: text("id").primaryKey(),
  title: text("title").notNull(),
  oneLiner: text("one_liner").notNull(),
  whyItMatters: text("why_it_matters").notNull(),
  category: text("category").notNull(),
  // geography(Point,4326) — [longitude, latitude] per GeoJSON convention
  location: geographyPoint("location").notNull(),
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
