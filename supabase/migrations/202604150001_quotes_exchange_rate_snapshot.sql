-- Exchange-rate cache + frozen USD snapshot fields for quote final PDF

create table if not exists public.currency_rates_cache (
  id bigserial primary key,
  base_currency text not null,
  target_currency text not null,
  rate numeric(14,6) not null,
  provider text not null default 'exchangerate-api',
  fetched_at timestamptz not null default now(),
  expires_at timestamptz not null,
  constraint currency_rates_cache_positive_rate_check check (rate > 0),
  constraint currency_rates_cache_nonempty_base_check check (length(trim(base_currency)) > 0),
  constraint currency_rates_cache_nonempty_target_check check (length(trim(target_currency)) > 0),
  constraint currency_rates_cache_nonempty_provider_check check (length(trim(provider)) > 0)
);

create index if not exists currency_rates_cache_pair_exp_idx
  on public.currency_rates_cache(base_currency, target_currency, expires_at desc);

alter table public.quotes
  add column if not exists final_exchange_rate numeric(14,6),
  add column if not exists final_exchange_base text,
  add column if not exists final_exchange_target text,
  add column if not exists final_exchange_provider text,
  add column if not exists final_exchange_captured_at timestamptz,
  add column if not exists final_subtotal_usd numeric(14,0),
  add column if not exists final_tax_usd numeric(14,0),
  add column if not exists final_total_usd numeric(14,0);

alter table public.quotes
  drop constraint if exists quotes_final_exchange_rate_positive_check;

alter table public.quotes
  add constraint quotes_final_exchange_rate_positive_check
  check (final_exchange_rate is null or final_exchange_rate > 0);
