begin;

alter table public.items
  add column if not exists mrp numeric(12,2),
  add column if not exists discount_percent numeric(5,2) not null default 0;

update public.items set mrp=price where mrp is null;
alter table public.items alter column mrp set not null;

do $$
begin
  alter table public.items
    add constraint items_mrp_nonnegative check (mrp >= 0);
exception when duplicate_object then
  null;
end;
$$;

do $$
begin
  alter table public.items
    add constraint items_discount_percent_range check (discount_percent between 0 and 100);
exception when duplicate_object then
  null;
end;
$$;

create or replace function public.sync_item_discounted_price()
returns trigger language plpgsql set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    new.mrp := coalesce(new.mrp,new.price);
    new.discount_percent := coalesce(new.discount_percent,0);
  elsif new.mrp is not distinct from old.mrp
    and new.discount_percent is not distinct from old.discount_percent
    and new.price is distinct from old.price then
    new.mrp := new.price;
    new.discount_percent := 0;
  end if;
  if new.mrp is null or new.mrp < 0 then
    raise exception 'MRP must be zero or greater';
  end if;
  if new.discount_percent is null or new.discount_percent < 0 or new.discount_percent > 100 then
    raise exception 'Product discount must be between 0 and 100 percent';
  end if;
  new.price := round(new.mrp * (100 - new.discount_percent) / 100,2);
  return new;
end;
$$;

drop trigger if exists items_sync_discounted_price on public.items;
create trigger items_sync_discounted_price
before insert or update of price,mrp,discount_percent on public.items
for each row execute function public.sync_item_discounted_price();

alter table public.bill_items
  add column if not exists unit_mrp numeric(12,2),
  add column if not exists unit_discount_percent numeric(5,2) not null default 0;

update public.bill_items set unit_mrp=unit_price where unit_mrp is null;
alter table public.bill_items alter column unit_mrp set not null;

do $$
begin
  alter table public.bill_items
    add constraint bill_items_unit_mrp_nonnegative check (unit_mrp >= 0);
exception when duplicate_object then
  null;
end;
$$;

do $$
begin
  alter table public.bill_items
    add constraint bill_items_unit_discount_percent_range check (unit_discount_percent between 0 and 100);
exception when duplicate_object then
  null;
end;
$$;

create or replace function public.create_shop_bill(
  p_shop_id uuid,
  p_customer_name text,
  p_customer_mobile text,
  p_discount numeric,
  p_items jsonb,
  p_payment_method text default 'upi',
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
  v_existing_product_savings numeric(12,2);
  v_existing_payment_method text;
  v_total numeric(12,2);
  v_discount numeric(12,2) := 0;
  v_product_savings numeric(12,2) := 0;
  v_line record;
  v_catalog_item public.items%rowtype;
  v_line_price numeric(12,2);
  v_line_mrp numeric(12,2);
  v_line_discount_percent numeric(5,2);
  v_line_name text;
  v_line_name_ta text;
begin
  if not public.is_shop_member(p_shop_id) then
    raise exception 'Not a member of this shop';
  end if;
  if p_client_request_id is not null then
    select id,bill_number,created_at,subtotal,discount,total,payment_method
      into v_existing_bill_id,v_number,v_existing_created,v_existing_subtotal,v_existing_discount,v_total,v_existing_payment_method
      from public.bills where shop_id=p_shop_id and client_request_id=p_client_request_id;
    if found then
      select coalesce(sum(round(quantity*(unit_mrp-unit_price),2)),0)
        into v_existing_product_savings
        from public.bill_items where bill_id=v_existing_bill_id;
      return jsonb_build_object('id',v_existing_bill_id,'bill_number',v_number,'created_at',v_existing_created,'subtotal',v_existing_subtotal,'discount',v_existing_discount,'total',v_total,'product_savings',v_existing_product_savings,'total_savings',v_existing_product_savings+v_existing_discount,'payment_method',v_existing_payment_method);
    end if;
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'A bill must contain at least one item';
  end if;

  for v_line in select * from jsonb_to_recordset(p_items) as x(item_id uuid,quantity numeric) loop
    if v_line.item_id is null or v_line.quantity is null or v_line.quantity::text in ('NaN','Infinity','-Infinity') or v_line.quantity <= 0 then
      raise exception 'Invalid bill item';
    end if;
    select * into v_catalog_item
      from public.items
      where id=v_line.item_id and shop_id=p_shop_id;
    if not found then raise exception 'A bill item is not in this shop catalog'; end if;
    v_subtotal := v_subtotal + round(v_line.quantity * v_catalog_item.price,2);
    v_product_savings := v_product_savings + round(v_line.quantity * (v_catalog_item.mrp-v_catalog_item.price),2);
  end loop;
  if p_discount is null or p_discount::text in ('NaN','Infinity','-Infinity') or p_discount < 0 or p_discount > v_subtotal then
    raise exception 'Discount exceeds the bill subtotal';
  end if;
  if p_payment_method is null or p_payment_method not in ('upi','cash') then
    raise exception 'Invalid payment method';
  end if;
  v_discount := round(p_discount,2);
  v_total := v_subtotal - v_discount;

  insert into public.bill_counters(shop_id,last_number) values(p_shop_id,1)
  on conflict(shop_id) do update set last_number=public.bill_counters.last_number+1
  returning last_number into v_seq;
  v_number := 'KB-' || lpad(v_seq::text,6,'0');

  insert into public.bills(id,shop_id,client_request_id,bill_number,created_by,customer_name,customer_mobile,subtotal,discount,total,payment_method)
  values(v_bill_id,p_shop_id,p_client_request_id,v_number,auth.uid(),p_customer_name,p_customer_mobile,v_subtotal,v_discount,v_total,p_payment_method);

  for v_line in select * from jsonb_to_recordset(p_items) as x(item_id uuid,quantity numeric) loop
    select * into v_catalog_item
      from public.items
      where id=v_line.item_id and shop_id=p_shop_id;
    v_line_price := v_catalog_item.price;
    v_line_mrp := v_catalog_item.mrp;
    v_line_discount_percent := v_catalog_item.discount_percent;
    v_line_name := v_catalog_item.name;
    v_line_name_ta := v_catalog_item.name_ta;
    insert into public.bill_items(shop_id,bill_id,item_id,item_name,item_name_ta,quantity,unit_price,unit_mrp,unit_discount_percent,line_total)
    values(p_shop_id,v_bill_id,v_line.item_id,v_line_name,v_line_name_ta,v_line.quantity,v_line_price,v_line_mrp,v_line_discount_percent,round(v_line.quantity*v_line_price,2));
  end loop;

  return jsonb_build_object('id',v_bill_id,'bill_number',v_number,'created_at',now(),'subtotal',v_subtotal,'discount',v_discount,'total',v_total,'product_savings',v_product_savings,'total_savings',v_product_savings+v_discount,'payment_method',p_payment_method);
end;
$$;

revoke all on function public.create_shop_bill(uuid,text,text,numeric,jsonb,text,uuid) from public,anon;
grant execute on function public.create_shop_bill(uuid,text,text,numeric,jsonb,text,uuid) to authenticated;

commit;
