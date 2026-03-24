# Supabase setup (REMA)

1. Crear proyecto en Supabase.
2. Ejecutar schema.sql en SQL Editor.
3. Ejecutar rls.sql en SQL Editor.
4. Copiar SUPABASE_URL y SUPABASE_ANON_KEY en .env.

## Modelo base

- clients: datos generales del cliente.
- client_responsibles: responsables por cliente para firmas y seguimiento. Cada cliente puede tener un supervisor y un gerente, con registro independiente y referencia a clients.
- projects: proyectos asociados al cliente.

## Storage

- Bucket privado: client-documents
- Bucket privado: survey-photos

## Nota sobre cPanel y BanaHosting

Puedes mantener BanaHosting para otros sitios, pero para esta app conviene dejar backend y storage en Supabase por escalabilidad y menor mantenimiento.
Flutter web se puede publicar como estatico en cPanel, consumiendo Supabase por HTTPS.
