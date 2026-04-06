# Runbook de Invitaciones y Reset de Contrasena (Produccion)

## Objetivo
Estandarizar el flujo de invitacion y reset para evitar errores de sesion faltante y resolver incidentes rapidamente.

## Alcance
Aplica a:
- Flutter Web en Vercel
- Supabase Auth
- Edge Function user-admin
- Envio de correos via Resend

## Arquitectura del flujo
1. Super admin ejecuta accion desde Ajustes:
   - invite_user
   - resend_invite
   - reset_password
2. Edge Function user-admin genera action_link con Supabase.
3. user-admin transforma ese action_link a link directo de app con estos parametros:
   - mode (invite o reset)
   - type (invite o recovery)
   - token
4. Se envia correo con ese link directo de app.
5. Usuario abre la URL en /register.
6. Frontend verifica token con Supabase y crea sesion.
7. Usuario guarda nueva contrasena.
8. App redirige a login.

## URL esperada en correo
Formato esperado:
- https://remaa.vercel.app/register?mode=invite&type=invite&token=...
- https://remaa.vercel.app/register?mode=reset&type=recovery&token=...

No debe enviarse como URL final de uso:
- https://<project>.supabase.co/auth/v1/verify?... como link principal para usuario

## Configuracion requerida
1. Supabase Auth
- Site URL debe ser el dominio de produccion de la app.
- Redirect URLs deben incluir al menos:
  - https://remaa.vercel.app
  - https://remaa.vercel.app/register

2. Secretos en Edge Function user-admin
- SUPABASE_URL
- SUPABASE_ANON_KEY
- SUPABASE_SERVICE_ROLE_KEY
- APP_PUBLIC_URL
- RESEND_API_KEY
- RESEND_FROM_EMAIL
- OWNER_EMAIL

3. Frontend
- Debe soportar lectura de mode, type y token desde query params.
- Debe bloquear submit mientras prepara sesion.

## Checklist de operacion
### Antes de invitar
1. Confirmar que el usuario no existe en auth.users.
2. Confirmar que super admin tiene sesion activa.

### Enviar invitacion
1. Invitar desde Ajustes.
2. Confirmar mensaje de exito en UI.
3. Validar en outbound_email_log que se registro envio.

### Validar enlace emitido
1. Revisar ultimo registro de outbound_email_log.
2. Verificar que payload invite_app_link o recovery_app_link existe.
3. Verificar que el link contiene mode, type y token.
4. Verificar que no termina en # y que no depende de grants agregados por redirect.

## Prueba end-to-end obligatoria
1. Abrir navegador en modo incognito.
2. Abrir link de correo.
3. Completar contrasena y confirmar guardado.
4. Verificar redireccion a login.
5. Iniciar sesion con nueva contrasena.
6. Repetir para reset_password.

## Diagnostico rapido
### Sintoma: Auth session missing
Causas mas probables:
1. URL sin token o type.
2. Link viejo o expirado.
3. Frontend entro a /register sin query params.

Acciones:
1. Revisar la URL real abierta en navegador.
2. Validar que contiene mode, type y token.
3. Reenviar invitacion y usar solo el correo mas reciente.

### Sintoma: Click en correo abre /register sin parametros
Causa probable:
- Se envio link basado en verify redirect en lugar de link directo de app.

Acciones:
1. Verificar deploy activo de user-admin.
2. Revisar outbound_email_log y confirmar invite_app_link.
3. Reenviar invitacion.

### Sintoma: Invite funciona y reset no
Causa probable:
- mode o type incorrectos para recovery.

Acciones:
1. Verificar URL de reset: mode=reset y type=recovery.
2. Verificar que frontend mapea type recovery correctamente.

## Queries utiles para soporte
1. Ultimos envios de invitacion y reset:
select created_at, template_key, to_email,
       payload->>'invite_app_link' as invite_app_link,
       payload->>'recovery_app_link' as recovery_app_link,
       payload->>'invite_action_link' as invite_action_link,
       payload->>'recovery_action_link' as recovery_action_link,
       status
from public.outbound_email_log
where template_key in ('user_invite','password_reset')
order by created_at desc
limit 20;

2. Auditoria de acciones de admin:
select created_at, actor_email, target_email, action, payload
from public.user_admin_audit
where action in ('invite_user','resend_invite','reset_password')
order by created_at desc
limit 20;

## Rollback
Si una version rompe el flujo:
1. Volver temporalmente al ultimo deploy estable de user-admin.
2. Mantener frontend actual (si no rompe login).
3. Reenviar invitaciones nuevas (los links previos pueden no servir).

## Recomendaciones operativas
1. No reutilizar links antiguos.
2. Probar siempre en incognito para validar flujo real.
3. Mantener un usuario de prueba dedicado para smoke test diario.
4. Registrar en cada incidente:
   - URL recibida (sin exponer token completo en reportes)
   - timestamp
   - resultado en outbound_email_log
   - estado final de login
