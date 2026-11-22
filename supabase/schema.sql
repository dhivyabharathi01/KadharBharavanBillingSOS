-- Multi-shop billing starter. One business can own several shops, and each user
-- can be assigned to one or more shops through shop_members.

create extension if not exists pgcrypto;

create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table public.shops (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  address text,
  phone text,
  upi_id text check (upi_id is null or upi_id ~ '^[A-Za-z0-9._-]{2,100}@[A-Za-z0-9.-]{2,50}$'),
  created_at timestamptz not null default now()
);

create table public.shop_members (
  shop_id uuid not null references public.shops(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null,
  role text not null check (role in ('owner','staff')),
  created_at timestamptz not null default now(),
  primary key (shop_id,user_id)
);

create table public.shop_upi_change_requests (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  requested_by uuid not null references auth.users(id) on delete cascade,
  new_upi_id text not null check (new_upi_id ~ '^[A-Za-z0-9._-]{2,100}@[A-Za-z0-9.-]{2,50}$'),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.items (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  name text not null,
  name_ta text,
  price numeric(12,2) not null check (price >= 0),
  deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table public.bills (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  client_request_id uuid,
  bill_number text not null,
  created_by uuid not null references auth.users(id),
  customer_name text,
  customer_mobile text,
  subtotal numeric(12,2) not null check (subtotal >= 0),
  discount numeric(12,2) not null default 0 check (discount >= 0),
  total numeric(12,2) not null check (total >= 0),
  deleted boolean not null default false,
  created_at timestamptz not null default now(),
  unique (shop_id,bill_number),
  unique (shop_id,client_request_id)
);

create table public.bill_items (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  bill_id uuid not null references public.bills(id) on delete cascade,
  item_id uuid references public.items(id) on delete set null,
  item_name text not null,
  item_name_ta text,
  quantity numeric(10,2) not null check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  line_total numeric(12,2) not null check (line_total >= 0),
  created_at timestamptz not null default now()
);

create table public.bill_counters (
  shop_id uuid primary key references public.shops(id) on delete cascade,
  last_number bigint not null default 0
);

create index items_shop_idx on public.items(shop_id,deleted,name);
create index bills_shop_date_idx on public.bills(shop_id,created_at desc);
create index bill_items_bill_idx on public.bill_items(bill_id);
create index shop_members_user_idx on public.shop_members(user_id,shop_id);

create or replace function public.is_shop_member(target_shop uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.shop_members m where m.shop_id=target_shop and m.user_id=auth.uid()) $$;

create or replace function public.is_shop_owner(target_shop uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.shop_members m where m.shop_id=target_shop and m.user_id=auth.uid() and m.role='owner') $$;

alter table public.shops enable row level security;
alter table public.businesses enable row level security;
alter table public.shop_members enable row level security;
alter table public.shop_upi_change_requests enable row level security;
alter table public.items enable row level security;
alter table public.bills enable row level security;
alter table public.bill_items enable row level security;
alter table public.bill_counters enable row level security;

create policy "members read their business" on public.businesses for select to authenticated using (exists (select 1 from public.shops s where s.business_id=id and public.is_shop_member(s.id)));
create policy "members read their shop" on public.shops for select to authenticated using (public.is_shop_member(id));
create policy "members read shop memberships" on public.shop_members for select to authenticated using (user_id=auth.uid() or public.is_shop_member(shop_id));
create policy "members read their UPI requests" on public.shop_upi_change_requests for select to authenticated using (requested_by=auth.uid() or public.is_shop_owner(shop_id));
create policy "members request UPI changes" on public.shop_upi_change_requests for insert to authenticated with check (requested_by=auth.uid() and public.is_shop_member(shop_id) and status='pending');
create policy "members read their shop items" on public.items for select to authenticated using (public.is_shop_member(shop_id));
create policy "owners add shop items" on public.items for insert to authenticated with check (public.is_shop_owner(shop_id));
create policy "owners update shop items" on public.items for update to authenticated using (public.is_shop_owner(shop_id)) with check (public.is_shop_owner(shop_id));
create policy "owners delete shop items" on public.items for delete to authenticated using (public.is_shop_owner(shop_id));
create policy "members read their shop bills" on public.bills for select to authenticated using (public.is_shop_member(shop_id));
create policy "members read their shop bill items" on public.bill_items for select to authenticated using (public.is_shop_member(shop_id));

revoke all on public.businesses,public.shops,public.shop_members,public.shop_upi_change_requests,public.items,public.bills,public.bill_items,public.bill_counters from anon,authenticated;
grant usage on schema public to authenticated;
grant select on public.businesses,public.shops,public.shop_members,public.bills,public.bill_items,public.shop_upi_change_requests to authenticated;
grant insert on public.shop_upi_change_requests to authenticated;
grant select,insert,update,delete on public.items to authenticated;
revoke all on function public.is_shop_member(uuid) from public,anon;
grant execute on function public.is_shop_member(uuid) to authenticated;
revoke all on function public.is_shop_owner(uuid) from public,anon;
grant execute on function public.is_shop_owner(uuid) to authenticated;

create or replace function public.register_business_shop(
  p_business_id uuid,
  p_name text,
  p_address text,
  p_phone text,
  p_upi_id text
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_shop_id uuid := gen_random_uuid(); v_display_name text;
begin
  if not exists (select 1 from public.shops s join public.shop_members m on m.shop_id=s.id where s.business_id=p_business_id and m.user_id=auth.uid() and m.role='owner') then
    raise exception 'Only a business owner can register a shop';
  end if;
  if nullif(trim(p_name),'') is null then raise exception 'Shop name is required'; end if;
  if p_upi_id is null or trim(p_upi_id) !~ '^[A-Za-z0-9._-]{2,100}@[A-Za-z0-9.-]{2,50}$' then raise exception 'A valid shop UPI ID is required'; end if;
  select m.display_name into v_display_name from public.shops s join public.shop_members m on m.shop_id=s.id where s.business_id=p_business_id and m.user_id=auth.uid() and m.role='owner' limit 1;
  insert into public.shops(id,business_id,name,address,phone,upi_id) values(v_shop_id,p_business_id,trim(p_name),nullif(trim(p_address),''),nullif(trim(p_phone),''),nullif(trim(p_upi_id),''));
  insert into public.shop_members(shop_id,user_id,display_name,role) values(v_shop_id,auth.uid(),v_display_name,'owner');
  return v_shop_id;
end;
$$;

create or replace function public.set_shop_upi_id(p_shop_id uuid,p_upi_id text)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_shop_owner(p_shop_id) then raise exception 'Only the shop owner can set the UPI ID'; end if;
  if p_upi_id is not null and trim(p_upi_id) !~ '^[A-Za-z0-9._-]{2,100}@[A-Za-z0-9.-]{2,50}$' then raise exception 'Invalid UPI ID'; end if;
  update public.shops set upi_id=nullif(trim(p_upi_id),'') where id=p_shop_id;
end;
$$;

create or replace function public.add_shop_staff(p_shop_id uuid,p_email text,p_display_name text)
returns uuid language plpgsql security definer set search_path = public
as $$
declare v_user_id uuid; v_added_user_id uuid;
begin
  if not public.is_shop_owner(p_shop_id) then raise exception 'Only the shop owner can add staff'; end if;
  if nullif(trim(p_email),'') is null or position('@' in trim(p_email)) < 2 then raise exception 'Enter a valid staff email address'; end if;
  if nullif(trim(p_display_name),'') is null then raise exception 'Enter the staff member name'; end if;
  select id into v_user_id from auth.users where lower(email)=lower(trim(p_email)) limit 1;
  if v_user_id is null then raise exception 'No account found for this email. Ask the staff member to register first'; end if;
  insert into public.shop_members(shop_id,user_id,display_name,role)
  values(p_shop_id,v_user_id,trim(p_display_name),'staff')
  on conflict(shop_id,user_id) do nothing
  returning user_id into v_added_user_id;
  if v_added_user_id is null then raise exception 'This account is already assigned to this shop'; end if;
  return v_user_id;
end;
$$;

create or replace function public.review_shop_upi_change(p_request_id uuid,p_approved boolean)
returns void language plpgsql security definer set search_path = public
as $$
declare v_request public.shop_upi_change_requests%rowtype;
begin
  select * into v_request from public.shop_upi_change_requests where id=p_request_id for update;
  if not found then raise exception 'UPI change request not found'; end if;
  if not public.is_shop_owner(v_request.shop_id) then raise exception 'Only the shop owner can review this request'; end if;
  if v_request.status <> 'pending' then raise exception 'This request was already reviewed'; end if;
  if p_approved then update public.shops set upi_id=v_request.new_upi_id where id=v_request.shop_id; end if;
  update public.shop_upi_change_requests set status=case when p_approved then 'approved' else 'rejected' end,reviewed_by=auth.uid(),reviewed_at=now() where id=p_request_id;
end;
$$;

create or replace function public.create_shop_bill(
  p_shop_id uuid,
  p_customer_name text,
  p_customer_mobile text,
  p_discount numeric,
  p_items jsonb,
  p_client_request_id uuid default null
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_seq bigint;
  v_number text;
  v_existing_created timestamptz;
  v_bill_id uuid := gen_random_uuid();
  v_existing_bill_id uuid;
  v_existing_subtotal numeric(12,2);
  v_subtotal numeric(12,2) := 0;
  v_existing_discount numeric(12,2);
  v_total numeric(12,2);
  v_line record;
begin
  if not public.is_shop_member(p_shop_id) then
    raise exception 'Not a member of this shop';
  end if;
  if p_client_request_id is not null then
    select id,bill_number,created_at,subtotal,discount,total into v_existing_bill_id,v_number,v_existing_created,v_existing_subtotal,v_existing_discount,v_total
      from public.bills where shop_id=p_shop_id and client_request_id=p_client_request_id;
    if found then
      return jsonb_build_object('id',v_existing_bill_id,'bill_number',v_number,'created_at',v_existing_created,'subtotal',v_existing_subtotal,'discount',v_existing_discount,'total',v_total);
    end if;
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'A bill must contain at least one item';
  end if;

  for v_line in select * from jsonb_to_recordset(p_items) as x(
    item_id uuid,item_name text,item_name_ta text,quantity numeric,unit_price numeric
  ) loop
    if v_line.quantity <= 0 or v_line.unit_price < 0 or v_line.item_name is null then
      raise exception 'Invalid bill item';
    end if;
    if v_line.item_id is not null and not exists (select 1 from public.items i where i.id=v_line.item_id and i.shop_id=p_shop_id and not i.deleted and i.price=v_line.unit_price) then
      raise exception 'A bill item is not in this shop catalog';
    end if;
    v_subtotal := v_subtotal + round(v_line.quantity * v_line.unit_price,2);
  end loop;
  if p_discount < 0 or p_discount > v_subtotal then
    raise exception 'Discount exceeds the bill subtotal';
  end if;
  v_total := v_subtotal - p_discount;

  insert into public.bill_counters(shop_id,last_number) values(p_shop_id,1)
  on conflict(shop_id) do update set last_number=public.bill_counters.last_number+1
  returning last_number into v_seq;
  v_number := 'KB-' || lpad(v_seq::text,6,'0');

  insert into public.bills(id,shop_id,client_request_id,bill_number,created_by,customer_name,customer_mobile,subtotal,discount,total)
  values(v_bill_id,p_shop_id,p_client_request_id,v_number,auth.uid(),p_customer_name,p_customer_mobile,v_subtotal,p_discount,v_total);

  for v_line in select * from jsonb_to_recordset(p_items) as x(
    item_id uuid,item_name text,item_name_ta text,quantity numeric,unit_price numeric
  ) loop
    insert into public.bill_items(shop_id,bill_id,item_id,item_name,item_name_ta,quantity,unit_price,line_total)
    values(p_shop_id,v_bill_id,v_line.item_id,v_line.item_name,v_line.item_name_ta,v_line.quantity,v_line.unit_price,round(v_line.quantity*v_line.unit_price,2));
  end loop;

  return jsonb_build_object('id',v_bill_id,'bill_number',v_number,'created_at',now(),'subtotal',v_subtotal,'discount',p_discount,'total',v_total);
end;
$$;

revoke all on function public.create_shop_bill(uuid,text,text,numeric,jsonb,uuid) from public,anon;
grant execute on function public.create_shop_bill(uuid,text,text,numeric,jsonb,uuid) to authenticated;

revoke all on function public.register_business_shop(uuid,text,text,text,text) from public,anon;
grant execute on function public.register_business_shop(uuid,text,text,text,text) to authenticated;
revoke all on function public.set_shop_upi_id(uuid,text) from public,anon;
grant execute on function public.set_shop_upi_id(uuid,text) to authenticated;
revoke all on function public.add_shop_staff(uuid,text,text) from public,anon;
grant execute on function public.add_shop_staff(uuid,text,text) to authenticated;
revoke all on function public.review_shop_upi_change(uuid,boolean) from public,anon;
grant execute on function public.review_shop_upi_change(uuid,boolean) to authenticated;

-- Do not put a Supabase secret/service_role key in config.js. The browser uses
-- only the project's publishable key; RLS and the RPC enforce shop membership.

-- register_owner: called right after a brand-new user signs up.
-- Creates a business, creates the first shop, and adds the user as owner.
create or replace function public.register_owner(
  p_business_name text,
  p_shop_name     text,
  p_display_name  text,
  p_upi_id        text,
  p_address       text default null,
  p_phone         text default null
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_business_id uuid := gen_random_uuid();
  v_shop_id     uuid := gen_random_uuid();
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if nullif(trim(p_business_name),'') is null then raise exception 'Business name is required'; end if;
  if nullif(trim(p_shop_name),'') is null then raise exception 'Shop name is required'; end if;
  if nullif(trim(p_display_name),'') is null then raise exception 'Display name is required'; end if;
  if p_upi_id is null or trim(p_upi_id) !~ '^[A-Za-z0-9._-]{2,100}@[A-Za-z0-9.-]{2,50}$' then
    raise exception 'A valid UPI ID is required (e.g. shopname@upi)';
  end if;
  -- Prevent duplicate registrations
  if exists (select 1 from public.shop_members where user_id=auth.uid()) then
    raise exception 'Your account is already linked to a shop. Please sign in instead.';
  end if;
  insert into public.businesses(id,name) values(v_business_id,trim(p_business_name));
  insert into public.shops(id,business_id,name,address,phone,upi_id)
    values(v_shop_id,v_business_id,trim(p_shop_name),
           nullif(trim(coalesce(p_address,'')),''),
           nullif(trim(coalesce(p_phone,'')),''),
           nullif(trim(p_upi_id),''));
  insert into public.shop_members(shop_id,user_id,display_name,role)
    values(v_shop_id,auth.uid(),trim(p_display_name),'owner');
  insert into public.bill_counters(shop_id,last_number) values(v_shop_id,0);
  return jsonb_build_object('business_id',v_business_id,'shop_id',v_shop_id);
end;
$$;

revoke all on function public.register_owner(text,text,text,text,text,text) from public,anon;
grant execute on function public.register_owner(text,text,text,text,text,text) to authenticated;
