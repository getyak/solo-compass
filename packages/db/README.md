# @solo-compass/db

Drizzle ORM schema and migrations for the Solo Compass Postgres database.

## Setup

### Start the database

```bash
pnpm db:up
```

This builds a PostgreSQL 16 development image with both PostGIS and pgvector,
then starts it through Docker Compose (defined at the repo root). Default
connection: `postgres://solo:solo@localhost:5432/solocompass`.

### Run migrations

```bash
pnpm db:migrate
```

Applies all pending SQL migrations from `./migrations/` to the database.
Run this from the repository root; the root script delegates to this package.

### Generate migrations after schema changes

```bash
pnpm db:generate
```

Diffs `./src/schema/` against the database and writes a new migration file to `./migrations/`.

## Environment

Set `DATABASE_URL` to override the default connection string:

```
DATABASE_URL=postgres://user:pass@host:5432/dbname
```
