import {
  pgEnum,
  pgTable,
  uuid,
  text,
  timestamp,
  doublePrecision,
  integer,
  jsonb,
  index,
  uniqueIndex,
} from "drizzle-orm/pg-core";
import { sql } from "drizzle-orm";
import { places } from "./evidence.js";

export const refreshJobStatusEnum = pgEnum("refresh_job_status", [
  "queued",
  "running",
  "succeeded",
  "failed",
  "dead_letter",
  "cancelled",
]);

export const refreshReasonEnum = pgEnum("refresh_reason", [
  "coverage_gap",
  "soft_stale",
  "hard_constraint",
  "user_report",
  "source_release",
  "manual",
]);

export const refreshUrgencyEnum = pgEnum("refresh_urgency", ["background", "interactive"]);

/** Durable, budget-auditable work queue. Jobs are claimed with SKIP LOCKED. */
export const refreshJobs = pgTable(
  "refresh_jobs",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    placeId: uuid("place_id").references(() => places.id, { onDelete: "cascade" }),
    featureKeys: text("feature_keys")
      .array()
      .notNull()
      .default(sql`'{}'::text[]`),
    query: jsonb("query"),
    reason: refreshReasonEnum("reason").notNull(),
    urgency: refreshUrgencyEnum("urgency").notNull().default("background"),
    priority: integer("priority").notNull(),
    providerHint: text("provider_hint"),
    budgetClass: text("budget_class").notNull(),
    idempotencyKey: text("idempotency_key").notNull(),
    status: refreshJobStatusEnum("status").notNull().default("queued"),
    demandScore: doublePrecision("demand_score").notNull(),
    decisionImpact: doublePrecision("decision_impact").notNull(),
    uncertainty: doublePrecision("uncertainty").notNull(),
    staleness: doublePrecision("staleness").notNull(),
    estimatedCost: doublePrecision("estimated_cost").notNull(),
    notBefore: timestamp("not_before", { withTimezone: true }).notNull().defaultNow(),
    claimedBy: text("claimed_by"),
    claimedAt: timestamp("claimed_at", { withTimezone: true }),
    leaseExpiresAt: timestamp("lease_expires_at", { withTimezone: true }),
    attempts: integer("attempts").notNull().default(0),
    maxAttempts: integer("max_attempts").notNull().default(5),
    lastError: text("last_error"),
    result: jsonb("result"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
    completedAt: timestamp("completed_at", { withTimezone: true }),
  },
  (table) => [
    uniqueIndex("uq_refresh_jobs_idempotency_key").on(table.idempotencyKey),
    index("idx_refresh_jobs_claim").on(table.status, table.notBefore, table.priority),
    index("idx_refresh_jobs_place_status").on(table.placeId, table.status),
  ],
);
