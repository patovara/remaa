# STAGING Implementation Runbook (REMAA)

Este runbook deja un entorno staging separado de produccion, reproducible y seguro.

## 0) Prerrequisitos

- Supabase CLI instalado y autenticado (`supabase login`).
- Vercel CLI instalado y autenticado (`vercel login`) o acceso a dashboard.
- Resend configurado con remitente valido.
- Rama `develop` existente en git.

## 1) Crear proyecto Supabase staging

1. Crear proyecto nuevo en Supabase Dashboard:
   - Nombre: `remaa-staging`
   - Region: misma que produccion (para latencia similar)
2. Guardar:
   - `PROJECT_REF_STAGING`
   - `DB_PASSWORD_STAGING`
   - `SUPABASE_URL_STAGING`
   - `SUPABASE_ANON_KEY_STAGING`
   - `SUPABASE_SERVICE_ROLE_KEY_STAGING`

## 2) Clonar esquema de produccion a staging

### Opcion A (exacta desde produccion)

```bash
PROD_PROJECT_REF=<prod_ref> PROD_DB_PASSWORD=<prod_db_password> ./scripts/staging/01_dump_prod_schema.sh
STAGING_DB_URL='postgresql://postgres:<pwd>@db.<staging_ref>.supabase.co:5432/postgres' ./scripts/staging/02_apply_schema_to_staging.sh
```

Resultado esperado:
- Tablas, indices, constraints, funciones, triggers y policies aplicadas en staging.

### Opcion B (baseline por migraciones del repo)

```bash
supabase link --project-ref <staging_ref> --password <staging_db_password>
supabase db push
```

## 3) Configurar Auth en staging

En Supabase Dashboard -> Authentication -> URL Configuration:

- Site URL: `https://staging-remaa.vercel.app`
- Redirect URLs:
  - `https://staging-remaa.vercel.app/*`
  - `http://localhost:3000/*`

Verificar Email templates / links para que usen dominio staging.

## 4) Configurar Vercel staging

Recomendado:
- `main` -> produccion
- `develop` -> staging

Pasos:
1. Crear proyecto Vercel para staging o usar Preview con alias fijo.
2. Configurar dominio/alias: `staging-remaa.vercel.app`.
3. Build Flutter web:
   - Build command: `flutter build web --dart-define=ENV_FILE=.env.staging`
   - Output: `build/web`
4. Conectar deploy automatico para `develop`.

## 5) Variables de entorno

### Frontend (Vercel - Staging)

Usar `.env.staging.example` como plantilla. Variables requeridas:

- `APP_ENV=staging`
- `APP_PUBLIC_URL=https://staging-remaa.vercel.app`
- `SUPABASE_URL=<staging_url>`
- `SUPABASE_ANON_KEY=<staging_anon_or_publishable_key>`
- `ENABLE_BILLING=false`

### Frontend (Vercel - Production)

- `APP_ENV=prod`
- `APP_PUBLIC_URL=<dominio_prod>`
- `SUPABASE_URL=<prod_url>`
- `SUPABASE_ANON_KEY=<prod_anon_or_publishable_key>`

### Edge Functions (Supabase - Staging)

Copiar `supabase/.env.staging.example` a `supabase/.env.staging` y cargar secretos:

```bash
STAGING_PROJECT_REF=<staging_ref> STAGING_DB_PASSWORD=<staging_db_password> ./scripts/staging/03_set_supabase_staging_secrets.sh
```

## 6) Resend en staging

Checklist:
- `RESEND_API_KEY` cargada en secrets de Supabase staging.
- `RESEND_FROM_EMAIL` valida.
- `APP_PUBLIC_URL` de secrets apunta a staging.
- Webhook inbound configurado con `EMAIL_WEBHOOK_SECRET` de staging.

## 7) Flujo Git

- `main` -> produccion
- `develop` -> staging
- `feature/*` -> desarrollo

Proceso:
1. Crear feature branch.
2. Merge a `develop`.
3. Deploy automatico en staging.
4. Validacion funcional.
5. Merge de `develop` a `main` para produccion.

## 8) Migraciones SQL (regla operativa)

Regla: nunca cambios manuales directos en produccion.

Proceso:
1. Crear archivo versionado en `supabase/migrations/`.
2. Probar en local.
3. Aplicar en staging (`supabase db push`).
4. Validar.
5. Promover a produccion con el mismo archivo.

Ejemplo de migracion real (referencia):
- `supabase/snippets/example_migration_add_projects_status.sql`

## 9) Validacion funcional obligatoria en staging

1. Registro de usuario.
2. Invitacion por correo.
3. Login.
4. Reset password.
5. Alta y edicion de cliente.
6. Creacion de cotizacion.
7. Flujo completo hasta PDF.

## 10) Criterio de salida

Staging esta correcto si:
- no comparte DB/Auth/keys con produccion,
- auth y correos usan dominio staging,
- flujo funcional principal pasa completo,
- despliegue por `develop` funciona.
