FROM pgvector/pgvector:pg16

# Solo Compass needs both extensions: PostGIS for map queries and pgvector for
# the existing review-enrichment pipeline. The upstream pgvector image keeps
# the regular Postgres entrypoint, so local development can still use the
# documented `solo` role and database.
RUN apt-get update \
    && apt-get install --yes --no-install-recommends postgresql-16-postgis-3 \
    && rm -rf /var/lib/apt/lists/*
