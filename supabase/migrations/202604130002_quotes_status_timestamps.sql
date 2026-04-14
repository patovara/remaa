-- Migration: add approved_at and acta_at timestamp columns to quotes table
-- approved_at: set automatically when status changes to 'approved'
-- acta_at:     set automatically when status changes to 'acta_finalizada'

alter table public.quotes
  add column if not exists approved_at timestamptz,
  add column if not exists acta_at timestamptz;

-- Trigger function: record the exact moment each status milestone is reached
create or replace function public.quote_status_timestamps()
returns trigger
language plpgsql
as $$
begin
  -- Set approved_at on first transition to 'approved'
  if NEW.status = 'approved' and (OLD.status is null or OLD.status <> 'approved') then
    NEW.approved_at := coalesce(NEW.approved_at, now());
  end if;

  -- Set acta_at on first transition to 'acta_finalizada'
  if NEW.status = 'acta_finalizada' and (OLD.status is null or OLD.status <> 'acta_finalizada') then
    NEW.acta_at := coalesce(NEW.acta_at, now());
  end if;

  return NEW;
end;
$$;

drop trigger if exists quotes_status_timestamps on public.quotes;

create trigger quotes_status_timestamps
  before update on public.quotes
  for each row
  execute function public.quote_status_timestamps();
