-- Allow multiple delivery certificates for the same quote.

alter table public.quote_acta_assets
  drop constraint if exists quote_acta_assets_pkey;

alter table public.quote_acta_assets
  add column if not exists id uuid default gen_random_uuid();

update public.quote_acta_assets
   set id = gen_random_uuid()
 where id is null;

alter table public.quote_acta_assets
  alter column id set not null;

alter table public.quote_acta_assets
  add constraint quote_acta_assets_pkey primary key (id);

alter table public.quote_acta_assets
  add column if not exists start_date date,
  add column if not exists conclusion_date date;

create index if not exists quote_acta_assets_quote_id_created_idx
  on public.quote_acta_assets (quote_id, created_at desc);