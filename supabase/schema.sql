-- REMA Arquitectura - Esquema inicial escalable (PostgreSQL / Supabase)
create extension if not exists pgcrypto;

create sequence if not exists public.project_key_seq start 1;

create or replace function public.next_project_key()
returns text
language plpgsql
security definer
as $$
declare
  seq_value bigint;
begin
  seq_value := nextval('public.project_key_seq');
  return 'PRJ' || lpad(seq_value::text, 3, '0');
end;
$$;

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  business_name text not null,
  contact_name text,
  rfc text,
  phone text,
  email text,
  address_line text,
  city text,
  state text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Validaciones de formato (aplicadas vía migración 202604030001)
  constraint clients_business_name_notempty check (length(trim(business_name)) >= 2),
  constraint clients_rfc_format check (
    rfc is null
    or (upper(trim(rfc)) ~ '^[A-Z&\u00D1]{3,4}[0-9]{6}[A-Z0-9]{3}$' and length(trim(rfc)) in (12, 13))
  ),
  constraint clients_phone_e164 check (
    phone is null or phone ~ '^\+52[0-9]{10}$'
  ),
  constraint clients_address_format check (
    address_line is null
    or (length(trim(address_line)) between 10 and 255
        and trim(address_line) ~ '[A-Za-záéíóúüñÁÉÍÓÚÜÑ]'
        and trim(address_line) ~ '[0-9]')
  )
);

alter table public.clients
  add column if not exists sector_label text;

alter table public.clients
  add column if not exists logo_path text;

alter table public.clients
  add column if not exists logo_mime_type text;

alter table public.clients
  add column if not exists is_hidden boolean not null default false;

alter table public.clients
  add column if not exists hidden_at timestamptz;

create table if not exists public.client_sector_tags (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.client_sector_tags (name)
values
  ('HOTELERO'),
  ('COMERCIAL'),
  ('CONSTRUCTORA'),
  ('RESIDENCIAL')
on conflict (name) do nothing;

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
  updated_at timestamptz not null default now(),
  constraint projects_name_not_blank_check check (length(trim(name)) > 0)
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
  universe_id uuid,
  project_type_id uuid,
  quote_number text not null,
  status text not null default 'draft',
  approval_pdf_path text,
  approval_pdf_uploaded_at timestamptz,
  subtotal numeric(14,2) not null default 0,
  tax numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  valid_until date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (quote_number)
);

create table if not exists public.project_survey_entries (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  quote_id uuid references public.quotes(id) on delete set null,
  description text,
  evidence_paths text[] not null default '{}',
  evidence_meta jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint project_survey_entries_evidence_paths_max_two check (coalesce(cardinality(evidence_paths), 0) <= 2),
  constraint project_survey_entries_evidence_meta_is_array check (jsonb_typeof(evidence_meta) = 'array'),
  constraint project_survey_entries_evidence_meta_max_two check (jsonb_array_length(evidence_meta) <= 2)
);

create table if not exists public.quote_acta_assets (
  quote_id uuid primary key references public.quotes(id) on delete cascade,
  pdf_object_path text not null,
  pdf_file_name text not null,
  pdf_file_size_bytes integer not null default 0,
  photo_meta jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quote_acta_assets_photo_meta_is_array check (jsonb_typeof(photo_meta) = 'array')
);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'quotes_universe_project_type_pair_check'
      and conrelid = 'public.quotes'::regclass
  ) then
    alter table public.quotes
      add constraint quotes_universe_project_type_pair_check
      check (
        (universe_id is null and project_type_id is null)
        or
        (universe_id is not null and project_type_id is not null)
      );
  end if;
end;
$$;

alter table public.quotes
  add column if not exists universe_id uuid;

alter table public.quotes
  add column if not exists project_type_id uuid;

alter table public.quotes
  add column if not exists approval_pdf_path text;

alter table public.quotes
  add column if not exists approval_pdf_uploaded_at timestamptz;

alter table public.clients
  add column if not exists contact_name text;

create table if not exists public.universes (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'quotes_universe_id_fkey'
      and conrelid = 'public.quotes'::regclass
  ) then
    alter table public.quotes
      add constraint quotes_universe_id_fkey
      foreign key (universe_id) references public.universes(id) on delete restrict;
  end if;
end;
$$;

create table if not exists public.project_types (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  action_base text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'quotes_project_type_id_fkey'
      and conrelid = 'public.quotes'::regclass
  ) then
    alter table public.quotes
      add constraint quotes_project_type_id_fkey
      foreign key (project_type_id) references public.project_types(id) on delete restrict;
  end if;
end;
$$;

create or replace function public.validate_quote_item_template_scope()
returns trigger
language plpgsql
as $$
declare
  quote_universe_id uuid;
  quote_project_type_id uuid;
  template_universe_id uuid;
  template_project_type_id uuid;
begin
  if new.template_id is null then
    return new;
  end if;

  select q.universe_id, q.project_type_id
    into quote_universe_id, quote_project_type_id
  from public.quotes q
  where q.id = new.quote_id;

  if quote_universe_id is null or quote_project_type_id is null then
    raise exception 'La cotizacion % debe tener universo y tipo de proyecto para usar template.', new.quote_id;
  end if;

  select ct.universe_id, ct.project_type_id
    into template_universe_id, template_project_type_id
  from public.concept_templates ct
  where ct.id = new.template_id;

  if template_universe_id is null or template_project_type_id is null then
    raise exception 'Template % no valido para quote_item.', new.template_id;
  end if;

  if quote_universe_id <> template_universe_id or quote_project_type_id <> template_project_type_id then
    raise exception 'Template % fuera del universo/tipo de la cotizacion %.', new.template_id, new.quote_id;
  end if;

  return new;
end;
$$;

create table if not exists public.concept_closures (
  id uuid primary key default gen_random_uuid(),
  text text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.concept_templates (
  id uuid primary key default gen_random_uuid(),
  universe_id uuid not null references public.universes(id) on delete restrict,
  project_type_id uuid not null references public.project_types(id) on delete restrict,
  closure_id uuid not null references public.concept_closures(id) on delete restrict,
  name text not null,
  base_description text not null,
  default_unit text not null,
  base_price numeric(14,2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint concept_templates_unique_name_per_universe unique (universe_id, name)
);

create table if not exists public.concept_attributes (
  id uuid primary key default gen_random_uuid(),
  concept_template_id uuid not null references public.concept_templates(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint concept_attributes_unique_name_per_template unique (concept_template_id, name)
);

create table if not exists public.attribute_options (
  id uuid primary key default gen_random_uuid(),
  attribute_id uuid not null references public.concept_attributes(id) on delete cascade,
  value text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attribute_options_unique_value_per_attribute unique (attribute_id, value)
);

create table if not exists public.quote_items (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid not null references public.quotes(id) on delete cascade,
  template_id uuid references public.concept_templates(id) on delete set null,
  concept text not null,
  generated_data jsonb,
  unit text,
  quantity numeric(12,2) not null default 0,
  unit_price numeric(14,2) not null default 0,
  line_total numeric(14,2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quote_items_generated_data_is_object check (
    generated_data is null or jsonb_typeof(generated_data) = 'object'
  )
);

create or replace view public.concept_usage_view as
select
  q.universe_id,
  ct.id as concept_id,
  ct.name,
  count(*) as usage_count,
  max(qi.created_at) as last_used
from public.quote_items qi
join public.quotes q on q.id = qi.quote_id
join public.concept_templates ct on ct.id = qi.template_id
where qi.template_id is not null
  and q.universe_id is not null
group by q.universe_id, ct.id, ct.name;

grant select on public.concept_usage_view to anon, authenticated;

alter table public.quote_items
  add column if not exists template_id uuid;

alter table public.quote_items
  add column if not exists generated_data jsonb;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'quote_items_template_id_fkey'
      and conrelid = 'public.quote_items'::regclass
  ) then
    alter table public.quote_items
      add constraint quote_items_template_id_fkey
      foreign key (template_id) references public.concept_templates(id) on delete set null;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'quote_items_generated_data_is_object'
      and conrelid = 'public.quote_items'::regclass
  ) then
    alter table public.quote_items
      add constraint quote_items_generated_data_is_object check (
        generated_data is null or jsonb_typeof(generated_data) = 'object'
      );
  end if;
end;
$$;

drop trigger if exists trg_quote_items_validate_template_scope on public.quote_items;

create trigger trg_quote_items_validate_template_scope
before insert or update of quote_id, template_id
on public.quote_items
for each row
execute function public.validate_quote_item_template_scope();

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
create index if not exists idx_project_survey_entries_project_id on public.project_survey_entries(project_id);
create index if not exists idx_quotes_project_id on public.quotes(project_id);
create index if not exists idx_quotes_universe_id on public.quotes(universe_id);
create index if not exists idx_quotes_project_type_id on public.quotes(project_type_id);
create index if not exists idx_quote_items_quote_id on public.quote_items(quote_id);
create index if not exists idx_quote_items_template_id on public.quote_items(template_id);
create index if not exists idx_concept_templates_universe_id on public.concept_templates(universe_id);
create index if not exists idx_concept_templates_project_type_id on public.concept_templates(project_type_id);
create index if not exists idx_concept_templates_closure_id on public.concept_templates(closure_id);
create index if not exists idx_concept_attributes_template_id on public.concept_attributes(concept_template_id);
create index if not exists idx_attribute_options_attribute_id on public.attribute_options(attribute_id);
create index if not exists idx_documents_client_id on public.documents(client_id);
create index if not exists idx_documents_project_id on public.documents(project_id);
create index if not exists idx_photos_project_survey_id on public.photos(project_survey_id);

insert into public.universes (name)
values
  ('Vidrio/Aluminio'),
  ('Recubrimientos'),
  ('Acero'),
  ('Paneles')
on conflict (name) do nothing;

insert into public.project_types (name, action_base)
values
  ('Mantenimiento', 'SUMINISTRAR Y APLICAR'),
  ('Remodelacion', 'SUMINISTRAR E INSTALAR'),
  ('Construccion', 'DEMOLER Y RETIRAR')
on conflict (name) do update set
  action_base = excluded.action_base,
  updated_at = now();

insert into public.concept_closures (text)
values
  ('INCLUYE MATERIAL DE PRIMERA CALIDAD, CORTES, DESPERDICIOS, ACARREOS, MANIOBRAS, MANO DE OBRA ESPECIALIZADA Y TODO LO NECESARIO PARA SU CORRECTA EJECUCION.'),
  ('INCLUYE HERRAMIENTA, EQUIPO DE SEGURIDAD, NIVELACION, LIMPIEZA FINAL Y RETIRO DE SOBRANTES.')
on conflict (text) do nothing;

insert into public.concept_templates (
  universe_id,
  project_type_id,
  closure_id,
  name,
  base_description,
  default_unit,
  base_price
)
select
  u.id,
  pt.id,
  cc.id,
  t.name,
  t.base_description,
  t.default_unit,
  t.base_price
from (
  values
    (
      'Recubrimientos',
      'Mantenimiento',
      'Pintura vinilica',
      'pintura vinilica marca {marca}, acabado {acabado}, a {manos} manos sobre superficie preparada',
      'm2',
      120.00::numeric
    ),
    (
      'Vidrio/Aluminio',
      'Remodelacion',
      'Canceleria de aluminio',
      'canceleria de aluminio serie {serie}, color {color}, con vidrio {vidrio} y herrajes completos',
      'm2',
      1650.00::numeric
    ),
    (
      'Acero',
      'Construccion',
      'Estructura metalica ligera',
      'estructura metalica con perfil tubular calibre {calibre}, soldadura {soldadura} y acabado {acabado}',
      'kg',
      58.00::numeric
    ),
    (
      'Paneles',
      'Remodelacion',
      'Panel de yeso',
      'sistema de panel de yeso tipo {tipo_panel}, espesor {espesor}, con estructura {estructura} y acabado {acabado}',
      'm2',
      290.00::numeric
    )
) as t(universe_name, project_type_name, name, base_description, default_unit, base_price)
join public.universes u on u.name = t.universe_name
join public.project_types pt on pt.name = t.project_type_name
join public.concept_closures cc on cc.text = 'INCLUYE MATERIAL DE PRIMERA CALIDAD, CORTES, DESPERDICIOS, ACARREOS, MANIOBRAS, MANO DE OBRA ESPECIALIZADA Y TODO LO NECESARIO PARA SU CORRECTA EJECUCION.'
on conflict (universe_id, name) do update set
  project_type_id = excluded.project_type_id,
  closure_id = excluded.closure_id,
  base_description = excluded.base_description,
  default_unit = excluded.default_unit,
  base_price = excluded.base_price,
  updated_at = now();

insert into public.concept_attributes (concept_template_id, name)
select
  ct.id,
  attrs.name
from public.concept_templates ct
join (
  values
    ('Pintura vinilica', 'marca'),
    ('Pintura vinilica', 'acabado'),
    ('Pintura vinilica', 'manos'),
    ('Canceleria de aluminio', 'serie'),
    ('Canceleria de aluminio', 'color'),
    ('Canceleria de aluminio', 'vidrio'),
    ('Estructura metalica ligera', 'calibre'),
    ('Estructura metalica ligera', 'soldadura'),
    ('Estructura metalica ligera', 'acabado'),
    ('Panel de yeso', 'tipo_panel'),
    ('Panel de yeso', 'espesor'),
    ('Panel de yeso', 'estructura'),
    ('Panel de yeso', 'acabado')
) as attrs(template_name, name)
  on attrs.template_name = ct.name
on conflict (concept_template_id, name) do nothing;

insert into public.attribute_options (attribute_id, value)
select
  ca.id,
  opts.value
from public.concept_attributes ca
join public.concept_templates ct on ct.id = ca.concept_template_id
join (
  values
    ('Pintura vinilica', 'marca', 'Comex'),
    ('Pintura vinilica', 'marca', 'Berel'),
    ('Pintura vinilica', 'marca', 'Sherwin Williams'),
    ('Pintura vinilica', 'acabado', 'Mate'),
    ('Pintura vinilica', 'acabado', 'Satinado'),
    ('Pintura vinilica', 'acabado', 'Semibrillante'),
    ('Pintura vinilica', 'manos', '1'),
    ('Pintura vinilica', 'manos', '2'),
    ('Pintura vinilica', 'manos', '3'),
    ('Canceleria de aluminio', 'serie', '70'),
    ('Canceleria de aluminio', 'serie', '80'),
    ('Canceleria de aluminio', 'serie', 'Eurovent'),
    ('Canceleria de aluminio', 'color', 'Natural'),
    ('Canceleria de aluminio', 'color', 'Negro'),
    ('Canceleria de aluminio', 'color', 'Blanco'),
    ('Canceleria de aluminio', 'vidrio', 'Claro 6mm'),
    ('Canceleria de aluminio', 'vidrio', 'Filtrasol 6mm'),
    ('Canceleria de aluminio', 'vidrio', 'Templado 9mm'),
    ('Estructura metalica ligera', 'calibre', '14'),
    ('Estructura metalica ligera', 'calibre', '16'),
    ('Estructura metalica ligera', 'soldadura', 'MIG'),
    ('Estructura metalica ligera', 'soldadura', 'Electrodo'),
    ('Estructura metalica ligera', 'acabado', 'Primer anticorrosivo'),
    ('Estructura metalica ligera', 'acabado', 'Esmalte alquidalico'),
    ('Panel de yeso', 'tipo_panel', 'STD'),
    ('Panel de yeso', 'tipo_panel', 'RH'),
    ('Panel de yeso', 'tipo_panel', 'RF'),
    ('Panel de yeso', 'espesor', '1/2"'),
    ('Panel de yeso', 'espesor', '5/8"'),
    ('Panel de yeso', 'estructura', 'Canal y poste 3 5/8"'),
    ('Panel de yeso', 'estructura', 'Canal y poste 6"'),
    ('Panel de yeso', 'acabado', 'Juntas con cinta y compuesto'),
    ('Panel de yeso', 'acabado', 'Listo para pintura')
) as opts(template_name, attribute_name, value)
  on opts.template_name = ct.name and opts.attribute_name = ca.name
on conflict (attribute_id, value) do nothing;

insert into storage.buckets (id, name, public)
values ('client-documents', 'client-documents', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('client-logos', 'client-logos', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('survey-photos', 'survey-photos', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('quote-approvals', 'quote-approvals', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('acta-files', 'acta-files', false)
on conflict (id) do nothing;

create table if not exists public.user_admin_audit (
  id bigint generated always as identity primary key,
  actor_user_id uuid not null,
  actor_email text not null,
  target_user_id uuid not null,
  target_email text not null,
  action text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists user_admin_audit_actor_idx on public.user_admin_audit (actor_user_id);
create index if not exists user_admin_audit_target_idx on public.user_admin_audit (target_user_id);
create index if not exists user_admin_audit_created_idx on public.user_admin_audit (created_at desc);

create table if not exists public.outbound_email_log (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid,
  actor_email text,
  to_email text not null,
  subject text not null,
  template_key text,
  provider text not null default 'resend',
  provider_message_id text,
  status text not null default 'queued',
  payload jsonb not null default '{}'::jsonb,
  error_text text,
  created_at timestamptz not null default now(),
  constraint outbound_email_log_status_check
    check (status in ('queued', 'sent', 'failed'))
);

create index if not exists outbound_email_log_created_idx
  on public.outbound_email_log (created_at desc);
create index if not exists outbound_email_log_to_email_idx
  on public.outbound_email_log (to_email);

create table if not exists public.inbound_email_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'resend',
  message_id text,
  from_email text,
  to_email text,
  subject text,
  text_body text,
  html_body text,
  raw_payload jsonb not null default '{}'::jsonb,
  received_at timestamptz not null default now(),
  processed boolean not null default false,
  processed_at timestamptz
);

create index if not exists inbound_email_events_received_idx
  on public.inbound_email_events (received_at desc);
create index if not exists inbound_email_events_message_idx
  on public.inbound_email_events (message_id);
