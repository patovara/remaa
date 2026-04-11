-- Migration: allow the same concept name under different project types within a universe.
-- Before: UNIQUE (universe_id, name)
-- After:  UNIQUE (universe_id, project_type_id, name)
--
-- This lets "Impermeabilizante" (and any future concept) exist independently
-- under Mantenimiento, Remodelacion and Construccion in the same universe.

-- 1. Drop old constraint
ALTER TABLE concept_templates
  DROP CONSTRAINT concept_templates_unique_name_per_universe;

-- 2. Add new constraint scoped to project_type
ALTER TABLE concept_templates
  ADD CONSTRAINT concept_templates_unique_name_per_universe_and_type
    UNIQUE (universe_id, project_type_id, name);

-- 3. Seed Impermeabilizante for Mantenimiento
--    (universe Recubrimientos, project_type Mantenimiento)
WITH tmpl AS (
  INSERT INTO concept_templates (universe_id, project_type_id, closure_id, name, base_description, default_unit, base_price)
  VALUES (
    'd6d53e28-90ee-440d-a90f-511695ba1edc',
    '7f2298c5-c00d-410f-a05d-9ff1c4cc90c9',
    '11090001-647b-4905-8d7d-819610caeeb9',
    'Impermeabilizante',
    'Suministro y aplicacion de impermeabilizante.',
    'm2',
    180.00
  )
  RETURNING id
),
a_tipo  AS (INSERT INTO concept_attributes (concept_template_id, name) SELECT id, 'tipo'  FROM tmpl RETURNING id),
a_marca AS (INSERT INTO concept_attributes (concept_template_id, name) SELECT id, 'marca' FROM tmpl RETURNING id),
a_capas AS (INSERT INTO concept_attributes (concept_template_id, name) SELECT id, 'capas' FROM tmpl RETURNING id),
o_tipo  AS (INSERT INTO attribute_options (attribute_id, value) SELECT id, v FROM a_tipo,  (VALUES ('Acrilico'),('Prefabricado')) x(v)),
o_marca AS (INSERT INTO attribute_options (attribute_id, value) SELECT id, v FROM a_marca, (VALUES ('Comex'),('Fester'))         x(v)),
o_capas AS (INSERT INTO attribute_options (attribute_id, value) SELECT id, v FROM a_capas, (VALUES ('2'),('3'))                 x(v))
SELECT id FROM tmpl;

-- 4. Seed Impermeabilizante for Construccion
--    (universe Recubrimientos, project_type Construccion)
WITH tmpl AS (
  INSERT INTO concept_templates (universe_id, project_type_id, closure_id, name, base_description, default_unit, base_price)
  VALUES (
    'd6d53e28-90ee-440d-a90f-511695ba1edc',
    '42ad1047-686d-4d31-9044-5308d82803fa',
    '11090001-647b-4905-8d7d-819610caeeb9',
    'Impermeabilizante',
    'Suministro y aplicacion de impermeabilizante.',
    'm2',
    180.00
  )
  RETURNING id
),
a_tipo  AS (INSERT INTO concept_attributes (concept_template_id, name) SELECT id, 'tipo'  FROM tmpl RETURNING id),
a_marca AS (INSERT INTO concept_attributes (concept_template_id, name) SELECT id, 'marca' FROM tmpl RETURNING id),
a_capas AS (INSERT INTO concept_attributes (concept_template_id, name) SELECT id, 'capas' FROM tmpl RETURNING id),
o_tipo  AS (INSERT INTO attribute_options (attribute_id, value) SELECT id, v FROM a_tipo,  (VALUES ('Acrilico'),('Prefabricado')) x(v)),
o_marca AS (INSERT INTO attribute_options (attribute_id, value) SELECT id, v FROM a_marca, (VALUES ('Comex'),('Fester'))         x(v)),
o_capas AS (INSERT INTO attribute_options (attribute_id, value) SELECT id, v FROM a_capas, (VALUES ('2'),('3'))                 x(v))
SELECT id FROM tmpl;
