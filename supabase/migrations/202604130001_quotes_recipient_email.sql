alter table public.quotes
  add column if not exists recipient_email text;
