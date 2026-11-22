insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('bill-receipts', 'bill-receipts', false, 5242880, array['application/pdf'])
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Shop members upload bill receipts" on storage.objects;
create policy "Shop members upload bill receipts"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'bill-receipts'
  and exists (
    select 1 from public.shop_members m
    where m.shop_id::text = (storage.foldername(name))[1]
      and m.user_id = auth.uid()
  )
  and exists (
    select 1 from public.bills b
    where b.shop_id::text = (storage.foldername(name))[1]
      and b.id::text = (storage.foldername(name))[2]
      and (b.created_by = auth.uid() or public.is_shop_owner(b.shop_id))
  )
);

drop policy if exists "Shop members read bill receipts" on storage.objects;
create policy "Shop members read bill receipts"
on storage.objects for select to authenticated
using (
  bucket_id = 'bill-receipts'
  and exists (
    select 1 from public.shop_members m
    where m.shop_id::text = (storage.foldername(name))[1]
      and m.user_id = auth.uid()
  )
);

drop policy if exists "Shop members update bill receipts" on storage.objects;
