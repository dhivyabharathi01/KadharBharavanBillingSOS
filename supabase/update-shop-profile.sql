create or replace function public.update_shop_profile(
  p_shop_id uuid,
  p_name text,
  p_address text,
  p_phone text
) returns void language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_shop_owner(p_shop_id) then raise exception 'Only the shop owner can update shop details'; end if;
  if nullif(trim(p_name),'') is null then raise exception 'Shop name is required'; end if;
  if length(trim(p_name)) > 120 or length(coalesce(p_address,'')) > 300 or length(coalesce(p_phone,'')) > 40 then
    raise exception 'Shop details exceed the allowed length';
  end if;
  update public.shops
    set name=trim(p_name),address=nullif(trim(p_address),''),phone=nullif(trim(p_phone),'')
    where id=p_shop_id;
end;
$$;

revoke all on function public.update_shop_profile(uuid,text,text,text) from public,anon;
grant execute on function public.update_shop_profile(uuid,text,text,text) to authenticated;
