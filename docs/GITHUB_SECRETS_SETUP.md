# GitHub Secrets Setup

## Secrets para workflow Supabase Staging Deploy

Crear estos secrets en GitHub:

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

## Valores esperados

- `SUPABASE_PROJECT_REF_STAGING`
  - solo el project ref, por ejemplo: `abcxyz123def`
- `SUPABASE_URL_STAGING`
  - URL completa del proyecto cloud, por ejemplo: `https://abcxyz123def.supabase.co`
- `APP_PUBLIC_URL_STAGING`
  - dominio web publico de staging/alfa, por ejemplo: `https://alfa.tu-dominio.com`
- `OWNER_EMAIL`
  - correo del super-admin real del sistema

## Secrets adicionales para Vercel

Estos van en Vercel Project Settings > Environment Variables:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `APP_PUBLIC_URL`

Nota: para el webhook inbound de Resend ya no se usa relay en Vercel. El webhook debe apuntar directo a Supabase `email-inbound`.

## Recomendacion operativa

1. Usa los mismos valores de dominio publico entre GitHub y Vercel.
2. No reutilices secretos locales comprometidos; rota llaves antes de staging.
3. Si cambias `APP_PUBLIC_URL`, actualiza tambien los redirects permitidos en Supabase Auth.
