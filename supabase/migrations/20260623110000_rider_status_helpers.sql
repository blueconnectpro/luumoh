create or replace function public.rider_update_order_status(
  p_order_id uuid,
  p_status public.order_status,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_profile_role() not in ('rider', 'admin') then
    raise exception 'Only riders can update delivery status';
  end if;

  if p_status not in ('out_for_delivery', 'delivered') then
    raise exception 'Riders cannot set order status to %', p_status;
  end if;

  update public.orders
  set status = p_status,
      eta_minutes = case when p_status = 'delivered' then 0 else eta_minutes end,
      eta_updated_at = case when p_status = 'delivered' then now() else eta_updated_at end
  where id = p_order_id
    and payment_status = 'paid'
    and (rider_id = auth.uid() or public.is_admin())
    and status in ('out_for_delivery', 'ready_for_pickup');

  if not found then
    raise exception 'Order is not assigned to this rider';
  end if;

  insert into public.delivery_events(order_id, rider_id, status, eta_minutes, note)
  values (
    p_order_id,
    auth.uid(),
    p_status,
    case when p_status = 'delivered' then 0 else null end,
    coalesce(p_note, 'Rider updated delivery status')
  );
end;
$$;
