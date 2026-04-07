drop policy if exists client_logos_select on storage.objects;
create policy client_logos_select on storage.objects
for select to anon, authenticated
using (bucket_id = 'client-logos');

drop policy if exists client_logos_insert on storage.objects;
create policy client_logos_insert on storage.objects
for insert to anon, authenticated
with check (bucket_id = 'client-logos');

drop policy if exists client_logos_update on storage.objects;
create policy client_logos_update on storage.objects
for update to anon, authenticated
using (bucket_id = 'client-logos')
with check (bucket_id = 'client-logos');

drop policy if exists client_logos_delete on storage.objects;
create policy client_logos_delete on storage.objects
for delete to anon, authenticated
using (bucket_id = 'client-logos');
