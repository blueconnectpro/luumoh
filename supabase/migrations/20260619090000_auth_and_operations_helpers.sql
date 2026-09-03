create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, role, full_name, phone)
  values (
    new.id,
    'customer',
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    new.raw_user_meta_data->>'phone'
  )
  on conflict (id) do update
  set full_name = excluded.full_name,
      phone = excluded.phone;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

drop policy if exists "profiles insert own customer row" on public.profiles;
create policy "profiles insert own customer row" on public.profiles
  for insert
  with check (id = auth.uid() and role = 'customer');

create or replace function public.claim_first_admin()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if exists (select 1 from public.profiles where role = 'admin') then
    raise exception 'An admin already exists';
  end if;

  update public.profiles
  set role = 'admin'
  where id = auth.uid();

  if not found then
    raise exception 'Profile not found for current user';
  end if;
end;
$$;

create or replace function public.admin_set_profile_role(
  p_user_id uuid,
  p_role public.profile_role
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can change profile roles';
  end if;

  update public.profiles
  set role = p_role
  where id = p_user_id;

  if not found then
    raise exception 'Profile not found';
  end if;
end;
$$;

create or replace function public.admin_add_store_member(
  p_store_id uuid,
  p_user_id uuid,
  p_can_manage_inventory boolean default true,
  p_can_manage_orders boolean default true
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

  insert into public.store_members (
    store_id,
    user_id,
    can_manage_inventory,
    can_manage_orders
  )
  values (
    p_store_id,
    p_user_id,
    p_can_manage_inventory,
    p_can_manage_orders
  )
  on conflict (store_id, user_id) do update
  set can_manage_inventory = excluded.can_manage_inventory,
      can_manage_orders = excluded.can_manage_orders;
end;
$$;

create or replace function public.store_update_order_status(
  p_order_id uuid,
  p_status public.order_status
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
begin
  select store_id
  into v_store_id
  from public.orders
  where id = p_order_id;

  if v_store_id is null then
    raise exception 'Order not found';
  end if;

  if not public.is_store_member(v_store_id) then
    raise exception 'Not allowed';
  end if;

  if p_status not in ('accepted', 'preparing', 'ready_for_pickup', 'cancelled') then
    raise exception 'Store cannot set order status to %', p_status;
  end if;

  update public.orders
  set status = p_status
  where id = p_order_id
    and payment_status = 'paid';

  if not found then
    raise exception 'Only paid orders can be updated by stores';
  end if;

  insert into public.delivery_events(order_id, status, note)
  values (p_order_id, p_status, 'Store updated order status');
end;
$$;

create or replace function public.admin_create_store(
  p_name text,
  p_category text,
  p_address text,
  p_owner_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Only admins can create stores';
  end if;

  insert into public.stores (owner_id, name, category, address, is_active, is_open)
  values (p_owner_id, p_name, p_category, p_address, true, true)
  returning id into v_store_id;

  if p_owner_id is not null then
    insert into public.store_members (store_id, user_id)
    values (v_store_id, p_owner_id)
    on conflict (store_id, user_id) do nothing;
  end if;

  return v_store_id;
end;
$$;
