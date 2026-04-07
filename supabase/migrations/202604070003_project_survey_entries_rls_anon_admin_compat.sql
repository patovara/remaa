-- Restore Cotizaciones evidence flows for MVP (anon) while preserving ownership for authenticated users.

-- Read
DROP POLICY IF EXISTS project_survey_entries_read_auth ON public.project_survey_entries;
DROP POLICY IF EXISTS project_survey_entries_read_own ON public.project_survey_entries;
DROP POLICY IF EXISTS project_survey_entries_read_null ON public.project_survey_entries;
CREATE POLICY project_survey_entries_read_auth ON public.project_survey_entries
FOR SELECT TO authenticated
USING (
  captured_by_user_id = auth.uid()
  OR captured_by_user_id IS NULL
  OR public.is_admin()
);

DROP POLICY IF EXISTS project_survey_entries_read_anon ON public.project_survey_entries;
CREATE POLICY project_survey_entries_read_anon ON public.project_survey_entries
FOR SELECT TO anon
USING (captured_by_user_id IS NULL);

-- Insert
DROP POLICY IF EXISTS project_survey_entries_insert_auth ON public.project_survey_entries;
DROP POLICY IF EXISTS project_survey_entries_insert_own ON public.project_survey_entries;
CREATE POLICY project_survey_entries_insert_auth ON public.project_survey_entries
FOR INSERT TO authenticated
WITH CHECK (
  captured_by_user_id = auth.uid()
  OR (captured_by_user_id IS NULL AND public.is_admin())
);

DROP POLICY IF EXISTS project_survey_entries_insert_anon ON public.project_survey_entries;
CREATE POLICY project_survey_entries_insert_anon ON public.project_survey_entries
FOR INSERT TO anon
WITH CHECK (captured_by_user_id IS NULL);

-- Update
DROP POLICY IF EXISTS project_survey_entries_update_auth ON public.project_survey_entries;
DROP POLICY IF EXISTS project_survey_entries_update_own ON public.project_survey_entries;
CREATE POLICY project_survey_entries_update_auth ON public.project_survey_entries
FOR UPDATE TO authenticated
USING (captured_by_user_id = auth.uid() OR public.is_admin())
WITH CHECK (captured_by_user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS project_survey_entries_update_anon ON public.project_survey_entries;
CREATE POLICY project_survey_entries_update_anon ON public.project_survey_entries
FOR UPDATE TO anon
USING (captured_by_user_id IS NULL)
WITH CHECK (captured_by_user_id IS NULL);

-- Delete
DROP POLICY IF EXISTS project_survey_entries_delete_auth ON public.project_survey_entries;
DROP POLICY IF EXISTS project_survey_entries_delete_own ON public.project_survey_entries;
CREATE POLICY project_survey_entries_delete_auth ON public.project_survey_entries
FOR DELETE TO authenticated
USING (captured_by_user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS project_survey_entries_delete_anon ON public.project_survey_entries;
CREATE POLICY project_survey_entries_delete_anon ON public.project_survey_entries
FOR DELETE TO anon
USING (captured_by_user_id IS NULL);
