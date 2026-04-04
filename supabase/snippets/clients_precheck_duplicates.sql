-- =============================================================================
-- PRECHECK de duplicados – ejecutar ANTES de la migración de hardening.
-- Propósito: identificar datos conflictivos que impedirán crear los índices
--            únicos o los checks de formato. Corregir o unificar antes de migrar.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Duplicados por EMAIL (case-insensitive)
-- ─────────────────────────────────────────────────────────────────────────────
select
  lower(trim(email)) as email_normalizado,
  count(*) as total,
  array_agg(id order by created_at) as ids,
  array_agg(business_name order by created_at) as razones_sociales,
  array_agg(created_at order by created_at) as fechas_creacion
from public.clients
where email is not null and trim(email) <> ''
group by lower(trim(email))
having count(*) > 1
order by total desc;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Duplicados por RFC (case-insensitive)
-- ─────────────────────────────────────────────────────────────────────────────
select
  upper(trim(rfc)) as rfc_normalizado,
  count(*) as total,
  array_agg(id order by created_at) as ids,
  array_agg(business_name order by created_at) as razones_sociales,
  array_agg(email order by created_at) as correos
from public.clients
where rfc is not null and trim(rfc) <> ''
group by upper(trim(rfc))
having count(*) > 1
order by total desc;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Duplicados por TELÉFONO (normalizado a 10 dígitos o E.164)
-- ─────────────────────────────────────────────────────────────────────────────
select
  regexp_replace(phone, '[^0-9]', '', 'g') as phone_digits,
  count(*) as total,
  array_agg(id order by created_at) as ids,
  array_agg(business_name order by created_at) as razones_sociales
from public.clients
where phone is not null and trim(phone) <> ''
group by regexp_replace(phone, '[^0-9]', '', 'g')
having count(*) > 1
order by total desc;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Duplicados por RAZÓN SOCIAL (case-insensitive)
-- ─────────────────────────────────────────────────────────────────────────────
select
  upper(trim(business_name)) as razon_social_normalizada,
  count(*) as total,
  array_agg(id order by created_at) as ids,
  array_agg(email order by created_at) as correos
from public.clients
group by upper(trim(business_name))
having count(*) > 1
order by total desc;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. RFC con formato inválido (no cumple regex MX)
-- ─────────────────────────────────────────────────────────────────────────────
select
  id, business_name, rfc, email,
  length(trim(rfc)) as longitud
from public.clients
where rfc is not null
  and trim(rfc) <> ''
  and (
    upper(trim(rfc)) !~ '^[A-Z&Ñ]{3,4}[0-9]{6}[A-Z0-9]{3}$'
    or length(trim(rfc)) not in (12, 13)
  )
order by business_name;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Teléfonos con formato no normalizable a E.164
-- ─────────────────────────────────────────────────────────────────────────────
select
  id, business_name, phone,
  length(regexp_replace(phone, '[^0-9]', '', 'g')) as num_digitos
from public.clients
where phone is not null
  and trim(phone) <> ''
  and phone !~ '^\+52[0-9]{10}$'
  and length(regexp_replace(phone, '[^0-9]', '', 'g')) not in (10, 12)
order by business_name;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Correos con formato básico inválido
-- ─────────────────────────────────────────────────────────────────────────────
select
  id, business_name, email
from public.clients
where email is not null
  and trim(email) <> ''
  and email !~ '^[^@\s]{4,}@[^@\s]+\.[^@\s]+$'
order by business_name;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Dirección fuera del rango de longitud o sin letras+números
-- ─────────────────────────────────────────────────────────────────────────────
select
  id, business_name, address_line,
  length(trim(address_line)) as longitud
from public.clients
where address_line is not null
  and trim(address_line) <> ''
  and (
    length(trim(address_line)) < 10
    or length(trim(address_line)) > 255
    or trim(address_line) !~ '[A-Za-záéíóúüñÁÉÍÓÚÜÑ]'
    or trim(address_line) !~ '[0-9]'
  )
order by business_name;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. Resumen de estado: ¿listo para migrar?
--    Si todas las consultas anteriores devuelven 0 filas, la BD está limpia.
-- ─────────────────────────────────────────────────────────────────────────────
select 'duplicados_email'       as tipo, count(*) as conflictos
from (
  select lower(trim(email)) from public.clients
  where email is not null and trim(email) <> ''
  group by 1 having count(*) > 1
) t
union all
select 'duplicados_rfc', count(*)
from (
  select upper(trim(rfc)) from public.clients
  where rfc is not null and trim(rfc) <> ''
  group by 1 having count(*) > 1
) t
union all
select 'duplicados_phone', count(*)
from (
  select regexp_replace(phone, '[^0-9]', '', 'g') from public.clients
  where phone is not null and trim(phone) <> ''
  group by 1 having count(*) > 1
) t
union all
select 'duplicados_business_name', count(*)
from (
  select upper(trim(business_name)) from public.clients
  group by 1 having count(*) > 1
) t
union all
select 'rfc_formato_invalido', count(*)
from public.clients
where rfc is not null and trim(rfc) <> ''
  and (upper(trim(rfc)) !~ '^[A-Z&Ñ]{3,4}[0-9]{6}[A-Z0-9]{3}$'
       or length(trim(rfc)) not in (12, 13))
union all
select 'phone_no_normalizable', count(*)
from public.clients
where phone is not null and trim(phone) <> ''
  and phone !~ '^\+52[0-9]{10}$'
  and length(regexp_replace(phone, '[^0-9]', '', 'g')) not in (10, 12)
order by tipo;

-- Si todos los valores en "conflictos" son 0, ejecuta la migración.
-- Si alguno es > 0, resuelve primero los conflictos (merge, corrección o archivado).
