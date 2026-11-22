begin;

create or replace function public.update_shop_item_discount(
  p_shop_id uuid,
  p_item_id uuid,
  p_discount_percent numeric
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_discount_percent numeric;
  v_item public.items%rowtype;
begin
  if auth.uid() is null or not public.is_shop_member(p_shop_id) then
    raise exception 'Not a member of this shop';
  end if;
  if p_discount_percent is null
    or p_discount_percent::text in ('NaN','Infinity','-Infinity')
    or p_discount_percent < 0
    or p_discount_percent > 100 then
    raise exception 'Item discount must be between 0 and 100 percent';
  end if;

  v_discount_percent := round(p_discount_percent,2);
  update public.items
    set discount_percent=v_discount_percent,updated_at=now()
    where id=p_item_id and shop_id=p_shop_id and deleted=false
    returning * into v_item;
  if not found then
    raise exception 'Item not found in this shop';
  end if;

  return jsonb_build_object(
    'id',v_item.id,
    'mrp',v_item.mrp,
    'price',v_item.price,
    'discount_percent',v_item.discount_percent
  );
end;
$$;

revoke all on function public.update_shop_item_discount(uuid,uuid,numeric) from public,anon;
grant execute on function public.update_shop_item_discount(uuid,uuid,numeric) to authenticated;

commit;
