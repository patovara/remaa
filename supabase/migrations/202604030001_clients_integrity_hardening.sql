-- =============================================================================
-- clients_integrity_hardening
-- Fecha: 2026-04-03
-- Propósito: Añadir unicidad, checks de formato y normalización a public.clients
--            garantizando integridad en 3 capas (DB / backend / frontend).
-- IMPORTANTE: ejecutar precheck de duplicados ANTES de aplicar esta migración.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 0 – Extensión para trigrama (búsquedas fuzzy futuras, ya disponible)
-- ─────────────────────────────────────────────────────────────────────────────
create extension if not exists pg_trgm;

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 1 – Función de normalización de teléfono E.164 MX
--   Acepta formatos de entrada: "9981234567", "+529981234567", "529981234567"
--   Siempre retorna "+52XXXXXXXXXX" o lanza excepción si no cumple formato.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.normalize_phone_e164_mx(raw text)
returns text
language plpgsql
immutable
as $$
declare
  digits text;
begin
  if raw is null or trim(raw) = '' then
    return null;
  end if;
  -- Extraer solo dígitos
  digits := regexp_replace(raw, '[^0-9]', '', 'g');
  -- Aceptar 10 dígitos (local MX) o 12 dígitos (52 + 10)
  if length(digits) = 10 then
    return '+52' || digits;
  elsif length(digits) = 12 and left(digits, 2) = '52' then
    return '+52' || substring(digits, 3);
  else
    raise exception 'Formato de teléfono inválido: %. Se esperan 10 dígitos MX o formato +52XXXXXXXXXX.', raw;
  end if;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 2 – Normalizar columnas existentes antes de crear constraints
--   Esto saneará registros históricos para evitar fallas al aplicar los índices.
--   RFC: trim + upper; email: trim + lower; phone: normalización E.164;
--   business_name: trim + upper.
-- ─────────────────────────────────────────────────────────────────────────────
do $$
begin
  -- RFC
  update public.clients
  set rfc = upper(trim(rfc))
  where rfc is not null and rfc != upper(trim(rfc));

  -- Email
  update public.clients
  set email = lower(trim(email))
  where email is not null and email != lower(trim(email));

  -- Business name
  update public.clients
  set business_name = upper(trim(business_name))
  where business_name != upper(trim(business_name));

  -- Phone: intentar normalizar; dejar null los que no cumplan ningún formato
  update public.clients
  set phone = (
    case
      when phone is null or trim(phone) = '' then null
      when regexp_replace(phone, '[^0-9]', '', 'g') ~ '^[0-9]{10}$'
        then '+52' || regexp_replace(phone, '[^0-9]', '', 'g')
      when regexp_replace(phone, '[^0-9]', '', 'g') ~ '^52[0-9]{10}$'
        then '+52' || substring(regexp_replace(phone, '[^0-9]', '', 'g'), 3)
      else null  -- teléfonos que no cumplan quedan null; reportar manualmente
    end
  )
  where phone is not null;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 3 – Constraint: business_name no puede quedar vacío después de trim
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.clients
  drop constraint if exists clients_business_name_notempty,
  add constraint clients_business_name_notempty
    check (length(trim(business_name)) >= 2);

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 4 – CHECK: longitud y contenido de dirección (cuando no sea null)
--   Mínimo 10, máximo 255 caracteres; debe contener al menos una letra y un dígito.
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.clients
  drop constraint if exists clients_address_format,
  add constraint clients_address_format
    check (
      address_line is null
      or (
        length(trim(address_line)) between 10 and 255
        and trim(address_line) ~ '[A-Za-záéíóúüñÁÉÍÓÚÜÑ]'
        and trim(address_line) ~ '[0-9]'
      )
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 5 – CHECK: formato RFC mexicano (cuando no sea null)
--   Persona moral:  XXX-XXXXXX-XXX  (12 caracteres alfanuméricos)
--   Persona física: XXXX-XXXXXX-XXX (13 caracteres alfanuméricos)
--   Patrón simplificado que cubre ambos casos.
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.clients
  drop constraint if exists clients_rfc_format,
  add constraint clients_rfc_format
    check (
      rfc is null
      or (
        upper(trim(rfc)) ~ '^[A-Z&\u00D1]{3,4}[0-9]{6}[A-Z0-9]{3}$'
        and length(trim(rfc)) in (12, 13)
      )
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 6 – CHECK: teléfono en formato E.164 MX (cuando no sea null)
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.clients
  drop constraint if exists clients_phone_e164,
  add constraint clients_phone_e164
    check (
      phone is null
      or phone ~ '^\+52[0-9]{10}$'
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 7 – Índices únicos funcionales (case-insensitive, globales)
--   Null es excluido de la unicidad por naturaleza de UNIQUE en Postgres.
--   Para RFC y email: se excluyen valores vacíos explícitamente.
-- ─────────────────────────────────────────────────────────────────────────────

-- Email único case-insensitive (excluye null y cadena vacía)
drop index if exists public.clients_email_unique_ci;
create unique index clients_email_unique_ci
  on public.clients (lower(trim(email)))
  where email is not null and trim(email) <> '';

-- RFC único case-insensitive (excluye null y cadena vacía)
drop index if exists public.clients_rfc_unique_ci;
create unique index clients_rfc_unique_ci
  on public.clients (upper(trim(rfc)))
  where rfc is not null and trim(rfc) <> '';

-- Teléfono único (E.164 ya normalizado, excluye null)
drop index if exists public.clients_phone_unique;
create unique index clients_phone_unique
  on public.clients (phone)
  where phone is not null;

-- Razón social única case-insensitive (excluye null y cadena vacía)
drop index if exists public.clients_business_name_unique_ci;
create unique index clients_business_name_unique_ci
  on public.clients (upper(trim(business_name)))
  where business_name is not null and trim(business_name) <> '';

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 8 – Índices de rendimiento para búsquedas y ordenamiento
-- ─────────────────────────────────────────────────────────────────────────────
create index if not exists clients_business_name_lower_idx
  on public.clients (lower(business_name));

create index if not exists clients_email_lower_idx
  on public.clients (lower(email))
  where email is not null;

create index if not exists clients_is_hidden_idx
  on public.clients (is_hidden);

create index if not exists clients_created_at_idx
  on public.clients (created_at desc);

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 9 – Trigger de normalización automática en INSERT/UPDATE
--   Garantiza que los datos lleguen normalizados sin importar el origen
--   (frontend, API directa, importación masiva).
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.normalize_client_fields()
returns trigger
language plpgsql
as $$
begin
  -- business_name: trim + upper
  new.business_name := upper(trim(new.business_name));

  -- contact_name: trim + upper (si existe)
  if new.contact_name is not null then
    new.contact_name := upper(trim(regexp_replace(
      new.contact_name, '[^A-Za-z\u00C0-\u00FF ]', ' ', 'g'
    )));
    new.contact_name := trim(regexp_replace(new.contact_name, '\s+', ' ', 'g'));
    if new.contact_name = '' then
      new.contact_name := null;
    end if;
  end if;

  -- email: trim + lower
  if new.email is not null then
    new.email := lower(trim(new.email));
    if new.email = '' then
      new.email := null;
    end if;
  end if;

  -- rfc: trim + upper
  if new.rfc is not null then
    new.rfc := upper(trim(new.rfc));
    if new.rfc = '' then
      new.rfc := null;
    end if;
  end if;

  -- phone: normalización E.164
  if new.phone is not null and trim(new.phone) <> '' then
    declare
      digits text;
    begin
      digits := regexp_replace(new.phone, '[^0-9]', '', 'g');
      if length(digits) = 10 then
        new.phone := '+52' || digits;
      elsif length(digits) = 12 and left(digits, 2) = '52' then
        new.phone := '+52' || substring(digits, 3);
      end if;
      -- Si ya tiene formato +52XXXXXXXXXX dejarlo
      if new.phone !~ '^\+52[0-9]{10}$' then
        new.phone := null;
      end if;
    end;
  elsif new.phone is not null and trim(new.phone) = '' then
    new.phone := null;
  end if;

  -- address_line: trim
  if new.address_line is not null then
    new.address_line := trim(new.address_line);
    if new.address_line = '' then
      new.address_line := null;
    end if;
  end if;

  -- updated_at
  new.updated_at := now();

  return new;
end;
$$;

drop trigger if exists clients_normalize_before_upsert on public.clients;
create trigger clients_normalize_before_upsert
  before insert or update on public.clients
  for each row
  execute function public.normalize_client_fields();
