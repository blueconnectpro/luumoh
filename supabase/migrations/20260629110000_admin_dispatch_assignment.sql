create or replace function public.admin_assign_order_rider(
  p_order_id uuid,
  p_rider_id uuid,
  p_eta_minutes integer default null,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can assign riders';
  end if;

  if p_eta_minutes is not null and p_eta_minutes < 0 then
    raise exception 'ETA cannot be negative';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = p_rider_id
      and p.role = 'rider'
  ) then
    raise exception 'Selected user is not a rider';
  end if;

  if not exists (
    select 1
    from public.rider_availability ra
    where ra.rider_id = p_rider_id
      and ra.is_online = true
  ) then
    raise exception 'Selected rider is offline';
  end if;

  update public.orders
  set rider_id = p_rider_id,
      status = 'out_for_delivery',
      eta_minutes = p_eta_minutes,
      eta_updated_at = case
        when p_eta_minutes is null then eta_updated_at
        else now()
      end
  where id = p_order_id
    and payment_status = 'paid'
    and status in ('ready_for_pickup', 'out_for_delivery');

  if not found then
    raise exception 'Order is not ready for rider assignment';
  end if;

  insert into public.delivery_events(
    order_id,
    rider_id,
    status,
    eta_minutes,
    note
  )
  values (
    p_order_id,
    p_rider_id,
    'out_for_delivery',
    p_eta_minutes,
    coalesce(p_note, 'Admin assigned rider')
  );
end;
$$;
