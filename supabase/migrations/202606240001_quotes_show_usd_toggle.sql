-- Persistent USD visibility toggle for quotes (default OFF).

alter table public.quotes
  add column if not exists show_usd boolean not null default false;