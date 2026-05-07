import {
  pgTable,
  pgEnum,
  uuid,
  text,
  integer,
  timestamp,
  jsonb,
  index,
} from "drizzle-orm/pg-core";
import { experiences } from "./experiences.js";

export const compilationJobStatusEnum = pgEnum("compilation_job_status", [
  "queued",
  "running",
  "completed",
  "failed",
]);

export const compilationJobs = pgTable("compilation_jobs", {
  id: uuid("id").primaryKey().defaultRandom(),
  query: jsonb("query").notNull(),
  status: compilationJobStatusEnum("status").notNull().default("queued"),
  startedAt: timestamp("started_at", { withTimezone: true }),
  completedAt: timestamp("completed_at", { withTimezone: true }),
  error: text("error"),
});

export const editorQueue = pgTable(
  "editor_queue",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    experienceId: uuid("experience_id")
      .notNull()
      .references(() => experiences.id, { onDelete: "cascade" }),
    priority: integer("priority").notNull().default(0),
    claimedBy: text("claimed_by"),
    claimedAt: timestamp("claimed_at", { withTimezone: true }),
  },
  (t) => [index("idx_editor_queue_priority").on(t.priority)],
);
