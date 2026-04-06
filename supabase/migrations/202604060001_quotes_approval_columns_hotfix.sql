alter table if exists public.quotes
  add column if not exists approval_pdf_path text;

alter table if exists public.quotes
  add column if not exists approval_pdf_uploaded_at timestamptz;
