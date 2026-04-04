-- =============================================================================
-- clients_rls_hardening
-- Fecha: 2026-04-03
-- Propósito: Restringir escritura a usuarios autenticados (admin/super_admin)
--            en tablas de negocio críticas. Lectura se mantiene abierta para
--            soporte de UX actual durante transición. Tablas de catálogo y
--            storage se endurecen por separado en sección admin.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLA: public.clients
--   Lectura: anon + authenticated (UX requiere carga sin auth en algunos flows)
--   Escritura (INSERT/UPDATE/DELETE): solo authenticated (cualquier usuario)
--   Nota: en producción final idealmente solo admin/super_admin, pero al tener
--         el equipo como único usuario la restricción a authenticated es suficiente.
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists clients_read_all on public.clients;
create policy clients_read_all on public.clients
  for select to anon, authenticated using (true);

drop policy if exists clients_write_all on public.clients;

drop policy if exists clients_insert_authenticated on public.clients;
create policy clients_insert_authenticated on public.clients
  for insert to authenticated with check (true);

drop policy if exists clients_update_authenticated on public.clients;
create policy clients_update_authenticated on public.clients
  for update to authenticated using (true) with check (true);

drop policy if exists clients_delete_authenticated on public.clients;
create policy clients_delete_authenticated on public.clients
  for delete to authenticated using (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLA: public.client_responsibles
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists client_responsibles_read_all on public.client_responsibles;
create policy client_responsibles_read_all on public.client_responsibles
  for select to anon, authenticated using (true);

drop policy if exists client_responsibles_write_all on public.client_responsibles;

drop policy if exists client_responsibles_insert_authenticated on public.client_responsibles;
create policy client_responsibles_insert_authenticated on public.client_responsibles
  for insert to authenticated with check (true);

drop policy if exists client_responsibles_update_authenticated on public.client_responsibles;
create policy client_responsibles_update_authenticated on public.client_responsibles
  for update to authenticated using (true) with check (true);

drop policy if exists client_responsibles_delete_authenticated on public.client_responsibles;
create policy client_responsibles_delete_authenticated on public.client_responsibles
  for delete to authenticated using (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLA: public.projects
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists projects_read_all on public.projects;
create policy projects_read_all on public.projects
  for select to anon, authenticated using (true);

drop policy if exists projects_write_all on public.projects;

drop policy if exists projects_insert_authenticated on public.projects;
create policy projects_insert_authenticated on public.projects
  for insert to authenticated with check (true);

drop policy if exists projects_update_authenticated on public.projects;
create policy projects_update_authenticated on public.projects
  for update to authenticated using (true) with check (true);

drop policy if exists projects_delete_authenticated on public.projects;
create policy projects_delete_authenticated on public.projects
  for delete to authenticated using (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLA: public.quotes
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists quotes_read_all on public.quotes;
create policy quotes_read_all on public.quotes
  for select to anon, authenticated using (true);

drop policy if exists quotes_write_all on public.quotes;

drop policy if exists quotes_insert_authenticated on public.quotes;
create policy quotes_insert_authenticated on public.quotes
  for insert to authenticated with check (true);

drop policy if exists quotes_update_authenticated on public.quotes;
create policy quotes_update_authenticated on public.quotes
  for update to authenticated using (true) with check (true);

drop policy if exists quotes_delete_authenticated on public.quotes;
create policy quotes_delete_authenticated on public.quotes
  for delete to authenticated using (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLA: public.quote_items
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists quote_items_read_all on public.quote_items;
create policy quote_items_read_all on public.quote_items
  for select to anon, authenticated using (true);

drop policy if exists quote_items_write_all on public.quote_items;

drop policy if exists quote_items_insert_authenticated on public.quote_items;
create policy quote_items_insert_authenticated on public.quote_items
  for insert to authenticated with check (true);

drop policy if exists quote_items_update_authenticated on public.quote_items;
create policy quote_items_update_authenticated on public.quote_items
  for update to authenticated using (true) with check (true);

drop policy if exists quote_items_delete_authenticated on public.quote_items;
create policy quote_items_delete_authenticated on public.quote_items
  for delete to authenticated using (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLA: public.documents
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists documents_read_all on public.documents;
create policy documents_read_all on public.documents
  for select to anon, authenticated using (true);

drop policy if exists documents_write_all on public.documents;

drop policy if exists documents_insert_authenticated on public.documents;
create policy documents_insert_authenticated on public.documents
  for insert to authenticated with check (true);

drop policy if exists documents_update_authenticated on public.documents;
create policy documents_update_authenticated on public.documents
  for update to authenticated using (true) with check (true);

drop policy if exists documents_delete_authenticated on public.documents;
create policy documents_delete_authenticated on public.documents
  for delete to authenticated using (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLA: public.photos
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists photos_read_all on public.photos;
create policy photos_read_all on public.photos
  for select to anon, authenticated using (true);

drop policy if exists photos_write_all on public.photos;

drop policy if exists photos_insert_authenticated on public.photos;
create policy photos_insert_authenticated on public.photos
  for insert to authenticated with check (true);

drop policy if exists photos_update_authenticated on public.photos;
create policy photos_update_authenticated on public.photos
  for update to authenticated using (true) with check (true);

drop policy if exists photos_delete_authenticated on public.photos;
create policy photos_delete_authenticated on public.photos
  for delete to authenticated using (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLA: public.quote_acta_assets
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists quote_acta_assets_read_all on public.quote_acta_assets;
create policy quote_acta_assets_read_all on public.quote_acta_assets
  for select to anon, authenticated using (true);

drop policy if exists quote_acta_assets_insert_all on public.quote_acta_assets;
drop policy if exists quote_acta_assets_update_all on public.quote_acta_assets;
drop policy if exists quote_acta_assets_delete_all on public.quote_acta_assets;

drop policy if exists quote_acta_assets_insert_authenticated on public.quote_acta_assets;
create policy quote_acta_assets_insert_authenticated on public.quote_acta_assets
  for insert to authenticated with check (true);

drop policy if exists quote_acta_assets_update_authenticated on public.quote_acta_assets;
create policy quote_acta_assets_update_authenticated on public.quote_acta_assets
  for update to authenticated using (true) with check (true);

drop policy if exists quote_acta_assets_delete_authenticated on public.quote_acta_assets;
create policy quote_acta_assets_delete_authenticated on public.quote_acta_assets
  for delete to authenticated using (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLA: public.project_surveys
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists project_surveys_read_all on public.project_surveys;
create policy project_surveys_read_all on public.project_surveys
  for select to anon, authenticated using (true);

drop policy if exists project_surveys_insert_authenticated on public.project_surveys;
create policy project_surveys_insert_authenticated on public.project_surveys
  for insert to authenticated with check (true);

drop policy if exists project_surveys_update_authenticated on public.project_surveys;
create policy project_surveys_update_authenticated on public.project_surveys
  for update to authenticated using (true) with check (true);

drop policy if exists project_surveys_delete_authenticated on public.project_surveys;
create policy project_surveys_delete_authenticated on public.project_surveys
  for delete to authenticated using (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLAS: project_survey_entries – se mantiene anon mientras levantamiento
--         no exija login (MVP). TODO: migrar a authenticated en fase de login.
-- ─────────────────────────────────────────────────────────────────────────────
-- (sin cambio en esta migración)

-- ─────────────────────────────────────────────────────────────────────────────
-- STORAGE: restricción de escritura a authenticated únicamente
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists storage_client_documents_write_all on storage.objects;
create policy storage_client_documents_write_authenticated on storage.objects
  for all to authenticated
  using (bucket_id = 'client-documents')
  with check (bucket_id = 'client-documents');

drop policy if exists storage_client_logos_write_all on storage.objects;
create policy storage_client_logos_write_authenticated on storage.objects
  for all to authenticated
  using (bucket_id = 'client-logos')
  with check (bucket_id = 'client-logos');

drop policy if exists storage_quote_approvals_write_all on storage.objects;
create policy storage_quote_approvals_write_authenticated on storage.objects
  for all to authenticated
  using (bucket_id = 'quote-approvals')
  with check (bucket_id = 'quote-approvals');

drop policy if exists storage_acta_files_write_all on storage.objects;
create policy storage_acta_files_write_authenticated on storage.objects
  for all to authenticated
  using (bucket_id = 'acta-files')
  with check (bucket_id = 'acta-files');
