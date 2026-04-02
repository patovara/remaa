# Bloque 2: Supabase Cloud Staging

Este bloque deja staging cloud listo para pruebas alfa con usuarios controlados.

## 1) Secrets que debes crear en GitHub (Settings > Secrets and variables > Actions)

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_PROJECT_REF_STAGING`
- `SUPABASE_DB_PASSWORD_STAGING`
- `SUPABASE_URL_STAGING`
- `SUPABASE_ANON_KEY_STAGING`
- `SUPABASE_SERVICE_ROLE_KEY_STAGING`
- `OWNER_EMAIL`
- `APP_PUBLIC_URL_STAGING`
- `RESEND_API_KEY`
- `RESEND_FROM_EMAIL`
- `EMAIL_WEBHOOK_SECRET`

## 2) Workflow disponible

Archivo: `.github/workflows/supabase-staging-deploy.yml`

Ejecución manual desde GitHub Actions:

1. Abrir workflow `Supabase Staging Deploy`.
2. `apply_db = true` para aplicar migraciones.
3. `deploy_functions = true` para secretos + deploy de functions.
4. Ejecutar.

## 3) Qué despliega

- Migración base: `supabase/migrations/202604010001_initial_schema_and_rls.sql`
- Edge Functions:
  - `user-admin`
  - `mailer`
  - `email-inbound`

## 4) Validación rápida después de deploy

1. En Supabase Dashboard > Edge Functions confirmar que están activas.
2. Probar invitación de usuario desde Ajustes.
3. Probar reenvío de invitación.
4. Verificar logs en `outbound_email_log`.

## 5) Rollback mínimo recomendado

- Si falla una function: volver a desplegar la última versión estable desde el mismo workflow.
- Si falla migración: no avanzar; corregir SQL y volver a ejecutar `apply_db`.
