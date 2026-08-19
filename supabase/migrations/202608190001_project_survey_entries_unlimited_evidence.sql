-- Allow unlimited evidence photos per survey entry.

alter table public.project_survey_entries
  drop constraint if exists project_survey_entries_evidence_paths_max_two;

alter table public.project_survey_entries
  drop constraint if exists project_survey_entries_evidence_meta_max_two;