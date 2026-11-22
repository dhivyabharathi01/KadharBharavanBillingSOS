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
    select id,bill_number,created_at,subtotal,discount,total
      into v_existing_bill_id,v_number,v_existing_created,v_existing_subtotal,v_existing_discount,v_total
      from public.bills
      where shop_id=p_shop_id and client_request_id=p_client_request_id;
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
