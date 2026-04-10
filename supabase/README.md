# Supabase setup (REMA)

Runbook de staging completo: `docs/STAGING_RUNBOOK.md`

1. Crear proyecto en Supabase.
2. Ejecutar schema.sql en SQL Editor.
3. Ejecutar rls.sql en SQL Editor.
4. Copiar SUPABASE_URL y SUPABASE_ANON_KEY en .env.

## Modelo base

- clients: datos generales del cliente.
- client_responsibles: responsables por cliente para firmas y seguimiento. Cada cliente puede tener un supervisor y un gerente, con registro independiente y referencia a clients.
- projects: proyectos asociados al cliente.

## Catalogo dinamico de conceptos

Se agrego una capa de catalogo para estandarizar conceptos de obra en cotizaciones:

- universes
- project_types
- concept_closures
- concept_templates
- concept_attributes
- attribute_options

Cambios de compatibilidad:

- quotes ahora permite universe_id para restringir una cotizacion a un solo universo.
- quotes ahora permite project_type_id para fijar el tipo de proyecto a nivel cotizacion.
- quote_items conserva concept y agrega template_id + generated_data (jsonb) para conceptos dinamicos sin romper items legacy.

Nota:

- generated_data guarda el contexto de generacion (tipo de proyecto, accion, universo, atributos, unidad y precio base).
- El precio final se persiste en unit_price y line_total; no se recalcula historicos si cambia el catalogo.

### Seguridad del catalogo

- `rls.sql` define lectura de catalogo para `anon` y `authenticated`.
- Escritura de catalogo (`universes`, `project_types`, `concept_templates`, `concept_attributes`, `attribute_options`, `concept_closures`) es solo para usuarios `authenticated` con rol admin en JWT (`app_metadata.role`, `user_metadata.role` o arrays `roles`).

### Importador CSV (módulo Catálogo)

- Obligatorias: `universe`, `concept`, `unit`, `base_price`, `attribute`, `option`
- Opcionales: `project_type`, `base_description`
- Si `project_type` viene en la fila, reemplaza el tipo destino seleccionado en UI.

## Storage

- Bucket privado: client-documents
- Bucket privado: survey-photos
- Bucket privado: acta-files

## Gestion de usuarios (super-admin)

Se agrego la Edge Function `user-admin` para que solo el super-admin gestione usuarios sin exponer `service_role` en Flutter.

En el entorno actual, `invite_user` y `reset_password` ya no dependen del SMTP local de Supabase para la entrega final del correo: generan el action link con Supabase Auth y envian el email real por Resend.

Acciones disponibles (POST body):

- `list_users`
- `invite_user` (`email`, `role` = `staff|admin`)
- `update_role` (`user_id`, `role` = `staff|admin`)
- `set_active` (`user_id`, `is_active`)
- `reset_password` (`user_id`)

Variables de entorno requeridas en la function:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `OWNER_EMAIL` (opcional, default: `mvazquez@gruporemaa.com`)
- `RESEND_API_KEY` (para enviar invitaciones y reset por Resend)
- `RESEND_FROM_EMAIL` (remitente verificado en Resend)

Despliegue local (ejemplo):

1. En desarrollo local, servir functions con `--no-verify-jwt` para evitar fallos de verificacion JWT de la CLI con tokens ES256:
	`supabase functions serve --env-file supabase/.env.local --no-verify-jwt`
2. Confirmar que el owner tenga rol `super_admin` o email igual a `OWNER_EMAIL`.

## Quickstart alfa (Supabase Cloud)

1. Configurar variables de funciones usando `supabase/.env.example` como plantilla (no commitear secretos reales).
2. Cargar secretos en Supabase Cloud:

	`supabase secrets set --env-file supabase/.env.cloud`

3. Desplegar funciones:

	`supabase functions deploy user-admin`
	`supabase functions deploy mailer`
	`supabase functions deploy email-inbound`

4. Verificar endpoints desplegados en Cloud y luego probar:

	- invitacion de usuario
	- reenvio de invitacion
	- reset password

## Nota sobre cPanel y BanaHosting

Puedes mantener BanaHosting para otros sitios, pero para esta app conviene dejar backend y storage en Supabase por escalabilidad y menor mantenimiento.
Flutter web se puede publicar como estatico en cPanel, consumiendo Supabase por HTTPS.

## Email opcion C (Resend + Supabase)

Se agrego base tecnica para pipeline hibrido:

- Auth emails (validacion/reset) pueden seguir por Supabase SMTP apuntando a Resend.
- Correos transaccionales propios via `supabase/functions/mailer`.
- Captura inbound via webhook directo a `supabase/functions/email-inbound`.

### Nuevas tablas

- `public.outbound_email_log`: bitacora de envio de correos salientes.
- `public.inbound_email_events`: captura de correos/eventos entrantes.

### Nuevas Edge Functions

- `mailer`:
	- action: `send_custom`
	- requiere usuario autenticado con rol admin/super_admin
	- envia email con Resend API
	- registra resultado en `outbound_email_log`

- `email-inbound`:
	- recibe payload directo desde webhook de Resend
	- autentica por header `x-email-webhook-secret`
	- persiste payload normalizado en `inbound_email_events`

### Variables de entorno requeridas

En `supabase/.env.local`:

- `OWNER_EMAIL`
- `RESEND_API_KEY`
- `RESEND_FROM_EMAIL`
- `EMAIL_WEBHOOK_SECRET`

En Resend (webhook endpoint):

- URL del endpoint: `https://<PROJECT_REF>.supabase.co/functions/v1/email-inbound`
- Header: `x-email-webhook-secret` (mismo valor que `EMAIL_WEBHOOK_SECRET` en Supabase)

### Despliegue local sugerido

1. `supabase functions serve --env-file supabase/.env.local --no-verify-jwt`
3. Configurar webhook de Resend directo al endpoint Supabase: `/functions/v1/email-inbound`

Nota:

- En este proyecto, `mailer` y `user-admin` ya validan el usuario dentro de la function con `auth.getUser()`, asi que desactivar la pre-verificacion de la CLI en local no abre acceso anonimo real; solo evita el bug de compatibilidad JWT del runtime local.

### Seguridad recomendada

- No guardar API keys reales en git.
- Rotar inmediatamente cualquier key que se haya compartido fuera de un vault seguro.
- Agregar validacion de firma de Resend en `email-inbound` cuando habilites `svix`.
