CREATE EXTENSION IF NOT EXISTS postgis;
--> statement-breakpoint
ALTER TABLE "experience_revisions" DROP CONSTRAINT IF EXISTS "experience_revisions_experience_id_experiences_id_fk";
ALTER TABLE "sources" DROP CONSTRAINT IF EXISTS "sources_experience_id_experiences_id_fk";
ALTER TABLE "editor_queue" DROP CONSTRAINT IF EXISTS "editor_queue_experience_id_experiences_id_fk";
ALTER TABLE "user_signals" DROP CONSTRAINT IF EXISTS "user_signals_experience_id_experiences_id_fk";
--> statement-breakpoint
ALTER TABLE "experiences" ALTER COLUMN "id" DROP DEFAULT;
ALTER TABLE "experiences" ALTER COLUMN "id" TYPE text USING "id"::text;
ALTER TABLE "experience_revisions" ALTER COLUMN "experience_id" TYPE text USING "experience_id"::text;
ALTER TABLE "sources" ALTER COLUMN "experience_id" TYPE text USING "experience_id"::text;
ALTER TABLE "editor_queue" ALTER COLUMN "experience_id" TYPE text USING "experience_id"::text;
ALTER TABLE "user_signals" ALTER COLUMN "experience_id" TYPE text USING "experience_id"::text;
--> statement-breakpoint
ALTER TABLE "experience_revisions" ADD CONSTRAINT "experience_revisions_experience_id_experiences_id_fk" FOREIGN KEY ("experience_id") REFERENCES "public"."experiences"("id") ON DELETE cascade ON UPDATE no action;
ALTER TABLE "sources" ADD CONSTRAINT "sources_experience_id_experiences_id_fk" FOREIGN KEY ("experience_id") REFERENCES "public"."experiences"("id") ON DELETE cascade ON UPDATE no action;
ALTER TABLE "editor_queue" ADD CONSTRAINT "editor_queue_experience_id_experiences_id_fk" FOREIGN KEY ("experience_id") REFERENCES "public"."experiences"("id") ON DELETE cascade ON UPDATE no action;
ALTER TABLE "user_signals" ADD CONSTRAINT "user_signals_experience_id_experiences_id_fk" FOREIGN KEY ("experience_id") REFERENCES "public"."experiences"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
CREATE TYPE "public"."place_operating_status" AS ENUM('unknown', 'active', 'temporarily_closed', 'permanently_closed');
CREATE TYPE "public"."artifact_retention_policy" AS ENUM('metadata_only', 'derived_only', 'cacheable_content', 'first_party');
CREATE TYPE "public"."observation_state" AS ENUM('observed', 'reported_unknown', 'not_applicable');
CREATE TYPE "public"."resolved_feature_status" AS ENUM('resolved', 'unknown', 'conflicted', 'stale');
CREATE TYPE "public"."refresh_job_status" AS ENUM('queued', 'running', 'succeeded', 'failed', 'dead_letter', 'cancelled');
CREATE TYPE "public"."refresh_reason" AS ENUM('coverage_gap', 'soft_stale', 'hard_constraint', 'user_report', 'source_release', 'manual');
CREATE TYPE "public"."refresh_urgency" AS ENUM('background', 'interactive');
--> statement-breakpoint
CREATE TABLE "places" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"canonical_name" text NOT NULL,
	"basic_category" text,
	"location" geography(Point,4326) NOT NULL,
	"operating_status" "place_operating_status" DEFAULT 'unknown' NOT NULL,
	"identity_confidence" double precision DEFAULT 0.5 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "places_identity_confidence_check" CHECK ("identity_confidence" >= 0 AND "identity_confidence" <= 1)
);
--> statement-breakpoint
CREATE TABLE "place_external_refs" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"place_id" uuid NOT NULL,
	"provider" text NOT NULL,
	"external_id" text NOT NULL,
	"first_seen_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_seen_at" timestamp with time zone DEFAULT now() NOT NULL,
	"retired_at" timestamp with time zone,
	"metadata" jsonb
);
--> statement-breakpoint
CREATE TABLE "source_artifacts" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"provider" text NOT NULL,
	"external_ref" text NOT NULL,
	"source_url" text,
	"content_hash" text NOT NULL,
	"license_code" text,
	"retention_policy" "artifact_retention_policy" NOT NULL,
	"raw_storage_key" text,
	"retrieved_at" timestamp with time zone NOT NULL,
	"source_observed_at" timestamp with time zone,
	"expires_at" timestamp with time zone,
	"metadata" jsonb,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "source_artifacts_restricted_storage_check" CHECK ("retention_policy" IN ('cacheable_content', 'first_party') OR "raw_storage_key" IS NULL)
);
--> statement-breakpoint
CREATE TABLE "place_observations" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"place_id" uuid NOT NULL,
	"artifact_id" uuid,
	"feature_key" text NOT NULL,
	"state" "observation_state" DEFAULT 'observed' NOT NULL,
	"value" jsonb,
	"confidence" double precision NOT NULL,
	"source_weight" double precision DEFAULT 1 NOT NULL,
	"independence_key" text NOT NULL,
	"time_scope" jsonb,
	"observed_at" timestamp with time zone NOT NULL,
	"expires_at" timestamp with time zone,
	"extractor_version" text NOT NULL,
	"dedupe_key" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "place_observations_confidence_check" CHECK ("confidence" >= 0 AND "confidence" <= 1),
	CONSTRAINT "place_observations_source_weight_check" CHECK ("source_weight" >= 0 AND "source_weight" <= 1),
	CONSTRAINT "place_observations_value_check" CHECK (("state" = 'observed' AND "value" IS NOT NULL) OR ("state" <> 'observed'))
);
--> statement-breakpoint
CREATE TABLE "resolved_place_features" (
	"place_id" uuid NOT NULL,
	"feature_key" text NOT NULL,
	"value" jsonb,
	"status" "resolved_feature_status" NOT NULL,
	"confidence" double precision NOT NULL,
	"latest_observed_at" timestamp with time zone,
	"fresh_until" timestamp with time zone,
	"supporting_observation_ids" uuid[] DEFAULT '{}'::uuid[] NOT NULL,
	"conflicting_observation_ids" uuid[] DEFAULT '{}'::uuid[] NOT NULL,
	"conflict_details" jsonb,
	"resolver_version" text NOT NULL,
	"resolution_fingerprint" text NOT NULL,
	"resolved_at" timestamp with time zone NOT NULL,
	CONSTRAINT "resolved_place_features_place_id_feature_key_pk" PRIMARY KEY("place_id", "feature_key"),
	CONSTRAINT "resolved_place_features_confidence_check" CHECK ("confidence" >= 0 AND "confidence" <= 1),
	CONSTRAINT "resolved_place_features_value_check" CHECK ("status" = 'unknown' OR "value" IS NOT NULL)
);
--> statement-breakpoint
CREATE TABLE "experience_place_links" (
	"experience_id" text PRIMARY KEY NOT NULL,
	"place_id" uuid NOT NULL,
	"confidence" double precision DEFAULT 1 NOT NULL,
	"method" text NOT NULL,
	"linked_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "experience_place_links_confidence_check" CHECK ("confidence" >= 0 AND "confidence" <= 1)
);
--> statement-breakpoint
CREATE TABLE "refresh_jobs" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"place_id" uuid,
	"feature_keys" text[] DEFAULT '{}'::text[] NOT NULL,
	"query" jsonb,
	"reason" "refresh_reason" NOT NULL,
	"urgency" "refresh_urgency" DEFAULT 'background' NOT NULL,
	"priority" integer NOT NULL,
	"provider_hint" text,
	"budget_class" text NOT NULL,
	"idempotency_key" text NOT NULL,
	"status" "refresh_job_status" DEFAULT 'queued' NOT NULL,
	"demand_score" double precision NOT NULL,
	"decision_impact" double precision NOT NULL,
	"uncertainty" double precision NOT NULL,
	"staleness" double precision NOT NULL,
	"estimated_cost" double precision NOT NULL,
	"not_before" timestamp with time zone DEFAULT now() NOT NULL,
	"claimed_by" text,
	"claimed_at" timestamp with time zone,
	"lease_expires_at" timestamp with time zone,
	"attempts" integer DEFAULT 0 NOT NULL,
	"max_attempts" integer DEFAULT 5 NOT NULL,
	"last_error" text,
	"result" jsonb,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"completed_at" timestamp with time zone,
	CONSTRAINT "refresh_jobs_scores_check" CHECK (
		"demand_score" BETWEEN 0 AND 1 AND
		"decision_impact" BETWEEN 0 AND 1 AND
		"uncertainty" BETWEEN 0 AND 1 AND
		"staleness" BETWEEN 0 AND 1 AND
		"estimated_cost" > 0
	),
	CONSTRAINT "refresh_jobs_attempts_check" CHECK ("attempts" >= 0 AND "max_attempts" > 0)
);
--> statement-breakpoint
ALTER TABLE "place_external_refs" ADD CONSTRAINT "place_external_refs_place_id_places_id_fk" FOREIGN KEY ("place_id") REFERENCES "public"."places"("id") ON DELETE cascade ON UPDATE no action;
ALTER TABLE "place_observations" ADD CONSTRAINT "place_observations_place_id_places_id_fk" FOREIGN KEY ("place_id") REFERENCES "public"."places"("id") ON DELETE cascade ON UPDATE no action;
ALTER TABLE "place_observations" ADD CONSTRAINT "place_observations_artifact_id_source_artifacts_id_fk" FOREIGN KEY ("artifact_id") REFERENCES "public"."source_artifacts"("id") ON DELETE set null ON UPDATE no action;
ALTER TABLE "resolved_place_features" ADD CONSTRAINT "resolved_place_features_place_id_places_id_fk" FOREIGN KEY ("place_id") REFERENCES "public"."places"("id") ON DELETE cascade ON UPDATE no action;
ALTER TABLE "experience_place_links" ADD CONSTRAINT "experience_place_links_place_id_places_id_fk" FOREIGN KEY ("place_id") REFERENCES "public"."places"("id") ON DELETE cascade ON UPDATE no action;
ALTER TABLE "refresh_jobs" ADD CONSTRAINT "refresh_jobs_place_id_places_id_fk" FOREIGN KEY ("place_id") REFERENCES "public"."places"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
CREATE INDEX "idx_places_location" ON "places" USING gist ("location");
CREATE INDEX "idx_places_operating_status" ON "places" USING btree ("operating_status");
CREATE UNIQUE INDEX "uq_place_external_refs_provider_id" ON "place_external_refs" USING btree ("provider", "external_id");
CREATE INDEX "idx_place_external_refs_place_provider" ON "place_external_refs" USING btree ("place_id", "provider");
CREATE UNIQUE INDEX "uq_source_artifacts_version" ON "source_artifacts" USING btree ("provider", "external_ref", "content_hash");
CREATE INDEX "idx_source_artifacts_expiry" ON "source_artifacts" USING btree ("provider", "expires_at");
CREATE UNIQUE INDEX "uq_place_observations_dedupe_key" ON "place_observations" USING btree ("dedupe_key");
CREATE INDEX "idx_place_observations_feature_time" ON "place_observations" USING btree ("place_id", "feature_key", "observed_at");
CREATE INDEX "idx_place_observations_artifact" ON "place_observations" USING btree ("artifact_id");
CREATE INDEX "idx_resolved_place_features_status_freshness" ON "resolved_place_features" USING btree ("status", "fresh_until");
CREATE INDEX "idx_experience_place_links_place" ON "experience_place_links" USING btree ("place_id");
CREATE UNIQUE INDEX "uq_refresh_jobs_idempotency_key" ON "refresh_jobs" USING btree ("idempotency_key");
CREATE INDEX "idx_refresh_jobs_claim" ON "refresh_jobs" USING btree ("status", "not_before", "priority");
CREATE INDEX "idx_refresh_jobs_place_status" ON "refresh_jobs" USING btree ("place_id", "status");
--> statement-breakpoint
CREATE OR REPLACE FUNCTION "sc_set_updated_at"()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
	NEW.updated_at = now();
	RETURN NEW;
END;
$$;
--> statement-breakpoint
CREATE TRIGGER "places_set_updated_at"
BEFORE UPDATE ON "places"
FOR EACH ROW EXECUTE FUNCTION "sc_set_updated_at"();
CREATE TRIGGER "refresh_jobs_set_updated_at"
BEFORE UPDATE ON "refresh_jobs"
FOR EACH ROW EXECUTE FUNCTION "sc_set_updated_at"();
--> statement-breakpoint
CREATE OR REPLACE FUNCTION "upsert_place_identity"(
	"p_provider" text,
	"p_external_id" text,
	"p_canonical_name" text,
	"p_longitude" double precision,
	"p_latitude" double precision,
	"p_basic_category" text DEFAULT NULL,
	"p_identity_confidence" double precision DEFAULT 0.5,
	"p_metadata" jsonb DEFAULT NULL
)
RETURNS "places"
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
	place_row places%ROWTYPE;
	existing_place_id uuid;
BEGIN
	IF p_longitude < -180 OR p_longitude > 180 OR p_latitude < -90 OR p_latitude > 90 THEN
		RAISE EXCEPTION 'invalid WGS-84 coordinate';
	END IF;
	IF p_identity_confidence < 0 OR p_identity_confidence > 1 THEN
		RAISE EXCEPTION 'identity confidence must be between 0 and 1';
	END IF;

	-- Serialize identity creation for one provider id so concurrent imports do
	-- not create an orphan place before the unique alias constraint wins.
	PERFORM pg_advisory_xact_lock(hashtextextended(p_provider || ':' || p_external_id, 0));
	SELECT place_id INTO existing_place_id
	FROM place_external_refs
	WHERE provider = p_provider AND external_id = p_external_id
	FOR UPDATE;

	IF existing_place_id IS NULL THEN
		INSERT INTO places (canonical_name, basic_category, location, identity_confidence)
		VALUES (
			p_canonical_name,
			p_basic_category,
			ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography,
			p_identity_confidence
		)
		RETURNING * INTO place_row;

		INSERT INTO place_external_refs (place_id, provider, external_id, metadata)
		VALUES (place_row.id, p_provider, p_external_id, p_metadata);
	ELSE
		UPDATE places
		SET canonical_name = p_canonical_name,
			basic_category = COALESCE(p_basic_category, basic_category),
			location = ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography,
			identity_confidence = greatest(identity_confidence, p_identity_confidence)
		WHERE id = existing_place_id
		RETURNING * INTO place_row;

		UPDATE place_external_refs
		SET last_seen_at = now(), retired_at = NULL, metadata = COALESCE(p_metadata, metadata)
		WHERE provider = p_provider AND external_id = p_external_id;
	END IF;

	RETURN place_row;
END;
$$;
--> statement-breakpoint
CREATE OR REPLACE FUNCTION "claim_refresh_jobs"(
	"p_worker" text,
	"p_batch_size" integer DEFAULT 10,
	"p_lease_seconds" integer DEFAULT 120
)
RETURNS SETOF "refresh_jobs"
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
	RETURN QUERY
	WITH candidates AS (
		SELECT id
		FROM refresh_jobs
		WHERE (
			(status = 'queued' AND not_before <= now())
			OR (status = 'running' AND lease_expires_at < now())
		)
		AND attempts < max_attempts
		ORDER BY urgency DESC, priority DESC, created_at ASC
		FOR UPDATE SKIP LOCKED
		LIMIT greatest(1, least(p_batch_size, 100))
	)
	UPDATE refresh_jobs AS jobs
	SET status = 'running',
		claimed_by = p_worker,
		claimed_at = now(),
		lease_expires_at = now() + make_interval(secs => greatest(30, p_lease_seconds)),
		attempts = jobs.attempts + 1,
		last_error = NULL,
		updated_at = now()
	FROM candidates
	WHERE jobs.id = candidates.id
	RETURNING jobs.*;
END;
$$;
