create or replace function public.place_order(
  p_store_id uuid,
  p_delivery_address text,
  p_items jsonb,
  p_promo_code text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order_id uuid;
  v_total numeric(12, 2) := 0;
  v_discount numeric(12, 2) := 0;
  v_promo_id uuid;
  v_promo public.promo_codes%rowtype;
  v_fees record;
  v_item record;
  v_product record;
  v_quantity_on_hand integer;
  v_reserved integer;
  v_available integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Order must contain at least one item';
  end if;

  insert into public.orders (
    customer_id,
    store_id,
    delivery_address,
    status,
    payment_status
  )
  values (
    auth.uid(),
    p_store_id,
    trim(p_delivery_address),
    'pending_payment',
    'pending'
  )
  returning id into v_order_id;

  for v_item in
    select *
    from jsonb_to_recordset(p_items) as item(product_id uuid, quantity integer)
  loop
    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'Invalid quantity for product %', v_item.product_id;
    end if;

    select p.id, p.name, p.price, p.is_available, s.is_open, s.is_active
    into v_product
    from public.products p
    join public.stores s on s.id = p.store_id
    where p.id = v_item.product_id
      and p.store_id = p_store_id
    for update of p;

    if not found then
      raise exception 'Product % not found for store', v_item.product_id;
    end if;

    insert into public.inventory_items (
      product_id,
      quantity_on_hand,
      reorder_level
    )
    values (
      v_product.id,
      0,
      5
    )
    on conflict (product_id) do nothing;

    select quantity_on_hand
    into v_quantity_on_hand
    from public.inventory_items
    where product_id = v_product.id
    for update;

    if not (v_product.is_available and v_product.is_open and v_product.is_active) then
      raise exception 'Product % is unavailable', v_product.name;
    end if;

    select coalesce(sum(quantity), 0)
    into v_reserved
    from public.inventory_reservations
    where product_id = v_item.product_id
      and active = true
      and expires_at > now();

    v_available := coalesce(v_quantity_on_hand, 0) - v_reserved;

    if v_available < v_item.quantity then
      raise exception 'Insufficient stock for %', v_product.name;
    end if;

    insert into public.order_items (
      order_id,
      product_id,
      product_name,
      quantity,
      unit_price
    )
    values (
      v_order_id,
      v_item.product_id,
      v_product.name,
      v_item.quantity,
      v_product.price
    );

    insert into public.inventory_reservations (
      order_id,
      product_id,
      quantity,
      expires_at
    )
    values (
      v_order_id,
      v_item.product_id,
      v_item.quantity,
      now() + interval '40 minutes'
    );

    v_total := v_total + (v_product.price * v_item.quantity);
  end loop;

  if public.normalize_promo_code(p_promo_code) <> '' then
    select *
    into v_promo
    from public.promo_codes
    where code = public.normalize_promo_code(p_promo_code)
      and (store_id = p_store_id or store_id is null)
    order by store_id nulls last
    limit 1
    for update;

    if not found then
      raise exception 'Promo code was not found';
    end if;

    if not v_promo.is_active
       or (v_promo.starts_at is not null and now() < v_promo.starts_at)
       or (v_promo.ends_at is not null and now() > v_promo.ends_at)
       or (v_promo.max_redemptions is not null and v_promo.redemption_count >= v_promo.max_redemptions)
       or v_total < v_promo.min_order_amount then
      raise exception 'Promo code is not valid for this order';
    end if;

    v_promo_id := v_promo.id;
    v_discount := public.calculate_promo_discount(
      v_promo.discount_type,
      v_promo.discount_value,
      v_total
    );
  end if;

  select *
  into v_fees
  from public.calculate_order_fees(v_total, v_discount);

  update public.orders
  set items_subtotal = v_total,
      discount_amount = v_discount,
      promo_code_id = v_promo_id,
      delivery_fee = v_fees.delivery_fee,
      service_fee = v_fees.service_fee,
      total_amount = v_fees.total_amount,
      store_payout_amount = v_fees.store_payout_amount,
      rider_payout_amount = v_fees.rider_payout_amount,
      platform_fee_amount = v_fees.platform_fee_amount
  where id = v_order_id;

  if v_promo_id is not null then
    insert into public.order_promo_redemptions (
      order_id,
      promo_code_id,
      customer_id,
      store_id,
      discount_amount
    )
    values (
      v_order_id,
      v_promo_id,
      auth.uid(),
      p_store_id,
      v_discount
    );

    update public.promo_codes
    set redemption_count = redemption_count + 1
    where id = v_promo_id;
  end if;

  return v_order_id;
end;
$$;
