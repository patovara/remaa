-- RLS base. Sin login activo en MVP inicial, se deja documentado para activarlo.
alter table public.clients enable row level security;
alter table public.client_responsibles enable row level security;
alter table public.projects enable row level security;
alter table public.project_surveys enable row level security;
alter table public.quotes enable row level security;
alter table public.quote_items enable row level security;
alter table public.documents enable row level security;
alter table public.photos enable row level security;

-- Politicas ejemplo cuando se active auth:
-- create policy clients_read on public.clients for select to authenticated using (true);
-- create policy clients_write on public.clients for all to authenticated using (true) with check (true);
-- create policy client_responsibles_read on public.client_responsibles for select to authenticated using (true);
-- create policy client_responsibles_write on public.client_responsibles for all to authenticated using (true) with check (true);

-- Storage policies ejemplo cuando se active auth:
-- create policy docs_read on storage.objects for select to authenticated using (bucket_id = 'client-documents');
-- create policy docs_write on storage.objects for insert to authenticated with check (bucket_id = 'client-documents');
