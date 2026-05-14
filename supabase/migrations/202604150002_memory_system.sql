-- Memory system for REMAA

create table if not exists public.memory_state (
  id uuid primary key default gen_random_uuid(),
  project_id text not null unique,
  state jsonb not null,
  updated_at timestamptz not null default now(),
  constraint memory_state_project_id_not_blank check (length(btrim(project_id)) > 0),
  constraint memory_state_state_is_object check (jsonb_typeof(state) = 'object')
);

create table if not exists public.memory_summary (
  id uuid primary key default gen_random_uuid(),
  project_id text not null unique,
  summary text not null,
  updated_at timestamptz not null default now(),
  constraint memory_summary_project_id_not_blank check (length(btrim(project_id)) > 0)
);

create table if not exists public.memory_logs (
  id uuid primary key default gen_random_uuid(),
  project_id text not null,
  role text not null,
  content text not null,
  created_at timestamptz not null default now(),
  constraint memory_logs_project_id_not_blank check (length(btrim(project_id)) > 0),
  constraint memory_logs_role_not_blank check (length(btrim(role)) > 0),
  constraint memory_logs_content_not_blank check (length(btrim(content)) > 0)
);

create index if not exists idx_memory_logs_project_created_at
  on public.memory_logs (project_id, created_at desc);

create index if not exists idx_memory_logs_role
  on public.memory_logs (role);

create index if not exists idx_memory_state_updated_at
  on public.memory_state (updated_at desc);

create index if not exists idx_memory_summary_updated_at
  on public.memory_summary (updated_at desc);

create or replace function public.memory_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_memory_state_set_updated_at on public.memory_state;
create trigger trg_memory_state_set_updated_at
before update on public.memory_state
for each row
execute function public.memory_set_updated_at();

drop trigger if exists trg_memory_summary_set_updated_at on public.memory_summary;
create trigger trg_memory_summary_set_updated_at
before update on public.memory_summary
for each row
execute function public.memory_set_updated_at();

alter table public.memory_state enable row level security;
alter table public.memory_summary enable row level security;
alter table public.memory_logs enable row level security;

insert into public.memory_state (project_id, state)
values (
  'remaa_app',
  $$
  {
    "proyecto": "REMAA plataforma de cotización y gestión",
    "fase_actual": "staging / alfa",
    "stack": {
      "frontend": "Flutter Web",
      "backend": "Supabase",
      "hosting": "Vercel",
      "database": "PostgreSQL",
      "auth": "Supabase Auth",
      "emails": "Resend"
    },
    "arquitectura": {
      "tipo": "modular por features",
      "capas": ["presentation", "data", "domain"],
      "reglas": [
        "UI no accede directo a SDK",
        "integraciones en capa data",
        "logica de negocio en domain"
      ]
    },
    "features": [
      "autenticacion (login, invite, reset password)",
      "gestion de clientes",
      "gestion de responsables por cliente",
      "creacion de cotizaciones",
      "edicion de conceptos",
      "generacion de PDF",
      "envio de correos transaccionales"
    ],
    "integraciones": [
      "Supabase Auth",
      "Supabase Edge Functions",
      "Resend (email)",
      "Vercel deploy"
    ],
    "edge_functions": [
      "user-admin",
      "mailer",
      "email-inbound"
    ],
    "entornos": {
      "produccion": {
        "branch": "main"
      },
      "staging": {
        "branch": "develop",
        "url": "remaa-staging.vercel.app"
      }
    },
    "flujo_auth": {
      "tipo": "token-based via email",
      "modos": ["invite", "reset"],
      "ruta_frontend": "/register",
      "parametros": ["mode", "type", "token"]
    },
    "modelo_datos": {
      "principales": [
        "clients",
        "client_responsibles",
        "quotes"
      ]
    },
    "decisiones": [
      "uso de Supabase como backend principal",
      "separacion clara entre staging y produccion",
      "uso de Edge Functions para logica sensible",
      "uso de Resend para emails",
      "Flutter Web como frontend unico"
    ],
    "pendientes": [
      "mejorar diseño de cotizaciones (multimoneda)",
      "implementar multicurrency",
      "optimizar UX de precios",
      "integrar sistema de memoria IA",
      "validaciones completas en staging"
    ],
    "problemas_resueltos": [
      "flujo de invitaciones y reset estable",
      "configuracion de staging separada",
      "deploy automatizado por ramas"
    ],
    "riesgos": [
      "manejo incorrecto de tokens en auth",
      "inconsistencia entre entornos",
      "dependencia de configuracion manual en staging"
    ]
  }
  $$::jsonb
)
on conflict (project_id) do update set
  state = excluded.state,
  updated_at = now();

insert into public.memory_summary (project_id, summary)
values (
  'remaa_app',
  'Proyecto REMAA en fase staging/alfa.

Sistema construido con Flutter Web + Supabase + Vercel.
Incluye autenticación completa, gestión de clientes y cotizaciones con PDF.

Arquitectura modular por capas (presentation, data, domain).

Se utilizan Edge Functions para lógica sensible y Resend para correos.

Actualmente se trabaja en multicurrency, mejoras de cotización y memoria IA.'
)
on conflict (project_id) do update set
  summary = excluded.summary,
  updated_at = now();
