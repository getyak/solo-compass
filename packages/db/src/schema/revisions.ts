import { pgTable, uuid, integer, text, timestamp, jsonb, index } from "drizzle-orm/pg-core";
import { experiences } from "./experiences.js";

export const experienceRevisions = pgTable(
  "experience_revisions",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    experienceId: uuid("experience_id")
      .notNull()
      .references(() => experiences.id, { onDelete: "cascade" }),
    revisionNumber: integer("revision_number").notNull(),
    fullPayload: jsonb("full_payload").notNull(),
    createdBy: text("created_by").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index("idx_experience_revisions_exp_rev").on(t.experienceId, t.revisionNumber)],
);
