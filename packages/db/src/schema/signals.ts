import { pgTable, pgEnum, uuid, text, timestamp, jsonb, index } from "drizzle-orm/pg-core";
import { experiences } from "./experiences.js";

export const signalTypeEnum = pgEnum("signal_type", ["gps_dwell", "micro_survey", "user_report"]);

export const userSignals = pgTable(
  "user_signals",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    experienceId: text("experience_id")
      .notNull()
      .references(() => experiences.id, { onDelete: "cascade" }),
    anonymousDeviceId: text("anonymous_device_id").notNull(),
    signalType: signalTypeEnum("signal_type").notNull(),
    payload: jsonb("payload"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index("idx_user_signals_experience_signal").on(t.experienceId, t.signalType)],
);

export const auditLog = pgTable("audit_log", {
  id: uuid("id").primaryKey().defaultRandom(),
  actor: text("actor").notNull(),
  action: text("action").notNull(),
  targetType: text("target_type").notNull(),
  targetId: text("target_id").notNull(),
  payload: jsonb("payload"),
  at: timestamp("at", { withTimezone: true }).notNull().defaultNow(),
});
