-- US-025: reviews_extracted table with pgvector embeddings.
-- Requires pgvector extension (available in ankane/pgvector or pgvector/pgvector images).

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS reviews_extracted (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    experience_id   TEXT NOT NULL,
    source          TEXT NOT NULL,
    raw_text        TEXT NOT NULL,
    embedding       vector(768),
    wifi_score      DOUBLE PRECISION,
    noise_score     DOUBLE PRECISION,
    seating_score   DOUBLE PRECISION,
    staff_score     DOUBLE PRECISION,
    lighting_score  DOUBLE PRECISION,
    safety_score    DOUBLE PRECISION,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reviews_extracted_experience_id
    ON reviews_extracted (experience_id);
