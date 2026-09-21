CREATE TYPE "public"."route_compilation_status" AS ENUM('solved', 'unsatisfiable');
--> statement-breakpoint
CREATE TABLE "route_compilations" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"cache_key" text NOT NULL,
	"request_fingerprint" text NOT NULL,
	"input_fingerprint" text NOT NULL,
	"status" "route_compilation_status" NOT NULL,
	"plan_payload" jsonb NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX "uq_route_compilations_user_cache" ON "route_compilations" USING btree ("user_id", "cache_key");
CREATE INDEX "idx_route_compilations_expiry" ON "route_compilations" USING btree ("expires_at");
CREATE INDEX "idx_route_compilations_user_updated" ON "route_compilations" USING btree ("user_id", "updated_at");
--> statement-breakpoint
CREATE TABLE "route_compile_quotas" (
	"user_id" uuid NOT NULL,
	"bucket_start" timestamp with time zone NOT NULL,
	"attempts" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "route_compile_quotas_user_id_bucket_start_pk" PRIMARY KEY("user_id", "bucket_start"),
	CONSTRAINT "route_compile_quotas_attempts_check" CHECK ("attempts" >= 0)
);
--> statement-breakpoint
CREATE INDEX "idx_route_compile_quotas_expiry" ON "route_compile_quotas" USING btree ("bucket_start");
--> statement-breakpoint
CREATE OR REPLACE FUNCTION "public"."consume_route_compile_quota"(
	"p_user_id" uuid,
	"p_limit" integer DEFAULT 30
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  allowed boolean;
  current_bucket timestamptz := date_trunc('hour', now());
BEGIN
  IF p_limit < 1 THEN RETURN false; END IF;
  INSERT INTO public.route_compile_quotas (user_id, bucket_start, attempts, updated_at)
  VALUES (p_user_id, current_bucket, 1, now())
  ON CONFLICT (user_id, bucket_start) DO UPDATE
    SET attempts = route_compile_quotas.attempts + 1,
        updated_at = now()
    WHERE route_compile_quotas.attempts < p_limit
  RETURNING true INTO allowed;
  RETURN coalesce(allowed, false);
END;
$$;
