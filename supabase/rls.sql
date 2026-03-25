-- RLS base. Sin login activo en MVP inicial, se deja documentado para activarlo.
alter table public.clients enable row level security;
alter table public.client_responsibles enable row level security;
alter table public.projects enable row level security;
alter table public.project_surveys enable row level security;
alter table public.quotes enable row level security;
alter table public.quote_items enable row level security;
alter table public.universes enable row level security;
alter table public.project_types enable row level security;
alter table public.concept_templates enable row level security;
alter table public.concept_attributes enable row level security;
alter table public.attribute_options enable row level security;
alter table public.concept_closures enable row level security;
alter table public.documents enable row level security;
alter table public.photos enable row level security;

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

-- Escritura del catalogo solo para admin autenticado.
drop policy if exists universes_insert_admin on public.universes;
create policy universes_insert_admin on public.universes for insert to authenticated with check (public.is_admin());
drop policy if exists universes_update_admin on public.universes;
create policy universes_update_admin on public.universes for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists universes_delete_admin on public.universes;
create policy universes_delete_admin on public.universes for delete to authenticated using (public.is_admin());

drop policy if exists project_types_insert_admin on public.project_types;
create policy project_types_insert_admin on public.project_types for insert to authenticated with check (public.is_admin());
drop policy if exists project_types_update_admin on public.project_types;
create policy project_types_update_admin on public.project_types for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists project_types_delete_admin on public.project_types;
create policy project_types_delete_admin on public.project_types for delete to authenticated using (public.is_admin());

drop policy if exists concept_templates_insert_admin on public.concept_templates;
create policy concept_templates_insert_admin on public.concept_templates for insert to authenticated with check (public.is_admin());
drop policy if exists concept_templates_update_admin on public.concept_templates;
create policy concept_templates_update_admin on public.concept_templates for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists concept_templates_delete_admin on public.concept_templates;
create policy concept_templates_delete_admin on public.concept_templates for delete to authenticated using (public.is_admin());

drop policy if exists concept_attributes_insert_admin on public.concept_attributes;
create policy concept_attributes_insert_admin on public.concept_attributes for insert to authenticated with check (public.is_admin());
drop policy if exists concept_attributes_update_admin on public.concept_attributes;
create policy concept_attributes_update_admin on public.concept_attributes for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists concept_attributes_delete_admin on public.concept_attributes;
create policy concept_attributes_delete_admin on public.concept_attributes for delete to authenticated using (public.is_admin());

drop policy if exists attribute_options_insert_admin on public.attribute_options;
create policy attribute_options_insert_admin on public.attribute_options for insert to authenticated with check (public.is_admin());
drop policy if exists attribute_options_update_admin on public.attribute_options;
create policy attribute_options_update_admin on public.attribute_options for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists attribute_options_delete_admin on public.attribute_options;
create policy attribute_options_delete_admin on public.attribute_options for delete to authenticated using (public.is_admin());

drop policy if exists concept_closures_insert_admin on public.concept_closures;
create policy concept_closures_insert_admin on public.concept_closures for insert to authenticated with check (public.is_admin());
drop policy if exists concept_closures_update_admin on public.concept_closures;
create policy concept_closures_update_admin on public.concept_closures for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists concept_closures_delete_admin on public.concept_closures;
create policy concept_closures_delete_admin on public.concept_closures for delete to authenticated using (public.is_admin());

-- Politicas ejemplo cuando se active auth:
-- create policy clients_read on public.clients for select to authenticated using (true);
-- create policy clients_write on public.clients for all to authenticated using (true) with check (true);
-- create policy client_responsibles_read on public.client_responsibles for select to authenticated using (true);
-- create policy client_responsibles_write on public.client_responsibles for all to authenticated using (true) with check (true);
-- create policy universes_read on public.universes for select to authenticated using (true);
-- create policy project_types_read on public.project_types for select to authenticated using (true);
-- create policy concept_templates_read on public.concept_templates for select to authenticated using (true);
-- create policy concept_attributes_read on public.concept_attributes for select to authenticated using (true);
-- create policy attribute_options_read on public.attribute_options for select to authenticated using (true);
-- create policy concept_closures_read on public.concept_closures for select to authenticated using (true);

-- Storage policies ejemplo cuando se active auth:
-- create policy docs_read on storage.objects for select to authenticated using (bucket_id = 'client-documents');
-- create policy docs_write on storage.objects for insert to authenticated with check (bucket_id = 'client-documents');
