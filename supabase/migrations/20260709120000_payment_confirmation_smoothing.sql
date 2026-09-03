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
  v_item record;
  v_store_id uuid;
begin
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

  if p_amount < v_payment.amount or p_amount < v_payment.total_amount then
    raise exception 'Paid amount is lower than expected amount';
  end if;

  if v_payment.status = 'paid' then
    perform public.create_store_settlement_for_order(v_payment.order_id);
    return;
  end if;

  update public.payments
  set status = 'paid',
      provider_transaction_reference = coalesce(
        p_provider_transaction_reference,
        provider_transaction_reference
      ),
      raw_response = p_raw_response
  where id = v_payment.id;

  update public.orders
  set payment_status = 'paid',
      status = case
        when status in ('pending_payment', 'cancelled') then 'paid'::public.order_status
        else status
      end
  where id = v_payment.order_id;

  for v_reservation in
    select ir.*, p.store_id
    from public.inventory_reservations ir
    join public.products p on p.id = ir.product_id
    where ir.order_id = v_payment.order_id
      and ir.active = true
    for update
  loop
    v_store_id := v_reservation.store_id;

    update public.inventory_items
    set quantity_on_hand = greatest(quantity_on_hand - v_reservation.quantity, 0),
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
      case
        when v_reservation.expires_at <= now()
          then 'Converted successful payment after reservation expiry'
        else 'Converted checkout reservation after successful payment'
      end
    );

    update public.inventory_reservations
    set active = false
    where id = v_reservation.id;
  end loop;

  for v_item in
    select oi.product_id, oi.quantity, p.store_id
    from public.order_items oi
    join public.products p on p.id = oi.product_id
    where oi.order_id = v_payment.order_id
      and not exists (
        select 1
        from public.inventory_movements im
        where im.product_id = oi.product_id
          and im.reason = 'sale'
          and im.note in (
            'Converted checkout reservation after successful payment',
            'Converted successful payment after reservation expiry',
            'Converted successful payment without active reservation'
          )
          and im.created_at >= v_payment.created_at
      )
  loop
    update public.inventory_items
    set quantity_on_hand = greatest(quantity_on_hand - v_item.quantity, 0),
        updated_at = now()
    where product_id = v_item.product_id;

    insert into public.inventory_movements (
      product_id,
      store_id,
      quantity_delta,
      reason,
      note
    )
    values (
      v_item.product_id,
      v_item.store_id,
      -v_item.quantity,
      'sale',
      'Converted successful payment without active reservation'
    );
  end loop;

  perform public.create_store_settlement_for_order(v_payment.order_id);
end;
$$;
