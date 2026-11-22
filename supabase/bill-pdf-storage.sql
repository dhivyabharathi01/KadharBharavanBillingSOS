insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('bill-receipts', 'bill-receipts', false, 5242880, array['application/pdf'])
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.bill_receipt_links (
  token uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  bill_id uuid not null references public.bills(id) on delete cascade,
  link_type text not null default 'receipt',
  object_path text,
  payment_uri text,
  created_by uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

alter table public.bill_receipt_links add column if not exists link_type text not null default 'receipt';
alter table public.bill_receipt_links add column if not exists payment_uri text;
alter table public.bill_receipt_links alter column object_path drop not null;
do $$
begin
  alter table public.bill_receipt_links
    add constraint bill_receipt_links_target_check check (
      (link_type = 'receipt' and object_path is not null and payment_uri is null)
      or (link_type = 'payment' and object_path is null and payment_uri like 'upi://pay?%')
    );
exception when duplicate_object then
  null;
end;
$$;

alter table public.bill_receipt_links enable row level security;
revoke all on public.bill_receipt_links from anon,authenticated;
grant all on public.bill_receipt_links to service_role;
create index if not exists bill_receipt_links_expiry_idx on public.bill_receipt_links(expires_at);

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
