-- Restrict catalog changes to shop owners and allow owners to assign existing
-- Supabase Auth users as billing staff.

drop policy if exists "members manage their shop items" on public.items;
drop policy if exists "members read their shop items" on public.items;
drop policy if exists "owners add shop items" on public.items;
drop policy if exists "owners update shop items" on public.items;
drop policy if exists "owners delete shop items" on public.items;

create policy "members read their shop items"
  on public.items for select to authenticated
  using (public.is_shop_member(shop_id));
create policy "owners add shop items"
  on public.items for insert to authenticated
  with check (public.is_shop_owner(shop_id));
create policy "owners update shop items"
  on public.items for update to authenticated
  using (public.is_shop_owner(shop_id))
  with check (public.is_shop_owner(shop_id));
create policy "owners delete shop items"
  on public.items for delete to authenticated
  using (public.is_shop_owner(shop_id));

grant select,insert,update,delete on public.items to authenticated;

create or replace function public.add_shop_staff(
  p_shop_id uuid,
  p_email text,
  p_display_name text
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_user_id uuid;
  v_added_user_id uuid;
begin
  if not public.is_shop_owner(p_shop_id) then
    raise exception 'Only the shop owner can add staff';
  end if;
  if nullif(trim(p_email),'') is null or position('@' in trim(p_email)) < 2 then
    raise exception 'Enter a valid staff email address';
  end if;
  if nullif(trim(p_display_name),'') is null then
    raise exception 'Enter the staff member name';
  end if;

  select id into v_user_id
  from auth.users
  where lower(email)=lower(trim(p_email))
  limit 1;
  if v_user_id is null then
    raise exception 'No account found for this email. Ask the staff member to register first';
  end if;

  insert into public.shop_members(shop_id,user_id,display_name,role)
  values(p_shop_id,v_user_id,trim(p_display_name),'staff')
  on conflict(shop_id,user_id) do nothing
  returning user_id into v_added_user_id;
  if v_added_user_id is null then
    raise exception 'This account is already assigned to this shop';
  end if;

  return v_user_id;
end;
$$;

revoke all on function public.add_shop_staff(uuid,text,text) from public,anon;
grant execute on function public.add_shop_staff(uuid,text,text) to authenticated;
