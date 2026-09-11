-- Restrict supporting catalogs and ensure the usage view honors caller RLS.

alter table public.client_sector_tags enable row level security;
alter table public.client_sector_codes enable row level security;
alter table public.currency_rates_cache enable row level security;

drop policy if exists client_sector_tags_read_authenticated on public.client_sector_tags;
create policy client_sector_tags_read_authenticated on public.client_sector_tags
  for select to authenticated using (true);

drop policy if exists client_sector_tags_write_authenticated on public.client_sector_tags;
create policy client_sector_tags_write_authenticated on public.client_sector_tags
  for insert to authenticated with check (true);

drop policy if exists client_sector_codes_service_only on public.client_sector_codes;
create policy client_sector_codes_service_only on public.client_sector_codes
  for all to service_role using (true) with check (true);

drop policy if exists currency_rates_cache_service_only on public.currency_rates_cache;
create policy currency_rates_cache_service_only on public.currency_rates_cache
  for all to service_role using (true) with check (true);

alter view public.concept_usage_view set (security_invoker = true);
revoke all on public.concept_usage_view from anon;
grant select on public.concept_usage_view to authenticated;

create policy memory_state_service_only on public.memory_state
  for all to service_role using (true) with check (true);

create policy memory_summary_service_only on public.memory_summary
  for all to service_role using (true) with check (true);

create policy memory_logs_service_only on public.memory_logs
  for all to service_role using (true) with check (true);

alter function public.memory_set_updated_at() set search_path = public, pg_temp;
alter function public.quote_status_timestamps() set search_path = public, pg_temp;
alter function public.invoices_set_updated_at() set search_path = public, pg_temp;
alter function public.is_admin() set search_path = public, pg_temp;
alter function public.is_super_admin() set search_path = public, pg_temp;
alter function public.sector_code_from_label(text) set search_path = public, pg_temp;
alter function public.project_type_code_from_name(text) set search_path = public, pg_temp;
alter function public.next_project_key() set search_path = public, pg_temp;
alter function public.next_structured_project_key(uuid, uuid) set search_path = public, pg_temp;

revoke execute on function public.next_project_key() from public;
revoke execute on function public.next_structured_project_key(uuid, uuid) from public;
grant execute on function public.next_project_key() to authenticated;
grant execute on function public.next_structured_project_key(uuid, uuid) to authenticated;