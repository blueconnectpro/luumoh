create table if not exists public.platform_fee_settings (
  id boolean primary key default true check (id),
  delivery_fee numeric(12, 2) not null default 800 check (delivery_fee >= 0),
  service_fee_percent numeric(6, 3) not null default 5 check (service_fee_percent >= 0),
  service_fee_fixed numeric(12, 2) not null default 0 check (service_fee_fixed >= 0),
  rider_delivery_payout numeric(12, 2) not null default 600 check (rider_delivery_payout >= 0),
  is_active boolean not null default true,
  updated_at timestamptz not null default now()
);

insert into public.platform_fee_settings (id)
values (true)
on conflict (id) do nothing;

alter table public.platform_fee_settings enable row level security;

create trigger platform_fee_settings_touch_updated_at
before update on public.platform_fee_settings
for each row execute function public.touch_updated_at();

drop policy if exists "fee settings admin read" on public.platform_fee_settings;
create policy "fee settings admin read" on public.platform_fee_settings
for select using (public.is_admin());

drop policy if exists "fee settings admin update" on public.platform_fee_settings;
create policy "fee settings admin update" on public.platform_fee_settings
for update using (public.is_admin()) with check (public.is_admin());

alter table public.orders
  add column if not exists items_subtotal numeric(12, 2) not null default 0,
  add column if not exists delivery_fee numeric(12, 2) not null default 0,
  add column if not exists service_fee numeric(12, 2) not null default 0,
  add column if not exists store_payout_amount numeric(12, 2) not null default 0,
  add column if not exists rider_payout_amount numeric(12, 2) not null default 0,
  add column if not exists platform_fee_amount numeric(12, 2) not null default 0;

update public.orders
set items_subtotal = case
      when items_subtotal = 0 then greatest(total_amount + coalesce(discount_amount, 0) - delivery_fee - service_fee, 0)
      else items_subtotal
    end,
    store_payout_amount = case
      when store_payout_amount = 0 then greatest(total_amount - delivery_fee - service_fee, 0)
      else store_payout_amount
    end,
    platform_fee_amount = case
      when platform_fee_amount = 0 then service_fee + greatest(delivery_fee - rider_payout_amount, 0)
      else platform_fee_amount
    end;

create table if not exists public.store_settlements (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  order_id uuid not null references public.orders(id) on delete cascade,
  gross_items_amount numeric(12, 2) not null default 0,
  discount_amount numeric(12, 2) not null default 0,
  net_items_amount numeric(12, 2) not null default 0,
  service_fee_amount numeric(12, 2) not null default 0,
  payout_amount numeric(12, 2) not null default 0,
  status text not null default 'pending' check (status in ('pending', 'processing', 'paid', 'held', 'cancelled')),
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(order_id)
);

create index if not exists store_settlements_store_status_idx
  on public.store_settlements(store_id, status, created_at desc);

create trigger store_settlements_touch_updated_at
before update on public.store_settlements
for each row execute function public.touch_updated_at();

alter table public.store_settlements enable row level security;

drop policy if exists "store settlements scoped read" on public.store_settlements;
create policy "store settlements scoped read" on public.store_settlements
for select using (public.is_store_member(store_id) or public.is_admin());

drop policy if exists "store settlements admin update" on public.store_settlements;
create policy "store settlements admin update" on public.store_settlements
for update using (public.is_admin()) with check (public.is_admin());

create table if not exists public.rider_settlements (
  id uuid primary key default gen_random_uuid(),
  rider_id uuid not null references public.profiles(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  order_id uuid not null references public.orders(id) on delete cascade,
  delivery_fee_amount numeric(12, 2) not null default 0,
  rider_payout_amount numeric(12, 2) not null default 0,
  platform_delivery_margin numeric(12, 2) not null default 0,
  status text not null default 'pending' check (status in ('pending', 'processing', 'paid', 'held', 'cancelled')),
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(order_id)
);

create index if not exists rider_settlements_rider_status_idx
  on public.rider_settlements(rider_id, status, created_at desc);

create trigger rider_settlements_touch_updated_at
before update on public.rider_settlements
for each row execute function public.touch_updated_at();

alter table public.rider_settlements enable row level security;

drop policy if exists "rider settlements scoped read" on public.rider_settlements;
create policy "rider settlements scoped read" on public.rider_settlements
for select using (rider_id = auth.uid() or public.is_admin());

drop policy if exists "rider settlements admin update" on public.rider_settlements;
create policy "rider settlements admin update" on public.rider_settlements
for update using (public.is_admin()) with check (public.is_admin());

create or replace function public.calculate_order_fees(
  p_items_subtotal numeric,
  p_discount_amount numeric
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
  end if;

  v_items_net := greatest(coalesce(p_items_subtotal, 0) - coalesce(p_discount_amount, 0), 0);
  delivery_fee := coalesce(v_settings.delivery_fee, 0);
  service_fee := round((v_items_net * coalesce(v_settings.service_fee_percent, 0) / 100) + coalesce(v_settings.service_fee_fixed, 0), 2);
  rider_payout_amount := coalesce(v_settings.rider_delivery_payout, delivery_fee);
  platform_fee_amount := service_fee + greatest(delivery_fee - rider_payout_amount, 0);
  total_amount := v_items_net + delivery_fee + service_fee;
  store_payout_amount := v_items_net;
  return next;
end;
$$;

create or replace function public.quote_order_totals(
  p_store_id uuid,
  p_items jsonb,
  p_promo_code text default null
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
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Order must contain at least one item';
  end if;

  items_subtotal := 0;
  discount_amount := 0;
  promo_is_valid := false;
  promo_message := '';

  for v_item in
    select *
    from jsonb_to_recordset(p_items) as item(product_id uuid, quantity integer)
  loop
    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'Invalid quantity for product %', v_item.product_id;
    end if;

    select p.id, p.name, p.price, p.is_available, s.is_open, s.is_active,
           coalesce(ii.quantity_on_hand, 0) as quantity_on_hand
    into v_product
    from public.products p
    join public.stores s on s.id = p.store_id
    left join public.inventory_items ii on ii.product_id = p.id
    where p.id = v_item.product_id
      and p.store_id = p_store_id;

    if not found then
      raise exception 'Product % not found for store', v_item.product_id;
    end if;

    if not (v_product.is_available and v_product.is_open and v_product.is_active) then
      raise exception 'Product % is unavailable', v_product.name;
    end if;

    select coalesce(sum(quantity), 0)
    into v_reserved
    from public.inventory_reservations
    where product_id = v_item.product_id
      and active = true
      and expires_at > now();

    v_available := v_product.quantity_on_hand - v_reserved;
    if v_available < v_item.quantity then
      raise exception 'Insufficient stock for %', v_product.name;
    end if;

    items_subtotal := items_subtotal + (v_product.price * v_item.quantity);
  end loop;

  if public.normalize_promo_code(p_promo_code) <> '' then
    select *
    into v_promo
    from public.promo_codes
    where code = public.normalize_promo_code(p_promo_code)
      and (store_id = p_store_id or store_id is null)
    order by store_id nulls last
    limit 1;

    if found and v_promo.is_active
       and (v_promo.starts_at is null or now() >= v_promo.starts_at)
       and (v_promo.ends_at is null or now() <= v_promo.ends_at)
       and (v_promo.max_redemptions is null or v_promo.redemption_count < v_promo.max_redemptions)
       and items_subtotal >= v_promo.min_order_amount then
      promo_code := v_promo.code;
      promo_is_valid := true;
      promo_message := 'Promo applied';
      discount_amount := public.calculate_promo_discount(
        v_promo.discount_type,
        v_promo.discount_value,
        items_subtotal
      );
    else
      promo_code := public.normalize_promo_code(p_promo_code);
      promo_message := 'Promo code is not valid for this order';
    end if;
  end if;

  select *
  into v_fees
  from public.calculate_order_fees(items_subtotal, discount_amount);

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

    select p.id, p.name, p.price, p.is_available, s.is_open, s.is_active,
           coalesce(ii.quantity_on_hand, 0) as quantity_on_hand
    into v_product
    from public.products p
    join public.stores s on s.id = p.store_id
    left join public.inventory_items ii on ii.product_id = p.id
    where p.id = v_item.product_id
      and p.store_id = p_store_id
    for update;

    if not found then
      raise exception 'Product % not found for store', v_item.product_id;
    end if;

    if not (v_product.is_available and v_product.is_open and v_product.is_active) then
      raise exception 'Product % is unavailable', v_product.name;
    end if;

    select coalesce(sum(quantity), 0)
    into v_reserved
    from public.inventory_reservations
    where product_id = v_item.product_id
      and active = true
      and expires_at > now();

    v_available := v_product.quantity_on_hand - v_reserved;

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

create or replace function public.create_store_settlement_for_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  select *
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found or v_order.payment_status <> 'paid' then
    return;
  end if;

  insert into public.store_settlements (
    store_id,
    order_id,
    gross_items_amount,
    discount_amount,
    net_items_amount,
    service_fee_amount,
    payout_amount,
    status
  )
  values (
    v_order.store_id,
    v_order.id,
    coalesce(v_order.items_subtotal, v_order.total_amount),
    coalesce(v_order.discount_amount, 0),
    coalesce(v_order.store_payout_amount, greatest(v_order.total_amount - v_order.delivery_fee - v_order.service_fee, 0)),
    coalesce(v_order.service_fee, 0),
    coalesce(v_order.store_payout_amount, greatest(v_order.total_amount - v_order.delivery_fee - v_order.service_fee, 0)),
    case when v_order.status = 'cancelled' then 'cancelled' else 'pending' end
  )
  on conflict (order_id) do nothing;
end;
$$;

create or replace function public.create_rider_settlement_for_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  select *
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found
     or v_order.payment_status <> 'paid'
     or v_order.status <> 'delivered'
     or v_order.rider_id is null then
    return;
  end if;

  insert into public.rider_settlements (
    rider_id,
    store_id,
    order_id,
    delivery_fee_amount,
    rider_payout_amount,
    platform_delivery_margin,
    status
  )
  values (
    v_order.rider_id,
    v_order.store_id,
    v_order.id,
    coalesce(v_order.delivery_fee, 0),
    coalesce(v_order.rider_payout_amount, 0),
    greatest(coalesce(v_order.delivery_fee, 0) - coalesce(v_order.rider_payout_amount, 0), 0),
    'pending'
  )
  on conflict (order_id) do nothing;
end;
$$;

create or replace function public.create_rider_settlement_on_delivery()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'delivered'
     and new.payment_status = 'paid'
     and new.rider_id is not null
     and (old.status is distinct from new.status or old.rider_id is distinct from new.rider_id) then
    perform public.create_rider_settlement_for_order(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists orders_create_rider_settlement_on_delivery on public.orders;
create trigger orders_create_rider_settlement_on_delivery
after update on public.orders
for each row execute function public.create_rider_settlement_on_delivery();

create or replace function public.sync_settlements_for_order_resolution()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'cancelled' or new.payment_status in ('refunded', 'expired') then
    update public.store_settlements
    set status = case when status = 'paid' then 'held' else 'cancelled' end
    where order_id = new.id
      and status in ('pending', 'processing', 'paid');

    update public.rider_settlements
    set status = case when status = 'paid' then 'held' else 'cancelled' end
    where order_id = new.id
      and status in ('pending', 'processing', 'paid');
  end if;
  return new;
end;
$$;

drop trigger if exists orders_sync_settlements_for_resolution on public.orders;
create trigger orders_sync_settlements_for_resolution
after update on public.orders
for each row execute function public.sync_settlements_for_order_resolution();

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
    perform public.create_store_settlement_for_order(v_payment.order_id);
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

  perform public.create_store_settlement_for_order(v_payment.order_id);
end;
$$;

create or replace function public.admin_mark_store_settlement_paid(p_settlement_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can mark settlements paid';
  end if;

  update public.store_settlements
  set status = 'paid',
      paid_at = now()
  where id = p_settlement_id
    and status in ('pending', 'processing');

  if not found then
    raise exception 'Store settlement is not payable';
  end if;
end;
$$;

create or replace function public.admin_mark_rider_settlement_paid(p_settlement_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can mark settlements paid';
  end if;

  update public.rider_settlements
  set status = 'paid',
      paid_at = now()
  where id = p_settlement_id
    and status in ('pending', 'processing');

  if not found then
    raise exception 'Rider settlement is not payable';
  end if;
end;
$$;

insert into public.store_settlements (
  store_id,
  order_id,
  gross_items_amount,
  discount_amount,
  net_items_amount,
  service_fee_amount,
  payout_amount,
  status
)
select
  o.store_id,
  o.id,
  coalesce(o.items_subtotal, o.total_amount),
  coalesce(o.discount_amount, 0),
  coalesce(o.store_payout_amount, greatest(o.total_amount - o.delivery_fee - o.service_fee, 0)),
  coalesce(o.service_fee, 0),
  coalesce(o.store_payout_amount, greatest(o.total_amount - o.delivery_fee - o.service_fee, 0)),
  case when o.status = 'cancelled' then 'cancelled' else 'pending' end
from public.orders o
where o.payment_status = 'paid'
on conflict (order_id) do nothing;

insert into public.rider_settlements (
  rider_id,
  store_id,
  order_id,
  delivery_fee_amount,
  rider_payout_amount,
  platform_delivery_margin,
  status
)
select
  o.rider_id,
  o.store_id,
  o.id,
  coalesce(o.delivery_fee, 0),
  coalesce(o.rider_payout_amount, 0),
  greatest(coalesce(o.delivery_fee, 0) - coalesce(o.rider_payout_amount, 0), 0),
  'pending'
from public.orders o
where o.payment_status = 'paid'
  and o.status = 'delivered'
  and o.rider_id is not null
on conflict (order_id) do nothing;

drop view if exists public.order_summaries;
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
  public.order_profile_phone(o.id, o.rider_id) as rider_phone
from public.orders o
join public.stores s on s.id = o.store_id;

drop view if exists public.payment_summaries;
create or replace view public.payment_summaries
with (security_invoker = true)
as
select
  p.id,
  p.order_id,
  o.store_id,
  s.name as store_name,
  o.customer_id,
  p.provider,
  p.payment_reference,
  p.provider_transaction_reference,
  p.amount,
  p.status,
  p.checkout_url,
  o.items_subtotal,
  o.discount_amount,
  o.delivery_fee,
  o.service_fee,
  o.store_payout_amount,
  o.rider_payout_amount,
  o.platform_fee_amount,
  p.created_at,
  p.updated_at
from public.payments p
join public.orders o on o.id = p.order_id
join public.stores s on s.id = o.store_id;

create or replace view public.store_settlement_summaries
with (security_invoker = true)
as
select
  ss.id,
  ss.store_id,
  s.name as store_name,
  ss.order_id,
  o.customer_id,
  o.status as order_status,
  o.payment_status,
  ss.gross_items_amount,
  ss.discount_amount,
  ss.net_items_amount,
  ss.service_fee_amount,
  ss.payout_amount,
  ss.status,
  ss.paid_at,
  ss.created_at,
  ss.updated_at
from public.store_settlements ss
join public.stores s on s.id = ss.store_id
join public.orders o on o.id = ss.order_id;

create or replace view public.rider_settlement_summaries
with (security_invoker = true)
as
select
  rs.id,
  rs.rider_id,
  nullif(trim(p.full_name), '') as rider_name,
  rs.store_id,
  s.name as store_name,
  rs.order_id,
  o.status as order_status,
  o.payment_status,
  rs.delivery_fee_amount,
  rs.rider_payout_amount,
  rs.platform_delivery_margin,
  rs.status,
  rs.paid_at,
  rs.created_at,
  rs.updated_at
from public.rider_settlements rs
join public.stores s on s.id = rs.store_id
join public.orders o on o.id = rs.order_id
left join public.profiles p on p.id = rs.rider_id;

grant select on public.platform_fee_settings to authenticated;
grant select on public.order_summaries to authenticated;
grant select on public.payment_summaries to authenticated;
grant select on public.store_settlements to authenticated;
grant select on public.rider_settlements to authenticated;
grant select on public.store_settlement_summaries to authenticated;
grant select on public.rider_settlement_summaries to authenticated;
grant execute on function public.calculate_order_fees(numeric, numeric) to authenticated;
grant execute on function public.quote_order_totals(uuid, jsonb, text) to authenticated;
grant execute on function public.admin_mark_store_settlement_paid(uuid) to authenticated;
grant execute on function public.admin_mark_rider_settlement_paid(uuid) to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.store_settlements;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.rider_settlements;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;
