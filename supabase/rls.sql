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
