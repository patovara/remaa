-- REMA Arquitectura - Esquema inicial escalable (PostgreSQL / Supabase)
create extension if not exists pgcrypto;

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  business_name text not null,
  rfc text,
  phone text,
  email text,
  address_line text,
  city text,
  state text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.client_responsibles (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  role text not null,
  title text,
  position text,
  full_name text not null,
  phone text,
  email text,
  contact_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint client_responsibles_role_check check (role in ('supervisor', 'gerente')),
  constraint client_responsibles_unique_role_per_client unique (client_id, role)
);

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  code text not null,
  name text not null,
  manager_name text,
  site_address text,
  status text not null default 'draft',
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.project_surveys (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  unit_measure text,
  estimated_area numeric(12,2),
  estimated_cost numeric(14,2),
  latitude numeric(10,7),
  longitude numeric(10,7),
  survey_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.quotes (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  quote_number text not null,
  status text not null default 'draft',
  subtotal numeric(14,2) not null default 0,
  tax numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  valid_until date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (quote_number)
);

create table if not exists public.quote_items (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid not null references public.quotes(id) on delete cascade,
  concept text not null,
  unit text,
  quantity numeric(12,2) not null default 0,
  unit_price numeric(14,2) not null default 0,
  line_total numeric(14,2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.documents (
  id uuid primary key default gen_random_uuid(),
  client_id uuid references public.clients(id) on delete cascade,
  project_id uuid references public.projects(id) on delete cascade,
  bucket_name text not null,
  object_path text not null,
  mime_type text,
  file_size_bytes bigint,
  original_name text,
  created_at timestamptz not null default now(),
  constraint documents_target_check check (client_id is not null or project_id is not null)
);

create table if not exists public.photos (
  id uuid primary key default gen_random_uuid(),
  project_survey_id uuid not null references public.project_surveys(id) on delete cascade,
  bucket_name text not null,
  object_path text not null,
  caption text,
  latitude numeric(10,7),
  longitude numeric(10,7),
  taken_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id bigserial primary key,
  event_name text not null,
  entity_type text,
  entity_id text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_projects_client_id on public.projects(client_id);
create index if not exists idx_client_responsibles_client_id on public.client_responsibles(client_id);
create index if not exists idx_project_surveys_project_id on public.project_surveys(project_id);
create index if not exists idx_quotes_project_id on public.quotes(project_id);
create index if not exists idx_quote_items_quote_id on public.quote_items(quote_id);
create index if not exists idx_documents_client_id on public.documents(client_id);
create index if not exists idx_documents_project_id on public.documents(project_id);
create index if not exists idx_photos_project_survey_id on public.photos(project_survey_id);

insert into storage.buckets (id, name, public)
values ('client-documents', 'client-documents', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('survey-photos', 'survey-photos', false)
on conflict (id) do nothing;
