-- Structured project keys: RM-{SEC}-{ID_CLIENTE_3D}-{TIPO}-{PRJnnn}

create sequence if not exists public.client_code_seq start 1;

alter table public.clients
  add column if not exists client_code integer;

update public.clients
set client_code = nextval('public.client_code_seq')
where client_code is null;

select setval(
  'public.client_code_seq',
  greatest((select coalesce(max(client_code), 0) from public.clients), 1),
  true
);

alter table public.clients
  alter column client_code set default nextval('public.client_code_seq');

alter table public.clients
  alter column client_code set not null;

create unique index if not exists clients_client_code_unique
  on public.clients (client_code);

create or replace function public.next_structured_project_key(
  p_client_id uuid,
  p_project_type_id uuid
)
returns text
language plpgsql
security definer
as $$
declare
  v_sector_label text;
  v_sector_code text;
  v_client_code integer;
  v_project_type_name text;
  v_project_type_code text;
  v_project_seq text;
begin
  select upper(coalesce(c.sector_label, '')),
         c.client_code
    into v_sector_label,
         v_client_code
    from public.clients c
   where c.id = p_client_id;

  if not found then
    raise exception 'Cliente no encontrado para clave estructurada: %', p_client_id;
  end if;

  if v_client_code is null then
    update public.clients
       set client_code = nextval('public.client_code_seq')
     where id = p_client_id
    returning client_code into v_client_code;
  end if;

  v_sector_code := case
    when v_sector_label like '%RESIDENCIAL%' then 'RES'
    when v_sector_label like '%HOTELERO%' then 'HOT'
    when v_sector_label like '%COMERCIAL%' then 'COM'
    when v_sector_label like '%CONSTRUCTORA%' then 'CON'
    else 'GEN'
  end;

  select upper(coalesce(pt.name, ''))
    into v_project_type_name
    from public.project_types pt
   where pt.id = p_project_type_id;

  if not found then
    raise exception 'Tipo de cotizacion no encontrado para clave estructurada: %', p_project_type_id;
  end if;

  v_project_type_code := case
    when v_project_type_name like '%MANTENIMIENTO%' then 'MNTO'
    when v_project_type_name like '%REMODEL%' then 'RMDL'
    when v_project_type_name like '%CONSTRU%' then 'CONS'
    else 'GENR'
  end;

  v_project_seq := public.next_project_key();

  return format(
    'RM-%s-%s-%s-%s',
    v_sector_code,
    lpad(v_client_code::text, 3, '0'),
    v_project_type_code,
    v_project_seq
  );
end;
$$;
