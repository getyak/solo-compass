CREATE TYPE "public"."source_type" AS ENUM('wikivoyage', 'osm', 'google_places');
--> statement-breakpoint
CREATE TABLE "sources" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"experience_id" uuid NOT NULL,
	"source_type" "source_type" NOT NULL,
	"source_url" text NOT NULL,
	"weight" integer DEFAULT 1 NOT NULL,
	"evidence" jsonb,
	"verified_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "dropped_candidates" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"evidence" jsonb,
	"reason" text NOT NULL,
	"dropped_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "sources" ADD CONSTRAINT "sources_experience_id_experiences_id_fk" FOREIGN KEY ("experience_id") REFERENCES "public"."experiences"("id") ON DELETE cascade ON UPDATE no action;
