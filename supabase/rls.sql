-- RLS base. Sin login activo en MVP inicial, se deja documentado para activarlo.
alter table public.clients enable row level security;
alter table public.client_responsibles enable row level security;
alter table public.projects enable row level security;
alter table public.project_surveys enable row level security;
alter table public.project_survey_entries enable row level security;
alter table public.quotes enable row level security;
alter table public.quote_acta_assets enable row level security;
alter table public.quote_items enable row level security;
alter table public.universes enable row level security;
alter table public.project_types enable row level security;
alter table public.concept_templates enable row level security;
alter table public.concept_attributes enable row level security;
alter table public.attribute_options enable row level security;
alter table public.concept_closures enable row level security;
alter table public.documents enable row level security;
alter table public.photos enable row level security;
alter table public.user_admin_audit enable row level security;
alter table public.outbound_email_log enable row level security;
alter table public.inbound_email_events enable row level security;

-- Admin helper: requiere JWT autenticado con role=admin (app_metadata o user_metadata).
create or replace function public.is_admin()
returns boolean
language sql
stable
as $$
	select coalesce(
		lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')) = 'admin'
		or lower(coalesce(auth.jwt() -> 'user_metadata' ->> 'role', '')) = 'admin'
		or exists (
			select 1
			from jsonb_array_elements_text(coalesce(auth.jwt() -> 'app_metadata' -> 'roles', '[]'::jsonb)) as r(value)
			where lower(r.value) = 'admin'
		)
		or exists (
			select 1
			from jsonb_array_elements_text(coalesce(auth.jwt() -> 'user_metadata' -> 'roles', '[]'::jsonb)) as r(value)
			where lower(r.value) = 'admin'
		),
		false
	);
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
as $$
	select coalesce(
		lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')) in ('super_admin', 'superadmin', 'owner')
		or lower(coalesce(auth.jwt() -> 'user_metadata' ->> 'role', '')) in ('super_admin', 'superadmin', 'owner')
		or lower(coalesce(auth.jwt() ->> 'email', '')) = 'mvazquez@gruporemaa.com',
		false
	);
$$;

drop policy if exists user_admin_audit_read_super_admin on public.user_admin_audit;
create policy user_admin_audit_read_super_admin on public.user_admin_audit
for select to authenticated
using (public.is_super_admin());

drop policy if exists user_admin_audit_insert_service on public.user_admin_audit;
create policy user_admin_audit_insert_service on public.user_admin_audit
for insert to service_role
with check (true);

drop policy if exists outbound_email_log_read_super_admin on public.outbound_email_log;
create policy outbound_email_log_read_super_admin on public.outbound_email_log
for select to authenticated
using (public.is_super_admin());

drop policy if exists outbound_email_log_insert_service on public.outbound_email_log;
create policy outbound_email_log_insert_service on public.outbound_email_log
for insert to service_role
with check (true);

drop policy if exists inbound_email_events_read_super_admin on public.inbound_email_events;
create policy inbound_email_events_read_super_admin on public.inbound_email_events
for select to authenticated
using (public.is_super_admin());

drop policy if exists inbound_email_events_insert_service on public.inbound_email_events;
create policy inbound_email_events_insert_service on public.inbound_email_events
for insert to service_role
with check (true);

-- Lectura del catalogo abierta para anon/authenticated (MVP sin login).
drop policy if exists universes_read_all on public.universes;
create policy universes_read_all on public.universes for select to anon, authenticated using (true);

drop policy if exists project_types_read_all on public.project_types;
create policy project_types_read_all on public.project_types for select to anon, authenticated using (true);

drop policy if exists concept_templates_read_all on public.concept_templates;
create policy concept_templates_read_all on public.concept_templates for select to anon, authenticated using (true);

drop policy if exists concept_attributes_read_all on public.concept_attributes;
create policy concept_attributes_read_all on public.concept_attributes for select to anon, authenticated using (true);

drop policy if exists attribute_options_read_all on public.attribute_options;
create policy attribute_options_read_all on public.attribute_options for select to anon, authenticated using (true);

drop policy if exists concept_closures_read_all on public.concept_closures;
create policy concept_closures_read_all on public.concept_closures for select to anon, authenticated using (true);

-- Read: authenticated users can see surveys they captured, or historical orphaned surveys (NULL owner) for admin use
drop policy if exists project_survey_entries_read_own on public.project_survey_entries;
create policy project_survey_entries_read_own on public.project_survey_entries
for select to authenticated using (captured_by_user_id = auth.uid());

drop policy if exists project_survey_entries_read_null on public.project_survey_entries;
create policy project_survey_entries_read_null on public.project_survey_entries
for select to authenticated using (captured_by_user_id is null);

-- Insert: authenticated users can insert, must set captured_by_user_id to their own user id
drop policy if exists project_survey_entries_insert_own on public.project_survey_entries;
create policy project_survey_entries_insert_own on public.project_survey_entries
for insert to authenticated with check (captured_by_user_id = auth.uid());

-- Update: authenticated users can update only their own surveys
drop policy if exists project_survey_entries_update_own on public.project_survey_entries;
create policy project_survey_entries_update_own on public.project_survey_entries
for update to authenticated using (captured_by_user_id = auth.uid()) with check (captured_by_user_id = auth.uid());

-- Delete: authenticated users can delete only their own surveys
drop policy if exists project_survey_entries_delete_own on public.project_survey_entries;
create policy project_survey_entries_delete_own on public.project_survey_entries
for delete to authenticated using (captured_by_user_id = auth.uid());

drop policy if exists clients_read_all on public.clients;
create policy clients_read_all on public.clients
for select to anon, authenticated using (true);

drop policy if exists clients_write_all on public.clients;
create policy clients_write_all on public.clients
for all to anon, authenticated using (true) with check (true);

drop policy if exists client_responsibles_read_all on public.client_responsibles;
create policy client_responsibles_read_all on public.client_responsibles
for select to anon, authenticated using (true);

drop policy if exists client_responsibles_write_all on public.client_responsibles;
create policy client_responsibles_write_all on public.client_responsibles
for all to anon, authenticated using (true) with check (true);

drop policy if exists projects_read_all on public.projects;
create policy projects_read_all on public.projects
for select to anon, authenticated using (true);

drop policy if exists projects_write_all on public.projects;
create policy projects_write_all on public.projects
for all to anon, authenticated using (true) with check (true);

drop policy if exists quotes_read_all on public.quotes;
create policy quotes_read_all on public.quotes
for select to anon, authenticated using (true);

drop policy if exists quotes_write_all on public.quotes;
create policy quotes_write_all on public.quotes
for all to anon, authenticated using (true) with check (true);

drop policy if exists quote_items_read_all on public.quote_items;
create policy quote_items_read_all on public.quote_items
for select to anon, authenticated using (true);

drop policy if exists quote_items_write_all on public.quote_items;
create policy quote_items_write_all on public.quote_items
for all to anon, authenticated using (true) with check (true);

drop policy if exists documents_read_all on public.documents;
create policy documents_read_all on public.documents
for select to anon, authenticated using (true);

drop policy if exists documents_write_all on public.documents;
create policy documents_write_all on public.documents
for all to anon, authenticated using (true) with check (true);

drop policy if exists photos_read_all on public.photos;
create policy photos_read_all on public.photos
for select to anon, authenticated using (true);

drop policy if exists photos_write_all on public.photos;
create policy photos_write_all on public.photos
for all to anon, authenticated using (true) with check (true);

drop policy if exists quote_acta_assets_read_all on public.quote_acta_assets;
create policy quote_acta_assets_read_all on public.quote_acta_assets
for select to anon, authenticated using (true);

drop policy if exists quote_acta_assets_insert_all on public.quote_acta_assets;
create policy quote_acta_assets_insert_all on public.quote_acta_assets
for insert to anon, authenticated with check (true);

drop policy if exists quote_acta_assets_update_all on public.quote_acta_assets;
create policy quote_acta_assets_update_all on public.quote_acta_assets
for update to anon, authenticated using (true) with check (true);

drop policy if exists quote_acta_assets_delete_all on public.quote_acta_assets;
create policy quote_acta_assets_delete_all on public.quote_acta_assets
for delete to anon, authenticated using (true);

-- Escritura del catalogo abierta en entorno local MVP.
drop policy if exists universes_insert_admin on public.universes;
create policy universes_insert_admin on public.universes for insert to anon, authenticated with check (true);
drop policy if exists universes_update_admin on public.universes;
create policy universes_update_admin on public.universes for update to anon, authenticated using (true) with check (true);
drop policy if exists universes_delete_admin on public.universes;
create policy universes_delete_admin on public.universes for delete to anon, authenticated using (true);

drop policy if exists project_types_insert_admin on public.project_types;
create policy project_types_insert_admin on public.project_types for insert to anon, authenticated with check (true);
drop policy if exists project_types_update_admin on public.project_types;
create policy project_types_update_admin on public.project_types for update to anon, authenticated using (true) with check (true);
drop policy if exists project_types_delete_admin on public.project_types;
create policy project_types_delete_admin on public.project_types for delete to anon, authenticated using (true);

drop policy if exists concept_templates_insert_admin on public.concept_templates;
create policy concept_templates_insert_admin on public.concept_templates for insert to anon, authenticated with check (true);
drop policy if exists concept_templates_update_admin on public.concept_templates;
create policy concept_templates_update_admin on public.concept_templates for update to anon, authenticated using (true) with check (true);
drop policy if exists concept_templates_delete_admin on public.concept_templates;
create policy concept_templates_delete_admin on public.concept_templates for delete to anon, authenticated using (true);

drop policy if exists concept_attributes_insert_admin on public.concept_attributes;
create policy concept_attributes_insert_admin on public.concept_attributes for insert to anon, authenticated with check (true);
drop policy if exists concept_attributes_update_admin on public.concept_attributes;
create policy concept_attributes_update_admin on public.concept_attributes for update to anon, authenticated using (true) with check (true);
drop policy if exists concept_attributes_delete_admin on public.concept_attributes;
create policy concept_attributes_delete_admin on public.concept_attributes for delete to anon, authenticated using (true);

drop policy if exists attribute_options_insert_admin on public.attribute_options;
create policy attribute_options_insert_admin on public.attribute_options for insert to anon, authenticated with check (true);
drop policy if exists attribute_options_update_admin on public.attribute_options;
create policy attribute_options_update_admin on public.attribute_options for update to anon, authenticated using (true) with check (true);
drop policy if exists attribute_options_delete_admin on public.attribute_options;
create policy attribute_options_delete_admin on public.attribute_options for delete to anon, authenticated using (true);

drop policy if exists concept_closures_insert_admin on public.concept_closures;
create policy concept_closures_insert_admin on public.concept_closures for insert to anon, authenticated with check (true);
drop policy if exists concept_closures_update_admin on public.concept_closures;
create policy concept_closures_update_admin on public.concept_closures for update to anon, authenticated using (true) with check (true);
drop policy if exists concept_closures_delete_admin on public.concept_closures;
create policy concept_closures_delete_admin on public.concept_closures for delete to anon, authenticated using (true);

-- Politicas ejemplo cuando se active auth:
-- create policy universes_read on public.universes for select to authenticated using (true);
-- create policy project_types_read on public.project_types for select to authenticated using (true);
-- create policy concept_templates_read on public.concept_templates for select to authenticated using (true);
-- create policy concept_attributes_read on public.concept_attributes for select to authenticated using (true);
-- create policy attribute_options_read on public.attribute_options for select to authenticated using (true);
-- create policy concept_closures_read on public.concept_closures for select to authenticated using (true);

-- Storage policies ejemplo cuando se active auth:
-- create policy docs_read on storage.objects for select to authenticated using (bucket_id = 'client-documents');
-- create policy docs_write on storage.objects for insert to authenticated with check (bucket_id = 'client-documents');

drop policy if exists storage_client_documents_read_all on storage.objects;
create policy storage_client_documents_read_all on storage.objects
for select to anon, authenticated using (bucket_id = 'client-documents');

drop policy if exists storage_client_documents_write_all on storage.objects;
create policy storage_client_documents_write_all on storage.objects
for all to anon, authenticated
using (bucket_id = 'client-documents')
with check (bucket_id = 'client-documents');

drop policy if exists storage_client_logos_read_all on storage.objects;
create policy storage_client_logos_read_all on storage.objects
for select to anon, authenticated using (bucket_id = 'client-logos');

drop policy if exists storage_client_logos_write_all on storage.objects;
create policy storage_client_logos_write_all on storage.objects
for all to anon, authenticated
using (bucket_id = 'client-logos')
with check (bucket_id = 'client-logos');

drop policy if exists storage_survey_photos_read_all on storage.objects;
create policy storage_survey_photos_read_all on storage.objects
for select to anon, authenticated using (bucket_id = 'survey-photos');

drop policy if exists storage_survey_photos_write_all on storage.objects;
create policy storage_survey_photos_write_all on storage.objects
for all to anon, authenticated
using (bucket_id = 'survey-photos')
with check (bucket_id = 'survey-photos');

drop policy if exists storage_quote_approvals_read_all on storage.objects;
create policy storage_quote_approvals_read_all on storage.objects
for select to anon, authenticated using (bucket_id = 'quote-approvals');

drop policy if exists storage_quote_approvals_write_all on storage.objects;
create policy storage_quote_approvals_write_all on storage.objects
for all to anon, authenticated
using (bucket_id = 'quote-approvals')
with check (bucket_id = 'quote-approvals');

drop policy if exists storage_acta_files_read_all on storage.objects;
create policy storage_acta_files_read_all on storage.objects
for select to anon, authenticated using (bucket_id = 'acta-files');

drop policy if exists storage_acta_files_write_all on storage.objects;
create policy storage_acta_files_write_all on storage.objects
for all to anon, authenticated
using (bucket_id = 'acta-files')
with check (bucket_id = 'acta-files');
