-- Use a dedicated sequence for structured folios to keep PRJ0001+ progression stable.

create sequence if not exists public.structured_project_key_seq start 1;

with structured_max as (
  select coalesce(
    max((regexp_match(upper(q.quote_number), '^RM-[A-Z]{3}[0-9]{2,}-[A-Z]{4}-PRJ([0-9]{4,})$'))[1]::bigint),
    0
  ) as max_value
  from public.quotes q
)
select setval('public.structured_project_key_seq', greatest((select max_value from structured_max), 0) + 1, false);

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
  v_sector_seq integer;
  v_project_type_name text;
  v_project_type_code text;
  v_project_seq_num bigint;
  v_project_seq_text text;
begin
  select coalesce(c.sector_label, '')
    into v_sector_label
    from public.clients c
   where c.id = p_client_id;

  if not found then
    raise exception 'Cliente no encontrado para clave estructurada: %', p_client_id;
  end if;

  v_sector_code := public.sector_code_from_label(v_sector_label);

  perform pg_advisory_xact_lock(hashtext(v_sector_code));

  select csc.sector_client_seq
    into v_sector_seq
    from public.client_sector_codes csc
   where csc.client_id = p_client_id
     and csc.sector_code = v_sector_code;

  if v_sector_seq is null then
    select coalesce(max(csc.sector_client_seq), 0) + 1
      into v_sector_seq
      from public.client_sector_codes csc
     where csc.sector_code = v_sector_code;

    insert into public.client_sector_codes (client_id, sector_code, sector_client_seq)
    values (p_client_id, v_sector_code, v_sector_seq)
    on conflict (client_id, sector_code) do update
      set updated_at = now()
    returning sector_client_seq into v_sector_seq;
  end if;

  select coalesce(pt.name, '')
    into v_project_type_name
    from public.project_types pt
   where pt.id = p_project_type_id;

  if not found then
    raise exception 'Tipo de cotizacion no encontrado para clave estructurada: %', p_project_type_id;
  end if;

  v_project_type_code := public.project_type_code_from_name(v_project_type_name);

  v_project_seq_num := nextval('public.structured_project_key_seq');
  v_project_seq_text := v_project_seq_num::text;
  if length(v_project_seq_text) < 4 then
    v_project_seq_text := lpad(v_project_seq_text, 4, '0');
  end if;

  return format(
    'RM-%s%s-%s-PRJ%s',
    v_sector_code,
    case
      when v_sector_seq < 10 then '0' || v_sector_seq::text
      else v_sector_seq::text
    end,
    v_project_type_code,
    v_project_seq_text
  );
end;
$$;
