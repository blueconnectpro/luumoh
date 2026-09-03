create or replace function public.admin_remove_store_member(
  p_store_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can manage store membership';
  end if;

  delete from public.store_members
  where store_id = p_store_id
    and user_id = p_user_id;

  if not found then
    raise exception 'Store membership not found';
  end if;
end;
$$;

create or replace function public.admin_update_store_status(
  p_store_id uuid,
  p_is_open boolean default null,
  p_is_active boolean default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can update store status';
  end if;

  update public.stores
  set is_open = coalesce(p_is_open, is_open),
      is_active = coalesce(p_is_active, is_active)
  where id = p_store_id;

  if not found then
    raise exception 'Store not found';
  end if;
end;
$$;
