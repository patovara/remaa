-- Example migration (copy to supabase/migrations/<timestamp>_add_projects_status.sql)
-- Purpose: show versioned migration workflow.

alter table if exists public.projects
  add column if not exists status text;

comment on column public.projects.status is 'Project lifecycle status, managed by versioned migrations.';
