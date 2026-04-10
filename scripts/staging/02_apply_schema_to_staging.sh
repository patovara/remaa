#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   STAGING_DB_URL='postgresql://postgres:<pwd>@db.<ref>.supabase.co:5432/postgres' \
#   ./scripts/staging/02_apply_schema_to_staging.sh
#
# Optional:
#   SCHEMA_FILE=supabase/.temp/prod_schema.sql ./scripts/staging/02_apply_schema_to_staging.sh

SCHEMA_FILE="${SCHEMA_FILE:-supabase/.temp/prod_schema.sql}"

if [[ ! -f "${SCHEMA_FILE}" ]]; then
  echo "Schema file not found: ${SCHEMA_FILE}"
  exit 1
fi

if [[ -z "${STAGING_DB_URL:-}" ]]; then
  echo "Missing STAGING_DB_URL"
  exit 1
fi

echo "Applying ${SCHEMA_FILE} to staging..."
psql "${STAGING_DB_URL}" -v ON_ERROR_STOP=1 -f "${SCHEMA_FILE}"

echo "Done."
