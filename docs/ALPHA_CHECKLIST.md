# Alpha Implementation Checklist

## Fase 1 - Entornos y secretos

- [x] Soporte para archivo de entorno por `--dart-define=ENV_FILE`.
- [x] Plantilla `/.env.alpha.example` creada.
- [x] Plantilla `/supabase/.env.example` creada para Edge Functions cloud.
- [x] `.gitignore` endurecido para bloquear `.env.*` y artefactos temporales.
- [ ] Rotar llaves expuestas (`RESEND_API_KEY`, publishable/anon keys comprometidas).
- [ ] Crear secretos en Vercel Project Settings.
- [ ] Crear secretos en Supabase Cloud (`supabase secrets set ...`).

## Fase 2 - Supabase Cloud staging

Guia detallada: `docs/BLOCK2_SUPABASE_STAGING.md`

- [ ] Aplicar `/supabase/schema.sql`.
- [ ] Aplicar `/supabase/rls.sql`.
- [ ] Desplegar funciones:
  - [ ] `user-admin`
  - [ ] `mailer`
  - [ ] `email-inbound`
- [ ] Validar flujo de invitación y reenvío en cloud.

## Fase 3 - Vercel Web Alpha

- [ ] Conectar repo a Vercel.
- [ ] Configurar build Flutter web.
- [ ] Build command:
  - `flutter build web --dart-define=ENV_FILE=.env.alpha`
- [ ] Definir `APP_PUBLIC_URL` final (dominio fijo).
- [ ] Configurar redirects permitidos en Supabase Auth.

## Smoke Test de salida a alfa

- [ ] Login/logout.
- [ ] Ajustes de perfil y contraseña.
- [ ] Invitar usuario.
- [ ] Reenviar invitación.
- [ ] Confirmar invitación y redirect correcto.
- [ ] Reset password.
- [ ] Cambiar rol / activar / desactivar usuario.
