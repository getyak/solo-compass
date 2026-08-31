CREATE TYPE "public"."work_session_outcome" AS ENUM('completed', 'partially_completed', 'abandoned');
CREATE TYPE "public"."work_session_failure_reason" AS ENUM('place_closed', 'no_seat', 'wifi_unreliable', 'too_noisy', 'no_power', 'video_call_not_allowed', 'long_stay_pressure', 'minimum_spend', 'other');
--> statement-breakpoint
CREATE TABLE "work_sessions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"experience_id" text NOT NULL,
	"place_id" uuid NOT NULL,
	"planned_task_kind" text NOT NULL,
	"started_at" timestamp with time zone NOT NULL,
	"ended_at" timestamp with time zone NOT NULL,
	"outcome" "work_session_outcome" NOT NULL,
	"failure_reason" "work_session_failure_reason",
	"place_was_open" boolean,
	"wifi_reliability" smallint,
	"noise_level" smallint,
	"power_available" boolean,
	"video_call_worked" boolean,
	"long_stay_accepted" boolean,
	"minimum_spend_amount" double precision,
	"minimum_spend_currency" text,
	"idempotency_key" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "work_sessions_time_check" CHECK ("ended_at" >= "started_at" AND "ended_at" <= "started_at" + interval '24 hours'),
	CONSTRAINT "work_sessions_wifi_check" CHECK ("wifi_reliability" IS NULL OR "wifi_reliability" BETWEEN 1 AND 5),
	CONSTRAINT "work_sessions_noise_check" CHECK ("noise_level" IS NULL OR "noise_level" BETWEEN 1 AND 5),
	CONSTRAINT "work_sessions_spend_check" CHECK (("minimum_spend_amount" IS NULL AND "minimum_spend_currency" IS NULL) OR ("minimum_spend_amount" >= 0 AND "minimum_spend_currency" ~ '^[A-Z]{3}$'))
);
--> statement-breakpoint
ALTER TABLE "work_sessions" ADD CONSTRAINT "work_sessions_place_id_places_id_fk" FOREIGN KEY ("place_id") REFERENCES "public"."places"("id") ON DELETE cascade ON UPDATE no action;
CREATE UNIQUE INDEX "uq_work_sessions_user_idempotency" ON "work_sessions" USING btree ("user_id", "idempotency_key");
CREATE INDEX "idx_work_sessions_user_time" ON "work_sessions" USING btree ("user_id", "ended_at");
CREATE INDEX "idx_work_sessions_place_time" ON "work_sessions" USING btree ("place_id", "ended_at");
CREATE INDEX "idx_work_sessions_experience_time" ON "work_sessions" USING btree ("experience_id", "ended_at");
