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
  v_order record;
begin
  select id, store_id, status, payment_status, rider_id
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if not public.is_store_member(v_order.store_id) then
    raise exception 'Not allowed to update this order';
  end if;

  if v_order.payment_status <> 'paid' then
    raise exception 'Only paid orders can be updated by stores';
  end if;

  if p_status not in ('accepted', 'preparing', 'ready_for_pickup', 'cancelled') then
    raise exception 'Store cannot set order status to %', p_status;
  end if;

  if v_order.status in ('cancelled', 'out_for_delivery', 'delivered') then
    raise exception 'Order cannot be changed by store from %', v_order.status;
  end if;

  if p_status = 'accepted' and v_order.status <> 'paid' then
    raise exception 'Only newly paid orders can be accepted';
  end if;

  if p_status = 'preparing' and v_order.status not in ('paid', 'accepted') then
    raise exception 'Only paid or accepted orders can move to preparing';
  end if;

  if p_status = 'ready_for_pickup' and v_order.status not in ('accepted', 'preparing') then
    raise exception 'Only accepted or preparing orders can be marked ready';
  end if;

  if p_status = 'cancelled' and v_order.rider_id is not null then
    raise exception 'Assigned orders must be cancelled by admin operations';
  end if;

  if p_status = 'cancelled' then
    perform public.restore_order_stock_once(
      p_order_id,
      'Returned stock after store cancelled order'
    );
  end if;

  update public.orders
  set status = p_status
  where id = p_order_id
    and payment_status = 'paid';

  insert into public.delivery_events(order_id, status, note)
  values (p_order_id, p_status, 'Store updated order status');
end;
$$;

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
declare
  v_order record;
begin
  if public.current_profile_role() not in ('rider', 'admin') then
    raise exception 'Only riders can update delivery status';
  end if;

  if p_status not in ('out_for_delivery', 'delivered') then
    raise exception 'Riders cannot set order status to %', p_status;
  end if;

  select id, status, payment_status, rider_id
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.payment_status <> 'paid'
     or not (v_order.rider_id = auth.uid() or public.is_admin()) then
    raise exception 'Order is not assigned to this rider';
  end if;

  if p_status = 'out_for_delivery' and v_order.status <> 'ready_for_pickup' then
    raise exception 'Only pickup-ready orders can be marked out for delivery';
  end if;

  if p_status = 'delivered' and v_order.status <> 'out_for_delivery' then
    raise exception 'Only out-for-delivery orders can be marked delivered';
  end if;

  update public.orders
  set status = p_status,
      eta_minutes = case when p_status = 'delivered' then 0 else eta_minutes end,
      eta_updated_at = case when p_status = 'delivered' then now() else eta_updated_at end
  where id = p_order_id;

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
