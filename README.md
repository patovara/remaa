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
2. Instalar dependencias:

```bash
flutter pub get
```

## Ejecutar

```bash
flutter run -d chrome
flutter run -d ios
flutter run -d android
```

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
