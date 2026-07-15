#!/usr/bin/env bash
set -euo pipefail
docker compose -f deploy/compose.prod.yml --project-name solo-compass up -d --build --remove-orphans
docker image prune -f
