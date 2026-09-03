create or replace function public.record_payment_outcome(
  p_payment_reference text,
  p_provider_transaction_reference text,
  p_status public.payment_status,
  p_raw_response jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment record;
begin
  select p.*, o.status as order_status, o.payment_status as order_payment_status
  into v_payment
  from public.payments p
  join public.orders o on o.id = p.order_id
  where p.payment_reference = p_payment_reference
  for update;

  if not found then
    return;
  end if;

  if v_payment.status = 'paid' and p_status in ('failed', 'expired') then
    return;
  end if;

  update public.payments
  set status = p_status,
      provider_transaction_reference = coalesce(
        p_provider_transaction_reference,
        provider_transaction_reference
      ),
      raw_response = p_raw_response
  where id = v_payment.id;

  if p_status in ('failed', 'expired')
     and v_payment.order_status = 'pending_payment'
     and v_payment.order_payment_status = 'pending' then
    update public.inventory_reservations
    set active = false
    where order_id = v_payment.order_id
      and active = true;

    update public.orders
    set status = 'cancelled',
        payment_status = p_status
    where id = v_payment.order_id;
  elsif p_status = 'refunded' then
    update public.orders
    set payment_status = 'refunded'
    where id = v_payment.order_id;
  end if;
end;
$$;
