-- Backfill quote links for historical survey entries created before the draft quote existed.
-- Strategy:
-- 1. Match only entries with quote_id IS NULL.
-- 2. Prefer the first quote of the same project created at or after the survey entry.
-- 3. If none exists after that timestamp, fallback to the latest quote for the same project.

with ranked_matches as (
  select
    pse.id as survey_entry_id,
    q.id as quote_id,
    row_number() over (
      partition by pse.id
      order by
        case when q.created_at >= pse.created_at then 0 else 1 end,
        case when q.created_at >= pse.created_at then q.created_at end asc nulls last,
        q.created_at desc,
        q.id
    ) as quote_rank
  from public.project_survey_entries pse
  join public.quotes q
    on q.project_id = pse.project_id
  where pse.quote_id is null
),
best_match as (
  select survey_entry_id, quote_id
  from ranked_matches
  where quote_rank = 1
)
update public.project_survey_entries pse
set quote_id = best_match.quote_id,
    updated_at = now()
from best_match
where pse.id = best_match.survey_entry_id
  and pse.quote_id is null;