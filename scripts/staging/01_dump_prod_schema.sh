#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   PROD_PROJECT_REF=<ref> PROD_DB_PASSWORD=<pwd> ./scripts/staging/01_dump_prod_schema.sh
# Output:
#   supabase/.temp/prod_schema.sql

if [[ -z "${PROD_PROJECT_REF:-}" ]]; then
  echo "Missing PROD_PROJECT_REF"
  exit 1
fi

if [[ -z "${PROD_DB_PASSWORD:-}" ]]; then
  echo "Missing PROD_DB_PASSWORD"
  exit 1
fi

mkdir -p supabase/.temp

echo "Linking production project ${PROD_PROJECT_REF}..."
supabase link --project-ref "${PROD_PROJECT_REF}" --password "${PROD_DB_PASSWORD}"

echo "Dumping schema from production (no data)..."
supabase db dump --linked --schema public,auth,storage --file supabase/.temp/prod_schema.sql

echo "Done: supabase/.temp/prod_schema.sql"
