create or replace function public.restore_order_stock_once(
  p_order_id uuid,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order record;
  v_item record;
begin
  select id, store_id, status
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.status = 'cancelled' then
    return;
  end if;

  for v_item in
    select product_id, quantity
    from public.order_items
    where order_id = p_order_id
  loop
    update public.inventory_items
    set quantity_on_hand = quantity_on_hand + v_item.quantity,
        updated_at = now()
    where product_id = v_item.product_id;

    insert into public.inventory_movements (
      product_id,
      store_id,
      quantity_delta,
      reason,
      note,
      created_by
    )
    values (
      v_item.product_id,
      v_order.store_id,
      v_item.quantity,
      'return',
      coalesce(p_note, 'Returned stock after order cancellation'),
      auth.uid()
    );
  end loop;
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
  v_order record;
begin
  select id, store_id, status, payment_status
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

create or replace function public.admin_cancel_order(
  p_order_id uuid,
  p_note text default null,
  p_restock boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order record;
begin
  if not public.is_admin() then
    raise exception 'Only admins can cancel orders';
  end if;

  select id, status, payment_status
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.status = 'delivered' then
    raise exception 'Delivered orders cannot be cancelled';
  end if;

  if p_restock and v_order.payment_status in ('paid', 'refunded') then
    perform public.restore_order_stock_once(
      p_order_id,
      coalesce(p_note, 'Returned stock after admin cancelled order')
    );
  end if;

  if v_order.payment_status = 'pending' then
    update public.inventory_reservations
    set active = false
    where order_id = p_order_id
      and active = true;

    update public.payments
    set status = 'expired'
    where order_id = p_order_id
      and status = 'pending';

    update public.orders
    set status = 'cancelled',
        payment_status = 'expired'
    where id = p_order_id;
  else
    update public.orders
    set status = 'cancelled'
    where id = p_order_id;
  end if;

  insert into public.delivery_events(order_id, status, note)
  values (p_order_id, 'cancelled', coalesce(p_note, 'Admin cancelled order'));
end;
$$;

create or replace function public.admin_mark_order_refunded(
  p_order_id uuid,
  p_note text default null,
  p_restock boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order record;
begin
  if not public.is_admin() then
    raise exception 'Only admins can mark orders refunded';
  end if;

  select id, status, payment_status
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.payment_status <> 'paid' then
    raise exception 'Only paid orders can be marked refunded';
  end if;

  if p_restock and v_order.status <> 'delivered' then
    perform public.restore_order_stock_once(
      p_order_id,
      coalesce(p_note, 'Returned stock after admin refund')
    );
  end if;

  update public.orders
  set status = case when status = 'delivered' then status else 'cancelled' end,
      payment_status = 'refunded'
  where id = p_order_id;

  update public.payments
  set status = 'refunded'
  where order_id = p_order_id
    and status = 'paid';

  insert into public.delivery_events(order_id, status, note)
  values (p_order_id, 'cancelled', coalesce(p_note, 'Admin marked order refunded'));
end;
$$;
