-- Add ownership tracking to project_survey_entries for staff-level data isolation
-- Allows filtering surveys per authenticated user and enforcing RLS policies

-- Add captured_by_user_id column to project_survey_entries
-- Nullable: allows existing historical records without an owner
-- ON DELETE SET NULL: if user is deleted, survey entry remains but becomes orphaned (admin visible)
alter table public.project_survey_entries
add column if not exists captured_by_user_id uuid references auth.users(id) on delete set null;

-- Create index for efficient filtering by user
create index if not exists idx_project_survey_entries_captured_by_user_id 
on public.project_survey_entries(captured_by_user_id);
