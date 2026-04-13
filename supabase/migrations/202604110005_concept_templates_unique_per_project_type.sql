-- Migration: allow the same concept name under different project types within a universe.
-- Before: UNIQUE (universe_id, name)
-- After:  UNIQUE (universe_id, project_type_id, name)
--
-- This lets "Impermeabilizante" (and any future concept) exist independently
-- under Mantenimiento, Remodelacion and Construccion in the same universe.

-- 1. Drop old constraint (tolerant: may already be gone in some environments)
ALTER TABLE concept_templates
  DROP CONSTRAINT IF EXISTS concept_templates_unique_name_per_universe;

-- 2. Add new constraint scoped to project_type (tolerant: skip if already exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'concept_templates_unique_name_per_universe_and_type'
      AND conrelid = 'public.concept_templates'::regclass
  ) THEN
    ALTER TABLE concept_templates
      ADD CONSTRAINT concept_templates_unique_name_per_universe_and_type
        UNIQUE (universe_id, project_type_id, name);
  END IF;
END;
$$;

-- 3. Seed Impermeabilizante for Mantenimiento (idempotent)
DO $$
DECLARE
  v_tmpl_id uuid;
  v_attr_id uuid;
BEGIN
  SELECT id INTO v_tmpl_id
  FROM public.concept_templates
  WHERE universe_id = 'd6d53e28-90ee-440d-a90f-511695ba1edc'
    AND project_type_id = '7f2298c5-c00d-410f-a05d-9ff1c4cc90c9'
    AND name = 'Impermeabilizante';

  IF v_tmpl_id IS NULL THEN
    INSERT INTO public.concept_templates (universe_id, project_type_id, closure_id, name, base_description, default_unit, base_price)
    VALUES ('d6d53e28-90ee-440d-a90f-511695ba1edc','7f2298c5-c00d-410f-a05d-9ff1c4cc90c9','11090001-647b-4905-8d7d-819610caeeb9','Impermeabilizante','Suministro y aplicacion de impermeabilizante.','m2',180.00)
    RETURNING id INTO v_tmpl_id;

    FOR v_attr_id IN
      INSERT INTO public.concept_attributes (concept_template_id, name) VALUES (v_tmpl_id,'tipo'),(v_tmpl_id,'marca'),(v_tmpl_id,'capas') RETURNING id
    LOOP
      INSERT INTO public.attribute_options (attribute_id, value)
      SELECT v_attr_id, v FROM (VALUES ('Acrilico'),('Prefabricado'),('Comex'),('Fester'),('2'),('3')) x(v)
      ON CONFLICT DO NOTHING;
    END LOOP;
  END IF;
END;
$$;

-- 4. Seed Impermeabilizante for Construccion (idempotent)
DO $$
DECLARE
  v_tmpl_id uuid;
  v_attr_id uuid;
BEGIN
  SELECT id INTO v_tmpl_id
  FROM public.concept_templates
  WHERE universe_id = 'd6d53e28-90ee-440d-a90f-511695ba1edc'
    AND project_type_id = '42ad1047-686d-4d31-9044-5308d82803fa'
    AND name = 'Impermeabilizante';

  IF v_tmpl_id IS NULL THEN
    INSERT INTO public.concept_templates (universe_id, project_type_id, closure_id, name, base_description, default_unit, base_price)
    VALUES ('d6d53e28-90ee-440d-a90f-511695ba1edc','42ad1047-686d-4d31-9044-5308d82803fa','11090001-647b-4905-8d7d-819610caeeb9','Impermeabilizante','Suministro y aplicacion de impermeabilizante.','m2',180.00)
    RETURNING id INTO v_tmpl_id;

    FOR v_attr_id IN
      INSERT INTO public.concept_attributes (concept_template_id, name) VALUES (v_tmpl_id,'tipo'),(v_tmpl_id,'marca'),(v_tmpl_id,'capas') RETURNING id
    LOOP
      INSERT INTO public.attribute_options (attribute_id, value)
      SELECT v_attr_id, v FROM (VALUES ('Acrilico'),('Prefabricado'),('Comex'),('Fester'),('2'),('3')) x(v)
      ON CONFLICT DO NOTHING;
    END LOOP;
  END IF;
END;
$$;
