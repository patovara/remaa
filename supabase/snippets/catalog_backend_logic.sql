-- Catalog backend logic (Supabase / PostgreSQL)
-- Scope: create concept, add attributes, prevent duplicates, import CSV rows.

create extension if not exists pgcrypto;

-- Normalizes text for duplicate checks and comparisons.
create or replace function public.normalize_text(input text)
returns text
language sql
immutable
as $$
  select lower(trim(regexp_replace(coalesce(input, ''), '\\s+', ' ', 'g')))
$$;

-- Defensive uniqueness to avoid semantic duplicates due to spaces/case.
create unique index if not exists ux_universes_name_norm
  on public.universes (public.normalize_text(name));

create unique index if not exists ux_project_types_name_norm
  on public.project_types (public.normalize_text(name));

create unique index if not exists ux_concept_templates_name_norm
  on public.concept_templates (universe_id, public.normalize_text(name));

create unique index if not exists ux_concept_attributes_name_norm
  on public.concept_attributes (concept_template_id, public.normalize_text(name));

create unique index if not exists ux_attribute_options_value_norm
  on public.attribute_options (attribute_id, public.normalize_text(value));

-- Creates or updates a concept template.
create or replace function public.catalog_upsert_concept(
  p_universe_id uuid,
  p_project_type_id uuid,
  p_closure_id uuid,
  p_name text,
  p_base_description text,
  p_default_unit text,
  p_base_price numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_name text;
  v_base_description text;
  v_unit text;
begin
  v_name := trim(coalesce(p_name, ''));
  v_base_description := trim(coalesce(p_base_description, ''));
  v_unit := trim(coalesce(p_default_unit, ''));

  if p_universe_id is null then
    raise exception 'universe_id es obligatorio';
  end if;

  if p_project_type_id is null then
    raise exception 'project_type_id es obligatorio';
  end if;

  if p_closure_id is null then
    raise exception 'closure_id es obligatorio';
  end if;

  if v_name = '' then
    raise exception 'name es obligatorio';
  end if;

  if v_base_description = '' then
    raise exception 'base_description es obligatorio';
  end if;

  if v_unit = '' then
    raise exception 'default_unit es obligatorio';
  end if;

  if p_base_price is null or p_base_price < 0 then
    raise exception 'base_price debe ser >= 0';
  end if;

  if not exists (select 1 from public.universes where id = p_universe_id) then
    raise exception 'universe_id no existe: %', p_universe_id;
  end if;

  if not exists (select 1 from public.project_types where id = p_project_type_id) then
    raise exception 'project_type_id no existe: %', p_project_type_id;
  end if;

  if not exists (select 1 from public.concept_closures where id = p_closure_id) then
    raise exception 'closure_id no existe: %', p_closure_id;
  end if;

  insert into public.concept_templates (
    universe_id,
    project_type_id,
    closure_id,
    name,
    base_description,
    default_unit,
    base_price
  )
  values (
    p_universe_id,
    p_project_type_id,
    p_closure_id,
    v_name,
    v_base_description,
    v_unit,
    p_base_price
  )
  on conflict (universe_id, name)
  do update set
    project_type_id = excluded.project_type_id,
    closure_id = excluded.closure_id,
    base_description = excluded.base_description,
    default_unit = excluded.default_unit,
    base_price = excluded.base_price,
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

-- Adds an attribute to a concept and optionally registers options.
create or replace function public.catalog_add_attribute(
  p_concept_template_id uuid,
  p_attribute_name text,
  p_options text[] default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_attribute_id uuid;
  v_name text;
  v_option text;
begin
  if p_concept_template_id is null then
    raise exception 'concept_template_id es obligatorio';
  end if;

  if not exists (
    select 1
    from public.concept_templates
    where id = p_concept_template_id
  ) then
    raise exception 'concept_template_id no existe: %', p_concept_template_id;
  end if;

  v_name := trim(coalesce(p_attribute_name, ''));

  if v_name = '' then
    raise exception 'attribute_name es obligatorio';
  end if;

  insert into public.concept_attributes (concept_template_id, name)
  values (p_concept_template_id, v_name)
  on conflict (concept_template_id, name)
  do update set updated_at = now()
  returning id into v_attribute_id;

  if p_options is not null and cardinality(p_options) > 0 then
    for v_option in
      select distinct trim(opt)
      from unnest(p_options) as opt
      where trim(coalesce(opt, '')) <> ''
    loop
      insert into public.attribute_options (attribute_id, value)
      values (v_attribute_id, v_option)
      on conflict (attribute_id, value)
      do update set updated_at = now();
    end loop;
  end if;

  return v_attribute_id;
end;
$$;

-- Imports one CSV row represented as JSON.
-- Expected keys:
-- universe, project_type, concept, unit, base_price, base_description, attribute, option, closure
create or replace function public.catalog_import_csv_row(
  p_row jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_universe_name text;
  v_project_type_name text;
  v_concept_name text;
  v_unit text;
  v_base_description text;
  v_attribute_name text;
  v_option_value text;
  v_closure_text text;
  v_base_price numeric;
  v_universe_id uuid;
  v_project_type_id uuid;
  v_closure_id uuid;
  v_concept_id uuid;
  v_attribute_id uuid;
begin
  v_universe_name := trim(coalesce(p_row ->> 'universe', ''));
  v_project_type_name := trim(coalesce(p_row ->> 'project_type', ''));
  v_concept_name := trim(coalesce(p_row ->> 'concept', ''));
  v_unit := trim(coalesce(p_row ->> 'unit', ''));
  v_base_description := trim(coalesce(p_row ->> 'base_description', ''));
  v_attribute_name := trim(coalesce(p_row ->> 'attribute', ''));
  v_option_value := trim(coalesce(p_row ->> 'option', ''));
  v_closure_text := trim(coalesce(p_row ->> 'closure', ''));

  if coalesce(p_row ->> 'base_price', '') = '' then
    raise exception 'base_price es obligatorio';
  end if;
  v_base_price := (p_row ->> 'base_price')::numeric;

  if v_universe_name = '' or v_project_type_name = '' or v_concept_name = '' then
    raise exception 'universe, project_type y concept son obligatorios';
  end if;

  if v_unit = '' then
    raise exception 'unit es obligatorio';
  end if;

  if v_base_description = '' then
    raise exception 'base_description es obligatorio';
  end if;

  select id into v_universe_id
  from public.universes
  where public.normalize_text(name) = public.normalize_text(v_universe_name)
  limit 1;

  if v_universe_id is null then
    raise exception 'universo no existe: %', v_universe_name;
  end if;

  select id into v_project_type_id
  from public.project_types
  where public.normalize_text(name) = public.normalize_text(v_project_type_name)
  limit 1;

  if v_project_type_id is null then
    raise exception 'project_type no existe: %', v_project_type_name;
  end if;

  if v_closure_text = '' then
    select id into v_closure_id
    from public.concept_closures
    order by created_at asc
    limit 1;
  else
    insert into public.concept_closures (text)
    values (v_closure_text)
    on conflict (text)
    do update set updated_at = now()
    returning id into v_closure_id;
  end if;

  if v_closure_id is null then
    raise exception 'no existe closure por defecto y closure viene vacio';
  end if;

  v_concept_id := public.catalog_upsert_concept(
    v_universe_id,
    v_project_type_id,
    v_closure_id,
    v_concept_name,
    v_base_description,
    v_unit,
    v_base_price
  );

  if v_attribute_name <> '' then
    v_attribute_id := public.catalog_add_attribute(
      v_concept_id,
      v_attribute_name,
      case when v_option_value = '' then null else array[v_option_value] end
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'concept_id', v_concept_id,
    'attribute_id', v_attribute_id
  );
end;
$$;

-- Batch import for multiple rows (CSV already parsed to JSON array).
create or replace function public.catalog_import_csv_batch(
  p_rows jsonb,
  p_fail_fast boolean default false
)
returns table (
  row_number int,
  ok boolean,
  message text,
  concept_id uuid,
  attribute_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb;
  v_result jsonb;
  v_idx int := 0;
begin
  if jsonb_typeof(p_rows) <> 'array' then
    raise exception 'p_rows debe ser un array json';
  end if;

  for v_item in select value from jsonb_array_elements(p_rows)
  loop
    v_idx := v_idx + 1;
    begin
      v_result := public.catalog_import_csv_row(v_item);
      row_number := v_idx;
      ok := true;
      message := 'ok';
      concept_id := (v_result ->> 'concept_id')::uuid;
      attribute_id := nullif(v_result ->> 'attribute_id', '')::uuid;
      return next;
    exception
      when others then
        if p_fail_fast then
          raise;
        end if;

        row_number := v_idx;
        ok := false;
        message := sqlerrm;
        concept_id := null;
        attribute_id := null;
        return next;
    end;
  end loop;

  return;
end;
$$;

-- Suggested execute grants for RPC usage.
grant execute on function public.catalog_upsert_concept(uuid, uuid, uuid, text, text, text, numeric) to authenticated;
grant execute on function public.catalog_add_attribute(uuid, text, text[]) to authenticated;
grant execute on function public.catalog_import_csv_row(jsonb) to authenticated;
grant execute on function public.catalog_import_csv_batch(jsonb, boolean) to authenticated;
