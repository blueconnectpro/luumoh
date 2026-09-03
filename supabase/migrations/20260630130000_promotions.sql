create table if not exists public.promo_codes (
  id uuid primary key default gen_random_uuid(),
  store_id uuid references public.stores(id) on delete cascade,
  code text not null unique,
  description text not null default '',
  discount_type text not null check (discount_type in ('percent', 'fixed')),
  discount_value numeric(12, 2) not null check (discount_value > 0),
  min_order_amount numeric(12, 2) not null default 0 check (min_order_amount >= 0),
  starts_at timestamptz,
  ends_at timestamptz,
  max_redemptions integer check (max_redemptions is null or max_redemptions > 0),
  redemption_count integer not null default 0 check (redemption_count >= 0),
  is_active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists promo_codes_store_idx on public.promo_codes(store_id);
create index if not exists promo_codes_active_idx on public.promo_codes(is_active);

drop trigger if exists promo_codes_touch_updated_at on public.promo_codes;
create trigger promo_codes_touch_updated_at
before update on public.promo_codes
for each row execute function public.touch_updated_at();

alter table public.orders
  add column if not exists promo_code_id uuid references public.promo_codes(id) on delete set null,
  add column if not exists discount_amount numeric(12, 2) not null default 0 check (discount_amount >= 0);

create table if not exists public.order_promo_redemptions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id) on delete cascade,
  promo_code_id uuid not null references public.promo_codes(id) on delete restrict,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  discount_amount numeric(12, 2) not null check (discount_amount >= 0),
  created_at timestamptz not null default now()
);

alter table public.promo_codes enable row level security;
alter table public.order_promo_redemptions enable row level security;

drop policy if exists "promo codes scoped read" on public.promo_codes;
create policy "promo codes scoped read" on public.promo_codes
  for select using (
    is_active = true
    or public.is_admin()
    or (store_id is not null and public.is_store_member(store_id))
  );

drop policy if exists "promo redemptions scoped read" on public.order_promo_redemptions;
create policy "promo redemptions scoped read" on public.order_promo_redemptions
  for select using (
    customer_id = auth.uid()
    or public.is_admin()
    or public.is_store_member(store_id)
  );

create or replace function public.normalize_promo_code(p_code text)
returns text
language sql
immutable
as $$
  select upper(regexp_replace(trim(coalesce(p_code, '')), '\s+', '', 'g'))
$$;

create or replace function public.calculate_promo_discount(
  p_discount_type text,
  p_discount_value numeric,
  p_subtotal numeric
)
returns numeric
language sql
immutable
as $$
  select least(
    greatest(coalesce(p_subtotal, 0), 0),
    case
      when p_discount_type = 'percent' then
        round(greatest(coalesce(p_subtotal, 0), 0) * least(p_discount_value, 100) / 100, 2)
      else
        round(p_discount_value, 2)
    end
  )
$$;

create or replace function public.validate_promo_code(
  p_store_id uuid,
  p_code text,
  p_subtotal numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := public.normalize_promo_code(p_code);
  v_promo public.promo_codes%rowtype;
  v_discount numeric(12, 2) := 0;
begin
  if v_code = '' then
    return jsonb_build_object('is_valid', false, 'message', 'Enter a promo code');
  end if;

  select *
  into v_promo
  from public.promo_codes
  where code = v_code
    and (store_id = p_store_id or store_id is null)
  order by store_id nulls last
  limit 1;

  if not found then
    return jsonb_build_object('is_valid', false, 'message', 'Promo code was not found');
  end if;

  if not v_promo.is_active then
    return jsonb_build_object('is_valid', false, 'message', 'Promo code is inactive');
  end if;

  if v_promo.starts_at is not null and now() < v_promo.starts_at then
    return jsonb_build_object('is_valid', false, 'message', 'Promo code is not active yet');
  end if;

  if v_promo.ends_at is not null and now() > v_promo.ends_at then
    return jsonb_build_object('is_valid', false, 'message', 'Promo code has expired');
  end if;

  if v_promo.max_redemptions is not null and v_promo.redemption_count >= v_promo.max_redemptions then
    return jsonb_build_object('is_valid', false, 'message', 'Promo code has reached its limit');
  end if;

  if coalesce(p_subtotal, 0) < v_promo.min_order_amount then
    return jsonb_build_object(
      'is_valid', false,
      'message', 'Minimum order is NGN ' || v_promo.min_order_amount
    );
  end if;

  v_discount := public.calculate_promo_discount(
    v_promo.discount_type,
    v_promo.discount_value,
    p_subtotal
  );

  return jsonb_build_object(
    'is_valid', true,
    'message', 'Promo applied',
    'promo_code_id', v_promo.id,
    'code', v_promo.code,
    'discount_amount', v_discount,
    'discount_type', v_promo.discount_type,
    'discount_value', v_promo.discount_value
  );
end;
$$;

create or replace function public.admin_create_promo_code(
  p_code text,
  p_discount_type text,
  p_discount_value numeric,
  p_store_id uuid default null,
  p_description text default '',
  p_min_order_amount numeric default 0,
  p_starts_at timestamptz default null,
  p_ends_at timestamptz default null,
  p_max_redemptions integer default null,
  p_is_active boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := public.normalize_promo_code(p_code);
  v_promo_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Only admins can create promo codes';
  end if;

  if length(v_code) < 3 then
    raise exception 'Promo code must be at least 3 characters';
  end if;

  if p_discount_type not in ('percent', 'fixed') then
    raise exception 'Invalid discount type';
  end if;

  if p_discount_value <= 0 then
    raise exception 'Discount must be greater than zero';
  end if;

  if p_discount_type = 'percent' and p_discount_value > 100 then
    raise exception 'Percent discount cannot exceed 100';
  end if;

  insert into public.promo_codes (
    store_id,
    code,
    description,
    discount_type,
    discount_value,
    min_order_amount,
    starts_at,
    ends_at,
    max_redemptions,
    is_active,
    created_by
  )
  values (
    p_store_id,
    v_code,
    coalesce(p_description, ''),
    p_discount_type,
    p_discount_value,
    coalesce(p_min_order_amount, 0),
    p_starts_at,
    p_ends_at,
    p_max_redemptions,
    coalesce(p_is_active, true),
    auth.uid()
  )
  returning id into v_promo_id;

  return v_promo_id;
end;
$$;

create or replace view public.promo_code_summaries
with (security_invoker = true)
as
select
  pc.id,
  pc.store_id,
  s.name as store_name,
  pc.code,
  pc.description,
  pc.discount_type,
  pc.discount_value,
  pc.min_order_amount,
  pc.starts_at,
  pc.ends_at,
  pc.max_redemptions,
  pc.redemption_count,
  pc.is_active,
  pc.created_at,
  pc.updated_at
from public.promo_codes pc
left join public.stores s on s.id = pc.store_id;

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

  update public.orders
  set total_amount = greatest(v_total - v_discount, 0),
      discount_amount = v_discount,
      promo_code_id = v_promo_id
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
