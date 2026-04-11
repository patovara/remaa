-- New structured folio format:
-- RM-{SECTOR}{NN}-{TIPO}-PRJ{0001+}
-- Example: RM-COM01-MNTO-PRJ0001

create table if not exists public.client_sector_codes (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  sector_code text not null,
  sector_client_seq integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint client_sector_codes_sector_code_check check (length(trim(sector_code)) = 3),
  constraint client_sector_codes_seq_positive_check check (sector_client_seq > 0),
  constraint client_sector_codes_unique_client_sector unique (client_id, sector_code),
  constraint client_sector_codes_unique_sector_seq unique (sector_code, sector_client_seq)
);

create or replace function public.sector_code_from_label(label text)
returns text
language plpgsql
immutable
as $$
declare
  value text;
begin
  value := upper(coalesce(label, ''));
  if value like '%RESIDENCIAL%' then
    return 'RES';
  elsif value like '%HOTELERO%' then
    return 'HOT';
  elsif value like '%COMERCIAL%' then
    return 'COM';
  elsif value like '%CONSTRUCTORA%' then
    return 'CON';
  else
    return 'GEN';
  end if;
end;
$$;

create or replace function public.project_type_code_from_name(value text)
returns text
language plpgsql
immutable
as $$
declare
  name text;
begin
  name := upper(coalesce(value, ''));
  if name like '%MANTENIMIENTO%' then
    return 'MNTO';
  elsif name like '%REMODEL%' then
    return 'RMDL';
  elsif name like '%CONSTRU%' then
    return 'CONS';
  else
    return 'GENR';
  end if;
end;
$$;

-- Keep next_project_key compatible but with 4-digit padding.
create or replace function public.next_project_key()
returns text
language plpgsql
security definer
as $$
declare
  seq_value bigint;
begin
  seq_value := nextval('public.project_key_seq');
  return 'PRJ' || lpad(seq_value::text, 4, '0');
end;
$$;

-- Backfill sector sequence mapping for existing clients,
-- preserving deterministic order by created_at then id.
insert into public.client_sector_codes (client_id, sector_code, sector_client_seq)
select
  ranked.id as client_id,
  ranked.sector_code,
  ranked.sector_seq
from (
  select
    c.id,
    public.sector_code_from_label(c.sector_label) as sector_code,
    row_number() over (
      partition by public.sector_code_from_label(c.sector_label)
      order by c.created_at asc, c.id asc
    )::integer as sector_seq
  from public.clients c
) as ranked
on conflict (client_id, sector_code) do nothing;

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

  v_project_seq_num := nextval('public.project_key_seq');
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
