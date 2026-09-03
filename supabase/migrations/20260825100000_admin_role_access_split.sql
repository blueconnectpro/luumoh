alter type public.profile_role add value if not exists 'rider_admin';
alter type public.profile_role add value if not exists 'super_admin';

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    public.current_profile_role()::text in ('admin', 'super_admin'),
    false
  )
$$;

create or replace function public.is_rider_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_profile_role()::text = 'rider_admin', false)
$$;

drop policy if exists "profiles rider admins read riders" on public.profiles;
create policy "profiles rider admins read riders" on public.profiles
  for select using (public.is_rider_admin() and role = 'rider');

drop policy if exists "orders rider admins read rider orders" on public.orders;
create policy "orders rider admins read rider orders" on public.orders
  for select using (public.is_rider_admin() and rider_id is not null);

drop policy if exists "rider availability rider admins read" on public.rider_availability;
create policy "rider availability rider admins read" on public.rider_availability
  for select using (public.is_rider_admin());

drop policy if exists "rider settlements rider admins read" on public.rider_settlements;
create policy "rider settlements rider admins read" on public.rider_settlements
  for select using (public.is_rider_admin());

drop policy if exists "rider location rider admins read" on public.rider_location_updates;
create policy "rider location rider admins read" on public.rider_location_updates
  for select using (
    public.is_rider_admin()
    and exists (
      select 1
      from public.orders o
      where o.id = order_id
        and o.rider_id is not null
    )
  );

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
    if not (
      public.is_rider_admin()
      and p_role::text = 'customer'
      and exists (
        select 1
        from public.profiles
        where id = p_user_id
          and role = 'rider'
      )
    ) then
      raise exception 'Only admins can change profile roles';
    end if;
  end if;

  update public.profiles
  set role = p_role
  where id = p_user_id;

  if not found then
    raise exception 'Profile not found';
  end if;
end;
$$;
