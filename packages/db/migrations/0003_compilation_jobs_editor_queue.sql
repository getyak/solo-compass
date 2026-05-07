CREATE TYPE "public"."compilation_job_status" AS ENUM('queued', 'running', 'completed', 'failed');
--> statement-breakpoint
CREATE TABLE "compilation_jobs" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"query" jsonb NOT NULL,
	"status" "compilation_job_status" DEFAULT 'queued' NOT NULL,
	"started_at" timestamp with time zone,
	"completed_at" timestamp with time zone,
	"error" text
);
--> statement-breakpoint
CREATE TABLE "editor_queue" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"experience_id" uuid NOT NULL,
	"priority" integer DEFAULT 0 NOT NULL,
	"claimed_by" text,
	"claimed_at" timestamp with time zone
);
--> statement-breakpoint
ALTER TABLE "editor_queue" ADD CONSTRAINT "editor_queue_experience_id_experiences_id_fk" FOREIGN KEY ("experience_id") REFERENCES "public"."experiences"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
CREATE INDEX "idx_editor_queue_priority" ON "editor_queue" ("priority");
