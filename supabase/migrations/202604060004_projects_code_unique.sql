-- Garantiza unicidad de clave de proyecto (case-insensitive) y corrige datos previos.

-- 1) Normaliza en mayusculas y sin espacios laterales.
update public.projects
set code = upper(btrim(code))
where code is not null
  and code <> upper(btrim(code));

-- 2) Asigna clave a registros sin code util.
do $$
begin
  update public.projects
  set code = public.next_project_key()
  where code is null or btrim(code) = '';
end
$$;

-- 3) Resuelve duplicados conservando el primer registro y regenerando los demas.
do $$
begin
  with ranked as (
    select
      id,
      row_number() over (
        partition by upper(btrim(code))
        order by created_at nulls first, id
      ) as rn
    from public.projects
  )
  update public.projects p
  set code = public.next_project_key()
  from ranked r
  where p.id = r.id
    and r.rn > 1;
end
$$;

-- 4) Enforce final de unicidad sin importar mayusculas/minusculas.
create unique index if not exists projects_code_unique_ci_idx
  on public.projects ((upper(btrim(code))));
