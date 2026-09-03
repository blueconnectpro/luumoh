create or replace function public.admin_create_product(
  p_store_id uuid,
  p_name text,
  p_description text default '',
  p_price numeric default 0,
  p_initial_stock integer default 0,
  p_reorder_level integer default 5,
  p_sku text default null,
  p_image_url text default null,
  p_is_available boolean default true
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
    image_url,
    is_available
  )
  values (
    p_store_id,
    trim(p_name),
    coalesce(p_description, ''),
    p_price,
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
