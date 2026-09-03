create or replace function public.store_create_promo_code(
  p_store_id uuid,
  p_code text,
  p_discount_type text,
  p_discount_value numeric,
  p_description text default '',
  p_min_order_amount numeric default 0,
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
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.is_store_member(p_store_id) then
    raise exception 'Only store members can create promo codes for this store';
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

  if coalesce(p_min_order_amount, 0) < 0 then
    raise exception 'Minimum order cannot be negative';
  end if;

  if p_max_redemptions is not null and p_max_redemptions <= 0 then
    raise exception 'Maximum redemptions must be greater than zero';
  end if;

  insert into public.promo_codes (
    store_id,
    code,
    description,
    discount_type,
    discount_value,
    min_order_amount,
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
    p_max_redemptions,
    coalesce(p_is_active, true),
    auth.uid()
  )
  returning id into v_promo_id;

  return v_promo_id;
end;
$$;

create or replace function public.store_update_promo_code(
  p_promo_id uuid,
  p_code text,
  p_discount_type text,
  p_discount_value numeric,
  p_description text default '',
  p_min_order_amount numeric default 0,
  p_max_redemptions integer default null,
  p_is_active boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := public.normalize_promo_code(p_code);
  v_store_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select store_id
  into v_store_id
  from public.promo_codes
  where id = p_promo_id;

  if not found then
    raise exception 'Promo code not found';
  end if;

  if v_store_id is null then
    raise exception 'Platform promo codes cannot be edited from the store app';
  end if;

  if not public.is_store_member(v_store_id) then
    raise exception 'Only store members can edit promo codes for this store';
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

  if coalesce(p_min_order_amount, 0) < 0 then
    raise exception 'Minimum order cannot be negative';
  end if;

  if p_max_redemptions is not null and p_max_redemptions <= 0 then
    raise exception 'Maximum redemptions must be greater than zero';
  end if;

  update public.promo_codes
  set code = v_code,
      description = coalesce(p_description, ''),
      discount_type = p_discount_type,
      discount_value = p_discount_value,
      min_order_amount = coalesce(p_min_order_amount, 0),
      max_redemptions = p_max_redemptions,
      is_active = coalesce(p_is_active, true)
  where id = p_promo_id;
end;
$$;

create or replace function public.store_delete_promo_code(p_promo_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
  v_has_redemptions boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select store_id
  into v_store_id
  from public.promo_codes
  where id = p_promo_id;

  if not found then
    raise exception 'Promo code not found';
  end if;

  if v_store_id is null then
    raise exception 'Platform promo codes cannot be deleted from the store app';
  end if;

  if not public.is_store_member(v_store_id) then
    raise exception 'Only store members can delete promo codes for this store';
  end if;

  select exists (
    select 1
    from public.order_promo_redemptions
    where promo_code_id = p_promo_id
  )
  into v_has_redemptions;

  if v_has_redemptions then
    update public.promo_codes
    set is_active = false
    where id = p_promo_id;
  else
    delete from public.promo_codes
    where id = p_promo_id;
  end if;
end;
$$;

grant execute on function public.store_create_promo_code(
  uuid,
  text,
  text,
  numeric,
  text,
  numeric,
  integer,
  boolean
) to authenticated;

grant execute on function public.store_update_promo_code(
  uuid,
  text,
  text,
  numeric,
  text,
  numeric,
  integer,
  boolean
) to authenticated;

grant execute on function public.store_delete_promo_code(uuid) to authenticated;

notify pgrst, 'reload schema';
