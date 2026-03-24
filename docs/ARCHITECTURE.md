# Arquitectura propuesta y viabilidad

Esta arquitectura SI es viable para escalar, con un ajuste importante: iniciar simple por capas + modulos y migrar a dominio puro cuando crezcan equipos y reglas de negocio.

## Capa 1 - Configuracion y secretos

- Archivo local: .env
- Plantilla compartible: .env.example
- Carga centralizada: lib/core/config/env.dart
- Regla: nunca subir llaves reales al repositorio.

## Capa 2 - Estructura de carpetas

Inicio simple recomendado (aplicado):

- lib/core: tema, config, logging, widgets base
- lib/app: bootstrap y router
- lib/features/<modulo>/{presentation,data,domain}

Cuando migrar a estructura por dominio completa:

- Al superar 8-10 features activas.
- Al tener 2 o mas equipos tocando modulos en paralelo.
- Cuando aparezcan reglas compartidas entre cotizaciones, billing y proyectos.

## Capa 3 - Separacion de responsabilidades

- Router: solo en lib/app/router.dart
- UI: en presentation
- Integraciones externas: en data
- Reglas de negocio: en domain

Regla operativa: ninguna pantalla debe acceder directo a SDK externos.

## Capa 4 - Pagos y billing (Stripe)

Estado actual:

- Provider abstracto en billing/domain.
- Stub en billing/data para no acoplar UI a Stripe aun.
- Stub de webhook en supabase/stripe_webhook_stub.ts

Siguiente paso profesional:

- Webhook con firma valida.
- Tabla billing_events.
- Idempotencia por event_id.
- Reconciliacion de estados de suscripcion.

## Capa 5 - Logging y monitoreo

Aplicado:

- Logging JSON con evento + timestamp + payload.
- Punto unico en lib/core/logging/app_logger.dart

Metricas minimas para MVP:

- Tiempo de carga por pantalla.
- Errores por modulo.
- Tasa de guardado exitoso en formularios.
- Exitos/fallos en carga de documentos y fotos.

## Capa 6 - Tests

Aplicado:

- Widget tests de render y navegacion.
- Unit test de configuracion/env.

Que NO testear todavia en MVP:

- Pixel-perfect de toda la UI.
- Integraciones externas reales en cada corrida de CI.

## Hosting y backend

Tu stack actual: BanaHosting + cPanel + phpMyAdmin.

Recomendacion aplicada:

- Backend y storage en Supabase (PostgreSQL + buckets) por escalabilidad.
- Flutter web se puede publicar como estatico en cPanel.
- La app consumira Supabase por HTTPS.

## Modelo relacional inicial

- clients centraliza la informacion del cliente.
- client_responsibles modela las dos personas de firma por cliente: supervisor y gerente.
- La restriccion por rol evita duplicar supervisor o gerente para un mismo cliente y deja el dato listo para actas de entrega.

Esto te permite crecer sin rehacer backend cuando suba carga o volumen de archivos.
