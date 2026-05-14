#!/usr/bin/env bash
set -euo pipefail

# Required env vars:
# SUPABASE_PROJECT_URL="https://<project-ref>.supabase.co"
# SUPABASE_ANON_KEY="<anon-key>"
# SUPABASE_JWT="<user-access-token>"

# 1) buildMemoryContext
curl -sS -X POST "$SUPABASE_PROJECT_URL/functions/v1/buildMemoryContext" \
  -H "Authorization: Bearer $SUPABASE_JWT" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "project_id": "remaa_app",
    "user_input": "Genera plan de pruebas para cotizaciones multicurrency"
  }'

echo

# 2) updateMemory (event only)
curl -sS -X POST "$SUPABASE_PROJECT_URL/functions/v1/updateMemory" \
  -H "Authorization: Bearer $SUPABASE_JWT" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "project_id": "remaa_app",
    "new_event": "Se desplego fix de nombre de PDF en staging"
  }'

echo

# 3) updateMemory con merge profundo para features
curl -sS -X POST "$SUPABASE_PROJECT_URL/functions/v1/updateMemory" \
  -H "Authorization: Bearer $SUPABASE_JWT" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "project_id": "remaa_app",
    "new_event": "Se completo integracion inicial de memoria IA",
    "optional_state_update": {
      "features": [
        "sistema de memoria persistente IA"
      ],
      "pendientes": [
        "activar monitoreo de memory logs en staging"
      ],
      "decisiones": [
        "persistir estado y resumen en tablas dedicadas"
      ],
      "arquitectura": {
        "reglas": [
          "state siempre se actualiza por merge profundo"
        ]
      }
    }
  }'

echo
