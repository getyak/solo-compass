import { pgTable, pgEnum, uuid, text, integer, timestamp, jsonb } from "drizzle-orm/pg-core";
import { experiences } from "./experiences.js";

export const sourceTypeEnum = pgEnum("source_type", [
  "wikivoyage",
  "osm",
  "google_places",
]);

export const sources = pgTable("sources", {
  id: uuid("id").primaryKey().defaultRandom(),
  experienceId: uuid("experience_id")
    .notNull()
    .references(() => experiences.id, { onDelete: "cascade" }),
  sourceType: sourceTypeEnum("source_type").notNull(),
  sourceUrl: text("source_url").notNull(),
  weight: integer("weight").notNull().default(1),
  evidence: jsonb("evidence"),
  verifiedAt: timestamp("verified_at", { withTimezone: true }),
});

export const droppedCandidates = pgTable("dropped_candidates", {
  id: uuid("id").primaryKey().defaultRandom(),
  evidence: jsonb("evidence"),
  reason: text("reason").notNull(),
  droppedAt: timestamp("dropped_at", { withTimezone: true }).notNull().defaultNow(),
});
