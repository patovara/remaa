# Supabase setup (REMA)

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

## Nota sobre cPanel y BanaHosting

Puedes mantener BanaHosting para otros sitios, pero para esta app conviene dejar backend y storage en Supabase por escalabilidad y menor mantenimiento.
Flutter web se puede publicar como estatico en cPanel, consumiendo Supabase por HTTPS.
