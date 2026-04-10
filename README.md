# REMA App

Aplicacion Flutter multiplataforma (iOS, Android y Web) para flujo de levantamiento, cotizaciones, clientes, ajustes, nuevo cliente y presupuesto.

## Stack

- Flutter + Dart
- GoRouter
- Riverpod
- Supabase (PostgreSQL + Storage)

## Configuracion

1. Editar .env con tus valores reales:
	- SUPABASE_URL
	- SUPABASE_ANON_KEY
	- ENABLE_BILLING=false (por defecto apagado)
2. Para un entorno alfa/staging, crear .env.alpha usando .env.alpha.example como base.
3. Instalar dependencias:

```bash
flutter pub get
```

## Ejecutar

```bash
flutter run -d chrome
flutter run -d ios
flutter run -d android
```

Para correr con entorno alfa:

```bash
flutter run -d chrome --dart-define=ENV_FILE=.env.alpha
```

Para build web alfa (Vercel):

```bash
flutter build web --dart-define=ENV_FILE=.env.alpha
```

## Estrategia de alfa recomendada

- Frontend web en Vercel.
- Backend, Auth, BD y Storage en Supabase Cloud.
- Supabase local solo para desarrollo.
- Secrets reales en Vercel y Supabase Secrets; nunca en archivos versionados.

## Staging operativo

Runbook principal: `docs/STAGING_RUNBOOK.md`

Checklist de validacion: `docs/STAGING_VALIDATION_CHECKLIST.md`

Plantillas nuevas:

- `/.env.staging.example`
- `/supabase/.env.staging.example`

Scripts de staging:

- `scripts/staging/01_dump_prod_schema.sh`
- `scripts/staging/02_apply_schema_to_staging.sh`
- `scripts/staging/03_set_supabase_staging_secrets.sh`

Flujo de ramas:

- `main` -> produccion
- `develop` -> staging
- `feature/*` -> nuevas funcionalidades

## Tests y analisis

```bash
flutter analyze
flutter test
```

## Base de datos

Revisar carpeta supabase:

- schema.sql
- rls.sql
- stripe_webhook_stub.ts
- README.md

## Arquitectura

Documento: docs/ARCHITECTURE.md
