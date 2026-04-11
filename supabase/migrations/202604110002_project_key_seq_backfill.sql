-- Ensure global project key sequence exists for folio generation.

create sequence if not exists public.project_key_seq start 1;

-- Backfill next value from existing quote numbers to avoid collisions.
with max_used as (
  select coalesce(max((regexp_match(upper(q.quote_number), 'PRJ([0-9]{1,})$'))[1]::bigint), 0) as max_value
  from public.quotes q
  where upper(coalesce(q.quote_number, '')) ~ 'PRJ[0-9]{1,}$'
)
select setval('public.project_key_seq', greatest((select max_value from max_used), 0) + 1, false);
