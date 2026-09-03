insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'product-images',
  'product-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "product images public read"
on storage.objects;

create policy "product images public read" on storage.objects
  for select using (bucket_id = 'product-images');

drop policy if exists "product images store upload"
on storage.objects;

create policy "product images store upload" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'product-images'
    and (
      public.is_admin()
      or public.is_store_member(((storage.foldername(name))[1])::uuid)
    )
  );

drop policy if exists "product images store update"
on storage.objects;

create policy "product images store update" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'product-images'
    and (
      public.is_admin()
      or public.is_store_member(((storage.foldername(name))[1])::uuid)
    )
  )
  with check (
    bucket_id = 'product-images'
    and (
      public.is_admin()
      or public.is_store_member(((storage.foldername(name))[1])::uuid)
    )
  );

drop policy if exists "product images store delete"
on storage.objects;

create policy "product images store delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'product-images'
    and (
      public.is_admin()
      or public.is_store_member(((storage.foldername(name))[1])::uuid)
    )
  );
