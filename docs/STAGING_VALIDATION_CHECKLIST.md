# Staging Validation Checklist

## Auth

- [ ] Login exitoso con usuario staging.
- [ ] Invitacion enviada y aceptada desde link staging.
- [ ] Reset password con link staging.
- [ ] Redirect final queda en `https://staging-remaa.vercel.app`.

## Email / Resend

- [ ] `user-admin` envia invitacion.
- [ ] `mailer` envia correo transaccional.
- [ ] `email-inbound` registra evento.

## Database / RLS

- [ ] Tablas esperadas presentes en staging.
- [ ] Policies RLS aplicadas.
- [ ] Escrituras permitidas solo por paths autorizados.

## App flow

- [ ] Alta de cliente.
- [ ] Edicion de cliente.
- [ ] Alta de cotizacion.
- [ ] Edicion de conceptos.
- [ ] Descarga / share de PDF.

## Deploy

- [ ] Push a `develop` despliega staging automaticamente.
- [ ] Push a `main` NO afecta staging.
- [ ] Secrets de staging y produccion estan separados.
