create extension if not exists pgcrypto;

create type public.profile_role as enum ('customer', 'rider', 'store_admin', 'admin');
create type public.order_status as enum (
  'pending_payment',
  'paid',
  'accepted',
  'preparing',
  'ready_for_pickup',
  'out_for_delivery',
  'delivered',
  'cancelled'
);
create type public.payment_status as enum (
  'pending',
  'paid',
  'failed',
  'expired',
  'refunded'
);
create type public.inventory_movement_reason as enum (
  'stock_in',
  'correction',
  'sale',
  'return',
  'waste'
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role public.profile_role not null default 'customer',
  full_name text not null default '',
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.stores (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references public.profiles(id) on delete set null,
  name text not null,
  category text not null default 'general',
  address text not null default '',
  is_active boolean not null default true,
  is_open boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.store_members (
  store_id uuid not null references public.stores(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  can_manage_inventory boolean not null default true,
  can_manage_orders boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (store_id, user_id)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null,
  description text not null default '',
  price numeric(12, 2) not null check (price >= 0),
  image_url text,
  is_available boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.inventory_items (
  product_id uuid primary key references public.products(id) on delete cascade,
  sku text,
  quantity_on_hand integer not null default 0 check (quantity_on_hand >= 0),
  reorder_level integer not null default 5 check (reorder_level >= 0),
  updated_at timestamptz not null default now()
);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  quantity_delta integer not null,
  reason public.inventory_movement_reason not null,
  note text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id) on delete restrict,
  store_id uuid not null references public.stores(id) on delete restrict,
  rider_id uuid references public.profiles(id) on delete set null,
  status public.order_status not null default 'pending_payment',
  payment_status public.payment_status not null default 'pending',
  total_amount numeric(12, 2) not null default 0 check (total_amount >= 0),
  delivery_address text not null,
  eta_minutes integer check (eta_minutes is null or eta_minutes >= 0),
  eta_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  product_name text not null,
  quantity integer not null check (quantity > 0),
  unit_price numeric(12, 2) not null check (unit_price >= 0),
  line_total numeric(12, 2) generated always as (quantity * unit_price) stored
);

create table public.inventory_reservations (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  quantity integer not null check (quantity > 0),
  expires_at timestamptz not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  provider text not null default 'monnify',
  payment_reference text not null unique,
  provider_transaction_reference text,
  amount numeric(12, 2) not null check (amount >= 0),
  status public.payment_status not null default 'pending',
  checkout_url text,
  raw_response jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.delivery_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  rider_id uuid references public.profiles(id) on delete set null,
  status public.order_status not null,
  eta_minutes integer check (eta_minutes is null or eta_minutes >= 0),
  note text,
  created_at timestamptz not null default now()
);

create index products_store_id_idx on public.products(store_id);
create index orders_customer_id_idx on public.orders(customer_id);
create index orders_store_id_idx on public.orders(store_id);
create index orders_rider_id_idx on public.orders(rider_id);
create index inventory_reservations_active_idx
  on public.inventory_reservations(product_id, active, expires_at);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_touch_updated_at before update on public.profiles
  for each row execute function public.touch_updated_at();
create trigger stores_touch_updated_at before update on public.stores
  for each row execute function public.touch_updated_at();
create trigger products_touch_updated_at before update on public.products
  for each row execute function public.touch_updated_at();
create trigger orders_touch_updated_at before update on public.orders
  for each row execute function public.touch_updated_at();
create trigger payments_touch_updated_at before update on public.payments
  for each row execute function public.touch_updated_at();

create or replace function public.create_inventory_item_for_product()
returns trigger
language plpgsql
as $$
begin
  insert into public.inventory_items(product_id, quantity_on_hand)
  values (new.id, 0)
  on conflict (product_id) do nothing;
  return new;
end;
$$;

create trigger products_create_inventory_item after insert on public.products
  for each row execute function public.create_inventory_item_for_product();

create or replace function public.current_profile_role()
returns public.profile_role
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_profile_role() = 'admin', false)
$$;

create or replace function public.is_store_member(p_store_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.store_members sm
    where sm.store_id = p_store_id
      and sm.user_id = auth.uid()
  ) or public.is_admin()
$$;

create or replace view public.customer_catalog as
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
    s.is_active
    and s.is_open
    and p.is_available
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
  ) as is_available
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
  o.total_amount,
  o.delivery_address,
  o.eta_minutes,
  o.eta_updated_at,
  o.created_at,
  o.updated_at
from public.orders o
join public.stores s on s.id = o.store_id;

create or replace view public.store_inventory as
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
  )::integer as quantity_available
from public.products p
left join public.inventory_items ii on ii.product_id = p.id
where public.is_store_member(p.store_id);

create or replace function public.place_order(
  p_store_id uuid,
  p_delivery_address text,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order_id uuid := gen_random_uuid();
  v_total numeric(12, 2) := 0;
  v_item record;
  v_product record;
  v_reserved integer;
  v_available integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Order must contain at least one item';
  end if;

  insert into public.orders (
    id,
    customer_id,
    store_id,
    delivery_address,
    status,
    payment_status
  )
  values (
    v_order_id,
    auth.uid(),
    p_store_id,
    p_delivery_address,
    'pending_payment',
    'pending'
  );

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
    for update of p;

    if not found then
      raise exception 'Product % was not found for this store', v_item.product_id;
    end if;

    if not (v_product.is_active and v_product.is_open and v_product.is_available) then
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

  update public.orders
  set total_amount = v_total
  where id = v_order_id;

  return v_order_id;
end;
$$;

create or replace function public.adjust_inventory(
  p_product_id uuid,
  p_delta integer,
  p_reason text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
  v_new_quantity integer;
begin
  select store_id into v_store_id
  from public.products
  where id = p_product_id;

  if v_store_id is null then
    raise exception 'Product not found';
  end if;

  if not public.is_store_member(v_store_id) then
    raise exception 'Not allowed';
  end if;

  insert into public.inventory_items(product_id, quantity_on_hand)
  values (p_product_id, 0)
  on conflict (product_id) do nothing;

  update public.inventory_items
  set quantity_on_hand = quantity_on_hand + p_delta,
      updated_at = now()
  where product_id = p_product_id
  returning quantity_on_hand into v_new_quantity;

  if v_new_quantity < 0 then
    raise exception 'Inventory cannot go below zero';
  end if;

  insert into public.inventory_movements (
    product_id,
    store_id,
    quantity_delta,
    reason,
    note,
    created_by
  )
  values (
    p_product_id,
    v_store_id,
    p_delta,
    p_reason::public.inventory_movement_reason,
    p_note,
    auth.uid()
  );
end;
$$;

create or replace function public.accept_rider_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_profile_role() not in ('rider', 'admin') then
    raise exception 'Only riders can accept orders';
  end if;

  update public.orders
  set rider_id = auth.uid(),
      status = 'out_for_delivery',
      eta_updated_at = now()
  where id = p_order_id
    and rider_id is null
    and status = 'ready_for_pickup';

  if not found then
    raise exception 'Order is not available';
  end if;

  insert into public.delivery_events(order_id, rider_id, status, note)
  values (p_order_id, auth.uid(), 'out_for_delivery', 'Rider accepted order');
end;
$$;

create or replace function public.update_rider_eta(
  p_order_id uuid,
  p_eta_minutes integer,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_eta_minutes < 0 then
    raise exception 'ETA cannot be negative';
  end if;

  update public.orders
  set eta_minutes = p_eta_minutes,
      eta_updated_at = now()
  where id = p_order_id
    and (rider_id = auth.uid() or public.is_admin());

  if not found then
    raise exception 'Order is not assigned to this rider';
  end if;

  insert into public.delivery_events(order_id, rider_id, status, eta_minutes, note)
  values (p_order_id, auth.uid(), 'out_for_delivery', p_eta_minutes, p_note);
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
  select p.*, o.store_id, o.total_amount
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

alter table public.profiles enable row level security;
alter table public.stores enable row level security;
alter table public.store_members enable row level security;
alter table public.products enable row level security;
alter table public.inventory_items enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.inventory_reservations enable row level security;
alter table public.payments enable row level security;
alter table public.delivery_events enable row level security;

create policy "profiles read own or admin" on public.profiles
  for select using (id = auth.uid() or public.is_admin());
create policy "profiles update own or admin" on public.profiles
  for update using (id = auth.uid() or public.is_admin());

create policy "stores public active read" on public.stores
  for select using (is_active = true or public.is_store_member(id));
create policy "stores members update" on public.stores
  for update using (public.is_store_member(id));
create policy "stores admins insert" on public.stores
  for insert with check (public.is_admin());

create policy "store members read" on public.store_members
  for select using (user_id = auth.uid() or public.is_admin());
create policy "store members admin write" on public.store_members
  for all using (public.is_admin()) with check (public.is_admin());

create policy "products public read" on public.products
  for select using (
    public.is_store_member(store_id)
    or exists (
      select 1 from public.stores s
      where s.id = store_id and s.is_active = true
    )
  );
create policy "products store write" on public.products
  for all using (public.is_store_member(store_id)) with check (public.is_store_member(store_id));

create policy "inventory public read" on public.inventory_items
  for select using (
    public.is_store_member((select p.store_id from public.products p where p.id = product_id))
    or exists (
      select 1
      from public.products p
      join public.stores s on s.id = p.store_id
      where p.id = product_id and s.is_active = true
    )
  );
create policy "inventory store write" on public.inventory_items
  for all using (
    public.is_store_member((select p.store_id from public.products p where p.id = product_id))
  ) with check (
    public.is_store_member((select p.store_id from public.products p where p.id = product_id))
  );

create policy "inventory movements store read" on public.inventory_movements
  for select using (public.is_store_member(store_id));
create policy "inventory movements store insert" on public.inventory_movements
  for insert with check (public.is_store_member(store_id));

create policy "orders scoped read" on public.orders
  for select using (
    customer_id = auth.uid()
    or rider_id = auth.uid()
    or (rider_id is null and status = 'ready_for_pickup')
    or public.is_store_member(store_id)
    or public.is_admin()
  );
create policy "orders customer insert" on public.orders
  for insert with check (customer_id = auth.uid());
create policy "orders scoped update" on public.orders
  for update using (
    customer_id = auth.uid()
    or rider_id = auth.uid()
    or public.is_store_member(store_id)
    or public.is_admin()
  );

create policy "order items scoped read" on public.order_items
  for select using (
    exists (
      select 1 from public.orders o
      where o.id = order_id
        and (
          o.customer_id = auth.uid()
          or o.rider_id = auth.uid()
          or public.is_store_member(o.store_id)
          or public.is_admin()
        )
    )
  );

create policy "reservations scoped read" on public.inventory_reservations
  for select using (
    exists (
      select 1 from public.orders o
      where o.id = order_id
        and (
          o.customer_id = auth.uid()
          or public.is_store_member(o.store_id)
          or public.is_admin()
        )
    )
  );

create policy "payments scoped read" on public.payments
  for select using (
    exists (
      select 1 from public.orders o
      where o.id = order_id
        and (
          o.customer_id = auth.uid()
          or public.is_store_member(o.store_id)
          or public.is_admin()
        )
    )
  );

create policy "delivery events scoped read" on public.delivery_events
  for select using (
    exists (
      select 1 from public.orders o
      where o.id = order_id
        and (
          o.customer_id = auth.uid()
          or o.rider_id = auth.uid()
          or public.is_store_member(o.store_id)
          or public.is_admin()
        )
    )
  );

alter publication supabase_realtime add table public.stores;
alter publication supabase_realtime add table public.products;
alter publication supabase_realtime add table public.inventory_items;
alter publication supabase_realtime add table public.inventory_reservations;
alter publication supabase_realtime add table public.orders;
alter publication supabase_realtime add table public.order_items;
alter publication supabase_realtime add table public.payments;
alter publication supabase_realtime add table public.delivery_events;
