create or replace function public.expire_stale_pending_orders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order_ids uuid[];
begin
  select coalesce(array_agg(distinct o.id), '{}')
  into v_order_ids
  from public.orders o
  join public.inventory_reservations ir on ir.order_id = o.id
  where o.status = 'pending_payment'
    and o.payment_status = 'pending'
    and ir.active = true
    and ir.expires_at <= now();

  if coalesce(array_length(v_order_ids, 1), 0) = 0 then
    return 0;
  end if;

  update public.inventory_reservations
  set active = false
  where order_id = any(v_order_ids)
    and active = true;

  update public.payments
  set status = 'expired'
  where order_id = any(v_order_ids)
    and status = 'pending';

  update public.orders
  set status = 'cancelled',
      payment_status = 'expired'
  where id = any(v_order_ids)
    and status = 'pending_payment'
    and payment_status = 'pending';

  return coalesce(array_length(v_order_ids, 1), 0);
end;
$$;

create or replace function public.customer_cancel_pending_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  update public.orders
  set status = 'cancelled',
      payment_status = 'expired'
  where id = p_order_id
    and customer_id = auth.uid()
    and status = 'pending_payment'
    and payment_status = 'pending';

  if not found then
    raise exception 'Only pending unpaid orders can be cancelled';
  end if;

  update public.inventory_reservations
  set active = false
  where order_id = p_order_id
    and active = true;

  update public.payments
  set status = 'expired'
  where order_id = p_order_id
    and status = 'pending';
end;
$$;

create or replace function public.finalize_paid_order(
  p_payment_reference text,
  p_provider_transaction_reference text,
  p_amount numeric,
  p_raw_response jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment record;
  v_reservation record;
  v_store_id uuid;
begin
  perform public.expire_stale_pending_orders();

  select p.*, o.store_id, o.total_amount, o.status as order_status,
         o.payment_status as order_payment_status
  into v_payment
  from public.payments p
  join public.orders o on o.id = p.order_id
  where p.payment_reference = p_payment_reference
  for update;

  if not found then
    raise exception 'Payment reference not found';
  end if;

  if v_payment.status = 'paid' then
    return;
  end if;

  if v_payment.order_status <> 'pending_payment'
     or v_payment.order_payment_status <> 'pending' then
    raise exception 'Order is no longer payable';
  end if;

  if exists (
    select 1
    from public.inventory_reservations ir
    where ir.order_id = v_payment.order_id
      and ir.active = true
      and ir.expires_at <= now()
  ) then
    update public.inventory_reservations
    set active = false
    where order_id = v_payment.order_id
      and active = true;

    update public.payments
    set status = 'expired'
    where id = v_payment.id;

    update public.orders
    set status = 'cancelled',
        payment_status = 'expired'
    where id = v_payment.order_id;

    raise exception 'Order reservation has expired';
  end if;

  if not exists (
    select 1
    from public.inventory_reservations ir
    where ir.order_id = v_payment.order_id
      and ir.active = true
      and ir.expires_at > now()
  ) then
    raise exception 'Order has no active reservation';
  end if;

  if p_amount < v_payment.amount or p_amount < v_payment.total_amount then
    raise exception 'Paid amount is lower than expected amount';
  end if;

  update public.payments
  set status = 'paid',
      provider_transaction_reference = p_provider_transaction_reference,
      raw_response = p_raw_response
  where id = v_payment.id;

  update public.orders
  set payment_status = 'paid',
      status = 'paid'
  where id = v_payment.order_id;

  for v_reservation in
    select ir.*, p.store_id
    from public.inventory_reservations ir
    join public.products p on p.id = ir.product_id
    where ir.order_id = v_payment.order_id
      and ir.active = true
      and ir.expires_at > now()
    for update
  loop
    v_store_id := v_reservation.store_id;

    update public.inventory_items
    set quantity_on_hand = quantity_on_hand - v_reservation.quantity,
        updated_at = now()
    where product_id = v_reservation.product_id;

    insert into public.inventory_movements (
      product_id,
      store_id,
      quantity_delta,
      reason,
      note
    )
    values (
      v_reservation.product_id,
      v_store_id,
      -v_reservation.quantity,
      'sale',
      'Converted checkout reservation after successful payment'
    );

    update public.inventory_reservations
    set active = false
    where id = v_reservation.id;
  end loop;
end;
$$;
