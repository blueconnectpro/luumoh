alter table public.stores
  add column if not exists latitude numeric(9, 6),
  add column if not exists longitude numeric(9, 6);

alter table public.customer_addresses
  add column if not exists latitude numeric(9, 6),
  add column if not exists longitude numeric(9, 6);

alter table public.orders
  add column if not exists store_latitude numeric(9, 6),
  add column if not exists store_longitude numeric(9, 6),
  add column if not exists delivery_latitude numeric(9, 6),
  add column if not exists delivery_longitude numeric(9, 6),
  add column if not exists delivery_distance_km numeric(8, 2) not null default 0;

alter table public.platform_fee_settings
  add column if not exists delivery_base_km numeric(8, 2) not null default 3,
  add column if not exists delivery_fee_per_km numeric(12, 2) not null default 150,
  add column if not exists minimum_delivery_fee numeric(12, 2) not null default 600;

update public.stores
set latitude = coalesce(latitude, 6.5244 + ((abs(hashtext(id::text)) % 120)::numeric / 10000)),
    longitude = coalesce(longitude, 3.3792 + ((abs(hashtext(name)) % 120)::numeric / 10000))
where latitude is null
   or longitude is null;

create or replace function public.distance_km(
  p_from_latitude numeric,
  p_from_longitude numeric,
  p_to_latitude numeric,
  p_to_longitude numeric
)
returns numeric
language sql
immutable
as $$
  select case
    when p_from_latitude is null
      or p_from_longitude is null
      or p_to_latitude is null
      or p_to_longitude is null
    then 0
    else round(
      (
        6371 * 2 * asin(
          sqrt(
            power(sin(radians((p_to_latitude - p_from_latitude) / 2)), 2) +
            cos(radians(p_from_latitude)) *
            cos(radians(p_to_latitude)) *
            power(sin(radians((p_to_longitude - p_from_longitude) / 2)), 2)
          )
        )
      )::numeric,
      2
    )
  end;
$$;

create or replace function public.calculate_order_fees(
  p_items_subtotal numeric,
  p_discount_amount numeric,
  p_fulfillment_type text default 'delivery',
  p_delivery_distance_km numeric default 0
)
returns table (
  delivery_fee numeric,
  service_fee numeric,
  rider_payout_amount numeric,
  platform_fee_amount numeric,
  total_amount numeric,
  store_payout_amount numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_settings public.platform_fee_settings%rowtype;
  v_items_net numeric(12, 2);
  v_is_pickup boolean;
  v_distance_km numeric(8, 2);
  v_extra_distance_km numeric(8, 2);
begin
  select *
  into v_settings
  from public.platform_fee_settings
  where id = true
    and is_active = true;

  if not found then
    v_settings.delivery_fee := 0;
    v_settings.service_fee_percent := 0;
    v_settings.service_fee_fixed := 0;
    v_settings.rider_delivery_payout := 0;
    v_settings.delivery_base_km := 3;
    v_settings.delivery_fee_per_km := 0;
    v_settings.minimum_delivery_fee := 0;
  end if;

  v_is_pickup := lower(coalesce(p_fulfillment_type, 'delivery')) = 'pickup';
  v_items_net := greatest(coalesce(p_items_subtotal, 0) - coalesce(p_discount_amount, 0), 0);
  v_distance_km := greatest(coalesce(p_delivery_distance_km, 0), 0);
  v_extra_distance_km := greatest(v_distance_km - coalesce(v_settings.delivery_base_km, 0), 0);

  delivery_fee := case
    when v_is_pickup then 0
    else greatest(
      coalesce(v_settings.minimum_delivery_fee, 0),
      coalesce(v_settings.delivery_fee, 0) +
      round(v_extra_distance_km * coalesce(v_settings.delivery_fee_per_km, 0), 2)
    )
  end;
  service_fee := round((v_items_net * coalesce(v_settings.service_fee_percent, 0) / 100) + coalesce(v_settings.service_fee_fixed, 0), 2);
  rider_payout_amount := case
    when v_is_pickup then 0
    else greatest(coalesce(v_settings.rider_delivery_payout, 0), round(delivery_fee * 0.7, 2))
  end;
  platform_fee_amount := service_fee + greatest(delivery_fee - rider_payout_amount, 0);
  total_amount := v_items_net + delivery_fee + service_fee;
  store_payout_amount := v_items_net;
  return next;
end;
$$;

create or replace function public.quote_order_totals(
  p_store_id uuid,
  p_items jsonb,
  p_promo_code text default null,
  p_fulfillment_type text default 'delivery',
  p_customer_latitude numeric default null,
  p_customer_longitude numeric default null
)
returns table (
  items_subtotal numeric,
  discount_amount numeric,
  delivery_fee numeric,
  service_fee numeric,
  total_amount numeric,
  store_payout_amount numeric,
  rider_payout_amount numeric,
  platform_fee_amount numeric,
  promo_code text,
  promo_is_valid boolean,
  promo_message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item record;
  v_product record;
  v_reserved integer;
  v_available integer;
  v_promo public.promo_codes%rowtype;
  v_fees record;
  v_store public.stores%rowtype;
  v_delivery_distance_km numeric(8, 2) := 0;
  v_fulfillment_type text := case when lower(coalesce(p_fulfillment_type, 'delivery')) = 'pickup' then 'pickup' else 'delivery' end;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select *
  into v_store
  from public.stores
  where id = p_store_id;

  if not found then
    raise exception 'Store not found';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Order must contain at least one item';
  end if;

  items_subtotal := 0;
  discount_amount := 0;
  promo_code := public.normalize_promo_code(p_promo_code);
  promo_is_valid := promo_code = '';
  promo_message := case when promo_code = '' then '' else 'Promo code not applied' end;

  for v_item in
    select *
    from jsonb_to_recordset(p_items) as item(product_id uuid, quantity integer)
  loop
    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'Invalid quantity for product %', v_item.product_id;
    end if;

    select p.id, p.name, p.price, p.is_available, p.unavailable_until
    into v_product
    from public.products p
    where p.id = v_item.product_id
      and p.store_id = p_store_id;

    if not found then
      raise exception 'Product % not found for store', v_item.product_id;
    end if;

    select coalesce(sum(quantity), 0)
    into v_reserved
    from public.inventory_reservations
    where product_id = v_item.product_id
      and active = true
      and expires_at > now();

    select coalesce(ii.quantity_on_hand, 0) - v_reserved
    into v_available
    from public.inventory_items ii
    where ii.product_id = v_product.id;

    v_available := coalesce(v_available, 0);

    if not v_product.is_available
       or (v_product.unavailable_until is not null and v_product.unavailable_until > now()) then
      raise exception 'Product % is unavailable', v_product.name;
    end if;

    if v_available < v_item.quantity then
      raise exception 'Insufficient stock for %', v_product.name;
    end if;

    items_subtotal := items_subtotal + (v_product.price * v_item.quantity);
  end loop;

  if promo_code <> '' then
    select *
    into v_promo
    from public.promo_codes pc
    where pc.code = promo_code
      and (pc.store_id = p_store_id or pc.store_id is null)
    order by pc.store_id nulls last
    limit 1;

    if found
       and v_promo.is_active
       and (v_promo.starts_at is null or now() >= v_promo.starts_at)
       and (v_promo.ends_at is null or now() <= v_promo.ends_at)
       and (v_promo.max_redemptions is null or v_promo.redemption_count < v_promo.max_redemptions)
       and items_subtotal >= v_promo.min_order_amount then
      discount_amount := public.calculate_promo_discount(
        v_promo.discount_type,
        v_promo.discount_value,
        items_subtotal
      );
      promo_is_valid := true;
      promo_message := 'Promo code applied';
    else
      promo_is_valid := false;
      promo_message := 'Promo code is not valid for this order';
    end if;
  end if;

  if v_fulfillment_type = 'delivery' then
    v_delivery_distance_km := public.distance_km(
      v_store.latitude,
      v_store.longitude,
      p_customer_latitude,
      p_customer_longitude
    );
  end if;

  select *
  into v_fees
  from public.calculate_order_fees(
    items_subtotal,
    discount_amount,
    v_fulfillment_type,
    v_delivery_distance_km
  );

  delivery_fee := v_fees.delivery_fee;
  service_fee := v_fees.service_fee;
  total_amount := v_fees.total_amount;
  store_payout_amount := v_fees.store_payout_amount;
  rider_payout_amount := v_fees.rider_payout_amount;
  platform_fee_amount := v_fees.platform_fee_amount;
  return next;
end;
$$;

create or replace function public.place_order(
  p_store_id uuid,
  p_delivery_address text,
  p_items jsonb,
  p_promo_code text default null,
  p_fulfillment_type text default 'delivery',
  p_customer_latitude numeric default null,
  p_customer_longitude numeric default null
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
  v_store public.stores%rowtype;
  v_quantity_on_hand integer;
  v_reserved integer;
  v_available integer;
  v_delivery_distance_km numeric(8, 2) := 0;
  v_fulfillment_type text := case when lower(coalesce(p_fulfillment_type, 'delivery')) = 'pickup' then 'pickup' else 'delivery' end;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select *
  into v_store
  from public.stores
  where id = p_store_id;

  if not found then
    raise exception 'Store not found';
  end if;

  if not public.is_store_taking_orders(p_store_id) then
    raise exception 'Store is not currently accepting new orders';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Order must contain at least one item';
  end if;

  if v_fulfillment_type = 'delivery' and length(trim(coalesce(p_delivery_address, ''))) = 0 then
    raise exception 'Delivery address is required';
  end if;

  if v_fulfillment_type = 'delivery' then
    v_delivery_distance_km := public.distance_km(
      v_store.latitude,
      v_store.longitude,
      p_customer_latitude,
      p_customer_longitude
    );
  end if;

  insert into public.orders (
    customer_id,
    store_id,
    delivery_address,
    fulfillment_type,
    status,
    payment_status,
    store_latitude,
    store_longitude,
    delivery_latitude,
    delivery_longitude,
    delivery_distance_km
  )
  values (
    auth.uid(),
    p_store_id,
    case when v_fulfillment_type = 'pickup' then 'Pickup at store' else trim(p_delivery_address) end,
    v_fulfillment_type,
    'pending_payment',
    'pending',
    v_store.latitude,
    v_store.longitude,
    case when v_fulfillment_type = 'pickup' then null else p_customer_latitude end,
    case when v_fulfillment_type = 'pickup' then null else p_customer_longitude end,
    case when v_fulfillment_type = 'pickup' then 0 else v_delivery_distance_km end
  )
  returning id into v_order_id;

  for v_item in
    select *
    from jsonb_to_recordset(p_items) as item(product_id uuid, quantity integer)
  loop
    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'Invalid quantity for product %', v_item.product_id;
    end if;

    select p.id, p.name, p.price, p.is_available, p.unavailable_until, s.is_open, s.is_active
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

    if not v_product.is_available
       or (v_product.unavailable_until is not null and v_product.unavailable_until > now())
       or not public.is_store_taking_orders(p_store_id) then
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
  from public.calculate_order_fees(
    v_total,
    v_discount,
    v_fulfillment_type,
    v_delivery_distance_km
  );

  update public.orders
  set items_subtotal = v_total,
      discount_amount = v_discount,
      promo_code_id = v_promo_id,
      delivery_fee = v_fees.delivery_fee,
      service_fee = v_fees.service_fee,
      total_amount = v_fees.total_amount,
      store_payout_amount = v_fees.store_payout_amount,
      rider_payout_amount = v_fees.rider_payout_amount,
      platform_fee_amount = v_fees.platform_fee_amount,
      delivery_distance_km = v_delivery_distance_km
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

create or replace function public.customer_save_address(
  p_label text,
  p_address text,
  p_is_default boolean default false,
  p_latitude numeric default null,
  p_longitude numeric default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_address_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in required';
  end if;

  if length(trim(coalesce(p_address, ''))) = 0 then
    raise exception 'Address is required';
  end if;

  if p_latitude is not null and (p_latitude < -90 or p_latitude > 90) then
    raise exception 'Latitude is invalid';
  end if;

  if p_longitude is not null and (p_longitude < -180 or p_longitude > 180) then
    raise exception 'Longitude is invalid';
  end if;

  if p_is_default then
    update public.customer_addresses
    set is_default = false
    where customer_id = auth.uid();
  end if;

  insert into public.customer_addresses (
    customer_id,
    label,
    address,
    is_default,
    latitude,
    longitude
  )
  values (
    auth.uid(),
    coalesce(nullif(trim(coalesce(p_label, '')), ''), 'Home'),
    trim(p_address),
    p_is_default,
    p_latitude,
    p_longitude
  )
  returning id into v_address_id;

  return v_address_id;
end;
$$;

create or replace view public.customer_catalog
with (security_invoker = true)
as
select
  p.id as product_id,
  p.store_id,
  s.name as store_name,
  p.name,
  p.description,
  p.price,
  p.image_url,
  greatest(
    coalesce(ii.quantity_on_hand, 0) - coalesce((
      select sum(ir.quantity)
      from public.inventory_reservations ir
      where ir.product_id = p.id
        and ir.active = true
        and ir.expires_at > now()
    ), 0),
    0
  )::integer as quantity_available,
  (
    public.is_store_taking_orders(s.id)
    and p.is_available
    and (p.unavailable_until is null or p.unavailable_until <= now())
    and greatest(
      coalesce(ii.quantity_on_hand, 0) - coalesce((
        select sum(ir.quantity)
        from public.inventory_reservations ir
        where ir.product_id = p.id
          and ir.active = true
          and ir.expires_at > now()
      ), 0),
      0
    ) > 0
  ) as is_available,
  public.customer_category_group(p.category) as category,
  p.unavailable_until,
  s.latitude as store_latitude,
  s.longitude as store_longitude
from public.products p
join public.stores s on s.id = p.store_id
left join public.inventory_items ii on ii.product_id = p.id
where s.is_active = true;

create or replace view public.order_summaries
with (security_invoker = true)
as
select
  o.id,
  o.customer_id,
  o.store_id,
  s.name as store_name,
  o.rider_id,
  o.status,
  o.payment_status,
  o.items_subtotal,
  o.discount_amount,
  o.delivery_fee,
  o.service_fee,
  o.total_amount,
  o.store_payout_amount,
  o.rider_payout_amount,
  o.platform_fee_amount,
  o.delivery_address,
  o.eta_minutes,
  o.eta_updated_at,
  o.created_at,
  o.updated_at,
  public.order_profile_name(o.id, o.customer_id) as customer_name,
  public.order_profile_phone(o.id, o.customer_id) as customer_phone,
  public.order_profile_name(o.id, o.rider_id) as rider_name,
  public.order_profile_phone(o.id, o.rider_id) as rider_phone,
  o.preparation_minutes,
  o.cancellation_reason,
  o.fulfillment_type,
  o.store_latitude,
  o.store_longitude,
  o.delivery_latitude,
  o.delivery_longitude,
  o.delivery_distance_km
from public.orders o
join public.stores s on s.id = o.store_id;

create or replace view public.rider_location_summaries
with (security_invoker = true)
as
select
  rlu.id,
  rlu.order_id,
  rlu.rider_id,
  public.order_profile_name(rlu.order_id, rlu.rider_id) as rider_name,
  rlu.latitude,
  rlu.longitude,
  rlu.accuracy_meters,
  rlu.heading,
  rlu.speed_mps,
  rlu.note,
  rlu.created_at,
  o.customer_id,
  o.store_id,
  s.name as store_name,
  o.status as order_status,
  o.payment_status,
  o.store_latitude,
  o.store_longitude,
  o.delivery_latitude,
  o.delivery_longitude,
  o.delivery_distance_km
from public.rider_location_updates rlu
join public.orders o on o.id = rlu.order_id
join public.stores s on s.id = o.store_id;

grant execute on function public.distance_km(numeric, numeric, numeric, numeric) to authenticated;
grant execute on function public.calculate_order_fees(numeric, numeric, text, numeric) to authenticated;
grant execute on function public.quote_order_totals(uuid, jsonb, text, text, numeric, numeric) to authenticated;
grant execute on function public.place_order(uuid, text, jsonb, text, text, numeric, numeric) to authenticated;
grant execute on function public.customer_save_address(text, text, boolean, numeric, numeric) to authenticated;
