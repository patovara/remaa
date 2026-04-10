#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   STAGING_PROJECT_REF=<ref> STAGING_DB_PASSWORD=<pwd> ./scripts/staging/03_set_supabase_staging_secrets.sh
#
# Requires:
#   supabase/.env.staging (copy from supabase/.env.staging.example)

if [[ -z "${STAGING_PROJECT_REF:-}" ]]; then
  echo "Missing STAGING_PROJECT_REF"
  exit 1
fi

if [[ -z "${STAGING_DB_PASSWORD:-}" ]]; then
  echo "Missing STAGING_DB_PASSWORD"
  exit 1
fi

if [[ ! -f "supabase/.env.staging" ]]; then
  echo "Missing supabase/.env.staging"
  exit 1
fi

echo "Linking staging project ${STAGING_PROJECT_REF}..."
supabase link --project-ref "${STAGING_PROJECT_REF}" --password "${STAGING_DB_PASSWORD}"

echo "Pushing function secrets to staging..."
supabase secrets set --env-file supabase/.env.staging

echo "Deploying edge functions to staging..."
supabase functions deploy user-admin
supabase functions deploy mailer
supabase functions deploy email-inbound

echo "Done."
