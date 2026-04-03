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
