alter table public.stores
  add column if not exists busy_until timestamptz,
  add column if not exists closed_until timestamptz;

alter table public.products
  add column if not exists unavailable_until timestamptz;

alter table public.orders
  add column if not exists preparation_minutes integer
    check (preparation_minutes is null or preparation_minutes between 0 and 240),
  add column if not exists cancellation_reason text;

create table if not exists public.store_opening_hours (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  day_of_week integer not null check (day_of_week between 0 and 6),
  opens_at time,
  closes_at time,
  is_closed boolean not null default false,
  updated_at timestamptz not null default now(),
  unique (store_id, day_of_week)
);

alter table public.store_opening_hours enable row level security;

drop policy if exists "store opening hours scoped read" on public.store_opening_hours;
create policy "store opening hours scoped read" on public.store_opening_hours
  for select using (
    exists (
      select 1
      from public.stores s
      where s.id = store_id
        and s.is_active = true
    )
  );

drop policy if exists "store opening hours scoped update" on public.store_opening_hours;
create policy "store opening hours scoped update" on public.store_opening_hours
  for all using (public.is_store_member(store_id) or public.is_admin())
  with check (public.is_store_member(store_id) or public.is_admin());

create or replace function public.is_store_taking_orders(
  p_store_id uuid,
  p_at timestamptz default now()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    s.is_active
    and s.is_open
    and (s.busy_until is null or s.busy_until <= p_at)
    and (s.closed_until is null or s.closed_until <= p_at)
    and coalesce((
      select not soh.is_closed
        and soh.opens_at is not null
        and soh.closes_at is not null
        and p_at::time >= soh.opens_at
        and p_at::time < soh.closes_at
      from public.store_opening_hours soh
      where soh.store_id = s.id
        and soh.day_of_week = extract(dow from p_at)::integer
      limit 1
    ), true)
  from public.stores s
  where s.id = p_store_id;
$$;

create or replace function public.store_set_availability_status(
  p_store_id uuid,
  p_mode text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today_end timestamptz := date_trunc('day', now()) + interval '1 day';
begin
  if not public.is_store_member(p_store_id) and not public.is_admin() then
    raise exception 'Not allowed to update this store';
  end if;

  if p_mode not in ('open', 'busy_30', 'closed_today') then
    raise exception 'Unsupported availability mode %', p_mode;
  end if;

  update public.stores
  set is_open = case when p_mode = 'closed_today' then false else true end,
      busy_until = case
        when p_mode = 'busy_30' then now() + interval '30 minutes'
        else null
      end,
      closed_until = case
        when p_mode = 'closed_today' then v_today_end
        else null
      end,
      updated_at = now()
  where id = p_store_id;
end;
$$;

create or replace function public.store_upsert_opening_hour(
  p_store_id uuid,
  p_day_of_week integer,
  p_opens_at time,
  p_closes_at time,
  p_is_closed boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.is_store_member(p_store_id) and not public.is_admin() then
    raise exception 'Not allowed to update this store';
  end if;

  if p_day_of_week < 0 or p_day_of_week > 6 then
    raise exception 'Invalid day of week';
  end if;

  if not p_is_closed and (p_opens_at is null or p_closes_at is null or p_opens_at >= p_closes_at) then
    raise exception 'Opening hours need a valid open and close time';
  end if;

  insert into public.store_opening_hours (
    store_id,
    day_of_week,
    opens_at,
    closes_at,
    is_closed,
    updated_at
  )
  values (
    p_store_id,
    p_day_of_week,
    case when p_is_closed then null else p_opens_at end,
    case when p_is_closed then null else p_closes_at end,
    p_is_closed,
    now()
  )
  on conflict (store_id, day_of_week) do update
    set opens_at = excluded.opens_at,
        closes_at = excluded.closes_at,
        is_closed = excluded.is_closed,
        updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.store_set_product_unavailability(
  p_product_id uuid,
  p_mode text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product record;
begin
  select id, store_id
  into v_product
  from public.products
  where id = p_product_id
  for update;

  if not found then
    raise exception 'Product not found';
  end if;

  if not public.is_store_member(v_product.store_id) and not public.is_admin() then
    raise exception 'Not allowed to update this product';
  end if;

  if p_mode not in ('available', 'today', 'indefinite') then
    raise exception 'Unsupported product availability mode %', p_mode;
  end if;

  update public.products
  set is_available = p_mode = 'available',
      unavailable_until = case
        when p_mode = 'today' then date_trunc('day', now()) + interval '1 day'
        else null
      end,
      updated_at = now()
  where id = p_product_id;
end;
$$;

create or replace function public.store_update_preparation_time(
  p_order_id uuid,
  p_preparation_minutes integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order record;
begin
  if p_preparation_minutes < 0 or p_preparation_minutes > 240 then
    raise exception 'Preparation time must be between 0 and 240 minutes';
  end if;

  select id, store_id, status, payment_status
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if not public.is_store_member(v_order.store_id) and not public.is_admin() then
    raise exception 'Not allowed to update this order';
  end if;

  if v_order.payment_status <> 'paid' or v_order.status in ('cancelled', 'out_for_delivery', 'delivered') then
    raise exception 'Preparation time cannot be changed for this order';
  end if;

  update public.orders
  set preparation_minutes = p_preparation_minutes,
      eta_minutes = p_preparation_minutes,
      eta_updated_at = now()
  where id = p_order_id;

  insert into public.delivery_events(order_id, status, eta_minutes, note)
  values (
    p_order_id,
    v_order.status,
    p_preparation_minutes,
    'Store updated preparation time'
  );
end;
$$;

create or replace function public.store_modify_order_item(
  p_order_id uuid,
  p_order_item_id uuid,
  p_action text,
  p_replacement_product_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order record;
  v_item record;
  v_replacement record;
  v_delta numeric(12, 2) := 0;
  v_fees record;
begin
  if p_action not in ('remove', 'replace') then
    raise exception 'Unsupported order modification action %', p_action;
  end if;

  select *
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if not public.is_store_member(v_order.store_id) and not public.is_admin() then
    raise exception 'Not allowed to modify this order';
  end if;

  if v_order.payment_status <> 'paid' or v_order.status not in ('paid', 'accepted') then
    raise exception 'Only new or accepted paid orders can be modified';
  end if;

  select *
  into v_item
  from public.order_items
  where id = p_order_item_id
    and order_id = p_order_id
  for update;

  if not found then
    raise exception 'Order item not found';
  end if;

  if p_action = 'remove' then
    v_delta := -v_item.line_total;
    delete from public.order_items where id = v_item.id;
    delete from public.inventory_reservations
    where order_id = p_order_id
      and product_id = v_item.product_id;
  else
    select p.id, p.name, p.price, p.is_available, p.unavailable_until
    into v_replacement
    from public.products p
    where p.id = p_replacement_product_id
      and p.store_id = v_order.store_id
    for update;

    if not found then
      raise exception 'Replacement product not found';
    end if;

    if not v_replacement.is_available
       or (v_replacement.unavailable_until is not null and v_replacement.unavailable_until > now()) then
      raise exception 'Replacement product is unavailable';
    end if;

    v_delta := (v_replacement.price * v_item.quantity) - v_item.line_total;

    update public.order_items
    set product_id = v_replacement.id,
        product_name = v_replacement.name,
        unit_price = v_replacement.price
    where id = v_item.id;

    update public.inventory_reservations
    set product_id = v_replacement.id
    where order_id = p_order_id
      and product_id = v_item.product_id;
  end if;

  if not exists (select 1 from public.order_items where order_id = p_order_id) then
    raise exception 'Order must contain at least one item';
  end if;

  select *
  into v_fees
  from public.calculate_order_fees(
    greatest(v_order.items_subtotal + v_delta, 0),
    v_order.discount_amount
  );

  update public.orders
  set status = 'accepted',
      items_subtotal = greatest(v_order.items_subtotal + v_delta, 0),
      total_amount = v_fees.total_amount,
      store_payout_amount = v_fees.store_payout_amount,
      rider_payout_amount = v_fees.rider_payout_amount,
      platform_fee_amount = v_fees.platform_fee_amount,
      updated_at = now()
  where id = p_order_id;

  insert into public.delivery_events(order_id, status, note)
  values (
    p_order_id,
    'accepted',
    case
      when p_action = 'remove' then 'Store removed unavailable item after customer confirmation'
      else 'Store replaced unavailable item after customer confirmation'
    end
  );
end;
$$;

create or replace function public.store_update_order_status(
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
  select id, store_id, status, payment_status, rider_id
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if not public.is_store_member(v_order.store_id) and not public.is_admin() then
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
  set status = p_status,
      cancellation_reason = case when p_status = 'cancelled' then p_note else cancellation_reason end
  where id = p_order_id
    and payment_status = 'paid';

  insert into public.delivery_events(order_id, status, note)
  values (
    p_order_id,
    p_status,
    coalesce(p_note, 'Store updated order status')
  );
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
  p.category,
  p.unavailable_until
from public.products p
join public.stores s on s.id = p.store_id
left join public.inventory_items ii on ii.product_id = p.id
where s.is_active = true;

create or replace view public.store_inventory
with (security_invoker = true)
as
select
  p.id as product_id,
  p.store_id,
  p.name,
  p.description,
  p.price,
  p.image_url,
  p.is_available as store_marked_available,
  coalesce(ii.quantity_on_hand, 0)::integer as quantity_on_hand,
  coalesce(ii.reorder_level, 5)::integer as reorder_level,
  coalesce((
    select sum(ir.quantity)
    from public.inventory_reservations ir
    where ir.product_id = p.id
      and ir.active = true
      and ir.expires_at > now()
  ), 0)::integer as quantity_reserved,
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
  ii.sku,
  p.category,
  p.unavailable_until
from public.products p
left join public.inventory_items ii on ii.product_id = p.id
where public.is_store_member(p.store_id);

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
  o.cancellation_reason
from public.orders o
join public.stores s on s.id = o.store_id;

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

  if not public.is_store_taking_orders(p_store_id) then
    raise exception 'Store is not currently accepting new orders';
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
    set redemption_count = redemption_count + 1,
        updated_at = now()
    where id = v_promo_id;
  end if;

  return v_order_id;
end;
$$;

grant select on public.store_opening_hours to authenticated;
grant execute on function public.is_store_taking_orders(uuid, timestamptz)
  to authenticated;
grant execute on function public.store_set_availability_status(uuid, text)
  to authenticated;
grant execute on function public.store_upsert_opening_hour(uuid, integer, time, time, boolean)
  to authenticated;
grant execute on function public.store_set_product_unavailability(uuid, text)
  to authenticated;
grant execute on function public.store_update_preparation_time(uuid, integer)
  to authenticated;
grant execute on function public.store_modify_order_item(uuid, uuid, text, uuid)
  to authenticated;
grant execute on function public.store_update_order_status(uuid, public.order_status, text)
  to authenticated;

revoke execute on function public.store_set_availability_status(uuid, text)
  from anon;
revoke execute on function public.store_upsert_opening_hour(uuid, integer, time, time, boolean)
  from anon;
revoke execute on function public.store_set_product_unavailability(uuid, text)
  from anon;
revoke execute on function public.store_update_preparation_time(uuid, integer)
  from anon;
revoke execute on function public.store_modify_order_item(uuid, uuid, text, uuid)
  from anon;
revoke execute on function public.store_update_order_status(uuid, public.order_status, text)
  from anon;

do $$
begin
  begin
    alter publication supabase_realtime add table public.store_opening_hours;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;
end;
$$;
