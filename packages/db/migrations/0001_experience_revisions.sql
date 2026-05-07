CREATE TABLE IF NOT EXISTS "experience_revisions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"experience_id" uuid NOT NULL,
	"revision_number" integer NOT NULL,
	"full_payload" jsonb NOT NULL,
	"created_by" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "experience_revisions"
  ADD CONSTRAINT "experience_revisions_experience_id_experiences_id_fk"
  FOREIGN KEY ("experience_id") REFERENCES "public"."experiences"("id")
  ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_experience_revisions_exp_rev"
  ON "experience_revisions" ("experience_id", "revision_number");
