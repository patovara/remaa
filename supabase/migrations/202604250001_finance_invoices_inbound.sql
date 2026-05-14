-- Finanzas: ingesta automatica de facturas inbound (email-inbound)

create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  uuid_sat text not null unique,
  proveedor text not null,
  total numeric(14,2) not null,
  fecha timestamptz not null,
  xml_url text not null,
  pdf_url text,
  provider_rfc text,
  provider_client_id uuid references public.clients(id) on delete set null,
  inbound_email_event_id uuid references public.inbound_email_events(id) on delete set null,
  source_email_id text,
  status text not null default 'unassigned',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint invoices_total_non_negative check (total >= 0),
  constraint invoices_status_check check (status in ('unassigned', 'allocated', 'cancelled')),
  constraint invoices_uuid_sat_not_blank check (length(btrim(uuid_sat)) > 0),
  constraint invoices_proveedor_not_blank check (length(btrim(proveedor)) > 0),
  constraint invoices_xml_url_not_blank check (length(btrim(xml_url)) > 0)
);

create table if not exists public.invoice_allocations (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete restrict,
  amount numeric(14,2) not null,
  percentage numeric(5,2),
  notes text,
  created_at timestamptz not null default now(),
  constraint invoice_allocations_amount_positive check (amount > 0),
  constraint invoice_allocations_percentage_check check (percentage is null or (percentage >= 0 and percentage <= 100)),
  constraint invoice_allocations_unique_invoice_project unique (invoice_id, project_id)
);

create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references public.projects(id) on delete set null,
  invoice_id uuid references public.invoices(id) on delete set null,
  kind text not null,
  amount numeric(14,2) not null,
  currency text not null default 'MXN',
  description text,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint transactions_kind_check check (kind in ('expense', 'income')),
  constraint transactions_amount_non_negative check (amount >= 0),
  constraint transactions_currency_not_blank check (length(btrim(currency)) > 0)
);

create index if not exists invoices_uuid_sat_idx
  on public.invoices (uuid_sat);

create index if not exists invoices_provider_rfc_idx
  on public.invoices (provider_rfc);

create index if not exists invoices_status_created_idx
  on public.invoices (status, created_at desc);

create index if not exists invoice_allocations_invoice_idx
  on public.invoice_allocations (invoice_id);

create index if not exists invoice_allocations_project_idx
  on public.invoice_allocations (project_id);

create index if not exists transactions_project_occurred_idx
  on public.transactions (project_id, occurred_at desc);

create index if not exists transactions_invoice_idx
  on public.transactions (invoice_id);

create or replace function public.invoices_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_invoices_set_updated_at on public.invoices;
create trigger trg_invoices_set_updated_at
before update on public.invoices
for each row
execute function public.invoices_set_updated_at();

insert into storage.buckets (id, name, public)
values ('invoices', 'invoices', false)
on conflict (id) do nothing;

alter table public.invoices enable row level security;
alter table public.invoice_allocations enable row level security;
alter table public.transactions enable row level security;

drop policy if exists invoices_service_all on public.invoices;
create policy invoices_service_all on public.invoices
for all to service_role
using (true)
with check (true);

drop policy if exists invoice_allocations_service_all on public.invoice_allocations;
create policy invoice_allocations_service_all on public.invoice_allocations
for all to service_role
using (true)
with check (true);

drop policy if exists transactions_service_all on public.transactions;
create policy transactions_service_all on public.transactions
for all to service_role
using (true)
with check (true);
