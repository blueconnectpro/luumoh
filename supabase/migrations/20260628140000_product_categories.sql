alter table public.products
add column if not exists category text not null default 'general';

create or replace function public.admin_create_product(
  p_store_id uuid,
  p_name text,
  p_description text default '',
  p_price numeric default 0,
  p_initial_stock integer default 0,
  p_reorder_level integer default 5,
  p_sku text default null,
  p_image_url text default null,
  p_is_available boolean default true,
  p_category text default 'general'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product_id uuid;
begin
  if not (public.is_admin() or public.is_store_member(p_store_id)) then
    raise exception 'Not allowed';
  end if;

  if length(trim(p_name)) = 0 then
    raise exception 'Product name is required';
  end if;

  if p_price < 0 then
    raise exception 'Product price cannot be negative';
  end if;

  if p_initial_stock < 0 then
    raise exception 'Initial stock cannot be negative';
  end if;

  if p_reorder_level < 0 then
    raise exception 'Reorder level cannot be negative';
  end if;

  insert into public.products (
    store_id,
    name,
    description,
    price,
    category,
    image_url,
    is_available
  )
  values (
    p_store_id,
    trim(p_name),
    coalesce(p_description, ''),
    p_price,
    coalesce(nullif(trim(coalesce(p_category, '')), ''), 'general'),
    nullif(trim(coalesce(p_image_url, '')), ''),
    p_is_available
  )
  returning id into v_product_id;

  insert into public.inventory_items (
    product_id,
    sku,
    quantity_on_hand,
    reorder_level
  )
  values (
    v_product_id,
    nullif(trim(coalesce(p_sku, '')), ''),
    p_initial_stock,
    p_reorder_level
  );

  if p_initial_stock > 0 then
    insert into public.inventory_movements (
      product_id,
      store_id,
      quantity_delta,
      reason,
      note,
      created_by
    )
    values (
      v_product_id,
      p_store_id,
      p_initial_stock,
      'stock_in',
      'Initial stock',
      auth.uid()
    );
  end if;

  return v_product_id;
end;
$$;

create or replace function public.store_update_product(
  p_product_id uuid,
  p_name text,
  p_description text default '',
  p_price numeric default 0,
  p_reorder_level integer default 5,
  p_sku text default null,
  p_image_url text default null,
  p_is_available boolean default true,
  p_category text default 'general'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
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

  if length(trim(p_name)) = 0 then
    raise exception 'Product name is required';
  end if;

  if p_price < 0 then
    raise exception 'Product price cannot be negative';
  end if;

  if p_reorder_level < 0 then
    raise exception 'Reorder level cannot be negative';
  end if;

  update public.products
  set name = trim(p_name),
      description = coalesce(p_description, ''),
      price = p_price,
      category = coalesce(nullif(trim(coalesce(p_category, '')), ''), 'general'),
      image_url = nullif(trim(coalesce(p_image_url, '')), ''),
      is_available = p_is_available
  where id = p_product_id;

  insert into public.inventory_items(product_id, sku, quantity_on_hand, reorder_level)
  values (
    p_product_id,
    nullif(trim(coalesce(p_sku, '')), ''),
    0,
    p_reorder_level
  )
  on conflict (product_id) do update
  set sku = excluded.sku,
      reorder_level = excluded.reorder_level,
      updated_at = now();
end;
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
  ) as is_available,
  p.category
from public.products p
join public.stores s on s.id = p.store_id
left join public.inventory_items ii on ii.product_id = p.id
where s.is_active = true;

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
  )::integer as quantity_available,
  ii.sku,
  p.category
from public.products p
left join public.inventory_items ii on ii.product_id = p.id
where public.is_store_member(p.store_id);
